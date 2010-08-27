-module(rabbit_webhooks).
-behaviour(gen_server).

-include("rabbit_webhooks.hrl").

-export([start_link/2]).
% gen_server callbacks
-export([
  init/1, 
  handle_call/3, 
  handle_cast/2, 
  handle_info/2, 
  terminate/2, 
  code_change/3
]).
% Helper methods
-export([
	send_request/6
]).

-define(REQUESTED_WITH, "RabbitMQ-Webhooks").
-define(VERSION, "1.0").
-define(ACCEPT, "application/json;q=.9,text/plain;q=.8,text/xml;q=.6,application/xml;q=.7,text/html;q=.5,*/*;q=.4").
-define(ACCEPT_ENCODING, "gzip").
            
-record(state, { channel, config=#webhook{}, queue, consumer }).

start_link(_Name, Config) ->   
  gen_server:start_link(?MODULE, [Config], []).
  
init([Config]) ->
  Connection = amqp_connection:start_direct(),
  Channel = amqp_connection:open_channel(Connection),

	% Our configuration
  Webhook = #webhook {
    url = proplists:get_value(url, Config),
		method = proplists:get_value(method, Config),
    exchange = case proplists:get_value(exchange, Config) of
			[{exchange, Xname} | Xconfig] -> #'exchange.declare'{
				exchange=Xname,
				type=proplists:get_value(type, Xconfig, <<"topic">>),
				auto_delete=proplists:get_value(auto_delete, Xconfig, true),
				durable=proplists:get_value(durable, Xconfig, false)}
		end,
		queue = case proplists:get_value(queue, Config) of
			% Allow for load-balancing by using named queues (optional)
			[{queue, Qname} | Qconfig] -> #'queue.declare'{
				queue=Qname,
				auto_delete=proplists:get_value(auto_delete, Qconfig, true),
				durable=proplists:get_value(durable, Qconfig, false)};
			% Default to an anonymous queue
			_ -> #'queue.declare'{ auto_delete=true }
		end,
    routing_key = proplists:get_value(routing_key, Config)
  },

  % Declare exchange
  #'exchange.declare_ok'{} = amqp_channel:call(Channel, Webhook#webhook.exchange),

  % Declare queue
  #'queue.declare_ok'{ queue=Q } = amqp_channel:call(Channel, Webhook#webhook.queue),

  % Bind queue
  QueueBind = #'queue.bind'{
    queue=Q,
    exchange=Webhook#webhook.exchange#'exchange.declare'.exchange,
    routing_key=Webhook#webhook.routing_key
  },
  #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind),

  % Subscribe to these events
  BasicConsume = #'basic.consume'{
    queue=Q,
    no_ack=false
  },
  #'basic.consume_ok'{ consumer_tag=Tag } = amqp_channel:subscribe(Channel, BasicConsume, self()),

  {ok, #state{ channel=Channel, config=Webhook, queue=Q, consumer=Tag }}.

handle_call(_Msg, _From, State = #state{ channel=_Channel, config=_Config }) ->
  {noreply, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(#'basic.consume_ok'{ consumer_tag=_Tag }, State) ->
  {noreply, State};
  
handle_info({#'basic.deliver'{ delivery_tag=DeliveryTag }, 
						#amqp_msg{ props=#'P_basic'{ 
											   content_type=ContentType, 
												 headers=Headers, 
												 reply_to=ReplyTo 
											 }, 
											 payload=Payload } }, 
            State = #state{ channel=Channel, config=Config }) ->
	% Transform message headers to HTTP headers
	[Xhdrs, Params] = process_headers(Headers),
	HttpHdrs = Xhdrs ++ [
		{"Content-Type", binary_to_list(ContentType)},
		{"Accept", ?ACCEPT},
		{"Accept-Encoding", ?ACCEPT_ENCODING},
		{"X-Requested-With", ?REQUESTED_WITH},
		{"X-Webhooks-Version", ?VERSION}
	] ++ case ReplyTo of
		undefined -> [];
		_ -> [{"X-ReplyTo", binary_to_list(ReplyTo)}]
	end,
	
	% Parameter-replace the URL
	Url = case proplists:get_value("url", Params) of
		undefined -> parse_url(Config#webhook.url, Params);
		NewUrl -> parse_url(NewUrl, Params)
	end,
	Method = case proplists:get_value("method", Params) of
		undefined -> Config#webhook.method;
		NewMethod -> list_to_atom(string:to_lower(NewMethod))
	end,
	
	% Issue the actual request.
	spawn(?MODULE, send_request, [Channel, DeliveryTag, Url, Method, HttpHdrs, Payload]),
	
  {noreply, State};

handle_info(Msg, State) ->
  rabbit_log:warning(" Unkown message: ~p~n State: ~p~n", [Msg, State]),
  {noreply, State}.
  
terminate(_, #state{ channel=Channel, config=_Webhook, queue=_Q, consumer=Tag }) -> 
	rabbit_log:info("Terminating ~p ~p~n", [self(), Tag]),
	amqp_channel:call(Channel, #'basic.cancel'{ consumer_tag = Tag }),
  amqp_channel:call(Channel, #'channel.close'{}),
  ok.

code_change(_OldVsn, State, _Extra) -> 
  {ok, State}.

process_headers(Headers) ->
	lists:foldl(fun (Hdr, AllHdrs) ->
		case Hdr of
			{Key, _, Value} ->
				[HttpHdrs, Params] = AllHdrs,
				case <<Key:2/binary>> of
					<<"X-">> ->
						[[{binary_to_list(Key), binary_to_list(Value)} | HttpHdrs], Params];
					_ ->
						[HttpHdrs, [{binary_to_list(Key), binary_to_list(Value)} | Params]]
				end
		end
	end, [[], []], Headers).
	
parse_url(From, Params) ->
	lists:foldl(fun (P, NewUrl) ->
		case P of
			{Param, Value} ->
				re:replace(NewUrl, io_lib:format("{~s}", [Param]), Value, [{return, list}])
		end
	end, From, Params).
	
send_request(Channel, DeliveryTag, Url, Method, HttpHdrs, Payload) ->
	% Issue the actual request.
	case lhttpc:request(Url, Method, HttpHdrs, Payload, infinity) of
		% Only process if the server returns 200.
		{ok, {{200, _}, Hdrs, Response}} ->
			% TODO: Place result back on a queue?
			rabbit_log:debug(" hdrs: ~p~n response: ~p~n", [Hdrs, Response]),
			% Check to see if we need to unzip this response
			case re:run(proplists:get_value("Content-Encoding", Hdrs), "(gzip)", [{capture, [1], list}]) of
				nomatch ->
					rabbit_log:debug("plain response: ~p~n", [Response]),
					ok;
				{match, ["gzip"]} ->
					Content = zlib:gunzip(Response),
					rabbit_log:debug("gzipped response: ~p~n", [Content]),
					ok
			end,
			amqp_channel:call(Channel, #'basic.ack'{ delivery_tag=DeliveryTag });
		Else ->
			rabbit_log:error("~p", [Else])
	end.
	
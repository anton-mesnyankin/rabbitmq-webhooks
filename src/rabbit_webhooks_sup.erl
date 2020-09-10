% -*- tab-width: 2 -*-
%%% -------------------------------------------------------------------
%%% Author  : J. Brisbin <jon@jbrisbin.com>
%%% Description : RabbitMQ plugin providing webhooks functionality.
%%%
%%% Created : Aug 24, 2010
%%% -------------------------------------------------------------------
-module(rabbit_webhooks_sup).

-author("J. Brisbin <jon@jbrisbin.com>").

-behaviour(supervisor).

-include("rabbit_webhooks.hrl").

-export([start_link/0, init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    rabbit_log:info("Configuring Webhooks...", []),
    Pid = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    rabbit_log:info("Webhooks have been configured", []),
    Pid.

init([]) ->
    Workers =
        case application:get_env(webhooks) of
            {ok, W} ->
                make_worker_configs(W);
            _ ->
                rabbit_log:info("No configs found...", []),
                []
        end,
    {ok, {{one_for_one, 3, 10}, Workers}}.

make_worker_configs(Configs) ->
    lists:foldl(
        fun(Config, Acc) ->
            case Config of
                {Name, C} ->
                    [
                        {Name, {rabbit_webhooks, start_link, [Name, C]}, permanent, ?WORKER_WAIT, worker, [
                            rabbit_webhooks
                        ]}
                        | Acc
                    ]
            end
        end,
        [],
        Configs
    ).

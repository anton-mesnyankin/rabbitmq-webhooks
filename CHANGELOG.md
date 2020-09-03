# Changelog

All notable changes to this project will be documented in this file.

* 0.19 - Bump erlang.mk and rabbitmq-components.mk
* 0.18 - Added ability to set `X-Webhooks-Signature` as part of webhook authentication
* 0.17 - Added basic auth from AMQP headers and messages requeue on dlhttp errors
* 0.16 - Build system changed to erlang.mk. Plugin builds and works on latest Erlang and RabbitMQ
* 0.15 - Re-built the .tar.gz file to makes sure it included the latest version of plugin code
* 0.14 - Lots better error handling and a Ruby script for generating config files
* 0.13 - Updated for use with the new plugin system in RabbitMQ 2.7
* 0.12 - Updated for use with RabbitMQ 2.3.0, now uses rebar for build
* 0.11 - Updated for use with RabbitMQ 2.2.0
* 0.9 - Incorporated patch from @cameronharris for OTP R13 compatibility, Makefile tweak
* 0.8 - Added error handling for request so bad URLs don't crash broker, fix for no message headers
* 0.7 - Added send window functionality for sending webhook requests only during specified time windows
* 0.6 - Added max_send config param for limiting how many outgoing HTTP requests happen
* 0.5 - Use RabbitMQ's worker_pool for sending requests to handle massive dumps of messages
* 0.4 - Accept more than just 200 status code for CouchDB
* 0.3 - Asynchronous HTTP send, URL and method overrideable per-message.
* 0.2 - URLs can be patterns and headers that start with "X-" get passed to REST URL.
* 0.1 - Synchronous HTTP send, no URL patterns. Rough draft.

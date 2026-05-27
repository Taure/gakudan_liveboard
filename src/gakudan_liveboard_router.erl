-module(gakudan_liveboard_router).
-behaviour(nova_router).

-export([routes/1]).

%% Pages, static assets, and the live SSE stream all run on Nova's listener.
%% The /sse route returns {stream, ...}, handled by gakudan_liveboard_sse which
%% holds the connection open (see that module + novaframework/nova#387).
routes(_Environment) ->
    [
        #{
            prefix => "",
            security => false,
            routes => [
                {"/", fun gakudan_liveboard_page_controller:index/1, #{methods => [get]}},
                {"/runs/:run_id", fun gakudan_liveboard_page_controller:show/1, #{methods => [get]}},
                {"/sse/runs/:run_id", fun gakudan_liveboard_sse:stream/1, #{methods => [get]}},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "static/assets"}
            ]
        }
    ].

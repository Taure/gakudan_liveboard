-module(gakudan_liveboard_router).
-behaviour(nova_router).

-export([routes/1]).

routes(_Environment) ->
    [
        #{
            prefix => "",
            security => false,
            routes => [
                {"/", arizona_nova_live:live(gakudan_liveboard_home_view), #{methods => [get]}},
                {"/runs/:run_id", arizona_nova_live:live(gakudan_liveboard_run_view), #{
                    methods => [get]
                }},
                {"/live", arizona_nova_websocket, #{protocol => ws}},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "static/assets"}
            ]
        }
    ].

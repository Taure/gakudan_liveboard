-module(gakudan_liveboard_router).
-behaviour(nova_router).

-export([routes/1]).

routes(_Environment) ->
    Layouts = [{gakudan_liveboard_layout, render}],
    arizona_nova:routes([
        #{
            prefix => "",
            security => false,
            routes => [
                {live, "/", gakudan_liveboard_home_view, #{layouts => Layouts}},
                {live, "/runs/:run_id", gakudan_liveboard_run_view, #{layouts => Layouts}},
                {"/ws", arizona_nova_ws, #{protocol => ws}},
                {"/heartbeat", fun(_) -> {status, 200} end, #{methods => [get]}},
                {"/assets/[...]", "static/assets"}
            ]
        }
    ]).

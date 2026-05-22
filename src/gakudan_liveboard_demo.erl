-module(gakudan_liveboard_demo).
-moduledoc """
Spawns a stub-LLM run for demo purposes. Each call to `start_demo_run/0`
starts a fresh planner/coder pair that emits one entry every ~1.5s so the
liveboard has something to show.
""".

-export([start_demo_run/0]).

start_demo_run() ->
    Self = self(),
    spawn(fun() ->
        Self ! {demo_starting, run(self())}
    end),
    ok.

run(_Caller) ->
    {ok, Script} = gakudan_llm_stub_script:start_link([
        slow(~"""
        1. Define the API surface.
        2. Sketch the data model.
        3. Wire it up.
        @demo_coder, take it from here.
        """),
        slow(
            ~"""
            Implemented all three steps. Ready for review.
            done
            """
        )
    ]),
    {ok, _Sup, RunId} = gakudan:start_run(#{
        agents => [demo_planner_agent, demo_coder_agent],
        router => {gakudan_router_handoff, #{start => demo_planner}},
        llm => {gakudan_llm_stub, #{script_owner => Script}},
        max_turns => 4
    }),
    spawn(fun() -> ok = gakudan:send(RunId, ~"Design a tiny URL shortener.") end),
    RunId.

slow(Text) ->
    %% Tag responses with a synthetic delay (the stub doesn't sleep, but
    %% we tag content so a future tweak could). For now this is just a no-op
    %% wrapper kept for readability.
    {text, Text}.

-module(demo_planner_agent).
-moduledoc false.
-behaviour(gakudan_agent).
-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> demo_planner.
system_prompt() -> ~"You are a planner. Produce a numbered plan and hand off to @demo_coder.".
tools() -> [].
model() -> ~"stub".

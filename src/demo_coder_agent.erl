-module(demo_coder_agent).
-moduledoc false.
-behaviour(gakudan_agent).
-export([id/0, system_prompt/0, tools/0, model/0]).

id() -> demo_coder.
system_prompt() ->
    ~"You are a coder. Implement the plan from @demo_planner and end with the word 'done'.".
tools() -> [].
model() -> ~"stub".

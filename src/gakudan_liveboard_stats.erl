-module(gakudan_liveboard_stats).
-moduledoc """
Per-run stats for the liveboard's instrument rail.

Attaches to the gakudan `:telemetry` surface and accumulates per-run tokens,
turns, LLM calls, the turn "score", router decisions, and guardrail/budget
events into an ETS table. Subscribers (the SSE handler) get a
`{gakudan_liveboard_stats, RunId, Stats}` message on every update, so the rail
patches live.
""".

-behaviour(gen_server).
-compile({no_auto_import, [get/1]}).

-export([start_link/0, get/1, subscribe/1, subscribe_index/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([handle_event/4]).

-define(TAB, ?MODULE).
-define(MAX_BEATS, 40).
-define(MAX_EVENTS, 40).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get(gakudan:run_id()) -> map().
get(RunId) ->
    case ets:lookup(?TAB, RunId) of
        [{_, Stats}] -> Stats;
        [] -> empty()
    end.

%% Subscribe the caller to live stat updates for a run.
-spec subscribe(gakudan:run_id()) -> ok.
subscribe(RunId) ->
    gen_server:call(?MODULE, {subscribe, RunId, self()}).

%% Subscribe the caller to run-index changes (a run started/stopped/cancelled),
%% so the left column can re-render live. Delivers `{gakudan_liveboard_index,
%% RunId}` messages.
-spec subscribe_index() -> ok.
subscribe_index() ->
    gen_server:call(?MODULE, {subscribe_index, self()}).

empty() ->
    #{
        status => unknown,
        agents => [],
        router => undefined,
        tokens_in => 0,
        tokens_out => 0,
        llm_calls => 0,
        turns => 0,
        beats => [],
        events => []
    }.

init([]) ->
    _ = ets:new(?TAB, [named_table, public, set, {read_concurrency, true}]),
    Events = [
        [gakudan, run, start],
        [gakudan, run, stop],
        [gakudan, run, cancelled],
        [gakudan, turn, stop],
        [gakudan, llm, request, stop],
        [gakudan, router, decide, stop],
        [gakudan, guardrail, block],
        [gakudan, budget, exceeded]
    ],
    ok = telemetry:attach_many(?MODULE, Events, fun ?MODULE:handle_event/4, undefined),
    {ok, #{subs => #{}, index_subs => []}}.

%% Telemetry callback (runs in the emitting process; just forward).
handle_event(Event, Measurements, Meta, _Config) ->
    gen_server:cast(?MODULE, {event, Event, Measurements, Meta}).

handle_call({subscribe, RunId, Pid}, _From, #{subs := Subs} = State) ->
    _ = erlang:monitor(process, Pid),
    Pids = maps:get(RunId, Subs, []),
    {reply, ok, State#{subs => Subs#{RunId => [Pid | Pids]}}};
handle_call({subscribe_index, Pid}, _From, #{index_subs := IndexSubs} = State) ->
    _ = erlang:monitor(process, Pid),
    {reply, ok, State#{index_subs => [Pid | IndexSubs]}}.

handle_cast({event, Event, Measurements, Meta}, State) ->
    case maps:get(run_id, Meta, undefined) of
        undefined ->
            {noreply, State};
        RunId ->
            Stats = update(Event, Measurements, Meta, get(RunId)),
            ets:insert(?TAB, {RunId, Stats}),
            notify(RunId, Stats, State),
            maybe_notify_index(Event, RunId, State),
            {noreply, State}
    end.

handle_info(
    {'DOWN', _Ref, process, Pid, _Reason}, #{subs := Subs, index_subs := IndexSubs} = State
) ->
    Subs1 = maps:map(fun(_RunId, Pids) -> lists:delete(Pid, Pids) end, Subs),
    {noreply, State#{subs => Subs1, index_subs => lists:delete(Pid, IndexSubs)}};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    _ = telemetry:detach(?MODULE),
    ok.

notify(RunId, Stats, #{subs := Subs}) ->
    Msg = {gakudan_liveboard_stats, RunId, Stats},
    lists:foreach(fun(Pid) -> Pid ! Msg end, maps:get(RunId, Subs, [])).

%% A run appeared or changed lifecycle state -> the left column needs a
%% re-render (new entry, or a status pip flip).
maybe_notify_index(Event, RunId, #{index_subs := IndexSubs}) when
    Event =:= [gakudan, run, start];
    Event =:= [gakudan, run, stop];
    Event =:= [gakudan, run, cancelled];
    Event =:= [gakudan, budget, exceeded]
->
    Msg = {gakudan_liveboard_index, RunId},
    lists:foreach(fun(Pid) -> Pid ! Msg end, IndexSubs);
maybe_notify_index(_Event, _RunId, _State) ->
    ok.

update([gakudan, run, start], _M, Meta, S) ->
    S#{
        status => running,
        agents => maps:get(agents, Meta, []),
        router => maps:get(router, Meta, undefined)
    };
update([gakudan, run, stop], M, Meta, S) ->
    S#{
        status => stop_status(maps:get(reason, Meta, normal)),
        turns => maps:get(turns, M, maps:get(turns, S))
    };
update([gakudan, run, cancelled], _M, _Meta, S) ->
    S#{status => cancelled};
update([gakudan, turn, stop], _M, Meta, S) ->
    Beat = {
        maps:get(turn, Meta, 0), maps:get(agent_id, Meta, undefined), maps:get(outcome, Meta, ok)
    },
    S#{
        turns => maps:get(turns, S) + 1,
        beats => cap(maps:get(beats, S) ++ [Beat], ?MAX_BEATS)
    };
update([gakudan, llm, request, stop], M, _Meta, S) ->
    S#{
        tokens_in => maps:get(tokens_in, S) + maps:get(tokens_in, M, 0),
        tokens_out => maps:get(tokens_out, S) + maps:get(tokens_out, M, 0),
        llm_calls => maps:get(llm_calls, S) + 1
    };
update([gakudan, router, decide, stop], _M, Meta, S) ->
    add_event({router, maps:get(decision, Meta, undefined)}, S);
update([gakudan, guardrail, block], _M, Meta, S) ->
    add_event(
        {guardrail_block, maps:get(guardrail, Meta, undefined), maps:get(stage, Meta, undefined)}, S
    );
update([gakudan, budget, exceeded], _M, Meta, S) ->
    add_event({budget_exceeded, maps:get(reason, Meta, undefined)}, S#{status => budget});
update(_Event, _M, _Meta, S) ->
    S.

add_event(Ev, S) ->
    S#{events => cap(maps:get(events, S) ++ [Ev], ?MAX_EVENTS)}.

cap(List, Max) when length(List) =< Max -> List;
cap(List, Max) -> lists:nthtail(length(List) - Max, List).

stop_status(normal) -> completed;
stop_status(shutdown) -> completed;
stop_status({shutdown, {budget_exceeded, _}}) -> budget;
stop_status({shutdown, _}) -> completed;
stop_status({budget_exceeded, _}) -> budget;
stop_status(_) -> error.

-module(gakudan_liveboard_sse_tests).
-include_lib("eunit/include/eunit.hrl").

-define(LISTENER, gakudan_liveboard_sse_tests).
-define(RUN, ~"run-1").
-define(NO_EVENT, #{type => ~"message", data => [], other => []}).

line_breaks_test_() ->
    {setup, fun start/0, fun stop/1, fun({Port, _Started}) ->
        {"an entry with CR, CRLF and LF is data of one event and keeps its line breaks", fun() ->
            [Transcript, Rail] = events(stream(Port)),
            #{type := Type, data := Data, other := Other} = Transcript,
            ?assertEqual({~"datastar-patch-elements", []}, {Type, Other}),
            ?assertEqual(
                [~"elements", ~"mode", ~"selector"],
                lists:usort([hd(binary:split(Line, ~" ")) || Line <- Data])
            ),
            ?assertEqual([~"#transcript"], values(~"selector", Data)),
            ?assertEqual([~"inner"], values(~"mode", Data)),
            Elements = <<<<Line/binary, $\n>> || Line <- values(~"elements", Data)>>,
            ?assertMatch(
                {_, _}, binary:match(Elements, ~"<div class=\"body-text\">a\nb\nc\nd</div>")
            ),
            ?assertMatch(#{type := ~"datastar-patch-elements", other := []}, Rail),
            ?assertEqual([~"#rail"], values(~"selector", maps:get(data, Rail)))
        end}
    end}.

start() ->
    {ok, _} = application:ensure_all_started([cowboy, telemetry]),
    Started =
        [Registry, Sup, Blackboard] = [
            unlinked(gakudan_registry:start_link()),
            unlinked(gakudan_liveboard_sup:start_link()),
            unlinked(gakudan_blackboard:start_link(?RUN))
        ],
    ok = gakudan_registry:register(?RUN, Sup, Registry, Blackboard, Registry),
    {ok, _Entry} = gakudan_blackboard:append(Blackboard, {agent, planner}, ~"a\rb\r\nc\nd"),
    Routes = [{"/sse/runs/:run_id", gakudan_liveboard_test_stream_handler, []}],
    Dispatch = cowboy_router:compile([{'_', Routes}]),
    {ok, _} = cowboy:start_clear(?LISTENER, [{port, 0}], #{env => #{dispatch => Dispatch}}),
    {ranch:get_port(?LISTENER), Started}.

-spec unlinked({ok, pid()}) -> pid().
unlinked({ok, Pid}) ->
    true = unlink(Pid),
    Pid.

stop({_Port, Started}) ->
    ok = cowboy:stop_listener(?LISTENER),
    [exit(Pid, shutdown) || Pid <- lists:reverse(Started), is_pid(Pid)],
    ok.

%% Over HTTP/1.0 the body is not chunked: what is read after the head is the
%% event stream as sent.
stream(Port) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}]),
    ok = gen_tcp:send(Socket, [~"GET /sse/runs/", ?RUN, ~" HTTP/1.0\r\n\r\n"]),
    Bytes = received(Socket, <<>>, 5000),
    ok = gen_tcp:close(Socket),
    [_Head, Body] = binary:split(Bytes, ~"\r\n\r\n"),
    Body.

%% Waits for the first bytes, then for as long as more keep arriving.
-spec received(gen_tcp:socket(), binary(), timeout()) -> binary().
received(Socket, Read, Wait) ->
    case gen_tcp:recv(Socket, 0, Wait) of
        {ok, Bytes} when is_binary(Bytes) -> received(Socket, <<Read/binary, Bytes/binary>>, 300);
        {error, timeout} -> Read
    end.

%% Reads a stream the way an SSE client does: a line ends at CRLF, CR or LF,
%% and an empty line ends an event. A field that is neither `event` nor `data`
%% is kept under `other`.
events(Stream) ->
    events(binary:split(Stream, [~"\r\n", ~"\r", ~"\n"], [global]), ?NO_EVENT, []).

events([], _Unfinished, Events) ->
    lists:reverse(Events);
events([~"" | Lines], Event, Events) when Event =:= ?NO_EVENT ->
    events(Lines, ?NO_EVENT, Events);
events([~"" | Lines], Event = #{data := Data, other := Other}, Events) ->
    Read = Event#{data := lists:reverse(Data), other := lists:reverse(Other)},
    events(Lines, ?NO_EVENT, [Read | Events]);
events([<<$:, _Comment/binary>> | Lines], Event, Events) ->
    events(Lines, Event, Events);
events([Line | Lines], Event = #{data := Data, other := Other}, Events) ->
    Next =
        case binary:split(Line, [~": ", ~":"]) of
            [~"event", Type] -> Event#{type := Type};
            [~"data", Value] -> Event#{data := [Value | Data]};
            [Name | _Value] -> Event#{other := [Name | Other]}
        end,
    events(Lines, Next, Events).

%% What follows `Word` on the data lines of a Datastar event that start with it.
-spec values(binary(), [binary()]) -> [binary()].
values(Word, Data) ->
    Size = byte_size(Word),
    [Value || <<Start:Size/binary, $\s, Value/binary>> <- Data, Start =:= Word].

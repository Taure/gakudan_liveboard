-module(gakudan_liveboard_sse).
-moduledoc """
Server-Sent Events for a run's live transcript, served on Nova's own listener.

`stream/1` is a normal Nova controller that returns `{stream, Code, Headers,
Source}`. That tuple is picked up by a Nova return-handler we register
(`handle_stream/3`), which `stream_reply`s the SSE headers and then **holds the
connection**: it subscribes to the run's blackboard and pushes
`datastar:patch_elements/2` frames as entries arrive, looping forever.

Because the handler never returns, Nova's post-handler `render_response`
(which would `cowboy_req:reply/2` and crash with `{response_already_sent}`)
never runs. On client disconnect Cowboy terminates the request process and
`gakudan_blackboard` drops the subscription (it monitors subscribers). No
separate Cowboy listener, no Nova change - see novaframework/nova#387.
""".

-export([register/0, stream/1, handle_stream/3]).

-define(TRANSCRIPT, ~"#transcript").

%% Register the {stream, ...} return tag with Nova. Called from app start.
%% Register an explicit /3 fun: current Nova invokes handlers with 3 args
%% (nova_handler:call_handler), and its `{Mod, Fun}` form wraps to arity /4,
%% which mismatches - so we pass the fun directly, like the built-in handlers.
-spec register() -> ok | {error, atom()}.
register() ->
    nova_handlers:register_handler(stream, fun ?MODULE:handle_stream/3).

%% Nova controller: GET /sse/runs/:run_id
stream(Req) ->
    RunId = maps:get(~"run_id", maps:get(bindings, Req, #{}), ~""),
    case gakudan_run:blackboard(RunId) of
        {ok, BB} -> {stream, 200, headers(), {run_transcript, BB}};
        {error, not_found} -> {status, 404, #{}, ~"run not found"}
    end.

%% Registered Nova handler. Holds the connection; never returns.
handle_stream({stream, Code, Headers, Source}, _Callback, Req0) ->
    Req = cowboy_req:stream_reply(Code, Headers, Req0),
    serve(Source, Req).

serve({run_transcript, BB}, Req) ->
    {ok, _Ref} = gakudan_blackboard:subscribe(BB),
    Initial = datastar:patch_elements(
        transcript_html(gakudan_blackboard:entries(BB)),
        #{selector => ?TRANSCRIPT, mode => inner}
    ),
    ok = cowboy_req:stream_body(Initial, nofin, Req),
    loop(Req).

loop(Req) ->
    receive
        {gakudan_blackboard, _RunId, {entry_added, Entry}} ->
            Frame = datastar:patch_elements(
                entry_html(Entry), #{selector => ?TRANSCRIPT, mode => append}
            ),
            ok = cowboy_req:stream_body(Frame, nofin, Req),
            loop(Req);
        _Other ->
            loop(Req)
    end.

headers() ->
    maps:from_list(datastar:sse_headers()).

transcript_html([]) ->
    ~"<p class=\"empty\">no entries yet</p>";
transcript_html(Entries) ->
    [entry_html(E) || E <- Entries].

entry_html(#{role := Role, content := Content}) ->
    {Class, Who, Color} = role_meta(Role),
    [
        ~"<div class=\"entry ",
        Class,
        ~"\" style=\"--agent:",
        Color,
        ~"\"><div class=\"entry-head\"><span class=\"who\">",
        html_escape(Who),
        ~"</span></div><div class=\"body-text\">",
        html_escape(to_text(Content)),
        ~"</div></div>"
    ].

role_meta(user) ->
    {~"user", ~"operator", ~"#aaa496"};
role_meta(system) ->
    {~"system", ~"system", ~"#565d72"};
role_meta({agent, A}) ->
    Name = atom_to_binary(A),
    {~"agent", Name, agent_color(Name)}.

agent_color(Name) ->
    Palette = {~"#d8a84b", ~"#62cdcd", ~"#f0c971", ~"#84b88f"},
    element(1 + erlang:phash2(Name, tuple_size(Palette)), Palette).

to_text(C) when is_binary(C) -> C;
to_text(_) -> ~"[non-text content]".

html_escape(B) ->
    B1 = binary:replace(B, ~"&", ~"&amp;", [global]),
    B2 = binary:replace(B1, ~"<", ~"&lt;", [global]),
    B3 = binary:replace(B2, ~">", ~"&gt;", [global]),
    binary:replace(B3, ~"\"", ~"&quot;", [global]).

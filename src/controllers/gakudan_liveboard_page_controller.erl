-module(gakudan_liveboard_page_controller).
-moduledoc """
Nova controllers for the liveboard pages. Server-render the conductor's-console
shell (HTML + the self-hosted CSS/fonts); the live transcript and run index are
filled by the SSE handler over Datastar (`data-init` opens the streams), and the
instrument rail is rendered from `gakudan_liveboard_stats` + the run's tree.
""".

-export([index/1, show/1, rail_html/2, run_index_html/2]).

index(_Req) ->
    Runs = gakudan_registry:all(),
    Center = [
        ~"<div class=\"stage\"><h1 class=\"stage-title\">the conductor's stand</h1>",
        ~"<p class=\"stage-sub\">select a run to watch it play, live.</p></div>"
    ],
    html(page(~"gakudan liveboard", console(runlist_html(Runs, undefined), Center, ~""))).

show(Req) ->
    RunId = maps:get(~"run_id", maps:get(bindings, Req, #{}), ~""),
    Runs = gakudan_registry:all(),
    Stats = gakudan_liveboard_stats:get(RunId),
    RunSup = run_sup(RunId),
    Center = [
        ~"<div class=\"stage\"><div class=\"stage-head\"><div>",
        ~"<h1 class=\"stage-title\">run</h1><div class=\"stage-sub\"><span>",
        html_escape(RunId),
        ~"</span></div></div><div class=\"controls\">",
        hitl_button(RunId, ~"interrupt", ~"btn", ~"Interrupt"),
        hitl_button(RunId, ~"resume", ~"btn", ~"Resume"),
        hitl_button(RunId, ~"cancel", ~"btn danger", ~"Cancel"),
        ~"<span id=\"toast\" class=\"toast\"></span></div></div>",
        %% data-init runs once when Datastar initialises the element; it opens
        %% the long-lived SSE stream, and the handler patches #transcript (and
        %% the rail) as entries/telemetry arrive.
        ~"<div data-init=\"@get('/sse/runs/",
        RunId,
        ~"')\"><div id=\"transcript\" class=\"transcript\">",
        ~"<p class=\"empty\">connecting...</p></div></div></div>"
    ],
    html(
        page(
            ~"gakudan liveboard - run",
            console(runlist_html(Runs, RunId), Center, rail_html(Stats, RunSup))
        )
    ).

%% ---- layout ----

console(Left, Center, Right) ->
    [
        ~"<div class=\"console\"><aside class=\"col rail-left\">",
        Left,
        ~"</aside><main class=\"col\">",
        Center,
        ~"</main><aside class=\"col rail-right\" id=\"rail\">",
        Right,
        ~"</aside></div>"
    ].

%% Page-load left column: a stable element that opens the index SSE stream,
%% wrapped around the live-patched #run-index. The stream re-renders #run-index
%% on every run start/stop/cancel, so new runs appear without a refresh. The
%% open run (Active) is carried via ?active so its highlight survives patches.
runlist_html(Runs, Active) ->
    [
        ~"<div data-init=\"@get('",
        index_stream_url(Active),
        ~"')\">",
        run_index_html(Runs, Active),
        ~"</div>"
    ].

index_stream_url(undefined) -> ~"/sse/runs";
index_stream_url(Active) -> [~"/sse/runs?active=", Active].

run_index_html(Runs, Active) ->
    [
        ~"<div id=\"run-index\">",
        ~"<div class=\"rail-head\"><h2>Runs</h2><span class=\"count\">",
        integer_to_binary(length(Runs)),
        ~"</span></div><div class=\"runlist\">",
        case Runs of
            [] -> ~"<p class=\"empty\">no active runs</p>";
            _ -> [run_link(R, Active) || R <- Runs]
        end,
        ~"</div></div>"
    ].

run_link({RunId, _Entry}, Active) ->
    {Pip, _Label} = status_pip(maps:get(status, gakudan_liveboard_stats:get(RunId), unknown)),
    Cls =
        case RunId =:= Active of
            true -> ~"run active";
            false -> ~"run"
        end,
    [
        ~"<a class=\"",
        Cls,
        ~"\" href=\"/runs/",
        RunId,
        ~"\"><div class=\"run-top\"><span class=\"pip ",
        Pip,
        ~"\"></span><span class=\"run-id\">",
        html_escape(RunId),
        ~"</span></div></a>"
    ].

%% ---- instrument rail ----

rail_html(Stats, RunSup) ->
    #{tokens_in := In, tokens_out := Out, llm_calls := Calls, turns := Turns} = Stats,
    [
        ~"<div class=\"panel\"><h3>This run</h3><div class=\"metrics\">",
        metric(~"tokens in", integer_to_binary(In)),
        metric(~"tokens out", integer_to_binary(Out)),
        metric(~"llm calls", integer_to_binary(Calls)),
        metric(~"turns", integer_to_binary(Turns)),
        ~"</div></div>",
        ~"<div class=\"panel\"><h3>Score &middot; turns</h3><div class=\"score\">",
        score_html(maps:get(beats, Stats, [])),
        ~"</div></div>",
        ~"<div class=\"panel\"><h3>Processes</h3><div class=\"tree\">",
        tree_html(RunSup),
        ~"</div></div>",
        ~"<div class=\"panel\"><h3>Events</h3><div class=\"audit\">",
        events_html(maps:get(events, Stats, [])),
        ~"</div></div>"
    ].

metric(Label, Value) ->
    [
        ~"<div class=\"metric\"><div class=\"label\">",
        Label,
        ~"</div><div class=\"value\">",
        Value,
        ~"</div></div>"
    ].

score_html([]) ->
    ~"<p class=\"empty\">no turns yet</p>";
score_html(Beats) ->
    [beat_html(B) || B <- Beats].

beat_html({Turn, Agent, Outcome}) ->
    [
        ~"<div class=\"beat\"><span class=\"t\">t",
        integer_to_binary(Turn),
        ~"</span><div><div class=\"who2\">",
        html_escape(to_bin(Agent)),
        ~"</div><div class=\"sub\">",
        to_bin(Outcome),
        ~"</div></div></div>"
    ].

tree_html(RunSup) when is_pid(RunSup) ->
    Children =
        try
            supervisor:which_children(RunSup)
        catch
            _:_ -> []
        end,
    [
        ~"<div class=\"node\"><span class=\"sup\">run_sup</span> <span class=\"pid\">",
        pid_bin(RunSup),
        ~"</span></div>",
        [
            [
                ~"<div class=\"node\"> &#9500;&#9472; <span class=\"alive\">",
                to_bin(Id),
                ~"</span> <span class=\"pid\">",
                pid_bin(Pid),
                ~"</span></div>"
            ]
         || {Id, Pid, _Type, _Mods} <- Children, is_pid(Pid)
        ]
    ];
tree_html(_) ->
    ~"<p class=\"empty\">run not found</p>".

events_html([]) ->
    ~"<p class=\"empty\">none</p>";
events_html(Events) ->
    [
        [~"<div class=\"ev\"><span class=\"ty\">", html_escape(event_label(E)), ~"</span></div>"]
     || E <- Events
    ].

event_label({router, D}) -> [~"router ", to_bin(D)];
event_label({guardrail_block, G, S}) -> [~"guardrail block ", to_bin(G), ~" (", to_bin(S), ~")"];
event_label({budget_exceeded, R}) -> [~"budget exceeded ", to_bin(R)];
event_label(E) -> to_bin(E).

%% ---- HITL ----

hitl_button(RunId, Action, Cls, Label) ->
    [
        ~"<button class=\"",
        Cls,
        ~"\" data-on-click=\"@post('/runs/",
        RunId,
        ~"/",
        Action,
        ~"')\">",
        Label,
        ~"</button>"
    ].

%% ---- helpers ----

run_sup(RunId) ->
    case gakudan_registry:lookup(RunId) of
        {ok, #{run_sup := Sup}} -> Sup;
        _ -> undefined
    end.

status_pip(running) -> {~"running", ~"running"};
status_pip(completed) -> {~"completed", ~"completed"};
status_pip(error) -> {~"error", ~"error"};
status_pip(budget) -> {~"error", ~"budget"};
status_pip(cancelled) -> {~"cancelled", ~"cancelled"};
status_pip(_) -> {~"idle", ~"idle"}.

pid_bin(Pid) -> list_to_binary(pid_to_list(Pid)).

to_bin(B) when is_binary(B) -> B;
to_bin(A) when is_atom(A) -> atom_to_binary(A);
to_bin(I) when is_integer(I) -> integer_to_binary(I);
to_bin(T) -> iolist_to_binary(io_lib:format("~p", [T])).

html(Body) ->
    %% Self-hosted everything; a strict CSP makes any stray off-origin request
    %% (font CDN, tracker) fail loudly. 'self' covers same-origin SSE + assets.
    Headers = #{
        ~"content-type" => ~"text/html; charset=utf-8",
        %% 'unsafe-eval' is for Datastar's data-* expression evaluation (Function);
        %% only same-origin code runs. The privacy-critical directives
        %% (connect/font/img/default-src 'self') stay strict - nothing off-origin.
        ~"content-security-policy" =>
            ~"default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"
    },
    {status, 200, Headers, iolist_to_binary(Body)}.

page(Title, Content) ->
    [
        ~"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\">",
        ~"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
        ~"<title>",
        html_escape(Title),
        ~"</title><link rel=\"stylesheet\" href=\"/assets/css/app.css\">",
        ~"<script type=\"module\" src=\"/assets/js/datastar.js\"></script></head>",
        ~"<body><div id=\"app\"><header class=\"site-header\">",
        ~"<h1><a href=\"/\"><span class=\"g-mark\">\x{697D}\x{56E3}</span> gakudan</a></h1>",
        ~"<span class=\"tagline\">liveboard &mdash; the conductor's stand</span>",
        ~"</header><div class=\"container\">",
        Content,
        ~"</div></div></body></html>"
    ].

html_escape(B0) ->
    B = iolist_to_binary(B0),
    B1 = binary:replace(B, ~"&", ~"&amp;", [global]),
    B2 = binary:replace(B1, ~"<", ~"&lt;", [global]),
    B3 = binary:replace(B2, ~">", ~"&gt;", [global]),
    binary:replace(B3, ~"\"", ~"&quot;", [global]).

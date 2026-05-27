-module(gakudan_liveboard_page_controller).
-moduledoc """
Nova controllers for the liveboard pages. Server-render the conductor's-console
shell (HTML + the self-hosted CSS/fonts); the live transcript is filled by the
SSE handler over Datastar (`data-on-load` opens the stream).
""".

-export([index/1, show/1]).

index(_Req) ->
    Runs = gakudan_registry:all(),
    Content = [
        ~"<div class=\"rail-head\"><h2>Runs</h2><span class=\"count\">",
        integer_to_binary(length(Runs)),
        ~" total</span></div><div class=\"runlist\">",
        run_links(Runs),
        ~"</div>"
    ],
    html(page(~"gakudan liveboard", Content)).

show(Req) ->
    %% Nova populates path params in Req.bindings with binary keys.
    RunId = maps:get(~"run_id", maps:get(bindings, Req, #{}), ~""),
    SseUrl = [~"/sse/runs/", RunId],
    Content = [
        ~"<div class=\"stage\"><div class=\"stage-head\"><div>",
        ~"<h1 class=\"stage-title\">run</h1>",
        ~"<div class=\"stage-sub\"><span>",
        html_escape(RunId),
        ~"</span></div></div><div class=\"controls\">",
        ~"<button class=\"btn\">Interrupt</button>",
        ~"<button class=\"btn\">Resume</button>",
        ~"<button class=\"btn danger\">Cancel</button>",
        ~"</div></div>",
        %% data-on-load opens the long-lived SSE stream; the handler patches
        %% #transcript as entries arrive.
        ~"<div data-on-load=\"@get('",
        SseUrl,
        ~"')\"><div id=\"transcript\" class=\"transcript\">",
        ~"<p class=\"empty\">connecting...</p>",
        ~"</div></div></div>"
    ],
    html(page(~"gakudan liveboard - run", Content)).

run_links([]) ->
    ~"<p class=\"empty\">no active runs</p>";
run_links(Runs) ->
    [run_link(R) || R <- Runs].

run_link({RunId, _}) ->
    [
        ~"<a class=\"run\" href=\"/runs/",
        RunId,
        ~"\"><div class=\"run-top\"><span class=\"pip running\"></span>",
        ~"<span class=\"run-id\">",
        html_escape(RunId),
        ~"</span></div></a>"
    ];
run_link(RunId) when is_binary(RunId) ->
    run_link({RunId, undefined}).

html(Body) ->
    {status, 200, #{~"content-type" => ~"text/html; charset=utf-8"}, iolist_to_binary(Body)}.

page(Title, Content) ->
    [
        ~"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\">",
        ~"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">",
        ~"<title>",
        html_escape(Title),
        ~"</title><link rel=\"stylesheet\" href=\"/assets/css/app.css\">",
        ~"<script type=\"module\" src=\"/assets/js/datastar.js\"></script></head>",
        ~"<body><div id=\"app\"><header class=\"site-header\">",
        ~"<h1><a href=\"/\"><span class=\"g-mark\">",
        ~"\xe6\xa5\xbd\xe5\x9b\xa3",
        ~"</span> gakudan</a></h1>",
        ~"<span class=\"tagline\">liveboard &mdash; the conductor's stand</span>",
        ~"</header><main class=\"container\">",
        Content,
        ~"</main></div></body></html>"
    ].

html_escape(B) ->
    B1 = binary:replace(B, ~"&", ~"&amp;", [global]),
    B2 = binary:replace(B1, ~"<", ~"&lt;", [global]),
    B3 = binary:replace(B2, ~">", ~"&gt;", [global]),
    binary:replace(B3, ~"\"", ~"&quot;", [global]).

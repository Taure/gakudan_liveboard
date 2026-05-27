-module(gakudan_liveboard_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% Register the {stream, ...} SSE return-handler on Nova's listener; the
    %% live stream is served same-origin, no separate Cowboy (nova#387).
    ok = gakudan_liveboard_sse:register(),
    gakudan_liveboard_sup:start_link().

stop(_State) ->
    ok.

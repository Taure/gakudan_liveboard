-module(gakudan_liveboard_test_stream_handler).
-moduledoc false.
-behaviour(cowboy_handler).

-export([init/2]).

%% Nova hands a controller its bindings under binary keys.
-spec init(cowboy_req:req(), term()) -> no_return().
init(Req, _State) ->
    Bindings = #{~"run_id" => cowboy_req:binding(run_id, Req)},
    Stream = gakudan_liveboard_sse:stream(Req#{bindings => Bindings}),
    gakudan_liveboard_sse:handle_stream(Stream, undefined, Req).

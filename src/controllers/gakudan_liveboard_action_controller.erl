-module(gakudan_liveboard_action_controller).
-moduledoc """
Human-in-the-loop actions: POST /runs/:run_id/{interrupt,resume,cancel}.

Each calls the matching gakudan control and returns a one-shot Datastar patch
(via datastar_nova) acknowledging it. The actual run change (a system entry, a
status flip) flows back live over the open SSE stream.
""".

-export([interrupt/1, resume/1, cancel/1]).

interrupt(Req) ->
    act(
        Req,
        fun(RunId) -> gakudan:interrupt(RunId, ~"interrupted via liveboard") end,
        ~"interrupt sent"
    ).

resume(Req) ->
    act(Req, fun(RunId) -> gakudan:resume(RunId, ~"resumed via liveboard") end, ~"resume sent").

cancel(Req) ->
    act(Req, fun(RunId) -> gakudan:cancel(RunId) end, ~"cancel sent").

act(Req, Fun, Label) ->
    RunId = maps:get(~"run_id", maps:get(bindings, Req, #{}), ~""),
    Msg =
        case Fun(RunId) of
            ok -> Label;
            {error, Reason} -> [Label, ~" - ", to_bin(Reason)]
        end,
    %% One-shot Datastar SSE response via Nova's built-in handle_status: SSE
    %% headers + the patch as the body. (The run change itself flows back over
    %% the page's open SSE stream.)
    Body = datastar:patch_elements(toast(Msg)),
    {status, 200, maps:from_list(datastar:sse_headers()), iolist_to_binary(Body)}.

toast(Msg) ->
    [~"<span id=\"toast\" class=\"toast\">", html_escape(Msg), ~"</span>"].

to_bin(B) when is_binary(B) -> B;
to_bin(A) when is_atom(A) -> atom_to_binary(A);
to_bin(T) -> iolist_to_binary(io_lib:format("~p", [T])).

html_escape(B0) ->
    B = iolist_to_binary(B0),
    B1 = binary:replace(B, ~"&", ~"&amp;", [global]),
    B2 = binary:replace(B1, ~"<", ~"&lt;", [global]),
    binary:replace(B2, ~">", ~"&gt;", [global]).

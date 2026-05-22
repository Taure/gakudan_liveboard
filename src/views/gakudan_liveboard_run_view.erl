-module(gakudan_liveboard_run_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_info/2]).

mount(_Arg, Req) ->
    RunId = cowboy_req:binding(run_id, arizona_request:to_cowboy_req(Req)),
    {Entries, BlackboardPid} =
        case gakudan_run:blackboard(RunId) of
            {ok, Pid} ->
                case arizona_live:is_connected(self()) of
                    true ->
                        {ok, _Ref} = gakudan_blackboard:subscribe(Pid);
                    false ->
                        ok
                end,
                {gakudan_blackboard:entries(Pid), Pid};
            {error, not_found} ->
                {[], undefined}
        end,
    Bindings = #{
        id => ~"run_view",
        run_id => RunId,
        entries => Entries,
        blackboard => BlackboardPid
    },
    Layout = {gakudan_liveboard_layout, render, main_content, #{}},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Entries = arizona_template:get_binding(entries, Bindings),
    RunId = arizona_template:get_binding(run_id, Bindings),
    arizona_template:from_html(
        ~""""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <h2>run <span class="mono">{RunId}</span></h2>
        <div class="transcript">
            {case Entries of
                [] -> arizona_template:from_html(~"<p class=\"empty\">no entries yet</p>");
                _ -> arizona_template:render_list(fun(E) ->
                    Role = format_role(maps:get(role, E)),
                    Content = maps:get(content, E),
                    Text = case is_binary(Content) of true -> Content; false -> ~"[...]" end,
                    arizona_template:from_html(~"""
                    <article class="entry">
                        <div class="role">{Role}</div>
                        <pre class="content">{Text}</pre>
                    </article>
                    """)
                end, Entries)
            end}
        </div>
    </div>
    """"
    ).

handle_info({gakudan_blackboard, _RunId, {entry_added, Entry}}, View) ->
    State = arizona_view:get_state(View),
    Entries = arizona_stateful:get_binding(entries, State) ++ [Entry],
    NewState = arizona_stateful:put_binding(entries, Entries, State),
    {[], arizona_view:update_state(NewState, View)};
handle_info(_Msg, View) ->
    {[], View}.

format_role(user) -> ~"user";
format_role(system) -> ~"system";
format_role({agent, A}) -> atom_to_binary(A).

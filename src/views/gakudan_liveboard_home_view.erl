-module(gakudan_liveboard_home_view).
-behaviour(arizona_view).
-compile({parse_transform, arizona_parse_transform}).

-export([mount/2, render/1, handle_event/3, handle_info/2]).

mount(_Arg, _Req) ->
    case arizona_live:is_connected(self()) of
        true -> erlang:send_after(1000, self(), refresh);
        false -> ok
    end,
    Runs = list_runs(),
    Bindings = #{id => ~"home", runs => Runs},
    Layout = {gakudan_liveboard_layout, render, main_content, #{}},
    arizona_view:new(?MODULE, Bindings, Layout).

render(Bindings) ->
    Runs = arizona_template:get_binding(runs, Bindings),
    arizona_template:from_html(
        ~""""
    <div id="{arizona_template:get_binding(id, Bindings)}">
        <div class="actions">
            <button class="btn" onclick="arizona.pushEvent('start_demo')">Start demo run</button>
        </div>
        <h2>Active runs</h2>
        {case Runs of
            [] -> arizona_template:from_html(~"<p class=\"empty\">no active runs</p>");
            _ -> arizona_template:render_list(fun({RunId, _}) ->
                Href = <<"/runs/", RunId/binary>>,
                arizona_template:from_html(~"""
                <a href="{Href}" class="run-link">
                    <span class="mono">{RunId}</span>
                </a>
                """)
            end, Runs)
        end}
    </div>
    """"
    ).

handle_event(~"start_demo", _Params, View) ->
    _ = gakudan_liveboard_demo:start_demo_run(),
    State = arizona_view:get_state(View),
    Runs = list_runs(),
    NewState = arizona_stateful:put_binding(runs, Runs, State),
    {[], arizona_view:update_state(NewState, View)}.

handle_info(refresh, View) ->
    erlang:send_after(1000, self(), refresh),
    State = arizona_view:get_state(View),
    Runs = list_runs(),
    NewState = arizona_stateful:put_binding(runs, Runs, State),
    {[], arizona_view:update_state(NewState, View)}.

list_runs() ->
    gakudan_registry:all().

-module(gakudan_liveboard_page_controller_tests).

-include_lib("eunit/include/eunit.hrl").

run_id_in_urls_test_() ->
    {foreach, fun setup/0, fun cleanup/1, [
        fun a_plain_run_id_is_written_as_it_is/0,
        fun a_run_id_from_the_path_cannot_end_an_expression/0,
        fun a_run_id_from_the_path_cannot_end_an_attribute/0,
        fun a_listed_run_id_cannot_end_its_link/0,
        fun a_run_id_that_is_not_text_is_still_shown/0,
        fun every_byte_is_written_as_a_url_writes_it/0
    ]}.

setup() ->
    [ets:new(Table, [named_table, public]) || Table <- tables()].

cleanup(_Tables) ->
    [ets:delete(Table) || Table <- tables()].

tables() ->
    [gakudan_registry, gakudan_liveboard_stats].

a_plain_run_id_is_written_as_it_is() ->
    Page = show(~"run-1_a.b~c"),
    ?assertMatch({_, _}, binary:match(Page, ~"data-init=\"@get('/sse/runs/run-1_a.b~c')\"")),
    ?assertMatch({_, _}, binary:match(Page, ~"data-init=\"@get('/sse/runs?active=run-1_a.b~c')\"")),
    ?assertMatch(
        {_, _}, binary:match(Page, ~"data-on-click=\"@post('/runs/run-1_a.b~c/cancel')\"")
    ).

a_run_id_from_the_path_cannot_end_an_expression() ->
    Page = show(~"x');alert(1);('"),
    Encoded = ~"x%27%29%3Balert%281%29%3B%28%27",
    ?assertEqual(nomatch, binary:match(Page, ~"/sse/runs/x')")),
    ?assertEqual(nomatch, binary:match(Page, ~"/runs/x')")),
    ?assertEqual(nomatch, binary:match(Page, ~"active=x')")),
    ?assertMatch(
        {_, _}, binary:match(Page, <<"data-init=\"@get('/sse/runs/", Encoded/binary, "')\"">>)
    ),
    ?assertMatch(
        {_, _},
        binary:match(Page, <<"data-init=\"@get('/sse/runs?active=", Encoded/binary, "')\"">>)
    ),
    [
        ?assertMatch(
            {_, _},
            binary:match(
                Page,
                <<"data-on-click=\"@post('/runs/", Encoded/binary, "/", Action/binary, "')\"">>
            )
        )
     || Action <- [~"interrupt", ~"resume", ~"cancel"]
    ].

a_run_id_from_the_path_cannot_end_an_attribute() ->
    Page = show(~"x\"><img src=y>"),
    ?assertEqual(nomatch, binary:match(Page, ~"<img")),
    ?assertMatch(
        {_, _}, binary:match(Page, ~"data-init=\"@get('/sse/runs/x%22%3E%3Cimg%20src%3Dy%3E')\"")
    ).

a_listed_run_id_cannot_end_its_link() ->
    true = ets:insert(gakudan_registry, {~"a'b\"c d", #{}}),
    {status, 200, _Headers, Body} = gakudan_liveboard_page_controller:index(#{}),
    Page = iolist_to_binary(Body),
    ?assertMatch({_, _}, binary:match(Page, ~"href=\"/runs/a%27b%22c%20d\"")),
    ?assertMatch({_, _}, binary:match(Page, ~"<span class=\"run-id\">a'b&quot;c d</span>")).

a_run_id_that_is_not_text_is_still_shown() ->
    RunId = <<"a", 255, "b">>,
    true = ets:insert(gakudan_registry, {RunId, #{}}),
    {status, 200, _Headers, Body} = gakudan_liveboard_page_controller:index(#{}),
    ?assertMatch({_, _}, binary:match(iolist_to_binary(Body), ~"href=\"/runs/a%FFb\"")),
    ?assertMatch({_, _}, binary:match(show(RunId), ~"data-init=\"@get('/sse/runs/a%FFb')\"")).

every_byte_is_written_as_a_url_writes_it() ->
    [
        ?assertMatch(
            {_, _},
            binary:match(
                show(<<"x", Byte>>),
                <<"@get('/sse/runs/", (iolist_to_binary(uri_string:quote(<<"x", Byte>>)))/binary,
                    "')">>
            )
        )
     || Byte <- lists:seq(0, 127)
    ].

show(RunId) ->
    {status, 200, _Headers, Body} =
        gakudan_liveboard_page_controller:show(#{bindings => #{~"run_id" => RunId}}),
    iolist_to_binary(Body).

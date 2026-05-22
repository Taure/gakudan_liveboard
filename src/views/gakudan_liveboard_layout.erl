-module(gakudan_liveboard_layout).

-export([render/1]).

render(Bindings) ->
    arizona_template:from_erl([
        ~"<!DOCTYPE html>",
        {html, [{lang, ~"en"}], [
            {head, [], [
                {meta, [{charset, ~"UTF-8"}], []},
                {meta,
                    [
                        {name, ~"viewport"},
                        {content, ~"width=device-width, initial-scale=1.0"}
                    ],
                    []},
                {title, [], ~"gakudan liveboard"},
                {link, [{rel, ~"stylesheet"}, {href, ~"/assets/css/app.css"}], []},
                {script, [{type, ~"module"}],
                    ~"""
                    import Arizona from '/assets/js/arizona.min.js';
                    globalThis.arizona = new Arizona();
                    arizona.connect('/live');
                    """}
            ]},
            {body, [], [
                {header, [{class, ~"site-header"}], [
                    {h1, [], [{a, [{href, ~"/"}], ~"gakudan"}]}
                ]},
                {main, [{class, ~"container"}], [
                    arizona_template:render_slot(maps:get(main_content, Bindings))
                ]}
            ]}
        ]}
    ]).

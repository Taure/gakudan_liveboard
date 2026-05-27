-module(gakudan_liveboard_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
    Children = [
        #{id => gakudan_liveboard_stats, start => {gakudan_liveboard_stats, start_link, []}}
    ],
    {ok, {SupFlags, Children}}.

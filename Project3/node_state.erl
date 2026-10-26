-module(node_state).
-export([learn/2, known/1, snapshot/1]).

learn(Nodes, State) ->
    Self = maps:get(id, State),
    Table = lists:foldl(fun(N, T) -> rtable:add(N, Self, T) end,
                        maps:get(table, State), Nodes),
    new_leafs:update(Nodes, State#{table => Table}).

known(State) ->
    {Sm, La} = maps:get(leaf_set, State),
    lists:ukeysort(1, Sm ++ La ++ rtable:nodes(maps:get(table, State))).

%% What a node sends to a joining node: itself plus everything it knows.
snapshot(State) ->
    [maps:get(self, State) | known(State)].

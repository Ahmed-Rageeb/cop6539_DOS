-module(new_leafs).
-export([newLeafs/2, update/2]).

-define(HALF, 8).   %% |L| = 16

newLeafs(LeafSet, State) ->
    State#{leaf_set => LeafSet,
           leaf_changes => maps:get(leaf_changes, State, 0) + 1}.

update(Nodes, State) ->
    Self = maps:get(id, State),
    {Sm0, La0} = maps:get(leaf_set, State),
    All = [N || {Id, _} = N <- lists:ukeysort(1, Nodes ++ Sm0 ++ La0),
                Id =/= Self],
    Larger = lists:sublist(
               lists:sort(fun({A, _}, {B, _}) ->
                                  pastry_util:cw(Self, A) =< pastry_util:cw(Self, B)
                          end, All), ?HALF),
    Smaller = lists:sublist(
                lists:sort(fun({A, _}, {B, _}) ->
                                   pastry_util:cw(A, Self) =< pastry_util:cw(B, Self)
                           end, All), ?HALF),
    case {Smaller, Larger} =:= {Sm0, La0} of
        true  -> State;
        false -> newLeafs({Smaller, Larger}, State)
    end.

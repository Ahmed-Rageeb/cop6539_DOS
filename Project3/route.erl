-module(route).
-export([route/3, next_hop/2]).


route(Msg, Key, State) ->
    Self = maps:get(id, State),
    case next_hop(Key, State) of
        Self   -> deliver:deliver(Msg, Key, State);
        NextId -> forward:forward(Msg, Key, NextId, State)
    end.

next_hop(Key, State) ->
    Self = maps:get(id, State),
    {Sm, La} = maps:get(leaf_set, State),
    case in_leaf_range(Key, Self, Sm, La) of
        true ->
            %% Key is within the leaf set range: closest node (or self).
            pastry_util:closest(Key, [Self | [I || {I, _} <- Sm ++ La]]);
        false ->
            L = pastry_util:shl(Self, Key),
            Col = pastry_util:digit(Key, L),
            case rtable:get(L, Col, maps:get(table, State)) of
                {Id, _} -> Id;
                undefined -> rare_case(Key, L, Self, State)
            end
    end.

in_leaf_range(_Key, _Self, [], []) ->
    true;
in_leaf_range(Key, Self, Sm, La) ->
    Min = edge(Self, Sm),
    Max = edge(Self, La),
    D1 = pastry_util:cw(Min, Self),
    D2 = pastry_util:cw(Self, Max),
    Span = D1 + D2,
    Span >= pastry_util:ring() orelse pastry_util:cw(Min, Key) =< Span.

edge(Self, []) -> Self;
edge(_, List)  -> {Id, _} = lists:last(List), Id.


rare_case(Key, L, Self, State) ->
    Cands = [I || {I, _} <- node_state:known(State),
                  pastry_util:shl(I, Key) >= L,
                  pastry_util:dist(I, Key) < pastry_util:dist(Self, Key)],
    case Cands of
        [] -> Self;
        _  -> pastry_util:closest(Key, Cands)
    end.

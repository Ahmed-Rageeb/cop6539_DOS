-module(route).
-export([route/3, next_hop/2, random_hop/2]).


%% Hop limit, like a TTL. Normal routing takes about log16(N) hops, so this
%% only matters under failures, where stale leaf sets could make a message
%% go around in circles.
-define(MAX_HOPS, 64).

%% number of best next hops a randomised retry picks from
-define(RANDOM_CHOICES, 3).

route(Msg, Key, State) ->
    Self = maps:get(id, State),
    Next = case maps:get(hops, Msg, 0) >= ?MAX_HOPS of
               true -> Self;
               false ->
                   case maps:get(randomize, Msg, false) of
                       true  -> random_hop(Key, State);
                       false -> next_hop(Key, State)
                   end
           end,
    case Next of
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

%% Randomised routing for retries (bonus). Normal routing always picks the
%% same next hop, so a retry would hit the same dead link again. The paper
%% suggests retrying through a random node that still makes progress.
%%
%% A node makes progress if it shares a longer prefix with the key, or the
%% same prefix and is numerically closer. Either way we move forward, so the
%% route still ends. We need the longer-prefix case too, because a node with
%% a longer prefix isn't always numerically closer.
random_hop(Key, State) ->
    Self = maps:get(id, State),
    {Sm, La} = maps:get(leaf_set, State),
    Closer = fun(I) -> pastry_util:dist(I, Key) < pastry_util:dist(Self, Key) end,
    Cands =
        case in_leaf_range(Key, Self, Sm, La) of
            true ->
                %% last step, the closest node is in the leaf set
                [I || {I, _} <- Sm ++ La, Closer(I)];
            false ->
                L = pastry_util:shl(Self, Key),
                [I || {I, _} <- node_state:known(State),
                      begin
                          P = pastry_util:shl(I, Key),
                          P > L orelse (P >= L andalso Closer(I))
                      end]
        end,
    %% Pick from the top few candidates only. Picking from all of them made
    %% routes much longer (about 11 hops instead of 2.5 at 1,000 nodes),
    %% and each extra hop is another chance to lose the message.
    Ranked = lists:sort([{-pastry_util:shl(I, Key), pastry_util:dist(I, Key), I}
                         || I <- lists:usort(Cands)]),
    case lists:sublist(Ranked, ?RANDOM_CHOICES) of
        []   -> Self;
        Best -> element(3, lists:nth(rand:uniform(length(Best)), Best))
    end.

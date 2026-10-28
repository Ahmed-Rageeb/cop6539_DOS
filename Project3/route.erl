-module(route).
-export([route/3, next_hop/2, random_hop/2]).


%% A time-to-live, as IP uses. Healthy routing needs about log16(N) hops --
%% roughly 4 at N = 100,000 -- so this never fires in normal operation. It
%% exists so that, under failures, a message routed on stale leaf sets
%% cannot circulate indefinitely: it is delivered where it stands, and if
%% that is the wrong node the lookup is honestly reported as not found.
-define(MAX_HOPS, 64).

%% How many of the best next hops a randomised retry chooses between.
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

%% Randomised routing, used when a lookup is retried (bonus).
%%
%% Pastry's routing is deterministic: from a given node, a given key always
%% takes the same next hop. That is exactly wrong for retrying across a
%% permanently dead link -- every retry walks straight back into it. The
%% paper's remedy (section 2.5) is to retry with a randomised choice among
%% the nodes that still make progress toward the key.
%%
%% A candidate makes progress if it either shares a strictly LONGER prefix
%% with the key (what a routing-table hop does), or shares at least as long
%% a prefix and is strictly closer numerically (what the rare case does).
%% Both strictly increase the pair (shared prefix length, -distance), which
%% is bounded, so the route cannot loop -- randomising the choice changes
%% the path, never whether it terminates.
%%
%% Allowing only "strictly closer" would be wrong: a longer-prefix node is
%% not necessarily closer numerically (0x0FFF... and the key 0x1000... share
%% no prefix yet are adjacent), so excluding prefix hops could make a node
%% deliver a message that should have travelled further.
random_hop(Key, State) ->
    Self = maps:get(id, State),
    {Sm, La} = maps:get(leaf_set, State),
    Closer = fun(I) -> pastry_util:dist(I, Key) < pastry_util:dist(Self, Key) end,
    Cands =
        case in_leaf_range(Key, Self, Sm, La) of
            true ->
                %% Final stretch: the closest node is in the leaf set.
                [I || {I, _} <- Sm ++ La, Closer(I)];
            false ->
                L = pastry_util:shl(Self, Key),
                [I || {I, _} <- node_state:known(State),
                      begin
                          P = pastry_util:shl(I, Key),
                          P > L orelse (P >= L andalso Closer(I))
                      end]
        end,
    %% Choose among the few BEST candidates, not among all of them.
    %%
    %% Choosing uniformly among every node that makes any progress was tried
    %% first and was badly wrong: many qualifying nodes are leaf-set
    %% neighbours only marginally closer to the key, so a message could crawl
    %% around the ring one neighbour at a time. Measured at 1,000 nodes, that
    %% raised the average route from 2.41 hops to 11.11. Since every hop is
    %% another chance to cross a failed link, the longer route lost far more
    %% than it gained -- under 20% transient loss, randomised retries
    %% succeeded LESS often than simply retrying the deterministic route.
    %%
    %% Ranking by progress -- longest shared prefix first, then numerically
    %% closest -- and choosing among the top few keeps routes near-optimal in
    %% length while still offering alternatives to a link that is down.
    Ranked = lists:sort([{-pastry_util:shl(I, Key), pastry_util:dist(I, Key), I}
                         || I <- lists:usort(Cands)]),
    case lists:sublist(Ranked, ?RANDOM_CHOICES) of
        []   -> Self;
        Best -> element(3, lists:nth(rand:uniform(length(Best)), Best))
    end.

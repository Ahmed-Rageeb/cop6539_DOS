-module(deliver).
-export([deliver/3]).

deliver(#{type := insert, value := Value, reply_to := ReplyTo, hops := Hops},
        Key, State) ->
    Store = maps:get(store, State),
    replicate(Key, Value, State),
    ReplyTo ! {put_done, Key, Hops},
    State#{store => Store#{Key => Value}};

%% The Ref ties the answer to the request that asked for it, so an origin
%% that retried can tell a late reply to an abandoned attempt from a fresh
%% one, and never counts a single request twice.
deliver(#{type := lookup, reply_to := ReplyTo, hops := Hops} = Msg, Key, State) ->
    Value = maps:get(Key, maps:get(store, State), not_found),
    ReplyTo ! {lookup_result, maps:get(ref, Msg, undefined), Key, Value, Hops},
    State;


deliver(#{type := join, joiner := {_, JoinerPid}, hops := Hops}, _Key, State) ->
    JoinerPid ! {join_state, Hops + 1, node_state:snapshot(State)},
    State;

deliver(_Msg, _Key, State) ->
    State.

%% Bonus: replication, as PAST does on top of Pastry.
%%
%% The root (numerically closest node) keeps the object and sends copies to
%% the K-1 nodes closest to the key among its own leaf set -- which are the
%% next-closest nodes in the whole network, since the leaf set is exactly
%% the root's nearest neighbours. If the root dies, the key's new closest
%% live node is one of those neighbours, so a lookup routed there still
%% finds the object. Without replication, killing the root destroys the
%% data no matter how well routing recovers.
replicate(Key, Value, State) ->
    case maps:get(replicas, maps:get(opts, State, #{}), 1) of
        K when K > 1 ->
            {Sm, La} = maps:get(leaf_set, State),
            Ranked = lists:sort([{pastry_util:dist(I, Key), P}
                                 || {I, P} <- lists:ukeysort(1, Sm ++ La)]),
            [P ! {replica, Key, Value}
             || {_, P} <- lists:sublist(Ranked, K - 1)],
            ok;
        _ ->
            ok
    end.

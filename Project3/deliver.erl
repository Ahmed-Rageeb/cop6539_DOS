-module(deliver).
-export([deliver/3]).

deliver(#{type := insert, value := Value, reply_to := ReplyTo, hops := Hops},
        Key, State) ->
    Store = maps:get(store, State),
    replicate(Key, Value, State),
    ReplyTo ! {put_done, Key, Hops},
    State#{store => Store#{Key => Value}};

%% send the ref back so the origin can match the reply to its attempt
deliver(#{type := lookup, reply_to := ReplyTo, hops := Hops} = Msg, Key, State) ->
    Value = maps:get(Key, maps:get(store, State), not_found),
    ReplyTo ! {lookup_result, maps:get(ref, Msg, undefined), Key, Value, Hops},
    State;


deliver(#{type := join, joiner := {_, JoinerPid}, hops := Hops}, _Key, State) ->
    JoinerPid ! {join_state, Hops + 1, node_state:snapshot(State)},
    State;

deliver(_Msg, _Key, State) ->
    State.

%% Bonus: replication like in PAST. The root also sends copies to the K-1
%% leaf set nodes closest to the key. If the root dies, the next closest
%% node becomes the root and already has a copy.
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

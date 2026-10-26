-module(deliver).
-export([deliver/3]).

deliver(#{type := insert, value := Value, reply_to := ReplyTo, hops := Hops},
        Key, State) ->
    Store = maps:get(store, State),
    ReplyTo ! {put_done, Key, Hops},
    State#{store => Store#{Key => Value}};

deliver(#{type := lookup, reply_to := ReplyTo, hops := Hops}, Key, State) ->
    Value = maps:get(Key, maps:get(store, State), not_found),
    ReplyTo ! {lookup_result, Key, Value, Hops},
    State;


deliver(#{type := join, joiner := {_, JoinerPid}, hops := Hops}, _Key, State) ->
    JoinerPid ! {join_state, Hops + 1, node_state:snapshot(State)},
    State;

deliver(_Msg, _Key, State) ->
    State.

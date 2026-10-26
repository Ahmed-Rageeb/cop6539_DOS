-module(forward).
-export([forward/4]).

forward(Msg, Key, NextId, State) ->
    case lists:keyfind(NextId, 1, node_state:known(State)) of
        {NextId, NextPid} ->
            Msg1 = app_forward(Msg, State),
            NextPid ! {route, Msg1#{hops => maps:get(hops, Msg1) + 1}, Key},
            State;
        false ->
            deliver:deliver(Msg, Key, State)
    end.


app_forward(#{type := join, joiner := {_, JoinerPid}} = Msg, State) ->
    JoinerPid ! {join_state, undefined, node_state:snapshot(State)},
    Msg;
app_forward(Msg, _State) ->
    Msg.

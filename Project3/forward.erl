-module(forward).
-export([forward/4]).

forward(Msg, Key, NextId, State) ->
    case lists:keyfind(NextId, 1, node_state:known(State)) of
        {NextId, NextPid} ->
            Msg1 = app_forward(Msg, State),
            case lost(Msg1, NextId, State) of
                true  -> ok;    % link failed, message is lost
                false -> NextPid ! {route, Msg1#{hops => maps:get(hops, Msg1) + 1}, Key}
            end,
            State;
        false ->
            deliver:deliver(Msg, Key, State)
    end.

%% Bonus: only lookups can be lost. Joins and inserts happen before the
%% failures start.
lost(#{type := lookup}, NextId, State) ->
    failure:lost(maps:get(id, State), NextId, maps:get(opts, State, #{}));
lost(_Msg, _NextId, _State) ->
    false.


app_forward(#{type := join, joiner := {_, JoinerPid}} = Msg, State) ->
    JoinerPid ! {join_state, undefined, node_state:snapshot(State)},
    Msg;
app_forward(Msg, _State) ->
    Msg.

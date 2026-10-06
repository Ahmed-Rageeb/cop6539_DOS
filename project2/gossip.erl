-module(gossip).
-export([run/2, start/3]).

-define(LIMIT, 10).
-define(TIMEOUT_MS, 120000).

start(PidT, N, _Main) ->
    element(rand:uniform(N), PidT) ! rumor,
    wait_all_heard(N).

wait_all_heard(0) -> converged;
wait_all_heard(K) ->
    receive {heard, _Pid} -> wait_all_heard(K - 1)
    after ?TIMEOUT_MS -> {timeout, still_waiting_for, K}
    end.

run(Main, _Id) ->
    receive {init, Nb} -> loop(Main, Nb, 0) end.


loop(Main, Nb, 0) ->
    receive rumor ->
        Main ! {heard, self()},
        loop(Main, Nb, 1)
    end;
loop(Main, Nb, Count) when Count >= ?LIMIT ->
    receive rumor -> loop(Main, Nb, Count) end;   
loop(Main, Nb, Count) ->
    receive rumor -> loop(Main, Nb, Count + 1)
    after 0 ->
        topology:pick(Nb) ! rumor,
        loop(Main, Nb, Count)
    end.
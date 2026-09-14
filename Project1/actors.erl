-module(actors).
-export([start/1, worker_loop/0]).

start(K) ->
    register(boss, self()),

    ChunkSize = 5000,  

    NumWorkers = erlang:system_info(schedulers),  
    io:format("Starting boss with ~p worker actors~n", [NumWorkers]),

    [spawn(fun worker_loop/0) || _ <- lists:seq(1, NumWorkers)],

    boss_loop(K, 0, ChunkSize).

boss_loop(K, NextNumber, ChunkSize) ->
    receive
        {request_work, WorkerPid} ->
            WorkerPid ! {work, NextNumber, NextNumber + ChunkSize - 1, K},
            boss_loop(K, NextNumber + ChunkSize, ChunkSize);

        {coin_found, Input, HashHex} ->
            io:format("~s\t~s~n", [Input, HashHex]),
            boss_loop(K, NextNumber, ChunkSize)
    end.

worker_loop() ->
    boss ! {request_work, self()},
    receive
        {work, Start, End, K} ->
            mine_range(Start, End, K),
            worker_loop()  
    end.

mine_range(Start, End, _K) when Start > End ->
    ok;
mine_range(Start, End, K) ->
    case project1:check_number("ahmedrageebahsan", Start, K) of
        true ->
            Input = "ahmedrageebahsan" ++ ";" ++ integer_to_list(Start),
            HashHex = project1:test_hash(Input),
            boss ! {coin_found, Input, HashHex};
        false ->
            ok
    end,
    mine_range(Start + 1, End, K).
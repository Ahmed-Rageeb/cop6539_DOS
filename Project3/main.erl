-module(main).
-export([main/1, start/2, start/3, run/3]).

%% The coordinator: builds the network, stores the objects, starts every
%% peer making requests, and collects the results.
%%
%% `start/2' prints, as before. `run/3' does the same work but returns the
%% statistics and tears the network down afterwards, so the experiment
%% harness can call it many times in one VM.

main([NodesArg, RequestsArg]) ->
    start(list_to_integer(NodesArg), list_to_integer(RequestsArg));
main(_) ->
    io:format("usage: main NumNodes NumRequests~n").

start(NumNodes, NumRequests) ->
    start(NumNodes, NumRequests, #{}).

start(NumNodes, NumRequests, Opts) when NumNodes > 0, NumRequests > 0 ->
    print(run(NumNodes, NumRequests, Opts)).

run(NumNodes, NumRequests, Opts) ->
    rand:seed(exsss, {erlang:phash2(self()), erlang:monotonic_time(),
                      erlang:unique_integer()}),
    Coordinator = self(),

    Peers = build_network(NumNodes, Coordinator, Opts),

    insert_objects(Peers, Coordinator),

    %% Bonus: node failure strikes once the network is built and populated.
    {Alive, Killed} = kill_nodes(Peers, maps:get(kill, Opts, 0.0)),

    lists:foreach(fun({_Id, Pid}) ->
                          Pid ! {start_requests, NumNodes, NumRequests}
                  end, Alive),
    Total = length(Alive) * NumRequests,
    Stats = collect_lookups(Total, #{done => 0, found => 0, replied => 0,
                                     hop_sum => 0, attempt_sum => 0}),

    [exit(Pid, kill) || {_, Pid} <- Peers],
    drain(),
    Stats#{nodes => NumNodes, requests => NumRequests, total => Total,
           killed => Killed, opts => Opts}.

print(#{nodes := N, requests := R, total := Total, done := Done,
        found := Found, replied := Replied, hop_sum := HopSum,
        killed := Killed, attempt_sum := AttemptSum}) ->
    Avg = case Replied of 0 -> 0.0; _ -> HopSum / Replied end,
    io:format("Nodes: ~p~nRequests per node: ~p~n"
              "Requests completed: ~p/~p (objects found: ~p)~n"
              "Average hops: ~.4f~n"
              "(log16(N) = ~.4f)~n",
              [N, R, Done, Total, Found, Avg, math:log(N) / math:log(16)]),
    case Killed of
        0 -> ok;
        _ -> io:format("Nodes killed: ~p of ~p~n", [Killed, N])
    end,
    case AttemptSum > Done of
        true -> io:format("Average attempts per request: ~.3f~n",
                          [AttemptSum / max(1, Done)]);
        false -> ok
    end.

build_network(NumNodes, Coordinator, Opts) ->
    {Id1, Pid1} = pastry_init:pastryInit(
                    #{name => {node, 1}, bootstrap => none,
                      notify => Coordinator, opts => Opts}, object_store),
    await_joined(Id1),
    build_network(2, NumNodes, Coordinator, Opts, [{Id1, Pid1}]).

build_network(N, NumNodes, _Coord, _Opts, Acc) when N > NumNodes ->
    lists:reverse(Acc);
build_network(N, NumNodes, Coord, Opts, Acc) ->
    {_, BootPid} = lists:nth(rand:uniform(length(Acc)), Acc),
    {Id, Pid} = pastry_init:pastryInit(
                  #{name => {node, N}, bootstrap => BootPid,
                    notify => Coord, opts => Opts}, object_store),
    await_joined(Id),
    build_network(N + 1, NumNodes, Coord, Opts, [{Id, Pid} | Acc]).

await_joined(Id) ->
    receive {joined, Id} -> ok
    after 10000 -> io:format("TIMEOUT waiting for node to join~n"), halt(1)
    end.

insert_objects(Peers, Coordinator) ->
    Keys = lists:map(
             fun({N, {_Id, Pid}}) ->
                     Key = pastry_util:hash({object, N}),
                     Value = lists:flatten(
                               io_lib:format("object stored for node ~p", [N])),
                     Pid ! {app_put, Key, Value, Coordinator},
                     Key
             end, lists:zip(lists:seq(1, length(Peers)), Peers)),
    lists:foreach(fun(_) ->
                          receive {put_done, _, _} -> ok
                          after 10000 ->
                                  io:format("TIMEOUT during insert~n"), halt(1)
                          end
                  end, Keys),
    Keys.

%% Bonus: kill a fraction P of the peers. The killed processes simply stop
%% existing -- they get no warning and send no goodbye, which is the hard
%% case for Pastry: neighbours learn of the failure only through detection.
kill_nodes(Peers, P) when P > 0.0 ->
    Shuffled = [X || {_, X} <- lists:sort([{rand:uniform(), Peer} || Peer <- Peers])],
    K = min(length(Peers) - 1, round(P * length(Peers))),
    {Victims, Alive} = lists:split(K, Shuffled),
    [exit(Pid, kill) || {_, Pid} <- Victims],
    {Alive, K};
kill_nodes(Peers, _) ->
    {Peers, 0}.

%% Every request ends in exactly one request_done: found, not found, or
%% given up on after its timeout. So the count of expected results is exact,
%% and the silence timeout below is a backstop, not the normal way out.
collect_lookups(Total, #{done := Total} = Stats) ->
    Stats;
collect_lookups(Total, Stats) ->
    receive
        {request_done, _Key, IsFound, Hops, Attempts} ->
            #{done := D, found := F, replied := Rp, hop_sum := H,
              attempt_sum := A} = Stats,
            Replied = Hops =/= undefined,
            collect_lookups(Total, Stats#{
                done        => D + 1,
                found       => F + case IsFound of true -> 1; false -> 0 end,
                replied     => Rp + case Replied of true -> 1; false -> 0 end,
                hop_sum     => H + case Replied of true -> Hops; false -> 0 end,
                attempt_sum => A + Attempts})
    after 30000 ->
            io:format("TIMEOUT: only ~p of ~p requests completed~n",
                      [maps:get(done, Stats), Total]),
            Stats
    end.

%% Leftover messages from the torn-down network must not leak into the next
%% run when several runs share one VM.
drain() ->
    receive _ -> drain() after 0 -> ok end.

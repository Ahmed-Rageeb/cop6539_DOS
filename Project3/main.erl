-module(main).
-export([main/1, start/2]).

main([NodesArg, RequestsArg]) ->
    start(list_to_integer(NodesArg), list_to_integer(RequestsArg));
main(_) ->
    io:format("usage: main NumNodes NumRequests~n").

start(NumNodes, NumRequests) when NumNodes > 0, NumRequests > 0 ->
    rand:seed(exsss, {erlang:phash2(self()), erlang:monotonic_time(),
                      erlang:unique_integer()}),
    Coordinator = self(),

    Peers = build_network(NumNodes, Coordinator),

    Keys = insert_objects(Peers, Coordinator),

    lists:foreach(fun({_Id, Pid}) ->
                          Pid ! {start_requests, Keys, NumRequests}
                  end, Peers),
    Total = NumNodes * NumRequests,
    {Done, Found, HopSum} = collect_lookups(Total, 0, 0, 0),

    Avg = case Done of 0 -> 0.0; _ -> HopSum / Done end,
    io:format("Nodes: ~p~nRequests per node: ~p~n"
              "Requests completed: ~p/~p (objects found: ~p)~n"
              "Average hops: ~.4f~n"
              "(log16(N) = ~.4f)~n",
              [NumNodes, NumRequests, Done, Total, Found, Avg,
               math:log(NumNodes) / math:log(16)]).

build_network(NumNodes, Coordinator) ->
    {Id1, Pid1} = pastry_init:pastryInit(
                    #{name => {node, 1}, bootstrap => none,
                      notify => Coordinator}, object_store),
    await_joined(Id1),
    build_network(2, NumNodes, Coordinator, [{Id1, Pid1}]).

build_network(N, NumNodes, _Coord, Acc) when N > NumNodes ->
    lists:reverse(Acc);
build_network(N, NumNodes, Coord, Acc) ->
    {_, BootPid} = lists:nth(rand:uniform(length(Acc)), Acc),
    {Id, Pid} = pastry_init:pastryInit(
                  #{name => {node, N}, bootstrap => BootPid,
                    notify => Coord}, object_store),
    await_joined(Id),
    build_network(N + 1, NumNodes, Coord, [{Id, Pid} | Acc]).

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

collect_lookups(Total, Total, Found, HopSum) ->
    {Total, Found, HopSum};
collect_lookups(Total, Done, Found, HopSum) ->
    receive
        {request_done, _Key, IsFound, Hops} ->
            collect_lookups(Total, Done + 1,
                            Found + case IsFound of true -> 1; false -> 0 end,
                            HopSum + Hops)
    after 15000 ->
            io:format("TIMEOUT: only ~p of ~p requests completed~n",
                      [Done, Total]),
            {Done, Found, HopSum}
    end.

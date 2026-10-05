-module(project2).
-export([start/3]).

start(N0, Topo, Algo) ->
    Mod = case Algo of
              gossip     -> gossip;
              'push-sum' -> push_sum
          end,
    N = topology:round_size(Topo, N0),
    {Time, Res} = measure_running_time(fun() -> run(N, Topo, Mod) end),
    io:format("~p ~p nodes=~p result=~p time=~p ms~n",
              [Algo, Topo, N, Res, Time / 1000]),
    ok.

measure_running_time(Fun) ->
    Start = erlang:monotonic_time(microsecond),
    Res = Fun(),
    End = erlang:monotonic_time(microsecond),
    {End - Start, Res}.

run(N, Topo, Mod) ->
    Main = self(),
    PidT = topology:create_actors(N, Topo, Mod, Main),
    Res = Mod:start(PidT, N, Main),
    [exit(P, kill) || P <- tuple_to_list(PidT)],
    Res.
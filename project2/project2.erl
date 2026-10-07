%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 2 -- Gossip / Push-Sum simulator.
%%%
%%%   project2 numNodes topology algorithm
%%%     topology  : full | 2D | line | imp2D
%%%     algorithm : gossip | push-sum
%%%
%%% Optional key=value arguments, in any position:
%%%     drop=0.1       drop 10% of messages (link failure)
%%%     death=0.2      20% of nodes die at a random time (node failure)
%%%     window=1000    the window, in ms, over which those deaths happen
%%%     hears=10       gossip: hears before an actor falls silent
%%%     timeout=60000  give up after this long
%%%
%%% `start/3' is kept for use from the Erlang shell; `main/1' adds the
%%% command line the assignment asks for. The main process is itself an
%%% actor: it builds the network, releases it, and then acts as the
%%% collector that decides when the run has converged.
%%%
%%% Two changes from the original driver:
%%%
%%%   * Setup is timed separately from convergence. The assignment asks for
%%%     the time to achieve convergence, not the time to build the network,
%%%     and for large networks the build is a substantial share.
%%%
%%%   * Failure to converge is detected rather than waited out. Gossip can
%%%     genuinely die before reaching everyone; when every actor that heard
%%%     the rumour has also fallen silent, no message can still be in
%%%     flight, so the run is over and there is nothing to wait for.
%%% @end
%%%-------------------------------------------------------------------
-module(project2).

-export([main/0, main/1, start/3, start/4, run/4, collect/3,
         measure_running_time/1]).

-define(DEFAULT_TIMEOUT, 120000).
%% If not one actor reports anything for this long, the network is quiet.
-define(STALL_MS, 2500).

-record(c, {n, algo,
            heard = 0,         % distinct actors that received the rumour
            stopped = 0,       % actors that hit the limit and fell silent
            terminated = 0,    % push-sum actors that met the stability rule
            dead = 0,
            dead_unheard = 0,
            ratios = []}).

%%====================================================================
%% Command line
%%====================================================================

main() -> usage().

main(Args) ->
    {Opts, Pos} = split_opts(Args),
    case Pos of
        [NStr, TopoStr, AlgoStr] ->
            case {num(NStr), topo(TopoStr), algo(AlgoStr)} of
                {{ok, N}, {ok, Topo}, {ok, Algo}} ->
                    report(start(N, Topo, Algo, Opts)),
                    halt(0);
                {{ok, _}, {ok, _}, error} ->
                    die("algorithm must be gossip or push-sum, got ~s", [AlgoStr]);
                {{ok, _}, error, _} ->
                    die("topology must be full, 2D, line or imp2D, got ~s", [TopoStr]);
                _ ->
                    die("numNodes must be a positive integer, got ~s", [NStr])
            end;
        _ -> usage()
    end.

topo("full")  -> {ok, full};
topo("2D")    -> {ok, '2D'};
topo("2d")    -> {ok, '2D'};
topo("line")  -> {ok, line};
topo("imp2D") -> {ok, imp2D};
topo("imp2d") -> {ok, imp2D};
topo(_)       -> error.

algo("gossip")   -> {ok, gossip};
algo("push-sum") -> {ok, push_sum};
algo("pushsum")  -> {ok, push_sum};
algo(_)          -> error.

num(S) ->
    case string:to_integer(S) of
        {I, ""} when I >= 1 -> {ok, I};
        _ -> error
    end.

die(Fmt, Args) ->
    io:format(standard_error, "ERROR: " ++ Fmt ++ "~n", Args),
    halt(1).

usage() ->
    io:format(standard_error,
      "COP6539 Project 2 -- Gossip / Push-Sum simulator~n~n"
      "  project2 <numNodes> <topology> <algorithm>~n~n"
      "  topology   full | 2D | line | imp2D~n"
      "  algorithm  gossip | push-sum~n~n"
      "Options (any position):~n"
      "  drop=0.1       drop this fraction of messages (link failure)~n"
      "  death=0.2      this fraction of nodes die mid-run (node failure)~n"
      "  window=1000    ms over which those deaths are spread~n"
      "  hears=10       gossip: hears before an actor falls silent~n"
      "  timeout=60000  give up after this many ms~n~n"
      "Examples:~n"
      "  project2 1000 full gossip~n"
      "  project2 1000 imp2D push-sum~n"
      "  project2 1000 line gossip death=0.1~n", []),
    halt(1).

split_opts(Args) ->
    lists:foldl(
      fun(A, {O, P}) ->
          case string:split(A, "=") of
              [K, V] ->
                  case opt_key(K) of
                      {ok, Key} -> {O#{Key => to_number(V)}, P};
                      error     -> {O, P ++ [A]}
                  end;
              _ -> {O, P ++ [A]}
          end
      end, {#{}, []}, Args).

opt_key("drop")    -> {ok, drop};
opt_key("death")   -> {ok, death};
opt_key("window")  -> {ok, death_window_ms};
opt_key("hears")   -> {ok, hears};
opt_key("timeout") -> {ok, timeout};
opt_key(_)         -> error.

to_number(V) ->
    case string:to_float(V) of
        {F, ""} -> F;
        _ ->
            case string:to_integer(V) of
                {I, ""} -> I;
                _ -> 0
            end
    end.

%%====================================================================
%% Timing -- exactly the shape the assignment specifies
%%====================================================================

measure_running_time(Fun) ->
    Start = erlang:monotonic_time(microsecond),
    Res = Fun(),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    {Duration, Res}.

%%====================================================================
%% A run
%%====================================================================

start(N0, Topo, Algo) -> start(N0, Topo, Algo, #{}).

start(N0, Topo, Algo, Opts) ->
    N = topology:round_size(Topo, N0),
    {SetupUs, PidT} = measure_running_time(
        fun() -> topology:create_actors(N, Topo, Algo, self(), Opts) end),
    {Us, Res} = measure_running_time(fun() -> run(N, Topo, Algo, {PidT, Opts}) end),
    teardown(PidT),
    Res#{requested => N0, nodes => N, topology => Topo, algorithm => Algo,
         micros => Us, setup_micros => SetupUs, expected => (N + 1) / 2}.

run(N, _Topo, Algo, {PidT, Opts}) ->
    Algo:start(PidT, N, Opts).

teardown(PidT) ->
    [exit(P, kill) || P <- tuple_to_list(PidT)],
    topology:unpublish(),
    drain().

%% Leftover reports from killed actors must not leak into the next run.
drain() -> receive _ -> drain() after 0 -> ok end.

%%====================================================================
%% Collector
%%====================================================================

collect(Algo, N, Opts) ->
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    collect(#c{n = N, algo = Algo}, Deadline).

collect(C, Deadline) ->
    case done(C) of
        true  -> finish(C, true, converged);
        false -> wait(C, Deadline)
    end.

%% Silence is not the same as being finished.
%%
%% The collector waits in short windows so that gossip can be cut off the
%% moment it is PROVABLY over, but a quiet window on its own proves nothing
%% -- a large push-sum network can run for seconds before the first actor
%% meets the stability rule. Treating any quiet window as the end capped
%% push-sum at 20,000 nodes: it converged 5/5 in 1.8 s at 20,000 and then
%% 0/5 at 50,000, purely because the warm-up outlasted the window.
%%
%% So a quiet window now only ends the run when it can be proved to be over;
%% otherwise we keep waiting until the real deadline.
wait(C, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining =< 0 of
        true  -> finish(C, false, timeout);
        false -> wait(C, Deadline, Remaining)
    end.

wait(C, Deadline, Remaining) ->
    receive
        {heard, _Pid} ->
            collect(C#c{heard = C#c.heard + 1}, Deadline);
        {stopped, _Pid} ->
            collect(C#c{stopped = C#c.stopped + 1}, Deadline);
        {terminated, _Pid, Ratio} ->
            collect(C#c{terminated = C#c.terminated + 1,
                        ratios = [Ratio | C#c.ratios]}, Deadline);
        {died, HadHeard} ->
            C1 = C#c{dead = C#c.dead + 1},
            C2 = case HadHeard of
                     true  -> C1;
                     false -> C1#c{dead_unheard = C1#c.dead_unheard + 1}
                 end,
            collect(C2, Deadline);
        _Other ->
            collect(C, Deadline)
    after min(?STALL_MS, Remaining) ->
        case stalled(C) of
            true  -> finish(C, false, stalled);   % gossip: provably over
            false -> wait(C, Deadline)            % keep waiting
        end
    end.

done(#c{algo = gossip, n = N, heard = H, dead_unheard = D})   -> H + D >= N;
done(#c{algo = push_sum, n = N, terminated = T, dead = D})    -> T + D >= N.

%% Gossip has provably finished spreading when no actor is still
%% transmitting, and the transmitters are exactly those that have heard the
%% rumour but not yet fallen silent. If that set is empty and coverage is
%% short of N, the rumour died out -- a real outcome on a line, not a bug.
stalled(#c{algo = gossip, heard = H, stopped = S, dead = D}) -> H - S - D =< 0;
%% Push-sum has no observable equivalent of "every transmitter is silent",
%% so it can never be proved finished early -- it waits for the deadline.
stalled(#c{algo = push_sum}) -> false.

finish(C, Converged, Reason) ->
    #{converged  => Converged,
      reason     => Reason,
      coverage   => C#c.heard,
      stopped    => C#c.stopped,
      terminated => C#c.terminated,
      dead       => C#c.dead,
      estimate   => median(C#c.ratios)}.

median([]) -> undefined;
median(L) ->
    S = lists:sort(L),
    K = length(S),
    case K rem 2 of
        1 -> lists:nth(K div 2 + 1, S);
        0 -> (lists:nth(K div 2, S) + lists:nth(K div 2 + 1, S)) / 2
    end.

%%====================================================================
%% Output
%%====================================================================

report(R) ->
    #{nodes := N, topology := Topo, algorithm := Algo, micros := Us,
      setup_micros := SetupUs, converged := Conv, coverage := Cov,
      estimate := Est, expected := Exp, reason := Reason} = R,
    io:format("~n== ~s / ~s ==~n", [algo_name(Algo), atom_to_list(Topo)]),
    io:format("Nodes:            ~p~n", [N]),
    case Conv of
        true  -> io:format("Converged in:     ~p microseconds  (~.3f ms)~n",
                           [Us, Us / 1000]);
        false -> io:format("DID NOT CONVERGE (~p) after ~p us~n", [Reason, Us])
    end,
    case Algo of
        gossip ->
            io:format("Coverage:         ~p/~p nodes (~.1f%)~n",
                      [Cov, N, 100 * Cov / N]);
        push_sum ->
            io:format("Terminated:       ~p/~p actors~n",
                      [maps:get(terminated, R), N]),
            case Est of
                undefined -> ok;
                _ ->
                    io:format("Average estimate: ~.10f  (true ~.10f)~n", [Est, Exp]),
                    io:format("Sum estimate:     ~.4f  (true ~.4f)~n",
                              [Est * N, Exp * N]),
                    io:format("Relative error:   ~.6e~n", [abs(Est - Exp) / Exp])
            end
    end,
    case maps:get(dead, R, 0) of
        0 -> ok;
        D -> io:format("Nodes died:       ~p~n", [D])
    end,
    io:format("Setup time:       ~p us (not counted)~n~n", [SetupUs]).

algo_name(gossip)   -> "gossip";
algo_name(push_sum) -> "push-sum".

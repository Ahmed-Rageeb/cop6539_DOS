%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 2 -- experiment harness.
%%%
%%% Sweeps network size across every topology and both algorithms, repeating
%%% each point several times, and writes one row per trial to CSV. The
%%% report is generated from that CSV; nothing here draws anything.
%%%
%%% Repeats matter. Gossip on a line is a genuinely stochastic process: at
%%% n = 100 it reaches every node roughly six times in ten and dies out the
%%% rest. A single trial per point would produce a meaningless curve, so
%%% every point records how many trials converged alongside the timings.
%%%
%%% Each (algorithm, topology) ladder stops climbing once a size stops
%%% converging, which is exactly the "largest network you managed to deal
%%% with" figure the README asks for.
%%% @end
%%%-------------------------------------------------------------------
-module(experiments).

-export([main/0, main/1, core/0, core/1, bonus/0, sweep/6]).


-define(CSV, "../results/project2.csv").
-define(BONUS_CSV, "../results/project2_bonus.csv").

-define(SIZES, [10, 20, 50, 100, 200, 500, 1000, 2000, 5000,
                10000, 20000, 50000, 100000]).
-define(TOPOLOGIES, [full, '2D', line, imp2D]).
-define(ALGORITHMS, [gossip, push_sum]).
-define(TRIALS, 5).

main() -> main(["core"]).

main(["core"])  -> core(), halt(0);
main(["one", A, T]) -> one(list_to_atom(A), list_to_atom(T), ?TRIALS), halt(0);
main(["header"]) -> header(), halt(0);
main(["bonus"]) -> bonus(), halt(0);
main(["all"])   -> core(), bonus(), halt(0);
main(_) ->
    io:format(standard_error, "usage: experiments core|bonus|all~n", []),
    halt(1).

core() -> core(?TRIALS).

core(Trials) ->
    {ok, F} = file:open(?CSV, [write]),
    io:format(F, "algorithm,topology,nodes,actual_nodes,trial,converged,"
                 "coverage,terminated,micros,estimate,expected,rel_error~n", []),
    [sweep(F, Algo, Topo, Trials) || Algo <- ?ALGORITHMS, Topo <- ?TOPOLOGIES],
    file:close(F),
    io:format(standard_error, "~nwrote ~s~n", [?CSV]).

%% Climb the size ladder until a configuration stops converging. Two
%% consecutive total failures end the ladder -- one alone could just be an
%% unlucky draw on a line.
sweep(F, Algo, Topo, Trials) ->
    io:format(standard_error, "~n=== ~p / ~p ===~n", [Algo, Topo]),
    sweep(F, Algo, Topo, Trials, ?SIZES, 0).

sweep(_F, _Algo, _Topo, _Trials, [], _Fails) -> ok;
sweep(_F, _Algo, _Topo, _Trials, _Sizes, Fails) when Fails >= 2 -> ok;
sweep(F, Algo, Topo, Trials, [N | Rest], Fails) ->
    Timeout = timeout_for(N),
    Rows = [trial(Algo, Topo, N, T, Timeout) || T <- lists:seq(1, Trials)],
    [emit(F, R) || R <- Rows],
    Ok = length([x || #{converged := true} <- Rows]),
    Times = [M || #{converged := true, micros := M} <- Rows],
    io:format(standard_error, "  n=~-7w ~w/~w converged~s~n",
              [N, Ok, Trials,
               case Times of
                   [] -> "";
                   _  -> io_lib:format("  median ~.1f ms", [median(Times) / 1000])
               end]),
    Fails1 = case Ok of 0 -> Fails + 1; _ -> 0 end,
    %% Stop climbing once a point already costs tens of seconds: the next
    %% size on the ladder is 2-5x larger and would only burn the full
    %% timeout on every trial to record a failure we can already predict.
    TooSlow = case Times of
                  [] -> false;
                  _  -> median(Times) > 35000000
              end,
    case TooSlow of
        true ->
            io:format(standard_error,
                      "  (ladder stops here: ~.1f s already, next size would time out)~n",
                      [median(Times) / 1000000]);
        false ->
            sweep(F, Algo, Topo, Trials, Rest, Fails1)
    end.

trial(Algo, Topo, N, T, Timeout) ->
    R = project2:start(N, Topo, Algo, #{timeout => Timeout}),
    R#{trial => T}.

%% Bigger networks legitimately need longer; without scaling, large sizes
%% would be recorded as failures when they were merely slow.
timeout_for(N) when N =< 1000  -> 15000;
timeout_for(N) when N =< 10000 -> 60000;
timeout_for(_)                 -> 180000.

emit(F, R) ->
    #{algorithm := Algo, topology := Topo, requested := Req, nodes := N,
      trial := T, converged := Conv, coverage := Cov, micros := Us,
      estimate := Est, expected := Exp, terminated := Term} = R,
    Err = case Est of
              undefined -> "";
              _ -> io_lib:format("~.12e", [abs(Est - Exp) / Exp])
          end,
    EstS = case Est of
               undefined -> "";
               _ -> io_lib:format("~.6f", [Est])
           end,
    %% ~s with atom_to_list, not ~p: ~p quotes any atom that needs quoting,
    %% so the topology '2D' would be written into the CSV as ''2D'' and no
    %% consumer comparing against "2D" would ever match it.
    io:format(F, "~s,~s,~p,~p,~p,~p,~p,~p,~p,~s,~.6f,~s~n",
              [atom_to_list(Algo), atom_to_list(Topo), Req, N, T, Conv, Cov,
               Term, Us, EstS, Exp, Err]).

median([]) -> 0;
median(L) ->
    S = lists:sort(L),
    K = length(S),
    case K rem 2 of
        1 -> lists:nth(K div 2 + 1, S);
        0 -> (lists:nth(K div 2, S) + lists:nth(K div 2 + 1, S)) / 2
    end.

%%====================================================================
%% Bonus: failure models
%%====================================================================

%% Two independent, parameterised failure models, swept across every
%% topology at a fixed network size so the parameter is the only thing
%% changing:
%%
%%   death = p  a fraction p of nodes die at a random moment mid-run
%%   drop  = q  each individual send is lost with probability q
%%
%% What matters is not just convergence time but COVERAGE -- how much of
%% the network the rumour still reached -- because under failure the
%% interesting outcome is partial delivery, not slower delivery.
%% Sized deliberately. The interesting outcome under failure is partial
%% coverage, and a run with partial coverage does not converge -- it burns
%% the whole timeout. So the cost of this sweep is dominated by failures,
%% and a 20 s timeout over 7 parameter values and 5 trials would run for
%% hours to say what 6 values and 3 trials say just as clearly. The timeout
%% only needs to exceed the converged time at n=500, which is well under
%% a second on every topology.
bonus() ->
    N = 500,
    Trials = 3,
    Ps = [0.0, 0.05, 0.10, 0.20, 0.35, 0.50],
    {ok, F} = file:open(?BONUS_CSV, [write]),
    io:format(F, "model,algorithm,topology,nodes,param,trial,converged,"
                 "coverage,terminated,reached_pct,micros,rel_error~n", []),
    [bonus_point(F, death, Algo, Topo, N, P, Trials)
     || Algo <- ?ALGORITHMS, Topo <- ?TOPOLOGIES, P <- Ps],
    [bonus_point(F, drop, Algo, Topo, N, Q, Trials)
     || Algo <- ?ALGORITHMS, Topo <- ?TOPOLOGIES, Q <- Ps],
    file:close(F),
    io:format(standard_error, "~nwrote ~s~n", [?BONUS_CSV]).

bonus_point(F, Model, Algo, Topo, N, Param, Trials) ->
    Opts0 = #{timeout => 8000},
    Opts = case Model of
               death -> Opts0#{death => Param, death_window_ms => 500};
               drop  -> Opts0#{drop => Param}
           end,
    Rows = [project2:start(N, Topo, Algo, Opts) || _ <- lists:seq(1, Trials)],
    [emit_bonus(F, Model, Param, I, R)
     || {I, R} <- lists:zip(lists:seq(1, Trials), Rows)],
    Ok = length([x || #{converged := true} <- Rows]),
    Covs = [100 * reached(Algo, R) / maps:get(nodes, R) || R <- Rows],
    io:format(standard_error, "  ~p ~p/~p ~s=~.2f  ~w/~w converged, mean reached ~.1f%~n",
              [Algo, Topo, N, Model, Param, Ok, Trials,
               lists:sum(Covs) / length(Covs)]).

emit_bonus(F, Model, Param, I, R) ->
    #{algorithm := Algo, topology := Topo, nodes := N, converged := Conv,
      coverage := Cov, terminated := Term, micros := Us,
      estimate := Est, expected := Exp} = R,
    Err = case Est of
              undefined -> "";
              _ -> io_lib:format("~.12e", [abs(Est - Exp) / Exp])
          end,
    io:format(F, "~s,~s,~s,~p,~.4f,~p,~p,~p,~p,~.4f,~p,~s~n",
              [atom_to_list(Model), atom_to_list(Algo), atom_to_list(Topo),
               N, Param, I, Conv, Cov, Term,
               100 * reached(Algo, R) / N, Us, Err]).

%%====================================================================
%% One configuration at a time
%%====================================================================

%% Each (algorithm, topology) pair is run in its own VM by sweep-all.sh, and
%% appends to the CSV. A sweep that dies at 50k nodes then costs one
%% configuration instead of the entire run, and every VM starts with a clean
%% heap and process table rather than inheriting the previous config's.
header() ->
    {ok, F} = file:open(?CSV, [write]),
    io:format(F, "algorithm,topology,nodes,actual_nodes,trial,converged,"
                 "coverage,terminated,micros,estimate,expected,rel_error~n", []),
    file:close(F).

one(Algo, Topo, Trials) ->
    {ok, F} = file:open(?CSV, [append]),
    sweep(F, Algo, Topo, Trials),
    file:close(F).

%% How much of the network the run actually got to. For gossip that is the
%% number of actors that heard the rumour; push-sum never sends `heard', so
%% its analogue is the number of actors that reached the termination rule.
%% Reporting gossip's metric for both would make every push-sum row read 0%.
reached(gossip, #{coverage := C})     -> C;
reached(push_sum, #{terminated := T}) -> T.

%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 3 -- experiment harness.
%%%
%%% Writes CSV; draws nothing. `report' turns the CSV into the PDFs.
%%%
%%%   experiments core N TRIALS   one row per trial: hops at network size N
%%%   experiments bonus MODEL     one failure model, every parameter and
%%%                               every defence, three trials each
%%%
%%% Driven by run-experiments.sh, which starts a fresh VM per invocation so
%%% that one failed or exhausted run cannot take the rest down with it.
%%% @end
%%%-------------------------------------------------------------------
-module(experiments).

-export([main/1]).

-define(CORE_CSV,  "results/project3.csv").
-define(BONUS_CSV, "results/project3_bonus.csv").

%% The bonus sweeps use a fixed, modest network so the failure parameter
%% is the only thing that changes between runs.
-define(BONUS_N, 1000).
-define(BONUS_REQUESTS, 3).
-define(BONUS_TRIALS, 3).

main(["header"]) ->
    write(?CORE_CSV, "nodes,requests,trial,completed,total,found,avg_hops,log16_n~n", [], write),
    write(?BONUS_CSV, "model,param,defence,trial,total,found,success_pct,avg_hops,avg_attempts~n", [], write),
    halt(0);

main(["core", NStr, TStr]) ->
    N = list_to_integer(NStr),
    [core_trial(N, T) || T <- lists:seq(1, list_to_integer(TStr))],
    halt(0);

main(["bonus", Model]) ->
    bonus(list_to_atom(Model)),
    halt(0).

%%====================================================================
%% Core: average hops as the network grows
%%====================================================================

%% Two requests per peer is plenty: hops depend on the network, not on how
%% long it runs, and N * 2 lookups is already 200,000 at the largest size.
core_trial(N, T) ->
    S = main:run(N, 2, #{}),
    Avg = avg_hops(S),
    write(?CORE_CSV, "~w,~w,~w,~w,~w,~w,~.4f,~.4f~n",
          [N, 2, T, maps:get(done, S), maps:get(total, S), maps:get(found, S),
           Avg, math:log(N) / math:log(16)], append),
    io:format(standard_error, "  N=~-7w trial ~w  ~w/~w found  ~.3f hops~n",
              [N, T, maps:get(found, S), maps:get(total, S), Avg]).

%%====================================================================
%% Bonus: one failure model at a time
%%====================================================================

%% Node death, against defences added one at a time, so each step's
%% contribution is visible on its own.
bonus(kill) ->
    Defences = [{"none",     #{}},
                {"repair",   #{repair => true}},
                {"replicas", #{repair => true, replicas => 4}},
                {"retry",    #{repair => true, replicas => 4, attempts => 3}}],
    sweep(kill, [0.0, 0.1, 0.2, 0.3, 0.4, 0.5], Defences);

%% Connection failures, against the retry policies. Temporary and permanent
%% failures reward OPPOSITE policies, which is the point of running both.
bonus(Model) when Model =:= drop; Model =:= links ->
    Defences = [{"none",   #{}},
                {"det",    #{attempts => 3, retry => det}},
                {"rand",   #{attempts => 3, retry => rand}},
                {"hybrid", #{attempts => 3, retry => hybrid}}],
    sweep(Model, [0.0, 0.05, 0.1, 0.2, 0.3], Defences).

sweep(Model, Params, Defences) ->
    [point(Model, P, Name, Opts, T)
     || P <- Params, {Name, Opts} <- Defences, T <- lists:seq(1, ?BONUS_TRIALS)],
    ok.

point(Model, P, Name, Opts, T) ->
    S = main:run(?BONUS_N, ?BONUS_REQUESTS, Opts#{Model => P}),
    #{total := Total, found := Found, done := Done, attempt_sum := A} = S,
    Pct = 100 * Found / max(1, Total),
    write(?BONUS_CSV, "~s,~.2f,~s,~w,~w,~w,~.2f,~.4f,~.4f~n",
          [atom_to_list(Model), P, Name, T, Total, Found, Pct,
           avg_hops(S), A / max(1, Done)], append),
    io:format(standard_error, "  ~s=~.2f ~-9s trial ~w  ~.1f% found~n",
              [atom_to_list(Model), P, Name, T, Pct]).

%%====================================================================

avg_hops(#{replied := 0}) -> 0.0;
avg_hops(#{replied := R, hop_sum := H}) -> H / R.

write(File, Fmt, Args, Mode) ->
    {ok, F} = file:open(File, [Mode]),
    io:format(F, Fmt, Args),
    file:close(F).

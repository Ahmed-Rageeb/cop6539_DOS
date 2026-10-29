%% Experiments for the report. Writes CSV files, report.erl makes the PDFs.
%%
%%   experiments core N TRIALS   average hops at network size N
%%   experiments bonus MODEL     one failure model with every defence
%%
%% run-experiments.sh starts a new VM for each of these.
-module(experiments).

-export([main/1]).

-define(CORE_CSV,  "results/project3.csv").
-define(BONUS_CSV, "results/project3_bonus.csv").

%% bonus runs all use the same network size so only the failure rate changes
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

%% Two requests per peer is enough, hops depend on the network size and not
%% on how long it runs.
core_trial(N, T) ->
    S = main:run(N, 2, #{}),
    Avg = avg_hops(S),
    write(?CORE_CSV, "~w,~w,~w,~w,~w,~w,~.4f,~.4f~n",
          [N, 2, T, maps:get(done, S), maps:get(total, S), maps:get(found, S),
           Avg, math:log(N) / math:log(16)], append),
    io:format(standard_error, "  N=~-7w trial ~w  ~w/~w found  ~.3f hops~n",
              [N, T, maps:get(found, S), maps:get(total, S), Avg]).

%% Node death. Each defence includes the ones before it, so we can see what
%% each one adds.
bonus(kill) ->
    Defences = [{"none",     #{}},
                {"repair",   #{repair => true}},
                {"replicas", #{repair => true, replicas => 4}},
                {"retry",    #{repair => true, replicas => 4, attempts => 3}}],
    sweep(kill, [0.0, 0.1, 0.2, 0.3, 0.4, 0.5], Defences);

%% Connection failures, against the different retry policies.
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


avg_hops(#{replied := 0}) -> 0.0;
avg_hops(#{replied := R, hop_sum := H}) -> H / R.

write(File, Fmt, Args, Mode) ->
    {ok, F} = file:open(File, [Mode]),
    io:format(F, Fmt, Args),
    file:close(F).

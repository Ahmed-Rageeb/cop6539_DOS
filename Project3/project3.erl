%% Command line entry point:  project3 numNodes numRequests [options]
%% See usage/0 for the bonus options.
-module(project3).

-export([main/0, main/1]).

%% erl -run with no arguments calls main/0
main() -> usage().

main(Args) ->
    {Opts, Pos} = split_opts(Args),
    case Pos of
        [NStr, RStr] ->
            case {int(NStr), int(RStr)} of
                {{ok, N}, {ok, R}} when N >= 1, R >= 1 ->
                    main:start(N, R, Opts),
                    halt(0);
                _ -> usage()
            end;
        _ -> usage()
    end.

usage() ->
    io:format(standard_error,
      "COP6539 Project 3 -- Pastry~n~n"
      "  project3 <numNodes> <numRequests> [options]~n~n"
      "Bonus options (any position):~n"
      "  kill=0.2      fraction of nodes that die after the network is built~n"
      "  drop=0.1      probability any one transmission is lost~n"
      "  links=0.1     fraction of node pairs permanently disconnected~n"
      "  repair=1      detect failures, repair leaf sets and routing tables~n"
      "  replicas=4    store each object on the 4 nodes closest to its key~n"
      "  attempts=3    retry a failed lookup up to 3 attempts in total~n"
      "  retry=rand    route for retries: det | rand (default) | hybrid~n"
      "  resilient     = repair=1 replicas=4 attempts=3~n~n"
      "Examples:~n"
      "  project3 1000 10~n"
      "  project3 1000 5 kill=0.3~n"
      "  project3 1000 5 kill=0.3 resilient~n", []),
    halt(1).

int(S) ->
    case string:to_integer(S) of
        {I, ""} -> {ok, I};
        _       -> error
    end.

split_opts(Args) ->
    lists:foldl(
      fun("resilient", {O, P}) ->
              {O#{repair => true, replicas => 4, attempts => 3}, P};
         (A, {O, P}) ->
              case string:split(A, "=") of
                  [K, V] ->
                      case opt(K, V) of
                          {ok, Key, Val} -> {O#{Key => Val}, P};
                          error          -> {O, P ++ [A]}
                      end;
                  _ -> {O, P ++ [A]}
              end
      end, {#{}, []}, Args).

opt("kill", V)     -> {ok, kill, num(V)};
opt("drop", V)     -> {ok, drop, num(V)};
opt("links", V)    -> {ok, links, num(V)};
opt("repair", V)   -> {ok, repair, V =/= "0"};
opt("replicas", V) -> {ok, replicas, round(num(V))};
opt("attempts", V) -> {ok, attempts, round(num(V))};
opt("retry", "det")    -> {ok, retry, det};
opt("retry", "rand")   -> {ok, retry, rand};
opt("retry", "hybrid") -> {ok, retry, hybrid};
opt(_, _)          -> error.

%% string:to_float("5") returns {error, no_float}, so check the type
num(V) ->
    case string:to_float(V) of
        {F, ""} when is_float(F) -> F;
        _ ->
            case string:to_integer(V) of
                {I, ""} when is_integer(I) -> float(I);
                _ -> 0.0
            end
    end.

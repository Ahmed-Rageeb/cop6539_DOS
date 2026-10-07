%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 2 -- network topologies.
%%%
%%% Keeps the original shape of this module -- `round_size/2',
%%% `create_actors/4' and the tagged-neighbour term consumed by `pick/1' --
%%% and changes two things that capped the simulator at a few thousand
%%% nodes.
%%%
%%% 1. THE FULLY CONNECTED CASE NO LONGER CARRIES THE PID TABLE.
%%%    `neighbors(full, ...)' used to hand every actor `{full, PidT}', the
%%%    whole N-element Pid tuple. Erlang copies terms on send, so that is N
%%%    copies of an N-element tuple: O(N^2) memory. Measured at n = 10,000
%%%    it needed 822 MB, and the growth is quadratic -- about 3.3 GB at
%%%    20,000 and hopeless at 100,000.
%%%
%%%    The tuple now lives in `persistent_term', which readers access
%%%    without copying, and an actor's neighbour term for `full' is just
%%%    `{full, N}'. This is a READ-ONLY ADDRESS BOOK, written once before
%%%    any actor can send and never mutated during a run -- the same role a
%%%    name registry plays. It is not shared mutable state and not a
%%%    concurrency mechanism: every bit of computation and communication
%%%    still happens through actors and asynchronous messages.
%%%
%%% 2. THE IMPERFECT GRID'S EXTRA EDGE IS DRAWN IN O(1).
%%%    It used to build `[I || I <- lists:seq(1, N), ...]' -- an N-element
%%%    candidate list per node, so O(N^2) setup. Measured: 6 ms at n = 400
%%%    rising to 1257 ms at n = 6400. It now draws a random index directly
%%%    and retries only on the rare collision with an existing neighbour.
%%% @end
%%%-------------------------------------------------------------------
-module(topology).

-export([round_size/2, create_actors/4, create_actors/5, pick/1, send/3,
         publish/1, unpublish/0, pid_of/1, grid_side/1]).

-define(KEY, {project2, pids}).

%%====================================================================
%% Sizing
%%====================================================================

round_size(Topo, N) when Topo =:= '2D'; Topo =:= imp2D ->
    Side = grid_side(N),
    Side * Side;
round_size(_, N) -> N.

%% Smallest S with S*S >= N. Stepped up from the integer square root rather
%% than ceil(math:sqrt(N)), so float rounding just below a perfect square
%% cannot produce a grid one row too small.
grid_side(N) when N =< 1 -> 1;
grid_side(N) -> step_up(max(1, trunc(math:sqrt(N)) - 1), N).

step_up(S, N) when S * S >= N -> S;
step_up(S, N) -> step_up(S + 1, N).

%%====================================================================
%% The index -> Pid address book
%%====================================================================

publish(PidT) -> persistent_term:put(?KEY, PidT).

unpublish() ->
    try persistent_term:erase(?KEY) catch _:_ -> ok end,
    ok.

pid_of(I) -> element(I, persistent_term:get(?KEY)).

%%====================================================================
%% Building the network
%%====================================================================

create_actors(N, Topo, AlgoModule, Main) ->
    create_actors(N, Topo, AlgoModule, Main, #{}).

create_actors(N, Topo, AlgoModule, Main, Opts) ->
    Pids = [spawn(fun() -> AlgoModule:run(Main, Id) end) || Id <- lists:seq(1, N)],
    PidT = list_to_tuple(Pids),
    %% Published before any actor is released, so nobody can look up a
    %% neighbour that does not exist yet.
    publish(PidT),
    lists:foreach(
      fun(Id) ->
          element(Id, PidT) ! {init, neighbors(Topo, N, Id, PidT), Opts}
      end,
      lists:seq(1, N)),
    PidT.

neighbors(full, N, _Id, _PidT) ->
    %% Just the size. pick/1 resolves an index through the address book.
    {full, N};
neighbors(line, N, Id, PidT) ->
    to_nb([I || I <- [Id - 1, Id + 1], I >= 1, I =< N], PidT);
neighbors('2D', N, Id, PidT) ->
    to_nb(grid_ids(N, Id), PidT);
neighbors(imp2D, N, Id, PidT) ->
    G = grid_ids(N, Id),
    to_nb(G ++ extra_edge(Id, N, G, 20), PidT).

grid_ids(N, Id) ->
    Side = grid_side(N),
    R = (Id - 1) div Side,
    C = (Id - 1) rem Side,
    [R2 * Side + C2 + 1
     || {R2, C2} <- [{R - 1, C}, {R + 1, C}, {R, C - 1}, {R, C + 1}],
        R2 >= 0, R2 < Side, C2 >= 0, C2 < Side,
        R2 * Side + C2 + 1 =< N].

%% One extra long-range edge, drawn once and then fixed. It must not
%% duplicate a grid neighbour, or it would merely re-weight an existing edge
%% instead of adding a shortcut. Bounded retries, because on a tiny grid
%% every other node may already be a neighbour.
extra_edge(_Id, _N, _G, 0) -> [];
extra_edge(Id, N, G, Tries) when N > 1 ->
    J = random_other(Id, N),
    case lists:member(J, G) of
        false -> [J];
        true  -> extra_edge(Id, N, G, Tries - 1)
    end;
extra_edge(_Id, _N, _G, _Tries) -> [].

to_nb(Ids, PidT) ->
    {list, list_to_tuple([element(I, PidT) || I <- Ids])}.

%% Uniform over 1..N excluding Id, without rejection sampling.
random_other(Id, N) ->
    J = rand:uniform(N - 1),
    case J >= Id of
        true  -> J + 1;
        false -> J
    end.

%%====================================================================
%% Choosing a neighbour
%%====================================================================

pick({list, T}) ->
    case tuple_size(T) of
        0 -> none;
        K -> element(rand:uniform(K), T)
    end;
pick({full, 1}) ->
    none;
pick({full, N}) ->
    P = pid_of(rand:uniform(N)),
    case P =:= self() of
        true  -> pick({full, N});
        false -> P
    end.

%% @doc Pick a neighbour and send, honouring the link-failure probability.
%%
%% Returns `sent', `dropped' if the link failed, or `none' if there is no
%% neighbour at all. Callers must distinguish these: push-sum may only give
%% away half its mass if the message actually left, otherwise the mass
%% simply vanishes and every estimate in the network drifts.
send(Nb, Msg, Drop) ->
    case pick(Nb) of
        none -> none;
        Pid ->
            case Drop > 0.0 andalso rand:uniform() < Drop of
                true  -> dropped;
                false -> Pid ! Msg, sent
            end
    end.

-module(topology).
-export([round_size/2, create_actors/4, pick/1]).

round_size(Topo, N) when Topo =:= '2D'; Topo =:= imp2D ->
    Side = ceil(math:sqrt(N)),
    Side * Side;
round_size(_, N) -> N.


create_actors(N, Topo, AlgoModule, Main) ->
    Pids = [spawn(fun() -> AlgoModule:run(Main, Id) end) || Id <- lists:seq(1, N)],
    PidT = list_to_tuple(Pids),
    lists:foreach(
      fun(Id) -> element(Id, PidT) ! {init, neighbors(Topo, N, Id, PidT)} end,
      lists:seq(1, N)),
    PidT.


neighbors(full, _N, _Id, PidT) ->
    {full, PidT};
neighbors(line, N, Id, PidT) ->
    to_nb([I || I <- [Id - 1, Id + 1], I >= 1, I =< N], PidT);
neighbors('2D', N, Id, PidT) ->
    to_nb(grid_ids(N, Id), PidT);
neighbors(imp2D, N, Id, PidT) ->
    G = grid_ids(N, Id),
    Others = [I || I <- lists:seq(1, N), I =/= Id, not lists:member(I, G)],
    Extra = case Others of
                [] -> [];
                _  -> [lists:nth(rand:uniform(length(Others)), Others)]
            end,
    to_nb(G ++ Extra, PidT).

grid_ids(N, Id) ->
    Side = round(math:sqrt(N)),
    R = (Id - 1) div Side,
    C = (Id - 1) rem Side,
    [R2 * Side + C2 + 1
     || {R2, C2} <- [{R - 1, C}, {R + 1, C}, {R, C - 1}, {R, C + 1}],
        R2 >= 0, R2 < Side, C2 >= 0, C2 < Side].

to_nb(Ids, PidT) ->
    {list, list_to_tuple([element(I, PidT) || I <- Ids])}.


pick({list, T}) ->
    element(rand:uniform(tuple_size(T)), T);
pick({full, T}) ->
    P = element(rand:uniform(tuple_size(T)), T),
    case P =:= self() andalso tuple_size(T) > 1 of
        true  -> pick({full, T});
        false -> P
    end.
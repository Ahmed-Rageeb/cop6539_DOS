-module(rtable).
-export([add/3, get/3, nodes/1, remove/2, row/2]).

add({Id, _} = Node, SelfId, Table) when Id =/= SelfId ->
    Row = pastry_util:shl(SelfId, Id),
    Col = pastry_util:digit(Id, Row),
    case maps:is_key({Row, Col}, Table) of
        true  -> Table;
        false -> Table#{{Row, Col} => Node}
    end;
add(_, _, Table) ->
    Table.

get(Row, Col, Table) ->
    maps:get({Row, Col}, Table, undefined).

nodes(Table) ->
    maps:values(Table).

%% Remove a failed node. Also returns the slots it was in so they can be
%% repaired.
remove(Id, Table) ->
    Vacated = [Slot || {Slot, {I, _}} <- maps:to_list(Table), I =:= Id],
    {maps:without(Vacated, Table), Vacated}.

%% all entries in one row, used when repairing a slot in that row
row(Row, Table) ->
    [Node || {{R, _}, Node} <- maps:to_list(Table), R =:= Row].

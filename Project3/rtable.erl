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

%% Drop a failed node. Returns the new table and the {Row, Col} slots it
%% occupied, so the caller knows which entries need repairing.
remove(Id, Table) ->
    Vacated = [Slot || {Slot, {I, _}} <- maps:to_list(Table), I =:= Id],
    {maps:without(Vacated, Table), Vacated}.

%% Every entry in one row -- the first place the paper looks for a
%% replacement when an entry in that row fails.
row(Row, Table) ->
    [Node || {{R, _}, Node} <- maps:to_list(Table), R =:= Row].

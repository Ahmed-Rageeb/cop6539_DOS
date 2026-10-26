-module(rtable).
-export([add/3, get/3, nodes/1]).

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

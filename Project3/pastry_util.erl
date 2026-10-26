-module(pastry_util).
-export([ring/0, num_digits/0, hash/1, digit/2, shl/2, cw/2, dist/2,
         closest/2, to_hex/1]).

-define(DIGITS, 32).
-define(RING, (1 bsl 128)).

ring() -> ?RING.
num_digits() -> ?DIGITS.

hash(Term) ->
    <<Id:128>> = erlang:md5(term_to_binary(Term)),
    Id.

digit(Id, Row) ->
    (Id bsr (4 * (?DIGITS - 1 - Row))) band 16#F.

shl(A, B) -> shl(A, B, 0).

shl(_, _, ?DIGITS) -> ?DIGITS;
shl(A, B, Row) ->
    case digit(A, Row) =:= digit(B, Row) of
        true  -> shl(A, B, Row + 1);
        false -> Row
    end.

cw(A, B) ->
    case B - A of
        D when D < 0 -> D + ?RING;
        D -> D
    end.

dist(A, B) ->
    D = cw(A, B),
    min(D, ?RING - D).

closest(Key, Ids) ->
    {_, Best} = lists:min([{dist(Key, I), I} || I <- Ids]),
    Best.

to_hex(Id) ->
    lists:flatten(io_lib:format("~32.16.0B", [Id])).

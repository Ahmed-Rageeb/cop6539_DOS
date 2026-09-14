-module(project1).

-export([check_number/3, test_hash/1,find_coin/1]).

test_hash(Text) ->

    HashBinary =
        crypto:hash(
            sha256,
            unicode:characters_to_binary(Text)
        ),

    HashHex =
        binary:encode_hex(HashBinary),

    %io:format("Input: ~s~n", [Text]),
    %io:format("Hash: ~s~n", [HashHex]),
    HashHex.

check_number(GatorId, Number, K) ->

    Input =
        GatorId ++ ";" ++ integer_to_list(Number),

    HashHex = test_hash(Input),

    Target = lists:duplicate(K, $0),
    Result = lists:prefix(Target, binary_to_list(HashHex)),

    %io:format("~p~n", [Result]),

    Result.

find_coin(K) ->
    find_coin(K, 0).

find_coin(K, Number) ->
    case check_number("ahmedrageebahsan", Number, K) of
        true ->
            Input = "ahmedrageebahsan" ++ ";" ++ integer_to_list(Number),
            HashHex = test_hash(Input),
            %io:format("FOUND coin with ~p leading zeros!~n", [K]),
            %io:format("Number: ~p~n", [Number]),
            io:format("~s\t~s~n", [Input, HashHex]),
            ok;
        false ->
            find_coin(K, Number + 1)
    end.
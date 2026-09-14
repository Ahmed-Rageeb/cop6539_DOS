%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 1 -- SHA-256 mining kernel.
%%%
%%% A "coin" is a string `<GatorId>;<N>' whose SHA-256 digest begins with
%%% at least K zero *hex digits*. One hex digit is 4 bits, so K leading
%%% hex zeros is exactly the same thing as 4*K leading zero bits -- which
%%% is what the hot loop below actually tests, straight on the raw 32-byte
%%% digest. Hex-encoding a candidate just to look at its first K
%%% characters would allocate a 64-byte binary on every single attempt;
%%% at millions of attempts per second that dominates the runtime. We only
%%% hex-encode the rare digests that actually win.
%%%
%%% This module is pure computation: no processes, no messages. All of the
%%% concurrency lives in `actors'.
%%% @end
%%%-------------------------------------------------------------------
-module(project1).

%% Original API, kept so existing calls and the Erlang shell keep working.
-export([test_hash/1, check_number/3, find_coin/1]).

%% Fast mining API used by the actor system.
-export([gator_id/0, hash/2, hex_lower/1, leading_zeros/1, mine_range/5]).

%% GatorLink ID of a team member, required by the assignment as a prefix so
%% that every group mines a disjoint set of coins.
-define(GATOR_ID, "ahmedrageebahsan").

%%====================================================================
%% Original API (behaviour preserved, implementation sped up)
%%====================================================================

gator_id() -> ?GATOR_ID.

%% @doc SHA-256 of `Text', as a lowercase hex binary.
%% Lowercase matches the assignment's sample output and the reference
%% calculator at xorbin.com.
test_hash(Text) ->
    hex_lower(crypto:hash(sha256, unicode:characters_to_binary(Text))).

%% @doc Does `<GatorId>;<Number>' hash to at least K leading zero hex digits?
check_number(GatorId, Number, K) ->
    leading_zeros(hash(GatorId, Number)) >= K.

%% @doc Sequential single-process search for one coin. Superseded by the
%% actor system in `actors'; retained only so the original entry point
%% still works from the shell.
find_coin(K) ->
    find_coin(K, 0).

find_coin(K, Number) ->
    Hash = hash(?GATOR_ID, Number),
    case leading_zeros(Hash) >= K of
        true ->
            io:format("~s;~w\t~s~n", [?GATOR_ID, Number, hex_lower(Hash)]),
            ok;
        false ->
            find_coin(K, Number + 1)
    end.

%%====================================================================
%% Hashing primitives
%%====================================================================

%% @doc SHA-256 digest (raw 32 bytes) of `<Prefix>;<N>'.
%% `crypto:hash/2' accepts iodata, so the pieces are handed over as a list
%% and never concatenated into an intermediate string.
hash(Prefix, N) ->
    crypto:hash(sha256, [Prefix, $;, integer_to_binary(N)]).

%% @doc Number of leading zero hex digits (nibbles) in a raw digest.
leading_zeros(Digest) ->
    count_zeros(Digest, 0).

count_zeros(<<0:4, Rest/bitstring>>, Acc) -> count_zeros(Rest, Acc + 1);
count_zeros(_, Acc) -> Acc.

%% @doc Lowercase hex encoding of a raw digest.
hex_lower(Digest) when is_binary(Digest) ->
    <<<<(hex_digit(Nibble))>> || <<Nibble:4>> <= Digest>>.

hex_digit(N) when N < 10 -> $0 + N;
hex_digit(N) -> $a + N - 10.

%%====================================================================
%% The hot loop
%%====================================================================

%% @doc Test every integer in `Start..End' as a coin candidate.
%%
%% `Report' is called as `Report(InputBinary, HexHashBinary, LeadingZeros)'
%% for each coin found. Because hits are astronomically rare relative to
%% attempts, everything expensive (hex encoding, counting zeros, building
%% the input binary, invoking the callback) happens only on a hit.
%%
%% Returns the number of hashes computed, which the caller reports back to
%% the boss so it can compute an overall hash rate.
mine_range(Prefix, Start, End, K, Report) ->
    %% Build "<prefix>;" once, outside the loop.
    Head = iolist_to_binary([Prefix, $;]),
    %% K leading zero hex digits == 4*K leading zero bits.
    ZeroBits = 4 * K,
    mine_loop(Head, Start, End, ZeroBits, Report, 0).

mine_loop(_Head, N, End, _ZeroBits, _Report, Count) when N > End ->
    Count;
mine_loop(Head, N, End, ZeroBits, Report, Count) ->
    Digest = crypto:hash(sha256, [Head, integer_to_binary(N)]),
    case Digest of
        <<0:ZeroBits, _/bitstring>> ->
            Input = <<Head/binary, (integer_to_binary(N))/binary>>,
            Report(Input, hex_lower(Digest), leading_zeros(Digest));
        _ ->
            ok
    end,
    mine_loop(Head, N + 1, End, ZeroBits, Report, Count + 1).

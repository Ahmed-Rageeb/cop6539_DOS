%% Failure models for the bonus. All are off by default.
%%
%%   kill=p   a fraction p of nodes die (done by the coordinator in main.erl)
%%   drop=q   each message is lost with probability q (temporary failure)
%%   links=r  a fraction r of node pairs can never talk (permanent failure)
%%
%% Failures start after the network is built and the objects are stored.
-module(failure).

-export([lost/3, link_dead/3]).

%% Is this message from FromId to ToId lost?
lost(FromId, ToId, Opts) ->
    link_dead(FromId, ToId, maps:get(links, Opts, 0.0))
        orelse transient(maps:get(drop, Opts, 0.0)).

transient(Q) when Q > 0.0 -> rand:uniform() < Q;
transient(_)              -> false.

%% A dead link is decided by hashing the pair of node ids, so every node
%% agrees on it without sharing any table, and it stays dead every time.
%% The pair is unordered so the link is dead in both directions.
link_dead(_A, _B, R) when R =< 0.0 -> false;
link_dead(A, B, R) ->
    erlang:phash2({min(A, B), max(A, B)}, 1000000) < R * 1000000.

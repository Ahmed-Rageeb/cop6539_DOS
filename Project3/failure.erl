%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 3 -- failure models (bonus).
%%%
%%% Three ways for the network to fail, matching the three the assignment
%%% names. All are off by default.
%%%
%%%   kill=p   A NODE DIES. A fraction p of the peers is killed after the
%%%            network is built and populated, just as the lookups begin.
%%%            Their processes exit, so anything in flight to them is lost.
%%%            (Applied by the coordinator in `main'.)
%%%
%%%   drop=q   A CONNECTION DIES TEMPORARILY. Each individual transmission is
%%%            lost independently with probability q. Retrying the very same
%%%            link may well succeed.
%%%
%%%   links=r  A CONNECTION DIES PERMANENTLY. A fraction r of all node pairs
%%%            cannot reach each other for the entire run, in either
%%%            direction. Retrying the same link never succeeds.
%%%
%%% Failures are injected once the network is built and its objects stored,
%%% so the experiments measure how LOOKUPS survive a failing system rather
%%% than whether a network can be built on top of one.
%%%
%%% Whether a link is permanently dead is a pure function of its two
%%% endpoints -- there is no table of dead links anywhere. Every node
%%% therefore agrees on it without coordination, and the same link is dead
%%% on every attempt, which is what "permanently" has to mean.
%%% @end
%%%-------------------------------------------------------------------
-module(failure).

-export([lost/3, link_dead/3]).

%% @doc Is this particular transmission from FromId to ToId lost?
lost(FromId, ToId, Opts) ->
    link_dead(FromId, ToId, maps:get(links, Opts, 0.0))
        orelse transient(maps:get(drop, Opts, 0.0)).

transient(Q) when Q > 0.0 -> rand:uniform() < Q;
transient(_)              -> false.

%% @doc Is the link between A and B permanently down?
%% Keyed on the unordered pair, so a dead link is dead in both directions.
link_dead(_A, _B, R) when R =< 0.0 -> false;
link_dead(A, B, R) ->
    erlang:phash2({min(A, B), max(A, B)}, 1000000) < R * 1000000.

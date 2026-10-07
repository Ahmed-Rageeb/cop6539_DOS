%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 2 -- the Push-Sum actor.
%%%
%%% Follows the same `run/2' + `start/3' shape as `gossip'.
%%%
%%% Actor i starts with s = i and w = 1. A transmit halves both and sends
%%% the other half onward; a receive adds the incoming pair in. Mass is
%%% conserved, so sum(s)/sum(w) is invariant and each actor's local ratio
%%% s/w converges to it. That invariant is (1+2+...+n)/n = (n+1)/2 -- the
%%% AVERAGE, not the sum. The assignment calls s/w the "sum estimate"; the
%%% sum is ratio * n. Both are reported.
%%%
%%% PACING. Each actor sends exactly one message per message received, and
%%% every actor is seeded with a single transmit at the start, so exactly n
%%% messages circulate for the whole run.
%%%
%%% The obvious alternative -- transmit continuously in a self-paced loop,
%%% as the Gossip actor does -- is quietly fatal here. Transmitting halves s
%%% and w, so an actor that is not receiving halves itself toward zero;
%%% after 1075 halvings w is EXACTLY 0.0 in IEEE double precision, which a
%%% busy loop reaches in well under a millisecond. From then on it ships
%%% (0.0, 0.0) messages. A recipient adding zero sees its ratio not move at
%%% all, counts that as a stable round, and terminates on whatever value it
%%% happened to be holding. Measured error with that scheme was 2-4%; with
%%% one-send-per-receive it is around 1e-13.
%%%
%%% Two further details, both fatal if missed:
%%%
%%%   1. Stability is judged ONLY on receive. Halving s and w leaves s/w
%%%      exactly unchanged, so if a transmit counted as a round then an
%%%      actor nobody ever talks to would see three identical ratios in a
%%%      row and terminate immediately, reporting its own index as the
%%%      network average.
%%%
%%%   2. Mass is given away only if the message actually departs. If the
%%%      failure model drops the send, or there is no neighbour, the actor
%%%      keeps its full s and w. Halving regardless would destroy mass and
%%%      drag every estimate in the network down.
%%%
%%% A terminated actor does not fall silent: it relays incoming mass to a
%%% random neighbour instead of absorbing it, so mass stays in circulation
%%% and the actors still running can finish converging.
%%% @end
%%%-------------------------------------------------------------------
-module(push_sum).

-export([run/2, start/3]).

-define(EPSILON, 1.0e-10).
-define(STABLE_ROUNDS, 3).

-record(s, {main, nb, s, w, ratio, stable = 0, drop = 0.0}).

%%====================================================================
%% Driver side
%%====================================================================

start(_PidT, N, Opts) ->
    %% Every actor is already active -- push-sum has no single starting
    %% node in the way gossip does; all n seed themselves on init.
    project2:collect(push_sum, N, Opts).

%%====================================================================
%% Actor side
%%====================================================================

run(Main, Id) ->
    receive
        {init, Nb, Opts} ->
            schedule_death(Opts),
            St = #s{main = Main, nb = Nb,
                    s = float(Id), w = 1.0, ratio = float(Id),
                    drop = maps:get(drop, Opts, 0.0)},
            %% Seed: one message per actor, so n are in flight at once.
            transmit(St)
    end.

schedule_death(Opts) ->
    case maps:get(death, Opts, 0.0) of
        P when P > 0.0 ->
            case rand:uniform() < P of
                true ->
                    W = maps:get(death_window_ms, Opts, 1000),
                    erlang:send_after(rand:uniform(max(1, W)), self(), die);
                false -> ok
            end;
        _ -> ok
    end.

loop(St) ->
    receive
        {push, Sr, Wr} -> absorb(St, Sr, Wr);
        die            -> St#s.main ! {died, false};
        _              -> loop(St)
    end.

transmit(St = #s{s = Sc, w = Wc}) ->
    Hs = Sc / 2.0,
    Hw = Wc / 2.0,
    case topology:send(St#s.nb, {push, Hs, Hw}, St#s.drop) of
        sent -> loop(St#s{s = Hs, w = Hw});
        _    -> loop(St)      % dropped or no neighbour: keep the mass
    end.

%% Receiving nothing carries no information, so it must not be allowed to
%% satisfy the stability rule.
absorb(St, Sr, Wr) when Sr == 0.0, Wr == 0.0 ->
    transmit(St);
absorb(St = #s{s = Sc, w = Wc, ratio = R0, stable = K}, Sr, Wr) ->
    S1 = Sc + Sr,
    W1 = Wc + Wr,
    R1 = S1 / W1,
    K1 = case abs(R1 - R0) < ?EPSILON of
             true  -> K + 1;
             false -> 0
         end,
    New = St#s{s = S1, w = W1, ratio = R1, stable = K1},
    case K1 >= ?STABLE_ROUNDS of
        true ->
            New#s.main ! {terminated, self(), R1},
            relay(New);
        false ->
            transmit(New)
    end.

%% Terminated, but still a useful relay: passing mass on rather than
%% absorbing it keeps the network's total conserved.
relay(St) ->
    receive
        {push, Sr, Wr} ->
            _ = topology:send(St#s.nb, {push, Sr, Wr}, St#s.drop),
            relay(St);
        die -> ok;
        _   -> relay(St)
    end.

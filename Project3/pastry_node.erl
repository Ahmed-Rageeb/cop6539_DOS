-module(pastry_node).
-export([start/1, loop/1]).

%% One actor per Pastry peer.
%%
%% The join protocol, routing and object store are unchanged from the
%% original. Additions, each explained where it appears:
%%   * requests carry a reference and a timeout, so every request ends in
%%     exactly one reported result even if its reply is lost
%%   * idle actors hibernate, which keeps the network's memory bounded
%%   * failure detection and the repair procedures of the Pastry paper,
%%     section 2.5 (bonus; off unless `repair' is set)

-define(IDLE_MS, 2000).

start(Init) ->
    spawn(fun() -> init(Init) end).

init(#{id := Id, app := App, bootstrap := Bootstrap, notify := Notify} = Init) ->
    rand:seed(exsss, {erlang:phash2(self()), erlang:monotonic_time(),
                      erlang:unique_integer()}),
    Self = {Id, self()},
    State = #{id => Id, self => Self, app => App, notify => Notify,
              table => #{}, leaf_set => {[], []}, store => #{},
              leaf_changes => 0,
              opts => maps:get(opts, Init, #{}),
              pending => #{},        % Ref -> {Key, Attempt} for our lookups
              monitored => #{},      % Pid -> Id, for failure detection
              dead => #{}},          % Ids known to have failed
    case Bootstrap of
        none ->                       %% first node of the network
            Notify ! {joined, Id},
            loop(State);
        BootPid ->                    %% join: route a join msg keyed by our id
            Msg = #{type => join, joiner => Self, hops => 0},
            BootPid ! {route, Msg, Id},
            loop(State#{join_recv => 0, join_expected => undefined})
    end.

loop(State) ->
    receive
        {route, Msg, Key} ->
            loop(route:route(Msg, Key, State));

        {join_state, Expected, Snapshot} ->
            S1 = learn(Snapshot, State),
            Recv = maps:get(join_recv, S1) + 1,
            Exp = case Expected of
                      undefined -> maps:get(join_expected, S1);
                      _ -> Expected
                  end,
            S2 = S1#{join_recv => Recv, join_expected => Exp},
            case Exp =:= Recv of
                true  -> loop(finish_join(S2));
                false -> loop(S2)
            end;

        {announce, Node} ->
            loop(learn([Node], State));

        {app_put, Key, Value, ReplyTo} ->
            Msg = #{type => insert, value => Value, reply_to => ReplyTo,
                    hops => 0},
            loop(route:route(Msg, Key, State));

        %% The keys in play are hash({object, K}) for K in 1..NumKeys, so a
        %% peer needs only the count to pick one. Sending every peer the list
        %% of keys instead -- which is what this message originally did --
        %% costs O(N^2) memory, because Erlang copies terms on send: measured
        %% at 4,000 nodes it added 785 MB, and 10,000 nodes ran out of memory.
        {start_requests, NumKeys, NumRequests} ->
            self() ! {tick, NumKeys, 1, NumRequests},
            loop(State);

        %% One request per second, as the assignment specifies.
        {tick, NumKeys, Seq, NumRequests} ->
            Key = pastry_util:hash({object, rand:uniform(NumKeys)}),
            S1 = send_lookup(Key, 1, State),
            case Seq < NumRequests of
                true  -> erlang:send_after(1000, self(),
                                           {tick, NumKeys, Seq + 1, NumRequests});
                false -> ok
            end,
            loop(S1);

        {lookup_result, Ref, Key, Value, Hops} ->
            loop(on_result(Ref, Key, Value, Hops, State));

        {lookup_timeout, Ref} ->
            loop(on_timeout(Ref, State));

        %% ---- bonus: replication, failure detection and repair ----

        {replica, Key, Value} ->
            Store = maps:get(store, State),
            loop(State#{store => Store#{Key => Value}});

        {'DOWN', _MRef, process, Pid, _Why} ->
            loop(on_down(Pid, State));

        {leafset_request, ReplyTo} ->
            ReplyTo ! {leafset_reply, node_state:snapshot(State)},
            loop(State);

        {leafset_reply, Nodes} ->
            loop(learn(Nodes, State));

        {rt_request, Row, Col, ReplyTo} ->
            case rtable:get(Row, Col, maps:get(table, State)) of
                undefined -> ok;
                Node      -> ReplyTo ! {rt_reply, [Node]}
            end,
            loop(State);

        {rt_reply, Nodes} ->
            loop(learn(Nodes, State))

    after ?IDLE_MS ->
        %% Idle for two seconds: compact. Hibernating garbage-collects the
        %% heap down to the live state, and the actor sleeps until the next
        %% message arrives. An idle actor blocked in receive never collects
        %% on its own, so without this the garbage left by join traffic stays
        %% resident: measured at 79 KB per node, against 9 KB with it -- the
        %% difference between topping out near 5,000 nodes and passing 50,000.
        erlang:hibernate(?MODULE, loop, [State])
    end.

finish_join(State) ->
    {Id, _} = Self = maps:get(self, State),
    [P ! {announce, Self} || {_, P} <- node_state:known(State)],
    maps:get(notify, State) ! {joined, Id},
    maps:without([join_recv, join_expected], State).

%%====================================================================
%% Learning about other nodes
%%====================================================================

%% Everything a node learns goes through here. A node already known to have
%% failed is never re-admitted: a neighbour answering a repair request may
%% not have noticed the failure yet, and would otherwise hand the dead node
%% straight back.
learn(Nodes, State) ->
    Dead = maps:get(dead, State),
    Live = [N || {Id, _} = N <- Nodes, not maps:is_key(Id, Dead)],
    watch(node_state:learn(Live, State)).

%% Failure detection (bonus). Pastry has leaf-set members exchange
%% keep-alive messages; an Erlang monitor is the runtime's own version of
%% exactly that, delivering 'DOWN' when the watched process dies. Only on
%% when repair is enabled, so the main project pays nothing for it.
watch(State) ->
    case repair_on(State) of
        false -> State;
        true ->
            Mon = maps:get(monitored, State),
            Mon1 = lists:foldl(
                     fun({Id, P}, M) ->
                         case maps:is_key(P, M) of
                             true  -> M;
                             false -> erlang:monitor(process, P), M#{P => Id}
                         end
                     end, Mon, node_state:known(State)),
            State#{monitored => Mon1}
    end.

repair_on(State) ->
    maps:get(repair, maps:get(opts, State), false) =:= true.

%%====================================================================
%% Repair after a node failure (bonus) -- Pastry paper, section 2.5
%%====================================================================

on_down(Pid, State) ->
    case maps:take(Pid, maps:get(monitored, State)) of
        error -> State;
        {Id, Mon} ->
            {Sm, La} = maps:get(leaf_set, State),
            {Table, Vacated} = rtable:remove(Id, maps:get(table, State)),
            S1 = State#{monitored => Mon,
                        dead      => (maps:get(dead, State))#{Id => true},
                        table     => Table,
                        leaf_set  => {lists:keydelete(Id, 1, Sm),
                                      lists:keydelete(Id, 1, La)}},
            repair_leaf_set(Id, Sm, La, S1),
            repair_routing_table(Vacated, S1),
            S1
    end.

%% "To replace a failed node in the leaf set, its neighbour in the nodeId
%% space contacts the live node with the largest index on the side of the
%% failed node, and asks that node for its leaf table." That node's leaf set
%% extends beyond ours on exactly the side we just lost a member from, so it
%% knows the candidates to take the failed node's place.
repair_leaf_set(Id, Sm0, La0, State) ->
    {Sm, La} = maps:get(leaf_set, State),
    [ask_leaf_set(Side, State)
     || {Side, Was} <- [{Sm, Sm0}, {La, La0}], lists:keymember(Id, 1, Was)],
    ok.

ask_leaf_set([], State) ->
    %% The whole side failed. Ask whoever we still know of.
    case node_state:known(State) of
        []           -> ok;
        [{_, P} | _] -> P ! {leafset_request, self()}
    end;
ask_leaf_set(Side, _State) ->
    {_, Farthest} = lists:last(Side),
    Farthest ! {leafset_request, self()}.

%% "To repair a failed routing table entry R[l][d], a node contacts first
%% the node referred to by another entry R[l][i], i /= d, of the same row,
%% and asks for that node's entry for R[l][d]." Every node in row l shares
%% the first l digits with us, so its own R[l][d] is a valid R[l][d] for us
%% too. Two are asked, in case the first has no such entry.
repair_routing_table(Vacated, State) ->
    Table = maps:get(table, State),
    [P ! {rt_request, Row, Col, self()}
     || {Row, Col} <- Vacated,
        {_, P} <- lists:sublist(rtable:row(Row, Table), 2)],
    ok.

%%====================================================================
%% Lookups: one result per request, with optional retry (bonus)
%%====================================================================

%% Every lookup carries a reference and arms a timeout. Without this, a
%% lookup whose message is lost -- to a dead node or a failed link -- would
%% simply never be heard of again, and nothing could count it as failed.
send_lookup(Key, Attempt, State) ->
    Opts = maps:get(opts, State),
    Ref = make_ref(),
    Msg = #{type => lookup, reply_to => self(), hops => 0, ref => Ref,
            randomize => randomize(maps:get(retry, Opts, rand), Attempt)},
    erlang:send_after(lookup_timeout(Opts), self(), {lookup_timeout, Ref}),
    Pending = maps:get(pending, State),
    route:route(Msg, Key, State#{pending => Pending#{Ref => {Key, Attempt}}}).

on_result(Ref, Key, Value, Hops, State) ->
    case maps:take(Ref, maps:get(pending, State)) of
        error ->
            %% A late answer to an attempt that already timed out and was
            %% retried or given up on. Counting it would count a request twice.
            State;
        {{_, Attempt}, Pending} ->
            S1 = State#{pending => Pending},
            Found = Value =/= not_found,
            case not Found andalso Attempt < attempts(S1) of
                %% Reached a node that does not hold the object -- possible
                %% while leaf sets are still being repaired. Try again.
                true  -> send_lookup(Key, Attempt + 1, S1);
                false -> report(Key, Found, Hops, Attempt, S1)
            end
    end.

on_timeout(Ref, State) ->
    case maps:take(Ref, maps:get(pending, State)) of
        error -> State;                          % answered in time
        {{Key, Attempt}, Pending} ->
            S1 = State#{pending => Pending},
            case Attempt < attempts(S1) of
                true  -> send_lookup(Key, Attempt + 1, S1);
                false -> report(Key, false, undefined, Attempt, S1)
            end
    end.

report(Key, Found, Hops, Attempts, State) ->
    maps:get(notify, State) ! {request_done, Key, Found, Hops, Attempts},
    State.

attempts(State) ->
    maps:get(attempts, maps:get(opts, State), 1).

%% How long to wait before declaring a lookup lost.
%%
%% Short only when something can actually be lost. In a healthy network no
%% message ever disappears, so a timeout can only ever produce FALSE
%% failures -- and it did: with a one-second timeout everywhere, 50,000
%% nodes reported half their lookups as not found and 100,000 nodes two
%% thirds, while scratch runs without the timeout found every one. Every
%% peer fires its first lookup at the same instant, and under that burst
%% some replies take longer than a second. They were not lost; they were
%% late, and the late answer was discarded as stale.
%%
%% So with no failure model and no retries, the timeout is only a backstop.
lookup_timeout(Opts) ->
    case maps:find(lookup_timeout, Opts) of
        {ok, T} -> T;
        error ->
            Failing = lists:any(fun(K) -> maps:get(K, Opts, 0.0) > 0.0 end,
                                [kill, drop, links])
                      orelse maps:get(attempts, Opts, 1) > 1,
            case Failing of
                true  -> 1000;
                false -> 60000
            end
    end.

%% Which route a retry takes. Measured at 1,000 nodes, 20% failure, three
%% attempts:
%%
%%                                  temporary   permanent   worst case
%%     no retry                         57%         57%         57%
%%     det:    same route              92%         58%         58%
%%     rand:   random route            85%         76%         76%
%%     hybrid: same once, then random  88%         70%         70%
%%
%% Against a TEMPORARY failure the same short route is best: each attempt is
%% an independent draw, and a random route only adds hops, each one another
%% chance to be lost. Against a PERMANENT failure the same route is useless
%% -- it walks straight back into the dead link.
%%
%% A node cannot tell which kind of failure lost its message, so the
%% default is the policy with the best worst case, `rand'. The hybrid looked
%% like it should combine the strengths of both, but measured it is never
%% best at either: with three attempts, spending one on the same route is
%% one attempt wasted whenever the failure is permanent.
randomize(det, _Attempt)     -> false;
randomize(rand, Attempt)     -> Attempt > 1;
randomize(hybrid, Attempt)   -> Attempt > 2.

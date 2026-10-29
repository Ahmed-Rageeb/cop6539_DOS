-module(pastry_node).
-export([start/1, loop/1]).

%% One actor per Pastry peer.

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

        %% Keys are hash({object, K}) for K in 1..NumKeys, so we only need the
        %% count. Sending the whole key list to every peer used O(N^2) memory.
        {start_requests, NumKeys, NumRequests} ->
            self() ! {tick, NumKeys, 1, NumRequests},
            loop(State);

        %% one request per second
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

        %% bonus: replication, failure detection and repair

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
        %% An idle actor never garbage collects on its own, so the garbage
        %% from join traffic would stay around. Hibernating compacts the heap.
        erlang:hibernate(?MODULE, loop, [State])
    end.

finish_join(State) ->
    {Id, _} = Self = maps:get(self, State),
    [P ! {announce, Self} || {_, P} <- node_state:known(State)],
    maps:get(notify, State) ! {joined, Id},
    maps:without([join_recv, join_expected], State).

%% Skip nodes we already know are dead. A neighbour answering a repair
%% request may not have noticed the failure yet.
learn(Nodes, State) ->
    Dead = maps:get(dead, State),
    Live = [N || {Id, _} = N <- Nodes, not maps:is_key(Id, Dead)],
    watch(node_state:learn(Live, State)).

%% Monitor every node in our tables so we get a 'DOWN' when one dies. This
%% stands in for the keep-alive messages in the paper. Only used with repair on.
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

%% Repair after a node failure, following section 2.5 of the paper.
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

%% Ask the farthest live leaf on the side that lost a node for its leaf set.
%% Its leaf set reaches further on that side, so it knows a replacement.
repair_leaf_set(Id, Sm0, La0, State) ->
    {Sm, La} = maps:get(leaf_set, State),
    [ask_leaf_set(Side, State)
     || {Side, Was} <- [{Sm, Sm0}, {La, La0}], lists:keymember(Id, 1, Was)],
    ok.

ask_leaf_set([], State) ->
    %% whole side is gone, ask anyone we still know
    case node_state:known(State) of
        []           -> ok;
        [{_, P} | _] -> P ! {leafset_request, self()}
    end;
ask_leaf_set(Side, _State) ->
    {_, Farthest} = lists:last(Side),
    Farthest ! {leafset_request, self()}.

%% Ask other nodes in the same row for their entry in the empty slot. They
%% share the same first Row digits with us, so their entry works for us too.
repair_routing_table(Vacated, State) ->
    Table = maps:get(table, State),
    [P ! {rt_request, Row, Col, self()}
     || {Row, Col} <- Vacated,
        {_, P} <- lists:sublist(rtable:row(Row, Table), 2)],
    ok.

%% Each lookup gets a ref and a timeout so a lost lookup still gets reported.
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
            %% late reply to an attempt we already retried, ignore it
            State;
        {{_, Attempt}, Pending} ->
            S1 = State#{pending => Pending},
            Found = Value =/= not_found,
            case not Found andalso Attempt < attempts(S1) of
                %% can happen while leaf sets are still being repaired
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

%% Use a short timeout only when messages can actually be lost. With no
%% failures, a short timeout just marks slow replies as failures on big
%% networks, so it is only a backstop there.
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

%% Route taken by a retry. det = same route, rand = random route,
%% hybrid = same route once, then random. rand is the default since it does
%% best when we don't know if a failure is temporary or permanent.
randomize(det, _Attempt)     -> false;
randomize(rand, Attempt)     -> Attempt > 1;
randomize(hybrid, Attempt)   -> Attempt > 2.

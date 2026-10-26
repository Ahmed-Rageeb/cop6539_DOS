-module(pastry_node).
-export([start/1]).

start(Init) ->
    spawn(fun() -> init(Init) end).

init(#{id := Id, app := App, bootstrap := Bootstrap, notify := Notify}) ->
    rand:seed(exsss, {erlang:phash2(self()), erlang:monotonic_time(),
                      erlang:unique_integer()}),
    Self = {Id, self()},
    State = #{id => Id, self => Self, app => App, notify => Notify,
              table => #{}, leaf_set => {[], []}, store => #{},
              leaf_changes => 0},
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
            S1 = node_state:learn(Snapshot, State),
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
            loop(node_state:learn([Node], State));

        {app_put, Key, Value, ReplyTo} ->
            Msg = #{type => insert, value => Value, reply_to => ReplyTo,
                    hops => 0},
            loop(route:route(Msg, Key, State));

        {start_requests, Keys, NumRequests} ->
            self() ! {tick, Keys, 1, NumRequests},
            loop(State);

        {tick, Keys, Seq, NumRequests} ->
            Key = lists:nth(rand:uniform(length(Keys)), Keys),
            Msg = #{type => lookup, reply_to => self(), hops => 0},
            S1 = route:route(Msg, Key, State),
            case Seq < NumRequests of
                true  -> erlang:send_after(1000, self(),
                                           {tick, Keys, Seq + 1, NumRequests});
                false -> ok
            end,
            loop(S1);

        {lookup_result, Key, Value, Hops} ->
            maps:get(notify, State) !
                {request_done, Key, Value =/= not_found, Hops},
            loop(State)
    end.

finish_join(State) ->
    {Id, _} = Self = maps:get(self, State),
    [P ! {announce, Self} || {_, P} <- node_state:known(State)],
    maps:get(notify, State) ! {joined, Id},
    maps:without([join_recv, join_expected], State).

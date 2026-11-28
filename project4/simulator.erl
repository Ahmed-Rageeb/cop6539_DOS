-module(simulator).
-export([run/4]).

%% Zipf exponent: subreddit of rank K gets about NumUsers / K^S members
%% and attracts posts proportionally to 1 / K^S.
-define(ZIPF_S, 1.0).

-record(c, {
    server,
    uid,
    subs = [],          % [{SubId, Rank}]
    users,              % tuple of all user ids
    deadline,
    feed = [],
    last_comment = none,
    stats = #{},        % Op => [Microseconds]
    sessions = 0
}).

%% =====================================================
%% ENTRY POINT
%% simulator:run('engine@HOST', NumUsers, NumSubs, DurationMs).
%% =====================================================

run(EngineNode, NumUsers0, NumSubs0, DurationMs) ->
    case net_adm:ping(EngineNode) of
        pong -> ok;
        pang -> erlang:error({cannot_reach_engine_node, EngineNode})
    end,
    Server = {reddit_engine, EngineNode},
    NumUsers = max(1, NumUsers0),
    NumSubs = max(1, min(NumSubs0, NumUsers)),

    ok = reddit_engine:request(Server, reset),

    %% ---------- setup ----------
    T0 = now_ms(),
    UserIds = [begin
                   {ok, Id} = reddit_engine:register_user(
                                Server, "user_" ++ integer_to_list(I)),
                   Id
               end || I <- lists:seq(1, NumUsers)],
    UserT = list_to_tuple(UserIds),

    Subs = [begin
                Owner = element(K, UserT),
                {ok, SId} = reddit_engine:create_subreddit(
                              Server, Owner, "sub_" ++ integer_to_list(K)),
                {K, SId, Owner}
            end || K <- lists:seq(1, NumSubs)],

    Joined0 = lists:foldl(
                fun({K, SId, Owner}, Acc) -> add_sub(Owner, {SId, K}, Acc) end,
                #{}, Subs),

    %% Zipf membership: rank K gets about NumUsers / K^S members
    Joined = lists:foldl(
        fun({K, SId, Owner}, Acc) ->
            Members = max(1, round(NumUsers / math:pow(K, ?ZIPF_S))),
            lists:foldl(
                fun(J, A) ->
                    Uid = element(((J + K * 13) rem NumUsers) + 1, UserT),
                    case Uid =:= Owner of
                        true -> A;
                        false ->
                            case reddit_engine:join_subreddit(Server, Uid, SId) of
                                ok -> add_sub(Uid, {SId, K}, A);
                                _  -> A
                            end
                    end
                end, Acc, lists:seq(0, Members - 1))
        end, Joined0, Subs),
    SetupMs = now_ms() - T0,

    %% ---------- run clients (each in its own process) ----------
    T1 = now_ms(),
    Deadline = T1 + DurationMs,
    Parent = self(),
    lists:foreach(
        fun(Uid) ->
            C = #c{server = Server, uid = Uid,
                   subs = maps:get(Uid, Joined, []),
                   users = UserT, deadline = Deadline},
            spawn_link(fun() -> client(Parent, C) end)
        end, UserIds),

    Results = collect(NumUsers, DurationMs + 60000, []),
    ElapsedMs = now_ms() - T1,

    report(Results, ElapsedMs, SetupMs, NumUsers, NumSubs, Server).

add_sub(U, S, Map) ->
    maps:update_with(U, fun(L) -> [S | L] end, [S], Map).

collect(0, _Timeout, Acc) -> Acc;
collect(N, Timeout, Acc) ->
    receive
        {done, Stats, Sessions} -> collect(N - 1, Timeout, [{Stats, Sessions} | Acc])
    after Timeout ->
        io:format("Timed out waiting for ~p clients~n", [N]),
        Acc
    end.

%% =====================================================
%% CLIENT: alternates ONLINE and OFFLINE periods
%% =====================================================

client(Parent, C) ->
    rand:seed(exsss, {erlang:phash2(self()),
                      erlang:unique_integer([positive]),
                      erlang:monotonic_time()}),
    Final = cycle(C),
    Parent ! {done, Final#c.stats, Final#c.sessions}.

cycle(C) ->
    case now_ms() >= C#c.deadline of
        true ->
            C;
        false ->
            C1 = reconnect(C),                         % fetch feed + inbox
            Until = min(C1#c.deadline, now_ms() + rand_between(300, 1000)),
            C2 = online(C1, Until),
            timer:sleep(rand_between(100, 500)),       % offline: no requests
            cycle(C2)
    end.

reconnect(C) ->
    {FeedR, C1} = timed(C, get_feed,
        fun() -> reddit_engine:get_feed(C#c.server, C#c.uid, 50) end),
    {_, C2} = timed(C1, get_messages,
        fun() -> reddit_engine:get_messages(C#c.server, C#c.uid) end),
    Feed = case FeedR of
               {ok, F} -> F;
               _ -> []
           end,
    C2#c{feed = Feed, sessions = C2#c.sessions + 1}.

online(C, Until) ->
    case now_ms() >= Until of
        true ->
            C;
        false ->
            C1 = action(C),
            timer:sleep(rand_between(1, 10)),
            online(C1, Until)
    end.

action(C) ->
    R = rand:uniform(100),
    if
        R =< 20 -> do_post(C);
        R =< 45 -> do_comment(C);
        R =< 75 -> do_vote(C);
        R =< 80 -> do_repost(C);
        R =< 90 -> do_dm(C);
        true    -> do_feed(C)
    end.

do_post(#c{subs = []} = C) ->
    C;
do_post(C) ->
    %% Popular (low-rank) subreddits get more posts
    {SubId, _Rank} = pick_weighted(C#c.subs),
    Text = text("post", C#c.uid),
    {_, C1} = timed(C, create_post,
        fun() -> reddit_engine:create_post(C#c.server, C#c.uid, SubId, Text) end),
    C1.

do_comment(#c{feed = []} = C) ->
    do_post(C);
do_comment(C) ->
    %% 30% of the time reply to own previous comment (nested), else top-level
    {PostId, Parent} =
        case {C#c.last_comment, rand:uniform(100) =< 30} of
            {{P, Cid}, true} -> {P, Cid};
            _ -> {maps:get(id, pick(C#c.feed)), none}
        end,
    Text = text("comment", C#c.uid),
    {R, C1} = timed(C, add_comment,
        fun() -> reddit_engine:add_comment(C#c.server, C#c.uid,
                                           PostId, Parent, Text) end),
    case R of
        {ok, NewId} -> C1#c{last_comment = {PostId, NewId}};
        _ -> C1
    end.

do_vote(#c{feed = []} = C) ->
    do_post(C);
do_vote(C) ->
    PostId = maps:get(id, pick(C#c.feed)),
    Type = case rand:uniform(100) =< 70 of
               true -> upvote;
               false -> downvote
           end,
    {_, C1} = timed(C, vote,
        fun() -> reddit_engine:vote(C#c.server, C#c.uid, Type, {post, PostId}) end),
    C1.

do_repost(#c{feed = []} = C) ->
    do_post(C);
do_repost(C) ->
    PostId = maps:get(id, pick(C#c.feed)),
    {_, C1} = timed(C, repost,
        fun() -> reddit_engine:repost(C#c.server, C#c.uid, PostId) end),
    C1.

do_dm(C) ->
    Other = element(rand:uniform(tuple_size(C#c.users)), C#c.users),
    Text = text("dm", C#c.uid),
    {_, C1} = timed(C, send_message,
        fun() -> reddit_engine:send_message(C#c.server, C#c.uid, Other, Text) end),
    C1.

do_feed(C) ->
    {R, C1} = timed(C, get_feed,
        fun() -> reddit_engine:get_feed(C#c.server, C#c.uid, 50) end),
    case R of
        {ok, F} -> C1#c{feed = F};
        _ -> C1
    end.

%% =====================================================
%% HELPERS
%% =====================================================

timed(C, Op, Fun) ->
    {Micros, Result} = timer:tc(Fun),
    Stats = maps:update_with(Op, fun(L) -> [Micros | L] end, [Micros], C#c.stats),
    {Result, C#c{stats = Stats}}.

text(Kind, Uid) ->
    iolist_to_binary(io_lib:format("~s by user ~p #~p",
        [Kind, Uid, erlang:unique_integer([positive])])).

now_ms() -> erlang:monotonic_time(millisecond).

rand_between(A, B) -> A + rand:uniform(B - A + 1) - 1.

pick(List) -> lists:nth(rand:uniform(length(List)), List).

%% Zipf-weighted choice among [{SubId, Rank}]
pick_weighted(Subs) ->
    Weighted = [{S, 1 / math:pow(K, ?ZIPF_S)} || {_Id, K} = S <- Subs],
    Total = lists:sum([W || {_, W} <- Weighted]),
    walk(Weighted, rand:uniform() * Total).

walk([{S, _}], _) -> S;
walk([{S, W} | Rest], R) ->
    case R =< W of
        true -> S;
        false -> walk(Rest, R - W)
    end.

%% =====================================================
%% REPORT
%% =====================================================

report(Results, ElapsedMs, SetupMs, NumUsers, NumSubs, Server) ->
    Merged = lists:foldl(
        fun({Stats, _}, Acc) ->
            maps:fold(
                fun(Op, L, A) ->
                    maps:update_with(Op, fun(X) -> L ++ X end, L, A)
                end, Acc, Stats)
        end, #{}, Results),
    Sessions = lists:sum([S || {_, S} <- Results]),
    Total = lists:sum([length(L) || L <- maps:values(Merged)]),

    io:format("~n=== Simulation report ===~n"),
    io:format("Users: ~p   Subreddits: ~p   Zipf s: ~p~n",
              [NumUsers, NumSubs, ?ZIPF_S]),
    io:format("Setup time: ~p ms   Run time: ~p ms~n", [SetupMs, ElapsedMs]),
    io:format("Connection sessions (connect/disconnect cycles): ~p~n", [Sessions]),
    io:format("Total requests: ~p   Throughput: ~.1f req/s~n~n",
              [Total, Total / (max(1, ElapsedMs) / 1000)]),

    io:format("~-14s ~8s ~10s ~10s ~10s ~10s ~10s~n",
              ["op", "count", "avg ms", "p50 ms", "p95 ms", "p99 ms", "max ms"]),
    lists:foreach(
        fun({Op, L}) ->
            Sorted = lists:sort(L),
            N = length(Sorted),
            Avg = lists:sum(Sorted) / N,
            io:format("~-14s ~8w ~10.2f ~10.2f ~10.2f ~10.2f ~10.2f~n",
                [atom_to_list(Op), N, Avg / 1000,
                 pct(Sorted, N, 0.50) / 1000,
                 pct(Sorted, N, 0.95) / 1000,
                 pct(Sorted, N, 0.99) / 1000,
                 lists:last(Sorted) / 1000])
        end, lists:sort(maps:to_list(Merged))),

    {ok, EngStats} = reddit_engine:stats(Server),
    io:format("~nEngine state: ~p~n", [EngStats]),
    ok.

pct(Sorted, N, P) ->
    lists:nth(max(1, min(N, ceil(N * P))), Sorted).

%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 1 -- the actor system.
%%%
%%% Two kinds of actor, and nothing else:
%%%
%%%   * one BOSS, registered locally under the name `boss'. It owns the
%%%     search space, hands out disjoint ranges of candidate numbers on
%%%     request, and is the only process that prints coins.
%%%   * many MINER actors. A miner asks for a range, grinds through it with
%%%     `project1:mine_range/5', reports any coins, and asks for the next
%%%     range. Miners hold no shared state and never talk to each other.
%%%
%%% Miners are location transparent: each one carries a `BossRef' in its
%%% own arguments rather than looking up the registered name `boss' in its
%%% local node. `BossRef' is the bare atom `boss' for a miner running
%%% beside the boss, and the tuple `{boss, BossNode}' for a miner running
%%% on a different machine. `BossRef ! Msg' behaves identically either way,
%%% so the exact same `miner_loop/1' code runs locally and remotely.
%%%
%%% Because the boss is the single source of ranges, ranges handed to
%%% different machines are disjoint by construction and no coin can be
%%% mined twice.
%%% @end
%%%-------------------------------------------------------------------
-module(actors).

-export([start/1, start/2,
         start_server/1, start_server/2,
         start_worker/1, start_worker/2,
         miner_loop/1,
         bench/0, bench/1]).

-define(BOSS, boss).

%% Work-unit size: how many candidate numbers a miner receives per request.
%% Chosen by measurement, not guesswork -- run `actors:bench()' to reproduce
%% the table in README.md. 10_000 was the fastest chunk size in every
%% benchmark pass, and it keeps a single work unit down to ~30 ms, which
%% both balances load across machines of different speeds and bounds how
%% much work is wasted when a worker disappears mid-chunk.
-define(DEFAULT_CHUNK, 10000).

%% How often the boss prints a live progress line to stderr.
-define(TICK_MS, 5000).

-record(boss, {
    k,                      % required number of leading zero hex digits
    prefix,                 % gatorlink id prefixed to every candidate
    next = 0,               % next unassigned candidate number
    chunk,                  % work-unit size
    limit = infinity,       % stop assigning past this many candidates (bench)
    coins = 0,              % coins found so far
    hashes = 0,             % hashes completed (reported by miners)
    best_zeros = 0,         % most leading zeros seen
    best_input = none,
    best_hash = none,
    live = 0,               % local miners still alive (for clean shutdown)
    miners = [],            % pids of the local miners, so we can stop them
    nodes = [],             % remote worker nodes that have joined
    by_node = #{},          % node() => hashes contributed, for the summary
    quiet = false,          % suppress coin printing (bench mode)
    file = undefined,       % coins.txt handle
    rt0, wc0                % runtime / wall_clock baselines
}).

%%====================================================================
%% Entry points
%%====================================================================

%% @doc Backwards-compatible entry point: mine for K leading zeros forever,
%% using one miner actor per scheduler.
start(K) -> start_server(K, #{}).

%% @doc Mine for K leading zeros for `Seconds' seconds, then print a summary.
start(K, Seconds) -> start_server(K, #{duration => Seconds * 1000}).

start_server(K) -> start_server(K, #{}).

%% @doc Start the boss and its local miners.
%%
%% Options: `chunk', `miners', `duration' (ms or `infinity'), `limit',
%% `prefix', `quiet'. Returns a stats map.
start_server(K, Opts) ->
    Chunk    = maps:get(chunk, Opts, ?DEFAULT_CHUNK),
    NMiners  = maps:get(miners, Opts, erlang:system_info(schedulers_online)),
    Duration = maps:get(duration, Opts, infinity),
    Limit    = maps:get(limit, Opts, infinity),
    Prefix   = maps:get(prefix, Opts, project1:gator_id()),
    Quiet    = maps:get(quiet, Opts, false),
    %% Where in the search space to begin. Runs always start at 0 by default,
    %% which keeps results reproducible, but that also means a second run
    %% re-covers ground the first run already searched. To push further into
    %% the space looking for more leading zeros, resume past the last run.
    Start    = maps:get(start, Opts, 0),

    try unregister(?BOSS) catch _:_ -> ok end,
    register(?BOSS, self()),

    File = case Quiet of
               true  -> undefined;
               false -> case file:open("coins.txt", [append]) of
                            {ok, F}   -> F;
                            {error, _} -> undefined
                        end
           end,

    Quiet orelse
        io:format(standard_error,
                  "Boss ~p starting: k=~p, ~p miner actors, chunk=~p, "
                  "start=~p, prefix=~s~n",
                  [node(), K, NMiners, Chunk, Start, Prefix]),

    %% Spawn the local miner actors. They address the boss by the bare
    %% registered name because they share its node.
    MinerPids = [element(1, spawn_monitor(fun() -> miner_loop(?BOSS) end))
                 || _ <- lists:seq(1, NMiners)],

    {RT0, _} = statistics(runtime),
    {WC0, _} = statistics(wall_clock),

    case Duration of
        infinity -> ok;
        Ms       -> erlang:send_after(Ms, self(), finish)
    end,
    Quiet orelse erlang:send_after(?TICK_MS, self(), tick),

    State = #boss{k = K, prefix = Prefix, chunk = Chunk, limit = Limit,
                  next = Start,
                  live = NMiners, miners = MinerPids, quiet = Quiet, file = File,
                  rt0 = RT0, wc0 = WC0},
    boss_loop(State).

%%====================================================================
%% Boss actor
%%====================================================================

boss_loop(S = #boss{next = Next, limit = Limit}) when Limit =/= infinity,
                                                      Next >= Limit ->
    %% Search space exhausted (bench mode): retire miners as they report in,
    %% and finish once every one of them has stopped.
    receive
        {request_work, Pid} ->
            Pid ! stop,
            boss_loop(S);
        {'DOWN', _Ref, process, _Pid, _Why} ->
            case S#boss.live - 1 of
                0    -> finish(S#boss{live = 0});
                Live -> boss_loop(S#boss{live = Live})
            end;
        finish ->
            finish(S);
        Other ->
            boss_loop(handle(Other, S))
    end;
boss_loop(S) ->
    receive
        {request_work, Pid} ->
            #boss{next = Next, chunk = Chunk, k = K, prefix = Prefix} = S,
            Pid ! {work, Next, Next + Chunk - 1, K, Prefix},
            boss_loop(S#boss{next = Next + Chunk});
        finish ->
            finish(S);
        Other ->
            boss_loop(handle(Other, S))
    end.

%% Messages whose handling does not depend on whether work remains.
handle({coin_found, Input, Hash, Zeros}, S = #boss{quiet = Quiet}) ->
    Quiet orelse io:format("~s\t~s~n", [Input, Hash]),
    case S#boss.file of
        undefined -> ok;
        F -> io:format(F, "~s\t~s~n", [Input, Hash])
    end,
    S1 = S#boss{coins = S#boss.coins + 1},
    case Zeros > S#boss.best_zeros of
        true  -> S1#boss{best_zeros = Zeros, best_input = Input, best_hash = Hash};
        false -> S1
    end;
handle({chunk_done, Pid, N}, S) ->
    %% node(Pid) tells us which machine did the work, so the summary can show
    %% each machine's contribution.
    Node = node(Pid),
    Acc = maps:get(Node, S#boss.by_node, 0),
    S#boss{hashes = S#boss.hashes + N,
           by_node = maps:put(Node, Acc + N, S#boss.by_node)};
handle({worker_joined, Node, NMiners}, S) ->
    io:format(standard_error, "Worker joined: ~p (~p miner actors)~n",
              [Node, NMiners]),
    S#boss{nodes = lists:usort([Node | S#boss.nodes])};
handle(tick, S) ->
    print_progress(S),
    erlang:send_after(?TICK_MS, self(), tick),
    S;
handle({'DOWN', _Ref, process, _Pid, _Why}, S) ->
    S#boss{live = max(0, S#boss.live - 1)};
handle(_Unknown, S) ->
    S.

%%====================================================================
%% Shutdown / statistics
%%====================================================================

finish(S) ->
    Stats = stats(S),
    %% Stop the local miners BEFORE giving up the registered name. Otherwise
    %% a miner mid-chunk sends to a name that no longer exists, which raises
    %% badarg and fills the console with crash reports just as the run ends.
    [exit(Pid, kill) || Pid <- S#boss.miners],
    try unregister(?BOSS) catch _:_ -> ok end,
    S#boss.quiet orelse print_summary(Stats),
    case S#boss.file of
        undefined -> ok;
        F -> file:close(F)
    end,
    Stats.

stats(#boss{rt0 = RT0, wc0 = WC0} = S) ->
    {RT1, _} = statistics(runtime),
    {WC1, _} = statistics(wall_clock),
    Cpu  = RT1 - RT0,
    Wall = max(1, WC1 - WC0),
    #{coins      => S#boss.coins,
      hashes     => S#boss.hashes,
      wall_ms    => Wall,
      cpu_ms     => Cpu,
      ratio      => Cpu / Wall,
      rate       => S#boss.hashes * 1000 / Wall,
      best_zeros => S#boss.best_zeros,
      best_input => S#boss.best_input,
      best_hash  => S#boss.best_hash,
      nodes      => S#boss.nodes,
      by_node    => S#boss.by_node}.

print_progress(S) ->
    #{hashes := H, rate := R, ratio := Ratio, wall_ms := W} = stats(S),
    io:format(standard_error,
              "  [~ps] coins=~p  hashes=~s  rate=~s/s  CPU/REAL=~.2f~n",
              [W div 1000, S#boss.coins, human(H), human(round(R)), Ratio]).

print_summary(Stats) ->
    #{coins := Coins, hashes := Hashes, wall_ms := Wall, cpu_ms := Cpu,
      ratio := Ratio, rate := Rate, best_zeros := BZ, best_input := BI,
      best_hash := BH, nodes := Nodes, by_node := ByNode} = Stats,
    io:format(standard_error, "~n===== Mining summary =====~n", []),
    io:format(standard_error, "Machines:      ~p (this one + ~p worker node(s))~n",
              [1 + length(Nodes), length(Nodes)]),
    io:format(standard_error, "Coins found:   ~p~n", [Coins]),
    io:format(standard_error, "Hashes tried:  ~p~n", [Hashes]),
    io:format(standard_error, "Hash rate:     ~s hashes/sec~n", [human(round(Rate))]),
    io:format(standard_error, "REAL time:     ~.3f s~n", [Wall / 1000]),
    io:format(standard_error, "CPU time:      ~.3f s~n", [Cpu / 1000]),
    io:format(standard_error, "CPU / REAL:    ~.2f   (cores effectively used on"
                              " THIS node)~n", [Ratio]),
    case maps:size(ByNode) > 1 of
        false -> ok;
        true ->
            io:format(standard_error, "Per machine:~n", []),
            [io:format(standard_error, "  ~-34s ~10s hashes (~.1f%)~n",
                       [atom_to_list(N), human(H), 100 * H / max(1, Hashes)])
             || {N, H} <- lists:sort(maps:to_list(ByNode))]
    end,
    case BI of
        none -> ok;
        _    -> io:format(standard_error, "Best coin:     ~s  (~p leading zeros)~n"
                                          "               ~s~n", [BI, BZ, BH])
    end,
    io:format(standard_error, "==========================~n", []).

human(N) when N >= 1000000000 -> io_lib:format("~.2fG", [N / 1000000000]);
human(N) when N >= 1000000    -> io_lib:format("~.2fM", [N / 1000000]);
human(N) when N >= 1000       -> io_lib:format("~.2fK", [N / 1000]);
human(N)                      -> io_lib:format("~p", [N]).

%%====================================================================
%% Miner actor -- identical code locally and remotely
%%====================================================================

miner_loop(BossRef) ->
    case send_boss(BossRef, {request_work, self()}) of
        gone -> ok;
        ok   -> await_work(BossRef)
    end.

await_work(BossRef) ->
    receive
        {work, Start, End, K, Prefix} ->
            Report = fun(Input, Hash, Zeros) ->
                             send_boss(BossRef, {coin_found, Input, Hash, Zeros})
                     end,
            N = project1:mine_range(Prefix, Start, End, K, Report),
            case send_boss(BossRef, {chunk_done, self(), N}) of
                gone -> ok;
                ok   -> miner_loop(BossRef)
            end;
        stop ->
            ok
    after 60000 ->
        %% Safety net: never wedge forever waiting on a reply. Re-asking is
        %% harmless -- the boss simply hands out the next range.
        miner_loop(BossRef)
    end.

%% Sending to a registered name that no longer exists raises badarg. That is
%% a normal race at the end of a run (the boss finishes while miners are
%% still mid-chunk), so treat it as "the boss is gone, stop quietly" rather
%% than letting the miner crash.
send_boss(BossRef, Msg) ->
    try
        BossRef ! Msg,
        ok
    catch
        _:_ -> gone
    end.

%%====================================================================
%% Worker node
%%====================================================================

start_worker(BossNode) ->
    start_worker(BossNode, erlang:system_info(schedulers_online)).

%% @doc Join the boss on `BossNode' and mine for it. Prints nothing except
%% diagnostics on stderr -- all coins are printed by the server, as the
%% assignment requires.
start_worker(BossNode, NMiners) ->
    case net_kernel:connect_node(BossNode) of
        true ->
            monitor_node(BossNode, true),
            BossRef = {?BOSS, BossNode},
            BossRef ! {worker_joined, node(), NMiners},
            Pids = [element(1, spawn_monitor(fun() -> miner_loop(BossRef) end))
                    || _ <- lists:seq(1, NMiners)],
            io:format(standard_error,
                      "Connected to ~p. Mining with ~p miner actors.~n"
                      "Coins are printed by the server, not here. Ctrl+C to stop.~n",
                      [BossNode, NMiners]),
            worker_wait(BossNode, Pids);
        false ->
            io:format(standard_error,
                      "ERROR: cannot reach ~p.~n"
                      "  * is the server running?~n"
                      "  * same LAN, and firewall open on TCP 4369 + 9100-9110?~n"
                      "  * same cookie on both machines?~n", [BossNode]),
            {error, {cannot_connect, BossNode}}
    end.

worker_wait(BossNode, Pids) ->
    receive
        {nodedown, BossNode} ->
            io:format(standard_error, "Server ~p went down. Stopping miners.~n",
                      [BossNode]),
            [exit(P, kill) || P <- Pids],
            ok;
        _Other ->
            worker_wait(BossNode, Pids)
    end.

%%====================================================================
%% Work-unit size benchmark (used to justify ?DEFAULT_CHUNK in the README)
%%====================================================================

bench() -> bench([100, 1000, 10000, 100000, 1000000]).

%% @doc Grind a fixed number of candidates with each chunk size and report
%% throughput. K is set high enough that no coin is ever found, so the
%% measurement reflects only hashing plus boss/miner coordination.
bench(Chunks) ->
    Total = 20000000,
    io:format(standard_error,
              "~nWork-unit benchmark: ~p candidates per run, ~p miner actors~n",
              [Total, erlang:system_info(schedulers_online)]),
    io:format(standard_error, "~-12s ~-14s ~-12s ~-12s ~-10s~n",
              ["Chunk", "Hashes/sec", "REAL (s)", "CPU (s)", "CPU/REAL"]),
    Rows = [bench_one(C, Total) || C <- Chunks],
    io:format(standard_error, "~n", []),
    Rows.

bench_one(Chunk, Total) ->
    Stats = start_server(12, #{chunk => Chunk, limit => Total, quiet => true}),
    #{rate := Rate, wall_ms := Wall, cpu_ms := Cpu, ratio := Ratio} = Stats,
    io:format(standard_error, "~-12s ~-14s ~-12.3f ~-12.3f ~-10.2f~n",
              [integer_to_list(Chunk), human(round(Rate)),
               Wall / 1000, Cpu / 1000, Ratio]),
    {Chunk, Stats}.

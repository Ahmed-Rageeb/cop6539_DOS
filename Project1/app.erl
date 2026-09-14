%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 1 -- command line entry point.
%%%
%%%   mine 4                 start a server mining coins with 4 leading zeros
%%%   mine 4 30              ... and stop after 30 seconds, printing a summary
%%%   mine 4 30 192.168.1.7  ... and advertise this exact IP to workers
%%%   mine 10.22.13.155      join the server at that address as a worker
%%%
%%% A numeric argument means "be the server"; anything containing a dot or
%%% a colon means "be a worker and go find the server at this address".
%%%
%%% Both modes bring up Erlang distribution themselves so the user never has
%%% to deal with -name/-setcookie. The distribution port range is pinned to
%%% 9100-9110 (instead of Erlang's default random high port) so that a single
%%% firewall rule is enough to let workers in.
%%% @end
%%%-------------------------------------------------------------------
-module(app).

%% main/0 as well as main/1: `erl -run app main' with no trailing arguments
%% calls app:main() with arity 0, not app:main([]).
-export([main/0, main/1, start/0]).

-define(COOKIE, 'cop6539').
-define(DIST_PORT_MIN, 9100).
-define(DIST_PORT_MAX, 9110).

%% Retained so the original `app:start/0' still exists.
start() -> usage().

main() -> usage().

main([]) ->
    usage();
main([Arg | Rest]) ->
    case is_number_arg(Arg) of
        true  -> server_mode(list_to_integer(Arg), Rest);
        false -> worker_mode(Arg, Rest)
    end.

is_number_arg(S) ->
    S =/= "" andalso lists:all(fun(C) -> C >= $0 andalso C =< $9 end, S).

usage() ->
    io:format(standard_error,
              "COP6539 Project 1 -- distributed bitcoin miner~n~n"
              "  mine <K> [Seconds] [BindIP]   run as the server, mining K leading zeros~n"
              "  mine <ServerIP>    [Miners]   run as a worker for the server at ServerIP~n~n"
              "Examples:~n"
              "  mine 4~n"
              "  mine 4 30~n"
              "  mine 10.22.13.155~n", []),
    halt(1).

%%====================================================================
%% Server
%%====================================================================

server_mode(K, Rest) ->
    Duration = case Rest of
                   [D | _] -> case is_number_arg(D) of
                                  true  -> list_to_integer(D) * 1000;
                                  false -> infinity
                              end;
                   [] -> infinity
               end,
    BindIP = case Rest of
                 [_, Ip | _] -> Ip;
                 _           -> local_ipv4()
             end,

    ok = start_distribution("boss@" ++ BindIP),

    io:format(standard_error,
              "~n================================================~n"
              " SERVER READY -- node ~p~n"
              " Workers should be started with:   mine ~s~n"
              "================================================~n",
              [node(), BindIP]),
    case Duration of
        infinity -> io:format(standard_error, "Mining until Ctrl+C.~n~n", []);
        Ms -> io:format(standard_error, "Mining for ~p seconds.~n~n", [Ms div 1000])
    end,

    actors:start_server(K, #{duration => Duration}),
    halt(0).

%%====================================================================
%% Worker
%%====================================================================

worker_mode(ServerIP, Rest) ->
    NMiners = case Rest of
                  [M | _] -> case is_number_arg(M) of
                                 true  -> list_to_integer(M);
                                 false -> erlang:system_info(schedulers_online)
                             end;
                  [] -> erlang:system_info(schedulers_online)
              end,

    MyIP = local_ipv4(),
    Suffix = integer_to_list(erlang:phash2({node(), erlang:monotonic_time()}, 100000)),
    ok = start_distribution("worker" ++ Suffix ++ "@" ++ MyIP),

    BossNode = list_to_atom("boss@" ++ ServerIP),
    io:format(standard_error, "Worker ~p connecting to ~p ...~n", [node(), BossNode]),

    case connect_retry(BossNode, 10) of
        true ->
            actors:start_worker(BossNode, NMiners),
            halt(0);
        false ->
            io:format(standard_error,
                      "~nERROR: could not reach ~p after 10 attempts.~n"
                      "Check that the server is running, that both machines are on~n"
                      "the same network, and that TCP 4369 and 9100-9110 are open.~n",
                      [BossNode]),
            halt(1)
    end.

connect_retry(Node, Max) -> connect_retry(Node, 1, Max).

connect_retry(_Node, Attempt, Max) when Attempt > Max -> false;
connect_retry(Node, Attempt, Max) ->
    case net_kernel:connect_node(Node) of
        true -> true;
        _ ->
            io:format(standard_error, "  attempt ~p/~p: no answer, retrying ...~n",
                      [Attempt, Max]),
            timer:sleep(2000),
            connect_retry(Node, Attempt + 1, Max)
    end.

%%====================================================================
%% Distribution bootstrap
%%====================================================================

start_distribution(NameStr) ->
    application:set_env(kernel, inet_dist_listen_min, ?DIST_PORT_MIN),
    application:set_env(kernel, inet_dist_listen_max, ?DIST_PORT_MAX),
    %% Cap how long a single connection attempt may block. The default lets
    %% connect_node/1 sit on an unroutable address for ~21 seconds, which
    %% makes a retry loop useless and a typo in the server IP look like a
    %% hang rather than an error.
    application:set_env(kernel, net_setuptime, 3),
    ensure_epmd(),
    start_distribution(NameStr, 3).

start_distribution(NameStr, Tries) ->
    case net_kernel:start([list_to_atom(NameStr), longnames]) of
        {ok, _} ->
            erlang:set_cookie(node(), ?COOKIE), ok;
        {error, {already_started, _}} ->
            erlang:set_cookie(node(), ?COOKIE), ok;
        {error, _Reason} when Tries > 1 ->
            ensure_epmd(),
            timer:sleep(500),
            start_distribution(NameStr, Tries - 1);
        {error, Reason} ->
            io:format(standard_error,
                      "ERROR: could not start Erlang distribution as ~s:~n  ~p~n"
                      "epmd (the Erlang port mapper) could not be started.~n",
                      [NameStr, Reason]),
            halt(1)
    end.

%% @doc Make sure epmd, the Erlang port mapper daemon, is running.
%%
%% epmd is how a worker discovers which TCP port the "boss" node listens on,
%% so distribution cannot start without it. The VM launches epmd by itself
%% only when a node name is supplied on the command line (-name/-sname);
%% this project brings distribution up programmatically, so nothing has
%% started it for us.
%%
%% The documented way to start it by hand, `epmd -daemon', does not work on
%% Windows: it returns success and then exits without staying resident.
%% What does work is briefly running a *named* VM, which makes the runtime
%% start epmd for us -- and epmd outlives that short-lived node. So that is
%% what we do, and only when port 4369 is not already answering.
ensure_epmd() ->
    case epmd_running() of
        true  -> ok;
        false -> boot_epmd(), wait_for_epmd(20)
    end.

epmd_running() ->
    case gen_tcp:connect({127, 0, 0, 1}, 4369, [], 500) of
        {ok, Sock} -> gen_tcp:close(Sock), true;
        _          -> false
    end.

boot_epmd() ->
    Erl = case os:type() of
              {win32, _} -> filename:join([code:root_dir(), "bin", "erl.exe"]);
              _          -> filename:join([code:root_dir(), "bin", "erl"])
          end,
    %% spawn_executable rather than os:cmd/1: the install path contains
    %% spaces and cmd.exe mangles nested quoting.
    try
        Port = open_port({spawn_executable, Erl},
                         [{args, ["-name", "epmdboot@127.0.0.1",
                                  "-setcookie", "epmdboot",
                                  "-noshell", "-eval", "halt()."]},
                          exit_status, hide]),
        receive {Port, {exit_status, _}} -> ok after 10000 -> ok end
    catch
        _:_ -> ok
    end.

wait_for_epmd(0) -> ok;
wait_for_epmd(N) ->
    case epmd_running() of
        true  -> ok;
        false -> timer:sleep(250), wait_for_epmd(N - 1)
    end.

%% @doc Best guess at this machine's LAN IPv4 address.
%%
%% Loopback is skipped. Machines with WSL / VirtualBox / Hyper-V adapters
%% expose several addresses and the guess can land on a virtual one, which
%% is why the server prints the address it chose and accepts an override as
%% its third argument.
local_ipv4() ->
    {ok, Ifs} = inet:getifaddrs(),
    Addrs = [Addr || {_Name, Opts} <- Ifs,
                     {addr, Addr = {A, _, _, _}} <- Opts,
                     A =/= 127,
                     tuple_size(Addr) =:= 4],
    case prefer_private(Addrs) of
        [] -> "127.0.0.1";
        [Addr | _] -> inet:ntoa(Addr)
    end.

%% Prefer ordinary private LAN ranges over the 172.16-31 block that Docker
%% and WSL typically occupy.
prefer_private(Addrs) ->
    {Good, Rest} = lists:partition(
                     fun({192, 168, _, _}) -> true;
                        ({10, _, _, _})    -> true;
                        (_)                -> false
                     end, Addrs),
    Good ++ Rest.

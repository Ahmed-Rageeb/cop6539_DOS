-module(pastry_init).
-export([pastryInit/2]).

pastryInit(Credentials, Application) ->
    NodeId = pastry_util:hash(maps:get(name, Credentials)),
    Pid = pastry_node:start(#{id => NodeId,
                       app => Application,
                       bootstrap => maps:get(bootstrap, Credentials, none),
                       notify => maps:get(notify, Credentials),
                       opts => maps:get(opts, Credentials, #{})}),
    {NodeId, Pid}.

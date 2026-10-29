```
Project3/
├── project3.erl       # Command line: project3 numNodes numRequests [options]
├── main.erl           # Entry point: builds the network, inserts objects, runs lookups, prints avg hops
├── pastry_init.erl    # pastryInit(Credentials, Application): creates a node and starts its join
├── pastry_node.erl    # Actor loop for one Pastry node (join protocol + application messages)
├── route.erl          # route(Msg, Key): leaf set, routing table, and rare-case routing
├── deliver.erl        # deliver(Msg, Key): application delivery (insert / lookup / join)
├── forward.erl        # forward(Msg, Key, NextId): hook + send to the next node
├── new_leafs.erl      # newLeafs(LeafSet): leaf set update and application notification
├── pastry_util.erl    # 128-bit ID helpers: hash, digits, shared prefix, circular distance
├── rtable.erl         # Routing table: add and lookup of {Row, Col} entries
├── node_state.erl     # State helpers: learn nodes, known nodes, join snapshot
├── failure.erl        # Failure models for the bonus: node death, link loss
├── experiments.erl    # Experiment sweeps -> CSV
└── report.erl         # CSV -> Report.pdf and Report-bonus.pdf
```

Full documentation is in [`Project3/README.md`](Project3/README.md).

## Build and run

```
cd Project3
build.bat
project3.bat <numNodes> <numRequests>
```

Example: `project3.bat 100 5`

On Mac or Linux: `sh project3 100 5` (from inside Project3, builds itself the first time).

Or by hand. Make sure to compile every module. `forward.erl` calls `failure.erl`
on every lookup, so if you leave it out it compiles fine but crashes when run:

```
erlc project3.erl main.erl pastry_init.erl pastry_node.erl route.erl deliver.erl forward.erl new_leafs.erl pastry_util.erl rtable.erl node_state.erl failure.erl
erl -noshell -run project3 main <numNodes> <numRequests> -s init stop
```

`erl -noshell -run main main 100 5 -s init stop` still works too.

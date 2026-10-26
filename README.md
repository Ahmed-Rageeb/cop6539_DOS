```
project3/
├── main.erl           # Entry point: builds the network, inserts objects, runs lookups, prints avg hops
├── pastry_init.erl    # pastryInit(Credentials, Application): creates a node and starts its join
├── pastry_node.erl    # Actor loop for one Pastry node (join protocol + application messages)
├── route.erl          # route(Msg, Key): leaf set, routing table, and rare-case routing
├── deliver.erl        # deliver(Msg, Key): application delivery (insert / lookup / join)
├── forward.erl        # forward(Msg, Key, NextId): hook + send to the next node
├── new_leafs.erl      # newLeafs(LeafSet): leaf set update and application notification
├── pastry_util.erl    # 128-bit ID helpers: hash, digits, shared prefix, circular distance
├── rtable.erl         # Routing table: add and lookup of {Row, Col} entries
└── node_state.erl     # State helpers: learn nodes, known nodes, join snapshot
```

## Build and run

```
erlc main.erl pastry_init.erl pastry_node.erl route.erl deliver.erl forward.erl new_leafs.erl pastry_util.erl rtable.erl node_state.erl
erl -noshell -run main main <numNodes> <numRequests> -s init stop
```

Example: `erl -noshell -run main main 100 5 -s init stop`

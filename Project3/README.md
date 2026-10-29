# COP6539 Project 3: Pastry

**Team:** Ahmed Rageeb Ahsan, Saiful Islam

This is an implementation of Pastry (Rowstron and Druschel) in Erlang using the
actor model. Each peer is one actor, and the actors only talk by sending
messages. On top of Pastry we built the simple application from the assignment,
an object store that maps a key (a 128-bit id, same as the node ids) to a string.

## How to run

```
build.bat
project3.bat <numNodes> <numRequests>
```

For example:

```
project3.bat 1000 10
```

Each peer makes `numRequests` lookups for random stored objects, one per second.
When all peers are done, the program prints the average number of hops and exits:

```
Nodes: 1000
Requests per node: 10
Requests completed: 10000/10000 (objects found: 10000)
Average hops: 2.4841
(log16(N) = 2.4914)
```

In PowerShell you need `.\` in front of the scripts, for example `.\build.bat`.
From the Erlang shell, `main:start(1000, 10)` does the same thing.

## What is working

Everything in the assignment, and the bonus.

- **Join** (section 2.4 of the paper). A new node asks a node it knows to route a
  `join` message with the new node's id as the key. Every node on the way sends
  its state to the new node, and the last one is the node closest to the new id.
  The new node builds its leaf set and routing table from these and then tells
  all the nodes it knows about itself.
- **Routing** (Table 1 in the paper). If the key is in the leaf set range we send
  to the closest leaf. Otherwise we use the routing table entry that shares one
  more digit with the key. If that entry is empty we use the rare case: any known
  node with at least as long a shared prefix that is closer to the key.
- **The API from section 2.3**: `pastryInit`, `route`, and the callbacks
  `deliver`, `forward` and `newLeafs`, each in its own module.
- **The object store**, with `insert` and `lookup` by 128-bit key.
- **One request per second per peer**, and the program exits after every peer
  has made all its requests.

We use the same parameters as the paper: b = 4 (hex digits), 128-bit ids and a
leaf set of size 16.

To check that the routing is correct, we did more than check that lookups find
their objects (that only shows inserts and lookups go to the same place). For a
set of test keys we found the closest node by brute force over all the node ids,
and every lookup ended at that node, for every network size we tried.

## Largest network

The largest network we ran was **100,000 nodes**. All lookups found their
object, with an average of **3.96 hops** (log16 N = 4.15).

| Nodes | Average hops | log16 N |
|---:|---:|---:|
| 10 | 0.90 | 0.83 |
| 100 | 1.66 | 1.66 |
| 1,000 | 2.48 | 2.49 |
| 10,000 | 3.21 | 3.32 |
| 100,000 | 3.96 | 4.15 |

Report.pdf has the results for all 13 sizes from 10 to 100,000 nodes. Up to
5,000 nodes each result is the average of three runs. In total 413,280 out of
413,280 lookups found their object.

The number of hops grows with log N, and from 100 nodes up it is at or a little
below log16 N. This is expected, since log16 N assumes we fix one hex digit per
hop, but the leaf set lets us do the last few digits in one hop. The paper
reports the same thing.

What limited us was the time to join the nodes one at a time, not memory.
Building 100,000 nodes took about four minutes on an 8 GB laptop.

The first version could only handle about 5,000 nodes. Two changes fixed this:

- Every peer was sent the whole list of keys. Erlang copies messages, so this
  used memory proportional to N squared (785 MB extra at 4,000 nodes), and
  10,000 nodes ran out of memory. The keys are `hash({object, K})` for K from 1
  to N, so now a peer only gets N and computes the key itself.
- Idle peers never freed their memory. Handling join messages grows an actor's
  heap, and an actor waiting in `receive` never garbage collects. Now a peer
  hibernates after two seconds with no messages, which brought memory from
  79 KB to 9 KB per node.

## Bonus: failure models

We implemented the three failures from the assignment, each controlled by one
parameter, and the recovery methods from section 2.5 of the paper. The details
and results are in **Report-bonus.pdf**.

```
project3.bat 1000 3 kill=0.2                  20% of nodes die
project3.bat 1000 3 drop=0.2                  each message lost with p = 0.2
project3.bat 1000 3 links=0.2                 20% of links dead for good
project3.bat 1000 3 kill=0.2 resilient        same, with all defences on
```

| Option | Meaning |
|---|---|
| `kill=p` | a fraction *p* of nodes die after the network is built |
| `drop=q` | temporary connection failure: each message is lost with probability *q* |
| `links=r` | permanent connection failure: a fraction *r* of node pairs can never talk |
| `repair=1` | detect failures and repair leaf sets and routing tables |
| `replicas=4` | store each object on the 4 nodes closest to its key, like PAST |
| `attempts=3` | retry a failed lookup, up to 3 attempts in total |
| `retry=rand` | route used for retries: `det` (same route), `rand` (default) or `hybrid` |
| `resilient` | same as `repair=1 replicas=4 attempts=3` |

All of these are off by default, so the normal program works exactly as the
assignment asks.

### Results

At 1,000 nodes with 20% failure (average of three runs):

| Failure | No defence | Best defence | Which defence |
|---|---:|---:|---|
| 20% of nodes die | 59.8% | **99.8%** | repair, replication and retry |
| 20% of messages lost | 58.0% | **91.7%** | retry on the same route |
| 20% of links dead for good | 58.2% | **77.7%** | retry on a *random* route |

- Each failure needed its own defence. With repair only, the lookups we lost
  matched the fraction of nodes killed, at every failure level. Those objects
  only had one copy and it was on a dead node. Replication is what saves them.
- With all defences on, node death gets close to the best possible result. The
  success rate matches 1 - p^4, the chance that at least one of the four copies
  survives, so the remaining failures are objects that could not be saved.
- The two connection failures need opposite retry strategies. For temporary
  failures, retrying on the same route is best. For permanent ones it doesn't
  help at all (same result as no retry), because Pastry sends a key the same way
  every time and hits the same dead link. Only a random route gets around it.
- A node can't tell which kind of failure it hit, so the default is the random
  route, which has the best worst case. We also tried a hybrid (same route once,
  then random), and it ended up between the other two at all eight failure
  levels we tested.

## Files

| File | What it does |
|---|---|
| `project3.erl` | command line: `project3 numNodes numRequests [options]` |
| `main.erl` | coordinator: builds the network, stores objects, collects results |
| `pastry_init.erl` | `pastryInit(Credentials, Application)`, creates a node and starts its join |
| `pastry_node.erl` | the actor for one peer: join, requests, failure detection and repair |
| `route.erl` | `route(Msg, Key)`: leaf set, routing table, rare case, random retry routes |
| `deliver.erl` | `deliver(Msg, Key)`: insert, lookup, join, replication |
| `forward.erl` | `forward(Msg, Key, NextId)`: application hook, then send |
| `new_leafs.erl` | `newLeafs(LeafSet)`: leaf set updates |
| `node_state.erl` | learning about nodes, known nodes, join snapshots |
| `rtable.erl` | the routing table |
| `pastry_util.erl` | 128-bit ids: hashing, digits, shared prefix, distance |
| `failure.erl` | the failure models (bonus) |
| `experiments.erl`, `report.erl` | run the experiments and make the reports |
| `build.bat`, `project3.bat`, `run-experiments.sh`, `report.bat` | scripts |

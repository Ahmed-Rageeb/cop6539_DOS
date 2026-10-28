# COP6539 Project 3 — Pastry

**Team:** Ahmed Rageeb Ahsan, Saiful Islam

An implementation of the Pastry peer-to-peer overlay (Rowstron & Druschel) in
Erlang, using the actor model throughout: **one actor per peer**, and nothing
but asynchronous message passing between them. On top of it runs the simple
application the assignment asks for — an object store that associates a key
(drawn from the same 128-bit id space as the nodes) with a string.

---

## Running

```
build.bat
project3.bat <numNodes> <numRequests>
```

```
project3.bat 1000 10
```

Every peer makes `numRequests` lookups, one per second, for randomly chosen
stored objects. When all of them are done the program prints the average
number of hops a lookup travelled to be delivered, and exits:

```
Nodes: 1000
Requests per node: 10
Requests completed: 10000/10000 (objects found: 10000)
Average hops: 2.4841
(log16(N) = 2.4914)
```

In PowerShell the scripts need a `.\` prefix: `.\build.bat`.

From the Erlang shell, `main:start(1000, 10)` does the same.

---

## What is working

Everything in the assignment, plus the bonus.

- **Network join**, as in section 2.4 of the paper. A new node asks a known
  node to route a `join` message keyed by its own id. Every node on the path
  sends the newcomer its state; the last one is the node numerically closest
  to it. The newcomer builds its leaf set and routing table from those, then
  announces itself to every node it now knows.
- **Routing**, as in Table 1 of the paper: leaf set if the key is within its
  range, otherwise the routing table entry sharing one more digit with the key,
  otherwise the rare case — any known node that shares at least as long a
  prefix and is numerically closer.
- **The paper's API** (section 2.3): `pastryInit`, `route`, and the application
  callbacks `deliver`, `forward` and `newLeafs`, each in its own module.
- **The object store**, keyed by 128-bit ids, with `insert` and `lookup`.
- **One request per second per peer**, exiting once every peer has made its
  requests.

Parameters are those the paper uses: b = 4 (hex digits), 128-bit ids, and a
leaf set of |L| = 16.

### How we know routing is correct

Every lookup in every run finds its object — but on its own that only proves
that inserts and lookups *agree* with each other. So routing was also checked
against an independent oracle: for each probe key, the true numerically
closest node was computed by brute force over every node id, not taken from
any node's tables. **Every probe reached it**, at every network size tested.

---

## Largest network

**100,000 nodes** — every lookup found, averaging **3.96 hops** against
log₁₆N = 4.15.

| Nodes | Average hops | log₁₆N |
|---:|---:|---:|
| 10 | 0.90 | 0.83 |
| 100 | 1.66 | 1.66 |
| 1,000 | 2.48 | 2.49 |
| 10,000 | 3.21 | 3.32 |
| 100,000 | 3.96 | 4.15 |

Full measurements for all 13 sizes, 10 to 100,000, are in **Report.pdf**; up
to 5,000 nodes each figure is the mean of three runs. Across all of them,
413,280 of 413,280 lookups found their object.

Hops grow as log N, as Pastry promises, and from 100 nodes upward run at or
slightly *under* log₁₆N at every size. That is expected: log₁₆N is the cost of
resolving a key one hex digit at a time, but the leaf set resolves the last
few digits in a single hop. The paper reports the same effect.

The ceiling is the time taken to join peers one at a time, not memory: 100,000
nodes took about four minutes to build on an 8 GB laptop.

### What it took to get there

The first version handled about 5,000 nodes. Two changes raised that twenty-fold:

- **Each peer was sent the full list of keys.** Erlang copies terms on send, so
  N peers × N keys is O(N²) memory — measured at +785 MB for 4,000 nodes, and
  10,000 nodes ran out of memory. Keys are `hash({object, K})` for K in 1..N,
  so a peer now needs only the integer N and computes any key itself.
- **Idle peers never freed memory.** Processing join traffic inflates an
  actor's heap, and an actor blocked in `receive` never collects its own
  garbage. Peers now hibernate after two seconds of silence, which compacts
  them. Measured: 79 KB per node down to 9 KB.

---

## Bonus: failure models

All three failures the assignment names are implemented, each driven by one
parameter, along with the recovery mechanisms from section 2.5 of the paper.
The full experiments and findings are in **Report-bonus.pdf**.

```
project3.bat 1000 3 kill=0.2                  20% of nodes die
project3.bat 1000 3 drop=0.2                  each transmission lost with p = 0.2
project3.bat 1000 3 links=0.2                 20% of links permanently down
project3.bat 1000 3 kill=0.2 resilient        ...with every defence enabled
```

| Option | Meaning |
|---|---|
| `kill=p` | a fraction *p* of nodes die once the network is built |
| `drop=q` | a connection dies temporarily: each transmission lost with probability *q* |
| `links=r` | a connection dies permanently: a fraction *r* of node pairs can never communicate |
| `repair=1` | detect failures; repair leaf sets and routing tables (paper §2.5) |
| `replicas=4` | store each object on the 4 nodes closest to its key (as PAST does) |
| `attempts=3` | retry a failed lookup, up to 3 attempts in all |
| `retry=rand` | route a retry takes: `det` (same route), `rand` (default), `hybrid` |
| `resilient` | shorthand for `repair=1 replicas=4 attempts=3` |

All of them are off by default, so the main program behaves exactly as
specified.

### Findings

Measured at 1,000 nodes, three runs per point, 20% failure:

| Failure | No defence | Best defence | |
|---|---:|---:|---|
| 20% of nodes die | 59.8% | **99.8%** | repair + replication + retry |
| 20% of transmissions lost | 58.0% | **91.7%** | retry along the same route |
| 20% of links permanently down | 58.2% | **77.7%** | retry along a *random* route |

- **Every failure needed its own defence.** Repair alone left exactly the
  killed fraction of objects lost, at every failure level — those whose only
  copy died. Replication is what saves the data.
- **With every defence on, node death hits its theoretical floor.** Success
  matches 1 − p⁴, the chance that at least one of an object's four copies
  survives: the only lookups still failing are for objects nothing could save.
- **The two connection failures reward opposite retry policies.** Against a
  temporary failure, retrying the same route wins. Against a permanent one it
  is worthless — identical to not retrying at all — because Pastry's routing is
  deterministic and walks back into the same dead link. Only a randomised route
  escapes it.
- **A node can't tell which failure it is facing**, so the default is the
  randomised retry, which has the best worst case. A hybrid (same route once,
  then random) was also tested and landed strictly between the two at every
  one of the eight failure levels.

---

## Files

| File | Role |
|---|---|
| `project3.erl` | Command line: `project3 numNodes numRequests [options]` |
| `main.erl` | Coordinator: builds the network, stores objects, collects results |
| `pastry_init.erl` | `pastryInit(Credentials, Application)` — creates a node and starts its join |
| `pastry_node.erl` | The actor for one peer: join, requests, failure detection and repair |
| `route.erl` | `route(Msg, Key)` — leaf set, routing table, rare case, randomised retry |
| `deliver.erl` | `deliver(Msg, Key)` — insert, lookup, join, replication |
| `forward.erl` | `forward(Msg, Key, NextId)` — application hook, then send |
| `new_leafs.erl` | `newLeafs(LeafSet)` — leaf set maintenance |
| `node_state.erl` | Learning about nodes, known nodes, join snapshots |
| `rtable.erl` | The routing table |
| `pastry_util.erl` | 128-bit ids: hashing, digits, shared prefix, ring distance |
| `failure.erl` | The failure models (bonus) |
| `experiments.erl`, `report.erl` | Experiments → CSV → reports |
| `build.bat`, `project3.bat`, `run-experiments.sh`, `report.bat` | Runners |

# COP6539 Project 2 — Gossip Simulator

**Team:** Ahmed Rageeb Ahsan, Saiful Islam

An Erlang actor simulator that measures how long Gossip and Push-Sum take to
converge across four network topologies. Every node is one actor. The only
coordination is asynchronous message passing — no ETS, no locks, no shared
mutable state, no parallelism of any other kind.

---

## Build and run

```
build.bat
run.bat <numNodes> <topology> <algorithm>
```

| | |
|---|---|
| topology | `full`, `2D`, `line`, `imp2D` |
| algorithm | `gossip`, `push-sum` |

```
run.bat 1000 full gossip
run.bat 1000 imp2D push-sum
run.bat 1000 line gossip death=0.1
```

Options may appear in any position: `drop=q` (fraction of messages lost),
`death=p` (fraction of nodes that die mid-run), `window=ms` (period the deaths
are spread over), `hears=k` (gossip hear-limit, default 10), `timeout=ms`.

From the Erlang shell, `project2:start(1000, full, gossip)` also works.

To reproduce the measurements and the report:

```
sweep.bat        -> results\project2.csv
report.bat       -> results\Report.html and results\Report.pdf
```

`report.bat` prints the HTML to PDF with headless Edge, so no Python, LaTeX or
charting tool is needed.

---

## What is working

Everything the assignment asks for, for **both algorithms on all four
topologies**.

- **Gossip.** A node starts spreading when it first hears the rumour and falls
  silent after hearing it 10 times. Convergence is when every node has heard it.
- **Push-Sum.** Each actor starts with `s = i`, `w = 1`, halves and sends on
  each transmit, and terminates once its ratio `s/w` has moved by less than
  10⁻¹⁰ three times in a row. Convergence is when every actor has terminated.
- **Topologies.** `full`, `line`, `2D`, and `imp2D` (the grid plus one extra
  long-range edge per node, drawn once and then fixed).
- **Failure models** (bonus): node death and message loss, each driven by one
  parameter.
- **Timing** uses `erlang:monotonic_time(microsecond)` in the shape the
  assignment specifies. Network construction is timed separately and excluded —
  the reported figure is convergence time, not build time.
- **Non-convergence is detected and reported** rather than waited out. Gossip
  can genuinely die before reaching everyone; when every actor that heard the
  rumour has also fallen silent, no message can still be in flight, so the run
  is over.

### Correctness check

`s/w` converges to `(n+1)/2` — the **average**, not the sum. (The assignment
calls `s/w` the sum estimate; the sum is `ratio × n`. The simulator prints
both.) The simulator checks its own answer against the true value:

| Topology | Relative error at n = 100 |
|---|---|
| full | ~1 × 10⁻¹³ |
| imp2D | ~1 × 10⁻¹³ |
| 2D | ~1 × 10⁻³ |
| line | ~3 × 10⁻² |

The two well-connected topologies are exact to floating-point noise. The error
on `2D` and `line` is not an implementation defect — the termination rule is
*local*, so on a slowly-mixing graph an actor's own ratio settles well before
the network as a whole has mixed. Accuracy and speed turn out to be the same
property of the topology.

---

## Largest network managed, per topology and algorithm

Measured on an AMD Ryzen 5 5500U (6 cores / 12 threads). Each point is 5 trials;
the figure below is the largest size at which trials converged. `2D` and `imp2D`
round up to a perfect square, so the actual node count is shown.

| Topology | Gossip | Push-Sum |
|---|---:|---:|
| **full** | **100,000** | **100,000** |
| **imp2D** | 20,164 | 50,176 |
| **2D** | 10,000 | 5,041 |
| **line** | 1,000 | 10,000 |

The limit is wall-clock patience, not memory: `full` at 100,000 nodes uses a few
hundred MB and converges in about 1.8 s for gossip and 25 s for push-sum.

Two results here are worth reading carefully rather than at a glance:

- **Push-Sum beats Gossip on the sparse topologies** (`line`: 10,000 vs 1,000).
  That inverts the usual expectation and it is not a mistake. Gossip on a line
  frequently *dies*, because a node falls silent after 10 hears and the node
  next to a fast talker reaches 10 almost immediately, having forwarded the
  rumour only a handful of times. Push-Sum has no such stopping rule — every
  actor keeps participating until its own ratio settles — so it is slow on a
  line but it does not give up.
- **Gossip on `line` is probabilistic, not merely slow.** At n = 100 it reaches
  every node in roughly six runs out of ten and dies out in the rest. This is
  why the harness runs five trials per point and records how many converged
  instead of reporting a bare average.

---

## Notes on the implementation

### The actor model, and the one shared structure

Every node is a process; all communication is message passing. The single piece
of shared data is the index → Pid table, held in `persistent_term`.

It is a **read-only address book**, written once before any actor is allowed to
send and never mutated while a run is in progress — exactly the role a name
registry plays in ordinary Erlang. It carries no algorithm state and is not a
coordination mechanism.

It is there for a concrete reason. Handing every actor the whole Pid tuple, as
the first version did, costs O(N²) memory because Erlang copies terms on send:
**822 MB at n = 10,000**, growing quadratically to roughly 3.3 GB at 20,000.
`persistent_term` readers do not copy, which is what makes 100,000 nodes
possible at all.

### Transmission is continuous, not one-send-per-receive

Read literally, "upon receive, select a random neighbour and send" means one
message in produces exactly one message out — so the entire network would carry
a single message at a time, a lone random walk. Gossip would barely spread.

Gossip actors therefore keep transmitting while active. The detail that matters
is that an active actor consumes **at most one** pending message before
transmitting, rather than draining its whole mailbox first. Draining first
starves propagation: a node beside a fast neighbour is never empty, so it
reaches 10 hears having forwarded the rumour almost never, and the frontier dies
where it stands. Measured at n = 100, draining first reached 20 nodes of 100 on
`2D`, 28 on `imp2D` and 3 on `line`; consuming one and always sending one
reaches 100% on all three.

### Push-Sum is paced differently, and must be

Push-Sum sends exactly one message per message received, with every actor seeded
by a single transmit, so exactly *n* messages circulate.

It cannot use the continuous loop that Gossip uses. Transmitting halves `s` and
`w`, so an actor that is not receiving halves itself toward zero — and after
**1075 halvings `w` is exactly 0.0** in IEEE double precision, which a busy loop
reaches in well under a millisecond. It then ships `(0.0, 0.0)` messages; a
recipient adding zero sees its ratio not move, counts that as a stable round,
and terminates on whatever value it was holding. Measured error under that
scheme was 2–4%; with one-send-per-receive it is ~10⁻¹³.

Two further details, both fatal if missed:

1. **Stability is judged only on receive.** Halving leaves `s/w` exactly
   unchanged, so counting transmits as rounds would make an actor nobody talks
   to terminate immediately, reporting its own index as the network average.
2. **Mass is given away only if the message actually departs.** If the failure
   model drops the send, the actor keeps its full `s` and `w`. Halving anyway
   would destroy mass and drag every estimate down.

A terminated actor relays incoming mass onward rather than absorbing it, so mass
stays conserved and the actors still running can finish.

---

## Files

| File | Role |
|---|---|
| `topology.erl` | Neighbour sets, grid sizing, the Pid address book, link-loss |
| `gossip.erl` | Gossip actor |
| `push_sum.erl` | Push-Sum actor |
| `project2.erl` | CLI, orchestration, collector, timing |
| `experiments.erl` | Sweeps → CSV |
| `report.erl` | CSV → self-contained HTML with inline SVG charts |
| `build.bat`, `run.bat`, `sweep.bat`, `report.bat` | Runners |

Note for PowerShell users: scripts need the `.\` prefix (`.\build.bat`), since
PowerShell does not run executables from the current directory without one.

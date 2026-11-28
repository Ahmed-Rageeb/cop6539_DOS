
# Reddit Clone in Erlang: Engine + Client Simulator (Project 4, Part I)

A Reddit-like engine implemented as a single Erlang `gen_server`, and a simulator that drives it
with thousands of independent client processes running on a **separate Erlang node**.

**Team members:** Ahmed Rageeb Ahsan, Saiful Islam

---

## Contents

- [Features](#features)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Build](#build)
- [Run the engine](#run-the-engine)
- [Run the simulator](#run-the-simulator)
- [Sample results](#sample-results)
- [Engine API reference](#engine-api-reference)
- [Design notes](#design-notes)
- [Troubleshooting](#troubleshooting)

## Features

**Engine** (`reddit_engine.erl`)

| Feature | Function |
|---|---|
| Register account | `register_user/2` |
| Create / join / leave sub-reddit | `create_subreddit/3`, `join_subreddit/3`, `leave_subreddit/3` |
| Post (plain text) in a sub-reddit | `create_post/4` |
| Re-post an existing post | `repost/3` |
| Hierarchical comments (comment on a post or on a comment) | `add_comment/5`, `get_comments/2` |
| Upvote / downvote / remove vote on posts and comments | `vote/4` |
| Karma | `get_karma/2` |
| Feed of posts from joined sub-reddits (newest first) | `get_feed/3` |
| Direct messages: send, list inbox, reply | `send_message/4`, `get_messages/2`, `reply_message/4` |
| Engine statistics / reset | `stats/1`, `reset/0` |

**Simulator** (`simulator.erl`)

- One Erlang process per simulated user, running on a different node than the engine.
- Periods of live connection and disconnection for every user (on reconnect the user fetches its feed and inbox).
- Zipf distribution of sub-reddit membership (rank *k* gets about N / k members); popular sub-reddits get more posts.
- Re-posts, nested comments, votes, direct messages and feed refreshes.
- Measures throughput and latency (average, p50, p95, p99, max) per operation and prints a report.

## Repository layout

```
.
├── reddit_engine.erl   # the engine (gen_server)
├── simulator.erl       # client simulator and metrics
└── README.md
```

## Requirements

- Erlang/OTP (developed and tested on **OTP 29**; any recent OTP with maps support works)
- `erl` and `erlc` available on your `PATH`

## Build

From the project folder:

```
erlc reddit_engine.erl
erlc simulator.erl
```

This produces `reddit_engine.beam` and `simulator.beam`.

## Run the engine

Open a terminal in the project folder and start a node named `engine`:

```
erl -sname engine
1> reddit_engine:start_link().
{ok,<0.92.0>}
```

The engine registers itself under the name `reddit_engine`. Keep this terminal open
(the server is linked to this shell). The node name is shown in the prompt, for example
`(engine@AhmedRageeb)1>`; the part after `@` is your `HOSTNAME`.

### Quick test of the engine (same shell)

Every API function takes a server reference as first argument: the atom `reddit_engine` locally.

```erlang
2> {ok, Alice} = reddit_engine:register_user(reddit_engine, "alice").
{ok,1}
3> {ok, Bob} = reddit_engine:register_user(reddit_engine, "bob").
{ok,2}
4> {ok, Sub} = reddit_engine:create_subreddit(reddit_engine, Alice, "erlang").
{ok,1}
5> reddit_engine:join_subreddit(reddit_engine, Bob, Sub).
ok
6> {ok, Post} = reddit_engine:create_post(reddit_engine, Alice, Sub, "hello world").
{ok,1}
7> {ok, C1} = reddit_engine:add_comment(reddit_engine, Bob, Post, none, "nice post").
{ok,1}
8> reddit_engine:add_comment(reddit_engine, Alice, Post, C1, "thanks!").   %% reply to a comment
{ok,2}
9> reddit_engine:vote(reddit_engine, Bob, upvote, {post, Post}).
{ok,vote_recorded}
10> reddit_engine:get_karma(reddit_engine, Alice).
{ok,1}
11> reddit_engine:repost(reddit_engine, Bob, Post).
{ok,2}
12> reddit_engine:get_feed(reddit_engine, Bob, 10).
{ok,[...]}
13> {ok, M1} = reddit_engine:send_message(reddit_engine, Alice, Bob, "hi bob").
{ok,1}
14> reddit_engine:reply_message(reddit_engine, Bob, M1, "hi alice").
{ok,2}
15> reddit_engine:stats(reddit_engine).
{ok,#{comments => 2,messages => 2,posts => 2,subreddits => 1,users => 2}}
16> reddit_engine:reset().
ok
```

## Run the simulator

The simulator must run in a **different terminal / Erlang node** than the engine.

**Terminal 1:** engine (see above, keep it running).

**Terminal 2:** open a new terminal in the same project folder (it needs `simulator.beam` and
`reddit_engine.beam`):

```
erl -sname client
1> net_adm:ping('engine@HOSTNAME').
pong
2> simulator:run('engine@HOSTNAME', 1000, 50, 10000).
```

Replace `HOSTNAME` with your machine name (for example `'engine@AhmedRageeb'`). If `net_adm:ping`
prints `pang`, the engine is not running, the name is wrong, or the nodes use different cookies.

### Parameters

```
simulator:run(EngineNode, NumUsers, NumSubreddits, DurationMs).
```

| Argument | Meaning |
|---|---|
| `EngineNode` | Node of the running engine, e.g. `'engine@AhmedRageeb'` |
| `NumUsers` | Number of simulated users (one Erlang process each) |
| `NumSubreddits` | Number of sub-reddits (at most `NumUsers`) |
| `DurationMs` | How long the clients run, in milliseconds |

Each call resets the engine first, so you can run several experiments one after another without
restarting it. The shell message *"Command is taking a long time"* while a run is in progress is
harmless.

### Experiments used in the report

```erlang
simulator:run('engine@HOSTNAME', 100,   10,  10000).
simulator:run('engine@HOSTNAME', 1000,  50,  10000).
simulator:run('engine@HOSTNAME', 5000,  100, 20000).
simulator:run('engine@HOSTNAME', 10000, 200, 30000).
```

### What the simulator does

1. **Setup:** registers the users, creates the sub-reddits (sub-reddit *k* is created by user *k*) and joins
   users following a Zipf law (rank *k* gets about N / k members, so rank 1 contains everyone).
2. **Clients:** each user alternates between
   - an **online** period of 300 to 1000 ms in which it acts, and
   - an **offline** period of 100 to 500 ms in which it sends nothing. On reconnect it fetches its feed and inbox.
3. **Actions while online** (1 to 10 ms think time): 20% post (sub-reddit chosen with probability
   proportional to 1/rank, so popular sub-reddits get more posts), 25% comment (30% of them reply to the
   client's own previous comment), 30% vote (70% up, 30% down), 5% re-post, 10% direct message, 10% feed refresh.
4. **Report:** total requests, throughput, number of connect/disconnect sessions, per-operation latency table
   and the final engine state.

Example output (shortened):

```
=== Simulation report ===
Users: 1000   Subreddits: 50   Zipf s: 1.0
Setup time: 607 ms   Run time: 10525 ms
Connection sessions (connect/disconnect cycles): 10461
Total requests: 284827   Throughput: 27061.9 req/s

op                count     avg ms     p50 ms     p95 ms     p99 ms     max ms
add_comment       63840      18.88      18.12      25.80      44.44      56.83
...
```

## Sample results

Measured on one Windows machine (Erlang/OTP 29, 16 schedulers); engine and simulator on two nodes of the
same machine; one run per configuration.

| Users | Sub-reddits | Run time | Requests | Throughput (req/s) | Avg latency (ms) | p95 (ms) | Max (ms) |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 | 10 | 10 s | 53,625 | 5,104 | 1.9 | 3.3 - 3.6 | 16 |
| 1,000 | 50 | 10 s | 284,827 | 27,062 | 19.1 | 25.8 - 30.3 | 57 |
| 5,000 | 100 | 20 s | 451,703 | 21,860 | 171.1 | 273 - 276 | 295 |
| 10,000 | 200 | 30 s | 503,159 | 16,135 | 520.6 | 753 - 761 | 928 |

Throughput peaks at about 1,000 users. After that, all requests queue in the single engine process, so
latency grows with the number of users and throughput falls. See the project report for the full analysis.

## Engine API reference

All functions return `{ok, Result}`, `ok`, or `{error, Reason}`.
`Server` is `reddit_engine` (local) or `{reddit_engine, Node}` (remote).

| Function | Returns on success |
|---|---|
| `register_user(Server, Username)` | `{ok, UserId}` |
| `create_subreddit(Server, UserId, Name)` | `{ok, SubId}` (creator is auto-joined) |
| `join_subreddit(Server, UserId, SubId)` | `ok` |
| `leave_subreddit(Server, UserId, SubId)` | `ok` |
| `create_post(Server, UserId, SubId, Text)` | `{ok, PostId}` |
| `repost(Server, UserId, PostId)` | `{ok, NewPostId}` (keeps a pointer to the original post) |
| `add_comment(Server, UserId, PostId, ParentId, Text)` | `{ok, CommentId}`; `ParentId` is `none` for a top-level comment or the id of a comment on the same post |
| `get_comments(Server, PostId)` | `{ok, [CommentMap]}` oldest first |
| `vote(Server, UserId, Type, {Kind, Id})` | `{ok, vote_recorded}`; `Type`: `upvote \| downvote \| remove`, `Kind`: `post \| comment` |
| `get_karma(Server, UserId)` | `{ok, Integer}` (sum of votes on the user's posts and comments) |
| `get_feed(Server, UserId, Limit)` | `{ok, [PostMap]}` newest first, from joined sub-reddits |
| `send_message(Server, FromId, ToId, Text)` | `{ok, MessageId}` |
| `get_messages(Server, UserId)` | `{ok, [MessageMap]}` inbox, newest first |
| `reply_message(Server, UserId, MessageId, Text)` | `{ok, NewMessageId}` (sent to the original sender) |
| `stats(Server)` | `{ok, #{users, subreddits, posts, comments, messages}}` |
| `reset()` / `request(Server, reset)` | `ok` |

### Error reasons

| Reason | Meaning |
|---|---|
| `invalid_username`, `invalid_subreddit_name`, `invalid_post`, `invalid_comment`, `invalid_message` | Empty or non-text input |
| `username_already_exists`, `subreddit_already_exists` | Name already taken |
| `user_not_found`, `sender_not_found`, `receiver_not_found`, `subreddit_not_found`, `post_not_found`, `message_not_found`, `target_not_found` | Unknown id |
| `already_member`, `not_a_member` | Membership errors (posting, commenting and re-posting require membership) |
| `invalid_parent_comment` | Parent comment does not exist or belongs to a different post |
| `already_voted`, `vote_not_found` | Duplicate vote / removing a vote that does not exist |
| `not_message_receiver` | Only the receiver of a message can reply to it |
| `invalid_request` | Unknown operation or malformed arguments |

## Design notes

- **One engine process.** All state lives in a single `gen_server`, so every operation is serialized and
  consistent. This satisfies the single-engine-process requirement and is also the throughput bottleneck.
- **Clients are separate processes on a separate node.** `request/2` uses `gen_server:call/3`, which also works
  with `{Name, Node}`, so clients reach the engine over Erlang distribution.
- **Efficient lookups.** Usernames and sub-reddit names are indexed in maps; members are stored in maps; karma is
  updated incrementally on each vote; each user has an inbox list; each sub-reddit keeps post ids newest first, so a
  feed only reads the newest `Limit` posts of each joined sub-reddit and merges them.
- **Voting.** Each post / comment keeps `UserId => 1 | -1`. A user can switch between upvote and downvote or remove
  the vote; voting the same way twice returns `already_voted`. Posts and comments have separate id spaces, so a
  vote target is always `{post, Id}` or `{comment, Id}`.
- **Re-posts** create a new post in the same sub-reddit with the same text and `original_post_id` set to the root
  original (re-posting a re-post still points to the original).
- **Ordering** uses a global sequence number instead of wall-clock time, so feed and inbox order is deterministic.

## Troubleshooting

- `erlc` / `erl` is not recognized: add the Erlang `bin` folder to your `PATH`
  (for example `C:\Program Files\Erlang OTP\bin` on Windows).
- `{error,{already_started,_}}` from `start_link()`: the engine is already running in this node.
- `net_adm:ping/1` returns `pang`: check the node name and hostname, that the engine node is running, and that both
  nodes use the same Erlang cookie (automatic when both run as the same user on the same machine).
- `undef` for `reddit_engine:...` or `simulator:...` on the client node: start `erl` from the folder that contains the
  `.beam` files, or use `erl -pa path/to/folder`.
- Large runs take a while to start because setup registers and joins users one call at a time.










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

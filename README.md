
# Reddit Clone Engine (Erlang) — Project 4, Part I


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

## Requirements

- Erlang/OTP (developed and tested on **OTP 29**; any recent OTP with maps support works)
- `erl` and `erlc` available on your `PATH`

## Repository layout

```
.
├── reddit_engine.erl   # the engine (gen_server)
└── README.md
```

## Build

```
erlc reddit_engine.erl
```

This produces `reddit_engine.beam` in the same folder.

## Run the engine

Start an Erlang node named `engine` and start the server:

```
erl -sname engine
1> reddit_engine:start_link().
{ok,<0.92.0>}
```

The engine registers itself under the name `reddit_engine`.
Keep this shell open: the server is linked to it.

### Quick test (same shell)

Every API function takes a **server reference** as its first argument.
Locally this is the atom `reddit_engine`.

```erlang
1> reddit_engine:start_link().
{ok,<0.92.0>}
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
8> {ok, C2} = reddit_engine:add_comment(reddit_engine, Alice, Post, C1, "thanks!").   %% reply to a comment
{ok,2}
9> reddit_engine:vote(reddit_engine, Bob, upvote, {post, Post}).
{ok,vote_recorded}
10> reddit_engine:vote(reddit_engine, Alice, upvote, {comment, C1}).
{ok,vote_recorded}
11> reddit_engine:get_karma(reddit_engine, Alice).
{ok,1}
12> reddit_engine:get_karma(reddit_engine, Bob).
{ok,1}
13> {ok, Reposted} = reddit_engine:repost(reddit_engine, Bob, Post).
{ok,2}
14> reddit_engine:get_feed(reddit_engine, Bob, 10).
{ok,[...]}                                  %% newest posts first
15> reddit_engine:get_comments(reddit_engine, Post).
{ok,[...]}                                  %% every comment with its parent_id
16> {ok, M1} = reddit_engine:send_message(reddit_engine, Alice, Bob, "hi bob").
{ok,1}
17> reddit_engine:get_messages(reddit_engine, Bob).
{ok,[...]}
18> reddit_engine:reply_message(reddit_engine, Bob, M1, "hi alice").
{ok,2}
19> reddit_engine:stats(reddit_engine).
{ok,#{comments => 2,messages => 2,posts => 2,subreddits => 1,users => 2}}
20> reddit_engine:reset().                  %% wipe all state
ok
```

### Run the engine and clients as separate processes / nodes

The engine and the clients can run on different Erlang nodes (this is how the simulator uses it).
Pass `{reddit_engine, 'engine@HOSTNAME'}` as the server reference.

**Terminal 1 – engine node**

```
erl -sname engine
1> reddit_engine:start_link().
```

**Terminal 2 – client node** (run from the folder that contains `reddit_engine.beam`)

```
erl -sname client
1> Srv = {reddit_engine, 'engine@HOSTNAME'}.
2> net_adm:ping('engine@HOSTNAME').          %% must print: pong
3> reddit_engine:register_user(Srv, "carol").
{ok,1}
```

Replace `HOSTNAME` with your machine name (it is shown in the shell prompt of the engine node,
e.g. `(engine@AhmedRageeb)1>`). Both nodes must use the same Erlang cookie
(automatic when they run as the same user on the same machine).

## API reference

All functions return `{ok, Result}`, `ok`, or `{error, Reason}`.
`Server` is `reddit_engine` (local) or `{reddit_engine, Node}` (remote).

| Function | Returns on success |
|---|---|
| `register_user(Server, Username)` | `{ok, UserId}` |
| `create_subreddit(Server, UserId, Name)` | `{ok, SubId}` (creator is auto-joined) |
| `join_subreddit(Server, UserId, SubId)` | `ok` |
| `leave_subreddit(Server, UserId, SubId)` | `ok` |
| `create_post(Server, UserId, SubId, Text)` | `{ok, PostId}` |
| `repost(Server, UserId, PostId)` | `{ok, NewPostId}` (keeps pointer to the original post) |
| `add_comment(Server, UserId, PostId, ParentId, Text)` | `{ok, CommentId}` — `ParentId` is `none` for a top-level comment, or the id of a comment on the same post |
| `get_comments(Server, PostId)` | `{ok, [CommentMap]}` oldest first |
| `vote(Server, UserId, Type, {Kind, Id})` | `{ok, vote_recorded}` — `Type`: `upvote \| downvote \| remove`, `Kind`: `post \| comment` |
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
| `invalid_username`, `invalid_subreddit_name`, `invalid_post`, `invalid_comment`, `invalid_message` | Empty / non-text input |
| `username_already_exists`, `subreddit_already_exists` | Name taken |
| `user_not_found`, `sender_not_found`, `receiver_not_found`, `subreddit_not_found`, `post_not_found`, `message_not_found`, `target_not_found` | Unknown id |
| `already_member`, `not_a_member` | Membership errors (posting, commenting and reposting require membership) |
| `invalid_parent_comment` | Parent comment does not exist or belongs to a different post |
| `already_voted`, `vote_not_found` | Duplicate vote / removing a vote that does not exist |
| `not_message_receiver` | Only the receiver of a message can reply to it |
| `invalid_request` | Unknown operation or malformed arguments |

## Design notes

- **One engine process.** All state lives in a single `gen_server`, so every operation is
  serialized and consistent. This satisfies the "single engine process" requirement and is
  also the throughput bottleneck, which is discussed in the report.
- **Separate processes for clients.** `request/2` uses `gen_server:call/3`, which also works with
  `{Name, Node}` references, so clients can be separate processes on separate nodes.
- **Efficient lookups** (no full scans on the hot paths):
  - usernames and sub-reddit names are indexed in maps (`O(log n)` uniqueness checks),
  - sub-reddit members are stored in a map,
  - karma is updated incrementally on every vote (the change in vote value is added to the author's karma),
  - each user has an inbox list, and each sub-reddit keeps its post ids newest-first, so a feed only reads the newest `Limit` posts per joined sub-reddit and merges them.
- **Voting.** Each post / comment keeps `UserId => 1 | -1`. A user can switch between upvote and
  downvote, or remove the vote; voting the same way twice returns `already_voted`.
  Posts and comments have separate id spaces, so a vote target is always `{post, Id}` or `{comment, Id}`.
- **Re-posts** create a new post in the same sub-reddit with the same text and
  `original_post_id` set to the root original (re-posting a re-post still points to the original).
- **Ordering** uses a global monotonically increasing sequence number instead of wall-clock time,
  so feed and inbox order is deterministic.

## Troubleshooting

- `erlc` / `erl` is not recognized: add the Erlang `bin` folder to your `PATH`
  (e.g. `C:\Program Files\Erlang OTP\bin` on Windows).
- `{error,{already_started,_}}` from `start_link()`: the engine is already running in this node.
- `net_adm:ping/1` returns `pang`: check the node name/hostname, that the engine node is running,
  and that both nodes use the same cookie.
- `undef` when calling `reddit_engine:...` from the client node: start `erl` from the folder that contains
  `reddit_engine.beam`, or use `erl -pa path/to/folder`.






























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

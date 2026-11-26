-module(reddit_engine).
-behaviour(gen_server).

%% Public API
-export([
    start_link/0, stop/0, reset/0, request/2,
    register_user/2,
    create_subreddit/3, join_subreddit/3, leave_subreddit/3,
    create_post/4, repost/3,
    add_comment/5, get_comments/2,
    vote/4, get_karma/2,
    get_feed/3,
    send_message/4, get_messages/2, reply_message/4,
    stats/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    users      = #{},   % UserId => #{id, username}
    usernames  = #{},   % Username(binary) => UserId
    subreddits = #{},   % SubId => #{id, name, owner, members => #{UserId=>true}, posts => [PostId] newest first}
    sub_names  = #{},   % Name(binary) => SubId
    joined     = #{},   % UserId => #{SubId => true}
    posts      = #{},   % PostId => map
    comments   = #{},   % CommentId => map
    messages   = #{},   % MsgId => map
    inbox      = #{},   % UserId => [MsgId] newest first
    karma      = #{},   % UserId => integer
    next_user = 1, next_subreddit = 1, next_post = 1,
    next_comment = 1, next_message = 1,
    sequence = 1
}).

%% =====================================================
%% PUBLIC API
%% Server can be ?MODULE, a pid, or {reddit_engine, 'engine@host'}
%% =====================================================

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
stop()       -> gen_server:stop(?MODULE).
reset()      -> request(?MODULE, reset).

request(Server, Request) -> gen_server:call(Server, Request, infinity).

register_user(Srv, Username)          -> request(Srv, {register_user, Username}).
create_subreddit(Srv, UserId, Name)   -> request(Srv, {create_subreddit, UserId, Name}).
join_subreddit(Srv, UserId, SubId)    -> request(Srv, {join_subreddit, UserId, SubId}).
leave_subreddit(Srv, UserId, SubId)   -> request(Srv, {leave_subreddit, UserId, SubId}).
create_post(Srv, UserId, SubId, Text) -> request(Srv, {create_post, UserId, SubId, Text}).
repost(Srv, UserId, PostId)           -> request(Srv, {repost, UserId, PostId}).
%% ParentId = none for a top-level comment, or a comment id
add_comment(Srv, UserId, PostId, ParentId, Text) ->
    request(Srv, {add_comment, UserId, PostId, ParentId, Text}).
get_comments(Srv, PostId)             -> request(Srv, {get_comments, PostId}).
%% Kind = post | comment, Type = upvote | downvote | remove
vote(Srv, UserId, Type, {Kind, Id})   -> request(Srv, {vote, UserId, Type, {Kind, Id}}).
get_karma(Srv, UserId)                -> request(Srv, {get_karma, UserId}).
get_feed(Srv, UserId, Limit)          -> request(Srv, {get_feed, UserId, Limit}).
send_message(Srv, From, To, Text)     -> request(Srv, {send_message, From, To, Text}).
get_messages(Srv, UserId)             -> request(Srv, {get_messages, UserId}).
reply_message(Srv, UserId, MsgId, T)  -> request(Srv, {reply_message, UserId, MsgId, T}).
stats(Srv)                            -> request(Srv, stats).

%% =====================================================
%% CALLBACKS
%% =====================================================

init([]) -> {ok, #state{}}.

handle_call(reset, _From, _S) ->
    {reply, ok, #state{}};
handle_call(Request, _From, S) ->
    {Reply, NewS} = execute(Request, S),
    {reply, Reply, NewS}.

handle_cast(_Msg, S)  -> {noreply, S}.
handle_info(_Info, S) -> {noreply, S}.
terminate(_Reason, _S) -> ok.
code_change(_Old, S, _Extra) -> {ok, S}.

%% =====================================================
%% EXECUTE (all clauses contiguous; catch-all last)
%% =====================================================

%% ---------- users ----------
execute({register_user, Username0}, S) ->
    case to_text(Username0) of
        error ->
            {{error, invalid_username}, S};
        Username ->
            case maps:is_key(Username, S#state.usernames) of
                true ->
                    {{error, username_already_exists}, S};
                false ->
                    Id = S#state.next_user,
                    User = #{id => Id, username => Username},
                    {{ok, Id}, S#state{
                        users = maps:put(Id, User, S#state.users),
                        usernames = maps:put(Username, Id, S#state.usernames),
                        next_user = Id + 1,
                        sequence = S#state.sequence + 1}}
            end
    end;

%% ---------- subreddits ----------
execute({create_subreddit, UserId, Name0}, S) ->
    case {user_exists(UserId, S), to_text(Name0)} of
        {false, _} ->
            {{error, user_not_found}, S};
        {true, error} ->
            {{error, invalid_subreddit_name}, S};
        {true, Name} ->
            case maps:is_key(Name, S#state.sub_names) of
                true ->
                    {{error, subreddit_already_exists}, S};
                false ->
                    Id = S#state.next_subreddit,
                    Sub = #{id => Id, name => Name, owner => UserId,
                            members => #{}, posts => []},
                    S1 = S#state{
                        sub_names = maps:put(Name, Id, S#state.sub_names),
                        next_subreddit = Id + 1},
                    {{ok, Id}, add_member(UserId, Id, Sub, S1)}
            end
    end;

execute({join_subreddit, UserId, SubId}, S) ->
    case {user_exists(UserId, S), maps:find(SubId, S#state.subreddits)} of
        {false, _} ->
            {{error, user_not_found}, S};
        {true, error} ->
            {{error, subreddit_not_found}, S};
        {true, {ok, Sub}} ->
            case maps:is_key(UserId, maps:get(members, Sub)) of
                true  -> {{error, already_member}, S};
                false -> {ok, add_member(UserId, SubId, Sub, S)}
            end
    end;

execute({leave_subreddit, UserId, SubId}, S) ->
    case {user_exists(UserId, S), maps:find(SubId, S#state.subreddits)} of
        {false, _} ->
            {{error, user_not_found}, S};
        {true, error} ->
            {{error, subreddit_not_found}, S};
        {true, {ok, Sub}} ->
            case maps:is_key(UserId, maps:get(members, Sub)) of
                false -> {{error, not_a_member}, S};
                true  -> {ok, remove_member(UserId, SubId, Sub, S)}
            end
    end;

%% ---------- posts ----------
execute({create_post, UserId, SubId, Content0}, S) ->
    case to_text(Content0) of
        error ->
            {{error, invalid_post}, S};
        Content ->
            case user_exists(UserId, S) of
                false ->
                    {{error, user_not_found}, S};
                true ->
                    case is_member(UserId, SubId, S) of
                        false -> {{error, not_a_member}, S};
                        true  -> create_post_record(UserId, SubId, Content, none, S)
                    end
            end
    end;

execute({repost, UserId, OriginalId}, S) ->
    case {user_exists(UserId, S), maps:find(OriginalId, S#state.posts)} of
        {false, _} ->
            {{error, user_not_found}, S};
        {true, error} ->
            {{error, post_not_found}, S};
        {true, {ok, Original}} ->
            SubId = maps:get(subreddit_id, Original),
            case is_member(UserId, SubId, S) of
                false ->
                    {{error, not_a_member}, S};
                true ->
                    Root = case maps:get(original_post_id, Original) of
                               none -> OriginalId;
                               R    -> R
                           end,
                    create_post_record(UserId, SubId,
                                       maps:get(content, Original), Root, S)
            end
    end;

%% ---------- comments (hierarchical) ----------
execute({add_comment, UserId, PostId, ParentId, Content0}, S) ->
    case to_text(Content0) of
        error ->
            {{error, invalid_comment}, S};
        Content ->
            case {user_exists(UserId, S), maps:find(PostId, S#state.posts)} of
                {false, _} ->
                    {{error, user_not_found}, S};
                {true, error} ->
                    {{error, post_not_found}, S};
                {true, {ok, Post}} ->
                    case is_member(UserId, maps:get(subreddit_id, Post), S) of
                        false ->
                            {{error, not_a_member}, S};
                        true ->
                            add_comment_record(UserId, PostId, Post,
                                               ParentId, Content, S)
                    end
            end
    end;

execute({get_comments, PostId}, S) ->
    case maps:find(PostId, S#state.posts) of
        error ->
            {{error, post_not_found}, S};
        {ok, Post} ->
            Ids = lists:reverse(maps:get(comments, Post)),   % oldest first
            {{ok, [maps:get(Id, S#state.comments) || Id <- Ids]}, S}
    end;

%% ---------- voting / karma ----------
execute({vote, UserId, Type, {Kind, Id}}, S)
  when (Type =:= upvote orelse Type =:= downvote orelse Type =:= remove),
       (Kind =:= post orelse Kind =:= comment) ->
    case user_exists(UserId, S) of
        false -> {{error, user_not_found}, S};
        true  -> apply_vote(UserId, Type, Kind, Id, S)
    end;

execute({get_karma, UserId}, S) ->
    case user_exists(UserId, S) of
        false -> {{error, user_not_found}, S};
        true  -> {{ok, maps:get(UserId, S#state.karma, 0)}, S}
    end;

%% ---------- feed ----------
execute({get_feed, UserId, Limit}, S) when is_integer(Limit), Limit >= 0 ->
    case user_exists(UserId, S) of
        false ->
            {{error, user_not_found}, S};
        true ->
            SubIds = maps:keys(maps:get(UserId, S#state.joined, #{})),
            %% each sub's post list is newest-first, so top Limit per sub is enough
            Lists = [begin
                         Sub = maps:get(SubId, S#state.subreddits),
                         Top = lists:sublist(maps:get(posts, Sub), Limit),
                         [maps:get(P, S#state.posts) || P <- Top]
                     end || SubId <- SubIds],
            Sorted = lists:sort(
                       fun(A, B) ->
                           maps:get(created_seq, A) >= maps:get(created_seq, B)
                       end, lists:append(Lists)),
            {{ok, lists:sublist(Sorted, Limit)}, S}
    end;

%% ---------- direct messages ----------
execute({send_message, From, To, Content0}, S) ->
    case {user_exists(From, S), user_exists(To, S), to_text(Content0)} of
        {false, _, _} -> {{error, sender_not_found}, S};
        {_, false, _} -> {{error, receiver_not_found}, S};
        {_, _, error} -> {{error, invalid_message}, S};
        {true, true, Content} -> create_message(From, To, Content, none, S)
    end;

execute({get_messages, UserId}, S) ->
    case user_exists(UserId, S) of
        false ->
            {{error, user_not_found}, S};
        true ->
            Ids = maps:get(UserId, S#state.inbox, []),
            {{ok, [maps:get(Id, S#state.messages) || Id <- Ids]}, S}
    end;

execute({reply_message, UserId, MsgId, Content0}, S) ->
    case {user_exists(UserId, S), maps:find(MsgId, S#state.messages),
          to_text(Content0)} of
        {false, _, _} ->
            {{error, user_not_found}, S};
        {_, error, _} ->
            {{error, message_not_found}, S};
        {_, _, error} ->
            {{error, invalid_message}, S};
        {true, {ok, Orig}, Content} ->
            case maps:get(receiver_id, Orig) =:= UserId of
                false -> {{error, not_message_receiver}, S};
                true  -> create_message(UserId, maps:get(sender_id, Orig),
                                        Content, MsgId, S)
            end
    end;

%% ---------- stats (handy for the report) ----------
execute(stats, S) ->
    {{ok, #{users => maps:size(S#state.users),
            subreddits => maps:size(S#state.subreddits),
            posts => maps:size(S#state.posts),
            comments => maps:size(S#state.comments),
            messages => maps:size(S#state.messages)}}, S};

execute(_Other, S) ->
    {{error, invalid_request}, S}.

%% =====================================================
%% HELPERS
%% =====================================================

%% Normalise text to a non-empty binary, or return error.
to_text(T) when is_list(T) ->
    try unicode:characters_to_binary(T) of
        B when is_binary(B) -> to_text(B);
        _ -> error
    catch _:_ -> error
    end;
to_text(T) when is_binary(T) ->
    case string:trim(T) of
        <<>> -> error;
        _    -> T
    end;
to_text(_) -> error.

user_exists(Id, S) -> maps:is_key(Id, S#state.users).

is_member(UserId, SubId, S) ->
    case maps:find(SubId, S#state.subreddits) of
        {ok, Sub} -> maps:is_key(UserId, maps:get(members, Sub));
        error     -> false
    end.

add_member(UserId, SubId, Sub, S) ->
    NewSub = Sub#{members := maps:put(UserId, true, maps:get(members, Sub))},
    J = maps:get(UserId, S#state.joined, #{}),
    S#state{
        subreddits = maps:put(SubId, NewSub, S#state.subreddits),
        joined = maps:put(UserId, maps:put(SubId, true, J), S#state.joined)}.

remove_member(UserId, SubId, Sub, S) ->
    NewSub = Sub#{members := maps:remove(UserId, maps:get(members, Sub))},
    J = maps:get(UserId, S#state.joined, #{}),
    S#state{
        subreddits = maps:put(SubId, NewSub, S#state.subreddits),
        joined = maps:put(UserId, maps:remove(SubId, J), S#state.joined)}.

create_post_record(UserId, SubId, Content, OriginalId, S) ->
    Id = S#state.next_post,
    Post = #{id => Id, user_id => UserId, subreddit_id => SubId,
             content => Content, original_post_id => OriginalId,
             votes => #{}, comments => [],
             created_seq => S#state.sequence},
    Sub = maps:get(SubId, S#state.subreddits),
    NewSub = Sub#{posts := [Id | maps:get(posts, Sub)]},
    {{ok, Id}, S#state{
        posts = maps:put(Id, Post, S#state.posts),
        subreddits = maps:put(SubId, NewSub, S#state.subreddits),
        next_post = Id + 1,
        sequence = S#state.sequence + 1}}.

add_comment_record(UserId, PostId, Post, ParentId, Content, S) ->
    case valid_parent(ParentId, PostId, S) of
        false ->
            {{error, invalid_parent_comment}, S};
        true ->
            Id = S#state.next_comment,
            Comment = #{id => Id, post_id => PostId, user_id => UserId,
                        parent_id => ParentId, content => Content,
                        votes => #{}, created_seq => S#state.sequence},
            NewPost = Post#{comments := [Id | maps:get(comments, Post)]},
            {{ok, Id}, S#state{
                comments = maps:put(Id, Comment, S#state.comments),
                posts = maps:put(PostId, NewPost, S#state.posts),
                next_comment = Id + 1,
                sequence = S#state.sequence + 1}}
    end.

valid_parent(none, _PostId, _S) -> true;
valid_parent(ParentId, PostId, S) ->
    case maps:find(ParentId, S#state.comments) of
        {ok, Parent} -> maps:get(post_id, Parent) =:= PostId;
        error        -> false
    end.

%% Votes: per-target map UserId => 1 | -1. Karma updated incrementally by delta.
apply_vote(UserId, Type, Kind, Id, S) ->
    Coll = case Kind of
               post    -> S#state.posts;
               comment -> S#state.comments
           end,
    case maps:find(Id, Coll) of
        error ->
            {{error, target_not_found}, S};
        {ok, Target} ->
            Votes = maps:get(votes, Target),
            Old = maps:get(UserId, Votes, 0),
            New = case Type of
                      upvote   -> 1;
                      downvote -> -1;
                      remove   -> 0
                  end,
            if
                Old =:= New, Type =:= remove ->
                    {{error, vote_not_found}, S};
                Old =:= New ->
                    {{error, already_voted}, S};
                true ->
                    NewVotes = case New of
                                   0 -> maps:remove(UserId, Votes);
                                   _ -> maps:put(UserId, New, Votes)
                               end,
                    Updated = Target#{votes := NewVotes},
                    Delta = New - Old,
                    Author = maps:get(user_id, Target),
                    Karma = maps:update_with(Author, fun(K) -> K + Delta end,
                                             Delta, S#state.karma),
                    S1 = case Kind of
                             post    -> S#state{posts = maps:put(Id, Updated, Coll)};
                             comment -> S#state{comments = maps:put(Id, Updated, Coll)}
                         end,
                    {{ok, vote_recorded}, S1#state{karma = Karma}}
            end
    end.

create_message(Sender, Receiver, Content, ReplyTo, S) ->
    Id = S#state.next_message,
    Msg = #{id => Id, sender_id => Sender, receiver_id => Receiver,
            content => Content, reply_to => ReplyTo,
            created_seq => S#state.sequence},
    Inbox = maps:get(Receiver, S#state.inbox, []),
    {{ok, Id}, S#state{
        messages = maps:put(Id, Msg, S#state.messages),
        inbox = maps:put(Receiver, [Id | Inbox], S#state.inbox),
        next_message = Id + 1,
        sequence = S#state.sequence + 1}}.

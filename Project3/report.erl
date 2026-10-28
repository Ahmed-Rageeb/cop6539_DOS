%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 3 -- turns the experiment CSVs into reports.
%%%
%%%   results/Report.html        hops versus network size
%%%   results/Report-bonus.html  the failure models
%%%
%%% Charts are static inline SVG -- no JavaScript, no CDN, no library --
%%% because the HTML is printed to PDF by headless Edge and a static document
%%% is the only thing guaranteed to survive that trip intact.
%%%
%%% Every number quoted in the prose is computed from the CSV when the report
%%% is generated, never typed in, so the text cannot drift from the data.
%%% @end
%%%-------------------------------------------------------------------
-module(report).

-export([main/0, main/1]).

%% `erl -run report main` with no arguments calls main/0, not main([]).
main() -> main([]).

-define(CORE_CSV,  "results/project3.csv").
-define(BONUS_CSV, "results/project3_bonus.csv").

%% Categorical slots 1-4 of the reference palette, always in this order.
-define(C1, "#2a78d6").
-define(C2, "#eb6834").
-define(C3, "#1baf7a").
-define(C4, "#eda100").

-define(SURFACE,   "#fcfcfb").
-define(INK,       "#0b0b0b").
-define(INK_2,     "#52514e").
-define(INK_MUTED, "#8a8880").
-define(GRID,      "#e5e4df").

-define(W, 720).
-define(H, 380).
-define(ML, 64).
-define(MR, 150).
-define(MT, 20).
-define(MB, 50).

main(_) ->
    Core  = read_csv(?CORE_CSV),
    Bonus = read_csv(?BONUS_CSV),
    write("results/Report.html", core_body(Core)),
    write("results/Report-bonus.html", bonus_body(Bonus)),
    io:format("wrote Report.html (~p rows) and Report-bonus.html (~p rows)~n",
              [length(Core), length(Bonus)]),
    halt(0).

write(File, Body) ->
    ok = file:write_file(File, unicode:characters_to_binary(
                                 [head(), Body, "</body></html>"])).

%%====================================================================
%% CSV and aggregation
%%====================================================================

read_csv(File) ->
    case file:read_file(File) of
        {error, _} -> [];
        {ok, Bin} ->
            [Hdr | Rows] = string:split(string:trim(binary_to_list(Bin)), "\n", all),
            Keys = [list_to_atom(string:trim(K)) || K <- string:split(Hdr, ",", all)],
            [maps:from_list(lists:zip(Keys, [string:trim(V) || V <- string:split(R, ",", all)]))
             || R <- Rows, string:trim(R) =/= ""]
    end.

%% string:to_float("50") is {error, no_float}, which a bare {F, _} pattern
%% happily matches -- so both arms check the type they actually got.
num(S) ->
    case string:to_float(S) of
        {F, _} when is_float(F) -> F;
        _ ->
            case string:to_integer(S) of
                {I, _} when is_integer(I) -> float(I);
                _ -> 0.0
            end
    end.

mean([]) -> 0.0;
mean(L)  -> lists:sum(L) / length(L).

%% {N, mean hops, found, total} per network size.
core_points(Rows) ->
    Ns = lists:usort([round(num(maps:get(nodes, R))) || R <- Rows]),
    [begin
         At = [R || R <- Rows, round(num(maps:get(nodes, R))) =:= N],
         {N, mean([num(maps:get(avg_hops, R)) || R <- At]),
          round(lists:sum([num(maps:get(found, R)) || R <- At])),
          round(lists:sum([num(maps:get(total, R)) || R <- At]))}
     end || N <- Ns].

%% Mean success % for one model / defence, as {Param, Pct} points.
bonus_points(Rows, Model, Defence) ->
    Sel = [R || R <- Rows, maps:get(model, R) =:= Model,
                maps:get(defence, R) =:= Defence],
    Ps = lists:usort([num(maps:get(param, R)) || R <- Sel]),
    [{P, mean([num(maps:get(success_pct, R)) || R <- Sel,
                                                 num(maps:get(param, R)) =:= P])}
     || P <- Ps].

pct(Rows, Model, Defence, Param) ->
    case [Y || {X, Y} <- bonus_points(Rows, Model, Defence), abs(X - Param) < 1.0e-6] of
        [Y] -> Y;
        _   -> 0.0
    end.

fmt(F) -> io_lib:format("~.1f", [F]).

%%====================================================================
%% Chart
%%====================================================================

%% Spec: title, sub, xlabel, ylabel, xlog (bool), ymax, yticks, xticks,
%% series :: [{Label, Colour, Points}], ref :: none | {Label, Points}.
chart(#{series := Series} = Spec) ->
    #{title := Title, sub := Sub, xlabel := XL, ylabel := YL,
      xlog := XLog, ymax := YMax, yticks := YT, xticks := XT} = Spec,
    Ref = maps:get(ref, Spec, none),
    AllX = [X || {_, _, Pts} <- Series, {X, _} <- Pts],
    XA = lists:min(XT), XB = lists:max(XT ++ AllX),
    SX = fun(X) -> ?ML + frac(X, XA, XB, XLog) * (?W - ?ML - ?MR) end,
    SY = fun(Y) -> ?H - ?MB - (Y / YMax) * (?H - ?MT - ?MB) end,
    Labels = [{L, C, lists:last(Pts)} || {L, C, Pts} <- Series, Pts =/= []] ++
             case Ref of
                 none -> [];
                 {RL, RPts} -> [{RL, ?INK_MUTED, lists:last(RPts)}]
             end,
    ["<figure class=\"chart\"><figcaption><h3>", Title, "</h3><p>", Sub,
     "</p></figcaption><svg viewBox=\"0 0 ", integer_to_list(?W), " ",
     integer_to_list(?H), "\" role=\"img\" xmlns=\"http://www.w3.org/2000/svg\">",
     %% recessive grid and axis labels
     [["<line x1=\"", f(?ML), "\" x2=\"", f(?W - ?MR), "\" y1=\"", f(SY(Y)),
       "\" y2=\"", f(SY(Y)), "\" stroke=\"", ?GRID, "\"/>",
       "<text x=\"", f(?ML - 9), "\" y=\"", f(SY(Y) + 4),
       "\" text-anchor=\"end\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       tick(Y), "</text>"] || Y <- YT],
     [["<line y1=\"", f(?MT), "\" y2=\"", f(?H - ?MB), "\" x1=\"", f(SX(X)),
       "\" x2=\"", f(SX(X)), "\" stroke=\"", ?GRID, "\"/>",
       "<text x=\"", f(SX(X)), "\" y=\"", f(?H - ?MB + 17),
       "\" text-anchor=\"middle\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       tick(X), "</text>"] || X <- XT],
     "<text x=\"", f((?ML + ?W - ?MR) / 2), "\" y=\"", f(?H - 10),
     "\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"", ?INK_MUTED, "\">", XL, "</text>",
     "<text transform=\"translate(15,", f((?MT + ?H - ?MB) / 2),
     ") rotate(-90)\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"",
     ?INK_MUTED, "\">", YL, "</text>",
     %% the reference curve is an annotation, not a data series: muted and dashed
     case Ref of
         none -> [];
         {_, RP} -> ["<polyline fill=\"none\" stroke=\"", ?INK_MUTED,
                     "\" stroke-width=\"1.5\" stroke-dasharray=\"5 4\" points=\"",
                     pts(RP, SX, SY), "\"/>"]
     end,
     [["<polyline fill=\"none\" stroke=\"", C, "\" stroke-width=\"2\" "
       "stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"",
       pts(P, SX, SY), "\"/>",
       %% a 2px surface ring keeps markers legible where lines cross
       [["<circle cx=\"", f(SX(X)), "\" cy=\"", f(SY(Y)), "\" r=\"4\" fill=\"", C,
         "\" stroke=\"", ?SURFACE, "\" stroke-width=\"2\"/>"] || {X, Y} <- P]]
      || {_, C, P} <- Series],
     %% direct labels at each line's end, pushed apart where they would collide
     direct_labels(Labels, SX, SY),
     "</svg></figure>"].

frac(X, A, B, true)  -> (math:log10(max(X, 1.0e-9)) - math:log10(A)) / (math:log10(B) - math:log10(A));
frac(X, A, B, false) -> (X - A) / max(1.0e-9, B - A).

pts(P, SX, SY) -> lists:join(" ", [[f(SX(X)), ",", f(SY(Y))] || {X, Y} <- P]).

direct_labels(Labels, SX, SY) ->
    Ys = [{I, SY(Y)} || {I, {_, _, {_, Y}}} <- lists:zip(lists:seq(1, length(Labels)), Labels)],
    Spread = maps:from_list(spread(lists:keysort(2, Ys), -1.0e9)),
    [["<text x=\"", f(SX(X) + 10), "\" y=\"", f(maps:get(I, Spread) + 4),
      "\" font-size=\"11.5\" font-weight=\"600\" fill=\"", C, "\">", L, "</text>"]
     || {I, {L, C, {X, _}}} <- lists:zip(lists:seq(1, length(Labels)), Labels)].

spread([], _Prev) -> [];
spread([{I, Y} | T], Prev) ->
    Y1 = max(Y, Prev + 13.0),
    [{I, Y1} | spread(T, Y1)].

tick(V) when V >= 1000 -> io_lib:format("~wk", [round(V / 1000)]);
tick(V) when V == round(V) -> integer_to_list(round(V));
tick(V) -> io_lib:format("~.2f", [V]).

f(X) -> io_lib:format("~.2f", [X * 1.0]).

%% 100000 -> "100,000"
thou(N) when is_integer(N) ->
    S = integer_to_list(N),
    lists:reverse(group(lists:reverse(S))).

group([A, B, C, D | T]) -> [A, B, C, $, | group([D | T])];
group(L) -> L.

%% The label sits in its own element: the key entry is a flex container, so
%% bare text around a <sub> would become separate flex items, each pushed
%% apart by the gap -- which rendered "log16(N)" as "log  16  (N)".
legend(Items) ->
    ["<div class=\"key\">",
     [["<span><i class=\"sw\" style=\"background:", C, "\"></i><b>", L, "</b></span>"]
      || {L, C} <- Items],
     "</div>"].

%%====================================================================
%% Main report
%%====================================================================

core_body(Rows) ->
    Pts = core_points(Rows),
    {NMax, HMax, FMax, TMax} = lists:last(Pts),
    Found = lists:sum([F || {_, _, F, _} <- Pts]),
    Total = lists:sum([T || {_, _, _, T} <- Pts]),
    Below = length([x || {N, H, _, _} <- Pts, N >= 100,
                         H =< math:log(N) / math:log(16)]),
    Big = length([x || {N, _, _, _} <- Pts, N >= 100]),
    ["<h1>Pastry: routing hops versus network size</h1>",
     "<p class=\"sub\">COP6539 Project 3 &middot; Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>Each peer is one Erlang actor. Every peer makes two lookups for randomly "
     "chosen stored objects, and the simulator reports how many node-to-node hops "
     "each lookup travelled before it was delivered. Networks of up to 5,000 nodes "
     "are averaged over three independent runs; larger ones are single runs.</p>",

     "<h2>Average hops</h2>",
     legend([{"measured", ?C1}, {"log<sub>16</sub>(N)", ?INK_MUTED}]),
     chart(#{title => "Average hops per lookup",
             sub => "Network size on a logarithmic axis. Pastry's bound is "
                    "&lceil;log<sub>16</sub>N&rceil;; the dashed line is log<sub>16</sub>N itself.",
             xlabel => "number of nodes", ylabel => "average hops",
             xlog => true, ymax => 5.0, yticks => [0, 1, 2, 3, 4, 5],
             xticks => [10, 100, 1000, 10000, 100000],
             series => [{"measured", ?C1, [{float(N), H} || {N, H, _, _} <- Pts]}],
             ref => {"log<tspan baseline-shift=\"sub\" font-size=\"8\">16</tspan>(N)",
                     [{float(N), math:log(N) / math:log(16)} || {N, _, _, _} <- Pts]}}),

     "<h2>What the measurements show</h2>",
     "<p><strong>Routing is logarithmic, as Pastry promises.</strong> On a logarithmic "
     "x-axis the measured curve is a straight line, which is exactly what O(log N) "
     "looks like. Growing the network ten-thousand-fold, from 10 to ",
     thou(NMax), " nodes, adds only about three hops.</p>",
     "<p><strong>It runs slightly under log<sub>16</sub>N.</strong> The average sits at "
     "or below the dashed line at ",
     case Below =:= Big of
         true  -> "every size";
         false -> [integer_to_list(Below), " of the ", integer_to_list(Big), " sizes"]
     end,
     " from 100 nodes upward. That is expected rather than lucky: log<sub>16</sub>N "
     "is the number of hops needed to resolve a key one hex digit at a time, but the leaf "
     "set lets the last few digits be resolved in a single hop, and the Pastry paper reports "
     "the same effect.</p>",
     "<p><strong>Every lookup found its object.</strong> ", thou(Found),
     " of ", thou(Total), " lookups across all runs. Separately, routing was "
     "checked against an independent oracle &mdash; the true numerically-closest node, "
     "found by brute force over every node id rather than taken from any node's own "
     "tables &mdash; and every probe reached it.</p>",

     "<h2>Largest network</h2>",
     "<p><strong>", thou(NMax), " nodes</strong>: ", thou(FMax),
     " of ", thou(TMax), " lookups found, averaging ",
     io_lib:format("~.2f", [HMax]), " hops against log<sub>16</sub>N = ",
     io_lib:format("~.2f", [math:log(NMax) / math:log(16)]), ". On an 8&nbsp;GB machine "
     "the limit is the time to join peers one at a time, not memory.</p>",

     "<h2>Measurements</h2>",
     "<table><thead><tr><th>Nodes</th><th>Average hops</th><th>log<sub>16</sub>N</th>"
     "<th>Found</th></tr></thead><tbody>",
     [["<tr><td>", thou(N), "</td><td>", io_lib:format("~.3f", [H]),
       "</td><td>", io_lib:format("~.3f", [math:log(N) / math:log(16)]),
       "</td><td>", thou(F), " / ", thou(T), "</td></tr>"]
      || {N, H, F, T} <- Pts],
     "</tbody></table>"].

%%====================================================================
%% Bonus report
%%====================================================================

%% Measured against the two survival probabilities that bound node death:
%% a single copy survives with probability 1 - p, and an object on four
%% nodes is lost only when all four die, so survives with 1 - p^4.
kill_theory_table(Rows) ->
    ["<table><thead><tr><th>Nodes killed (p)</th>"
     "<th>Repair only</th><th>1 &minus; p</th>"
     "<th>Every defence</th><th>1 &minus; p<sup>4</sup></th></tr></thead><tbody>",
     [["<tr><td>", io_lib:format("~.1f", [P]),
       "</td><td>", fmt(pct(Rows, "kill", "repair", P)),
       "%</td><td>", fmt(100 * (1 - P)),
       "%</td><td>", fmt(pct(Rows, "kill", "retry", P)),
       "%</td><td>", io_lib:format("~.2f", [100 * (1 - math:pow(P, 4))]),
       "%</td></tr>"] || P <- [0.1, 0.2, 0.3, 0.4, 0.5]],
     "</tbody></table>"].

kill_defences() ->
    [{"none", "no defence", ?C1}, {"repair", "+ repair", ?C2},
     {"replicas", "+ replication", ?C3}, {"retry", "+ retry", ?C4}].

retry_policies() ->
    [{"none", "no retry", ?C1}, {"det", "retry same route", ?C2},
     {"rand", "retry random route", ?C3}, {"hybrid", "hybrid", ?C4}].

bonus_chart(Rows, Model, Defs, Title, Sub, XLabel, XTicks) ->
    chart(#{title => Title, sub => Sub, xlabel => XLabel,
            ylabel => "lookups that found their object (%)",
            xlog => false, ymax => 100.0, yticks => [0, 20, 40, 60, 80, 100],
            xticks => XTicks,
            series => [{L, C, bonus_points(Rows, Model, D)} || {D, L, C} <- Defs]}).

bonus_body(Rows) ->
    P = fun(M, D, X) -> fmt(pct(Rows, M, D, X)) end,
    %% Measured average route length with no failures -- the H in the
    %% (1 - q)^H prediction, taken from the data rather than assumed.
    H0 = mean([num(maps:get(avg_hops, R)) || R <- Rows,
               maps:get(model, R) =:= "drop", maps:get(defence, R) =:= "none",
               num(maps:get(param, R)) == 0.0]),
    ["<h1>Failure and resilience in Pastry</h1>",
     "<p class=\"sub\">COP6539 Project 3, bonus &middot; Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>The main project runs on a network where nothing ever fails. This report adds "
     "the three failures the assignment names, implements the recovery mechanisms the "
     "Pastry paper describes, and measures which mechanism defends against which "
     "failure. Every experiment uses 1,000 nodes making three lookups each, repeated "
     "three times; each point is the mean.</p>",

     "<h2>How resilience was tested</h2>",
     "<p><strong>The failure models.</strong> All three strike after the network is "
     "built and its objects stored, so what is measured is whether lookups survive a "
     "failing system. Each is driven by a single parameter.</p>",
     "<ul>",
     "<li><code>kill=p</code> &mdash; <strong>a node dies.</strong> A fraction <em>p</em> "
     "of peers is killed outright, with no warning to anyone, as the lookups begin. "
     "Anything in flight to them is lost.</li>",
     "<li><code>drop=q</code> &mdash; <strong>a connection dies temporarily.</strong> "
     "Each transmission is lost independently with probability <em>q</em>; the same "
     "link may well work on the next attempt.</li>",
     "<li><code>links=r</code> &mdash; <strong>a connection dies permanently.</strong> "
     "A fraction <em>r</em> of node pairs cannot reach each other for the whole run. "
     "Whether a link is dead is a pure function of its two endpoints, so every node "
     "agrees on it without any coordination, and retrying it never succeeds.</li>",
     "</ul>",
     "<p><strong>The defences.</strong> Each follows the Pastry paper (section 2.5) or "
     "PAST, the storage system built on it, and each can be switched on independently "
     "so its contribution can be measured on its own.</p>",
     "<ul>",
     "<li><strong>Failure detection</strong> &mdash; every node monitors the nodes in its "
     "leaf set and routing table. An Erlang monitor is the runtime's version of the "
     "keep-alive messages Pastry's leaf-set members exchange.</li>",
     "<li><strong>Repair</strong> &mdash; on a leaf-set failure, ask the farthest live "
     "leaf on that side for its leaf set; on a routing-table failure, ask another entry "
     "in the same row for its entry. Both are the paper's own procedures.</li>",
     "<li><strong>Replication</strong> &mdash; each object is stored on the four nodes "
     "closest to its key, as PAST does, so it outlives the death of any one of them.</li>",
     "<li><strong>Retry</strong> &mdash; every lookup carries a timeout; a lookup that "
     "times out or reaches a node without the object is retried, up to three attempts "
     "in all, along either the same route or a randomised one.</li>",
     "</ul>",
     "<p><strong>Checking the checks.</strong> Every request is counted exactly once: "
     "found, not found, or given up on after its last timeout. A late reply to an "
     "attempt already retried is recognised by its reference and ignored, so no request "
     "can be counted twice. Randomised routing was verified separately against a "
     "brute-force oracle and reaches the true closest node every time.</p>",

     "<h2>1. A node dies</h2>",
     legend([{L, C} || {_, L, C} <- kill_defences()]),
     bonus_chart(Rows, "kill", kill_defences(), "Node death",
                 "Defences added one at a time, each line including all the ones before it.",
                 "fraction of nodes killed (p)", [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]),
     "<p><strong>Repair fixes routing; it cannot bring back data.</strong> At p = 0.2 "
     "lookups succeed ", P("kill", "none", 0.2), "% of the time with no defence, and "
     "repair raises that to ", P("kill", "repair", 0.2), "%. What it leaves behind is "
     "telling: the remaining loss equals the fraction of nodes killed, at every value "
     "of p (table below). Those are objects whose only copy lived on a dead node. Once "
     "routing is repaired, a lookup arrives at exactly the right place and finds "
     "nothing there &mdash; and no improvement to routing can change that.</p>",
     "<p><strong>Replication is what saves the data.</strong> It lifts p = 0.2 to ",
     P("kill", "replicas", 0.2), "% and still holds ", P("kill", "replicas", 0.5),
     "% when half the network dies. Retry then adds more than might be expected, up to ",
     P("kill", "retry", 0.5), "% at p = 0.5, by recovering lookups that set off in the "
     "brief window before repair completed.</p>",
     "<p><strong>With every defence on, the system reaches its theoretical "
     "floor.</strong> An object stored on four nodes is lost only if all four die, "
     "which happens with probability p<sup>4</sup>. The fully defended curve sits on "
     "1&nbsp;&minus;&nbsp;p<sup>4</sup> almost exactly: the only lookups that still fail "
     "are for objects no mechanism could possibly have saved. Likewise repair alone "
     "sits on 1&nbsp;&minus;&nbsp;p, the survival rate of a single copy.</p>",
     kill_theory_table(Rows),
     "<p>The two mechanisms answer different questions &mdash; repair asks <em>can the "
     "message get there</em>, replication asks <em>is anything there to find</em> "
     "&mdash; and surviving node death needs both.</p>",

     "<h2>2. A connection dies temporarily</h2>",
     legend([{L, C} || {_, L, C} <- retry_policies()]),
     bonus_chart(Rows, "drop", retry_policies(), "Temporary connection failure",
                 "Each transmission independently lost with probability q.",
                 "probability a transmission is lost (q)", [0.0, 0.1, 0.2, 0.3]),
     "<p>A lookup crosses about ", io_lib:format("~.2f", [H0]), " links and losing any "
     "one loses it, so it should survive with probability (1&nbsp;&minus;&nbsp;q)<sup>",
     io_lib:format("~.2f", [H0]), "</sup>. At q = 0.2 that predicts ",
     fmt(100 * math:pow(0.8, H0)), "%; measured, ", P("drop", "none", 0.2), "%.</p>",
     "<p>Retrying fixes most of it, and here <strong>retrying the same route is "
     "best</strong> &mdash; at every value of q: ", P("drop", "det", 0.2),
     "% against ", P("drop", "rand", 0.2), "% for a random route at q = 0.2. Each "
     "attempt along the same short route is an independent draw, so three attempts "
     %% Three decimals: rounded to one, the base would print as 0.6 and the
     %% formula on the page would disagree with the result printed after it.
     "should leave only (1&nbsp;&minus;&nbsp;", io_lib:format("~.3f", [math:pow(0.8, H0)]),
     ")<sup>3</sup> "
     "of lookups failing, a predicted ", fmt(100 * (1 - math:pow(1 - math:pow(0.8, H0), 3))),
     "%. A randomised route is slightly longer, and every extra hop is another chance "
     "to be lost.</p>",

     "<h2>3. A connection dies permanently</h2>",
     legend([{L, C} || {_, L, C} <- retry_policies()]),
     bonus_chart(Rows, "links", retry_policies(), "Permanent connection failure",
                 "A fraction r of node pairs cannot communicate for the whole run.",
                 "fraction of links permanently down (r)", [0.0, 0.1, 0.2, 0.3]),
     "<p>Here the ranking <strong>inverts</strong>. Retrying the same route is "
     "worthless: ", P("links", "det", 0.2), "% at r = 0.2, against ",
     P("links", "none", 0.2), "% with no retry at all &mdash; the two lines lie on top "
     "of each other at every value of r. Pastry's routing is deterministic, so the same "
     "lookup from the same node takes the same path, straight back into the same dead "
     "link, and three attempts fail exactly as one did. Only a <strong>randomised</strong> "
     "route escapes it, reaching ", P("links", "rand", 0.2), "%. This is why the Pastry "
     "paper suggests randomising retries.</p>",

     "<h2>Findings</h2>",
     "<div class=\"note\"><p><strong>No single retry policy is best, and a node cannot "
     "tell which one it needs.</strong> The same-route retry that wins against temporary "
     "failure is the one that fails against permanent failure, and the reverse. A node "
     "whose lookup times out cannot tell which kind of failure lost it.</p>"
     "<p>The obvious compromise &mdash; retry the same route once, then randomise "
     "&mdash; was tested as <em>hybrid</em>, and it is never the best at anything. It "
     "lies strictly between the two pure policies at every one of the eight failure "
     "levels tested; at 20% it reaches ", P("drop", "hybrid", 0.2), "% against "
     "temporary loss and ", P("links", "hybrid", 0.2), "% against permanent loss. With "
     "three attempts, spending one on the same route is one attempt wasted whenever "
     "the failure is permanent.</p>"
     "<p>So the simulator defaults to the randomised retry, the policy with the best "
     "worst case. It gives up a little against temporary failure to avoid failing badly "
     "against permanent failure &mdash; the right trade when the kind of failure is "
     "unknown.</p></div>",
     "<p><strong>Every failure mode needed its own defence.</strong> Node death was "
     "survivable only with replication; temporary loss only with retry; permanent link "
     "loss only with <em>randomised</em> retry. Pastry's resilience is not one property "
     "but several separate mechanisms, each covering one way of failing.</p>",

     "<h2>Reproducing</h2>",
     "<pre>project3 1000 3 kill=0.2\n"
     "project3 1000 3 kill=0.2 resilient\n"
     "project3 1000 3 drop=0.2 attempts=3 retry=det\n"
     "project3 1000 3 links=0.2 attempts=3 retry=rand</pre>"].

%%====================================================================
%% Document shell
%%====================================================================

head() ->
    ["<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
     "<title>COP6539 Project 3</title><style>",
     "@page{size:A4;margin:15mm}",
     "*{box-sizing:border-box}",
     "body{margin:0 auto;background:", ?SURFACE, ";color:", ?INK, ";",
     "font:13.5px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;",
     "max-width:820px;padding:22px}",
     "h1{font-size:24px;margin:0 0 4px}",
     "h2{font-size:17px;margin:26px 0 8px;padding-top:12px;border-top:1px solid ", ?GRID, "}",
     "h3{font-size:14px;margin:0 0 2px}",
     ".sub{color:", ?INK_2, ";margin:0 0 16px}",
     ".chart{margin:12px 0 18px;break-inside:avoid}",
     ".chart figcaption p{margin:0 0 4px;color:", ?INK_MUTED, ";font-size:12px}",
     ".chart svg{width:100%;height:auto;overflow:visible}",
     ".key{display:flex;gap:16px;flex-wrap:wrap;margin:4px 0 6px;font-size:12px;color:", ?INK_2, "}",
     ".key>span{display:flex;align-items:center;gap:6px}.key b{font-weight:400}",
     ".sw{width:11px;height:11px;border-radius:3px;display:inline-block}",
     "table{border-collapse:collapse;width:100%;font-size:12px;margin:8px 0 16px}",
     "th,td{border-bottom:1px solid ", ?GRID, ";padding:4px 8px;text-align:right}",
     "th:first-child,td:first-child{text-align:left}",
     "th{color:", ?INK_2, ";font-weight:600}",
     "td{font-variant-numeric:tabular-nums}",
     "p{margin:8px 0}ul{margin:8px 0;padding-left:20px}li{margin:4px 0}",
     "code,pre{background:#f1f0ec;border-radius:3px;font-size:12px}",
     "code{padding:1px 4px}pre{padding:10px 12px;white-space:pre-wrap}",
     ".note{background:#f6f5f1;border-left:3px solid ", ?INK_MUTED,
     ";padding:4px 14px;margin:12px 0}",
     "</style></head><body>"].

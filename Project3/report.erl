%% Makes results/Report.html and results/Report-bonus.html from the CSVs.
%% report.bat then prints them to PDF with Edge. The charts are plain SVG so
%% they print without any JavaScript. Numbers in the text come from the CSV.
-module(report).

-export([main/0, main/1]).

%% erl -run with no arguments calls main/0
main() -> main([]).

-define(CORE_CSV,  "results/project3.csv").
-define(BONUS_CSV, "results/project3_bonus.csv").

%% series colours, always used in this order
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

read_csv(File) ->
    case file:read_file(File) of
        {error, _} -> [];
        {ok, Bin} ->
            [Hdr | Rows] = string:split(string:trim(binary_to_list(Bin)), "\n", all),
            Keys = [list_to_atom(string:trim(K)) || K <- string:split(Hdr, ",", all)],
            [maps:from_list(lists:zip(Keys, [string:trim(V) || V <- string:split(R, ",", all)]))
             || R <- Rows, string:trim(R) =/= ""]
    end.

%% string:to_float("50") returns {error, no_float}, so check the type
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

%% Line chart. Spec has title, sub, xlabel, ylabel, xlog, ymax, yticks,
%% xticks, series [{Label, Colour, Points}] and an optional ref line.
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
     %% grid and axis labels
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
     %% reference line, drawn dashed in grey
     case Ref of
         none -> [];
         {_, RP} -> ["<polyline fill=\"none\" stroke=\"", ?INK_MUTED,
                     "\" stroke-width=\"1.5\" stroke-dasharray=\"5 4\" points=\"",
                     pts(RP, SX, SY), "\"/>"]
     end,
     [["<polyline fill=\"none\" stroke=\"", C, "\" stroke-width=\"2\" "
       "stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"",
       pts(P, SX, SY), "\"/>",
       %% white ring around markers so they stay visible where lines cross
       [["<circle cx=\"", f(SX(X)), "\" cy=\"", f(SY(Y)), "\" r=\"4\" fill=\"", C,
         "\" stroke=\"", ?SURFACE, "\" stroke-width=\"2\"/>"] || {X, Y} <- P]]
      || {_, C, P} <- Series],
     %% labels at the end of each line, moved apart if they overlap
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

%% Label goes in its own element, otherwise the flex gap splits text around
%% a <sub> (log16(N) showed up as "log 16 (N)").
legend(Items) ->
    ["<div class=\"key\">",
     [["<span><i class=\"sw\" style=\"background:", C, "\"></i><b>", L, "</b></span>"]
      || {L, C} <- Items],
     "</div>"].

core_body(Rows) ->
    Pts = core_points(Rows),
    {NMax, HMax, FMax, TMax} = lists:last(Pts),
    Found = lists:sum([F || {_, _, F, _} <- Pts]),
    Total = lists:sum([T || {_, _, _, T} <- Pts]),
    Below = length([x || {N, H, _, _} <- Pts, N >= 100,
                         H =< math:log(N) / math:log(16)]),
    Big = length([x || {N, _, _, _} <- Pts, N >= 100]),
    ["<h1>Pastry: routing hops versus network size</h1>",
     "<p class=\"sub\">COP6539 Project 3. Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>Each peer is an Erlang actor. Every peer makes two lookups for random "
     "stored objects, and we count how many hops each lookup takes before it is "
     "delivered. Networks of up to 5,000 nodes are averaged over three runs, the "
     "larger ones are a single run.</p>",

     "<h2>Average hops</h2>",
     legend([{"measured", ?C1}, {"log<sub>16</sub>(N)", ?INK_MUTED}]),
     chart(#{title => "Average hops per lookup",
             sub => "Number of nodes is on a log scale. The dashed line is "
                    "log<sub>16</sub>N, the expected number of hops.",
             xlabel => "number of nodes", ylabel => "average hops",
             xlog => true, ymax => 5.0, yticks => [0, 1, 2, 3, 4, 5],
             xticks => [10, 100, 1000, 10000, 100000],
             series => [{"measured", ?C1, [{float(N), H} || {N, H, _, _} <- Pts]}],
             ref => {"log<tspan baseline-shift=\"sub\" font-size=\"8\">16</tspan>(N)",
                     [{float(N), math:log(N) / math:log(16)} || {N, _, _, _} <- Pts]}}),

     "<h2>Results</h2>",
     "<p>The number of hops grows with log N, which is what Pastry is supposed to "
     "give. Since the x axis is on a log scale, this shows up as a straight line. "
     "Going from 10 nodes to ",
     thou(NMax), " nodes only adds about three hops.</p>",
     "<p>From 100 nodes up, the average is at or a little below log<sub>16</sub>N "
     "at ",
     case Below =:= Big of
         true  -> "every size";
         false -> [integer_to_list(Below), " of the ", integer_to_list(Big), " sizes"]
     end,
     ". This makes sense because log<sub>16</sub>N assumes we fix one hex digit "
     "per hop, but once the key is in range of the leaf set the last few digits are "
     "done in a single hop. The Pastry paper reports the same thing.</p>",
     "<p>All lookups found their object, ", thou(Found),
     " out of ", thou(Total), " over all runs. We also tested the routing on its "
     "own. For each test key we found the closest node by checking every node id, "
     "and every lookup ended at that node.</p>",

     "<h2>Largest network</h2>",
     "<p>The largest network we ran had ", thou(NMax), " nodes. ", thou(FMax),
     " out of ", thou(TMax), " lookups were found, with an average of ",
     io_lib:format("~.2f", [HMax]), " hops (log<sub>16</sub>N = ",
     io_lib:format("~.2f", [math:log(NMax) / math:log(16)]), "). On our 8&nbsp;GB "
     "laptop the limit was the time it takes to join the nodes one by one, not "
     "memory.</p>",

     "<h2>Measurements</h2>",
     "<table><thead><tr><th>Nodes</th><th>Average hops</th><th>log<sub>16</sub>N</th>"
     "<th>Found</th></tr></thead><tbody>",
     [["<tr><td>", thou(N), "</td><td>", io_lib:format("~.3f", [H]),
       "</td><td>", io_lib:format("~.3f", [math:log(N) / math:log(16)]),
       "</td><td>", thou(F), " / ", thou(T), "</td></tr>"]
      || {N, H, F, T} <- Pts],
     "</tbody></table>"].

%% Compare with theory: one copy survives with probability 1 - p, and an
%% object with four copies survives unless all four die, 1 - p^4.
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
    %% average hops with no failures, used for the (1 - q)^H estimate
    H0 = mean([num(maps:get(avg_hops, R)) || R <- Rows,
               maps:get(model, R) =:= "drop", maps:get(defence, R) =:= "none",
               num(maps:get(param, R)) == 0.0]),
    ["<h1>Failure and resilience in Pastry</h1>",
     "<p class=\"sub\">COP6539 Project 3, bonus. Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>In the main project nothing ever fails. For the bonus we added the three "
     "failures from the assignment, implemented the recovery methods described in the "
     "Pastry paper, and measured which method helps against which failure. All "
     "experiments use 1,000 nodes that each make three lookups. Every point is the "
     "average of three runs.</p>",

     "<h2>How we tested resilience</h2>",
     "<p><b>Failure models.</b> All three start after the network is built and the "
     "objects are stored, so we are measuring whether lookups still work while things "
     "fail. Each one is controlled by one parameter.</p>",
     "<ul>",
     "<li><code>kill=p</code>: <b>a node dies.</b> A fraction <em>p</em> of the "
     "peers is killed with no warning when the lookups start. Any message on its way "
     "to them is lost.</li>",
     "<li><code>drop=q</code>: <b>a connection dies temporarily.</b> Each message "
     "is lost with probability <em>q</em>, so the same link can work on the next "
     "try.</li>",
     "<li><code>links=r</code>: <b>a connection dies permanently.</b> A fraction "
     "<em>r</em> of node pairs can never reach each other. We decide this by hashing "
     "the two node ids, so all nodes agree on it without sharing anything, and a dead "
     "link stays dead on every retry.</li>",
     "</ul>",
     "<p><b>Defences.</b> These follow section 2.5 of the Pastry paper, plus "
     "replication from PAST. Each one can be turned on separately so we can see what "
     "it adds.</p>",
     "<ul>",
     "<li><b>Failure detection:</b> each node monitors the nodes in its leaf set and "
     "routing table. We use Erlang monitors for this instead of the keep-alive "
     "messages in the paper.</li>",
     "<li><b>Repair:</b> when a leaf set node fails, ask the farthest live leaf on "
     "that side for its leaf set. When a routing table entry fails, ask another node "
     "in the same row for its entry. Both come from the paper.</li>",
     "<li><b>Replication:</b> each object is stored on the four nodes closest to its "
     "key, like PAST does, so it survives if one of them dies.</li>",
     "<li><b>Retry:</b> each lookup has a timeout. If it times out, or reaches a node "
     "that doesn't have the object, it is retried up to three times in total, either "
     "on the same route or on a random one.</li>",
     "</ul>",
     "<p>Each request is counted exactly once, as found, not found, or failed after "
     "its last timeout. If a late reply comes back for an attempt we already retried, "
     "we ignore it, so nothing is counted twice. We also checked the random routing "
     "against the brute force closest node, and it always reached the right one.</p>",

     "<h2>1. A node dies</h2>",
     legend([{L, C} || {_, L, C} <- kill_defences()]),
     bonus_chart(Rows, "kill", kill_defences(), "Node death",
                 "Each line includes the defences of the lines before it.",
                 "fraction of nodes killed (p)", [0.0, 0.1, 0.2, 0.3, 0.4, 0.5]),
     "<p><b>Repair fixes the routing but can't bring back lost data.</b> At p = 0.2, ",
     P("kill", "none", 0.2), "% of lookups succeed with no defence, and repair "
     "brings this up to ", P("kill", "repair", 0.2), "%. The loss that remains is "
     "about the same as the fraction of nodes killed, at every value of p (see the "
     "table below). These are objects whose only copy was on a node that died. After "
     "repair the lookup goes to the right node, but the object is not there, and "
     "better routing can't fix that.</p>",
     "<p><b>Replication is what keeps the data.</b> With it, p = 0.2 goes up to ",
     P("kill", "replicas", 0.2), "%, and it is still ", P("kill", "replicas", 0.5),
     "% when half of the nodes die. Adding retry helps more than we expected, up to ",
     P("kill", "retry", 0.5), "% at p = 0.5. It catches lookups that were sent in the "
     "short time before repair finished.</p>",
     "<p><b>With all defences on, we get close to the best possible result.</b> An "
     "object with four copies is only lost if all four nodes die, which happens with "
     "probability p<sup>4</sup>. The measured curve is very close to "
     "1&nbsp;&minus;&nbsp;p<sup>4</sup>, so the lookups that still fail are for objects "
     "that could not have been saved. In the same way, repair alone follows "
     "1&nbsp;&minus;&nbsp;p, which is the chance that a single copy survives.</p>",
     kill_theory_table(Rows),
     "<p>So repair and replication solve two different problems. Repair makes sure "
     "the message can get to the right node, and replication makes sure the object "
     "is still there. To handle node death we need both.</p>",

     "<h2>2. A connection dies temporarily</h2>",
     legend([{L, C} || {_, L, C} <- retry_policies()]),
     bonus_chart(Rows, "drop", retry_policies(), "Temporary connection failure",
                 "Each message is lost with probability q.",
                 "probability a message is lost (q)", [0.0, 0.1, 0.2, 0.3]),
     "<p>A lookup takes about ", io_lib:format("~.2f", [H0]), " hops, and if any of "
     "them is lost the lookup fails. So we expect it to succeed with probability "
     "(1&nbsp;&minus;&nbsp;q)<sup>",
     io_lib:format("~.2f", [H0]), "</sup>. For q = 0.2 that gives ",
     fmt(100 * math:pow(0.8, H0)), "%, and we measured ", P("drop", "none", 0.2), "%.</p>",
     "<p>Retrying fixes most of this, and here <b>retrying on the same route works "
     "best</b>, for every value of q. At q = 0.2 it gets ", P("drop", "det", 0.2),
     "%, against ", P("drop", "rand", 0.2), "% for a random route. Each try on the "
     "same route fails independently, so after three tries we expect "
     %% 3 decimals, with 1 it shows 0.6 and the formula looks wrong
     "(1&nbsp;&minus;&nbsp;", io_lib:format("~.3f", [math:pow(0.8, H0)]),
     ")<sup>3</sup> "
     "of lookups to fail, which predicts ", fmt(100 * (1 - math:pow(1 - math:pow(0.8, H0), 3))),
     "%. A random route is a bit longer, and every extra hop is another chance to "
     "lose the message.</p>",

     "<h2>3. A connection dies permanently</h2>",
     legend([{L, C} || {_, L, C} <- retry_policies()]),
     bonus_chart(Rows, "links", retry_policies(), "Permanent connection failure",
                 "A fraction r of node pairs can never communicate.",
                 "fraction of links that are dead (r)", [0.0, 0.1, 0.2, 0.3]),
     "<p>Here it is the other way around. Retrying on the same route does not help "
     "at all: ", P("links", "det", 0.2), "% at r = 0.2, compared to ",
     P("links", "none", 0.2), "% with no retry. The two lines are on top of each "
     "other for every value of r. Pastry always picks the same next hop for a key, "
     "so a retry from the same node goes the same way and hits the same dead link "
     "again. Only a <b>random</b> route gets around it, and that gets ",
     P("links", "rand", 0.2), "%. This is why the Pastry paper suggests randomizing "
     "the route when retrying.</p>",

     "<h2>Conclusion</h2>",
     "<div class=\"note\"><p><b>No retry policy is best for both kinds of connection "
     "failure, and a node can't tell which one it is dealing with.</b> Retrying on the "
     "same route is best for temporary failures but useless for permanent ones, and "
     "the random route is the opposite. When a lookup times out, the node doesn't know "
     "which kind of failure caused it.</p>"
     "<p>We also tried a mix, called <em>hybrid</em> in the charts: retry the same "
     "route once, then use random routes. It was never the best. It was always "
     "between the other two, at all eight failure levels we tested. At 20% it got ",
     P("drop", "hybrid", 0.2), "% for temporary failures and ", P("links", "hybrid", 0.2),
     "% for permanent ones. With only three attempts, using one on the same route "
     "wastes it when the link is dead for good.</p>"
     "<p>Because of this the program uses random routes for retries by default. It "
     "has the best worst case: it loses a little on temporary failures but does much "
     "better on permanent ones, which is what we want when we don't know the type of "
     "failure.</p></div>",
     "<p>Overall, each type of failure needed its own fix. Node death needed "
     "replication, temporary connection failures needed retry, and permanent "
     "connection failures needed retry with a <em>random</em> route.</p>",

     "<h2>How to reproduce</h2>",
     "<pre>project3 1000 3 kill=0.2\n"
     "project3 1000 3 kill=0.2 resilient\n"
     "project3 1000 3 drop=0.2 attempts=3 retry=det\n"
     "project3 1000 3 links=0.2 attempts=3 retry=rand</pre>"].

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

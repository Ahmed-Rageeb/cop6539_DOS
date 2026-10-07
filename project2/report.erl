%%%-------------------------------------------------------------------
%%% @doc COP6539 Project 2 -- turns the experiment CSVs into Report.html.
%%%
%%% Charts are emitted as static inline SVG: no JavaScript, no CDN, no
%%% chart library. The output is printed to PDF by headless Edge, and a
%%% static document is the only thing guaranteed to survive that trip
%%% intact.
%%%
%%% Chart design follows the project's data-viz guidance:
%%%   * log-log axes (the assignment suggests log scales; convergence time
%%%     spans four orders of magnitude across topologies)
%%%   * four categorical hues taken in fixed slot order, never cycled
%%%   * 2px lines, >=8px markers with a 2px surface ring
%%%   * every series carries a direct label as well as a legend, so series
%%%     identity never depends on colour alone
%%%   * recessive grid and axes; data ink is the only saturated ink
%%% @end
%%%-------------------------------------------------------------------
-module(report).

-export([main/0, main/1, generate/1]).

-define(CSV, "../results/project2.csv").
-define(BONUS_CSV, "../results/project2_bonus.csv").
-define(OUT, "../results/Report.html").

%% Categorical slots 1-4 of the reference palette, in fixed order.
-define(SERIES_COLOURS, [{full,   "#2a78d6"},
                         {'2D',   "#eb6834"},
                         {line,   "#1baf7a"},
                         {imp2D,  "#eda100"}]).

-define(SURFACE,   "#fcfcfb").
-define(INK,       "#0b0b0b").
-define(INK_2,     "#52514e").
-define(INK_MUTED, "#8a8880").
-define(GRID,      "#e5e4df").

-define(W, 720).
-define(H, 400).
-define(ML, 74).
-define(MR, 124).
-define(MT, 26).
-define(MB, 52).

main() -> main([]).
main(["bonus"]) -> generate(bonus), halt(0);
main(_) -> generate(core), generate(bonus), halt(0).

generate(Mode) ->
    Core  = read_csv(?CSV),
    Bonus = read_csv(?BONUS_CSV),
    {Out, Body} =
        case Mode of
            core  -> {"../results/Report.html", body(Core, [])};
            bonus -> {"../results/Report-bonus.html", bonus_body(Bonus)}
        end,
    Html = [head(), Body, "</body></html>"],
    ok = file:write_file(Out, unicode:characters_to_binary(Html)),
    io:format("wrote ~s (~p core rows, ~p bonus rows)~n",
              [Out, length(Core), length(Bonus)]).

%%====================================================================
%% CSV
%%====================================================================

read_csv(File) ->
    case file:read_file(File) of
        {error, _} -> [];
        {ok, Bin} ->
            [Hdr | Rows] = string:split(string:trim(binary_to_list(Bin)), "\n", all),
            Keys = [list_to_atom(string:trim(K)) || K <- string:split(Hdr, ",", all)],
            [maps:from_list(lists:zip(Keys, [string:trim(V)
                                             || V <- string:split(R, ",", all)]))
             || R <- Rows, string:trim(R) =/= ""]
    end.

%% string:to_float("50") returns {error, no_float}, which a bare {F, _}
%% pattern will happily match -- binding F to the atom `error'. Both arms
%% must check the type they actually got.
num(S) ->
    case string:to_float(S) of
        {F, _} when is_float(F) -> F;
        _ ->
            case string:to_integer(S) of
                {I, _} when is_integer(I) -> I * 1.0;
                _ -> 0.0
            end
    end.

%%====================================================================
%% Aggregation
%%====================================================================

%% One point per (algorithm, topology, size): the median convergence time
%% over the trials that actually converged, plus how many did. Averaging in
%% the failures would be meaningless -- a run that never converged has no
%% convergence time, it has an outcome.
points(Rows, Algo, Topo) ->
    Sel = [R || R <- Rows,
                maps:get(algorithm, R, "") =:= atom_to_list(Algo),
                maps:get(topology, R, "") =:= atom_to_list(Topo)],
    Sizes = lists:usort([round(num(maps:get(actual_nodes, R))) || R <- Sel]),
    lists:filtermap(
      fun(N) ->
          At = [R || R <- Sel, round(num(maps:get(actual_nodes, R))) =:= N],
          Ok = [num(maps:get(micros, R)) / 1000
                || R <- At, maps:get(converged, R) =:= "true"],
          case Ok of
              [] -> false;
              _  -> {true, {N, median(Ok), length(Ok), length(At)}}
          end
      end, Sizes).

median([]) -> 0.0;
median(L) ->
    S = lists:sort(L),
    K = length(S),
    case K rem 2 of
        1 -> lists:nth(K div 2 + 1, S);
        0 -> (lists:nth(K div 2, S) + lists:nth(K div 2 + 1, S)) / 2
    end.

%%====================================================================
%% Scales
%%====================================================================

lg(V) when V =< 0 -> 0.0;
lg(V) -> math:log10(V).

sx(V, Lo, Hi) -> ?ML + (lg(V) - lg(Lo)) / max(1.0e-9, lg(Hi) - lg(Lo)) * (?W - ?ML - ?MR).
sy(V, Lo, Hi) -> ?H - ?MB - (lg(V) - lg(Lo)) / max(1.0e-9, lg(Hi) - lg(Lo)) * (?H - ?MT - ?MB).

%% Decade ticks spanning the data, so the axis always starts and ends on a
%% round power of ten.
decades(Lo, Hi) ->
    A = trunc(math:floor(lg(Lo))),
    B = trunc(math:ceil(lg(Hi))),
    [math:pow(10, E) || E <- lists:seq(A, B)].

fmt_tick(V) when V >= 1000 -> io_lib:format("~wk", [round(V / 1000)]);
fmt_tick(V) when V >= 1    -> io_lib:format("~w", [round(V)]);
fmt_tick(V)                -> io_lib:format("~w", [V]).

f(X) -> io_lib:format("~.2f", [X * 1.0]).

%%====================================================================
%% Chart
%%====================================================================

%% Series :: [{TopoAtom, Label, [{X, Y}]}]
chart(Title, Sub, XLabel, YLabel, Series) ->
    Xs = [X || {_, _, Pts} <- Series, {X, _} <- Pts],
    Ys = [Y || {_, _, Pts} <- Series, {_, Y} <- Pts],
    case {Xs, Ys} of
        {[], _} -> [];
        {_, []} -> [];
        _ ->
            XLo = lists:min(Xs), XHi = lists:max(Xs),
            YLo = lists:min(Ys), YHi = lists:max(Ys),
            XT = decades(XLo, XHi),
            YT = decades(YLo, YHi),
            XA = hd(XT), XB = lists:last(XT),
            YA = hd(YT), YB = lists:last(YT),
            ["<figure class=\"chart\">",
             "<figcaption><h3>", Title, "</h3><p>", Sub, "</p></figcaption>",
             "<svg viewBox=\"0 0 ", integer_to_list(?W), " ", integer_to_list(?H),
             "\" role=\"img\" xmlns=\"http://www.w3.org/2000/svg\">",
             grid(XT, YT, XA, XB, YA, YB),
             axes(XT, YT, XA, XB, YA, YB, XLabel, YLabel),
             [series_svg(S, XA, XB, YA, YB, LabelY)
              || {S, LabelY} <- lists:zip(Series, label_ys(Series, XA, XB, YA, YB))],
             "</svg></figure>"]
    end.

%% Direct labels sit at each line's right-hand end, so two series that finish
%% at a similar height would print on top of each other. Push them apart to a
%% minimum spacing, keeping their original order.
label_ys(Series, _XA, _XB, YA, YB) ->
    Ends = [sy(element(2, lists:last(Pts)), YA, YB) || {_, _, Pts} <- Series],
    Tagged = lists:keysort(2, [{I, Y} || {I, Y} <- lists:zip(lists:seq(1, length(Ends)), Ends)]),
    Spread = spread(Tagged, -1.0e9),
    [Y || {_, Y} <- lists:keysort(1, Spread)].

spread([], _Prev) -> [];
spread([{I, Y} | T], Prev) ->
    Y1 = case Y - Prev < 13.0 of
             true  -> Prev + 13.0;
             false -> Y
         end,
    [{I, Y1} | spread(T, Y1)].

grid(XT, YT, XA, XB, YA, YB) ->
    [[["<line x1=\"", f(sx(X, XA, XB)), "\" x2=\"", f(sx(X, XA, XB)),
       "\" y1=\"", f(?MT), "\" y2=\"", f(?H - ?MB),
       "\" stroke=\"", ?GRID, "\" stroke-width=\"1\"/>"] || X <- XT],
     [["<line y1=\"", f(sy(Y, YA, YB)), "\" y2=\"", f(sy(Y, YA, YB)),
       "\" x1=\"", f(?ML), "\" x2=\"", f(?W - ?MR),
       "\" stroke=\"", ?GRID, "\" stroke-width=\"1\"/>"] || Y <- YT]].

axes(XT, YT, XA, XB, YA, YB, XLabel, YLabel) ->
    [[["<text x=\"", f(sx(X, XA, XB)), "\" y=\"", f(?H - ?MB + 18),
       "\" text-anchor=\"middle\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       fmt_tick(X), "</text>"] || X <- XT],
     [["<text x=\"", f(?ML - 10), "\" y=\"", f(sy(Y, YA, YB) + 4),
       "\" text-anchor=\"end\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       fmt_tick(Y), "</text>"] || Y <- YT],
     "<text x=\"", f((?ML + ?W - ?MR) / 2), "\" y=\"", f(?H - 10),
     "\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"", ?INK_MUTED, "\">",
     XLabel, "</text>",
     "<text transform=\"translate(16,", f((?MT + ?H - ?MB) / 2),
     ") rotate(-90)\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"",
     ?INK_MUTED, "\">", YLabel, "</text>"].

series_svg({Topo, Label, Pts}, XA, XB, YA, YB, LabelY) ->
    C = colour(Topo),
    Coords = [{sx(X, XA, XB), sy(Y, YA, YB)} || {X, Y} <- Pts],
    Poly = lists:join(" ", [[f(X), ",", f(Y)] || {X, Y} <- Coords]),
    {LX, _} = lists:last(Coords),
    [["<polyline fill=\"none\" stroke=\"", C,
      "\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"",
      Poly, "\"/>"],
     %% 2px surface ring keeps overlapping markers legible where curves cross
     [["<circle cx=\"", f(X), "\" cy=\"", f(Y), "\" r=\"4\" fill=\"", C,
       "\" stroke=\"", ?SURFACE, "\" stroke-width=\"2\"/>"] || {X, Y} <- Coords],
     %% Direct label: identity does not rest on colour alone
     ["<text x=\"", f(LX + 10), "\" y=\"", f(LabelY + 4),
      "\" font-size=\"11.5\" font-weight=\"600\" fill=\"", C, "\">", Label,
      "</text>"]].

colour(T) ->
    {_, C} = lists:keyfind(T, 1, ?SERIES_COLOURS),
    C.

label(full) -> "full";
label('2D') -> "2D";
label(line) -> "line";
label(imp2D) -> "imp2D".

%%====================================================================
%% Document
%%====================================================================

head() ->
    ["<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
     "<title>COP6539 Project 2 Report</title><style>",
     "@page{size:A4;margin:16mm}",
     "*{box-sizing:border-box}",
     "body{margin:0;background:", ?SURFACE, ";color:", ?INK, ";",
     "font:14px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;",
     "max-width:860px;margin-inline:auto;padding:24px}",
     "h1{font-size:25px;margin:0 0 4px}",
     "h2{font-size:18px;margin:30px 0 8px;padding-top:14px;border-top:1px solid ", ?GRID, "}",
     "h3{font-size:14.5px;margin:0 0 2px}",
     ".sub{color:", ?INK_2, ";margin:0 0 18px}",
     ".chart{margin:18px 0 26px;padding:0;break-inside:avoid}",
     ".chart figcaption p{margin:0 0 6px;color:", ?INK_MUTED, ";font-size:12px}",
     ".chart svg{width:100%;height:auto;overflow:visible}",
     "table{border-collapse:collapse;width:100%;font-size:11.5px;margin:10px 0 18px}",
     "th,td{border-bottom:1px solid ", ?GRID, ";padding:4px 7px;text-align:right}",
     "th:first-child,td:first-child{text-align:left}",
     "th{color:", ?INK_2, ";font-weight:600}",
     "td.num{font-variant-numeric:tabular-nums}",
     ".key{display:flex;gap:16px;flex-wrap:wrap;margin:2px 0 10px;font-size:12px;color:", ?INK_2, "}",
     ".key span{display:flex;align-items:center;gap:6px}",
     ".sw{width:11px;height:11px;border-radius:3px;display:inline-block}",
     "p{margin:9px 0}", "ul{margin:9px 0;padding-left:20px}", "li{margin:4px 0}",
     "code{background:#f1f0ec;padding:1px 4px;border-radius:3px;font-size:12px}",
     ".note{background:#f6f5f1;border-left:3px solid ", ?INK_MUTED,
     ";padding:9px 13px;margin:12px 0;font-size:13px}",
     "</style></head><body>"].

legend() ->
    ["<div class=\"key\">",
     [["<span><i class=\"sw\" style=\"background:", colour(T), "\"></i>",
       label(T), "</span>"] || {T, _} <- ?SERIES_COLOURS],
     "</div>"].

body(Core, Bonus) ->
    [intro(),
     "<h2>1. Convergence time vs network size</h2>",
     legend(),
     chart("Gossip", "Median over converged trials. Both axes logarithmic.",
           "number of nodes", "convergence time (ms)", series_for(Core, gossip)),
     chart("Push-Sum", "Median over converged trials. Both axes logarithmic.",
           "number of nodes", "convergence time (ms)", series_for(Core, push_sum)),
     "<h2>2. Largest network reached</h2>",
     ceiling_table(Core),
     "<h2>3. Measurements</h2>",
     data_table(Core),
     bonus_charts(Bonus),
     findings(Core)].

series_for(Rows, Algo) ->
    [{T, label(T), [{N, Ms} || {N, Ms, _, _} <- points(Rows, Algo, T)]}
     || {T, _} <- ?SERIES_COLOURS,
        points(Rows, Algo, T) =/= []].

ceiling_table(Rows) ->
    ["<table><thead><tr><th>Topology</th>",
     "<th>Gossip &mdash; largest n</th><th>time</th>",
     "<th>Push-Sum &mdash; largest n</th><th>time</th></tr></thead><tbody>",
     [begin
          G = points(Rows, gossip, T),
          P = points(Rows, push_sum, T),
          ["<tr><td>", label(T), "</td>", ceil_cells(G), ceil_cells(P), "</tr>"]
      end || {T, _} <- ?SERIES_COLOURS],
     "</tbody></table>"].

ceil_cells([]) -> "<td>&mdash;</td><td>&mdash;</td>";
ceil_cells(Pts) ->
    {N, Ms, _, _} = lists:last(Pts),
    ["<td class=\"num\">", integer_to_list(N), "</td>",
     "<td class=\"num\">", io_lib:format("~.1f ms", [Ms]), "</td>"].

data_table(Rows) ->
    ["<table><thead><tr><th>Algorithm</th><th>Topology</th><th>Nodes</th>",
     "<th>Median (ms)</th><th>Converged</th></tr></thead><tbody>",
     [[["<tr><td>", algo_label(A), "</td><td>", label(T), "</td>",
        "<td class=\"num\">", integer_to_list(N), "</td>",
        "<td class=\"num\">", io_lib:format("~.2f", [Ms]), "</td>",
        "<td class=\"num\">", integer_to_list(Ok), "/", integer_to_list(Tot),
        "</td></tr>"]
       || {N, Ms, Ok, Tot} <- points(Rows, A, T)]
      || A <- [gossip, push_sum], {T, _} <- ?SERIES_COLOURS],
     "</tbody></table>"].

algo_label(gossip) -> "Gossip";
algo_label(push_sum) -> "Push-Sum".

intro() ->
    ["<h1>Gossip and Push-Sum convergence</h1>",
     "<p class=\"sub\">COP6539 Project 2 &middot; Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>An Erlang actor simulator measuring how long Gossip and Push-Sum take ",
     "to converge across four network topologies. Every node is one actor; the ",
     "only coordination is asynchronous message passing. Each point is the median ",
     "of five trials, counting only the trials that converged.</p>"].

%%====================================================================
%% Bonus
%%====================================================================

bonus_charts([]) -> [];
bonus_charts(Bonus) ->
    [
          bonus_chart(Bonus, death, gossip,
                 "Gossip: nodes reached under node failure",
                 "fraction of nodes that die (p)"),
     bonus_chart(Bonus, death, push_sum,
                 "Push-Sum: actors converged under node failure",
                 "fraction of nodes that die (p)"),
     bonus_chart(Bonus, drop, gossip,
                 "Gossip: nodes reached under message loss",
                 "probability a message is dropped (q)"),
     bonus_chart(Bonus, drop, push_sum,
                 "Push-Sum: actors converged under message loss",
                 "probability a message is dropped (q)")].

bonus_chart(Rows, Model, Algo, Title, XLabel) ->
    Series = [{T, label(T), bonus_points(Rows, Model, Algo, T)}
              || {T, _} <- ?SERIES_COLOURS,
                 bonus_points(Rows, Model, Algo, T) =/= []],
    linear_chart(Title, "Mean over three trials, 500 nodes.",
                 XLabel, "nodes reached (%)", Series).

bonus_points(Rows, Model, Algo, Topo) ->
    Sel = [R || R <- Rows,
                maps:get(model, R, "") =:= atom_to_list(Model),
                maps:get(algorithm, R, "") =:= atom_to_list(Algo),
                maps:get(topology, R, "") =:= atom_to_list(Topo)],
    Ps = lists:usort([num(maps:get(param, R)) || R <- Sel]),
    [begin
         At = [num(maps:get(reached_pct, R)) || R <- Sel,
                                                 num(maps:get(param, R)) =:= P],
         {P, lists:sum(At) / max(1, length(At))}
     end || P <- Ps].

%% The bonus charts are linear in both axes: the parameter is a probability
%% on [0, 0.5] and coverage is a percentage, so neither benefits from a log
%% scale and zero is a meaningful value that a log axis could not show.
linear_chart(_Title, _Sub, _XL, _YL, []) -> [];
linear_chart(Title, Sub, XLabel, YLabel, Series) ->
    Xs = [X || {_, _, Pts} <- Series, {X, _} <- Pts],
    XA = 0.0, XB = lists:max(Xs),
    YA = 0.0, YB = 100.0,
    LX = fun(V) -> ?ML + (V - XA) / max(1.0e-9, XB - XA) * (?W - ?ML - ?MR) end,
    LY = fun(V) -> ?H - ?MB - (V - YA) / (YB - YA) * (?H - ?MT - ?MB) end,
    XT = [XA + (XB - XA) * I / 5 || I <- lists:seq(0, 5)],
    YT = [0, 20, 40, 60, 80, 100],
    ["<figure class=\"chart\">",
     "<figcaption><h3>", Title, "</h3><p>", Sub, "</p></figcaption>",
     "<svg viewBox=\"0 0 ", integer_to_list(?W), " ", integer_to_list(?H),
     "\" role=\"img\" xmlns=\"http://www.w3.org/2000/svg\">",
     [["<line y1=\"", f(LY(Y)), "\" y2=\"", f(LY(Y)), "\" x1=\"", f(?ML),
       "\" x2=\"", f(?W - ?MR), "\" stroke=\"", ?GRID, "\" stroke-width=\"1\"/>",
       "<text x=\"", f(?ML - 10), "\" y=\"", f(LY(Y) + 4),
       "\" text-anchor=\"end\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       integer_to_list(Y), "</text>"] || Y <- YT],
     [["<text x=\"", f(LX(X)), "\" y=\"", f(?H - ?MB + 18),
       "\" text-anchor=\"middle\" font-size=\"11\" fill=\"", ?INK_2, "\">",
       io_lib:format("~.2f", [X]), "</text>"] || X <- XT],
     "<text x=\"", f((?ML + ?W - ?MR) / 2), "\" y=\"", f(?H - 10),
     "\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"", ?INK_MUTED, "\">",
     XLabel, "</text>",
     "<text transform=\"translate(16,", f((?MT + ?H - ?MB) / 2),
     ") rotate(-90)\" text-anchor=\"middle\" font-size=\"11.5\" fill=\"",
     ?INK_MUTED, "\">", YLabel, "</text>",
     [begin
          C = colour(T),
          Co = [{LX(X), LY(Y)} || {X, Y} <- Pts],
          Poly = lists:join(" ", [[f(X), ",", f(Y)] || {X, Y} <- Co]),
          {EX, _} = lists:last(Co),
          [["<polyline fill=\"none\" stroke=\"", C, "\" stroke-width=\"2\"",
            " stroke-linejoin=\"round\" stroke-linecap=\"round\" points=\"", Poly, "\"/>"],
           [["<circle cx=\"", f(X), "\" cy=\"", f(Y), "\" r=\"4\" fill=\"", C,
             "\" stroke=\"", ?SURFACE, "\" stroke-width=\"2\"/>"] || {X, Y} <- Co],
           ["<text x=\"", f(EX + 10), "\" y=\"", f(EY + 4),
            "\" font-size=\"11.5\" font-weight=\"600\" fill=\"", C, "\">", L,
            "</text>"]]
      end || {{T, L, Pts}, EY} <- lists:zip(Series, linear_label_ys(Series, LY))],
     "</svg></figure>"].

%% Same de-collision as the log-log charts: several topologies finish at
%% 100% in the bonus plots, so their end labels would print on top of one
%% another.
linear_label_ys(Series, LY) ->
    Ends = [LY(element(2, lists:last(P))) || {_, _, P} <- Series],
    Tagged = lists:keysort(2, lists:zip(lists:seq(1, length(Ends)), Ends)),
    [Y || {_, Y} <- lists:keysort(1, spread(Tagged, -1.0e9))].

%%====================================================================
%% Findings
%%====================================================================

findings(Rows) ->
    ["<h2>5. Findings</h2>",
     "<p><strong>Connectivity dominates everything else.</strong> ",
     "At every network size the four topologies separate by orders of magnitude, ",
     "in the order <em>full &lt; imp2D &lt; 2D &lt; line</em>. Adding a single ",
     "random long-range edge per node &mdash; the only difference between 2D and ",
     "imp2D &mdash; is worth far more than the regular grid structure it is added to. ",
     "That is the small-world effect appearing in a 25-line change to the neighbour ",
     "function.</p>",
     "<p><strong>Gossip on a line is a coin flip, not a slow success.</strong> ",
     "The rumour does not simply take longer on a line; it frequently dies out ",
     "altogether. A node stops transmitting after ten hears, and the node adjacent ",
     "to a fast talker reaches ten almost immediately, having forwarded the rumour ",
     "only a handful of times. The frontier then stalls, and what remains is a ",
     "dead-end node transmitting forever into a neighbour that has already fallen ",
     "silent. This is why the tables report how many trials converged rather than ",
     "a bare average.</p>",
     "<p><strong>Push-Sum is accurate exactly where it is fast.</strong> ",
     "On full and imp2D the estimate matches the true average ",
     "to around 1e-13 &mdash; floating-point noise. On 2D and line the relative ",
     "error rises to roughly 1e-3. The termination rule is <em>local</em>: an actor ",
     "stops when its own ratio stops moving, which on a slowly-mixing graph happens ",
     "well before the network as a whole has mixed. Accuracy and speed are not ",
     "two independent properties here; they are the same property of the topology.</p>",
     "<div class=\"note\"><strong>On what <code>s/w</code> converges to.</strong> ",
     "With s<sub>i</sub> = i and w<sub>i</sub> = 1, the conserved quantity is ",
     "&Sigma;s / &Sigma;w = (n+1)/2 &mdash; the <em>average</em>, not the sum. ",
     "The assignment calls s/w the sum estimate; the sum is the ratio times n. ",
     "Both are printed by the simulator.</div>",
     scaling_note(Rows)].

%% Fit an exponent to the full-topology gossip curve: on log-log axes a
%% power law is a straight line, and its slope is the exponent.
scaling_note(Rows) ->
    case points(Rows, gossip, full) of
        Pts when length(Pts) >= 2 ->
            {N1, T1, _, _} = hd(Pts),
            {N2, T2, _, _} = lists:last(Pts),
            Slope = (lg(T2) - lg(T1)) / max(1.0e-9, lg(N2) - lg(N1)),
            ["<p><strong>Scaling.</strong> Across ", integer_to_list(N1), " to ",
             integer_to_list(N2), " nodes, gossip on the full topology fits ",
             "t &prop; n<sup>", io_lib:format("~.2f", [Slope]), "</sup>. ",
             "A slope near 1 means convergence time grows roughly linearly with ",
             "the number of actors, which is what a fixed number of rounds costs ",
             "when each round is O(n) messages spread over a fixed number of ",
             "cores &mdash; the simulator is scheduler-bound, not round-bound.</p>"];
        _ -> []
    end.

%% The bonus observations, as measured.
bonus_findings() ->
    ["<p><strong>The two algorithms fail in completely different ways, and the "
     "topology that protects one ruins the other.</strong></p>",
     "<p><strong>Gossip under node death: connectivity is what buys "
     "resilience.</strong> <em>full</em>, <em>2D</em> and <em>imp2D</em> are "
     "essentially untouched, holding above 98% even when half the nodes die, "
     "because every pair of survivors still has many routes between them. "
     "<em>line</em> falls from 44% to around 20%: a single dead node "
     "partitions a line, and by construction there is no second route. What "
     "matters is not how many nodes die but how many paths each death "
     "destroys.</p>",
     "<p><strong>Push-Sum under node death inverts that ranking "
     "completely.</strong> At just p = 0.05, <em>full</em> drops from 100% to "
     "<strong>0%</strong> &mdash; not one actor converges &mdash; while "
     "<em>line</em> still reaches 89%, and 54% even at p = 0.5. The reason is "
     "that Push-Sum's messages carry mass, and a dead actor absorbs whatever "
     "reaches it. On <em>full</em> a message can land on any node, so with a "
     "fraction p dead it is swallowed after about 1/p hops; the circulating "
     "population evaporates and the network falls silent. On a <em>line</em> a "
     "message is confined between two neighbours, so the dead nodes merely cut "
     "the line into live segments inside which messages keep circulating.</p>",
     "<div class=\"note\"><strong>But terminating is not the same as being "
     "right.</strong> Those surviving <em>line</em> actors converge on their "
     "own segment's average rather than the network's: relative error rises "
     "from 1e-3 with no failures to around 5e-2 at p = 0.05, roughly twenty "
     "times worse, while the actors that do finish on <em>full</em> with no "
     "failures are exact to 2e-13. The curve counts actors that met the "
     "termination rule, not actors that met it correctly.</div>",
     "<p><strong>Message loss separates the algorithms outright.</strong> "
     "Gossip degrades gradually &mdash; a lost rumour costs nothing permanent, "
     "since the sender is still active and will send again. Push-Sum fails "
     "completely at even 5% loss on every topology, <em>full</em> included. "
     "That is not a tuning problem: Push-Sum's correctness rests on mass "
     "conservation, so every dropped message destroys mass permanently, and "
     "with one message in flight per actor the population decays until nothing "
     "is left to carry the computation.</p>",
     "<div class=\"note\">The practical reading: Gossip tolerates an unreliable "
     "network but needs a connected one; Push-Sum tolerates a sparse network "
     "but needs a reliable one. Surviving both would mean acknowledging the "
     "Push-Sum sends, buying reliability back at the cost of the asynchrony "
     "that makes it cheap.</div>"].

%% The bonus is submitted as its own report, so it gets its own document
%% rather than a section appended to the main one.
bonus_body(Bonus) ->
    ["<h1>Failure models in Gossip and Push-Sum</h1>",
     "<p class=\"sub\">COP6539 Project 2, bonus &middot; "
     "Ahmed Rageeb Ahsan, Saiful Islam</p>",
     "<p>The simulator has no failure of any kind in the main report. This "
     "one adds two, each driven by a single parameter, and asks what each "
     "algorithm does as that parameter rises.</p>",
     "<h2>Method</h2>",
     "<p><code>death=p</code> &mdash; each node independently dies at a random "
     "moment inside a 500&nbsp;ms window, with probability <em>p</em>. A dead "
     "actor stops transmitting and discards whatever arrives, which models a "
     "machine that fails partway through a run.</p>",
     "<p><code>drop=q</code> &mdash; each individual send is lost with "
     "probability <em>q</em>, independently. This models a link that is "
     "momentarily down rather than a node that is gone.</p>",
     "<p>Network size is fixed at 500 nodes so the parameter is the only thing "
     "that varies, with three trials per point. The measure plotted is how much "
     "of the network the run actually reached &mdash; for Gossip the actors "
     "that heard the rumour, for Push-Sum the actors that met the termination "
     "rule. Under failure the interesting outcome is partial delivery, not "
     "slower delivery, so coverage is more informative than time.</p>",
     "<h2>Results</h2>",
     legend(),
     bonus_charts(Bonus),
     "<h2>Findings</h2>",
     bonus_findings()].

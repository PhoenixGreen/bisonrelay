import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/tile_maps.dart';
import 'package:bruig/plugin_system/canvas/model/world_map.dart';

// chart_presets.dart is the Charts tab's gallery (Ken, 2026-11-17, from
// prototype v7 and its research): every kind of chart, grouped by the
// question it answers, with the starting designs -- sub-presets -- it
// offers. A sub-preset sets layout, labels, emphasis, notes, grid and
// motion; never the data, the colours or the words, so a style (see
// data_styles.dart) and a preset mix freely. The gallery is built from the
// columns ticked on the left: each kind says how it would read them, or
// what it needs instead.

/// ChartQuestion is what a chart answers, after the FT's Visual
/// Vocabulary; a kind can answer several.
enum ChartQuestion {
  magnitude("Compare sizes"),
  time("Change over time"),
  ranking("Rank"),
  part("Part of a whole"),
  distribution("Spread"),
  correlation("Relationship"),
  deviation("Up or down"),
  flow("Flow"),
  spatial("Places"),
  single("One number");

  final String label;
  const ChartQuestion(this.label);
}

/// ChartUse is what a design suits: an infographic, an explainer video,
/// analysis.
enum ChartUse {
  infographic("Infographic"),
  video("Video"),
  analysis("Analysis");

  final String label;
  const ChartUse(this.label);
}

/// Picks is the ticked columns, sorted by what they hold.
class Picks {
  final DataSheet sheet;
  final CellRange range;
  final List<int> numbers, dates, names;
  const Picks(this.sheet, this.range,
      {this.numbers = const [], this.dates = const [], this.names = const []});

  /// labels is the column a chart is labelled by: a date for time, else a
  /// name, else the range's first column.
  int get labels => names.isNotEmpty
      ? names.first
      : dates.isNotEmpty
          ? dates.first
          : 0;

  SheetLink link(int labels, List<int> series) =>
      SheetLink(sheet.id, range, labels: labels, series: series);

  /// flows is whether a name column holds "From > To" labels.
  bool get flows => names.any((n) {
        for (var r = range.r0 + 1; r <= range.r1; r++) {
          var v = sheetShown(sheet, r, range.c0 + n);
          if (RegExp(r"->|→|>").hasMatch(v)) return true;
        }
        return false;
      });
}

/// ChartPreset is one starting design for a kind.
class ChartPreset {
  final String name, says;
  final List<ChartUse> uses;

  /// plays is whether it moves on its own (a race, steps): its card plays.
  final bool plays;

  /// needs, when set, is what it needs that the ticked columns lack
  /// ("a date column"); the card says so and can't be started.
  final String? Function(Picks)? needs;

  /// apply is the design on [e], which already reads the ticked columns.
  final ChartElement Function(ChartElement e, Picks p) apply;
  const ChartPreset(this.name, this.says, this.uses, this.apply,
      {this.plays = false, this.needs});
}

/// ChartKind is one kind of chart in the gallery.
class ChartKind {
  final ChartType type;
  final String name, use;
  final List<ChartQuestion> questions;
  final String caveat;

  /// isNew marks the kinds the research added (Ken, 2026-11-17).
  final bool isNew;

  /// reads is how it would draw the ticked columns, or null when it can't.
  final SheetLink? Function(Picks) reads;

  /// needs says what it needs, for a kind that can't read the columns.
  final String needs;
  final List<ChartPreset> presets;
  const ChartKind(this.type, this.name, this.use, this.questions, this.reads,
      this.needs, this.presets,
      {this.caveat = "", this.isNew = false});
}

const _i = ChartUse.infographic, _v = ChartUse.video, _a = ChartUse.analysis;

// ---- Small helpers the presets share.

/// _leader is the label of the largest mark of [e]'s first series.
String _leader(ChartElement e) {
  var d = e.data;
  if (d.series.isEmpty || d.categories.isEmpty) return "";
  var best = 0;
  for (var i = 0; i < d.categories.length; i++) {
    if (d.valueAt(0, i) > d.valueAt(0, best)) best = i;
  }
  return d.categories[best];
}

double _average(ChartElement e) {
  var d = e.data;
  if (d.series.isEmpty) return 0;
  var vs = [
    for (var i = 0; i < d.categories.length; i++)
      if (!d.valueAt(0, i).isNaN) d.valueAt(0, i)
  ];
  return vs.isEmpty ? 0 : vs.reduce((a, b) => a + b) / vs.length;
}

ChartElement _relink(ChartElement e, SheetLink Function(SheetLink) f) {
  var l = e.sheet;
  return l == null ? e : e.copyWith(sheet: f(l));
}

ChartHighlight _top(int n, {bool named = true}) => ChartHighlight(
    reach: ChartReach.top, n: n, fade: true, named: named, colour: _accent);
const _accent = Color(0xFFF2B33D);

/// _arrive is how a design arrives, by the research's motion rules (its
/// section 4.7): a line drawn at a steady rate, since easing bends the
/// sense of time; bars and slices easing out, staggered a little, never
/// overshooting a value the data doesn't have; dots popping in close
/// together; a whole-plot wipe or sweep steady.
ChartAnimation _arrive(ChartAnimationPreset p, {bool inTurn = false}) =>
    ChartAnimation(
        preset: p,
        seriesInTurn: inTurn,
        ease: switch (p) {
          ChartAnimationPreset.drawOn ||
          ChartAnimationPreset.wipe ||
          ChartAnimationPreset.sweep =>
            ChartEase.linear,
          _ => ChartEase.easeOut,
        },
        gap: switch (p) {
          ChartAnimationPreset.grow => 0.3,
          ChartAnimationPreset.popIn || ChartAnimationPreset.random => 0.15,
          ChartAnimationPreset.fadeIn => 0.25,
          ChartAnimationPreset.morph => 0,
          _ => 0.55,
        });

String? _needsDates(Picks p) => p.dates.isEmpty ? "a date column" : null;

// ---- How each kind reads the ticked columns.

SheetLink? _oneNumber(Picks p) =>
    p.numbers.isEmpty ? null : p.link(p.labels, [p.numbers.first]);

/// _whenReads is a timeline's: its events named, placed by a column of
/// numbers -- or by the years they happened, which read as dates.
SheetLink? _whenReads(Picks p) {
  if (p.numbers.isNotEmpty) return _oneNumber(p);
  if (p.dates.isEmpty) return null;
  var named = p.names.isNotEmpty ? p.names.first : p.dates.first;
  return p.link(named, [p.dates.first]);
}

SheetLink? _ranked(Picks p) => p.numbers.isEmpty
    ? null
    : p.link(p.labels, [p.numbers.first]).copyWith(sortBy: p.numbers.first);
SheetLink? _several(Picks p) =>
    p.numbers.length < 2 ? null : p.link(p.labels, p.numbers.take(6).toList());
SheetLink? _overTime(Picks p) {
  if (p.numbers.isEmpty || p.dates.isEmpty) return null;
  // A long sheet: one number, a line for each name. A wide one: a line
  // for each column of numbers (found making the Charts canvas: five
  // clubs' columns ticked drew Arsenal's alone).
  if (p.names.isNotEmpty) {
    return p.link(p.dates.first, [p.numbers.first]).copyWith(
        colourBy: p.names.first);
  }
  return p.link(p.dates.first, p.numbers.take(6).toList());
}

SheetLink? _pair(Picks p) => p.numbers.length < 2
    ? null
    : p.link(p.numbers.first, [p.numbers[1]]).copyWith(
        // The points named by the names ticked (found making the Charts
        // canvas: "Every point named" wrote their numbers).
        pointNames: p.names.isNotEmpty ? p.names.first : -1);

final chartKinds = _withWays(<ChartKind>[
  ChartKind(
      ChartType.bar,
      "Columns",
      "Compare a few amounts, or show a total each period.",
      [ChartQuestion.magnitude, ChartQuestion.time],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset(
            "Clean columns",
            "A hairline grid with the numbers on it, a dark baseline, no value labels.",
            [_a],
            _cleanColumns),
        ChartPreset(
            "Labelled, no axis",
            "A bold value above every column; no axis or grid.",
            [_i, _v],
            _labelledColumns),
        ChartPreset(
            "One-column story",
            "Every column grey but the largest, which carries its value and a label.",
            [_a, _v],
            _oneStory),
        ChartPreset(
            "Above and below average",
            "A dashed average line; columns above it lit, the rest faded.",
            [_a],
            _aboveAverage),
        ChartPreset(
            "Poster columns",
            "Thick round-topped columns on pale tracks, the values printed inside.",
            [_i],
            _posterColumns),
      ]),
  ChartKind(
      ChartType.horizontalBar,
      "Bars",
      "Rank things, especially with long names.",
      [ChartQuestion.magnitude, ChartQuestion.ranking],
      _ranked,
      "a column of numbers",
      [
        ChartPreset(
            "Ranked list",
            "Sorted, each name on its own line above a thin bar, the value at the end.",
            [_a, _i],
            _rankedList),
        ChartPreset("Highlight one", "Every bar grey but the leader.", [_a, _v],
            _barsOneLit),
        ChartPreset(
            "Labels inside",
            "Thick rounded bars with their values written inside.",
            [_i, _v],
            _thickBars),
        ChartPreset(
            "Track bars",
            "A pale full-length track behind each bar, so it reads as filled up.",
            [_i],
            _trackBars),
        ChartPreset("Scale and grid", "Hairlines and a scale; no value labels.",
            [_a], _barsScale),
        ChartPreset(
            "Top five and the rest",
            "The first five, then everyone else added up as one grey bar.",
            [_a, _i],
            _topFive),
        ChartPreset(
            "Bar race",
            "Plays through the dates: bars swap places, the date large behind.",
            [_v],
            _barRace,
            plays: true,
            needs: _needsDates),
      ]),
  ChartKind(
      ChartType.groupedBar,
      "Paired columns",
      "Compare two series side by side within each group.",
      [ChartQuestion.magnitude, ChartQuestion.time],
      _several,
      "two columns of numbers",
      [
        ChartPreset("Pairs with values", "Pairs of columns, values on top.",
            [_a], _pairsValues),
        ChartPreset("Pairs, no axis", "No grid or axis; a key at the top.",
            [_i, _v], _pairsClean),
        ChartPreset(
            "Small charts",
            "A small chart for each, its pair side by side, on one scale.",
            [_a],
            _pairsSplit),
      ]),
  ChartKind(
      ChartType.stackedBar,
      "Stacked columns",
      "Show totals and what they're made of.",
      [ChartQuestion.part, ChartQuestion.magnitude],
      _several,
      "two columns of numbers",
      [
        ChartPreset("Stacked, keyed", "The parts stacked, a key beside.", [_a],
            _stackKeyed),
        ChartPreset("Labelled blocks", "Every part with its value printed.",
            [_i], _stackLabelled),
        ChartPreset(
            "Built layer by layer",
            "Each layer arrives across every column in turn.",
            [_v],
            _stackLayers),
      ]),
  ChartKind(
      ChartType.line,
      "Line",
      "Show change over time; compare a few trends.",
      [ChartQuestion.time],
      _overTime,
      "a date column and numbers",
      [
        ChartPreset(
            "Editorial lines",
            "Names at the line ends, no key, hairline grid.",
            [_a],
            _editorialLines),
        ChartPreset("Top three lit",
            "Every line grey but the top three, named.", [_a, _v], _linesLit),
        ChartPreset(
            "Hero line",
            "One thick curved line with its points, no grid.",
            [_i, _v],
            _heroLine),
        ChartPreset("Log scale", "Each step up ten times the last.", [_a, _v],
            _logLines),
        ChartPreset("Small charts",
            "A small chart for each thing, on one scale.", [_a], _splitLines,
            needs: _needsName),
        ChartPreset("Steps", "Flat then straight up: for values that jump.",
            [_a], _stepLines),
        ChartPreset("Drawn on", "The lines trace themselves along the dates.",
            [_v], _drawnLines,
            plays: true),
      ]),
  ChartKind(
      ChartType.area,
      "Area",
      "A total over time, or how its parts change.",
      [ChartQuestion.time, ChartQuestion.part],
      _overTime,
      "a date column and numbers",
      [
        ChartPreset("Filled area", "A filled area from zero.", [_a, _i], _area),
        ChartPreset(
            "Curved, no grid", "Soft curves, no grid.", [_i, _v], _areaSoft),
        ChartPreset("Wiped across", "Uncovered from the left.", [_v], _areaWipe,
            plays: true),
      ]),
  ChartKind(
      ChartType.scatter,
      "Scatter",
      "Show how two numbers relate across many things.",
      [ChartQuestion.correlation],
      _pair,
      "two columns of numbers",
      [
        ChartPreset(
            "Labelled points", "Every point named.", [_a], _scatterNamed),
        ChartPreset("Top three lit", "Everything grey but the top three.",
            [_a, _v], _scatterLit),
        ChartPreset("Popping in", "Points appear in no particular order.", [_v],
            _scatterPop,
            plays: true),
        ChartPreset(
            "Quadrants",
            "Dashed lines at the averages split it in four.",
            [_i, _a],
            _scatterQuadrants),
        ChartPreset("With a trend", "A straight trend line through the points.",
            [_a], _scatterTrend),
        ChartPreset("Joined", "The points joined in the order of the rows.",
            [_a], _scatterJoined),
      ]),
  ChartKind(
      ChartType.candlestick,
      "Candles",
      "Open, high, low and close for each period (prices).",
      [ChartQuestion.time],
      _candles,
      "four columns of numbers: open, high, low, close",
      [
        ChartPreset("Classic", "Up and down candles with a grid.", [_a],
            _candleClassic),
        ChartPreset("Clean", "No grid; thick candles.", [_i, _v], _candleClean),
      ]),
  ChartKind(
      ChartType.pie,
      "Pie",
      "Two or three shares of one whole.",
      [ChartQuestion.part],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset(
            "Largest slice lit",
            "The biggest slice in the accent, the rest faded.",
            [_i, _v],
            _pieOne),
        ChartPreset(
            "Labelled", "Each slice with its share.", [_a], _pieLabelled),
        ChartPreset(
            "Swept round", "The slices sweep in from the top.", [_v], _pieSweep,
            plays: true),
      ],
      caveat:
          "Hard to compare more than a few slices: Bars or a Share bar read better."),
  ChartKind(
      ChartType.donut,
      "Doughnut",
      "Shares of a whole with a number in the middle.",
      [ChartQuestion.part, ChartQuestion.single],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Total in the middle",
            "A ring with the total in the middle.", [_i, _v, _a], _donutTotal),
        ChartPreset(
            "Leader in the middle",
            "The largest share named in the middle, lit.",
            [_i, _v],
            _donutLeader),
        ChartPreset("Thin ring", "A thin ring with a key.", [_a], _donutThin),
        ChartPreset(
            "Half doughnut",
            "An arch with the total in its opening: shares of seats.",
            [_i, _a],
            _donutHalf),
        ChartPreset("Gapped", "Gaps between the parts: friendlier.", [_i],
            _donutGapped),
      ]),
  ChartKind(
      ChartType.waffle,
      "Waffle",
      "A share as so many in a hundred.",
      [ChartQuestion.part, ChartQuestion.single],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset(
            "Squares", "A hundred squares shared out.", [_i, _v], _waffle),
        ChartPreset(
            "Filling in", "The squares fill one by one.", [_v], _waffleFill,
            plays: true),
      ]),
  ChartKind(
      ChartType.radialBar,
      "Radial bars",
      "A few values as rings round a circle.",
      [ChartQuestion.magnitude, ChartQuestion.single],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Rings", "Rings, largest outside.", [_i, _v], _radial),
        ChartPreset(
            "Swept round", "The rings sweep round in turn.", [_v], _radialSweep,
            plays: true),
      ]),
  ChartKind(
      ChartType.radar,
      "Radar",
      "A profile across five or six measures.",
      [ChartQuestion.magnitude],
      _radarReads,
      "three or more columns of numbers",
      [
        ChartPreset(
            "Profile", "Filled shapes with a polygon grid.", [_i, _a], _radar),
        ChartPreset("Leader against the rest",
            "The leader lit, the others faded.", [_a, _v], _radarLit),
      ],
      caveat:
          "The shape depends on the axis order: Radial bars or small charts are often clearer."),
  ChartKind(
      ChartType.gauge,
      "Gauge",
      "One value against its range or target.",
      [ChartQuestion.single],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Dial", "The first value on a dial.", [_i, _a], _gauge),
        ChartPreset(
            "Sweeping", "The dial sweeps up to the value.", [_v], _gaugeSweep,
            plays: true),
      ],
      caveat: "Shows little for its size: a Bullet says more."),
  ChartKind(
      ChartType.pictogram,
      "Pictogram",
      "Counts as rows of icons: people, coins, tickets.",
      [ChartQuestion.part, ChartQuestion.single, ChartQuestion.magnitude],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("People", "A row of people, coloured by the shares.",
            [_i, _v], _pictoPeople),
        ChartPreset("Coins", "Coins, popping in.", [_i, _v], _pictoCoins,
            plays: true),
      ]),
  ChartKind(
      ChartType.sankey,
      "Flow",
      "Amounts flowing from sources into uses.",
      [ChartQuestion.flow],
      _flowReads,
      "labels like “Tickets > Revenue” and an amount",
      [
        ChartPreset("Left to right", "Flows coloured by where they start.",
            [_a, _i], _sankey),
        ChartPreset(
            "Growing", "The flows grow across in turn.", [_v], _sankeyGrow,
            plays: true),
      ]),
  ChartKind(
      ChartType.treemap,
      "Treemap",
      "Many parts of a whole as rectangles.",
      [ChartQuestion.part],
      _ranked,
      "a column of numbers",
      [
        ChartPreset("Tiles", "Largest first, names and values inside.",
            [_a, _i], _treemap),
        ChartPreset("Leader lit", "Every tile grey but the largest.", [_a, _v],
            _treemapLit),
      ]),
  ChartKind(
      ChartType.timeline,
      "Timeline",
      "Events along a line.",
      [ChartQuestion.time],
      _whenReads,
      "a column of numbers (dates or years)",
      [
        ChartPreset(
            "Along a line", "Events placed along a line.", [_i, _a], _timeline),
        ChartPreset(
            "One at a time", "Each event arrives in turn.", [_v], _timelineTurn,
            plays: true),
      ]),
  ChartKind(
      ChartType.funnel,
      "Funnel",
      "Stages narrowing as people drop out.",
      [ChartQuestion.flow],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Stages", "Stages with their values.", [_i, _a], _funnel),
        ChartPreset("Dropping in", "The stages drop in one at a time.", [_v],
            _funnelTurn,
            plays: true),
      ]),
  ChartKind(
      ChartType.bubbles,
      "Bubbles",
      "Sizes as circles packed together.",
      [ChartQuestion.magnitude, ChartQuestion.part],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Packed", "Circles sized by area, names inside.", [_i, _v],
            _bubbles),
        ChartPreset("Leader lit", "Every bubble grey but the largest.",
            [_a, _v], _bubblesLit),
      ]),
  ChartKind(
      ChartType.bullet,
      "Bullet",
      "A value against its target and bands.",
      [ChartQuestion.single, ChartQuestion.deviation],
      _bulletReads,
      "a column of numbers (and one of targets)",
      [
        ChartPreset(
            "Against target", "A bar against its target tick.", [_a], _bullet),
        ChartPreset(
            "Growing", "The bars grow to their values.", [_v, _i], _bulletGrow,
            plays: true),
      ]),
  ChartKind(
      ChartType.slope,
      "Slope",
      "Each thing from one value to the next.",
      [ChartQuestion.time, ChartQuestion.ranking],
      _several,
      "two columns of numbers",
      [
        ChartPreset(
            "Two columns", "Names and values at both ends.", [_a, _i], _slope),
        ChartPreset("Top three lit", "Every line grey but the top three.",
            [_a, _v], _slopeLit),
      ]),
  ChartKind(
      ChartType.shareBar,
      "Share bar",
      "One bar split into its shares.",
      [ChartQuestion.part],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset("Named shares", "One bar, the shares written inside.",
            [_i, _a], _shareBar),
        ChartPreset("Wiped across", "The shares wipe in left to right.", [_v],
            _shareWipe,
            plays: true),
      ]),
  ChartKind(
      ChartType.lollipop,
      "Lollipop",
      "Ranked values with the end point in focus.",
      [ChartQuestion.magnitude, ChartQuestion.ranking, ChartQuestion.deviation],
      _ranked,
      "a column of numbers",
      [
        ChartPreset("Ranked", "Thin stems, round ends, values beside.",
            [_a, _i], _lollipop),
        ChartPreset("Leader lit", "Grey stems, the leader in the accent.",
            [_a, _v], _lollipopLit),
      ]),
  // ---- The research's new kinds (Ken, 2026-11-17).
  ChartKind(
      ChartType.diverging,
      "Diverging bars",
      "Winners and losers either side of zero; survey answers.",
      [ChartQuestion.deviation, ChartQuestion.ranking],
      _ranked,
      "a column of numbers (up and down)",
      [
        ChartPreset(
            "Gains and losses",
            "Sorted, up one colour, down another, names on the far side of zero.",
            [_a, _i, _v],
            _divBars),
        ChartPreset("Agree or disagree",
            "Survey answers centred on the middle one.", [_a], _divLikert,
            needs: _needsThree),
        ChartPreset("Change columns", "Columns up and down from zero.",
            [_a, _v], _divColumns),
      ],
      isNew: true),
  ChartKind(
      ChartType.dumbbell,
      "Dumbbell",
      "The gap between two values for each thing.",
      [ChartQuestion.deviation, ChartQuestion.time],
      _twoNumbers,
      "two columns of numbers",
      [
        ChartPreset("The gap", "Two dots joined, named once at the top.",
            [_a, _i], (e, p) => _mode(e, "gap")),
        ChartPreset(
            "Arrows",
            "From before to after, coloured by the way it went.",
            [_a, _v],
            (e, p) => _mode(e, "arrows")),
        ChartPreset(
            "Range",
            "A pale bar from one to the other, a tick at the second.",
            [_a, _i],
            (e, p) => _mode(e, "range")),
      ],
      isNew: true),
  ChartKind(
      ChartType.waterfall,
      "Waterfall",
      "How a start figure becomes an end figure, step by step.",
      [ChartQuestion.part, ChartQuestion.flow],
      _oneNumber,
      "a column of numbers: a start, then the changes",
      [
        ChartPreset(
            "Bridge",
            "Totals grey, rises and falls coloured, joined by thin lines.",
            [_a, _v],
            (e, p) => _mode(e, "bridge", values: true, grow: true)),
        ChartPreset("Down the page", "Steps running down, for long names.",
            [_a], (e, p) => _mode(e, "down", values: true, grow: true)),
      ],
      isNew: true),
  ChartKind(
      ChartType.heatmap,
      "Heatmap",
      "A value across two dimensions as shades.",
      [
        ChartQuestion.time,
        ChartQuestion.correlation,
        ChartQuestion.distribution
      ],
      _allNumbers,
      "columns of numbers",
      [
        ChartPreset(
            "Grid with values",
            "A shade per value, each number printed.",
            [_a],
            (e, p) => _mode(e, "grid", values: true),
            needs: _needsTwoNumbers),
        ChartPreset("Calendar", "Weeks across, days down.", [_a, _i],
            (e, p) => _first(_mode(e, "calendar")),
            // A day a row, or it is a grid of nothing (found making the
            // Charts canvas: clubs by month drew five grey squares).
            needs: (p) =>
                p.dates.isEmpty ? "a column of dates, a day a row" : null),
        ChartPreset(
            "Stripes",
            "One stripe per row, cool to warm: the poster form.",
            [_i, _v],
            (e, p) => _first(_mode(e, "stripes"))),
      ],
      isNew: true),
  ChartKind(
      ChartType.bigNumber,
      "Big number",
      "One headline figure with its context.",
      [ChartQuestion.single],
      _oneNumber,
      "a column of numbers",
      [
        ChartPreset(
            "Hero number",
            "The latest figure, huge, its name under it.",
            [_v, _i],
            (e, p) => _mode(e, "hero", grow: true)),
        ChartPreset("With the change", "And how it moved since the one before.",
            [_v, _i, _a], (e, p) => _mode(e, "delta", grow: true)),
        ChartPreset("With a sparkline", "Over a small line of its history.",
            [_a, _v], (e, p) => _mode(e, "spark", grow: true)),
        ChartPreset("Four tiles", "The first four, side by side.", [_a, _i],
            (e, p) => _mode(e, "tiles", grow: true)),
      ],
      isNew: true),
  ChartKind(
      ChartType.beeswarm,
      "Dot spread",
      "Every value as a dot, to show how they spread.",
      [ChartQuestion.distribution],
      _allNumbers,
      "a column of numbers",
      [
        ChartPreset("Beeswarm", "Dots pushed apart so none overlap.", [_a, _v],
            (e, p) => _mode(e, "swarm", pop: true)),
        ChartPreset("Strip", "Soft dots along a line.", [_a],
            (e, p) => _mode(e, "strip", pop: true)),
        ChartPreset("Barcode", "A thin tick per value.", [_a],
            (e, p) => _mode(e, "barcode")),
      ],
      isNew: true),
  ChartKind(
      ChartType.parliament,
      "Parliament",
      "Seats by party in a half circle.",
      [ChartQuestion.part],
      _oneNumber,
      "a column of numbers (seats)",
      [
        ChartPreset("Seats in rows", "A dot a seat, the majority marked.",
            [_a, _i, _v], (e, p) => _mode(e, "rows", values: true, pop: true)),
        ChartPreset("Wedges", "Each party a solid wedge.", [_i],
            (e, p) => _mode(e, "wedges", values: true, grow: true)),
      ],
      isNew: true),
  ChartKind(
      ChartType.tileMap,
      "Tile map",
      "A value per place, every place the same size.",
      [ChartQuestion.spatial],
      _oneNumber,
      "a column of numbers, named by place",
      [
        ChartPreset(
            "Squares",
            "A shaded square per place, its code inside.",
            [_a, _i, _v],
            (e, p) => _mode(e, "squares", values: true, pop: true)),
        ChartPreset("Hexagons", "Hexagon tiles.", [_i],
            (e, p) => _mode(e, "hex", values: true, pop: true)),
        ChartPreset("Sized circles", "A circle per place, sized by its value.",
            [_a], (e, p) => _mode(e, "circles", pop: true)),
        ChartPreset(
            "Drawn map",
            "Countries drawn and shaded by value, framed on those named.",
            [_a, _i, _v],
            (e, p) => _mode(e, "drawn", values: true)),
      ],
      caveat:
          "Places named by US state codes (TX), European country codes (FR) or UK regions (London) sit on the map; others in a grid.",
      isNew: true),
  ChartKind(
      ChartType.pyramid,
      "Pyramid",
      "Two sides mirrored band by band: age, home and away.",
      [ChartQuestion.distribution, ChartQuestion.magnitude],
      _twoNumbers,
      "two columns of numbers",
      [
        ChartPreset("Pyramid", "Bands with no gaps, a colour each side.",
            [_a, _i], (e, p) => _mode(e, "pyramid", grow: true)),
        ChartPreset(
            "Butterfly",
            "Names down the middle, values at the ends.",
            [_a, _i, _v],
            (e, p) => _mode(e, "butterfly", values: true, grow: true)),
      ],
      isNew: true),
  // The kinds analysis needs (Ken, 2026-11-17, the improvements report's
  // ninth item): chart_analysis.dart.
  ChartKind(
      ChartType.boxPlot,
      "Box plot",
      "How each column's numbers spread: middle, middle half, the odd ones.",
      [ChartQuestion.distribution],
      _allNumbers,
      "a column of numbers for each group",
      [
        ChartPreset(
            "Box and whiskers",
            "The middle half as a box, its median marked, odd ones as dots.",
            [_a],
            (e, p) => _mode(e, "box", values: true, grow: true)),
        ChartPreset("Violin", "The spread's shape, mirrored.", [_a, _i],
            (e, p) => _mode(e, "violin", grow: true)),
        ChartPreset("Every value", "Each value a dot over a faint box.",
            [_a, _i], (e, p) => _mode(e, "dots", pop: true)),
      ],
      isNew: true),
  ChartKind(
      ChartType.bump,
      "Bump chart",
      "Who is where, period after period: places, not values.",
      [ChartQuestion.ranking, ChartQuestion.time],
      _bumpReads,
      "a date column and a column of numbers for each one",
      [
        ChartPreset(
            "Ranked by value",
            "Each period's largest at the top, a line each through its places.",
            [_a, _i],
            (e, p) => _mode(e, "values")),
        ChartPreset(
            "Places as given",
            "The numbers are already places, 1 the top.",
            [_a],
            (e, p) => _mode(e, "places")),
        ChartPreset(
            "Drawn on",
            "The lines trace along the periods.",
            [_v],
            (e, p) => _mode(e, "values")
                .copyWith(animation: _arrive(ChartAnimationPreset.drawOn)),
            plays: true),
      ],
      isNew: true),
  ChartKind(
      ChartType.marimekko,
      "Marimekko",
      "Each row's parts, each row as wide as its total.",
      [ChartQuestion.part, ChartQuestion.magnitude],
      _allNumbers,
      "two or more columns of numbers",
      [
        ChartPreset(
            "Shares by size",
            "Widths by total, heights by share, % inside.",
            [_a, _i],
            (e, p) => _mode(e, "", values: true, grow: true),
            needs: _needsTwoNumbers),
        ChartPreset("With a key", "The parts named in a key above.", [_a],
            (e, p) => _mode(e, "", grow: true).copyWith(showLegend: true),
            needs: _needsTwoNumbers),
      ],
      isNew: true),
]);

/// _bumpReads is a bump chart's: the periods down a date column, a column
/// of numbers for each one ranked.
SheetLink? _bumpReads(Picks p) => p.dates.isEmpty || p.numbers.length < 2
    ? null
    : p.link(p.dates.first, p.numbers.take(10).toList());

SheetLink? _twoNumbers(Picks p) =>
    p.numbers.length < 2 ? null : p.link(p.labels, p.numbers.take(2).toList());
SheetLink? _allNumbers(Picks p) =>
    p.numbers.isEmpty ? null : p.link(p.labels, p.numbers.take(8).toList());
String? _needsThree(Picks p) =>
    p.numbers.length < 3 ? "three or more columns of answers" : null;
String? _needsTwoNumbers(Picks p) =>
    p.numbers.length < 2 ? "two or more columns of numbers" : null;

/// _mode is [e] drawn its kind's way [m] (ChartDesign.mode).
ChartElement _mode(ChartElement e, String m,
        {bool values = false, bool grow = false, bool pop = false}) =>
    _plain(e).copyWith(
        design: ChartDesign(mode: m),
        showValues: values || e.type == ChartType.bigNumber,
        animation: _arrive(grow
            ? ChartAnimationPreset.grow
            : pop
                ? ChartAnimationPreset.popIn
                : ChartAnimationPreset.fadeIn));

/// _first is [e] reading only its first column of numbers.
ChartElement _first(ChartElement e) => _relink(e,
    (l) => l.copyWith(series: l.series.isEmpty ? l.series : [l.series.first]));

ChartElement _divBars(ChartElement e, Picks p) =>
    _mode(e, "bars", values: true, grow: true);
ChartElement _divColumns(ChartElement e, Picks p) => _relink(
    _mode(e, "columns", values: true, grow: true),
    (l) => l.copyWith(sortBy: -1));
ChartElement _divLikert(ChartElement e, Picks p) => _relink(
    _mode(e, "likert", values: true, grow: true),
    (l) => l.copyWith(series: p.numbers.take(7).toList(), sortBy: -1));

String? _needsName(Picks p) =>
    p.names.isEmpty ? "a column of names to split by" : null;

SheetLink? _candles(Picks p) =>
    p.numbers.length < 4 ? null : p.link(p.labels, p.numbers.take(4).toList());
SheetLink? _radarReads(Picks p) =>
    p.numbers.length < 3 ? null : p.link(p.labels, p.numbers.take(6).toList());
SheetLink? _flowReads(Picks p) => !p.flows || p.numbers.isEmpty
    ? null
    : p.link(p.names.first, [p.numbers.first]);
SheetLink? _bulletReads(Picks p) =>
    p.numbers.isEmpty ? null : p.link(p.labels, p.numbers.take(2).toList());

// ---- The presets (B1: the chart's own fields; B2 adds what they lack).

ChartElement _plain(ChartElement e) => e.copyWith(
    highlights: const [],
    notes: const [],
    showLegend: false,
    design: const ChartDesign());

ChartElement _cleanColumns(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showAxes: true,
    showYLabels: true,
    showValues: false,
    barRadius: 0,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _labelledColumns(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showYLabels: false,
    showValues: true,
    barRadius: 4,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _oneStory(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showYLabels: false,
    showValues: false,
    highlights: [_top(1)],
    notes: [
      ChartNote(
          kind: ChartNoteKind.label,
          who: _leader(e),
          colour: const Color(0xFFFFFFFF))
    ],
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _aboveAverage(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showValues: false,
    highlights: [
      ChartHighlight(
          reach: ChartReach.when,
          op: ">=",
          value: _average(e),
          fade: true,
          colour: _accent),
    ],
    notes: const [ChartNote(kind: ChartNoteKind.line, text: "Average")],
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _posterColumns(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showYLabels: false,
    showAxes: false,
    showValues: true,
    barRadius: 40,
    barGap: 0.18,
    design: const ChartDesign(track: true, valuesInside: true),
    animation: _arrive(ChartAnimationPreset.popIn));

ChartElement _rankedList(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showAxes: false,
    showXLabels: false,
    showValues: true,
    barRadius: 2,
    barGap: 0.3,
    design: const ChartDesign(labelsAbove: true),
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _barsOneLit(ChartElement e, Picks p) =>
    _rankedList(e, p).copyWith(highlights: [_top(1)]);
ChartElement _thickBars(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showAxes: false,
    showXLabels: false,
    showValues: true,
    barRadius: 40,
    barGap: 0.14,
    design: const ChartDesign(valuesInside: true),
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _trackBars(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showAxes: false,
    showXLabels: false,
    showValues: true,
    barRadius: 40,
    barGap: 0.5,
    design: const ChartDesign(track: true),
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _barsScale(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showAxes: true,
    showValues: false,
    barRadius: 0,
    animation: _arrive(ChartAnimationPreset.wipe));
ChartElement _topFive(ChartElement e, Picks p) {
  var made =
      _relink(_rankedList(e, p), (l) => l.copyWith(top: 5, others: true));
  // The rest in grey: a rule picking out just that one bar.
  return made.copyWith(highlights: [
    const ChartHighlight(
        reach: ChartReach.one, who: "All others", colour: Color(0xFFB0B0B0)),
  ]);
}

ChartElement _barRace(ChartElement e, Picks p) {
  if (p.dates.isEmpty) return e;
  var v = p.numbers.first;
  return _relink(
      _rankedList(e, p),
      (l) => l.copyWith(
          labels: p.names.isNotEmpty ? p.names.first : l.labels,
          through: p.dates.first,
          sortBy: v,
          top: math.min(10, math.max(0, l.top)))).copyWith(play: 1.0);
}

ChartElement _pairsValues(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showValues: true,
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _pairsClean(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showYLabels: false,
    showAxes: false,
    showValues: true,
    showLegend: true,
    legend: e.legend.copyWith(placement: LegendPlacement.top),
    animation: _arrive(ChartAnimationPreset.grow, inTurn: true));
ChartElement _pairsSplit(ChartElement e, Picks p) => _relink(_plain(e),
    (l) => l.copyWith(split: p.names.isNotEmpty ? p.names.first : -1));

ChartElement _stackKeyed(ChartElement e, Picks p) => _plain(e).copyWith(
    showLegend: true,
    showGrid: true,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _stackLabelled(ChartElement e, Picks p) => _plain(e).copyWith(
    showLegend: true,
    showValues: true,
    showGrid: false,
    showYLabels: false,
    barGap: 0.2,
    animation: _arrive(ChartAnimationPreset.popIn));
ChartElement _stackLayers(ChartElement e, Picks p) => _plain(e).copyWith(
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.grow, inTurn: true));

ChartElement _editorialLines(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showPoints: false,
    strokeWidth: 2.2,
    smooth: false,
    animation: _arrive(ChartAnimationPreset.drawOn));
ChartElement _linesLit(ChartElement e, Picks p) =>
    _editorialLines(e, p).copyWith(highlights: [_top(3)]);
ChartElement _heroLine(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    showPoints: true,
    pointSize: 5,
    strokeWidth: 4.5,
    smooth: true,
    animation: _arrive(ChartAnimationPreset.drawOn));
ChartElement _logLines(ChartElement e, Picks p) =>
    _editorialLines(e, p).copyWith(logScale: true);
ChartElement _splitLines(ChartElement e, Picks p) => p.names.isEmpty
    ? e
    : _relink(_editorialLines(e, p),
        (l) => l.copyWith(split: p.names.first, colourBy: -1));
ChartElement _stepLines(ChartElement e, Picks p) =>
    _editorialLines(e, p).copyWith(design: const ChartDesign(step: true));
ChartElement _drawnLines(ChartElement e, Picks p) => _editorialLines(e, p)
    .copyWith(animation: _arrive(ChartAnimationPreset.drawOn, inTurn: true));

ChartElement _area(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    smooth: false,
    animation: _arrive(ChartAnimationPreset.wipe));
ChartElement _areaSoft(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    smooth: true,
    animation: _arrive(ChartAnimationPreset.wipe));
ChartElement _areaWipe(ChartElement e, Picks p) =>
    _areaSoft(e, p).copyWith(animation: _arrive(ChartAnimationPreset.wipe));

ChartElement _scatterNamed(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: true,
    showValues: true,
    pointSize: 6,
    animation: _arrive(ChartAnimationPreset.popIn));
ChartElement _scatterLit(ChartElement e, Picks p) =>
    _scatterNamed(e, p).copyWith(highlights: [_top(3)], showValues: false);
ChartElement _scatterPop(ChartElement e, Picks p) =>
    _scatterNamed(e, p).copyWith(
        showValues: false, animation: _arrive(ChartAnimationPreset.random));

ChartElement _scatterQuadrants(ChartElement e, Picks p) => _scatterNamed(e, p)
    .copyWith(showGrid: false, design: const ChartDesign(quadrants: true));
ChartElement _scatterTrend(ChartElement e, Picks p) => _scatterNamed(e, p)
    .copyWith(showValues: false, design: const ChartDesign(trend: true));
ChartElement _scatterJoined(ChartElement e, Picks p) =>
    _scatterNamed(e, p).copyWith(
        design: const ChartDesign(connect: true),
        animation: _arrive(ChartAnimationPreset.drawOn));

ChartElement _candleClassic(ChartElement e, Picks p) => _plain(e)
    .copyWith(showGrid: true, animation: _arrive(ChartAnimationPreset.wipe));
ChartElement _candleClean(ChartElement e, Picks p) => _plain(e).copyWith(
    showGrid: false,
    barGap: 0.25,
    animation: _arrive(ChartAnimationPreset.grow));

ChartElement _pieOne(ChartElement e, Picks p) => _plain(e).copyWith(
    highlights: [_top(1)],
    showValues: true,
    animation: _arrive(ChartAnimationPreset.sweep));
ChartElement _pieLabelled(ChartElement e, Picks p) => _plain(e).copyWith(
    showValues: true,
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _pieSweep(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.sweep));

ChartElement _donutTotal(ChartElement e, Picks p) => _plain(e).copyWith(
    innerRadius: 0.62,
    centreLabel: "{total}",
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.sweep));
ChartElement _donutLeader(ChartElement e, Picks p) => _plain(e).copyWith(
    innerRadius: 0.62,
    centreLabel: "{leader by ${_seriesName(e)}}",
    highlights: [_top(1, named: false)],
    animation: _arrive(ChartAnimationPreset.sweep));
ChartElement _donutThin(ChartElement e, Picks p) => _plain(e).copyWith(
    innerRadius: 0.82,
    centreLabel: "",
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.sweep));
ChartElement _donutHalf(ChartElement e, Picks p) => _plain(e).copyWith(
    innerRadius: 0.58,
    centreLabel: "{total}",
    showLegend: true,
    design: const ChartDesign(half: true),
    animation: _arrive(ChartAnimationPreset.sweep));
ChartElement _donutGapped(ChartElement e, Picks p) => _plain(e).copyWith(
    innerRadius: 0.62,
    centreLabel: "{total}",
    showLegend: true,
    design: const ChartDesign(gaps: true),
    animation: _arrive(ChartAnimationPreset.grow));
String _seriesName(ChartElement e) =>
    e.data.series.isEmpty ? "" : e.data.series.first.name;

ChartElement _waffle(ChartElement e, Picks p) => _plain(e).copyWith(
    showLegend: true, animation: _arrive(ChartAnimationPreset.fadeIn));
ChartElement _waffleFill(ChartElement e, Picks p) => _plain(e)
    .copyWith(showLegend: true, animation: _arrive(ChartAnimationPreset.popIn));

ChartElement _radial(ChartElement e, Picks p) => _relink(
    _plain(e).copyWith(
        showValues: true, animation: _arrive(ChartAnimationPreset.grow)),
    (l) => l.copyWith(sortBy: p.numbers.first));
ChartElement _radialSweep(ChartElement e, Picks p) =>
    _radial(e, p).copyWith(animation: _arrive(ChartAnimationPreset.sweep));

ChartElement _radar(ChartElement e, Picks p) => _plain(e).copyWith(
    showLegend: true,
    showGrid: true,
    animation: _arrive(ChartAnimationPreset.grow));
ChartElement _radarLit(ChartElement e, Picks p) =>
    _radar(e, p).copyWith(highlights: [_top(1)]);

ChartElement _gauge(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.none));
ChartElement _gaugeSweep(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.sweep));

ChartElement _pictoPeople(ChartElement e, Picks p) => _plain(e).copyWith(
    pictoShape: PictoShape.person,
    pictoCount: 20,
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.fadeIn));
ChartElement _pictoCoins(ChartElement e, Picks p) => _plain(e).copyWith(
    pictoShape: PictoShape.coin,
    pictoCount: 30,
    showLegend: true,
    animation: _arrive(ChartAnimationPreset.popIn));

ChartElement _sankey(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.none));
ChartElement _sankeyGrow(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.wipe));

ChartElement _treemap(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.popIn));
ChartElement _treemapLit(ChartElement e, Picks p) =>
    _treemap(e, p).copyWith(highlights: [_top(1)]);

ChartElement _timeline(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.none));
ChartElement _timelineTurn(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.popIn));

ChartElement _funnel(ChartElement e, Picks p) => _relink(
    _plain(e).copyWith(
        showValues: true, animation: _arrive(ChartAnimationPreset.none)),
    (l) => l.copyWith(sortBy: p.numbers.first));
ChartElement _funnelTurn(ChartElement e, Picks p) =>
    _funnel(e, p).copyWith(animation: _arrive(ChartAnimationPreset.popIn));

ChartElement _bubbles(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.popIn));
ChartElement _bubblesLit(ChartElement e, Picks p) =>
    _bubbles(e, p).copyWith(highlights: [_top(1)]);

ChartElement _bullet(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.none));
ChartElement _bulletGrow(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.grow));

ChartElement _slope(ChartElement e, Picks p) => _plain(e).copyWith(
    showValues: true, animation: _arrive(ChartAnimationPreset.drawOn));
ChartElement _slopeLit(ChartElement e, Picks p) =>
    _slope(e, p).copyWith(highlights: [_top(3)]);

ChartElement _shareBar(ChartElement e, Picks p) => _relink(
    _plain(e).copyWith(
        showValues: true, animation: _arrive(ChartAnimationPreset.none)),
    (l) => l.copyWith(sortBy: p.numbers.first));
ChartElement _shareWipe(ChartElement e, Picks p) =>
    _shareBar(e, p).copyWith(animation: _arrive(ChartAnimationPreset.wipe));

ChartElement _lollipop(ChartElement e, Picks p) => _plain(e)
    .copyWith(showValues: true, animation: _arrive(ChartAnimationPreset.grow));
ChartElement _lollipopLit(ChartElement e, Picks p) =>
    _lollipop(e, p).copyWith(highlights: [_top(1)]);

// ---- Modifiers: chips under the presets rather than more cards.

/// ChartModifier is one of the extras a preset can be given.
enum ChartModifier {
  highlight("Highlight", "Pick out the top one; fade the rest"),
  average("Average line", "A dashed line at the average"),
  split("Small charts", "One per thing, on one scale"),
  play("Play through", "Through the date column"),
  log("Log scale", "Each step ten times the last");

  final String label, says;
  const ChartModifier(this.label, this.says);

  /// fits is whether it means something for [type] with [p].
  bool fits(ChartType type, Picks p) => switch (this) {
        highlight => true,
        average => type.isCartesian,
        split => p.names.isNotEmpty && (type.isLinear || type.isBar),
        play => p.dates.isNotEmpty &&
            type != ChartType.line &&
            type != ChartType.area,
        log => type.isCartesian && !type.isBar,
      };

  ChartElement apply(ChartElement e, Picks p) => switch (this) {
        highlight => e.copyWith(highlights: [...e.highlights, _top(1)]),
        average => e.copyWith(notes: [
            ...e.notes,
            const ChartNote(kind: ChartNoteKind.line, text: "Average"),
          ]),
        split =>
          _relink(e, (l) => l.copyWith(split: p.names.first, colourBy: -1)),
        play => _relink(e, (l) => l.copyWith(through: p.dates.first))
            .copyWith(play: 1),
        log => e.copyWith(logScale: true),
      };
}

/// picksOf sorts ticked [picks] of [range] by what they hold.
Picks picksOf(DataSheet sheet, CellRange range, List<int> picks,
    List<int> numbers, List<int> dates, List<int> names) {
  return Picks(sheet, range, numbers: [
    for (var p in picks)
      if (numbers.contains(p)) p
  ], dates: [
    for (var p in picks)
      if (dates.contains(p)) p
  ], names: [
    for (var p in picks)
      if (names.contains(p)) p
  ]);
}

/// KindFit is how well a kind suits the ticked columns: [score] 1 for
/// well, less where it reads badly, and [why] says so in plain words (Ken,
/// 2026-11-17, the improvements report's third item: the gallery offered a
/// gauge of eight clubs and a pie of twenty as readily as bars).
class KindFit {
  final double score;
  final String? why;
  const KindFit(this.score, [this.why]);
  static const good = KindFit(1);
  bool get poor => score < 0.6;
}

const _parts = {
  ChartType.pie,
  ChartType.donut,
  ChartType.shareBar,
  ChartType.parliament,
};

/// kindFit is how well [k] suits [p]'s ticked columns (see KindFit). Only
/// for a kind that can read them.
KindFit kindFit(ChartKind k, Picks p) {
  var g = p.range;
  var rows = g.rows - 1;
  var numbers = p.numbers;
  List<double> col(int c) => [
        for (var r = g.r0 + 1; r <= g.r1; r++)
          if (sheetValue(p.sheet, r, g.c0 + c) case double v) v
      ];
  var first = numbers.isEmpty ? const <double>[] : col(numbers.first);
  var below = first.any((v) => v < 0);
  // A long sheet (dates and names ticked) is read at its latest date: as
  // many rows as names.
  if (p.dates.isNotEmpty && p.names.isNotEmpty) {
    var seen = <String>{};
    for (var r = g.r0 + 1; r <= g.r1; r++) {
      seen.add(sheetShown(p.sheet, r, g.c0 + p.names.first));
    }
    if (k.questions.contains(ChartQuestion.time) == false) rows = seen.length;
  }
  switch (k.type) {
    case var t when _parts.contains(t):
      if (below) return const KindFit(0.2, "Shares can't be below zero.");
      if (rows > 6) {
        return KindFit(
            0.3,
            "$rows parts: past six they are hard to tell "
            "apart. Bars read better.");
      }
    case ChartType.waffle || ChartType.pictogram:
      if (below) return const KindFit(0.2, "Shares can't be below zero.");
      if (rows > 4) {
        return KindFit(
            0.4,
            "$rows parts in one picture: best with two to "
            "four.");
      }
    case ChartType.gauge:
      if (rows > 1) {
        return KindFit(0.4, "Shows one number: the first of $rows.");
      }
    case ChartType.bigNumber:
      if (rows > 1 && p.dates.isEmpty) {
        return KindFit(0.5, "Shows one number, the last of $rows.");
      }
    case ChartType.radar:
      if (rows < 3) return const KindFit(0.2, "Needs three or more spokes.");
      if (rows > 10) return KindFit(0.4, "$rows spokes are hard to read.");
    case ChartType.line || ChartType.area:
      if (rows < 3) return KindFit(0.4, "Only $rows dates to join.");
    case ChartType.bar:
      if (rows > 15) {
        return KindFit(0.6, "$rows columns: Bars fit long lists better.");
      }
    case ChartType.bubbles:
      if (below) return const KindFit(0.2, "Sizes can't be below zero.");
      if (rows > 25) return KindFit(0.5, "$rows circles: hard to compare.");
    case ChartType.treemap:
      if (below) return const KindFit(0.2, "Sizes can't be below zero.");
      if (rows < 3) return const KindFit(0.5, "Few parts for a treemap.");
    case ChartType.funnel:
      var falls = 0;
      for (var i = 1; i < first.length; i++) {
        if (first[i] <= first[i - 1]) falls++;
      }
      if (first.length > 1 && falls * 2 < first.length - 1) {
        return const KindFit(0.4, "Its numbers don't fall stage by stage.");
      }
    case ChartType.timeline:
      var years = first.isNotEmpty &&
          first.every((v) => v == v.roundToDouble() && v > 1000 && v < 3000);
      if (!years && p.dates.isEmpty) {
        return const KindFit(0.4, "Its numbers aren't years or dates.");
      }
    case ChartType.tileMap:
      var named = p.names.isNotEmpty ? p.names.first : p.labels;
      var codes = [
        for (var r = g.r0 + 1; r <= g.r1; r++)
          sheetShown(p.sheet, r, g.c0 + named).trim().toUpperCase()
      ];
      var countries = codes.where((c) => countryFor(c) != null).length;
      if (tileMapOf(codes) == null && countries * 2 < codes.length) {
        return const KindFit(0.5,
            "Not places on a map (countries, US states, UK regions): drawn as a grid.");
      }
    case ChartType.slope || ChartType.dumbbell || ChartType.pyramid:
      if (numbers.length > 2) {
        return KindFit(
            0.8,
            "Uses the first two of ${numbers.length} "
            "columns.");
      }
    case ChartType.heatmap:
      if (numbers.length < 3) {
        return const KindFit(0.5, "Best with three or more columns.");
      }
    case ChartType.beeswarm:
      if (rows < 8) return const KindFit(0.5, "Few values to spread.");
    case ChartType.scatter:
      if (rows < 5) return const KindFit(0.6, "Few points to relate.");
    case ChartType.diverging:
      if (!below) {
        return const KindFit(0.5, "Nothing below zero to diverge.");
      }
    default:
      break;
  }
  return KindFit.good;
}

/// presetChart is [kind]'s [preset] (and [mods]) made from [p]: a new chart
/// of [like]'s size, reading the ticked columns, its data read. Null when
/// the kind can't read them, or the preset needs what they lack.
ChartElement? presetChart(
    ChartKind kind, ChartPreset preset, Picks p, ChartElement like,
    {Set<ChartModifier> mods = const {}}) {
  var link = kind.reads(p);
  if (link == null || preset.needs?.call(p) != null) return null;
  // A long sheet -- a row a club a week -- ranked or shared out: each
  // club once, as at the latest date, not every week's row (found making
  // the Charts canvas: Bars of Week, Club and Pts listed 36 bars).
  if (!kind.questions.contains(ChartQuestion.time) &&
      p.names.isNotEmpty &&
      p.dates.isNotEmpty) {
    link = link.copyWith(
        labels: p.dates.contains(link.labels) ? p.names.first : link.labels,
        through: p.dates.first);
  }
  ChartElement read(ChartElement c) => c.copyWith(
      data: chartDataOf(p.sheet, c.sheet!, const ChartData(),
          type: c.type, highlights: chartLights(c.highlights, p.sheet)));
  var chart = read(ChartElement(
      ElementBase(id: like.id, width: like.width, height: like.height),
      type: kind.type,
      sheet: link,
      title: like.title));
  chart = preset.apply(chart, p);
  for (var m in mods) {
    if (m.fits(chart.type, p)) chart = m.apply(chart, p);
  }
  return read(chart);
}

/// reread is [c] with its data read again from [sheet] -- after a style has
/// recoloured its series, so its faded marks are tints of the new colours.
ChartElement reread(ChartElement c, DataSheet sheet) {
  var link = c.sheet;
  if (link == null) return c;
  return c.copyWith(
      data: chartDataOf(sheet, link, c.data,
          type: c.type, highlights: chartLights(c.highlights, sheet)));
}

/// _way is [e] drawn another of its kind's ways (ChartDesign.mode).
ChartElement _way(ChartElement e, String m) =>
    e.copyWith(design: e.design.copyWith(mode: m));

/// _waysOf is the starting designs the older kinds gained with their other
/// ways (Ken, 2026-11-17: "do the remaining designs"), after their own.
final Map<ChartType, List<ChartPreset>> _waysOf = {
  // The analysis ways (Ken, 2026-11-17, the improvements report's ninth
  // item).
  ChartType.area: [
    ChartPreset(
        "Shares of the whole",
        "Each band its share, stacked to a hundred: how the mix changes.",
        [_a],
        (e, p) => _way(_plain(e), "share").copyWith(
            showLegend: true, animation: _arrive(ChartAnimationPreset.wipe)),
        needs: _needsTwoNumbers),
  ],
  ChartType.scatter: [
    ChartPreset(
        "Sized by a third number",
        "A bubble each, as big as its third number: spend, points and crowd.",
        [_a, _i],
        (e, p) => _relink(_way(_scatterNamed(e, p), "sized"),
            (l) => l.copyWith(series: [p.numbers[1], p.numbers[2]])),
        needs: (p) =>
            p.numbers.length < 3 ? "a third column of numbers" : null),
    ChartPreset(
        "Over time, joined",
        "The points joined in date order, each named by its date.",
        [_a, _v],
        (e, p) => _relink(
            _scatterNamed(e, p).copyWith(
                design: const ChartDesign(connect: true),
                animation: _arrive(ChartAnimationPreset.drawOn)),
            (l) => l.copyWith(pointNames: p.dates.first)),
        needs: (p) => p.dates.isEmpty ? "a date column" : null),
  ],
  ChartType.bar: [
    ChartPreset(
        "Histogram",
        "How the numbers spread: counted into eight ranges, columns touching.",
        [_a],
        (e, p) => _relink(_cleanColumns(e, p), (l) => l.copyWith(bins: 8))
            .copyWith(barGap: 0.04, showValues: true)),
  ],
  ChartType.funnel: [
    ChartPreset(
        "Bars from one edge",
        "Stages as bars on one baseline, so lengths compare; the share kept beside.",
        [_a],
        (e, p) => _way(_funnel(e, p), "bars")),
    ChartPreset(
        "What was lost",
        "Each stage over a pale ghost of the one before.",
        [_a, _v],
        (e, p) => _way(_funnelTurn(e, p), "ghost")),
  ],
  ChartType.bubbles: [
    ChartPreset(
        "In a row",
        "Circles side by side on one floor, so sizes compare.",
        [_i, _a],
        (e, p) => _way(_bubbles(e, p), "row")),
    ChartPreset(
        "In groups",
        "A named cluster per group, from a second column of names.",
        [_a, _i],
        (e, p) => _way(
            p.names.length > 1
                ? _relink(
                    _bubbles(e, p), (l) => l.copyWith(colourBy: p.names[1]))
                : _relink(_bubbles(e, p),
                    (l) => l.copyWith(series: p.numbers.take(4).toList())),
            "clusters"),
        needs: (p) => p.names.length < 2 && p.numbers.length < 2
            ? "a second column of names to group by"
            : null),
  ],
  ChartType.timeline: [
    ChartPreset(
        "Down the page",
        "Events down a line at the left, for long stories.",
        [_i, _v],
        (e, p) => _way(_timelineTurn(e, p), "down")),
  ],
  ChartType.gauge: [
    ChartPreset("Needle over bands", "A needle over three graduated bands.",
        [_i], (e, p) => _way(_gaugeSweep(e, p), "bands")),
    ChartPreset("Speedometer", "Open at the bottom with ticks, like a car's.",
        [_i, _v], (e, p) => _way(_gaugeSweep(e, p), "dial")),
  ],
  ChartType.pictogram: [
    ChartPreset(
        "A row each",
        "Icons in a row per category, compared like bars.",
        [_a, _i],
        (e, p) => _way(_pictoPeople(e, p), "rows")),
    ChartPreset("One big icon", "A large figure filling up to the first share.",
        [_i, _v], (e, p) => _way(_pictoPeople(e, p), "big")),
  ],
  ChartType.sankey: [
    ChartPreset("Follow the largest", "Every flow faded but the largest.",
        [_a, _v], (e, p) => _sankey(e, p).copyWith(highlights: [_top(1)])),
    ChartPreset(
        "Where the money goes",
        "What comes in one colour, what goes out another, profit in the accent.",
        [_i, _a],
        (e, p) => _way(_sankey(e, p), "money")),
  ],
  ChartType.treemap: [
    ChartPreset(
        "Up and down",
        "Sized by the first number, coloured by whether the second is up or down.",
        [_a],
        // The second number read too: the change it is coloured by
        // (found making the Charts canvas: it read the size alone).
        (e, p) => _relink(_way(_treemap(e, p), "market"),
            (l) => l.copyWith(series: p.numbers.take(2).toList())),
        needs: (p) =>
            p.numbers.length < 2 ? "a second column: the change" : null),
  ],
  ChartType.shareBar: [
    ChartPreset("From the middle", "Two sides growing out from a centre line.",
        [_a, _v], (e, p) => _way(_shareWipe(e, p), "middle")),
    ChartPreset(
        "With the halfway mark",
        "A line at the halfway mark and how many make a majority.",
        [_a, _v],
        (e, p) => _way(_shareBar(e, p), "majority")),
  ],
  ChartType.lollipop: [
    ChartPreset(
        "From the average",
        "Stems out from an average line, above and below in two colours.",
        [_a],
        (e, p) => _way(_lollipop(e, p), "average")),
    ChartPreset("Value in the dot", "Large dots with the value inside.",
        [_i, _v], (e, p) => _way(_lollipop(e, p), "big")),
  ],
  ChartType.slope: [
    ChartPreset(
        "Rank to rank",
        "Places rather than values: who went up the table.",
        [_a, _v],
        (e, p) => _way(_slope(e, p), "rank")),
  ],
  ChartType.radialBar: [
    ChartPreset(
        "Rings on tracks",
        "Full rings on pale tracks, each a share of the largest.",
        [_i, _v],
        (e, p) => _way(_radialSweep(e, p), "rings")),
    ChartPreset(
        "Bars round a circle",
        "Bars standing out from a centre circle.",
        [_i, _v],
        (e, p) => _way(_radial(e, p), "bars")),
    ChartPreset("Rose", "A wedge each, its area matching its value.", [_a, _i],
        (e, p) => _way(_radial(e, p), "rose")),
  ],
  ChartType.radar: [
    ChartPreset("Dots on spokes", "Values as dots, no filled area to mislead.",
        [_a], (e, p) => _way(_radar(e, p), "dots")),
    ChartPreset(
        "Against another",
        "The first filled, the others as grey outlines behind it.",
        [_a, _v],
        (e, p) => _way(_radar(e, p), "compare")),
  ],
  ChartType.waffle: [
    ChartPreset("Dots", "Circles instead of squares, for a rounded look.", [_i],
        (e, p) => _way(_waffle(e, p), "dots")),
    ChartPreset("Rising", "Filling from the bottom up, like a column.",
        [_i, _v], (e, p) => _way(_waffleFill(e, p), "rising")),
  ],
  ChartType.candlestick: [
    ChartPreset("Print mono", "Up candles hollow, down solid, in one ink.",
        [_a], (e, p) => _way(_candleClassic(e, p), "mono")),
    ChartPreset("Price bars", "A tick each side for open and close.", [_a],
        (e, p) => _way(_candleClassic(e, p), "bars")),
    ChartPreset("Simple range", "High to low as a bar, the close as a dot.",
        [_v, _i], (e, p) => _way(_candleClean(e, p), "range")),
  ],
};

List<ChartKind> _withWays(List<ChartKind> kinds) => [
      for (var k in kinds)
        _waysOf[k.type] == null
            ? k
            : ChartKind(k.type, k.name, k.use, k.questions, k.reads, k.needs,
                [...k.presets, ..._waysOf[k.type]!],
                caveat: k.caveat, isNew: k.isNew),
    ];

// chart_design.dart is how a chart's marks are drawn beyond its type: the
// gallery designs' choices, kept apart so the chart's list stays readable.
// Each is off unless a design or the Charts tab turns it on.

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

class ChartDesign {
  /// track draws a pale full-length bar behind each bar, so a bar reads as
  /// so much of the whole filled (a poster's "track bars").
  final bool track;

  /// valuesInside writes each bar's value inside its end, in an ink that
  /// reads on it, rather than past it.
  final bool valuesInside;

  /// labelsAbove puts a sideways bar's name on its own line above it, so a
  /// long name gets the whole width.
  final bool labelsAbove;

  /// step draws a line flat then straight up: for values that jump.
  final bool step;

  /// quadrants splits a scatter in four at its averages, with dashed lines.
  final bool quadrants;

  /// trend draws a scatter's straight trend line through its points.
  final bool trend;

  /// connect joins a scatter's points in the order of the rows.
  final bool connect;

  /// half draws a pie or doughnut as an arch, for shares of seats.
  final bool half;

  /// gaps leaves a gap between a pie's or doughnut's slices.
  final bool gaps;

  /// mode is how a newer kind is drawn (a dumbbell's "gap" or "range", a
  /// heatmap's "grid" or "stripes"; see chartModes). Empty, its first.
  final String mode;

  /// even spaces a timeline's events evenly in order, the time between them
  /// in the gaps ("12 yrs"), for dates bunched in one stretch.
  final bool even;

  const ChartDesign({
    this.track = false,
    this.valuesInside = false,
    this.labelsAbove = false,
    this.step = false,
    this.quadrants = false,
    this.trend = false,
    this.connect = false,
    this.half = false,
    this.gaps = false,
    this.mode = "",
    this.even = false,
  });

  bool get any =>
      track ||
      valuesInside ||
      labelsAbove ||
      step ||
      quadrants ||
      trend ||
      connect ||
      half ||
      gaps ||
      even ||
      mode.isNotEmpty;

  ChartDesign copyWith({
    bool? track,
    bool? valuesInside,
    bool? labelsAbove,
    bool? step,
    bool? quadrants,
    bool? trend,
    bool? connect,
    bool? half,
    bool? gaps,
    String? mode,
    bool? even,
  }) =>
      ChartDesign(
        track: track ?? this.track,
        valuesInside: valuesInside ?? this.valuesInside,
        labelsAbove: labelsAbove ?? this.labelsAbove,
        step: step ?? this.step,
        quadrants: quadrants ?? this.quadrants,
        trend: trend ?? this.trend,
        connect: connect ?? this.connect,
        half: half ?? this.half,
        gaps: gaps ?? this.gaps,
        mode: mode ?? this.mode,
        even: even ?? this.even,
      );

  Map<String, dynamic> toJson() => {
        if (track) "track": true,
        if (valuesInside) "valuesInside": true,
        if (labelsAbove) "labelsAbove": true,
        if (step) "step": true,
        if (quadrants) "quadrants": true,
        if (trend) "trend": true,
        if (connect) "connect": true,
        if (half) "half": true,
        if (gaps) "gaps": true,
        if (mode.isNotEmpty) "mode": mode,
        if (even) "even": true,
      };

  static ChartDesign fromJson(Object? j) {
    if (j is! Map) return const ChartDesign();
    bool b(String k) => j[k] == true;
    return ChartDesign(
      track: b("track"),
      valuesInside: b("valuesInside"),
      labelsAbove: b("labelsAbove"),
      step: b("step"),
      quadrants: b("quadrants"),
      trend: b("trend"),
      connect: b("connect"),
      half: b("half"),
      gaps: b("gaps"),
      mode: jsonString(j["mode"], ""),
      even: b("even"),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChartDesign && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

/// chartModes is each new kind's ways, as (name, what it says); the first
/// is the one an empty ChartDesign.mode means.
const Map<String, List<(String, String)>> chartModes = {
  "diverging": [
    ("bars", "Bars either side"),
    ("likert", "Agree or disagree"),
    ("columns", "Columns up and down")
  ],
  "dumbbell": [
    ("gap", "Two dots joined"),
    ("arrows", "Arrows"),
    ("range", "A range")
  ],
  "waterfall": [("bridge", "Bridge"), ("down", "Down the page")],
  "heatmap": [
    ("grid", "Grid"),
    ("calendar", "Calendar"),
    ("stripes", "Stripes")
  ],
  "bigNumber": [
    ("hero", "The number"),
    ("delta", "With the change"),
    ("spark", "With a sparkline"),
    ("tiles", "Four tiles")
  ],
  "beeswarm": [
    ("swarm", "Beeswarm"),
    ("strip", "A strip"),
    ("barcode", "Barcode")
  ],
  "parliament": [("rows", "Seats in rows"), ("wedges", "Wedges")],
  "tileMap": [
    ("squares", "Squares"),
    ("hex", "Hexagons"),
    ("circles", "Sized circles"),
    ("drawn", "A drawn map")
  ],
  "pyramid": [("pyramid", "Pyramid"), ("butterfly", "Butterfly")],
  "scatter": [("dots", "Dots"), ("sized", "Sized by a third number")],
  "area": [("filled", "Filled"), ("share", "Shares of the whole")],
  "boxPlot": [
    ("box", "Box and whiskers"),
    ("violin", "Violin"),
    ("dots", "Every value")
  ],
  "bump": [("values", "Ranked by value"), ("places", "Places as given")],
  // The older kinds' other ways (chart_variants.dart, and candles in
  // chart_cartesian.dart); each one's first is its own painter.
  "funnel": [
    ("tapered", "Tapered"),
    ("bars", "Bars from one edge"),
    ("ghost", "What was lost")
  ],
  "bubbles": [
    ("packed", "Packed"),
    ("row", "In a row"),
    ("clusters", "In groups")
  ],
  "timeline": [
    ("line", "Along a line"),
    ("down", "Down the page"),
    ("spans", "Spans"),
    ("lanes", "Swimlanes"),
    ("eras", "Era bands"),
    ("value", "On a value line"),
    ("cards", "Cards"),
    ("bubbles", "Bubbles in lanes"),
    ("serpentine", "Serpentine"),
    ("progress", "We are here"),
    ("zoom", "A stretch zoomed in"),
    ("spiral", "Spiral"),
    ("thenNow", "Then and now"),
    ("strip", "Event strip"),
    ("aligned", "From the same start")
  ],
  "gauge": [("arc", "Arc"), ("bands", "Needle over bands"), ("dial", "Dial")],
  "pictogram": [
    ("icons", "Icons"),
    ("rows", "A row each"),
    ("big", "One big icon")
  ],
  "sankey": [("flows", "A colour each"), ("money", "Where the money goes")],
  "treemap": [("tiles", "Tiles"), ("market", "Up and down")],
  "shareBar": [
    ("bar", "One bar"),
    ("middle", "From the middle"),
    ("majority", "With the halfway mark")
  ],
  "lollipop": [
    ("ranked", "Ranked"),
    ("average", "From the average"),
    ("big", "Value in the dot")
  ],
  "slope": [("values", "Values"), ("rank", "Rank to rank")],
  "radialBar": [
    ("arcs", "Arcs"),
    ("rings", "Rings"),
    ("bars", "Bars round a circle"),
    ("rose", "Rose")
  ],
  "radar": [
    ("filled", "Filled"),
    ("dots", "Dots on spokes"),
    ("compare", "Against another")
  ],
  "waffle": [("squares", "Squares"), ("dots", "Dots"), ("rising", "Rising")],
  "candlestick": [
    ("candles", "Candles"),
    ("mono", "Print mono"),
    ("bars", "Price bars"),
    ("range", "Simple range")
  ],
};

/// modeOf is [design]'s way for a kind named [type], its first when unset.
String modeOf(ChartDesign design, String type) {
  var ways = chartModes[type];
  if (ways == null) return design.mode;
  return ways.any((w) => w.$1 == design.mode) ? design.mode : ways.first.$1;
}

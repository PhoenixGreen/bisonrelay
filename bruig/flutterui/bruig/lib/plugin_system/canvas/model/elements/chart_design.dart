// chart_design.dart is how a chart's marks are drawn beyond its type: the
// choices the gallery's starting designs need (Ken, 2026-11-17; prototype
// v7 and its research) that a chart had no field for. Kept together so the
// chart's own list stays readable; each is off unless a design, or the
// Charts tab, turns it on.

class ChartDesign {
  /// track draws a pale full-length bar behind each bar, so a bar reads as
  /// so much of the whole filled (a poster's "track bars").
  final bool track;

  /// valuesInside writes each bar's value inside its end, in an ink that
  /// reads on it, rather than past it.
  final bool valuesInside;

  /// labelsAbove puts a sideways bar's name on its own line above it, so a
  /// long name gets the whole width (Datawrapper's "labels on a separate
  /// line").
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

  /// mode is which way one of the new kinds is drawn: a dumbbell's "gap",
  /// "arrows" or "range"; a heatmap's "grid", "calendar" or "stripes"... (see
  /// chartModes). Empty, its first.
  final String mode;

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
      mode: j["mode"] is String ? j["mode"] as String : "",
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
    ("circles", "Sized circles")
  ],
  "pyramid": [("pyramid", "Pyramid"), ("butterfly", "Butterfly")],
  // The older kinds' other ways (chart_variants.dart, and candles in
  // chart_cartesian.dart); each one's first is its own painter.
  "funnel": [
    ("tapered", "Tapered"),
    ("bars", "Bars from one edge"),
    ("ghost", "What was lost")
  ],
  "bubbles": [("packed", "Packed"), ("row", "In a row")],
  "timeline": [("line", "Along a line"), ("down", "Down the page")],
  "gauge": [("arc", "Arc"), ("bands", "Needle over bands"), ("dial", "Dial")],
  "pictogram": [
    ("icons", "Icons"),
    ("rows", "A row each"),
    ("big", "One big icon")
  ],
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
  "radar": [("filled", "Filled"), ("dots", "Dots on spokes")],
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

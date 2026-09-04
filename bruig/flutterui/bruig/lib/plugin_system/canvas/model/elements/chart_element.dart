import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// chart_element.dart is a chart as data plus a handful of decisions, drawn
// from scratch by render/chart_painter.dart.
//
// No charting library. Not for lack of one -- it is that everything else on
// this canvas is a path on a ui.Canvas that exports at any size, animates
// through the same keyframes and rotates with the same handles, and a widget
// from a package is none of those. A chart here is 200 lines of trigonometry
// that behaves exactly like a star or a pitch does, which is worth far more
// than the features a library would have brought.

/// ChartType is which drawing the numbers get.
enum ChartType {
  bar("Bars", "One bar per category"),
  groupedBar("Grouped bars", "Series side by side within each category"),
  stackedBar("Stacked bars", "Series stacked within each category"),
  horizontalBar("Horizontal bars", "Bars running left to right"),
  line("Line", "A line through the values"),
  area("Area", "A line with the space beneath it filled"),
  scatter("Scatter", "A point per value, unconnected"),
  pie("Pie", "Shares of a whole"),
  donut("Donut", "Shares of a whole, with the middle open"),
  radialBar("Radial bars", "Bars bent around a circle"),
  radar("Radar", "One axis per category, radiating from the centre");

  final String label;
  final String description;
  const ChartType(this.label, this.description);

  static ChartType fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => ChartType.bar);

  /// isCircular marks the types that have no x and y axis, so the settings
  /// bar can stop offering axis labels for a pie.
  bool get isCircular =>
      this == pie || this == donut || this == radialBar || this == radar;

  /// isStacked is whether values accumulate, which changes how the axis
  /// maximum is worked out.
  bool get isStacked => this == stackedBar;

  /// wantsMultipleSeries is whether adding a second series does anything
  /// useful. A pie of two series is two pies, which this does not draw.
  bool get wantsMultipleSeries =>
      this != pie && this != donut && this != radialBar;

  /// needsMultipleSeries is whether the type is *only* different from plain
  /// bars once there are two series to group or stack.
  ///
  /// Worth naming, because choosing one of these on a one-series chart draws
  /// exactly what was already there -- which reads as the setting being
  /// broken rather than as there being nothing to group.
  bool get needsMultipleSeries => this == groupedBar || this == stackedBar;

  /// usesSmooth is whether curving between the points means anything. Bars
  /// have nothing to curve, and a scatter is unconnected by definition.
  bool get usesSmooth => this == line || this == area || this == radar;

  /// isBar and isLinear split the cartesian types by how they are drawn,
  /// which is what an overlay of two kinds on one pair of axes needs to know.
  bool get isBar =>
      this == bar || this == groupedBar || this == stackedBar ||
      this == horizontalBar;
  bool get isLinear => this == line || this == area || this == scatter;
}

/// ChartLabel is a chart's title or description: whether it is shown, and
/// where.
///
/// Placement is optional and off to begin with. A chart lays its own title out
/// -- stacked at the top, taking the height it needs and giving the rest to
/// the plot -- which is right until somebody wants the title down the side or
/// over the corner of the plot, and there is no arrangement of automatic rules
/// that covers both. So [x] is NaN until the label is moved, and the moment it
/// is moved it stops taking room from the plot and starts sitting where it was
/// put.
class ChartLabel {
  final bool show;

  /// x, y, width and height are fractions of the element's own box, so a
  /// title stays where it was put when the chart is resized.
  final double x;
  final double y;
  final double width;
  final double height;

  const ChartLabel({
    this.show = true,
    this.x = double.nan,
    this.y = 0,
    this.width = 1,
    this.height = 0.14,
  });

  /// placed is whether it has been moved off the chart's own arrangement.
  bool get placed => !x.isNaN;

  Rect rectIn(Rect box) => Rect.fromLTWH(
        box.left + x * box.width,
        box.top + y * box.height,
        width * box.width,
        height * box.height,
      );

  ChartLabel copyWith({
    bool? show,
    double? x,
    double? y,
    double? width,
    double? height,
    bool unplace = false,
  }) =>
      ChartLabel(
        show: show ?? this.show,
        x: unplace ? double.nan : (x ?? this.x),
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  Map<String, dynamic> toJson() => {
        if (!show) "off": true,
        if (placed) "x": x,
        if (placed) "y": y,
        if (placed) "w": width,
        if (placed) "h": height,
      };

  factory ChartLabel.fromJson(Map<String, dynamic> json) => ChartLabel(
        show: !jsonBool(json["off"], false),
        x: jsonDouble(json["x"], double.nan),
        y: jsonDouble(json["y"], 0),
        width: jsonDouble(json["w"], 1),
        height: jsonDouble(json["h"], 0.14),
      );
}

/// chartPalette is the default series colours.
///
/// Ordered so that the first three are distinguishable from each other in
/// greyscale as well as in colour, because the commonest chart has two or
/// three series and the commonest failure is two of them being the same grey
/// once somebody has printed it.
const List<Color> chartPalette = [
  Color(0xFF3D7EFF),
  Color(0xFFFFB020),
  Color(0xFF2FD3A0),
  Color(0xFFE85D75),
  Color(0xFF9B7BFF),
  Color(0xFF52C4E8),
  Color(0xFFF07C3E),
  Color(0xFFB8D24A),
];

/// ChartSeries is one line, one set of bars, or one ring.
class ChartSeries {
  final String name;
  final Color color;
  final List<double> values;

  /// type draws this series differently from the rest of the chart, so a set
  /// of bars can have a line over it.
  ///
  /// Null means "whatever the chart is", which is what almost every series
  /// wants and is why this is an override rather than a required field. Only
  /// meaningful for the types with an x and a y axis: a pie has one ring and
  /// nothing to overlay on it.
  final ChartType? type;

  const ChartSeries({
    required this.name,
    required this.color,
    required this.values,
    this.type,
  });

  /// typeIn is how this series is actually drawn on a chart of [chartType].
  ChartType typeIn(ChartType chartType) => type ?? chartType;

  ChartSeries copyWith({
    String? name,
    Color? color,
    List<double>? values,
    ChartType? type,
    bool followChart = false,
  }) =>
      ChartSeries(
        name: name ?? this.name,
        color: color ?? this.color,
        values: values ?? this.values,
        type: followChart ? null : (type ?? this.type),
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "color": colorToJson(color),
        "values": values,
        if (type != null) "type": type!.name,
      };

  factory ChartSeries.fromJson(Map<String, dynamic> json, int index) {
    var raw = json["values"];
    return ChartSeries(
      name: jsonString(json["name"], "Series ${index + 1}"),
      color: colorFromJson(
          json["color"], chartPalette[index % chartPalette.length]),
      type: json["type"] is String
          ? ChartType.fromName(json["type"] as String?)
          : null,
      values: raw is List
          ? [for (var v in raw) v is num ? v.toDouble() : 0.0]
          : const [],
    );
  }
}

/// ChartData is the categories and the series together, and the parser that
/// fills them in from pasted text.
class ChartData {
  final List<String> categories;
  final List<ChartSeries> series;

  const ChartData({this.categories = const [], this.series = const []});

  bool get isEmpty => series.isEmpty || categories.isEmpty;

  /// valueAt is the number at [row] of [seriesIndex], or zero where the data
  /// is ragged.
  ///
  /// Ragged data is normal, not an error. Somebody pasting a table with a
  /// missing cell should get a chart with a gap in it, not a red message
  /// telling them to go and fix their spreadsheet.
  double valueAt(int seriesIndex, int row) {
    if (seriesIndex < 0 || seriesIndex >= series.length) return 0;
    var v = series[seriesIndex].values;
    return row >= 0 && row < v.length ? v[row] : 0;
  }

  /// asText renders the data back into the format [parse] reads, which is
  /// what the quick-entry box is filled with when a chart is selected. The
  /// round trip is the whole feature: edit the text, get the chart.
  String asText() {
    var out = StringBuffer();
    out.writeln(["", ...series.map((s) => s.name)].join("\t"));
    for (var i = 0; i < categories.length; i++) {
      out.writeln([
        categories[i],
        ...series.map((s) => i < s.values.length ? _num(s.values[i]) : ""),
      ].join("\t"));
    }
    return out.toString().trimRight();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// parse reads a pasted table.
  ///
  /// The splitting is [splitTable]'s -- tab, comma or a run of spaces, chosen
  /// once for the whole paste. See tabular_text.dart, and in particular why
  /// the line is not trimmed before it is split.
  ///
  /// The first row is treated as series names if none of its cells after the
  /// first parses as a number. Sniffed rather than declared, for the same
  /// reason -- and it is the right guess almost always, since a header row of
  /// numbers is indistinguishable from data by any means at all.
  /// [keep] is the series this is replacing, if any. Their colours and their
  /// per-series types are carried across by position, so editing the numbers
  /// does not throw away the fact that the second series was drawn as a line.
  static ChartData parse(String text, {List<Color>? colors,
      List<ChartSeries>? keep}) {
    var rows = splitTable(text);
    if (rows.isEmpty) return const ChartData();

    var header = rows.first;
    var hasHeader = header.length > 1 &&
        header.skip(1).every((c) => double.tryParse(c) == null);
    var names = hasHeader
        ? header.skip(1).toList()
        : [for (var i = 1; i < header.length; i++) "Series $i"];
    var body = hasHeader ? rows.skip(1).toList() : rows;

    var categories = <String>[];
    var values = List.generate(names.length, (_) => <double>[]);
    for (var row in body) {
      categories.add(row.isEmpty ? "" : row.first);
      for (var i = 0; i < names.length; i++) {
        var cell = i + 1 < row.length ? row[i + 1] : "";
        values[i].add(double.tryParse(cell.replaceAll("%", "")) ?? 0);
      }
    }

    return ChartData(
      categories: categories,
      series: [
        for (var i = 0; i < names.length; i++)
          ChartSeries(
            name: names[i],
            color: colors != null && i < colors.length
                ? colors[i]
                : keep != null && i < keep.length
                    ? keep[i].color
                    : chartPalette[i % chartPalette.length],
            type: keep != null && i < keep.length ? keep[i].type : null,
            values: values[i],
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        "categories": categories,
        "series": series.map((s) => s.toJson()).toList(),
      };

  factory ChartData.fromJson(Map<String, dynamic> json) {
    var cats = json["categories"];
    var ser = json["series"];
    return ChartData(
      categories: cats is List ? [for (var c in cats) "$c"] : const [],
      series: ser is List
          ? [
              for (var i = 0; i < ser.length; i++)
                if (ser[i] is Map<String, dynamic>)
                  ChartSeries.fromJson(ser[i] as Map<String, dynamic>, i),
            ]
          : const [],
    );
  }
}

/// chartAnimationSeconds is how long a preset runs when it is first applied.
///
/// A starting point, not a setting: the two keyframes it lays are dragged on
/// the timeline like anything else, which is where the length actually lives.
const int chartAnimationSeconds = 2;

/// ChartAnimationPreset is how a chart arrives.
///
/// Presets rather than a set of controls that could express all of them. What
/// somebody wants is "the bars grow up one after another"; what a general
/// mechanism asks is which property, over what range, with what stagger and
/// what easing, four times over -- and the answer is the same four answers
/// every time. The two things that genuinely vary are how much the items
/// overlap and what the end of the movement does, and those are settings.
enum ChartAnimationPreset {
  none("None", "The chart is simply there"),

  /// grow is the one anybody means. Bars rise out of the axis, horizontal bars
  /// run out from it, pie slices open out from the middle.
  grow("Grow", "Each one grows to its full size, in turn"),

  /// drawOn traces a line from its start to its end. For bars there is nothing
  /// to trace, so it grows them instead.
  drawOn("Draw on", "Lines are drawn along their length"),

  /// wipe reveals the plot left to right, everything in it at once. The one
  /// preset with nothing to stagger.
  wipe("Wipe across", "The whole plot is uncovered from the left"),

  /// sweep is wipe for a circle: the chart is uncovered clockwise.
  sweep("Sweep round", "The chart is uncovered clockwise from the top"),

  popIn("Pop in", "Each one springs up where it stands, in turn"),

  /// random is popIn with the order shuffled. What a scatter wants: points in
  /// a scatter have no order worth animating in -- left to right is a
  /// property of how they were typed rather than of what they mean -- and a
  /// cloud that fills in unevenly reads as a cloud arriving rather than as a
  /// row being dealt.
  random("Random", "Each one appears on its own, in no particular order"),

  fadeIn("Fade in", "Each one fades up, in turn");

  final String label;
  final String description;
  const ChartAnimationPreset(this.label, this.description);

  static ChartAnimationPreset fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => ChartAnimationPreset.none,
      );

  /// staggers is whether the items go one after another, which is what the gap
  /// setting decides. A wipe and a sweep move one edge across everything at
  /// once and have nothing to space out.
  bool get staggers =>
      this != none && this != wipe && this != sweep;

  /// scrambles is whether the order things arrive in is shuffled.
  bool get scrambles => this == random;

  /// suitsCircular and suitsCartesian are which chart families a preset makes
  /// sense on. A wipe across a pie is a wipe across a circle, which reads as a
  /// mistake; a sweep round a bar chart is worse.
  bool get suitsCircular =>
      this == none || this == grow || this == sweep || this == popIn ||
      this == random || this == fadeIn;

  bool get suitsCartesian => this != sweep;
}

/// ChartEase is what the end of an item's movement does.
///
/// The reason this is a setting and not a fixed curve: a bar that eases to a
/// stop is a chart, and a bar that overshoots and settles is an advertisement,
/// and which of the two is wanted is not something a drawing routine can know.
enum ChartEase {
  linear("Linear"),
  easeOut("Ease out"),
  overshoot("Overshoot"),
  bounce("Bounce"),
  spring("Spring");

  final String label;
  const ChartEase(this.label);

  static ChartEase fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => ChartEase.easeOut);

  /// apply maps 0..1 onto the eased value, which may leave 0..1 on the way --
  /// that is what an overshoot is.
  double apply(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    switch (this) {
      case ChartEase.linear:
        return t;
      case ChartEase.easeOut:
        return 1 - math.pow(1 - t, 3).toDouble();
      case ChartEase.overshoot:
        // The standard back-out: one overshoot and a settle, no wobble.
        const c = 1.70158;
        var u = t - 1;
        return 1 + (c + 1) * u * u * u + c * u * u;
      case ChartEase.bounce:
        return _bounce(t);
      case ChartEase.spring:
        // A decaying oscillation. Three visible swings before it settles,
        // which is enough to read as a spring and few enough to stop being
        // charming on the fourth chart.
        var decay = math.pow(2, -9 * t).toDouble();
        return 1 - decay * math.cos(t * math.pi * 6);
    }
  }

  static double _bounce(double t) {
    const n = 7.5625, d = 2.75;
    if (t < 1 / d) return n * t * t;
    if (t < 2 / d) {
      var u = t - 1.5 / d;
      return n * u * u + 0.75;
    }
    if (t < 2.5 / d) {
      var u = t - 2.25 / d;
      return n * u * u + 0.9375;
    }
    var u = t - 2.625 / d;
    return n * u * u + 0.984375;
  }
}

/// ChartAnimation is how a chart draws itself on, and how much of it has.
///
/// The *timing* is not here. It is two keyframes on the element's own track,
/// pinning KeyframeChannel.reveal at 0 and at 1, so the length of the
/// animation is dragged on the timeline like everything else that moves. A
/// duration stored here would be a second timeline that the first one could
/// not see.
class ChartAnimation {
  final ChartAnimationPreset preset;

  /// gap is how long after one item starts before the next does, as a
  /// fraction of one item's own movement.
  ///
  /// 1 is strictly one after another: each finishes as the next begins. Below
  /// 1 they overlap, and 0 is all of them together. Above 1 leaves a pause
  /// between one finishing and the next starting.
  final double gap;

  final ChartEase ease;

  const ChartAnimation({
    this.preset = ChartAnimationPreset.none,
    this.gap = 0.55,
    this.ease = ChartEase.easeOut,
  });

  bool get on => preset != ChartAnimationPreset.none;

  ChartAnimation copyWith({
    ChartAnimationPreset? preset,
    double? gap,
    ChartEase? ease,
  }) =>
      ChartAnimation(
        preset: preset ?? this.preset,
        gap: gap ?? this.gap,
        ease: ease ?? this.ease,
      );

  /// progressAt is how far item [index] of [count] has got when the whole
  /// animation is [reveal] through.
  ///
  /// The arithmetic is in one place because the painter asks it for bars, for
  /// points, for slices and for series, and a stagger that meant something
  /// slightly different in four places is four animations that do not line up
  /// with each other.
  double progressAt(double reveal, int index, int count) {
    if (!on) return 1;
    if (reveal >= 1) return 1;
    if (reveal <= 0) return 0;
    if (!preset.staggers || count <= 1) return ease.apply(reveal);

    // The whole animation is one item's movement plus the gaps before every
    // later one, measured in item-movements.
    var step = gap.clamp(0.0, 4.0);
    var total = 1 + step * (count - 1);
    var place = preset.scrambles
        ? scrambled(index, count)
        : index.toDouble();
    var local = (reveal * total - step * place).clamp(0.0, 1.0);
    return ease.apply(local);
  }

  /// scrambled is where item [index] comes in the order things arrive, for the
  /// presets that shuffle. Not a whole number: two items may well arrive
  /// together, which is what random looks like.
  ///
  /// Arithmetic rather than a shuffled list, and the same answer every time
  /// rather than a fresh one. A chart is drawn once per frame and exported
  /// frame by frame in a separate pass, so anything that consulted a random
  /// number generator would deal the points differently on every frame and on
  /// every export -- which is not an animation, it is static.
  ///
  /// A mix rather than "multiply by a prime and take the remainder", which is
  /// the obvious version and is not random at all: the multiplier is only ever
  /// used modulo the count, so twelve items came out as a plain reversal and
  /// two series of six arrived one series at a time -- which is the exact
  /// thing this preset exists to avoid.
  static double scrambled(int index, int count) {
    if (count <= 1) return 0;
    return _mix(index) * (count - 1);
  }

  /// _mix avalanches an index into 0..1. Murmur3's finaliser, which is the
  /// standard answer to "spread these integers out" and is three multiplies.
  static double _mix(int index) {
    var x = (index + 1) & 0xFFFFFFFF;
    x ^= x >>> 16;
    x = (x * 0x85EBCA6B) & 0xFFFFFFFF;
    x ^= x >>> 13;
    x = (x * 0xC2B2AE35) & 0xFFFFFFFF;
    x ^= x >>> 16;
    return x / 0xFFFFFFFF;
  }

  Map<String, dynamic> toJson() => {
        "preset": preset.name,
        "gap": gap,
        "ease": ease.name,
      };

  factory ChartAnimation.fromJson(Map<String, dynamic> json) => ChartAnimation(
        preset: ChartAnimationPreset.fromName(json["preset"] as String?),
        gap: jsonDouble(json["gap"], 0.55).clamp(0.0, 4.0),
        ease: ChartEase.fromName(json["ease"] as String?),
      );
}

/// LegendPlacement is which side of the chart the key sits on.
enum LegendPlacement {
  top("Top"),
  bottom("Bottom"),
  left("Left"),
  right("Right");

  final String label;
  const LegendPlacement(this.label);

  bool get isSide => this == left || this == right;

  static LegendPlacement fromName(String? name) => values.firstWhere(
        (p) => p.name == name,
        orElse: () => LegendPlacement.top,
      );
}

/// ChartLegend is everything about the key except whether it is shown.
///
/// Whether it is shown stays on the element as showLegend, where it already
/// was and where every saved document already has it. Splitting a setting in
/// two to tidy the model is how a chart that used to have a legend stops
/// having one.
class ChartLegend {
  final LegendPlacement placement;

  /// vertical puts one entry per line. Horizontal wraps them along the width
  /// it is given, which is what a key over the top of a chart wants and what a
  /// key down the side of one does not.
  final bool vertical;

  /// scale sizes the key against the chart's own label size, so a legend
  /// stays in proportion when the labels are changed and can still be made
  /// bigger or smaller than them.
  final double scale;

  /// spacing is the gap between one entry and the next, in ems of the key's
  /// own type.
  final double spacing;

  /// values writes each entry's number beside its name.
  ///
  /// Its own switch rather than the chart's showValues. They are two
  /// questions -- a bar chart may well want numbers on its bars and a key
  /// without them, and a radial bar has nowhere to put a number *except* the
  /// key -- and one switch answering both meant neither could be had alone.
  final bool values;

  const ChartLegend({
    this.placement = LegendPlacement.top,
    this.vertical = false,
    this.scale = 1,
    this.spacing = 1,
    this.values = false,
  });

  ChartLegend copyWith({
    LegendPlacement? placement,
    bool? vertical,
    double? scale,
    double? spacing,
    bool? values,
  }) =>
      ChartLegend(
        placement: placement ?? this.placement,
        vertical: vertical ?? this.vertical,
        scale: scale ?? this.scale,
        spacing: spacing ?? this.spacing,
        values: values ?? this.values,
      );

  Map<String, dynamic> toJson() => {
        "at": placement.name,
        if (vertical) "vertical": true,
        if (scale != 1) "scale": scale,
        if (spacing != 1) "spacing": spacing,
        if (values) "values": true,
      };

  factory ChartLegend.fromJson(Map<String, dynamic> json) => ChartLegend(
        placement: LegendPlacement.fromName(json["at"] as String?),
        vertical: jsonBool(json["vertical"], false),
        scale: jsonDouble(json["scale"], 1).clamp(0.3, 4.0),
        spacing: jsonDouble(json["spacing"], 1).clamp(0.0, 6.0),
        values: jsonBool(json["values"], false),
      );
}

/// ChartBody is where the chart itself is drawn inside its element, as
/// fractions of the box.
///
/// The whole box, until a label is dragged outside it. The box then grows to
/// hold the label -- so that the text is inside the selection outline and is
/// picked up by a marquee, which is what says it belongs to this chart -- and
/// the body stays exactly where it was, so the plot does not resize under a
/// drag that was never about the plot.
///
/// Resizing the element by its handles scales the body with everything else,
/// which is the behaviour that was already there and is the one anybody
/// dragging a corner is expecting.
class ChartBody {
  final double x;
  final double y;
  final double width;
  final double height;

  const ChartBody({this.x = 0, this.y = 0, this.width = 1, this.height = 1});

  bool get isWhole => x == 0 && y == 0 && width == 1 && height == 1;

  Rect rectIn(Rect box) => Rect.fromLTWH(
        box.left + x * box.width,
        box.top + y * box.height,
        width * box.width,
        height * box.height,
      );

  /// fitting is the body that puts [want] inside [box], for when the box has
  /// just grown and the chart must not move.
  static ChartBody fitting(Rect want, Rect box) => box.width <= 0 ||
          box.height <= 0
      ? const ChartBody()
      : ChartBody(
          x: (want.left - box.left) / box.width,
          y: (want.top - box.top) / box.height,
          width: want.width / box.width,
          height: want.height / box.height,
        );

  Map<String, dynamic> toJson() => {"x": x, "y": y, "w": width, "h": height};

  factory ChartBody.fromJson(Map<String, dynamic> json) => ChartBody(
        x: jsonDouble(json["x"], 0),
        y: jsonDouble(json["y"], 0),
        width: jsonDouble(json["w"], 1),
        height: jsonDouble(json["h"], 1),
      );
}

/// defaultTitlePlacement and defaultDescriptionPlacement are where a label
/// goes the first time somebody takes control of it.
///
/// Where the chart would have put it, near enough: across the top, title
/// first and description under it. Both used to land in the same corner, so
/// placing the second put it exactly over the first -- and since the
/// description is drawn last, that looked like a description sitting above a
/// title, which is almost never what anybody means.
const ChartLabel defaultTitlePlacement =
    ChartLabel(x: 0.02, y: 0.02, width: 0.96, height: 0.14);

ChartLabel defaultDescriptionPlacement(ChartLabel title, bool hasTitle) {
  // Under the title wherever the title is, so the two stay a pair. With no
  // title to sit under, the description takes the top itself rather than
  // leaving a band of nothing above it.
  var top = hasTitle
      ? (title.placed ? title.y + title.height : defaultTitlePlacement.y +
          defaultTitlePlacement.height)
      : 0.02;
  return ChartLabel(
      x: hasTitle && title.placed ? title.x : 0.02,
      y: top + 0.01,
      width: hasTitle && title.placed ? title.width : 0.96,
      height: 0.1);
}

/// ChartElement is a chart on the canvas.
class ChartElement extends CanvasElement {
  final ChartType type;
  final ChartData data;

  final String title;
  final String description;

  /// titleBox and descriptionBox say whether those two are shown and, once
  /// they have been moved, where. See [ChartLabel].
  final ChartLabel titleBox;
  final ChartLabel descriptionBox;

  /// body is where the chart itself is drawn. See [ChartBody].
  final ChartBody body;

  /// animation is how the chart draws itself on. See [ChartAnimation].
  final ChartAnimation animation;

  /// legend is everything about the key except whether it is shown, which is
  /// [showLegend]. See [ChartLegend].
  final ChartLegend legend;

  /// descriptionSpec is the description's own type, or null to follow the
  /// label size -- which is where it started and is what every document saved
  /// before this had.
  final TextSpec? descriptionSpec;

  final String xAxisLabel;
  final String yAxisLabel;

  /// showGrid is the ruled matrix behind the plot. On by default: a bar chart
  /// without one is a picture of some bars, and reading a value off it means
  /// guessing.
  final bool showGrid;
  final bool showAxes;
  final bool showLegend;

  /// showValues prints each number on its own bar or point, which is what
  /// makes a chart readable at chat-message size where the axis labels are
  /// too small to follow.
  final bool showValues;

  final Color gridColor;
  final Color axisColor;

  /// titleSpec, labelSpec and valueSpec are the three sizes of type on a
  /// chart. Separate so a chart shrunk to fit a corner can keep a readable
  /// title while its tick labels get out of the way.
  final TextSpec titleSpec;
  final TextSpec labelSpec;
  final TextSpec valueSpec;

  /// yMin and yMax pin the value axis. NaN means "work it out from the data",
  /// which is the default and is what almost every chart wants.
  final double yMin;
  final double yMax;

  /// barGap is the space between bars as a fraction of the slot width.
  final double barGap;
  final double barRadius;

  /// innerRadius is the hole in a donut, as a fraction of the outer radius.
  final double innerRadius;

  /// strokeWidth is the line weight for the line, area and radar types.
  final double strokeWidth;

  /// smooth curves a line chart through its points instead of joining them
  /// with straight segments.
  final bool smooth;

  const ChartElement(
    super.base, {
    this.type = ChartType.bar,
    this.data = const ChartData(),
    this.title = "",
    this.description = "",
    this.titleBox = const ChartLabel(),
    this.descriptionBox = const ChartLabel(height: 0.1),
    this.body = const ChartBody(),
    this.animation = const ChartAnimation(),
    this.legend = const ChartLegend(),
    this.descriptionSpec,
    this.xAxisLabel = "",
    this.yAxisLabel = "",
    this.showGrid = true,
    this.showAxes = true,
    this.showLegend = false,
    this.showValues = false,
    this.gridColor = const Color(0x33FFFFFF),
    this.axisColor = const Color(0x99FFFFFF),
    this.titleSpec = const TextSpec(fontSize: 28, weight: 700),
    this.labelSpec = const TextSpec(fontSize: 16, weight: 400),
    this.valueSpec = const TextSpec(fontSize: 14, weight: 600),
    this.yMin = double.nan,
    this.yMax = double.nan,
    this.barGap = 0.3,
    this.barRadius = 4,
    this.innerRadius = 0.55,
    this.strokeWidth = 3,
    this.smooth = false,
  });

  @override
  ElementKind get kind => ElementKind.chart;

  /// descriptionText is the type the description is actually set in: its own
  /// when it has been given one, and the label size otherwise.
  TextSpec get descriptionText => descriptionSpec ?? labelSpec;

  @override
  CanvasElement rebase(ElementBase base) => _copy(base);

  ChartElement copyWith({
    ChartType? type,
    ChartData? data,
    String? title,
    String? description,
    ChartLabel? titleBox,
    ChartLabel? descriptionBox,
    ChartBody? body,
    ChartAnimation? animation,
    ChartLegend? legend,
    TextSpec? descriptionSpec,
    String? xAxisLabel,
    String? yAxisLabel,
    bool? showGrid,
    bool? showAxes,
    bool? showLegend,
    bool? showValues,
    Color? gridColor,
    Color? axisColor,
    TextSpec? titleSpec,
    TextSpec? labelSpec,
    TextSpec? valueSpec,
    double? yMin,
    double? yMax,
    double? barGap,
    double? barRadius,
    double? innerRadius,
    double? strokeWidth,
    bool? smooth,
  }) =>
      _copy(base,
          type: type,
          data: data,
          title: title,
          description: description,
          titleBox: titleBox,
          descriptionBox: descriptionBox,
          body: body,
          animation: animation,
          legend: legend,
          descriptionSpec: descriptionSpec,
          xAxisLabel: xAxisLabel,
          yAxisLabel: yAxisLabel,
          showGrid: showGrid,
          showAxes: showAxes,
          showLegend: showLegend,
          showValues: showValues,
          gridColor: gridColor,
          axisColor: axisColor,
          titleSpec: titleSpec,
          labelSpec: labelSpec,
          valueSpec: valueSpec,
          yMin: yMin,
          yMax: yMax,
          barGap: barGap,
          barRadius: barRadius,
          innerRadius: innerRadius,
          strokeWidth: strokeWidth,
          smooth: smooth);

  /// _copy is copyWith and rebase sharing one body, since a chart has enough
  /// fields that writing the list out twice is where a dropped field would
  /// hide.
  ChartElement _copy(
    ElementBase newBase, {
    ChartType? type,
    ChartData? data,
    String? title,
    String? description,
    ChartLabel? titleBox,
    ChartLabel? descriptionBox,
    ChartBody? body,
    ChartAnimation? animation,
    ChartLegend? legend,
    TextSpec? descriptionSpec,
    String? xAxisLabel,
    String? yAxisLabel,
    bool? showGrid,
    bool? showAxes,
    bool? showLegend,
    bool? showValues,
    Color? gridColor,
    Color? axisColor,
    TextSpec? titleSpec,
    TextSpec? labelSpec,
    TextSpec? valueSpec,
    double? yMin,
    double? yMax,
    double? barGap,
    double? barRadius,
    double? innerRadius,
    double? strokeWidth,
    bool? smooth,
  }) =>
      ChartElement(newBase,
          type: type ?? this.type,
          data: data ?? this.data,
          title: title ?? this.title,
          description: description ?? this.description,
          titleBox: titleBox ?? this.titleBox,
          descriptionBox: descriptionBox ?? this.descriptionBox,
          body: body ?? this.body,
          animation: animation ?? this.animation,
          legend: legend ?? this.legend,
          descriptionSpec: descriptionSpec ?? this.descriptionSpec,
          xAxisLabel: xAxisLabel ?? this.xAxisLabel,
          yAxisLabel: yAxisLabel ?? this.yAxisLabel,
          showGrid: showGrid ?? this.showGrid,
          showAxes: showAxes ?? this.showAxes,
          showLegend: showLegend ?? this.showLegend,
          showValues: showValues ?? this.showValues,
          gridColor: gridColor ?? this.gridColor,
          axisColor: axisColor ?? this.axisColor,
          titleSpec: titleSpec ?? this.titleSpec,
          labelSpec: labelSpec ?? this.labelSpec,
          valueSpec: valueSpec ?? this.valueSpec,
          yMin: yMin ?? this.yMin,
          yMax: yMax ?? this.yMax,
          barGap: barGap ?? this.barGap,
          barRadius: barRadius ?? this.barRadius,
          innerRadius: innerRadius ?? this.innerRadius,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          smooth: smooth ?? this.smooth);

  @override
  Map<String, dynamic> props() => {
        "type": type.name,
        "data": data.toJson(),
        if (title.isNotEmpty) "title": title,
        if (description.isNotEmpty) "desc": description,
        if (titleBox.toJson().isNotEmpty) "titleBox": titleBox.toJson(),
        if (descriptionBox.toJson().isNotEmpty)
          "descBox": descriptionBox.toJson(),
        if (!body.isWhole) "body": body.toJson(),
        if (animation.on) "anim": animation.toJson(),
        // Kept even with the legend switched off: turning it off and on
        // again should find it where it was left, not back at the top in a
        // row.
        if (showLegend || legend.toJson().length > 1)
          "legendSpec": legend.toJson(),
        if (descriptionSpec != null) "descSpec": descriptionSpec!.toJson(),
        if (xAxisLabel.isNotEmpty) "xlabel": xAxisLabel,
        if (yAxisLabel.isNotEmpty) "ylabel": yAxisLabel,
        "grid": showGrid,
        "axes": showAxes,
        "legend": showLegend,
        "values": showValues,
        "gridColor": colorToJson(gridColor),
        "axisColor": colorToJson(axisColor),
        "titleSpec": titleSpec.toJson(),
        "labelSpec": labelSpec.toJson(),
        "valueSpec": valueSpec.toJson(),
        if (!yMin.isNaN) "ymin": yMin,
        if (!yMax.isNaN) "ymax": yMax,
        "barGap": barGap,
        "barRadius": barRadius,
        "inner": innerRadius,
        "sw": strokeWidth,
        if (smooth) "smooth": true,
      };

  factory ChartElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ChartElement(b,
          type: ChartType.fromName(json["type"] as String?),
          data: jsonSpec(json["data"], ChartData.fromJson, const ChartData()),
          title: jsonString(json["title"], ""),
          description: jsonString(json["desc"], ""),
          titleBox: jsonSpec(json["titleBox"], ChartLabel.fromJson,
              const ChartLabel()),
          descriptionBox: jsonSpec(json["descBox"], ChartLabel.fromJson,
              const ChartLabel(height: 0.1)),
          body: jsonSpec(json["body"], ChartBody.fromJson, const ChartBody()),
          animation: jsonSpec(json["anim"], ChartAnimation.fromJson,
              const ChartAnimation()),
          legend: jsonSpec(json["legendSpec"], ChartLegend.fromJson,
              const ChartLegend()),
          descriptionSpec: json["descSpec"] is Map<String, dynamic>
              ? TextSpec.fromJson(json["descSpec"] as Map<String, dynamic>)
              : null,
          xAxisLabel: jsonString(json["xlabel"], ""),
          yAxisLabel: jsonString(json["ylabel"], ""),
          showGrid: jsonBool(json["grid"], true),
          showAxes: jsonBool(json["axes"], true),
          showLegend: jsonBool(json["legend"], false),
          showValues: jsonBool(json["values"], false),
          gridColor: colorFromJson(json["gridColor"], const Color(0x33FFFFFF)),
          axisColor: colorFromJson(json["axisColor"], const Color(0x99FFFFFF)),
          titleSpec: jsonSpec(json["titleSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 28, weight: 700)),
          labelSpec: jsonSpec(json["labelSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 16, weight: 400)),
          valueSpec: jsonSpec(json["valueSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 14, weight: 600)),
          yMin: jsonDouble(json["ymin"], double.nan),
          yMax: jsonDouble(json["ymax"], double.nan),
          barGap: jsonDouble(json["barGap"], 0.3),
          barRadius: jsonDouble(json["barRadius"], 4),
          innerRadius: jsonDouble(json["inner"], 0.55),
          strokeWidth: jsonDouble(json["sw"], 3),
          smooth: jsonBool(json["smooth"], false));
}

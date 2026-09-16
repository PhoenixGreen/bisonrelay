import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';

// chart_data.dart is the numbers a chart is drawn from: the series, the
// categories they are indexed by, and the colours they arrive in.
//
// Kept apart from the element because it is the half that gets typed, pasted
// and parsed. Everything the data editor does lands here -- see
// tabular_text.dart for the paste -- while the element next door is only
// settings, and neither has to be read to work on the other.
//
// ChartType is here rather than with the element because the data has to know
// it: how many series a type can use, and whether it reads its colours off
// the series or off the values, are questions ChartData answers.

/// ChartType is which drawing the numbers get.
enum ChartType {
  bar("Bars", "One bar per category"),
  groupedBar("Grouped bars", "Series side by side within each category"),
  stackedBar("Stacked bars", "Series stacked within each category"),
  horizontalBar("Horizontal bars", "Bars running left to right"),
  line("Line", "A line through the values"),
  area("Area", "A line with the space beneath it filled"),
  scatter("Scatter", "A point per value, unconnected"),
  candlestick("Candlesticks", "Open, high, low and close for each period"),
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

  /// isCandles is the one type that reads four series as a single mark.
  ///
  /// Named rather than compared to the constant everywhere, because it is
  /// asked in half a dozen places -- what the axis does, how many series are
  /// wanted, what the legend says -- and each of them means "is this the
  /// four-values-per-period type" rather than "is this that particular
  /// enum".
  bool get isCandles => this == candlestick;

  /// startsAtZero is whether the value axis has to include zero.
  ///
  /// Bars must: a bar is read as a length, and one drawn from 12 to 16 on an
  /// axis starting at 12 says four times what it means. A candlestick is read
  /// as a position, not a length -- a price chart forced down to zero is a
  /// flat line along the top with the whole month squeezed into a tenth of
  /// the plot, which is exactly what makes it useless.
  bool get startsAtZero => !isCandles;

  /// isStacked is whether values accumulate, which changes how the axis
  /// maximum is worked out.
  bool get isStacked => this == stackedBar;

  /// needsFourSeries is the candlestick's requirement, stated so the settings
  /// can say so rather than drawing nothing and leaving it a mystery.
  bool get needsFourSeries => isCandles;

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

  /// isCartesian is everything drawn against an x and a y axis, which is
  /// every type that is not circular.
  bool get isCartesian => !isCircular;

  /// isBar and isLinear split the cartesian types by how they are drawn,
  /// which is what an overlay of two kinds on one pair of axes needs to know.
  bool get isBar =>
      this == bar ||
      this == groupedBar ||
      this == stackedBar ||
      this == horizontalBar;
  bool get isLinear => this == line || this == area || this == scatter;
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

  /// numbers writes this series' values differently from the rest of the
  /// chart, or null to write them the way the chart does.
  ///
  /// An override for the same reason [type] is one. A chart of a price beside
  /// a market cap is two series whose figures are four orders of magnitude
  /// apart, and one style across both writes either "0.0B" against the price
  /// or "18,400,000,000" against the cap. The axis keeps the chart's own
  /// style, since there is one axis and it cannot be two things.
  final ChartNumbers? numbers;

  /// gradient draws this series in two colours instead of one. Null for the
  /// almost every series that is one colour.
  ///
  /// Set in the colour picker beside [color] rather than in a row of its own,
  /// which is why it has no on/off flag of its own: there either is a second
  /// colour or there is not.
  final GradientSpec? gradient;

  /// delay shifts this series' arrival, as a fraction of the whole animation:
  /// positive starts it later, negative starts it sooner. 0 for almost every
  /// series.
  ///
  /// A fraction rather than seconds, because how long a chart's arrival takes
  /// is the two keyframes on the timeline and they are dragged about -- an
  /// offset in seconds would mean something different every time the length
  /// changed, which is the opposite of what somebody lining two series up
  /// wants.
  ///
  /// It exists because the presets stagger by *item*, and two series drawn
  /// differently do not have the same items: a set of bars is one item per
  /// category and a line is one item per series, so the line traces over the
  /// whole window while the bars go one after another. That is right for each
  /// of them on its own and wrong for the pair, and no single stagger rule
  /// fixes it -- which is why this is a knob rather than a cleverer default.
  final double delay;

  /// width overrides the chart's stroke for this series, or 0 to draw it at
  /// whatever the chart's own is.
  ///
  /// So that a line laid over a set of bars can be heavy enough to read
  /// against them without every other line on the chart thickening with it.
  final double width;

  /// corner, smooth, points, pointSize and pointColor are how this series is
  /// drawn, or null to be drawn the way the chart is.
  ///
  /// They were the chart's own settings, in three groups under the table --
  /// Bars, Lines, Points -- which asked somebody reading a chart of bars with
  /// a line over it to work out which group was about which half of it. They
  /// are per series now, behind the series' own button, so the answer is
  /// where the question is.
  ///
  /// Null rather than a sentinel because every one of these has a meaningful
  /// zero: a corner of nought is a square bar, points off is points off. Null
  /// is the only value left to mean "whatever the chart says", which is what
  /// makes a series drawn the same way as the first one follow it.
  final double? corner;
  final bool? smooth;
  final bool? points;
  final double? pointSize;
  final Color? pointColor;

  const ChartSeries({
    required this.name,
    required this.color,
    required this.values,
    this.type,
    this.numbers,
    this.gradient,
    this.width = 0,
    this.delay = 0,
    this.corner,
    this.smooth,
    this.points,
    this.pointSize,
    this.pointColor,
  });

  /// paint is the colour and the gradient as one thing, for the picker and
  /// for the painters.
  PaintSpec get paint => PaintSpec(color, gradient: gradient);

  /// widthOn is how thick this series is drawn on a chart whose own stroke is
  /// [chartWidth].
  double widthOn(double chartWidth) => width > 0 ? width : chartWidth;

  /// cornerOn and the four beside it are the same question as [widthOn] for
  /// the rest of the drawing: this series' own answer where it has been given
  /// one, and the chart's where it has not.
  double cornerOn(double chartCorner) => corner ?? chartCorner;
  bool smoothOn(bool chartSmooth) => smooth ?? chartSmooth;
  bool pointsOn(bool chartPoints) => points ?? chartPoints;
  double pointSizeOn(double chartSize) => pointSize ?? chartSize;
  Color pointColorOn(Color chartColor) => pointColor ?? chartColor;

  /// revealAt is how far through its own arrival this series is, given how
  /// far through the whole thing the chart is.
  ///
  /// The offset moves the *start* and the series still finishes with the
  /// chart: delayed by a quarter, it waits a quarter and then has three
  /// quarters of the window to arrive in. Brought forward by a quarter, it
  /// starts at once and is done a quarter early.
  ///
  /// Squeezed into what is left rather than shifted whole, which is what this
  /// did first and was wrong: shifted, a series delayed by a quarter was only
  /// three quarters arrived when the chart stopped animating -- and then the
  /// chart drew itself complete, so the series appeared to race and jump to
  /// the end.
  double revealAt(double reveal) {
    if (delay == 0) return reveal;
    // Never the whole window: an offset of one would leave no time at all,
    // and a series that arrives in no time does not arrive.
    var shift = delay.clamp(-0.95, 0.95);
    var window = 1 - shift.abs();
    var into = shift > 0 ? reveal - shift : reveal;
    return (into / window).clamp(0.0, 1.0);
  }

  /// typeIn is how this series is actually drawn on a chart of [chartType].
  ChartType typeIn(ChartType chartType) => type ?? chartType;

  ChartSeries copyWith({
    String? name,
    Color? color,
    List<double>? values,
    ChartType? type,
    ChartNumbers? numbers,
    GradientSpec? gradient,
    double? width,
    double? delay,
    double? corner,
    bool? smooth,
    bool? points,
    double? pointSize,
    Color? pointColor,
    bool followChart = false,
    bool writtenLikeChart = false,
    bool oneColour = false,
  }) =>
      ChartSeries(
        name: name ?? this.name,
        color: color ?? this.color,
        values: values ?? this.values,
        type: followChart ? null : (type ?? this.type),
        numbers: writtenLikeChart ? null : (numbers ?? this.numbers),
        gradient: oneColour ? null : (gradient ?? this.gradient),
        width: width ?? this.width,
        delay: delay ?? this.delay,
        corner: corner ?? this.corner,
        smooth: smooth ?? this.smooth,
        points: points ?? this.points,
        pointSize: pointSize ?? this.pointSize,
        pointColor: pointColor ?? this.pointColor,
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "color": colorToJson(color),
        "values": values,
        if (type != null) "type": type!.name,
        if (numbers != null) "numbers": numbers!.toJson(),
        if (gradient != null) "gradient": gradient!.toJson(),
        if (width > 0) "width": width,
        if (delay != 0) "delay": delay,
        // Written only where this series has been given its own, so a chart
        // whose series all follow it saves the same file it always did.
        if (corner != null) "corner": corner,
        if (smooth != null) "smooth": smooth,
        if (points != null) "points": points,
        if (pointSize != null) "pointSize": pointSize,
        if (pointColor != null) "pointColor": colorToJson(pointColor!),
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
      numbers: json["numbers"] is Map<String, dynamic>
          ? ChartNumbers.fromJson(json["numbers"] as Map<String, dynamic>)
          : null,
      // A gradient saved before the second colour moved into the picker
      // carried an "on" flag with it, and one saved switched off is one
      // nobody wanted: read as no gradient rather than as a black fade.
      gradient: json["gradient"] is Map<String, dynamic> &&
              (json["gradient"] as Map<String, dynamic>)["on"] != false
          ? GradientSpec.fromJson(json["gradient"] as Map<String, dynamic>)
          : null,
      width: json["width"] is num ? (json["width"] as num).toDouble() : 0,
      delay: json["delay"] is num
          ? (json["delay"] as num).toDouble().clamp(-1.0, 1.0)
          : 0,
      corner: json["corner"] is num ? (json["corner"] as num).toDouble() : null,
      smooth: json["smooth"] is bool ? json["smooth"] as bool : null,
      points: json["points"] is bool ? json["points"] as bool : null,
      pointSize: json["pointSize"] is num
          ? (json["pointSize"] as num).toDouble()
          : null,
      pointColor:
          json["pointColor"] == null ? null : colorFromJson(json["pointColor"]),
      values: raw is List
          ? [for (var v in raw) v is num ? v.toDouble() : 0.0]
          : const [],
    );
  }
}

/// Ohlc is one period of a candlestick chart: where the price opened, the
/// highest and lowest it reached, and where it closed.
class Ohlc {
  final double open;
  final double high;
  final double low;
  final double close;

  const Ohlc(this.open, this.high, this.low, this.close);

  /// rose is whether the period closed above where it opened, which is the
  /// only thing that decides a candle's colour.
  bool get rose => close >= open;

  /// top and bottom are the body's ends, which are the open and the close
  /// whichever way round they came.
  double get top => math.max(open, close);
  double get bottom => math.min(open, close);
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

  /// ohlcAt is one period of a candlestick chart, or null when there is not
  /// enough to draw one.
  ///
  /// Four series read as one mark. By name where the names say which is
  /// which -- a source that sends "Open, High, Low, Close" in any order is
  /// read correctly -- and by position otherwise, which is the order every
  /// market API sends them in and the order anybody typing them would use.
  ///
  /// Reading the names is what makes the ordinary path work without a fifth
  /// setting to say which column is which: the mapping already named the
  /// columns, and naming them twice is a thing to get wrong.
  Ohlc? ohlcAt(int row) {
    if (series.length < 4) return null;
    var at = _ohlcOrder ?? const [0, 1, 2, 3];
    return Ohlc(
      valueAt(at[0], row),
      valueAt(at[1], row),
      valueAt(at[2], row),
      valueAt(at[3], row),
    );
  }

  /// _ohlcOrder is which series is the open, the high, the low and the close,
  /// worked out from their names -- or null when the names do not say, in
  /// which case the first four in order are taken.
  ///
  /// All four have to be found, and found once each. Half a match is worse
  /// than none: a chart drawing the high as the open because one column
  /// happened to be called "Close price" and another "Closing" would be
  /// wrong in a way nobody could see.
  List<int>? get _ohlcOrder {
    var wanted = ["open", "high", "low", "close"];
    var found = <int>[];
    for (var word in wanted) {
      var at = -1;
      for (var i = 0; i < series.length; i++) {
        if (series[i].name.toLowerCase().contains(word) && !found.contains(i)) {
          at = i;
          break;
        }
      }
      if (at < 0) return null;
      found.add(at);
    }
    return found;
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
  static ChartData parse(String text,
      {List<Color>? colors, List<ChartSeries>? keep}) {
    var rows = splitTable(text);
    if (rows.isEmpty) return const ChartData();

    var header = rows.first;
    // Through cellNumber, so a row beginning "Jan 1,000" is a row of numbers
    // and not a header. tryParse refuses a thousands separator, which made
    // every figure written the way people write it look like a word.
    var hasHeader =
        header.length > 1 && header.skip(1).every((c) => cellNumber(c) == null);
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
        values[i].add(cellNumber(cell) ?? 0);
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
            // What was decided about how it looks survives its numbers being
            // retyped, the same way it survives a refresh.
            numbers: keep != null && i < keep.length ? keep[i].numbers : null,
            gradient: keep != null && i < keep.length ? keep[i].gradient : null,
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

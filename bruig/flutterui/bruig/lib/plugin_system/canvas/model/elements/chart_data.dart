import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';

// chart_data.dart is the numbers a chart is drawn from: the series, the
// categories they are indexed by, and the colours they arrive in. It is what
// the data editor and the paste (tabular_text.dart) change; chart_element.dart
// is the settings. ChartType is here because the data has to know it.

/// ChartLineStyle is what a line is drawn as: a stroke, a run of dashes, or a
/// run of dots.
///
/// A property of the series, separate from the marking of an estimated year:
/// a dotted series stays dotted across an estimated stretch, where faintness
/// carries the estimate.
enum ChartLineStyle {
  solid("Solid"),
  dashed("Dashed"),
  dotted("Dotted");

  final String label;
  const ChartLineStyle(this.label);

  static ChartLineStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ChartLineStyle.solid,
      );

  /// pattern is the on and off lengths, in multiples of the line's own
  /// weight, or null for solid. A dot is a near-zero dash drawn with a round
  /// cap.
  List<double>? get pattern => switch (this) {
        ChartLineStyle.solid => null,
        ChartLineStyle.dashed => const [2.6, 2.0],
        ChartLineStyle.dotted => const [0.02, 1.9],
      };
}

/// ChartBackdropGrow is where a bar's background grows from when it is a
/// different size from the bar.
///
/// Left and right anchor it to that side of the bar, and grow it up from the
/// axis. Bottom grows it up from the axis, centred across the bar; top hangs
/// it down from the top of the chart; centre centres it both ways, about the
/// middle of the chart. On a chart drawn sideways, "up" is along the bars
/// and "left" is the edge nearer the top.
enum ChartBackdropGrow {
  left("Left"),
  centre("Centre"),
  right("Right"),
  bottom("Bottom"),
  top("Top");

  final String label;
  const ChartBackdropGrow(this.label);

  static ChartBackdropGrow fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ChartBackdropGrow.centre,
      );
}

/// maxBackdropHeight is the tallest a bar's background is drawn, as a share
/// of the chart's height.
const double maxBackdropHeight = 3;

/// ChartBackdrop is a panel drawn behind every bar of one series: the track
/// a progress bar fills, or a card each bar stands on.
///
/// [height] is a share of the plot along the value axis (1 is the whole
/// chart); [width] is a share of the bar's thickness. Kept when switched off,
/// so switching it back on finds it as it was.
class ChartBackdrop {
  final bool on;
  final double height;
  final double width;
  final Color fill;
  final Color border;
  final double radius;
  final double borderWidth;
  final ChartBackdropGrow grow;

  const ChartBackdrop({
    this.on = false,
    this.height = 1,
    this.width = 1,
    this.fill = const Color(0x33FFFFFF),
    this.border = const Color(0x00000000),
    this.radius = 0,
    this.borderWidth = 0,
    this.grow = ChartBackdropGrow.centre,
  });

  ChartBackdrop copyWith({
    bool? on,
    double? height,
    double? width,
    Color? fill,
    Color? border,
    double? radius,
    double? borderWidth,
    ChartBackdropGrow? grow,
  }) =>
      ChartBackdrop(
        on: on ?? this.on,
        height: height ?? this.height,
        width: width ?? this.width,
        fill: fill ?? this.fill,
        border: border ?? this.border,
        radius: radius ?? this.radius,
        borderWidth: borderWidth ?? this.borderWidth,
        grow: grow ?? this.grow,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        "height": height,
        "width": width,
        "fill": colorToJson(fill),
        "border": colorToJson(border),
        "radius": radius,
        "borderWidth": borderWidth,
        "grow": grow.name,
      };

  factory ChartBackdrop.fromJson(Map<String, dynamic> json) {
    double num_(String k, double or, double lo, double hi) =>
        json[k] is num ? (json[k] as num).toDouble().clamp(lo, hi) : or;
    return ChartBackdrop(
      on: json["on"] == true,
      height: num_("height", 1, 0, maxBackdropHeight),
      width: num_("width", 1, 0.1, 4),
      fill: colorFromJson(json["fill"], const Color(0x33FFFFFF)),
      border: colorFromJson(json["border"], const Color(0x00000000)),
      radius: num_("radius", 0, 0, 200),
      borderWidth: num_("borderWidth", 0, 0, 40),
      grow: ChartBackdropGrow.fromName(jsonStr(json["grow"])),
    );
  }
}

/// missingValue is a cell nobody filled in. A NaN rather than a nullable
/// double, so a series' values stay a plain list of doubles; the places that
/// care ask [ChartData.hasValueAt].
const double missingValue = double.nan;

/// maxSeriesDelay is how far a series may be offset, in seconds either way:
/// a guard against a typo, not a scale.
const double maxSeriesDelay = 30;

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
  bool get isCandles => this == candlestick;

  /// startsAtZero is whether the value axis has to include zero. Bars are
  /// read as lengths, so they must; a candlestick is read as a position, and
  /// forcing it down to zero squeezes the month into a sliver.
  bool get startsAtZero => !isCandles;

  /// isStacked is whether values accumulate, which changes how the axis
  /// maximum is worked out.
  bool get isStacked => this == stackedBar;

  /// needsFourSeries is the candlestick's requirement, so the settings can
  /// say so rather than draw nothing.
  bool get needsFourSeries => isCandles;

  /// needsMultipleSeries is whether the type only differs from plain bars
  /// once there are two series to group or stack.
  bool get needsMultipleSeries => this == groupedBar || this == stackedBar;

  /// usesSmooth is whether curving between the points means anything.
  bool get usesSmooth => this == line || this == area || this == radar;

  /// isCartesian is everything drawn against an x and a y axis.
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

/// chartPalette is the default series colours, ordered so the first three
/// stay distinguishable in greyscale.
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
  /// of bars can have a line over it, or null for the chart's own. Only
  /// meaningful on cartesian types.
  final ChartType? type;

  /// numbers writes this series' values differently from the rest of the
  /// chart (a price beside a market cap), or null for the chart's own. The
  /// axis always keeps the chart's style.
  final ChartNumbers? numbers;

  /// band fills the space between this line and the next one (by position,
  /// so it survives reordering), fading from this series' colour into the
  /// next one's.
  final bool band;

  /// lineStyle is whether this series is drawn as a stroke, a run of dashes
  /// or a run of dots. Only meaningful where the series is drawn as a line.
  final ChartLineStyle lineStyle;

  /// hidden takes this series off the chart without taking it out of the
  /// table; toggled from its entry in the key. The axis re-scales to what is
  /// left.
  final bool hidden;

  /// gradient draws this series in two colours instead of one, or null. Set
  /// in the colour picker beside [color], so it has no on/off flag.
  final GradientSpec? gradient;

  /// delay shifts this series' arrival in **seconds**: positive starts it
  /// later, negative sooner. A shift in time, not a change of speed; see
  /// chartSeriesReveal.
  ///
  /// Needed because presets stagger by item, and bars (one item per
  /// category) and a line (one per series) on the same chart do not line up.
  final double delay;

  /// width overrides the chart's stroke for this series, or 0 for the
  /// chart's own.
  final double width;

  /// corner, smooth, points, pointSize and pointColor are how this series is
  /// drawn, or null to follow the chart (each has a meaningful zero, so null
  /// is the only "unset").
  final double? corner;
  final bool? smooth;
  final bool? points;
  final double? pointSize;
  final Color? pointColor;

  /// backdrop is the panel drawn behind each of this series' bars, or null
  /// for none. Only drawn where the series is drawn as bars.
  final ChartBackdrop? backdrop;

  const ChartSeries({
    required this.name,
    required this.color,
    required this.values,
    this.type,
    this.numbers,
    this.gradient,
    this.hidden = false,
    this.band = false,
    this.lineStyle = ChartLineStyle.solid,
    this.width = 0,
    this.delay = 0,
    this.corner,
    this.smooth,
    this.points,
    this.pointSize,
    this.pointColor,
    this.backdrop,
  });

  /// paint is the colour and the gradient as one thing, for the picker and
  /// for the painters.
  PaintSpec get paint => PaintSpec(color, gradient: gradient);

  /// widthOn is how thick this series is drawn on a chart whose own stroke is
  /// [chartWidth].
  double widthOn(double chartWidth) => width > 0 ? width : chartWidth;

  /// cornerOn and the four beside it are like [widthOn]: this series' own
  /// value where set, else the chart's.
  double cornerOn(double chartCorner) => corner ?? chartCorner;
  bool smoothOn(bool chartSmooth) => smooth ?? chartSmooth;
  bool pointsOn(bool chartPoints) => points ?? chartPoints;
  double pointSizeOn(double chartSize) => pointSize ?? chartSize;
  Color pointColorOn(Color chartColor) => pointColor ?? chartColor;

  /// typeIn is how this series is actually drawn on a chart of [chartType].
  ChartType typeIn(ChartType chartType) => type ?? chartType;

  ChartSeries copyWith({
    String? name,
    Color? color,
    List<double>? values,
    ChartType? type,
    ChartNumbers? numbers,
    GradientSpec? gradient,
    bool? hidden,
    bool? band,
    ChartLineStyle? lineStyle,
    double? width,
    double? delay,
    double? corner,
    bool? smooth,
    bool? points,
    double? pointSize,
    Color? pointColor,
    ChartBackdrop? backdrop,
    bool followChart = false,
    bool writtenLikeChart = false,
    bool oneColour = false,

    /// drawnLikeChart drops every override about how this series is drawn,
    /// for the series that leads its kind of drawing: the panel writes its
    /// settings to the chart, so an override would keep winning.
    bool drawnLikeChart = false,
  }) =>
      ChartSeries(
        name: name ?? this.name,
        color: color ?? this.color,
        values: values ?? this.values,
        type: followChart ? null : (type ?? this.type),
        numbers: writtenLikeChart ? null : (numbers ?? this.numbers),
        gradient: oneColour ? null : (gradient ?? this.gradient),
        hidden: hidden ?? this.hidden,
        band: drawnLikeChart ? false : (band ?? this.band),
        lineStyle: drawnLikeChart
            ? ChartLineStyle.solid
            : (lineStyle ?? this.lineStyle),
        width: drawnLikeChart ? 0 : (width ?? this.width),
        delay: delay ?? this.delay,
        corner: drawnLikeChart ? null : (corner ?? this.corner),
        smooth: drawnLikeChart ? null : (smooth ?? this.smooth),
        points: drawnLikeChart ? null : (points ?? this.points),
        pointSize: drawnLikeChart ? null : (pointSize ?? this.pointSize),
        pointColor: drawnLikeChart ? null : (pointColor ?? this.pointColor),
        backdrop: backdrop ?? this.backdrop,
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "color": colorToJson(color),
        // A gap is written as a null, because JSON has no NaN.
        "values": [for (var v in values) v.isNaN ? null : v],
        if (type != null) "type": type!.name,
        if (numbers != null) "numbers": numbers!.toJson(),
        if (gradient != null) "gradient": gradient!.toJson(),
        if (hidden) "off": true,
        if (lineStyle != ChartLineStyle.solid) "line": lineStyle.name,
        if (band) "band": true,
        if (width > 0) "width": width,
        if (delay != 0) "delay": delay,
        // Written only where this series has its own.
        if (corner != null) "corner": corner,
        if (smooth != null) "smooth": smooth,
        if (points != null) "points": points,
        if (pointSize != null) "pointSize": pointSize,
        if (pointColor != null) "pointColor": colorToJson(pointColor!),
        if (backdrop != null) "backdrop": backdrop!.toJson(),
      };

  factory ChartSeries.fromJson(Map<String, dynamic> json, int index) {
    var raw = json["values"];
    return ChartSeries(
      name: jsonString(json["name"], "Series ${index + 1}"),
      color: colorFromJson(
          json["color"], chartPalette[index % chartPalette.length]),
      type: json["type"] is String
          ? ChartType.fromName(jsonStr(json["type"]))
          : null,
      numbers: json["numbers"] is Map<String, dynamic>
          ? ChartNumbers.fromJson(json["numbers"] as Map<String, dynamic>)
          : null,
      gradient: json["gradient"] is Map<String, dynamic>
          ? GradientSpec.fromJson(json["gradient"] as Map<String, dynamic>)
          : null,
      hidden: json["off"] == true,
      lineStyle: ChartLineStyle.fromName(jsonStr(json["line"])),
      band: json["band"] == true,
      width: json["width"] is num ? (json["width"] as num).toDouble() : 0,
      delay: json["delay"] is num
          ? (json["delay"] as num)
              .toDouble()
              .clamp(-maxSeriesDelay, maxSeriesDelay)
          : 0,
      corner: json["corner"] is num ? (json["corner"] as num).toDouble() : null,
      smooth: json["smooth"] is bool ? json["smooth"] as bool : null,
      points: json["points"] is bool ? json["points"] as bool : null,
      pointSize: json["pointSize"] is num
          ? (json["pointSize"] as num).toDouble()
          : null,
      pointColor:
          json["pointColor"] == null ? null : colorFromJson(json["pointColor"]),
      backdrop: json["backdrop"] is Map<String, dynamic>
          ? ChartBackdrop.fromJson(json["backdrop"] as Map<String, dynamic>)
          : null,
      // A null is a cell nobody filled in; anything else not a number is 0.
      values: raw is List
          ? [
              for (var v in raw)
                v == null
                    ? missingValue
                    : v is num
                        ? v.toDouble()
                        : 0.0
            ]
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

  /// rose is whether the period closed at or above where it opened, which
  /// decides a candle's colour.
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

  /// estimated marks the rows (categories, not series: a year is sourced or
  /// it is not) whose figures are worked out rather than looked up. Empty on
  /// charts that do not mark them.
  final List<bool> estimated;

  const ChartData({
    this.categories = const [],
    this.series = const [],
    this.estimated = const [],
  });

  bool get isEmpty => series.isEmpty || categories.isEmpty;

  ChartData copyWith({
    List<String>? categories,
    List<ChartSeries>? series,
    List<bool>? estimated,
  }) =>
      ChartData(
        categories: categories ?? this.categories,
        series: series ?? this.series,
        estimated: estimated ?? this.estimated,
      );

  /// withRowRemoved takes a row out of the categories, every series and the
  /// estimate marks, keeping the three lists in step.
  ChartData withRowRemoved(int row) => ChartData(
        categories: [...categories]..removeAt(row),
        series: [
          for (var s in series)
            s.copyWith(
                values: row < s.values.length
                    ? ([...s.values]..removeAt(row))
                    : s.values),
        ],
        estimated: row < estimated.length
            ? ([...estimated]..removeAt(row))
            : estimated,
      );

  /// withEstimated marks or unmarks one row.
  ChartData withEstimated(int row, bool value) {
    var out = [...estimated];
    while (out.length <= row) {
      out.add(false);
    }
    out[row] = value;
    return copyWith(estimated: out);
  }

  /// isEstimated is whether [row]'s figures are worked out rather than looked
  /// up. False for every row of a chart that does not mark them.
  bool isEstimated(int row) =>
      row >= 0 && row < estimated.length && estimated[row];

  /// marksEstimates is whether this chart marks any row estimated, which
  /// decides whether the key explains the two weights.
  bool get marksEstimates => estimated.contains(true);

  /// valueAt is the number at [row] of [seriesIndex], [missingValue] for a
  /// gap, or zero where the data is ragged (normal, not an error).
  double valueAt(int seriesIndex, int row) {
    if (seriesIndex < 0 || seriesIndex >= series.length) return 0;
    var v = series[seriesIndex].values;
    return row >= 0 && row < v.length ? v[row] : 0;
  }

  /// hasValueAt is whether there is a number there at all: an empty cell is
  /// a gap, not a nought, and is drawn as one.
  bool hasValueAt(int seriesIndex, int row) => !valueAt(seriesIndex, row).isNaN;

  /// ohlcAt is one period of a candlestick chart, or null when there are not
  /// four series. The series are matched by name where the names say which
  /// is which, else taken in open, high, low, close order.
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
  /// from their names, or null unless all four are found once each (half a
  /// match would be silently wrong).
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

  /// asText renders the data back into the format [parse] reads, for the
  /// quick-entry box.
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

  // A gap writes as nothing, which is what parse reads back as a gap.
  static String _num(double v) => v.isNaN
      ? ""
      : v == v.roundToDouble()
          ? v.round().toString()
          : v.toString();

  /// parse reads a pasted table, split by [splitTable]. The first row is
  /// series names if none of its cells after the first is a number.
  ///
  /// [keep] is the series this is replacing, if any: their settings are
  /// carried across by position, so retyping the numbers keeps how each
  /// series is drawn.
  static ChartData parse(String text,
      {List<Color>? colors, List<ChartSeries>? keep}) {
    var rows = splitTable(text);
    if (rows.isEmpty) return const ChartData();

    var header = rows.first;
    // cellNumber, not tryParse, so "1,000" counts as a number.
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
        // Empty is a gap; something unreadable is a typo, read as 0.
        values[i]
            .add(cell.trim().isEmpty ? missingValue : cellNumber(cell) ?? 0);
      }
    }

    return ChartData(
      categories: categories,
      series: [
        for (var i = 0; i < names.length; i++)
          if (keep != null && i < keep.length)
            keep[i].copyWith(
                name: names[i],
                values: values[i],
                color: colors != null && i < colors.length ? colors[i] : null)
          else
            ChartSeries(
              name: names[i],
              color: colors != null && i < colors.length
                  ? colors[i]
                  : chartPalette[i % chartPalette.length],
              values: values[i],
            ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        "categories": categories,
        "series": series.map((s) => s.toJson()).toList(),
        if (estimated.contains(true)) "est": estimated,
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
      estimated: json["est"] is List
          ? [for (var v in json["est"] as List) v == true]
          : const [],
    );
  }
}

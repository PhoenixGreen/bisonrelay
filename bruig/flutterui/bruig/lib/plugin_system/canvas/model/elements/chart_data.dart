import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
  static ChartData parse(String text,
      {List<Color>? colors, List<ChartSeries>? keep}) {
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

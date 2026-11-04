import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_legend.dart is a chart's key: where it sits, which way it runs, how
// big it is and what each entry says.

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
/// Whether it is shown stays on the element as showLegend, where saved
/// documents keep it.
class ChartLegend {
  final LegendPlacement placement;

  /// vertical puts one entry per line; otherwise entries wrap along the
  /// width given, which suits a key above or below the chart.
  final bool vertical;

  /// scale sizes the key against the chart's own label size, so a legend
  /// stays in proportion when the labels are changed and can still be made
  /// bigger or smaller than them.
  final double scale;

  /// spacing is the gap between one entry and the next, in ems of the key's
  /// own type.
  final double spacing;

  /// x and y are where the key sits when the labels are floating, as
  /// fractions of the chart's box. NaN until it is dragged, and then
  /// [placement] no longer decides where it goes.
  final double x;
  final double y;

  /// separator goes between an entry's name and its number; one of
  /// [separators].
  final String separator;

  /// values writes each entry's number beside its name. Separate from the
  /// chart's showValues so bars and key can differ (a radial bar can show
  /// its numbers only in the key).
  final bool values;

  const ChartLegend({
    this.placement = LegendPlacement.top,
    this.vertical = false,
    this.scale = 1,
    this.spacing = 1,
    this.values = false,
    this.separator = ": ",
    this.x = double.nan,
    this.y = double.nan,
  });

  /// hasPlace is whether it has been dragged somewhere of its own.
  bool get hasPlace => !x.isNaN && !y.isNaN;

  /// separators are the ones offered: a fixed list rather than free text.
  static const List<(String, String)> separators = [
    (": ", "Colon"),
    (" - ", "Dash"),
    (" — ", "Long dash"),
    ("  ", "A space"),
    (" = ", "Equals"),
  ];

  ChartLegend copyWith({
    LegendPlacement? placement,
    bool? vertical,
    double? scale,
    double? spacing,
    bool? values,
    String? separator,
    double? x,
    double? y,
    bool unplace = false,
  }) =>
      ChartLegend(
        placement: placement ?? this.placement,
        vertical: vertical ?? this.vertical,
        scale: scale ?? this.scale,
        spacing: spacing ?? this.spacing,
        values: values ?? this.values,
        separator: separator ?? this.separator,
        x: unplace ? double.nan : (x ?? this.x),
        y: unplace ? double.nan : (y ?? this.y),
      );

  Map<String, dynamic> toJson() => {
        "at": placement.name,
        if (vertical) "vertical": true,
        if (scale != 1) "scale": scale,
        if (spacing != 1) "spacing": spacing,
        if (values) "values": true,
        if (separator != ": ") "sep": separator,
        if (hasPlace) "x": x,
        if (hasPlace) "y": y,
      };

  factory ChartLegend.fromJson(Map<String, dynamic> json) => ChartLegend(
        placement: LegendPlacement.fromName(jsonStr(json["at"])),
        vertical: jsonBool(json["vertical"], false),
        scale: jsonDouble(json["scale"], 1).clamp(0.3, 4.0),
        spacing: jsonDouble(json["spacing"], 1).clamp(0.0, 6.0),
        values: jsonBool(json["values"], false),
        separator: jsonString(json["sep"], ": "),
        x: jsonDouble(json["x"], double.nan),
        y: jsonDouble(json["y"], double.nan),
      );
}

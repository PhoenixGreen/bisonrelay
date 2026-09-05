import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_legend.dart is the key: where it sits, which way it runs, how big it
// is and what each entry says.
//
// Whether there is one at all stays on the element as showLegend, where every
// saved document already has it. Everything else about the key is here,
// because a key is the one part of a chart people adjust for a while, and its
// settings outnumber the ones for the chart itself.

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

  /// x and y are where the key sits when the labels are floating, as
  /// fractions of the chart's box. NaN until it is dragged, and then
  /// [placement] no longer decides where it goes.
  final double x;
  final double y;

  /// separator goes between an entry's name and its number.
  ///
  /// A string rather than a boolean, because which one reads best depends on
  /// the names: a colon after "Q1" is a label and a colon after "Revenue
  /// 2024" is a sentence, and two spaces is enough on a short list.
  final String separator;

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
    this.separator = ": ",
    this.x = double.nan,
    this.y = double.nan,
  });

  /// hasPlace is whether it has been dragged somewhere of its own.
  bool get hasPlace => !x.isNaN && !y.isNaN;

  /// separators are the ones offered. Free text would be a field somebody
  /// could put a paragraph in.
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
        placement: LegendPlacement.fromName(json["at"] as String?),
        vertical: jsonBool(json["vertical"], false),
        scale: jsonDouble(json["scale"], 1).clamp(0.3, 4.0),
        spacing: jsonDouble(json["spacing"], 1).clamp(0.0, 6.0),
        values: jsonBool(json["values"], false),
        separator: jsonString(json["sep"], ": "),
        x: jsonDouble(json["x"], double.nan),
        y: jsonDouble(json["y"], double.nan),
      );
}

import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// A chart's data, its animation and its key are each large enough to be read
// on their own, and each is worked on without the others. They are exported
// so that "import chart_element.dart" still brings a whole chart -- splitting
// a model into four files that every caller then has to import four of is a
// tidier directory and a worse codebase.
export 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';

import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';

// chart_element.dart is a chart as data plus a handful of decisions, drawn
// from scratch by render/chart_painter.dart.
//
// No charting library. Not for lack of one -- it is that everything else on
// this canvas is a path on a ui.Canvas that exports at any size, animates
// through the same keyframes and rotates with the same handles, and a widget
// from a package is none of those. A chart here is 200 lines of trigonometry
// that behaves exactly like a star or a pitch does, which is worth far more
// than the features a library would have brought.

/// ChartLabel is a chart's title or description: whether it is shown, and
/// where.
///
/// Whether the place is *used* is [ChartElement.floatingLabels]. A chart lays
/// its own title out -- stacked at the top, taking the height it needs and
/// giving the rest to the plot -- which is right until somebody wants the
/// title down the side or over the corner of the plot, and there is no
/// arrangement of automatic rules that covers both.
///
/// The coordinates are kept either way, which is what makes the switch a
/// switch rather than a decision: turning it off puts the chart back exactly
/// as it was, and turning it on again finds the labels where they were
/// dragged to rather than back at their defaults.
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

  /// hasPlace is whether it has been given coordinates of its own. Without
  /// them a floating label falls back to where the chart would have put it --
  /// see defaultTitlePlacement.
  bool get hasPlace => !x.isNaN;

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
        if (hasPlace) "x": x,
        if (hasPlace) "y": y,
        if (hasPlace) "w": width,
        if (hasPlace) "h": height,
      };

  factory ChartLabel.fromJson(Map<String, dynamic> json) => ChartLabel(
        show: !jsonBool(json["off"], false),
        x: jsonDouble(json["x"], double.nan),
        y: jsonDouble(json["y"], 0),
        width: jsonDouble(json["w"], 1),
        height: jsonDouble(json["h"], 0.14),
      );
}

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
  static ChartBody fitting(Rect want, Rect box) =>
      box.width <= 0 || box.height <= 0
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
      ? (title.hasPlace
          ? title.y + title.height
          : defaultTitlePlacement.y + defaultTitlePlacement.height)
      : 0.02;
  return ChartLabel(
      x: hasTitle && title.hasPlace ? title.x : 0.02,
      y: top + 0.01,
      width: hasTitle && title.hasPlace ? title.width : 0.96,
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

  /// floatingLabels puts the title, the description and the key *over* the
  /// chart instead of taking room from it, and lets them be dragged anywhere.
  ///
  /// Off to begin with. Stacked above the plot is what a chart looks like and
  /// is right until somebody wants otherwise; floating is the answer to "I
  /// want the title in that corner", which is a thing to ask for rather than
  /// a thing to be given.
  ///
  /// On, each of the three sits where it has been put -- or where the chart
  /// would have put it, until it is moved -- and takes no room from the plot,
  /// so none of their settings resizes the chart. The coordinates are kept
  /// when it is switched off again, so the switch goes both ways without
  /// losing anything.
  final bool floatingLabels;

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

  /// showAxisLabels is the writing along the axes: the tick values, the
  /// category names and the two axis titles.
  ///
  /// One switch for all of it rather than three. They are read together or
  /// not at all -- a chart with numbers up the side and no categories along
  /// the bottom is not a simpler chart, it is a broken one -- and what
  /// switching them off is for is a small chart in a corner that is a shape
  /// rather than a reading.
  final bool showAxisLabels;
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
    this.floatingLabels = false,
    this.descriptionSpec,
    this.xAxisLabel = "",
    this.yAxisLabel = "",
    this.showGrid = true,
    this.showAxes = true,
    this.showAxisLabels = true,
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

  /// aroundTheChart is this element with its box back round the chart itself.
  ///
  /// Dragging a floating label outside the box grows the box to hold it and
  /// insets the body to keep the chart where it was. Switched off, the label
  /// goes back into the chart's own arrangement -- and without this the box
  /// stayed grown, so the chart sat small in the middle of an element with a
  /// margin of nothing around it, and the switch did not go both ways after
  /// all.
  ChartElement aroundTheChart() {
    if (body.isWhole) return this;
    var was = body.rectIn(Rect.fromLTWH(x, y, width, height));
    return copyWith(body: const ChartBody()).withBase(
      x: was.left,
      y: was.top,
      width: was.width,
      height: was.height,
    ) as ChartElement;
  }

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
    bool? floatingLabels,
    TextSpec? descriptionSpec,
    String? xAxisLabel,
    String? yAxisLabel,
    bool? showGrid,
    bool? showAxes,
    bool? showAxisLabels,
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
          floatingLabels: floatingLabels,
          descriptionSpec: descriptionSpec,
          xAxisLabel: xAxisLabel,
          yAxisLabel: yAxisLabel,
          showGrid: showGrid,
          showAxes: showAxes,
          showAxisLabels: showAxisLabels,
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
    bool? floatingLabels,
    TextSpec? descriptionSpec,
    String? xAxisLabel,
    String? yAxisLabel,
    bool? showGrid,
    bool? showAxes,
    bool? showAxisLabels,
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
          floatingLabels: floatingLabels ?? this.floatingLabels,
          descriptionSpec: descriptionSpec ?? this.descriptionSpec,
          xAxisLabel: xAxisLabel ?? this.xAxisLabel,
          yAxisLabel: yAxisLabel ?? this.yAxisLabel,
          showGrid: showGrid ?? this.showGrid,
          showAxes: showAxes ?? this.showAxes,
          showAxisLabels: showAxisLabels ?? this.showAxisLabels,
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
        if (floatingLabels) "floatLabels": true,
        if (descriptionSpec != null) "descSpec": descriptionSpec!.toJson(),
        if (xAxisLabel.isNotEmpty) "xlabel": xAxisLabel,
        if (yAxisLabel.isNotEmpty) "ylabel": yAxisLabel,
        "grid": showGrid,
        "axes": showAxes,
        if (!showAxisLabels) "noAxisLabels": true,
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
          titleBox:
              jsonSpec(json["titleBox"], ChartLabel.fromJson,
                  const ChartLabel()),
          descriptionBox:
              jsonSpec(json["descBox"], ChartLabel.fromJson,
                  const ChartLabel(height: 0.1)),
          body: jsonSpec(json["body"], ChartBody.fromJson, const ChartBody()),
          animation:
              jsonSpec(json["anim"], ChartAnimation.fromJson,
                  const ChartAnimation()),
          legend:
              jsonSpec(json["legendSpec"], ChartLegend.fromJson,
                  const ChartLegend()),
          floatingLabels: jsonBool(json["floatLabels"], false),
          descriptionSpec:
              json["descSpec"]
                      is Map<String, dynamic>
                  ? TextSpec.fromJson(json["descSpec"] as Map<String, dynamic>)
                  : null,
          xAxisLabel: jsonString(json["xlabel"], ""),
          yAxisLabel: jsonString(json["ylabel"], ""),
          showGrid: jsonBool(json["grid"], true),
          showAxes: jsonBool(json["axes"], true),
          showAxisLabels: !jsonBool(json["noAxisLabels"], false),
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

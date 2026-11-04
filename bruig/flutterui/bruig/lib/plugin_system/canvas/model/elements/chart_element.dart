import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';

// The chart's data, animation and key live in their own files, exported so
// that importing chart_element.dart still brings a whole chart.
export 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';

import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';

// chart_element.dart is a chart as data plus its settings, drawn from scratch
// by render/chart_painter.dart. No charting library: a chart is painted on a
// ui.Canvas like every other element, so it exports at any size, animates and
// rotates the same way.

/// ChartLabel is a chart's title or description: whether it is shown, and
/// where. The place is used only with [ChartElement.floatingLabels], and is
/// kept when that is off so turning it on again finds the labels where they
/// were dragged.
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

/// ChartBody is where the chart itself is drawn within the element's box, as
/// fractions of the box.
///
/// The whole box, until a floating label is dragged outside it. The box then
/// grows to hold the label (so a marquee picks it up) and the body is inset
/// so the plot stays where it was. Resizing by the handles scales the body
/// with everything else.
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
/// goes the first time it floats: across the top, title first and the
/// description under it.
const ChartLabel defaultTitlePlacement =
    ChartLabel(x: 0.02, y: 0.02, width: 0.96, height: 0.14);

ChartLabel defaultDescriptionPlacement(ChartLabel title, bool hasTitle) {
  // Under the title wherever it is; with no title, at the top.
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

  /// fromTable is the table on this canvas the numbers were taken from, if
  /// they were. See [TableLink]. [data] is still the chart's own copy; this
  /// lets refreshing the table bring the chart with it.
  final TableLink fromTable;

  /// source is where the chart fetches its own numbers, when it does, so
  /// Refresh can get them again. [data] is still the chart's own copy.
  final DataSource source;

  /// fromSource is which of the fetched columns are the axis and the series,
  /// and how many points to keep. See [ChartSourceMap].
  final ChartSourceMap fromSource;

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
  /// Off by default; their places are kept when it is switched off.
  final bool floatingLabels;

  /// descriptionSpec is the description's own type, or null to follow
  /// [labelSpec].
  final TextSpec? descriptionSpec;

  final String xAxisLabel;
  final String yAxisLabel;

  /// showGrid is the ruled grid behind the plot. On by default.
  final bool showGrid;
  final bool showAxes;

  /// showXLabels and showYLabels are the tick values or category names along
  /// each axis. By axis rather than by content, since horizontal bars swap
  /// which axis carries which. The axis titles are [showXTitle] and
  /// [showYTitle].
  final bool showXLabels;
  final bool showYLabels;

  /// xLabelSize, xLabelColor and the two beside them are that axis' own size
  /// and colour, or null for [labelSpec]'s. Font and weight are the chart's.
  final double? xLabelSize;
  final Color? xLabelColor;
  final double? yLabelSize;
  final Color? yLabelColor;

  /// xLabelGap and yLabelGap move each axis's values away from the chart
  /// (or, below zero, closer to it), in points.
  final double xLabelGap;
  final double yLabelGap;

  /// showXTitle and showYTitle show or hide the axis titles, [xAxisLabel] and
  /// [yAxisLabel], without emptying them. The tick values are [showXLabels]
  /// and [showYLabels].
  final bool showXTitle;
  final bool showYTitle;

  final bool showLegend;

  /// showValues prints each number on its own bar or point.
  final bool showValues;

  final Color gridColor;
  final Color axisColor;

  /// riseColor and fallColor are a candlestick's two colours, for a period
  /// that closed up and one that closed down. Used instead of the series
  /// colours, since all four series are one mark.
  final Color riseColor;
  final Color fallColor;

  /// sliceColors are a pie's, a donut's or a radial bar's colours, one per
  /// category in order. Where it is short, the rest come from the series
  /// (where there are several) or the palette. See sliceColour.
  final List<Color> sliceColors;

  /// titleSpec, labelSpec and valueSpec are the three sizes of type on a
  /// chart. Separate so a chart shrunk to fit a corner can keep a readable
  /// title while its tick labels get out of the way.
  final TextSpec titleSpec;
  final TextSpec labelSpec;
  final TextSpec valueSpec;

  /// numbers is how a value is written: on the bars, on the points, and in a
  /// legend that carries values. See [ChartNumbers].
  final ChartNumbers numbers;

  /// axisNumbers is how the figures up the side are written, or null (the
  /// default) for the same as [numbers]. Lets a value be exact (2.049M) while
  /// the axis stays round (2.0M).
  final ChartNumbers? axisNumbers;

  /// axisSteps is roughly how many divisions the value axis is ruled into,
  /// or zero to let the chart decide. Roughly, because the steps are kept
  /// round; on a log axis it counts decades.
  final int axisSteps;

  /// logScale asks for the value axis by decades rather than evenly. Ignored
  /// where it cannot mean anything; see [logs].
  final bool logScale;

  /// axisSpec is the type the two axis titles are set in, or null to follow
  /// [labelSpec].
  final TextSpec? axisSpec;

  /// axisGap is extra room between an axis title and the plot, in document
  /// units, on top of the usual one and a half title heights.
  final double axisGap;

  /// yMin and yMax pin the value axis, or NaN (the default) to work it out
  /// from the data.
  final double yMin;
  final double yMax;

  /// barGap is the space between bars as a fraction of the slot width.
  final double barGap;
  final double barRadius;

  /// barFloor is the least height a bar is drawn at, in pixels, so a measured
  /// nought still makes a mark and looks different from a gap (see
  /// ChartData.hasValueAt). Zero by default.
  final double barFloor;

  /// innerRadius is the hole in a donut, as a fraction of the outer radius.
  final double innerRadius;

  /// centreLabel is the words in a donut's hole, or empty for none.
  /// "{total}" in them is the slices added up, counting up as they arrive.
  final String centreLabel;

  /// showPoints marks each reading on a line or an area. A scatter, and a
  /// chart writing its values, has dots whatever this says.
  final bool showPoints;

  /// pointSize is the radius of those dots, or 0 to take it from the line's
  /// weight.
  final double pointSize;

  /// pointColor is what they are drawn in, or transparent for the series'
  /// own colour.
  final Color pointColor;

  /// strokeWidth is the line weight for the line, area and radar types.
  final double strokeWidth;

  /// smooth curves a line chart through its points instead of joining them
  /// with straight segments.
  final bool smooth;

  const ChartElement(
    super.base, {
    this.type = ChartType.bar,
    this.data = const ChartData(),
    this.fromTable = const TableLink(),
    this.source = const DataSource(),
    this.fromSource = const ChartSourceMap(),
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
    this.showXLabels = true,
    this.showYLabels = true,
    this.xLabelSize,
    this.xLabelColor,
    this.yLabelSize,
    this.yLabelColor,
    this.xLabelGap = 0,
    this.yLabelGap = 0,
    this.showXTitle = true,
    this.showYTitle = true,
    this.showLegend = false,
    this.showValues = false,
    this.gridColor = const Color(0x33FFFFFF),
    this.axisColor = const Color(0x99FFFFFF),
    this.riseColor = const Color(0xFF2FD3A0),
    this.sliceColors = const [],
    this.fallColor = const Color(0xFFE85D75),
    this.axisSteps = 0,
    this.logScale = false,
    this.numbers = const ChartNumbers(),
    this.axisNumbers,
    this.axisSpec,
    this.axisGap = 0,
    this.titleSpec = const TextSpec(fontSize: 28, weight: 700),
    this.labelSpec = const TextSpec(fontSize: 16, weight: 400),
    this.valueSpec = const TextSpec(fontSize: 14, weight: 600),
    this.yMin = double.nan,
    this.yMax = double.nan,
    this.barGap = 0.3,
    this.barRadius = 4,
    this.barFloor = 0,
    this.innerRadius = 0.55,
    this.centreLabel = "",
    this.showPoints = false,
    this.pointSize = 0,
    this.pointColor = const Color(0x00000000),
    this.strokeWidth = 3,
    this.smooth = false,
  });

  @override
  ElementKind get kind => ElementKind.chart;

  /// aroundTheChart is this element with its box back round the chart itself
  /// (see [ChartBody]), for when floating labels are switched off.
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

  /// axisText is the type the axis titles are actually set in, and
  /// axisFigures is how the numbers up the side are actually written: their
  /// own where they have been given one, and the values' otherwise.
  TextSpec get axisText => axisSpec ?? labelSpec;
  ChartNumbers get axisFigures => axisNumbers ?? numbers;

  /// logs is whether this chart is actually drawn on a log axis: [logScale]
  /// on a cartesian chart whose numbers a log axis can show (see
  /// [positiveOnly]). The settings say when it is refused.
  bool get logs => logScale && type.isCartesian && positiveOnly;

  /// showAxisLabels is whether there is any writing on the axes at all, tick
  /// values or titles, which is what the gutters round the plot are kept for.
  bool get showAxisLabels =>
      showXLabels || showYLabels || showsXTitle || showsYTitle;

  /// xLabels and yLabels are the type each axis is actually written in: the
  /// chart's own label type, with whatever that axis has been told instead.
  TextSpec get xLabels => _axisLabelSpec(xLabelSize, xLabelColor);
  TextSpec get yLabels => _axisLabelSpec(yLabelSize, yLabelColor);

  TextSpec _axisLabelSpec(double? size, Color? color) {
    var spec = labelSpec;
    if (size != null) spec = spec.copyWith(fontSize: size);
    if (color != null) spec = spec.copyWith(color: color);
    return spec;
  }

  /// showsXTitle and showsYTitle are whether each axis title is actually
  /// drawn: switched on and with something to say, whatever the tick values'
  /// switch says.
  bool get showsXTitle => showXTitle && xAxisLabel.isNotEmpty;
  bool get showsYTitle => showYTitle && yAxisLabel.isNotEmpty;

  /// positiveOnly is whether a log axis can describe this chart's numbers:
  /// nothing below zero, and something above it.
  ///
  /// Zeros are allowed (drawn at the bottom of the axis), since a newly added
  /// row is all zeros and should not switch the log scale off.
  bool get positiveOnly {
    var any = false;
    for (var series in data.series) {
      for (var v in series.values) {
        if (v < 0) return false;
        if (v > 0) any = true;
      }
    }
    // An empty chart has nothing to scale.
    return any;
  }

  /// descriptionText is the type the description is actually set in: its own
  /// when it has been given one, and the label size otherwise.
  TextSpec get descriptionText => descriptionSpec ?? labelSpec;

  @override
  CanvasElement rebase(ElementBase base) => _copy(base);

  ChartElement copyWith({
    ChartType? type,
    ChartData? data,
    TableLink? fromTable,
    DataSource? source,
    ChartSourceMap? fromSource,
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
    bool? showXLabels,
    bool? showYLabels,
    double? xLabelSize,
    Color? xLabelColor,
    double? yLabelSize,
    Color? yLabelColor,
    double? xLabelGap,
    double? yLabelGap,
    bool? showXTitle,
    bool? showYTitle,
    bool? showLegend,
    bool? showValues,
    Color? gridColor,
    Color? axisColor,
    Color? riseColor,
    List<Color>? sliceColors,
    Color? fallColor,
    int? axisSteps,
    bool? logScale,
    ChartNumbers? numbers,
    ChartNumbers? axisNumbers,
    bool axisFollowsValues = false,
    TextSpec? axisSpec,
    double? axisGap,
    TextSpec? titleSpec,
    TextSpec? labelSpec,
    TextSpec? valueSpec,
    double? yMin,
    double? yMax,
    double? barGap,
    double? barRadius,
    double? barFloor,
    double? innerRadius,
    String? centreLabel,
    bool? showPoints,
    double? pointSize,
    Color? pointColor,
    double? strokeWidth,
    bool? smooth,
  }) =>
      _copy(base,
          type: type,
          data: data,
          fromTable: fromTable,
          source: source,
          fromSource: fromSource,
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
          showXLabels: showXLabels,
          showYLabels: showYLabels,
          xLabelSize: xLabelSize,
          xLabelColor: xLabelColor,
          yLabelSize: yLabelSize,
          yLabelColor: yLabelColor,
          xLabelGap: xLabelGap,
          yLabelGap: yLabelGap,
          showXTitle: showXTitle,
          showYTitle: showYTitle,
          showLegend: showLegend,
          showValues: showValues,
          gridColor: gridColor,
          axisColor: axisColor,
          riseColor: riseColor,
          sliceColors: sliceColors,
          fallColor: fallColor,
          axisSteps: axisSteps,
          logScale: logScale,
          numbers: numbers,
          axisNumbers: axisNumbers,
          axisFollowsValues: axisFollowsValues,
          axisSpec: axisSpec,
          axisGap: axisGap,
          titleSpec: titleSpec,
          labelSpec: labelSpec,
          valueSpec: valueSpec,
          yMin: yMin,
          yMax: yMax,
          barGap: barGap,
          barRadius: barRadius,
          barFloor: barFloor,
          innerRadius: innerRadius,
          centreLabel: centreLabel,
          showPoints: showPoints,
          pointSize: pointSize,
          pointColor: pointColor,
          strokeWidth: strokeWidth,
          smooth: smooth);

  /// _copy is copyWith and rebase sharing one body, so no field can be
  /// dropped from one of them.
  ChartElement _copy(
    ElementBase newBase, {
    ChartType? type,
    ChartData? data,
    TableLink? fromTable,
    DataSource? source,
    ChartSourceMap? fromSource,
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
    bool? showXLabels,
    bool? showYLabels,
    double? xLabelSize,
    Color? xLabelColor,
    double? yLabelSize,
    Color? yLabelColor,
    double? xLabelGap,
    double? yLabelGap,
    bool? showXTitle,
    bool? showYTitle,
    bool? showLegend,
    bool? showValues,
    Color? gridColor,
    Color? axisColor,
    Color? riseColor,
    List<Color>? sliceColors,
    Color? fallColor,
    int? axisSteps,
    bool? logScale,
    ChartNumbers? numbers,
    ChartNumbers? axisNumbers,
    bool axisFollowsValues = false,
    TextSpec? axisSpec,
    double? axisGap,
    TextSpec? titleSpec,
    TextSpec? labelSpec,
    TextSpec? valueSpec,
    double? yMin,
    double? yMax,
    double? barGap,
    double? barRadius,
    double? barFloor,
    double? innerRadius,
    String? centreLabel,
    bool? showPoints,
    double? pointSize,
    Color? pointColor,
    double? strokeWidth,
    bool? smooth,
  }) =>
      ChartElement(newBase,
          type: type ?? this.type,
          data: data ?? this.data,
          fromTable: fromTable ?? this.fromTable,
          source: source ?? this.source,
          fromSource: fromSource ?? this.fromSource,
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
          showXLabels: showXLabels ?? this.showXLabels,
          showYLabels: showYLabels ?? this.showYLabels,
          xLabelSize: xLabelSize ?? this.xLabelSize,
          xLabelColor: xLabelColor ?? this.xLabelColor,
          yLabelSize: yLabelSize ?? this.yLabelSize,
          yLabelColor: yLabelColor ?? this.yLabelColor,
          xLabelGap: xLabelGap ?? this.xLabelGap,
          yLabelGap: yLabelGap ?? this.yLabelGap,
          showXTitle: showXTitle ?? this.showXTitle,
          showYTitle: showYTitle ?? this.showYTitle,
          showLegend: showLegend ?? this.showLegend,
          showValues: showValues ?? this.showValues,
          gridColor: gridColor ?? this.gridColor,
          axisColor: axisColor ?? this.axisColor,
          riseColor: riseColor ?? this.riseColor,
          sliceColors: sliceColors ?? this.sliceColors,
          fallColor: fallColor ?? this.fallColor,
          axisSteps: axisSteps ?? this.axisSteps,
          logScale: logScale ?? this.logScale,
          numbers: numbers ?? this.numbers,
          // A flag because null is the value being set ("follow the values").
          axisNumbers:
              axisFollowsValues ? null : (axisNumbers ?? this.axisNumbers),
          axisSpec: axisSpec ?? this.axisSpec,
          axisGap: axisGap ?? this.axisGap,
          titleSpec: titleSpec ?? this.titleSpec,
          labelSpec: labelSpec ?? this.labelSpec,
          valueSpec: valueSpec ?? this.valueSpec,
          yMin: yMin ?? this.yMin,
          yMax: yMax ?? this.yMax,
          barGap: barGap ?? this.barGap,
          barRadius: barRadius ?? this.barRadius,
          barFloor: barFloor ?? this.barFloor,
          innerRadius: innerRadius ?? this.innerRadius,
          centreLabel: centreLabel ?? this.centreLabel,
          showPoints: showPoints ?? this.showPoints,
          pointSize: pointSize ?? this.pointSize,
          pointColor: pointColor ?? this.pointColor,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          smooth: smooth ?? this.smooth);

  @override
  Map<String, dynamic> props() => {
        "type": type.name,
        "data": data.toJson(),
        if (fromTable.on) "fromTable": fromTable.toJson(),
        if (source.on) "source": source.toJson(),
        if (source.on) "fromSource": fromSource.toJson(),
        if (title.isNotEmpty) "title": title,
        if (description.isNotEmpty) "desc": description,
        if (titleBox.toJson().isNotEmpty) "titleBox": titleBox.toJson(),
        if (descriptionBox.toJson().isNotEmpty)
          "descBox": descriptionBox.toJson(),
        if (!body.isWhole) "body": body.toJson(),
        if (animation.any) "anim": animation.toJson(),
        // Kept even with the legend switched off, so it comes back as left.
        if (showLegend || legend.toJson().length > 1)
          "legendSpec": legend.toJson(),
        if (floatingLabels) "floatLabels": true,
        if (descriptionSpec != null) "descSpec": descriptionSpec!.toJson(),
        if (xAxisLabel.isNotEmpty) "xlabel": xAxisLabel,
        if (yAxisLabel.isNotEmpty) "ylabel": yAxisLabel,
        "grid": showGrid,
        "axes": showAxes,
        // The older single key while both axes agree.
        if (!showXLabels && !showYLabels) "noAxisLabels": true,
        if (!showXLabels && showYLabels) "noXLabels": true,
        if (!showYLabels && showXLabels) "noYLabels": true,
        if (xLabelSize != null) "xLabelSize": xLabelSize,
        if (xLabelColor != null) "xLabelColor": colorToJson(xLabelColor!),
        if (yLabelSize != null) "yLabelSize": yLabelSize,
        if (yLabelColor != null) "yLabelColor": colorToJson(yLabelColor!),
        if (xLabelGap != 0) "xLabelGap": xLabelGap,
        if (yLabelGap != 0) "yLabelGap": yLabelGap,
        if (!showXTitle) "noXTitle": true,
        if (!showYTitle) "noYTitle": true,
        "legend": showLegend,
        "values": showValues,
        "gridColor": colorToJson(gridColor),
        "axisColor": colorToJson(axisColor),
        if (axisSteps > 0) "axisSteps": axisSteps,
        if (logScale) "log": true,
        if (numbers.toJson().isNotEmpty) "numbers": numbers.toJson(),
        if (axisNumbers != null) "axisNumbers": axisNumbers!.toJson(),
        if (axisSpec != null) "axisSpec": axisSpec!.toJson(),
        if (axisGap != 0) "axisGap": axisGap,
        "riseColor": colorToJson(riseColor),
        if (sliceColors.isNotEmpty)
          "sliceColors": [for (var c in sliceColors) colorToJson(c)],
        "fallColor": colorToJson(fallColor),
        "titleSpec": titleSpec.toJson(),
        "labelSpec": labelSpec.toJson(),
        "valueSpec": valueSpec.toJson(),
        if (!yMin.isNaN) "ymin": yMin,
        if (!yMax.isNaN) "ymax": yMax,
        "barGap": barGap,
        "barRadius": barRadius,
        if (barFloor > 0) "barFloor": barFloor,
        "inner": innerRadius,
        if (centreLabel.isNotEmpty) "centre": centreLabel,
        "sw": strokeWidth,
        if (showPoints) "points": true,
        if (pointSize > 0) "pointSize": pointSize,
        if (pointColor.a > 0) "pointColor": colorToJson(pointColor),
        if (smooth) "smooth": true,
      };

  factory ChartElement.fromJson(Map<String, dynamic> json, ElementBase b) => ChartElement(
      b,
      type: ChartType.fromName(jsonStr(json["type"])),
      data: jsonSpec(json["data"], ChartData.fromJson, const ChartData()),
      fromTable:
          jsonSpec(json["fromTable"], TableLink.fromJson, const TableLink()),
      source: jsonSpec(json["source"], DataSource.fromJson, const DataSource()),
      fromSource: jsonSpec(
          json["fromSource"], ChartSourceMap.fromJson, const ChartSourceMap()),
      title: jsonString(json["title"], ""),
      description: jsonString(json["desc"], ""),
      titleBox:
          jsonSpec(json["titleBox"], ChartLabel.fromJson, const ChartLabel()),
      descriptionBox: jsonSpec(
          json["descBox"], ChartLabel.fromJson, const ChartLabel(height: 0.1)),
      body: jsonSpec(json["body"], ChartBody.fromJson, const ChartBody()),
      animation: jsonSpec(
          json["anim"], ChartAnimation.fromJson, const ChartAnimation()),
      legend: jsonSpec(
          json["legendSpec"], ChartLegend.fromJson, const ChartLegend()),
      floatingLabels: jsonBool(json["floatLabels"], false),
      descriptionSpec: json["descSpec"] is Map<String, dynamic>
          ? TextSpec.fromJson(json["descSpec"] as Map<String, dynamic>)
          : null,
      xAxisLabel: jsonString(json["xlabel"], ""),
      yAxisLabel: jsonString(json["ylabel"], ""),
      showGrid: jsonBool(json["grid"], true),
      showAxes: jsonBool(json["axes"], true),
      showXLabels: !jsonBool(json["noAxisLabels"], false) &&
          !jsonBool(json["noXLabels"], false),
      showYLabels: !jsonBool(json["noAxisLabels"], false) &&
          !jsonBool(json["noYLabels"], false),
      xLabelSize: json["xLabelSize"] is num
          ? (json["xLabelSize"] as num).toDouble()
          : null,
      xLabelColor: json["xLabelColor"] == null
          ? null
          : colorFromJson(json["xLabelColor"]),
      yLabelSize: json["yLabelSize"] is num
          ? (json["yLabelSize"] as num).toDouble()
          : null,
      yLabelColor: json["yLabelColor"] == null
          ? null
          : colorFromJson(json["yLabelColor"]),
      xLabelGap:
          json["xLabelGap"] is num ? (json["xLabelGap"] as num).toDouble() : 0,
      yLabelGap:
          json["yLabelGap"] is num ? (json["yLabelGap"] as num).toDouble() : 0,
      showXTitle: !jsonBool(json["noXTitle"], false),
      showYTitle: !jsonBool(json["noYTitle"], false),
      showLegend: jsonBool(json["legend"], false),
      showValues: jsonBool(json["values"], false),
      gridColor: colorFromJson(json["gridColor"], const Color(0x33FFFFFF)),
      axisSteps: jsonInt(json["axisSteps"], 0).clamp(0, 40),
      logScale: jsonBool(json["log"], false),
      numbers: jsonSpec(
          json["numbers"], ChartNumbers.fromJson, const ChartNumbers()),
      // Null when nothing is saved: the axis follows the values.
      axisNumbers: json["axisNumbers"] is Map<String, dynamic>
          ? ChartNumbers.fromJson(json["axisNumbers"] as Map<String, dynamic>)
          : null,
      axisSpec: json["axisSpec"] is Map<String, dynamic>
          ? TextSpec.fromJson(json["axisSpec"] as Map<String, dynamic>)
          : null,
      axisGap: jsonDouble(json["axisGap"], 0),
      riseColor: colorFromJson(json["riseColor"], const Color(0xFF2FD3A0)),
      sliceColors: json["sliceColors"] is List
          ? [
              for (var c in json["sliceColors"] as List)
                if (c is num) colorFromJson(c),
            ]
          : const [],
      fallColor: colorFromJson(json["fallColor"], const Color(0xFFE85D75)),
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
      barFloor: jsonDouble(json["barFloor"], 0),
      innerRadius: jsonDouble(json["inner"], 0.55),
      centreLabel: json["centre"] is String ? json["centre"] as String : "",
      strokeWidth: jsonDouble(json["sw"], 3),
      showPoints: jsonBool(json["points"], false),
      pointSize: jsonDouble(json["pointSize"], 0).clamp(0, 200),
      pointColor: colorFromJson(json["pointColor"], const Color(0x00000000)),
      smooth: jsonBool(json["smooth"], false));
}

/// ChartSourceMap is which of a fetched source's columns the chart draws: the
/// [TableLink] choice, made about a DataSource's columns.
class ChartSourceMap {
  /// categoryColumn is the column the labels along the axis come from -- the
  /// date, usually.
  final int categoryColumn;

  /// valueColumns are the columns that become series, in order.
  final List<int> valueColumns;

  /// maxPoints is how many to keep, or zero for all of them. The points kept
  /// are real ones, evenly spaced, with the most recent always among them.
  /// See [thinTo].
  final int maxPoints;

  /// interval takes a reading on the dates asked for rather than one point in
  /// every so many (see [ChartInterval]). When on, it replaces [maxPoints]
  /// rather than adding to it.
  final ChartInterval interval;

  const ChartSourceMap({
    this.categoryColumn = 0,
    this.valueColumns = const [1],
    this.maxPoints = 0,
    this.interval = const ChartInterval(),
  });

  ChartSourceMap copyWith({
    int? categoryColumn,
    List<int>? valueColumns,
    int? maxPoints,
    ChartInterval? interval,
  }) =>
      ChartSourceMap(
        categoryColumn: categoryColumn ?? this.categoryColumn,
        valueColumns: valueColumns ?? this.valueColumns,
        maxPoints: maxPoints ?? this.maxPoints,
        interval: interval ?? this.interval,
      );

  /// afterMove and afterRemoval keep the drawing pointed at the same columns
  /// when the columns themselves are rearranged; the map holds indices, so
  /// they must be carried across.
  ChartSourceMap afterMove(int from, int to) => copyWith(
        categoryColumn: movedIndex(categoryColumn, from, to),
        valueColumns: [
          for (var c in valueColumns) movedIndex(c, from, to),
        ]..sort(),
      );

  ChartSourceMap afterRemoval(int at) => copyWith(
        categoryColumn: indexAfterRemoval(categoryColumn, at) ?? 0,
        valueColumns: [
          for (var c in valueColumns)
            if (indexAfterRemoval(c, at) case var moved?) moved,
        ],
      );

  Map<String, dynamic> toJson() => {
        "cat": categoryColumn,
        "vals": valueColumns,
        if (maxPoints > 0) "max": maxPoints,
        if (interval.on) "interval": interval.toJson(),
      };

  factory ChartSourceMap.fromJson(Map<String, dynamic> json) => ChartSourceMap(
        categoryColumn: jsonInt(json["cat"], 0),
        valueColumns: [
          if (json["vals"] case List raw)
            for (var v in raw)
              if (v is num) v.toInt(),
        ],
        maxPoints: jsonInt(json["max"], 0),
        interval: jsonSpec(
            json["interval"], ChartInterval.fromJson, const ChartInterval()),
      );
}

/// chartDataFromRows turns mapped rows into a chart's numbers, for both a
/// table on the canvas and a source of the chart's own. A cell that is not a
/// number counts as zero, so a wrongly picked column gives an obviously
/// wrong chart rather than an error.
///
/// [when] is the date of each body row, for [ChartSourceMap.interval]; without
/// dates the chart falls back to thinning.
ChartData chartDataFromRows(
  List<List<String>> rows,
  ChartSourceMap map, {
  bool headerRow = true,
  String Function(int column)? nameOf,
  List<DateTime?>? when,

  /// keeping is the series as they stand, so how each one looks survives a
  /// refresh. Carried by position (the i-th of [ChartSourceMap.valueColumns]);
  /// the name is not carried, since it comes from the column.
  List<ChartSeries> keeping = const [],
}) {
  if (map.valueColumns.isEmpty || rows.isEmpty) return const ChartData();
  var body = headerRow ? rows.skip(1).toList() : rows;

  // Each point is a label and the rows that make it: one row for most charts,
  // a whole period where a reading combines them.
  var points = <(String, List<List<String>>)>[];
  String labelOf(List<String> row) =>
      map.categoryColumn < row.length ? row[map.categoryColumn] : "";

  var dated = map.interval.on && when != null && when.length >= body.length;
  if (dated && map.interval.how.combines) {
    for (var group
        in groupAtIntervals(when.sublist(0, body.length), map.interval)) {
      // Labelled by the period's first row rather than the mark, so the date
      // is in the column's own format.
      points.add((
        labelOf(body[group.rows.first]),
        [
          for (var i in group.rows) body[i],
        ]
      ));
    }
  } else if (dated) {
    for (var i in pickAtIntervals(when.sublist(0, body.length), map.interval)) {
      points.add((labelOf(body[i]), [body[i]]));
    }
  }
  if (points.isEmpty) {
    for (var row in thinTo(body, map.maxPoints)) {
      points.add((labelOf(row), [row]));
    }
  }

  String header(int column) =>
      nameOf?.call(column) ??
      (headerRow && column < rows.first.length ? rows.first[column] : "");

  double valueIn(List<List<String>> made, int column) => map.interval.how.of([
        for (var row in made)
          if (column < row.length) cellNumber(row[column]) ?? 0 else 0,
      ]);

  return ChartData(
    categories: [for (var (label, _) in points) label],
    series: [
      for (var (i, column) in map.valueColumns.indexed)
        if (i < keeping.length)
          keeping[i].copyWith(
              name: header(column),
              values: [for (var (_, made) in points) valueIn(made, column)])
        else
          ChartSeries(
            name: header(column),
            color: chartPalette[i % chartPalette.length],
            values: [for (var (_, made) in points) valueIn(made, column)],
          ),
    ],
  );
}

/// datesIn reads the date of each body row out of the unformatted,
/// header-first rows [raw], or null when there are none.
List<DateTime?>? datesIn(List<List<String>> raw, int column) {
  if (raw.length < 2 || column < 0) return null;
  var out = <DateTime?>[];
  var any = false;
  for (var row in raw.skip(1)) {
    var at = column < row.length ? asDate(row[column]) : null;
    if (at != null) any = true;
    out.add(at);
  }
  return any ? out : null;
}

/// thinTo keeps at most [most] rows, evenly spread from the first to the
/// last. Always ending on the last matters: otherwise a price chart can be
/// quietly weeks out of date.
List<List<String>> thinTo(List<List<String>> rows, int most) {
  if (most <= 0 || rows.length <= most) return rows;
  if (most == 1) return [rows.last];
  var step = (rows.length - 1) / (most - 1);
  return [
    for (var i = 0; i < most; i++) rows[(i * step).round()],
  ];
}

/// chartDataFromTable is [link] applied to [table]: the chart's numbers taken
/// from the table's cells, with the series named after their columns.
ChartData chartDataFromTable(TableElement table, TableLink link,
    {List<ChartSeries> keeping = const []}) {
  if (!link.on) return const ChartData();
  return chartDataFromRows(
    table.rows,
    ChartSourceMap(
        categoryColumn: link.categoryColumn, valueColumns: link.valueColumns),
    headerRow: table.headerRow,
    // The table's name for the column, which a hidden header row still has.
    nameOf: table.columnName,
    keeping: keeping,
  );
}

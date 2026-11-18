import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_highlight.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';

// The chart's data, animation and key live in their own files, exported so
// that importing chart_element.dart still brings a whole chart.
export 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_design.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_highlight.dart';
export 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';

import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_legend.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'dart:convert' show jsonEncode;

// chart_element.dart is a chart as data and settings, painted from scratch
// by render/chart_painter.dart on a ui.Canvas like every element, so it
// exports at any size, animates and turns the same way.

final String _plainBox = jsonEncode(const BoxSpec(padding: 0).toJson());

/// chartBoxIsPlain is whether [box] draws nothing and keeps no room: a chart
/// as made, with no card behind it.
bool chartBoxIsPlain(BoxSpec box) => jsonEncode(box.toJson()) == _plainBox;

/// ChartLabel is a title or description: shown or not, and where with
/// [ChartElement.floatingLabels] (kept when that is off).
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

  /// hasPlace is whether it has its own coordinates; if not, a floating
  /// label goes where the chart puts it (see defaultTitlePlacement).
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

/// ChartBody is where the chart itself is drawn within the element's box,
/// as fractions of it: the whole box, until a floating label is dragged
/// outside. The box then grows to hold the label (so a marquee picks it up)
/// and the body is inset so the plot stays put. Handle resizes scale it.
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

/// defaultTitlePlacement and defaultDescriptionPlacement are where labels
/// first float: across the top, the description under the title.
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

class ChartElement extends CanvasElement {
  final ChartType type;
  final ChartData data;

  /// fromTable is the canvas table the numbers came from, if any, so a
  /// table refresh brings the chart along; [data] is still its own copy.
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
  /// moved, where. See [ChartLabel].
  final ChartLabel titleBox;
  final ChartLabel descriptionBox;

  final ChartBody body;

  final ChartAnimation animation;

  /// legend is all about the key but whether it shows ([showLegend]).
  final ChartLegend legend;

  /// floatingLabels puts the title, description and key *over* the chart
  /// instead of taking room from it, and lets them be dragged anywhere.
  final bool floatingLabels;

  /// descriptionSpec is the description's type, or null for [labelSpec].
  final TextSpec? descriptionSpec;

  final String xAxisLabel;
  final String yAxisLabel;

  /// showGrid is the ruled grid behind the plot.
  final bool showGrid;
  final bool showAxes;

  /// showXLabels and showYLabels are the tick values or category names along
  /// each axis: by axis, not content, since horizontal bars swap which axis
  /// carries which. The axis titles are [showXTitle] and [showYTitle].
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
  /// [yAxisLabel], without emptying them.
  final bool showXTitle;
  final bool showYTitle;

  final bool showLegend;

  final bool showValues;

  final Color gridColor;
  final Color axisColor;

  /// riseColor and fallColor are a candlestick's up and down colours, in
  /// place of the series', since all four series are one mark.
  final Color riseColor;
  final Color fallColor;

  /// sliceColors are a pie's, donut's or radial bar's colours by category;
  /// past its end, the series' or the palette's. See sliceColour.
  final List<Color> sliceColors;

  /// box is the card the chart is drawn on: its fill, border and corners
  /// round everything, title and key included, and its padding the room
  /// kept inside it (see chartInner). Clear and unpadded as made.
  final BoxSpec box;

  /// titleSpec, labelSpec and valueSpec are its three type sizes, apart so
  /// a chart shrunk into a corner keeps a readable title.
  final TextSpec titleSpec;
  final TextSpec labelSpec;
  final TextSpec valueSpec;

  /// numbers is how a value is written: on the bars, on the points, and in a
  /// legend that carries values. See [ChartNumbers].
  final ChartNumbers numbers;

  /// axisNumbers is how the axis figures are written, or null for [numbers]:
  /// a value can be exact (2.049M) while the axis stays round (2.0M).
  final ChartNumbers? axisNumbers;

  /// axisSteps is about how many divisions the value axis has (kept round),
  /// or zero to let the chart decide. On a log axis it counts decades.
  final int axisSteps;

  /// logScale asks for a value axis by decades, where it can; see [logs].
  final bool logScale;

  /// axisSpec is the axis titles' type, or null for [labelSpec].
  final TextSpec? axisSpec;

  /// axisGap is extra room between an axis title and the plot, in document
  /// units, on top of the usual one and a half title heights.
  final double axisGap;

  /// yMin and yMax pin the value axis, or NaN to work it out from the data.
  final double yMin;
  final double yMax;

  /// barGap is the space between bars as a fraction of the slot width.
  final double barGap;
  final double barRadius;

  /// barFloor is a bar's least height in pixels, so a measured nought makes
  /// a mark unlike a gap (see ChartData.hasValueAt).
  final double barFloor;

  /// innerRadius is the hole in a donut, as a fraction of the outer radius.
  final double innerRadius;

  /// centreLabel is the words in a donut's hole, or empty for none.
  /// "{total}" in them is the slices added up, counting up as they arrive.
  final String centreLabel;

  /// pictoShape is what a pictogram's icons are, and pictoCount how many,
  /// each a share of the whole (ten: a tenth each).
  final PictoShape pictoShape;
  final int pictoCount;

  /// showPoints marks each reading on a line or an area. A scatter, and a
  /// chart writing its values, has dots regardless.
  final bool showPoints;

  /// pointSize is the dots' radius, or 0 to take it from the line weight.
  final double pointSize;

  /// pointColor is the dots' colour, or transparent for the series'.
  final Color pointColor;

  /// strokeWidth is the line weight for the line, area and radar types.
  final double strokeWidth;

  /// smooth curves a line through its points instead of straight segments.
  final bool smooth;

  /// sheet is the canvas sheet range this chart draws (data_sheet.dart) and
  /// its label and series columns, kept in step both ways (data_sync.dart).
  /// Null only until it is given a sheet.
  final SheetLink? sheet;

  /// highlights are marks picked out in colours of their own (see
  /// chart_highlight.dart), worked into the data's marks by data_sync.dart.
  final List<ChartHighlight> highlights;

  /// notes are lines, bands and words drawn on it (chart_highlight.dart).
  final List<ChartNote> notes;

  /// play is the seconds the chart spends on each date or step once it has
  /// arrived; 0, still.
  final double play;

  /// steps tell the chart in parts (ChartStep); [stepAt] is the one being
  /// worked on, whose title, highlights, notes and date are the chart's.
  final List<ChartStep> steps;
  final int stepAt;

  /// follow is what moves it between steps: its own pace, the timeline's
  /// marks, or the scenes (chart_play.dart). Kept by name, for older builds.
  final String follow;

  /// panel fills the chart's box behind everything (a style's ground, so a
  /// dark chart reads on a light page); clear for none.
  final Color panel;

  /// style is the name of the style last given (data_styles.dart), shown as
  /// picked in its settings. Empty, none.
  final String style;

  /// design is how its marks are drawn beyond its type (chart_design.dart).
  final ChartDesign design;

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
    this.box = const BoxSpec(padding: 0),
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
    this.pictoShape = PictoShape.person,
    this.pictoCount = 10,
    this.showPoints = false,
    this.pointSize = 0,
    this.pointColor = const Color(0x00000000),
    this.strokeWidth = 3,
    this.smooth = false,
    this.sheet,
    this.highlights = const [],
    this.notes = const [],
    this.play = 0,
    this.steps = const [],
    this.stepAt = 0,
    this.follow = "time",
    this.panel = const Color(0x00000000),
    this.style = "",
    this.design = const ChartDesign(),
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

  /// axisText is the type the axis titles are set in, and axisFigures how
  /// the axis numbers are written: their own where given, else the values'.
  TextSpec get axisText => axisSpec ?? labelSpec;
  ChartNumbers get axisFigures => axisNumbers ?? numbers;

  /// logs is whether it is drawn on a log axis: [logScale] on a cartesian
  /// chart that can show one (see [positiveOnly]).
  bool get logs => logScale && type.isCartesian && positiveOnly;

  /// showAxisLabels is whether there is any writing on the axes, tick values
  /// or titles, which the gutters round the plot are kept for.
  bool get showAxisLabels =>
      showXLabels || showYLabels || showsXTitle || showsYTitle;

  /// xLabels and yLabels are the type each axis is written in: the chart's
  /// label type, with whatever that axis was told instead.
  TextSpec get xLabels => _axisLabelSpec(xLabelSize, xLabelColor);
  TextSpec get yLabels => _axisLabelSpec(yLabelSize, yLabelColor);

  TextSpec _axisLabelSpec(double? size, Color? color) {
    var spec = labelSpec;
    if (size != null) spec = spec.copyWith(fontSize: size);
    if (color != null) spec = spec.copyWith(color: color);
    return spec;
  }

  /// showsXTitle and showsYTitle are whether each axis title is drawn:
  /// switched on and with something to say.
  bool get showsXTitle => showXTitle && xAxisLabel.isNotEmpty;
  bool get showsYTitle => showYTitle && yAxisLabel.isNotEmpty;

  /// positiveOnly is whether a log axis can show its numbers: none below
  /// zero, one above. Zeros are allowed, at the axis bottom, since a new row
  /// is all zeros and must not switch the log scale off.
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

  /// descriptionText is the description's type: its own, else the label's.
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
    BoxSpec? box,
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
    PictoShape? pictoShape,
    int? pictoCount,
    bool? showPoints,
    double? pointSize,
    Color? pointColor,
    double? strokeWidth,
    bool? smooth,
    SheetLink? sheet,
    bool clearSheet = false,
    List<ChartHighlight>? highlights,
    List<ChartNote>? notes,
    double? play,
    List<ChartStep>? steps,
    int? stepAt,
    String? follow,
    Color? panel,
    String? style,
    ChartDesign? design,
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
          box: box,
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
          pictoShape: pictoShape,
          pictoCount: pictoCount,
          showPoints: showPoints,
          pointSize: pointSize,
          pointColor: pointColor,
          strokeWidth: strokeWidth,
          smooth: smooth,
          sheet: sheet,
          clearSheet: clearSheet,
          highlights: highlights,
          notes: notes,
          play: play,
          steps: steps,
          stepAt: stepAt,
          follow: follow,
          panel: panel,
          style: style,
          design: design);

  /// _copy is copyWith's and rebase's one body, so neither drops a field.
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
    BoxSpec? box,
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
    PictoShape? pictoShape,
    int? pictoCount,
    bool? showPoints,
    double? pointSize,
    Color? pointColor,
    double? strokeWidth,
    bool? smooth,
    SheetLink? sheet,
    bool clearSheet = false,
    List<ChartHighlight>? highlights,
    List<ChartNote>? notes,
    double? play,
    List<ChartStep>? steps,
    int? stepAt,
    String? follow,
    Color? panel,
    String? style,
    ChartDesign? design,
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
          box: box ?? this.box,
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
          pictoShape: pictoShape ?? this.pictoShape,
          pictoCount: (pictoCount ?? this.pictoCount).clamp(1, 200),
          showPoints: showPoints ?? this.showPoints,
          pointSize: pointSize ?? this.pointSize,
          pointColor: pointColor ?? this.pointColor,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          smooth: smooth ?? this.smooth,
          sheet: clearSheet ? null : sheet ?? this.sheet,
          highlights: highlights ?? this.highlights,
          notes: notes ?? this.notes,
          play: play ?? this.play,
          steps: steps ?? this.steps,
          stepAt: stepAt ?? this.stepAt,
          follow: follow ?? this.follow,
          panel: panel ?? this.panel,
          style: style ?? this.style,
          design: design ?? this.design);

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
        if (!chartBoxIsPlain(box)) "box": box.toJson(),
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
        if (pictoShape != PictoShape.person) "picto": pictoShape.name,
        if (pictoCount != 10) "pictoN": pictoCount,
        "sw": strokeWidth,
        if (showPoints) "points": true,
        if (pointSize > 0) "pointSize": pointSize,
        if (pointColor.a > 0) "pointColor": colorToJson(pointColor),
        if (smooth) "smooth": true,
        if (sheet != null) "sheet": sheet!.toJson(),
        if (highlights.isNotEmpty)
          "highlights": [for (var h in highlights) h.toJson()],
        if (notes.isNotEmpty) "notes": [for (var n in notes) n.toJson()],
        if (play > 0) "play": play,
        if (steps.isNotEmpty) "steps": [for (var st in steps) st.toJson()],
        if (steps.isNotEmpty) "stepAt": stepAt,
        if (follow != "time") "follow": follow,
        if (panel.a > 0) "panel": colorToJson(panel),
        if (style.isNotEmpty) "style": style,
        if (design.any) "design": design.toJson(),
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
      title: jsonLabel(json["title"], ""),
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
      xAxisLabel: jsonLabel(json["xlabel"], ""),
      yAxisLabel: jsonLabel(json["ylabel"], ""),
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
      box: jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec(padding: 0)),
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
      centreLabel: jsonString(json["centre"], ""),
      pictoShape: PictoShape.fromName(json["picto"]),
      pictoCount: json["pictoN"] is num
          ? (json["pictoN"] as num).toInt().clamp(1, 200)
          : 10,
      strokeWidth: jsonDouble(json["sw"], 3),
      showPoints: jsonBool(json["points"], false),
      pointSize: jsonDouble(json["pointSize"], 0).clamp(0, 200),
      pointColor: colorFromJson(json["pointColor"], const Color(0x00000000)),
      smooth: jsonBool(json["smooth"], false),
      sheet: SheetLink.fromJson(json["sheet"]),
      highlights: [
        if (json["highlights"] case List hs)
          for (var h in hs)
            if (ChartHighlight.fromJson(h) case var hl?) hl,
      ],
      notes: [
        if (json["notes"] case List ns)
          for (var n in ns)
            if (ChartNote.fromJson(n) case var note?) note,
      ],
      play: jsonDouble(json["play"], 0).clamp(0, 600).toDouble(),
      steps: [
        if (json["steps"] case List ss)
          for (var st in ss)
            if (ChartStep.fromJson(st) case var step?) step,
      ],
      stepAt: jsonInt(json["stepAt"], 0),
      follow: jsonString(json["follow"], "time"),
      panel: colorFromJson(json["panel"], const Color(0x00000000)),
      style: jsonString(json["style"], ""),
      design: ChartDesign.fromJson(json["design"]));
}

/// ChartSourceMap is which of a fetched source's columns the chart draws:
/// the [TableLink] choice, for a DataSource.
class ChartSourceMap {
  /// categoryColumn is the axis labels' column, usually the date.
  final int categoryColumn;

  /// valueColumns are the columns that become series, in order.
  final List<int> valueColumns;

  /// maxPoints is how many to keep, or zero for all: real points, evenly
  /// spaced, the most recent always among them. See [thinTo].
  final int maxPoints;

  /// interval takes a reading on the dates asked for rather than one point in
  /// every so many (see [ChartInterval]); when on, it replaces [maxPoints].
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

  /// afterMove and afterRemoval keep the drawing on the same columns when the
  /// columns are rearranged: the map holds indices.
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

/// chartDataFromRows turns mapped rows into a chart's numbers. A non-number
/// counts as zero, so a wrong column gives an obviously wrong chart. [when]
/// is each row's date, for [ChartSourceMap.interval]; else it thins.
ChartData chartDataFromRows(
  List<List<String>> rows,
  ChartSourceMap map, {
  bool headerRow = true,
  String Function(int column)? nameOf,
  List<DateTime?>? when,

  /// keeping is the series as they stand, so how each looks survives a
  /// refresh. Carried by position; the name comes from the column.
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

/// thinTo keeps at most [most] rows spread evenly, always ending on the
/// last, or a price chart can be quietly weeks out of date.
List<List<String>> thinTo(List<List<String>> rows, int most) {
  if (most <= 0 || rows.length <= most) return rows;
  if (most == 1) return [rows.last];
  var step = (rows.length - 1) / (most - 1);
  return [
    for (var i = 0; i < most; i++) rows[(i * step).round()],
  ];
}

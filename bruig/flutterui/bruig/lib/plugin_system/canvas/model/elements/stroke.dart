import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// stroke.dart is the one stroked outline a line and a path are both drawn
// as: its colour or fade, width, cap, what is drawn on each end and how big,
// and its dash (StrokeSpec); the element that holds one (StrokedElement);
// and the sizes of what is drawn on the ends (EndShape). The painter is
// paintStroke, in the renderer.

/// LineStrokeCap is how the stroke itself finishes; what is drawn at the
/// end is [LineEnd], apart, since a line can want a round end and an arrow.
enum LineStrokeCap {
  flat("Flat", StrokeCap.butt),
  round("Round", StrokeCap.round),
  square("Square", StrokeCap.square);

  final String label;
  final StrokeCap flutter;
  const LineStrokeCap(this.label, this.flutter);

  static LineStrokeCap fromName(String? name) => values.firstWhere(
        (c) => c.name == name,
        orElse: () => LineStrokeCap.flat,
      );
}

/// maxEndSize is the largest end size a stroke is read with: ten times what
/// the panels offer, so nothing made here is changed, while a received
/// canvas cannot draw an arrowhead a billion times the page.
const double maxEndSize = 80;

/// maxDash is the longest dash a stroke is read with: what a line's panel
/// offers.
const double maxDash = 400;

/// LineEnd is what is drawn at one end of a stroke, set for each end.
enum LineEnd {
  none("None"),
  arrow("Arrow"),
  openArrow("Open arrow"),
  hollowArrow("Hollow arrow"),
  diamond("Diamond"),
  hollowDiamond("Hollow diamond"),
  circle("Circle"),
  hollowCircle("Hollow circle"),
  square("Square"),
  bar("Bar");

  final String label;
  const LineEnd(this.label);

  static LineEnd fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => LineEnd.none);

  /// reach is how far this decoration extends from the stroke's end, as a
  /// multiple of the stroke width, for the selection box to allow for.
  double get reach => switch (this) {
        LineEnd.none => 0,
        LineEnd.bar => EndShape.barReach,
        LineEnd.circle || LineEnd.hollowCircle => 1.4,
        LineEnd.square => 1.6,
        LineEnd.diamond || LineEnd.hollowDiamond => 2.4,
        LineEnd.arrow ||
        LineEnd.openArrow ||
        LineEnd.hollowArrow =>
          EndShape.arrowBarb,
      };

  /// cover is how far back from the stroke's end this decoration's ink
  /// reaches along the stroke's middle, in end widths: where the stroke's
  /// own ink stops (StrokeSpec.cutBack), so there is no gap before the end
  /// and nothing of the stroke inside a hollow one. A hollow end's is its
  /// back edge, a solid end's a little inside it so there is no seam. A bar
  /// crosses the stroke, which reaches it.
  double get cover => switch (this) {
        LineEnd.none || LineEnd.bar => 0,
        LineEnd.arrow => EndShape.arrowBase * EndShape.seam,
        LineEnd.openArrow =>
          EndShape.openArrowBarb * EndShape.openArrowNotch * EndShape.seam,
        LineEnd.hollowArrow => EndShape.arrowBase,
        LineEnd.diamond => EndShape.diamondSeat,
        LineEnd.hollowDiamond => EndShape.diamondLength,
        LineEnd.circle || LineEnd.hollowCircle => EndShape.circleRadius,
        LineEnd.square => EndShape.squareSide / 2,
      };
}

/// EndShape is the size of each mark drawn on a stroke's end, in end widths
/// (the stroke's width times its end size): the one place both the drawing
/// (paintStroke) and the cut-back under each mark (LineEnd.cover) read
/// them, since the stroke must stop where the mark begins.
abstract final class EndShape {
  /// arrowSpread is the half-angle between an arrow's axis and each barb,
  /// in radians.
  static const double arrowSpread = 0.42;

  /// arrowBarb is how long an arrow's or a hollow arrow's barbs are, from
  /// the tip.
  static const double arrowBarb = 3.5;

  /// arrowBase is how far behind its tip an arrow's barbs end, where its
  /// base crosses the stroke.
  static double get arrowBase => arrowBarb * math.cos(arrowSpread);

  /// openArrowBarb is how long an open arrow's barbs are, and
  /// openArrowNotch how far behind its tip the notch between them is, as a
  /// fraction of a barb, so it keeps its proportions at any size.
  static const double openArrowBarb = 4.2, openArrowNotch = 0.58;

  /// seam is how much of the way to a solid end's back edge the stroke is
  /// cut, so the two overlap by a hair and no line of the page shows
  /// between them.
  static const double seam = 0.92;

  /// diamondLength and diamondWidth are half a diamond's length along the
  /// stroke and half its width across, centred on the end.
  static const double diamondLength = 1.7, diamondWidth = 1.0;

  /// diamondSeat is how far behind its middle a solid diamond's stroke
  /// stops: well short of its back point, where it is too narrow to cover
  /// a thick stroke.
  static const double diamondSeat = 1.2;

  /// circleRadius is a circle's, centred on the end.
  static const double circleRadius = 1.2;

  /// squareSide is a square's side, centred on the end.
  static const double squareSide = 2.2;

  /// barReach is how far a bar reaches either side of the stroke.
  static const double barReach = 1.6;
}

/// StrokeSpec is how a stroke is drawn, a line's and a path's alike. It has
/// no defaults of its own: a line and a path each start from theirs.
class StrokeSpec {
  /// color is the stroke's colour, or where its [fade] starts.
  final Color color;

  /// fade is the second colour the stroke runs to, or null for a flat one,
  /// chosen in the picker beside [color] (see GradientSpec).
  final GradientSpec? fade;

  final double strokeWidth;

  /// cap is how the stroke finishes; startEnd and endEnd are what is drawn
  /// on its two ends.
  final LineStrokeCap cap;
  final LineEnd startEnd;
  final LineEnd endEnd;

  /// endSize scales what is drawn at both ends, as a multiple of the stroke
  /// width, so an arrow stays in proportion when the stroke thickens.
  final double endSize;

  /// dash is the on/off length in design units. Zero draws a solid stroke.
  final double dash;

  const StrokeSpec({
    required this.color,
    this.fade,
    required this.strokeWidth,
    required this.cap,
    required this.startEnd,
    required this.endEnd,
    required this.endSize,
    required this.dash,
  });

  /// copyWith is this stroke with the parts given changed; [flat] takes its
  /// fade away.
  StrokeSpec copyWith({
    Color? color,
    GradientSpec? fade,
    bool flat = false,
    double? strokeWidth,
    LineStrokeCap? cap,
    LineEnd? startEnd,
    LineEnd? endEnd,
    double? endSize,
    double? dash,
  }) =>
      StrokeSpec(
          color: color ?? this.color,
          fade: flat ? null : (fade ?? this.fade),
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          startEnd: startEnd ?? this.startEnd,
          endEnd: endEnd ?? this.endEnd,
          endSize: endSize ?? this.endSize,
          dash: dash ?? this.dash);

  /// cutBack is how far back from its end the stroke is drawn short under
  /// [end], in design units: to where the end's own ink reaches
  /// (LineEnd.cover), and further by what a round or square cap reaches
  /// past the cut, so the cap's ink stops there too. Under no end, or a bar,
  /// it is not cut.
  double cutBack(LineEnd end) {
    if (end == LineEnd.none || end == LineEnd.bar) return 0;
    var cap = this.cap == LineStrokeCap.flat ? 0.0 : strokeWidth / 2;
    return end.cover * strokeWidth * endSize + cap;
  }

  /// endReach is how far past the stroke its ends reach, as a multiple of
  /// its width: the further of the two.
  double get endReach => math.max(startEnd.reach, endEnd.reach) * endSize;

  /// mapColours is this stroke with its colour and fade put through [f]:
  /// itself where nothing changes. See ColourMap.
  StrokeSpec mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p(this.color);
    var fade = p.partOrNone(this.fade, (g) => g.mapColours(f));
    if (!p.changed) return this;
    return copyWith(color: color, fade: fade);
  }

  /// toJson is this stroke as saved, beside an element's other keys. The
  /// colour, width and cap are always written; the rest only where they
  /// differ from [defaults], the element's own, or are set at all.
  Map<String, dynamic> toJson(StrokeSpec defaults) => {
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        "sw": strokeWidth,
        "strokeCap": cap.name,
        if (startEnd != defaults.startEnd) "startEnd": startEnd.name,
        if (endEnd != defaults.endEnd) "endEnd": endEnd.name,
        if (endSize != defaults.endSize) "endSize": endSize,
        if (dash > 0) "dash": dash,
      };

  /// StrokeSpec.fromJson reads a stroke saved by [toJson], taking what is
  /// missing from [defaults]. A cap that is not a name is the default; a
  /// name that is no cap is flat. An end that is written is read as written
  /// (no end, where it is no end's name), so only an end left out is the
  /// default.
  factory StrokeSpec.fromJson(Map<String, dynamic> json, StrokeSpec defaults) =>
      StrokeSpec(
          color: colorFromJson(json["color"], defaults.color),
          fade: json["fade"] is Map
              ? GradientSpec.fromJson(
                  (json["fade"] as Map).cast<String, dynamic>())
              : null,
          strokeWidth: jsonLength(json["sw"], defaults.strokeWidth),
          cap: json[
                  "strokeCap"] is String
              ? LineStrokeCap.fromName(jsonStr(json["strokeCap"]))
              : defaults.cap,
          startEnd: json.containsKey("startEnd")
              ? LineEnd.fromName(jsonStr(json["startEnd"]))
              : defaults.startEnd,
          endEnd: json.containsKey("endEnd")
              ? LineEnd.fromName(jsonStr(json["endEnd"]))
              : defaults.endEnd,
          endSize: jsonDouble(json["endSize"], defaults.endSize)
              .clamp(0.0, maxEndSize),
          dash: jsonDouble(json["dash"], defaults.dash).clamp(0.0, maxDash));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeSpec &&
          other.color == color &&
          other.fade == fade &&
          other.strokeWidth == strokeWidth &&
          other.cap == cap &&
          other.startEnd == startEnd &&
          other.endEnd == endEnd &&
          other.endSize == endSize &&
          other.dash == dash;

  @override
  int get hashCode => Object.hash(
      color, fade, strokeWidth, cap, startEnd, endEnd, endSize, dash);
}

/// StrokedElement is an element drawn as one stroke along its curve: a line
/// or a path. Its stroke is held part by part rather than as a
/// [StrokeSpec], so a line or a path can still be written `const` with the
/// parts named; [stroke] gathers them, and [StrokedElement.of] lays one
/// down. Each part is as on [StrokeSpec].
abstract class StrokedElement extends CanvasElement {
  final Color color;
  final GradientSpec? fade;
  final double strokeWidth;
  final LineStrokeCap cap;
  final LineEnd startEnd;
  final LineEnd endEnd;
  final double endSize;
  final double dash;

  const StrokedElement(
    super.base, {
    required this.color,
    this.fade,
    required this.strokeWidth,
    required this.cap,
    required this.startEnd,
    required this.endEnd,
    required this.endSize,
    required this.dash,
  });

  StrokedElement.of(super.base, StrokeSpec stroke)
      : color = stroke.color,
        fade = stroke.fade,
        strokeWidth = stroke.strokeWidth,
        cap = stroke.cap,
        startEnd = stroke.startEnd,
        endEnd = stroke.endEnd,
        endSize = stroke.endSize,
        dash = stroke.dash;

  /// stroke is this element's stroke as one value.
  StrokeSpec get stroke => StrokeSpec(
      color: color,
      fade: fade,
      strokeWidth: strokeWidth,
      cap: cap,
      startEnd: startEnd,
      endEnd: endEnd,
      endSize: endSize,
      dash: dash);

  /// drawnStroke is [stroke] as it is drawn: without the ends where none
  /// are drawn, so nothing (the selection box) allows room for them.
  StrokeSpec get drawnStroke => stroke;

  /// withStroke is this element drawn with [stroke] instead.
  StrokedElement withStroke(StrokeSpec stroke);

  /// curve is the line the stroke runs along, in the box as it is drawn
  /// before its turn and slant: what paintStroke strokes once paintElement
  /// has laid the canvas out by [boxFrame]. Empty where there is nothing
  /// to stroke (a path of fewer than two points).
  Path get curve;

  /// curvePoints is [curve] walked into points, in the same space, finely
  /// enough to stand for it (CubicSegment.samplesPerPiece to a piece):
  /// what a loop runs round, and, on the page, what is pressed, measured
  /// and ridden. Empty where [curve] is.
  List<Offset> get curvePoints;

  /// bowedBy is this element as [pose] shapes its curve: a line bowed as
  /// the pose keys it (KeyframeChannel.bow). A path has no bow of its own.
  StrokedElement bowedBy(Keyframe pose) => this;

  /// curveOnPage is [curvePoints] where they are drawn on the page as the
  /// element rests: through its turn and slant.
  List<Offset> get curveOnPage => curvePlaced(placedBy(Keyframe.rest));

  /// curvePlaced is [curvePoints] laid on the page by [place], where the
  /// painter lays the element out on a frame: the one answer to where the
  /// curve is, which the selection box, the press, text set on it and
  /// whatever follows it ask (render's strokeOnPage, with the pose a frame
  /// gives it).
  List<Offset> curvePlaced(ElementPlace place) {
    var points = curvePoints;
    if (place.leavesAlone) return points;
    return [for (var p in points) place.place(p)];
  }
}

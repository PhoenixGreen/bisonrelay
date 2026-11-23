import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/cubic_segment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';

/// lineSliver is the depth of a level line's box, or the width of an
/// upright one's: see LineElement.withEnds.
const double lineSliver = 0.01;

/// _maxCurvature is the largest bow a line is read with: ten times what the
/// panel offers, so nothing made here is changed, while a received canvas
/// cannot draw a bow a billion times the page.
const double _maxCurvature = 10;

/// snapLineAngle is [moving] swung about [fixed] onto the nearest multiple of
/// 45 degrees, when it is within [within] degrees of it or [always] is set.
Offset snapLineAngle(Offset fixed, Offset moving,
    {bool always = false, double within = 4}) {
  var d = moving - fixed;
  if (d.distance == 0) return moving;
  var angle = math.atan2(d.dy, d.dx) * 180 / math.pi;
  var nearest = (angle / 45).round() * 45.0;
  if (!always && (angle - nearest).abs() > within) return moving;
  var r = nearest * math.pi / 180;
  // Exactly level or upright, not a cosine's worth of rounding away from it.
  var c = (nearest % 180 == 90) ? 0.0 : math.cos(r);
  var sn = (nearest % 180 == 0) ? 0.0 : math.sin(r);
  return fixed + Offset(c, sn) * d.distance;
}

/// LineElement is a stroke corner to corner of its box, so the usual
/// handles resize, turn and animate it; [flipped] picks the corners. Its
/// stroke is a StrokedElement's: white, 4 wide, flat, with no ends.
class LineElement extends StrokedElement {
  /// curvature bows the line out from the straight path between its ends, as
  /// a fraction of its length. Negative bows the other way.
  final double curvature;

  /// flipped runs the line bottom-left to top-right.
  final bool flipped;

  /// animation is how it arrives on the page and leaves.
  final ElementAnimation animation;

  const LineElement(
    super.base, {
    super.color = const Color(0xFFFFFFFF),
    super.fade,
    super.strokeWidth = 4,
    super.cap = LineStrokeCap.flat,
    super.startEnd = LineEnd.none,
    super.endEnd = LineEnd.none,
    super.endSize = 1,
    super.dash = 0,
    this.curvature = 0,
    this.flipped = false,
    this.animation = const ElementAnimation(),
  });

  LineElement._of(
    super.base,
    super.stroke, {
    required this.curvature,
    required this.flipped,
    required this.animation,
  }) : super.of();

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = LineElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.line;

  /// start and end are the line's two ends at corners of its own box, in
  /// the document's coordinates before its turn and slant: what its [curve]
  /// runs between. On a turned or slanted line they are not where its ends
  /// are drawn; [length] and [angle] are of the line as drawn, and
  /// strokeOnPage (in the renderer) has its ends on any frame.
  Offset get start => flipped ? bounds.bottomLeft : bounds.topLeft;
  Offset get end => flipped ? bounds.topRight : bounds.bottomRight;

  /// _drawnStart and _drawnEnd are where its two ends are drawn on the page
  /// as it rests: [start] and [end] through its turn and slant.
  Offset get _drawnStart => onPage(start);
  Offset get _drawnEnd => onPage(end);

  /// length and angle are the line as it is drawn at rest, from its start
  /// to its end: what a person sees, which a turn or a slant makes other
  /// than its box's. The angle is in degrees clockwise from pointing right.
  double get length => (_drawnEnd - _drawnStart).distance;
  double get angle {
    var d = _drawnEnd - _drawnStart;
    return math.atan2(d.dy, d.dx) * 180 / math.pi;
  }

  /// withLength and withAngle are this line drawn [length] long, or
  /// pointing at [angle] degrees, from where its start is drawn: the rest of
  /// what is drawn kept as it is.
  LineElement withLength(double length) => _drawnFromStart(angle, length);
  LineElement withAngle(double angle) => _drawnFromStart(angle, length);

  LineElement _drawnFromStart(double angle, double length) {
    var r = angle * math.pi / 180;
    return withEndsDrawnAt(
        _drawnStart, _drawnStart + Offset(math.cos(r), math.sin(r)) * length);
  }

  /// withEnds is this line drawn from [a] to [b]. A level line would be a box
  /// with no height, which is not drawn, so it gets [lineSliver]. The box
  /// always runs left to right, so a line drawn right to left has its ends
  /// swapped.
  LineElement withEnds(Offset a, Offset b) {
    var backwards = b.dx < a.dx || (b.dx == a.dx && b.dy < a.dy);
    var from = backwards ? b : a, to = backwards ? a : b;
    var w = math.max((to.dx - from.dx).abs(), lineSliver);
    var h = math.max((to.dy - from.dy).abs(), lineSliver);
    var up = to.dy < from.dy;
    var swapped =
        backwards ? copyWith(startEnd: endEnd, endEnd: startEnd) : this;
    return swapped.copyWith(flipped: up).withBase(
        x: from.dx,
        y: up ? to.dy : from.dy,
        width: w,
        height: h) as LineElement;
  }

  /// withEndsDrawnAt is this line laid so that, posed as [pose] (its own
  /// turn and slant, and what a frame's motion does: ElementPlace), its
  /// start is drawn at [a] and its end at [b] on the page. How far apart the
  /// ends are in the box is the page's taken back through the turn, slant
  /// and size, none of which depends on where the box is; the box is then
  /// moved until the start is drawn at [a]. Every point the place lays out
  /// moves with the box, its middle and its anchor being shares of it, so
  /// the end is drawn at [b].
  LineElement withEndsDrawnAt(Offset a, Offset b,
      [Keyframe pose = Keyframe.rest]) {
    var place = placedBy(pose);
    if (place.leavesAlone) return withEnds(a, b);
    var apart = place.unplace(b) - place.unplace(a);
    var drawnFrom =
        withEnds(Offset.zero, apart).placedBy(pose).place(Offset.zero);
    var by = a - drawnFrom;
    return withEnds(by, apart + by);
  }

  /// level and plumb are this line drawn flat or upright about where its
  /// start is drawn, keeping its length and the side it points to: level on
  /// the page, whatever its turn or slant.
  LineElement get level {
    var a = _drawnStart, d = _drawnEnd - a;
    return withEndsDrawnAt(a, a + Offset(d.dx < 0 ? -length : length, 0));
  }

  LineElement get plumb {
    var a = _drawnStart, d = _drawnEnd - a;
    return withEndsDrawnAt(a, a + Offset(0, d.dy < 0 ? -length : length));
  }

  /// controlPoint is the control point of a bowed line's quadratic, in the
  /// box as it is drawn before its turn and slant. Pushed out square to the
  /// chord, so the bow is the same either way round.
  Offset get controlPoint {
    var a = start, b = end;
    var mid = (a + b) / 2;
    var d = b - a;
    var length = d.distance;
    if (length == 0 || curvature == 0) return mid;
    return mid + Offset(-d.dy / length, d.dx / length) * (length * curvature);
  }

  @override
  LineElement bowedBy(Keyframe pose) {
    var bow = pose.values[KeyframeChannel.bow];
    return bow == null ? this : copyWith(curvature: bow);
  }

  @override
  Path get curve {
    var path = Path()..moveTo(start.dx, start.dy);
    if (curvature == 0) return path..lineTo(end.dx, end.dy);
    var control = controlPoint;
    return path..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
  }

  /// curvePoints is a bowed line's quadratic walked as finely as two pieces
  /// of a path are; a straight line is its two ends.
  @override
  List<Offset> get curvePoints {
    var a = start, b = end;
    if (curvature == 0) return [a, b];
    var control = controlPoint;
    const steps = CubicSegment.samplesPerPiece * 2;
    return [
      for (var i = 0; i <= steps; i++) _quadratic(a, control, b, i / steps)
    ];
  }

  static Offset _quadratic(Offset a, Offset control, Offset b, double t) {
    var u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
    );
  }

  @override
  CanvasElement rebase(ElementBase base) => LineElement._of(base, stroke,
      curvature: curvature, flipped: flipped, animation: animation);

  @override
  LineElement withStroke(StrokeSpec stroke) => LineElement._of(base, stroke,
      curvature: curvature, flipped: flipped, animation: animation);

  LineElement copyWith({
    Color? color,
    GradientSpec? fade,
    bool flat = false,
    double? strokeWidth,
    LineStrokeCap? cap,
    LineEnd? startEnd,
    LineEnd? endEnd,
    double? endSize,
    double? dash,
    double? curvature,
    bool? flipped,
    ElementAnimation? animation,
  }) =>
      LineElement._of(
          base,
          stroke.copyWith(
              color: color,
              fade: fade,
              flat: flat,
              strokeWidth: strokeWidth,
              cap: cap,
              startEnd: startEnd,
              endEnd: endEnd,
              endSize: endSize,
              dash: dash),
          curvature: curvature ?? this.curvature,
          flipped: flipped ?? this.flipped,
          animation: animation ?? this.animation);

  @override
  LineElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var stroke = p.part(this.stroke, (s) => s.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return LineElement._of(base, stroke,
        curvature: curvature, flipped: flipped, animation: animation);
  }

  @override
  Map<String, dynamic> props() => {
        ...stroke.toJson(_defaults.stroke),
        if (curvature != _defaults.curvature) "curve": curvature,
        if (flipped) "flipped": true,
        if (animation.any) "anim": animation.toJson(),
      };

  factory LineElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      LineElement._of(b, StrokeSpec.fromJson(json, _defaults.stroke),
          curvature: jsonDouble(json["curve"], _defaults.curvature)
              .clamp(-_maxCurvature, _maxCurvature),
          flipped: jsonBool(json["flipped"], _defaults.flipped),
          animation: jsonSpec(
              json["anim"], ElementAnimation.fromJson, _defaults.animation));
}

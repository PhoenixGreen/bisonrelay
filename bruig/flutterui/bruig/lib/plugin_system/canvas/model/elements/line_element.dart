import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';

/// legacyCap is an older file's single "cap" (see LineCapStyle) as the
/// stroke's cap and its two ends.
(LineStrokeCap, LineEnd, LineEnd) legacyCap(Object? cap) =>
    switch (LineCapStyle.fromName(jsonStr(cap))) {
      LineCapStyle.round => (LineStrokeCap.round, LineEnd.none, LineEnd.none),
      LineCapStyle.square => (LineStrokeCap.square, LineEnd.none, LineEnd.none),
      LineCapStyle.arrow => (LineStrokeCap.flat, LineEnd.none, LineEnd.arrow),
      LineCapStyle.arrowBoth => (
          LineStrokeCap.flat,
          LineEnd.arrow,
          LineEnd.arrow
        ),
      LineCapStyle.dot => (LineStrokeCap.round, LineEnd.circle, LineEnd.circle),
      _ => (LineStrokeCap.flat, LineEnd.none, LineEnd.none),
    };

/// LineCapStyle is an older file's single "cap": the stroke's cap and its
/// decoration in one. Read only; LineElement.fromJson maps it onto
/// [LineStrokeCap] and [LineEnd].
enum LineCapStyle {
  flat,
  round,
  square,
  arrow,
  arrowBoth,
  dot;

  static LineCapStyle? fromName(String? name) {
    for (var v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// LineStrokeCap is how the stroke itself finishes. What is drawn at the end
/// is [LineEnd], separately, since a line can want a round end and an arrow.
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

/// lineSliver is the depth of a level line's box, or the width of an
/// upright one's -- see LineElement.withEnds.
const double lineSliver = 0.01;

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

/// LineEnd is what is drawn at one end of a line, set for each end.
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

  /// isPointed marks the ends that come to a point on the line's end.
  bool get isPointed =>
      this == arrow || this == openArrow || this == hollowArrow;

  /// reach is how far this decoration extends from the line's end, as a
  /// multiple of the stroke width, for the selection box to allow for.
  double get reach => switch (this) {
        LineEnd.none => 0,
        LineEnd.bar => 1.6,
        LineEnd.circle || LineEnd.hollowCircle => 1.4,
        LineEnd.square => 1.6,
        LineEnd.diamond || LineEnd.hollowDiamond => 2.4,
        _ => 3.5,
      };

  /// cover is how much of the line this decoration sits on top of, as a
  /// multiple of the stroke width, so the stroke is cut back to where the
  /// decoration begins. Otherwise the line shows through a hollow end or
  /// pokes out beside a solid one. A bar crosses the line, which reaches it.
  double get cover => switch (this) {
        LineEnd.none || LineEnd.bar => 0,
        LineEnd.circle || LineEnd.hollowCircle => 1.2,
        LineEnd.square => 1.1,
        LineEnd.diamond || LineEnd.hollowDiamond => 1.2,
        // Back to where the barbs meet, less a hair so there is no seam.
        _ => 3.2 * 0.92,
      };
}

/// LineElement is a stroke from one corner of its box to the other, so it
/// resizes, rotates and animates through the same handles as everything
/// else. [flipped] chooses which pair of corners.
class LineElement extends CanvasElement {
  final Color color;

  /// fade is the second colour the stroke runs to, or null for a flat one.
  /// Chosen in the picker beside [color] -- see GradientSpec.
  final GradientSpec? fade;
  final double strokeWidth;

  /// cap is how the stroke finishes, and startEnd/endEnd are what is drawn at
  /// each end.
  final LineStrokeCap cap;
  final LineEnd startEnd;
  final LineEnd endEnd;

  /// endSize scales whatever is drawn at both ends. A multiple of the stroke
  /// width, so an arrow stays in proportion when the line thickens.
  final double endSize;

  /// dash is the on/off length in design units. Zero draws a solid line.
  final double dash;

  /// curvature bows the line out from the straight path between its ends, as
  /// a fraction of its length. Negative bows the other way.
  final double curvature;

  /// flipped runs the line from bottom-left to top-right instead of from
  /// top-left to bottom-right.
  final bool flipped;

  /// animation is how it arrives and leaves. See ElementAnimation.
  final ElementAnimation animation;

  const LineElement(
    super.base, {
    this.color = const Color(0xFFFFFFFF),
    this.fade,
    this.strokeWidth = 4,
    this.cap = LineStrokeCap.flat,
    this.startEnd = LineEnd.none,
    this.endEnd = LineEnd.none,
    this.endSize = 1,
    this.dash = 0,
    this.curvature = 0,
    this.flipped = false,
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.line;

  /// start and end are the endpoints in the document's own coordinates.
  Offset get start => flipped ? bounds.bottomLeft : bounds.topLeft;
  Offset get end => flipped ? bounds.topRight : bounds.bottomRight;

  /// length and angle are the line between its two ends, the angle in
  /// degrees clockwise from pointing right.
  double get length => (end - start).distance;
  double get angle {
    var d = end - start;
    return math.atan2(d.dy, d.dx) * 180 / math.pi;
  }

  /// withEnds is this line drawn from [a] to [b].
  ///
  /// A level line would be a box with no height, which is not drawn, so it
  /// gets [lineSliver]: too little to see as a slope. The box always runs
  /// left to right, so a line drawn right to left has its ends swapped.
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

  /// level and plumb are this line turned flat or upright about its start,
  /// keeping its length and the side it points to.
  LineElement get level {
    var d = end - start;
    return withEnds(start, start + Offset(d.dx < 0 ? -length : length, 0));
  }

  LineElement get plumb {
    var d = end - start;
    return withEnds(start, start + Offset(0, d.dy < 0 ? -length : length));
  }

  @override
  CanvasElement rebase(ElementBase base) => LineElement(base,
      color: color,
      fade: fade,
      strokeWidth: strokeWidth,
      cap: cap,
      startEnd: startEnd,
      endEnd: endEnd,
      endSize: endSize,
      dash: dash,
      curvature: curvature,
      flipped: flipped,
      animation: animation);

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
      LineElement(base,
          color: color ?? this.color,
          fade: flat ? null : (fade ?? this.fade),
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          startEnd: startEnd ?? this.startEnd,
          endEnd: endEnd ?? this.endEnd,
          endSize: endSize ?? this.endSize,
          dash: dash ?? this.dash,
          curvature: curvature ?? this.curvature,
          flipped: flipped ?? this.flipped,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "color": colorToJson(color),
        if (fade != null) "fade": fade!.toJson(),
        "sw": strokeWidth,
        "strokeCap": cap.name,
        if (startEnd != LineEnd.none) "startEnd": startEnd.name,
        if (endEnd != LineEnd.none) "endEnd": endEnd.name,
        if (endSize != 1) "endSize": endSize,
        if (dash > 0) "dash": dash,
        if (curvature != 0) "curve": curvature,
        if (flipped) "flipped": true,
        if (animation.any) "anim": animation.toJson(),
      };

  factory LineElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var (oldCap, oldStart, oldEnd) = legacyCap(json["cap"]);

    return LineElement(b,
        color: colorFromJson(json["color"]),
        fade: json["fade"] is Map
            ? GradientSpec.fromJson(
                (json["fade"] as Map).cast<String, dynamic>())
            : null,
        strokeWidth: jsonDouble(json["sw"], 4),
        cap: json["strokeCap"] is String
            ? LineStrokeCap.fromName(jsonStr(json["strokeCap"]))
            : oldCap,
        startEnd: json.containsKey("startEnd") || json.containsKey("strokeCap")
            ? LineEnd.fromName(jsonStr(json["startEnd"]))
            : oldStart,
        endEnd: json.containsKey("endEnd") || json.containsKey("strokeCap")
            ? LineEnd.fromName(jsonStr(json["endEnd"]))
            : oldEnd,
        endSize: jsonDouble(json["endSize"], 1),
        dash: jsonDouble(json["dash"], 0).clamp(0.0, 400.0),
        curvature: jsonDouble(json["curve"], 0),
        flipped: jsonBool(json["flipped"], false),
        animation: jsonSpec(
            json["anim"], ElementAnimation.fromJson, const ElementAnimation()));
  }
}

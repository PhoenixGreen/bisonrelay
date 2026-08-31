import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

/// LineCapStyle is what a line's ends used to be: the stroke's cap and its
/// decoration in one enum.
///
/// Kept only so documents saved before the two were separated still open. New
/// documents write [LineStrokeCap] and [LineEnd]; see LineElement.fromJson,
/// which maps each of these onto the pair it meant.
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

/// LineStrokeCap is how the stroke itself finishes.
///
/// Only the three things a stroke can do, unlike the enum above: what is drawn
/// *at* the end is a separate decision now, because "round end" and "arrow"
/// are not alternatives -- a line can want both.
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

/// LineEnd is what is drawn at one end of a line.
///
/// Per end rather than one setting for both, because the two ends of an arrow
/// almost never want the same thing: a run off the ball starts at a dot and
/// finishes in an arrowhead, and a measurement has a bar at each end.
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

  /// isPointed marks the ends that come to a point on the line's end, and so
  /// need the stroke trimmed back to their base -- see trimFor.
  bool get isPointed =>
      this == arrow || this == openArrow || this == hollowArrow;

  /// reach is how far this decoration extends from the line's end, as a
  /// multiple of the stroke width. What the selection box has to allow for.
  double get reach => switch (this) {
        LineEnd.none => 0,
        LineEnd.bar => 1.6,
        LineEnd.circle || LineEnd.hollowCircle => 1.4,
        LineEnd.square => 1.4,
        LineEnd.diamond || LineEnd.hollowDiamond => 2.2,
        _ => 3.5,
      };
}

/// LineElement is a stroke from one corner of its box to the other.
///
/// A box rather than two endpoints, so that a line resizes, rotates and
/// animates through exactly the same handles as everything else. The endpoints
/// are the box's own corners, chosen by [flipped], which is what lets a line
/// run either way across the same rectangle.
class LineElement extends CanvasElement {
  final Color color;
  final double strokeWidth;
  /// cap is how the stroke finishes, and startEnd/endEnd are what is drawn at
  /// each end. Three settings where there was one; see [LineCapStyle].
  final LineStrokeCap cap;
  final LineEnd startEnd;
  final LineEnd endEnd;

  /// dash is the on/off length in design units. Zero draws a solid line.
  final double dash;

  /// curvature bows the line out from the straight path between its ends, as
  /// a fraction of its length. Negative bows the other way.
  final double curvature;

  /// flipped runs the line from bottom-left to top-right instead of from
  /// top-left to bottom-right.
  final bool flipped;

  const LineElement(
    super.base, {
    this.color = const Color(0xFFFFFFFF),
    this.strokeWidth = 4,
    this.cap = LineStrokeCap.flat,
    this.startEnd = LineEnd.none,
    this.endEnd = LineEnd.none,
    this.dash = 0,
    this.curvature = 0,
    this.flipped = false,
  });

  @override
  ElementKind get kind => ElementKind.line;

  /// start and end are the endpoints in the document's own coordinates.
  Offset get start => flipped ? bounds.bottomLeft : bounds.topLeft;
  Offset get end => flipped ? bounds.topRight : bounds.bottomRight;

  @override
  CanvasElement rebase(ElementBase base) => LineElement(base,
      color: color,
      strokeWidth: strokeWidth,
      cap: cap,
      startEnd: startEnd,
      endEnd: endEnd,
      dash: dash,
      curvature: curvature,
      flipped: flipped);

  LineElement copyWith({
    Color? color,
    double? strokeWidth,
    LineStrokeCap? cap,
    LineEnd? startEnd,
    LineEnd? endEnd,
    double? dash,
    double? curvature,
    bool? flipped,
  }) =>
      LineElement(base,
          color: color ?? this.color,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          startEnd: startEnd ?? this.startEnd,
          endEnd: endEnd ?? this.endEnd,
          dash: dash ?? this.dash,
          curvature: curvature ?? this.curvature,
          flipped: flipped ?? this.flipped);

  @override
  Map<String, dynamic> props() => {
        "color": colorToJson(color),
        "sw": strokeWidth,
        "strokeCap": cap.name,
        if (startEnd != LineEnd.none) "startEnd": startEnd.name,
        if (endEnd != LineEnd.none) "endEnd": endEnd.name,
        if (dash > 0) "dash": dash,
        if (curvature != 0) "curve": curvature,
        if (flipped) "flipped": true,
      };

  factory LineElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    // A document saved before the stroke's cap and the ends' decorations were
    // separated has one "cap" holding both. Each old value maps onto the pair
    // it actually meant.
    var old = LineCapStyle.fromName(json["cap"] as String?);
    var (oldCap, oldStart, oldEnd) = switch (old) {
      LineCapStyle.round => (LineStrokeCap.round, LineEnd.none, LineEnd.none),
      LineCapStyle.square => (LineStrokeCap.square, LineEnd.none, LineEnd.none),
      LineCapStyle.arrow => (LineStrokeCap.flat, LineEnd.none, LineEnd.arrow),
      LineCapStyle.arrowBoth => (LineStrokeCap.flat, LineEnd.arrow, LineEnd.arrow),
      LineCapStyle.dot => (LineStrokeCap.round, LineEnd.circle, LineEnd.circle),
      _ => (LineStrokeCap.flat, LineEnd.none, LineEnd.none),
    };

    return LineElement(b,
        color: colorFromJson(json["color"]),
        strokeWidth: jsonDouble(json["sw"], 4),
        cap: json["strokeCap"] is String
            ? LineStrokeCap.fromName(json["strokeCap"] as String?)
            : oldCap,
        startEnd: json.containsKey("startEnd") || json.containsKey("strokeCap")
            ? LineEnd.fromName(json["startEnd"] as String?)
            : oldStart,
        endEnd: json.containsKey("endEnd") || json.containsKey("strokeCap")
            ? LineEnd.fromName(json["endEnd"] as String?)
            : oldEnd,
        dash: jsonDouble(json["dash"], 0),
        curvature: jsonDouble(json["curve"], 0),
        flipped: jsonBool(json["flipped"], false));
  }
}

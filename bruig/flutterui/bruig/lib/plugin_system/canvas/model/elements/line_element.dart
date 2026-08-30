import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

/// LineCapStyle is how a line finishes. Our own enum rather than Flutter's
/// StrokeCap because two of these -- the arrowheads -- are not caps at all,
/// and a diagram of a run off the ball is mostly arrows.
enum LineCapStyle {
  flat("Flat"),
  round("Round"),
  square("Square"),
  arrow("Arrow"),
  arrowBoth("Arrow both ends"),
  dot("Dot");

  final String label;
  const LineCapStyle(this.label);

  static LineCapStyle fromName(String? name) => values.firstWhere(
        (c) => c.name == name,
        orElse: () => LineCapStyle.flat,
      );

  bool get hasEndArrow => this == arrow || this == arrowBoth;
  bool get hasStartArrow => this == arrowBoth;
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
  final LineCapStyle cap;

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
    this.cap = LineCapStyle.flat,
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
      dash: dash,
      curvature: curvature,
      flipped: flipped);

  LineElement copyWith({
    Color? color,
    double? strokeWidth,
    LineCapStyle? cap,
    double? dash,
    double? curvature,
    bool? flipped,
  }) =>
      LineElement(base,
          color: color ?? this.color,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cap: cap ?? this.cap,
          dash: dash ?? this.dash,
          curvature: curvature ?? this.curvature,
          flipped: flipped ?? this.flipped);

  @override
  Map<String, dynamic> props() => {
        "color": colorToJson(color),
        "sw": strokeWidth,
        "cap": cap.name,
        if (dash > 0) "dash": dash,
        if (curvature != 0) "curve": curvature,
        if (flipped) "flipped": true,
      };

  factory LineElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      LineElement(b,
          color: colorFromJson(json["color"]),
          strokeWidth: jsonDouble(json["sw"], 4),
          cap: LineCapStyle.fromName(json["cap"] as String?),
          dash: jsonDouble(json["dash"], 0),
          curvature: jsonDouble(json["curve"], 0),
          flipped: jsonBool(json["flipped"], false));
}

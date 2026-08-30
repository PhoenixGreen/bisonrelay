import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// ShapeKind is which outline a shape element draws.
///
/// One element with a dropdown rather than one element per shape, because
/// changing your mind about whether the callout is a circle or a rounded
/// rectangle should not mean deleting it and losing its position, its colour
/// and its place in the animation.
enum ShapeKind {
  rectangle("Rectangle"),
  square("Square"),
  ellipse("Ellipse"),
  circle("Circle"),
  triangle("Triangle"),
  diamond("Diamond"),
  pentagon("Pentagon"),
  hexagon("Hexagon"),
  star("Star"),
  arrow("Arrow"),
  chevron("Chevron"),
  cross("Cross"),
  speechBubble("Speech bubble");

  final String label;
  const ShapeKind(this.label);

  static ShapeKind fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ShapeKind.rectangle,
      );

  /// isRegular means the shape only makes sense in a square box, so the
  /// resize handles keep the aspect. A "circle" dragged into an oval is an
  /// ellipse, and there is already an ellipse.
  bool get isRegular => this == ShapeKind.square || this == ShapeKind.circle;

  /// hasPoints is whether the point count control applies.
  bool get hasPoints => this == ShapeKind.star;
}

/// ShapeElement is a filled and stroked outline, optionally with a label
/// inside it.
class ShapeElement extends CanvasElement {
  final ShapeKind shape;
  final Color fill;
  final Color strokeColor;
  final double strokeWidth;

  /// cornerRadius rounds a rectangle, and is ignored by the shapes that have
  /// no corners to round.
  final double cornerRadius;

  /// points and innerRatio shape a star: how many spikes, and how deep the
  /// valleys between them go.
  final int points;
  final double innerRatio;

  /// text is the label inside. Empty is the normal case, and drawing nothing
  /// costs nothing.
  final String text;
  final TextSpec textSpec;

  const ShapeElement(
    super.base, {
    this.shape = ShapeKind.rectangle,
    this.fill = const Color(0xFF3D7EFF),
    this.strokeColor = const Color(0xFFFFFFFF),
    this.strokeWidth = 0,
    this.cornerRadius = 0,
    this.points = 5,
    this.innerRatio = 0.42,
    this.text = "",
    this.textSpec = const TextSpec(fontSize: 24, weight: 700),
  });

  @override
  ElementKind get kind => ElementKind.shape;

  @override
  CanvasElement rebase(ElementBase base) => ShapeElement(base,
      shape: shape,
      fill: fill,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
      points: points,
      innerRatio: innerRatio,
      text: text,
      textSpec: textSpec);

  ShapeElement copyWith({
    ShapeKind? shape,
    Color? fill,
    Color? strokeColor,
    double? strokeWidth,
    double? cornerRadius,
    int? points,
    double? innerRatio,
    String? text,
    TextSpec? textSpec,
  }) =>
      ShapeElement(base,
          shape: shape ?? this.shape,
          fill: fill ?? this.fill,
          strokeColor: strokeColor ?? this.strokeColor,
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cornerRadius: cornerRadius ?? this.cornerRadius,
          points: points ?? this.points,
          innerRatio: innerRatio ?? this.innerRatio,
          text: text ?? this.text,
          textSpec: textSpec ?? this.textSpec);

  @override
  Map<String, dynamic> props() => {
        "shape": shape.name,
        "fill": colorToJson(fill),
        if (strokeWidth > 0) "sw": strokeWidth,
        if (strokeWidth > 0) "sc": colorToJson(strokeColor),
        if (cornerRadius > 0) "cr": cornerRadius,
        if (shape.hasPoints) "points": points,
        if (shape.hasPoints) "inner": innerRatio,
        if (text.isNotEmpty) "text": text,
        if (text.isNotEmpty) "textSpec": textSpec.toJson(),
      };

  factory ShapeElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ShapeElement(b,
          shape: ShapeKind.fromName(json["shape"] as String?),
          fill: colorFromJson(json["fill"], const Color(0xFF3D7EFF)),
          strokeColor: colorFromJson(json["sc"]),
          strokeWidth: jsonDouble(json["sw"], 0),
          cornerRadius: jsonDouble(json["cr"], 0),
          points: jsonInt(json["points"], 5),
          innerRatio: jsonDouble(json["inner"], 0.42),
          text: jsonString(json["text"], ""),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 24, weight: 700)));
}

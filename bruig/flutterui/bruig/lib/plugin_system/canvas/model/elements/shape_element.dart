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

/// BubbleBody is the outline of a speech bubble.
enum BubbleBody {
  rounded("Rounded"),
  oval("Oval"),
  cloud("Cloud"),
  burst("Burst");

  final String label;
  const BubbleBody(this.label);

  static BubbleBody fromName(String? name) => values.firstWhere(
        (b) => b.name == name,
        orElse: () => BubbleBody.rounded,
      );
}

/// BubbleTail is what comes out of the bubble and points at whoever is
/// talking.
enum BubbleTail {
  none("None"),
  pointer("Pointer"),
  curved("Curved"),
  thought("Thought");

  final String label;
  const BubbleTail(this.label);

  static BubbleTail fromName(String? name) => values.firstWhere(
        (t) => t.name == name,
        orElse: () => BubbleTail.pointer,
      );
}

/// SpeechBubbleSpec is everything about a speech bubble that a rectangle is
/// not.
///
/// Its own object rather than six more fields on the element, for the same
/// reason a text element's columns are: every one of them is meaningless
/// unless the shape is a bubble, and grouping them is what lets the settings
/// show them only then.
class SpeechBubbleSpec {
  final BubbleBody body;
  final BubbleTail tail;

  /// tailAngle is where the tail leaves the bubble, in degrees clockwise from
  /// the right-hand side -- so it travels all the way around rather than being
  /// stuck at the bottom-left, which is where it used to be nailed.
  final double tailAngle;

  /// tailLength is how far the tail reaches past the bubble, as a fraction of
  /// the bubble's own half-height.
  final double tailLength;

  /// tailWidth is how wide the tail is where it meets the bubble, as the same
  /// kind of fraction. Long and thin or short and fat are both bubbles people
  /// draw.
  final double tailWidth;

  /// curl bends a curved tail. Ignored by the others.
  final double curl;

  const SpeechBubbleSpec({
    this.body = BubbleBody.rounded,
    this.tail = BubbleTail.pointer,
    this.tailAngle = 115,
    this.tailLength = 0.45,
    this.tailWidth = 0.32,
    this.curl = 0.5,
  });

  SpeechBubbleSpec copyWith({
    BubbleBody? body,
    BubbleTail? tail,
    double? tailAngle,
    double? tailLength,
    double? tailWidth,
    double? curl,
  }) =>
      SpeechBubbleSpec(
        body: body ?? this.body,
        tail: tail ?? this.tail,
        tailAngle: tailAngle ?? this.tailAngle,
        tailLength: tailLength ?? this.tailLength,
        tailWidth: tailWidth ?? this.tailWidth,
        curl: curl ?? this.curl,
      );

  Map<String, dynamic> toJson() => {
        "body": body.name,
        "tail": tail.name,
        "angle": tailAngle,
        "length": tailLength,
        "width": tailWidth,
        if (tail == BubbleTail.curved) "curl": curl,
      };

  factory SpeechBubbleSpec.fromJson(Map<String, dynamic> json) =>
      SpeechBubbleSpec(
        body: BubbleBody.fromName(json["body"] as String?),
        tail: BubbleTail.fromName(json["tail"] as String?),
        tailAngle: jsonDouble(json["angle"], 115),
        tailLength: jsonDouble(json["length"], 0.45).clamp(0.0, 2.0),
        tailWidth: jsonDouble(json["width"], 0.32).clamp(0.02, 2.0),
        curl: jsonDouble(json["curl"], 0.5),
      );
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

  /// bubble is read only when [shape] is a speech bubble.
  final SpeechBubbleSpec bubble;

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
    this.bubble = const SpeechBubbleSpec(),
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
      textSpec: textSpec,
      bubble: bubble);

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
    SpeechBubbleSpec? bubble,
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
          textSpec: textSpec ?? this.textSpec,
          bubble: bubble ?? this.bubble);

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
        if (shape == ShapeKind.speechBubble) "bubble": bubble.toJson(),
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
              const TextSpec(fontSize: 24, weight: 700)),
          bubble: jsonSpec(json["bubble"], SpeechBubbleSpec.fromJson,
              const SpeechBubbleSpec()));
}

import 'package:bruig/components/paint_spec.dart';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
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

  /// hasCorners is whether rounding the corners means anything. A circle has
  /// none to round, and a field that does nothing is worse than no field.
  bool get hasCorners =>
      this == ShapeKind.rectangle ||
      this == ShapeKind.square ||
      this == ShapeKind.speechBubble;
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

  /// painted is a picture or a pattern inside the shape instead of a flat
  /// colour, cut to the shape's own outline.
  ///
  /// The same spec the letters and a box are painted with -- see TextFill --
  /// because it is the same question asked of a third shape.
  final TextFill painted;
  final Color strokeColor;

  /// fillFade and strokeFade are the second colours, when the fill or the
  /// outline fades to one. Null for the flat ones, which is most of them.
  ///
  /// Set in the picker beside the colour itself rather than in settings of
  /// their own -- see GradientSpec. That is why they have no on/off flag:
  /// there either is a second colour or there is not.
  final GradientSpec? fillFade;
  final GradientSpec? strokeFade;
  final double strokeWidth;

  /// cornerRadius rounds a rectangle, and is ignored by the shapes that have
  /// no corners to round.
  final double cornerRadius;

  /// radTL, radTR, radBR and radBL are the corners that have been given their
  /// own rounding, or null for "whatever [cornerRadius] says".
  ///
  /// The same shape a box's corners take, and the same [Corners] underneath,
  /// so a rectangle shape and a picture's frame round themselves by one piece
  /// of code. See BoxSpec.
  final double? radTL;
  final double? radTR;
  final double? radBR;
  final double? radBL;

  /// padding is the room kept between the shape's edge and its label, and
  /// padL..padB are the sides that have been given their own.
  ///
  /// Room inside rather than room around: a shape's label is words, and words
  /// reflow into whatever is left -- unlike a picture, which has to keep its
  /// proportions and would crop. See grownForPadding, which is the other
  /// answer for the other case.
  ///
  /// Zero means the shape decides for itself, which is what it always did: a
  /// circle needs more inset than a rectangle, a triangle more again, and
  /// those fractions are the sensible default nobody should have to set. See
  /// labelRoom.
  final double padding;
  final double? padL;
  final double? padT;
  final double? padR;
  final double? padB;

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

  /// animation is how the shape arrives and leaves. See ElementAnimation --
  /// the same two keyframes a chart and a headline use, so they can arrive
  /// together.
  final ElementAnimation animation;

  const ShapeElement(
    super.base, {
    this.shape = ShapeKind.rectangle,
    this.fill = const Color(0xFF3D7EFF),
    this.strokeColor = const Color(0xFFFFFFFF),
    this.fillFade,
    this.strokeFade,
    this.strokeWidth = 0,
    this.cornerRadius = 0,
    this.radTL,
    this.radTR,
    this.radBR,
    this.radBL,
    this.padding = 0,
    this.padL,
    this.padT,
    this.padR,
    this.padB,
    this.points = 5,
    this.innerRatio = 0.42,
    this.text = "",
    this.textSpec = const TextSpec(fontSize: 24, weight: 700),
    this.bubble = const SpeechBubbleSpec(),
    this.painted = const TextFill(),
    this.animation = const ElementAnimation(),
  });

  @override
  ElementKind get kind => ElementKind.shape;

  /// corners is the four radii, one number answering for whichever of them
  /// has not been given its own.
  Corners get corners =>
      Corners(all: cornerRadius, tl: radTL, tr: radTR, br: radBR, bl: radBL);

  /// pad is the room kept for the label on each side, or all zeroes where the
  /// shape is still deciding for itself.
  Room get pad => Room(all: padding, l: padL, t: padT, r: padR, b: padB);

  /// padded is whether anybody has asked for a particular amount of room.
  bool get padded =>
      pad.left > 0 || pad.top > 0 || pad.right > 0 || pad.bottom > 0;

  /// assetIds is the picture this shape is painted with, where it has one.
  /// Without it the sweep takes the picture away and the shape opens empty.
  @override
  Set<String> get assetIds =>
      painted.assetId.isEmpty ? const {} : {painted.assetId};

  @override
  CanvasElement rebase(ElementBase base) => ShapeElement(base,
      shape: shape,
      fill: fill,
      strokeColor: strokeColor,
      fillFade: fillFade,
      strokeFade: strokeFade,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
      radTL: radTL,
      radTR: radTR,
      radBR: radBR,
      radBL: radBL,
      padding: padding,
      padL: padL,
      padT: padT,
      padR: padR,
      padB: padB,
      points: points,
      innerRatio: innerRatio,
      text: text,
      textSpec: textSpec,
      bubble: bubble,
      painted: painted,
      animation: animation);

  ShapeElement copyWith({
    ShapeKind? shape,
    Color? fill,
    Color? strokeColor,
    GradientSpec? fillFade,
    GradientSpec? strokeFade,
    bool flatFill = false,
    bool flatStroke = false,
    double? strokeWidth,
    double? cornerRadius,
    double? radTL,
    double? radTR,
    double? radBR,
    double? radBL,
    double? padding,
    double? padL,
    double? padT,
    double? padR,
    double? padB,
    int? points,
    double? innerRatio,
    String? text,
    TextSpec? textSpec,
    SpeechBubbleSpec? bubble,
    TextFill? painted,
    ElementAnimation? animation,

    /// clearCorners and clearRoom take the four overrides as given, nulls
    /// and all, rather than filling a null with what was there before. What
    /// "set all four corners to one number" needs: through the ordinary
    /// copyWith the three that had their own would have survived it.
    bool clearCorners = false,
    bool clearRoom = false,
  }) =>
      ShapeElement(base,
          shape: shape ?? this.shape,
          fill: fill ?? this.fill,
          strokeColor: strokeColor ?? this.strokeColor,
          fillFade: flatFill ? null : (fillFade ?? this.fillFade),
          strokeFade: flatStroke ? null : (strokeFade ?? this.strokeFade),
          strokeWidth: strokeWidth ?? this.strokeWidth,
          cornerRadius: cornerRadius ?? this.cornerRadius,
          radTL: clearCorners ? radTL : (radTL ?? this.radTL),
          radTR: clearCorners ? radTR : (radTR ?? this.radTR),
          radBR: clearCorners ? radBR : (radBR ?? this.radBR),
          radBL: clearCorners ? radBL : (radBL ?? this.radBL),
          padding: padding ?? this.padding,
          padL: clearRoom ? padL : (padL ?? this.padL),
          padT: clearRoom ? padT : (padT ?? this.padT),
          padR: clearRoom ? padR : (padR ?? this.padR),
          padB: clearRoom ? padB : (padB ?? this.padB),
          points: points ?? this.points,
          innerRatio: innerRatio ?? this.innerRatio,
          text: text ?? this.text,
          textSpec: textSpec ?? this.textSpec,
          bubble: bubble ?? this.bubble,
          painted: painted ?? this.painted,
          animation: animation ?? this.animation);

  @override
  Map<String, dynamic> props() => {
        "shape": shape.name,
        "fill": colorToJson(fill),
        if (painted.on) "painted": painted.toJson(),
        if (fillFade != null) "fillFade": fillFade!.toJson(),
        if (strokeFade != null) "strokeFade": strokeFade!.toJson(),
        if (strokeWidth > 0) "sw": strokeWidth,
        if (strokeWidth > 0) "sc": colorToJson(strokeColor),
        if (cornerRadius > 0) "cr": cornerRadius,
        if (radTL != null) "rTL": radTL,
        if (radTR != null) "rTR": radTR,
        if (radBR != null) "rBR": radBR,
        if (radBL != null) "rBL": radBL,
        if (padding > 0) "pad": padding,
        if (padL != null) "padL": padL,
        if (padT != null) "padT": padT,
        if (padR != null) "padR": padR,
        if (padB != null) "padB": padB,
        if (shape.hasPoints) "points": points,
        if (shape.hasPoints) "inner": innerRatio,
        if (text.isNotEmpty) "text": text,
        if (text.isNotEmpty) "textSpec": textSpec.toJson(),
        if (shape == ShapeKind.speechBubble) "bubble": bubble.toJson(),
        if (animation.on || animation.closes) "anim": animation.toJson(),
      };

  factory ShapeElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ShapeElement(b,
          shape: ShapeKind.fromName(json["shape"] as String?),
          fill: colorFromJson(json["fill"], const Color(0xFF3D7EFF)),
          painted: json["painted"] is Map
              ? TextFill.fromJson(
                  (json["painted"] as Map).cast<String, dynamic>())
              : const TextFill(),
          fillFade:
              json["fillFade"]
                      is Map
                  ? GradientSpec.fromJson((json[
                          "fillFade"] as Map)
                      .cast<String, dynamic>())
                  : null,
          strokeFade:
              json[
                      "strokeFade"] is Map
                  ? GradientSpec
                      .fromJson(
                          (json["strokeFade"] as Map).cast<String, dynamic>())
                  : null,
          strokeColor: colorFromJson(json["sc"]),
          strokeWidth: jsonDouble(json["sw"], 0),
          cornerRadius: jsonDouble(json["cr"], 0),
          radTL: json["rTL"] == null ? null : jsonDouble(json["rTL"], 0),
          radTR: json["rTR"] == null ? null : jsonDouble(json["rTR"], 0),
          radBR: json["rBR"] == null ? null : jsonDouble(json["rBR"], 0),
          radBL: json["rBL"] == null ? null : jsonDouble(json["rBL"], 0),
          padding: jsonDouble(json["pad"], 0),
          padL: json["padL"] == null ? null : jsonDouble(json["padL"], 0),
          padT: json["padT"] == null ? null : jsonDouble(json["padT"], 0),
          padR: json["padR"] == null ? null : jsonDouble(json["padR"], 0),
          padB: json["padB"] == null ? null : jsonDouble(json["padB"], 0),
          points: jsonInt(json["points"], 5),
          innerRatio: jsonDouble(json["inner"], 0.42),
          text: jsonString(json["text"], ""),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              const TextSpec(fontSize: 24, weight: 700)),
          bubble: jsonSpec(json["bubble"], SpeechBubbleSpec.fromJson,
              const SpeechBubbleSpec()),
          animation: jsonSpec(json["anim"], ElementAnimation.fromJson,
              const ElementAnimation()));
}

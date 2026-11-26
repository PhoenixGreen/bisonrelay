import 'package:bruig/components/paint_spec.dart';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

/// ShapeKind is which outline a shape element draws: one element with a
/// choice of outline, so changing it keeps everything else.
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

  // What each kind is, asked by whatever draws, measures or offers it. Each
  // is a switch with no default, so a new kind has to answer every one.

  /// isRegular is whether the shape is drawn square: in the square in the
  /// middle of its box, whatever shape the box is (shapeBox).
  bool get isRegular => switch (this) {
        square || circle => true,
        rectangle || ellipse || triangle || diamond || pentagon => false,
        hexagon || star || arrow || chevron || cross || speechBubble => false,
      };

  /// hasPoints is whether the point count control applies.
  bool get hasPoints => switch (this) {
        star => true,
        rectangle || square || ellipse || circle || triangle => false,
        diamond || pentagon || hexagon || arrow || chevron => false,
        cross || speechBubble => false,
      };

  /// hasCornersWith is whether rounding the corners means anything for this
  /// kind, given the [body] a speech bubble would have: only a rounded body
  /// has corners to round.
  bool hasCornersWith(BubbleBody body) => switch (this) {
        rectangle || square => true,
        speechBubble => body == BubbleBody.rounded,
        ellipse || circle || triangle || diamond || pentagon => false,
        hexagon || star || arrow || chevron || cross => false,
      };

  /// labelInsetWith is how far in from the edge of its room a label is set
  /// when no padding is asked for, as a share of the room's shorter side: a
  /// crude inset rather than the rectangle inscribed in the outline, enough
  /// to keep words in a circle or a triangle off the edge. A speech bubble's
  /// room is its body, and depends on that [body].
  double labelInsetWith(BubbleBody body) => switch (this) {
        rectangle || square || arrow || chevron || cross => 0.06,
        circle || ellipse => 0.15,
        triangle => 0.24,
        diamond || star => 0.26,
        pentagon || hexagon => 0.16,
        speechBubble => body == BubbleBody.burst ? 0.22 : 0.1,
      };

  /// labelDrop is how far a label's room is moved down from the middle, as
  /// a share of the box's height: a triangle's top is a point.
  double get labelDrop => switch (this) {
        triangle => 0.1,
        rectangle || square || ellipse || circle || diamond => 0,
        pentagon || hexagon || star || arrow || chevron => 0,
        cross || speechBubble => 0,
      };

  /// facing is the way the shape's front end points as drawn, in degrees
  /// clockwise from the right, or null for a shape with no front end: what
  /// a shape turns by to point the way it is going.
  double? get facing => switch (this) {
        arrow || chevron => 0,
        triangle => -90,
        rectangle || square || ellipse || circle || diamond => null,
        pentagon || hexagon || star || cross || speechBubble => null,
      };
}

/// minStarPoints, maxStarPoints, minStarDepth and maxStarDepth are the
/// points and depth a star is drawn with whatever it holds: the panel's
/// range, and what a received one is read within.
const int minStarPoints = 3, maxStarPoints = 24;
const double minStarDepth = 0.05, maxStarDepth = 0.95;

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

/// BubbleTail is what points from the bubble at whoever is talking.
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

/// SpeechBubbleSpec is everything a speech bubble has that a rectangle has
/// not, grouped so the settings show it only for a bubble.
class SpeechBubbleSpec {
  /// body is the bubble's outline round its words, and tail what points
  /// from it at whoever is talking.
  final BubbleBody body;
  final BubbleTail tail;

  /// tailAngle is where the tail leaves, degrees clockwise from the right.
  final double tailAngle;

  /// tailLength is the tail's reach past the bubble, of its half-height;
  /// tailWidth its width where it meets the bubble, the same way. Each is
  /// set, and read, within its least and most below: past them the body
  /// gives up all its room to the tail and collapses.
  final double tailLength;

  final double tailWidth;

  static const double minTailLength = 0.05, maxTailLength = 1.2;
  static const double minTailWidth = 0.05, maxTailWidth = 1;

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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = SpeechBubbleSpec();

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
        body: BubbleBody.fromName(jsonStr(json["body"])),
        tail: BubbleTail.fromName(jsonStr(json["tail"])),
        // A turn either way is every angle there is; a curl is held to ten
        // times what the panel offers, so a received one cannot fling the
        // tail across the page; a length and a width to what the panel
        // offers.
        tailAngle:
            jsonDouble(json["angle"], _defaults.tailAngle).clamp(-360.0, 360.0),
        tailLength: jsonDouble(json["length"], _defaults.tailLength)
            .clamp(minTailLength, maxTailLength),
        tailWidth: jsonDouble(json["width"], _defaults.tailWidth)
            .clamp(minTailWidth, maxTailWidth),
        curl: jsonDouble(json["curl"], _defaults.curl).clamp(-15.0, 15.0),
      );
}

/// ShapeElement is a filled and outlined shape drawn to its box, of any
/// [ShapeKind], with words set inside it if it has any. Its outline is
/// worked out in one place (shapeOutline, in the renderer), which the
/// painter, a loop, wrapped words and the stage's press all ask.
class ShapeElement extends CanvasElement {
  /// shape is which outline it draws.
  final ShapeKind shape;

  /// fill is the colour inside the outline, or where its [fillFade] starts.
  final Color fill;

  /// painted is a picture or a pattern inside the shape instead of a flat
  /// colour, cut to its outline: the TextFill letters and boxes use.
  final TextFill painted;

  /// strokeColor is the outline's colour, or where its [strokeFade] starts.
  /// No outline is drawn while [strokeWidth] is 0, however it is coloured.
  final Color strokeColor;

  /// fillFade and strokeFade are the second colours a fill or outline fades
  /// to, or null for flat. See GradientSpec.
  final GradientSpec? fillFade;
  final GradientSpec? strokeFade;

  /// strokeWidth is the outline's width, drawn centred on the outline, so
  /// half of it falls outside; 0 is no outline.
  final double strokeWidth;

  /// cornerRadius rounds the corners of a kind that has them (hasCorners:
  /// a rectangle, a square, a rounded bubble); the others ignore it.
  final double cornerRadius;

  /// radTL, radTR, radBR and radBL are corners given their own rounding, or
  /// null for [cornerRadius]'s: the [Corners] a BoxSpec uses.
  final double? radTL;
  final double? radTR;
  final double? radBR;
  final double? radBL;

  /// padding is the room between the shape's edge and its label, padL..padB
  /// the sides given their own: room inside, since words reflow (a picture
  /// grows instead; see grownForPadding). Zero lets the shape choose its own
  /// inset; see labelRoom.
  final double padding;
  final double? padL;
  final double? padT;
  final double? padR;
  final double? padB;

  /// points and innerRatio shape a star: spikes, and how deep between. It is
  /// drawn, and read, within [minStarPoints]..[maxStarPoints] and
  /// [minStarDepth]..[maxStarDepth].
  final int points;
  final double innerRatio;

  /// text is the label inside, usually empty, and textSpec the type it is
  /// set in.
  final String text;
  final TextSpec textSpec;

  /// bubble is read only when [shape] is a speech bubble.
  final SpeechBubbleSpec bubble;

  /// animation is how it arrives on the page and leaves.
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ShapeElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.shape;

  /// corners is the four radii, [cornerRadius] standing in for unset ones.
  Corners get corners =>
      Corners(all: cornerRadius, tl: radTL, tr: radTR, br: radBR, bl: radBL);

  /// hasCorners is whether this shape's corners can be rounded: its kind's
  /// answer for its own bubble's body.
  bool get hasCorners => shape.hasCornersWith(bubble.body);

  /// labelInset is how far in its label is set while no padding is asked
  /// for: its kind's answer for its own bubble's body.
  double get labelInset => shape.labelInsetWith(bubble.body);

  /// pad is the room kept for the label on each side, or all zeroes while
  /// the shape decides for itself.
  Room get pad => Room(all: padding, l: padL, t: padT, r: padR, b: padB);

  /// padded is whether a particular amount of room has been asked for.
  bool get padded =>
      pad.left > 0 || pad.top > 0 || pad.right > 0 || pad.bottom > 0;

  /// assetIds is the picture this shape is painted with, where it has one:
  /// without it the sweep takes the picture away.
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

    /// clearCorners and clearRoom take the four overrides as given, nulls and
    /// all, so "set all four corners to one number" can clear them.
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
  bool get scalesInside => true;

  /// scaledBy sizes what is measured in design units by [by]: its words'
  /// type, its outline, its corners and its padding. What its kind draws (a
  /// star's depth, a bubble's tail) is a share of its box, which is sized
  /// apart.
  @override
  ShapeElement scaledBy(double by) {
    var c = corners.scaledBy(by), r = pad.scaledBy(by);
    return copyWith(
        textSpec: textSpec.scaledBy(by),
        strokeWidth: strokeWidth * by,
        cornerRadius: c.all,
        radTL: c.tl,
        radTR: c.tr,
        radBR: c.br,
        radBL: c.bl,
        clearCorners: true,
        padding: r.all,
        padL: r.l,
        padT: r.t,
        padR: r.r,
        padB: r.b,
        clearRoom: true);
  }

  /// keepsAspectByKind is true of a square or a circle, which is drawn
  /// square in the middle of its box (shapeBox): held square, what is drawn
  /// stays the whole box.
  @override
  bool get keepsAspectByKind => shape.isRegular;

  /// withKind is this shape as [kind], wherever it is chosen. A square or a
  /// circle is drawn square in the middle of its box (shapeBox), so its box
  /// is made square on its shorter side, about its middle; its kind then
  /// keeps it square ([keepsAspectByKind]). Whether the person holds its
  /// proportions is theirs, and no kind changes it. Only choosing squares a
  /// box: a saved oblong square or circle is read and drawn as it was.
  ShapeElement withKind(ShapeKind kind) {
    var next = copyWith(shape: kind);
    if (!kind.isRegular) return next;
    var side = math.min(width, height);
    return next.withBase(
        x: x + (width - side) / 2,
        y: y + (height - side) / 2,
        width: side,
        height: side) as ShapeElement;
  }

  /// withOutline is this shape with its outline coloured [color], faded to
  /// [fade], or made flat ([flat]). An outline with no width is not drawn
  /// however it is coloured, so a colour or a fade asked for is an outline
  /// asked for: one with none is given a width to see it by.
  ShapeElement withOutline(
          {Color? color, GradientSpec? fade, bool flat = false}) =>
      copyWith(
          strokeColor: color,
          strokeFade: fade,
          flatStroke: flat,
          strokeWidth: strokeWidth > 0 || (color == null && fade == null)
              ? null
              : _outlineToSee());

  /// _outlineToSee is the width for a shape outlined for the first time:
  /// enough to see on a big shape, not enough to swallow a small one.
  double _outlineToSee() => (math.min(width, height) * 0.015).clamp(1.0, 6.0);

  /// mapOwnColours maps the shape's fill, its outline (hidden with no
  /// width) and their fades, the picture or pattern it is painted with
  /// (hidden unless painted), its words' type (hidden with no words) and its
  /// arrival. A speech bubble's shape holds no colour.
  @override
  ShapeElement mapOwnColours(ColourMap f) {
    var lined = strokeWidth > 0;
    var p = ColourPass(f);
    var fill = p(this.fill);
    var strokeColor = p(this.strokeColor, shown: lined);
    var fillFade = p.partOrNone(this.fillFade, (g) => g.mapColours(f));
    var strokeFade = p.partOrNone(
        this.strokeFade, (g) => g.mapColours(f.shownOnlyIf(lined)));
    var painted =
        p.part(this.painted, (x) => x.mapColours(f.shownOnlyIf(x.on)));
    var textSpec = p.part(
        this.textSpec, (s) => s.mapColours(f.shownOnlyIf(text.isNotEmpty)));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      fill: fill,
      strokeColor: strokeColor,
      fillFade: fillFade,
      strokeFade: strokeFade,
      painted: painted,
      textSpec: textSpec,
      animation: animation,
    );
  }

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
        if (animation.any) "anim": animation.toJson(),
      };

  factory ShapeElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      ShapeElement(b,
          shape: ShapeKind.fromName(jsonStr(json["shape"])),
          fill: colorFromJson(json["fill"], _defaults.fill),
          painted: jsonSpec(
              json["painted"], TextFill.fromJson, _defaults.painted),
          fillFade: jsonSpec<GradientSpec?>(
              json["fillFade"], GradientSpec.fromJson, null),
          strokeFade:
              jsonSpec<
                      GradientSpec?>(
                  json["strokeFade"], GradientSpec.fromJson, null),
          strokeColor: colorFromJson(json["sc"], _defaults.strokeColor),
          strokeWidth: jsonLength(json["sw"], _defaults.strokeWidth),
          cornerRadius: jsonLength(json["cr"], _defaults.cornerRadius),
          radTL: json["rTL"] == null ? null : jsonLength(json["rTL"], 0),
          radTR: json["rTR"] == null ? null : jsonLength(json["rTR"], 0),
          radBR: json["rBR"] == null ? null : jsonLength(json["rBR"], 0),
          radBL: json["rBL"] == null ? null : jsonLength(json["rBL"], 0),
          padding: jsonLength(json["pad"], _defaults.padding),
          padL: json["padL"] == null ? null : jsonLength(json["padL"], 0),
          padT: json["padT"] == null ? null : jsonLength(json["padT"], 0),
          padR: json["padR"] == null ? null : jsonLength(json["padR"], 0),
          padB: json["padB"] == null ? null : jsonLength(json["padB"], 0),
          points: jsonInt(json["points"],
                  _defaults.points)
              .clamp(minStarPoints, maxStarPoints),
          innerRatio:
              jsonDouble(json["inner"], _defaults.innerRatio)
                  .clamp(minStarDepth, maxStarDepth),
          text: jsonString(json["text"], _defaults.text),
          textSpec:
              jsonSpec(json["textSpec"], TextSpec.fromJson, _defaults.textSpec),
          bubble: jsonSpec(
              json["bubble"], SpeechBubbleSpec.fromJson, _defaults.bubble),
          animation: jsonSpec(
              json["anim"], ElementAnimation.fromJson, _defaults.animation));
}

import 'dart:ui';

// vector_brush.dart is how the pencil tool draws a line: how wide, how the
// pen's pressure, tilt and speed change it, how its ends taper and how much
// the hand's wobble is smoothed out. A brush makes lines in a drawing --
// each stroke a shape, its thickness carried point by point -- so a brush
// stroke stays a drawing: sharp at any size, and edited like any other line.

/// VectorBrush is one brush: the built-in ones below, or one somebody saved.
class VectorBrush {
  final String name;

  /// size is the line's full width, in pixels on screen when it is drawn --
  /// the same brush however far in the canvas is zoomed.
  final double size;

  /// pressure is whether the pen's pressure -- or, with none, the speed it
  /// moves at -- makes the line thicker and thinner; thinnest is how thin, as
  /// a share of [size], at the lightest touch; and curve how pressure turns
  /// into width: under 1 a light touch already goes wide, over 1 it takes a
  /// firm press.
  final bool pressure;
  final double thinnest;
  final double curve;

  /// opacity is how see-through the line is.
  final double opacity;

  /// taperIn and taperOut are how much of the stroke, from 0 to half of it,
  /// its start and end take to swell from nothing and fade back to it.
  final double taperIn;
  final double taperOut;

  /// smoothing is how much the hand's wobble is taken out, 0 to 1.
  final double smoothing;

  /// tilt is how much tilting the pen widens the line -- shading with the
  /// side of a pencil.
  final double tilt;

  /// nib and nibAngle make it a broad nib: [nib] of the width depends on
  /// which way the stroke goes, thinnest along [nibAngle] (degrees, 0 to the
  /// right, turning clockwise) and widest across it.
  final double nib;
  final double nibAngle;

  /// flat ends the line square at its first and last points; otherwise
  /// they are round.
  final bool flat;

  /// fill closes each stroke and fills it -- with the pencil's fill colour
  /// -- and line is whether its line is drawn too. A fill with no line is a
  /// shape painted in one stroke, round its edge.
  final bool fill;
  final bool line;

  const VectorBrush({
    required this.name,
    this.size = 4,
    this.pressure = true,
    this.thinnest = 0.3,
    this.curve = 1,
    this.opacity = 1,
    this.taperIn = 0,
    this.taperOut = 0,
    this.smoothing = 0.4,
    this.tilt = 0,
    this.nib = 0,
    this.nibAngle = 45,
    this.flat = false,
    this.fill = false,
    this.line = true,
  });

  VectorBrush copyWith({
    String? name,
    double? size,
    bool? pressure,
    double? thinnest,
    double? curve,
    double? opacity,
    double? taperIn,
    double? taperOut,
    double? smoothing,
    double? tilt,
    double? nib,
    double? nibAngle,
    bool? flat,
    bool? fill,
    bool? line,
  }) =>
      VectorBrush(
        name: name ?? this.name,
        size: size ?? this.size,
        pressure: pressure ?? this.pressure,
        thinnest: thinnest ?? this.thinnest,
        curve: curve ?? this.curve,
        opacity: opacity ?? this.opacity,
        taperIn: taperIn ?? this.taperIn,
        taperOut: taperOut ?? this.taperOut,
        smoothing: smoothing ?? this.smoothing,
        tilt: tilt ?? this.tilt,
        nib: nib ?? this.nib,
        nibAngle: nibAngle ?? this.nibAngle,
        flat: flat ?? this.flat,
        fill: fill ?? this.fill,
        line: line ?? this.line,
      );

  /// cap is how the line ends.
  StrokeCap get cap => flat ? StrokeCap.butt : StrokeCap.round;

  /// sameAs is whether [other] draws exactly as this does, whatever either
  /// is called -- whether the brush in hand is still the one picked.
  bool sameAs(VectorBrush other) =>
      size == other.size &&
      pressure == other.pressure &&
      thinnest == other.thinnest &&
      curve == other.curve &&
      opacity == other.opacity &&
      taperIn == other.taperIn &&
      taperOut == other.taperOut &&
      smoothing == other.smoothing &&
      tilt == other.tilt &&
      nib == other.nib &&
      nibAngle == other.nibAngle &&
      flat == other.flat &&
      fill == other.fill &&
      line == other.line;

  Map<String, dynamic> toJson() => {
        "name": name,
        "size": size,
        "pressure": pressure,
        "thinnest": thinnest,
        "curve": curve,
        "opacity": opacity,
        "taperIn": taperIn,
        "taperOut": taperOut,
        "smoothing": smoothing,
        "tilt": tilt,
        "nib": nib,
        "nibAngle": nibAngle,
        "flat": flat,
        if (fill) "fill": true,
        if (!line) "line": false,
      };

  factory VectorBrush.fromJson(Map<String, dynamic> json) {
    double n(String key, double fallback) =>
        json[key] is num ? (json[key] as num).toDouble() : fallback;
    const d = VectorBrush(name: "");
    return VectorBrush(
      name: json["name"] is String ? json["name"] as String : "Brush",
      size: n("size", d.size),
      pressure: json["pressure"] is bool ? json["pressure"] as bool : true,
      thinnest: n("thinnest", d.thinnest),
      curve: n("curve", d.curve),
      opacity: n("opacity", d.opacity),
      taperIn: n("taperIn", d.taperIn),
      taperOut: n("taperOut", d.taperOut),
      smoothing: n("smoothing", d.smoothing),
      tilt: n("tilt", d.tilt),
      nib: n("nib", d.nib),
      nibAngle: n("nibAngle", d.nibAngle),
      flat: json["flat"] == true,
      fill: json["fill"] == true,
      line: json["line"] != false,
    );
  }
}

/// builtInBrushes are the brushes there always are.
const builtInBrushes = [
  VectorBrush(
      name: "Pencil",
      size: 3,
      thinnest: 0.45,
      opacity: 0.85,
      taperIn: 0.04,
      taperOut: 0.04,
      smoothing: 0.3,
      tilt: 0.8),
  VectorBrush(
      name: "Fine liner",
      size: 2,
      pressure: false,
      thinnest: 1,
      smoothing: 0.5),
  VectorBrush(
      name: "Ink pen",
      size: 4,
      thinnest: 0.2,
      curve: 1.3,
      taperIn: 0.12,
      taperOut: 0.25,
      smoothing: 0.5),
  VectorBrush(
      name: "Paint brush",
      size: 16,
      thinnest: 0.1,
      curve: 0.7,
      opacity: 0.9,
      taperIn: 0.2,
      taperOut: 0.35,
      smoothing: 0.4,
      tilt: 0.3),
  VectorBrush(
      name: "Marker",
      size: 14,
      thinnest: 0.9,
      opacity: 0.55,
      smoothing: 0.3,
      flat: true),
  VectorBrush(
      name: "Calligraphy",
      size: 12,
      thinnest: 0.7,
      taperIn: 0.04,
      taperOut: 0.04,
      smoothing: 0.5,
      nib: 0.85,
      nibAngle: 45,
      flat: true),
  // Painted round its edge and filled: a shape in one stroke. Steadier than
  // the others, so the edge is clean, and the same width all the way.
  VectorBrush(
      name: "Fill",
      size: 2,
      pressure: false,
      thinnest: 1,
      smoothing: 0.6,
      fill: true,
      line: false),
];

/// StylusAction is what a button on the pen -- or its other end -- does
/// with the pencil out.
enum StylusAction {
  draw("Draw"),
  erase("Erase lines"),
  pickColour("Pick colour"),
  pan("Move the view"),
  undo("Undo"),
  select("Select tool"),
  nothing("Nothing");

  final String label;
  const StylusAction(this.label);
}

/// PenSample is one reading of the pen as a stroke is drawn: where it was
/// on the canvas, how hard it pressed (0 to 1, or null where the pen or the
/// platform does not say), how far over it was tilted (0 upright to a
/// quarter turn flat, or null), and when.
class PenSample {
  final Offset at;
  final double? pressure;
  final double? tilt;
  final Duration time;

  const PenSample(this.at,
      {this.pressure, this.tilt, this.time = Duration.zero});
}

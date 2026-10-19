import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// image_strokes.dart is brushwork: paint laid on a paint layer, and the
// retouching done to a picture -- cloning, healing, dodging, burning,
// blurring.
//
// Kept as strokes, as a mask's marks are, rather than as pixels: a stroke is
// a few hundred points, where the pixels it touched are a few hundred
// thousand, and kept as strokes they are drawn as sharp as the canvas is at
// whatever size it is exported. A paint layer's strokes are fractions of the
// picture's frame; a retouching stroke's are fractions of the picture it is
// on, so it stays on the blemish however the picture is moved or cropped.

/// StrokeKind is what a stroke does.
enum StrokeKind {
  /// paint lays colour on a paint layer; erase takes it off again.
  paint("Paint"),
  erase("Erase"),

  /// clone copies the picture from somewhere else onto where it goes.
  clone("Clone"),

  /// heal fills where it goes with the colours round it: a spot, a speck,
  /// a stray hair gone.
  heal("Spot heal"),

  /// dodge lightens, burn darkens.
  dodge("Dodge"),
  burn("Burn"),

  /// blur softens what it goes over; sharpen crisps it.
  blur("Blur"),
  sharpen("Sharpen"),

  /// smudge drags colour along the way the brush goes.
  smudge("Smudge");

  final String label;
  const StrokeKind(this.label);

  static StrokeKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => StrokeKind.paint);

  /// retouches is whether the stroke is done to a picture rather than laid
  /// on a paint layer.
  bool get retouches => this != paint && this != erase;
}

/// BrushTip is the shape of a brush and how the pen drives it: what a stroke
/// is made of beyond its size, softness, strength and colour.
///
/// The default is the round brush every stroke was before there were others,
/// so a stroke saved without one draws as it always did.
class BrushTip {
  /// roundness is how round the tip is: 1 a circle, near 0 a flat nib.
  final double roundness;

  /// angle is which way a flat nib lies, in degrees from across.
  final double angle;

  /// followTilt turns the nib the way the pen leans, as a real nib does.
  final bool followTilt;

  /// spacing is how far apart the dabs are, as a share of the tip's width.
  final double spacing;

  /// scatter throws each dab off the line by up to this share of the tip.
  final double scatter;

  /// grain leaves gaps in the paint, as a pencil or chalk on paper does.
  final double grain;

  /// pressureSize is how much a light touch thins the line, and
  /// pressureOpacity how much it fades it -- nothing at 0, all of it at 1.
  final double pressureSize;
  final double pressureOpacity;

  /// pressureCurve shapes the pen's pressure: under 1 a light hand gets a
  /// full line sooner, over 1 it takes a firm press to get there.
  final double pressureCurve;

  /// tiltSize widens the line as the pen leans over, as the side of a
  /// pencil does.
  final double tiltSize;

  const BrushTip({
    this.roundness = 1,
    this.angle = 0,
    this.followTilt = false,
    this.spacing = 0.2,
    this.scatter = 0,
    this.grain = 0,
    this.pressureSize = 0.75,
    this.pressureOpacity = 0,
    this.pressureCurve = 1,
    this.tiltSize = 0,
  });

  BrushTip copyWith({
    double? roundness,
    double? angle,
    bool? followTilt,
    double? spacing,
    double? scatter,
    double? grain,
    double? pressureSize,
    double? pressureOpacity,
    double? pressureCurve,
    double? tiltSize,
  }) =>
      BrushTip(
        roundness: roundness ?? this.roundness,
        angle: angle ?? this.angle,
        followTilt: followTilt ?? this.followTilt,
        spacing: spacing ?? this.spacing,
        scatter: scatter ?? this.scatter,
        grain: grain ?? this.grain,
        pressureSize: pressureSize ?? this.pressureSize,
        pressureOpacity: pressureOpacity ?? this.pressureOpacity,
        pressureCurve: pressureCurve ?? this.pressureCurve,
        tiltSize: tiltSize ?? this.tiltSize,
      );

  bool get plain => this == const BrushTip();

  @override
  bool operator ==(Object other) =>
      other is BrushTip &&
      other.roundness == roundness &&
      other.angle == angle &&
      other.followTilt == followTilt &&
      other.spacing == spacing &&
      other.scatter == scatter &&
      other.grain == grain &&
      other.pressureSize == pressureSize &&
      other.pressureOpacity == pressureOpacity &&
      other.pressureCurve == pressureCurve &&
      other.tiltSize == tiltSize;

  @override
  int get hashCode => Object.hash(roundness, angle, followTilt, spacing,
      scatter, grain, pressureSize, pressureOpacity, pressureCurve, tiltSize);

  Map<String, dynamic> toJson() => {
        if (roundness != 1) "round": roundness,
        if (angle != 0) "angle": angle,
        if (followTilt) "followTilt": true,
        if (spacing != 0.2) "spacing": spacing,
        if (scatter != 0) "scatter": scatter,
        if (grain != 0) "grain": grain,
        if (pressureSize != 0.75) "pSize": pressureSize,
        if (pressureOpacity != 0) "pOpacity": pressureOpacity,
        if (pressureCurve != 1) "pCurve": pressureCurve,
        if (tiltSize != 0) "tiltSize": tiltSize,
      };

  factory BrushTip.fromJson(Object? raw) {
    if (raw is! Map) return const BrushTip();
    double n(String k, double d, double lo, double hi) =>
        (raw[k] is num ? (raw[k] as num).toDouble() : d).clamp(lo, hi);
    return BrushTip(
      roundness: n("round", 1, 0.05, 1),
      angle: n("angle", 0, -180, 180),
      followTilt: raw["followTilt"] == true,
      spacing: n("spacing", 0.2, 0.02, 2),
      scatter: n("scatter", 0, 0, 2),
      grain: n("grain", 0, 0, 1),
      pressureSize: n("pSize", 0.75, 0, 1),
      pressureOpacity: n("pOpacity", 0, 0, 1),
      pressureCurve: n("pCurve", 1, 0.2, 5),
      tiltSize: n("tiltSize", 0, 0, 3),
    );
  }
}

/// BrushPreset is a brush with a name: a tip, and the size, softness and
/// strength it is usually used at.
class BrushPreset {
  final String id;
  final String name;
  final double size;
  final double hardness;
  final double strength;
  final BrushTip tip;

  const BrushPreset(this.id, this.name,
      {this.size = 0.03,
      this.hardness = 0.6,
      this.strength = 1,
      this.tip = const BrushTip()});

  Map<String, dynamic> toJson() => {
        "size": size,
        "hardness": hardness,
        "strength": strength,
        "tip": tip.toJson(),
      };

  factory BrushPreset.fromJson(
          String id, String name, Map<String, dynamic> j) =>
      BrushPreset(id, name,
          size: jsonDouble(j["size"], 0.03).clamp(0.001, 0.5),
          hardness: jsonDouble(j["hardness"], 0.6).clamp(0.0, 1.0),
          strength: jsonDouble(j["strength"], 1).clamp(0.01, 1.0),
          tip: BrushTip.fromJson(j["tip"]));
}

/// brushPresets are the brushes that come with the canvas.
const brushPresets = [
  BrushPreset("round", "Round"),
  BrushPreset("ink", "Ink pen",
      size: 0.012,
      hardness: 1,
      tip: BrushTip(spacing: 0.08, pressureSize: 0.95, pressureCurve: 1.4)),
  BrushPreset("pencil", "Pencil",
      size: 0.005,
      hardness: 0.9,
      tip: BrushTip(
          spacing: 0.15,
          grain: 0.55,
          pressureSize: 0.3,
          pressureOpacity: 0.6,
          tiltSize: 1.5)),
  BrushPreset("marker", "Marker",
      size: 0.025,
      hardness: 0.85,
      strength: 0.8,
      tip: BrushTip(roundness: 0.35, angle: 45, pressureSize: 0.1)),
  BrushPreset("calligraphy", "Calligraphy",
      size: 0.03,
      hardness: 0.95,
      tip: BrushTip(
          roundness: 0.15,
          angle: 40,
          followTilt: true,
          spacing: 0.06,
          pressureSize: 0.6)),
  BrushPreset("airbrush", "Airbrush",
      size: 0.06,
      hardness: 0,
      strength: 0.35,
      tip: BrushTip(spacing: 0.1, pressureSize: 0.2, pressureOpacity: 0.8)),
  BrushPreset("watercolour", "Watercolour",
      size: 0.05,
      hardness: 0.1,
      strength: 0.25,
      tip: BrushTip(spacing: 0.05, scatter: 0.1, pressureOpacity: 0.6)),
  BrushPreset("chalk", "Chalk",
      size: 0.03,
      hardness: 0.6,
      tip: BrushTip(spacing: 0.25, scatter: 0.3, grain: 0.7, tiltSize: 1)),
  BrushPreset("splatter", "Splatter",
      size: 0.02,
      hardness: 0.9,
      tip: BrushTip(spacing: 0.6, scatter: 1.2, grain: 0.3, pressureSize: 0.5)),
];

/// StrokeMark is one stroke of a brush.
class StrokeMark {
  final StrokeKind kind;

  /// points are the path, as fractions -- of the frame for paint, of the
  /// picture for retouching.
  final List<Offset> points;

  /// pressure is the pen's at each point, 0 to 1; empty for a mouse.
  final List<double> pressure;

  /// radius is a fraction of the frame's or picture's shorter side.
  final double radius;
  final double hardness;

  /// strength is how much the stroke does at most: paint's opacity, how far
  /// dodging lightens, how much blurring blurs.
  final double strength;

  /// colour is paint's colour.
  final Color colour;

  /// source is where a clone copies from, as how far from the stroke: the
  /// stroke's points plus this are what is copied.
  final Offset source;

  /// tip is the brush's shape and how the pen drives it -- see BrushTip.
  final BrushTip tip;

  /// tilt is the pen's lean at each point, across and down, each -1 to 1;
  /// empty for a mouse, or a pen that does not say.
  final List<Offset> tilt;

  const StrokeMark({
    required this.kind,
    required this.points,
    this.pressure = const [],
    this.radius = 0.02,
    this.hardness = 0.6,
    this.strength = 1,
    this.colour = const Color(0xFF000000),
    this.source = Offset.zero,
    this.tip = const BrushTip(),
    this.tilt = const [],
  });

  StrokeMark copyWith(
          {List<Offset>? points,
          List<double>? pressure,
          List<Offset>? tilt,
          double? radius,
          Offset? source}) =>
      StrokeMark(
        kind: kind,
        points: points ?? this.points,
        pressure: pressure ?? this.pressure,
        radius: radius ?? this.radius,
        hardness: hardness,
        strength: strength,
        colour: colour,
        source: source ?? this.source,
        tip: tip,
        tilt: tilt ?? this.tilt,
      );

  static double _round(double v) => (v * 100000).round() / 100000;

  Map<String, dynamic> toJson() => {
        "k": kind.name,
        "p": [
          for (var p in points) ...[_round(p.dx), _round(p.dy)]
        ],
        if (pressure.isNotEmpty) "pr": [for (var v in pressure) _round(v)],
        "r": radius,
        "h": hardness,
        if (strength != 1) "s": strength,
        if (kind == StrokeKind.paint) "c": colorToJson(colour),
        if (kind == StrokeKind.clone) "src": [source.dx, source.dy],
        if (!tip.plain) "tip": tip.toJson(),
        if (tilt.isNotEmpty)
          "tl": [
            for (var t in tilt) ...[_round(t.dx), _round(t.dy)]
          ],
      };

  factory StrokeMark.fromJson(Map<String, dynamic> json) {
    var flat = json["p"];
    var points = <Offset>[];
    if (flat is List) {
      for (var i = 0; i + 1 < flat.length; i += 2) {
        var x = flat[i], y = flat[i + 1];
        if (x is num && y is num) {
          points.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    var src = json["src"];
    var rawTilt = json["tl"];
    var tilt = <Offset>[];
    if (rawTilt is List) {
      for (var i = 0; i + 1 < rawTilt.length; i += 2) {
        var x = rawTilt[i], y = rawTilt[i + 1];
        if (x is num && y is num) tilt.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    return StrokeMark(
      tip: BrushTip.fromJson(json["tip"]),
      tilt: tilt,
      kind: StrokeKind.fromName(json["k"] as String?),
      points: points,
      pressure: [
        if (json["pr"] case List raw)
          for (var v in raw)
            if (v is num) v.toDouble().clamp(0.0, 1.0)
      ],
      radius: jsonDouble(json["r"], 0.02).clamp(0.0005, 1.0),
      hardness: jsonDouble(json["h"], 0.6).clamp(0.0, 1.0),
      strength: jsonDouble(json["s"], 1).clamp(0.0, 1.0),
      colour: colorFromJson(json["c"], const Color(0xFF000000)),
      source: src is List && src.length == 2 && src[0] is num && src[1] is num
          ? Offset((src[0] as num).toDouble(), (src[1] as num).toDouble())
          : Offset.zero,
    );
  }
}

/// strokesFromJson reads a list of strokes, skipping what is not one.
List<StrokeMark> strokesFromJson(Object? raw) => [
      if (raw is List)
        for (var s in raw)
          if (s is Map<String, dynamic>) StrokeMark.fromJson(s)
    ];

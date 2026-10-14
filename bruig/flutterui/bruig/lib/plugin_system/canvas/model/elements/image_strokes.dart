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

  const StrokeMark({
    required this.kind,
    required this.points,
    this.pressure = const [],
    this.radius = 0.02,
    this.hardness = 0.6,
    this.strength = 1,
    this.colour = const Color(0xFF000000),
    this.source = Offset.zero,
  });

  StrokeMark copyWith({List<Offset>? points, List<double>? pressure}) =>
      StrokeMark(
        kind: kind,
        points: points ?? this.points,
        pressure: pressure ?? this.pressure,
        radius: radius,
        hardness: hardness,
        strength: strength,
        colour: colour,
        source: source,
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
      };

  factory StrokeMark.fromJson(Map<String, dynamic> json) {
    var flat = json["p"];
    var points = <Offset>[];
    if (flat is List) {
      for (var i = 0; i + 1 < flat.length; i += 2) {
        var x = flat[i], y = flat[i + 1];
        if (x is num && y is num) points.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    var src = json["src"];
    return StrokeMark(
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

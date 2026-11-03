// character_sculpt.dart is a new 3D character shaped by hand: strokes of a
// brush drawn over the body in the Character Studio, each raising, lowering
// or flattening the surface under it. A stroke is kept where it was drawn
// on the body at rest, so it moves with the body as the body moves, and the
// clothes over it follow it as they follow the rest of the shaping. What a
// stroke does to the mesh is in render/vrm/vrm_shape.dart (StrokeDeformer).

/// SculptTool is what a stroke does to the surface under it.
enum SculptTool {
  raise("Raise"),
  lower("Lower"),
  flatten("Flatten");

  final String label;
  const SculptTool(this.label);

  static SculptTool fromName(Object? name) =>
      values.where((t) => t.name == name).firstOrNull ?? raise;
}

/// SculptPoint is one place a stroke passed over: where on the body at rest,
/// and the way the surface faced there.
class SculptPoint {
  final double x, y, z, nx, ny, nz;
  const SculptPoint(this.x, this.y, this.z, this.nx, this.ny, this.nz);

  @override
  bool operator ==(Object other) =>
      other is SculptPoint &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.nx == nx &&
      other.ny == ny &&
      other.nz == nz;

  @override
  int get hashCode => Object.hash(x, y, z, nx, ny, nz);
}

/// SculptStroke is one stroke of the brush. Immutable.
class SculptStroke {
  final SculptTool tool;

  /// radius is the brush's, in metres on the body as made; strength how
  /// far it goes, nought to one: a raise of one lifts the surface by a
  /// third of the radius.
  final double radius, strength;

  /// mirror draws it on the other side as well, as a mirror image.
  final bool mirror;
  final List<SculptPoint> points;

  const SculptStroke({
    required this.tool,
    required this.radius,
    required this.strength,
    this.mirror = false,
    this.points = const [],
  });

  SculptStroke withPoint(SculptPoint p) => SculptStroke(
      tool: tool,
      radius: radius,
      strength: strength,
      mirror: mirror,
      points: [...points, p]);

  /// key says exactly what the stroke is, for the shaping to know when it
  /// has changed.
  String get key => "${tool.name}|$radius|$strength|$mirror|${points.length}|"
      "${points.isEmpty ? "" : _p(points.last)}|${Object.hashAll(points)}";

  static String _p(SculptPoint p) => "${p.x},${p.y},${p.z}";

  static double _round(double v) => (v * 1e5).roundToDouble() / 1e5;

  Map<String, dynamic> toJson() => {
        "tool": tool.name,
        "radius": radius,
        "strength": strength,
        if (mirror) "mirror": true,
        // Six numbers a point, rounded to a hundredth of a millimetre.
        "points": [
          for (final p in points)
            for (final v in [p.x, p.y, p.z, p.nx, p.ny, p.nz]) _round(v)
        ],
      };

  /// fromJson reads what toJson wrote, or null for what is not a stroke.
  static SculptStroke? fromJson(Object? json) {
    if (json is! Map) return null;
    final r = json["radius"], s = json["strength"], raw = json["points"];
    if (r is! num || s is! num || raw is! List) return null;
    final nums = [
      for (final v in raw)
        if (v is num && v.isFinite) v.toDouble()
    ];
    if (nums.length != raw.length || nums.length % 6 != 0 || nums.isEmpty) {
      return null;
    }
    return SculptStroke(
      tool: SculptTool.fromName(json["tool"]),
      radius: r.toDouble().clamp(0.002, 0.5),
      strength: s.toDouble().clamp(0.0, 1.0),
      mirror: json["mirror"] == true,
      points: [
        for (var i = 0; i < nums.length; i += 6)
          SculptPoint(nums[i], nums[i + 1], nums[i + 2], nums[i + 3],
              nums[i + 4], nums[i + 5])
      ],
    );
  }

  @override
  bool operator ==(Object other) => other is SculptStroke && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// PaintTool is what a paint stroke does: lays colour on, or rubs out the
/// paint already there.
enum PaintTool {
  paint("Paint"),
  rubOut("Rub out");

  final String label;
  const PaintTool(this.label);

  static PaintTool fromName(Object? name) =>
      values.where((t) => t.name == name).firstOrNull ?? paint;
}

/// PaintStroke is one stroke of paint on the character: on the skin (the
/// face as well) or on a piece of clothing, by its slot's name ("top").
/// Its points are on the body as it was made, before any shaping, so the
/// paint stays where it was put however the body is shaped after. What is
/// drawn from it is in render/vrm/vrm_paint.dart.
class PaintStroke {
  final String on;
  final PaintTool tool;

  /// colour is 0xRRGGBB.
  final int colour;

  /// radius is the brush's, in metres; opacity how much of the colour goes
  /// on, nought to one; softness how far in from the edge it fades, nought
  /// (a hard edge) to one (fading from the middle).
  final double radius, opacity, softness;
  final bool mirror;
  final List<SculptPoint> points;

  const PaintStroke({
    required this.on,
    this.tool = PaintTool.paint,
    this.colour = 0x9c3a32,
    required this.radius,
    this.opacity = 1,
    this.softness = 0.5,
    this.mirror = false,
    this.points = const [],
  });

  PaintStroke withPoint(SculptPoint p) => PaintStroke(
      on: on,
      tool: tool,
      colour: colour,
      radius: radius,
      opacity: opacity,
      softness: softness,
      mirror: mirror,
      points: [...points, p]);

  String get key => "$on|${tool.name}|$colour|$radius|$opacity|$softness|"
      "$mirror|${points.length}|${Object.hashAll(points)}";

  Map<String, dynamic> toJson() => {
        "on": on,
        if (tool != PaintTool.paint) "tool": tool.name,
        "colour": colour,
        "radius": radius,
        "opacity": opacity,
        "softness": softness,
        if (mirror) "mirror": true,
        "points": [
          for (final p in points)
            for (final v in [p.x, p.y, p.z, p.nx, p.ny, p.nz])
              SculptStroke._round(v)
        ],
      };

  /// fromJson reads what toJson wrote, or null for what is not a stroke.
  static PaintStroke? fromJson(Object? json) {
    if (json is! Map) return null;
    final on = json["on"], r = json["radius"], raw = json["points"];
    if (on is! String || on.isEmpty || r is! num || raw is! List) return null;
    final nums = [
      for (final v in raw)
        if (v is num && v.isFinite) v.toDouble()
    ];
    if (nums.length != raw.length || nums.length % 6 != 0 || nums.isEmpty) {
      return null;
    }
    double n(String k, double d) => json[k] is num && (json[k] as num).isFinite
        ? (json[k] as num).toDouble().clamp(0.0, 1.0)
        : d;
    return PaintStroke(
      on: on,
      tool: PaintTool.fromName(json["tool"]),
      colour: json["colour"] is int ? (json["colour"] as int) & 0xffffff : 0,
      radius: r.toDouble().clamp(0.001, 0.3),
      opacity: n("opacity", 1),
      softness: n("softness", 0.5),
      mirror: json["mirror"] == true,
      points: [
        for (var i = 0; i < nums.length; i += 6)
          SculptPoint(nums[i], nums[i + 1], nums[i + 2], nums[i + 3],
              nums[i + 4], nums[i + 5])
      ],
    );
  }

  @override
  bool operator ==(Object other) => other is PaintStroke && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

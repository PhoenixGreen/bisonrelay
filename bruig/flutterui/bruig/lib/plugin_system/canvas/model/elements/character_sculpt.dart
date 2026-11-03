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

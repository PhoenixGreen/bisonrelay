import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// character_hair.dart is a sketch's hair as strokes, as VRoid draws hair as
// tufts and Moho bends a stroke of its own width: each one growing from a
// point on the scalp -- so it turns with the head, whichever view it is
// seen from -- out and down as long as it is, leaning and curling, as
// wide as it is at its root, its middle and its tip. Strokes come in
// groups -- the fringe, the sides, the top and the back -- each with its
// own length, volume, curl and width over its strokes'.
//
// A stroke is drawn in front of the face where it grows on the side of
// the head towards the reader, and behind the head where it grows on the
// far side: turn the character round and the back hair is in front.

/// HairGroup is a group of strokes.
enum HairGroup {
  fringe("Fringe"),
  sides("Sides"),
  top("Top"),
  back("Back");

  final String label;
  const HairGroup(this.label);

  static HairGroup fromName(String? name) =>
      values.firstWhere((g) => g.name == name, orElse: () => back);
}

/// HairStroke is one stroke of hair.
class HairStroke {
  final HairGroup group;

  /// lon and lat are where it grows on the scalp, in degrees: round the
  /// head from the front -- the character's left positive -- and up from
  /// the middle of it.
  final double lon;
  final double lat;

  /// length is how long it is, in head heights.
  final double length;

  /// lean is how far it sweeps sideways, -1 to 1 of its length, and curl
  /// how far its end turns, -1 to 1.
  final double lean;
  final double curl;

  /// turn is how far it is turned about where it grows, in degrees, as
  /// that side of the head is seen face on: down, as hair falls, at nought,
  /// and round -- towards the character's left on the front -- as it goes
  /// positive. Spiky hair is strokes turned up.
  final double turn;

  /// w0, w1 and w2 are its width at the root, the middle and the tip, in
  /// head heights.
  final double w0;
  final double w1;
  final double w2;

  /// shapedAt is where on the scalp its shape was made for -- lon and lat
  /// -- when it has been moved from there: moved, a stroke keeps its shape
  /// and only grows from somewhere else. Null for where it grows.
  final (double, double)? shapedAt;

  /// spin is how it has been turned about its root as a whole, a rotation
  /// in the head's space as a quaternion -- w, then x, y, z -- so it turns
  /// all the way round, as seen from wherever it was turned, keeping its
  /// shape.
  final List<double> spin;

  static const List<double> noSpin = [1, 0, 0, 0];

  /// bend is how far its curve's two handles -- off the root and off the
  /// tip -- are pulled from where its length, lean and curl put them, as
  /// steps in the head's space before it is turned: x, y, z for the root's,
  /// then the tip's. Pulled by hand on the canvas.
  final List<double> bend;

  static const List<double> noBend = [0, 0, 0, 0, 0, 0];

  const HairStroke(this.group, this.lon, this.lat,
      {this.length = 0.5,
      this.lean = 0,
      this.curl = 0,
      this.turn = 0,
      this.w0 = 0.12,
      this.w1 = 0.13,
      this.w2 = 0.02,
      this.shapedAt,
      this.spin = noSpin,
      this.bend = noBend});

  HairStroke copyWith(
          {HairGroup? group,
          double? lon,
          double? lat,
          double? length,
          double? lean,
          double? curl,
          double? turn,
          double? w0,
          double? w1,
          double? w2,
          (double, double)? shapedAt,
          List<double>? spin,
          List<double>? bend}) =>
      HairStroke(group ?? this.group, lon ?? this.lon,
          (lat ?? this.lat).clamp(-80.0, 90.0),
          length: (length ?? this.length).clamp(0.02, 6.0),
          lean: (lean ?? this.lean).clamp(-1.5, 1.5),
          curl: (curl ?? this.curl).clamp(-1.5, 1.5),
          turn: _wrap(turn ?? this.turn),
          w0: (w0 ?? this.w0).clamp(0.0, 1.0),
          w1: (w1 ?? this.w1).clamp(0.0, 1.0),
          w2: (w2 ?? this.w2).clamp(0.0, 1.0),
          shapedAt: shapedAt ?? this.shapedAt,
          spin: spin == null ? this.spin : _unit(spin),
          bend: bend == null || bend.length != 6 ? this.bend : bend);

  /// mirrored is it on the other side of the head: a turn the other way
  /// round, seen in a mirror.
  HairStroke get mirrored => HairStroke(group, -lon, lat,
      length: length,
      lean: -lean,
      curl: -curl,
      turn: -turn,
      w0: w0,
      w1: w1,
      w2: w2,
      shapedAt: shapedAt == null ? null : (-shapedAt!.$1, shapedAt!.$2),
      spin: [spin[0], spin[1], -spin[2], -spin[3]],
      bend: [-bend[0], bend[1], bend[2], -bend[3], bend[4], bend[5]]);

  static List<double> _unit(List<double> q) {
    if (q.length != 4) return noSpin;
    var n = math.sqrt(q.fold(0.0, (a, v) => a + v * v));
    return n < 1e-9 ? noSpin : [for (var v in q) v / n];
  }

  bool get _spun =>
      (spin[0] - 1).abs() > 1e-9 || spin[1] != 0 || spin[2] != 0 || spin[3] != 0;

  static double _wrap(double degrees) {
    var d = degrees % 360;
    return d > 180 ? d - 360 : d;
  }

  Map<String, dynamic> toJson() => {
        "group": group.name,
        "lon": _r(lon),
        "lat": _r(lat),
        "length": _r(length),
        if (lean != 0) "lean": _r(lean),
        if (curl != 0) "curl": _r(curl),
        if (turn != 0) "turn": _r(turn),
        "w": [_r(w0), _r(w1), _r(w2)],
        if (shapedAt case var at?) "shapedAt": [_r(at.$1), _r(at.$2)],
        if (_spun) "spin": [for (var v in spin) (v * 100000).round() / 100000],
        if (bend.any((v) => v != 0)) "bend": [for (var v in bend) _r(v)],
      };

  static double _r(double v) => (v * 1000).round() / 1000;

  static HairStroke? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var w = json["w"] is List ? json["w"] as List : const [];
    double wAt(int i, double d) =>
        i < w.length && w[i] is num ? (w[i] as num).toDouble() : d;
    return const HairStroke(HairGroup.back, 0, 0).copyWith(
      group: HairGroup.fromName(json["group"] as String?),
      lon: jsonDouble(json["lon"], 0),
      lat: jsonDouble(json["lat"], 0),
      length: jsonDouble(json["length"], 0.5),
      lean: jsonDouble(json["lean"], 0),
      curl: jsonDouble(json["curl"], 0),
      turn: jsonDouble(json["turn"], 0),
      w0: wAt(0, 0.12),
      w1: wAt(1, 0.13),
      w2: wAt(2, 0.02),
      shapedAt: switch (json["shapedAt"]) {
        [num a, num b] => (a.toDouble(), b.toDouble()),
        _ => null,
      },
      bend: json["bend"] is List &&
              (json["bend"] as List).length == 6 &&
              (json["bend"] as List).every((v) => v is num)
          ? [for (var v in json["bend"] as List) (v as num).toDouble()]
          : null,
      spin: switch (json["spin"]) {
        [num a, num b, num c, num d] => [
            a.toDouble(),
            b.toDouble(),
            c.toDouble(),
            d.toDouble()
          ],
        _ => null,
      },
    );
  }
}

/// HairGroupLook is what a group's strokes are made over: longer, fuller,
/// curlier, wider.
class HairGroupLook {
  final double length;
  final double volume;
  final double curl;
  final double width;
  const HairGroupLook(
      {this.length = 1, this.volume = 1, this.curl = 0, this.width = 1});

  static const HairGroupLook plain = HairGroupLook();

  bool get isPlain => length == 1 && volume == 1 && curl == 0 && width == 1;

  HairGroupLook copyWith(
          {double? length, double? volume, double? curl, double? width}) =>
      HairGroupLook(
          length: (length ?? this.length).clamp(0.1, 4.0),
          volume: (volume ?? this.volume).clamp(0.0, 3.0),
          curl: (curl ?? this.curl).clamp(-1.0, 1.0),
          width: (width ?? this.width).clamp(0.2, 3.0));

  Map<String, dynamic> toJson() =>
      {"length": length, "volume": volume, "curl": curl, "width": width};

  factory HairGroupLook.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return plain;
    return const HairGroupLook().copyWith(
        length: jsonDouble(json["length"], 1),
        volume: jsonDouble(json["volume"], 1),
        curl: jsonDouble(json["curl"], 0),
        width: jsonDouble(json["width"], 1));
  }
}

/// HairRig is the hair as strokes, and each group's look.
class HairRig {
  final String name;
  final List<HairStroke> strokes;
  final Map<HairGroup, HairGroupLook> groups;
  const HairRig(this.name, this.strokes, [this.groups = const {}]);

  HairGroupLook lookOf(HairGroup g) => groups[g] ?? HairGroupLook.plain;

  /// inGroup is the strokes of [g], with where each is in [strokes].
  List<(int, HairStroke)> inGroup(HairGroup g) => [
        for (var (i, s) in strokes.indexed)
          if (s.group == g) (i, s),
      ];

  HairRig withStroke(int i, HairStroke s) =>
      HairRig(name, [...strokes]..[i] = s, groups);

  HairRig withGroup(HairGroup g, HairGroupLook l) =>
      HairRig(name, strokes, {...groups, g: l});

  /// withAdded is this with a stroke beside [i] -- like it, a little way
  /// round the head -- and its index.
  (HairRig, int) withAdded(int i) {
    var s = strokes[i];
    var next = [...strokes]..insert(i + 1, s.copyWith(lon: s.lon + 9));
    return (HairRig(name, next, groups), i + 1);
  }

  HairRig without(int i) => HairRig(name, [...strokes]..removeAt(i), groups);

  Map<String, dynamic> toJson() => {
        "name": name,
        "strokes": [for (var s in strokes) s.toJson()],
        if (groups.values.any((g) => !g.isPlain))
          "groups": {
            for (var e in groups.entries)
              if (!e.value.isPlain) e.key.name: e.value.toJson()
          },
      };

  static HairRig? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return HairRig(
      jsonString(json["name"], "Strokes"),
      [
        for (var s in json["strokes"] as List? ?? const [])
          if (HairStroke.fromJson(s) case var stroke?) stroke,
      ],
      {
        if (json["groups"] case Map raw)
          for (var e in raw.entries)
            HairGroup.fromName("${e.key}"): HairGroupLook.fromJson(e.value),
      },
    );
  }
}

/// hairPresets are hair made of strokes to start from.
List<HairRig> get hairPresets => [_short(), _messy(), _spiky(), _bob(), _long()];

List<HairStroke> _fan(
    HairGroup g, int n, double lonFrom, double lonTo, double lat, double length,
    {double lean = 0,
    double curl = 0,
    double w0 = 0.12,
    double w1 = 0.13,
    double w2 = 0.02,
    double jitter = 0,
    int seed = 1}) {
  var rnd = math.Random(seed);
  return [
    for (var i = 0; i < n; i++)
      () {
        var t = n == 1 ? 0.5 : i / (n - 1);
        var lon = lonFrom + (lonTo - lonFrom) * t;
        var j = jitter == 0 ? 0 : (rnd.nextDouble() - 0.5) * jitter;
        return HairStroke(g, lon, lat,
            length: length * (1 + j),
            // Leaning out, the way round the head it grows.
            lean: lean * math.sin(lon * math.pi / 180),
            curl: curl * (lon >= 0 ? 1 : -1),
            w0: w0,
            w1: w1,
            w2: w2);
      }(),
  ];
}

HairRig _short() => HairRig("Short", [
      ..._fan(HairGroup.back, 11, 100, 260, 28, 0.5,
          lean: 0.15, w0: 0.26, w1: 0.24, w2: 0.04, jitter: 0.2, seed: 21),
      ..._fan(HairGroup.sides, 2, -100, -72, 34, 0.42,
          lean: 0.05, w0: 0.24, w1: 0.2, w2: 0.03, seed: 23),
      ..._fan(HairGroup.sides, 2, 72, 100, 34, 0.42,
          lean: 0.05, w0: 0.24, w1: 0.2, w2: 0.03, seed: 25),
      // A small crown, lying flat: the rest of the top is the hair's volume.
      const HairStroke(HairGroup.top, 0, 84,
          length: 0.1, turn: 180, w0: 0.14, w1: 0.12, w2: 0.02),
      ..._fan(HairGroup.fringe, 6, -48, 48, 60, 0.42,
          lean: 0.22, w0: 0.22, w1: 0.2, w2: 0.03, jitter: 0.2, seed: 27),
    ]);

/// _messy is the anime boy's: a full dome over the crown, a fringe of
/// pointed clumps down to the eyes, the sides to the jaw and a cowlick
/// turned up off the crown.
HairRig _messy() => HairRig("Messy", [
      ..._fan(HairGroup.back, 13, 95, 265, 28, 0.72,
          lean: 0.22,
          curl: 0.1,
          w0: 0.27,
          w1: 0.22,
          w2: 0.0,
          jitter: 0.35,
          seed: 3),
      ..._fan(HairGroup.sides, 3, -112, -68, 34, 0.7,
          lean: 0.08,
          curl: 0.15,
          w0: 0.24,
          w1: 0.2,
          w2: 0.0,
          jitter: 0.25,
          seed: 5),
      ..._fan(HairGroup.sides, 3, 68, 112, 34, 0.7,
          lean: 0.08,
          curl: 0.15,
          w0: 0.24,
          w1: 0.2,
          w2: 0.0,
          jitter: 0.25,
          seed: 7),
      // A cowlick: one short tuft turned up off the crown.
      const HairStroke(HairGroup.top, 8, 86,
          length: 0.15, curl: 0.6, turn: 170, w0: 0.045, w1: 0.04, w2: 0.0),
      ..._fan(HairGroup.fringe, 7, -52, 52, 60, 0.72,
          lean: 0.2,
          curl: 0.12,
          w0: 0.22,
          w1: 0.19,
          w2: 0.0,
          jitter: 0.3,
          seed: 11),
    ]);

/// _spiky is a shōnen lead's: the crown in points turned up and back, the
/// fringe in a few sharp locks.
HairRig _spiky() => HairRig("Spiky", [
      ..._fan(HairGroup.back, 9, 100, 260, 30, 0.6,
          lean: 0.3, w0: 0.26, w1: 0.2, w2: 0.0, jitter: 0.3, seed: 13),
      for (var (i, lon) in [-80.0, -45.0, -15.0, 15.0, 45.0, 80.0].indexed)
        HairStroke(HairGroup.top, lon, 66 + (i % 2) * 8,
            length: 0.5 + 0.12 * ((i * 5) % 3),
            turn: 180 - lon * 0.9,
            w0: 0.24,
            w1: 0.18,
            w2: 0.0),
      ..._fan(HairGroup.sides, 2, -105, -75, 32, 0.55,
          lean: 0.1, w0: 0.22, w1: 0.16, w2: 0.0, seed: 15),
      ..._fan(HairGroup.sides, 2, 75, 105, 32, 0.55,
          lean: 0.1, w0: 0.22, w1: 0.16, w2: 0.0, seed: 17),
      ..._fan(HairGroup.fringe, 5, -45, 45, 60, 0.62,
          lean: 0.35, curl: 0.2, w0: 0.22, w1: 0.17, w2: 0.0, jitter: 0.3, seed: 19),
    ]);

/// hairForStyle is the hair a style that draws hair in strokes draws [style]
/// as -- spiky in a style that spikes it, combed into rounded locks in a
/// [soft] one -- grown as [look] says: fuller,
/// longer, a longer fringe, parted further over -- and long hair as long
/// for a body [headsTall] heads tall. Null for hair a style
/// draws its own way: a bun, curls, none.
HairRig? hairForStyle(HairStyle style, Appearance look,
    {bool spiky = false, bool soft = false, double headsTall = 6}) {
  var base = switch (style) {
    HairStyle.short => spiky ? _spiky() : (soft ? _short() : _messy()),
    HairStyle.long => _long(),
    _ => null,
  };
  if (base == null) return null;
  if (soft) {
    // A cartoon's hair: the same locks with rounded ends, combed.
    // The fringe shorter and swept over to one side, clear of the eyes.
    base = HairRig(base.name, [
      for (var s in base.strokes)
        s.copyWith(
            w2: math.max(s.w2, s.w1 * 0.3),
            curl: s.curl * 0.5,
            w0: s.w0 * 1.15,
            w1: s.w1 * 1.15,
            length: s.group == HairGroup.fringe ? s.length * 0.85 : null,
            lean: s.group == HairGroup.fringe ? s.lean * 0.3 + 0.45 : null),
    ]);
  }
  // A lower hairline grows the fringe from lower on the brow.
  var hairline = look[Look.hairline];
  if (hairline != 0) {
    base = HairRig(base.name, [
      for (var s in base.strokes)
        s.group == HairGroup.fringe ? s.copyWith(lat: s.lat - 10 * hairline) : s,
    ]);
  }
  var volume = 1 + 0.5 * look[Look.hairVolume];
  // Long hair falls as far down the back on a short body as on a tall
  // one: a chibi's is not as long as the rest of it.
  var body = style == HairStyle.long ? ((headsTall - 1) / 5).clamp(0.3, 1.2) : 1.0;
  var length = (1 + 0.6 * look[Look.hairLength]) * body;
  var fringe = 1 + 0.5 * look[Look.fringe];
  return HairRig(base.name, base.strokes, {
    for (var g in HairGroup.values)
      g: HairGroupLook(
          volume: volume,
          length: switch (g) {
            HairGroup.back || HairGroup.sides => length,
            HairGroup.fringe => fringe,
            HairGroup.top => 1,
          },
          curl: g == HairGroup.fringe ? 0.4 * look[Look.parting] : 0),
  });
}

HairRig _bob() => HairRig("Bob", [
      ..._fan(HairGroup.back, 9, 100, 260, 15, 0.95,
          lean: 0.25, curl: 0.3, w0: 0.18, w1: 0.2, w2: 0.08),
      ..._fan(HairGroup.sides, 3, -110, -70, 20, 0.9,
          lean: 0.15, curl: 0.35, w0: 0.15, w1: 0.17, w2: 0.07),
      ..._fan(HairGroup.sides, 3, 70, 110, 20, 0.9,
          lean: 0.15, curl: 0.35, w0: 0.15, w1: 0.17, w2: 0.07),
      ..._fan(HairGroup.top, 2, -15, 15, 78, 0.3, w0: 0.18, w1: 0.18),
      ..._fan(HairGroup.fringe, 7, -45, 45, 52, 0.4,
          w0: 0.13, w1: 0.13, w2: 0.06),
    ]);

HairRig _long() => HairRig("Long", [
      // A small crown, lying flat: the rest of the top is the hair's volume.
      const HairStroke(HairGroup.top, 0, 84,
          length: 0.1, turn: 180, w0: 0.14, w1: 0.12, w2: 0.02),
      ..._fan(HairGroup.back, 11, 95, 265, 15, 2.2,
          lean: 0.3, curl: 0.2, w0: 0.2, w1: 0.22, w2: 0.05),
      ..._fan(HairGroup.sides, 3, -115, -70, 20, 1.9,
          lean: 0.2, curl: 0.25, w0: 0.16, w1: 0.17, w2: 0.04),
      ..._fan(HairGroup.sides, 3, 70, 115, 20, 1.9,
          lean: 0.2, curl: 0.25, w0: 0.16, w1: 0.17, w2: 0.04),
      ..._fan(HairGroup.fringe, 4, -55, -5, 55, 0.55,
          lean: 0.4, curl: 0.3, w0: 0.13, w1: 0.13, w2: 0.03),
      ..._fan(HairGroup.fringe, 4, 5, 55, 55, 0.55,
          lean: 0.4, curl: 0.3, w0: 0.13, w1: 0.13, w2: 0.03),
    ]);

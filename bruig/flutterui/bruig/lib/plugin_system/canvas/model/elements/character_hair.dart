import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

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

  /// w0, w1 and w2 are its width at the root, the middle and the tip, in
  /// head heights.
  final double w0;
  final double w1;
  final double w2;

  const HairStroke(this.group, this.lon, this.lat,
      {this.length = 0.5,
      this.lean = 0,
      this.curl = 0,
      this.w0 = 0.12,
      this.w1 = 0.13,
      this.w2 = 0.02});

  HairStroke copyWith(
          {HairGroup? group,
          double? lon,
          double? lat,
          double? length,
          double? lean,
          double? curl,
          double? w0,
          double? w1,
          double? w2}) =>
      HairStroke(group ?? this.group, lon ?? this.lon, (lat ?? this.lat).clamp(-80.0, 90.0),
          length: (length ?? this.length).clamp(0.02, 6.0),
          lean: (lean ?? this.lean).clamp(-1.5, 1.5),
          curl: (curl ?? this.curl).clamp(-1.5, 1.5),
          w0: (w0 ?? this.w0).clamp(0.0, 1.0),
          w1: (w1 ?? this.w1).clamp(0.0, 1.0),
          w2: (w2 ?? this.w2).clamp(0.0, 1.0));

  /// mirrored is it on the other side of the head.
  HairStroke get mirrored => copyWith(lon: -lon, lean: -lean, curl: -curl);

  Map<String, dynamic> toJson() => {
        "group": group.name,
        "lon": _r(lon),
        "lat": _r(lat),
        "length": _r(length),
        if (lean != 0) "lean": _r(lean),
        if (curl != 0) "curl": _r(curl),
        "w": [_r(w0), _r(w1), _r(w2)],
      };

  static double _r(double v) => (v * 1000).round() / 1000;

  static HairStroke? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var w = json["w"] is List ? json["w"] as List : const [];
    double wAt(int i, double d) => i < w.length && w[i] is num ? (w[i] as num).toDouble() : d;
    return const HairStroke(HairGroup.back, 0, 0).copyWith(
      group: HairGroup.fromName(json["group"] as String?),
      lon: jsonDouble(json["lon"], 0),
      lat: jsonDouble(json["lat"], 0),
      length: jsonDouble(json["length"], 0.5),
      lean: jsonDouble(json["lean"], 0),
      curl: jsonDouble(json["curl"], 0),
      w0: wAt(0, 0.12),
      w1: wAt(1, 0.13),
      w2: wAt(2, 0.02),
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
  const HairGroupLook({this.length = 1, this.volume = 1, this.curl = 0, this.width = 1});

  static const HairGroupLook plain = HairGroupLook();

  bool get isPlain => length == 1 && volume == 1 && curl == 0 && width == 1;

  HairGroupLook copyWith({double? length, double? volume, double? curl, double? width}) =>
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

  HairRig withGroup(HairGroup g, HairGroupLook l) => HairRig(name, strokes, {...groups, g: l});

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
          for (var e in raw.entries) HairGroup.fromName("${e.key}"): HairGroupLook.fromJson(e.value),
      },
    );
  }
}

/// hairPresets are hair made of strokes to start from.
List<HairRig> get hairPresets => [_short(), _messy(), _bob(), _long()];

List<HairStroke> _fan(HairGroup g, int n, double lonFrom, double lonTo, double lat,
    double length,
    {double lean = 0, double curl = 0, double w0 = 0.12, double w1 = 0.13, double w2 = 0.02,
    double jitter = 0, int seed = 1}) {
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
      ..._fan(HairGroup.back, 9, 100, 260, 20, 0.45, lean: 0.15, w0: 0.16, w1: 0.17),
      ..._fan(HairGroup.sides, 2, -95, -70, 25, 0.38, lean: 0.05),
      ..._fan(HairGroup.sides, 2, 70, 95, 25, 0.38, lean: 0.05),
      ..._fan(HairGroup.top, 3, -30, 30, 72, 0.32, w0: 0.16, w1: 0.16),
      ..._fan(HairGroup.fringe, 5, -40, 40, 52, 0.28, lean: 0.2, w0: 0.12, w1: 0.12),
    ]);

/// _messy is the anime boy's: a pointed fringe over the eyes, spiky at the
/// back and sides, a cowlick on the crown.
HairRig _messy() => HairRig("Messy", [
      ..._fan(HairGroup.back, 11, 95, 265, 15, 0.55,
          lean: 0.35, curl: 0.2, w0: 0.17, w1: 0.15, w2: 0.0, jitter: 0.5, seed: 3),
      ..._fan(HairGroup.sides, 3, -105, -65, 22, 0.5,
          lean: 0.1, curl: 0.2, w0: 0.14, w1: 0.12, w2: 0.0, jitter: 0.3, seed: 5),
      ..._fan(HairGroup.sides, 3, 65, 105, 22, 0.5,
          lean: 0.1, curl: 0.2, w0: 0.14, w1: 0.12, w2: 0.0, jitter: 0.3, seed: 7),
      // A cowlick: one short tuft standing up off the crown.
      ..._fan(HairGroup.top, 2, -10, 15, 84, 0.16, lean: 0.6, curl: 0.5, w0: 0.06, w1: 0.05, w2: 0.0),
      ..._fan(HairGroup.fringe, 7, -48, 48, 55, 0.58,
          lean: 0.25, curl: 0.15, w0: 0.14, w1: 0.12, w2: 0.0, jitter: 0.35, seed: 11),
    ]);

HairRig _bob() => HairRig("Bob", [
      ..._fan(HairGroup.back, 9, 100, 260, 15, 0.95, lean: 0.25, curl: 0.3, w0: 0.18, w1: 0.2, w2: 0.08),
      ..._fan(HairGroup.sides, 3, -110, -70, 20, 0.9, lean: 0.15, curl: 0.35, w0: 0.15, w1: 0.17, w2: 0.07),
      ..._fan(HairGroup.sides, 3, 70, 110, 20, 0.9, lean: 0.15, curl: 0.35, w0: 0.15, w1: 0.17, w2: 0.07),
      ..._fan(HairGroup.top, 2, -15, 15, 78, 0.3, w0: 0.18, w1: 0.18),
      ..._fan(HairGroup.fringe, 7, -45, 45, 52, 0.4, w0: 0.13, w1: 0.13, w2: 0.06),
    ]);

HairRig _long() => HairRig("Long", [
      ..._fan(HairGroup.back, 11, 95, 265, 15, 2.2, lean: 0.3, curl: 0.2, w0: 0.2, w1: 0.22, w2: 0.05),
      ..._fan(HairGroup.sides, 3, -115, -70, 20, 1.9, lean: 0.2, curl: 0.25, w0: 0.16, w1: 0.17, w2: 0.04),
      ..._fan(HairGroup.sides, 3, 70, 115, 20, 1.9, lean: 0.2, curl: 0.25, w0: 0.16, w1: 0.17, w2: 0.04),
      ..._fan(HairGroup.top, 2, -15, 15, 78, 0.35, w0: 0.18, w1: 0.18),
      ..._fan(HairGroup.fringe, 4, -55, -5, 55, 0.55, lean: 0.4, curl: 0.3, w0: 0.13, w1: 0.13, w2: 0.03),
      ..._fan(HairGroup.fringe, 4, 5, 55, 55, 0.55, lean: 0.4, curl: 0.3, w0: 0.13, w1: 0.13, w2: 0.03),
    ]);

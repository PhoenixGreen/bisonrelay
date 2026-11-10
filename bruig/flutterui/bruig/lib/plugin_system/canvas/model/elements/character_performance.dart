import 'package:bruig/plugin_system/canvas/model/lip_sync.dart';

// character_performance.dart is what a new 3D character does in one scene
// of the canvas: how it stands and leans, the motions it plays and when, the
// walks that carry it across the page, its feeling and mouth, the line it
// says, what it does by itself, and its shadow. The character itself -- its
// body, clothes, face and how it moves -- is its design (character_design.
// dart); this is the scene's. Times are in seconds on the scene's timeline.

/// performanceMotions are the motions a scene can add, by name.
const List<String> performanceMotions = [
  "Wave",
  "Nod",
  "Shake head",
  "Clap",
  "Bow",
  "Jump",
  "Dance",
  "Look around",
  "Walk",
  "Run",
  // Ken, 2026-11-10: "a character can punch and kick" -- and in a game,
  // the punch and kick actions play them (see canvas_game.dart).
  "Punch",
  "Kick",
];

/// performanceWearing are the outfits a scene can put it in, by name.
const List<String> performanceWearing = [
  "As designed",
  "Underwear only",
  "Swimwear",
  "Casual",
];

/// performanceMouths are the mouth shapes it can hold, with their names.
const List<(String, String)> performanceMouths = [
  ("rest", "Rest"),
  ("A", "A · ah"),
  ("I", "I · ee"),
  ("U", "U · oo"),
  ("E", "E · eh"),
  ("O", "O · oh"),
];

/// performanceShadows are the shadows under it.
const List<String> performanceShadows = ["None", "Soft", "Hard"];

/// _same stands for a value not given to copyWith, where null means
/// something.
const Object _same = Object();

double _num(Object? v, double d, double lo, double hi) =>
    v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : d;

/// MotionClip3d is one motion on the timeline: what, from when and for how
/// long, how fast and how much, mirrored left for right; a walk or a run
/// with a [dir] carries the character across the page that way (see
/// [CharacterPerformance.travelAt]). Immutable.
class MotionClip3d {
  final String kind;
  final double start, length, speed, strength;
  final bool mirror;

  /// dir is which way a walk or run goes across the page as it is seen: 1
  /// to the right, -1 to the left, nought for one on the spot.
  final int dir;

  const MotionClip3d({
    required this.kind,
    required this.start,
    this.length = 2,
    this.speed = 1,
    this.strength = 1,
    this.mirror = false,
    this.dir = 0,
  });

  double get end => start + length;

  /// weightAt is how much of it plays at [t]: nothing outside it, faded in
  /// and out over its first and last 0.3 s -- a strike over 0.06 s: it
  /// winds up and comes back by itself, and faded as slowly, a punch
  /// (0.45 s) never got to three quarters of itself.
  double weightAt(double t) {
    if (t < start || t > end) return 0;
    var fade = kind == "Punch" || kind == "Kick" ? 0.06 : 0.3;
    return [1.0, (t - start) / fade, (end - t) / fade]
        .reduce((a, b) => a < b ? a : b)
        .clamp(0.0, 1.0);
  }

  MotionClip3d copyWith(
          {double? start,
          double? length,
          double? speed,
          double? strength,
          bool? mirror}) =>
      MotionClip3d(
          kind: kind,
          start: start ?? this.start,
          length: length ?? this.length,
          speed: speed ?? this.speed,
          strength: strength ?? this.strength,
          mirror: mirror ?? this.mirror,
          dir: dir);

  Map<String, dynamic> toJson() => {
        "kind": kind,
        "start": start,
        "length": length,
        if (speed != 1) "speed": speed,
        if (strength != 1) "strength": strength,
        if (mirror) "mirror": true,
        if (dir != 0) "dir": dir,
      };

  static MotionClip3d? fromJson(Object? j) {
    if (j is! Map || !performanceMotions.contains(j["kind"])) return null;
    return MotionClip3d(
      kind: j["kind"] as String,
      start: _num(j["start"], 0, 0, 3600),
      length: _num(j["length"], 2, 0.3, 3600),
      speed: _num(j["speed"], 1, 0.25, 3),
      strength: _num(j["strength"], 1, 0, 1.5),
      mirror: j["mirror"] == true,
      dir: j["dir"] is int ? (j["dir"] as int).clamp(-1, 1) : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MotionClip3d &&
      other.kind == kind &&
      other.start == start &&
      other.length == length &&
      other.speed == speed &&
      other.strength == strength &&
      other.mirror == mirror &&
      other.dir == dir;

  @override
  int get hashCode =>
      Object.hash(kind, start, length, speed, strength, mirror, dir);
}

/// PoseKey holds a pose and a feeling from its time until the next key.
/// Immutable.
class PoseKey {
  final double t;
  final String stance;
  final double lean, tilt;
  final String feeling;
  const PoseKey(
      {required this.t,
      this.stance = "Relaxed",
      this.lean = 0,
      this.tilt = 0,
      this.feeling = "Neutral"});

  PoseKey copyWith(
          {double? t,
          String? stance,
          double? lean,
          double? tilt,
          String? feeling}) =>
      PoseKey(
          t: t ?? this.t,
          stance: stance ?? this.stance,
          lean: lean ?? this.lean,
          tilt: tilt ?? this.tilt,
          feeling: feeling ?? this.feeling);

  Map<String, dynamic> toJson() => {
        "t": t,
        "stance": stance,
        if (lean != 0) "lean": lean,
        if (tilt != 0) "tilt": tilt,
        "feeling": feeling,
      };

  static PoseKey? fromJson(Object? j) {
    if (j is! Map) return null;
    return PoseKey(
      t: _num(j["t"], 0, 0, 3600),
      stance: j["stance"] is String ? j["stance"] as String : "Relaxed",
      lean: _num(j["lean"], 0, -1, 1),
      tilt: _num(j["tilt"], 0, -1, 1),
      feeling: j["feeling"] is String ? j["feeling"] as String : "Neutral",
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PoseKey &&
      other.t == t &&
      other.stance == stance &&
      other.lean == lean &&
      other.tilt == tilt &&
      other.feeling == feeling;

  @override
  int get hashCode => Object.hash(t, stance, lean, tilt, feeling);
}

/// MouthAt is one mouth of a lip sync, held from [t] seconds until the
/// next.
typedef MouthAt = ({double t, MouthShape shape});

/// CharacterPerformance is what it does in a scene. Immutable.
class CharacterPerformance {
  final String wearing;

  /// stance, lean and tilt are how it stands between keys; null stance for
  /// as designed.
  final String? stance;
  final double lean, tilt;
  final List<PoseKey> keys;
  final List<MotionClip3d> clips;

  /// feeling is the expression it wears, by name, between keys; null for
  /// as designed. mixTo and mixAmount move it part of the way to another.
  final String? feeling;
  final String mixTo;
  final double mixAmount;

  /// mouth is a mouth shape held, "rest" for none.
  final String mouth;
  final bool blink, breathe, glance;
  final String shadow;

  /// line is a line it says, from [lineAt] seconds: its mouth moves to it.
  final String line;
  final double lineAt;

  /// mouths are its lip sync, from a voice-over: each mouth held until the
  /// next (lip_sync.dart).
  final List<MouthAt> mouths;

  /// startsAt is where in its box its walks start from: -1 the left edge,
  /// 1 the right, nought the middle.
  final int startsAt;

  /// speaksFor is the mixer channel it speaks for, by key, or empty: a slot
  /// played on it -- a narrator's line -- moves its mouth and shows it while
  /// it is heard.
  final String speaksFor;

  const CharacterPerformance({
    this.wearing = "As designed",
    this.stance,
    this.lean = 0,
    this.tilt = 0,
    this.keys = const [],
    this.clips = const [],
    this.feeling,
    this.mixTo = "Happy",
    this.mixAmount = 0,
    this.mouth = "rest",
    this.blink = true,
    this.breathe = true,
    this.glance = true,
    this.shadow = "Soft",
    this.line = "",
    this.lineAt = 0,
    this.mouths = const [],
    this.speaksFor = "",
    this.startsAt = 0,
  });

  /// copyWith is this with what is given changed; [stance] and [feeling]
  /// may be given as null, for as designed.
  CharacterPerformance copyWith({
    String? wearing,
    Object? stance = _same,
    double? lean,
    double? tilt,
    List<PoseKey>? keys,
    List<MotionClip3d>? clips,
    Object? feeling = _same,
    String? mixTo,
    double? mixAmount,
    String? mouth,
    bool? blink,
    bool? breathe,
    bool? glance,
    String? shadow,
    String? line,
    double? lineAt,
    List<MouthAt>? mouths,
    String? speaksFor,
    int? startsAt,
  }) =>
      CharacterPerformance(
        wearing: wearing ?? this.wearing,
        stance: identical(stance, _same) ? this.stance : stance as String?,
        lean: lean ?? this.lean,
        tilt: tilt ?? this.tilt,
        keys: keys ?? this.keys,
        clips: clips ?? this.clips,
        feeling: identical(feeling, _same) ? this.feeling : feeling as String?,
        mixTo: mixTo ?? this.mixTo,
        mixAmount: mixAmount ?? this.mixAmount,
        mouth: mouth ?? this.mouth,
        blink: blink ?? this.blink,
        breathe: breathe ?? this.breathe,
        glance: glance ?? this.glance,
        shadow: shadow ?? this.shadow,
        line: line ?? this.line,
        lineAt: lineAt ?? this.lineAt,
        mouths: mouths ?? this.mouths,
        speaksFor: speaksFor ?? this.speaksFor,
        startsAt: startsAt ?? this.startsAt,
      );

  /// mouthAt is the lip sync's mouth at [t] seconds, or null before its
  /// first.
  MouthShape? mouthAt(double t) {
    MouthShape? out;
    for (final m in mouths) {
      if (m.t > t + 1e-6) break;
      out = m.shape;
    }
    return out;
  }

  /// withMouths is this with [mouths] laid between [from] and [to] seconds
  /// -- those already there kept outside it -- or, with neither, in place
  /// of them all.
  CharacterPerformance withMouths(List<MouthAt> mouths,
      {double? from, double? to}) {
    final kept = from == null && to == null
        ? const <MouthAt>[]
        : [
            for (final m in this.mouths)
              if (m.t < (from ?? double.negativeInfinity) ||
                  m.t > (to ?? double.infinity))
                m
          ];
    return copyWith(
        mouths: [...kept, ...mouths]..sort((a, b) => a.t.compareTo(b.t)));
  }

  /// keyAt is the key holding at [t], or null before the first.
  PoseKey? keyAt(double t) {
    PoseKey? k;
    for (final x in keys) {
      if (x.t <= t + 1e-6) k = x;
    }
    return k;
  }

  /// clipAt is the motion playing at [t] -- the last that does -- and how
  /// much of it.
  (MotionClip3d, double)? clipAt(double t) {
    (MotionClip3d, double)? out;
    for (final c in clips) {
      final w = c.weightAt(t);
      if (w > 0) out = (c, w);
    }
    return out;
  }

  /// travelAt is how far the walks have carried it across the page by [t],
  /// in metres of its own body ([pace] metres a second for a walk at speed
  /// one), and how far it is turned to face the way it goes: a quarter turn
  /// at full weight.
  ({double x, double turn}) travelAt(
      double t, double Function(MotionClip3d) pace) {
    var x = 0.0, turn = 0.0;
    for (final c in clips) {
      if (c.dir == 0) continue;
      x += c.dir * pace(c) * (t - c.start).clamp(0.0, c.length);
      turn += c.dir * c.weightAt(t);
    }
    return (x: x.clamp(-2.6, 2.6), turn: turn);
  }

  bool get isEmpty => this == const CharacterPerformance();

  Map<String, dynamic> toJson() => {
        if (wearing != "As designed") "wearing": wearing,
        if (stance != null) "stance": stance,
        if (lean != 0) "lean": lean,
        if (tilt != 0) "tilt": tilt,
        if (keys.isNotEmpty) "keys": [for (final k in keys) k.toJson()],
        if (clips.isNotEmpty) "clips": [for (final c in clips) c.toJson()],
        if (feeling != null) "feeling": feeling,
        if (mixTo != "Happy") "mixTo": mixTo,
        if (mixAmount != 0) "mixAmount": mixAmount,
        if (mouth != "rest") "mouth": mouth,
        if (!blink) "blink": false,
        if (!breathe) "breathe": false,
        if (!glance) "glance": false,
        if (shadow != "Soft") "shadow": shadow,
        if (line.isNotEmpty) "line": line,
        if (lineAt != 0) "lineAt": lineAt,
        if (mouths.isNotEmpty)
          "mouths": [
            for (final m in mouths) [m.t, m.shape.name]
          ],
        if (speaksFor.isNotEmpty) "speaksFor": speaksFor,
        if (startsAt != 0) "startsAt": startsAt,
      };

  static CharacterPerformance fromJson(Object? j, {String? feeling}) {
    if (j is! Map) return CharacterPerformance(feeling: feeling);
    return CharacterPerformance(
      wearing: performanceWearing.contains(j["wearing"])
          ? j["wearing"] as String
          : "As designed",
      stance: j["stance"] is String ? j["stance"] as String : null,
      lean: _num(j["lean"], 0, -1, 1),
      tilt: _num(j["tilt"], 0, -1, 1),
      keys: [
        for (final k in (j["keys"] is List ? j["keys"] as List : const []))
          if (PoseKey.fromJson(k) case final x?) x
      ]..sort((a, b) => a.t.compareTo(b.t)),
      clips: [
        for (final c in (j["clips"] is List ? j["clips"] as List : const []))
          if (MotionClip3d.fromJson(c) case final x?) x
      ],
      feeling: j["feeling"] is String ? j["feeling"] as String : feeling,
      mixTo: j["mixTo"] is String ? j["mixTo"] as String : "Happy",
      mixAmount: _num(j["mixAmount"], 0, 0, 1),
      mouth: performanceMouths.any((m) => m.$1 == j["mouth"])
          ? j["mouth"] as String
          : "rest",
      blink: j["blink"] != false,
      breathe: j["breathe"] != false,
      glance: j["glance"] != false,
      shadow: performanceShadows.contains(j["shadow"])
          ? j["shadow"] as String
          : "Soft",
      line: j["line"] is String ? j["line"] as String : "",
      lineAt: _num(j["lineAt"], 0, 0, 3600),
      mouths: [
        for (final m in (j["mouths"] is List ? j["mouths"] as List : const []))
          if (m is List && m.length == 2 && m[0] is num && m[1] is String)
            (
              t: _num(m[0], 0, -3600, 3600),
              shape: MouthShape.fromName(m[1] as String)
            )
      ]..sort((a, b) => a.t.compareTo(b.t)),
      speaksFor: j["speaksFor"] is String ? j["speaksFor"] as String : "",
      startsAt: j["startsAt"] is int ? (j["startsAt"] as int).clamp(-1, 1) : 0,
    );
  }

  static bool _sameList<T>(List<T> a, List<T> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  bool operator ==(Object other) =>
      other is CharacterPerformance &&
      other.wearing == wearing &&
      other.stance == stance &&
      other.lean == lean &&
      other.tilt == tilt &&
      _sameList(other.keys, keys) &&
      _sameList(other.clips, clips) &&
      other.feeling == feeling &&
      other.mixTo == mixTo &&
      other.mixAmount == mixAmount &&
      other.mouth == mouth &&
      other.blink == blink &&
      other.breathe == breathe &&
      other.glance == glance &&
      other.shadow == shadow &&
      other.line == line &&
      other.lineAt == lineAt &&
      _sameList(other.mouths, mouths) &&
      other.speaksFor == speaksFor &&
      other.startsAt == startsAt;

  @override
  int get hashCode => Object.hash(
      wearing,
      stance,
      lean,
      tilt,
      keys.length,
      clips.length,
      feeling,
      mixTo,
      mixAmount,
      mouth,
      blink,
      breathe,
      glance,
      shadow,
      line,
      lineAt,
      mouths.length,
      speaksFor,
      startsAt);
}

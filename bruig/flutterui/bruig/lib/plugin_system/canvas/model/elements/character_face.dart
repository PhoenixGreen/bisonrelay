// character_face.dart is a new 3D character's face, as the Character
// Studio's Face step sets it: an expression made from the face's own shapes,
// region by region, where the eyes look, how the head tilts, a blush, and
// what the face does by itself. Every VRoid face has the same shapes
// (Fcl_BRW_*, Fcl_EYE_*, Fcl_MTH_*, Fcl_HA_*), so an expression is a mix of
// them, by their names after "Fcl_": "EYE_Joy".

/// faceUnits are the face's shapes, region by region, with their names.
const Map<String, List<(String, String)>> faceUnits = {
  "brows": [
    ("BRW_Angry", "Frown"),
    ("BRW_Joy", "Happy"),
    ("BRW_Sorrow", "Worried"),
    ("BRW_Surprised", "Raised"),
    ("BRW_Fun", "Playful"),
  ],
  "eyes": [
    ("EYE_Close", "Closed"),
    ("EYE_Close_L", "Left closed"),
    ("EYE_Close_R", "Right closed"),
    ("EYE_Joy", "Smiling"),
    ("EYE_Joy_L", "Left smiling"),
    ("EYE_Joy_R", "Right smiling"),
    ("EYE_Angry", "Narrowed"),
    ("EYE_Sorrow", "Sad"),
    ("EYE_Surprised", "Wide"),
    ("EYE_Natural", "Relaxed"),
    ("EYE_Extra", "Sparkle"),
  ],
  "mouth": [
    ("MTH_Joy", "Smile"),
    ("MTH_Fun", "Grin"),
    ("MTH_Sorrow", "Frown"),
    ("MTH_Angry", "Snarl"),
    ("MTH_Surprised", "Gasp"),
    ("MTH_Up", "Corners up"),
    ("MTH_Down", "Corners down"),
    ("MTH_Neutral", "Pressed"),
    ("MTH_A", "Open, A"),
    ("MTH_I", "Wide, I"),
    ("MTH_U", "Round, U"),
    ("MTH_E", "E"),
    ("MTH_O", "O"),
  ],
  "teeth": [
    ("HA_Fung1", "Fang"),
    ("HA_Fung1_Up", "Fang above"),
    ("HA_Fung1_Low", "Fang below"),
    ("HA_Fung2", "Two fangs"),
    ("HA_Fung2_Up", "Two above"),
    ("HA_Fung2_Low", "Two below"),
  ],
};

/// FaceMix is one expression: how much of each of the face's shapes, the
/// blush, where the eyes look (-1 to 1 across and up, as the viewer sees
/// it) and how far the head tilts (-1 to 1). Immutable.
class FaceMix {
  final Map<String, double> w;
  final double blush, gazeX, gazeY, tilt;
  const FaceMix(
      {this.w = const {},
      this.blush = 0,
      this.gazeX = 0,
      this.gazeY = 0,
      this.tilt = 0});

  double unit(String u) => w[u] ?? 0;

  FaceMix withUnit(String u, double v) =>
      _copy(w: {...w, u: v}..removeWhere((_, x) => x == 0));

  FaceMix copyWith(
          {double? blush, double? gazeX, double? gazeY, double? tilt}) =>
      _copy(blush: blush, gazeX: gazeX, gazeY: gazeY, tilt: tilt);

  /// lerp is [a] moved [t] of the way to [b].
  static FaceMix lerp(FaceMix a, FaceMix b, double t) {
    if (t <= 0) return a;
    double l(double x, double y) => x + (y - x) * t;
    return FaceMix(
      w: {
        for (final k in {...a.w.keys, ...b.w.keys})
          if (l(a.unit(k), b.unit(k)) case final v when v != 0) k: v
      },
      blush: l(a.blush, b.blush),
      gazeX: l(a.gazeX, b.gazeX),
      gazeY: l(a.gazeY, b.gazeY),
      tilt: l(a.tilt, b.tilt),
    );
  }

  FaceMix _copy(
          {Map<String, double>? w,
          double? blush,
          double? gazeX,
          double? gazeY,
          double? tilt}) =>
      FaceMix(
          w: w ?? this.w,
          blush: blush ?? this.blush,
          gazeX: gazeX ?? this.gazeX,
          gazeY: gazeY ?? this.gazeY,
          tilt: tilt ?? this.tilt);

  /// region is [region]'s shapes set to none.
  FaceMix withoutRegion(String region) => _copy(w: {
        for (final e in w.entries)
          if (!(faceUnits[region] ?? const []).any((u) => u.$1 == e.key))
            e.key: e.value
      });

  Map<String, dynamic> toJson() => {
        if (w.isNotEmpty) "w": w,
        if (blush != 0) "blush": blush,
        if (gazeX != 0) "gazeX": gazeX,
        if (gazeY != 0) "gazeY": gazeY,
        if (tilt != 0) "tilt": tilt,
      };

  static FaceMix fromJson(Object? json) {
    if (json is! Map) return const FaceMix();
    double n(String k, double lo, double hi) =>
        json[k] is num && (json[k] as num).isFinite
            ? (json[k] as num).toDouble().clamp(lo, hi)
            : 0;
    final w = json["w"];
    return FaceMix(
      w: {
        if (w is Map)
          for (final e in w.entries)
            if (e.key is String && e.value is num && (e.value as num).isFinite)
              e.key as String: (e.value as num).toDouble().clamp(0.0, 1.0)
      },
      blush: n("blush", 0, 1),
      gazeX: n("gazeX", -1, 1),
      gazeY: n("gazeY", -1, 1),
      tilt: n("tilt", -1, 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceMix &&
      other.blush == blush &&
      other.gazeX == gazeX &&
      other.gazeY == gazeY &&
      other.tilt == tilt &&
      other.w.length == w.length &&
      w.entries.every((e) => other.w[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
      blush,
      gazeX,
      gazeY,
      tilt,
      Object.hashAllUnordered(
          w.entries.map((e) => Object.hash(e.key, e.value))));
}

/// faceExpressions are the expressions to start from.
const Map<String, FaceMix> faceExpressions = {
  "Neutral": FaceMix(),
  "Happy": FaceMix(w: {"BRW_Joy": 0.8, "EYE_Joy": 0.55, "MTH_Joy": 0.8}),
  "Laughing": FaceMix(
      w: {"BRW_Joy": 1, "EYE_Joy": 1, "MTH_Fun": 1, "MTH_A": 0.35}, tilt: 0.1),
  "Smug": FaceMix(w: {
    "BRW_Fun": 0.6,
    "EYE_Joy_R": 0.45,
    "EYE_Natural": 0.4,
    "MTH_Up": 0.7,
    "MTH_Fun": 0.25
  }, gazeX: 0.2, tilt: -0.25),
  "Wink": FaceMix(
      w: {"BRW_Fun": 0.5, "EYE_Close_L": 1, "MTH_Joy": 0.75}, tilt: 0.2),
  "Angry": FaceMix(w: {"BRW_Angry": 1, "EYE_Angry": 0.8, "MTH_Angry": 0.75}),
  "Furious": FaceMix(w: {
    "BRW_Angry": 1,
    "EYE_Angry": 1,
    "MTH_Angry": 1,
    "MTH_A": 0.45,
    "HA_Fung2": 0.6
  }),
  "Sad": FaceMix(
      w: {"BRW_Sorrow": 1, "EYE_Sorrow": 0.8, "MTH_Sorrow": 0.7}, gazeY: -0.45),
  "Surprised": FaceMix(
      w: {"BRW_Surprised": 1, "EYE_Surprised": 1, "MTH_Surprised": 0.8}),
  "Scared": FaceMix(w: {
    "BRW_Sorrow": 0.7,
    "BRW_Surprised": 0.5,
    "EYE_Surprised": 0.8,
    "MTH_Down": 0.6,
    "MTH_I": 0.3
  }),
  "Shy": FaceMix(w: {
    "BRW_Sorrow": 0.45,
    "EYE_Joy": 0.3,
    "MTH_Neutral": 0.5,
    "MTH_Up": 0.2
  }, blush: 0.8, gazeX: 0.45, gazeY: -0.5, tilt: 0.3),
  "Sleepy": FaceMix(
      w: {"EYE_Close": 0.62, "BRW_Sorrow": 0.3, "MTH_O": 0.12}, tilt: 0.2),
  "Thinking": FaceMix(w: {
    "BRW_Angry": 0.3,
    "BRW_Surprised": 0.2,
    "EYE_Natural": 0.5,
    "MTH_Down": 0.3,
    "MTH_U": 0.15
  }, gazeX: -0.5, gazeY: 0.55, tilt: -0.2),
  "Pouty": FaceMix(
      w: {"BRW_Angry": 0.4, "MTH_U": 0.55, "MTH_Down": 0.2},
      blush: 0.35,
      gazeX: -0.3),
  "Determined":
      FaceMix(w: {"BRW_Angry": 0.6, "EYE_Angry": 0.3, "MTH_Neutral": 0.6}),
};

/// CharacterFace is the face: the expression it wears and the name it was
/// started from, the mixes kept to use again, and whether it blinks and
/// glances about by itself. Immutable.
class CharacterFace {
  final String name;
  final FaceMix mix;
  final Map<String, FaceMix> kept;
  final bool blinks, glances;

  const CharacterFace({
    this.name = "Neutral",
    this.mix = const FaceMix(),
    this.kept = const {},
    this.blinks = true,
    this.glances = false,
  });

  /// expressions are every expression it can wear: the ones to start from
  /// and the ones kept.
  Map<String, FaceMix> get expressions => {...faceExpressions, ...kept};

  /// wearing is [name]'s expression, or this face's own where it has no
  /// such one.
  FaceMix wearing(String? name) =>
      name == null ? mix : expressions[name] ?? mix;

  CharacterFace copyWith(
          {String? name,
          FaceMix? mix,
          Map<String, FaceMix>? kept,
          bool? blinks,
          bool? glances}) =>
      CharacterFace(
          name: name ?? this.name,
          mix: mix ?? this.mix,
          kept: kept ?? this.kept,
          blinks: blinks ?? this.blinks,
          glances: glances ?? this.glances);

  /// changed is whether the mix is not the expression it was started from.
  bool get changed => expressions[name] != mix;

  Map<String, dynamic> toJson() => {
        if (name != "Neutral") "name": name,
        if (mix != const FaceMix()) "mix": mix.toJson(),
        if (kept.isNotEmpty)
          "kept": {for (final e in kept.entries) e.key: e.value.toJson()},
        if (!blinks) "blinks": false,
        if (glances) "glances": true,
      };

  static CharacterFace fromJson(Object? json) {
    if (json is! Map) return const CharacterFace();
    final kept = json["kept"];
    return CharacterFace(
      name: json["name"] is String ? json["name"] as String : "Neutral",
      mix: FaceMix.fromJson(json["mix"]),
      kept: {
        if (kept is Map)
          for (final e in kept.entries)
            if (e.key is String) e.key as String: FaceMix.fromJson(e.value)
      },
      blinks: json["blinks"] != false,
      glances: json["glances"] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CharacterFace &&
      other.name == name &&
      other.mix == mix &&
      other.blinks == blinks &&
      other.glances == glances &&
      other.kept.length == kept.length &&
      kept.entries.every((e) => other.kept[e.key] == e.value);

  @override
  int get hashCode => Object.hash(name, mix, blinks, glances, kept.length);
}

/// SpokenLine is a line said: each letter a beat, with the mouth shapes it
/// makes, and how many beats in all.
class SpokenLine {
  final List<({double at, double long, Map<String, double> mouth})> beats;
  final double total;
  const SpokenLine(this.beats, this.total);

  /// beatsPerSecond is how fast it is said.
  static const double beatsPerSecond = 13;

  /// of is [text] as it is said: vowels open the mouth their own way,
  /// closed consonants shut it, spaces and stops are pauses.
  factory SpokenLine.of(String text) {
    final out = <({double at, double long, Map<String, double> mouth})>[];
    var t = 0.0;
    for (final ch in text.toLowerCase().split("")) {
      var d = 1.0;
      final Map<String, double> v;
      if (ch == "a") {
        v = {"A": 1};
      } else if ("iy".contains(ch)) {
        v = {"I": 0.85};
      } else if ("uw".contains(ch)) {
        v = {"U": 0.85};
      } else if (ch == "e") {
        v = {"E": 0.85};
      } else if (ch == "o") {
        v = {"O": 0.95};
      } else if ("fv".contains(ch)) {
        v = {"I": 0.3};
      } else if ("lntdszr".contains(ch)) {
        v = {"E": 0.35, "I": 0.2};
      } else if ("ckgqhxj".contains(ch)) {
        v = {"A": 0.4};
      } else {
        v = const {};
        if (ch == " ") d = 0.7;
        if (",;:".contains(ch)) d = 3;
        if (".!?".contains(ch)) d = 4.5;
      }
      out.add((at: t, long: d, mouth: v));
      t += d;
    }
    return SpokenLine(out, t);
  }

  /// seconds is how long it takes to say.
  double get seconds => total / beatsPerSecond;

  /// mouthAt is the mouth's shapes [seconds] in -- "MTH_A" and the rest --
  /// easing from one beat's into the next; null once it is said.
  Map<String, double>? mouthAt(double seconds) {
    final beat = seconds * beatsPerSecond;
    if (beat < 0 || beat > total) return null;
    final k = beats.indexWhere((b) => b.at + b.long > beat);
    if (k < 0) return const {};
    final b = beats[k];
    final next =
        k + 1 < beats.length ? beats[k + 1].mouth : const <String, double>{};
    // The last third of a beat moves toward the next.
    final into = ((beat - b.at) / b.long - 0.66).clamp(0.0, 1.0) / 0.34;
    final out = <String, double>{};
    for (final v in const ["A", "I", "U", "E", "O"]) {
      final x = (b.mouth[v] ?? 0) * (1 - into) + (next[v] ?? 0) * into;
      if (x > 0) out["MTH_$v"] = x;
    }
    return out;
  }
}

import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonSpec;

// mix.dart is how the media on the timeline is mixed: each channel's level,
// balance, EQ and compressor, and the master's EQ, compressor, limiter and
// loudness target.
//
// A mix plays in three places -- the editor through SoLoud, an exported video
// through ffmpeg, and later an interactive EPUB through Web Audio -- and it has
// to sound the same in all of them. So everything here is something all three
// can do, and each setting is defined once, here, in terms each of them is
// told exactly:
//
// - the EQ is RBJ biquads (cuts, shelves and bells), which is what ffmpeg's
//   highpass/lowpass/lowshelf/equalizer/highshelf and Web Audio's
//   BiquadFilterNode are. SoLoud's EQ is a set of bands rather than biquads,
//   so it is given this curve sampled at its band centres -- see
//   eqBandGains -- and follows it to within a fraction of a decibel;
// - balance is a gain on each side, worked out here and handed to each of
//   them as two numbers, not as a "pan" each would read by its own law;
// - the compressor and limiter take the parameters all three share.

/// EqKind is what a band of the EQ does: cut everything beyond it, lift or
/// lower everything beyond it, or lift or lower round it.
enum EqKind { lowCut, lowShelf, bell, highShelf, highCut }

/// EqSlot is one of the EQ's eight bands, in order up the spectrum -- the
/// layout of a channel EQ on a desk or in Logic.
enum EqSlot {
  lowCut("Low cut", EqKind.lowCut, EqBand(30, on: false)),
  low("Low shelf", EqKind.lowShelf, EqBand(120)),
  lowMid("Low mid", EqKind.bell, EqBand(300, q: 1)),
  mid("Mid", EqKind.bell, EqBand(1000, q: 1)),
  highMid("High mid", EqKind.bell, EqBand(2500, q: 1)),
  presence("Presence", EqKind.bell, EqBand(5000, q: 1)),
  high("High shelf", EqKind.highShelf, EqBand(8000)),
  highCut("High cut", EqKind.highCut, EqBand(18000, on: false));

  final String label;
  final EqKind kind;
  final EqBand initial;
  const EqSlot(this.label, this.kind, this.initial);

  bool get isCut => kind == EqKind.lowCut || kind == EqKind.highCut;
}

/// eqSlopes are the steepnesses a cut can have, in decibels an octave: one,
/// two, three or four second-order sections, each of which every player has.
const eqSlopes = [12, 24, 36, 48];

/// EqBand is one band: where it acts, how much, how widely -- and, for a
/// cut, how steeply.
class EqBand {
  final double freq;
  final double gainDb;
  final double q;
  final bool on;

  /// slope is a cut's steepness, in decibels an octave: one of eqSlopes.
  final int slope;

  const EqBand(this.freq,
      {this.gainDb = 0, this.q = 0.707, this.on = true, this.slope = 12});

  EqBand copyWith(
          {double? freq, double? gainDb, double? q, bool? on, int? slope}) =>
      EqBand(freq ?? this.freq,
          gainDb: gainDb ?? this.gainDb,
          q: q ?? this.q,
          on: on ?? this.on,
          slope: slope ?? this.slope);

  Map<String, dynamic> toJson() => {
        "f": freq,
        "g": gainDb,
        "q": q,
        if (!on) "on": false,
        if (slope != 12) "s": slope,
      };

  static EqBand fromJson(dynamic json, EqBand fallback) => json is Map
      ? EqBand(jsonDouble(json["f"], fallback.freq).clamp(20.0, 20000.0),
          gainDb: jsonDouble(json["g"], 0).clamp(-12.0, 12.0),
          q: jsonDouble(json["q"], fallback.q).clamp(0.1, 10.0),
          // Written only when off: a band that is there and says nothing
          // is on, whatever its slot starts as.
          on: jsonBool(json["on"], true),
          slope: eqSlopes.contains(json["s"]) ? json["s"] as int : 12)
      : fallback;
}

/// Eq is a channel EQ of eight bands: a low cut, a low shelf, four bells, a
/// high shelf and a high cut, then a gain.
///
/// The gains are limited to twelve decibels either way, which is as far as
/// the band EQ in the editor can follow. Files from before there were eight
/// bands have "low", "mid" and "high", which are still those three.
class Eq {
  final bool on;
  final EqBand lowCut;
  final EqBand low;
  final EqBand lowMid;
  final EqBand mid;
  final EqBand highMid;
  final EqBand presence;
  final EqBand high;
  final EqBand highCut;

  /// gainDb is the level after the bands.
  final double gainDb;

  const Eq({
    this.on = false,
    this.lowCut = const EqBand(30, on: false),
    this.low = const EqBand(120),
    this.lowMid = const EqBand(300, q: 1),
    this.mid = const EqBand(1000, q: 1),
    this.highMid = const EqBand(2500, q: 1),
    this.presence = const EqBand(5000, q: 1),
    this.high = const EqBand(8000),
    this.highCut = const EqBand(18000, on: false),
    this.gainDb = 0,
  });

  EqBand band(EqSlot slot) => switch (slot) {
        EqSlot.lowCut => lowCut,
        EqSlot.low => low,
        EqSlot.lowMid => lowMid,
        EqSlot.mid => mid,
        EqSlot.highMid => highMid,
        EqSlot.presence => presence,
        EqSlot.high => high,
        EqSlot.highCut => highCut,
      };

  Eq withBand(EqSlot slot, EqBand b) => switch (slot) {
        EqSlot.lowCut => copyWith(lowCut: b),
        EqSlot.low => copyWith(low: b),
        EqSlot.lowMid => copyWith(lowMid: b),
        EqSlot.mid => copyWith(mid: b),
        EqSlot.highMid => copyWith(highMid: b),
        EqSlot.presence => copyWith(presence: b),
        EqSlot.high => copyWith(high: b),
        EqSlot.highCut => copyWith(highCut: b),
      };

  /// shaping is whether [slot] changes anything: on, and -- unless it is a
  /// cut, which always does -- lifting or lowering.
  bool shaping(EqSlot slot) {
    var b = band(slot);
    return b.on && (slot.isCut || b.gainDb != 0);
  }

  bool get flat => !on || (gainDb == 0 && !EqSlot.values.any(shaping));

  Eq copyWith({
    bool? on,
    EqBand? lowCut,
    EqBand? low,
    EqBand? lowMid,
    EqBand? mid,
    EqBand? highMid,
    EqBand? presence,
    EqBand? high,
    EqBand? highCut,
    double? gainDb,
  }) =>
      Eq(
        on: on ?? this.on,
        lowCut: lowCut ?? this.lowCut,
        low: low ?? this.low,
        lowMid: lowMid ?? this.lowMid,
        mid: mid ?? this.mid,
        highMid: highMid ?? this.highMid,
        presence: presence ?? this.presence,
        high: high ?? this.high,
        highCut: highCut ?? this.highCut,
        gainDb: gainDb ?? this.gainDb,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        for (var slot in EqSlot.values) slot.name: band(slot).toJson(),
        if (gainDb != 0) "gain": gainDb,
      };

  factory Eq.fromJson(Map<String, dynamic> json) {
    EqBand read(EqSlot slot) => EqBand.fromJson(json[slot.name], slot.initial);
    return Eq(
      on: jsonBool(json["on"], false),
      lowCut: read(EqSlot.lowCut),
      low: read(EqSlot.low),
      lowMid: read(EqSlot.lowMid),
      mid: read(EqSlot.mid),
      highMid: read(EqSlot.highMid),
      presence: read(EqSlot.presence),
      high: read(EqSlot.high),
      highCut: read(EqSlot.highCut),
      gainDb: jsonDouble(json["gain"], 0).clamp(-12.0, 12.0),
    );
  }

  /// bandDb is what [slot] alone does to [freq], in decibels: each band's
  /// own curve, drawn in its colour.
  double bandDb(EqSlot slot, double freq, {double sampleRate = 48000}) {
    var b = band(slot);
    if (!b.on) return 0;
    return [
      for (var q in _sections(slot, b, sampleRate))
        _biquadDb(q, freq, sampleRate)
    ].fold(0.0, (a, v) => a + v);
  }

  /// responseDb is how much this EQ lifts or cuts [freq], in decibels -- the
  /// curve drawn on screen, and the one both players are made to follow.
  double responseDb(double freq, {double sampleRate = 48000}) {
    if (!on) return 0;
    var db = gainDb;
    for (var slot in EqSlot.values) {
      if (shaping(slot)) db += bandDb(slot, freq, sampleRate: sampleRate);
    }
    return db;
  }
}

/// _sections is [b] in [slot] as the biquads that make it: one for a shelf
/// or a bell, and for a cut one per twelve decibels an octave -- the first
/// at the band's Q, so it can ring at the corner, the rest Butterworth.
List<_Biquad> _sections(EqSlot slot, EqBand b, double fs) =>
    switch (slot.kind) {
      EqKind.lowShelf => [_shelf(b, fs, high: false)],
      EqKind.highShelf => [_shelf(b, fs, high: true)],
      EqKind.bell => [_bell(b, fs)],
      EqKind.lowCut || EqKind.highCut => [
          for (var i = 0; i < b.slope ~/ 12; i++)
            _pass(b.freq, i == 0 ? b.q : 0.707, fs,
                high: slot.kind == EqKind.lowCut),
        ],
    };

/// eqBandCentres is where SoLoud's EQ bands sit for [bands] of them: spaced
/// evenly on a log scale from 30 Hz to 16 kHz, as its own source places them.
List<double> eqBandCentres(int bands) => [
      for (var i = 0; i < bands; i++)
        bands == 1 ? 1000.0 : 30.0 * math.pow(16000 / 30, i / (bands - 1)),
    ];

/// soloudBands is how many bands the editor's EQ is given: SoLoud's most.
const int soloudBands = 64;

/// soloudBlend is how SoLoud's band EQ weighs its bands at [f], given their
/// [centres]: a triangle round each centre reaching to the midpoints either
/// side, linear in hertz, normalised to sum to one -- written out from
/// parametric_eq_filter.cpp, so that what it will do can be worked out here.
List<double> soloudBlend(double f, List<double> centres,
    {double nyquist = 24000}) {
  var n = centres.length;
  var weights = List<double>.filled(n, 0);
  var sum = 0.0;
  for (var b = 0; b < n; b++) {
    var c = centres[b];
    var lo = b == 0 ? 0.0 : (centres[b - 1] + c) / 2;
    var hi = b == n - 1 ? nyquist : math.min(nyquist, (c + centres[b + 1]) / 2);
    var w = 0.0;
    if (f <= c && c - lo > 0) {
      var x = 1 - (c - f) / (c - lo);
      if (x >= 0) w = math.max(x, 0.001);
    } else if (f > c && hi - c > 0) {
      var x = 1 - (f - c) / (hi - c);
      if (x >= 0) w = math.max(x, 0.001);
    }
    weights[b] = w;
    sum += w;
  }
  if (sum > 0) {
    for (var b = 0; b < n; b++) {
      weights[b] /= sum;
    }
  }
  return weights;
}

/// eqBandGains is what to give SoLoud's band EQ so that it follows [eq]'s
/// curve: linear gains, nought to four, one per band.
///
/// Fitted, not sampled. SoLoud blends neighbouring bands in a straight line
/// between their centres, so a curve sampled at the centres is right at the
/// centres and wrong between them -- by three and a half decibels for a
/// narrow cut, which is a different sound from the export's. Instead the
/// gains are the ones whose blend comes closest to the curve everywhere from
/// 30 Hz to 16 kHz: a least-squares fit, weighted so an error counts by how
/// many decibels it is rather than by how big a number. Worked out only when
/// an EQ is changed.
List<double> eqBandGains(Eq eq, {int bands = soloudBands}) {
  var centres = eqBandCentres(bands);
  // The curve, at many more points than there are bands.
  const points = 480;
  var rows = <List<double>>[];
  var targets = <double>[];
  var weights = <double>[];
  for (var i = 0; i <= points; i++) {
    var f = 30 * math.pow(16000 / 30, i / points).toDouble();
    var t = math.pow(10, eq.responseDb(f) / 20).toDouble();
    rows.add(soloudBlend(f, centres));
    targets.add(t);
    weights.add(1 / (t * t));
  }
  // Normal equations: (A^T W A) g = A^T W t, with a whisker of ridge so that a
  // band no point reaches still has an answer.
  var n = bands;
  var m = List.generate(n, (_) => List<double>.filled(n + 1, 0));
  for (var r = 0; r < rows.length; r++) {
    var row = rows[r], w = weights[r];
    for (var a = 0; a < n; a++) {
      if (row[a] == 0) continue;
      var wa = w * row[a];
      for (var b = 0; b < n; b++) {
        if (row[b] != 0) m[a][b] += wa * row[b];
      }
      m[a][n] += wa * targets[r];
    }
  }
  for (var a = 0; a < n; a++) {
    m[a][a] += 1e-6;
  }
  // Gaussian elimination with partial pivoting.
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    var swap = m[col];
    m[col] = m[pivot];
    m[pivot] = swap;
    var p = m[col][col];
    if (p.abs() < 1e-12) continue;
    for (var r = 0; r < n; r++) {
      if (r == col) continue;
      var f = m[r][col] / p;
      if (f == 0) continue;
      for (var c = col; c <= n; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  return [
    for (var a = 0; a < n; a++)
      (m[a][a].abs() < 1e-12 ? 1.0 : m[a][n] / m[a][a]).clamp(0.0, 4.0),
  ];
}

/// eqFfmpeg is [eq] as ffmpeg filters, the same biquads: ffmpeg's highpass
/// and lowpass, two-pole, are the RBJ ones, as its shelves and bells are.
List<String> eqFfmpeg(Eq eq) {
  if (eq.flat) return const [];
  String n(double v) => v.toStringAsFixed(3);
  return [
    for (var slot in EqSlot.values)
      if (eq.shaping(slot))
        ...switch ((slot.kind, eq.band(slot))) {
          (EqKind.lowCut || EqKind.highCut, var b) => [
              for (var i = 0; i < b.slope ~/ 12; i++)
                "${slot.kind == EqKind.lowCut ? "highpass" : "lowpass"}"
                    "=f=${n(b.freq)}:p=2:t=q:w=${n(i == 0 ? b.q : 0.707)}",
            ],
          (EqKind.lowShelf, var b) => [
              "lowshelf=f=${n(b.freq)}:t=q:w=${n(b.q)}:g=${n(b.gainDb)}"
            ],
          (EqKind.highShelf, var b) => [
              "highshelf=f=${n(b.freq)}:t=q:w=${n(b.q)}:g=${n(b.gainDb)}"
            ],
          (EqKind.bell, var b) => [
              "equalizer=f=${n(b.freq)}:t=q:w=${n(b.q)}:g=${n(b.gainDb)}"
            ],
        },
    if (eq.gainDb != 0) "volume=${n(eq.gainDb)}dB",
  ];
}

/// dynamicsAndEq is a strip's EQ and compressor as ffmpeg filters, in the
/// strip's order.
List<String> dynamicsAndEq(Eq eq, Dynamics comp, bool compFirst) => [
      if (compFirst && comp.on) comp.ffmpeg,
      ...eqFfmpeg(eq),
      if (!compFirst && comp.on) comp.ffmpeg,
    ];

/// AutoGain is a compressor making up, by itself, what it takes off: none,
/// enough that a full-scale level comes out at full scale, or enough that
/// one twelve decibels down does.
enum AutoGain {
  off("Off"),
  zero("0 dB"),
  minus12("−12 dB");

  final String label;
  const AutoGain(this.label);

  static AutoGain fromName(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => off);
}

/// Dynamics is a compressor: above [threshold], turned down by [ratio].
class Dynamics {
  final bool on;
  final double threshold;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double makeupDb;

  /// kneeDb is how wide the bend at the threshold is: nought is a hard
  /// corner, wider eases into the ratio.
  final double kneeDb;

  /// mix is how much of the compressed sound is heard against the dry: one
  /// is all compressed, less is parallel compression.
  final double mix;

  /// autoGain makes up what is taken off, on top of [makeupDb].
  final AutoGain autoGain;

  const Dynamics({
    this.on = false,
    this.threshold = -18,
    this.ratio = 3,
    this.attackMs = 10,
    this.releaseMs = 150,
    this.makeupDb = 0,
    this.kneeDb = 6,
    this.mix = 1,
    this.autoGain = AutoGain.off,
  });

  Dynamics copyWith({
    bool? on,
    double? threshold,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupDb,
    double? kneeDb,
    double? mix,
    AutoGain? autoGain,
  }) =>
      Dynamics(
        on: on ?? this.on,
        threshold: threshold ?? this.threshold,
        ratio: ratio ?? this.ratio,
        attackMs: attackMs ?? this.attackMs,
        releaseMs: releaseMs ?? this.releaseMs,
        makeupDb: makeupDb ?? this.makeupDb,
        kneeDb: kneeDb ?? this.kneeDb,
        mix: mix ?? this.mix,
        autoGain: autoGain ?? this.autoGain,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        "threshold": threshold,
        "ratio": ratio,
        "attack": attackMs,
        "release": releaseMs,
        "makeup": makeupDb,
        if (kneeDb != 6) "knee": kneeDb,
        if (mix != 1) "mix": mix,
        if (autoGain != AutoGain.off) "autoGain": autoGain.name,
      };

  factory Dynamics.fromJson(Map<String, dynamic> json) => Dynamics(
        on: jsonBool(json["on"], false),
        threshold: jsonDouble(json["threshold"], -18).clamp(-60.0, 0.0),
        ratio: jsonDouble(json["ratio"], 3).clamp(1.0, 10.0),
        attackMs: jsonDouble(json["attack"], 10).clamp(0.1, 100.0),
        releaseMs: jsonDouble(json["release"], 150).clamp(10.0, 1000.0),
        makeupDb: jsonDouble(json["makeup"], 0).clamp(0.0, 24.0),
        kneeDb: jsonDouble(json["knee"], 6).clamp(0.0, 18.0),
        mix: jsonDouble(json["mix"], 1).clamp(0.0, 1.0),
        autoGain: AutoGain.fromName(json["autoGain"] as String?),
      );

  /// reducedDb is what the threshold, ratio and knee make of a level of
  /// [input] dB, before any makeup: untouched below the knee, turned down by
  /// the ratio above it, and a curve between.
  double reducedDb(double input) {
    var t = threshold, r = math.max(1.0, ratio), k = kneeDb;
    if (k <= 0) return input <= t ? input : t + (input - t) / r;
    if (input < t - k / 2) return input;
    if (input > t + k / 2) return t + (input - t) / r;
    var over = input - t + k / 2;
    return input + (1 / r - 1) * over * over / (2 * k);
  }

  /// totalMakeupDb is the makeup asked for and what auto gain adds: enough
  /// to bring its reference level back to where it went in.
  double get totalMakeupDb {
    var auto = switch (autoGain) {
      AutoGain.off => 0.0,
      AutoGain.zero => -reducedDb(0),
      AutoGain.minus12 => -12 - reducedDb(-12),
    };
    return (makeupDb + math.max(0.0, auto)).clamp(0.0, 36.0);
  }

  /// ffmpeg is this compressor as ffmpeg's acompressor, which takes its
  /// levels as ratios rather than decibels -- its knee among them, from one
  /// (a hard corner) to eight.
  String get ffmpeg {
    String n(double v) => v.toStringAsFixed(4);
    return "acompressor=threshold=${n(dbToGain(threshold))}"
        ":ratio=${n(ratio)}:attack=${n(attackMs)}:release=${n(releaseMs)}"
        ":makeup=${n(math.max(1, dbToGain(totalMakeupDb)))}"
        ":knee=${n(dbToGain(kneeDb).clamp(1.0, 8.0))}"
        ":mix=${n(mix)}";
  }
}

/// DuckCurve is how a ducked channel sinks and comes back.
enum DuckCurve {
  /// hard is no fade at all: down and up at once.
  hard("Hard"),
  linear("Linear"),

  /// smooth eases in and out, an S: the change is gentlest at both ends.
  smooth("Smooth"),

  /// natural is even in decibels rather than in level, which is how a hand
  /// on a fader moves and how an ear hears an even fade.
  natural("Natural");

  final String label;
  const DuckCurve(this.label);

  static DuckCurve fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => smooth);
}

/// Ducking is a channel turning the others down while it is heard: a voice
/// over music, the music sinking under every line.
///
/// Set on the channel that is listened for -- the voice -- not on each
/// channel that sinks, so one setting covers everything under it. Every
/// other channel is ducked except those in [except]. Worked out from the
/// listened-for channel's own recordings, where it is speaking, rather than
/// from a level meter while it plays: so what is heard while editing and
/// what is exported are the same, and the dips can be drawn. See
/// duckEnvelopes.
class Ducking {
  final bool on;

  /// depthDb is how far the other channels sink, below nought.
  final double depthDb;

  /// attack is how long, in seconds, a channel takes to sink before a line,
  /// and release how long it takes to come back after one.
  final double attack;
  final double release;

  /// except are the channels, by key, left alone.
  final List<String> except;

  /// curve is the shape of the way down and the way back up.
  final DuckCurve curve;

  const Ducking({
    this.on = false,
    this.depthDb = -10,
    this.attack = 0.3,
    this.release = 0.8,
    this.except = const [],
    this.curve = DuckCurve.smooth,
  });

  Ducking copyWith({
    bool? on,
    double? depthDb,
    double? attack,
    double? release,
    List<String>? except,
    DuckCurve? curve,
  }) =>
      Ducking(
        on: on ?? this.on,
        depthDb: depthDb ?? this.depthDb,
        attack: attack ?? this.attack,
        release: release ?? this.release,
        except: except ?? this.except,
        curve: curve ?? this.curve,
      );

  Map<String, dynamic> toJson() => {
        "on": on,
        if (depthDb != -10) "depth": depthDb,
        "attack": attack,
        "release": release,
        if (except.isNotEmpty) "except": except,
        if (curve != DuckCurve.smooth) "curve": curve.name,
      };

  factory Ducking.fromJson(Map<String, dynamic> json) => Ducking(
        on: jsonBool(json["on"], false),
        depthDb: jsonDouble(json["depth"], -10).clamp(-40.0, -1.0),
        attack: jsonDouble(json["attack"], 0.3).clamp(0.0, 2.0),
        release: jsonDouble(json["release"], 0.8).clamp(0.0, 4.0),
        curve: DuckCurve.fromName(json["curve"] as String?),
        except: [
          if (json["except"] is List)
            for (var k in json["except"] as List)
              if (k is String) k,
        ],
      );
}

/// ChannelMix is one channel strip.
class ChannelMix {
  final double gainDb;

  /// balance is from -1 (left only) to 1 (right only). See [gains].
  final double balance;
  final bool mute;
  final Eq eq;
  final Dynamics comp;

  /// duck is how this channel turns the others down while it is heard --
  /// see Ducking.
  final Ducking duck;

  /// compFirst is whether the compressor comes before the EQ. Either order
  /// is a way to mix; what matters is that playing and exporting agree, so
  /// it is said here rather than left to whichever was switched on first.
  final bool compFirst;

  const ChannelMix({
    this.gainDb = 0,
    this.balance = 0,
    this.mute = false,
    this.eq = const Eq(),
    this.comp = const Dynamics(),
    this.duck = const Ducking(),
    this.compFirst = false,
  });

  bool get isDefault =>
      gainDb == 0 &&
      balance == 0 &&
      !mute &&
      !eq.on &&
      !comp.on &&
      !duck.on &&
      !compFirst;

  /// gains is the level of each side: the fader, and the balance taking away
  /// from the side it turns from. Nothing is ever made louder than the fader
  /// by turning -- a balance that boosts one side makes a sound jump in level
  /// as it is placed, which reads as the fader moving.
  (double, double) get gains {
    var level = dbToGain(gainDb);
    var b = balance.clamp(-1.0, 1.0);
    return (level * (b > 0 ? 1 - b : 1), level * (b < 0 ? 1 + b : 1));
  }

  ChannelMix copyWith({
    double? gainDb,
    double? balance,
    bool? mute,
    Eq? eq,
    Dynamics? comp,
    Ducking? duck,
    bool? compFirst,
  }) =>
      ChannelMix(
        gainDb: gainDb ?? this.gainDb,
        balance: balance ?? this.balance,
        mute: mute ?? this.mute,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
        duck: duck ?? this.duck,
        compFirst: compFirst ?? this.compFirst,
      );

  Map<String, dynamic> toJson() => {
        if (gainDb != 0) "gain": gainDb,
        if (balance != 0) "balance": balance,
        if (mute) "mute": true,
        if (eq.on) "eq": eq.toJson(),
        if (comp.on) "comp": comp.toJson(),
        if (duck.on) "duck": duck.toJson(),
        if (compFirst) "compFirst": true,
      };

  factory ChannelMix.fromJson(Map<String, dynamic> json) => ChannelMix(
        gainDb: jsonDouble(json["gain"], 0).clamp(-90.0, 12.0),
        balance: jsonDouble(json["balance"], 0).clamp(-1.0, 1.0),
        mute: jsonBool(json["mute"], false),
        eq: jsonSpec(json["eq"], Eq.fromJson, const Eq()),
        comp: jsonSpec(json["comp"], Dynamics.fromJson, const Dynamics()),
        duck: jsonSpec(json["duck"], Ducking.fromJson, const Ducking()),
        compFirst: jsonBool(json["compFirst"], false),
      );

  /// ffmpeg is this strip as ffmpeg filters, in the order the editor runs
  /// them: the EQ and the compressor in the order set, then level and
  /// balance.
  List<String> get ffmpeg {
    var (l, r) = gains;
    String n(double v) => v.toStringAsFixed(4);
    return [
      ...dynamicsAndEq(eq, comp, compFirst),
      if (l != 1 || r != 1) "pan=stereo|c0=${n(l)}*c0|c1=${n(r)}*c1",
    ];
  }
}

/// loudnessTargets are the targets offered: what the loudest services play
/// at, what podcasts do, and the broadcast standard.
const loudnessTargets = <(double, String)>[
  (-14, "−14 LUFS · streaming"),
  (-16, "−16 LUFS · podcast"),
  (-23, "−23 LUFS · EBU R128 broadcast"),
];

/// MasterMix is the master strip: what everything is summed through.
class MasterMix {
  final double gainDb;
  final Eq eq;

  /// comp is the "glue": a gentle compressor over the whole mix.
  final Dynamics comp;

  /// limiter keeps the peaks under [ceilingDb], true peak.
  final bool limiter;
  final double ceilingDb;

  /// target is the loudness the mix is aimed at, and normalise whether an
  /// export is brought to it -- measured and adjusted, rather than hoped.
  final double target;
  final bool normalise;

  /// compFirst is whether the glue comes before the EQ -- see
  /// ChannelMix.compFirst. The limiter is always last.
  final bool compFirst;

  const MasterMix({
    this.gainDb = 0,
    this.eq = const Eq(),
    this.comp =
        const Dynamics(threshold: -12, ratio: 2, attackMs: 30, releaseMs: 200),
    this.limiter = true,
    this.ceilingDb = -1,
    this.target = -16,
    this.normalise = false,
    this.compFirst = false,
  });

  bool get isDefault =>
      gainDb == 0 &&
      !eq.on &&
      !comp.on &&
      limiter &&
      ceilingDb == -1 &&
      target == -16 &&
      !normalise &&
      !compFirst;

  MasterMix copyWith({
    double? gainDb,
    Eq? eq,
    Dynamics? comp,
    bool? limiter,
    double? ceilingDb,
    double? target,
    bool? normalise,
    bool? compFirst,
  }) =>
      MasterMix(
        gainDb: gainDb ?? this.gainDb,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
        limiter: limiter ?? this.limiter,
        ceilingDb: ceilingDb ?? this.ceilingDb,
        target: target ?? this.target,
        normalise: normalise ?? this.normalise,
        compFirst: compFirst ?? this.compFirst,
      );

  Map<String, dynamic> toJson() => {
        if (gainDb != 0) "gain": gainDb,
        if (eq.on) "eq": eq.toJson(),
        if (comp.on) "comp": comp.toJson(),
        if (!limiter) "noLimiter": true,
        if (ceilingDb != -1) "ceiling": ceilingDb,
        if (target != -16) "target": target,
        if (normalise) "normalise": true,
        if (compFirst) "compFirst": true,
      };

  factory MasterMix.fromJson(Map<String, dynamic> json) => MasterMix(
        gainDb: jsonDouble(json["gain"], 0).clamp(-90.0, 12.0),
        eq: jsonSpec(json["eq"], Eq.fromJson, const Eq()),
        comp: jsonSpec(
            json["comp"],
            Dynamics.fromJson,
            const Dynamics(
                threshold: -12, ratio: 2, attackMs: 30, releaseMs: 200)),
        limiter: !jsonBool(json["noLimiter"], false),
        ceilingDb: jsonDouble(json["ceiling"], -1).clamp(-12.0, 0.0),
        target: jsonDouble(json["target"], -16).clamp(-36.0, -6.0),
        normalise: jsonBool(json["normalise"], false),
        compFirst: jsonBool(json["compFirst"], false),
      );

  /// ffmpeg is the master as ffmpeg filters: EQ, glue, level, then -- where
  /// asked -- the loudness brought to the target, and last the limiter, so
  /// nothing after it can take a peak back over the ceiling.
  List<String> get ffmpeg {
    String n(double v) => v.toStringAsFixed(4);
    return [
      ...dynamicsAndEq(eq, comp, compFirst),
      if (gainDb != 0) "volume=${n(gainDb)}dB",
      if (normalise)
        "loudnorm=I=${n(target)}:TP=${n(ceilingDb)}:LRA=11:linear=true",
      if (limiter)
        "alimiter=limit=${n(dbToGain(ceilingDb))}:attack=5:release=50"
            ":level=disabled",
    ];
  }
}

double dbToGain(double db) => db <= -90 ? 0 : math.pow(10, db / 20).toDouble();

double gainToDb(double gain) =>
    gain <= 0 ? -double.infinity : 20 * math.log(gain) / math.ln10;

// The RBJ "Audio EQ Cookbook" biquads, which ffmpeg's lowshelf, equalizer and
// highshelf and Web Audio's BiquadFilterNode implement. Only their magnitude
// is needed here -- for drawing the curve and for telling SoLoud's band EQ
// what to follow.

typedef _Biquad = (double, double, double, double, double, double);

_Biquad _bell(EqBand band, double fs) {
  var a = math.pow(10, band.gainDb / 40).toDouble();
  var w0 = 2 * math.pi * band.freq / fs;
  var alpha = math.sin(w0) / (2 * band.q);
  var c = math.cos(w0);
  return (
    1 + alpha * a, -2 * c, 1 - alpha * a, //
    1 + alpha / a, -2 * c, 1 - alpha / a,
  );
}

_Biquad _shelf(EqBand band, double fs, {required bool high}) {
  var a = math.pow(10, band.gainDb / 40).toDouble();
  var w0 = 2 * math.pi * band.freq / fs;
  var c = math.cos(w0);
  var alpha = math.sin(w0) / (2 * band.q);
  var sq = 2 * math.sqrt(a) * alpha;
  if (!high) {
    return (
      a * ((a + 1) - (a - 1) * c + sq),
      2 * a * ((a - 1) - (a + 1) * c),
      a * ((a + 1) - (a - 1) * c - sq),
      (a + 1) + (a - 1) * c + sq,
      -2 * ((a - 1) + (a + 1) * c),
      (a + 1) + (a - 1) * c - sq,
    );
  }
  return (
    a * ((a + 1) + (a - 1) * c + sq),
    -2 * a * ((a - 1) + (a + 1) * c),
    a * ((a + 1) + (a - 1) * c - sq),
    (a + 1) - (a - 1) * c + sq,
    2 * ((a - 1) - (a + 1) * c),
    (a + 1) - (a - 1) * c - sq,
  );
}

/// _pass is the RBJ high-pass or low-pass at [freq] with [q]: half of a
/// cut's every twelve decibels an octave.
_Biquad _pass(double freq, double q, double fs, {required bool high}) {
  var w0 = 2 * math.pi * freq.clamp(1.0, fs / 2 - 1) / fs;
  var c = math.cos(w0);
  var alpha = math.sin(w0) / (2 * q);
  var b = high ? (1 + c) / 2 : (1 - c) / 2;
  return (b, high ? -(1 + c) : 1 - c, b, 1 + alpha, -2 * c, 1 - alpha);
}

double _biquadDb(_Biquad q, double f, double fs) {
  var (b0, b1, b2, a0, a1, a2) = q;
  var w = 2 * math.pi * f / fs;
  // |H(e^jw)| from the coefficients: the magnitude of the numerator over
  // that of the denominator, each a quadratic in e^-jw.
  double mag(double c0, double c1, double c2) {
    var re = c0 + c1 * math.cos(w) + c2 * math.cos(2 * w);
    var im = -(c1 * math.sin(w) + c2 * math.sin(2 * w));
    return math.sqrt(re * re + im * im);
  }

  var num = mag(b0, b1, b2), den = mag(a0, a1, a2);
  if (den <= 0 || num <= 0) return 0;
  return 20 * math.log(num / den) / math.ln10;
}

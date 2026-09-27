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
// - the EQ is three RBJ biquads (a low shelf, a bell, a high shelf), which is
//   what ffmpeg's lowshelf/equalizer/highshelf and Web Audio's
//   BiquadFilterNode are. SoLoud's EQ is a set of bands rather than biquads,
//   so it is given this curve sampled at its band centres -- see
//   eqBandGains -- and follows it to within a fraction of a decibel;
// - balance is a gain on each side, worked out here and handed to each of
//   them as two numbers, not as a "pan" each would read by its own law;
// - the compressor and limiter take the parameters all three share.

/// EqBand is one of the three: where it acts, how much, and how widely.
class EqBand {
  final double freq;
  final double gainDb;
  final double q;

  const EqBand(this.freq, {this.gainDb = 0, this.q = 0.707});

  EqBand copyWith({double? freq, double? gainDb, double? q}) =>
      EqBand(freq ?? this.freq, gainDb: gainDb ?? this.gainDb, q: q ?? this.q);

  Map<String, dynamic> toJson() => {"f": freq, "g": gainDb, "q": q};

  static EqBand fromJson(dynamic json, EqBand fallback) => json is Map
      ? EqBand(jsonDouble(json["f"], fallback.freq).clamp(20.0, 20000.0),
          gainDb: jsonDouble(json["g"], 0).clamp(-12.0, 12.0),
          q: jsonDouble(json["q"], fallback.q).clamp(0.1, 10.0))
      : fallback;
}

/// Eq is a low shelf, a bell and a high shelf.
///
/// Three because three is what a channel strip on a mixing desk has, and what
/// a person can hold in their head: the bottom, the middle, the top. Their
/// gains are limited to twelve decibels either way, which is as far as the
/// band EQ in the editor can follow.
class Eq {
  final bool on;
  final EqBand low;
  final EqBand mid;
  final EqBand high;

  const Eq({
    this.on = false,
    this.low = const EqBand(120),
    this.mid = const EqBand(1000, q: 1),
    this.high = const EqBand(8000),
  });

  bool get flat =>
      !on || (low.gainDb == 0 && mid.gainDb == 0 && high.gainDb == 0);

  Eq copyWith({bool? on, EqBand? low, EqBand? mid, EqBand? high}) => Eq(
        on: on ?? this.on,
        low: low ?? this.low,
        mid: mid ?? this.mid,
        high: high ?? this.high,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        "low": low.toJson(),
        "mid": mid.toJson(),
        "high": high.toJson(),
      };

  factory Eq.fromJson(Map<String, dynamic> json) => Eq(
        on: jsonBool(json["on"], false),
        low: EqBand.fromJson(json["low"], const EqBand(120)),
        mid: EqBand.fromJson(json["mid"], const EqBand(1000, q: 1)),
        high: EqBand.fromJson(json["high"], const EqBand(8000)),
      );

  /// responseDb is how much this EQ lifts or cuts [freq], in decibels -- the
  /// curve drawn on screen, and the one both players are made to follow.
  double responseDb(double freq, {double sampleRate = 48000}) {
    if (!on) return 0;
    return _biquadDb(_shelf(low, sampleRate, high: false), freq, sampleRate) +
        _biquadDb(_bell(mid, sampleRate), freq, sampleRate) +
        _biquadDb(_shelf(high, sampleRate, high: true), freq, sampleRate);
  }
}

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

/// eqFfmpeg is [eq] as ffmpeg filters, the same three biquads.
List<String> eqFfmpeg(Eq eq) {
  if (eq.flat) return const [];
  String n(double v) => v.toStringAsFixed(3);
  return [
    if (eq.low.gainDb != 0)
      "lowshelf=f=${n(eq.low.freq)}:t=q:w=${n(eq.low.q)}:g=${n(eq.low.gainDb)}",
    if (eq.mid.gainDb != 0)
      "equalizer=f=${n(eq.mid.freq)}:t=q:w=${n(eq.mid.q)}:g=${n(eq.mid.gainDb)}",
    if (eq.high.gainDb != 0)
      "highshelf=f=${n(eq.high.freq)}:t=q:w=${n(eq.high.q)}:g=${n(eq.high.gainDb)}",
  ];
}

/// Dynamics is a compressor: above [threshold], turned down by [ratio].
class Dynamics {
  final bool on;
  final double threshold;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double makeupDb;

  const Dynamics({
    this.on = false,
    this.threshold = -18,
    this.ratio = 3,
    this.attackMs = 10,
    this.releaseMs = 150,
    this.makeupDb = 0,
  });

  /// kneeDb is fixed: a soft knee a few decibels wide is what a compressor
  /// that is not meant to be heard wants, and one fewer setting is one fewer
  /// setting.
  static const double kneeDb = 6;

  Dynamics copyWith({
    bool? on,
    double? threshold,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupDb,
  }) =>
      Dynamics(
        on: on ?? this.on,
        threshold: threshold ?? this.threshold,
        ratio: ratio ?? this.ratio,
        attackMs: attackMs ?? this.attackMs,
        releaseMs: releaseMs ?? this.releaseMs,
        makeupDb: makeupDb ?? this.makeupDb,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        "threshold": threshold,
        "ratio": ratio,
        "attack": attackMs,
        "release": releaseMs,
        "makeup": makeupDb,
      };

  factory Dynamics.fromJson(Map<String, dynamic> json) => Dynamics(
        on: jsonBool(json["on"], false),
        threshold: jsonDouble(json["threshold"], -18).clamp(-60.0, 0.0),
        ratio: jsonDouble(json["ratio"], 3).clamp(1.0, 10.0),
        attackMs: jsonDouble(json["attack"], 10).clamp(0.1, 100.0),
        releaseMs: jsonDouble(json["release"], 150).clamp(10.0, 1000.0),
        makeupDb: jsonDouble(json["makeup"], 0).clamp(0.0, 24.0),
      );

  /// ffmpeg is this compressor as ffmpeg's acompressor, which takes its
  /// levels as ratios rather than decibels.
  String get ffmpeg {
    String n(double v) => v.toStringAsFixed(4);
    return "acompressor=threshold=${n(dbToGain(threshold))}"
        ":ratio=${n(ratio)}:attack=${n(attackMs)}:release=${n(releaseMs)}"
        ":makeup=${n(math.max(1, dbToGain(makeupDb)))}"
        ":knee=${n(dbToGain(kneeDb))}";
  }
}

/// ChannelMix is one channel strip.
class ChannelMix {
  final double gainDb;

  /// balance is from -1 (left only) to 1 (right only). See [gains].
  final double balance;
  final bool mute;
  final Eq eq;
  final Dynamics comp;

  const ChannelMix({
    this.gainDb = 0,
    this.balance = 0,
    this.mute = false,
    this.eq = const Eq(),
    this.comp = const Dynamics(),
  });

  bool get isDefault =>
      gainDb == 0 && balance == 0 && !mute && !eq.on && !comp.on;

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
  }) =>
      ChannelMix(
        gainDb: gainDb ?? this.gainDb,
        balance: balance ?? this.balance,
        mute: mute ?? this.mute,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
      );

  Map<String, dynamic> toJson() => {
        if (gainDb != 0) "gain": gainDb,
        if (balance != 0) "balance": balance,
        if (mute) "mute": true,
        if (eq.on) "eq": eq.toJson(),
        if (comp.on) "comp": comp.toJson(),
      };

  factory ChannelMix.fromJson(Map<String, dynamic> json) => ChannelMix(
        gainDb: jsonDouble(json["gain"], 0).clamp(-90.0, 12.0),
        balance: jsonDouble(json["balance"], 0).clamp(-1.0, 1.0),
        mute: jsonBool(json["mute"], false),
        eq: jsonSpec(json["eq"], Eq.fromJson, const Eq()),
        comp: jsonSpec(json["comp"], Dynamics.fromJson, const Dynamics()),
      );

  /// ffmpeg is this strip as ffmpeg filters, in the order the editor runs
  /// them: EQ, then the compressor, then level and balance.
  List<String> get ffmpeg {
    var (l, r) = gains;
    String n(double v) => v.toStringAsFixed(4);
    return [
      ...eqFfmpeg(eq),
      if (comp.on) comp.ffmpeg,
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

  const MasterMix({
    this.gainDb = 0,
    this.eq = const Eq(),
    this.comp =
        const Dynamics(threshold: -12, ratio: 2, attackMs: 30, releaseMs: 200),
    this.limiter = true,
    this.ceilingDb = -1,
    this.target = -16,
    this.normalise = false,
  });

  bool get isDefault =>
      gainDb == 0 &&
      !eq.on &&
      !comp.on &&
      limiter &&
      ceilingDb == -1 &&
      target == -16 &&
      !normalise;

  MasterMix copyWith({
    double? gainDb,
    Eq? eq,
    Dynamics? comp,
    bool? limiter,
    double? ceilingDb,
    double? target,
    bool? normalise,
  }) =>
      MasterMix(
        gainDb: gainDb ?? this.gainDb,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
        limiter: limiter ?? this.limiter,
        ceilingDb: ceilingDb ?? this.ceilingDb,
        target: target ?? this.target,
        normalise: normalise ?? this.normalise,
      );

  Map<String, dynamic> toJson() => {
        if (gainDb != 0) "gain": gainDb,
        if (eq.on) "eq": eq.toJson(),
        if (comp.on) "comp": comp.toJson(),
        if (!limiter) "noLimiter": true,
        if (ceilingDb != -1) "ceiling": ceilingDb,
        if (target != -16) "target": target,
        if (normalise) "normalise": true,
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
      );

  /// ffmpeg is the master as ffmpeg filters: EQ, glue, level, then -- where
  /// asked -- the loudness brought to the target, and last the limiter, so
  /// nothing after it can take a peak back over the ceiling.
  List<String> get ffmpeg {
    String n(double v) => v.toStringAsFixed(4);
    return [
      ...eqFfmpeg(eq),
      if (comp.on) comp.ffmpeg,
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

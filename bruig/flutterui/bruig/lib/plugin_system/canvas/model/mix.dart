import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
export 'package:bruig/plugin_system/canvas/model/surround.dart'
    show SurroundPan, SpeakerLayout;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonSpec, jsonStr;

// mix.dart is the mix settings: each channel strip and the master strip.
//
// media/mix/dsp.dart is the arithmetic that runs them. A mix also plays
// through SoLoud's filters and Web Audio (interactive EPUB), so each setting
// is defined here in terms all of them can be told exactly:
//
// - the EQ is RBJ biquads, which dsp.dart runs and Web Audio's
//   BiquadFilterNode is. SoLoud's band EQ is given a fit of the curve
//   ([eqBandGains]);
// - balance is a gain per side ([ChannelMix.gains]), not a "pan" each
//   player would read by its own law;
// - the compressor and limiter take the parameters all three share.

/// EqKind is what a band of the EQ does: a cut, a shelf or a bell.
enum EqKind { lowCut, lowShelf, bell, highShelf, highCut }

/// EqSlot is one of the EQ's eight bands, in order up the spectrum.
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

/// eqSlopes are the steepnesses a cut can have, in dB an octave: one to four
/// second-order sections.
const eqSlopes = [12, 24, 36, 48];

/// EqBand is one band: frequency, gain, Q and, for a cut, [slope].
class EqBand {
  final double freq;
  final double gainDb;
  final double q;
  final bool on;

  /// slope is a cut's steepness in dB an octave: one of [eqSlopes].
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
          // Written only when off, so a band present without it is on.
          on: jsonBool(json["on"], true),
          slope: eqSlopes.contains(json["s"]) ? json["s"] as int : 12)
      : fallback;
}

/// Eq is a channel EQ of eight bands: a low cut, a low shelf, four bells, a
/// high shelf and a high cut, then a gain.
///
/// Gains are limited to ±12 dB, as far as SoLoud's band EQ can follow. Older
/// three-band files' "low", "mid" and "high" are still those slots.
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

  /// shaping is whether [slot] changes anything: on, and a cut or non-zero
  /// gain.
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

  /// bandDb is what [slot] alone does to [freq], in dB.
  double bandDb(EqSlot slot, double freq, {double sampleRate = 48000}) {
    var b = band(slot);
    if (!b.on) return 0;
    return [
      for (var q in _sections(slot, b, sampleRate))
        _biquadDb(q, freq, sampleRate)
    ].fold(0.0, (a, v) => a + v);
  }

  /// responseDb is how much this EQ lifts or cuts [freq], in dB: the curve
  /// drawn and the one every player follows.
  double responseDb(double freq, {double sampleRate = 48000}) {
    if (!on) return 0;
    var db = gainDb;
    for (var slot in EqSlot.values) {
      if (shaping(slot)) db += bandDb(slot, freq, sampleRate: sampleRate);
    }
    return db;
  }
}

/// eqBiquads is [eq] as biquads in order up the spectrum, each
/// `[b0, b1, b2, a1, a2]` normalised by a0. [Eq.gainDb] is not included.
List<List<double>> eqBiquads(Eq eq, double sampleRate) => [
      if (eq.on)
        for (var slot in EqSlot.values)
          if (eq.shaping(slot))
            for (var (b0, b1, b2, a0, a1, a2)
                in _sections(slot, eq.band(slot), sampleRate))
              [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0],
    ];

/// _sections is [b] in [slot] as biquads: one for a shelf or bell; for a cut
/// one per 12 dB an octave, the first at the band's Q (so it can resonate),
/// the rest Butterworth.
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

/// eqBandCentres is where SoLoud places [bands] EQ bands: log-spaced from
/// 30 Hz to 16 kHz.
List<double> eqBandCentres(int bands) => [
      for (var i = 0; i < bands; i++)
        bands == 1 ? 1000.0 : 30.0 * math.pow(16000 / 30, i / (bands - 1)),
    ];

/// soloudBands is how many bands the editor's EQ is given: SoLoud's most.
const int soloudBands = 64;

/// soloudBlend is how SoLoud's band EQ weighs its bands at [f]: a triangle
/// round each centre to the midpoints either side, linear in hertz,
/// normalised to sum to one. Mirrors SoLoud's parametric_eq_filter.cpp.
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
/// Fitted, not sampled: SoLoud blends bands linearly between centres, so a
/// curve sampled at the centres is off by up to 3.5 dB between them for a
/// narrow cut. This is a least-squares fit over 30 Hz to 16 kHz, weighted so
/// errors count in dB. Cached, as the audio runtime asks every tick.
List<double> eqBandGains(Eq eq, {int bands = soloudBands}) {
  var key = "$bands ${jsonEncode(eq.toJson())}";
  if (_fitted[key] case var known?) return known;
  if (_fitted.length >= 64) _fitted.remove(_fitted.keys.first);
  return _fitted[key] = List.unmodifiable(_fitBandGains(eq, bands));
}

final Map<String, List<double>> _fitted = {};

List<double> _fitBandGains(Eq eq, int bands) {
  var centres = eqBandCentres(bands);
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
  // Normal equations (A^T W A) g = A^T W t, with a little ridge so a band no
  // point reaches still has an answer.
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

/// AutoGain is a compressor's own makeup: none, enough that 0 dB in comes out
/// at 0 dB, or enough that −12 dB does.
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

  /// kneeDb is the width of the knee at the threshold; nought is hard.
  final double kneeDb;

  /// mix is the wet share: one is all compressed, less is parallel
  /// compression.
  final double mix;

  /// autoGain makes up what is taken off, on top of [makeupDb].
  final AutoGain autoGain;

  /// source is the channel, by key, whose sound it listens to rather than
  /// its own -- a sidechain: a kick pumping a pad, a voice pushing the music
  /// down live -- or "" for its own. See [sidechain].
  final String source;

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
    this.source = "",
  });

  /// sidechain is the channel it listens to, while it is on and has one.
  String? get sidechain => on && source.isNotEmpty ? source : null;

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
    String? source,
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
        source: source ?? this.source,
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
        if (source.isNotEmpty) "source": source,
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
        autoGain: AutoGain.fromName(jsonStr(json["autoGain"])),
        source: jsonStr(json["source"]) ?? "",
      );

  /// reducedDb is [input] dB after threshold, ratio and knee, before
  /// makeup.
  double reducedDb(double input) {
    var t = threshold, r = math.max(1.0, ratio), k = kneeDb;
    if (k <= 0) return input <= t ? input : t + (input - t) / r;
    if (input < t - k / 2) return input;
    if (input > t + k / 2) return t + (input - t) / r;
    var over = input - t + k / 2;
    return input + (1 / r - 1) * over * over / (2 * k);
  }

  /// totalMakeupDb is [makeupDb] plus what [autoGain] adds.
  double get totalMakeupDb {
    var auto = switch (autoGain) {
      AutoGain.off => 0.0,
      AutoGain.zero => -reducedDb(0),
      AutoGain.minus12 => -12 - reducedDb(-12),
    };
    return (makeupDb + math.max(0.0, auto)).clamp(0.0, 36.0);
  }
}

/// DuckCurve is how a ducked channel sinks and comes back.
enum DuckCurve {
  /// hard is no fade: down and up at once.
  hard("Hard"),
  linear("Linear"),

  /// smooth is an S curve, gentlest at both ends.
  smooth("Smooth"),

  /// natural is even in decibels rather than in level, as an ear hears an
  /// even fade.
  natural("Natural");

  final String label;
  const DuckCurve(this.label);

  static DuckCurve fromName(String? name) =>
      values.firstWhere((c) => c.name == name, orElse: () => smooth);
}

/// sceneBusKey is the scene's bus (see CanvasScene.bus) among the strips,
/// wherever a strip is named by key: its meters, its chain.
const sceneBusKey = "\u0000scene";

/// Ducking is a channel (a voice) turning the others down while it is
/// heard. It is set on the voice; every other channel is ducked except those
/// in [except]. The dips are worked out from the voice's recordings, not a
/// live meter, so editing and export agree and the dips can be drawn. See
/// duckEnvelopes in audio_tools.dart.
class Ducking {
  final bool on;

  /// depthDb is how far the other channels sink, below nought.
  final double depthDb;

  /// attack and release are seconds to sink before a line and to come back
  /// after it.
  final double attack;
  final double release;

  /// except are the channels, by key, left alone.
  final List<String> except;

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
        curve: DuckCurve.fromName(jsonStr(json["curve"])),
        except: [
          if (json["except"] is List)
            for (var k in json["except"] as List)
              if (k is String) k,
        ],
      );
}

/// ChannelMix is one channel strip.
/// maxChainDevices is the most devices a chain is read with: each holds
/// buffers once played (a delay's are seconds long), and a received canvas
/// could otherwise ask for tens of thousands.
const int maxChainDevices = 32;

class ChannelMix {
  final double gainDb;

  /// balance is from -1 (left only) to 1 (right only). See [gains].
  final double balance;
  final bool mute;
  final Eq eq;
  final Dynamics comp;

  /// duck is how this channel turns the others down. See [Ducking].
  final Ducking duck;

  /// compFirst is whether the compressor comes before the EQ, stored so
  /// playing and exporting agree. Kept in step with [order], which says
  /// where each goes among the devices too.
  final bool compFirst;

  /// order is the strip's chain as it was last arranged: device ids, and
  /// [chainEq] and [chainComp] for its EQ and compressor. Empty for one
  /// never arranged. Read through [chain], which mends it.
  final List<String> order;

  /// chain is the order the strip runs in: see chainOrder.
  List<String> get chain => chainOrder(devices, order, compFirst);

  /// sidechains are the channels this strip listens to beside its own
  /// sound: a vocoder's carrier, a gate's or the compressor's key. Such a
  /// channel is still played when muted, to be heard through them.
  Set<String> get sidechains => {
        for (var d in devices)
          if (d.sidechain case var c?) c,
        if (comp.sidechain case var c?) c,
      };

  /// sends is how much of this channel also goes to each return, by return
  /// id, in dB. A return not listed is sent nothing.
  final Map<String, double> sends;

  /// surround is where this channel is heard in a surround mix (null: the
  /// front pair), and lfeDb how much also goes to the LFE (null: none).
  /// Ignored in stereo. See surround.dart.
  final SurroundPan? surround;
  final double? lfeDb;

  /// devices are the channel's own devices, in order, before its EQ and
  /// compressor. See devices.dart.
  final List<MixDevice> devices;

  /// speech is the channel's Speech device, if any. See speech_spec.dart.
  final SpeechSpec? speech;

  /// vocaliser is the channel's Vocaliser, if any: its Speech take sung to
  /// a MIDI channel's notes. See media/vocaliser.dart.
  final VocaliserSpec? vocaliser;

  /// automation is the channel's automation lanes. See automation.dart.
  final List<AutomationLane> automation;

  /// output is where the channel goes after its fader: "" the master, or a
  /// return's id (all of it, as a group bus). A missing return means the
  /// master.
  final String output;

  const ChannelMix({
    this.output = "",
    this.automation = const [],
    this.speech,
    this.vocaliser,
    this.devices = const [],
    this.surround,
    this.lfeDb,
    this.sends = const {},
    this.gainDb = 0,
    this.balance = 0,
    this.mute = false,
    this.eq = const Eq(),
    this.comp = const Dynamics(),
    this.duck = const Ducking(),
    this.compFirst = false,
    this.order = const [],
  });

  bool get isDefault =>
      gainDb == 0 &&
      balance == 0 &&
      !mute &&
      !eq.on &&
      !comp.on &&
      !duck.on &&
      !compFirst &&
      order.isEmpty &&
      surround == null &&
      lfeDb == null &&
      sends.isEmpty &&
      devices.isEmpty &&
      speech == null &&
      vocaliser == null &&
      automation.isEmpty &&
      output.isEmpty;

  /// sendDb is how much goes to return [id], or null for none.
  double? sendDb(String id) => sends[id];

  /// withSend sets how much goes to return [id]; null sends nothing.
  ChannelMix withSend(String id, double? db) => copyWith(sends: {
        for (var e in sends.entries)
          if (e.key != id) e.key: e.value,
        if (db != null && db > -90) id: db.clamp(-90.0, 6.0),
      });

  /// gains is the level of each side: the fader, with the balance taking
  /// away from the far side. Balance never boosts, or placing a sound would
  /// change its level.
  (double, double) get gains {
    var level = dbToGain(gainDb);
    var b = balance.clamp(-1.0, 1.0);
    return (level * (b > 0 ? 1 - b : 1), level * (b < 0 ? 1 + b : 1));
  }

  /// withSurround places the channel; null puts it back on the front pair.
  ChannelMix withSurround(SurroundPan? pan) => ChannelMix(
        output: output,
        automation: automation,
        speech: speech,
        vocaliser: vocaliser,
        devices: devices,
        surround: pan,
        lfeDb: lfeDb,
        sends: sends,
        gainDb: gainDb,
        balance: balance,
        mute: mute,
        eq: eq,
        comp: comp,
        duck: duck,
        compFirst: compFirst,
        order: order,
      );

  /// withLfe sets how much goes to the LFE; null sends none.
  ChannelMix withLfe(double? db) => ChannelMix(
        output: output,
        automation: automation,
        speech: speech,
        vocaliser: vocaliser,
        devices: devices,
        surround: surround,
        lfeDb: db == null || db <= -60 ? null : db.clamp(-60.0, 6.0),
        sends: sends,
        gainDb: gainDb,
        balance: balance,
        mute: mute,
        eq: eq,
        comp: comp,
        duck: duck,
        compFirst: compFirst,
        order: order,
      );

  ChannelMix copyWith({
    double? gainDb,
    double? balance,
    bool? mute,
    Eq? eq,
    Dynamics? comp,
    Ducking? duck,
    bool? compFirst,
    List<String>? order,
    Map<String, double>? sends,
    List<MixDevice>? devices,
    SpeechSpec? speech,
    bool noSpeech = false,
    VocaliserSpec? vocaliser,
    bool noVocaliser = false,
    List<AutomationLane>? automation,
    String? output,
  }) =>
      ChannelMix(
        output: output ?? this.output,
        automation: automation ?? this.automation,
        speech: noSpeech ? null : speech ?? this.speech,
        vocaliser: noVocaliser ? null : vocaliser ?? this.vocaliser,
        devices: devices == null ? this.devices : withDeviceIds(devices),
        surround: surround,
        lfeDb: lfeDb,
        sends: sends ?? this.sends,
        gainDb: gainDb ?? this.gainDb,
        balance: balance ?? this.balance,
        mute: mute ?? this.mute,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
        duck: duck ?? this.duck,
        compFirst: compFirst ?? this.compFirst,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        if (gainDb != 0) "gain": gainDb,
        if (balance != 0) "balance": balance,
        if (mute) "mute": true,
        if (eq.on) "eq": eq.toJson(),
        if (comp.on) "comp": comp.toJson(),
        if (duck.on) "duck": duck.toJson(),
        if (compFirst) "compFirst": true,
        if (order.isNotEmpty) "order": order,
        if (sends.isNotEmpty) "sends": sends,
        if (surround case var s?) "surround": s.toJson(),
        if (lfeDb case var l?) "lfe": l,
        if (devices.isNotEmpty) "devices": [for (var d in devices) d.toJson()],
        if (speech case var s?) "speech": s.toJson(),
        if (vocaliser case var v?) "vocaliser": v.toJson(),
        if (automation.isNotEmpty)
          "automation": [for (var a in automation) a.toJson()],
        if (output.isNotEmpty) "output": output,
      };

  factory ChannelMix.fromJson(Map<String, dynamic> json) => ChannelMix(
        automation: [
          if (json["automation"] case List list)
            for (var raw in list)
              if (AutomationLane.fromJson(raw) case var a?) a,
        ],
        speech:
            json["speech"] is Map ? SpeechSpec.fromJson(json["speech"]) : null,
        vocaliser: json["vocaliser"] is Map
            ? VocaliserSpec.fromJson(json["vocaliser"])
            : null,
        devices: withDeviceIds([
          if (json["devices"] case List list)
            for (var raw in list.take(maxChainDevices))
              if (MixDevice.fromJson(raw) case var d?) d,
        ]),
        surround: json["surround"] is Map<String, dynamic>
            ? SurroundPan.fromJson(json["surround"] as Map<String, dynamic>)
            : null,
        lfeDb: json["lfe"] is num
            ? (json["lfe"] as num).toDouble().clamp(-60.0, 6.0)
            : null,
        sends: {
          if (json["sends"] case Map raw)
            for (var e in raw.entries)
              if (e.key is String && e.value is num)
                e.key as String: (e.value as num).toDouble().clamp(-90.0, 6.0),
        },
        gainDb: jsonDouble(json["gain"], 0).clamp(-90.0, 12.0),
        balance: jsonDouble(json["balance"], 0).clamp(-1.0, 1.0),
        mute: jsonBool(json["mute"], false),
        eq: jsonSpec(json["eq"], Eq.fromJson, const Eq()),
        comp: jsonSpec(json["comp"], Dynamics.fromJson, const Dynamics()),
        duck: jsonSpec(json["duck"], Ducking.fromJson, const Ducking()),
        compFirst: jsonBool(json["compFirst"], false),
        order: [
          if (json["order"] case List list)
            for (var o in list.take(maxChainDevices + 2))
              if (o is String) o,
        ],
        output: json["output"] is String ? json["output"] as String : "",
      );
}

/// loudnessTargets are the loudness targets offered, one list for every
/// place a target is chosen (mixer, Canvas settings, Publish).
const loudnessTargets = <(double, String)>[
  (-9, "−9 LUFS · loud master"),
  (-12, "−12 LUFS · CD"),
  (-14, "−14 LUFS · streaming"),
  (-16, "−16 LUFS · podcast"),
  (-18, "−18 LUFS · dynamic"),
  (-23, "−23 LUFS · EBU R128 broadcast"),
  (-24, "−24 LKFS · film & TV"),
];

/// loudnessOptions is [loudnessTargets] plus [current] when it is none of
/// them, so a dropdown always has an item for the value it shows.
List<(double, String)> loudnessOptions(double current) => [
      ...loudnessTargets,
      if (!loudnessTargets.any((t) => t.$1 == current))
        (current, "${current.round()} LUFS"),
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

  /// target is the loudness (LUFS) the mix is aimed at, and normalise
  /// whether an export is measured and adjusted to it.
  final double target;
  final bool normalise;

  /// compFirst is whether the glue comes before the EQ. The limiter is
  /// always last.
  final bool compFirst;

  /// order and chain: see ChannelMix.order. The limiter is not in it: it is
  /// always last.
  final List<String> order;
  List<String> get chain => chainOrder(devices, order, compFirst);

  /// devices are the master's own devices, in order, before its EQ and
  /// glue.
  final List<MixDevice> devices;

  const MasterMix({
    this.devices = const [],
    this.gainDb = 0,
    this.eq = const Eq(),
    this.comp =
        const Dynamics(threshold: -12, ratio: 2, attackMs: 30, releaseMs: 200),
    this.limiter = true,
    this.ceilingDb = -1,
    this.target = -16,
    this.normalise = false,
    this.compFirst = false,
    this.order = const [],
  });

  bool get isDefault =>
      gainDb == 0 &&
      !eq.on &&
      !comp.on &&
      limiter &&
      ceilingDb == -1 &&
      target == -16 &&
      !normalise &&
      !compFirst &&
      order.isEmpty &&
      devices.isEmpty;

  MasterMix copyWith({
    List<MixDevice>? devices,
    double? gainDb,
    Eq? eq,
    Dynamics? comp,
    bool? limiter,
    double? ceilingDb,
    double? target,
    bool? normalise,
    bool? compFirst,
    List<String>? order,
  }) =>
      MasterMix(
        devices: devices == null ? this.devices : withDeviceIds(devices),
        gainDb: gainDb ?? this.gainDb,
        eq: eq ?? this.eq,
        comp: comp ?? this.comp,
        limiter: limiter ?? this.limiter,
        ceilingDb: ceilingDb ?? this.ceilingDb,
        target: target ?? this.target,
        normalise: normalise ?? this.normalise,
        compFirst: compFirst ?? this.compFirst,
        order: order ?? this.order,
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
        if (order.isNotEmpty) "order": order,
        if (devices.isNotEmpty) "devices": [for (var d in devices) d.toJson()],
      };

  factory MasterMix.fromJson(Map<String, dynamic> json) => MasterMix(
        devices: withDeviceIds([
          if (json["devices"] case List list)
            for (var raw in list)
              if (MixDevice.fromJson(raw) case var d?) d,
        ]),
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
        order: [
          if (json["order"] case List list)
            for (var o in list.take(64))
              if (o is String) o,
        ],
      );
}

double dbToGain(double db) => db <= -90 ? 0 : math.pow(10, db / 20).toDouble();

double gainToDb(double gain) =>
    gain <= 0 ? -double.infinity : 20 * math.log(gain) / math.ln10;

// The RBJ "Audio EQ Cookbook" biquads, as Web Audio's BiquadFilterNode
// implements them. Each is (b0, b1, b2, a0, a1, a2).

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

/// _pass is the RBJ high-pass or low-pass at [freq] with [q]: one 12 dB an
/// octave section of a cut.
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
  // |H(e^jw)|: numerator magnitude over denominator, each a quadratic in
  // e^-jw.
  double mag(double c0, double c1, double c2) {
    var re = c0 + c1 * math.cos(w) + c2 * math.cos(2 * w);
    var im = -(c1 * math.sin(w) + c2 * math.sin(2 * w));
    return math.sqrt(re * re + im * im);
  }

  var num = mag(b0, b1, b2), den = mag(a0, a1, a2);
  if (den <= 0 || num <= 0) return 0;
  return 20 * math.log(num / den) / math.ln10;
}

/// chainEq and chainComp are a strip's EQ and compressor in its order (see
/// ChannelMix.order).
const String chainEq = "eq", chainComp = "comp";

/// chainOrder is the order a strip runs in, from its [devices], the [order]
/// it was last arranged in and [compFirst]: what is in [order], in that
/// order, of what is still there; the EQ and the compressor, where it does
/// not have them, last (the compressor first if [compFirst]); and a device
/// it does not have -- one just put on -- before the EQ and compressor
/// where they are last, or else at the end.
List<String> chainOrder(
    List<MixDevice> devices, List<String> order, bool compFirst) {
  var ids = [for (var i = 0; i < devices.length; i++) deviceIdAt(devices, i)];
  var out = <String>[];
  for (var o in order) {
    if ((o == chainEq || o == chainComp || ids.contains(o)) &&
        !out.contains(o)) {
      out.add(o);
    }
  }
  for (var p in compFirst ? [chainComp, chainEq] : [chainEq, chainComp]) {
    if (!out.contains(p)) out.add(p);
  }
  var at = out.length;
  while (at > 0 && (out[at - 1] == chainEq || out[at - 1] == chainComp)) {
    at--;
  }
  var missing = [
    for (var id in ids)
      if (!out.contains(id)) id
  ];
  out.insertAll(at, missing);
  return out;
}

/// compFirstIn is whether [chain] has the compressor before the EQ.
bool compFirstIn(List<String> chain) =>
    chain.indexOf(chainComp) < chain.indexOf(chainEq);

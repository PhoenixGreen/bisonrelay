import 'dart:math' as math;

// instrument_shape.dart is how an instrument plays its sound, set in its
// editor (see instrument_editor.dart) and done by the sampler
// (media/synth/sampler.dart): its volume envelope, a filter with an envelope
// of its own, an LFO, and how its voices go -- one at a time or many, gliding
// from note to note, how far the bend wheel bends, its tuning and how hard a
// key must be struck. As it is by default, it plays the sound as the bank
// (or the built-in voice) has it.

/// VoiceMode is how many notes sound at once: any number; one, each note
/// started afresh; or one, a note played while another is held only moving
/// its pitch, as a singer's legato.
enum VoiceMode {
  poly("Poly", "Any number of notes at once"),
  mono("Mono", "One note at a time, each started afresh"),
  legato(
      "Legato",
      "One note at a time; one played while another is held "
          "only moves the pitch");

  final String label;
  final String hint;
  const VoiceMode(this.label, this.hint);
}

/// SynthFilter is the instrument's filter: none, or what it lets through.
enum SynthFilter {
  off("Off"),
  lowPass("Low-pass"),
  highPass("High-pass"),
  bandPass("Band-pass");

  final String label;
  const SynthFilter(this.label);
}

/// LfoTarget is what the instrument's LFO moves.
enum LfoTarget {
  pitch("Pitch"),
  filter("Filter"),
  volume("Volume");

  final String label;
  const LfoTarget(this.label);
}

/// InstrumentShape is how an instrument plays: see the file comment.
class InstrumentShape {
  /// envelope is whether its own volume envelope -- [attack], [decay],
  /// [sustain], [release] -- shapes each note, rather than the sound's.
  final bool envelope;

  /// attack is seconds to full; decay seconds from there to [sustain] (nought
  /// to one), held while the key is; release seconds to silence after.
  final double attack, decay, sustain, release;

  final SynthFilter filter;

  /// cutoff is the filter's corner, in hertz; resonance its peak there,
  /// nought to one.
  final double cutoff, resonance;

  /// filterEnvelope is how far each note's start opens the filter: up to
  /// four octaves above [cutoff] at one, below at minus one, falling back
  /// over [filterDecay] seconds.
  final double filterEnvelope, filterDecay;

  /// lfoRate is the LFO's speed in hertz, lfoDepth how far it moves
  /// [lfoTarget], nought to one: a semitone either way of pitch, two octaves
  /// of filter, or the whole of the volume.
  final double lfoRate, lfoDepth;
  final LfoTarget lfoTarget;

  final VoiceMode mode;

  /// glide is seconds to slide from one note to the next, in [VoiceMode.mono]
  /// and [VoiceMode.legato].
  final double glide;

  /// voices is how many sound at once, at most.
  final int voices;

  /// bendRange is how far the bend wheel bends, in semitones each way;
  /// tune moves every note, in cents.
  final double bendRange, tune;

  /// velocityCurve is how hard a key must be struck: nought as played, up to
  /// one to need a harder strike, down to minus one a lighter.
  final double velocityCurve;

  const InstrumentShape({
    this.envelope = false,
    this.attack = 0.005,
    this.decay = 0.7,
    this.sustain = 0.3,
    this.release = 0.4,
    this.filter = SynthFilter.off,
    this.cutoff = 5200,
    this.resonance = 0.15,
    this.filterEnvelope = 0,
    this.filterDecay = 0.4,
    this.lfoRate = 5.5,
    this.lfoDepth = 0,
    this.lfoTarget = LfoTarget.pitch,
    this.mode = VoiceMode.poly,
    this.glide = 0.08,
    this.voices = maxVoices,
    this.bendRange = 2,
    this.tune = 0,
    this.velocityCurve = 0,
  });

  /// maxVoices is the most voices an instrument has.
  static const int maxVoices = 64;

  /// plain is the sound as it is: nothing done to it.
  bool get plain => this == const InstrumentShape();

  /// glides is whether one note slides to the next.
  bool get glides => mode != VoiceMode.poly && glide > 0;

  /// velocity is [played] through [velocityCurve].
  int velocity(int played) {
    if (velocityCurve == 0 || played <= 0) return played;
    var u = played.clamp(1, 127) / 127;
    var e = math.pow(2, velocityCurve * 1.5);
    return (127 * math.pow(u, e)).round().clamp(1, 127);
  }

  InstrumentShape copyWith({
    bool? envelope,
    double? attack,
    double? decay,
    double? sustain,
    double? release,
    SynthFilter? filter,
    double? cutoff,
    double? resonance,
    double? filterEnvelope,
    double? filterDecay,
    double? lfoRate,
    double? lfoDepth,
    LfoTarget? lfoTarget,
    VoiceMode? mode,
    double? glide,
    int? voices,
    double? bendRange,
    double? tune,
    double? velocityCurve,
  }) =>
      InstrumentShape(
        envelope: envelope ?? this.envelope,
        attack: (attack ?? this.attack).clamp(0.001, 10),
        decay: (decay ?? this.decay).clamp(0.01, 20),
        sustain: (sustain ?? this.sustain).clamp(0, 1),
        release: (release ?? this.release).clamp(0.01, 20),
        filter: filter ?? this.filter,
        cutoff: (cutoff ?? this.cutoff).clamp(20, 20000),
        resonance: (resonance ?? this.resonance).clamp(0, 1),
        filterEnvelope: (filterEnvelope ?? this.filterEnvelope).clamp(-1, 1),
        filterDecay: (filterDecay ?? this.filterDecay).clamp(0.01, 10),
        lfoRate: (lfoRate ?? this.lfoRate).clamp(0.05, 30),
        lfoDepth: (lfoDepth ?? this.lfoDepth).clamp(0, 1),
        lfoTarget: lfoTarget ?? this.lfoTarget,
        mode: mode ?? this.mode,
        glide: (glide ?? this.glide).clamp(0, 5),
        voices: (voices ?? this.voices).clamp(1, maxVoices),
        bendRange: (bendRange ?? this.bendRange).clamp(0, 24),
        tune: (tune ?? this.tune).clamp(-100, 100),
        velocityCurve: (velocityCurve ?? this.velocityCurve).clamp(-1, 1),
      );

  List<Object> get _fields => [
        envelope,
        attack,
        decay,
        sustain,
        release,
        filter,
        cutoff,
        resonance,
        filterEnvelope,
        filterDecay,
        lfoRate,
        lfoDepth,
        lfoTarget,
        mode,
        glide,
        voices,
        bendRange,
        tune,
        velocityCurve,
      ];

  @override
  bool operator ==(Object other) {
    if (other is! InstrumentShape) return false;
    var a = _fields, b = other._fields;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  /// toJson is only what differs from as it is by default.
  Map<String, dynamic> toJson() {
    const d = InstrumentShape();
    return {
      if (envelope != d.envelope) "envelope": envelope,
      if (attack != d.attack) "attack": attack,
      if (decay != d.decay) "decay": decay,
      if (sustain != d.sustain) "sustain": sustain,
      if (release != d.release) "release": release,
      if (filter != d.filter) "filter": filter.name,
      if (cutoff != d.cutoff) "cutoff": cutoff,
      if (resonance != d.resonance) "resonance": resonance,
      if (filterEnvelope != d.filterEnvelope) "filterEnvelope": filterEnvelope,
      if (filterDecay != d.filterDecay) "filterDecay": filterDecay,
      if (lfoRate != d.lfoRate) "lfoRate": lfoRate,
      if (lfoDepth != d.lfoDepth) "lfoDepth": lfoDepth,
      if (lfoTarget != d.lfoTarget) "lfoTarget": lfoTarget.name,
      if (mode != d.mode) "mode": mode.name,
      if (glide != d.glide) "glide": glide,
      if (voices != d.voices) "voices": voices,
      if (bendRange != d.bendRange) "bendRange": bendRange,
      if (tune != d.tune) "tune": tune,
      if (velocityCurve != d.velocityCurve) "velocityCurve": velocityCurve,
    };
  }

  static InstrumentShape fromJson(Object? raw) {
    if (raw is! Map) return const InstrumentShape();
    const d = InstrumentShape();
    double n(String k, double or) =>
        raw[k] is num ? (raw[k] as num).toDouble() : or;
    T pick<T extends Enum>(List<T> values, String k, T or) =>
        values.where((v) => v.name == raw[k]).firstOrNull ?? or;
    return d.copyWith(
      envelope: raw["envelope"] == true,
      attack: n("attack", d.attack),
      decay: n("decay", d.decay),
      sustain: n("sustain", d.sustain),
      release: n("release", d.release),
      filter: pick(SynthFilter.values, "filter", d.filter),
      cutoff: n("cutoff", d.cutoff),
      resonance: n("resonance", d.resonance),
      filterEnvelope: n("filterEnvelope", d.filterEnvelope),
      filterDecay: n("filterDecay", d.filterDecay),
      lfoRate: n("lfoRate", d.lfoRate),
      lfoDepth: n("lfoDepth", d.lfoDepth),
      lfoTarget: pick(LfoTarget.values, "lfoTarget", d.lfoTarget),
      mode: pick(VoiceMode.values, "mode", d.mode),
      glide: n("glide", d.glide),
      voices: raw["voices"] is num ? (raw["voices"] as num).round() : d.voices,
      bendRange: n("bendRange", d.bendRange),
      tune: n("tune", d.tune),
      velocityCurve: n("velocityCurve", d.velocityCurve),
    );
  }
}

/// instrumentTarget is the instrument among a chain's devices, as a macro's
/// targets name it (ModTarget.device): its settings are the part's, not a
/// device's.
const String instrumentTarget = "instrument";

/// InstrumentKnob is one of the instrument's settings a macro or a
/// controller can turn: its range, and whether it turns on a log scale.
class InstrumentKnob {
  final String id, label;
  final double min, max;
  final bool log;
  const InstrumentKnob(this.id, this.label, this.min, this.max,
      {this.log = false});
}

/// instrumentKnobs are the Instrument card's knobs, as a macro sees them.
const List<InstrumentKnob> instrumentKnobs = [
  InstrumentKnob("attack", "Attack", 0.001, 10, log: true),
  InstrumentKnob("decay", "Decay", 0.01, 20, log: true),
  InstrumentKnob("sustain", "Sustain", 0, 1),
  InstrumentKnob("release", "Release", 0.01, 20, log: true),
  InstrumentKnob("cutoff", "Cutoff", 20, 20000, log: true),
  InstrumentKnob("glide", "Glide", 0, 5),
];

/// instrumentValue is setting [id] of [s].
double instrumentValue(InstrumentShape s, String id) => switch (id) {
      "attack" => s.attack,
      "decay" => s.decay,
      "sustain" => s.sustain,
      "release" => s.release,
      "cutoff" => s.cutoff,
      "glide" => s.glide,
      _ => 0,
    };

/// withInstrumentValue is [s] with setting [id] at [v], as its knob sets it:
/// an envelope knob gives it an envelope of its own, the cutoff a filter.
InstrumentShape withInstrumentValue(InstrumentShape s, String id, double v) =>
    switch (id) {
      "attack" => s.copyWith(attack: v, envelope: true),
      "decay" => s.copyWith(decay: v, envelope: true),
      "sustain" => s.copyWith(sustain: v, envelope: true),
      "release" => s.copyWith(release: v, envelope: true),
      "cutoff" => s.copyWith(
          cutoff: v,
          filter: s.filter == SynthFilter.off ? SynthFilter.lowPass : s.filter),
      "glide" => s.copyWith(glide: v),
      _ => s,
    };

/// turnedBy is [base], setting [k], moved by [amount] -- a share of its
/// travel, as a chain device's knob is moved (see modulation.dart) -- along
/// its own scale: a log one for times and frequencies.
double turnedBy(InstrumentKnob k, double base, double amount) {
  if (!k.log || k.min <= 0) {
    return (base + amount * (k.max - k.min) / 2).clamp(k.min, k.max);
  }
  var lo = math.log(k.min), hi = math.log(k.max);
  var at = math.log(base.clamp(k.min, k.max)) + amount * (hi - lo) / 2;
  return math.exp(at.clamp(lo, hi));
}

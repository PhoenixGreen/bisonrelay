import 'dart:math' as math;

// synth_patch.dart is a synth built of modules patched together (Ken,
// 2026-11-14: "instrument components ... as separate, placeable canvas
// elements ... chainable on the canvas with patch cables"): a keyboard, an
// oscillator, an envelope, a filter, an LFO, an amp, a mixer and a speaker,
// each with its settings, and each input taking a cable from another's
// output. The speaker is an instrument: what it plays, the patch makes
// (see media/synth/patch_voice.dart).

/// SynthSignal is what a jack carries: sound, a control that moves
/// something (an envelope, an LFO), a key held or not, and which key.
enum SynthSignal { audio, mod, gate, pitch }

/// SynthPort is a jack on a module: its name and what it carries.
typedef SynthPort = ({String name, SynthSignal signal});

/// SynthModuleKind is a kind of module: its name, its jacks in and out,
/// and its settings as they start (numbers and choices).
enum SynthModuleKind {
  keys("Keyboard", [], [
    (name: "gate", signal: SynthSignal.gate),
    (name: "pitch", signal: SynthSignal.pitch),
  ], <String, double>{}, <String, String>{}),
  osc("Oscillator", [
    (name: "pitch", signal: SynthSignal.pitch),
    (name: "mod", signal: SynthSignal.mod),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "octave": 0,
    "detune": 0,
    "level": 0.8,
    "mod": 12,
  }, {
    "wave": "sine",
  }),
  noise("Noise", [], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "level": 0.5,
  }, <String, String>{}),
  env("Envelope", [
    (name: "gate", signal: SynthSignal.gate),
  ], [
    (name: "env", signal: SynthSignal.mod),
  ], {
    "a": 0.02,
    "d": 0.25,
    "s": 0.6,
    "r": 0.4,
  }, <String, String>{}),
  lfo("LFO", [], [
    (name: "lfo", signal: SynthSignal.mod),
  ], {
    "rate": 4,
    "depth": 0.5,
  }, {
    "shape": "sine",
  }),
  filter("Filter", [
    (name: "in", signal: SynthSignal.audio),
    (name: "cutoff", signal: SynthSignal.mod),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "cutoff": 2400,
    "res": 1,
    "amount": 3,
  }, {
    "type": "lowpass",
  }),
  amp("Amp", [
    (name: "in", signal: SynthSignal.audio),
    (name: "gain", signal: SynthSignal.mod),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "level": 0.8,
  }, <String, String>{}),
  mixer("Mixer", [
    (name: "a", signal: SynthSignal.audio),
    (name: "b", signal: SynthSignal.audio),
    (name: "c", signal: SynthSignal.audio),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "a": 0.8,
    "b": 0.8,
    "c": 0.8,
  }, <String, String>{}),
  // An echo: what comes in, again and again, quieter each time. Its time
  // can be moved by a control patched in.
  delay("Delay", [
    (name: "in", signal: SynthSignal.audio),
    (name: "time", signal: SynthSignal.mod),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "time": 0.3,
    "feedback": 0.4,
    "mix": 0.35,
  }, <String, String>{}),
  // A room: what comes in, blurred into a tail.
  reverb("Reverb", [
    (name: "in", signal: SynthSignal.audio),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "size": 0.6,
    "damp": 0.4,
    "mix": 0.3,
  }, <String, String>{}),
  // A big screen of what passes through it, passed on as it is.
  scope("Scope", [
    (name: "in", signal: SynthSignal.audio),
  ], [
    (name: "out", signal: SynthSignal.audio),
  ], {
    "zoom": 2,
  }, <String, String>{}),
  out("Speaker", [
    (name: "in", signal: SynthSignal.audio),
  ], [], {
    "volume": 0.7,
  }, <String, String>{});

  final String label;
  final List<SynthPort> ins, outs;

  /// defaults and choiceDefaults are its settings as it starts.
  final Map<String, double> defaults;
  final Map<String, String> choiceDefaults;
  const SynthModuleKind(
      this.label, this.ins, this.outs, this.defaults, this.choiceDefaults);

  SynthPort? input(String name) => ins.where((p) => p.name == name).firstOrNull;
  SynthPort? output(String name) =>
      outs.where((p) => p.name == name).firstOrNull;

  static SynthModuleKind? fromName(String? name) =>
      SynthModuleKind.values.where((k) => k.name == name).firstOrNull;
}

/// synthChoices are what each choosing setting can be.
const synthChoices = <String, List<String>>{
  "wave": ["sine", "triangle", "sawtooth", "square"],
  "shape": ["sine", "triangle", "square", "sawtooth"],
  "type": ["lowpass", "highpass", "bandpass"],
};

/// SynthPlug is the output a cable comes from: a module's, by id, and its
/// jack.
typedef SynthPlug = ({String module, String port});

/// SynthModule is one module in a patch: its kind, its settings, and the
/// cable into each input that has one.
class SynthModule {
  final String id;
  final SynthModuleKind kind;
  final Map<String, double> values;
  final Map<String, String> choices;
  final Map<String, SynthPlug> inputs;

  const SynthModule(this.id, this.kind,
      {this.values = const {},
      this.choices = const {},
      this.inputs = const {}});

  /// value is setting [name], or its kind's starting value.
  double value(String name) => values[name] ?? kind.defaults[name] ?? 0;
  String choice(String name) =>
      choices[name] ?? kind.choiceDefaults[name] ?? "";

  SynthModule copyWith(
          {Map<String, double>? values,
          Map<String, String>? choices,
          Map<String, SynthPlug>? inputs}) =>
      SynthModule(id, kind,
          values: values ?? this.values,
          choices: choices ?? this.choices,
          inputs: inputs ?? this.inputs);

  Map<String, dynamic> toJson() => {
        "id": id,
        "kind": kind.name,
        if (values.isNotEmpty) "values": values,
        if (choices.isNotEmpty) "choices": choices,
        if (inputs.isNotEmpty)
          "inputs": {
            for (var MapEntry(:key, :value) in inputs.entries)
              key: [value.module, value.port],
          },
      };

  static SynthModule? fromJson(Object? j) {
    if (j is! Map) return null;
    var kind = SynthModuleKind.fromName(j["kind"] as String?);
    var id = j["id"];
    if (kind == null || id is! String) return null;
    return SynthModule(id, kind, values: {
      if (j["values"] case Map m)
        for (var e in m.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toDouble(),
    }, choices: {
      if (j["choices"] case Map m)
        for (var e in m.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    }, inputs: {
      if (j["inputs"] case Map m)
        for (var e in m.entries)
          if (e.key is String &&
              e.value is List &&
              (e.value as List).length == 2 &&
              (e.value as List).every((v) => v is String))
            e.key as String: (
              module: (e.value as List)[0] as String,
              port: (e.value as List)[1] as String
            ),
    });
  }
}

/// SynthPatch is the modules a speaker plays: everything its sound comes
/// from, through the cables.
class SynthPatch {
  final List<SynthModule> modules;

  /// speaker is the module that is heard, by id.
  final String speaker;

  /// lanes are knobs turned as it plays -- keyed in the Chain's Design --
  /// each "module/knob" its values [laneRate] a second from the part's
  /// start, held at the last past the end. See at.
  final Map<String, List<double>> lanes;
  final double laneRate;
  const SynthPatch(this.modules, this.speaker,
      {this.lanes = const {}, this.laneRate = 24});

  /// withLanes is it with [lanes], [rate] a second.
  SynthPatch withLanes(Map<String, List<double>> lanes, double rate) =>
      SynthPatch(modules, speaker, lanes: lanes, laneRate: rate);

  /// at is it [t] seconds into its part: each knob in a lane where the
  /// lane has it then, between its steps. Itself with no lanes.
  SynthPatch at(double t) {
    if (lanes.isEmpty) return this;
    var turned = <String, Map<String, double>>{};
    var x = math.max(0.0, t * laneRate);
    for (var MapEntry(:key, :value) in lanes.entries) {
      if (value.isEmpty) continue;
      var slash = key.lastIndexOf("/");
      if (slash < 0) continue;
      var i = x.floor();
      double v;
      if (i >= value.length - 1) {
        v = value.last;
      } else {
        var f = x - i;
        v = value[i] * (1 - f) + value[i + 1] * f;
      }
      (turned[key.substring(0, slash)] ??= {})[key.substring(slash + 1)] = v;
    }
    return SynthPatch([
      for (var m in modules)
        if (turned[m.id] case var vs?)
          m.copyWith(values: {...m.values, ...vs})
        else
          m
    ], speaker, lanes: lanes, laneRate: laneRate);
  }

  SynthModule? byId(String id) => modules.where((m) => m.id == id).firstOrNull;

  /// wiring names the patch's modules and cables, not their settings: two
  /// patches wired alike can share what is sounding as a setting changes.
  String get wiring => [
        for (var m in modules)
          "${m.id}:${m.kind.name}<${[
            for (var MapEntry(:key, :value) in m.inputs.entries)
              "$key=${value.module}.${value.port}"
          ].join(",")}>"
      ].join(";");

  Map<String, dynamic> toJson() => {
        "speaker": speaker,
        "modules": [for (var m in modules) m.toJson()],
        if (lanes.isNotEmpty) ...{
          "lanes": lanes,
          "laneRate": laneRate,
        },
      };

  static SynthPatch? fromJson(Object? j) {
    if (j is! Map || j["speaker"] is! String) return null;
    return SynthPatch(
        [
          for (var m
              in (j["modules"] is List ? j["modules"] as List : const []))
            if (SynthModule.fromJson(m) case var x?) x,
        ],
        j["speaker"] as String,
        lanes: {
          if (j["lanes"] case Map l)
            for (var e in l.entries)
              if (e.key is String && e.value is List)
                e.key as String: [
                  for (var v in e.value as List)
                    if (v is num) v.toDouble()
                ],
        },
        laneRate:
            j["laneRate"] is num ? (j["laneRate"] as num).toDouble() : 24);
  }

  /// heard are the modules the speaker's sound comes from, sources first:
  /// what a voice plays, in the order it works them out. A module patched
  /// into nothing that leads to the speaker is not heard; a loop is cut
  /// where it closes.
  List<SynthModule> get heard {
    var out = <SynthModule>[];
    var seen = <String>{}, on = <String>{};
    void visit(String id) {
      if (seen.contains(id) || on.contains(id)) return;
      var m = byId(id);
      if (m == null) return;
      on.add(id);
      for (var plug in m.inputs.values) {
        visit(plug.module);
      }
      on.remove(id);
      seen.add(id);
      out.add(m);
    }

    visit(speaker);
    return out;
  }
}

/// synthPlugFits is whether a cable from [from] can go into [to]: an
/// output into an input carrying the same.
bool synthPlugFits(SynthPort from, SynthPort to) => from.signal == to.signal;

import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';

// synth_module_element.dart is one synth module on a canvas (Ken,
// 2026-11-14: "instrument components ... as separate, placeable canvas
// elements ... chainable on the canvas with patch cables"): a keyboard, an
// oscillator, an envelope, a filter, an LFO, an amp, a mixer, noise or a
// speaker, drawn as a hardware panel (Analogue) or a soft synth's
// (Digital).
//
// A cable is kept by the module it goes into: each input names the module
// (by element id) and output it comes from, as a SynthModule's inputs do.
// Every module on the canvas is one patch; each speaker plays it on a
// hidden instrument channel of its own (see synth_channels.dart), so it is
// heard, mixed and recorded as any instrument is.
//
// A teacher sets a starting point -- settings and cables -- and a student
// can always get back to it (↺); a module can be locked so its settings
// stay as set.

/// SynthLook is how a module is drawn.
enum SynthLook {
  /// analogue is a Eurorack-style panel: printed legends, corner screws,
  /// skirted knobs, a phosphor screen.
  analogue("Analogue"),

  /// digital is a soft synth's panel: dark, glowing arc knobs, big
  /// screens.
  digital("Digital");

  final String label;
  const SynthLook(this.label);

  static SynthLook fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => analogue);
}

/// SynthModuleElement is one module; see the top of this file.
class SynthModuleElement extends CanvasElement {
  final SynthModuleKind module;
  final Map<String, double> values;
  final Map<String, String> choices;

  /// inputs are the cables into it: each input's source, a module by
  /// element id and its output.
  final Map<String, SynthPlug> inputs;

  /// start is the teacher's starting point -- settings and cables -- that
  /// ↺ goes back to; null, the kind's own settings and no cables.
  final SynthModule? start;

  /// fixed locks its settings for students: drawn dimmed, its knobs not
  /// turned (Ken's "Lock").
  final bool fixed;

  final SynthLook look;

  /// channel is, on a speaker, the hidden instrument channel it plays on.
  final String channel;

  const SynthModuleElement(
    super.base, {
    required this.module,
    this.values = const {},
    this.choices = const {},
    this.inputs = const {},
    this.start,
    this.fixed = false,
    this.look = SynthLook.analogue,
    this.channel = "",
  });

  @override
  ElementKind get kind => ElementKind.synth;

  /// asModule is it as a patch has it, by its element id.
  SynthModule get asModule =>
      SynthModule(id, module, values: values, choices: choices, inputs: inputs);

  double value(String name) => asModule.value(name);
  String choice(String name) => asModule.choice(name);

  /// startValue and startChoice are setting [name] at the starting point.
  double startValue(String name) =>
      (start ?? SynthModule(id, module)).value(name);
  String startChoice(String name) =>
      (start ?? SynthModule(id, module)).choice(name);

  /// changed is whether its settings are not the starting point's.
  bool get changed {
    for (var k in module.defaults.keys) {
      if ((value(k) - startValue(k)).abs() > 1e-9) return true;
    }
    for (var k in module.choiceDefaults.keys) {
      if (choice(k) != startChoice(k)) return true;
    }
    return false;
  }

  /// reset is it back at the starting point's settings, its cables as they
  /// are; with [cables], those too.
  SynthModuleElement reset({bool cables = false}) => SynthModuleElement(base,
      module: module,
      values: start?.values ?? const {},
      choices: start?.choices ?? const {},
      inputs: cables ? start?.inputs ?? const {} : inputs,
      start: start,
      fixed: fixed,
      look: look,
      channel: channel);

  /// startHere makes its settings and cables now the starting point.
  SynthModuleElement startHere() => SynthModuleElement(base,
      module: module,
      values: values,
      choices: choices,
      inputs: inputs,
      start: SynthModule(id, module,
          values: values, choices: choices, inputs: inputs),
      fixed: fixed,
      look: look,
      channel: channel);

  @override
  CanvasElement rebase(ElementBase base) => SynthModuleElement(base,
      module: module,
      values: values,
      choices: choices,
      inputs: inputs,
      start: start,
      fixed: fixed,
      look: look,
      channel: channel);

  SynthModuleElement copyWith({
    Map<String, double>? values,
    Map<String, String>? choices,
    Map<String, SynthPlug>? inputs,
    SynthModule? start,
    bool? fixed,
    SynthLook? look,
    String? channel,
  }) =>
      SynthModuleElement(base,
          module: module,
          values: values ?? this.values,
          choices: choices ?? this.choices,
          inputs: inputs ?? this.inputs,
          start: start ?? this.start,
          fixed: fixed ?? this.fixed,
          look: look ?? this.look,
          channel: channel ?? this.channel);

  /// withValue and withChoice are it with one setting changed.
  SynthModuleElement withValue(String name, double v) =>
      copyWith(values: {...values, name: v});
  SynthModuleElement withChoice(String name, String v) =>
      copyWith(choices: {...choices, name: v});

  /// plugged and unplugged are it with a cable into [input] from [from],
  /// or none.
  SynthModuleElement plugged(String input, SynthPlug from) =>
      copyWith(inputs: {...inputs, input: from});
  SynthModuleElement unplugged(String input) =>
      copyWith(inputs: {...inputs}..remove(input));

  @override
  Map<String, dynamic> props() {
    var m = asModule.toJson()
      ..remove("id")
      ..remove("kind");
    return {
      "module": module.name,
      ...m,
      if (start != null) "start": (start!.toJson()..remove("id")),
      if (fixed) "fixed": true,
      if (look != SynthLook.analogue) "look": look.name,
      if (channel.isNotEmpty) "channel": channel,
    };
  }

  static SynthModuleElement? fromJson(
      Map<String, dynamic> json, ElementBase b) {
    var kind = SynthModuleKind.fromName(json["module"] as String?);
    if (kind == null) return null;
    var m = SynthModule.fromJson({...json, "id": b.id, "kind": kind.name})!;
    var s = json["start"] is Map
        ? SynthModule.fromJson(
            {...(json["start"] as Map), "id": b.id, "kind": kind.name})
        : null;
    return SynthModuleElement(b,
        module: kind,
        values: m.values,
        choices: m.choices,
        inputs: m.inputs,
        start: s,
        fixed: json["fixed"] == true,
        look: SynthLook.fromName(json["look"] as String?),
        channel: json["channel"] is String ? json["channel"] as String : "");
  }
}

/// SynthKnob is one of a module's knobs: the setting it turns, its name on
/// the panel, its range, and how its value is written.
class SynthKnob {
  final String key, label;
  final double min, max;

  /// step is what it moves in (0: smoothly); log turns it on a log scale,
  /// as times and frequencies are heard.
  final double step;
  final bool log;
  final String Function(double) show;
  const SynthKnob(this.key, this.label, this.min, this.max, this.show,
      {this.step = 0, this.log = false});

  /// turn is where [v] is on the knob, nought to one.
  double turn(double v) {
    var x = v.clamp(min, max);
    if (log) return (math.log(x / min) / math.log(max / min)).clamp(0.0, 1.0);
    return max == min ? 0 : (x - min) / (max - min);
  }

  /// at is the value at [t] round the knob.
  double at(double t) {
    t = t.clamp(0.0, 1.0);
    var x = log ? min * math.pow(max / min, t) : min + t * (max - min);
    if (step > 0) x = (x / step).round() * step;
    return x.clamp(min, max).toDouble();
  }
}

String _pct(double v) => "${(v * 100).round()}%";
String _secs(double v) =>
    v < 1 ? "${(v * 1000).round()}ms" : "${v.toStringAsFixed(2)}s";
String _hz(double v) =>
    v >= 1000 ? "${(v / 1000).toStringAsFixed(1)}k" : "${v.round()}";
String _signed(double v) => "${v > 0 ? "+" : ""}${v.round()}";

/// synthKnobs are each kind's knobs, in the order on its panel.
final synthKnobs = <SynthModuleKind, List<SynthKnob>>{
  SynthModuleKind.keys: const [],
  SynthModuleKind.osc: [
    SynthKnob("octave", "Oct", -2, 2, _signed, step: 1),
    SynthKnob("detune", "Fine", -50, 50, (v) => "${v.round()}¢", step: 1),
    SynthKnob("level", "Level", 0, 1, _pct),
    SynthKnob("mod", "Mod", 0, 24, (v) => "${v.round()}st", step: 1),
  ],
  SynthModuleKind.noise: [SynthKnob("level", "Level", 0, 1, _pct)],
  SynthModuleKind.env: [
    SynthKnob("a", "Att", 0.001, 3, _secs, log: true),
    SynthKnob("d", "Dec", 0.01, 3, _secs, log: true),
    SynthKnob("s", "Sus", 0, 1, _pct),
    SynthKnob("r", "Rel", 0.01, 4, _secs, log: true),
  ],
  SynthModuleKind.lfo: [
    SynthKnob("rate", "Rate", 0.05, 20, (v) => "${v.toStringAsFixed(2)}Hz",
        log: true),
    SynthKnob("depth", "Depth", 0, 1, _pct),
  ],
  SynthModuleKind.filter: [
    SynthKnob("cutoff", "Cutoff", 40, 16000, _hz, log: true),
    SynthKnob("res", "Res", 0.1, 20, (v) => v.toStringAsFixed(1)),
    SynthKnob("amount", "Amt", 0, 6, (v) => "${v.toStringAsFixed(1)}oct"),
  ],
  SynthModuleKind.amp: [SynthKnob("level", "Level", 0, 1, _pct)],
  SynthModuleKind.mixer: [
    SynthKnob("a", "A", 0, 1, _pct),
    SynthKnob("b", "B", 0, 1, _pct),
    SynthKnob("c", "C", 0, 1, _pct),
  ],
  SynthModuleKind.out: [SynthKnob("volume", "Volume", 0, 1, _pct)],
};

/// synthChoiceNames are what each choosing setting's options are called
/// on a panel.
const synthChoiceNames = <String, String>{
  "sine": "Sin",
  "triangle": "Tri",
  "sawtooth": "Saw",
  "square": "Sqr",
  "lowpass": "LP",
  "highpass": "HP",
  "bandpass": "BP",
};

/// synthChoiceOf is the choosing setting a kind has, if it has one.
String? synthChoiceOf(SynthModuleKind kind) =>
    kind.choiceDefaults.keys.firstOrNull;

/// synthPanelName is the short name printed on a panel, as on hardware.
String synthPanelName(SynthModuleKind kind) => switch (kind) {
      SynthModuleKind.keys => "KBD",
      SynthModuleKind.osc => "VCO",
      SynthModuleKind.noise => "NOISE",
      SynthModuleKind.env => "ADSR",
      SynthModuleKind.lfo => "LFO",
      SynthModuleKind.filter => "VCF",
      SynthModuleKind.amp => "VCA",
      SynthModuleKind.mixer => "MIX",
      SynthModuleKind.out => "OUT",
    };

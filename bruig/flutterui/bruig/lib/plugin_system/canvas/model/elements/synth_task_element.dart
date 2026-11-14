import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';

// synth_task_element.dart is a task card beside a synth rack (the
// prototype's "Make a soft, slow pad", Ken approved 2026-11-14): what to
// make, a button to hear the teacher's sound, and a list of checks ticked
// as the student's patch meets them.
//
// The teacher doesn't write the checks: they build the sound on the rack
// and set it as the target, and the card keeps that patch (to be heard)
// and makes a check of every cable and setting that differs from the
// rack's starting point -- each worded, its range widened or taken out
// after, as the teacher likes.

/// SynthCheckKind is what a check looks at: a cable, a knob, a choice.
enum SynthCheckKind { cable, value, choice }

/// SynthCheck is one thing the student's patch must do.
class SynthCheck {
  final SynthCheckKind kind;
  final String label;

  /// module is the module it is about, by element id; input its input for
  /// a cable, setting its knob or choice otherwise.
  final String module;
  final String input;
  final String setting;

  /// from is where a cable check's cable comes from.
  final SynthPlug? from;

  /// min and max are a knob's range; choice a choice check's option.
  final double min, max;
  final String choice;

  const SynthCheck(this.kind, this.label,
      {required this.module,
      this.input = "",
      this.setting = "",
      this.from,
      this.min = 0,
      this.max = 0,
      this.choice = ""});

  SynthCheck copyWith({String? label, double? min, double? max}) =>
      SynthCheck(kind, label ?? this.label,
          module: module,
          input: input,
          setting: setting,
          from: from,
          min: min ?? this.min,
          max: max ?? this.max,
          choice: choice);

  /// remapped is it about the modules [ids] maps to, where it does: a
  /// task card copied with its rack.
  SynthCheck remapped(Map<String, String> ids) => SynthCheck(kind, label,
      module: ids[module] ?? module,
      input: input,
      setting: setting,
      from: from == null
          ? null
          : (module: ids[from!.module] ?? from!.module, port: from!.port),
      min: min,
      max: max,
      choice: choice);

  /// met is whether [doc]'s modules do it.
  bool met(CanvasDocument doc) {
    var m = doc.elementById(module);
    if (m is! SynthModuleElement) return false;
    return switch (kind) {
      SynthCheckKind.cable => m.inputs[input] == from,
      SynthCheckKind.value =>
        m.value(setting) >= min - 1e-9 && m.value(setting) <= max + 1e-9,
      SynthCheckKind.choice => m.choice(setting) == choice,
    };
  }

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "label": label,
        "module": module,
        if (input.isNotEmpty) "input": input,
        if (setting.isNotEmpty) "setting": setting,
        if (from case var f?) "from": [f.module, f.port],
        if (kind == SynthCheckKind.value) ...{"min": min, "max": max},
        if (choice.isNotEmpty) "choice": choice,
      };

  static SynthCheck? fromJson(Object? j) {
    if (j is! Map) return null;
    var kind =
        SynthCheckKind.values.where((k) => k.name == j["kind"]).firstOrNull;
    var module = j["module"];
    if (kind == null || module is! String) return null;
    var f = j["from"];
    return SynthCheck(kind, j["label"] is String ? j["label"] as String : "",
        module: module,
        input: j["input"] is String ? j["input"] as String : "",
        setting: j["setting"] is String ? j["setting"] as String : "",
        from: f is List && f.length == 2 && f.every((x) => x is String)
            ? (module: f[0] as String, port: f[1] as String)
            : null,
        min: j["min"] is num ? (j["min"] as num).toDouble() : 0,
        max: j["max"] is num ? (j["max"] as num).toDouble() : 0,
        choice: j["choice"] is String ? j["choice"] as String : "");
  }
}

/// SynthTaskElement is a task card; see the top of this file.
class SynthTaskElement extends CanvasElement {
  final String title;
  final String text;

  /// target is the teacher's sound: the patch "Hear the target" plays,
  /// through [speaker]'s channel. Null until one is set.
  final SynthPatch? target;
  final String speaker;
  final List<SynthCheck> checks;

  const SynthTaskElement(
    super.base, {
    this.title = "Make a sound",
    this.text = "Patch the modules and turn their knobs until your sound "
        "matches the target.",
    this.target,
    this.speaker = "",
    this.checks = const [],
  });

  @override
  ElementKind get kind => ElementKind.synthTask;

  @override
  CanvasElement rebase(ElementBase base) => SynthTaskElement(base,
      title: title,
      text: text,
      target: target,
      speaker: speaker,
      checks: checks);

  SynthTaskElement copyWith({
    String? title,
    String? text,
    SynthPatch? target,
    String? speaker,
    List<SynthCheck>? checks,
  }) =>
      SynthTaskElement(base,
          title: title ?? this.title,
          text: text ?? this.text,
          target: target ?? this.target,
          speaker: speaker ?? this.speaker,
          checks: checks ?? this.checks);

  @override
  Map<String, dynamic> props() => {
        "title": title,
        "text": text,
        if (target case var t?) "target": t.toJson(),
        if (speaker.isNotEmpty) "speaker": speaker,
        if (checks.isNotEmpty) "checks": [for (var c in checks) c.toJson()],
      };

  factory SynthTaskElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      SynthTaskElement(b,
          title: json["title"] is String ? json["title"] as String : "",
          text: json["text"] is String ? json["text"] as String : "",
          target: SynthPatch.fromJson(json["target"]),
          speaker: json["speaker"] is String ? json["speaker"] as String : "",
          checks: [
            if (json["checks"] case List l)
              for (var c in l)
                if (SynthCheck.fromJson(c) case var x?) x,
          ]);
}

/// synthChecksFor are the checks of making [target] from the rack's
/// modules as they start ([modules]' starting points): every cable in it
/// that is not there at the start, every choice that differs, and every
/// knob that is turned -- each a range about the target, a fifth of a
/// turn wide, or up to the end it is near.
List<SynthCheck> synthChecksFor(
    SynthPatch target, List<SynthModuleElement> modules) {
  var byId = {for (var m in modules) m.id: m};
  String name(String id) => byId[id]?.module.label ?? "module";
  var out = <SynthCheck>[];
  for (var t in target.modules) {
    var m = byId[t.id];
    if (m == null) continue;
    var start = m.start ?? SynthModule(m.id, m.module);
    for (var MapEntry(key: input, value: plug) in t.inputs.entries) {
      if (start.inputs[input] == plug) continue;
      out.add(SynthCheck(SynthCheckKind.cable,
          "The ${name(plug.module)}'s ${plug.port} into the ${t.kind.label}'s $input",
          module: t.id, input: input, from: plug));
    }
    for (var c in t.kind.choiceDefaults.keys) {
      if (t.choice(c) == start.choice(c)) continue;
      out.add(SynthCheck(
          SynthCheckKind.choice,
          "${t.kind.label} ${c == "type" ? "type" : c}: "
          "${synthChoiceNames[t.choice(c)] ?? t.choice(c)}",
          module: t.id,
          setting: c,
          choice: t.choice(c)));
    }
    for (var k in synthKnobs[t.kind]!) {
      var at = k.turn(t.value(k.key)), was = k.turn(start.value(k.key));
      if ((at - was).abs() < 0.03) continue;
      var lo = at - 0.1, hi = at + 0.1;
      // Near an end, up to the end: "at least", "at most".
      if (lo < 0.05) lo = 0;
      if (hi > 0.95) hi = 1;
      var min = k.at(lo), max = k.at(hi);
      var label = lo <= 0
          ? "${t.kind.label} ${k.label} at most ${k.show(max)}"
          : hi >= 1
              ? "${t.kind.label} ${k.label} at least ${k.show(min)}"
              : "${t.kind.label} ${k.label} between ${k.show(min)} and ${k.show(max)}";
      out.add(SynthCheck(SynthCheckKind.value, label,
          module: t.id, setting: k.key, min: min, max: max));
    }
  }
  return out;
}

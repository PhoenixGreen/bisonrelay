import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// play_task_element.dart is a task card for an instrument, as a code task is
// for a Code panel: a title and a list of steps, each ticked as the keys
// played on the page do it -- every C found, a tune's notes in order, a
// chord held, a take on the music played well enough -- or ticked by the
// student, for a step no key can show ("say the finger numbers out loud").
// The card is a box and type like a text element's (BoxSpec, TextSpec), so
// it is styled as one.

/// PlayCheckKind is what a step is marked by.
enum PlayCheckKind {
  /// keys: each of [PlayCheck.steps] played, in any order, [PlayCheck.count]
  /// times or more.
  keys("Play these keys"),

  /// order: [PlayCheck.steps] played one after another.
  order("Play these in order"),

  /// along: a take on the music (Play along, or Wait for me) with
  /// [PlayCheck.percent] of its notes right.
  along("Play along with the music"),

  /// self: ticked by the student, on the card.
  self("Ticked by the student");

  final String label;
  const PlayCheckKind(this.label);

  /// byKeys is whether keys played decide it.
  bool get byKeys => this == keys || this == order;
}

/// PlayCheck is one step of a play task.
class PlayCheck {
  final PlayCheckKind kind;

  /// label is what the card says the step is.
  final String label;

  /// steps are the notes, written by name and octave ("C4", "F#3", "Bb2"),
  /// with a chord's notes joined by "+" ("C3+E3+G3"), spaces between.
  final String steps;

  /// count is how many times each of a keys step's notes must be played.
  final int count;

  /// percent is how much of the music an along step must have right.
  final int percent;

  const PlayCheck(this.kind, this.label,
      {this.steps = "", this.count = 1, this.percent = 80});

  PlayCheck copyWith(
          {PlayCheckKind? kind,
          String? label,
          String? steps,
          int? count,
          int? percent}) =>
      PlayCheck(kind ?? this.kind, label ?? this.label,
          steps: steps ?? this.steps,
          count: (count ?? this.count).clamp(1, 99),
          percent: (percent ?? this.percent).clamp(1, 100));

  /// keys are [steps] read: each a set of MIDI notes played together. A
  /// name that is not a note is left out.
  List<Set<int>> get keys => readSteps(steps);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        "label": label,
        if (steps.isNotEmpty) "steps": steps,
        if (count != 1) "count": count,
        if (kind == PlayCheckKind.along) "percent": percent,
      };

  static PlayCheck? fromJson(Object? j) {
    if (j is! Map) return null;
    var kind = PlayCheckKind.values.asNameMap()[j["kind"]];
    if (kind == null) return null;
    return PlayCheck(kind, jsonLabel(j["label"], ""),
        steps: jsonLabel(j["steps"], ""),
        count: jsonInt(j["count"], 1).clamp(1, 99),
        percent: jsonInt(j["percent"], 80).clamp(1, 100));
  }
}

const _pitchClass = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11};

/// noteNumber is the MIDI number of a note written by name, accidental and
/// octave ("C4" is 60; "F#3", "F♯3", "Bb2", "B♭2"), or null.
int? noteNumber(String name) {
  var m = RegExp(r"^([A-Ga-g])([#♯b♭]?)(-?\d)$").firstMatch(name.trim());
  if (m == null) return null;
  var pc = _pitchClass[m.group(1)!.toUpperCase()]!;
  var shift = switch (m.group(2)) {
    "#" || "♯" => 1,
    "b" || "♭" => -1,
    _ => 0,
  };
  var n = (int.parse(m.group(3)!) + 1) * 12 + pc + shift;
  return n < 0 || n > 127 ? null : n;
}

/// readSteps reads a check's steps (see PlayCheck.steps).
List<Set<int>> readSteps(String written) => [
      for (var token in written.split(RegExp(r"[\s,]+")))
        if (token.isNotEmpty)
          if ({
            for (var n in token.split("+"))
              if (noteNumber(n) case var k?) k
          }
              case var chord when chord.isNotEmpty)
            chord,
    ];

/// PlayCheckState is how far a student has got with one check.
class PlayCheckState {
  final bool done;

  /// counts is how often each step has been played (keys); at is the next
  /// step due (order).
  final List<int> counts;
  final int at;

  const PlayCheckState(
      {this.done = false, this.counts = const [], this.at = 0});

  static const fresh = PlayCheckState();
}

/// playedStep is whether pressing [key], with [held] down (it among them),
/// plays [step]: the last of its notes to go down, the rest still held.
bool playedStep(Set<int> step, int key, Set<int> held) =>
    step.contains(key) && step.every(held.contains);

/// heardBy is [state] after [key] is pressed with [held] down, for a check
/// marked by keys; others are left as they are.
PlayCheckState heardBy(
    PlayCheck check, PlayCheckState state, int key, Set<int> held) {
  if (state.done || !check.kind.byKeys) return state;
  var steps = check.keys;
  if (steps.isEmpty) return state;
  if (check.kind == PlayCheckKind.keys) {
    var counts = List<int>.generate(
        steps.length, (i) => i < state.counts.length ? state.counts[i] : 0);
    for (var (i, step) in steps.indexed) {
      if (playedStep(step, key, held)) counts[i]++;
    }
    return PlayCheckState(
        done: counts.every((c) => c >= check.count), counts: counts);
  }
  // In order: the next step played goes on; a key of it goes on waiting for
  // the rest of a chord, or for the same note again; anything else starts
  // over, from the first step if this key was it.
  var at = state.at;
  if (playedStep(steps[at], key, held)) {
    at++;
    return PlayCheckState(done: at >= steps.length, at: at);
  }
  if (steps[at].contains(key)) return state;
  if (at > 0 && steps[at - 1].contains(key)) return state;
  at = playedStep(steps.first, key, held) ? 1 : 0;
  return PlayCheckState(done: at >= steps.length, at: at);
}

/// PlayTaskElement is a play task card; see the top of this file.
class PlayTaskElement extends CanvasElement {
  final String title;

  /// text is what the card says under its title, or "".
  final String text;
  final List<PlayCheck> checks;

  /// passed is what it says once every step is ticked.
  final String passed;

  /// instrument is the instrument whose keys it listens to, by id, or "" for
  /// any on the page; sheet the music an along step is played on, or "" for
  /// the first on the page.
  final String instrument, sheet;

  /// box is the card behind it all; titleSpec its title's type, and spec
  /// the steps' (and [text]'s).
  final BoxSpec box;
  final TextSpec titleSpec, spec;

  /// accent is each step's number and its tick.
  final Color accent;

  const PlayTaskElement(
    super.base, {
    this.title = "Practise",
    this.text = "",
    this.checks = const [],
    this.passed = "Well done! On to the next lesson.",
    this.instrument = "",
    this.sheet = "",
    this.box = const BoxSpec(
        fill: Color(0xFFFFF6E6),
        borderWidth: 2,
        borderColor: Color(0xFFF0DDB8),
        borderRadius: 18,
        padding: 28),
    this.titleSpec = const TextSpec(
        fontFamily: "Inter",
        fontSize: 26,
        weight: 800,
        lineHeight: 1.2,
        color: Color(0xFF1C1B19)),
    this.spec = const TextSpec(
        fontFamily: "Inter",
        fontSize: 21,
        weight: 500,
        lineHeight: 1.45,
        color: Color(0xFF55524C)),
    this.accent = const Color(0xFFE39B2D),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = PlayTaskElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.playTask;

  @override
  CanvasElement rebase(ElementBase base) => PlayTaskElement(base,
      title: title,
      text: text,
      checks: checks,
      passed: passed,
      instrument: instrument,
      sheet: sheet,
      box: box,
      titleSpec: titleSpec,
      spec: spec,
      accent: accent);

  PlayTaskElement copyWith({
    String? title,
    String? text,
    List<PlayCheck>? checks,
    String? passed,
    String? instrument,
    String? sheet,
    BoxSpec? box,
    TextSpec? titleSpec,
    TextSpec? spec,
    Color? accent,
  }) =>
      PlayTaskElement(base,
          title: title ?? this.title,
          text: text ?? this.text,
          checks: checks ?? this.checks,
          passed: passed ?? this.passed,
          instrument: instrument ?? this.instrument,
          sheet: sheet ?? this.sheet,
          box: box ?? this.box,
          titleSpec: titleSpec ?? this.titleSpec,
          spec: spec ?? this.spec,
          accent: accent ?? this.accent);

  /// maxChecks is the most steps a card is read with.
  static const maxChecks = 40;

  @override
  Map<String, dynamic> props() => {
        "title": title,
        if (text.isNotEmpty) "text": text,
        if (checks.isNotEmpty) "checks": [for (var c in checks) c.toJson()],
        "passed": passed,
        if (instrument.isNotEmpty) "instrument": instrument,
        if (sheet.isNotEmpty) "sheet": sheet,
        "box": box.toJson(),
        "titleSpec": titleSpec.toJson(),
        "spec": spec.toJson(),
        "accent": colorToJson(accent),
      };

  factory PlayTaskElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    const plain = PlayTaskElement(ElementBase(id: ""));
    Map<String, dynamic>? map(Object? v) =>
        v is Map<String, dynamic> ? v : null;
    return PlayTaskElement(b,
        title: jsonLabel(json["title"], plain.title),
        text: jsonString(json["text"], _defaults.text),
        checks: [
          for (var c in (json["checks"] is List ? json["checks"] as List : [])
              .take(maxChecks))
            if (PlayCheck.fromJson(c) case var check?) check
        ],
        passed: jsonLabel(json["passed"], plain.passed),
        instrument: jsonId(json["instrument"], _defaults.instrument),
        sheet: jsonId(json["sheet"], _defaults.sheet),
        box: map(json["box"]) == null
            ? plain.box
            : BoxSpec.fromJson(map(json["box"])!),
        titleSpec: map(json["titleSpec"]) == null
            ? plain.titleSpec
            : TextSpec.fromJson(map(json["titleSpec"])!),
        spec: map(json["spec"]) == null
            ? plain.spec
            : TextSpec.fromJson(map(json["spec"])!),
        accent: colorFromJson(json["accent"], plain.accent));
  }
}

import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble;
import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// midi_effects.dart is what a MIDI channel does to its notes before its
// instrument plays them, as Ableton's MIDI effects do: a chord built on each
// note, the notes kept to a scale, a held chord played as an arpeggio, the
// velocities squeezed or roughened.
//
// They act on the notes, not on the sound, so the same chain is used twice:
// on the notes of a part or a clip, before they are played into a file (see
// applyMidiEffects), and on the keys played live, as they are pressed (see
// liveKeys and Arpeggio). What is recorded is what was played, before them --
// so changing an effect changes the recording too, as it does in Ableton.

/// MidiParam is one setting of a MIDI effect: a number, or -- with
/// [choices] -- one of a list, stored as its index.
class MidiParam {
  final String id;
  final String label;
  final double min;
  final double _max;
  final double initial;
  final List<String> choices;
  final String unit;

  const MidiParam(this.id, this.label, this.min, double max, this.initial,
      {this.unit = ""})
      : _max = max,
        choices = const [];

  /// MidiParam.choice is a setting that is one of [choices].
  const MidiParam.choice(this.id, this.label, this.choices, int initial)
      : min = 0,
        _max = 0,
        initial = initial + 0.0,
        unit = "";

  double get max => choices.isNotEmpty ? choices.length - 1.0 : _max;

  bool get isChoice => choices.isNotEmpty;

  /// reading is [v] as the knob says it.
  String reading(double v) {
    if (isChoice) return choices[v.round().clamp(0, choices.length - 1)];
    return switch (unit) {
      "st" => v.round() == 0 ? "off" : "${v > 0 ? "+" : ""}${v.round()} st",
      "%" => "${(v * 100).round()}%",
      "" => "${v.round()}",
      _ => "${v.round()} $unit",
    };
  }
}

/// scaleNames and scaleSteps are the scales the Scale effect keeps notes
/// to: each its semitones from the root.
const scaleNames = [
  "Major",
  "Minor",
  "Harmonic minor",
  "Dorian",
  "Mixolydian",
  "Major pentatonic",
  "Minor pentatonic",
  "Blues",
];
const scaleSteps = [
  [0, 2, 4, 5, 7, 9, 11],
  [0, 2, 3, 5, 7, 8, 10],
  [0, 2, 3, 5, 7, 8, 11],
  [0, 2, 3, 5, 7, 9, 10],
  [0, 2, 4, 5, 7, 9, 10],
  [0, 2, 4, 7, 9],
  [0, 3, 5, 7, 10],
  [0, 3, 5, 6, 7, 10],
];
const noteNames = [
  "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B", //
];

/// arpRates are the arpeggiator's steps, each as a share of a whole note.
const arpRateNames = ["1/4", "1/8", "1/8 T", "1/16", "1/16 T", "1/32"];
const arpRates = [1 / 4, 1 / 8, 1 / 12, 1 / 16, 1 / 24, 1 / 32];
const arpStyleNames = [
  "Up",
  "Down",
  "Up and down",
  "Down and up",
  "As played",
  "Random"
];

/// MidiEffectKind is what a MIDI effect does.
enum MidiEffectKind {
  arpeggiator("Arpeggiator", "Arp", [
    MidiParam.choice("rate", "Rate", arpRateNames, 3),
    MidiParam.choice("style", "Style", arpStyleNames, 0),
    MidiParam("octaves", "Octaves", 1, 4, 1),
    MidiParam("gate", "Gate", 0.1, 1, 0.6, unit: "%"),
  ]),
  chord("Chord", "Chord", [
    MidiParam("shift1", "Note 2", -24, 24, 4, unit: "st"),
    MidiParam("shift2", "Note 3", -24, 24, 7, unit: "st"),
    MidiParam("shift3", "Note 4", -24, 24, 0, unit: "st"),
  ]),
  scale("Scale", "Scale", [
    MidiParam.choice("root", "Root", noteNames, 0),
    MidiParam.choice("scale", "Scale", scaleNames, 0),
  ]),
  velocity("Velocity", "Vel", [
    MidiParam("low", "Lowest", 1, 127, 1),
    MidiParam("high", "Highest", 1, 127, 127),
    MidiParam("random", "Random", 0, 64, 0),
  ]);

  final String label;

  /// short is its name on a strip's slot.
  final String short;
  final List<MidiParam> params;
  const MidiEffectKind(this.label, this.short, this.params);

  MidiParam param(String id) => params.firstWhere((p) => p.id == id);

  static MidiEffectKind? fromName(Object? name) =>
      values.where((k) => k.name == name).firstOrNull;
}

/// MidiEffect is one effect in a MIDI channel's chain: what it is, whether
/// it is on, and the settings that are not its kind's own.
class MidiEffect {
  final MidiEffectKind kind;
  final bool on;
  final Map<String, double> values;

  const MidiEffect(this.kind, {this.on = true, this.values = const {}});

  double value(String id) => values[id] ?? kind.param(id).initial;
  int choice(String id) => value(id).round();

  MidiEffect withValue(String id, double v) {
    var p = kind.param(id);
    var x = v.clamp(p.min, p.max).toDouble();
    if (p.isChoice || p.unit != "%") x = x.roundToDouble();
    return MidiEffect(kind, on: on, values: {...values, id: x});
  }

  MidiEffect switched(bool on) => MidiEffect(kind, on: on, values: values);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
      };

  static MidiEffect? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var kind = MidiEffectKind.fromName(json["kind"]);
    if (kind == null) return null;
    var values = <String, double>{};
    if (json["values"] case Map<String, dynamic> m) {
      for (var p in kind.params) {
        if (m[p.id] != null) {
          values[p.id] =
              jsonDouble(m[p.id], p.initial).clamp(p.min, p.max).toDouble();
        }
      }
    }
    return MidiEffect(kind, on: jsonBool(json["on"], true), values: values);
  }

  @override
  String toString() =>
      "${kind.name}:$on:${[for (var p in kind.params) value(p.id)].join(",")}";
}

/// liveKeys is what one key pressed sounds as, through every effect but
/// the arpeggiator -- which plays over time, and so is not one note's: a
/// chord's keys, each kept to the scale, at the velocity the chain gives.
List<(int, int)> liveKeys(List<MidiEffect> effects, int key, int velocity,
    {math.Random? random}) {
  var out = [(key, velocity)];
  for (var e in effects) {
    if (!e.on) continue;
    out = switch (e.kind) {
      MidiEffectKind.chord => [
          for (var (k, v) in out) ...[
            (k, v),
            for (var id in const ["shift1", "shift2", "shift3"])
              if (e.value(id).round() != 0) (k + e.value(id).round(), v),
          ],
        ],
      MidiEffectKind.scale => [
          for (var (k, v) in out) (_toScale(e, k), v),
        ],
      MidiEffectKind.velocity => [
          for (var (k, v) in out) (k, _velocity(e, v, random)),
        ],
      MidiEffectKind.arpeggiator => out,
    };
  }
  // Each key once, in range.
  var seen = <int>{};
  return [
    for (var (k, v) in out)
      if (k >= 0 && k <= 127 && seen.add(k)) (k, v),
  ];
}

int _toScale(MidiEffect e, int key) {
  var root = e.choice("root");
  var steps = scaleSteps[e.choice("scale").clamp(0, scaleSteps.length - 1)];
  var rel = (key - root) % 12;
  // Down to the nearest note of the scale: a key between two is the one
  // under it, as Ableton's Scale does by default.
  var best = steps.lastWhere((s) => s <= rel, orElse: () => steps.first);
  return key - rel + best;
}

int _velocity(MidiEffect e, int v, math.Random? random) {
  var lo = e.value("low"), hi = math.max(lo, e.value("high"));
  var out = lo + (v - 1) / 126 * (hi - lo);
  var spread = e.value("random");
  if (spread > 0) {
    out += ((random ?? math.Random()).nextDouble() * 2 - 1) * spread;
  }
  return out.round().clamp(1, 127);
}

/// arpeggiatorOf is the chain's first arpeggiator that is on, if it has one.
MidiEffect? arpeggiatorOf(List<MidiEffect> effects) => effects
    .where((e) => e.on && e.kind == MidiEffectKind.arpeggiator)
    .firstOrNull;

/// arpStepSeconds is how long one of [arp]'s steps lasts at [secondsPerBeat]
/// a quarter note.
double arpStepSeconds(MidiEffect arp, double secondsPerBeat) =>
    arpRates[arp.choice("rate").clamp(0, arpRates.length - 1)] *
    4 *
    secondsPerBeat;

/// Arpeggio is the order an arpeggiator plays held keys in: asked for the
/// next key, step by step.
class Arpeggio {
  final MidiEffect arp;
  final math.Random random;
  int _step = 0;
  Arpeggio(this.arp, {math.Random? random}) : random = random ?? math.Random();

  /// sequence is [held] -- in the order they were pressed -- as the style
  /// plays them, through the octaves.
  List<int> sequence(List<int> held) {
    if (held.isEmpty) return const [];
    var octaves = arp.value("octaves").round().clamp(1, 4);
    var sorted = [...held]..sort();
    var style = arp.choice("style");
    var base = style == 4 ? held : sorted;
    var up = [
      for (var o = 0; o < octaves; o++)
        for (var k in base) k + 12 * o,
    ].where((k) => k <= 127).toList();
    return switch (style) {
      1 => up.reversed.toList(),
      2 => up.length < 3
          ? up
          : [...up, ...up.reversed.skip(1).take(up.length - 2)],
      3 => up.length < 3
          ? up.reversed.toList()
          : [...up.reversed, ...up.skip(1).take(up.length - 2)],
      _ => up,
    };
  }

  /// next is the key to play on this step from [held], or null for none.
  int? next(List<int> held) {
    var seq = sequence(held);
    if (seq.isEmpty) return null;
    if (arp.choice("style") == 5) return seq[random.nextInt(seq.length)];
    return seq[_step++ % seq.length];
  }

  void reset() => _step = 0;
}

/// applyMidiEffects is [notes] -- starts and lengths in seconds -- as the
/// chain plays them: for a part or a clip, before its instrument plays it
/// into a file. [secondsPerBeat] times the arpeggiator. The random parts
/// are seeded, so the same notes always make the same file.
List<MidiNote> applyMidiEffects(
    List<MidiNote> notes, List<MidiEffect> effects, double secondsPerBeat) {
  if (notes.isEmpty || !effects.any((e) => e.on)) return notes;
  var random = math.Random(notes.length * 31 + effects.length);
  // Chord, scale and velocity on each note, in the chain's order; the
  // arpeggiator over what they make.
  var out = <MidiNote>[
    for (var n in notes)
      for (var (k, v) in liveKeys(effects, n.key, n.velocity, random: random))
        MidiNote(k, n.start, n.length, v),
  ];
  var arp = arpeggiatorOf(effects);
  if (arp == null) return out..sort((a, b) => a.start.compareTo(b.start));
  var step = math.max(0.01, arpStepSeconds(arp, secondsPerBeat));
  var gate = arp.value("gate").clamp(0.1, 1.0);
  var player = Arpeggio(arp, random: random);
  var end = out.map((n) => n.end).reduce(math.max);
  var played = <MidiNote>[];
  // Held as pressed: by when each started.
  var byStart = [...out]..sort((a, b) => a.start.compareTo(b.start));
  List<int>? was;
  // From the first note, on the step grid from nought, as the transport's.
  var t = (byStart.first.start / step).floor() * step;
  for (; t < end - 1e-6; t += step) {
    var held = [
      for (var n in byStart)
        if (n.start <= t + 1e-6 && n.end > t + 1e-6) n,
    ];
    var keys = [for (var n in held) n.key];
    if (keys.isEmpty) {
      player.reset();
      was = null;
      continue;
    }
    // A new chord starts its pattern again.
    if (was == null || !_sameKeys(was, keys)) player.reset();
    was = keys;
    var key = player.next(keys);
    if (key == null) continue;
    var velocity = held.map((n) => n.velocity).reduce(math.max);
    played.add(MidiNote(key, t, step * gate, velocity));
  }
  return played;
}

bool _sameKeys(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var sa = {...a};
  return b.every(sa.contains);
}

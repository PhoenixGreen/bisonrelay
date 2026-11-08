import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonInt, jsonDouble, jsonStr;
import 'package:bruig/plugin_system/canvas/model/instrument_shape.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:crypto/crypto.dart';

export 'package:bruig/plugin_system/canvas/model/instrument_shape.dart';

// instrument.dart is an instrument's part: the notes it plays, the sound it
// plays them with, and the keyboard it is drawn as.
//
// An instrument is an Audio element with a part. Its notes are rendered
// (media/synth/sampler.dart) into an ordinary sound file, its clip's file, so
// everywhere else it is a sound like any other and a canvas sent to someone
// without the sound bank still plays. Played live it is the sampler itself,
// on the same channel.

/// MidiNote is one note: which key (MIDI's numbering, middle C is 60),
/// when and for how long (seconds in a part, beats in a clip), and how hard.
class MidiNote {
  final int key;
  final double start;
  final double length;
  final int velocity;

  /// muted is a note kept but not played: drawn hollow.
  final bool muted;

  /// chance is how likely it is to play each time round, nought to one:
  /// the same each time for the same note (see InstrumentPart.played).
  final double chance;

  const MidiNote(this.key, this.start, this.length,
      [this.velocity = 96, this.muted = false, this.chance = 1]);

  double get end => start + length;

  MidiNote copyWith(
          {int? key,
          double? start,
          double? length,
          int? velocity,
          bool? muted,
          double? chance}) =>
      MidiNote(
          (key ?? this.key).clamp(0, 127),
          // Within an hour: a part is rendered as long as its last note.
          (start ?? this.start).clamp(0.0, 3600.0),
          (length ?? this.length).clamp(0.01, 3600.0),
          (velocity ?? this.velocity).clamp(1, 127),
          muted ?? this.muted,
          (chance ?? this.chance).clamp(0.0, 1.0));

  List<num> toJson() => [
        key,
        _round(start),
        _round(length),
        velocity,
        if (chance != 1 || muted) ...[_round(chance), if (muted) 1],
      ];

  static double _round(double v) => (v * 10000).round() / 10000;

  static MidiNote? fromJson(Object? json) {
    if (json is! List || json.length < 3) return null;
    return const MidiNote(60, 0, 1).copyWith(
        key: jsonInt(json[0], 60),
        start: jsonDouble(json[1], 0),
        length: jsonDouble(json[2], 0.5),
        velocity: json.length > 3 ? jsonInt(json[3], 96) : 96,
        chance: json.length > 4 ? jsonDouble(json[4], 1) : 1,
        muted: json.length > 5 && jsonInt(json[5], 0) == 1);
  }

  @override
  bool operator ==(Object other) =>
      other is MidiNote &&
      other.key == key &&
      other.start == start &&
      other.length == length &&
      other.velocity == velocity &&
      other.muted == muted &&
      other.chance == chance;

  @override
  int get hashCode => Object.hash(key, start, length, velocity, muted, chance);
}

/// notesHeard is [notes] as they play: without the muted, and each with a
/// chance below one kept or not by a roll that is the same each time for
/// the same note, so a part sounds the same played and exported. [notes]
/// itself where every note plays.
List<MidiNote> notesHeard(List<MidiNote> notes) {
  if (notes.every((n) => !n.muted && n.chance >= 1)) return notes;
  return [
    for (var n in notes)
      if (!n.muted && (n.chance >= 1 || _roll(n) < n.chance)) n,
  ];
}

/// _roll is a number from nought to one for [n]: its key and its start.
double _roll(MidiNote n) {
  var x = (n.key * 73856093 ^ (n.start * 1000).round() * 19349663) & 0xFFFFFFFF;
  x ^= x >> 15;
  x = (x * 0x85EBCA77) & 0xFFFFFFFF;
  x ^= x >> 13;
  x = (x * 0xC2B2AE3D) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x / 0xFFFFFFFF;
}

/// InstrumentSound is what an instrument's notes are played with.
enum InstrumentSound {
  /// builtin is the small piano of our own: always there.
  builtin("Built-in piano"),

  /// bank is the General MIDI sound bank, once it has been downloaded.
  bank("MuseScore General"),

  /// slices are a sound cut at its hits, each played by a key of its own:
  /// see SliceKit.
  slices("Slices of a sound");

  final String label;
  const InstrumentSound(this.label);

  static InstrumentSound fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => builtin);
}

/// SliceKit is an instrument made of a sound cut into slices -- a clip
/// sliced "into a note clip" or "into drum pads", as the prototype's -- each
/// slice played by its own key, at its own pitch, to its end.
class SliceKit {
  /// assetId is the stored sound; cuts are where it is cut, in seconds
  /// into it, first and last included: slice i runs from cuts[i] to
  /// cuts[i + 1].
  final String assetId;
  final List<double> cuts;

  /// keys are the key each slice is played by, in order.
  final List<int> keys;

  /// oneShot is whether a slice plays to its end once struck, as a drum
  /// pad's does, rather than stopping when its key is let go.
  final bool oneShot;
  const SliceKit(this.assetId, this.cuts, this.keys, {this.oneShot = false});

  int get count => math.min(keys.length, math.max(0, cuts.length - 1));

  /// key is what its sound depends on, for a cache.
  String get key =>
      "$assetId|${cuts.join(",")}|${keys.join(",")}|${oneShot ? 1 : 0}";

  Map<String, dynamic> toJson() => {
        "asset": assetId,
        "cuts": [for (var c in cuts) (c * 10000).round() / 10000],
        "keys": keys,
        if (oneShot) "oneShot": true,
      };

  static SliceKit? fromJson(Object? json) {
    if (json is! Map) return null;
    var asset = json["asset"];
    if (asset is! String || asset.isEmpty) return null;
    return SliceKit(
        asset,
        [
          if (json["cuts"] case List list)
            for (var c in list)
              if (c is num) c.toDouble(),
        ],
        [
          if (json["keys"] case List list)
            for (var k in list)
              if (k is num) k.toInt().clamp(0, 127),
        ],
        oneShot: json["oneShot"] == true);
  }

  @override
  bool operator ==(Object other) => other is SliceKit && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// InstrumentLook is what an instrument is played on, and drawn as.
enum InstrumentLook {
  keyboard("Keyboard", 0, 0),
  drums("Drum pads", 128, 0),
  guitar("Guitar", 0, 25),
  bass("Bass guitar", 0, 33);

  final String label;

  /// bank and program are the General MIDI sound it starts with: a drum kit
  /// is bank 128, a steel-string guitar program 25, a fingered bass 33.
  final int bank, program;
  const InstrumentLook(this.label, this.bank, this.program);

  static InstrumentLook fromName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => keyboard);
}

/// drumPads are the pads of a drum kit, in rows from the top: General
/// MIDI's key for each, and its name.
const drumPads = <(int, String)>[
  (49, "Crash"),
  (51, "Ride"),
  (46, "Open hat"),
  (42, "Closed hat"),
  (50, "High tom"),
  (48, "Mid tom"),
  (45, "Low tom"),
  (41, "Floor tom"),
  (39, "Clap"),
  (37, "Rim"),
  (54, "Tambourine"),
  (56, "Cowbell"),
  (36, "Kick"),
  (38, "Snare"),
  (40, "Snare 2"),
  (44, "Pedal hat"),
];

/// guitarStrings and bassStrings are the open strings, lowest first.
const guitarStrings = [40, 45, 50, 55, 59, 64];
const bassStrings = [28, 33, 38, 43];

/// frets is how many frets a neck is drawn with.
const frets = 15;

/// fretFor is where [key] is played on [strings]: the string and fret
/// nearest the nut that has it, or null for a key the neck has not.
(int, int)? fretFor(int key, List<int> strings) {
  (int, int)? best;
  for (var (i, open) in strings.indexed) {
    var fret = key - open;
    if (fret < 0 || fret > frets) continue;
    if (best == null || fret < best.$2) best = (i, fret);
  }
  return best;
}

/// InstrumentPart is an instrument's part.
class InstrumentPart {
  final InstrumentSound sound;

  /// look is what it is played on: a keyboard, drum pads, a neck.
  final InstrumentLook look;

  /// bank and program are the General MIDI sound, where [sound] is the bank:
  /// program 0 is the grand piano.
  final int bank, program;

  /// withLook is played on [look]: its General MIDI sound with it.
  InstrumentPart withLook(InstrumentLook look) =>
      copyWith(look: look, bank: look.bank, program: look.program);

  /// lowKey and keys are the keyboard drawn: its lowest key and how many,
  /// to the eighty-eight of a piano.
  final int lowKey, keys;

  final List<MidiNote> notes;

  /// controls are its controllers' curves -- expression, the mod wheel,
  /// pitch bend and the rest -- in seconds, as its notes are.
  final Map<MidiControl, List<ControlPoint>> controls;

  /// effects are the channel's MIDI effects, in order: what is done to the
  /// notes before they are played. See midi_effects.dart.
  final List<MidiEffect> effects;

  /// input is where the channel's notes come from live: "" for every MIDI
  /// input, [noInput] for none, or one keyboard's name.
  final String input;

  /// monitor is when what comes in is heard -- see MidiMonitor.
  final MidiMonitor monitor;

  /// rendered is the [signature] the clip's file was rendered from, so it is
  /// rendered again only when that changes.
  final String rendered;

  /// shape is how it plays its sound: its envelope, filter, LFO and voices.
  /// See instrument_shape.dart.
  final InstrumentShape shape;

  /// quantise and swing are its feel as it plays, as the prototype's Note
  /// clips card: how far (0 to 1) each note is pulled onto the sixteenth
  /// grid, and how far every second sixteenth is pushed late (at 1, a third
  /// of a step). The notes themselves are left as drawn.
  final double quantise, swing;

  /// grooved is whether [quantise] or [swing] changes what it plays.
  bool get grooved => quantise > 0 || swing > 0;

  const InstrumentPart({
    this.look = InstrumentLook.keyboard,
    this.sound = InstrumentSound.builtin,
    this.bank = 0,
    this.program = 0,
    this.lowKey = 48,
    this.keys = 25,
    this.notes = const [],
    this.effects = const [],
    this.controls = const {},
    this.input = "",
    this.monitor = MidiMonitor.auto,
    this.rendered = "",
    this.shape = const InstrumentShape(),
    this.slices,
    this.quantise = 0,
    this.swing = 0,
  });

  /// slices are what it plays where its sound is [InstrumentSound.slices].
  final SliceKit? slices;

  /// highKey is the keyboard's top key.
  int get highKey => lowKey + keys - 1;

  /// length is how long the part plays: to the end of its last note, and
  /// the release after it.
  double get length => notes.isEmpty
      ? 0
      : notes.map((n) => n.end).reduce(math.max) + releaseTail;

  /// releaseTail is how long a note is let ring after its end.
  static const double releaseTail = 1.5;

  /// name is the sound's name: its General MIDI name in the bank, or the
  /// built-in piano.
  String get name => sound == InstrumentSound.slices
      ? "Slices"
      : sound == InstrumentSound.builtin
          ? switch (look) {
              InstrumentLook.keyboard => "Piano",
              InstrumentLook.drums => "Drums",
              InstrumentLook.guitar => "Guitar",
              InstrumentLook.bass => "Bass",
            }
          : bank == 128
              ? "Drum kit"
              : gmPrograms[program.clamp(0, 127)];

  /// signature is a short hash of what the part sounds like: the same
  /// signature is the same file. Worked out once per part (parts never
  /// change): every edit asks whether each part needs playing again.
  String get signature => _signatures[this] ??= _sign();

  static final Expando<String> _signatures = Expando();

  String _sign() {
    var text = jsonEncode([
      // The look changes the sound only for the built-in instrument.
      if (sound == InstrumentSound.builtin) look.name,
      sound.name,
      if (sound == InstrumentSound.slices) slices?.key,
      bank,
      program,
      for (var n in notes) n.toJson(),
      for (var e in effects)
        if (e.on) e.toString(),
      if (controls.isNotEmpty) controlsToJson(controls),
      // As it is by default, nothing: a part from before keeps its file.
      if (!shape.plain) shape.toJson(),
      if (grooved) "groove $quantise $swing",
    ]);
    return sha256.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  /// signatureAt is [signature] at a tempo of [secondsPerBeat] a beat: an
  /// arpeggiator's steps follow the tempo, so its part sounds different at
  /// another. Without one, the tempo changes nothing.
  String signatureAt(double secondsPerBeat) =>
      arpeggiatorOf(effects) == null && !grooved
          ? signature
          : "$signature@${secondsPerBeat.toStringAsFixed(4)}";

  /// needsPlayingAt is whether the part's file is not this part's at a
  /// tempo of [secondsPerBeat] a beat (see [signatureAt]).
  bool needsPlayingAt(double secondsPerBeat) =>
      notes.isNotEmpty && rendered != signatureAt(secondsPerBeat);

  /// played is the part as its instrument plays it: its notes through its
  /// effects, at [secondsPerBeat] a beat.
  InstrumentPart played(double secondsPerBeat) {
    var heard = groovedNotes(notesHeard(notes), secondsPerBeat,
        quantise: quantise, swing: swing);
    if (effects.isEmpty) {
      return identical(heard, notes) ? this : copyWith(notes: heard);
    }
    return copyWith(notes: applyMidiEffects(heard, effects, secondsPerBeat));
  }

  /// sounding is the keys down at [seconds] into the part.
  Set<int> sounding(double seconds) => {
        for (var n in notes)
          if (seconds >= n.start && seconds < n.end) n.key,
      };

  InstrumentPart copyWith({
    InstrumentLook? look,
    InstrumentSound? sound,
    int? bank,
    int? program,
    int? lowKey,
    int? keys,
    List<MidiNote>? notes,
    List<MidiEffect>? effects,
    Map<MidiControl, List<ControlPoint>>? controls,
    String? input,
    MidiMonitor? monitor,
    String? rendered,
    InstrumentShape? shape,
    SliceKit? slices,
    double? quantise,
    double? swing,
  }) {
    var k = (keys ?? this.keys).clamp(12, 88);
    return InstrumentPart(
      look: look ?? this.look,
      sound: sound ?? this.sound,
      bank: (bank ?? this.bank).clamp(0, 128),
      program: (program ?? this.program).clamp(0, 127),
      lowKey: (lowKey ?? this.lowKey).clamp(0, 127 - k + 1),
      keys: k,
      notes: notes ?? this.notes,
      effects: effects ?? this.effects,
      controls: controls ?? this.controls,
      input: input ?? this.input,
      monitor: monitor ?? this.monitor,
      rendered: rendered ?? this.rendered,
      shape: shape ?? this.shape,
      slices: slices ?? this.slices,
      quantise: (quantise ?? this.quantise).clamp(0.0, 1.0),
      swing: (swing ?? this.swing).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() => {
        if (look != InstrumentLook.keyboard) "look": look.name,
        if (sound != InstrumentSound.builtin) "sound": sound.name,
        if (bank != 0) "bank": bank,
        if (program != 0) "program": program,
        "low": lowKey,
        "keys": keys,
        if (notes.isNotEmpty) "notes": [for (var n in notes) n.toJson()],
        if (effects.isNotEmpty) "effects": [for (var e in effects) e.toJson()],
        if (controls.isNotEmpty) "controls": controlsToJson(controls),
        if (input.isNotEmpty) "input": input,
        if (monitor != MidiMonitor.auto) "monitor": monitor.name,
        if (rendered.isNotEmpty) "rendered": rendered,
        if (!shape.plain) "shape": shape.toJson(),
        if (slices case var k?) "slices": k.toJson(),
        if (quantise > 0) "quantise": quantise,
        if (swing > 0) "swing": swing,
      };

  factory InstrumentPart.fromJson(Map<String, dynamic> json) =>
      const InstrumentPart().copyWith(
        look: InstrumentLook.fromName(jsonStr(json["look"])),
        sound: InstrumentSound.fromName(jsonStr(json["sound"])),
        bank: jsonInt(json["bank"], 0),
        program: jsonInt(json["program"], 0),
        lowKey: jsonInt(json["low"], 48),
        keys: jsonInt(json["keys"], 25),
        notes: [
          if (json["notes"] case List list)
            for (var raw in list)
              if (MidiNote.fromJson(raw) case var n?) n,
        ]..sort((a, b) => a.start.compareTo(b.start)),
        effects: [
          if (json["effects"] case List list)
            for (var raw in list)
              if (MidiEffect.fromJson(raw) case var e?) e,
        ],
        controls: controlsFromJson(json["controls"]),
        input: json["input"] is String ? json["input"] as String : "",
        monitor: MidiMonitor.values
                .where((m) => m.name == json["monitor"])
                .firstOrNull ??
            MidiMonitor.auto,
        rendered: json["rendered"] is String ? json["rendered"] as String : "",
        shape: InstrumentShape.fromJson(json["shape"]),
        slices: SliceKit.fromJson(json["slices"]),
        quantise: jsonDouble(json["quantise"], 0),
        swing: jsonDouble(json["swing"], 0),
      );
}

/// groovedNotes is [notes] (in seconds, at [secondsPerBeat] a beat) with a
/// feel: each pulled [quantise] of the way onto the nearest sixteenth, and
/// those on every second sixteenth pushed [swing] of a third of a step late.
/// Each keeps its length; with neither, [notes] as they are.
List<MidiNote> groovedNotes(List<MidiNote> notes, double secondsPerBeat,
    {double quantise = 0, double swing = 0}) {
  if (notes.isEmpty || (quantise <= 0 && swing <= 0)) return notes;
  var grid = secondsPerBeat / 4;
  if (grid <= 0) return notes;
  return [
    for (var n in notes)
      () {
        var step = (n.start / grid).round();
        var start = n.start + (step * grid - n.start) * quantise;
        // Swung only what sits on an off-beat sixteenth once pulled in.
        if (swing > 0 && step.isOdd && (start - step * grid).abs() < grid / 4) {
          start += swing * grid / 3;
        }
        return n.copyWith(start: math.max(0.0, start));
      }(),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// noInput is a MIDI channel's input when it takes none.
const noInput = "none";

/// MidiMonitor is when a MIDI channel plays what comes in, as Ableton's
/// Monitor: always, only while it is armed, or never -- its clips and its
/// part alone.
enum MidiMonitor {
  input("In", "Always plays what comes in"),
  auto("Auto", "Plays what comes in while it is armed"),
  off("Off", "Never plays what comes in: only its clips and its part");

  final String label;
  final String hint;
  const MidiMonitor(this.label, this.hint);
}

/// keyboards are the keyboards offered: a lowest key and how many.
const keyboards = <(String, int, int)>[
  ("2 octaves", 48, 25),
  ("3 octaves", 48, 37),
  ("4 octaves", 36, 49),
  ("61 keys", 36, 61),
  ("76 keys", 28, 76),
  ("88 keys, a piano", 21, 88),
];

/// isBlackKey is whether [key] is a black key.
bool isBlackKey(int key) => const {1, 3, 6, 8, 10}.contains(key % 12);

/// gmPrograms are General MIDI's 128 sounds, by program number.
const gmPrograms = [
  "Acoustic grand piano",
  "Bright acoustic piano",
  "Electric grand piano",
  "Honky-tonk piano",
  "Electric piano 1",
  "Electric piano 2",
  "Harpsichord",
  "Clavinet",
  "Celesta",
  "Glockenspiel",
  "Music box",
  "Vibraphone",
  "Marimba",
  "Xylophone",
  "Tubular bells",
  "Dulcimer",
  "Drawbar organ",
  "Percussive organ",
  "Rock organ",
  "Church organ",
  "Reed organ",
  "Accordion",
  "Harmonica",
  "Tango accordion",
  "Nylon guitar",
  "Steel guitar",
  "Jazz guitar",
  "Clean electric guitar",
  "Muted electric guitar",
  "Overdriven guitar",
  "Distortion guitar",
  "Guitar harmonics",
  "Acoustic bass",
  "Fingered bass",
  "Picked bass",
  "Fretless bass",
  "Slap bass 1",
  "Slap bass 2",
  "Synth bass 1",
  "Synth bass 2",
  "Violin",
  "Viola",
  "Cello",
  "Contrabass",
  "Tremolo strings",
  "Pizzicato strings",
  "Orchestral harp",
  "Timpani",
  "String ensemble 1",
  "String ensemble 2",
  "Synth strings 1",
  "Synth strings 2",
  "Choir aahs",
  "Voice oohs",
  "Synth voice",
  "Orchestra hit",
  "Trumpet",
  "Trombone",
  "Tuba",
  "Muted trumpet",
  "French horn",
  "Brass section",
  "Synth brass 1",
  "Synth brass 2",
  "Soprano sax",
  "Alto sax",
  "Tenor sax",
  "Baritone sax",
  "Oboe",
  "English horn",
  "Bassoon",
  "Clarinet",
  "Piccolo",
  "Flute",
  "Recorder",
  "Pan flute",
  "Blown bottle",
  "Shakuhachi",
  "Whistle",
  "Ocarina",
  "Square lead",
  "Sawtooth lead",
  "Calliope lead",
  "Chiff lead",
  "Charang lead",
  "Voice lead",
  "Fifths lead",
  "Bass + lead",
  "New age pad",
  "Warm pad",
  "Polysynth pad",
  "Choir pad",
  "Bowed pad",
  "Metallic pad",
  "Halo pad",
  "Sweep pad",
  "Rain",
  "Soundtrack",
  "Crystal",
  "Atmosphere",
  "Brightness",
  "Goblins",
  "Echoes",
  "Sci-fi",
  "Sitar",
  "Banjo",
  "Shamisen",
  "Koto",
  "Kalimba",
  "Bagpipe",
  "Fiddle",
  "Shanai",
  "Tinkle bell",
  "Agogo",
  "Steel drums",
  "Woodblock",
  "Taiko drum",
  "Melodic tom",
  "Synth drum",
  "Reverse cymbal",
  "Guitar fret noise",
  "Breath noise",
  "Seashore",
  "Bird tweet",
  "Telephone ring",
  "Helicopter",
  "Applause",
  "Gunshot",
];

/// MidiControl is one of the controllers a part can carry besides its
/// notes, as a curve under them in the piano roll -- each a MIDI controller,
/// or pitch bend, which MIDI keeps apart.
enum MidiControl {
  expression("Expression", 11, 1),
  modulation("Modulation", 1, 0),
  pitchBend("Pitch bend", -1, 0.5),
  sustain("Sustain", 64, 0),
  volume("Volume", 7, 100 / 127),
  pan("Pan", 10, 0.5);

  final String label;

  /// cc is its MIDI controller number; -1 for pitch bend.
  final int cc;

  /// rest is where it sits when nothing moves it, nought to one: pitch
  /// bend and pan in the middle, volume at General MIDI's hundred.
  final double rest;
  const MidiControl(this.label, this.cc, this.rest);

  static MidiControl? ofCc(int cc) =>
      values.where((c) => c.cc == cc).firstOrNull;
}

/// ControlPoint is a point on a controller's curve: when, in the part's
/// time -- seconds for a part, beats for a clip -- and the value there,
/// nought to one. Between two points the value goes in a straight line.
typedef ControlPoint = (double, double);

/// controlAt is [points]' value at [t]: the first's before it, the last's
/// after it, a straight line between -- or [rest] with no points at all.
double controlAt(List<ControlPoint> points, double t, double rest) {
  if (points.isEmpty) return rest;
  if (t <= points.first.$1) return points.first.$2;
  for (var i = 1; i < points.length; i++) {
    var (t1, v1) = points[i];
    if (t < t1) {
      var (t0, v0) = points[i - 1];
      return t1 <= t0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
    }
  }
  return points.last.$2;
}

/// ControlCursor reads [points] as controlAt does, for times that only go
/// on -- a part rendered from its start -- from where it last was rather
/// than from the curve's start each time (Ken's systems review, 2026-11-08:
/// a long take's mod wheel was read from its first point at every block).
class ControlCursor {
  final List<ControlPoint> points;
  final double rest;
  int _i = 1;
  ControlCursor(this.points, this.rest);

  double at(double t) {
    if (points.isEmpty) return rest;
    if (t <= points.first.$1) return points.first.$2;
    while (_i < points.length && t >= points[_i].$1) {
      _i++;
    }
    if (_i >= points.length) return points.last.$2;
    var (t0, v0) = points[_i - 1];
    var (t1, v1) = points[_i];
    return t1 <= t0 ? v1 : v0 + (v1 - v0) * (t - t0) / (t1 - t0);
  }
}

/// controlsToJson and controlsFromJson keep a part's or a clip's curves.
Map<String, dynamic> controlsToJson(Map<MidiControl, List<ControlPoint>> c) => {
      for (var e in c.entries)
        if (e.value.isNotEmpty)
          e.key.name: [
            for (var (t, v) in e.value)
              [(t * 10000).round() / 10000, (v * 1000).round() / 1000]
          ],
    };

Map<MidiControl, List<ControlPoint>> controlsFromJson(Object? json) {
  var out = <MidiControl, List<ControlPoint>>{};
  if (json is! Map<String, dynamic>) return out;
  for (var c in MidiControl.values) {
    if (json[c.name] case List points) {
      var list = <ControlPoint>[
        for (var p in points)
          if (p is List && p.length >= 2)
            (jsonDouble(p[0], 0), jsonDouble(p[1], c.rest).clamp(0.0, 1.0)),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      if (list.isNotEmpty) out[c] = list;
    }
  }
  return out;
}

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonStr;
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';

// devices.dart is the effects a channel's chain can hold beyond its strip --
// a reverb, a delay -- and the returns they usually live on.
//
// A device is a kind and its settings by name, each a number with a range
// and a default: the processors in media/mix/dsp.dart read them and the panel
// draws a knob for each.

/// DeviceParam is one setting of a device: its name in the file, what it is
/// called on the knob, its range and its default, and how it is shown.
class DeviceParam {
  final String id;
  final String label;
  final double min;
  final double max;
  final double initial;

  /// unit is how the knob reads: "ms", "Hz", "dB", "x", "bits", "#" (a
  /// count), "st" (semitones), "note" (a MIDI note, by name), or "" for a
  /// share, shown as a percentage.
  final String unit;

  /// choices are the names of a setting that is one of a few -- a filter's
  /// kind, an LFO's shape -- its value their index. Empty for a number.
  final List<String> choices;
  const DeviceParam(this.id, this.label, this.min, this.max, this.initial,
      [this.unit = "", this.choices = const []]);

  bool get isChoice => choices.isNotEmpty;

  /// reading is [v] as its knob says it.
  String reading(double v) {
    if (isChoice) return choices[v.round().clamp(0, choices.length - 1)];
    return switch (unit) {
      "ms" => v < 10 ? "${v.toStringAsFixed(1)} ms" : "${v.round()} ms",
      "Hz" => v >= 1000
          ? "${(v / 1000).toStringAsFixed(1)} kHz"
          : v < 10
              ? "${v.toStringAsFixed(2)} Hz"
              : "${v.round()} Hz",
      "dB" => "${v >= 0 ? "" : "−"}${v.abs().toStringAsFixed(1)} dB",
      "x" => "×${v.round()}",
      "bits" => "${v.round()} bits",
      "#" => "${v.round()}",
      "st" => v == 0
          ? "0 st"
          : "${v > 0 ? "+" : "−"}${v.abs().toStringAsFixed(1)} st",
      "note" => noteName(v.round()),
      "s" => "${v.toStringAsFixed(v.abs() < 10 ? 2 : 1)} s",
      "px" => "${v.toStringAsFixed(v < 10 ? 1 : 0)} px",
      "°" => "${v.round()}°",
      "×" => "×${v.toStringAsFixed(2)}",
      "LUFS" => "${v >= 0 ? "" : "−"}${v.abs().round()} LUFS",
      _ => "${(v * 100).round()}%",
    };
  }
}

/// noteName is MIDI note [midi] by name and octave: 60 is C4.
String noteName(int midi) => "${_noteNames[midi % 12]}${midi ~/ 12 - 1}";

const _noteNames = [
  "C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B", //
];
const _scales = [
  "Chromatic",
  "Major",
  "Minor",
  "Harmonic minor",
  "Dorian",
  "Mixolydian",
  "Major pentatonic",
  "Minor pentatonic",
  "Blues",
];

/// vocoderCarriers are what a vocoder's voice is laid onto: hiss, a buzz on
/// one note, a buzz that follows the voice's own pitch, or another channel
/// -- an instrument playing the chords, say.
const vocoderCarriers = ["Noise", "Buzz", "Follow pitch", "Channel"];

/// deviceExtras are the settings any device may have beyond its knobs, set
/// from its ⋯ menu as the prototype's: Oversample (a drive's) and Works on
/// (the whole sound, only its middle, or only its sides).
const List<DeviceParam> deviceExtras = [
  DeviceParam("oversample", "Oversample", 1, 4, 1, "x"),
  DeviceParam("stereo", "Works on", 0, 2, 0, "", ["Both sides", "Mid", "Side"]),
  // Out: how loud what it gives on is, after it -- the prototype's trim at
  // the foot of every effect.
  DeviceParam("out", "Out", -12, 12, 0, "dB"),
];

/// carrierFromChannel is the Carrier setting that takes another channel.
const int carrierFromChannel = 3;

/// paramShown is whether [p] does anything for [device] as it is set: a
/// vocoder's Note only for a buzz on one note.
bool paramShown(MixDevice device, DeviceParam p) => switch ((device.kind, p.id)) {
      (DeviceKind.vocoder, "note") => device.value("carrier").round() == 1,
      _ => true,
    };

/// deviceAbout is what [kind] does, in a few words: what a device's "?"
/// shows.
String deviceAbout(DeviceKind kind) => switch (kind) {
      DeviceKind.reverb =>
        "A room round the sound: Size is how big, Damping how dull its walls, "
            "Pre-delay how long before the room answers.",
      DeviceKind.delay => "Echoes: Time apart, Feedback how many come back.",
      DeviceKind.gate =>
        "Lets sound through only above its Threshold: quiet between notes, "
            "hiss and spill cut out. It can listen to another channel.",
      DeviceKind.autoFilter =>
        "A filter that moves by itself, with the beat or with how loud the "
            "sound is.",
      DeviceKind.chorus =>
        "Thickens the sound with copies of itself, slightly late and moving.",
      DeviceKind.flanger => "A sweeping, jet-like comb of the sound with itself.",
      DeviceKind.phaser => "A swirl of moving notches across the sound.",
      DeviceKind.autoPan => "Moves the sound from side to side, with the beat.",
      DeviceKind.saturator => "Warms the sound, as tape or valves would.",
      DeviceKind.overdrive => "Pushes the sound into a crunchy distortion.",
      DeviceKind.bitCrusher =>
        "Fewer bits and a lower rate: the sound of old machines.",
      DeviceKind.autoTune =>
        "Pulls a voice onto the notes of a key, gently or hard.",
      DeviceKind.vocoder =>
        "Makes a sound speak with a voice: the voice shapes a synth, or "
            "another channel.",
      DeviceKind.tuner => "The note it hears, and how far off it is.",
      DeviceKind.spectrum =>
        "How loud each pitch is, low to high; over time as a spectrogram.",
      DeviceKind.scope => "The wave itself, left and right, over its Time.",
      DeviceKind.stereoImage =>
        "Left against right: a line up the middle is mono, a cloud is wide. "
            "Correlation under minus nought means the sides cancel in mono.",
      DeviceKind.loudness =>
        "Broadcast loudness: momentary, the last three seconds, the whole "
            "since reset, and the true peak between the samples.",
      DeviceKind.utility =>
        "Gain, width, mono and phase: the plain tools.",
      DeviceKind.lfo =>
        "Makes no sound: moves other knobs up and down. Right-click a knob to "
            "have it moved.",
      DeviceKind.follower =>
        "Makes no sound: moves other knobs as the sound gets louder.",
      DeviceKind.macro =>
        "Makes no sound: one knob that turns several others at once.",
      DeviceKind.split =>
        "Sends the sound down two or more chains at once and mixes them back: "
            "side by side, middle and sides, left and right, or lows and highs.",
    };

/// listensOnly is whether [kind] only listens -- an analyser: a tuner, a
/// spectrum, a scope -- and changes nothing it is given.
bool listensOnly(DeviceKind kind) => kind.group == DeviceGroup.analysers;

/// DeviceGroup is where a device is listed when one is added.
enum DeviceGroup {
  space("Space"),
  dynamics("Dynamics"),
  filter("Filter"),
  modulation("Modulation"),
  drive("Drive"),
  pitch("Pitch"),
  utility("Utility"),

  /// analysers only listen, and show what they hear where they are.
  analysers("Analysers"),

  /// modulators make no sound: they move other devices' knobs.
  modulators("Modulators");

  final String label;
  const DeviceGroup(this.label);
}

/// DeviceKind is what a device does.
enum DeviceKind {
  reverb("Reverb", DeviceGroup.space, [
    DeviceParam("size", "Size", 0, 1, 0.7),
    DeviceParam("damping", "Damping", 0, 1, 0.4),
    DeviceParam("predelay", "Pre-delay", 0, 200, 12, "ms"),
    DeviceParam("width", "Width", 0, 1, 1),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  delay("Delay", DeviceGroup.space, [
    DeviceParam("time", "Time", 10, 2000, 375, "ms"),
    DeviceParam("feedback", "Feedback", 0, 0.95, 0.35),
    DeviceParam("tone", "Tone", 500, 18000, 5000, "Hz"),
    DeviceParam("pingpong", "Ping-pong", 0, 1, 0),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  gate("Gate", DeviceGroup.dynamics, [
    DeviceParam("threshold", "Threshold", -80, 0, -40, "dB"),
    DeviceParam("attack", "Attack", 0.1, 50, 1, "ms"),
    DeviceParam("hold", "Hold", 1, 500, 20, "ms"),
    DeviceParam("release", "Release", 5, 1000, 100, "ms"),
    DeviceParam("floor", "Floor", -80, 0, -80, "dB"),
  ]),
  autoFilter("Auto Filter", DeviceGroup.filter, [
    DeviceParam("type", "Type", 0, 2, 0, "",
        ["Low-pass", "High-pass", "Band-pass"]),
    DeviceParam("freq", "Frequency", 20, 20000, 1200, "Hz"),
    DeviceParam("res", "Resonance", 0, 1, 0.3),
    DeviceParam("amount", "LFO amount", 0, 1, 0),
    DeviceParam("rate", "LFO rate", 0.05, 10, 1, "Hz"),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  chorus("Chorus", DeviceGroup.modulation, [
    DeviceParam("rate", "Rate", 0.05, 5, 0.8, "Hz"),
    DeviceParam("depth", "Depth", 0, 1, 0.5),
    DeviceParam("delay", "Delay", 5, 30, 15, "ms"),
    DeviceParam("feedback", "Feedback", 0, 0.9, 0),
    DeviceParam("mix", "Mix", 0, 1, 0.5),
  ]),
  flanger("Flanger", DeviceGroup.modulation, [
    DeviceParam("rate", "Rate", 0.05, 5, 0.3, "Hz"),
    DeviceParam("depth", "Depth", 0, 1, 0.7),
    DeviceParam("delay", "Delay", 0.5, 10, 2, "ms"),
    DeviceParam("feedback", "Feedback", 0, 0.95, 0.5),
    DeviceParam("mix", "Mix", 0, 1, 0.5),
  ]),
  phaser("Phaser", DeviceGroup.modulation, [
    DeviceParam("rate", "Rate", 0.05, 5, 0.5, "Hz"),
    DeviceParam("depth", "Depth", 0, 1, 0.7),
    DeviceParam("stages", "Stages", 2, 12, 4, "#"),
    DeviceParam("feedback", "Feedback", 0, 0.95, 0.4),
    DeviceParam("mix", "Mix", 0, 1, 0.5),
  ]),
  autoPan("Auto Pan", DeviceGroup.modulation, [
    DeviceParam("rate", "Rate", 0.05, 10, 1, "Hz"),
    DeviceParam("amount", "Amount", 0, 1, 0.5),
    DeviceParam("shape", "Shape", 0, 2, 0, "", ["Sine", "Triangle", "Square"]),
  ]),
  saturator("Saturator", DeviceGroup.drive, [
    DeviceParam("drive", "Drive", 0, 36, 6, "dB"),
    DeviceParam("type", "Type", 0, 2, 0, "", ["Soft", "Warm", "Hard"]),
    DeviceParam("output", "Output", -24, 6, 0, "dB"),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  overdrive("Overdrive", DeviceGroup.drive, [
    DeviceParam("drive", "Drive", 0, 1, 0.5),
    DeviceParam("tone", "Tone", 500, 12000, 3000, "Hz"),
    DeviceParam("output", "Output", -24, 6, -6, "dB"),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  bitCrusher("Bit Crusher", DeviceGroup.drive, [
    DeviceParam("bits", "Bits", 1, 16, 8, "bits"),
    DeviceParam("down", "Downsample", 1, 50, 1, "x"),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  autoTune("Auto-tune", DeviceGroup.pitch, [
    DeviceParam("key", "Key", 0, 11, 0, "", _noteNames),
    DeviceParam("scale", "Scale", 0, 8, 0, "", _scales),
    DeviceParam("retune", "Retune", 0, 400, 20, "ms"),
    DeviceParam("amount", "Amount", 0, 1, 1),
    // Held notes eased onto the scale more slowly, as a singer settles.
    DeviceParam("humanise", "Humanise", 0, 1, 0.2),
    // The singer's own vibrato kept: none, as sung, or more.
    DeviceParam("vibrato", "Vibrato", 0, 1.5, 1, "x"),
  ]),
  vocoder("Vocoder", DeviceGroup.pitch, [
    DeviceParam("carrier", "Carrier", 0, 3, 1, "", vocoderCarriers),
    DeviceParam("note", "Note", 24, 84, 48, "note"),
    DeviceParam("bands", "Bands", 8, 40, 20, "#"),
    DeviceParam("low", "Low", 50, 1000, 100, "Hz"),
    DeviceParam("high", "High", 2000, 16000, 10000, "Hz"),
    DeviceParam("formant", "Formant", -12, 12, 0, "st"),
    DeviceParam("attack", "Attack", 0.5, 100, 4, "ms"),
    DeviceParam("release", "Release", 5, 500, 60, "ms"),
    DeviceParam("unvoiced", "Unvoiced", 0, 1, 0.3),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  tuner("Tuner", DeviceGroup.analysers, []),
  spectrum("Spectrum", DeviceGroup.analysers, [
    DeviceParam("view", "View", 0, 1, 0, "", ["Spectrum", "Spectrogram"]),
  ]),
  scope("Scope", DeviceGroup.analysers, [
    DeviceParam("time", "Time", 1, 100, 20, "ms"),
    DeviceParam("zoom", "Zoom", 0.5, 8, 1, "×"),
  ]),
  stereoImage("Stereo Image", DeviceGroup.analysers, []),
  loudness("Loudness", DeviceGroup.analysers, [
    DeviceParam("target", "Target", -24, -8, -14, "LUFS"),
  ]),
  utility("Utility", DeviceGroup.utility, [
    DeviceParam("gain", "Gain", -36, 36, 0, "dB"),
    DeviceParam("width", "Width", 0, 2, 1),
    DeviceParam("mono", "Mono", 0, 1, 0, "", ["Off", "On"]),
    DeviceParam("invert", "Phase", 0, 3, 0, "", ["Normal", "Left", "Right", "Both"]),
  ]),

  /// lfo makes no sound: it turns other devices' knobs up and down (see
  /// MixDevice.mods and modulation.dart).
  lfo("LFO", DeviceGroup.modulators, lfoParams),

  /// follower makes no sound either: it moves other devices' knobs by how
  /// loud its own sound is where it stands, or another channel's (its
  /// source).
  follower("Follower", DeviceGroup.modulators, followerParams),

  /// macro is eight knobs, each turning any knobs of the chain it is given:
  /// one move for many.
  macro("Macro", DeviceGroup.modulators, macroParams),

  /// split runs its sound through branches side by side -- each its own
  /// chain of devices (MixDevice.branches) -- and sums them again: all of
  /// it into each, or its middle and sides, left and right, or lows and
  /// highs apart.
  split("Split", DeviceGroup.utility, [
    DeviceParam("mode", "Splits", 0, 3, 0, "",
        ["In parallel", "Mid / Side", "Left / Right", "Low / High"]),
    DeviceParam("crossover", "Crossover", 60, 12000, 800, "Hz"),
  ]);

  final String label;
  final DeviceGroup group;
  final List<DeviceParam> params;
  const DeviceKind(this.label, this.group, this.params);

  DeviceParam param(String id) => params.firstWhere((p) => p.id == id,
      orElse: () => deviceExtras.firstWhere((p) => p.id == id));

  /// oversamples is whether it can be run oversampled (its ⋯ menu's
  /// Oversample): a drive, whose harmonics would otherwise fold back down.
  bool get oversamples =>
      this == DeviceKind.saturator || this == DeviceKind.overdrive;

  /// hasOut is whether it has an Out trim (see deviceExtras): every effect
  /// that changes the sound and has no output level of its own.
  bool get hasOut =>
      worksOnSides && !params.any((p) => p.id == "output" || p.id == "gain");

  /// worksOnSides is whether it can be given only the middle or only the
  /// sides of the sound (its ⋯ menu's Works on): one that changes sound.
  bool get worksOnSides =>
      !modulates &&
      group != DeviceGroup.analysers &&
      this != DeviceKind.split &&
      this != DeviceKind.utility &&
      this != DeviceKind.autoPan;

  /// modulates is whether it moves other devices' knobs (see MixDevice.mods)
  /// rather than making or changing sound.
  bool get modulates => group == DeviceGroup.modulators;

  static DeviceKind? fromName(String? name) =>
      values.where((k) => k.name == name).firstOrNull;
}

/// MixDevice is one device in a chain: what it is, whether it is on, and
/// any settings that are not its kind's defaults.
class MixDevice {
  final DeviceKind kind;
  final bool on;
  final Map<String, double> values;

  /// id is the device's own name within its chain, kept when it moves, so
  /// that a lane or a fold follows the device and not its place: see
  /// withDeviceIds. "" until the chain is next written.
  final String id;

  /// source is the channel a device takes a second sound from -- a
  /// vocoder's carrier -- by key, or "" for none.
  final String source;

  /// mods are the knobs a modulator (an LFO) moves: see modulation.dart.
  final List<ModTarget> mods;

  /// branches are a split's chains, side by side: see DeviceKind.split.
  final List<SplitBranch> branches;

  /// variations are a macro's saved settings -- its knobs' values, each a
  /// variation -- to come back to (see the Macros card's Variation).
  final List<Map<String, double>> variations;

  const MixDevice(this.kind,
      {this.on = true,
      this.values = const {},
      this.source = "",
      this.id = "",
      this.mods = const [],
      this.branches = const [],
      this.variations = const []});

  /// sidechain is the channel this device hears beside its own, or null:
  /// a vocoder set to take its carrier from a channel that is chosen, or a
  /// gate opened by another channel's sound.
  String? get sidechain => !on || source.isEmpty
      ? null
      : switch (kind) {
          DeviceKind.vocoder
              when value("carrier").round() == carrierFromChannel =>
            source,
          DeviceKind.gate || DeviceKind.follower => source,
          _ => null,
        };

  /// value is setting [id], or its default.
  double value(String id) {
    var p = kind.param(id);
    return (values[id] ?? p.initial).clamp(p.min, p.max).toDouble();
  }

  MixDevice withValue(String id, double v) {
    var p = kind.param(id);
    // A choice, a count, bits: whole steps only.
    var whole = p.isChoice || const {"#", "bits", "x"}.contains(p.unit);
    return MixDevice(kind,
        on: on,
        values: {...values, id: whole ? v.roundToDouble() : v},
        source: source,
        id: this.id,
        mods: mods, branches: branches, variations: variations);
  }

  MixDevice switched(bool on) => MixDevice(kind,
      on: on, values: values, source: source, id: id, mods: mods, branches: branches, variations: variations);

  MixDevice withSource(String source) => MixDevice(kind,
      on: on, values: values, source: source, id: id, mods: mods, branches: branches, variations: variations);

  MixDevice withId(String id) => MixDevice(kind,
      on: on, values: values, source: source, id: id, mods: mods, branches: branches, variations: variations);

  MixDevice withBranches(List<SplitBranch> branches) => MixDevice(kind,
      on: on,
      values: values,
      source: source,
      id: id,
      mods: mods,
      variations: variations,
      branches: [
        for (var b in branches) b.copyWith(devices: withDeviceIds(b.devices))
      ]);

  MixDevice withVariations(List<Map<String, double>> variations) =>
      MixDevice(kind,
          on: on,
          values: values,
          source: source,
          id: id,
          mods: mods,
          branches: branches,
          variations: variations);

  MixDevice withMods(List<ModTarget> mods) => MixDevice(kind,
      on: on, values: values, source: source, id: id, mods: mods, branches: branches, variations: variations);

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) "id": id,
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
        if (source.isNotEmpty) "source": source,
        if (mods.isNotEmpty) "mods": [for (var m in mods) m.toJson()],
        if (branches.isNotEmpty)
          "branches": [for (var b in branches) b.toJson()],
        if (variations.isNotEmpty) "variations": variations,
      };

  static MixDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = DeviceKind.fromName(jsonStr(json["kind"]));
    if (kind == null) return null;
    var raw = json["values"];
    return MixDevice(kind,
        on: jsonBool(json["on"], true),
        values: {
          if (raw is Map)
            for (var p in [...kind.params, ...deviceExtras])
              if (raw[p.id] is num) p.id: jsonDouble(raw[p.id], p.initial),
        },
        source: json["source"] is String ? json["source"] as String : "",
        id: json["id"] is String ? json["id"] as String : "",
        mods: readModTargets(json["mods"]),
        branches: [
          if (json["branches"] case List raw)
            for (var b in raw.take(maxBranches))
              if (SplitBranch.fromJson(b) case var branch?) branch,
        ],
        variations: [
          if (json["variations"] case List raw)
            for (var v in raw)
              if (v is Map)
                {
                  for (var p in kind.params)
                    if (v[p.id] is num) p.id: (v[p.id] as num).toDouble(),
                },
        ]);
  }

  @override
  bool operator ==(Object other) =>
      other is MixDevice &&
      other.kind == kind &&
      other.on == on &&
      other.source == source &&
      other.id == id &&
      other.mods.length == mods.length &&
      other.branches.length == branches.length &&
      [for (var i = 0; i < branches.length; i++)
        other.branches[i] == branches[i]].every((x) => x) &&
      [for (var i = 0; i < mods.length; i++) other.mods[i] == mods[i]]
          .every((x) => x) &&
      other.values.length == values.length &&
      other.values.entries.every((e) => values[e.key] == e.value) &&
      other.variations.length == variations.length &&
      [
        for (var i = 0; i < variations.length; i++)
          other.variations[i].length == variations[i].length &&
              other.variations[i]
                  .entries
                  .every((e) => variations[i][e.key] == e.value)
      ].every((x) => x);

  @override
  int get hashCode => Object.hash(kind, on, source, id, values.length);
}

/// deviceIdAt is device [i]'s id in [chain]: its own, or "d<i>" for one
/// that has none yet -- the id withDeviceIds would give it, which is also
/// how a lane saved before devices had ids, "device:<i>:…", finds it.
String deviceIdAt(List<MixDevice> chain, int i) =>
    chain[i].id.isEmpty ? "d$i" : chain[i].id;

/// deviceKey is the mixer's name for the device with [id] -- how a strip
/// opens it, folds it and scrolls to it -- "dev:<id>", so it follows the
/// device when the chain is put in another order.
String deviceKey(String id) => "dev:$id";

/// deviceKeyId is the device id in a deviceKey, or null for another key
/// ("eq", "speech", "midi0").
String? deviceKeyId(String key) =>
    key.startsWith("dev:") && key.length > 4 ? key.substring(4) : null;

/// deviceIndexOf is where the device with [id] is in [chain], or -1.
int deviceIndexOf(List<MixDevice> chain, String id) {
  for (var i = 0; i < chain.length; i++) {
    if (deviceIdAt(chain, i) == id) return i;
  }
  return -1;
}

/// withDeviceIds is [chain] with an id on every device. A chain with none
/// yet -- one saved before ids -- gets them by place, "d0", "d1"…; a device
/// added to a chain that has them gets one never used in it, so a lane
/// left from a device taken out can't land on the new one.
List<MixDevice> withDeviceIds(List<MixDevice> chain) {
  if (chain.every((d) => d.id.isNotEmpty)) return chain;
  if (chain.every((d) => d.id.isEmpty)) {
    return [for (var (i, d) in chain.indexed) d.withId("d$i")];
  }
  var next = 0;
  for (var d in chain) {
    var n = d.id.startsWith("d") ? int.tryParse(d.id.substring(1)) : null;
    if (n != null && n >= next) next = n + 1;
  }
  return [for (var d in chain) d.id.isEmpty ? d.withId("d${next++}") : d];
}

/// tempoSynced is [devices] with each LFO set to Sync given its rate at
/// [bpm], as the engine -- which knows no tempo -- runs it.
List<MixDevice> tempoSynced(List<MixDevice> devices, double bpm,
        {int beatsPerBar = 4}) =>
    devices.any((d) => d.kind == DeviceKind.lfo && d.value("sync") > 0)
        ? [
            for (var d in devices)
              d.kind == DeviceKind.lfo && d.value("sync") > 0
                  ? d.withValue("rate",
                      lfoRate(d.value, bpm: bpm, beatsPerBar: beatsPerBar))
                  : d,
          ]
        : devices;

/// branchDeviceId names device [device] in branch [branch] of split
/// [split] (each by its id or place) for a modulator to move one of its
/// knobs: see ModTarget.device.
String branchDeviceId(String split, int branch, String device) =>
    "$split/$branch/$device";

/// branchDevicePath is a name branchDeviceId made, taken apart; null for a
/// device of the chain itself.
(String, int, String)? branchDevicePath(String id) {
  var parts = id.split("/");
  if (parts.length != 3) return null;
  var b = int.tryParse(parts[1]);
  return b == null ? null : (parts[0], b, parts[2]);
}

/// maxBranches is the most branches a split has.
const int maxBranches = 4;

/// SplitBranch is one of a split's chains: its devices in order, how loud
/// it comes back, and whether it is heard at all.
class SplitBranch {
  final List<MixDevice> devices;
  final double gainDb;
  final bool mute;
  const SplitBranch({this.devices = const [], this.gainDb = 0, this.mute = false});

  SplitBranch copyWith({List<MixDevice>? devices, double? gainDb, bool? mute}) =>
      SplitBranch(
          devices: devices ?? this.devices,
          gainDb: gainDb ?? this.gainDb,
          mute: mute ?? this.mute);

  Map<String, dynamic> toJson() => {
        if (devices.isNotEmpty) "devices": [for (var d in devices) d.toJson()],
        if (gainDb != 0) "gain": gainDb,
        if (mute) "mute": true,
      };

  static SplitBranch? fromJson(Object? json) {
    if (json is! Map) return null;
    return SplitBranch(
      devices: withDeviceIds([
        if (json["devices"] case List raw)
          for (var d in raw)
            // No split in a split: one level of branches.
            if (MixDevice.fromJson(d) case var device?
                when device.kind != DeviceKind.split)
              device,
      ]),
      gainDb: jsonDouble(json["gain"], 0).clamp(-60.0, 12.0),
      mute: jsonBool(json["mute"], false),
    );
  }

  /// structure is what of it a running split is made of: a changed
  /// setting is retuned, a device added or switched remade.
  String get structure => [
        for (var (i, d) in devices.indexed)
          "${deviceIdAt(devices, i)}:${d.kind.name}:${d.on}:${d.source}"
      ].join(",");

  @override
  bool operator ==(Object other) =>
      other is SplitBranch &&
      other.gainDb == gainDb &&
      other.mute == mute &&
      other.devices.length == devices.length &&
      [for (var i = 0; i < devices.length; i++) other.devices[i] == devices[i]]
          .every((x) => x);

  @override
  int get hashCode => Object.hash(gainDb, mute, devices.length);
}

/// splitBranchNames are a split's branches' names in [mode] (see
/// DeviceKind.split): two of them, but in parallel as many as [count].
List<String> splitBranchNames(int mode, int count) => switch (mode) {
      1 => const ["Mid", "Side"],
      2 => const ["Left", "Right"],
      3 => const ["Low", "High"],
      _ => [for (var i = 0; i < count; i++) "Branch ${String.fromCharCode(65 + i)}"],
    };

/// ReturnChannel is a return: a channel fed by the others' sends rather than
/// by sounds of its own -- one reverb every channel feeds a little of, rather
/// than a reverb on each. Its devices run first, then its strip.
class ReturnChannel {
  final String id;
  final String name;
  final List<MixDevice> devices;
  final ChannelMix mix;

  /// pre is whether its sends are taken before each channel's fader, so the
  /// fader does not change how much is sent.
  final bool pre;

  const ReturnChannel(this.id,
      {this.name = "",
      this.devices = const [],
      this.mix = const ChannelMix(),
      this.pre = false});

  ReturnChannel copyWith(
          {String? name,
          List<MixDevice>? devices,
          ChannelMix? mix,
          bool? pre}) =>
      ReturnChannel(id,
          name: name ?? this.name,
          devices: devices == null ? this.devices : withDeviceIds(devices),
          mix: mix ?? this.mix,
          pre: pre ?? this.pre);

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        if (devices.isNotEmpty)
          "devices": [for (var d in devices) d.toJson()],
        if (!mix.isDefault) "mix": mix.toJson(),
        if (pre) "pre": true,
      };

  static ReturnChannel? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var id = json["id"];
    if (id is! String || id.isEmpty) return null;
    return ReturnChannel(id,
        name: json["name"] is String ? json["name"] as String : "",
        devices: withDeviceIds([
          if (json["devices"] case List list)
            for (var d in list.take(maxChainDevices))
              if (MixDevice.fromJson(d) case var device?) device,
        ]),
        mix: json["mix"] is Map<String, dynamic>
            ? ChannelMix.fromJson(json["mix"] as Map<String, dynamic>)
            : const ChannelMix(),
        pre: jsonBool(json["pre"], false));
  }

  String toKey() => toJson().toString();

  /// chainMix is its strip with its devices on it: what runs, its EQ and
  /// compressor among its devices in the order they were put, as a
  /// channel's (ChannelMix.chain).
  ChannelMix get chainMix => mix.copyWith(devices: devices);
}

/// returnLetter is the letter a return goes by, from its place: A, B, C.
String returnLetter(int index) =>
    index < 26 ? String.fromCharCode(65 + index) : "R${index + 1}";

/// defaultReturns are the two every document starts with: a reverb and a
/// delay.
const List<ReturnChannel> defaultReturns = [
  ReturnChannel("returnA", name: "Reverb", devices: [MixDevice(DeviceKind.reverb)]),
  ReturnChannel("returnB", name: "Delay", devices: [MixDevice(DeviceKind.delay)]),
];

/// maxReturns is the most returns a document can have.
const int maxReturns = 8;

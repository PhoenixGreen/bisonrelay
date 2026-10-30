import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble;
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// devices.dart is the effects a channel's chain can hold beyond its strip --
// a reverb, a delay -- and the returns they usually live on.
//
// A device is a kind and its settings by name, each a number with a range
// and a default: the processors in media/mix/dsp.dart read them, the panel
// draws a knob for each, and a setting a later device adds needs nothing
// more than a line in its table.

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

/// carrierFromChannel is the Carrier setting that takes another channel.
const int carrierFromChannel = 3;

/// paramShown is whether [p] does anything for [device] as it is set: a
/// vocoder's Note only for a buzz on one note.
bool paramShown(MixDevice device, DeviceParam p) => switch ((device.kind, p.id)) {
      (DeviceKind.vocoder, "note") => device.value("carrier").round() == 1,
      _ => true,
    };

/// listens is whether [kind] only listens -- a tuner, a spectrum -- and
/// changes nothing it is given.
bool listensOnly(DeviceKind kind) =>
    kind == DeviceKind.tuner || kind == DeviceKind.spectrum;

/// DeviceGroup is where a device is listed when one is added.
enum DeviceGroup {
  space("Space"),
  dynamics("Dynamics"),
  filter("Filter"),
  modulation("Modulation"),
  drive("Drive"),
  pitch("Pitch"),
  utility("Utility");

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
  tuner("Tuner", DeviceGroup.pitch, []),
  spectrum("Spectrum", DeviceGroup.pitch, []),
  utility("Utility", DeviceGroup.utility, [
    DeviceParam("gain", "Gain", -36, 36, 0, "dB"),
    DeviceParam("width", "Width", 0, 2, 1),
    DeviceParam("mono", "Mono", 0, 1, 0, "", ["Off", "On"]),
    DeviceParam("invert", "Phase", 0, 3, 0, "", ["Normal", "Left", "Right", "Both"]),
  ]);

  final String label;
  final DeviceGroup group;
  final List<DeviceParam> params;
  const DeviceKind(this.label, this.group, this.params);

  DeviceParam param(String id) => params.firstWhere((p) => p.id == id);

  static DeviceKind? fromName(String? name) =>
      values.where((k) => k.name == name).firstOrNull;
}

/// MixDevice is one device in a chain: what it is, whether it is on, and
/// any settings that are not its kind's defaults.
class MixDevice {
  final DeviceKind kind;
  final bool on;
  final Map<String, double> values;

  /// source is the channel a device takes a second sound from -- a
  /// vocoder's carrier -- by key, or "" for none.
  final String source;

  const MixDevice(this.kind,
      {this.on = true, this.values = const {}, this.source = ""});

  /// sidechain is the channel this device hears beside its own, or null:
  /// a vocoder set to take its carrier from a channel that is chosen.
  String? get sidechain => kind == DeviceKind.vocoder &&
          on &&
          source.isNotEmpty &&
          value("carrier").round() == carrierFromChannel
      ? source
      : null;

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
        source: source);
  }

  MixDevice switched(bool on) =>
      MixDevice(kind, on: on, values: values, source: source);

  MixDevice withSource(String source) =>
      MixDevice(kind, on: on, values: values, source: source);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
        if (source.isNotEmpty) "source": source,
      };

  static MixDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = DeviceKind.fromName(json["kind"] as String?);
    if (kind == null) return null;
    var raw = json["values"];
    return MixDevice(kind,
        on: jsonBool(json["on"], true),
        values: {
          if (raw is Map)
            for (var p in kind.params)
              if (raw[p.id] is num) p.id: jsonDouble(raw[p.id], p.initial),
        },
        source: json["source"] is String ? json["source"] as String : "");
  }

  @override
  bool operator ==(Object other) =>
      other is MixDevice &&
      other.kind == kind &&
      other.on == on &&
      other.source == source &&
      other.values.length == values.length &&
      other.values.entries.every((e) => values[e.key] == e.value);

  @override
  int get hashCode => Object.hash(kind, on, source, values.length);
}

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
          devices: devices ?? this.devices,
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
        devices: [
          if (json["devices"] case List list)
            for (var d in list)
              if (MixDevice.fromJson(d) case var device?) device,
        ],
        mix: json["mix"] is Map<String, dynamic>
            ? ChannelMix.fromJson(json["mix"] as Map<String, dynamic>)
            : const ChannelMix(),
        pre: jsonBool(json["pre"], false));
  }

  String toKey() => toJson().toString();
}

/// returnLetter is the letter a return goes by, from its place: A, B, C.
String returnLetter(int index) =>
    index < 26 ? String.fromCharCode(65 + index) : "R${index + 1}";

/// defaultReturns are the two every document starts with: a reverb and a
/// delay, the two sends nearly every mix uses.
const List<ReturnChannel> defaultReturns = [
  ReturnChannel("returnA", name: "Reverb", devices: [MixDevice(DeviceKind.reverb)]),
  ReturnChannel("returnB", name: "Delay", devices: [MixDevice(DeviceKind.delay)]),
];

/// maxReturns is as many returns as a document has.
const int maxReturns = 8;

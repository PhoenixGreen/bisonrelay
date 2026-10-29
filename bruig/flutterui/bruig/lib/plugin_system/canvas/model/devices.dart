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
  final String unit;
  const DeviceParam(this.id, this.label, this.min, this.max, this.initial,
      [this.unit = ""]);
}

/// DeviceKind is what a device does.
enum DeviceKind {
  reverb("Reverb", [
    DeviceParam("size", "Size", 0, 1, 0.7),
    DeviceParam("damping", "Damping", 0, 1, 0.4),
    DeviceParam("predelay", "Pre-delay", 0, 200, 12, "ms"),
    DeviceParam("width", "Width", 0, 1, 1),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]),
  delay("Delay", [
    DeviceParam("time", "Time", 10, 2000, 375, "ms"),
    DeviceParam("feedback", "Feedback", 0, 0.95, 0.35),
    DeviceParam("tone", "Tone", 500, 18000, 5000, "Hz"),
    DeviceParam("pingpong", "Ping-pong", 0, 1, 0),
    DeviceParam("mix", "Mix", 0, 1, 1),
  ]);

  final String label;
  final List<DeviceParam> params;
  const DeviceKind(this.label, this.params);

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

  const MixDevice(this.kind, {this.on = true, this.values = const {}});

  /// value is setting [id], or its default.
  double value(String id) {
    var p = kind.param(id);
    return (values[id] ?? p.initial).clamp(p.min, p.max).toDouble();
  }

  MixDevice withValue(String id, double v) =>
      MixDevice(kind, on: on, values: {...values, id: v});

  MixDevice switched(bool on) => MixDevice(kind, on: on, values: values);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
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
        });
  }

  @override
  bool operator ==(Object other) =>
      other is MixDevice &&
      other.kind == kind &&
      other.on == on &&
      other.values.length == values.length &&
      other.values.entries.every((e) => values[e.key] == e.value);

  @override
  int get hashCode => Object.hash(kind, on, values.length);
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

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonStr;
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;
import 'package:bruig/plugin_system/canvas/model/modulation.dart';

// motion_devices.dart is an element's motion chain beyond its clips: the
// devices of its Chain's Motion view. Three rules make it work (see the
// chain prototype):
//
//  1. Left of the drawing works on where it is -- a pose; right of it, on
//     how it looks. Each kind belongs to one side (MotionDeviceSide), and
//     is only offered there.
//  2. A device that changes time changes it for everything to its left: it
//     asks them for another moment. Motion is pulled, as sound is pushed.
//  3. Left of Instances is shared; right of it, each instance has its own
//     seed and start (to come, with instancing).

/// MotionDeviceSide is which side of the drawing a device works on.
enum MotionDeviceSide {
  /// pose devices change where it is, and when: left of the drawing.
  pose,

  /// look devices change how it looks once drawn: right of it.
  look,
}

/// MotionDeviceKind is a kind of motion device, with its settings.
enum MotionDeviceKind {
  /// instances is where an element reused splits into its instances (rule
  /// 3): what is left of it is worked out once, for all of them; what is
  /// right of it, for each. Its settings are ElementMotion.instances.
  instances("Instances", MotionDeviceSide.pose, []),
  time("Time", MotionDeviceSide.pose, [
    DeviceParam("speed", "Speed", 0.1, 4, 1, "×"),
    DeviceParam("offset", "Offset", -10, 10, 0, "s"),
    DeviceParam("loop", "Loop", 0, 2, 0, "", ["Off", "Cycle", "Ping-pong"]),
    DeviceParam("every", "Every", 0.1, 30, 2, "s"),
    DeviceParam("hold", "Hold frames", 1, 6, 1, "#"),
  ]),
  wiggle("Wiggle", MotionDeviceSide.pose, [
    DeviceParam("speed", "Speed", 0.1, 10, 2, "Hz"),
    DeviceParam("amount", "Amount", 0, 200, 12, "px"),
    DeviceParam("turn", "Turn", 0, 45, 5, "°"),
    DeviceParam("seed", "Seed", 0, 1, 1, "", ["Same for all", "Each its own"]),
  ]),
  oscillate("Oscillate", MotionDeviceSide.pose, [
    DeviceParam("rate", "Rate", 0.05, 5, 0.5, "Hz"),
    DeviceParam("amount", "Amount", 0, 400, 30, "px"),
    DeviceParam("moves", "Moves", 0, 3, 0, "",
        ["Up and down", "Side to side", "Size", "Turn"]),
    DeviceParam("phase", "Phase", 0, 1, 0),
  ]),
  spring("Spring", MotionDeviceSide.pose, [
    DeviceParam("stiffness", "Stiffness", 1, 40, 12, "#"),
    DeviceParam("damping", "Damping", 0, 1, 0.35),
  ]),
  followPath("Follow path", MotionDeviceSide.pose, [
    DeviceParam("start", "Start along", 0, 1, 0),
    DeviceParam("lap", "Once round", 0.5, 60, 6, "s"),
    DeviceParam("loop", "At the end", 0, 1, 0, "", ["Round again", "Stops"]),
    DeviceParam("turns", "Turns with it", 0, 1, 1, "", ["No", "Yes"]),
  ]),
  lookAt("Look at", MotionDeviceSide.pose, [
    DeviceParam("smooth", "Smooth", 0, 1, 0),
    DeviceParam("offset", "Offset", -180, 180, 0, "°"),
  ]),
  squash("Squash", MotionDeviceSide.pose, [
    DeviceParam("amount", "Amount", 0, 1, 0.4),
    DeviceParam("bySpeed", "By speed", 0, 1, 0.6),
  ]),
  followSound("Follow sound", MotionDeviceSide.pose, [
    DeviceParam("amount", "Amount", 0, 2, 0.6, "×"),
    DeviceParam("smooth", "Smooth", 0, 1, 0.3),
    DeviceParam(
        "moves", "Moves", 0, 3, 0, "", ["Size", "Up", "Turn", "Opacity"]),
  ]),

  /// lfo moves no pose itself: it turns other devices' knobs up and down,
  /// a move's or a look's (see MotionDevice.mods and modulation.dart).
  lfo("LFO", MotionDeviceSide.pose, lfoParams),

  /// macro is four knobs, each turning any knobs of the chain it is given.
  macro("Macro", MotionDeviceSide.pose, macroParams),

  /// follower moves other devices' knobs by how loud a channel is (its
  /// target), as Follow sound moves the element.
  follower("Follower", MotionDeviceSide.pose, [
    DeviceParam("smooth", "Smooth", 0, 1, 0.3),
    DeviceParam("gain", "Gain", 0.1, 8, 2, "×"),
  ]),
  glow("Glow", MotionDeviceSide.look, [
    DeviceParam("radius", "Radius", 0, 60, 10, "px"),
    DeviceParam("strength", "Strength", 0, 1, 0.6),
  ]),
  shadow("Shadow", MotionDeviceSide.look, [
    DeviceParam("distance", "Distance", 0, 80, 8, "px"),
    DeviceParam("blur", "Blur", 0, 60, 10, "px"),
    DeviceParam("angle", "Angle", 0, 360, 135, "°"),
    DeviceParam("strength", "Strength", 0, 1, 0.5),
  ]),
  blur("Blur", MotionDeviceSide.look, [
    DeviceParam("amount", "Amount", 0, 40, 4, "px"),
  ]),
  colour("Colour", MotionDeviceSide.look, [
    DeviceParam("hue", "Hue", -180, 180, 0, "°"),
    DeviceParam("saturation", "Saturation", 0, 2, 1, "×"),
    DeviceParam("brightness", "Brightness", -1, 1, 0),
  ]),
  outline("Outline", MotionDeviceSide.look, [
    DeviceParam("width", "Width", 0, 30, 3, "px"),
    DeviceParam("softness", "Softness", 0, 1, 0),
  ]);

  final String label;
  final MotionDeviceSide side;
  final List<DeviceParam> params;
  const MotionDeviceKind(this.label, this.side, this.params);

  DeviceParam param(String id) => params.firstWhere((p) => p.id == id);

  static MotionDeviceKind? fromName(String? name) =>
      values.where((k) => k.name == name).firstOrNull;

  /// on is the kinds offered on [side]: see rule 1. Instances is not one:
  /// it is always there, as Reuse.
  static List<MotionDeviceKind> on(MotionDeviceSide side) => [
        for (var k in values)
          if (k.side == side && k != instances) k
      ];
}

/// MotionDevice is one device of an element's motion chain: its kind, its
/// switch and its settings. Immutable. [id] is its own name within the
/// chain, kept when it moves (see withMotionDeviceIds).
class MotionDevice {
  final MotionDeviceKind kind;
  final bool on;
  final Map<String, double> values;
  final String id;

  /// target is the element it works with, by id -- the path Follow path
  /// goes along, what Look at looks at -- or "" for none.
  final String target;

  /// mods are the knobs an LFO moves: see modulation.dart.
  final List<ModTarget> mods;

  /// colour is the colour a look draws in -- a glow's, a shadow's, an
  /// outline's -- as ARGB; null for the kind's own.
  final int? colour;

  const MotionDevice(this.kind,
      {this.on = true,
      this.values = const {},
      this.id = "",
      this.colour,
      this.target = "",
      this.mods = const []});

  /// takesTarget is whether it works with another element.
  bool get takesTarget =>
      kind == MotionDeviceKind.followPath ||
      kind == MotionDeviceKind.lookAt ||
      kind == MotionDeviceKind.followSound ||
      kind == MotionDeviceKind.follower;

  /// modulates is whether it moves other devices' knobs (see [mods]).
  bool get modulates =>
      kind == MotionDeviceKind.lfo ||
      kind == MotionDeviceKind.follower ||
      kind == MotionDeviceKind.macro;

  MotionDeviceSide get side => kind.side;

  /// value is setting [id], or its default.
  double value(String id) {
    var p = kind.param(id);
    return (values[id] ?? p.initial).clamp(p.min, p.max).toDouble();
  }

  MotionDevice withValue(String id, double v) {
    var p = kind.param(id);
    var whole = p.isChoice || p.unit == "#";
    return MotionDevice(kind,
        on: on,
        values: {...values, id: whole ? v.roundToDouble() : v},
        id: this.id,
        colour: colour,
        target: target,
        mods: mods);
  }

  MotionDevice switched(bool on) => MotionDevice(kind,
      on: on,
      values: values,
      id: id,
      colour: colour,
      target: target,
      mods: mods);

  MotionDevice withId(String id) => MotionDevice(kind,
      on: on,
      values: values,
      id: id,
      colour: colour,
      target: target,
      mods: mods);

  MotionDevice withColour(int? colour) => MotionDevice(kind,
      on: on,
      values: values,
      id: id,
      colour: colour,
      target: target,
      mods: mods);

  MotionDevice withTarget(String target) => MotionDevice(kind,
      on: on,
      values: values,
      id: id,
      colour: colour,
      target: target,
      mods: mods);

  MotionDevice withMods(List<ModTarget> mods) => MotionDevice(kind,
      on: on,
      values: values,
      id: id,
      colour: colour,
      target: target,
      mods: mods);

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
        if (id.isNotEmpty) "id": id,
        if (colour != null) "colour": colour,
        if (target.isNotEmpty) "target": target,
        if (mods.isNotEmpty) "mods": [for (var m in mods) m.toJson()],
      };

  static MotionDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = MotionDeviceKind.fromName(jsonStr(json["kind"]));
    if (kind == null) return null;
    var ids = {for (var p in kind.params) p.id};
    return MotionDevice(kind,
        on: jsonBool(json["on"], true),
        values: {
          if (json["values"] case Map raw)
            for (var MapEntry(:key, :value) in raw.entries)
              if (key is String && ids.contains(key))
                key: jsonDouble(value, kind.param(key).initial),
        },
        id: jsonStr(json["id"]) ?? "",
        colour: json["colour"] is int ? json["colour"] as int : null,
        target: jsonStr(json["target"]) ?? "",
        mods: readModTargets(json["mods"]));
  }

  @override
  bool operator ==(Object other) =>
      other is MotionDevice &&
      other.kind == kind &&
      other.on == on &&
      other.id == id &&
      other.colour == colour &&
      other.target == target &&
      other.mods.length == mods.length &&
      [for (var i = 0; i < mods.length; i++) other.mods[i] == mods[i]]
          .every((x) => x) &&
      other.values.length == values.length &&
      values.entries.every((e) => other.values[e.key] == e.value);

  @override
  int get hashCode => Object.hash(kind, on, id, colour, values.length);
}

/// withMotionDeviceIds is [chain] with an id on every device: those it has
/// kept, and the next free "m" and a number for any without.
List<MotionDevice> withMotionDeviceIds(List<MotionDevice> chain) {
  if (chain.every((d) => d.id.isNotEmpty)) return chain;
  var next = 0;
  for (var d in chain) {
    var n = d.id.startsWith("m") ? int.tryParse(d.id.substring(1)) : null;
    if (n != null && n >= next) next = n + 1;
  }
  return [for (var d in chain) d.id.isEmpty ? d.withId("m${next++}") : d];
}

/// motionDevicesInOrder is [chain] as it runs: its pose devices first, in
/// their order, then its looks in theirs -- the drawing between them, as
/// rule 1 has it, wherever a device was put.
List<MotionDevice> motionDevicesInOrder(List<MotionDevice> chain) => [
      for (var d in chain)
        if (d.side == MotionDeviceSide.pose) d,
      for (var d in chain)
        if (d.side == MotionDeviceSide.look) d,
    ];

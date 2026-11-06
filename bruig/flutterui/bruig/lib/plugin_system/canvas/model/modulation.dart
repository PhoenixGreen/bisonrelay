import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceParam;

// modulation.dart is a modulator moving other devices' knobs: an LFO in a
// chain -- a sound's or an element's motion -- turning the knobs it is given
// up and down around where they are set, by its depth. A knob it moves shows
// a pink ring.

/// ModTarget is one knob a modulator moves: a device in the same chain by
/// id, one of its settings, and how far -- a share of the knob's travel
/// either way of where it is set; negative turns it the other way.
class ModTarget {
  final String device;
  final String param;
  final double depth;
  const ModTarget(this.device, this.param, [this.depth = 0.5]);

  ModTarget withDepth(double depth) => ModTarget(device, param, depth);

  Map<String, dynamic> toJson() =>
      {"device": device, "param": param, "depth": depth};

  static ModTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    var device = json["device"], param = json["param"], depth = json["depth"];
    if (device is! String || param is! String) return null;
    return ModTarget(
        device, param, depth is num ? depth.toDouble().clamp(-1.0, 1.0) : 0.5);
  }

  @override
  bool operator ==(Object other) =>
      other is ModTarget &&
      other.device == device &&
      other.param == param &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(device, param, depth);
}

/// readModTargets reads a modulator's targets from [json].
List<ModTarget> readModTargets(Object? json) => [
      if (json is List)
        for (var t in json)
          if (ModTarget.fromJson(t) case var target?) target,
    ];

/// lfoParams are an LFO's settings, as a sound's and a motion's LFO both
/// have them.
const List<DeviceParam> lfoParams = [
  DeviceParam("rate", "Rate", 0.05, 20, 1, "Hz"),
  DeviceParam(
      "shape", "Shape", 0, 3, 0, "", ["Sine", "Triangle", "Square", "Random"]),
  DeviceParam("phase", "Phase", 0, 1, 0),
];

/// lfoValue is an LFO of [shape] (see lfoParams) [cycles] cycles in, from
/// minus one to one. Random holds a new value each cycle, the same for the
/// same cycle.
double lfoValue(int shape, double cycles) {
  var p = cycles - cycles.floorToDouble();
  switch (shape) {
    case 1:
      return 1 - 4 * (p - 0.5).abs();
    case 2:
      return p < 0.5 ? 1 : -1;
    case 3:
      var n = cycles.floor();
      var x = (n * 0x9E3779B1 + 0x7F4A7C15) & 0xFFFFFFFF;
      x ^= x >> 15;
      x = (x * 0x85EBCA77) & 0xFFFFFFFF;
      x ^= x >> 13;
      return x / 0xFFFFFFFF * 2 - 1;
    default:
      return math.sin(2 * math.pi * p);
  }
}

/// modulated is [base], a setting of [param], moved by [amount] -- a share
/// of its travel either way (depth times where the LFO is) -- and kept on
/// the knob.
double modulated(DeviceParam param, double base, double amount) =>
    (base + amount * (param.max - param.min) / 2)
        .clamp(param.min, param.max)
        .toDouble();

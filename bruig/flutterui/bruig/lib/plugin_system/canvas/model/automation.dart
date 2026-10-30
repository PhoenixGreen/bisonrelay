import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';

// automation.dart is a channel's automation: lanes, each one setting of the
// channel -- its volume, its pan, a send, a knob of one of its devices --
// and the points it moves through along the timeline, in seconds counted as
// a clip's start is, from the start of its scene. Between two points the
// setting goes in a straight line; before the first and after the last it
// stays where they are.
//
// Played, a channel's mix at a moment is its own with each automated
// setting put in -- see automatedAt. A setting moved by hand is left where
// the hand put it until it is handed back, as Ableton does: see
// CanvasController.backToArrangement.

/// AutomationPoint is a point of a lane: seconds, and the setting's value
/// there, in its own units -- decibels, a pan, a knob's value.
typedef AutomationPoint = (double, double);

enum AutomationKind { volume, pan, send, device }

/// AutomationTarget is what a lane moves, read from its id: `volume`,
/// `pan`, `send:<return id>`, or `device:<index>:<kind>:<setting>` -- a
/// device by its place in the chain and its kind, so a lane whose device
/// has been taken out or replaced moves nothing.
class AutomationTarget {
  final AutomationKind kind;
  final String send;
  final int device;
  final DeviceKind? deviceKind;
  final String param;

  const AutomationTarget._(this.kind,
      {this.send = "", this.device = -1, this.deviceKind, this.param = ""});

  static const volume = AutomationTarget._(AutomationKind.volume);
  static const pan = AutomationTarget._(AutomationKind.pan);
  static AutomationTarget sendTo(String id) =>
      AutomationTarget._(AutomationKind.send, send: id);
  static AutomationTarget deviceSetting(
          int index, DeviceKind kind, String param) =>
      AutomationTarget._(AutomationKind.device,
          device: index, deviceKind: kind, param: param);

  static AutomationTarget? parse(String id) {
    if (id == "volume") return volume;
    if (id == "pan") return pan;
    if (id.startsWith("send:") && id.length > 5) return sendTo(id.substring(5));
    var parts = id.split(":");
    if (parts.length == 4 && parts[0] == "device") {
      var kind = DeviceKind.fromName(parts[2]);
      var index = int.tryParse(parts[1]);
      if (kind == null || index == null || index < 0) return null;
      if (!kind.params.any((p) => p.id == parts[3])) return null;
      return deviceSetting(index, kind, parts[3]);
    }
    return null;
  }

  String get id => switch (kind) {
        AutomationKind.volume => "volume",
        AutomationKind.pan => "pan",
        AutomationKind.send => "send:$send",
        AutomationKind.device => "device:$device:${deviceKind!.name}:$param",
      };

  DeviceParam? get setting => deviceKind?.param(param);

  /// steps is whether it moves in whole steps -- a choice, a count -- and
  /// so jumps from one point's value to the next rather than gliding.
  bool get steps {
    var p = setting;
    return p != null &&
        (p.isChoice || const {"#", "bits", "x", "note"}.contains(p.unit));
  }

  /// on is whether it moves anything on [mix]: a device setting only while
  /// that device is where it was, and is still that kind.
  bool on(ChannelMix mix) =>
      kind != AutomationKind.device ||
      (device < mix.devices.length && mix.devices[device].kind == deviceKind);

  /// own is the setting as the channel has it, untouched by automation.
  double own(ChannelMix mix) => switch (kind) {
        AutomationKind.volume => mix.gainDb,
        AutomationKind.pan => mix.balance,
        AutomationKind.send => mix.sendDb(send) ?? silent,
        AutomationKind.device =>
          on(mix) ? mix.devices[device].value(param) : setting!.initial,
      };

  /// silent is a volume or a send at the bottom: nothing.
  static const double silent = -90;

  /// height is [v] up a lane, nought at the bottom to one at the top: a
  /// volume as the fader has it, a send as its dial, a frequency or a time
  /// on a log scale as its knob turns.
  double height(double v) {
    switch (kind) {
      case AutomationKind.volume:
        return 1 - faderTravel(v);
      case AutomationKind.pan:
        return ((v + 1) / 2).clamp(0.0, 1.0);
      case AutomationKind.send:
        return v <= -60 ? 0 : ((v + 60) / 66).clamp(0.02, 1.0);
      case AutomationKind.device:
        var p = setting!;
        if (_log(p)) {
          var lo = math.log(math.max(p.min, 0.01)), hi = math.log(p.max);
          return ((math.log(math.max(v, 0.01)) - lo) / (hi - lo))
              .clamp(0.0, 1.0);
        }
        return ((v - p.min) / (p.max - p.min)).clamp(0.0, 1.0);
    }
  }

  /// valueAt is the value at [h] up a lane: height turned back.
  double valueAt(double h) {
    h = h.clamp(0.0, 1.0);
    switch (kind) {
      case AutomationKind.volume:
        return faderLevel(1 - h);
      case AutomationKind.pan:
        return h * 2 - 1;
      case AutomationKind.send:
        return h <= 0.02 ? silent : -60 + h * 66;
      case AutomationKind.device:
        var p = setting!;
        double v;
        if (_log(p)) {
          var lo = math.log(math.max(p.min, 0.01)), hi = math.log(p.max);
          v = math.exp(lo + h * (hi - lo));
        } else {
          v = p.min + h * (p.max - p.min);
        }
        return steps ? v.roundToDouble().clamp(p.min, p.max) : v;
    }
  }

  static bool _log(DeviceParam p) =>
      (p.unit == "Hz" || p.unit == "ms") && p.max / math.max(p.min, 0.01) > 20;

  /// reading is [v] as the setting reads.
  String reading(double v) => switch (kind) {
        AutomationKind.volume || AutomationKind.send => v <= -60
            ? "−∞ dB"
            : "${v > 0 ? "+" : v < 0 ? "−" : ""}"
                "${v.abs().toStringAsFixed(1)} dB",
        AutomationKind.pan => v.abs() < 0.01
            ? "C"
            : "${v < 0 ? "L" : "R"} ${(v.abs() * 100).round()}",
        AutomationKind.device => setting!.reading(v),
      };

  /// label is what a lane moving it is called: "Volume", "Send A · Reverb",
  /// "Vocoder › Formant".
  String label(ChannelMix mix, List<ReturnChannel> returns) {
    switch (kind) {
      case AutomationKind.volume:
        return "Volume";
      case AutomationKind.pan:
        return "Pan";
      case AutomationKind.send:
        var i = returns.indexWhere((r) => r.id == send);
        if (i < 0) return "Send (gone)";
        var r = returns[i];
        return "Send ${returnLetter(i)}${r.name.isEmpty ? "" : " · ${r.name}"}";
      case AutomationKind.device:
        var name = "${deviceKind!.label} › ${setting!.label}";
        // Two of one kind: told apart by their place.
        var same = mix.devices.where((d) => d.kind == deviceKind).length;
        return same > 1 ? "$name (${device + 1})" : name;
    }
  }
}

/// faderTravel is where [db] sits along the fader, nought at the top to one
/// at the bottom: most of the travel where mixing happens, between minus
/// thirty and the top. The mixer's fader is drawn on it -- see
/// faderPosition.
double faderTravel(double db) =>
    db <= -60 ? 1 : math.pow((6 - db) / 66, 0.6).toDouble().clamp(0.0, 1.0);

/// faderLevel is the level at [travel] along the fader -- faderTravel
/// turned back; silence at the very bottom.
double faderLevel(double travel) => travel >= 0.995
    ? AutomationTarget.silent
    : 6 - math.pow(travel.clamp(0.0, 1.0), 1 / 0.6) * 66;

/// AutomationLane is one setting's automation: what it moves, and its
/// points in order of time.
class AutomationLane {
  final String target;
  final List<AutomationPoint> points;
  const AutomationLane(this.target, [this.points = const []]);

  AutomationTarget? get what => AutomationTarget.parse(target);

  /// valueAt is the setting at [seconds], or null with no points.
  double? valueAt(double seconds) {
    var p = points;
    if (p.isEmpty) return null;
    if (seconds <= p.first.$1) return p.first.$2;
    if (seconds >= p.last.$1) return p.last.$2;
    var lo = 0, hi = p.length - 1;
    while (hi - lo > 1) {
      var mid = (lo + hi) ~/ 2;
      if (p[mid].$1 <= seconds) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    var (t0, v0) = p[lo];
    var (t1, v1) = p[hi];
    if (what?.steps ?? false) return v0;
    return t1 <= t0 ? v1 : v0 + (v1 - v0) * (seconds - t0) / (t1 - t0);
  }

  /// withPoints is the lane with [points], put in order of time.
  AutomationLane withPoints(List<AutomationPoint> points) =>
      AutomationLane(target, [...points]..sort((a, b) => a.$1.compareTo(b.$1)));

  /// written is the lane with a point of [value] at [seconds]: one already
  /// within [near] seconds of it replaced, as a fader held while recording
  /// writes over what was there.
  AutomationLane written(double seconds, double value, {double near = 0.05}) =>
      withPoints([
        for (var p in points)
          if ((p.$1 - seconds).abs() > near) p,
        (math.max(0.0, seconds), value),
      ]);

  Map<String, dynamic> toJson() => {
        "target": target,
        "points": [
          for (var (t, v) in points) [t, v]
        ],
      };

  static AutomationLane? fromJson(Object? json) {
    if (json is! Map) return null;
    var target = json["target"];
    if (target is! String || AutomationTarget.parse(target) == null) {
      return null;
    }
    return AutomationLane(
        target,
        [
          if (json["points"] case List list)
            for (var p in list)
              if (p case [num t, num v]) (t.toDouble(), v.toDouble()),
        ]..sort((a, b) => a.$1.compareTo(b.$1)));
  }

  @override
  bool operator ==(Object other) =>
      other is AutomationLane &&
      other.target == target &&
      other.points.length == points.length &&
      [for (var i = 0; i < points.length; i++) other.points[i] == points[i]]
          .every((x) => x);

  @override
  int get hashCode => Object.hash(target, points.length);
}

/// automatedAt is [mix] as it plays at [seconds]: each lane with points
/// putting its setting in -- all but those in [except], held by hand.
ChannelMix automatedAt(ChannelMix mix, double seconds,
    {Set<String> except = const {}}) {
  if (mix.automation.isEmpty) return mix;
  var gain = mix.gainDb, balance = mix.balance;
  var sends = {...mix.sends};
  var devices = [...mix.devices];
  var changed = false;
  for (var lane in mix.automation) {
    if (except.contains(lane.target)) continue;
    var what = lane.what;
    var v = lane.valueAt(seconds);
    if (what == null || v == null || !what.on(mix)) continue;
    changed = true;
    switch (what.kind) {
      case AutomationKind.volume:
        gain = v;
      case AutomationKind.pan:
        balance = v.clamp(-1.0, 1.0);
      case AutomationKind.send:
        if (v <= -60) {
          sends.remove(what.send);
        } else {
          sends[what.send] = v.clamp(-60.0, 6.0);
        }
      case AutomationKind.device:
        devices[what.device] = devices[what.device].withValue(what.param, v);
    }
  }
  if (!changed) return mix;
  return mix.copyWith(
      gainDb: gain, balance: balance, sends: sends, devices: devices);
}

/// automationTargets are the settings of [mix] a lane can move: its volume
/// and pan, a send to each return, and every setting of each device.
List<AutomationTarget> automationTargets(
        ChannelMix mix, List<ReturnChannel> returns) =>
    [
      AutomationTarget.volume,
      AutomationTarget.pan,
      for (var r in returns) AutomationTarget.sendTo(r.id),
      for (var (i, d) in mix.devices.indexed)
        for (var p in d.kind.params)
          AutomationTarget.deviceSetting(i, d.kind, p.id),
    ];

/// ClipAutomation is a slot clip's envelope of one of its channel's
/// settings -- the volume, a send, a device's knob -- moved while the clip
/// plays, then back to where it was when it stops. Its points are each a
/// beat into the clip and a height up the setting's range, nought to one,
/// as the clip's own gain and pan envelopes are. [length] is its own
/// length in beats, going round and round however long the clip is, as an
/// LFO does -- or null to go with the clip's loop.
class ClipAutomation {
  final String target;
  final List<(double, double)> points;
  final double? length;
  const ClipAutomation(this.target, {this.points = const [], this.length});

  AutomationTarget? get what => AutomationTarget.parse(target);

  ClipAutomation copyWith(
          {List<(double, double)>? points,
          double? length,
          bool linked = false}) =>
      ClipAutomation(target,
          points: points ?? this.points,
          length: linked ? null : length ?? this.length);

  /// heightAt is its height [beat] into its own length -- or into the clip,
  /// linked -- straight between points, held past either end.
  double? heightAt(double beat) {
    var p = points;
    if (p.isEmpty) return null;
    if (beat <= p.first.$1) return p.first.$2;
    if (beat >= p.last.$1) return p.last.$2;
    for (var i = 1; i < p.length; i++) {
      if (beat <= p[i].$1) {
        var (b0, v0) = p[i - 1];
        var (b1, v1) = p[i];
        if (what?.steps ?? false) return v0;
        return b1 <= b0 ? v1 : v0 + (v1 - v0) * (beat - b0) / (b1 - b0);
      }
    }
    return p.last.$2;
  }

  Map<String, dynamic> toJson() => {
        "target": target,
        "points": [
          for (var (b, v) in points) [b, v]
        ],
        if (length case var l?) "length": l,
      };

  static ClipAutomation? fromJson(Object? json) {
    if (json is! Map) return null;
    var target = json["target"];
    if (target is! String || AutomationTarget.parse(target) == null) {
      return null;
    }
    var length = json["length"];
    return ClipAutomation(target,
        points: [
          if (json["points"] case List list)
            for (var p in list)
              if (p case [num b, num v])
                (b.toDouble(), v.toDouble().clamp(0.0, 1.0)),
        ]..sort((a, b) => a.$1.compareTo(b.$1)),
        length: length is num && length > 0 ? length.toDouble() : null);
  }

  @override
  bool operator ==(Object other) =>
      other is ClipAutomation &&
      other.target == target &&
      other.length == length &&
      other.points.length == points.length &&
      [for (var i = 0; i < points.length; i++) other.points[i] == points[i]]
          .every((x) => x);

  @override
  int get hashCode => Object.hash(target, length, points.length);
}

/// clipAutomatedAt is [mix] with a playing clip's envelopes put in, over
/// whatever the timeline's lanes had: [beat] is where the clip is in
/// itself, round its loop, and [elapsed] the beats since it was launched,
/// for an envelope of its own length. Those in [except], held by a hand,
/// are left.
ChannelMix clipAutomatedAt(
    ChannelMix mix, List<ClipAutomation> lanes, double beat, double elapsed,
    {Set<String> except = const {}}) {
  if (lanes.isEmpty) return mix;
  var gain = mix.gainDb, balance = mix.balance;
  var sends = {...mix.sends};
  var devices = [...mix.devices];
  var changed = false;
  for (var lane in lanes) {
    if (except.contains(lane.target)) continue;
    var what = lane.what;
    if (what == null || !what.on(mix)) continue;
    var at = switch (lane.length) {
      var l? when l > 0 => elapsed % l,
      _ => beat,
    };
    var h = lane.heightAt(at);
    if (h == null) continue;
    var v = what.valueAt(h);
    changed = true;
    switch (what.kind) {
      case AutomationKind.volume:
        gain = v;
      case AutomationKind.pan:
        balance = v.clamp(-1.0, 1.0);
      case AutomationKind.send:
        if (v <= -60) {
          sends.remove(what.send);
        } else {
          sends[what.send] = v.clamp(-60.0, 6.0);
        }
      case AutomationKind.device:
        devices[what.device] = devices[what.device].withValue(what.param, v);
    }
  }
  if (!changed) return mix;
  return mix.copyWith(
      gainDb: gain, balance: balance, sends: sends, devices: devices);
}

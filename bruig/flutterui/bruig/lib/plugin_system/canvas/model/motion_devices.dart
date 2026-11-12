import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart'
    show jsonBool, jsonDouble, jsonInt, jsonStr;
import 'package:bruig/plugin_system/canvas/model/design_device.dart'
    show designParams;
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

  /// design is the element's own settings, animated: at the drawing itself
  /// (Ken, 2026-11-12). Its move, turn, size and fade join the pose after
  /// the pose devices; the rest are the element's own settings, keyed. See
  /// design_device.dart.
  design,
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
    DeviceParam(
        "loop", "Loop", 0, 3, 0, "", ["Off", "Cycle", "Ping-pong", "Continue"]),
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
    // Its own keys, sprung; or another element (its target), chased.
    DeviceParam(
        "follows", "Follows", 0, 1, 0, "", ["Its keys", "Another element"]),
  ]),
  followPath("Follow path", MotionDeviceSide.pose, [
    DeviceParam("start", "Start along", 0, 1, 0),
    DeviceParam("lap", "Once round", 0.5, 60, 6, "s"),
    DeviceParam("loop", "At the end", 0, 2, 0, "",
        ["Round again", "Stops", "Back and forth"]),
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

  /// macro is eight knobs, each turning any knobs of the chain it is given.
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
    // The way it falls, as a compass reads (0 up, 90 right): one name and
    // one meaning in the Chain and the settings panel (Ken, 2026-11-11).
    DeviceParam("angle", "Falls", 0, 360, 135, "°"),
    DeviceParam("strength", "Strength", 0, 1, 0.5),
    DeviceParam("turns", "Turns with it", 0, 1, 0, "",
        ["No: the light stays put", "Yes"]),
  ]),
  blur("Blur", MotionDeviceSide.look, [
    DeviceParam("amount", "Amount", 0, 40, 4, "px"),
    // Smeared along the way it moves, by how fast.
    DeviceParam("motion", "Motion blur", 0, 1, 0),
  ]),
  colour("Colour", MotionDeviceSide.look, [
    DeviceParam("hue", "Hue", -180, 180, 0, "°"),
    // A share, as Strength is: 100% as it was, 0% grey.
    DeviceParam("saturation", "Saturation", 0, 2, 1),
    DeviceParam("brightness", "Brightness", -1, 1, 0),
  ]),
  outline("Outline", MotionDeviceSide.look, [
    DeviceParam("width", "Width", 0, 30, 3, "px"),
    DeviceParam("softness", "Softness", 0, 1, 0),
  ]),

  /// wear eats it away as worn ink is: grunge, dust or halftone dots taken
  /// out of it -- an icon or a slab printed rather than drawn (Ken's privacy
  /// video, 2026-11-11: "too clean for this style").
  wear("Wear", MotionDeviceSide.look, [
    DeviceParam(
        "texture", "Texture", 0, 2, 0, "", ["Grunge", "Dust", "Halftone"]),
    DeviceParam("amount", "Amount", 0, 1, 0.45),
    DeviceParam("size", "Size", 0.2, 5, 1, "×"),
    DeviceParam("seed", "Seed", 1, 99, 1, "#"),
  ]),

  /// edges fades it out towards the edges of its box, so it lies in what is
  /// under it rather than on it: feathered all round, and faded from a side
  /// or round the middle as asked (see EdgeMask; Ken's privacy video: a
  /// picture "part of the same background").
  edges("Edges", MotionDeviceSide.look, [
    DeviceParam("feather", "Feather", 0, 0.5, 0.12),
    DeviceParam("fade", "Fade", 0, 7, 7, "", [
      "None", "From the left", "From the right", "From the top", //
      "From the bottom", "Both sides", "Top and bottom", "Round the middle",
    ]),
    DeviceParam("reach", "Reach", 0, 1, 0.6),
  ]),

  /// lens is a magnifying glass over it, going round: what is under the
  /// glass drawn bigger, inside a rim with a handle -- a ledger read for
  /// what it gives away (Ken's privacy video, 2026-11-11: "it should be
  /// circular magnifying the data").
  lens("Lens", MotionDeviceSide.look, [
    DeviceParam("x", "Across", 0, 1, 0.5),
    DeviceParam("y", "Down", 0, 1, 0.5),
    DeviceParam("size", "Size", 0.05, 1, 0.35),
    DeviceParam("zoom", "Zoom", 1, 4, 2, "×"),
    DeviceParam("orbit", "Goes round", 0, 1, 0.4),
    DeviceParam("laps", "Laps a second", 0, 2, 0.15, "/s"),
  ]),

  /// design animates the element's own settings: see design_device.dart.
  design("Design", MotionDeviceSide.design, designParams);

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

  /// layer is what of its element a look is laid on: "" for all of it -- a
  /// text's box and every piece in it as well as its words -- or one layer
  /// of it alone: [bodyLayer] for a text's own words, or a piece's id (see
  /// TextItem), its letters or its picture without the box behind them. A
  /// text's letters had a shadow, a glow and an outline of their own apart
  /// from the Chain's; they are looks on that layer now, so each is kept
  /// once (Ken, 2026-11-11). Only a look's is read.
  final String layer;

  /// bodyLayer is [layer] for a text's own words.
  static const bodyLayer = "body";

  /// keys are its settings' Independent keys, by setting: where one has
  /// any, it is that value at that moment, and in a straight line between
  /// (Ken, 2026-11-11: the settings panel sets how it rests, the Chain
  /// animates the same settings). Times are seconds into the scene.
  final Map<String, List<DeviceKey>> keys;

  /// phaseKeys are its settings' keys in its element's arrival, leaving and
  /// loop (Ken, 2026-11-12: "A, L, Loop, I"): times are shares of that
  /// clip -- 0 its start, 1 its end; of one cycle for the loop -- so they
  /// move and stretch with it. See PhaseSpans.
  final Map<MotionPhase, Map<String, List<DeviceKey>>> phaseKeys;

  /// plays are the phases its keys play in: its card's A, L, Loop and I.
  /// A phase switched off keeps its keys, unplayed.
  final Set<MotionPhase> plays;

  /// shown are the settings on its card, where a kind offers more than it
  /// shows at once: Design's, added from the element's settings panel.
  final List<String> shown;

  const MotionDevice(this.kind,
      {this.on = true,
      this.values = const {},
      this.id = "",
      this.colour,
      this.target = "",
      this.layer = "",
      this.keys = const {},
      this.phaseKeys = const {},
      this.plays = const {MotionPhase.free},
      this.shown = const [],
      this.mods = const []});

  MotionDevice _copy({
    bool? on,
    Map<String, double>? values,
    String? id,
    int? Function()? colour,
    String? target,
    String? layer,
    Map<String, List<DeviceKey>>? keys,
    Map<MotionPhase, Map<String, List<DeviceKey>>>? phaseKeys,
    Set<MotionPhase>? plays,
    List<String>? shown,
    List<ModTarget>? mods,
  }) =>
      MotionDevice(kind,
          on: on ?? this.on,
          values: values ?? this.values,
          id: id ?? this.id,
          colour: colour == null ? this.colour : colour(),
          target: target ?? this.target,
          layer: layer ?? this.layer,
          keys: keys ?? this.keys,
          phaseKeys: phaseKeys ?? this.phaseKeys,
          plays: plays ?? this.plays,
          shown: shown ?? this.shown,
          mods: mods ?? this.mods);

  /// takesTarget is whether it works with another element.
  bool get takesTarget =>
      kind == MotionDeviceKind.followPath ||
      kind == MotionDeviceKind.lookAt ||
      (kind == MotionDeviceKind.spring && value("follows").round() == 1) ||
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
    return _copy(values: {...values, id: whole ? v.roundToDouble() : v});
  }

  MotionDevice switched(bool on) => _copy(on: on);
  MotionDevice withId(String id) => _copy(id: id);
  MotionDevice withColour(int? colour) => _copy(colour: () => colour);
  MotionDevice withTarget(String target) => _copy(target: target);
  MotionDevice withLayer(String layer) => _copy(layer: layer);
  MotionDevice withMods(List<ModTarget> mods) => _copy(mods: mods);
  MotionDevice withShown(List<String> shown) => _copy(shown: shown);

  /// keysIn are its settings' keys in phase [ph].
  Map<String, List<DeviceKey>> keysIn(MotionPhase ph) =>
      ph == MotionPhase.free ? keys : phaseKeys[ph] ?? const {};

  MotionDevice _withKeysIn(MotionPhase ph, Map<String, List<DeviceKey>> next) {
    var tidy = {
      for (var MapEntry(:key, :value) in next.entries)
        if (value.isNotEmpty) key: value
    };
    if (ph == MotionPhase.free) return _copy(keys: tidy);
    var all = {...phaseKeys};
    if (tidy.isEmpty) {
      all.remove(ph);
    } else {
      all[ph] = tidy;
    }
    return _copy(phaseKeys: all);
  }

  /// playing is whether its keys in [ph] play: see [plays].
  bool playing(MotionPhase ph) => plays.contains(ph);

  /// withPlaying is this with its keys in [ph] played, or not.
  MotionDevice withPlaying(MotionPhase ph, bool play) =>
      _copy(plays: play ? {...plays, ph} : ({...plays}..remove(ph)));

  /// keyed is whether setting [id] is animated by keys, in any phase.
  bool keyed(String id) => MotionPhase.values.any((ph) => keyedIn(id, ph));

  /// keyedIn is whether setting [id] has keys in phase [ph].
  bool keyedIn(String id, MotionPhase ph) =>
      keysIn(ph)[id]?.isNotEmpty ?? false;

  /// animated is whether any of its settings is.
  bool get animated => MotionPhase.values
      .any((ph) => keysIn(ph).values.any((k) => k.isNotEmpty));

  /// liveIn is the phase whose keys of setting [id] play at [t] -- the clip
  /// playing then, where its keys play in it and it has some; otherwise
  /// Independent -- or null where none do.
  MotionPhase? liveIn(String id, double t, PhaseSpans spans) {
    for (var ph in spans.phasesAt(t)) {
      if (playing(ph) && keyedIn(id, ph)) return ph;
    }
    if (playing(MotionPhase.free) && keyedIn(id, MotionPhase.free)) {
      return MotionPhase.free;
    }
    return null;
  }

  /// valueAt is setting [id] at [t] seconds: by the keys playing then (see
  /// [liveIn]), level before the first and after the last; how it rests
  /// where none play.
  double valueAt(String id, double t, {PhaseSpans spans = PhaseSpans.none}) {
    var ph = liveIn(id, t, spans);
    if (ph == null) return value(id);
    var ks = keysIn(ph)[id]!;
    var p = kind.param(id);
    var at = ph == MotionPhase.free ? t : spans.shareIn(ph, t);
    return p.unit == "argb"
        ? _alongColour(ks, at)
        : _along(ks, at).clamp(p.min, p.max).toDouble();
  }

  /// at is this device as it is [t] seconds into the scene: its keyed
  /// settings' values then. Itself where nothing is keyed.
  MotionDevice at(double t, {PhaseSpans spans = PhaseSpans.none}) {
    if (!animated) return this;
    var next = this;
    var ids = {for (var ph in MotionPhase.values) ...keysIn(ph).keys};
    for (var id in ids) {
      if (liveIn(id, t, spans) != null) {
        next = next._withPlainValue(id, valueAt(id, t, spans: spans));
      }
    }
    return next;
  }

  /// keyPhase is the phase a key made at [t] goes in: the clip playing then
  /// where its keys play in it; otherwise Independent.
  MotionPhase keyPhase(double t, PhaseSpans spans) =>
      spans.phasesAt(t).firstWhere(playing, orElse: () => MotionPhase.free);

  double _when(MotionPhase ph, double t, PhaseSpans spans) =>
      ph == MotionPhase.free ? t : spans.shareIn(ph, t);

  /// keyAt is whether setting [id] has a key at [t], in the phase a key
  /// made there would go in: within a frame or so.
  bool keyAt(String id, double t,
      {double near = 0.02, PhaseSpans spans = PhaseSpans.none}) {
    var ph = keyPhase(t, spans);
    var at = _when(ph, t, spans);
    var within = ph == MotionPhase.free ? near : 0.01;
    return keysIn(ph)[id]?.any((k) => (k.t - at).abs() <= within) ?? false;
  }

  /// withKey is this with setting [id] keyed to [v] at [t], in the phase a
  /// key made there goes in (see [keyPhase]): a key already there moved to
  /// it.
  MotionDevice withKey(String id, double t, double v,
      {double near = 0.02, PhaseSpans spans = PhaseSpans.none}) {
    var p = kind.param(id);
    var ph = keyPhase(t, spans);
    var at = _when(ph, t, spans);
    var within = ph == MotionPhase.free ? near : 0.01;
    var was = keysIn(ph)[id] ?? const <DeviceKey>[];
    var kept = was.where((k) => (k.t - at).abs() <= within).firstOrNull;
    var list = [
      for (var k in was)
        if ((k.t - at).abs() > within) k,
      DeviceKey(at, p.unit == "argb" ? v : v.clamp(p.min, p.max).toDouble(),
          ease: kept?.ease ?? KeyEase.straight),
    ]..sort((a, b) => a.t.compareTo(b.t));
    return _withKeysIn(ph, {...keysIn(ph), id: list}).withPlaying(ph, true);
  }

  /// withoutKeyAt is this without setting [id]'s key at [t], in the phase
  /// a key there is in. Its last key taken away, the setting keeps the
  /// value it had there, where it was keyed independently.
  MotionDevice withoutKeyAt(String id, double t,
      {double near = 0.02, PhaseSpans spans = PhaseSpans.none}) {
    var ph = keyPhase(t, spans);
    var at = _when(ph, t, spans);
    var within = ph == MotionPhase.free ? near : 0.01;
    var list = [
      for (var k in keysIn(ph)[id] ?? const <DeviceKey>[])
        if ((k.t - at).abs() > within) k,
    ];
    if (list.isEmpty && ph == MotionPhase.free) {
      var v = valueAt(id, t, spans: spans);
      return _withKeysIn(ph, {...keysIn(ph)}..remove(id))
          ._withPlainValue(id, v);
    }
    return _withKeysIn(ph, {...keysIn(ph), id: list});
  }

  /// withKeysOf is this with setting [id]'s keys in [ph] made [list].
  MotionDevice withKeysOf(String id, MotionPhase ph, List<DeviceKey> list) =>
      _withKeysIn(ph, {...keysIn(ph), id: list});

  /// withoutKeys is this with setting [id] no longer animated, in any
  /// phase: it keeps the value it has at [at].
  MotionDevice withoutKeys(String id,
      {double at = 0, PhaseSpans spans = PhaseSpans.none}) {
    var v = valueAt(id, at, spans: spans);
    var next = this;
    for (var ph in MotionPhase.values) {
      next = next._withKeysIn(ph, {...next.keysIn(ph)}..remove(id));
    }
    return next._withPlainValue(id, v);
  }

  MotionDevice _withPlainValue(String id, double v) =>
      _copy(values: {...values, id: v});

  static List<List<num>> _keysJson(List<DeviceKey> ks) => [
        for (var k in ks)
          [k.t, k.v, if (k.ease != KeyEase.straight) k.ease.index]
      ];

  static Map<String, List<DeviceKey>> _keysRead(Object? raw, Set<String> ids) =>
      {
        if (raw case Map m)
          for (var MapEntry(:key, :value) in m.entries)
            if (key is String && ids.contains(key) && value is List)
              key: [
                for (var k in value)
                  if (k is List && k.length >= 2)
                    DeviceKey(jsonDouble(k[0], 0), jsonDouble(k[1], 0),
                        ease: k.length > 2
                            ? KeyEase.values[jsonInt(k[2], 0)
                                .clamp(0, KeyEase.values.length - 1)]
                            : KeyEase.straight),
              ]..sort((a, b) => a.t.compareTo(b.t)),
      };

  Map<String, dynamic> toJson() => {
        "kind": kind.name,
        if (!on) "on": false,
        if (values.isNotEmpty) "values": values,
        if (id.isNotEmpty) "id": id,
        if (colour != null) "colour": colour,
        if (target.isNotEmpty) "target": target,
        if (layer.isNotEmpty) "layer": layer,
        if (keys.isNotEmpty)
          "keys": {
            for (var MapEntry(:key, :value) in keys.entries)
              key: _keysJson(value),
          },
        if (phaseKeys.isNotEmpty)
          "phaseKeys": {
            for (var MapEntry(:key, :value) in phaseKeys.entries)
              key.name: {
                for (var e in value.entries) e.key: _keysJson(e.value),
              },
          },
        if (!(plays.length == 1 && plays.contains(MotionPhase.free)))
          "plays": [for (var ph in plays) ph.name],
        if (shown.isNotEmpty) "shown": shown,
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
        layer: jsonStr(json["layer"]) ?? "",
        keys: _keysRead(json["keys"], ids),
        phaseKeys: {
          if (json["phaseKeys"] case Map raw)
            for (var MapEntry(:key, :value) in raw.entries)
              if (MotionPhase.values.where((p) => p.name == key).firstOrNull
                  case var ph? when ph != MotionPhase.free)
                ph: _keysRead(value, ids),
        },
        plays: json["plays"] is List
            ? {
                for (var n in json["plays"] as List)
                  if (MotionPhase.values.where((p) => p.name == n).firstOrNull
                      case var ph?)
                    ph
              }
            : const {MotionPhase.free},
        shown: [
          if (json["shown"] case List raw)
            for (var s in raw)
              if (s is String && ids.contains(s)) s
        ],
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
      other.layer == layer &&
      _sameKeys(other.keys, keys) &&
      other.phaseKeys.length == phaseKeys.length &&
      phaseKeys.entries.every(
          (e) => _sameKeys(other.phaseKeys[e.key] ?? const {}, e.value)) &&
      other.plays.length == plays.length &&
      other.plays.containsAll(plays) &&
      other.shown.join(",") == shown.join(",") &&
      other.mods.length == mods.length &&
      [for (var i = 0; i < mods.length; i++) other.mods[i] == mods[i]]
          .every((x) => x) &&
      other.values.length == values.length &&
      values.entries.every((e) => other.values[e.key] == e.value);

  @override
  int get hashCode => Object.hash(kind, on, id, colour, values.length);
}

/// MotionPhase is where a device's keys play (Ken, 2026-11-12): in its
/// element's arrival, its leaving, its loop -- or independently, in the
/// scene's own time. Its card's A, L, Loop and I.
enum MotionPhase {
  arrive("Arrive", "A"),
  leave("Leave", "L"),
  loop("Loop", "Loop"),
  free("Independent", "I");

  final String label;
  final String short;
  const MotionPhase(this.label, this.short);
}

/// PhaseSpans are when an element's arrival, leaving and loop play, in
/// seconds: what phase keys are timed by. See phaseSpansOf.
class PhaseSpans {
  final (double, double)? arrive;
  final (double, double)? leave;
  final (double, double)? loop;

  /// cycle is how long one go round the loop takes.
  final double cycle;

  const PhaseSpans({this.arrive, this.leave, this.loop, this.cycle = 2});

  /// none has no clips: every key plays independently.
  static const none = PhaseSpans();

  (double, double)? spanOf(MotionPhase ph) => switch (ph) {
        MotionPhase.arrive => arrive,
        MotionPhase.leave => leave,
        MotionPhase.loop => loop,
        MotionPhase.free => null,
      };

  /// phasesAt are the clips playing at [t]: an arrival's or leaving's
  /// last moment is in it, so its end can be keyed, though the loop starts
  /// there too.
  List<MotionPhase> phasesAt(double t) => [
        for (var ph in const [MotionPhase.arrive, MotionPhase.leave])
          if (spanOf(ph) case (var a, var b) when t >= a && t <= b) ph,
        if (loop case (var a, var b) when t >= a && t < b) MotionPhase.loop,
      ];

  /// phaseAt is the clip playing at [t], or free outside them all.
  MotionPhase phaseAt(double t) => phasesAt(t).firstOrNull ?? MotionPhase.free;

  /// shareIn is [t] as a share of phase [ph]: of its clip, or of one go
  /// round the loop.
  double shareIn(MotionPhase ph, double t) {
    var span = spanOf(ph);
    if (span == null) return t;
    var (a, b) = span;
    if (ph == MotionPhase.loop) {
      var c = cycle <= 0 ? 1.0 : cycle;
      return (((t - a) % c) + c) % c / c;
    }
    return ((t - a) / math.max(0.0001, b - a)).clamp(0.0, 1.0).toDouble();
  }

  /// timeOf is a key at share [share] of phase [ph] in seconds: the loop's
  /// first go round.
  double timeOf(MotionPhase ph, double share) {
    var span = spanOf(ph);
    if (span == null) return share;
    var (a, b) = span;
    return ph == MotionPhase.loop ? a + share * cycle : a + share * (b - a);
  }

  @override
  bool operator ==(Object other) =>
      other is PhaseSpans &&
      other.arrive == arrive &&
      other.leave == leave &&
      other.loop == loop &&
      other.cycle == cycle;

  @override
  int get hashCode => Object.hash(arrive, leave, loop, cycle);
}

/// KeyEase is how a key's value goes into the next key's.
enum KeyEase {
  straight("Straight"),
  easeInOut("Ease in and out"),
  easeOut("Ease out"),
  hold("Hold");

  final String label;
  const KeyEase(this.label);

  double apply(double f) => switch (this) {
        KeyEase.straight => f,
        KeyEase.easeInOut =>
          f < 0.5 ? 2 * f * f : 1 - math.pow(-2 * f + 2, 2) / 2,
        KeyEase.easeOut => 1 - (1 - f) * (1 - f),
        KeyEase.hold => f >= 1 ? 1 : 0,
      };
}

/// DeviceKey is one key of a device's setting: value [v] at [t] -- seconds
/// into the scene, or a share of a clip (see MotionDevice.phaseKeys) --
/// and how it goes into the next.
class DeviceKey {
  final double t;
  final double v;
  final KeyEase ease;
  const DeviceKey(this.t, this.v, {this.ease = KeyEase.straight});

  DeviceKey copyWith({double? t, double? v, KeyEase? ease}) =>
      DeviceKey(t ?? this.t, v ?? this.v, ease: ease ?? this.ease);

  @override
  bool operator ==(Object other) =>
      other is DeviceKey && other.t == t && other.v == v && other.ease == ease;

  @override
  int get hashCode => Object.hash(t, v, ease);
}

/// _along is the value [ks] come to at [t]: level before the first and
/// after the last, eased between as each key says.
double _along(List<DeviceKey> ks, double t) {
  if (t <= ks.first.t) return ks.first.v;
  if (t >= ks.last.t) return ks.last.v;
  for (var i = 1; i < ks.length; i++) {
    var a = ks[i - 1], b = ks[i];
    if (t <= b.t) {
      var f = b.t == a.t ? 1.0 : (t - a.t) / (b.t - a.t);
      return a.v + (b.v - a.v) * a.ease.apply(f);
    }
  }
  return ks.last.v;
}

/// _alongColour is [_along] for colours kept as ARGB: each channel blended.
double _alongColour(List<DeviceKey> ks, double t) {
  int ch(double v, int shift) => (v.toInt() >> shift) & 0xFF;
  if (t <= ks.first.t) return ks.first.v;
  if (t >= ks.last.t) return ks.last.v;
  for (var i = 1; i < ks.length; i++) {
    var a = ks[i - 1], b = ks[i];
    if (t <= b.t) {
      var f = a.ease.apply(b.t == a.t ? 1.0 : (t - a.t) / (b.t - a.t));
      var out = 0;
      for (var shift in const [24, 16, 8, 0]) {
        var x = ch(a.v, shift), y = ch(b.v, shift);
        out |= ((x + (y - x) * f).round().clamp(0, 255)) << shift;
      }
      return out.toDouble();
    }
  }
  return ks.last.v;
}

bool _sameKeys(Map<String, List<DeviceKey>> a, Map<String, List<DeviceKey>> b) {
  if (a.length != b.length) return false;
  for (var MapEntry(:key, :value) in a.entries) {
    var other = b[key];
    if (other == null || other.length != value.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (other[i] != value[i]) return false;
    }
  }
  return true;
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
        if (d.side == MotionDeviceSide.design) d,
      for (var d in chain)
        if (d.side == MotionDeviceSide.look) d,
    ];

/// motionFamily is where [kind] is listed when one is added, as the sound
/// chain's devices are: by what it does.
String motionFamily(MotionDeviceKind kind) => switch (kind) {
      MotionDeviceKind.time => "Time",
      MotionDeviceKind.wiggle ||
      MotionDeviceKind.oscillate ||
      MotionDeviceKind.spring ||
      MotionDeviceKind.squash =>
        "Movement",
      MotionDeviceKind.followPath ||
      MotionDeviceKind.lookAt ||
      MotionDeviceKind.followSound =>
        "Follow",
      MotionDeviceKind.lfo ||
      MotionDeviceKind.macro ||
      MotionDeviceKind.follower =>
        "Modulators",
      MotionDeviceKind.glow ||
      MotionDeviceKind.shadow ||
      MotionDeviceKind.outline ||
      MotionDeviceKind.edges =>
        "Light and edge",
      MotionDeviceKind.blur ||
      MotionDeviceKind.colour ||
      MotionDeviceKind.wear ||
      MotionDeviceKind.lens =>
        "Picture",
      MotionDeviceKind.instances => "Instances",
      MotionDeviceKind.design => "Design",
    };

/// motionAbout is what [kind] does, in a few words: what its "?" and its
/// ⋯ menu's "What it does" say.
String motionAbout(MotionDeviceKind kind) => switch (kind) {
      MotionDeviceKind.instances =>
        "Where the element splits into its copies: what is left of it is "
            "worked out once for all of them, what is right of it for each.",
      MotionDeviceKind.time =>
        "Changes time for everything to its left: Speed, an Offset, a Loop "
            "round a stretch Every so long, and Hold frames for a "
            "stepped, drawn-by-hand look.",
      MotionDeviceKind.wiggle =>
        "A restless drift: moves it about by Amount, Speed times a second, "
            "with a little Turn. Each its own gives every copy its own.",
      MotionDeviceKind.oscillate =>
        "A steady swing: up and down, side to side, in size or in turn, "
            "Rate times a second.",
      MotionDeviceKind.spring =>
        "Overshoots where its keys take it and settles: Stiffness is how "
            "quickly, Damping how soon it calms.",
      MotionDeviceKind.followPath =>
        "Travels along a path or line element, once round in so many "
            "seconds, turning with it if asked.",
      MotionDeviceKind.lookAt =>
        "Turns to face another element, as smoothly as asked, with an "
            "Offset for an element drawn facing another way.",
      MotionDeviceKind.squash =>
        "Squashes and stretches as it moves: more the faster it goes.",
      MotionDeviceKind.followSound =>
        "Moves with a channel's loudness: grows, rises, turns or shows "
            "as it gets louder.",
      MotionDeviceKind.lfo =>
        "Moves nothing itself: turns other devices' knobs up and down in a "
            "wave. Give it knobs below, or right-click a knob.",
      MotionDeviceKind.macro =>
        "Eight knobs, each turning any knobs of this chain you give it.",
      MotionDeviceKind.follower =>
        "Turns other devices' knobs by how loud a channel is.",
      MotionDeviceKind.glow => "A soft light round it.",
      MotionDeviceKind.shadow =>
        "A shadow under it, Distance away at an Angle, as blurred as asked.",
      MotionDeviceKind.blur => "Blurs it as a whole.",
      MotionDeviceKind.colour => "Shifts its hue, saturation and brightness.",
      MotionDeviceKind.outline => "A line round its edge.",
      MotionDeviceKind.wear =>
        "Wears it away like old ink: grunge, dust or halftone dots taken "
            "out of it, as much as Amount, as coarse as Size.",
      MotionDeviceKind.edges =>
        "Fades it into what is under it: its edges feathered, and faded "
            "from a side or round the middle, as far in as Reach.",
      MotionDeviceKind.lens =>
        "A magnifying glass over it: what is under the glass Zoom times "
            "bigger, going round its middle so many Laps a second.",
      MotionDeviceKind.design =>
        "The element's own settings, animated: where it is, its turn, "
            "size and fade, and the settings of its panel you add -- in "
            "its arrival, leaving and loop, or on their own.",
    };

/// motionParamShown is whether [p] of [d] does anything as it is set, so
/// is shown: Time's Every only while it loops, Wiggle's Seed only on an
/// element with copies.
bool motionParamShown(MotionDevice d, DeviceParam p, {bool reused = false}) =>
    switch ((d.kind, p.id)) {
      (MotionDeviceKind.time, "every") => d.value("loop").round() != 0,
      (MotionDeviceKind.wiggle, "seed") => reused,
      _ => true,
    };

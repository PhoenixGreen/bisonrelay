import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';

// motion.dart is how an element moves: its clips. A clip is a piece of
// animation belonging to one element (an arrival, a loop, a way out, an
// action) made of keys, played from a slot, a cue or a trigger, or placed on
// the timeline.
//
// Clips are the animation model. Legacy keyframe tracks are converted to
// clips when a canvas opens (motion_convert.dart); a preset only writes a
// clip's keys (motion_presets.dart). render/motion_pose.dart works out what
// an element looks like at a moment.
//
// Times in a clip are seconds from its start, and on the timeline seconds
// from the scene's start, so changing the frame rate changes no speeds.

/// MotionProp is one thing a clip's keys move, relative to the element as
/// set (moved by, sized by, turned by), so one clip works on any element.
enum MotionProp {
  x("Across", 0),
  y("Down", 0),
  scale("Size", 1),
  turn("Turn", 0),
  opacity("Opacity", 1);

  final String label;

  /// rest is its value when nothing moves it.
  final double rest;
  const MotionProp(this.label, this.rest);

  static MotionProp? fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// MotionPlaceKind is a place a key can name instead of a number, worked out
/// as the clip plays so it holds when the page or its target moves.
enum MotionPlaceKind {
  /// offLeft and its fellows are just past an edge, the element wholly out
  /// of sight.
  offLeft("Off the left edge"),
  offRight("Off the right edge"),
  offTop("Above the page"),
  offBottom("Below the page"),

  /// beside is next to another element, on the side it is on; ground puts
  /// their bottoms level.
  beside("Beside"),
  ground("On the ground of"),

  /// on is where another element is drawn now, as it moves: what a
  /// following camera looks at.
  on("On");

  final String label;
  const MotionPlaceKind(this.label);

  bool get needsTarget => this == beside || this == ground || this == on;

  static MotionPlaceKind? fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// MotionValue is a key's value: a number, or a place worked out as it plays.
sealed class MotionValue {
  const MotionValue();

  Object toJson();

  static MotionValue fromJson(Object? json, double fallback) {
    if (json is num && json.isFinite) return MotionNumber(json.toDouble());
    if (json is Map) {
      var kind = MotionPlaceKind.fromName(json["place"]);
      if (kind != null) {
        return MotionPlace(kind,
            target: json["of"] is String ? json["of"] as String : "",
            by: jsonDouble(json["by"], 0).clamp(-4000.0, 4000.0));
      }
    }
    return MotionNumber(fallback);
  }
}

class MotionNumber extends MotionValue {
  final double value;
  const MotionNumber(this.value);

  @override
  Object toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is MotionNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class MotionPlace extends MotionValue {
  final MotionPlaceKind kind;

  /// target is the element it is worked out from, by id, where it names one.
  final String target;

  /// by is how many pixels on from the place it is, the way the place
  /// moves it (across, or up and down for above and below the page): the
  /// prototype's Place Offset.
  final double by;
  const MotionPlace(this.kind, {this.target = "", this.by = 0});

  /// moves is whether the place moves an element along [prop]: an edge
  /// along its own axis, a place by another element along both.
  bool moves(MotionProp prop) => switch (kind) {
        MotionPlaceKind.offLeft ||
        MotionPlaceKind.offRight =>
          prop == MotionProp.x,
        MotionPlaceKind.offTop ||
        MotionPlaceKind.offBottom =>
          prop == MotionProp.y,
        _ => prop == MotionProp.x || prop == MotionProp.y,
      };

  /// offsets is the axis [by] is along.
  MotionProp get offsets =>
      kind == MotionPlaceKind.offTop || kind == MotionPlaceKind.offBottom
          ? MotionProp.y
          : MotionProp.x;

  MotionPlace copyWith({MotionPlaceKind? kind, String? target, double? by}) =>
      MotionPlace(kind ?? this.kind,
          target: target ?? this.target, by: by ?? this.by);

  @override
  Object toJson() => {
        "place": kind.name,
        if (target.isNotEmpty) "of": target,
        if (by != 0) "by": by,
      };

  @override
  bool operator ==(Object other) =>
      other is MotionPlace &&
      other.kind == kind &&
      other.target == target &&
      other.by == by;

  @override
  int get hashCode => Object.hash(kind, target, by);
}

/// MotionKey is where a property is at [t] seconds into the clip, and the
/// easing from the key before.
class MotionKey {
  final double t;
  final MotionValue value;
  final KeyframeEasing ease;

  const MotionKey(this.t, this.value, {this.ease = KeyframeEasing.linear});

  MotionKey copyWith({double? t, MotionValue? value, KeyframeEasing? ease}) =>
      MotionKey(t ?? this.t, value ?? this.value, ease: ease ?? this.ease);

  Map<String, dynamic> toJson() => {
        "t": t,
        "v": value.toJson(),
        if (ease != KeyframeEasing.linear) "ease": ease.name,
      };

  static MotionKey fromJson(Map json, double rest) => MotionKey(
        jsonDouble(json["t"], 0).clamp(0.0, 3600.0),
        MotionValue.fromJson(json["v"], rest),
        ease: KeyframeEasing.fromName(jsonStr(json["ease"])),
      );

  @override
  bool operator ==(Object other) =>
      other is MotionKey &&
      other.t == t &&
      other.value == value &&
      other.ease == ease;

  @override
  int get hashCode => Object.hash(t, value, ease);
}

/// MotionKind is what a clip is for. It sets the clip's colour, the presets
/// offered, and its default holds before and after (an arrival waits at its
/// first frame, a way out stays gone).
enum MotionKind {
  arrive("Arriving", ClipHold.first, ClipHold.rest),
  loop("Looping", ClipHold.rest, ClipHold.rest),
  leave("Leaving", ClipHold.rest, ClipHold.last),
  action("Action", ClipHold.rest, ClipHold.rest),

  /// model is a 3D model's own animation: the keys are in the model file;
  /// the clip says which, and when.
  model("From the model", ClipHold.rest, ClipHold.rest),

  /// camera is a Camera element's move: where it looks and how near.
  camera("Camera move", ClipHold.rest, ClipHold.last),

  /// sound is a sound, on an element's own sound lane or a channel.
  sound("Sound", ClipHold.rest, ClipHold.rest);

  final String label;
  final ClipHold before;
  final ClipHold after;
  const MotionKind(this.label, this.before, this.after);

  static MotionKind fromName(Object? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => action);
}

/// ClipHold is what a clip does outside the time it plays: nothing, or hold
/// its first or last frame.
enum ClipHold {
  rest("As it is"),
  first("Holds its first frame"),
  last("Holds its last frame");

  final String label;
  const ClipHold(this.label);

  static ClipHold fromName(Object? name, ClipHold fallback) =>
      values.firstWhere((h) => h.name == name, orElse: () => fallback);
}

/// ClipLaunch is what a press on a clip's slot does, as the audio slots'
/// LaunchMode.
enum ClipLaunch {
  trigger("Starts it"),
  gate("Plays while held"),
  toggle("Starts or stops it"),
  repeat("Repeats while held");

  final String label;
  const ClipLaunch(this.label);

  static ClipLaunch fromName(Object? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => trigger);
}

/// ClipThen is what happens when a clip that plays once has played.
enum ClipThen {
  nothing("Nothing"),
  next("Plays the next slot"),
  play("Plays another clip"),
  stop("Stops"),
  back("Back to the timeline");

  final String label;
  const ClipThen(this.label);

  static ClipThen fromName(Object? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => nothing);
}

/// ClipTriggerKind is what else starts a clip besides its slot, in a
/// published interactive canvas, a game, or the editor's Try it.
enum ClipTriggerKind {
  sceneStarts("The scene starts"),
  clicked("Clicked"),
  key("A key is pressed"),
  clipEnds("Another clip ends"),
  marker("The playhead reaches a marker"),
  touched("A player touches it"),
  count("A count reaches");

  final String label;
  const ClipTriggerKind(this.label);

  static ClipTriggerKind? fromName(Object? name) =>
      values.where((t) => t.name == name).firstOrNull;
}

/// ClipTrigger is one trigger: its kind, the element, key, clip, marker or
/// count it names, and [amount] for a count.
class ClipTrigger {
  final ClipTriggerKind kind;
  final String target;
  final double amount;

  const ClipTrigger(this.kind, {this.target = "", this.amount = 0});

  Map<String, dynamic> toJson() => {
        "on": kind.name,
        if (target.isNotEmpty) "of": target,
        if (amount != 0) "n": amount,
      };

  static ClipTrigger? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = ClipTriggerKind.fromName(json["on"]);
    if (kind == null) return null;
    return ClipTrigger(kind,
        target: jsonString(json["of"], ""), amount: jsonDouble(json["n"], 0));
  }

  @override
  bool operator ==(Object other) =>
      other is ClipTrigger &&
      other.kind == kind &&
      other.target == target &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(kind, target, amount);
}

/// motionLayers is how many layers an element's motion has. Clips on
/// different layers play together, their moves added (floating while
/// sliding in).
const int motionLayers = 3;

/// soundLayer is the lane an element's own sound plays on, after its motion
/// layers.
const int soundLayer = motionLayers;

/// MotionClip is one clip. Immutable.
class MotionClip {
  final String id;
  final String name;
  final MotionKind kind;

  /// preset is the ready-made motion that wrote the keys; [edited] once a
  /// key is changed by hand.
  final String preset;
  final bool edited;

  /// length is the clip's own length in seconds, and speed how fast it plays
  /// from a slot (on the timeline its placement sets its pace).
  final double length;
  final double speed;
  final bool loop;

  /// replace is whether, while it plays, its layer takes the element over
  /// from the layers under it (as far as its weight goes) rather than
  /// adding to them: the prototype's Layer: Replace | Add.
  final bool replace;

  /// layer is which of the element's layers it plays on: 0 to
  /// [motionLayers] - 1, or [soundLayer] for a sound.
  final int layer;

  final ClipHold before;
  final ClipHold after;

  /// absolute makes its across and down keys page positions rather than
  /// moves from where the element is.
  final bool absolute;

  final Map<MotionProp, List<MotionKey>> keys;

  final ClipLaunch launch;

  /// quantise is what a launch waits for: null for the timeline's setting,
  /// else "off", "beat" or "bar".
  final String? quantise;
  final ClipThen then;

  /// thenClip is the clip id [ClipThen.play] plays.
  final String thenClip;
  final List<ClipTrigger> triggers;

  /// inside is settings only this kind of element has in a clip (a text's
  /// words, a character's face, a model's animation by name), kept as
  /// settings rather than keys. See [insideAt].
  final Map<String, dynamic> inside;

  /// sound is a sound clip's asset id.
  final String sound;

  const MotionClip({
    required this.id,
    this.name = "",
    this.kind = MotionKind.action,
    this.preset = "",
    this.edited = false,
    this.length = 1,
    this.speed = 1,
    this.loop = false,
    this.replace = false,
    this.layer = 0,
    this.before = ClipHold.rest,
    this.after = ClipHold.rest,
    this.absolute = false,
    this.keys = const {},
    this.launch = ClipLaunch.trigger,
    this.quantise,
    this.then = ClipThen.nothing,
    this.thenClip = "",
    this.triggers = const [],
    this.inside = const {},
    this.sound = "",
  });

  /// ofKind is a new clip of [kind], holding as that kind holds.
  factory MotionClip.ofKind(String id, MotionKind kind,
          {String name = "",
          String preset = "",
          double length = 1,
          int layer = 0,
          Map<MotionProp, List<MotionKey>> keys = const {}}) =>
      MotionClip(
        id: id,
        name: name,
        kind: kind,
        preset: preset,
        length: length,
        loop: kind == MotionKind.loop,
        layer: kind == MotionKind.sound ? soundLayer : layer,
        before: kind.before,
        after: kind.after,
        keys: keys,
      );

  bool get isSound => kind == MotionKind.sound;

  /// span is how long it plays from a slot, at [speed].
  double get span => length / (speed <= 0 ? 1 : speed);

  MotionClip copyWith({
    String? id,
    String? name,
    MotionKind? kind,
    String? preset,
    bool? edited,
    double? length,
    double? speed,
    bool? loop,
    bool? replace,
    int? layer,
    ClipHold? before,
    ClipHold? after,
    bool? absolute,
    Map<MotionProp, List<MotionKey>>? keys,
    ClipLaunch? launch,
    String? Function()? quantise,
    ClipThen? then,
    String? thenClip,
    List<ClipTrigger>? triggers,
    Map<String, dynamic>? inside,
    String? sound,
  }) =>
      MotionClip(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        preset: preset ?? this.preset,
        edited: edited ?? this.edited,
        length: (length ?? this.length).clamp(0.02, 3600.0),
        speed: (speed ?? this.speed).clamp(0.05, 20.0),
        loop: loop ?? this.loop,
        replace: replace ?? this.replace,
        layer: (layer ?? this.layer).clamp(0, soundLayer),
        before: before ?? this.before,
        after: after ?? this.after,
        absolute: absolute ?? this.absolute,
        keys: keys ?? this.keys,
        launch: launch ?? this.launch,
        quantise: quantise != null ? quantise() : this.quantise,
        then: then ?? this.then,
        thenClip: thenClip ?? this.thenClip,
        triggers: triggers ?? this.triggers,
        inside: inside ?? this.inside,
        sound: sound ?? this.sound,
      );

  /// retimed is this clip [length] seconds long, its keys scaled with it.
  MotionClip retimed(double length) {
    var to = length.clamp(0.02, 3600.0);
    var f = to / this.length;
    return copyWith(length: to, keys: {
      for (var MapEntry(:key, :value) in keys.entries)
        key: [for (var k in value) k.copyWith(t: k.t * f)],
    });
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        "kind": kind.name,
        if (preset.isNotEmpty) "preset": preset,
        if (edited) "edited": true,
        "length": length,
        if (speed != 1) "speed": speed,
        if (loop) "loop": true,
        if (replace) "replace": true,
        if (layer != 0) "layer": layer,
        if (before != kind.before) "before": before.name,
        if (after != kind.after) "after": after.name,
        if (absolute) "absolute": true,
        if (keys.isNotEmpty)
          "keys": {
            for (var MapEntry(:key, :value) in keys.entries)
              if (value.isNotEmpty) key.name: [for (var k in value) k.toJson()],
          },
        if (launch != ClipLaunch.trigger) "launch": launch.name,
        if (quantise != null) "quantise": quantise,
        if (then != ClipThen.nothing) "then": then.name,
        if (thenClip.isNotEmpty) "thenClip": thenClip,
        if (triggers.isNotEmpty)
          "triggers": [for (var t in triggers) t.toJson()],
        if (inside.isNotEmpty) "inside": inside,
        if (sound.isNotEmpty) "sound": sound,
      };

  static MotionClip? fromJson(Object? json) {
    if (json is! Map || json["id"] is! String) return null;
    var kind = MotionKind.fromName(json["kind"]);
    var keys = <MotionProp, List<MotionKey>>{};
    if (json["keys"] case Map raw) {
      for (var MapEntry(:key, :value) in raw.entries) {
        var prop = MotionProp.fromName(key);
        if (prop == null || value is! List) continue;
        var list = [
          for (var k in value)
            if (k is Map) MotionKey.fromJson(k, prop.rest),
        ]..sort((a, b) => a.t.compareTo(b.t));
        if (list.isNotEmpty) keys[prop] = list;
      }
    }
    return MotionClip(
      id: json["id"] as String,
      name: jsonString(json["name"], ""),
      kind: kind,
      preset: jsonString(json["preset"], ""),
      edited: jsonBool(json["edited"], false),
      length: jsonDouble(json["length"], 1).clamp(0.02, 3600.0),
      speed: jsonDouble(json["speed"], 1).clamp(0.05, 20.0),
      loop: jsonBool(json["loop"], false),
      replace: jsonBool(json["replace"], false),
      layer: jsonInt(json["layer"], kind == MotionKind.sound ? soundLayer : 0)
          .clamp(0, soundLayer),
      before: ClipHold.fromName(json["before"], kind.before),
      after: ClipHold.fromName(json["after"], kind.after),
      absolute: jsonBool(json["absolute"], false),
      keys: keys,
      launch: ClipLaunch.fromName(json["launch"]),
      quantise: json["quantise"] is String ? json["quantise"] as String : null,
      then: ClipThen.fromName(json["then"]),
      thenClip: jsonString(json["thenClip"], ""),
      triggers: [
        if (json["triggers"] case List raw)
          for (var t in raw)
            if (ClipTrigger.fromJson(t) case var trigger?) trigger,
      ],
      inside: json["inside"] is Map
          ? Map<String, dynamic>.from(json["inside"] as Map)
          : const {},
      sound: jsonString(json["sound"], ""),
    );
  }
}

/// PinKind is what a placed clip's start or end follows: the scene's start
/// or end, a marker, or the end of another placed clip.
enum PinKind { sceneStart, sceneEnd, marker, after }

/// ClipPin is a pin: its kind, and the marker or placement it names.
class ClipPin {
  final PinKind kind;
  final String target;
  const ClipPin(this.kind, {this.target = ""});

  Map<String, dynamic> toJson() =>
      {"to": kind.name, if (target.isNotEmpty) "of": target};

  static ClipPin? fromJson(Object? json) {
    if (json is! Map) return null;
    var kind = PinKind.values.where((k) => k.name == json["to"]).firstOrNull;
    if (kind == null) return null;
    return ClipPin(kind, target: jsonString(json["of"], ""));
  }

  @override
  bool operator ==(Object other) =>
      other is ClipPin && other.kind == kind && other.target == target;

  @override
  int get hashCode => Object.hash(kind, target);
}

/// ClipPlacement is a clip placed on the timeline: layer, start, length and
/// the stretch of the clip it plays (a clip cut in two is two placements).
/// A one-shot fills its place by being retimed; a loop by repeating.
class ClipPlacement {
  final String id;
  final String clip;
  final int layer;

  /// start is seconds from the scene's start, unless [startPin] says.
  final double start;

  /// length is how long it lasts in seconds, unless [endPin] says; null is
  /// the clip's own span from [from] to [to].
  final double? length;

  /// from and to are the stretch of the clip it plays, in seconds; [to] null
  /// is the clip's end.
  final double from;
  final double? to;

  final ClipPin? startPin;
  final ClipPin? endPin;

  /// link is the sound on the timeline it moves with, by its element's id
  /// (Ken, 2026-11-10: linked clips), or "" for none.
  final String link;

  const ClipPlacement({
    this.link = "",
    required this.id,
    required this.clip,
    this.layer = 0,
    this.start = 0,
    this.length,
    this.from = 0,
    this.to,
    this.startPin,
    this.endPin,
  });

  ClipPlacement copyWith({
    String? id,
    int? layer,
    double? start,
    double? Function()? length,
    double? from,
    double? Function()? to,
    ClipPin? Function()? startPin,
    ClipPin? Function()? endPin,
    String? link,
  }) =>
      ClipPlacement(
        link: link ?? this.link,
        id: id ?? this.id,
        clip: clip,
        layer: layer ?? this.layer,
        start: math0(start ?? this.start),
        length: length != null ? length() : this.length,
        from: from ?? this.from,
        to: to != null ? to() : this.to,
        startPin: startPin != null ? startPin() : this.startPin,
        endPin: endPin != null ? endPin() : this.endPin,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "clip": clip,
        if (layer != 0) "layer": layer,
        if (start != 0) "start": start,
        if (length != null) "length": length,
        if (from != 0) "from": from,
        if (to != null) "to": to,
        if (startPin != null) "startPin": startPin!.toJson(),
        if (endPin != null) "endPin": endPin!.toJson(),
        if (link.isNotEmpty) "link": link,
      };

  static ClipPlacement? fromJson(Object? json) {
    if (json is! Map || json["id"] is! String || json["clip"] is! String) {
      return null;
    }
    return ClipPlacement(
      id: json["id"] as String,
      clip: json["clip"] as String,
      layer: jsonInt(json["layer"], 0).clamp(0, soundLayer),
      start: math0(jsonDouble(json["start"], 0)),
      length: json["length"] is num
          ? (json["length"] as num).toDouble().clamp(0.02, 3600.0)
          : null,
      from: jsonDouble(json["from"], 0).clamp(0.0, 3600.0),
      to: json["to"] is num ? (json["to"] as num).toDouble() : null,
      startPin: ClipPin.fromJson(json["startPin"]),
      endPin: ClipPin.fromJson(json["endPin"]),
      link: json["link"] is String ? json["link"] as String : "",
    );
  }
}

/// markerKey is how a pin names a marker: its id, or `m<frame>` for one made
/// without an id.
String markerKey(TimelineAction a) => a.id.isNotEmpty ? a.id : "m${a.frame}";

/// math0 keeps a time from going before the scene's start.
double math0(double v) => v < 0 ? 0 : v;

/// InsideChannel is a renderer channel only some elements have: their own
/// arrival and way out, a counter's count, a line's bow, text sliding along
/// its line.
enum InsideChannel {
  reveal("reveal"),
  close("close"),
  count("count"),
  bow("bow"),
  slide("slide");

  /// channel is the KeyframeChannel the renderer reads it from.
  final String channel;
  const InsideChannel(this.channel);
}

/// insideAt is [c]'s [MotionClip.inside] settings at [t] seconds in, as a
/// value for each renderer channel they set. An own arrival or way out runs
/// nought to one across the clip; a count, bow or slide from its set start
/// to its set end.
Map<String, double> insideAt(MotionClip c, double t) {
  var inside = c.inside;
  if (inside.isEmpty) return const {};
  var p = c.length <= 0 ? 1.0 : (t / c.length).clamp(0.0, 1.0);
  // A converted keyframe stretch keeps its easing.
  if (inside["ease"] case String ease) {
    p = KeyframeEasing.fromName(ease).apply(p);
  }
  var out = <String, double>{};
  if (inside["own"] == true) {
    if (c.kind == MotionKind.arrive) out[InsideChannel.reveal.channel] = p;
    if (c.kind == MotionKind.leave) out[InsideChannel.close.channel] = p;
  }
  for (var ch in InsideChannel.values) {
    if (inside[ch.name] case [num from, num to]) {
      out[ch.channel] = from + (to - from) * p;
    }
  }
  return out;
}

/// maxClipSlots caps the slots read back (one per cue row).
const int maxClipSlots = 256;

/// ElementMotion is all of an element's motion (ElementBase.motion): its
/// clips, its slots, its placements and its layer weights. Immutable.
class ElementMotion {
  final List<MotionClip> clips;

  /// slots are the clip ids in the element's slots, one per cue row; "" is
  /// empty. A clip need not be in a slot.
  final List<String> slots;
  final List<ClipPlacement> placed;

  /// weights are each layer's weight, 0 to 1, as the strip's cross-fader
  /// and pins leave them (see crossFade) -- before [amount] and [off]: read
  /// [weight] for what plays.
  final List<double> weights;

  /// pins are the layers pinned on the strip's cross-fader, bit i layer i:
  /// each played in full, the fader blending the others (Ken, 2026-11-08).
  final int pins;

  /// links are the slot rows whose motion launches with the element's own
  /// sound in the same row, either pressed (Ken, 2026-11-10; the approved
  /// design's linked slots), in order.
  final List<int> links;

  /// fade is where the cross-fader stands, 0 to 1, along the layers in use
  /// that are not pinned.
  final double fade;

  /// amount is how much of its motion is seen, 0 to 1: every layer's
  /// weight scaled by it.
  final double amount;

  /// off is its motion switched off (the ◆ on its row and strip): drawn as
  /// if it had none -- its layers, its pose devices but its copies, and its
  /// looks. Its sound is its own.
  final bool off;

  /// output is the sound channel the element's own sound goes into, by
  /// name, or "" for its own lane.
  final String output;

  /// devices are its motion chain beyond its clips, as arranged: pose
  /// devices that run left of its drawing and looks right of it -- see
  /// motion_devices.dart. Read [poseDevices] and [looks] for the order they
  /// run in.
  final List<MotionDevice> devices;

  /// instances are the element reused, or null for an element placed once:
  /// see instances.dart. Where they split in its chain is its Instances
  /// device, first of its moves unless moved.
  final InstanceSet? instances;

  /// kept is whether it keeps its channel -- its row on the timeline, its
  /// slots and strip -- with no clips left: its last clip taken out is not
  /// it taken out (Ken, 2026-11-08). See channelled.
  final bool kept;

  /// drawSize is how big its Drawing draws it, a share of its size: the
  /// Drawing device's Size. A copy can have its own (key "drawSize").
  final double drawSize;

  const ElementMotion({
    this.clips = const [],
    this.slots = const [],
    this.placed = const [],
    this.weights = const [1, 1, 1],
    this.pins = 0,
    this.links = const [],
    this.fade = 0,
    this.amount = 1,
    this.off = false,
    this.output = "",
    this.devices = const [],
    this.instances,
    this.kept = false,
    this.drawSize = 1,
  });

  static const ElementMotion none = ElementMotion();

  bool get isEmpty => clips.isEmpty && placed.isEmpty;

  /// channelled is whether the element has a channel of its own: clips, or
  /// a chain, or one kept when its last clip went.
  bool get channelled => !isEmpty || kept || devices.isNotEmpty;

  /// poseDevices are its pose devices switched on, in the order they run:
  /// made once for each motion (it never changes), as a pose is asked for
  /// many times a frame and its poses are kept by this list (see
  /// motion_document.dart's _pulled).
  List<MotionDevice> get poseDevices =>
      _poseDevices[this] ??= List.unmodifiable(_makePoseDevices());

  static final Expando<List<MotionDevice>> _poseDevices =
      Expando("poseDevices");

  List<MotionDevice> _makePoseDevices() {
    var poses = [
      if (!off)
        for (var d in devices)
          if (d.on && d.side == MotionDeviceSide.pose) d,
    ];
    // Its Instances only with instances, and always first (Ken, 2026-11-08):
    // every copy has the whole chain, each with what it has of its own.
    if (instances == null) return poses;
    return [const MotionDevice(MotionDeviceKind.instances), ...poses];
  }

  /// looks are its look devices switched on, in the order they run.
  List<MotionDevice> get looks => [
        if (!off)
          for (var d in devices)
            if (d.on && d.side == MotionDeviceSide.look) d,
      ];

  /// moves is whether anything of its motion can move it: a clip, or a pose
  /// device.
  bool get moves =>
      !isEmpty ||
      instances != null ||
      drawSize != 1 ||
      devices.any((d) => d.on && d.side == MotionDeviceSide.pose);

  /// isBlank is whether there is nothing of it to keep.
  bool get isBlank =>
      isEmpty && devices.isEmpty && instances == null && drawSize == 1;

  MotionClip? clip(String id) => clips.where((c) => c.id == id).firstOrNull;

  ClipPlacement? placement(String id) =>
      placed.where((p) => p.id == id).firstOrNull;

  /// slot is the clip in slot [i], or null.
  MotionClip? slot(int i) =>
      i >= 0 && i < slots.length && slots[i].isNotEmpty ? clip(slots[i]) : null;

  /// weight is how much [layer] plays: its fader's weight, by [amount],
  /// and none while [off].
  double weight(int layer) => off ? 0 : layerWeight(layer) * amount;

  /// layerWeight is [layer]'s weight as the cross-fader and pins leave it.
  double layerWeight(int layer) =>
      layer >= 0 && layer < weights.length ? weights[layer] : 1;

  /// isPinned is whether [layer] is pinned on the cross-fader.
  bool isPinned(int layer) => pins & (1 << layer) != 0;

  /// layersInUse are the motion layers something is on, a clip or a
  /// placement, lowest first: what the cross-fader spans.
  List<int> get layersInUse => [
        for (var l = 0; l < motionLayers; l++)
          if (placed.any((p) => p.layer == l) || clips.any((c) => c.layer == l))
            l,
      ];

  /// freeLayers are those of [layersInUse] not pinned: the cross-fader's.
  List<int> get freeLayers => [
        for (var l in layersInUse)
          if (!isPinned(l)) l
      ];

  /// faded is this with the cross-fader at [to], its weights following.
  ElementMotion faded(double to) {
    var f = to.clamp(0.0, 1.0).toDouble();
    return copyWith(fade: f, weights: crossFade(layersInUse, pins, f));
  }

  /// pinnedAs is this with [layer] pinned or not, its weights following.
  /// Every layer in use pinned leaves nothing to fade: refused, as the
  /// prototype does.
  ElementMotion pinnedAs(int layer, bool pinned) {
    var next = pinned ? pins | (1 << layer) : pins & ~(1 << layer);
    var used = layersInUse;
    if (used.isNotEmpty && used.every((l) => next & (1 << l) != 0)) {
      return this;
    }
    return copyWith(pins: next, weights: crossFade(used, next, fade));
  }

  /// hasSound is whether any clip is a sound, giving it a sound lane and
  /// fader.
  bool get hasSound => clips.any((c) => c.isSound);

  ElementMotion copyWith({
    List<MotionClip>? clips,
    List<String>? slots,
    List<ClipPlacement>? placed,
    List<double>? weights,
    int? pins,
    List<int>? links,
    double? fade,
    double? amount,
    bool? off,
    String? output,
    List<MotionDevice>? devices,
    InstanceSet? instances,
    bool clearInstances = false,
    bool? kept,
    double? drawSize,
  }) =>
      ElementMotion(
        clips: clips ?? this.clips,
        slots: slots ?? this.slots,
        placed: placed ?? this.placed,
        weights: weights ?? this.weights,
        pins: pins ?? this.pins,
        links: links ?? this.links,
        fade: fade ?? this.fade,
        amount: amount ?? this.amount,
        off: off ?? this.off,
        output: output ?? this.output,
        devices: devices == null ? this.devices : withMotionDeviceIds(devices),
        instances: clearInstances ? null : instances ?? this.instances,
        kept: kept ?? this.kept,
        drawSize: drawSize ?? this.drawSize,
      );

  /// renamedFor is this for a copy, element [id]: fresh placement ids, with
  /// its own pins following. Two elements sharing a placement id would play
  /// each other's timing.
  ElementMotion renamedFor(String id) {
    if (placed.isEmpty) return this;
    var names = {
      for (var (i, p) in placed.indexed) p.id: "$id-p$i",
    };
    ClipPin? moved(ClipPin? pin) => pin != null &&
            pin.kind == PinKind.after &&
            names.containsKey(pin.target)
        ? ClipPin(PinKind.after, target: names[pin.target]!)
        : pin;
    return copyWith(placed: [
      for (var p in placed)
        p.copyWith(
            id: names[p.id],
            startPin: () => moved(p.startPin),
            endPin: () => moved(p.endPin)),
    ]);
  }

  /// shiftedBy is this with every placement not pinned at its start moved
  /// [seconds] later: what moving a word cue does to what is tied to it.
  ElementMotion shiftedBy(double seconds) => placed.isEmpty
      ? this
      : copyWith(placed: [
          for (var p in placed)
            p.startPin == null ? p.copyWith(start: p.start + seconds) : p,
        ]);

  /// withClip is this with [c] added, or replacing the clip with its id.
  ElementMotion withClip(MotionClip c) => copyWith(
      clips: clips.any((x) => x.id == c.id)
          ? [for (var x in clips) x.id == c.id ? c : x]
          : [...clips, c]);

  /// inSlot is this with [clip] in slot [i] -- "" to empty it.
  ElementMotion inSlot(int i, String clip) {
    var next = [...slots];
    while (next.length <= i) {
      next.add("");
    }
    next[i] = clip;
    while (next.isNotEmpty && next.last.isEmpty) {
      next.removeLast();
    }
    return copyWith(slots: next);
  }

  /// isLinked is whether slot row [row]'s motion launches with its sound.
  bool isLinked(int row) => links.contains(row);

  /// linkedAs is this with slot row [row] linked to its sound, or not.
  ElementMotion linkedAs(int row, bool linked) {
    if (isLinked(row) == linked) return this;
    var next = {...links};
    linked ? next.add(row) : next.remove(row);
    return copyWith(links: next.toList()..sort());
  }

  /// withCueAt is this with an empty slot inserted at cue row [at]: the
  /// links at and past it go down a row with their slots.
  ElementMotion withCueAt(int at) => slots.length <= at
      ? this
      : copyWith(
          slots: [...slots]..insert(at, ""),
          links: [for (var r in links) r >= at ? r + 1 : r]);

  /// withoutCue is this with cue row [row] removed. Its clip goes too unless
  /// it is in another slot or on the timeline.
  ElementMotion withoutCue(int row) {
    if (slots.length <= row) return this;
    var gone = slots[row];
    var next = copyWith(slots: [...slots]..removeAt(row), links: [
      for (var r in links)
        if (r != row) r > row ? r - 1 : r
    ]);
    if (gone.isEmpty ||
        next.slots.contains(gone) ||
        placed.any((p) => p.clip == gone)) {
      return next;
    }
    return next.copyWith(clips: [
      for (var c in clips)
        if (c.id != gone) c
    ]);
  }

  /// withPlacement is this with [p] added, or replacing the one with its
  /// id.
  ElementMotion withPlacement(ClipPlacement p) => copyWith(placed: [
        for (var x in placed)
          if (x.id != p.id) x,
        p,
      ]);

  Map<String, dynamic> toJson() => {
        if (clips.isNotEmpty) "clips": [for (var c in clips) c.toJson()],
        if (slots.isNotEmpty) "slots": slots,
        if (placed.isNotEmpty) "placed": [for (var p in placed) p.toJson()],
        if (weights.any((w) => w != 1)) "weights": weights,
        if (pins != 0) "pins": pins,
        if (links.isNotEmpty) "links": links,
        if (fade != 0) "fade": fade,
        if (amount != 1) "amount": amount,
        if (off) "off": true,
        if (output.isNotEmpty) "output": output,
        if (devices.isNotEmpty) "devices": [for (var d in devices) d.toJson()],
        if (instances != null) "instances": instances!.toJson(),
        if (kept) "kept": true,
        if (drawSize != 1) "drawSize": drawSize,
      };

  static ElementMotion fromJson(Object? json) {
    if (json is! Map) return none;
    var clips = [
      if (json["clips"] case List raw)
        for (var c in raw)
          if (MotionClip.fromJson(c) case var clip?) clip,
    ];
    var ids = {for (var c in clips) c.id};
    return ElementMotion(
      clips: clips,
      slots: [
        if (json["slots"] case List raw)
          for (var s in raw.take(maxClipSlots))
            s is String && ids.contains(s) ? s : "",
      ],
      placed: [
        if (json["placed"] case List raw)
          for (var p in raw)
            if (ClipPlacement.fromJson(p) case var placed?
                when ids.contains(placed.clip))
              placed,
      ],
      weights: [
        for (var i = 0; i < motionLayers; i++)
          if (json["weights"] case List w when i < w.length)
            jsonDouble(w[i], 1).clamp(0.0, 1.0)
          else
            1.0,
      ],
      pins: json["pins"] is int
          ? (json["pins"] as int) & ((1 << motionLayers) - 1)
          : 0,
      links: json["links"] is List
          ? ({
              for (var r in json["links"] as List)
                if (r is int && r >= 0) r
            }.toList()
            ..sort())
          : const [],
      fade: jsonDouble(json["fade"], 0).clamp(0.0, 1.0),
      amount: jsonDouble(json["amount"], 1).clamp(0.0, 1.0),
      off: json["off"] == true,
      output: jsonString(json["output"], ""),
      devices: withMotionDeviceIds([
        if (json["devices"] case List raw)
          for (var d in raw)
            // An Instances kept as a device, from before its copies were
            // the chain's first card: dropped, as it stands for nothing.
            if (MotionDevice.fromJson(d) case var device?
                when device.kind != MotionDeviceKind.instances)
              device,
      ]),
      instances: InstanceSet.fromJson(json["instances"]),
      kept: json["kept"] == true,
      drawSize: jsonDouble(json["drawSize"], 1).clamp(0.05, 8.0),
    );
  }
}

/// crossFade is each layer's weight for the strip's cross-fader at [fade]
/// over [used] layers, [pins] pinned (the prototype's weights(), Ken
/// 2026-11-08): a pinned layer plays in full; the free ones are spread along
/// the fader, it blending between the two it stands between; one free layer
/// plays in full. A layer not in use keeps 1, there being nothing on it.
List<double> crossFade(List<int> used, int pins, double fade) {
  var w = List<double>.filled(motionLayers, 1);
  var free = [
    for (var l in used)
      if (pins & (1 << l) == 0) l
  ];
  if (free.length < 2) return w;
  for (var l in free) {
    w[l] = 0;
  }
  var x = fade.clamp(0.0, 1.0) * (free.length - 1);
  var i = math.min(x.floor(), free.length - 2);
  var f = x - i;
  w[free[i]] = 1 - f;
  w[free[i + 1]] = f;
  return w;
}

/// MotionTimes resolves where placed clips are, following their pins. One
/// per scene, for every element at once, since a pin can name another
/// element's placement.
class MotionTimes {
  /// sceneEnd is the scene's length, in seconds.
  final double sceneEnd;

  /// markers are each marker's time, in seconds, by id.
  final Map<String, double> markers;

  /// placements are every placement in the scene, by id, with its clip.
  final Map<String, (ClipPlacement, MotionClip)> placements;

  final Map<String, ClipSpan> _spans = {};

  MotionTimes({
    required this.sceneEnd,
    required this.markers,
    required this.placements,
  });

  /// span is where [id] plays, its pins followed. A circular pin chain
  /// stops where it returns to itself.
  ClipSpan? span(String id) => _span(id, {});

  ClipSpan? _span(String id, Set<String> seen) {
    if (_spans[id] case var known?) return known;
    var entry = placements[id];
    if (entry == null) return null;
    var (p, c) = entry;
    if (!seen.add(id)) {
      return ClipSpan(
          p.start, p.start + (p.length ?? c.span), p.from, p.to ?? c.length, 1);
    }
    double? at(ClipPin? pin) => switch (pin?.kind) {
          null => null,
          PinKind.sceneStart => 0,
          PinKind.sceneEnd => sceneEnd,
          PinKind.marker => markers[pin!.target],
          // A very long pin chain is cut off before the stack runs out.
          PinKind.after =>
            seen.length > 64 ? null : _span(pin!.target, seen)?.end,
        };
    var from = p.from.clamp(0.0, c.length);
    var to = (p.to ?? c.length).clamp(from, c.length);
    var start = at(p.startPin) ?? p.start;
    var own = p.length ?? (c.loop ? c.span : (to - from) / c.speed);
    var end = start + own;
    if (at(p.endPin) case var e? when e > start + 0.02) end = e;
    var span = ClipSpan(start, end, from, to,
        c.loop ? c.speed : (to - from) / (end - start).clamp(0.02, 1e9));
    _spans[id] = span;
    return span;
  }
}

/// ClipSpan is where a placed clip plays: from [start] to [end] on the
/// timeline, playing the clip from [from] to [to] at [speed].
class ClipSpan {
  final double start, end, from, to, speed;
  const ClipSpan(this.start, this.end, this.from, this.to, this.speed);

  double get length => end - start;

  /// clipTime is where in [c] it is at [t] on the timeline, wrapping for a
  /// loop.
  double clipTime(MotionClip c, double t) {
    var u = (t - start) * speed;
    if (c.loop) {
      var l = c.length <= 0 ? 1.0 : c.length;
      return (from + u) % l;
    }
    return (from + u).clamp(from, to);
  }
}

/// revealsIn is whether [c] plays its element's arrival, across which
/// piece-by-piece arrivals (words, layers, shapes) are timed.
bool revealsIn(MotionClip c) =>
    (c.inside["own"] == true && c.kind == MotionKind.arrive) ||
    c.inside["reveal"] is List;

/// revealFrom and revealTo are pose value keys for where the arrival clip
/// starts and ends (seconds from a clip, frames on a keyframe pose), which
/// its pieces are timed against.
const String revealFrom = "@revealFrom", revealTo = "@revealTo";

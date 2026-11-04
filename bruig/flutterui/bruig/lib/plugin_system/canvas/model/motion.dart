import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// motion.dart is how an element moves: its clips. A clip is a small piece of
// animation that belongs to one element -- an arrival, a loop, a way out, an
// action -- made of keys, played from a slot, a cue or a trigger, or placed
// on the timeline.
//
// It replaces three things that grew up separately: keyframes on a track,
// the ready-made arrive/leave/loop presets, and the keyframe settings on the
// timeline bar. A preset now only writes a clip's keys; after that the clip
// is its keys. See render/motion_pose.dart for what an element looks like
// at a moment, and the prototype these rules were settled in
// (https://claude.ai/artifact/63vgUVykmP1Ezx82gvUJhd).
//
// Times inside a clip are seconds from its start. Places on the timeline are
// seconds from the scene's start: the frame rate is a property of the
// picture, and a clip retimed to a new frame rate should not change speed.

/// MotionProp is one thing a clip's keys move. Each is relative to the
/// element as it is set -- moved by, sized by, turned by -- so one clip works
/// on any element, wherever it has been put.
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

/// MotionPlaceKind is a place a key can name instead of a number: worked out
/// as the clip plays, so it holds when the page changes shape or the things
/// it names have moved.
enum MotionPlaceKind {
  /// offLeft and its fellows are just past an edge of the page, the element
  /// wholly out of sight.
  offLeft("Off the left edge"),
  offRight("Off the right edge"),
  offTop("Above the page"),
  offBottom("Below the page"),

  /// beside is next to another element, on the side it is on; ground is
  /// standing on the same ground as it -- their bottoms level.
  beside("Beside"),
  ground("On the ground of"),

  /// on is where another element is drawn now, moving: what a camera that
  /// follows somebody looks at.
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
            target: json["of"] is String ? json["of"] as String : "");
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
  const MotionPlace(this.kind, {this.target = ""});

  @override
  Object toJson() => {"place": kind.name, if (target.isNotEmpty) "of": target};

  @override
  bool operator ==(Object other) =>
      other is MotionPlace && other.kind == kind && other.target == target;

  @override
  int get hashCode => Object.hash(kind, target);
}

/// MotionKey is one key: where a property is at [t] seconds into the clip,
/// and how it gets there from the key before.
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
        ease: KeyframeEasing.fromName(json["ease"] as String?),
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
/// offered for it, and what it does before it starts and after it ends --
/// an arrival waits at its first frame, a way out stays gone.
enum MotionKind {
  arrive("Arriving", ClipHold.first, ClipHold.rest),
  loop("Looping", ClipHold.rest, ClipHold.rest),
  leave("Leaving", ClipHold.rest, ClipHold.last),
  action("Action", ClipHold.rest, ClipHold.rest),

  /// model is a 3D model's own animation, read from its file: its keys are
  /// in the model; the clip says which, and when.
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

/// ClipHold is what a clip does outside the time it plays: nothing -- the
/// element as it is -- or hold its first or last frame.
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
/// LaunchMode: start it; play it while held; start or stop it; repeat it
/// while held.
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

/// ClipTriggerKind is what else starts a clip, beside its slot: in a
/// published interactive canvas, in a game, and in the editor's Try it.
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

/// ClipTrigger is one: its kind, and what it names -- an element clicked, a
/// key, a clip, a marker, a count -- with a number for a count.
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

/// motionLayers is how many layers an element's motion has: clips on
/// different layers play together, their moves added. A layer is how an
/// element floats while it slides in, or waves while it walks.
const int motionLayers = 3;

/// soundLayer is the lane an element's own sound plays on: after its motion
/// layers, in its group on the timeline.
const int soundLayer = motionLayers;

/// MotionClip is one clip. Immutable.
class MotionClip {
  final String id;
  final String name;
  final MotionKind kind;

  /// preset is the ready-made motion the keys were written by, until a key
  /// is changed by hand -- then [edited].
  final String preset;
  final bool edited;

  /// length is the clip's own length, in seconds, and speed how fast it is
  /// played from a slot: on the timeline its place sets its pace.
  final double length;
  final double speed;
  final bool loop;

  /// layer is which of the element's layers it plays on: 0 to
  /// [motionLayers] - 1, or [soundLayer] for a sound.
  final int layer;

  final ClipHold before;
  final ClipHold after;

  /// absolute writes its across and down keys as places on the page rather
  /// than as moves from where the element is.
  final bool absolute;

  final Map<MotionProp, List<MotionKey>> keys;

  final ClipLaunch launch;

  /// quantise is what a launch waits for: null the timeline's own setting,
  /// else "off", "beat" or "bar".
  final String? quantise;
  final ClipThen then;

  /// thenClip is the clip [then] plays, by id, when it is [ClipThen.play].
  final String thenClip;
  final List<ClipTrigger> triggers;

  /// inside is what only this kind of element does in a clip -- a text's
  /// words one after another, a character's face, a model's animation by
  /// name -- kept as its own settings rather than as keys.
  final Map<String, dynamic> inside;

  /// sound is the sound a sound clip plays: an asset id.
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

  /// span is how long it plays from a slot, at its own speed.
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

  /// retimed is this clip [length] seconds long, its keys spread or
  /// squeezed with it.
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

/// ClipPin is one: its kind, and the marker or placed clip it names.
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

/// ClipPlacement is a clip placed on the timeline: on which layer, from when,
/// for how long, and which stretch of the clip -- a clip cut in two is two
/// placements of it, each playing its own part.
///
/// A one-shot fills its place by being retimed; a loop, by repeating.
class ClipPlacement {
  final String id;
  final String clip;
  final int layer;

  /// start is seconds from the scene's start, unless [startPin] says.
  final double start;

  /// length is how long it lasts, in seconds; null is the clip's own span
  /// (from [from] to [to] at its speed) -- unless [endPin] says.
  final double? length;

  /// from and to are the stretch of the clip it plays, seconds into it;
  /// [to] null is the clip's end.
  final double from;
  final double? to;

  final ClipPin? startPin;
  final ClipPin? endPin;

  const ClipPlacement({
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
  }) =>
      ClipPlacement(
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
    );
  }
}

/// markerKey is how a marker is named for a pin: its own id, or -- one made
/// without one -- the one it is read back with.
String markerKey(TimelineAction a) => a.id.isNotEmpty ? a.id : "m${a.frame}";

/// math0 keeps a time from going before the scene's start.
double math0(double v) => v < 0 ? 0 : v;

/// clipSlots is how many slots an element's strip has at the least: it has
/// one per cue row, as many as the mixer has.
const int clipSlots = 4;

/// maxClipSlots is the most read back: a cue row each.
const int maxClipSlots = 256;

/// ElementMotion is all of an element's motion: its clips, which are in its
/// slots, where they are placed on the timeline, and how much each layer
/// counts. On ElementBase.motion. Immutable.
class ElementMotion {
  final List<MotionClip> clips;

  /// slots are the clips in the element's slots, by id, one per cue row;
  /// "" an empty slot. A clip need not be in a slot: one made on the
  /// timeline has none until it is dragged into one.
  final List<String> slots;
  final List<ClipPlacement> placed;

  /// weights are how much each layer counts, 0 to 1: the layer faders on
  /// the element's strip.
  final List<double> weights;

  /// output is the sound channel an element's own sound goes into, by its
  /// name, or "" its own lane in its group.
  final String output;

  const ElementMotion({
    this.clips = const [],
    this.slots = const [],
    this.placed = const [],
    this.weights = const [1, 1, 1],
    this.output = "",
  });

  static const ElementMotion none = ElementMotion();

  bool get isEmpty => clips.isEmpty && placed.isEmpty;

  MotionClip? clip(String id) => clips.where((c) => c.id == id).firstOrNull;

  ClipPlacement? placement(String id) =>
      placed.where((p) => p.id == id).firstOrNull;

  /// slot is the clip in slot [i], or null.
  MotionClip? slot(int i) =>
      i >= 0 && i < slots.length && slots[i].isNotEmpty ? clip(slots[i]) : null;

  double weight(int layer) =>
      layer >= 0 && layer < weights.length ? weights[layer] : 1;

  /// hasSound is whether any of its clips is a sound: its group has a
  /// sound lane, and its strip a sound fader.
  bool get hasSound => clips.any((c) => c.isSound);

  ElementMotion copyWith({
    List<MotionClip>? clips,
    List<String>? slots,
    List<ClipPlacement>? placed,
    List<double>? weights,
    String? output,
  }) =>
      ElementMotion(
        clips: clips ?? this.clips,
        slots: slots ?? this.slots,
        placed: placed ?? this.placed,
        weights: weights ?? this.weights,
        output: output ?? this.output,
      );

  /// withClip is this with [c] added, or put in place of the clip it
  /// replaces.
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

  /// withCueAt is this with an empty slot put in at cue row [at], those
  /// under it moved down a row with their cues.
  ElementMotion withCueAt(int at) =>
      slots.length <= at ? this : copyWith(slots: [...slots]..insert(at, ""));

  /// withoutCue is this with cue row [row] taken away, the slots under it
  /// moved up. The clip in it goes too, unless it is on the timeline.
  ElementMotion withoutCue(int row) {
    if (slots.length <= row) return this;
    var gone = slots[row];
    var next = copyWith(slots: [...slots]..removeAt(row));
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

  /// withPlacement is this with [p] added, or put in place of the one with
  /// its id.
  ElementMotion withPlacement(ClipPlacement p) => copyWith(placed: [
        for (var x in placed)
          if (x.id != p.id) x,
        p,
      ]);

  /// withoutPlacement takes [id] off the timeline. Whatever was pinned to
  /// its end keeps the time it had: see [MotionTimes.unpinned].
  ElementMotion withoutPlacement(String id) => copyWith(placed: [
        for (var x in placed)
          if (x.id != id) x
      ]);

  Map<String, dynamic> toJson() => {
        if (clips.isNotEmpty) "clips": [for (var c in clips) c.toJson()],
        if (slots.isNotEmpty) "slots": slots,
        if (placed.isNotEmpty) "placed": [for (var p in placed) p.toJson()],
        if (weights.any((w) => w != 1)) "weights": weights,
        if (output.isNotEmpty) "output": output,
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
      output: jsonString(json["output"], ""),
    );
  }
}

/// MotionTimes resolves where placed clips are: their pins followed, through
/// other placements, markers and the scene's ends. One per scene, for every
/// element's placements at once, since a pin can name another element's.
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

  /// span is where [id] plays, its pins followed. A pin that goes round in
  /// a circle stops where it comes back to itself.
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
          PinKind.after => _span(pin!.target, seen)?.end,
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

  /// clipTime is where in [c] it is at [t] on the timeline: within the
  /// stretch it plays, going round for a loop.
  double clipTime(MotionClip c, double t) {
    var u = (t - start) * speed;
    if (c.loop) {
      var l = c.length <= 0 ? 1.0 : c.length;
      return (from + u) % l;
    }
    return (from + u).clamp(from, to);
  }
}

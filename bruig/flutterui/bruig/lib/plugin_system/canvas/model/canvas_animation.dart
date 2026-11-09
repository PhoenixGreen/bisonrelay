import 'dart:math' as math;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_animation.dart is keyframe tracks and the timeline's markers.
//
// Tracks are the legacy animation model: clips (motion.dart) replace them,
// and motion_convert.dart turns tracks into clips when a canvas opens. Tracks
// remain for what a clip cannot say -- backgrounds, stages, scenery, teams --
// and Keyframe is still the pose type the clip system produces.
//
// A track is a sparse list of poses, each holding every animated property at
// once, interpolated between, so any frame can be asked for without playing
// the ones before it.

/// KeyframeEasing is the shape of the interpolation between two keyframes.
/// (Not `Easing`, which Material also defines.)
enum KeyframeEasing {
  linear("Linear"),
  easeIn("Ease in"),
  easeOut("Ease out"),
  easeInOut("Ease in-out"),

  /// overshoot, bounce and spring go past the value they are travelling to
  /// and come back, leaving 0..1 on the way. The same three as ChartEase.
  overshoot("Overshoot"),
  bounce("Bounce"),
  spring("Spring"),

  /// hold does not interpolate at all: the pose snaps at the next keyframe.
  hold("Hold");

  final String label;
  const KeyframeEasing(this.label);

  static KeyframeEasing fromName(String? name) => values
      .firstWhere((e) => e.name == name, orElse: () => KeyframeEasing.linear);

  /// apply maps a 0..1 position between two keyframes onto an eased one.
  double apply(double t) {
    switch (this) {
      case KeyframeEasing.linear:
        return t;
      case KeyframeEasing.easeIn:
        return t * t;
      case KeyframeEasing.easeOut:
        return 1 - (1 - t) * (1 - t);
      case KeyframeEasing.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
      case KeyframeEasing.overshoot:
        // The standard back-out. Pinned at the ends, where the arithmetic
        // leaves a hair of rounding and a keyframe has to be reached exactly.
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        const c = 1.70158;
        var u = t - 1;
        return 1 + (c + 1) * u * u * u + c * u * u;
      case KeyframeEasing.bounce:
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        return bounceOut(t);
      case KeyframeEasing.spring:
        // A decaying oscillation: three visible swings before it settles.
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        var decay = math.pow(2, -9 * t).toDouble();
        return 1 - decay * math.cos(t * math.pi * 6);
      case KeyframeEasing.hold:
        return 0;
    }
  }
}

/// Keyframe is one pose: where an element is at one frame.
///
/// The offsets are relative to the element's own resting position, so an
/// animation survives the element being moved afterwards.
class Keyframe {
  final int frame;

  /// dx and dy shift the element from its resting position, in design units.
  final double dx;
  final double dy;

  /// scale multiplies the element's size about its anchor.
  final double scale;

  /// rotate adds to the element's own rotation, in degrees.
  final double rotate;

  /// opacity multiplies the element's own opacity.
  final double opacity;

  /// easing is how to get *from* this keyframe to the next one.
  final KeyframeEasing easing;

  /// values are the extra properties this keyframe pins, by name: the ones
  /// only some elements have (how far a caption has slid, how far a line is
  /// bowed). Absolute values, not offsets, as they have no resting state.
  /// Keys are the constants in [KeyframeChannel].
  final Map<String, double> values;

  const Keyframe({
    required this.frame,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotate = 0,
    this.opacity = 1,
    this.easing = KeyframeEasing.linear,
    this.values = const {},
  });

  /// posesElement is whether this keyframe moves, resizes, turns or fades
  /// the element. One that carries only [values] (how much of a chart is
  /// drawn, say) does not.
  bool get posesElement =>
      dx != 0 || dy != 0 || scale != 1 || rotate != 0 || opacity != 1;

  /// movesElement is whether this keyframe moves, resizes or turns the
  /// element; unlike [posesElement], not a fade. See
  /// ElementTrack.posesAnything.
  bool get movesElement => dx != 0 || dy != 0 || scale != 1 || rotate != 0;

  /// rest is the pose that changes nothing, which is what a track with no
  /// keyframes evaluates to and what a new keyframe starts from.
  static const Keyframe rest = Keyframe(frame: 0);

  Keyframe copyWith({
    int? frame,
    double? dx,
    double? dy,
    double? scale,
    double? rotate,
    double? opacity,
    KeyframeEasing? easing,
    Map<String, double>? values,
  }) =>
      Keyframe(
        frame: frame ?? this.frame,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        scale: scale ?? this.scale,
        rotate: rotate ?? this.rotate,
        opacity: opacity ?? this.opacity,
        easing: easing ?? this.easing,
        values: values ?? this.values,
      );

  /// differsFrom is whether this keyframe's pose or any channel both pin
  /// differs from [other]'s: whether the stretch between them gets a bar on
  /// the timeline.
  bool differsFrom(Keyframe other) {
    if (dx != other.dx ||
        dy != other.dy ||
        scale != other.scale ||
        rotate != other.rotate ||
        opacity != other.opacity) {
      return true;
    }
    // Only the channels both pin: a missing one holds the value set before
    // it (see ElementTrack._withHeldValues), so it is not a change.
    for (var channel in values.keys) {
      if (!other.values.containsKey(channel)) continue;
      if (values[channel] != other.values[channel]) return true;
    }
    return false;
  }

  /// withValue is this keyframe with one extra property pinned.
  Keyframe withValue(String key, double value) =>
      copyWith(values: {...values, key: value});

  Keyframe withoutValue(String key) =>
      copyWith(values: {...values}..remove(key));

  /// lerp is this pose blended towards [other] by [t], already eased.
  Keyframe lerp(Keyframe other, double t) => Keyframe(
        frame: frame,
        dx: dx + (other.dx - dx) * t,
        dy: dy + (other.dy - dy) * t,
        scale: scale + (other.scale - scale) * t,
        rotate: rotate + (other.rotate - rotate) * t,
        opacity: opacity + (other.opacity - opacity) * t,
        easing: easing,
        // A property only one end pins is held, not interpolated towards a
        // guessed value.
        values: {
          for (var key in {...values.keys, ...other.values.keys})
            key: values.containsKey(key) && other.values.containsKey(key)
                ? values[key]! + (other.values[key]! - values[key]!) * t
                : (values[key] ?? other.values[key]!),
        },
      );

  bool get isRest =>
      values.isEmpty &&
      dx == 0 &&
      dy == 0 &&
      scale == 1 &&
      rotate == 0 &&
      opacity == 1;

  Map<String, dynamic> toJson() => {
        "f": frame,
        if (dx != 0) "dx": dx,
        if (dy != 0) "dy": dy,
        if (scale != 1) "s": scale,
        if (rotate != 0) "r": rotate,
        if (opacity != 1) "o": opacity,
        if (easing != KeyframeEasing.linear) "e": easing.name,
        if (values.isNotEmpty) "v": values,
      };

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
        frame: (jsonNum(json["f"]))?.toInt() ?? 0,
        dx: (jsonNum(json["dx"]))?.toDouble() ?? 0,
        dy: (jsonNum(json["dy"]))?.toDouble() ?? 0,
        scale: (jsonNum(json["s"]))?.toDouble() ?? 1,
        rotate: (jsonNum(json["r"]))?.toDouble() ?? 0,
        opacity: (jsonNum(json["o"]))?.toDouble() ?? 1,
        easing: KeyframeEasing.fromName(jsonStr(json["e"])),
        values: {
          if (json["v"] case Map<String, dynamic> raw)
            for (var entry in raw.entries)
              if (entry.value is num)
                entry.key: (entry.value as num).toDouble(),
        },
      );
}

/// ElementTrack is one element's keyframes, sorted by frame on construction
/// (it is read every frame, written rarely).
class ElementTrack {
  final List<Keyframe> keys;

  ElementTrack(List<Keyframe> keys)
      : keys = List.unmodifiable(
            [...keys]..sort((a, b) => a.frame.compareTo(b.frame)));

  static final ElementTrack empty = ElementTrack(const []);

  bool get isEmpty => keys.isEmpty;

  /// posesAnything is whether a drag of the element records a pose rather
  /// than moving it.
  ///
  /// True if any keyframe moves, sizes or turns the element; not for fades or
  /// channels, which play wherever the element is put (counted, every drag
  /// after a "Dim the others" fade wrote a keyframe). Also true of a track of
  /// nothing but resting keyframes, the usual way to start a movement: pin
  /// the start, then pose at a later frame.
  bool get posesAnything =>
      keys.any((k) => k.movesElement) ||
      (keys.isNotEmpty &&
          keys.every((k) => k.values.isEmpty && !k.posesElement));

  /// at returns the pose for [frame]. Before the first keyframe the first
  /// pose holds, and after the last the last does; nothing extrapolates.
  Keyframe at(int frame) => _withHeldValues(frame, _poseAt(frame));

  /// between is the pose part way through a frame, [frame] fractional: the
  /// same curve [at] reads whole frames of, for drawing it smoothly (the
  /// Curves).
  Keyframe between(double frame) =>
      _withHeldValues(frame.floor(), _poseAt(frame));

  /// _withHeldValues fills in any extra channel this frame's pose does not
  /// name itself, from the last keyframe that did, so channels hold past
  /// their last key as the pose does.
  Keyframe _withHeldValues(int frame, Keyframe pose) {
    if (keys.isEmpty) return pose;
    var held = <String, double>{};
    for (var k in keys) {
      if (k.frame > frame) break;
      held.addAll(k.values);
    }
    if (held.isEmpty) held.addAll(keys.first.values);
    if (held.isEmpty) return pose;
    // The pose's own values win: those are the interpolated ones.
    return pose.copyWith(values: {...held, ...pose.values});
  }

  Keyframe _poseAt(num frame) {
    if (keys.isEmpty) return Keyframe.rest;
    if (frame <= keys.first.frame) return keys.first;
    if (frame >= keys.last.frame) return keys.last;

    for (var i = 0; i < keys.length - 1; i++) {
      var a = keys[i], b = keys[i + 1];
      if (frame < a.frame || frame > b.frame) continue;
      var span = b.frame - a.frame;
      if (span <= 0) return b;
      return a.lerp(b, a.easing.apply((frame - a.frame) / span));
    }
    return keys.last;
  }

  /// keyAt is the keyframe standing exactly on [frame], if there is one.
  Keyframe? keyAt(int frame) {
    for (var k in keys) {
      if (k.frame == frame) return k;
    }
    return null;
  }

  /// seededFor is this track with a resting pose at frame 0, when it is empty
  /// and [frame] is not the start. Without it, a drag recorded at frame 12
  /// onto an empty track would be one key, held for the whole document.
  ElementTrack seededFor(int frame) =>
      keys.isEmpty && frame > 0 ? withKey(const Keyframe(frame: 0)) : this;

  /// restingAt is a new keyframe for [frame] that changes nothing: the pose
  /// the track already gives there, with no channels of its own, and the
  /// easing of the stretch it splits.
  ///
  /// A keyframe laid for another reason (the ends of an arrival or an exit)
  /// starts from this, not from rest: a pose is not held between keys as a
  /// channel is, so a rest key would drag a moved element back.
  Keyframe restingAt(int frame) {
    var pose = _poseAt(frame);
    var easing = KeyframeEasing.linear;
    for (var k in keys) {
      if (k.frame > frame) break;
      easing = k.easing;
    }
    return Keyframe(
        frame: frame,
        dx: pose.dx,
        dy: pose.dy,
        scale: pose.scale,
        rotate: pose.rotate,
        opacity: pose.opacity,
        easing: easing);
  }

  /// withKey adds or replaces the keyframe at its own frame.
  ElementTrack withKey(Keyframe key) =>
      ElementTrack([...keys.where((k) => k.frame != key.frame), key]);

  ElementTrack withoutFrame(int frame) =>
      ElementTrack(keys.where((k) => k.frame != frame).toList());

  /// lastFrame is where this track stops changing.
  int get lastFrame => keys.isEmpty ? 0 : keys.last.frame;

  Map<String, dynamic> toJson() =>
      {"keys": keys.map((k) => k.toJson()).toList()};

  factory ElementTrack.fromJson(Map<String, dynamic> json) {
    var raw = json["keys"];
    if (raw is! List) return ElementTrack.empty;
    return ElementTrack([
      for (var k in raw)
        if (k is Map<String, dynamic>) Keyframe.fromJson(k),
    ]);
  }
}

/// TimelineActionKind is what happens when playback reaches a marked frame.
enum TimelineActionKind {
  stop("Stop", "Playback holds on this frame until something starts it again"),
  loop("Loop back", "Jump back to the target frame and carry on"),
  jump("Jump to", "Jump forward or back to the target frame once"),
  pause("Pause", "Hold for a moment, then carry on"),
  // A place, not an instruction: playback carries on past it, as a player
  // that does not know the kind does anyway.
  locator("Locator", "A named place on the ruler to jump to");

  final String label;
  final String description;
  const TimelineActionKind(this.label, this.description);

  static TimelineActionKind fromName(String? name) => values.firstWhere(
        (k) => k.name == name,
        orElse: () => TimelineActionKind.stop,
      );
}

/// TimelineAction is a marker on the timeline. A published interactive
/// canvas obeys them; an exported file plays straight through.
class TimelineAction {
  /// id names the marker for what is pinned to it -- a clip that starts or
  /// ends there follows it when it is moved.
  final String id;

  final int frame;
  final TimelineActionKind kind;

  /// target is the frame [kind] jumps to, and is ignored by stop and pause.
  final int target;

  /// repeats bounds a loop, so a "loop back" marker does not necessarily run
  /// forever. Zero means no limit.
  final int repeats;

  /// holdFrames is how long [TimelineActionKind.pause] waits.
  final int holdFrames;

  /// label is a word or two beside the flag, a note for the editor, and
  /// showLabel whether it is drawn there.
  final String label;
  final bool showLabel;

  /// waitsFor is what a stop waits for to go on, beside Play: one of the
  /// game controls' actions, by id -- "press A to start" -- or "" nothing
  /// more. See CanvasDocument.controlsNow.
  final String waitsFor;

  const TimelineAction({
    this.id = "",
    required this.frame,
    required this.kind,
    this.target = 0,
    this.repeats = 0,
    this.holdFrames = 12,
    this.label = "",
    this.showLabel = true,
    this.waitsFor = "",
  });

  TimelineAction copyWith({
    String? id,
    int? frame,
    TimelineActionKind? kind,
    int? target,
    int? repeats,
    int? holdFrames,
    String? label,
    bool? showLabel,
    String? waitsFor,
  }) =>
      TimelineAction(
        id: id ?? this.id,
        frame: frame ?? this.frame,
        kind: kind ?? this.kind,
        target: target ?? this.target,
        repeats: repeats ?? this.repeats,
        holdFrames: holdFrames ?? this.holdFrames,
        label: label ?? this.label,
        showLabel: showLabel ?? this.showLabel,
        waitsFor: waitsFor ?? this.waitsFor,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) "id": id,
        "f": frame,
        "kind": kind.name,
        if (target != 0) "target": target,
        if (repeats != 0) "repeats": repeats,
        if (holdFrames != 12) "hold": holdFrames,
        if (label.isNotEmpty) "label": label,
        if (!showLabel) "hideLabel": true,
        if (waitsFor.isNotEmpty) "waitsFor": waitsFor,
      };

  factory TimelineAction.fromJson(Map<String, dynamic> json) => TimelineAction(
        id: json["id"] is String ? json["id"] as String : "",
        frame: (jsonNum(json["f"]))?.toInt() ?? 0,
        kind: TimelineActionKind.fromName(jsonStr(json["kind"])),
        target: (jsonNum(json["target"]))?.toInt() ?? 0,
        repeats: (jsonNum(json["repeats"]))?.toInt() ?? 0,
        holdFrames: (jsonNum(json["hold"]))?.toInt() ?? 12,
        label: json["label"] is String ? json["label"] as String : "",
        showLabel: json["hideLabel"] != true,
        waitsFor: json["waitsFor"] is String ? json["waitsFor"] as String : "",
      );
}

/// KeyframeBand is two keyframes that belong together: the start and the end
/// of one movement, drawn joined on the timeline and dragged as one.
class KeyframeBand {
  final int from;
  final int to;

  const KeyframeBand(this.from, this.to);

  int get length => to - from;
  bool get real => to > from;
}

/// bandsIn is every bar the timeline draws over [track]: one for each
/// stretch in which something changes. None for one whose ends read the
/// same, or one that leaves a held key (it steps at the far end rather than
/// travelling).
List<KeyframeBand> bandsIn(ElementTrack? track) {
  if (track == null) return const [];
  var out = <KeyframeBand>[];
  var keys = [...track.keys]..sort((a, b) => a.frame - b.frame);
  for (var i = 0; i + 1 < keys.length; i++) {
    var from = keys[i], to = keys[i + 1];
    if (from.easing == KeyframeEasing.hold) continue;
    if (!from.differsFrom(to)) continue;
    out.add(KeyframeBand(from.frame, to.frame));
  }
  return out;
}

/// KeyframeChannel names the extra properties a keyframe can pin, as
/// constants so the writer and the reader cannot disagree on a spelling.
class KeyframeChannel {
  KeyframeChannel._();

  /// slide is how far along its line a caption has travelled, as the fraction
  /// TextOnCurve.offset holds.
  static const String slide = "slide";

  /// reveal is how much of a chart has been drawn, 0 to 1: one channel for
  /// the whole chart, each bar's share worked out by ChartAnimation.
  static const String reveal = "reveal";

  /// close is how far through leaving a chart is, 0 to 1. Separate from
  /// [reveal] because the arrival and the exit can be different animations.
  static const String close = "close";

  /// bow is how far a line element is curved, as LineElement.curvature holds.
  static const String bow = "bow";

  /// pose is not a channel anybody pins: it labels a bar over an ordinary
  /// stretch where the element itself moves, grows, turns or fades.
  static const String pose = "pose";

  /// count is the number a counter is showing: the value itself, not a
  /// fraction, so a count can pass its end and come back.
  static const String count = "count";

  /// squash is how far an element is stretched along [squashAngle]
  /// (radians, across the page) and squeezed across it, its area kept: a
  /// ball squashing as it goes. One is as it is. See the Squash device.
  static const String squash = "squash";
  static const String squashAngle = "squashAngle";

  /// loopTurn, loopSx and loopSy are how a moving loop (see ElementLoop)
  /// turns and sizes the element about [loopPivotX], [loopPivotY] -- the
  /// loop's own pivot, a share of its box: a swing hangs from its top. Its
  /// moving and fading are the pose's own (see poseWithMotion).
  static const String loopTurn = "loopTurn";
  static const String loopSx = "loopSx";
  static const String loopSy = "loopSy";
  static const String loopPivotX = "loopPivotX";
  static const String loopPivotY = "loopPivotY";
}

/// bounceOut is the classic four-stage bounce -- the one curve a keyframe's
/// easing and a chart's both bounce on.
double bounceOut(double t) {
  const n = 7.5625, d = 2.75;
  if (t < 1 / d) return n * t * t;
  if (t < 2 / d) {
    var u = t - 1.5 / d;
    return n * u * u + 0.75;
  }
  if (t < 2.5 / d) {
    var u = t - 2.25 / d;
    return n * u * u + 0.9375;
  }
  var u = t - 2.625 / d;
  return n * u * u + 0.984375;
}

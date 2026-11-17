import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_animation.dart is keyframe tracks and the timeline's markers.
// Tracks are the legacy model: motion_convert.dart turns them into clips
// (motion.dart) when a canvas opens. They remain for what a clip cannot say
// (backgrounds, stages, scenery, teams), and Keyframe is the pose type clips
// produce. A track is sparse poses, each holding every animated property,
// interpolated between, so any frame can be asked for without the others.

/// KeyframeEasing is how two keyframes are eased between (Material owns
/// `Easing`).
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
  hold("Hold"),

  /// custom is the shape the Curves' handles drew: an [EaseCurve] kept with
  /// the key. Asked of the easing alone it is an ease-in-out.
  custom("Custom");

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
      case KeyframeEasing.custom:
        return EaseCurve.inOut.apply(t);
    }
  }

  /// asCurve is this easing as handles, for the Curves to start from: the
  /// curve it is, or near it; an ease-in-out for bounce, spring and hold.
  EaseCurve get asCurve => switch (this) {
        KeyframeEasing.linear => EaseCurve.linear,
        // t² and its mirror are exactly these cubics.
        KeyframeEasing.easeIn => const EaseCurve(1 / 3, 0, 2 / 3, 1 / 3),
        KeyframeEasing.easeOut => const EaseCurve(1 / 3, 2 / 3, 2 / 3, 1),
        KeyframeEasing.overshoot => const EaseCurve(0.175, 0.885, 0.32, 1.275),
        _ => EaseCurve.inOut,
      };
}

/// EaseCurve is an ease drawn with two handles, as CSS's cubic-bezier: from
/// (0, 0) to (1, 1) through (x1, y1) and (x2, y2), time across, progress up.
/// The xs stay in 0..1 so time only goes forward; the ys may leave it, to
/// overshoot. One per keyframe, shaped in the Curves.
class EaseCurve {
  final double x1, y1, x2, y2;
  const EaseCurve(this.x1, this.y1, this.x2, this.y2);

  static const linear = EaseCurve(1 / 3, 1 / 3, 2 / 3, 2 / 3);
  static const inOut = EaseCurve(0.42, 0, 0.58, 1);

  EaseCurve copyWith({double? x1, double? y1, double? x2, double? y2}) =>
      EaseCurve((x1 ?? this.x1).clamp(0.0, 1.0).toDouble(), y1 ?? this.y1,
          (x2 ?? this.x2).clamp(0.0, 1.0).toDouble(), y2 ?? this.y2);

  static double _b(double a, double b, double t) {
    var u = 1 - t;
    return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
  }

  static double _db(double a, double b, double t) {
    var u = 1 - t;
    return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b);
  }

  /// apply is its height at [t] across; pinned at the ends so keys are hit.
  double apply(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // The curve's own parameter where it is t across: Newton's method,
    // then halving where that wanders.
    var s = t;
    for (var i = 0; i < 8; i++) {
      var x = _b(x1, x2, s) - t;
      if (x.abs() < 1e-7) return _b(y1, y2, s);
      var d = _db(x1, x2, s);
      if (d.abs() < 1e-6) break;
      s -= x / d;
    }
    var lo = 0.0, hi = 1.0;
    s = t;
    for (var i = 0; i < 40; i++) {
      var x = _b(x1, x2, s);
      if ((x - t).abs() < 1e-7) break;
      if (x < t) {
        lo = s;
      } else {
        hi = s;
      }
      s = (lo + hi) / 2;
    }
    return _b(y1, y2, s);
  }

  List<double> toJson() => [x1, y1, x2, y2];

  static EaseCurve? fromJson(Object? json) {
    if (json case [num a, num b, num c, num d]) {
      return EaseCurve(a.toDouble().clamp(0.0, 1.0).toDouble(), b.toDouble(),
          c.toDouble().clamp(0.0, 1.0).toDouble(), d.toDouble());
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is EaseCurve &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

/// Keyframe is one pose: where an element is at one frame. The offsets are
/// relative to the element's resting position, so an animation survives the
/// element being moved afterwards.
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

  /// curve is the shape of that, where [easing] is custom: see EaseCurve.
  final EaseCurve? curve;

  /// values are the extra properties this keyframe pins, by name (keys in
  /// [KeyframeChannel]): ones only some elements have, such as a caption's
  /// slide or a line's bow. Absolute, not offsets: they have no resting state.
  final Map<String, double> values;

  const Keyframe({
    required this.frame,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotate = 0,
    this.opacity = 1,
    this.easing = KeyframeEasing.linear,
    this.curve,
    this.values = const {},
  });

  /// ease is [t] eased to the next key: by [curve] where set, else [easing].
  double ease(double t) => easing == KeyframeEasing.custom && curve != null
      ? curve!.apply(t)
      : easing.apply(t);

  /// posesElement is whether this keyframe moves, resizes, turns or fades
  /// the element; one carrying only [values] (a chart's reveal) does not.
  bool get posesElement =>
      dx != 0 || dy != 0 || scale != 1 || rotate != 0 || opacity != 1;

  /// movesElement is [posesElement] without a fade; see posesAnything.
  bool get movesElement => dx != 0 || dy != 0 || scale != 1 || rotate != 0;

  /// rest changes nothing: an empty track's pose, and a new key's start.
  static const Keyframe rest = Keyframe(frame: 0);

  Keyframe copyWith({
    int? frame,
    double? dx,
    double? dy,
    double? scale,
    double? rotate,
    double? opacity,
    KeyframeEasing? easing,
    EaseCurve? curve,
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
        curve: curve ?? this.curve,
        values: values ?? this.values,
      );

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
        curve: curve,
        // A property only one end pins is held, not interpolated.
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
        if (easing == KeyframeEasing.custom && curve != null)
          "c": curve!.toJson(),
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
        curve: EaseCurve.fromJson(json["c"]),
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
  /// than moving it: true if any keyframe moves, sizes or turns it, or of a
  /// track of nothing but resting keyframes (the usual start: pin the start,
  /// then pose later). Not for fades or channels, which play wherever the
  /// element is put, or every drag after a fade would write a keyframe.
  bool get posesAnything =>
      keys.any((k) => k.movesElement) ||
      (keys.isNotEmpty &&
          keys.every((k) => k.values.isEmpty && !k.posesElement));

  /// at is the pose at [frame]; the ends hold, nothing extrapolates.
  Keyframe at(int frame) => _withHeldValues(frame, _poseAt(frame));

  /// between is the pose at fractional [frame], on the same curve [at] reads
  /// whole frames of, for drawing it smoothly (the Curves).
  Keyframe between(double frame) =>
      _withHeldValues(frame.floor(), _poseAt(frame));

  /// _withHeldValues fills in each extra channel this frame's pose lacks from
  /// the last keyframe that set it, so channels hold past their last key.
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
      return a.lerp(b, a.ease((frame - a.frame) / span));
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
  /// the track gives there, no channels, the easing of the stretch it splits.
  /// A keyframe laid for another reason (an arrival's or exit's ends) starts
  /// from this, not rest: poses are not held between keys as channels are,
  /// so a rest key would drag a moved element back.
  Keyframe restingAt(int frame) {
    var pose = _poseAt(frame);
    var easing = KeyframeEasing.linear;
    EaseCurve? curve;
    for (var k in keys) {
      if (k.frame > frame) break;
      easing = k.easing;
      curve = k.curve;
    }
    return Keyframe(
        frame: frame,
        dx: pose.dx,
        dy: pose.dy,
        scale: pose.scale,
        rotate: pose.rotate,
        opacity: pose.opacity,
        easing: easing,
        curve: curve);
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
  /// id names the marker; clips starting or ending there follow it.
  final String id;

  final int frame;
  final TimelineActionKind kind;

  /// target is the frame [kind] jumps to, and is ignored by stop and pause.
  final int target;

  /// repeats bounds a "loop back" marker's loop; zero means no limit.
  final int repeats;

  /// holdFrames is how long [TimelineActionKind.pause] waits.
  final int holdFrames;

  /// label is a word or two beside the flag, a note for the editor, and
  /// showLabel whether it is drawn there.
  final String label;
  final bool showLabel;

  /// waitsFor is a game control action (by id) a stop also waits for, as
  /// "press A to start", or "". See CanvasDocument.controlsNow.
  final String waitsFor;

  /// noteAt is its label's centre on the canvas while playback holds there,
  /// as shares of the canvas, and noteSize how big, one standard (see
  /// ui/timeline/marker_note.dart).
  final Offset noteAt;
  final double noteSize;

  /// defaultNoteAt is the foot of the canvas, in the middle.
  static const Offset defaultNoteAt = Offset(0.5, 0.92);

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
    this.noteAt = defaultNoteAt,
    this.noteSize = 1,
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
    Offset? noteAt,
    double? noteSize,
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
        noteAt: noteAt ?? this.noteAt,
        noteSize: noteSize ?? this.noteSize,
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
        if (noteAt != defaultNoteAt) "noteAt": [noteAt.dx, noteAt.dy],
        if (noteSize != 1) "noteSize": noteSize,
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
        noteAt: switch (json["noteAt"]) {
          [num x, num y] =>
            Offset(x.toDouble().clamp(0.0, 1.0), y.toDouble().clamp(0.0, 1.0)),
          _ => defaultNoteAt,
        },
        noteSize: (jsonNum(json["noteSize"])?.toDouble() ?? 1).clamp(0.3, 6.0),
      );
}

/// KeyframeChannel names the extra properties a keyframe can pin, as
/// constants so the writer and the reader cannot disagree on a spelling.
class KeyframeChannel {
  KeyframeChannel._();

  /// slide is a caption's travel along its line, as TextOnCurve.offset.
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

  /// squash stretches an element along [squashAngle] (radians) and squeezes
  /// it across, area kept, as a ball squashes; one is none. See Squash.
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

/// bounceOut is the four-stage bounce shared by keyframe and chart easing.
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

import 'dart:math' as math;

// canvas_animation.dart is how an element changes over the length of a
// document, and what the timeline does when playback reaches a frame.
//
// The model is keyframes, not a script. A track is a sparse list of "at frame
// N this element is *here*, this big, this transparent", and everything
// between two of them is interpolated. That is the only model that lets the
// same document be scrubbed backwards, exported frame by frame, and replayed
// inside a published interactive canvas -- all three need to ask "what does
// frame 37 look like" without having played frames 0 to 36 first.
//
// Deliberately absent: a per-property track. One keyframe holds every animated
// property at once, so a keyframe is a *pose*. Per-property tracks are more
// expressive and are what a real animation tool has; they are also four
// timelines to read instead of one, and this is a tool for moving a footballer
// across a pitch.

/// KeyframeEasing is the shape of the interpolation between two keyframes.
///
/// Named for what it eases rather than plainly `Easing`, which Material also
/// defines -- any file importing both would otherwise have to prefix one of
/// them at every single use.
enum KeyframeEasing {
  linear("Linear"),
  easeIn("Ease in"),
  easeOut("Ease out"),
  easeInOut("Ease in-out"),

  /// hold does not interpolate at all: the pose snaps at the next keyframe.
  /// What a cut is, and what "show this, then that" needs.
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
      case KeyframeEasing.hold:
        return 0;
    }
  }
}

/// Keyframe is one pose: where an element is at one frame.
///
/// The offsets are *relative to the element's own resting position*, not
/// absolute coordinates. That is what makes an animation survive the element
/// being dragged somewhere else afterwards -- a fade that was written for a
/// title still fades the title after the title has been moved, rather than
/// dragging it back to where it was when the keyframe was made.
class Keyframe {
  final int frame;

  /// dx and dy shift the element from its resting position, in design units.
  final double dx;
  final double dy;

  /// scale multiplies the element's size about its centre.
  final double scale;

  /// rotate adds to the element's own rotation, in degrees.
  final double rotate;

  /// opacity multiplies the element's own opacity.
  final double opacity;

  /// easing is how to get *from* this keyframe to the next one.
  final KeyframeEasing easing;

  /// values are the extra properties this keyframe pins, by name.
  ///
  /// The five fields above are the pose every element has -- where it is, how
  /// big, how turned, how faded. This is for the ones only some elements have:
  /// how far along a line a caption has slid, how far a line is bowed. They
  /// are absolute values rather than offsets, because unlike a position they
  /// have no meaningful "resting" state to be an offset from.
  ///
  /// A map rather than a field per property, so a new animatable setting is a
  /// name and two call sites instead of a change to the file format. Keys are
  /// the constants in [KeyframeChannel].
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

  /// posesElement is whether this keyframe says anything about *where* the
  /// element is -- moved, resized, turned or faded.
  ///
  /// A keyframe that says none of those is still a real keyframe: a chart's
  /// animation preset lays two that carry nothing but how much of the chart
  /// has been drawn, and a caption sliding along a line is the same. The
  /// difference matters because "this element has been animated" is the
  /// question a drag asks before deciding whether it is posing or moving --
  /// see CanvasController.posesRatherThanMoves -- and a chart that has only
  /// been told how to arrive has not been animated *in space* at all.
  bool get posesElement =>
      dx != 0 || dy != 0 || scale != 1 || rotate != 0 || opacity != 1;

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

  /// lerp is this pose blended towards [other] by [t], already eased.
  /// withValue is this keyframe with one extra property pinned.
  Keyframe withValue(String key, double value) =>
      copyWith(values: {...values, key: value});

  Keyframe withoutValue(String key) =>
      copyWith(values: {...values}..remove(key));

  Keyframe lerp(Keyframe other, double t) => Keyframe(
        frame: frame,
        dx: dx + (other.dx - dx) * t,
        dy: dy + (other.dy - dy) * t,
        scale: scale + (other.scale - scale) * t,
        rotate: rotate + (other.rotate - rotate) * t,
        opacity: opacity + (other.opacity - opacity) * t,
        easing: easing,
        // A property only one end pins is held rather than interpolated
        // towards nothing: there is no second value to move to, and guessing
        // one -- zero, say -- would send a slide back to the start of its line
        // the moment it stopped being keyed.
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
        frame: (json["f"] as num?)?.toInt() ?? 0,
        dx: (json["dx"] as num?)?.toDouble() ?? 0,
        dy: (json["dy"] as num?)?.toDouble() ?? 0,
        scale: (json["s"] as num?)?.toDouble() ?? 1,
        rotate: (json["r"] as num?)?.toDouble() ?? 0,
        opacity: (json["o"] as num?)?.toDouble() ?? 1,
        easing: KeyframeEasing.fromName(json["e"] as String?),
        values: {
          if (json["v"] case Map<String, dynamic> raw)
            for (var entry in raw.entries)
              if (entry.value is num)
                entry.key: (entry.value as num).toDouble(),
        },
      );
}

/// ElementTrack is one element's keyframes, kept sorted by frame.
///
/// Sorted on construction rather than on read, because it is read once per
/// element per frame -- sixty times a second during playback, and once per
/// exported frame -- and sorted whenever the user adds a keyframe, which is
/// as often as they press a button.
class ElementTrack {
  final List<Keyframe> keys;

  ElementTrack(List<Keyframe> keys)
      : keys = List.unmodifiable(
            [...keys]..sort((a, b) => a.frame.compareTo(b.frame)));

  static final ElementTrack empty = ElementTrack(const []);

  bool get isEmpty => keys.isEmpty;

  /// posesAnything is whether this track is about where the element is, as
  /// opposed to being nothing but channels.
  ///
  /// True if any keyframe either poses the element or pins nothing at all. The
  /// second half matters: a keyframe deliberately laid to hold something where
  /// it is has a rest pose and no channels, and it is the clearest possible
  /// statement that this element's position is being animated -- pinning the
  /// start and then moving at a later frame is the ordinary way to make an
  /// animation by hand.
  ///
  /// So what this excludes is only a track whose every keyframe exists to
  /// carry a channel: a chart told how to arrive, a caption told how far along
  /// its line to sit. Those say nothing about position, and treating them as
  /// though they did turned every later drag into a keyframe nobody asked for.
  bool get posesAnything => keys.any((k) => k.posesElement || k.values.isEmpty);

  /// at returns the pose for [frame].
  ///
  /// Before the first keyframe the first pose holds; after the last, the last
  /// does. Holding rather than extrapolating is the only behaviour that does
  /// not surprise: an element that fades in over frames 0-10 should stay
  /// visible for the rest of the document, not carry on getting brighter.
  Keyframe at(int frame) => _withHeldValues(frame, _poseAt(frame));

  /// _withHeldValues fills in any extra channel this frame's pose does not
  /// name itself, from the last keyframe that did.
  ///
  /// A channel is pinned only on the keyframes that mention it, so a caption
  /// keyed to slide at frames 0 and 10 has nothing to say at frame 20 -- and
  /// without this it would snap back to the element's own resting slide the
  /// instant playback passed the last key that mentioned it. Held is what
  /// every other property here does; this makes the extra ones agree.
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

  Keyframe _poseAt(int frame) {
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

  /// keyAt is the keyframe standing exactly on [frame], if there is one. What
  /// the timeline asks to decide whether adding a keyframe here replaces one.
  Keyframe? keyAt(int frame) {
    for (var k in keys) {
      if (k.frame == frame) return k;
    }
    return null;
  }

  /// seededFor is this track with a resting pose at frame 0, when it is empty
  /// and [frame] is not the start.
  ///
  /// A track with one keyframe on it holds that pose at every frame -- before
  /// the first key the first key applies, which is the right rule and the
  /// wrong outcome here. Recording a drag at frame 12 onto an empty track
  /// would put the element in its new place for the whole document, and read
  /// as the drag having simply moved it. Seeding the start turns the same
  /// gesture into what it looked like: from where it was, to where it was put.
  ///
  /// Only when the track is empty. A second key is the author placing poses
  /// deliberately, and inserting one they did not ask for would be the tool
  /// overwriting their first frame.
  ElementTrack seededFor(int frame) =>
      keys.isEmpty && frame > 0 ? withKey(const Keyframe(frame: 0)) : this;

  /// withKey adds or replaces the keyframe at its own frame.
  ElementTrack withKey(Keyframe key) =>
      ElementTrack([...keys.where((k) => k.frame != key.frame), key]);

  ElementTrack withoutFrame(int frame) =>
      ElementTrack(keys.where((k) => k.frame != frame).toList());

  /// lastFrame is where this track stops changing. The document uses the
  /// largest across its elements to warn that its length is too short to show
  /// everything that was drawn.
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
  pause("Pause", "Hold for a moment, then carry on");

  final String label;
  final String description;
  const TimelineActionKind(this.label, this.description);

  static TimelineActionKind fromName(String? name) => values.firstWhere(
        (k) => k.name == name,
        orElse: () => TimelineActionKind.stop,
      );
}

/// TimelineAction is a marker on the timeline.
///
/// These are what turn a linear animation into something a reader can be
/// walked through: a play that stops after the first movement, a button that
/// runs the next phase, a loop that keeps a background alive underneath. A
/// published interactive canvas obeys them; an exported GIF flattens them,
/// because a GIF has no way to wait for a click.
class TimelineAction {
  final int frame;
  final TimelineActionKind kind;

  /// target is the frame [kind] jumps to, and is ignored by stop and pause.
  final int target;

  /// repeats bounds a loop, so a "loop back" marker does not necessarily run
  /// forever. Zero means no limit.
  final int repeats;

  /// holdFrames is how long [TimelineActionKind.pause] waits.
  final int holdFrames;

  const TimelineAction({
    required this.frame,
    required this.kind,
    this.target = 0,
    this.repeats = 0,
    this.holdFrames = 12,
  });

  TimelineAction copyWith({
    int? frame,
    TimelineActionKind? kind,
    int? target,
    int? repeats,
    int? holdFrames,
  }) =>
      TimelineAction(
        frame: frame ?? this.frame,
        kind: kind ?? this.kind,
        target: target ?? this.target,
        repeats: repeats ?? this.repeats,
        holdFrames: holdFrames ?? this.holdFrames,
      );

  Map<String, dynamic> toJson() => {
        "f": frame,
        "kind": kind.name,
        if (target != 0) "target": target,
        if (repeats != 0) "repeats": repeats,
        if (holdFrames != 12) "hold": holdFrames,
      };

  factory TimelineAction.fromJson(Map<String, dynamic> json) => TimelineAction(
        frame: (json["f"] as num?)?.toInt() ?? 0,
        kind: TimelineActionKind.fromName(json["kind"] as String?),
        target: (json["target"] as num?)?.toInt() ?? 0,
        repeats: (json["repeats"] as num?)?.toInt() ?? 0,
        holdFrames: (json["hold"] as num?)?.toInt() ?? 12,
      );
}

/// KeyframeChannel names the extra properties a keyframe can pin.
///
/// Constants rather than free strings, because the name is written in one
/// place and read in another and a typo between the two is an animation that
/// silently does nothing.
class KeyframeChannel {
  KeyframeChannel._();

  /// slide is how far along its line a caption has travelled, as the fraction
  /// TextOnCurve.offset holds.
  static const String slide = "slide";

  /// reveal is how much of a chart has been drawn, 0 to 1.
  ///
  /// One channel for the whole chart rather than one per bar. What each bar is
  /// doing at a given moment is worked out from this and the chart's own
  /// animation settings -- see ChartAnimation -- because a chart of forty bars
  /// would otherwise be forty channels on one keyframe, and moving the end of
  /// the animation would mean moving forty of them.
  static const String reveal = "reveal";

  /// bow is how far a line element is curved, as LineElement.curvature holds.
  static const String bow = "bow";
}

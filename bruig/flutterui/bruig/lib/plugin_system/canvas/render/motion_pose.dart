import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// motion_pose.dart is what an element's clips make of it at a moment: how
// far it has moved, how big it is, how turned, how faded -- from the clips
// placed on the timeline, or from the clips its slots are playing.
//
// The rules:
//
//  - Layers add. Each layer's pose is worked out alone and added to the
//    others, scaled by the layer's weight: L1 walks while L2 waves.
//  - On a layer, one clip at a time: the latest to have started.
//  - Before its first clip starts, a layer is at rest -- unless that clip
//    holds its first frame (an arrival does), so nothing is seen early.
//  - A clip that holds its last frame (a way out does) holds it only until
//    the next clip on its layer starts. For an element the next clip carries
//    on from where it was left; for a camera, the next move replaces it --
//    a camera's keys say where to look, not how far to move from there.
//  - A key can name a place rather than a number, worked out as it plays:
//    off an edge of the page, beside another element, on its ground, or on
//    it where it is drawn now.

/// MotionScene is what places are worked out against: the page, where each
/// element is set, and where each is drawn at this moment.
class MotionScene {
  final Size page;

  /// boundsOf is an element's box as it is set, by id; null where there is
  /// none.
  final Rect? Function(String id) boundsOf;

  /// drawnAt is the middle of an element as it is drawn now, moving -- for
  /// "on"; null to use where it is set.
  final Offset? Function(String id)? drawnAt;

  const MotionScene({required this.page, required this.boundsOf, this.drawnAt});
}

/// MotionPose is what clips make of an element: moved by [dx], [dy],
/// [scale]d, [turn]ed by degrees and faded by [opacity]. With the clips it
/// was made from, for what only that kind of element does with them -- a
/// text's words one after another.
class MotionPose {
  final double dx, dy, scale, turn, opacity;
  final List<MotionSource> sources;

  /// values are the renderer's channels a clip's Inside it sets -- see
  /// insideAt -- by name: the latest clip's, not added up.
  final Map<String, double> values;

  const MotionPose({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.turn = 0,
    this.opacity = 1,
    this.sources = const [],
    this.values = const {},
  });

  static const MotionPose rest = MotionPose();

  bool get isRest =>
      dx == 0 &&
      dy == 0 &&
      scale == 1 &&
      turn == 0 &&
      opacity == 1 &&
      values.isEmpty;

  /// withValues is this setting [more] of the renderer's channels as well.
  MotionPose withValues(Map<String, double> more) => MotionPose(
      dx: dx,
      dy: dy,
      scale: scale,
      turn: turn,
      opacity: opacity,
      sources: sources,
      values: {...values, ...more});

  MotionPose withSources(List<MotionSource> s) => MotionPose(
      dx: dx,
      dy: dy,
      scale: scale,
      turn: turn,
      opacity: opacity,
      sources: s,
      values: values);

  /// toward is this moved [weight] of the way to [p]: [p] replacing it, its
  /// values over this one's.
  MotionPose toward(MotionPose p, double weight) {
    double mix(double a, double b) => a + (b - a) * weight;
    return MotionPose(
      dx: mix(dx, p.dx),
      dy: mix(dy, p.dy),
      turn: mix(turn, p.turn),
      scale: mix(scale, p.scale),
      opacity: mix(opacity, p.opacity),
      sources: [...sources, ...p.sources],
      values: weight <= 0 ? values : {...values, ...p.values},
    );
  }

  /// plus is this with [p] added on top, counted [weight] of the way.
  MotionPose plus(MotionPose p, [double weight = 1]) => MotionPose(
        dx: dx + p.dx * weight,
        dy: dy + p.dy * weight,
        turn: turn + p.turn * weight,
        scale: scale * (1 + (p.scale - 1) * weight),
        opacity: opacity * (1 + (p.opacity - 1) * weight),
        sources: [...sources, ...p.sources],
        // A layer turned all the way down sets nothing of its own.
        values: weight <= 0 || p.values.isEmpty
            ? values
            : values.isEmpty
                ? p.values
                : {...values, ...p.values},
      );

  /// onto is [pose] (from a legacy keyframe track, or rest) with the clips'
  /// moves added on top.
  Keyframe onto(Keyframe pose) => isRest
      ? pose
      : pose.copyWith(
          dx: pose.dx + dx,
          dy: pose.dy + dy,
          scale: pose.scale * scale,
          rotate: pose.rotate + turn,
          opacity: pose.opacity * opacity,
          values: values.isEmpty ? null : {...pose.values, ...values},
        );

  @override
  String toString() =>
      "MotionPose(dx: $dx, dy: $dy, scale: $scale, turn: $turn, opacity: $opacity)";
}

/// MotionSource is a clip a pose was made from, and where in it.
class MotionSource {
  final MotionClip clip;
  final double time;
  final int layer;
  const MotionSource(this.clip, this.time, this.layer);
}

/// LivePlay is a clip playing from a slot: since [start] seconds on the
/// clock it plays to, or [ended] once a one-shot has played.
class LivePlay {
  final String clip;
  final double start;
  final bool ended;
  const LivePlay(this.clip, this.start, {this.ended = false});

  LivePlay done() => LivePlay(clip, start, ended: true);
}

/// MotionLive is an element playing from its slots rather than the
/// timeline: what each layer is playing, and where each was left.
class MotionLive {
  final List<LivePlay?> plays;
  final List<MotionPose?> carry;

  const MotionLive({
    this.plays = const [null, null, null, null],
    this.carry = const [null, null, null, null],
  });

  LivePlay? play(int layer) => layer < plays.length ? plays[layer] : null;
  MotionPose? left(int layer) => layer < carry.length ? carry[layer] : null;
}

/// motionValue is what [v] -- a number or a place -- comes to for [prop],
/// for an element set at [self]: always a move from where it is set.
double motionValue(MotionClip c, MotionProp prop, MotionValue v, Rect self,
    MotionScene scene) {
  switch (v) {
    case MotionNumber(:var value):
      if (c.absolute && prop == MotionProp.x) return value - self.center.dx;
      if (c.absolute && prop == MotionProp.y) return value - self.center.dy;
      return value;
    case MotionPlace(:var kind, :var target):
      var across = prop == MotionProp.x;
      switch (kind) {
        case MotionPlaceKind.offLeft:
          return across ? -self.right - 14 : 0;
        case MotionPlaceKind.offRight:
          return across ? scene.page.width - self.left + 14 : 0;
        case MotionPlaceKind.offTop:
          return across ? 0 : -self.bottom - 14;
        case MotionPlaceKind.offBottom:
          return across ? 0 : scene.page.height - self.top + 14;
        case MotionPlaceKind.beside:
          var o = scene.boundsOf(target);
          if (o == null) return 0;
          if (!across) return o.center.dy - self.center.dy;
          var side = o.center.dx >= self.center.dx ? -1 : 1;
          return o.center.dx -
              self.center.dx +
              side * (o.width / 2 + self.width / 2 + 4);
        case MotionPlaceKind.ground:
          var o = scene.boundsOf(target);
          if (o == null) return 0;
          return across ? o.center.dx - self.center.dx : o.bottom - self.bottom;
        case MotionPlaceKind.on:
          var at =
              scene.drawnAt?.call(target) ?? scene.boundsOf(target)?.center;
          if (at == null) return 0;
          return across ? at.dx - self.center.dx : at.dy - self.center.dy;
      }
  }
}

/// sampleProp is [prop] at [t] seconds into [c], or null where the clip has
/// no keys for it.
double? sampleProp(
    MotionClip c, MotionProp prop, double t, Rect self, MotionScene scene) {
  var keys = c.keys[prop];
  if (keys == null || keys.isEmpty) return null;
  double at(MotionKey k) => motionValue(c, prop, k.value, self, scene);
  if (t <= keys.first.t) return at(keys.first);
  if (t >= keys.last.t) return at(keys.last);
  for (var i = 0; i < keys.length - 1; i++) {
    var a = keys[i], b = keys[i + 1];
    if (t < a.t || t > b.t) continue;
    var span = b.t - a.t;
    var p = span <= 1e-9 ? 1.0 : (t - a.t) / span;
    var e = b.ease.apply(p);
    var va = at(a), vb = at(b);
    return va + (vb - va) * e;
  }
  return null;
}

/// clipPose is [c] at [t] seconds in, on top of [from].
MotionPose clipPose(MotionClip c, double t, Rect self, MotionScene scene,
    {MotionPose from = MotionPose.rest}) {
  double v(MotionProp p) => sampleProp(c, p, t, self, scene) ?? p.rest;
  return MotionPose(
    dx: from.dx + v(MotionProp.x),
    dy: from.dy + v(MotionProp.y),
    scale: from.scale * v(MotionProp.scale),
    turn: from.turn + v(MotionProp.turn),
    opacity: from.opacity * v(MotionProp.opacity),
    values:
        c.inside.isEmpty ? from.values : {...from.values, ...insideAt(c, t)},
  );
}

/// layerPose is what [layer] of [motion] makes of an element set at [self]
/// at [t] seconds into the scene, from its placed clips. [replaces] is a
/// camera's rule: a held last frame is replaced, not carried on from.
MotionPose layerPose(ElementMotion motion, int layer, double t, Rect self,
    MotionTimes times, MotionScene scene,
    {bool replaces = false}) {
  var mine = [
    for (var p in motion.placed)
      if (p.layer == layer)
        if ((motion.clip(p.clip), times.span(p.id)) case (var c?, var s?))
          (p, c, s),
  ]..sort((a, b) => a.$3.start.compareTo(b.$3.start));
  MotionPose? held;
  (MotionClip, double, ClipSpan)? active;
  for (var (n, (_, c, s)) in mine.indexed) {
    if (t < s.start) {
      if (n == 0 && c.before == ClipHold.first && active == null) {
        active = (c, s.from, s);
      }
      continue;
    }
    if (t >= s.end) {
      if (c.after == ClipHold.last) {
        held = clipPose(c, c.loop ? s.from : s.to, self, scene,
            from: replaces || held == null ? MotionPose.rest : held);
        if (revealsIn(c)) {
          held = held.withValues({revealFrom: s.start, revealTo: s.end});
        }
      }
      continue;
    }
    active = (c, s.clipTime(c, t), s);
  }
  if (active case (var c, var ct, var s)) {
    var base = replaces || held == null ? MotionPose.rest : held;
    var pose = clipPose(c, ct, self, scene, from: base)
        .withSources([MotionSource(c, ct, layer)]);
    // Its pieces timed across the clip that plays its arrival.
    return revealsIn(c)
        ? pose.withValues({revealFrom: s.start, revealTo: s.end})
        : pose;
  }
  return held ?? MotionPose.rest;
}

/// livePose is what [layer] makes of an element playing from its slots, at
/// [clock] seconds.
MotionPose livePose(ElementMotion motion, MotionLive live, int layer,
    double clock, Rect self, MotionScene scene,
    {bool replaces = false}) {
  var left = live.left(layer);
  var play = live.play(layer);
  var c = play == null ? null : motion.clip(play.clip);
  if (play == null || c == null || play.ended || clock < play.start) {
    return left ?? MotionPose.rest;
  }
  var ct = liveTime(c, play, clock);
  var base = replaces || left == null ? MotionPose.rest : left;
  return clipPose(c, ct, self, scene, from: base)
      .withSources([MotionSource(c, ct, layer)]);
}

/// liveTime is where in [c] a slot's play of it is at [clock].
double liveTime(MotionClip c, LivePlay play, double clock) {
  var u = (clock - play.start) * c.speed;
  if (c.loop) {
    var l = c.length <= 0 ? 1.0 : c.length;
    return ((u % l) + l) % l;
  }
  return u.clamp(0.0, c.length);
}

/// motionPose is everything [motion] makes of an element set at [self]: its
/// layers added, each weighed. From [live] -- its slots -- where it has left
/// the timeline, else from the timeline at [t] seconds.
MotionPose motionPose(ElementMotion motion, double t, Rect self,
    MotionTimes times, MotionScene scene,
    {MotionLive? live, double clock = 0, bool replaces = false}) {
  if (motion.isEmpty) return MotionPose.rest;
  var total = MotionPose.rest;
  for (var layer = 0; layer < motionLayers; layer++) {
    var p = live != null
        ? livePose(motion, live, layer, clock, self, scene, replaces: replaces)
        : layerPose(motion, layer, t, self, times, scene, replaces: replaces);
    // A layer playing a clip that replaces takes over from those under it,
    // as far as its weight goes; otherwise it adds.
    if (p.sources.any((s) => s.clip.replace)) {
      total = total.toward(p, motion.weight(layer));
    } else {
      total = total.plus(p, motion.weight(layer));
    }
  }
  return total;
}

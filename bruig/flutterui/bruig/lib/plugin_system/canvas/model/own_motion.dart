import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// own_motion.dart is an element's own arrival and way out: the stretch an
// arrival preset plays across, kept as one clip of kind arrive (or leave)
// marked "own". Presets write it here; whatever needs to know when an
// element arrives reads it here.

/// ownClipOf is [e]'s own clip of [kind] and its placement, if it has one.
(MotionClip, ClipPlacement)? ownClipOf(CanvasElement e, MotionKind kind) {
  var m = e.base.motion;
  for (var p in m.placed) {
    var c = m.clip(p.clip);
    if (c != null && c.kind == kind && c.inside["own"] == true) return (c, p);
  }
  return null;
}

/// ownSpan is the frame [e]'s own [kind] starts on and how many frames it
/// takes, at [rate] frames a second, from its clip. Null without one.
(int, int)? ownSpan(CanvasElement e, MotionKind kind, int rate) {
  if (ownClipOf(e, kind) case (var c, var p)) {
    var r = math.max(1, rate);
    var start = (p.start * r).round();
    var length = ((p.length ?? c.span) * r).round();
    return (start, math.max(1, length));
  }
  return null;
}

/// ownEnd is the frame [e]'s arrival finishes on, or null with none.
int? ownEnd(CanvasElement e, int rate) =>
    switch (ownSpan(e, MotionKind.arrive, rate)) {
      (var from, var length) => from + length,
      null => null,
    };

/// withOwnSpan is [e] with its own [kind] playing from frame [from] to
/// [to]: its clip retimed, or one made. [name] is what the clip is called on the timeline.
CanvasElement withOwnSpan(
    CanvasElement e, MotionKind kind, int from, int to, int rate,
    {String name = ""}) {
  var r = math.max(1, rate);
  var start = math.max(0, from) / r;
  var length = math.max(1, to - from) / r;
  var m = e.base.motion;
  var had = ownClipOf(e, kind);
  var label = name.isNotEmpty
      ? name
      : kind == MotionKind.leave
          ? "Leaves"
          : "Arrives";
  MotionClip clip;
  ClipPlacement placement;
  if (had case (var c, var p)) {
    clip = c.copyWith(name: label, length: length, speed: 1);
    placement =
        p.copyWith(start: start, length: () => null, from: 0, to: () => null);
  } else {
    var layer = freeLayer(m, start, start + length);
    var id = freeId(m, "${e.id}-${kind.name}");
    clip = MotionClip.ofKind(id, kind, name: label, layer: layer).copyWith(
      length: length,
      before: kind == MotionKind.arrive ? ClipHold.first : ClipHold.rest,
      after: ClipHold.last,
      inside: const {"own": true},
    );
    placement = ClipPlacement(
        id: freeId(m, "$id-p"), clip: id, layer: layer, start: start);
  }
  var motion = m.withClip(clip).copyWith(placed: [
    for (var p in m.placed)
      if (p.id != placement.id) p,
    placement,
  ]);
  return e.withBase(motion: motion);
}

/// withoutOwn is [e] with no own [kind]: its clip and its placements gone.
CanvasElement withoutOwn(CanvasElement e, MotionKind kind) {
  var m = e.base.motion;
  var had = ownClipOf(e, kind);
  if (had == null) return e;
  var (c, _) = had;
  return e.withBase(
    motion: m.copyWith(
      clips: [
        for (var x in m.clips)
          if (x.id != c.id) x,
      ],
      placed: [
        for (var p in m.placed)
          if (p.clip != c.id) p,
      ],
      slots: [
        for (var s in m.slots) s == c.id ? "" : s,
      ],
    ),
  );
}

/// freeLayer is a layer with nothing placed between [from] and [to]
/// seconds -- the second first, where arrivals usually go -- or the second.
int freeLayer(ElementMotion m, double from, double to) {
  for (var layer in const [1, 2, 0]) {
    var clash = m.placed.any((p) {
      if (p.layer != layer) return false;
      var c = m.clip(p.clip);
      var end = p.start + (p.length ?? c?.span ?? 0);
      return p.start < to && end > from;
    });
    if (!clash) return layer;
  }
  return 1;
}

/// freeId is [want], or it with a number on, not yet a clip or placement.
String freeId(ElementMotion m, String want) {
  bool taken(String id) =>
      m.clips.any((c) => c.id == id) || m.placed.any((p) => p.id == id);
  if (!taken(want)) return want;
  for (var i = 2;; i++) {
    if (!taken("$want$i")) return "$want$i";
  }
}

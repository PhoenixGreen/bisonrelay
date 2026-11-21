import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// motion_convert.dart turns an element's keyframe track into clips, frame
// for frame: tests build their clips with it from keys, which are quicker to
// write. Canvases themselves keep their tracks.
//
// An element's moves (across, down, size, turn, fade) become one clip from
// its first keyframe to its last, holding its first pose before and its last
// after as a track does. Its other keyed values (count, bow, slide) become
// a clip for each stretch between two keyframes naming them, on a layer per
// group, easing as the stretch did.
//
// Left as tracks, and still played: backgrounds, stages, scenery, players
// (a team's runs), and any track keying something a clip cannot say.

/// _groups are the keyed values a clip can say; each group's stretches share
/// one layer.
const _groups = [
  ["count"],
  ["bow"],
  ["slide"],
];

/// convertible is whether [e]'s keyframes are ones a clip can say.
bool convertible(CanvasElement e) {
  var track = e.track;
  if (track == null || track.keys.isEmpty) return false;
  if (e is BackgroundElement || e is StageElement || e is ParallaxElement) {
    return false;
  }
  if (e.kind == ElementKind.player) return false;
  var known = {for (var g in _groups) ...g};
  return track.keys.every((k) => k.values.keys.every(known.contains));
}

/// convertElement is [e] with its keyframes made into clips, or null where
/// they cannot all be said by clips.
CanvasElement? convertElement(CanvasElement e, int rate) {
  if (!convertible(e)) return null;
  var keys = [...e.track!.keys]..sort((a, b) => a.frame.compareTo(b.frame));
  var motion = e.base.motion;
  var clips = <MotionClip>[...motion.clips];
  var placed = <ClipPlacement>[...motion.placed];
  var n = 0;
  String id(String kind) => "${e.id}-$kind${n++}";
  double sec(int frames) => frames / rate;

  // The moves: one clip, first keyframe to last.
  var props = <MotionProp, double Function(Keyframe)>{
    MotionProp.x: (k) => k.dx,
    MotionProp.y: (k) => k.dy,
    MotionProp.scale: (k) => k.scale,
    MotionProp.turn: (k) => k.rotate,
    MotionProp.opacity: (k) => k.opacity,
  };
  var moved = <MotionProp, List<MotionKey>>{};
  for (var MapEntry(key: prop, value: of) in props.entries) {
    var first = of(keys.first);
    var varies = keys.any((k) => (of(k) - first).abs() > 1e-9);
    if (!varies && (first - prop.rest).abs() <= 1e-9) continue;
    moved[prop] = [
      for (var (i, k) in keys.indexed)
        MotionKey(sec(k.frame - keys.first.frame), MotionNumber(of(k)),
            // A track eases out of each key; a clip eases into it.
            ease: i == 0 ? KeyframeEasing.linear : keys[i - 1].easing),
    ];
  }
  var layers = <int>[0, 1, 2];
  if (moved.isNotEmpty) {
    layers.remove(0);
    var length = math.max(0.05, sec(keys.last.frame - keys.first.frame));
    var clip = MotionClip.ofKind(id("c"), MotionKind.action, name: "Keyframes")
        .copyWith(
            length: length,
            before: ClipHold.first,
            after: ClipHold.last,
            keys: moved,
            edited: true);
    clips.add(clip);
    placed.add(ClipPlacement(
        id: id("p"),
        clip: clip.id,
        layer: 0,
        start: sec(keys.first.frame),
        length: length));
  }

  // The keyed values: a clip for each stretch, each kind on a layer.
  for (var group in _groups) {
    var stretches = <(int, int, double, double, KeyframeEasing, String)>[];
    var lone = <(int, double, String)>[];
    for (var ch in group) {
      var named = [
        for (var k in keys)
          if (k.values[ch] case var v?) (k.frame, v, k.easing)
      ];
      if (named.length == 1) lone.add((named.single.$1, named.single.$2, ch));
      for (var i = 0; i + 1 < named.length; i++) {
        var (fa, va, ea) = named[i];
        var (fb, vb, _) = named[i + 1];
        stretches.add((fa, fb, va, vb, ea, ch));
      }
    }
    if (stretches.isEmpty && lone.isEmpty) continue;
    if (layers.isEmpty) return null;
    var layer = layers.removeAt(0);
    var all = [
      ...stretches,
      for (var (f, v, ch) in lone) (f, f, v, v, KeyframeEasing.linear, ch),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    // One after another on its layer, or it cannot be said.
    for (var i = 0; i + 1 < all.length; i++) {
      if (all[i + 1].$1 < all[i].$2) return null;
    }
    for (var (i, (fa, fb, va, vb, ease, ch)) in all.indexed) {
      var length = math.max(0.05, sec(fb - fa));
      var clip = MotionClip.ofKind(id("c"), MotionKind.action,
              layer: layer,
              name: switch (ch) {
                "count" => "Counts",
                "bow" => "Bows",
                _ => "Slides",
              })
          .copyWith(
        length: length,
        before: i == 0 ? ClipHold.first : ClipHold.rest,
        after: ClipHold.last,
        inside: {
          ch: [va, vb],
          if (ease != KeyframeEasing.linear) "ease": ease.name,
        },
      );
      clips.add(clip);
      placed.add(ClipPlacement(
          id: id("p"),
          clip: clip.id,
          layer: layer,
          start: sec(fa),
          length: length));
    }
  }
  return e.withBase(
      clearTrack: true, motion: motion.copyWith(clips: clips, placed: placed));
}

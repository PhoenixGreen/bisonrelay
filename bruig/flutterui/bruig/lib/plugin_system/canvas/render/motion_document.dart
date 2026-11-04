import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';

// motion_document.dart joins clips to a document: where every placed clip in
// the scene plays, worked out once per scene, and an element's pose with its
// clips' moves on top of its own keyframes. See motion.dart and
// motion_pose.dart.

/// _times keeps each scene's resolved placements, by its list of elements --
/// a new list is a changed scene, so a stale answer is never given.
final Expando<MotionTimes> _times = Expando("motionTimes");

/// motionTimesOf is where every placed clip among [doc]'s elements plays.
MotionTimes motionTimesOf(CanvasDocument doc) {
  var elements = doc.elements;
  if (_times[elements] case var known?) return known;
  var rate = math.max(1, doc.frameRate);
  var times = MotionTimes(
    sceneEnd: doc.frames / rate,
    markers: {for (var a in doc.actions) markerKey(a): a.frame / rate},
    placements: {
      for (var e in elements)
        for (var p in e.base.motion.placed)
          if (e.base.motion.clip(p.clip) case var c?) p.id: (p, c),
    },
  );
  _times[elements] = times;
  return times;
}

/// boxOf is [e]'s box as it is set.
Rect boxOf(CanvasElement e) => Rect.fromLTWH(e.x, e.y, e.width, e.height);

/// motionSceneOf is what places are worked out against in [doc]: its page,
/// its elements' boxes, and -- for "on" -- where each is drawn on [frame].
MotionScene motionSceneOf(CanvasDocument doc, int frame, {int depth = 0}) =>
    MotionScene(
      page: doc.size.size,
      boundsOf: (id) => switch (doc.elementById(id)) {
        var o? => boxOf(o),
        null => null,
      },
      // Where another element is drawn now; one level deep, so two that
      // follow each other do not go round for ever.
      drawnAt: depth > 0
          ? null
          : (id) {
              var o = doc.elementById(id);
              if (o == null) return null;
              var p = motionPoseIn(doc, o, frame, depth: depth + 1);
              var k = o.track?.at(frame) ?? Keyframe.rest;
              return boxOf(o).center + Offset(k.dx + p.dx, k.dy + p.dy);
            },
    );

/// motionPoseIn is what [e]'s placed clips make of it on [frame] of [doc].
MotionPose motionPoseIn(CanvasDocument doc, CanvasElement e, int frame,
    {MotionLive? live, double clock = 0, int depth = 0}) {
  var motion = e.base.motion;
  if (motion.isEmpty) return MotionPose.rest;
  var rate = math.max(1, doc.frameRate);
  return motionPose(motion, frame / rate, boxOf(e), motionTimesOf(doc),
      motionSceneOf(doc, frame, depth: depth),
      live: live,
      clock: clock,
      replaces: motion.clips.any((c) => c.kind == MotionKind.camera));
}

/// poseWithMotion is [e]'s pose on [frame]: its own keyframes', with its
/// clips' moves on top. Without [doc] -- a lone element drawn -- its
/// keyframes alone.
Keyframe poseWithMotion(CanvasElement e, int frame, CanvasDocument? doc) {
  var pose = e.track?.at(frame) ?? Keyframe.rest;
  if (doc == null || e.base.motion.isEmpty) return pose;
  return motionPoseIn(doc, e, frame).onto(pose);
}

/// MovedElement is where an element is with its clips' moves on it: the
/// selection box, the handles and the hit-test have to agree with what is
/// drawn -- the boundsAt lesson, again, for clips.
extension MovedElement on CanvasElement {
  /// movedBoundsAt is boundsAt with [doc]'s placed clips moving it too.
  Rect movedBoundsAt(int frame, CanvasDocument doc) => base.motion.isEmpty
      ? boundsAt(frame)
      : boundsWith(poseWithMotion(this, frame, doc));

  /// movedRotationAt is rotationAt with the clips' turn added.
  double movedRotationAt(int frame, CanvasDocument doc) => base.motion.isEmpty
      ? rotationAt(frame)
      : rotation + poseWithMotion(this, frame, doc).rotate;

  /// movedFrameAt is frameAt with the clips' turn added.
  BoxFrame movedFrameAt(int frame, CanvasDocument doc) =>
      BoxFrame(movedRotationAt(frame, doc), base.skewX, base.skewY);
}

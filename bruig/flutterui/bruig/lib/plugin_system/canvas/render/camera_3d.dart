import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';

// camera_3d.dart is a Camera element in a scene on a 3D stage: the stage's
// camera, from where the Camera stands -- its own view, or the stage's
// until it has one -- moved by its clips, as Ken settled it:
//
//   a turn orbits round what it looks at;
//   a size dollies it closer -- 2 is half as far;
//   an "on" another element aims it at that element's spot on the stage,
//     as far along as the clip has got: a push in arrives there, a follow
//     stays there as it walks, a pull back leaves;
//   across and down without a place -- a shake -- pan it, as far in metres
//     as that many pixels are across the picture at what it looks at.
//
// Drawn through it while playing, exporting and looking through it -- see
// directedBy -- and through the stage's own camera while editing.

/// camera3dAt is what [cam] makes of [stage]'s camera on [frame] of [doc].
StageCamera camera3dAt(
    CameraElement cam, StageElement stage, int frame, CanvasDocument doc,
    {LiveMotion? live}) {
  var base = cam.view ?? stage.ownCameraAt(frame);
  var pose = poseWithMotion(cam, frame, doc, live: live);
  var yaw = base.yaw + pose.rotate;
  var distance = base.distance / math.max(0.05, pose.scale);
  var (tx, ty, tz) = (base.tx, base.ty, base.tz);
  var aim = _aim(cam, frame, doc, pose.dx, pose.dy);
  if (aim != null) {
    var (spot, f) = aim;
    tx += (spot.$1 - tx) * f;
    ty += (spot.$2 - ty) * f;
    tz += (spot.$3 - tz) * f;
  } else if (pose.dx != 0 || pose.dy != 0) {
    // Panned in the picture's plane: across along the camera's right,
    // down as down.
    var view = StageView(stage.bounds, base.copyWith(yaw: yaw));
    var hfov = 2 * math.atan(36 / (2 * base.lens));
    var metres =
        2 * distance * math.tan(hfov / 2) / math.max(1, doc.size.rect.width);
    var (rx, _, rz) = view.right;
    tx += rx * pose.dx * metres;
    tz += rz * pose.dx * metres;
    ty -= pose.dy * metres;
  }
  return base.copyWith(yaw: yaw, distance: distance, tx: tx, ty: ty, tz: tz);
}

/// _aim is where [cam]'s clips have it look on [frame], and how far along
/// to it -- from what its across and down have made of a place "on"
/// another element that stands on a stage -- or null where it looks at no
/// such place.
((double, double, double), double)? _aim(
    CameraElement cam, int frame, CanvasDocument doc, double dx, double dy) {
  var motion = cam.base.motion;
  if (motion.isEmpty) return null;
  // The clip whose place it is: the one playing, or the last before it.
  var t = frame / math.max(1, doc.frameRate);
  var times = motionTimesOf(doc);
  MotionClip? clip;
  var latest = double.negativeInfinity;
  for (var p in motion.placed) {
    var span = times.span(p.id);
    var c = motion.clip(p.clip);
    if (span == null || c == null || span.start > t + 1e-9) continue;
    if (span.start >= latest) {
      latest = span.start;
      clip = c;
    }
  }
  String? target;
  for (var k in clip?.keys[MotionProp.x] ?? const <MotionKey>[]) {
    if (k.value case MotionPlace(kind: MotionPlaceKind.on, target: var named)
        when named.isNotEmpty) {
      target = named;
    }
  }
  if (clip == null || target == null) return null;
  var who = doc.elementById(target);
  var spot = who?.spotAt(frame);
  if (who == null || spot == null) return null;
  // How far along: the move made of the whole way there.
  var scene = motionSceneOf(doc, frame);
  var self = boxOf(cam);
  var whole = MotionPlace(MotionPlaceKind.on, target: target);
  var wx = motionValue(clip, MotionProp.x, whole, self, scene);
  var wy = motionValue(clip, MotionProp.y, whole, self, scene);
  var f = wx.abs() > 1
      ? dx / wx
      : wy.abs() > 1
          ? dy / wy
          : 1.0;
  return ((spot.x, spot.lift, spot.z), f.clamp(0.0, 1.0));
}

/// directedBy runs [paint] with [doc]'s Camera directing every stage drawn
/// -- in a scene on a 3D stage, where it has one -- and puts the stages back
/// on their own cameras after.
T directedBy<T>(CanvasDocument doc, LiveMotion? live, T Function() paint) {
  var cam = cameraOf(doc);
  if (cam == null || !isStageScene(doc)) return paint();
  var was = StageElement.director;
  StageElement.director =
      (stage, frame) => camera3dAt(cam, stage, frame, doc, live: live);
  try {
    return paint();
  } finally {
    StageElement.director = was;
  }
}

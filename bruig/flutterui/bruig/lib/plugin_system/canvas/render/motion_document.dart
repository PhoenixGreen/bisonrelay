import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/render/model3d/model_scene.dart'
    show ModelPlay;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';

// motion_document.dart joins clips to a document: where every placed clip in
// the scene plays, worked out once per scene, and an element's pose with its
// clips' moves on top of any legacy keyframe track it kept (see
// model/motion_convert.dart). See motion.dart and motion_pose.dart.

/// _times keeps each scene's resolved placements, by its list of
/// elements, with what else they were worked out from: the scene's length,
/// rate and markers, and the master's elements.
final Expando<(int, int, Object, Object?, MotionTimes)> _times =
    Expando("motionTimes");

/// motionTimesOf is where every placed clip among [doc]'s elements plays --
/// and the master's, which play under the scene.
MotionTimes motionTimesOf(CanvasDocument doc) {
  var elements = doc.elements;
  var master = doc.editingMaster ? null : doc.masterScene?.elements;
  if (_times[elements] case (var f, var r, var a, var m, var known)
      when f == doc.frames &&
          r == doc.frameRate &&
          identical(a, doc.actions) &&
          identical(m, master)) {
    return known;
  }
  var rate = math.max(1, doc.frameRate);
  var times = MotionTimes(
    sceneEnd: doc.frames / rate,
    markers: {for (var a in doc.actions) markerKey(a): a.frame / rate},
    placements: {
      for (var e in [...?master, ...elements])
        for (var p in e.base.motion.placed)
          if (e.base.motion.clip(p.clip) case var c?) p.id: (p, c),
    },
  );
  _times[elements] = (doc.frames, doc.frameRate, doc.actions, master, times);
  return times;
}

/// settledFrameOf is the frame [doc] opens on: everything arrived, by the
/// clips that play its arrivals.
int settledFrameOf(CanvasDocument doc) {
  var last = 0;
  var times = motionTimesOf(doc);
  var rate = math.max(1, doc.frameRate);
  for (var e in doc.elements) {
    var m = e.base.motion;
    for (var p in m.placed) {
      var c = m.clip(p.clip);
      if (c == null || !(c.kind == MotionKind.arrive || revealsIn(c))) continue;
      if (times.span(p.id) case var s?) {
        last = math.max(last, (s.end * rate).ceil());
      }
    }
  }
  return last.clamp(0, math.max(0, doc.frames - 1)).toInt();
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

/// LiveMotion is what each element is playing from its slots at this moment,
/// on [clock] (see ui/motion_player.dart). Handed to the renderer by whoever
/// runs it; an export has nothing playing and is drawn from the timeline.
abstract class LiveMotion {
  double get clock;

  /// of is what [element] is playing from its slots, or null for an
  /// element on its timeline.
  MotionLive? of(String element);
}

/// MotionPreview is what plays live, with one element's motion chain shown
/// as it stands at one join -- its first [upto] pose devices -- for the
/// Chain's "Preview from here". Handed to the stage as its LiveMotion; an
/// export has none, and draws every chain whole.
class MotionPreview implements LiveMotion {
  final LiveMotion? playing;
  final String element;
  final int upto;
  const MotionPreview(this.playing, this.element, this.upto);

  @override
  double get clock => playing?.clock ?? 0;

  @override
  MotionLive? of(String element) => playing?.of(element);
}

/// liveShifted is [live] seen [seconds] later (earlier, negative): what is
/// playing the same, its clock moved. For asking where something live was a
/// moment ago, as the frames before this one ask of the timeline.
LiveMotion liveShifted(LiveMotion live, double seconds) =>
    _ShiftedLive(live, seconds);

class _ShiftedLive implements LiveMotion {
  final LiveMotion live;
  final double by;
  _ShiftedLive(this.live, this.by);

  @override
  double get clock => live.clock + by;

  @override
  MotionLive? of(String element) => live.of(element);
}

/// poseWithMotion is [e]'s pose on [frame]: its track's, if it kept one, with
/// its clips' moves on top -- from its slots where [live] has it off its
/// timeline -- and then its pose devices', each asking the ones to its left
/// (see motion_devices.dart). With [upto], only the first that many of its
/// pose devices: the chain as it stands at that join. Without [doc] (a lone
/// element drawn), its track alone.
Keyframe poseWithMotion(CanvasElement e, int frame, CanvasDocument? doc,
    {LiveMotion? live, int? upto}) {
  if (doc == null) return e.track?.at(frame) ?? Keyframe.rest;
  if (live case MotionPreview p when upto == null && p.element == e.id) {
    upto = p.upto;
  }
  var devices = e.base.motion.poseDevices;
  if (upto != null && upto < devices.length) {
    devices = devices.sublist(0, upto.clamp(0, devices.length));
  }
  if (devices.isEmpty) return _clipPose(e, frame, doc, live);
  return _pulled(e, frame, doc, live, devices, devices.length - 1);
}

/// _pulled is [e]'s pose on [frame] after pose device [i] of [devices]:
/// what the device makes of what those to its left give it -- asked, by a
/// device that changes time, for another moment (rule 2).
Keyframe _pulled(CanvasElement e, int frame, CanvasDocument doc,
    LiveMotion? live, List<MotionDevice> devices, int i) {
  if (i < 0) return _clipPose(e, frame, doc, live);
  var d = devices[i];
  switch (d.kind) {
    case MotionDeviceKind.time:
      var rate = math.max(1, doc.frameRate).toDouble();
      var t = frame / rate, tt = retimed(d, t);
      // What plays live is asked at its own clock, moved alike.
      var shifted = live == null ? null : liveShifted(live, tt - t);
      return _pulled(e, (tt * rate).round(), doc, shifted, devices, i - 1);
    default:
      // A look is not a pose device; it passes the pose on.
      return _pulled(e, frame, doc, live, devices, i - 1);
  }
}

/// motionSpeedAt is how fast [e] is going on [frame], in the page's pixels a
/// second, as its chain stands after its first [upto] pose devices: for the
/// meters between them. With it, the pose there.
(double, Keyframe) motionSpeedAt(CanvasElement e, int frame, CanvasDocument doc,
    {int? upto, LiveMotion? live}) {
  var rate = math.max(1, doc.frameRate).toDouble();
  var now = poseWithMotion(e, frame, doc, live: live, upto: upto ?? 1 << 20);
  var before = poseWithMotion(e, frame - 1, doc,
      live: live == null ? null : liveShifted(live, -1 / rate),
      upto: upto ?? 1 << 20);
  var dx = now.dx - before.dx, dy = now.dy - before.dy;
  return (math.sqrt(dx * dx + dy * dy) * rate, now);
}

/// retimed is the moment a Time device asks the devices to its left for,
/// at [t] seconds: shifted, sped up or slowed, held to every few frames
/// (as stop motion is), and looped -- cycled or there and back -- over its
/// Every.
double retimed(MotionDevice d, double t) {
  var tt = (t + d.value("offset")) * d.value("speed");
  var every = d.value("every");
  switch (d.value("loop").round()) {
    case 1:
      tt = tt % every;
    case 2:
      var q = tt % (2 * every);
      tt = q > every ? 2 * every - q : q;
    default:
      tt = math.max(0.0, tt);
  }
  var hold = d.value("hold").round();
  // Held in steps of so many frames of a 24 a second film.
  if (hold > 1) tt = (tt * 24 / hold).floor() / (24 / hold);
  return tt;
}

/// _clipPose is [e]'s pose on [frame] from its track and its clips: the
/// start of its chain, before any pose device.
Keyframe _clipPose(
    CanvasElement e, int frame, CanvasDocument doc, LiveMotion? live) {
  var pose = e.track?.at(frame) ?? Keyframe.rest;
  if (e.base.motion.isEmpty) return pose;
  var off = live?.of(e.id);
  var moved = motionPoseIn(doc, e, frame, live: off, clock: live?.clock ?? 0)
      .onto(pose);
  // The stretch its arrival plays over, in this document's frames.
  if (moved.values[revealFrom] case var from?) {
    var rate = math.max(1, doc.frameRate);
    moved = moved.copyWith(values: {
      ...moved.values,
      revealFrom: from * rate,
      revealTo: (moved.values[revealTo] ?? from) * rate,
    });
  }
  return moved;
}

/// MovedElement is where an element is with its clips' moves on it, so the
/// selection box, the handles and the hit-test agree with what is drawn.
extension MovedElement on CanvasElement {
  /// movedBoundsAt is boundsAt with [doc]'s placed clips moving it too. A
  /// camera's is the frame it shows: closer, smaller.
  Rect movedBoundsAt(int frame, CanvasDocument doc, {LiveMotion? live}) {
    if (this case CameraElement cam) {
      return cameraFrame(cam, frame, doc, live: live);
    }
    return !base.motion.moves
        ? boundsAt(frame)
        : boundsWith(poseWithMotion(this, frame, doc, live: live));
  }

  /// movedRotationAt is rotationAt with the clips' turn added.
  double movedRotationAt(int frame, CanvasDocument doc, {LiveMotion? live}) =>
      !base.motion.moves
          ? rotationAt(frame)
          : rotation + poseWithMotion(this, frame, doc, live: live).rotate;

  /// movedFrameAt is frameAt with the clips' turn added.
  BoxFrame movedFrameAt(int frame, CanvasDocument doc, {LiveMotion? live}) =>
      BoxFrame(movedRotationAt(frame, doc, live: live), base.skewX, base.skewY);
}

/// cameraOf is [doc]'s camera: the first one shown, if there is one.
CameraElement? cameraOf(CanvasDocument doc) =>
    doc.elements.whereType<CameraElement>().where((c) => c.visible).firstOrNull;

/// cameraFraming is how [cam] frames the page on [frame]: a zoom -- never
/// less than one, so the page is always filled -- and the point it is
/// centred on, held in far enough that the picture stays on the page. Its
/// box's width is how much it shows; its clips move where it looks and how
/// close: see CameraElement.
(double, Offset) cameraFraming(CameraElement cam, int frame, CanvasDocument doc,
    {LiveMotion? live}) {
  var page = doc.size.rect;
  var pose = poseWithMotion(cam, frame, doc, live: live);
  var box = cam.bounds;
  var zoom = math.max(
      1.0, page.width / math.max(1.0, box.width) * math.max(0.01, pose.scale));
  var c = box.center + Offset(pose.dx, pose.dy);
  var hx = page.width / 2 / zoom, hy = page.height / 2 / zoom;
  return (
    zoom,
    Offset(c.dx.clamp(page.left + hx, page.right - hx),
        c.dy.clamp(page.top + hy, page.bottom - hy)),
  );
}

/// cameraFrame is the part of the page [cam] shows on [frame], page-shaped.
Rect cameraFrame(CameraElement cam, int frame, CanvasDocument doc,
    {LiveMotion? live}) {
  var page = doc.size.rect;
  var (zoom, at) = cameraFraming(cam, frame, doc, live: live);
  return Rect.fromCenter(
      center: at, width: page.width / zoom, height: page.height / zoom);
}

/// sceneFraming is how [doc]'s scene is framed on [frame]: through its
/// Camera, which takes over where there is one; else its slow move, if it
/// has one (SceneCamera); else null, the whole page.
(double, Offset)? sceneFraming(CanvasDocument doc, int frame,
    {LiveMotion? live}) {
  if (cameraOf(doc) case var cam?) {
    // On a 3D stage it is the stage's camera, not a frame on the page.
    if (isStageScene(doc)) return null;
    return cameraFraming(cam, frame, doc, live: live);
  }
  return doc.scene.camera
      ?.at(frame / math.max(1, doc.frames - 1), doc.size.rect);
}

/// cameraMostZoom is the closest [doc]'s camera ever comes: its frame, and
/// the largest size any of its clips is keyed to -- one if it has none. For
/// what is drawn ahead, to be sharp under it.
double cameraMostZoom(CanvasDocument doc) {
  var cam = cameraOf(doc);
  if (cam == null) return 1;
  var most = 1.0;
  for (var c in cam.base.motion.clips) {
    for (var k in c.keys[MotionProp.scale] ?? const <MotionKey>[]) {
      if (k.value case MotionNumber(:var value)) most = math.max(most, value);
    }
  }
  var base = doc.size.rect.width / math.max(1.0, cam.width);
  return (math.max(1.0, base) * most).clamp(1.0, 8.0);
}

/// isStageScene is whether [doc]'s scene is played on a 3D stage -- its
/// background's, or a Background element showing one: a Camera there lives
/// in the scene rather than framing the page. See camera_3d.dart.
bool isStageScene(CanvasDocument doc) =>
    doc.drawnBackground.isStage ||
    doc.elements.any((e) => e is BackgroundElement && e.isStage);

/// modelPlaysAt is which of [e]'s model's own animations its clips play on
/// [frame], how far into each and how much each counts: see ModelScene.
List<ModelPlay> modelPlaysAt(CanvasElement e, int frame, CanvasDocument doc,
    {LiveMotion? live}) {
  var motion = e.base.motion;
  if (motion.isEmpty) return const [];
  var off = live?.of(e.id);
  var pose = motionPoseIn(doc, e, frame, live: off, clock: live?.clock ?? 0);
  return [
    for (var s in pose.sources)
      if (s.clip.kind == MotionKind.model)
        (
          s.clip.inside["animation"] is String
              ? s.clip.inside["animation"] as String
              : s.clip.name,
          s.time,
          motion.weight(s.layer),
        ),
  ];
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/render/model3d/model_scene.dart'
    show ModelPlay;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart'
    show channelLevelAt;
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show pathPointsOf, wholeLoopOf;

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

/// masterTimesOf is where the master's own clips play, under a run of
/// scenes: on the run's clock, as the master is drawn (see paintCanvasDocument)
/// -- the run's length its end, its own markers its markers -- not on the
/// scene's (Ken's systems review, 2026-11-08). Null where the master is not
/// drawn on that clock: no scenes, a book, or the master being edited.
MotionTimes? masterTimesOf(CanvasDocument doc) {
  var master = doc.masterScene;
  if (master == null || doc.editingMaster || !doc.hasScenes || doc.isPages) {
    return null;
  }
  var elements = master.elements;
  if (_masterTimes[elements] case (var f, var r, var a, var known)
      when f == doc.sequenceFrames &&
          r == doc.frameRate &&
          identical(a, master.actions)) {
    return known;
  }
  var rate = math.max(1, doc.frameRate);
  var times = MotionTimes(
    sceneEnd: doc.sequenceFrames / rate,
    markers: {for (var a in master.actions) markerKey(a): a.frame / rate},
    placements: {
      for (var e in elements)
        for (var p in e.base.motion.placed)
          if (e.base.motion.clip(p.clip) case var c?) p.id: (p, c),
    },
  );
  _masterTimes[elements] =
      (doc.sequenceFrames, doc.frameRate, master.actions, times);
  _onMaster[elements] = {for (var e in elements) e.id};
  return times;
}

final Expando<(int, int, Object, MotionTimes)> _masterTimes =
    Expando("masterTimes");
final Expando<Set<String>> _onMaster = Expando("onMaster");

/// _timesFor is where [e]'s clips play: the master's own clock for one on
/// the master under a run of scenes, else the scene's.
MotionTimes _timesFor(CanvasDocument doc, CanvasElement e) {
  if (masterTimesOf(doc) case var m?) {
    if (_onMaster[doc.masterScene!.elements]?.contains(e.id) ?? false) {
      return m;
    }
  }
  return motionTimesOf(doc);
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
  return motionPose(motion, frame / rate, boxOf(e), _timesFor(doc, e),
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

  /// pointer is where the pointer is over the page, in its coordinates, for
  /// a Look at that faces it -- or null, off the page, or in an export.
  Offset? get pointer;

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
  final Offset? pointerAt;
  const MotionPreview(this.playing, this.element, this.upto, {this.pointerAt});

  @override
  double get clock => playing?.clock ?? 0;

  @override
  Offset? get pointer => playing?.pointer ?? pointerAt;

  @override
  MotionLive? of(String element) => playing?.of(element);
}

/// liveShifted is [live] seen [seconds] later (earlier, negative): what is
/// playing the same, its clock moved. For asking where something live was a
/// moment ago, as the frames before this one ask of the timeline.
LiveMotion liveShifted(LiveMotion live, double seconds) =>
    _ShiftedLive(live, seconds);

/// liveForCopy is [live] as a copy of an element reused sees it (Ken,
/// 2026-11-08: launched from their slots, the copies moved as one): each
/// clip playing started [start] seconds later and going at [speed] -- the
/// clock the same, each play's start moved so that what it has played is
/// the copy's share of it, holding its first moment until its start.
/// A clip played once has ended for the copy only when its own share of it
/// has: its clips are read from [motion].
LiveMotion liveForCopy(
        LiveMotion live, double start, double speed, ElementMotion motion) =>
    start == 0 && speed == 1 ? live : _CopyLive(live, start, speed, motion);

class _CopyLive implements LiveMotion {
  final LiveMotion live;
  final double start, speed;
  final ElementMotion motion;
  _CopyLive(this.live, this.start, this.speed, this.motion);

  @override
  double get clock => live.clock;

  @override
  Offset? get pointer => live.pointer;

  @override
  MotionLive? of(String element) {
    var m = live.of(element);
    if (m == null) return null;
    var now = live.clock;
    LivePlay? copied(LivePlay? p) {
      if (p == null) return null;
      var played = math.max(0.0, now - p.start - start) * speed;
      var clip = motion.clip(p.clip);
      // Ended for the element; for a copy that started later, only once it
      // has played its own way through.
      var ended = p.ended &&
          (clip == null ||
              clip.loop ||
              played * clip.speed >= clip.length - 1e-6);
      return LivePlay(p.clip, now - played, ended: ended);
    }

    return MotionLive(
        plays: [for (var p in m.plays) copied(p)], carry: m.carry);
  }
}

/// _CopyPlays is [live] as one copy of element [id] sees it: what the copy
/// plays of its own, by [key] in [raw], laid over the element's, layer by
/// layer -- an empty layer of the copy's is the element's.
class _CopyPlays implements LiveMotion {
  final LiveMotion live, raw;
  final String id, key;
  _CopyPlays(this.live, this.raw, this.id, this.key);

  @override
  double get clock => live.clock;

  @override
  Offset? get pointer => live.pointer;

  @override
  MotionLive? of(String element) {
    var base = live.of(element);
    if (element != id) return base;
    var own = raw.of(key);
    if (own == null) return base;
    if (base == null) return own;
    var n = math.max(own.plays.length, base.plays.length);
    return MotionLive(plays: [
      for (var i = 0; i < n; i++) own.play(i) ?? base.play(i),
    ], carry: [
      for (var i = 0; i < n; i++)
        own.play(i) != null ? own.left(i) : base.left(i),
    ]);
  }
}

class _ShiftedLive implements LiveMotion {
  final LiveMotion live;
  final double by;
  _ShiftedLive(this.live, this.by);

  @override
  double get clock => live.clock + by;

  @override
  Offset? get pointer => live.pointer;

  @override
  MotionLive? of(String element) => live.of(element);
}

/// poseWithMotion is [e]'s pose on [frame]: its track's, if it kept one, with
/// its clips' moves on top -- from its slots where [live] has it off its
/// timeline -- and then its pose devices', each asking the ones to its left
/// (see motion_devices.dart). With [upto], only the first that many of its
/// pose devices: the chain as it stands at that join. Without [doc] (a lone
/// element drawn), its track alone.
///
/// [instance] is which of an element reused (see instances.dart) -- its
/// place, start and size put on at its Instances device (rule 3); null for
/// the element as it is placed, as one.
///
/// [frameRate] is the rate a lone element is drawn at, for its loop.
Keyframe poseWithMotion(CanvasElement e, int frame, CanvasDocument? doc,
    {LiveMotion? live, int? upto, int? instance, int? frameRate}) {
  if (doc == null) {
    return _withLoop(e, frame, frameRate ?? defaultFrameRate, 1 << 30,
        e.track?.at(frame) ?? Keyframe.rest, instance);
  }
  if (live case MotionPreview p when upto == null && p.element == e.id) {
    upto = p.upto;
  }
  var devices = e.base.motion.poseDevices;
  if (upto != null && upto < devices.length) {
    devices = devices.sublist(0, upto.clamp(0, devices.length));
  }
  var pose = devices.isEmpty
      ? _clipPose(e, frame, doc, live)
      : _pulled(e, frame, doc, live, devices, devices.length - 1, instance);
  pose = _withLoop(
      e, frame, math.max(1, doc.frameRate), doc.frames - 1, pose, instance);
  // Drawn at its Drawing's size -- a copy's own, where it has one.
  var m = e.base.motion;
  var size = m.drawSize;
  if (m.instances case var set?
      when instance != null && instance >= 0 && instance < set.count) {
    size = set.items[instance].own["drawSize"] ?? size;
  }
  return size == 1 ? pose : pose.copyWith(scale: pose.scale * size);
}

/// stampsCopies is whether [e]'s copies can be drawn once and stamped at
/// each place (InstanceSet.uniform): alike in their own values, and with
/// nothing that works each one out from where it is or who it is -- a
/// Wiggle each its own, a Look at, a Follow path, a Spring after another
/// element, a clip's key at a place (off the page's edge, beside another),
/// or a copy playing a clip of its own (Ken's systems review, 2026-11-08:
/// stamped, every copy wiggled as one and a touched coin never popped).
bool stampsCopies(CanvasElement e, LiveMotion? live) {
  var m = e.base.motion;
  var set = m.instances;
  if (set == null || !set.uniform) return false;
  for (var d in m.devices) {
    if (!d.on) continue;
    switch (d.kind) {
      case MotionDeviceKind.wiggle when d.value("seed").round() == 1:
      case MotionDeviceKind.lookAt:
      case MotionDeviceKind.followPath:
      case MotionDeviceKind.spring when d.value("follows").round() == 1:
        return false;
      default:
    }
  }
  for (var c in m.clips) {
    for (var keys in c.keys.values) {
      if (keys.any((k) => k.value is MotionPlace)) return false;
    }
  }
  if (live != null) {
    for (var item in set.items) {
      if (live.of(instanceKey(e.id, item.id)) != null) return false;
    }
  }
  return true;
}

/// movesAtAll is whether anything moves [e] beyond its keyframes: its
/// motion (see ElementMotion.moves), or a loop that moves it.
bool movesAtAll(CanvasElement e) {
  if (e.base.motion.moves) return true;
  var loop = wholeLoopOf(e);
  return loop != null && loop.on && loop.preset.moves;
}

/// _withLoop is [pose] with [e]'s moving loop on it (see ElementLoop): its
/// move and fade the pose's own, so what follows the element -- a Look at,
/// a Spring, its trail, its box on the stage, a copy -- sees them; its turn
/// and size about the loop's own pivot as channels the renderer turns it
/// by. One motion path: the loop is not put on again as it is drawn. A
/// copy's loop starts as much later as the copy does.
Keyframe _withLoop(CanvasElement e, int frame, int rate, int last,
    Keyframe pose, int? instance) {
  var loop = wholeLoopOf(e);
  if (loop == null || !loop.on || !loop.preset.moves) return pose;
  var at = frame;
  if (e.base.motion.instances case var set?
      when instance != null && instance >= 0 && instance < set.count) {
    at -= (set.startOf(instance) * rate).round();
  }
  var swing = loop.poseAt(at, arrived: arrivalEnd(e, rate), last: last);
  if (swing == null) return pose;
  var box = boxOf(e);
  return pose.copyWith(
    dx: pose.dx + swing.dx * box.width,
    dy: pose.dy + swing.dy * box.height,
    opacity: pose.opacity * swing.opacity,
    values: {
      ...pose.values,
      KeyframeChannel.loopTurn: swing.turn,
      KeyframeChannel.loopSx: swing.sx,
      KeyframeChannel.loopSy: swing.sy,
      KeyframeChannel.loopPivotX: swing.pivot.dx,
      KeyframeChannel.loopPivotY: swing.pivot.dy,
    },
  );
}

/// withOwnValues is [d] as copy [instance] of [set] has it: each knob it has
/// a value of its own for (see deviceOwnKey) set to that. As it is for the
/// element, or one placed once.
MotionDevice withOwnValues(MotionDevice d, InstanceSet? set, int? instance) {
  if (set == null || instance == null || instance < 0) return d;
  if (instance >= set.count) return d;
  var own = set.items[instance].own;
  if (own.isEmpty) return d;
  var out = d;
  for (var p in d.kind.params) {
    if (own[deviceOwnKey(d.id, p.id)] case var v?) {
      out = out.withValue(p.id, v);
    }
  }
  return out;
}

/// _pulled is [e]'s pose on [frame] after pose device [i] of [devices]:
/// what the device makes of what those to its left give it -- asked, by a
/// device that changes time, for another moment (rule 2).
Keyframe _pulled(CanvasElement e, int frame, CanvasDocument doc,
    LiveMotion? live, List<MotionDevice> devices, int i, int? instance) {
  if (i < 0) return _clipPose(e, frame, doc, live);
  // Its knobs where its LFOs have them at this moment -- and, for one copy
  // of an element reused, where that copy has its own (see instances.dart).
  var d = withOwnValues(
      motionModulated(
          devices[i], e.base.motion.devices, frame / math.max(1, doc.frameRate),
          doc: doc),
      e.base.motion.instances,
      instance);
  switch (d.kind) {
    case MotionDeviceKind.instances:
      var set = e.base.motion.instances;
      if (set == null || instance == null || instance < 0) {
        return _pulled(e, frame, doc, live, devices, i - 1, null);
      }
      if (instance >= set.count) {
        return _pulled(e, frame, doc, live, devices, i - 1, null);
      }
      // What is left of it is the same for every instance, asked at this
      // one's own moment: later by its start -- holding its first frame
      // before then, never wrapping round -- and at its own speed.
      var rate = math.max(1, doc.frameRate).toDouble();
      var t = frame / rate;
      var at = math.max(0.0, t - set.startOf(instance)) * set.speedOf(instance);
      // Live from its slots, on their own clock: each clip playing seen as
      // this copy plays it -- later by its start, at its speed.
      var shifted = live == null
          ? null
          : liveForCopy(live, set.startOf(instance), set.speedOf(instance),
              e.base.motion);
      // And what this copy plays of its own -- a coin's pop when it alone is
      // taken -- over the element's, layer by layer, on the real clock.
      var own = instanceKey(e.id, set.items[instance].id);
      if (live != null && shifted != null && live.of(own) != null) {
        shifted = _CopyPlays(shifted, live, e.id, own);
      }
      // Its clips worked out from where this copy stands: a place such as
      // "off the left edge" is past the page's edge from the copy, not
      // from the element (Ken: Slide in left copies on the page).
      var item = set.items[instance];
      var here = item.dx == 0 && item.dy == 0
          ? e
          : e.withBase(x: e.base.x + item.dx, y: e.base.y + item.dy);
      var left = _pulled(
          here, (at * rate).round(), doc, shifted, devices, i - 1, null);
      return left.copyWith(
          dx: left.dx + item.dx,
          dy: left.dy + item.dy,
          scale: left.scale * set.sizeOf(instance),
          rotate: left.rotate + set.turnOf(instance),
          opacity: left.opacity * set.opacityOf(instance));
    case MotionDeviceKind.time:
      var rate = math.max(1, doc.frameRate).toDouble();
      var t = frame / rate, tt = retimed(d, t);
      // Continue: past its stretch, on at the speed it ended going -- its
      // last two frames inside it, as what ends there may let go at once.
      var every = d.value("every");
      var last = (every * rate).round() - 1;
      if (d.value("loop").round() == 3 && tt * rate > last && last > 0) {
        var end = _pulled(
            e,
            last,
            doc,
            live == null ? null : liveShifted(live, last / rate - t),
            devices,
            i - 1,
            instance);
        var before = _pulled(
            e,
            last - 1,
            doc,
            live == null ? null : liveShifted(live, (last - 1) / rate - t),
            devices,
            i - 1,
            instance);
        var steps = tt * rate - last;
        return end.copyWith(
            dx: end.dx + (end.dx - before.dx) * steps,
            dy: end.dy + (end.dy - before.dy) * steps,
            rotate: end.rotate + (end.rotate - before.rotate) * steps,
            scale:
                math.max(0.0, end.scale + (end.scale - before.scale) * steps));
      }
      // What plays live is asked at its own clock, moved alike.
      var shifted = live == null ? null : liveShifted(live, tt - t);
      return _pulled(
          e, (tt * rate).round(), doc, shifted, devices, i - 1, instance);
    case MotionDeviceKind.wiggle:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var t = frame / math.max(1, doc.frameRate);
      var f = d.value("speed"), a = d.value("amount");
      // Each instance its own wiggle, when asked: rule 3.
      var seed = d.value("seed").round() == 1 && (instance ?? -1) >= 0
          ? instance! * 7.31 + 1
          : 0.0;
      double nz(double x) =>
          math.sin(x * 2.1) * 0.5 +
          math.sin(x * 4.7 + 1.3) * 0.3 +
          math.sin(x * 9.3 + 2.1) * 0.2;
      var at = t * f + seed * 3;
      return p.copyWith(
          dx: p.dx + nz(at) * a,
          dy: p.dy + nz(at + 40) * a,
          rotate: p.rotate + nz(at + 80) * d.value("turn"));
    case MotionDeviceKind.oscillate:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var t = frame / math.max(1, doc.frameRate);
      var s = math.sin(2 * math.pi * (d.value("rate") * t + d.value("phase")));
      var a = d.value("amount");
      return switch (d.value("moves").round()) {
        1 => p.copyWith(dx: p.dx + s * a),
        // Size: the amount a share, a hundred to the whole.
        2 => p.copyWith(scale: p.scale * math.max(0.0, 1 + s * a / 100)),
        3 => p.copyWith(rotate: p.rotate + s * a),
        _ => p.copyWith(dy: p.dy + s * a),
      };
    case MotionDeviceKind.spring:
      // What is to its left, followed by a spring: the moments before this
      // one, each weighed by how a spring answers a push that long ago.
      var rate = math.max(1, doc.frameRate).toDouble();
      var w0 = d.value("stiffness") * 0.9;
      var z = d.value("damping").clamp(0.03, 0.95);
      var wd = w0 * math.sqrt(1 - z * z);
      var dt = 1 / rate;
      var base = _pulled(e, frame, doc, live, devices, i - 1, instance);
      // Following another: where it was, a moment ago and before, chased.
      if (d.value("follows").round() == 1 && d.target.isNotEmpty) {
        var me = Offset(e.x + e.width / 2, e.y + e.height / 2);
        var fx = 0.0, fy = 0.0, fsum = 0.0;
        for (var j = 0; j < 16; j++) {
          var tau = j * dt;
          var h = math.exp(-z * w0 * tau) * math.sin(wd * (tau + dt));
          var at = _centreOf(doc, d.target, frame - j);
          if (at == null) return base;
          fx += (at.dx - me.dx) * h;
          fy += (at.dy - me.dy) * h;
          fsum += h;
        }
        if (fsum.abs() < 1e-4) return base;
        return base.copyWith(dx: fx / fsum, dy: fy / fsum);
      }
      var dx = 0.0, dy = 0.0, sc = 0.0, turn = 0.0, sum = 0.0;
      for (var j = 0; j < 16; j++) {
        var tau = j * dt;
        var h = math.exp(-z * w0 * tau) * math.sin(wd * (tau + dt));
        var q = j == 0
            ? base
            : _pulled(
                e,
                frame - j,
                doc,
                live == null ? null : liveShifted(live, -tau),
                devices,
                i - 1,
                instance);
        dx += q.dx * h;
        dy += q.dy * h;
        sc += q.scale * h;
        turn += q.rotate * h;
        sum += h;
      }
      if (sum.abs() < 1e-4) return base;
      return base.copyWith(
          dx: dx / sum, dy: dy / sum, scale: sc / sum, rotate: turn / sum);
    case MotionDeviceKind.followPath:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var host = doc.elementById(d.target);
      var points = host == null ? null : pathPointsOf(host, frame);
      if (points == null || points.length < 2) return p;
      var t = frame / math.max(1, doc.frameRate);
      var u = d.value("start") + t / d.value("lap");
      u = d.value("loop").round() == 1 ? u.clamp(0.0, 1.0) : u % 1;
      var (point, angle) = _alongPath(points, u);
      var turned = d.value("turns").round() == 1;
      return p.copyWith(
          dx: point.dx - (e.x + e.width / 2),
          dy: point.dy - (e.y + e.height / 2),
          rotate: turned ? p.rotate + angle * 180 / math.pi : p.rotate);
    case MotionDeviceKind.lookAt:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var aim = switch (d.target) {
        lookAtCamera => _cameraCentre(doc, frame),
        lookAtPointer => live?.pointer,
        var id => _centreOf(doc, id, frame),
      };
      if (aim == null || d.target == e.id) return p;
      var me = Offset(e.x + e.width / 2 + p.dx, e.y + e.height / 2 + p.dy);
      // Facing right when it looks straight ahead, as it is drawn.
      var want = math.atan2(aim.dy - me.dy, aim.dx - me.dx) * 180 / math.pi +
          d.value("offset") -
          e.rotation;
      var smooth = d.value("smooth");
      return p.copyWith(
          rotate: p.rotate + (want - p.rotate) * (1 - smooth * 0.8));
    case MotionDeviceKind.squash:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var rate = math.max(1, doc.frameRate).toDouble();
      var q = _pulled(
          e,
          frame - 1,
          doc,
          live == null ? null : liveShifted(live, -1 / rate),
          devices,
          i - 1,
          instance);
      var vx = (p.dx - q.dx) * rate, vy = (p.dy - q.dy) * rate;
      var speed = math.sqrt(vx * vx + vy * vy);
      // Six hundred pixels a second, all by speed, squashes it most.
      var k = math.min(0.8, speed / 600 * d.value("bySpeed"));
      if (k <= 0) return p;
      return p.copyWith(values: {
        ...p.values,
        KeyframeChannel.squash: 1 + k * d.value("amount"),
        KeyframeChannel.squashAngle: math.atan2(vy, vx),
      });
    case MotionDeviceKind.followSound:
      var p = _pulled(e, frame, doc, live, devices, i - 1, instance);
      var peaks = motionSoundPeaks;
      if (peaks == null || d.target.isEmpty) return p;
      var t = frame / math.max(1, doc.frameRate);
      var level = channelLevelAt(doc, d.target, t, peaks,
              window: d.value("smooth") * 0.5) *
          d.value("amount");
      if (level <= 0) return p;
      return switch (d.value("moves").round()) {
        1 => p.copyWith(dy: p.dy - level * 40),
        2 => p.copyWith(rotate: p.rotate + level * 30),
        3 =>
          p.copyWith(opacity: (p.opacity * (1 - level * 0.5)).clamp(0.0, 1.0)),
        _ => p.copyWith(scale: p.scale * (1 + level * 0.45)),
      };
    default:
      // A look is not a pose device; it passes the pose on.
      return _pulled(e, frame, doc, live, devices, i - 1, instance);
  }
}

/// motionSoundPeaks is where Follow sound reads a recording's shape -- its
/// loudness along it -- by asset: the editor's, which reads them as they are
/// asked for. Null, as for a lone element drawn, follows nothing.
Float32List? Function(String assetId)? motionSoundPeaks;

/// _alongPath is the point [u] of the way along [points] (nought to one,
/// by length) and the way it heads there, in radians.
(Offset, double) _alongPath(List<Offset> points, double u) {
  var lengths = <double>[0];
  for (var i = 1; i < points.length; i++) {
    lengths.add(lengths.last + (points[i] - points[i - 1]).distance);
  }
  var want = u.clamp(0.0, 1.0) * lengths.last;
  for (var i = 1; i < points.length; i++) {
    if (lengths[i] >= want || i == points.length - 1) {
      var span = lengths[i] - lengths[i - 1];
      var f = span <= 0 ? 0.0 : (want - lengths[i - 1]) / span;
      var a = points[i - 1], b = points[i];
      return (
        Offset.lerp(a, b, f.clamp(0.0, 1.0))!,
        math.atan2(b.dy - a.dy, b.dx - a.dx)
      );
    }
  }
  return (points.first, 0);
}

/// _looking is how deep Look at is in asking where its targets are: two
/// elements looking at each other would ask for ever.
int _looking = 0;

/// _centreOf is the middle of element [id] on [frame], as it moves.
/// lookAtCamera is the target a Look at is given to face the camera.
const lookAtCamera = "@camera";

/// lookAtPointer is the target it is given to face the pointer, while it
/// is over the page (see LiveMotion.pointer).
const lookAtPointer = "@pointer";

/// PointerLive is nothing playing from its slots, with the pointer over
/// the page: what the stage hands the renderer for a Look at the pointer.
class PointerLive implements LiveMotion {
  @override
  final Offset? pointer;
  const PointerLive(this.pointer);

  @override
  double get clock => 0;

  @override
  MotionLive? of(String element) => null;
}

/// facesPointer is whether anything in [doc] looks at the pointer: only
/// then is the pointer handed to the renderer, and the stage drawn again
/// as it moves.
bool facesPointer(CanvasDocument doc) => [
      ...doc.elements,
      ...?doc.masterScene?.elements,
    ].any((e) => e.base.motion.devices.any((d) =>
        d.on &&
        d.kind == MotionDeviceKind.lookAt &&
        d.target == lookAtPointer));

/// _cameraCentre is the middle of what the scene's camera shows on
/// [frame], or of the page with none.
Offset? _cameraCentre(CanvasDocument doc, int frame) {
  if (_looking > 3) return doc.size.rect.center;
  _looking++;
  try {
    return sceneFraming(doc, frame)?.$2 ?? doc.size.rect.center;
  } finally {
    _looking--;
  }
}

Offset? _centreOf(CanvasDocument doc, String id, int frame) {
  var t = doc.elementById(id);
  if (t == null) return null;
  if (_looking > 3) return t.bounds.center;
  _looking++;
  try {
    return t.boundsWith(poseWithMotion(t, frame, doc)).center;
  } finally {
    _looking--;
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

/// motionModulated is [d] with what the modulators of [chain] add to its
/// knobs [t] seconds in (see modulation.dart): its LFOs, and its followers
/// of [doc]'s channels; as it is where none moves it.
MotionDevice motionModulated(MotionDevice d, List<MotionDevice> chain, double t,
    {CanvasDocument? doc}) {
  if (d.kind.params.isEmpty || d.id.isEmpty) return d;
  Map<String, double>? add;
  for (var l in chain) {
    if (!l.on || !l.modulates || l.mods.isEmpty) continue;
    double? v;
    for (var m in l.mods) {
      if (m.device != d.id || !d.kind.params.any((p) => p.id == m.param)) {
        continue;
      }
      v ??= switch (l.kind) {
        MotionDeviceKind.lfo => lfoValue(
            l.value("shape").round(),
            lfoRate(l.value,
                        bpm: doc?.audio.tempo ?? 120,
                        beatsPerBar: doc?.audio.beatsPerBar ?? 4) *
                    t +
                l.value("phase")),
        MotionDeviceKind.follower => _followed(l, t, doc),
        _ => 0.0,
      };
      // A macro's each by its own knob, nought to all the way.
      var by = l.kind == MotionDeviceKind.macro
          ? macroValue(l.value, m.from) * 2
          : v;
      (add ??= {})[m.param] = (add[m.param] ?? 0) + m.depth * by;
    }
  }
  if (add == null) return d;
  var next = d;
  for (var MapEntry(key: id, value: by) in add.entries) {
    next = next.withValue(id, modulated(d.kind.param(id), d.value(id), by));
  }
  return next;
}

/// _followed is how loud follower [l]'s channel is [t] seconds into
/// [doc], times its gain: nought to one.
double _followed(MotionDevice l, double t, CanvasDocument? doc) {
  var peaks = motionSoundPeaks;
  if (doc == null || peaks == null || l.target.isEmpty) return 0;
  return (channelLevelAt(doc, l.target, t, peaks,
              window: l.value("smooth") * 0.5) *
          l.value("gain"))
      .clamp(0.0, 1.0);
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
    if (!movesAtAll(this)) return boundsAt(frame);
    // An element reused is all of its instances.
    if (base.motion.instances case var set?) {
      Rect? all;
      for (var i = 0; i < set.count; i++) {
        var b = boundsWith(
            poseWithMotion(this, frame, doc, live: live, instance: i));
        all = all == null ? b : all.expandToInclude(b);
      }
      if (all != null) return all;
    }
    return boundsWith(poseWithMotion(this, frame, doc, live: live));
  }

  /// instanceAt is which of this element reused is at [point] on [frame],
  /// the last drawn first; null where none is, or it is placed once.
  int? instanceAt(Offset point, int frame, CanvasDocument doc,
      {LiveMotion? live}) {
    var set = base.motion.instances;
    if (set == null) return null;
    for (var i = set.count - 1; i >= 0; i--) {
      if (boundsWith(poseWithMotion(this, frame, doc, live: live, instance: i))
          .contains(point)) {
        return i;
      }
    }
    return null;
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
  return doc.scene.camera?.at(
      frame / math.max(1, doc.frames - 1), doc.size.rect,
      seconds: frame / math.max(1, doc.frameRate));
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

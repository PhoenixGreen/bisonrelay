import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

// motion_player.dart is the elements' slots played live: a clip launched
// from a slot, a cue, a trigger or another clip's Then, keeping the clock of
// the session in canvas_controller.dart.
//
// A launched element leaves its timeline, as an Ableton track does, and is
// drawn from its slots until Back to the timeline. Each layer plays one clip
// at a time; a clip launched on a layer starts from wherever the last left it
// (the carry), and one that ends holds its last frame or goes back to where
// it began, as it says. Pure: the controller hands it the document, the frame
// and the clock; the renderer reads it as a LiveMotion.

/// MotionSlotState is how an element's slot is doing, for its strip.
enum MotionSlotState { empty, stopped, queued, playing, stopping }

/// MotionPlayed is a clip played while recording: written onto the
/// timeline as a placement when the take is kept.
class MotionPlayed {
  final String element;
  final String clip;
  final int layer;
  final double start;
  double end;

  /// to is how far into the clip it had got: the whole of it, played out.
  double to;
  final bool loop;

  MotionPlayed(this.element, this.clip, this.layer, this.start,
      {required this.loop})
      : end = start,
        to = 0;
}

/// MotionEvent is something a step saw happen, for the controller: a
/// clip ending, or an element asking to go back to its timeline.
sealed class MotionEvent {
  final String element;
  const MotionEvent(this.element);
}

class MotionEnded extends MotionEvent {
  final MotionClip clip;
  final double at;
  const MotionEnded(super.element, this.clip, this.at);
}

class MotionBack extends MotionEvent {
  const MotionBack(super.element);
}

class _Layer {
  LivePlay? play;
  MotionPose? carry;

  /// fromTimeline is whether [carry] is where the timeline left the layer,
  /// no clip of the slots played on it yet: the first launched on it takes
  /// the layer over from the timeline, starting from rest rather than on
  /// top of it (Ken, 2026-11-08: an arrival placed and launched played on
  /// its own held first frame -- Pop at nothing, Slide in off the page).
  bool fromTimeline = false;

  /// next is the clip waiting to start at [nextAt]; "" a stop waiting.
  String? next;
  double nextAt = 0;
  MotionPlayed? taking;
}

class _Playing {
  final List<_Layer> layers = List.generate(motionLayers, (_) => _Layer());

  /// held are the clips whose slot is held down: gate and repeat.
  final Set<String> held = {};

  MotionLive get live => MotionLive(
      plays: [for (var l in layers) l.play],
      carry: [for (var l in layers) l.carry]);
}

/// motionKeyName is [k] as a clip's "Key pressed" trigger names it: Space,
/// Enter, or the key's own letter.
String motionKeyName(LogicalKeyboardKey k) => k == LogicalKeyboardKey.space
    ? "Space"
    : k == LogicalKeyboardKey.enter
        ? "Enter"
        : k.keyLabel.toUpperCase();

/// _elementIn is [id] among [doc]'s elements, or the master's drawn with
/// them -- a game's HUD plays its clips as a scene's elements do.
/// An id can be one copy of an element reused (see instanceKey): what that
/// copy plays alone, its element's.
CanvasElement? _elementIn(CanvasDocument doc, String id) {
  var at = id.indexOf("#");
  if (at > 0) id = id.substring(0, at);
  return doc.elementById(id) ??
      (doc.editingMaster
          ? null
          : doc.masterScene?.elements.where((e) => e.id == id).firstOrNull);
}

/// _elementsOf are [doc]'s elements, and the master's drawn with them.
Iterable<CanvasElement> _elementsOf(CanvasDocument doc) => [
      ...doc.elements,
      if (!doc.editingMaster) ...?doc.masterScene?.elements,
    ];

/// _FrozenLive is a MotionPlayer's plays as they were at one moment.
class _FrozenLive implements LiveMotion {
  @override
  final double clock;
  @override
  final Offset? pointer;
  final Map<String, MotionLive> _of;
  _FrozenLive(this.clock, this.pointer, this._of);

  @override
  MotionLive? of(String element) => _of[element];
}

class MotionPlayer implements LiveMotion {
  final Map<String, _Playing> _of = {};
  final List<MotionPlayed> _log = [];
  double _clock = 0;

  /// revision goes up at every step, so a painter knows to paint again.
  int revision = 0;

  @override
  double get clock => _clock;

  /// pointer is where the pointer is over the page: see LiveMotion.pointer.
  /// Set by the stage as it moves.
  @override
  Offset? pointer;

  @override
  MotionLive? of(String element) => _of[element]?.live;

  /// frozen is what is playing now, held as it is: for a scene being left,
  /// drawn as it was while the next one's clips start (see gameChange).
  LiveMotion frozen() => _FrozenLive(_clock, pointer,
      {for (var MapEntry(:key, :value) in _of.entries) key: value.live});

  /// offTimeline is whether any element has left its timeline for its
  /// slots: what Back to the timeline lights for.
  bool get offTimeline => _of.isNotEmpty;

  bool isOff(String element) => _of.containsKey(element);

  /// playing is whether anything is playing or waiting to: the clock has
  /// to keep going, and the canvas be painted.
  bool get playing => _of.values.any((p) => p.layers
      .any((l) => l.next != null || (l.play != null && !l.play!.ended)));

  /// slotState is how [clip] of [element] is doing.
  MotionSlotState slotState(String element, MotionClip? clip) {
    if (clip == null) return MotionSlotState.empty;
    var p = _of[element];
    if (p == null) return MotionSlotState.stopped;
    for (var l in p.layers) {
      if (l.next == clip.id) return MotionSlotState.queued;
    }
    for (var l in p.layers) {
      if (l.play case var play? when play.clip == clip.id && !play.ended) {
        return l.next == ""
            ? MotionSlotState.stopping
            : MotionSlotState.playing;
      }
    }
    return MotionSlotState.stopped;
  }

  /// launch queues [clip] of [element] to start at [at]: at once, if that is
  /// now. The element leaves its timeline, carrying on from where the
  /// timeline has it on [frame].
  void launch(
      CanvasDocument doc, int frame, String element, String clip, double at) {
    var e = _elementIn(doc, element);
    var c = e?.base.motion.clip(clip);
    if (e == null || c == null || c.isSound || c.kind == MotionKind.model) {
      return;
    }
    var p = _of[element] ??= _enter(doc, frame, e);
    var l = p.layers[c.layer.clamp(0, motionLayers - 1)];
    l.next = clip;
    l.nextAt = at;
  }

  /// press is a slot pressed: what it does is the clip's launch mode --
  /// started, or, toggled on a clip playing, stopped.
  void press(
      CanvasDocument doc, int frame, String element, String clip, double at) {
    var c = _elementIn(doc, element)?.base.motion.clip(clip);
    if (c == null) return;
    var state = slotState(element, c);
    if (c.launch == ClipLaunch.toggle &&
        (state == MotionSlotState.playing || state == MotionSlotState.queued)) {
      stop(element, layer: c.layer, at: at);
      return;
    }
    launch(doc, frame, element, clip, at);
    if (c.launch == ClipLaunch.gate || c.launch == ClipLaunch.repeat) {
      _of[element]?.held.add(clip);
    }
  }

  /// release is a slot let go: a gate stops at once; a repeat repeats no
  /// more.
  void release(CanvasDocument doc, String element, String clip, double now) {
    var p = _of[element];
    if (p == null || !p.held.remove(clip)) return;
    var c = _elementIn(doc, element)?.base.motion.clip(clip);
    if (c?.launch == ClipLaunch.gate) stop(element, layer: c!.layer, at: now);
  }

  /// stop stops what [element] plays -- on [layer], or every one -- at [at].
  /// It stays off its timeline, where it was left.
  void stop(String element, {int? layer, required double at}) {
    var p = _of[element];
    if (p == null) return;
    var only = layer?.clamp(0, motionLayers - 1);
    for (var (i, l) in p.layers.indexed) {
      if (only != null && i != only) continue;
      // A launch still waiting is called off; what plays stops at [at].
      if (l.next case var n? when n.isNotEmpty) l.next = null;
      if (l.play != null && !l.play!.ended) {
        l.next = "";
        l.nextAt = at;
      }
    }
  }

  void stopAll(double at) {
    for (var id in _of.keys) {
      stop(id, at: at);
    }
  }

  /// halt stops everything at [now], each element left where it is -- a
  /// Stop on a timeline being played over.
  void halt(CanvasDocument doc, int frame, double now) {
    stopAll(now);
    step(doc, frame, now);
    for (var p in _of.values) {
      p.held.clear();
      for (var l in p.layers) {
        l.next = null;
      }
    }
  }

  /// isPlaying is whether [element] has a clip playing, or about to --
  /// one of [only], where they are given.
  bool isPlaying(String element, {Set<String>? only}) =>
      _of[element]?.layers.any((l) =>
          (l.next != null &&
              l.next!.isNotEmpty &&
              (only?.contains(l.next) ?? true)) ||
          (l.play != null &&
              !l.play!.ended &&
              (only?.contains(l.play!.clip) ?? true))) ??
      false;

  /// leave sends [element] back to its timeline; clear, every element.
  void leave(String element) => _of.remove(element);
  void clear() => _of.clear();

  /// fire launches every clip that starts on [kind] -- of [target], where it
  /// names one -- at [at]. A touch with no target is the clip's own element
  /// touched: [target] is the element a player touched. A count's trigger
  /// starts on any change of it, or, with an amount, as [value] reaches it.
  void fire(CanvasDocument doc, int frame, ClipTriggerKind kind, String target,
      double at,
      {double? value}) {
    bool counted(ClipTrigger t) =>
        kind != ClipTriggerKind.count || t.amount == 0 || t.amount == value;
    for (var e in _elementsOf(doc)) {
      for (var c in e.base.motion.clips) {
        if (c.triggers.any((t) =>
            t.kind == kind &&
            counted(t) &&
            (t.target.isEmpty
                ? kind != ClipTriggerKind.touched ||
                    e.id == target ||
                    target.startsWith("${e.id}#")
                : t.target == target))) {
          // One copy touched plays it alone, by its own key.
          var copy =
              kind == ClipTriggerKind.touched && target.startsWith("${e.id}#");
          launch(doc, frame, copy ? target : e.id, c.id, at);
        }
      }
    }
  }

  /// step plays on to [now]: launches and stops waiting for it happen, and
  /// clips that have played out end -- their Then followed. With
  /// [recording], what starts is written down for the timeline.
  List<MotionEvent> step(CanvasDocument doc, int frame, double now,
      {bool recording = false}) {
    _clock = now;
    revision++;
    var events = <MotionEvent>[];
    if (_of.isEmpty) return events;
    MotionScene? scene;
    for (var id in [..._of.keys]) {
      var p = _of[id]!;
      var e = _elementIn(doc, id);
      if (e == null) {
        _of.remove(id);
        continue;
      }
      var motion = e.base.motion;
      var box = boxOf(e);
      scene ??= motionSceneOf(doc, frame);
      var replaces = motion.clips.any((c) => c.kind == MotionKind.camera);
      for (var (i, l) in p.layers.indexed) {
        // Ended first: a clip that played out before a launch waiting for
        // the same moment hands it the pose it left.
        _end(id, p, l, motion, box, scene, replaces, now, events);
        if (l.next case var next? when now >= l.nextAt - 1e-9) {
          var at = l.nextAt;
          var here =
              livePose(motion, p.live, i, at, box, scene, replaces: replaces);
          var was = l.play == null ? null : motion.clip(l.play!.clip);
          // Started again while it plays: from where it started, not from
          // part way through itself -- a bump over a bump would end bigger.
          var again = was != null && !l.play!.ended && was.id == next;
          _close(l, was, at);
          if (next.isEmpty) {
            if (was != null && !l.play!.ended && was.after == ClipHold.last) {
              l.carry = here;
            }
            l.play = null;
          } else {
            if (!again) l.carry = l.fromTimeline ? null : here;
            l.fromTimeline = false;
            l.play = LivePlay(next, at);
            if (recording) {
              var c = motion.clip(next);
              var taken = MotionPlayed(id, next, i, at, loop: c?.loop ?? false);
              l.taking = taken;
              _log.add(taken);
            }
          }
          l.next = null;
          _end(id, p, l, motion, box, scene, replaces, now, events);
        }
      }
    }
    // Clips that start when another ends.
    for (var ev in events) {
      if (ev is MotionEnded) {
        fire(doc, frame, ClipTriggerKind.clipEnds, ev.clip.id, ev.at);
      }
    }
    return events;
  }

  /// _playedFor is how long [c] plays once launched: its length at its
  /// speed -- or, reused, until the last of its copies is through it, each
  /// later by its start and at its own speed (see liveForCopy).
  static double _playedFor(MotionClip c, ElementMotion motion) {
    var own = c.length / math.max(0.01, c.speed);
    var set = motion.instances;
    if (set == null) return own;
    var longest = own;
    for (var i = 0; i < set.count; i++) {
      longest = math.max(
          longest, set.startOf(i) + own / math.max(0.05, set.speedOf(i)));
    }
    return longest;
  }

  void _end(String id, _Playing p, _Layer l, ElementMotion motion, Rect box,
      MotionScene scene, bool replaces, double now, List<MotionEvent> events) {
    var play = l.play;
    if (play == null || play.ended) return;
    var c = motion.clip(play.clip);
    if (c == null) {
      l.play = null;
      return;
    }
    if (c.loop) return;
    // One copy's own play (a coin touched: "el#copy") is that copy's
    // alone, played as it is: done at its own length, not the slowest
    // copy's.
    var end = play.start +
        (id.contains("#")
            ? c.length / math.max(0.01, c.speed)
            : _playedFor(c, motion));
    if (now < end - 1e-9) return;
    if (c.after == ClipHold.last) {
      l.carry = clipPose(c, c.length, box, scene,
          from: replaces || l.carry == null ? MotionPose.rest : l.carry!);
    }
    l.play = play.done();
    if (l.taking case var t?) {
      t
        ..end = end
        ..to = c.length;
      l.taking = null;
    }
    events.add(MotionEnded(id, c, end));
    // Held down, a repeat goes again; otherwise what it says comes next.
    if (c.launch == ClipLaunch.repeat && p.held.contains(c.id)) {
      if (l.next == null) {
        l.next = c.id;
        l.nextAt = end;
      }
      return;
    }
    switch (c.then) {
      case ClipThen.next:
        var i = motion.slots.indexOf(c.id);
        var after = i < 0 ? null : motion.slot(i + 1);
        if (after != null) _queue(p, after, end);
      case ClipThen.play:
        if (motion.clip(c.thenClip) case var other?) _queue(p, other, end);
      case ClipThen.back:
        events.add(MotionBack(id));
      case ClipThen.nothing || ClipThen.stop:
        break;
    }
  }

  void _queue(_Playing p, MotionClip c, double at) {
    if (c.isSound || c.kind == MotionKind.model) return;
    var l = p.layers[c.layer.clamp(0, motionLayers - 1)];
    l.next = c.id;
    l.nextAt = at;
  }

  void _close(_Layer l, MotionClip? c, double at) {
    var t = l.taking;
    if (t == null) return;
    t.end = at;
    var play = l.play;
    t.to = c == null || play == null ? 0 : liveTime(c, play, at);
    l.taking = null;
  }

  /// _enter is [e] leaving its timeline: each layer carrying on from where
  /// the timeline has it.
  _Playing _enter(CanvasDocument doc, int frame, CanvasElement e) {
    var p = _Playing();
    var motion = e.base.motion;
    var t = frame / math.max(1, doc.frameRate);
    var times = motionTimesOf(doc);
    var scene = motionSceneOf(doc, frame);
    var replaces = motion.clips.any((c) => c.kind == MotionKind.camera);
    for (var (i, l) in p.layers.indexed) {
      // Where it was left: what has played, not a clip yet to start held
      // at its first frame -- an arrival waiting would keep it hidden.
      var pose = layerPose(motion, i, t, boxOf(e), times, scene,
          replaces: replaces, holdBefore: false);
      l.carry = pose.isRest ? null : pose;
      l.fromTimeline = true;
    }
    return p;
  }

  /// takeLog is what was recorded, those still playing taken to [now]; the
  /// log emptied.
  List<MotionPlayed> takeLog(CanvasDocument doc, double now) {
    for (var p in _of.values) {
      for (var l in p.layers) {
        var play = l.play;
        if (l.taking == null || play == null) continue;
        var e =
            doc.elements.where((e) => e.id == l.taking!.element).firstOrNull;
        _close(l, e?.base.motion.clip(play.clip), now);
      }
    }
    var log = [..._log];
    _log.clear();
    return log;
  }
}

/// writeMotionTakes is [doc] with [takes] written onto its timeline, each a
/// placement of the clip where it was played, for as long as it was. One
/// played out whole is its own; one stopped part way is cut there.
CanvasDocument writeMotionTakes(
    CanvasDocument doc, List<MotionPlayed> takes, String Function() newId) {
  var next = doc;
  for (var t in takes) {
    var e = next.elementById(t.element);
    var c = e?.base.motion.clip(t.clip);
    if (e == null || c == null || t.end - t.start < 0.02) continue;
    var whole = !t.loop && t.to >= c.length - 1e-6;
    var p = ClipPlacement(
      id: newId(),
      clip: t.clip,
      layer: t.layer,
      start: t.start,
      length: t.end - t.start,
      to: t.loop || whole ? null : math.max(0.02, t.to),
    );
    next = next.withElement(e.withBase(motion: e.base.motion.withPlacement(p)));
  }
  return next;
}

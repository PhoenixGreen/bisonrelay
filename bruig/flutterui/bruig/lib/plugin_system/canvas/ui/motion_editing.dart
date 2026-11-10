import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart' show freeId;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// motion_editing.dart is what the timeline, the slots and the Animation
// panel do to an element's clips: make, place, move, stretch, cut, pin and
// remove. Each changes the element's ElementMotion through the controller, so
// it is undone as any change is. A drag is transient until its end: the
// caller opens the interaction and closes it.

int _seq = 0;

/// motionId is a new id for a clip or a placement.
String motionId(String prefix) =>
    "$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}";

extension MotionEditing on CanvasController {
  /// motionOf is [element]'s motion, or none.
  ElementMotion motionOf(String element) =>
      document.elementById(element)?.base.motion ?? ElementMotion.none;

  /// setMotion writes [element]'s motion.
  void setMotion(String element, ElementMotion motion,
      {bool transient = false}) {
    var e = document.elementById(element);
    if (e == null) return;
    // Its last clip taken out, it keeps its channel: see ElementMotion.kept.
    if (motion.isEmpty && !motion.kept && e.base.motion.channelled) {
      motion = motion.copyWith(kept: true);
    }
    replaceElement(e.withBase(motion: motion), transient: transient);
  }

  /// motionDevicesOf is [element]'s motion devices, in the order they run
  /// (its pose devices, then its looks: see motionDevicesInOrder), each with
  /// its id.
  List<MotionDevice> motionDevicesOf(String element) =>
      motionDevicesInOrder(withMotionDeviceIds(motionOf(element).devices));

  /// setMotionDevices writes [element]'s motion devices.
  void setMotionDevices(String element, List<MotionDevice> devices,
          {bool transient = false}) =>
      setMotion(element, motionOf(element).copyWith(devices: devices),
          transient: transient);

  /// bakeMotionDevice turns what pose device [device] of [element] does
  /// into keys: a clip over the whole scene, on a layer of its own, of how
  /// far it moves, turns and sizes the element each frame -- and the device
  /// switched off, the prototype's "Bake into keys" (for an EPUB, which plays
  /// keys). The clip is at the start of the chain, so what is left of the
  /// device now has it too. Null when done; otherwise why not.
  String? bakeMotionDevice(String element, String device) {
    var e = document.elementById(element);
    if (e == null) return "It is gone";
    var m = e.base.motion;
    var poses = m.poseDevices;
    var k = poses.indexWhere((d) => d.id == device);
    if (k < 0)
      return "Only a device that moves it can be baked, while it is on";
    var rate = math.max(1, document.frameRate);
    var frames = math.max(2, document.frames);
    var end = (frames - 1) / rate;
    // Free all the way through: a clip on a layer gives way to the next one
    // to start on it.
    int? layer;
    for (var l = motionLayers - 1; l >= 0; l--) {
      if (!m.placed.any((p) => p.layer == l)) {
        layer = l;
        break;
      }
    }
    if (layer == null) {
      return "Every layer has clips on it: empty one to bake into";
    }
    var samples = {for (var p in MotionProp.values) p: <double>[]};
    for (var f = 0; f < frames; f++) {
      var before = poseWithMotion(e, f, document, upto: k);
      var after = poseWithMotion(e, f, document, upto: k + 1);
      double ratio(double a, double b) => a.abs() < 1e-9 ? 1 : b / a;
      samples[MotionProp.x]!.add(after.dx - before.dx);
      samples[MotionProp.y]!.add(after.dy - before.dy);
      samples[MotionProp.turn]!.add(after.rotate - before.rotate);
      samples[MotionProp.scale]!.add(ratio(before.scale, after.scale));
      samples[MotionProp.opacity]!.add(ratio(before.opacity, after.opacity));
    }
    var keys = <MotionProp, List<MotionKey>>{};
    for (var MapEntry(key: prop, value: v) in samples.entries) {
      var eps =
          prop == MotionProp.scale || prop == MotionProp.opacity ? 0.002 : 0.05;
      if (v.every((x) => (x - prop.rest).abs() < eps)) continue;
      keys[prop] = [
        for (var i in keptSamples(v, eps))
          MotionKey(i / rate, MotionNumber(v[i]))
      ];
    }
    if (keys.isEmpty) return "It moves nothing here to bake";
    var d = poses[k];
    var id = freeId(m, "baked-${d.kind.name}");
    var clip = MotionClip.ofKind(id, MotionKind.action,
            name: "Baked ${d.kind.label.toLowerCase()}", layer: layer)
        .copyWith(
      length: math.max(1 / rate, end),
      keys: keys,
      before: ClipHold.first,
      after: ClipHold.last,
    );
    var placement =
        ClipPlacement(id: freeId(m, "$id-p"), clip: id, layer: layer, start: 0);
    var motion = m.withClip(clip).copyWith(
      placed: [...m.placed, placement],
      devices: [
        for (var x in m.devices) x.id == device ? x.switched(false) : x
      ],
    );
    beginInteraction();
    setMotion(element, motion, transient: true);
    endInteraction();
    return null;
  }

  /// addMotionDevice puts a [kind] on [element]: last of its side -- the
  /// last pose device, before the drawing, or the last look -- and returns
  /// its id.
  String addMotionDevice(String element, MotionDeviceKind kind) {
    var devices =
        withMotionDeviceIds([...motionDevicesOf(element), MotionDevice(kind)]);
    setMotionDevices(element, motionDevicesInOrder(devices));
    return devices.last.id;
  }

  /// removeMotionDevice takes device [id] off [element].
  void removeMotionDevice(String element, String id) =>
      setMotionDevices(element, [
        for (var d in motionDevicesOf(element))
          if (d.id != id) d
      ]);

  /// moveMotionDevice moves device [id] [by] places among those on its
  /// side of the drawing -- it never crosses it (rule 1).
  void moveMotionDevice(String element, String id, int by) {
    var all = motionDevicesOf(element);
    var d = all.where((x) => x.id == id).firstOrNull;
    if (d == null) return;
    var side = [
      for (var x in all)
        if (x.side == d.side) x
    ];
    var i = side.indexOf(d), j = i + by;
    if (j < 0 || j >= side.length || by == 0) return;
    side.insert(j, side.removeAt(i));
    setMotionDevices(element, [
      if (d.side == MotionDeviceSide.look)
        for (var x in all)
          if (x.side == MotionDeviceSide.pose) x,
      ...side,
      if (d.side == MotionDeviceSide.pose)
        for (var x in all)
          if (x.side == MotionDeviceSide.look) x,
    ]);
  }

  /// setInstances writes [element]'s instances: null places it once again.
  void setInstances(String element, InstanceSet? set,
      {bool transient = false}) {
    var m = motionOf(element);
    setMotion(
        element,
        set == null
            ? m.copyWith(clearInstances: true)
            : m.copyWith(instances: set),
        transient: transient);
  }

  /// _stepOf is how far apart [element]'s instances are laid: half as far
  /// again as it is big.
  double _stepOf(String element) {
    var e = document.elementById(element);
    if (e == null) return 60;
    return math.max(e.base.width, e.base.height) * 1.5;
  }

  /// reuseElement makes [element] [count] instances, in a line to its
  /// right.
  void reuseElement(String element, int count) => setInstances(
      element,
      (motionOf(element).instances ?? const InstanceSet())
          .withCount(count, gap: _stepOf(element)));

  /// layOutInstances places [element]'s instances by [layout].
  void layOutInstances(String element, InstanceLayout layout) {
    var set = motionOf(element).instances;
    if (set == null) return;
    setInstances(
        element,
        set.laidOut(layout,
            gap: _stepOf(element),
            columns: math.max(1, math.sqrt(set.count).ceil())));
  }

  /// spanOf is where placement [id] plays, its pins followed.
  ClipSpan? spanOf(String id) => motionTimesOf(document).span(id);

  /// secondsAt is [frame] in seconds; frameAt the frame at [seconds].
  double secondsAt(int frame) => frame / math.max(1, document.frameRate);
  int frameAt(double seconds) =>
      (seconds * math.max(1, document.frameRate)).round();

  /// newClip makes a clip of [preset] -- or, with none, an empty one of
  /// [kind] -- for [element], and puts it in slot [slot] if one is given.
  /// Its id.
  String newClip(String element,
      {MotionPreset? preset,
      MotionKind kind = MotionKind.action,
      MotionWay? way,
      String target = "",
      int layer = 0,
      int? slot}) {
    var id = motionId("c");
    var clip = preset != null
        ? preset.clip(id, way: way, target: target, layer: layer)
        : MotionClip.ofKind(id, kind, layer: layer, name: kind.label);
    var m = motionOf(element).withClip(clip);
    if (slot != null) m = m.inSlot(slot, id);
    setMotion(element, m);
    return id;
  }

  /// placeClip places [clip] of [element] on the timeline at [seconds], on
  /// [layer] -- its own layer if none. The placement's id.
  String placeClip(String element, String clip,
      {required double seconds, int? layer}) {
    var m = motionOf(element);
    var c = m.clip(clip);
    if (c == null) return "";
    var id = motionId("p");
    setMotion(
        element,
        m.withPlacement(ClipPlacement(
            id: id,
            clip: clip,
            layer: c.isSound ? soundLayer : (layer ?? c.layer),
            start: math.max(0, seconds))));
    return id;
  }

  /// copyClipTo is [clip] of [from] copied to [to], as its own clip there --
  /// a clip that moves from where an element is works on any -- in its
  /// first empty slot if it has one. The new clip's id, or null where it
  /// cannot go: a model's own animation stays with its model.
  String? copyClipTo(String from, String clip, String to) {
    var c = motionOf(from).clip(clip);
    if (c == null || c.kind == MotionKind.model) return null;
    var id = motionId("c");
    var m = motionOf(to).withClip(c.copyWith(id: id, triggers: const []));
    // Its first empty slot: there is always one, past the last.
    var free = 0;
    while (m.slot(free) != null) {
      free++;
    }
    m = m.inSlot(free, id);
    setMotion(to, m);
    return id;
  }

  ClipPlacement? _placement(String element, String id) =>
      motionOf(element).placement(id);

  void _put(String element, ClipPlacement p, {bool transient = false}) =>
      setMotion(element, motionOf(element).withPlacement(p),
          transient: transient);

  /// movePlacement moves [id] to start at [seconds], on [layer]. Moved by
  /// hand, it lets go of its pins: it stays where it is put. Whether it let
  /// go of any.
  bool movePlacement(String element, String id, double seconds,
      {int? layer, bool transient = false}) {
    var p = _placement(element, id);
    var span = spanOf(id);
    if (p == null || span == null) return false;
    var pinned = p.startPin != null || p.endPin != null;
    _put(
        element,
        p.copyWith(
          start: math.max(0, seconds),
          layer: layer,
          // Its length kept as it was being played, pins or none.
          length: p.endPin != null ? () => span.length : null,
          startPin: () => null,
          endPin: () => null,
        ),
        transient: transient);
    return pinned;
  }

  /// stretchPlacement moves [id]'s start or end to [seconds]: a one-shot is
  /// retimed to fill it, a loop repeats to. The other end stays put; the
  /// end moved lets go of its pin.
  void stretchPlacement(String element, String id,
      {double? start, double? end, bool transient = false}) {
    var p = _placement(element, id);
    var span = spanOf(id);
    if (p == null || span == null) return;
    if (end != null) {
      _put(
          element,
          p.copyWith(
              start: span.start,
              startPin: () => p.startPin,
              length: () => math.max(0.05, end - span.start),
              endPin: () => null),
          transient: transient);
    } else if (start != null) {
      var s = math.min(start, span.end - 0.05).clamp(0.0, 1e9);
      _put(
          element,
          p.copyWith(
              start: s,
              startPin: () => null,
              length: p.endPin != null ? null : () => span.end - s),
          transient: transient);
    }
  }

  /// cutPlacement cuts [id] in two at [seconds]: each part plays its own
  /// stretch of the clip, the second carrying on where the first stops.
  /// Whatever followed it follows the second part. The new part's id.
  String? cutPlacement(String element, String id, double seconds) {
    var m = motionOf(element);
    var p = m.placement(id);
    var span = spanOf(id);
    var c = p == null ? null : m.clip(p.clip);
    if (p == null || span == null || c == null) return null;
    if (seconds <= span.start + 0.02 || seconds >= span.end - 0.02) return null;
    var mid = span.clipTime(c, seconds);
    var second = motionId("p");
    var first = p.copyWith(
        start: span.start,
        startPin: () => p.startPin,
        length: () => seconds - span.start,
        to: c.loop ? null : () => mid,
        endPin: () => null);
    var rest = ClipPlacement(
      id: second,
      clip: p.clip,
      layer: p.layer,
      start: seconds,
      length: span.end - seconds,
      from: mid,
      to: c.loop ? null : span.to,
      endPin: p.endPin,
    );
    var placed = [
      for (var x in m.placed)
        if (x.id == id)
          first
        else if (x.startPin == ClipPin(PinKind.after, target: id))
          x.copyWith(startPin: () => ClipPin(PinKind.after, target: second))
        else
          x,
      rest,
    ];
    setMotion(element, m.copyWith(placed: placed));
    return second;
  }

  /// removePlacement takes [id] off the timeline. Anything pinned to its end
  /// keeps the time it had rather than jumping.
  void removePlacement(String element, String id) {
    var times = motionTimesOf(document);
    var doc = document;
    var pin = ClipPin(PinKind.after, target: id);
    for (var e in doc.elements) {
      var m = e.base.motion;
      if (m.placed.isEmpty) continue;
      var changed = false;
      var placed = [
        for (var p in m.placed)
          if (p.id == id && e.id == element)
            null
          else if (p.startPin == pin || p.endPin == pin)
            () {
              changed = true;
              var s = times.span(p.id);
              if (s == null) return p;
              return p.copyWith(
                start: s.start,
                length: () => s.length,
                startPin: () => p.startPin == pin ? null : p.startPin,
                endPin: () => p.endPin == pin ? null : p.endPin,
              );
            }()
          else
            p,
      ].whereType<ClipPlacement>().toList();
      if (e.id == element || changed) {
        doc = doc.withElement(e.withBase(motion: m.copyWith(placed: placed)));
      }
    }
    // An element's own arrival or way out taken off the timeline is that
    // animation gone: its clip, and its setting back to None.
    var owner = document.elementById(element);
    var gone = owner?.base.motion.placement(id);
    var clip = gone == null ? null : owner!.base.motion.clip(gone.clip);
    if (clip != null &&
        clip.inside["own"] == true &&
        (clip.kind == MotionKind.arrive || clip.kind == MotionKind.leave)) {
      if (doc.elementById(element) case var now?) {
        doc = doc.withElement(withoutOwnPreset(now, clip.kind));
      }
    }
    apply(doc);
  }

  /// pinPlacement pins [id]'s start, or its end, to [pin] -- null lets go,
  /// keeping the time it had.
  void pinPlacement(String element, String id, ClipPin? pin,
      {bool end = false}) {
    var p = _placement(element, id);
    var span = spanOf(id);
    if (p == null || span == null) return;
    _put(
        element,
        end
            ? p.copyWith(
                endPin: () => pin,
                length: pin == null ? () => span.length : null)
            : p.copyWith(startPin: () => pin, start: span.start));
  }

  /// addMarker puts a marker on the timeline at [frame], or leaves the one
  /// there. Its id.
  String addMarker(int frame, {String label = ""}) {
    var doc = document;
    if (doc.actions.where((a) => a.frame == frame).firstOrNull case var a?) {
      return markerKey(a);
    }
    var id = motionId("m");
    var count = doc.actions.length + 1;
    apply(doc.copyWith(
        actions: [
      ...doc.actions,
      TimelineAction(
          id: id,
          frame: frame,
          kind: TimelineActionKind.locator,
          label: label.isEmpty ? "Marker $count" : label),
    ]..sort((a, b) => a.frame.compareTo(b.frame))));
    return id;
  }

  /// editMotionClip replaces [clip] of [element] with what [change] makes of it.
  void editMotionClip(
      String element, String clip, MotionClip Function(MotionClip) change,
      {bool transient = false}) {
    var m = motionOf(element);
    var c = m.clip(clip);
    if (c == null) return;
    setMotion(element, m.withClip(change(c)), transient: transient);
  }

  /// moveMotionSlot moves the clip in slot [from] of [element] to slot [to]
  /// of [into] -- swapping with what is there, on the same element -- or,
  /// with [copy] or onto another element, puts a copy of it there. Whether
  /// anything moved.
  bool moveMotionSlot(String element, int from, String into, int to,
      {bool copy = false}) {
    var m = motionOf(element);
    var c = m.slot(from);
    if (c == null || (element == into && from == to)) return false;
    if (element == into && !copy) {
      var there = m.slots.length > to ? m.slots[to] : "";
      setMotion(element, m.inSlot(to, c.id).inSlot(from, there));
      return true;
    }
    if (c.kind == MotionKind.model && element != into) return false;
    var id = motionId("c");
    var target = element == into ? m : motionOf(into);
    setMotion(
        into,
        target
            .withClip(
                c.copyWith(id: id, triggers: element == into ? null : const []))
            .inSlot(to, id));
    return true;
  }

  /// linkMotionSlot links slot row [row] of [element]'s motion to its own
  /// sound in the same row, or unlinks it: linked, pressing either launches
  /// both (Ken, 2026-11-10).
  void linkMotionSlot(String element, int row, bool linked) {
    var m = motionOf(element);
    if (m.isLinked(row) == linked) return;
    setMotion(element, m.linkedAs(row, linked));
  }

  /// clearMotionSlot empties slot [slot] of [element]: the clip stays,
  /// where it is on the timeline, unless it is nowhere else -- then it goes.
  void clearMotionSlot(String element, int slot) {
    var m = motionOf(element);
    var c = m.slot(slot);
    if (c == null) return;
    var next = m.inSlot(slot, "");
    if (!next.slots.contains(c.id) && !next.placed.any((p) => p.clip == c.id)) {
      next = next.copyWith(clips: [
        for (var x in next.clips)
          if (x.id != c.id) x
      ]);
    }
    setMotion(element, next);
  }

  /// fadeLayers moves [element]'s cross-fader to [to], 0 to 1.
  void fadeLayers(String element, double to, {bool transient = false}) =>
      setMotion(element, motionOf(element).faded(to), transient: transient);

  /// pinLayer pins [layer] of [element] on its cross-fader, or unpins it.
  void pinLayer(String element, int layer, bool pinned) {
    var m = motionOf(element);
    var next = m.pinnedAs(layer, pinned);
    if (!identical(next, m)) setMotion(element, next);
  }

  /// setMotionAmount sets how much of [element]'s motion is seen, 0 to 1.
  void setMotionAmount(String element, double amount,
          {bool transient = false}) =>
      setMotion(
          element, motionOf(element).copyWith(amount: amount.clamp(0.0, 1.0)),
          transient: transient);

  /// switchMotion switches [element]'s motion on or off: the ◆.
  void switchMotion(String element, bool on) =>
      setMotion(element, motionOf(element).copyWith(off: !on));

  /// weighLayer sets how much [layer] of [element] counts, 0 to 1.
  void weighLayer(String element, int layer, double weight,
      {bool transient = false}) {
    var m = motionOf(element);
    var w = [...m.weights];
    while (w.length < motionLayers) {
      w.add(1);
    }
    w[layer] = weight.clamp(0.0, 1.0);
    setMotion(element, m.copyWith(weights: w), transient: transient);
  }
}

/// everyMotion is [doc] with [change] made to every element's motion that
/// has any: cue rows put in or taken away, for one.
CanvasDocument everyMotion(
    CanvasDocument doc, ElementMotion Function(ElementMotion m) change) {
  var next = doc;
  for (var e in doc.elements) {
    var m = e.base.motion;
    if (m.isEmpty) continue;
    var changed = change(m);
    if (!identical(changed, m)) {
      next = next.withElement(e.withBase(motion: changed));
    }
  }
  return next;
}

/// keptSamples are the frames of [v] to keep as keys: the first, the last,
/// and each where a straight line from the last kept one would miss by more
/// than [eps] -- so a steady move is two keys, and a wiggle all it needs.
List<int> keptSamples(List<double> v, double eps) {
  if (v.length <= 2) return [for (var i = 0; i < v.length; i++) i];
  var kept = [0];
  var from = 0;
  for (var i = 2; i < v.length; i++) {
    // Would a line from the last kept to i pass near every one between?
    var ok = true;
    for (var j = from + 1; j < i; j++) {
      var u = (j - from) / (i - from);
      var line = v[from] + (v[i] - v[from]) * u;
      if ((v[j] - line).abs() > eps) {
        ok = false;
        break;
      }
    }
    if (!ok) {
      kept.add(i - 1);
      from = i - 1;
    }
  }
  kept.add(v.length - 1);
  return kept;
}

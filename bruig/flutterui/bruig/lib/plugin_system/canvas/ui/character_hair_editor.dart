import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_hair_shape.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';

// character_hair_editor.dart is a sketch's hair strokes shaped on the
// canvas -- see character_hair.dart. A stroke is picked by clicking it.
// The picked one has its root, which drags it round the scalp; its tip,
// which sets how long it is and how it leans; and a ring at its root,
// middle and tip, a knob on its edge, dragged out or in to make it wider or
// narrower there; and a wide ring round its root, which turns it all the
// way round about where it grows, keeping its shape -- as moving it by its
// root does -- with a knob on it that makes the whole stroke bigger or
// smaller, longer and wider together; and its curve's two handles, off the
// root and off the tip, which bend it as a pen tool's do. Pressing on the
// scalp where there is no stroke grows a new one there -- of the group
// that part of the head grows -- and dragging out sets its tip. Delete
// takes the picked one away.

/// HairGrab is what of a stroke is taken hold of.
enum HairGrab { body, root, tip, width0, width1, width2, turn, scale, bend0, bend1 }

/// HairHold is a stroke taken hold of, and what of it.
class HairHold {
  final int index;
  final HairGrab grab;
  const HairHold(this.index, this.grab);
}

Offset _turned(Offset v, double degrees) {
  var t = degrees * math.pi / 180;
  var c = math.cos(t), s = math.sin(t);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// HairView is a sketch's hair strokes where they are on the page.
class HairView {
  final CharacterElement element;
  final CharacterPlacement placed;
  final HeadView head;
  final HairRig hair;

  /// shapes is each stroke as seen, in the head's own space.
  final List<HairStrokeShape> shapes;

  HairView._(this.element, this.placed, this.head, this.hair, this.shapes);

  static HairView? of(CharacterElement e, int frame,
      {int frameRate = 12, CanvasDocument? document}) {
    var hair = e.dna.hairRig;
    if (hair == null || e.body.inThreeD) return null;
    var placed = CharacterPlacement.of(e, frame,
        frameRate: frameRate, document: document);
    var (_, face) = e.performanceAt(e.style.frameOf(frame), frameRate);
    var rig = placed.rig;
    var r = rig.headRadii;
    // As the painter sees it: turned with the face, nodded with it.
    var head = HeadView(
        r.width,
        r.height,
        (face[FaceControl.turn] + rig.yaw) * math.pi / 180,
        rig.tilt * math.pi / 180,
        nod: r.height * 0.35 * math.sin(face[FaceControl.nod] * math.pi / 180));
    return HairView._(e, placed, head, hair, [
      for (var s in hair.strokes)
        hairStrokeShape(s, hair.lookOf(s.group), head),
    ]);
  }

  double get _scale => placed.rig.headScale;

  /// toDrawing and toHead take a point between the head's own space and
  /// the drawing's.
  Offset toDrawing(Offset p) =>
      placed.rig.headCentre + _turned(p * _scale, placed.rig.headTurn);
  Offset toHead(Offset d) =>
      _turned(d - placed.rig.headCentre, -placed.rig.headTurn) /
      (_scale == 0 ? 1 : _scale);

  Offset page(Offset head) => placed.toPage(toDrawing(head));
  Offset headOf(Offset page) => toHead(placed.toLocal(page));

  double get _px => _scale == 0 ? 1 : _scale;

  int _at(int i, int k) => switch (k) {
        0 => 0,
        1 => shapes[i].middle.length ~/ 2,
        _ => shapes[i].middle.length - 1
      };

  /// widthKnobAt is the knob on stroke [i]'s edge at its root, middle or
  /// tip -- [k] 0, 1, 2 -- and the way out from its middle there, in the
  /// head's space: on the edge, or a little way out where it is too thin
  /// to take hold of apart from the middle, at [scale] screen pixels to a
  /// page unit.
  (Offset, Offset) widthKnobAt(int i, int k, double scale) {
    var s = shapes[i];
    var at = _at(i, k);
    var out = s.left[at] - s.middle[at];
    var l = out.distance;
    var dir = l < 1e-9 ? const Offset(1, 0) : out / l;
    var least = 10 / (scale * _px);
    return (s.middle[at] + dir * math.max(l, least), dir);
  }

  /// turnRingAt is the ring round stroke [i]'s root that turns it: its
  /// middle and how far round, in the head's space, clear of its root's
  /// width knob, at [scale] screen pixels to a page unit.
  (Offset, double) turnRingAt(int i, double scale) {
    var px = scale * _px;
    var (knob, _) = widthKnobAt(i, 0, scale);
    var root = shapes[i].root;
    return (root, math.max(34 / px, (knob - root).distance + 14 / px));
  }

  /// scaleKnobAt is the knob on the turning ring that makes stroke [i]
  /// bigger or smaller: behind the root, away from the stroke.
  Offset scaleKnobAt(int i, double scale) {
    var s = shapes[i];
    var (c, r) = turnRingAt(i, scale);
    var away = s.root - s.middle[math.min(4, s.middle.length - 1)];
    var l = away.distance;
    return c + (l < 1e-9 ? const Offset(0, -1) : away / l) * r;
  }

  /// under is what is under [page] -- of the stroke [picked] first, its
  /// handles, then any stroke, nearest the reader first -- within [reach]
  /// page units.
  HairHold? under(Offset page, double scale, double reach, {int? picked}) {
    var p = headOf(page);
    var r = reach / (_scale == 0 ? 1 : _scale);
    if (picked != null && picked < shapes.length) {
      var s = shapes[picked];
      if ((s.tip - p).distance <= r) return HairHold(picked, HairGrab.tip);
      if ((s.root - p).distance <= r) return HairHold(picked, HairGrab.root);
      if ((s.handles.$2 - p).distance <= r) return HairHold(picked, HairGrab.bend1);
      if ((s.handles.$1 - p).distance <= r) return HairHold(picked, HairGrab.bend0);
      // The nearest knob of the edge's three, then the ring's scale knob,
      // then anywhere on the ring.
      HairHold? best;
      var nearest = r;
      for (var k = 0; k < 3; k++) {
        var (knob, _) = widthKnobAt(picked, k, scale);
        var d = (knob - p).distance;
        if (d <= nearest) {
          nearest = d;
          best = HairHold(picked, HairGrab.values[HairGrab.width0.index + k]);
        }
      }
      if (best != null) return best;
      if ((scaleKnobAt(picked, scale) - p).distance <= r) {
        return HairHold(picked, HairGrab.scale);
      }
      var (c, ring) = turnRingAt(picked, scale);
      if (((p - c).distance - ring).abs() <= r * 0.7) {
        return HairHold(picked, HairGrab.turn);
      }
    }
    var order = [for (var i = 0; i < shapes.length; i++) i]
      ..sort((a, b) => shapes[b].depth.compareTo(shapes[a].depth));
    for (var i in order) {
      if (shapes[i].outline.contains(p)) return HairHold(i, HairGrab.body);
    }
    return null;
  }

  /// grownAt is a new stroke growing where [page] is on the scalp -- of the
  /// group that part of the head grows, as wide as that group's strokes --
  /// or null off the head.
  HairStroke? grownAt(Offset page) {
    var at = head.scalpAt(headOf(page));
    if (at == null) return null;
    var (lon, lat) = at;
    // Not on the face: hair grows from the hairline up and round.
    if (lat < 15 && lon.abs() < 70) return null;
    var group = lat > 72
        ? HairGroup.top
        : lon.abs() < 60 && lat > 25
            ? HairGroup.fringe
            : lon.abs() > 120
                ? HairGroup.back
                : HairGroup.sides;
    var like = hair.inGroup(group).firstOrNull?.$2;
    return HairStroke(group, lon, math.max(lat, -40),
        length: 0.04,
        w0: like?.w0 ?? 0.12,
        w1: like?.w1 ?? 0.12,
        w2: like?.w2 ?? 0.02);
  }

  /// dragged is the element with [hold] dragged from [from] to [to] on the
  /// page.
  CharacterElement dragged(HairHold hold, Offset from, Offset to) {
    var i = hold.index;
    if (i >= hair.strokes.length) return element;
    var s = hair.strokes[i];
    var shape = shapes[i];
    var step = headOf(to) - headOf(from);
    HairStroke next;
    switch (hold.grab) {
      case HairGrab.root || HairGrab.body:
        // Moved, it keeps the shape it had: only where it grows changes.
        var at = head.scalpAt(shape.root + step);
        if (at == null) return element;
        next = s.copyWith(
            lon: at.$1, lat: at.$2, shapedAt: s.shapedAt ?? (s.lon, s.lat));
      case HairGrab.tip:
        next = _reaching(s, shape.tip + step);
      case HairGrab.turn:
        // Turned about the line the reader looks along, through its root:
        // on the page, the whole stroke goes round as the ring is dragged.
        double angle(Offset v) => math.atan2(v.dy, v.dx) * 180 / math.pi;
        var swept = angle(headOf(to) - shape.root) - angle(headOf(from) - shape.root);
        // The page is y down; a turn about the reader's line goes the
        // other way round in the head's y up.
        next = s.copyWith(
            spin: spinThen(s.spin, spinAbout(head.toward, -swept)));
      case HairGrab.width0 || HairGrab.width1 || HairGrab.width2:
        // Wider by as far as the knob is dragged out from the middle.
        var k = hold.grab.index - HairGrab.width0.index;
        var (_, dir) = widthKnobAt(i, k, 1);
        var moved = step.dx * dir.dx + step.dy * dir.dy;
        var per = hair.lookOf(s.group).width * s.size * head.h;
        if (per <= 0) return element;
        var dw = moved / per;
        next = switch (k) {
          0 => s.copyWith(w0: s.w0 + dw),
          1 => s.copyWith(w1: s.w1 + dw),
          _ => s.copyWith(w2: s.w2 + dw),
        };
      case HairGrab.bend0 || HairGrab.bend1:
        // The handle pulled across the page, kept as it was before the
        // stroke was turned, so it turns with it.
        var d = [for (var v in unturned(s, head.unstep(step))) v / s.size];
        var b = [...s.bend];
        var o = hold.grab == HairGrab.bend0 ? 0 : 3;
        for (var k = 0; k < 3; k++) {
          b[o + k] += d[k];
        }
        next = s.copyWith(bend: b);
      case HairGrab.scale:
        // Bigger by as far again as the knob goes from the root.
        var r0 = (headOf(from) - shape.root).distance;
        if (r0 < 1e-6) return element;
        var f = (headOf(to) - shape.root).distance / r0;
        next = s.copyWith(size: s.size * f);
    }
    return element.copyWith(
        dna: element.dna.copyWith(hairRig: hair.withStroke(i, next)));
  }

  /// _reaching is [s] made as long, and leaning as far, as takes its tip
  /// to [target]: a few steps of Newton's, each measured from the shape.
  HairStroke _reaching(HairStroke s, Offset target) {
    var g = hair.lookOf(s.group);
    Offset tipOf(HairStroke t) => hairStrokeShape(t, g, head).tip;
    var next = s;
    for (var k = 0; k < 4; k++) {
      var tip = tipOf(next);
      var miss = target - tip;
      if (miss.distance < 0.2) break;
      const dl = 0.02, dn = 0.02;
      var a = (tipOf(next.copyWith(length: next.length + dl)) - tip) / dl;
      var b = (tipOf(next.copyWith(lean: next.lean + dn)) - tip) / dn;
      var det = a.dx * b.dy - a.dy * b.dx;
      if (det.abs() < 1e-9) break;
      var dLen = (miss.dx * b.dy - miss.dy * b.dx) / det;
      var dLean = (a.dx * miss.dy - a.dy * miss.dx) / det;
      next = next.copyWith(length: next.length + dLen, lean: next.lean + dLean);
    }
    return next;
  }
}

/// hairColour is the hair editor's colour, apart from the limbs' green and
/// the face's orange.
const Color hairColour = Color(0xFF3FB8D9);

/// paintHairEditor draws [view]'s strokes for shaping: each one's middle,
/// faint; the picked one's outline, root, tip and rings. [at] takes a page
/// point to the screen, [scale] screen pixels to a page unit.
void paintHairEditor(
    Canvas canvas, HairView view, Offset Function(Offset) at, double scale,
    {int? picked}) {
  Offset p(Offset head) => at(view.page(head));
  var faint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = hairColour.withValues(alpha: 0.5);
  for (var s in view.shapes) {
    // Those on the far side of the head, fainter: behind the face.
    canvas.drawPath(Path()..addPolygon([for (var q in s.middle) p(q)], false),
        Paint.from(faint)..color = hairColour.withValues(alpha: s.depth >= -0.1 ? 0.5 : 0.15));
  }

  if (picked == null || picked >= view.shapes.length) return;
  var s = view.shapes[picked];
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = hairColour;
  var outline = s.outline.computeMetrics().expand((m) sync* {
    for (var d = 0.0; d <= m.length; d += 2) {
      if (m.getTangentForOffset(d) case var t?) yield t.position;
    }
  }).toList();
  canvas.drawPath(
      Path()..addPolygon([for (var q in outline) p(q)], true), line);
  // A knob on the edge at the root, the middle and the tip: diamonds, on a
  // short line out from the middle.
  for (var k = 0; k < 3; k++) {
    var (knob, dir) = view.widthKnobAt(picked, k, scale);
    var at = p(knob);
    var from = p(knob - dir * (10 / (scale * view._px)));
    canvas.drawLine(from, at, faint..color = hairColour.withValues(alpha: 0.8));
    var diamond = Path()
      ..addPolygon([
        at + const Offset(0, -5),
        at + const Offset(5, 0),
        at + const Offset(0, 5),
        at + const Offset(-5, 0),
      ], true);
    canvas.drawPath(diamond, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(diamond, line);
  }
  var white = Paint()..color = const Color(0xFFFFFFFF);
  var root = p(s.root);
  canvas.drawRect(Rect.fromCenter(center: root, width: 10, height: 10), white);
  canvas.drawRect(Rect.fromCenter(center: root, width: 10, height: 10), line);
  // The turning ring round the root, with arrows going round it.
  var (rc, rr) = view.turnRingAt(picked, scale);
  var ringCentre = p(rc);
  var ringRadius = (p(rc + Offset(rr, 0)) - ringCentre).distance;
  var turnPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = hairColour.withValues(alpha: 0.85);
  canvas.drawCircle(ringCentre, ringRadius, turnPaint);
  for (var a in [-math.pi / 4, math.pi * 3 / 4]) {
    var at = ringCentre + Offset.fromDirection(a, ringRadius);
    var along = Offset.fromDirection(a + math.pi / 2, 5);
    var outward = Offset.fromDirection(a, 3.5);
    canvas.drawPath(
        Path()
          ..addPolygon([at + along, at - along * 0.3 + outward, at - along * 0.3 - outward], true),
        Paint()..color = hairColour);
  }
  // The curve's handles: a line out from the root and from the tip to a
  // round knob each.
  var handle = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = hairColour.withValues(alpha: 0.9);
  for (var (end, h) in [(s.root, s.handles.$1), (s.tip, s.handles.$2)]) {
    canvas.drawLine(p(end), p(h), handle);
    canvas.drawCircle(p(h), 4, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(p(h), 4, handle..strokeWidth = 1.4);
    handle.strokeWidth = 1;
  }
  // The scale knob on the ring: a square with corners out.
  var sk = p(view.scaleKnobAt(picked, scale));
  canvas.drawRect(Rect.fromCenter(center: sk, width: 9, height: 9), Paint()..color = hairColour);
  canvas.drawRect(Rect.fromCenter(center: sk, width: 9, height: 9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFFFFFFF));
  var tip = p(s.tip);
  canvas.drawCircle(tip, 5.5, Paint()..color = hairColour);
  canvas.drawCircle(tip, 5.5, line..color = const Color(0xFFFFFFFF));
}

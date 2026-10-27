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
// middle and tip, which makes it wider or narrower there. Pressing on the
// scalp where there is no stroke grows a new one there -- of the group
// that part of the head grows -- and dragging out sets its tip. Delete
// takes the picked one away.

/// HairGrab is what of a stroke is taken hold of.
enum HairGrab { body, root, tip, ring0, ring1, ring2 }

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

  /// ringAt is the [k]th ring of stroke [i] -- root, middle, tip -- its
  /// middle and how far round it is, in the head's space, never too small
  /// to take hold of at [scale] screen pixels to a page unit.
  (Offset, double) ringAt(int i, int k, double scale) {
    var s = shapes[i];
    var at = switch (k) {
      0 => 0,
      1 => s.middle.length ~/ 2,
      _ => s.middle.length - 1
    };
    return (
      s.middle[at],
      math.max(s.widths[at], 7 / (scale * (_scale == 0 ? 1 : _scale)))
    );
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
      for (var k = 0; k < 3; k++) {
        var (c, rad) = ringAt(picked, k, scale);
        if (((p - c).distance - rad).abs() <= r * 0.6) {
          return HairHold(picked, HairGrab.values[HairGrab.ring0.index + k]);
        }
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
        var at = head.scalpAt(shape.root + step);
        if (at == null) return element;
        next = s.copyWith(lon: at.$1, lat: at.$2);
      case HairGrab.tip:
        next = _reaching(s, shape.tip + step);
      case HairGrab.ring0 || HairGrab.ring1 || HairGrab.ring2:
        var k = hold.grab.index - HairGrab.ring0.index;
        var c = switch (k) { 0 => shape.root, 1 => shape.mid, _ => shape.tip };
        var r0 = (headOf(from) - c).distance;
        if (r0 < 1e-6) return element;
        var f = (headOf(to) - c).distance / r0;
        next = switch (k) {
          0 => s.copyWith(w0: s.w0 * f),
          1 => s.copyWith(w1: s.w1 * f),
          _ => s.copyWith(w2: s.w2 * f),
        };
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
  for (var k = 0; k < 3; k++) {
    var (c, r) = view.ringAt(picked, k, scale);
    var centre = p(c);
    var edge = p(c + Offset(r, 0));
    canvas.drawCircle(centre, (edge - centre).distance,
        faint..color = hairColour.withValues(alpha: 0.7));
  }
  var white = Paint()..color = const Color(0xFFFFFFFF);
  var root = p(s.root);
  canvas.drawRect(Rect.fromCenter(center: root, width: 10, height: 10), white);
  canvas.drawRect(Rect.fromCenter(center: root, width: 10, height: 10), line);
  var tip = p(s.tip);
  canvas.drawCircle(tip, 5.5, Paint()..color = hairColour);
  canvas.drawCircle(tip, 5.5, line..color = const Color(0xFFFFFFFF));
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:bruig/plugin_system/canvas/ui/character_rig_editor.dart';

// character_face_rig_editor.dart is a sketch's face set on the canvas,
// feature by feature, on the panel it is seen from -- see
// character_face_rig.dart. Each feature has the rig's three handles: its
// middle moves it, a ring round it sizes it, and a knob on the ring turns
// it. A corner of the mouth is only moved. Delete puts the feature picked
// back as it was.

/// FaceHold is a feature taken hold of, and what of it.
class FaceHold {
  final FacePoint point;
  final RigGrab grab;
  const FaceHold(this.point, this.grab);
}

/// _size is how big each feature is, for its ring, in head units.
double _size(FacePoint p) => switch (p) {
      FacePoint.eyeL || FacePoint.eyeR => 0.13,
      FacePoint.browL || FacePoint.browR => 0.1,
      FacePoint.nose => 0.08,
      FacePoint.mouth => 0.13,
      FacePoint.cornerL || FacePoint.cornerR => 0,
    };

Offset _turned(Offset v, double degrees) {
  var t = degrees * math.pi / 180;
  var c = math.cos(t), s = math.sin(t);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

/// FaceRigView is a sketch's face, feature by feature, where it is on the
/// page on the panel it is seen from.
class FaceRigView {
  final CharacterElement element;
  final CharacterPlacement placed;

  /// pivots is where each feature shown is set about, in the head's space.
  final Map<FacePoint, Offset> pivots;

  /// rig is the panel's face, and mirrored whether it is the other side's.
  final FaceRig rig;
  final bool mirrored;
  final double turn, tilt;

  /// key is the view's -- see viewKeyOf -- what its face rig is kept by.
  final String key;

  FaceRigView._(this.element, this.placed, this.pivots, this.rig, this.mirrored,
      this.turn, this.tilt, this.key);

  factory FaceRigView.of(CharacterElement e, int frame,
      {int frameRate = 12, CanvasDocument? document}) {
    var placed = CharacterPlacement.of(e, frame,
        frameRate: frameRate, document: document);
    var (pose, face) = e.performanceAt(e.style.frameOf(frame), frameRate);
    var panel = e.inView(pose);
    var key = e.viewKey(pose);
    var (rig, mirrored) = e.faceRigAt(key);
    return FaceRigView._(
        e,
        placed,
        facePivots(placed.rig, e.style.dnaOf(e.dna), face, e.style),
        rig,
        mirrored,
        panel.panelTurn,
        panel.panelTilt,
        key);
  }

  double get _u => placed.rig.unit;

  /// _toDrawing takes a point in the head's space into the drawing's.
  Offset _toDrawing(Offset head) =>
      placed.rig.headCentre +
      _turned(head * placed.rig.headScale, placed.rig.headTurn);

  /// _headVector is a step in the drawing taken into the head's space.
  Offset _headVector(Offset v) =>
      _turned(v, -placed.rig.headTurn) / placed.rig.headScale;

  /// handle is where [p] is now, set as it is, in the drawing's space.
  Offset handle(FacePoint p) {
    var pivot = pivots[p]!;
    var a = rig[p];
    if (!p.movesOnly) return _toDrawing(pivot + Offset(a.dx, a.dy) * _u);
    // A corner goes with the mouth as it is set.
    var mouth = pivots[FacePoint.mouth]!;
    var m = rig[FacePoint.mouth];
    var local = pivot - mouth + Offset(a.dx, a.dy) * _u;
    return _toDrawing(
        mouth + Offset(m.dx, m.dy) * _u + _turned(local * m.scale, m.turn));
  }

  /// ring is how far round [p] its ring is, in the drawing's space, at
  /// [scale] screen pixels to a page unit: never too small to take hold of.
  double ring(FacePoint p, double scale) =>
      math.max(_size(p) * _u * rig[p].scale * placed.rig.headScale, 11 / scale);

  /// knob is where [p]'s turning knob is: on its ring, up to the right --
  /// clear of the corners of the mouth, level with its middle -- and turned
  /// with it.
  Offset knob(FacePoint p, double scale) =>
      handle(p) +
      _turned(
          Offset(ring(p, scale), 0), rig[p].turn + placed.rig.headTurn - 45);

  /// under is the feature under [page], and what of it, within [reach].
  FaceHold? under(Offset page, double scale, double reach) {
    var local = placed.toLocal(page);
    // A feature's middle first: a click on a dot is meant for it, whatever
    // ring or knob of another feature it is near.
    for (var grab in const [RigGrab.centre, RigGrab.knob, RigGrab.ring]) {
      for (var p in pivots.keys) {
        if (p.movesOnly && grab != RigGrab.centre) continue;
        var hit = switch (grab) {
          RigGrab.knob => (knob(p, scale) - local).distance <= reach,
          RigGrab.centre => (handle(p) - local).distance <= reach,
          RigGrab.ring =>
            ((handle(p) - local).distance - ring(p, scale)).abs() <=
                reach * 0.6,
        };
        if (hit) return FaceHold(p, grab);
      }
    }
    return null;
  }

  /// dragged is the element with [hold] dragged from [from] to [to] on the
  /// page -- on this panel, its own from then on.
  ///
  /// With [mirror], the feature on the other side -- the other eye, brow
  /// or corner -- is set as its mirror.
  CharacterElement dragged(FaceHold hold, Offset from, Offset to, double scale,
      {bool mirror = false}) {
    var a = placed.toLocal(from), b = placed.toLocal(to);
    var p = hold.point;
    var adj = rig[p];
    switch (hold.grab) {
      case RigGrab.centre:
        var step = _headVector(b - a);
        // A corner's step is in the mouth's own measure.
        if (p.movesOnly) {
          var m = rig[FacePoint.mouth];
          step = _turned(step, -m.turn) / (m.scale == 0 ? 1 : m.scale);
        }
        adj =
            adj.copyWith(dx: adj.dx + step.dx / _u, dy: adj.dy + step.dy / _u);
      case RigGrab.ring:
        var c = handle(p);
        var r0 = (a - c).distance;
        if (r0 < 1e-6) return element;
        var next = adj.scale * (b - c).distance / r0;
        adj = adj.copyWith(scale: next < 0.04 ? 0 : next);
      case RigGrab.knob:
        var c = handle(p);
        double angle(Offset d) => math.atan2(d.dy, d.dx);
        var by = (angle(b - c) - angle(a - c)) * 180 / math.pi;
        adj = adj.copyWith(turn: (adj.turn + by + 180) % 360 - 180);
    }
    return element.withFaceRigAt(key, withFacePoint(rig, p, adj, mirror: mirror));
  }
}

/// withFacePoint is [rig] with [p] set as [a] -- and, with [mirror], the
/// feature on the other side set as its mirror.
FaceRig withFacePoint(FaceRig rig, FacePoint p, FaceAdjust a,
    {bool mirror = false}) {
  var next = rig.withPoint(p, a);
  if (mirror && p.mirrored != p) next = next.withPoint(p.mirrored, a.mirrored);
  return next;
}

/// faceDragged is [start] -- as it was when [hold] was taken at [from] --
/// with it dragged to [to].
CharacterElement faceDragged(CharacterElement start, FaceHold hold, Offset from,
        Offset to, int frame, double scale,
        {int frameRate = 12, CanvasDocument? document, bool mirror = false}) =>
    FaceRigView.of(start, frame, frameRate: frameRate, document: document)
        .dragged(hold, from, to, scale, mirror: mirror);

/// withFacePointBack is [e] with [p] put back as it was on the panel seen
/// on [frame].
CharacterElement withFacePointBack(CharacterElement e, FacePoint p, int frame,
    {int frameRate = 12, bool mirror = false}) {
  var view = FaceRigView.of(e, frame, frameRate: frameRate);
  return e.withFaceRigAt(
      view.key, withFacePoint(view.rig, p, FaceAdjust.rest, mirror: mirror));
}

/// faceColour is the face rig's colour, apart from the limbs' green.
const Color faceColour = Color(0xFFE39B17);

/// paintFaceRig draws [view]'s features for setting -- [at] takes a point
/// on the page to the screen -- [picked] the one picked.
void paintFaceRig(
    Canvas canvas, FaceRigView view, Offset Function(Offset) at, double scale,
    {FacePoint? picked}) {
  Offset p(Offset local) => at(view.placed.toPage(local));
  var ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = faceColour.withValues(alpha: 0.6);
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = faceColour;
  var white = Paint()..color = const Color(0xFFFFFFFF);
  for (var f in view.pivots.keys) {
    var isPicked = f == picked;
    var c = p(view.handle(f));
    if (!f.movesOnly) {
      var r = view.ring(f, scale) * scale;
      canvas.drawCircle(c, r, isPicked ? line : ringPaint);
      var k = p(view.knob(f, scale));
      canvas.drawCircle(k, 3.5, white);
      canvas.drawCircle(k, 3.5, line);
    }
    var size = isPicked ? 5.5 : 4.0;
    canvas.drawCircle(
        c, size, isPicked ? (Paint()..color = faceColour) : white);
    canvas.drawCircle(c, size, line);
  }
}

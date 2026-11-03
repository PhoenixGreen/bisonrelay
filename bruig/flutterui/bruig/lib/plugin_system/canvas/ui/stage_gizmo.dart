import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';

// stage_gizmo.dart is the handle drawn on an element standing on a 3D
// stage while it is selected: arrows along the stage's three ways and a
// square across its floor to move it, a ring on the floor to turn it, and a
// box on a stem to grow and shrink it -- whichever of the three the bar's
// 3D tool asks for (StageTool).
//
// It is drawn through the stage's own camera, so its arrows run the way
// the floor does however the camera is turned, and it is the same size on
// screen however far off the element is. Dragging a part works out the
// element's new spot from where the drag started, never step by step, so a
// slow drag and a fast one end in the same place.

/// GizmoPart is a part of the gizmo that can be taken hold of.
enum GizmoPart { x, y, z, floor, turn, scale }

/// gizmoColours are the parts' colours: the three ways as a 3D program
/// draws them -- across red, up green, nearer blue -- and the floor square
/// and the scale box amber.
const Map<GizmoPart, Color> gizmoColours = {
  GizmoPart.x: Color(0xFFE0484D),
  GizmoPart.y: Color(0xFF3AA35C),
  GizmoPart.z: Color(0xFF3B74E0),
  GizmoPart.floor: Color(0xFFE3A21A),
  GizmoPart.turn: Color(0xFF3AA35C),
  GizmoPart.scale: Color(0xFFE3A21A),
};

/// gizmoHot is a part's colour while the pointer is on it.
const Color gizmoHot = Color(0xFFFFD34D);

/// StageGizmo is the gizmo on one element, as its stage's camera sees it,
/// in page units.
class StageGizmo {
  final Staged at;
  final StageTool tool;

  /// length is how long its arrows are, in metres: as long as a fixed
  /// stretch of the screen at the distance it is from the camera.
  final double length;

  /// body is whether it is on a 3D character, which is as tall as it was
  /// made and so is not scaled.
  final bool body;

  StageGizmo._(this.at, this.tool, this.length, this.body);

  /// onScreen is how long its arrows are on screen, in screen pixels.
  static const double onScreen = 84;

  /// of is the gizmo on [e], standing where [at] says, for [tool] -- with
  /// [pageScale] screen pixels to a page unit, so it is drawn the same
  /// size at any zoom. Null where the camera cannot see its foot.
  static StageGizmo? of(
      CanvasElement e, Staged at, StageTool tool, double pageScale) {
    var (x, y, z) = _footOf(at);
    var depth = at.view.see(x, y, z).depth;
    if (depth <= StageView.nearest || pageScale <= 0) return null;
    var length = onScreen / pageScale / at.view.scaleAt(depth);
    return StageGizmo._(at, tool, length, e is Character3dElement);
  }

  static (double, double, double) _footOf(Staged at) {
    var spot = at.spot;
    return spot.stand == SpotStand.wall
        ? (spot.x, spot.lift, -at.stage.size + 0.01)
        : (spot.x, spot.lift, spot.z);
  }

  /// foot is the point it stands on, in metres.
  (double, double, double) get foot => _footOf(at);

  bool get _onWall => at.spot.stand == SpotStand.wall;

  /// parts are what is drawn and can be taken hold of, for its tool.
  List<GizmoPart> get parts => switch (tool) {
        StageTool.move => _onWall
            ? const [GizmoPart.x, GizmoPart.y]
            : const [GizmoPart.floor, GizmoPart.x, GizmoPart.z, GizmoPart.y],
        // A flat that faces the camera, or hangs on the wall, has no way
        // round to turn.
        StageTool.rotate => _onWall || at.spot.stand == SpotStand.camera
            ? const []
            : const [GizmoPart.turn],
        StageTool.scale => body ? const [] : const [GizmoPart.scale],
      };

  Offset _see(double x, double y, double z) => at.view.see(x, y, z).page;

  /// centre is its foot on the page.
  Offset get centre {
    var (x, y, z) = foot;
    return _see(x, y, z);
  }

  static (double, double, double) _way(GizmoPart axis) => switch (axis) {
        GizmoPart.x => (1, 0, 0),
        GizmoPart.y => (0, 1, 0),
        _ => (0, 0, 1),
      };

  /// tip is the end of [axis]'s arrow on the page.
  Offset tip(GizmoPart axis) {
    var (x, y, z) = foot;
    var (dx, dy, dz) = _way(axis);
    return _see(x + dx * length, y + dy * length, z + dz * length);
  }

  /// square is the floor square's four corners on the page, in the corner
  /// between the across and nearer arrows.
  List<Offset> get square {
    var (x, y, z) = foot;
    var a = length * 0.14, b = length * 0.5;
    return [
      _see(x + a, y, z + a),
      _see(x + b, y, z + a),
      _see(x + b, y, z + b),
      _see(x + a, y, z + b),
    ];
  }

  /// ring is the turning ring on the floor round its foot, on the page.
  List<Offset> get ring {
    var (x, y, z) = foot;
    var r = length * 0.7;
    return [
      for (var k = 0; k < 48; k++)
        _see(x + math.sin(k / 48 * 2 * math.pi) * r, y,
            z + math.cos(k / 48 * 2 * math.pi) * r),
    ];
  }

  /// facingTick is the point on the ring the way it faces.
  Offset get facingTick {
    var (x, y, z) = foot;
    var t = at.spot.facing * math.pi / 180, r = length * 0.7;
    return _see(x + math.sin(t) * r, y, z + math.cos(t) * r);
  }

  /// scaleBox is the scale handle's middle, at the top of its stem.
  Offset get scaleBox {
    var (x, y, z) = foot;
    return _see(x, y + length * 0.86, z);
  }

  /// hit is the part under [page], within [reach] page units, or null.
  GizmoPart? hit(Offset page, double reach) {
    var shown = parts;
    // The scale box first: it is what is aimed at.
    if (shown.contains(GizmoPart.scale) &&
        (scaleBox - page).distance <= reach * 1.6) {
      return GizmoPart.scale;
    }
    // Inside the floor square, the square.
    var sq = shown.contains(GizmoPart.floor) ? square : const <Offset>[];
    if (sq.isNotEmpty && (Path()..addPolygon(sq, true)).contains(page)) {
      return GizmoPart.floor;
    }
    // Then the nearest arrow.
    GizmoPart? best;
    var nearest = reach;
    for (var axis in const [GizmoPart.x, GizmoPart.y, GizmoPart.z]) {
      if (!shown.contains(axis)) continue;
      var d = _toSegment(page, centre, tip(axis));
      if (d <= nearest) {
        nearest = d;
        best = axis;
      }
    }
    if (best != null) return best;
    // And near the square's edges: from a camera looking along the floor
    // it is a sliver, and the sliver is still meant.
    for (var k = 0; k < sq.length; k++) {
      if (_toSegment(page, sq[k], sq[(k + 1) % sq.length]) <= reach * 0.6) {
        return GizmoPart.floor;
      }
    }
    if (shown.contains(GizmoPart.turn)) {
      var r = ring;
      for (var k = 0; k < r.length; k++) {
        if (_toSegment(page, r[k], r[(k + 1) % r.length]) <= reach) {
          return GizmoPart.turn;
        }
      }
    }
    return null;
  }

  static double _toSegment(Offset p, Offset a, Offset b) {
    var ab = b - a;
    var len = ab.distanceSquared;
    if (len == 0) return (p - a).distance;
    var t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// dragged is the spot [part] dragged from [from] to [to] -- page points
  /// -- puts it on, from where it stood when the drag began. [pageScale]
  /// is screen pixels to a page unit; with [step] above nought it moves in
  /// steps of that many metres, and with [turn] turns in steps of that
  /// many degrees.
  StageSpot dragged(GizmoPart part, Offset from, Offset to,
      {double pageScale = 1, double step = 0, double turn = 0}) {
    var spot = at.spot;
    double snap(double v) => step > 0 ? (v / step).roundToDouble() * step : v;
    switch (part) {
      case GizmoPart.x || GizmoPart.y || GizmoPart.z:
        // Along the arrow as it is seen: how far the pointer went along it,
        // in the arrow's own metres.
        var along = tip(part) - centre;
        var len = along.distanceSquared;
        if (len < 1e-9) return spot;
        var by = to - from;
        var metres = (by.dx * along.dx + by.dy * along.dy) / len * length;
        return switch (part) {
          GizmoPart.x => spot.copyWith(x: snap(spot.x + metres)),
          GizmoPart.z => spot.copyWith(z: snap(spot.z + metres)),
          _ => spot.copyWith(lift: math.max(0.0, snap(spot.lift + metres))),
        };
      case GizmoPart.floor:
        var level = spot.stand == SpotStand.floor ? 0.0 : spot.lift;
        var a = at.view.toFloor(from, y: level),
            b = at.view.toFloor(to, y: level);
        if (a == null || b == null) return spot;
        return spot.copyWith(
            x: snap(spot.x + b.dx - a.dx), z: snap(spot.z + b.dy - a.dy));
      case GizmoPart.turn:
        var (x, y, z) = foot;
        var a = at.view.toFloor(from, y: y), b = at.view.toFloor(to, y: y);
        if (a == null || b == null) return spot;
        var a0 = math.atan2(a.dx - x, a.dy - z);
        var a1 = math.atan2(b.dx - x, b.dy - z);
        var f = spot.facing + (a1 - a0) * 180 / math.pi;
        f = (f + 540) % 360 - 180;
        if (turn > 0) f = (f / turn).roundToDouble() * turn;
        return spot.copyWith(facing: f == -180 ? 180 : f);
      case GizmoPart.scale:
        // Up grows it, down shrinks it, by the screen's pixels.
        var dy = (to.dy - from.dy) * pageScale;
        var h = spot.height * math.exp(-dy * 0.006);
        if (step > 0) h = math.max(0.1, (h * 10).roundToDouble() / 10);
        return spot.copyWith(height: h.clamp(0.05, 30.0));
    }
  }
}

/// StageGizmoPainter draws [gizmo] on the stage widget, where a page point
/// p is at p × [scale] + [origin]. [hot] is the part the pointer is on, or
/// being dragged.
class StageGizmoPainter extends CustomPainter {
  final StageGizmo gizmo;
  final GizmoPart? hot;
  final double scale;
  final Offset origin;

  const StageGizmoPainter(this.gizmo,
      {this.hot, required this.scale, required this.origin});

  Offset _s(Offset page) => page * scale + origin;

  @override
  void paint(Canvas canvas, Size size) {
    Color colour(GizmoPart p) => p == hot ? gizmoHot : gizmoColours[p]!;
    var shade = Paint()
      ..color = const Color(0x66000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    Paint pen(GizmoPart p, [double w = 2.5]) => Paint()
      ..color = colour(p)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    var centre = _s(gizmo.centre);
    for (var part in gizmo.parts) {
      switch (part) {
        case GizmoPart.floor:
          var sq = Path()
            ..addPolygon([for (var p in gizmo.square) _s(p)], true);
          canvas.drawPath(
              sq, Paint()..color = colour(part).withValues(alpha: 0.55));
          canvas.drawPath(sq, pen(part, 1.2));
        case GizmoPart.x || GizmoPart.y || GizmoPart.z:
          var tip = _s(gizmo.tip(part));
          canvas.drawLine(centre, tip, shade);
          canvas.drawLine(centre, tip, pen(part));
          // A head pointing along it.
          var d = tip - centre;
          if (d.distance < 1) break;
          var u = d / d.distance, n = Offset(-u.dy, u.dx);
          var head = Path()
            ..moveTo(tip.dx + u.dx * 9, tip.dy + u.dy * 9)
            ..lineTo(tip.dx + n.dx * 5, tip.dy + n.dy * 5)
            ..lineTo(tip.dx - n.dx * 5, tip.dy - n.dy * 5)
            ..close();
          canvas.drawPath(head, Paint()..color = colour(part));
        case GizmoPart.turn:
          var ring = Path()
            ..addPolygon([for (var p in gizmo.ring) _s(p)], true);
          canvas.drawPath(ring, shade);
          canvas.drawPath(ring, pen(part));
          var tick = _s(gizmo.facingTick);
          canvas.drawCircle(tick, 5, Paint()..color = colour(part));
          canvas.drawLine(centre, tick, pen(part, 1.2));
        case GizmoPart.scale:
          var top = _s(gizmo.scaleBox);
          canvas.drawLine(centre, top, shade);
          canvas.drawLine(centre, top, pen(part, 2));
          var box = Rect.fromCenter(center: top, width: 11, height: 11);
          canvas.drawRect(
              box.inflate(1.5), Paint()..color = const Color(0x66000000));
          canvas.drawRect(box, Paint()..color = colour(part));
      }
    }
    // Its foot, where it stands.
    canvas.drawCircle(centre, 3.5, Paint()..color = Colors.white);
    canvas.drawCircle(
        centre,
        3.5,
        Paint()
          ..color = const Color(0x99000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(StageGizmoPainter old) =>
      old.hot != hot ||
      old.scale != scale ||
      old.origin != origin ||
      old.gizmo.tool != gizmo.tool ||
      old.gizmo.at.spot != gizmo.at.spot ||
      old.gizmo.at.view.camera != gizmo.at.view.camera ||
      old.gizmo.length != gizmo.length;
}

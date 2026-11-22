import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

/// StageHitTest answers "what is at this point of the document, now": where
/// each element is drawn at this frame, and which is under a point. Made
/// from the document as it is and nothing else, so it can be asked without
/// a stage.
class StageHitTest {
  /// document is what is on the page.
  final CanvasDocument document;

  /// frame is the frame the page is drawn at.
  final int frame;

  /// live is what plays off the timeline (CanvasController.liveMotion), or
  /// null when everything plays from it.
  final LiveMotion? live;

  /// scale is stage pixels to a document unit, for a reach that is so many
  /// pixels on screen (a thin line's, a small tab's).
  final double scale;

  /// cameras is whether a Camera's frame is drawn over the page, and so can
  /// be hit there (CanvasStageState._camerasShown).
  final bool cameras;

  const StageHitTest({
    required this.document,
    required this.frame,
    this.live,
    required this.scale,
    this.cameras = true,
  });

  /// posed is where [e] is drawn now: its resting box moved by its motion.
  Rect posed(CanvasElement e) => e.movedBoundsAt(frame, document, live: live);

  /// contains is whether document point [at] is on [e] as drawn, turn and
  /// slant undone.
  bool contains(CanvasElement e, Offset at) {
    // A camera is hit by its frame's edge: what it shows inside is picked as
    // if it were not there. Where the frame is not drawn, nothing is hit.
    if (e is CameraElement) {
      if (!cameras) return false;
      var frame = posed(e);
      // Its name tab is drawn upright, so it is hit upright.
      if (cameraTab(e, frame, scale).contains(at)) return true;
      // The frame and its corners are drawn turned by its roll, so the
      // point is turned back before they are tried.
      var roll = cameraLookAt(e, this.frame, document, live: live).roll;
      var local = roll == 0
          ? at
          : frame.center + BoxFrame(roll, 0, 0).invert(at - frame.center);
      var reach = _strokeReach(2) + 4 / scale;
      if (frame.inflate(reach).contains(local) &&
          !frame.deflate(reach).contains(local)) {
        return true;
      }
      // Its corner brackets too, the size they are drawn: an edge on the
      // page's edge is hard to pick.
      var corner = math.min(18 / scale, frame.shortestSide / 4);
      for (var c in [
        frame.topLeft,
        frame.topRight,
        frame.bottomLeft,
        frame.bottomRight,
      ]) {
        var inside = Rect.fromCenter(
            center: Offset(c.dx + (c.dx == frame.left ? 1 : -1) * corner / 2,
                c.dy + (c.dy == frame.top ? 1 : -1) * corner / 2),
            width: corner,
            height: corner);
        if (inside.contains(local)) return true;
      }
      return false;
    }
    // A team on a pitch is wherever the pitch puts its players.
    if (e is TeamElement && e.linked) return playerOf(e, at) != null;
    // Something on a stage is inside the four corners the camera sees.
    if (e.base.spot != null) {
      if (stagedIn(document, e, frame) case var staged?) {
        return (Path()..addPolygon(staged.quad, true)).contains(at);
      }
    }
    // A curve is hit by its stroke, not its box: a bowed line or path bulges
    // out of its box, and text on a line is wherever the line is.
    if (e is LineElement || e is PathElement) {
      var curve = curveOfElement(e is LineElement ? lineWithPose(e, frame) : e);
      if (curve != null && curve.length >= 2) {
        var width =
            e is LineElement ? e.strokeWidth : (e as PathElement).strokeWidth;
        return _nearPolyline(curve, at, _strokeReach(width));
      }
    }
    if (e is TextElement) {
      var curve = curveUnderText(e, document, frame);
      if (curve != null && curve.length >= 2) {
        // Generous: the target is a row of letters on the line.
        return _nearPolyline(
            curve, at, _strokeReach(e.textSpec.fontSize * 1.2));
      }
    }

    var box = posed(e);
    var shape = e.movedFrameAt(frame, document, live: live);
    var local = at;
    if (!shape.upright) local = box.center + shape.invert(at - box.center);
    if (!box.contains(local)) return false;

    if (e is ShapeElement && e.shape == ShapeKind.circle) {
      var r = box.shortestSide / 2;
      return (local - box.center).distance <= r;
    }
    return true;
  }

  /// topmost is the element drawn over the others at [at], or null: the
  /// first from the front that is shown, unlocked and [contains] it.
  /// [among] narrows the search to those elements, in the order they are
  /// drawn (the document's by default); [where] to those it accepts.
  CanvasElement? topmost(Offset at,
      {Iterable<CanvasElement>? among, bool Function(CanvasElement e)? where}) {
    var from = among?.toList() ?? document.elements;
    for (var i = from.length - 1; i >= 0; i--) {
      var e = from[i];
      if (!e.visible || e.locked) continue;
      if (where != null && !where(e)) continue;
      if (contains(e, at)) return e;
    }
    return null;
  }

  /// playerOf is the topmost of [team]'s players at [at], or null. A locked
  /// player cannot be hit, so a run can be dragged through a pinned back
  /// four.
  int? playerOf(TeamElement team, Offset at) {
    var rx = team.dotWidth / 2;
    var ry = team.dotHeight / 2;
    if (rx <= 0 || ry <= 0) return null;
    var ground = teamGround(document, team, frame);

    for (var i = team.players.length - 1; i >= 0; i--) {
      var spot = team.players[i];
      if (spot.locked || spot.hidden) continue;
      // Where the pitch draws them on this frame.
      var place = playerPlace(ground, team, spot, frame);
      if (!place.shown) continue;
      var d = at - place.centre;
      var own = spot.ball ? team.radiusOf(spot) : null;
      var sx = (own ?? rx) * place.size, sy = (own ?? ry) * place.size;
      // Tested against the ellipse, so gaps between dots in a tight back four
      // stay gaps.
      if ((d.dx * d.dx) / (sx * sx) + (d.dy * d.dy) / (sy * sy) <= 1) return i;
    }
    return null;
  }

  /// _strokeReach is how near a line, in document units, counts as on it.
  double _strokeReach(double strokeWidth) =>
      math.max(strokeWidth / 2, 0) + strokeHitSlop / scale;

  bool _nearPolyline(List<Offset> points, Offset point, double reach) {
    for (var i = 1; i < points.length; i++) {
      var a = points[i - 1], b = points[i];
      var ab = b - a;
      var lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
      var t = lengthSquared == 0
          ? 0.0
          : (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      var closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
      if ((point - closest).distance <= reach) return true;
    }
    return false;
  }
}

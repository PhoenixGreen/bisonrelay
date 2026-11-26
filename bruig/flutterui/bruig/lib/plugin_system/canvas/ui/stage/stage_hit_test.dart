import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

/// _edgesKept is a shape outline's edge walked into points for one reach,
/// kept with the outline itself: shapeOutline keeps each outline it builds
/// and hands back the same one for the same shape in the same box, and a
/// pointer moving over one shape asks at every move. Let go with the
/// outline.
final Expando<(double, List<List<Offset>>)> _edgesKept =
    Expando("outline edges");

/// _edgesOf is [outline]'s edge as runs of points, in steps short beside
/// [reach] so a corner is not stepped over, and never more than a few
/// thousand of them.
List<List<Offset>> _edgesOf(Path outline, double reach) {
  if (_edgesKept[outline] case (var r, var edges) when r == reach) {
    return edges;
  }
  var edges = [
    for (var metric in outline.computeMetrics())
      [
        for (var d = 0.0;
            d < metric.length;
            d += math.max(reach / 4, metric.length / 2000))
          metric.getTangentForOffset(d)!.position,
        metric.getTangentForOffset(metric.length)!.position,
      ],
  ];
  _edgesKept[outline] = (reach, edges);
  return edges;
}

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

  /// drawn is [posed] where the page draws it: a mirrored page number on a
  /// left-hand page is drawn across the page (CounterElement.drawnBox), and
  /// pressed there.
  Rect drawn(CanvasElement e) => switch (e) {
        CounterElement c => c.drawnBox(posed(e),
            page: document.size.rect, leftHand: document.pageIsLeftHand),
        _ => posed(e),
      };

  /// contains is whether document point [at] is on [e] as drawn, turn and
  /// slant undone.
  bool contains(CanvasElement e, Offset at) {
    // A camera is hit by its frame's edge: what it shows inside is picked as
    // if it were not there. Where the frame is not drawn, nothing is hit.
    if (e is CameraElement) {
      if (!cameras) return false;
      var frame = posed(e);
      // Its name tab is drawn upright, so it is hit upright: longer on one
      // shown that does not frame the scene, for saying so.
      var inUse = !e.visible || cameraOf(document)?.id == e.id;
      if (cameraTab(e, frame, scale, inUse: inUse).contains(at)) return true;
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
    // out of its box, and text on a line is wherever the line is. What is
    // drawn on its ends is hit where it is drawn, however far it reaches.
    if (e is StrokedElement) {
      var drawn = strokeOnPage(e, frame, document, live);
      if (drawn != null && drawn.curve.length >= 2) {
        return _nearPolyline(drawn.curve, at,
                _strokeReach(e.strokeWidth * drawn.place.stretch)) ||
            _onEnds(drawn, at);
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

    var box = drawn(e);
    var shape = e.movedFrameAt(frame, document, live: live);
    var local = at;
    if (!shape.upright) local = box.center + shape.invert(at - box.center);
    // A shape's outline is drawn centred on its edge, so half of a thick one
    // lies outside its box, and is pressed there too.
    var outside =
        e is ShapeElement && e.strokeWidth > 0 ? e.strokeWidth / 2 : 0.0;
    if (!box.inflate(outside).contains(local)) return false;

    // A shape is pressed inside its outline, filled or not, or near enough
    // its edge to pick a thin one; its box's empty corners are left to
    // what is behind it.
    if (e is ShapeElement) {
      var outline = shapeOutline(e, box);
      return outline.contains(local) ||
          _nearOutline(outline, local, _strokeReach(e.strokeWidth));
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

  /// _onEnds is whether [at] is on what [drawn] draws on its ends: inside
  /// one, or near enough its edge to pick it (a hollow one's edge, or a bar,
  /// being drawn the stroke's width). Its curve's two ends are asked about
  /// only when [at] is in their reach.
  bool _onEnds(StrokeOnPage drawn, Offset at) {
    var e = drawn.shaped;
    var curve = drawn.curve;
    var stroke = e.drawnStroke;
    // In the curve's own space, before it is laid on the page, where the
    // marks are worked out and their reach is measured: the pointer's slop
    // shrinks there by as much as the pose grows the stroke.
    var stretch = drawn.place.stretch <= 0 ? 1.0 : drawn.place.stretch;
    var slop = _strokeReach(0) / stretch;
    var edge = math.max(e.strokeWidth / 2, 0) + slop;
    var local = drawn.place.unplace(at);
    bool within(LineEnd end, Offset tip) =>
        end != LineEnd.none &&
        (local - drawn.place.unplace(tip)).distance <=
            e.strokeWidth * stroke.endSize * end.reach + edge;
    if (!within(stroke.startEnd, curve.first) &&
        !within(stroke.endEnd, curve.last)) {
      return false;
    }
    for (var mark in strokeEndMarks(e.curve, stroke)) {
      var reach = mark.solid ? slop : edge;
      if (mark.corners.isEmpty) {
        if ((local - mark.at).distance <= mark.radius + reach) return true;
        continue;
      }
      if (mark.end != LineEnd.bar && mark.outline.contains(local)) return true;
      var ring = mark.end == LineEnd.bar
          ? mark.corners
          : [...mark.corners, mark.corners.first];
      if (_nearPolyline(ring, local, reach)) return true;
    }
    return false;
  }

  /// _strokeReach is how near a line, in document units, counts as on it.
  double _strokeReach(double strokeWidth) =>
      math.max(strokeWidth / 2, 0) + strokeHitSlop / scale;

  /// _nearOutline is whether [point] is within [reach] of [outline]'s edge.
  bool _nearOutline(Path outline, Offset point, double reach) {
    if (!outline.getBounds().inflate(reach).contains(point)) return false;
    return _edgesOf(outline, reach)
        .any((run) => _nearPolyline(run, point, reach));
  }

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

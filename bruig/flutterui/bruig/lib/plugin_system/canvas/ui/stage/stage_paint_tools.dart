import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

// stage_paint_tools.dart is what the tool in hand draws over the page: a
// drawing edited point by point (its outlines, points and handles, the
// shapes tool's box, the pencil's mirror lines), a picture's layers with
// its brush, lasso and warp grid, a picture being reframed, and the
// knife's line. Drawn from the tools' marks, in stage pixels: [scale]
// pixels to a document unit, the document's top-left at [origin].

/// _paintWarp draws a warp grid being worked on: lines dark under light,
/// to show over any picture; points as squares, picked ones filled; and
/// the box round the picked ones with its corners and turning knob.
void _paintWarp(Canvas canvas, StageWarp w, Offset Function(Offset) screen) {
  drawDarkUnderLight((paint) {
    for (var line in w.lines) {
      canvas.drawPath(
          Path()..addPolygon([for (var p in line) screen(p)], false), paint);
    }
  }, strokes: const [(2.6, Color(0x88000000)), (1.0, Color(0xCCFFFFFF))]);
  const white = Color(0xFFFFFFFF);
  for (var (k, p) in w.points.indexed) {
    var picked = w.picks.contains(k);
    drawSquareHandle(canvas, screen(p),
        size: 8,
        fill: picked ? stageBlue : white,
        edge: picked ? white : stageBlue,
        width: 1.2);
  }
  if (w.box case var corners?) {
    var at = [for (var p in corners) screen(p)];
    canvas.drawPath(
        Path()..addPolygon(at, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = stageBlue);
    for (var c in at) {
      drawSquareHandle(canvas, c, size: 9);
    }
    if (w.knob case var k?) {
      var top = (at[0] + at[1]) / 2, knob = screen(k);
      canvas.drawLine(top, knob, Paint()..color = stageBlue);
      drawRoundKnob(canvas, knob, 5.5);
    }
  }
}

/// paintShapeBox draws the box round the shape the shapes tool picked, in
/// the drawing's units [box], with move and resize handles.
void paintShapeBox(
    Canvas canvas, VectorElement e, Rect box, double scale, Offset origin,
    {bool turnable = false}) {
  var space = VectorSpace(e);
  Offset screen(Offset p) => space.toCanvas(p) * scale + origin;
  var colour = e.handleColor;
  var corners = [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]
      .map(screen)
      .toList();
  canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colour);
  // The turn handle on a stalk above the box, as an element's.
  if (turnable) {
    var top = screen(box.topCenter);
    var knob = shapeTurnKnob(top);
    canvas.drawLine(
        top,
        knob,
        Paint()
          ..strokeWidth = 1
          ..color = colour);
    drawRoundKnob(canvas, knob, 5, edge: colour);
  }
  for (var h in boxHandles(box)) {
    drawSquareHandle(canvas, screen(h), size: 8, edge: colour);
  }
}

/// paintLayerBoxes draws the layers of a picture being edited: a faint
/// outline round each layer that can be picked, and the picked one's box
/// with its handles and turning knob.
void paintLayerBoxes(Canvas canvas, StageLayers layers,
    CanvasImageSource images, double scale, Offset origin) {
  Offset screen(Offset p) => p * scale + origin;
  if (layers.masking case var m? when m.view != MaskView.result) {
    saveInDocument(canvas, scale, origin);
    paintMaskView(canvas, m.element, m.layer, images,
        overlay: m.view == MaskView.overlay);
    canvas.restore();
  }
  if (layers.trail case (var points, var radius, var subtract)) {
    var colour = subtract ? const Color(0x66FF3030) : const Color(0x6630A0FF);
    var paint = Paint()
      ..color = colour
      ..strokeWidth = radius * scale * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    var at = [for (var p in points) screen(p)];
    if (at.length == 1) {
      canvas.drawCircle(
          at.single, radius * scale, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(Path()..addPolygon(at, false), paint);
    }
  }
  // The lasso as drawn, closed, dark under light to show over any picture,
  // its inside faintly tinted.
  if (layers.lasso case var points? when points.length >= 2) {
    var path = Path()..addPolygon([for (var p in points) screen(p)], true);
    canvas.drawPath(path, Paint()..color = const Color(0x2230A0FF));
    drawDarkUnderLight((paint) => canvas.drawPath(path, paint),
        join: StrokeJoin.round);
  }
  if (layers.warp case var w?) _paintWarp(canvas, w, screen);
  if (layers.marker case var m?) {
    var at = screen(m);
    drawDarkUnderLight((paint) {
      canvas.drawLine(at - const Offset(8, 0), at + const Offset(8, 0), paint);
      canvas.drawLine(at - const Offset(0, 8), at + const Offset(0, 8), paint);
    });
  }
  if (layers.ring case (var centre, var radius)) {
    var at = screen(centre);
    var r = radius * scale;
    drawDarkUnderLight((paint) => canvas.drawCircle(at, r, paint));
  }
  Path outline(List<Offset> corners) =>
      Path()..addPolygon(corners.map(screen).toList(), true);
  const colour = defaultHandleColor;
  for (var corners in layers.others) {
    canvas.drawPath(
        outline(corners),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colour.withValues(alpha: 0.35));
  }
  for (var corners in layers.chosen) {
    canvas.drawPath(
        outline(corners),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colour);
  }
  var picked = layers.picked;
  if (picked == null) return;
  canvas.drawPath(
      outline(picked),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = colour);
  if (layers.knob case var knob?) {
    var top = screen((picked[0] + picked[1]) / 2);
    var at = screen(knob);
    canvas.drawLine(
        top,
        at,
        Paint()
          ..strokeWidth = 1
          ..color = colour);
    drawRoundKnob(canvas, at, 5, edge: colour);
  }
  for (var h in layers.handles) {
    drawSquareHandle(canvas, screen(h), edge: colour);
  }
}

/// paintMirrorLines draws the pencil's dashed mirror lines through the
/// middle of the drawing [e], so a stroke's mirror can be foreseen.
void paintMirrorLines(Canvas canvas, VectorElement e, bool across, bool down,
    double scale, Offset origin) {
  if (!across && !down) return;
  var space = VectorSpace(e);
  var v = e.viewBox;
  // A little past the drawing, so it reads as a line, not an edge.
  var r = v.inflate(math.max(v.width, v.height) * 0.1);
  var paint = Paint()
    ..color = e.handleColor.withValues(alpha: 0.7)
    ..strokeWidth = 1;
  void dashed(Offset a, Offset b) => drawDashedLine(
      canvas,
      space.toCanvas(a) * scale + origin,
      space.toCanvas(b) * scale + origin,
      paint,
      dash: 6,
      gap: 4);

  if (across) {
    dashed(Offset(v.center.dx, r.top), Offset(v.center.dx, r.bottom));
  }
  if (down) dashed(Offset(r.left, v.center.dy), Offset(r.right, v.center.dy));
}

/// paintVectorControls draws a drawing being edited: every shape's outline
/// faint, the picked shape's lit with its points, the points of any shape
/// with points picked, and the handles of a single picked point.
/// [everyShape] shows every shape's points, while a box is dragged.
void paintVectorControls(Canvas canvas, VectorElement e, int picked,
    VectorPick? pick, Set<VectorPick> picks, double scale, Offset origin,
    {bool everyShape = false, Set<int>? combining}) {
  var shapes = e.shapes;
  if (shapes == null) return;
  var space = VectorSpace(e);
  var colour = e.handleColor;
  Offset screen(Offset v) => space.toCanvas(v) * scale + origin;

  // Through the drawing's own placement and turn, so outlines lie on it.
  var place = e.placement(e.bounds, e.viewBox);
  var centre = e.bounds.center;
  saveInDocument(canvas, scale, origin);
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(e.rotation * math.pi / 180);
  canvas.translate(-centre.dx, -centre.dy);
  canvas.translate(place.dx, place.dy);
  canvas.scale(place.sx, place.sy);
  var hair = 1 / (scale * math.max(1e-6, math.min(place.sx, place.sy)));
  // Combining picks whole shapes, so outlines only, with the picked ones
  // and every shape combined into them lit.
  if (combining != null) {
    for (var i = 0; i < shapes.length; i++) {
      var lit = combining.contains(groupOf(e, i));
      var path = vectorShapePath(shapes[i]);
      if (lit) {
        canvas.drawPath(
            path, Paint()..color = colour.withValues(alpha: colour.a * 0.12));
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (lit ? 2 : 1) * hair
            ..color = lit ? colour : colour.withValues(alpha: colour.a * 0.35));
    }
    canvas.restore();
    return;
  }
  for (var i = 0; i < shapes.length; i++) {
    canvas.drawPath(
        vectorShapePath(shapes[i]),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (i == picked ? 1.5 : 1) * hair
          ..color =
              i == picked ? colour : colour.withValues(alpha: colour.a * 0.35));
  }
  canvas.restore();

  // Every shape's points while a box is dragged or nothing is picked, so
  // there is always something to take hold of.
  if (picked < 0 && picks.isEmpty) everyShape = true;
  var shown = <int>{
    if (everyShape) ...[for (var i = 0; i < shapes.length; i++) i],
    if (picked >= 0 && picked < shapes.length) picked,
    for (var p in picks)
      if (p.shape < shapes.length) p.shape,
  };
  if (shown.isEmpty) return;
  // The faint box round several picked points, where a press takes them
  // all.
  if (picksBox(e, picks) case var box?) {
    var r = onScreen(box, scale, origin).inflate(e.handleSize);
    canvas.drawRect(r, Paint()..color = colour.withValues(alpha: 0.08));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = colour.withValues(alpha: 0.6));
  }
  var size = e.handleSize;
  const white = Color(0xFFFFFFFF);
  var line = Paint()
    ..strokeWidth = 1
    ..color = colour;

  // The picked point's handles first, so points sit on their lines.
  if (pick != null && pick.shape < shapes.length) {
    var node = vectorNodeAt(e, pick);
    if (node != null) {
      var at = screen(node.point);
      for (var (has, handle) in [
        (node.hasIn, node.inHandle),
        (node.hasOut, node.outHandle),
      ]) {
        if (!has) continue;
        var h = screen(handle);
        canvas.drawLine(at, h, line);
        drawRoundKnob(canvas, h, size / 2, edge: colour);
      }
    }
  }
  // A joint is one point however many lines meet at it: every end there is
  // drawn picked, or those drawn over it would hide that it is.
  var lit = joinedTo(e, picks);
  for (var showing in shown) {
    var paths = shapes[showing].paths;
    for (var p = 0; p < paths.length; p++) {
      for (var n = 0; n < paths[p].nodes.length; n++) {
        var node = paths[p].nodes[n];
        var at = screen(node.point);
        var chosen = lit.contains(VectorPick(showing, p, n));
        // Smooth round, corner square: it decides how a handle moves.
        if (node.smooth) {
          drawRoundKnob(canvas, at, size / 2,
              fill: chosen ? colour : white, edge: colour);
        } else {
          drawSquareHandle(canvas, at,
              size: size, fill: chosen ? colour : white, edge: colour);
        }
      }
    }
  }
}

/// paintFraming shows the rest of a picture moved inside its frame, faint
/// outside the frame, so what comes into shot can be seen.
void paintFraming(
    Canvas canvas, StageFraming? framing, double scale, Offset origin) {
  var it = framing;
  if (it == null || it.dst.isEmpty) return;

  saveInDocument(canvas, scale, origin);
  if (it.rotation != 0) {
    var pivot = it.pivot ?? it.frame.center;
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(it.rotation);
    canvas.translate(-pivot.dx, -pivot.dy);
  }
  if (it.flipX || it.flipY) {
    canvas.translate(it.frame.center.dx, it.frame.center.dy);
    canvas.scale(it.flipX ? -1 : 1, it.flipY ? -1 : 1);
    canvas.translate(-it.frame.center.dx, -it.frame.center.dy);
  }

  // Faint with the frame punched out, so the renderer's full-strength part
  // and this read as one picture.
  canvas.save();
  canvas.clipRect(it.frame, clipOp: ui.ClipOp.difference);
  canvas.drawImageRect(
      it.image,
      it.src,
      it.dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0x55FFFFFF));
  canvas.restore();

  // The frame, so the edge being placed against is clear.
  canvas.drawRect(
      it.frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale
        ..color = stageBlue);
  canvas.restore();
}

/// paintKnife draws the knife's line over a pale edge, so it shows on
/// anything.
void paintKnife(
    Canvas canvas, List<Offset> knife, double scale, Offset origin) {
  if (knife.length < 2) return;
  var path = lineOnScreen(knife, scale, origin);
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xCCFFFFFF));
  canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFE53935));
}

/// paintVectorEditing draws a drawing being edited point by point, in place
/// of a selection box: the pencil's mirror lines, the shapes tool's box,
/// and unless bare, the drawing's outlines, points and handles.
void paintVectorEditing(
    Canvas canvas, StageVectorEdit editing, double scale, Offset origin) {
  // Bare while painting (tint, or the pencil with points hidden).
  if (editing.mirror case var m?) {
    paintMirrorLines(canvas, editing.element, m.across, m.down, scale, origin);
  }
  if (editing.shapeBox case var box?) {
    paintShapeBox(canvas, editing.element, box, scale, origin,
        turnable: editing.turnable);
  }
  if (editing.bare) return;
  paintVectorControls(canvas, editing.element, editing.shape, editing.pick,
      {...editing.picks, ...editing.boxed}, scale, origin,
      everyShape: editing.boxing, combining: editing.combining);
}

/// paintCaret draws a drawing's text caret, [caret] its top and bottom on
/// the page.
void paintCaret(
    Canvas canvas, (Offset, Offset)? caret, double scale, Offset origin) {
  if (caret case (var top, var bottom)?) {
    canvas.drawLine(
        top * scale + origin,
        bottom * scale + origin,
        Paint()
          ..color = stageBlue
          ..strokeWidth = 1.5);
  }
}

/// paintMarquee draws the box being dragged, [marquee] on the page.
void paintMarquee(Canvas canvas, Rect? marquee, double scale, Offset origin) {
  if (marquee == null) return;
  var box = onScreen(marquee, scale, origin);
  canvas.drawRect(box, Paint()..color = stageBlue.withAlpha(0x22));
  canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stageBlue.withAlpha(0xAA));
}

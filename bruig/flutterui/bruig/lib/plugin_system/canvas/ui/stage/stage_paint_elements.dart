import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

// stage_paint_elements.dart is what the stage marks on elements other than
// by the selection's box: every element's box, each Camera's frame, a
// game's touch areas, the links between text boxes and a text box's grips,
// a chart's placed labels, a table's column rules, a Layout's lines, knobs
// and reading numbers, and a path's points. Drawn from the marks on
// elements and, for boxes and cameras, the page shown, in stage pixels:
// [scale] pixels to a document unit, the document's top-left at [origin].

/// paintKeptBoxes outlines every element when showAllBounds is set,
/// quieter than the selection and under it; [selected] are left to the
/// selection's own box.
void paintKeptBoxes(Canvas canvas, bool showAllBounds, Set<String> selected,
    StageShown shown, LiveMotion? motion, double scale, Offset origin) {
  if (!showAllBounds) return;
  var document = shown.document;
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = stageBlue.withAlpha(0x80);

  for (var element in document.elements) {
    if (!element.visible) continue;
    if (selected.contains(element.id)) continue;

    // Its box as laid on the page, turned and slanted.
    var box = element.movedBoundsAt(shown.frame, document, live: motion);
    var corners =
        BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
            .corners(box);
    canvas.drawPath(
        Path()..addPolygon([for (var p in corners) p * scale + origin], true),
        paint);
  }
}

/// paintCameras draws each Camera's frame over the page, unless the
/// stage says not ([camerasShown]): while looking through one, when the
/// page is the frame, and on a 3D stage, where it is in the scene.
void paintCameras(Canvas canvas, bool camerasShown, StageShown shown,
    LiveMotion? motion, double scale, Offset origin) {
  if (!camerasShown) return;
  var document = shown.document;
  var frame = shown.frame;
  for (var cam in document.elements.whereType<CameraElement>()) {
    if (!cam.visible) continue;
    var r = cameraFrame(cam, frame, document, live: motion);
    var box = onScreen(r, scale, origin);
    var ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xE6F2A33D);
    // Turned by its roll, as what it takes in is.
    var roll = cameraLookAt(cam, frame, document, live: motion).roll;
    canvas.save();
    if (roll != 0) {
      canvas.translate(box.center.dx, box.center.dy);
      canvas.rotate(roll * math.pi / 180);
      canvas.translate(-box.center.dx, -box.center.dy);
    }
    // Dashed round, and solid at its corners, as a viewfinder.
    const dash = 8.0, gap = 6.0;
    for (var (a, b) in [
      (box.topLeft, box.topRight),
      (box.topRight, box.bottomRight),
      (box.bottomRight, box.bottomLeft),
      (box.bottomLeft, box.topLeft),
    ]) {
      drawDashedLine(canvas, a, b, ink, dash: dash, gap: gap);
    }
    var corner = math.min(18.0, box.shortestSide / 4);
    var solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFF2A33D);
    for (var (c, dx, dy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomRight, -1.0, -1.0),
      (box.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(corner * dx, 0), solid);
      canvas.drawLine(c, c + Offset(0, corner * dy), solid);
    }
    canvas.restore();
    // Its name on a tab inside its corner, to take hold of where its edge
    // lies on the page's (see cameraTab).
    var tab = cameraTab(cam, r, scale);
    var at = onScreen(tab, scale, origin);
    canvas.drawRRect(RRect.fromRectAndRadius(at, const Radius.circular(3)),
        Paint()..color = const Color(0xFFF2A33D));
    var label = TextPainter(
      text: TextSpan(
          text: cam.name,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1B1408))),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, at.width - 20));
    label.paint(
        canvas, at.topLeft + Offset(18, (at.height - label.height) / 2));
    _paintCameraIcon(canvas, at.topLeft + Offset(4, at.height / 2));
  }
}

/// _paintCameraIcon draws a small film camera, [left] its left middle.
void _paintCameraIcon(Canvas canvas, Offset left) {
  var ink = Paint()..color = const Color(0xFF1B1408);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left.dx, left.dy - 4, 8, 8),
          const Radius.circular(1.5)),
      ink);
  canvas.drawPath(
      Path()
        ..moveTo(left.dx + 8, left.dy - 1)
        ..lineTo(left.dx + 12, left.dy - 3.5)
        ..lineTo(left.dx + 12, left.dy + 3.5)
        ..lineTo(left.dx + 8, left.dy + 1)
        ..close(),
      ink);
}

/// paintFlowLines draws the links between text boxes from a list, not the
/// selection, before anything can return early: a link belongs to two
/// boxes, and one asked to stay visible shows whatever is selected.
void paintFlowLines(Canvas canvas, List<FlowLine> flowLines) {
  for (var line in flowLines) {
    // Red: the box the words leave has more than it can show.
    var colour = line.overflowing ? const Color(0xFFE5484D) : stageBlue;
    canvas.drawLine(
        line.from,
        line.to,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colour.withValues(alpha: 0.75));
    canvas.drawCircle(line.to, 3.5, Paint()..color = colour);
  }
}

/// paintFlowGrips draws a text box's two chain dots: where words come in,
/// and where the ones that do not fit go; and the link being dragged out
/// of it, [flowDrag].
void paintFlowGrips(Canvas canvas, TextFlowGrips? grips, FlowLine? flowDrag) {
  if (grips == null) return;

  // Red is the only sign on the canvas of words the box is not showing.
  var out = grips.overflowing ? const Color(0xFFE5484D) : stageBlue;

  if (flowDrag case var dragged?) {
    canvas.drawLine(
        dragged.from,
        dragged.to,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = out);
    canvas.drawCircle(dragged.to, 4, Paint()..color = out);
  }

  void dot(Offset at, Color colour, bool filled) {
    // The grip's own size, not the resize handles'.
    var radius = flowGripSize / 2 + 1;
    drawRoundKnob(canvas, at, radius,
        fill: filled ? colour : const Color(0xFFFFFFFF),
        edge: colour,
        width: 1.2);
  }

  dot(grips.inAt, stageBlue, grips.receiving);
  dot(grips.outAt, out, grips.overflowing || grips.linked);
}

/// paintTouchAreas outlines each element's game touch area.
void paintTouchAreas(
    Canvas canvas, List<Rect> touchAreas, double scale, Offset origin) {
  if (touchAreas.isEmpty) return;
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xCC5AA9FF);
  for (var r in touchAreas) {
    canvas.drawRect(onScreen(r, scale, origin), line);
  }
}

/// paintChartLabels outlines a chart's placed labels, dashed so it does
/// not read as design, with a resize grip on the corner of each that
/// resizes.
void paintChartLabels(Canvas canvas, List<({Rect rect, bool grip})> labels,
    double scale, Offset origin) {
  if (labels.isEmpty) return;
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = stageBlue.withAlpha(0x88);

  for (var (:rect, :grip) in labels) {
    var box = onScreen(rect, scale, origin);
    for (var (from, to) in [
      (box.topLeft, box.topRight),
      (box.bottomLeft, box.bottomRight),
      (box.topLeft, box.bottomLeft),
      (box.topRight, box.bottomRight),
    ]) {
      drawDashedLine(canvas, from, to, line, dash: 5, gap: 4);
    }
    if (!grip) continue;
    canvas.drawRect(
        Rect.fromCenter(center: box.bottomRight, width: 7, height: 7),
        Paint()..color = stageBlue);
  }
}

/// paintTableColumns puts a short bar at the top and bottom of each inner
/// column rule, which the table draws itself.
void paintTableColumns(Canvas canvas, List<(double, double, double)> columns,
    double scale, Offset origin) {
  if (columns.isEmpty) return;
  var paint = Paint()..color = stageBlue;

  for (var (x, top, bottom) in columns) {
    for (var grip in tableColumnGrips(
        Offset(x, top) * scale + origin, Offset(x, bottom) * scale + origin)) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(grip, const Radius.circular(2)), paint);
    }
  }
}

/// paintLayoutMarks shows a selected Layout's lines that can be dragged,
/// and its picked cell outlined.
void paintLayoutMarks(
    Canvas canvas, LayoutMarks? marks, double scale, Offset origin) {
  if (marks == null) return;
  saveInDocument(canvas, scale, origin);
  var thin = 1.5 / scale;
  for (var (a, b) in marks.lines) {
    canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = thin * 2
          ..color = stageBlue.withAlpha(0x55));
    canvas.drawCircle(
        Offset.lerp(a, b, 0.5)!, 5 / scale, Paint()..color = stageBlue);
  }
  // A cut's own knobs: a ring turns it, a square on its gutter's edge
  // widens the gutter.
  var blue = Paint()..color = stageBlue;
  var white = Paint()..color = const Color(0xFFFFFFFF);
  var edge = Paint()
    ..strokeWidth = thin
    ..color = stageBlue.withAlpha(0xAA);
  for (var k in marks.knobs) {
    canvas.drawLine(k.edgeA.$1, k.edgeA.$2, edge);
    canvas.drawLine(k.edgeB.$1, k.edgeB.$2, edge);
    drawRoundKnob(canvas, k.turn, 5.5 / scale, width: thin * 1.4);
    canvas.drawCircle(k.turn, 1.8 / scale, blue);
    var square = Rect.fromCenter(
        center: k.gutter, width: 11 / scale, height: 11 / scale);
    canvas.drawRect(square, white);
    canvas.drawRect(square.deflate(1.5 / scale), blue);
  }
  // Each cell's place in the reading order: blue, or amber while it is
  // being clicked; a ring with a dash for one left out.
  for (var b in marks.badges) {
    var colour = b.ordering ? const Color(0xFFF2A33D) : stageBlue;
    var r = 13 / scale;
    if (b.number == null) {
      canvas.drawCircle(b.at, r, Paint()..color = const Color(0xDDFFFFFF));
      canvas.drawCircle(
          b.at,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thin * 1.4
            ..color = colour);
    } else {
      canvas.drawCircle(b.at, r, Paint()..color = colour);
    }
    var label = TextPainter(
      text: TextSpan(
          text: b.number == null ? "–" : "${b.number}",
          style: TextStyle(
              fontSize: 13 / scale,
              fontWeight: FontWeight.w700,
              color: b.number == null ? colour : const Color(0xFFFFFFFF))),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, b.at - Offset(label.width / 2, label.height / 2));
    label.dispose();
  }
  if (marks.picked.value case var path?) {
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thin * 2
          ..color = stageBlue);
  }
  canvas.restore();
}

/// paintPathControls draws a path's points, and handles where a node is
/// bent (an unbent node's sit on it).
void paintPathControls(
    Canvas canvas, PathElement path, double scale, Offset origin) {
  Offset at(Offset doc) => doc * scale + origin;

  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = stageBlue.withAlpha(0x88);

  for (var node in path.nodes) {
    var point = at(path.pointOf(node));

    for (var (dx, dy, handle) in [
      (node.outDx, node.outDy, path.outHandleOf(node)),
      (node.inDx, node.inDy, path.inHandleOf(node)),
    ]) {
      if (!handleBent(dx, dy)) continue;
      var end = at(handle);
      canvas.drawLine(point, end, line);
      drawRoundKnob(canvas, end, 4, edge: stageBlue.withAlpha(0x88), width: 1);
    }

    // The point last, over its handle lines.
    drawRoundKnob(canvas, point, 5, width: 2);
    canvas.drawCircle(point, 2.5, Paint()..color = stageBlue);
  }
}

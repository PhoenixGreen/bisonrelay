import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

// stage_paint_selection.dart is the selection as the stage draws it: its
// box, handles and turn knob, each element of several outlined, a reused
// element's copies, its motion trail and onion skin, the whole chain under
// a join being previewed, and its anchors, all drawn through the scene's
// camera as the page is. Drawn from the selection's marks, the page shown
// and what is live, in stage pixels: [scale] pixels to a document unit,
// the document's top-left at [origin].

/// chosenOutlines is every element of a multi-selection, each outlined so
/// overlapping ones can be told apart. Empty for a single selection.
List<CanvasElement> chosenOutlines(
    CanvasDocument document, Set<String> selection) {
  if (selection.length < 2) return const [];
  return [
    for (var element in document.elements)
      if (selection.contains(element.id) && element.visible) element,
  ];
}

/// paintThroughCamera paints [marks], drawn in stage space, moved as the
/// scene's [camera] (StageShown.camera) moves the page: its middle, [mid],
/// to the camera's focus, closer by its zoom.
void paintThroughCamera(Canvas canvas, (double, Offset)? camera, Offset mid,
    double scale, Offset origin, void Function() marks) {
  if (camera case (var zoom, var focus)?) {
    saveInDocument(canvas, scale, origin);
    canvas.translate(mid.dx, mid.dy);
    canvas.scale(zoom);
    canvas.translate(-focus.dx, -focus.dy);
    canvas.scale(1 / scale);
    canvas.translate(-origin.dx, -origin.dy);
    try {
      marks();
    } finally {
      canvas.restore();
    }
    return;
  }
  marks();
}

/// paintSelectionBox draws the box round the selection, [bounds] in
/// document units, turned and slanted by its frame, with its handles and
/// turn knob unless they belong to another element.
void paintSelectionBox(Canvas canvas, StageSelectionMarks selection,
    Rect bounds, double scale, Offset origin) {
  var centre = bounds.center * scale + origin;
  var half = Offset(bounds.width, bounds.height) * scale / 2;

  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  // Turned and slanted with the selection, so handles sit on its corners.
  selection.frame.applyTo(canvas, Offset.zero);
  var box = Rect.fromCenter(
      center: Offset.zero, width: half.dx * 2, height: half.dy * 2);
  canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stageBlue);
  // The line out to the rotate ring, so it reads as attached.
  if (selection.showHandles) {
    canvas.drawLine(
        Offset(0, -half.dy),
        Offset(0, -half.dy - rotateHandleGap),
        Paint()
          ..strokeWidth = 1
          ..color = stageBlue);
  }
  canvas.restore();

  // The outline alone for something placed by another element.
  if (!selection.showHandles) return;

  for (var handle in StageHandle.values) {
    var at = stageHandleAt(handle, bounds, selection.frame,
        scale: scale, origin: origin);
    if (handle == StageHandle.rotate) {
      drawRoundKnob(canvas, at, handleSize / 2 + 1);
      continue;
    }
    drawSquareHandle(canvas, at);
  }
}

/// paintChosenBoxes outlines each element of a multi-selection.
void paintChosenBoxes(Canvas canvas, Set<String> ids, StageShown shown,
    LiveMotion? motion, double scale, Offset origin) {
  var document = shown.document;
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = stageBlue.withAlpha(0x99);

  for (var element in chosenOutlines(document, ids)) {
    var box = element.movedBoundsAt(shown.frame, document, live: motion);
    var corners =
        BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
            .corners(box);
    canvas.drawPath(
        Path()..addPolygon([for (var p in corners) p * scale + origin], true),
        paint);
  }
}

/// paintWholeChain draws the element previewed from a chain join faintly
/// as its whole chain has it, to compare with where the join leaves it.
void paintWholeChain(Canvas canvas, StageShown shown, StageLive live,
    double scale, Offset origin) {
  if (live.liveMotion.value case MotionPreview(:var element, :var playing)) {
    var document = shown.document;
    var e = document.elementById(element);
    if (e == null) return;
    saveInDocument(canvas, scale, origin);
    canvas.saveLayer(null, Paint()..color = const Color(0x40000000));
    paintElement(canvas, e, shown.frame,
        frameRate: math.max(1, document.frameRate),
        images: live.images,
        document: document,
        liveMotion: playing,
        backgrounds: live.backgrounds,
        editing: true);
    canvas.restore();
    canvas.restore();
  }
}

/// paintTrail draws the selected element's motion while open in the
/// Chain: its middle's path three seconds either side of now, dashed, and
/// faint copies where it was a moment before. Nothing if it stands still.
void paintTrail(Canvas canvas, StageSelectionMarks selection, StageShown shown,
    StageLive live, double scale, Offset origin) {
  if (!selection.trail || selection.ids.length != 1) return;
  var document = shown.document;
  var frame = shown.frame;
  var motion = live.liveMotion.value;
  var e = document.elementById(selection.ids.first);
  if (e == null || e.base.motion.isEmpty || e is CameraElement) return;
  var rate = math.max(1, document.frameRate);
  var last = math.max(0, document.frames - 1);
  Keyframe at(int f) => poseWithMotion(e, f, document,
      live: motion == null ? null : liveShifted(motion, (f - frame) / rate));
  var reach = rate * 3, step = math.max(1, rate ~/ 12);
  var points = <Offset>[
    for (var f = math.max(0, frame - reach);
        f <= math.min(last, frame + reach);
        f += step)
      e.boundsWith(at(f)).center * scale + origin,
  ];
  if (points.length < 2) return;
  var moved = points.any((p) => (p - points.first).distance > 1);
  if (!moved) return;
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0x7762C9A0);
  // Four on, five off, along the whole path.
  var on = true;
  var left = 4.0;
  for (var i = 0; i < points.length - 1; i++) {
    var a = points[i], b = points[i + 1];
    var length = (b - a).distance;
    var done = 0.0;
    while (done < length) {
      var run = math.min(left, length - done);
      var p = a + (b - a) * (done / length);
      var q = a + (b - a) * ((done + run) / length);
      if (on) canvas.drawLine(p, q, line);
      done += run;
      left -= run;
      if (left <= 0) {
        on = !on;
        left = on ? 4 : 5;
      }
    }
  }
  // Where it was a moment before, fading the further back.
  var gap = math.max(1, (rate * 0.09).round());
  saveInDocument(canvas, scale, origin);
  for (var q = 4; q >= 1; q--) {
    var f = frame - q * gap;
    if (f < 0) continue;
    canvas.saveLayer(
        null, Paint()..color = Color.fromRGBO(0, 0, 0, 0.32 - q * 0.06));
    paintElement(canvas, e, f,
        frameRate: rate,
        images: live.images,
        document: document,
        liveMotion:
            motion == null ? null : liveShifted(motion, (f - frame) / rate),
        backgrounds: live.backgrounds,
        editing: true);
    canvas.restore();
  }
  canvas.restore();
}

/// paintCopies shows the selected reused element's copies: each outlined
/// faintly, those picked (what its chain edits) ringed and numbered.
void paintCopies(Canvas canvas, StageSelectionMarks selection, StageShown shown,
    LiveMotion? motion, double scale, Offset origin) {
  if (selection.ids.length != 1) return;
  var document = shown.document;
  var e = document.elementById(selection.ids.first);
  var set = e?.base.motion.instances;
  if (e == null || set == null || set.count < 2) return;
  var faint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = stageBlue.withAlpha(0x66);
  var ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = const Color(0xFFE2B04A);
  for (var (i, copy) in set.items.indexed) {
    var box = e.boundsWith(
        poseWithMotion(e, shown.frame, document, live: motion, instance: i));
    var r = Rect.fromLTRB(
        box.left * scale + origin.dx,
        box.top * scale + origin.dy,
        box.right * scale + origin.dx,
        box.bottom * scale + origin.dy);
    var picked = selection.pickedCopies.contains(copy.id);
    // A lone pick has the selection's box instead (see CanvasStage's
    // _oneCopy), so only its number.
    var boxed = picked && selection.pickedCopies.length == 1;
    if (!boxed) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r.inflate(picked ? 3 : 1), const Radius.circular(3)),
          picked ? ring : faint);
    }
    if (!picked) continue;
    var tp = TextPainter(
        text: TextSpan(
            text: "#${i + 1}",
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B1A22))),
        textDirection: TextDirection.ltr)
      ..layout();
    var tag = Rect.fromLTWH(
        r.left - 3, r.top - tp.height - 7, tp.width + 8, tp.height + 3);
    canvas.drawRRect(RRect.fromRectAndRadius(tag, const Radius.circular(3)),
        Paint()..color = const Color(0xFFE2B04A));
    tp.paint(canvas, tag.topLeft + const Offset(4, 1.5));
  }
}

/// paintAnchors draws each anchor as a ring and cross, grey where locked.
void paintAnchors(Canvas canvas, List<({Offset at, bool locked})> anchors,
    double scale, Offset origin) {
  for (var a in anchors) {
    var c = a.at * scale + origin;
    var ink = a.locked ? const Color(0xFF9E9E9E) : stageBlue;
    var halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = const Color(0xCCFFFFFF);
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ink;
    for (var paint in [halo, line]) {
      canvas.drawCircle(c, 6, paint);
      canvas.drawLine(c - const Offset(anchorReach, 0),
          c + const Offset(anchorReach, 0), paint);
      canvas.drawLine(c - const Offset(0, anchorReach),
          c + const Offset(0, anchorReach), paint);
    }
    canvas.drawCircle(c, 1.8, Paint()..color = ink);
  }
}

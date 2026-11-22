part of 'stage_painter.dart';

// What is drawn over the elements: chart labels, the knife's line, cameras and
// the selection. Part of StagePainter: its fields, lifecycle and build are in
// stage_painter.dart.

extension StagePainterMarks on StagePainter {
  /// _skippedWords is the words an open editor draws itself, which the
  /// canvas leaves out: a piece's id, textBodyWords for the paragraph, or
  /// null while the canvas draws them under a see-through field.
  String? _skippedWords(CanvasDocument document) {
    var id = editingText;
    if (id == null) return null;
    var e = document.elementById(id);
    if (e is! TextElement) return null;
    TextItem? item;
    for (var it in e.items) {
      if (it.id == editingItem) item = it;
    }
    if (!editorDrawsWords(e, item)) return null;
    return item?.id ?? textBodyWords;
  }

  /// _paintContents is the page being edited as the editor shows it, without
  /// its backdrop unless [part] is all.
  void _paintContents(Canvas canvas, CanvasDocument document, int frame,
      {CanvasPaintPart part = CanvasPaintPart.contents,
      (double, Offset)? camera,
      LiveMotion? live}) {
    paintCanvasDocument(canvas, document,
        frame: frame,
        part: part,
        camera: camera,
        images: images,
        hoveredButton: hoveredButton,
        // Only words the editor shows itself (see editorDrawsWords): the
        // box and the other pieces stay, and usually nothing is left out.
        skipTextItem: _skippedWords(document),
        counterValue: counterValue,
        liveMotion: live ?? liveMotion,
        counterPressed: counterPressed,
        counterRunning: counterRunning,
        audioState: audioState,
        videoShow: videoShow,
        // Kept while design and size hold still: the editor repaints on
        // every pointer move.
        backgrounds: backgrounds,
        // Guide paths show only while editing.
        editing: true,
        previewing: previewing);
  }

  /// _paintLayoutMarks shows a selected Layout's lines that can be dragged,
  /// and its picked cell outlined.
  void _paintLayoutMarks(Canvas canvas) {
    var marks = layoutMarks;
    if (marks == null) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    var thin = 1.5 / scale;
    for (var (a, b) in marks.lines) {
      canvas.drawLine(
          a,
          b,
          Paint()
            ..strokeWidth = thin * 2
            ..color = const Color(0x553D7EFF));
      canvas.drawCircle(Offset.lerp(a, b, 0.5)!, 5 / scale,
          Paint()..color = const Color(0xFF3D7EFF));
    }
    // A cut's own knobs: a ring turns it, a square on its gutter's edge
    // widens the gutter.
    var blue = Paint()..color = const Color(0xFF3D7EFF);
    var white = Paint()..color = const Color(0xFFFFFFFF);
    var ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thin * 1.4
      ..color = const Color(0xFF3D7EFF);
    var edge = Paint()
      ..strokeWidth = thin
      ..color = const Color(0xAA3D7EFF);
    for (var k in marks.knobs) {
      canvas.drawLine(k.edgeA.$1, k.edgeA.$2, edge);
      canvas.drawLine(k.edgeB.$1, k.edgeB.$2, edge);
      canvas.drawCircle(k.turn, 5.5 / scale, white);
      canvas.drawCircle(k.turn, 5.5 / scale, ring);
      canvas.drawCircle(k.turn, 1.8 / scale, blue);
      var square =
          Rect.fromCenter(center: k.gutter, width: 11 / scale, height: 11 / scale);
      canvas.drawRect(square, white);
      canvas.drawRect(square.deflate(1.5 / scale), blue);
    }
    // Each cell's place in the reading order: blue, or amber while it is
    // being clicked; a ring with a dash for one left out.
    for (var b in marks.badges) {
      var colour =
          b.ordering ? const Color(0xFFF2A33D) : const Color(0xFF3D7EFF);
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
    if (marks.picked case var path?) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thin * 2
            ..color = const Color(0xFF3D7EFF));
    }
    canvas.restore();
  }

  /// _paintChartLabels outlines a chart's placed labels, dashed so it does
  /// not read as design, with a resize grip on the corner of each that
  /// resizes.
  void _paintChartLabels(Canvas canvas) {
    if (chartLabels.isEmpty) return;
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x883D7EFF);

    for (var (:rect, :grip) in chartLabels) {
      var box = Rect.fromPoints(
          rect.topLeft * scale + origin, rect.bottomRight * scale + origin);
      const dash = 5.0, gap = 4.0;
      for (var (from, to) in [
        (box.topLeft, box.topRight),
        (box.bottomLeft, box.bottomRight),
        (box.topLeft, box.bottomLeft),
        (box.topRight, box.bottomRight),
      ]) {
        var span = (to - from).distance;
        if (span <= 0) continue;
        var step = (to - from) / span;
        for (var at = 0.0; at < span; at += dash + gap) {
          canvas.drawLine(
              from + step * at, from + step * math.min(at + dash, span), line);
        }
      }
      if (!grip) continue;
      canvas.drawRect(
          Rect.fromCenter(center: box.bottomRight, width: 7, height: 7),
          Paint()..color = const Color(0xFF3D7EFF));
    }
  }

  /// _paintTableColumns puts a short bar at the top and bottom of each inner
  /// column rule, which the table draws itself.
  void _paintTableColumns(Canvas canvas) {
    if (tableColumns.isEmpty) return;
    var paint = Paint()..color = const Color(0xFF3D7EFF);

    for (var (x, top, bottom) in tableColumns) {
      var at = x * scale + origin.dx;
      var t = top * scale + origin.dy;
      var b = bottom * scale + origin.dy;
      for (var y in [t + 5, b - 5]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(at, y), width: 4, height: 12),
                const Radius.circular(2)),
            paint);
      }
    }
  }

  /// _paintKnife draws the knife's line over a pale edge, so it shows on
  /// anything.
  void _paintKnife(Canvas canvas) {
    if (knife.length < 2) return;
    var path = Path()
      ..moveTo(knife.first.dx * scale + origin.dx,
          knife.first.dy * scale + origin.dy);
    for (var p in knife.skip(1)) {
      path.lineTo(p.dx * scale + origin.dx, p.dy * scale + origin.dy);
    }
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

  /// _paintAnchors draws each anchor as a ring and cross, grey where locked.
  void _paintAnchors(Canvas canvas) {
    for (var a in anchors) {
      var c = a.at * scale + origin;
      var ink = a.locked ? const Color(0xFF9E9E9E) : const Color(0xFF3D7EFF);
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
        canvas.drawLine(
            c - const Offset(10, 0), c + const Offset(10, 0), paint);
        canvas.drawLine(
            c - const Offset(0, 10), c + const Offset(0, 10), paint);
      }
      canvas.drawCircle(c, 1.8, Paint()..color = ink);
    }
  }

  /// _paintTouchAreas outlines each element's game touch area.
  void _paintTouchAreas(Canvas canvas) {
    if (touchAreas.isEmpty) return;
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xCC5AA9FF);
    for (var r in touchAreas) {
      canvas.drawRect(
          Rect.fromPoints(r.topLeft * scale + origin, r.bottomRight * scale + origin),
          line);
    }
  }

  /// _paintCameras draws each Camera's frame over the page, except while
  /// looking through it, when the page is the frame.
  void _paintCameras(Canvas canvas) {
    // On a 3D stage it is in the scene, not a frame on the page.
    if (camera != null || directed || isStageScene(document)) {
      return;
    }
    for (var cam in document.elements.whereType<CameraElement>()) {
      if (!cam.visible) continue;
      var r = cameraFrame(cam, frame, document, live: liveMotion);
      var box = Rect.fromPoints(
          r.topLeft * scale + origin, r.bottomRight * scale + origin);
      var ink = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xE6F2A33D);
      // Turned by its roll, as what it takes in is.
      var roll = cameraLookAt(cam, frame, document, live: liveMotion).roll;
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
        var d = b - a;
        var length = d.distance;
        if (length <= 0) continue;
        var unit = d / length;
        for (var t = 0.0; t < length; t += dash + gap) {
          canvas.drawLine(
              a + unit * t, a + unit * math.min(length, t + dash), ink);
        }
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
      var at = Rect.fromPoints(
          tab.topLeft * scale + origin, tab.bottomRight * scale + origin);
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

  /// _throughCamera paints [marks], drawn in stage space, moved as the
  /// scene's [camera] moves the page: its middle to the camera's focus,
  /// closer by its zoom.
  void _throughCamera(Canvas canvas, void Function() marks) {
    if (camera case (var zoom, var focus)?) {
      var mid = document.size.rect.center;
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
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

  void _paintSelection(Canvas canvas) {
    if (!showHelpers) return;

    _paintCameras(canvas);
    _paintKeptBoxes(canvas);
    _paintFlowLines(canvas);
    _paintTouchAreas(canvas);

    _paintChartLabels(canvas);
    _paintLayoutMarks(canvas);
    _paintTableColumns(canvas);
    // A path shows points and handles, not a box: the box round a curve
    // cannot be usefully dragged.
    var path = selectedPath;
    if (path != null) {
      _paintPathControls(canvas, path);
      return;
    }
    if (editingLayers case var layers?) {
      _paintLayerBoxes(canvas, layers);
      return;
    }
    if (editingVector case var editing?) {
      // Bare while painting (tint, or the pencil with points hidden).
      if (editing.mirror case var m?) {
        _paintMirrorLines(canvas, editing.element, m.across, m.down);
      }
      if (editing.shapeBox case var box?) {
        _paintShapeBox(canvas, editing.element, box,
            turnable: editing.turnable);
      }
      if (editing.bare) return;
      _paintVectorControls(canvas, editing.element, editing.shape, editing.pick,
          {...editing.picks, ...editing.boxed},
          everyShape: editing.boxing, combining: editing.combining);
      return;
    }

    var bounds = selectionBounds;
    if (bounds == null) return;

    // Each element of a multi-selection outlined under the group's box,
    // without handles: the group is what is resized.
    _paintChosenBoxes(canvas);
    _paintWholeChain(canvas);
    _paintTrail(canvas);
    _paintCopies(canvas);

    var centre = bounds.center * scale + origin;
    var half = Offset(bounds.width, bounds.height) * scale / 2;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // Turned and slanted with the selection, so handles sit on its corners.
    BoxFrame(selectionRotation * 180 / math.pi, selectionSkew.dx,
            selectionSkew.dy)
        .applyTo(canvas, Offset.zero);
    var box = Rect.fromCenter(
        center: Offset.zero, width: half.dx * 2, height: half.dy * 2);
    canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF3D7EFF));
    // The line out to the rotate ring, so it reads as attached.
    if (showHandles) {
      canvas.drawLine(
          Offset(0, -half.dy),
          Offset(0, -half.dy - rotateHandleGap),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFF3D7EFF));
    }
    canvas.restore();

    // The outline alone for something placed by another element.
    if (!showHandles) return;

    var fill = Paint()..color = const Color(0xFFFFFFFF);
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF3D7EFF);

    for (var handle in StageHandle.values) {
      var at = handleFor(handle, bounds);
      if (handle == StageHandle.rotate) {
        canvas.drawCircle(at, handleSize / 2 + 1, fill);
        canvas.drawCircle(at, handleSize / 2 + 1, edge);
        continue;
      }
      var square =
          Rect.fromCenter(center: at, width: handleSize, height: handleSize);
      canvas.drawRect(square, fill);
      canvas.drawRect(square, edge);
    }

    _paintFlowGrips(canvas);
  }

  /// _paintChosenBoxes outlines each element of a multi-selection.
  void _paintChosenBoxes(Canvas canvas) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x993D7EFF);

    for (var element in chosenOutlines(document, selection, frame)) {
      var box = element.movedBoundsAt(frame, document, live: liveMotion);
      var corners =
          BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
              .corners(box);
      canvas.drawPath(
          Path()..addPolygon([for (var p in corners) p * scale + origin], true),
          paint);
    }
  }

  /// _paintWholeChain draws the element previewed from a chain join faintly
  /// as its whole chain has it, to compare with where the join leaves it.
  void _paintWholeChain(Canvas canvas) {
    if (liveMotion case MotionPreview(:var element, :var playing)) {
      var e = document.elementById(element);
      if (e == null) return;
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
      canvas.saveLayer(null, Paint()..color = const Color(0x40000000));
      paintElement(canvas, e, frame,
          frameRate: math.max(1, document.frameRate),
          images: images,
          document: document,
          liveMotion: playing,
          backgrounds: backgrounds,
          editing: true);
      canvas.restore();
      canvas.restore();
    }
  }
}

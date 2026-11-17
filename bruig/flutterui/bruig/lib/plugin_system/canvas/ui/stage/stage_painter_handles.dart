part of 'stage_painter.dart';

// The handles and guides of the tools: trails, copies, the warp grid, flow
// grips, shape and layer boxes, mirror lines, vector and path controls, framing
// and the rulers' guides. Part of StagePainter: its fields, lifecycle and build
// are in stage_painter.dart.

extension StagePainterHandles on StagePainter {
  /// _paintTrail draws the selected element's motion while open in the
  /// Chain: its middle's path three seconds either side of now, dashed, and
  /// faint copies where it was a moment before. Nothing if it stands still.
  void _paintTrail(Canvas canvas) {
    if (!trail || selection.length != 1) return;
    var e = document.elementById(selection.first);
    if (e == null || e.base.motion.isEmpty || e is CameraElement) return;
    var rate = math.max(1, document.frameRate);
    var last = math.max(0, document.frames - 1);
    Keyframe at(int f) => poseWithMotion(e, f, document,
        live: liveMotion == null
            ? null
            : liveShifted(liveMotion!, (f - frame) / rate));
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
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    for (var q = 4; q >= 1; q--) {
      var f = frame - q * gap;
      if (f < 0) continue;
      canvas.saveLayer(
          null, Paint()..color = Color.fromRGBO(0, 0, 0, 0.32 - q * 0.06));
      paintElement(canvas, e, f,
          frameRate: rate,
          images: images,
          document: document,
          liveMotion: liveMotion == null
              ? null
              : liveShifted(liveMotion!, (f - frame) / rate),
          backgrounds: backgrounds,
          editing: true);
      canvas.restore();
    }
    canvas.restore();
  }

  /// _paintCopies shows the selected reused element's copies: each outlined
  /// faintly, those picked (what its chain edits) ringed and numbered.
  void _paintCopies(Canvas canvas) {
    if (selection.length != 1) return;
    var e = document.elementById(selection.first);
    var set = e?.base.motion.instances;
    if (e == null || set == null || set.count < 2) return;
    var faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x663D7EFF);
    var ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFE2B04A);
    for (var (i, copy) in set.items.indexed) {
      var box = e.boundsWith(
          poseWithMotion(e, frame, document, live: liveMotion, instance: i));
      var r = Rect.fromLTRB(box.left * scale + origin.dx,
          box.top * scale + origin.dy, box.right * scale + origin.dx,
          box.bottom * scale + origin.dy);
      var picked = pickedCopies.contains(copy.id);
      // A lone pick has the selection's box instead (see CanvasStage's
      // _oneCopy), so only its number.
      var boxed = picked && pickedCopies.length == 1;
      if (!boxed) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(picked ? 3 : 1),
              const Radius.circular(3)),
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

  /// _paintKeptBoxes outlines every element when [showAllBounds] is set,
  /// quieter than the selection and under it.
  void _paintKeptBoxes(Canvas canvas) {
    if (!showAllBounds) return;
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x803D7EFF);

    for (var element in document.elements) {
      if (!element.visible) continue;
      if (selection.contains(element.id)) continue;

      // Its box as laid on the page, turned and slanted.
      var box = element.movedBoundsAt(frame, document, live: liveMotion);
      var corners =
          BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
              .corners(box);
      canvas.drawPath(
          Path()..addPolygon([for (var p in corners) p * scale + origin], true),
          paint);
    }
  }

  /// _paintWarp draws a warp grid being worked on: lines dark under light,
  /// to show over any picture; points as squares, picked ones filled; and
  /// the box round the picked ones with its corners and turning knob.
  void _paintWarp(Canvas canvas, StageWarp w, Offset Function(Offset) screen) {
    for (var (width, colour) in const [
      (2.6, Color(0x88000000)),
      (1.0, Color(0xCCFFFFFF)),
    ]) {
      var paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = colour;
      for (var line in w.lines) {
        canvas.drawPath(
            Path()..addPolygon([for (var p in line) screen(p)], false), paint);
      }
    }
    const accent = Color(0xFF3D7EFF);
    for (var (k, p) in w.points.indexed) {
      var at = screen(p);
      var square = Rect.fromCenter(center: at, width: 8, height: 8);
      var picked = w.picks.contains(k);
      canvas.drawRect(
          square, Paint()..color = picked ? accent : const Color(0xFFFFFFFF));
      canvas.drawRect(
          square,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = picked ? const Color(0xFFFFFFFF) : accent);
    }
    if (w.box case var corners?) {
      var at = [for (var p in corners) screen(p)];
      canvas.drawPath(
          Path()..addPolygon(at, true),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = accent);
      for (var c in at) {
        var square = Rect.fromCenter(center: c, width: 9, height: 9);
        canvas.drawRect(square, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawRect(
            square,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent);
      }
      if (w.knob case var k?) {
        var top = (at[0] + at[1]) / 2, knob = screen(k);
        canvas.drawLine(top, knob, Paint()..color = accent);
        canvas.drawCircle(knob, 5.5, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(
            knob,
            5.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent);
      }
    }
  }

  /// _paintFlowLines draws the links between text boxes from a list, not the
  /// selection, before anything can return early: a link belongs to two
  /// boxes, and one asked to stay visible shows whatever is selected.
  void _paintFlowLines(Canvas canvas) {
    for (var line in flowLines) {
      // Red: the box the words leave has more than it can show.
      var colour =
          line.overflowing ? const Color(0xFFE5484D) : const Color(0xFF3D7EFF);
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

  /// _paintFlowGrips draws a text box's two chain dots: where words come in,
  /// and where the ones that do not fit go.
  void _paintFlowGrips(Canvas canvas) {
    var white = Paint()..color = const Color(0xFFFFFFFF);
    var blue = const Color(0xFF3D7EFF);

    var grips = flowGrips;
    if (grips == null) return;

    // Red is the only sign on the canvas of words the box is not showing.
    var out = grips.overflowing ? const Color(0xFFE5484D) : blue;

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
      canvas.drawCircle(at, radius, filled ? (Paint()..color = colour) : white);
      canvas.drawCircle(
          at,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = colour);
    }

    dot(grips.inAt, blue, grips.receiving);
    dot(grips.outAt, out, grips.overflowing || grips.linked);
  }

  /// _paintShapeBox draws the box round the shape the shapes tool picked, in
  /// the drawing's units [box], with move and resize handles.
  void _paintShapeBox(Canvas canvas, VectorElement e, Rect box,
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
      var knob = top - const Offset(0, shapeTurnReach);
      canvas.drawLine(
          top,
          knob,
          Paint()
            ..strokeWidth = 1
            ..color = colour);
      canvas.drawCircle(knob, 5, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
          knob,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour);
    }
    for (var h in boxHandles(box)) {
      var r = Rect.fromCenter(center: screen(h), width: 8, height: 8);
      canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour);
    }
  }

  /// _paintLayerBoxes draws the layers of a picture being edited: a faint
  /// outline round each layer that can be picked, and the picked one's box
  /// with its handles and turning knob.
  void _paintLayerBoxes(Canvas canvas, StageLayers layers) {
    Offset screen(Offset p) => p * scale + origin;
    if (layers.masking case var m? when m.view != MaskView.result) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
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
      for (var (width, colour) in const [
        (3.0, Color(0xAA000000)),
        (1.2, Color(0xFFFFFFFF)),
      ]) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeJoin = StrokeJoin.round
              ..color = colour);
      }
    }
    if (layers.warp case var w?) _paintWarp(canvas, w, screen);
    if (layers.marker case var m?) {
      var at = screen(m);
      for (var (width, colour) in const [
        (3.0, Color(0xAA000000)),
        (1.2, Color(0xFFFFFFFF)),
      ]) {
        var paint = Paint()
          ..strokeWidth = width
          ..color = colour;
        canvas.drawLine(
            at - const Offset(8, 0), at + const Offset(8, 0), paint);
        canvas.drawLine(
            at - const Offset(0, 8), at + const Offset(0, 8), paint);
      }
    }
    if (layers.ring case (var centre, var radius)) {
      var at = screen(centre);
      var r = radius * scale;
      for (var (width, colour) in const [
        (3.0, Color(0xAA000000)),
        (1.2, Color(0xFFFFFFFF)),
      ]) {
        canvas.drawCircle(
            at,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..color = colour);
      }
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
      canvas.drawCircle(at, 5, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
          at,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour);
    }
    for (var h in layers.handles) {
      var r = Rect.fromCenter(center: screen(h), width: 8, height: 8);
      canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = colour);
    }
  }

  /// _paintMirrorLines draws the pencil's dashed mirror lines through the
  /// middle of the drawing [e], so a stroke's mirror can be foreseen.
  void _paintMirrorLines(
      Canvas canvas, VectorElement e, bool across, bool down) {
    if (!across && !down) return;
    var space = VectorSpace(e);
    var v = e.viewBox;
    // A little past the drawing, so it reads as a line, not an edge.
    var r = v.inflate(math.max(v.width, v.height) * 0.1);
    var paint = Paint()
      ..color = e.handleColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    void dashed(Offset a, Offset b) {
      var from = space.toCanvas(a) * scale + origin;
      var to = space.toCanvas(b) * scale + origin;
      var length = (to - from).distance;
      if (length == 0) return;
      var step = (to - from) / length;
      for (var d = 0.0; d < length; d += 10) {
        canvas.drawLine(
            from + step * d, from + step * math.min(length, d + 6), paint);
      }
    }

    if (across) {
      dashed(Offset(v.center.dx, r.top), Offset(v.center.dx, r.bottom));
    }
    if (down) dashed(Offset(r.left, v.center.dy), Offset(r.right, v.center.dy));
  }

  /// _paintVectorControls draws a drawing being edited: every shape's outline
  /// faint, the picked shape's lit with its points, the points of any shape
  /// with points picked, and the handles of a single picked point.
  /// [everyShape] shows every shape's points, while a box is dragged.
  void _paintVectorControls(Canvas canvas, VectorElement e, int picked,
      VectorPick? pick, Set<VectorPick> picks,
      {bool everyShape = false, Set<int>? combining}) {
    var shapes = e.shapes;
    if (shapes == null) return;
    var space = VectorSpace(e);
    var colour = e.handleColor;
    Offset screen(Offset v) => space.toCanvas(v) * scale + origin;

    // Through the drawing's own placement and turn, so outlines lie on it.
    var place = e.placement(e.bounds, e.viewBox);
    var centre = e.bounds.center;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
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
              ..color =
                  lit ? colour : colour.withValues(alpha: colour.a * 0.35));
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
            ..color = i == picked
                ? colour
                : colour.withValues(alpha: colour.a * 0.35));
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
      var r = Rect.fromPoints(
              box.topLeft * scale + origin, box.bottomRight * scale + origin)
          .inflate(e.handleSize);
      canvas.drawRect(r, Paint()..color = colour.withValues(alpha: 0.08));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = colour.withValues(alpha: 0.6));
    }
    var size = e.handleSize;
    var fill = Paint()..color = const Color(0xFFFFFFFF);
    var ink = Paint()..color = colour;
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = colour;
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
          canvas.drawCircle(h, size / 2, fill);
          canvas.drawCircle(h, size / 2, edge);
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
            canvas.drawCircle(at, size / 2, chosen ? ink : fill);
            canvas.drawCircle(at, size / 2, edge);
          } else {
            var square = Rect.fromCenter(center: at, width: size, height: size);
            canvas.drawRect(square, chosen ? ink : fill);
            canvas.drawRect(square, edge);
          }
        }
      }
    }
  }

  /// _paintPathControls draws a path's points, and handles where a node is
  /// bent (an unbent node's sit on it).
  void _paintPathControls(Canvas canvas, PathElement path) {
    Offset at(Offset doc) => doc * scale + origin;

    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x883D7EFF);
    var fill = Paint()..color = const Color(0xFF3D7EFF);
    var knob = Paint()..color = const Color(0xFFFFFFFF);

    for (var node in path.nodes) {
      var point = at(path.pointOf(node));

      for (var (dx, dy, handle) in [
        (node.outDx, node.outDy, path.outHandleOf(node)),
        (node.inDx, node.inDy, path.inHandleOf(node)),
      ]) {
        if (dx == 0 && dy == 0) continue;
        var end = at(handle);
        canvas.drawLine(point, end, line);
        canvas.drawCircle(end, 4, knob);
        canvas.drawCircle(end, 4, line);
      }

      // The point last, over its handle lines.
      canvas.drawCircle(point, 5, knob);
      canvas.drawCircle(
          point,
          5,
          fill
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      canvas.drawCircle(point, 2.5, fill..style = PaintingStyle.fill);
    }
  }

  /// _paintFraming shows the rest of a picture moved inside its frame, faint
  /// outside the frame, so what comes into shot can be seen.
  void _paintFraming(Canvas canvas) {
    var it = framing;
    if (it == null || it.dst.isEmpty) return;

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
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
          ..color = const Color(0xFF3D7EFF));
    canvas.restore();
  }

  /// _paintGuides draws the grid, guides and whatever a drag is caught on:
  /// over the document, so a photograph cannot hide a guide, and under the
  /// selection, so handles stay findable.
  void _paintGuides(Canvas canvas) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);

    // In document units. [page] is the frame on screen; adding its offset
    // would shift every guide with the window.
    var sheet = Offset.zero & document.size.size;
    var size = sheet.size;
    canvas.clipRect(sheet);
    // Hairlines: divided by the zoom, one pixel on screen at any zoom.
    var thin = 1 / scale;

    if (guides.showGrid) {
      var (majorX, minorX) =
          gridLines(size.width, guides.gridSize, guides.subdivisions);
      var (majorY, minorY) =
          gridLines(size.height, guides.gridSize, guides.subdivisions);
      var minor = Paint()
        ..strokeWidth = thin
        ..color = const Color(0x22FFFFFF);
      var major = Paint()
        ..strokeWidth = thin
        ..color = const Color(0x40FFFFFF);

      for (var x in minorX) {
        canvas.drawLine(Offset(sheet.left + x, sheet.top),
            Offset(sheet.left + x, sheet.bottom), minor);
      }
      for (var y in minorY) {
        canvas.drawLine(Offset(sheet.left, sheet.top + y),
            Offset(sheet.right, sheet.top + y), minor);
      }
      for (var x in majorX) {
        canvas.drawLine(Offset(sheet.left + x, sheet.top),
            Offset(sheet.left + x, sheet.bottom), major);
      }
      for (var y in majorY) {
        canvas.drawLine(Offset(sheet.left, sheet.top + y),
            Offset(sheet.right, sheet.top + y), major);
      }
    }

    if (guides.showGuides) {
      var paint = Paint()
        ..strokeWidth = thin
        ..color = const Color(0xAA35C4F0);
      for (var guide in guides.guides) {
        if (guide.axis == GuideAxis.vertical) {
          canvas.drawLine(Offset(sheet.left + guide.at, sheet.top),
              Offset(sheet.left + guide.at, sheet.bottom), paint);
        } else {
          canvas.drawLine(Offset(sheet.left, sheet.top + guide.at),
              Offset(sheet.right, sheet.top + guide.at), paint);
        }
      }
    }

    // What the drag has caught, in a colour nothing else uses.
    if (snapped case var it? when it.caught) {
      var paint = Paint()
        ..strokeWidth = thin * 1.5
        ..color = const Color(0xFFFF4081);
      if (it.onVertical case var x?) {
        canvas.drawLine(Offset(sheet.left + x, sheet.top),
            Offset(sheet.left + x, sheet.bottom), paint);
      }
      if (it.onHorizontal case var y?) {
        canvas.drawLine(Offset(sheet.left, sheet.top + y),
            Offset(sheet.right, sheet.top + y), paint);
      }
    }
    canvas.restore();
  }

  /// _paintRulers draws the rulers along the page unless [rulersApart].
  void _paintRulers(Canvas canvas, Size size) {
    if (rulersApart) return;
    paintStageRulers(canvas, size, guides, document.size.size, scale, origin, page);
  }
}

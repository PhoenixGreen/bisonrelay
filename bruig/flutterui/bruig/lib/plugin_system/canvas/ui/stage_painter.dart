import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:flutter/material.dart';

// stage_painter.dart is everything the stage draws: the document itself, the
// sheet it sits on, and the marks over the top that say what is selected and
// what can be taken hold of.
//
// Split from canvas_stage.dart because the two halves have nothing to say to
// each other. This one is handed a pile of already-decided values -- where
// the handles go, which labels are placed, what the held stroke looks like --
// and draws them. It never asks a question, which is why it can be read on
// its own; deciding is the stage's half.

/// StageFraming is a picture being repositioned inside its frame, worked out
/// by the stage and drawn by [StagePainter].
///
/// [src] is the whole of the picture the frame is choosing from and [dst] is
/// where all of it would land, which is bigger than [frame] in at least one
/// direction -- that difference is precisely what is being spent. The painter
/// draws the whole of it faintly, so that what is being dragged out of shot
/// can be seen while it is being dragged.
class StageFraming {
  final ui.Image image;
  final Rect src;
  final Rect dst;

  /// frame is the element's own rectangle: the part of [dst] that is actually
  /// kept, and the only part drawn at full strength -- by the renderer, which
  /// has already drawn it under all of this.
  final Rect frame;

  /// rotation is the element's, in radians. The overlay turns with it, or a
  /// tilted photograph would be reframed against a level ghost of itself.
  final double rotation;

  const StageFraming(this.image, this.src, this.dst, this.frame, this.rotation);
}

/// StagePainter draws the document, the page edge, the handles and the
/// marquee.
class StagePainter extends CustomPainter {
  final CanvasDocument document;
  final int frame;

  /// scale is document units to screen pixels -- the fitted size times the
  /// reader's zoom, already combined by the stage.
  final double scale;
  final Offset origin;
  final CanvasImageSource images;
  final String? hoveredButton;
  final Set<String> selection;
  final Rect? selectionBounds;
  final double selectionRotation;
  final Offset Function(StageHandle, Rect) handleFor;
  final Rect? marquee;

  /// page is the frame the canvas is drawn inside. Everything the document
  /// contributes is clipped to it; the shadow and the border are drawn outside
  /// the clip, which is what keeps the edge of the canvas visible at every
  /// zoom.
  final Rect page;

  /// view is everything drawn: the page, plus the overspill around it when
  /// that is showing. The clip is this rather than [page], so an element
  /// waiting off the left of the canvas can be seen and taken hold of.
  final Rect view;

  /// selectedPath is the selected element when it is a path, whose points and
  /// handles are drawn in place of a selection box.
  final PathElement? selectedPath;

  /// chartLabels is the boxes of the selected chart's placed labels, in
  /// document units. Outlined so that a title somebody has taken control of
  /// looks like something that can be taken hold of -- placed and then not
  /// drawn, it is a piece of text that mysteriously moves when dragged and
  /// has no visible corner to resize by.
  final List<Rect> chartLabels;

  /// tableColumns is where a selected table's column rules are, in document
  /// units, so each can be given a grip.
  ///
  /// Without one there was nothing to say a rule could be dragged at all: the
  /// pointer had to be within a few pixels of a hairline nobody had been told
  /// about.
  final List<(double, double, double)> tableColumns;

  /// preview is a picture of what a held stroke would do, and previewOn is
  /// the placement it is drawn through. Both null when nothing is held.
  ///
  /// The placement, not just a destination. The preview is the size of the
  /// whole picture, and the picture is not necessarily drawn whole -- "fill
  /// the box" shows a centre crop of it. Stretching the whole preview into the
  /// element put the tint somewhere other than the stroke, over an area that
  /// had nothing to do with it.
  final ui.Image? preview;
  final ImagePlacement? previewOn;

  /// liveStroke is the retouching stroke being drawn, in canvas coordinates,
  /// with liveStrokeRadius its width and liveStrokeKeeps which way round it
  /// works.
  ///
  /// Drawn here rather than by changing the picture, because changing the
  /// picture means reprocessing every pixel of it -- see
  /// CanvasStageState._liveImage. This is what the reader watches while the
  /// stroke is being made; the picture catches up when the pointer comes up.
  final List<Offset> liveStroke;
  final double liveStrokeRadius;
  final bool liveStrokeKeeps;

  /// editingText is the id of a text element being typed into, whose own words
  /// are left unpainted -- the editor over the top is drawing them, and both
  /// at once is the same sentence twice, half a pixel apart.
  final String? editingText;

  /// showHandles is false for something whose size and angle belong to
  /// another element -- text riding a line. The outline is still drawn, so it
  /// is clear what is selected; the eight squares and the rotate ring are not,
  /// because they would be controls that appear to do nothing.
  final bool showHandles;

  /// framing is the picture being repositioned inside its frame, if one is.
  final StageFraming? framing;

  /// showHelpers draws the selection box, the handles and the rotation ring.
  ///
  /// Passed in rather than being faked by blanking the selection, which is how
  /// this was first written and did nothing at all: _paintSelection reads
  /// selectionBounds, not the selection, so emptying the set left every mark
  /// exactly where it was.
  final bool showHelpers;

  /// The picture store is handed to CustomPainter as something to repaint on,
  /// which is the only way a picture that arrives late reaches the screen.
  ///
  /// Pictures load off the disk after the frame that asked for them: the
  /// painter draws a placeholder, the bytes turn up a moment later and the
  /// store says so. Nothing else here changes when that happens -- the
  /// document is the same, the selection is the same -- so shouldRepaint
  /// answered no and the placeholder stayed until something unrelated forced
  /// a repaint. The reported version of that was a picture put in a table
  /// cell showing a grey crossed box until another cell was clicked.
  StagePainter({
    required this.page,
    required this.view,
    required this.showHandles,
    required this.showHelpers,
    required this.framing,
    required this.selectedPath,
    required this.chartLabels,
    required this.tableColumns,
    required this.editingText,
    required this.preview,
    required this.previewOn,
    required this.liveStroke,
    required this.liveStrokeRadius,
    required this.liveStrokeKeeps,
    required this.document,
    required this.frame,
    required this.scale,
    required this.origin,
    required this.images,
    required this.hoveredButton,
    required this.selection,
    required this.selectionBounds,
    required this.selectionRotation,
    required this.handleFor,
    required this.marquee,
  }) : super(repaint: images is Listenable ? images as Listenable : null);

  @override
  void paint(Canvas canvas, Size size) {
    // A shadow under the frame, so the canvas reads as a sheet on a desk
    // rather than as a region of the window -- which matters most when the
    // document's own background happens to be the same colour as the editor's.
    canvas.drawRect(
        view.shift(const Offset(0, 6)),
        Paint()
          ..color = const Color(0x55000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));

    // Everything the document contributes goes inside the frame, at whatever
    // zoom, including the selection handles. The frame itself never moves --
    // see CanvasStage._pageRect.
    canvas.save();
    canvas.clipRect(view);

    var docSize = document.size.size;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    paintCanvasDocument(canvas, document,
        frame: frame,
        images: images,
        hoveredButton: hoveredButton,
        skipElement: editingText,
        // Guide paths show here and nowhere else: the line describing a run is
        // scaffolding, and a published diagram with every run drawn on it is
        // unreadable.
        editing: true);
    canvas.restore();

    _paintFraming(canvas);
    _paintSelection(canvas);

    if (marquee != null) {
      var box = Rect.fromPoints(marquee!.topLeft * scale + origin,
          marquee!.bottomRight * scale + origin);
      canvas.drawRect(box, Paint()..color = const Color(0x223D7EFF));
      canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xAA3D7EFF));
    }

    // What a held stroke would do, over the picture it belongs to. Drawn from
    // the brush's own output rather than from its settings, so what is shown
    // and what will happen cannot drift apart -- see strokePreview.
    if (preview != null && previewOn != null) {
      var to = previewOn!.dst;
      canvas.drawImageRect(
          preview!,
          previewOn!.src,
          Rect.fromLTRB(
            to.left * scale + origin.dx,
            to.top * scale + origin.dy,
            to.right * scale + origin.dx,
            to.bottom * scale + origin.dy,
          ),
          Paint()..filterQuality = FilterQuality.medium);
    }

    // The stroke being drawn, inside the frame's clip along with everything
    // else the document contributes -- unclipped, a stroke on a zoomed canvas
    // carries on over the sidebar. A thick
    // round-capped line rather than a stamp per point: it is a preview of a
    // brush that will be dabbed along the same path, and the two read the same
    // at any speed the pointer moves.
    if (liveStroke.length > 1 && liveStrokeRadius > 0) {
      var path = Path()
        ..moveTo(liveStroke.first.dx * scale + origin.dx,
            liveStroke.first.dy * scale + origin.dy);
      for (var point in liveStroke.skip(1)) {
        path.lineTo(point.dx * scale + origin.dx, point.dy * scale + origin.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = liveStrokeRadius * 2 * scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = liveStrokeKeeps
                ? const Color(0x6633DD88)
                : const Color(0x66FF5544));
    }

    canvas.restore();

    // Everything outside the page dimmed, so the edge of what will actually be
    // published stays obvious. Four bands rather than a stroked rectangle with
    // a hole in it, which is what a Path.difference would be for one frame of
    // shading.
    if (view != page) {
      var shade = Paint()..color = const Color(0x66000000);
      canvas.drawRect(
          Rect.fromLTRB(view.left, view.top, view.right, page.top), shade);
      canvas.drawRect(
          Rect.fromLTRB(view.left, page.bottom, view.right, view.bottom),
          shade);
      canvas.drawRect(
          Rect.fromLTRB(view.left, page.top, page.left, page.bottom), shade);
      canvas.drawRect(
          Rect.fromLTRB(page.right, page.top, view.right, page.bottom), shade);
    }

    // The border last and outside the clip, so it is a crisp full-width line
    // rather than a half-width one sitting on the edge of the clip.
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x55FFFFFF));

    // A hint that there is more of the canvas outside the frame. Drawn only
    // when there is: at zoom 1 the document exactly fills the frame and a
    // shadow round the inside would be saying something untrue.
    if (docSize.width * scale > page.width + 1) {
      canvas.drawRect(
        page,
        Paint()
          ..shader = ui.Gradient.radial(
            page.center,
            math.max(page.width, page.height) * 0.7,
            [const Color(0x00000000), const Color(0x33000000)],
            [0.7, 1.0],
          ),
      );
    }
  }

  /// _paintChartLabels outlines a chart's placed title and description, with a
  /// grip on the corner that resizes them.
  ///
  /// Dashes rather than a solid line, so it does not read as part of the
  /// design: it is scaffolding, the same as the selection box, and it is never
  /// exported -- this painter draws over the document rather than into it.
  void _paintChartLabels(Canvas canvas) {
    if (chartLabels.isEmpty) return;
    var line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x883D7EFF);

    for (var rect in chartLabels) {
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
      canvas.drawRect(
          Rect.fromCenter(center: box.bottomRight, width: 7, height: 7),
          Paint()..color = const Color(0xFF3D7EFF));
    }
  }

  /// _paintTableColumns puts a grip on each of a table's inner column rules.
  ///
  /// A short bar at the top and the bottom rather than a line down the whole
  /// rule: the rule is already drawn by the table, and a second line over it
  /// would read as the table having two.
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

  void _paintSelection(Canvas canvas) {
    if (!showHelpers) return;

    _paintChartLabels(canvas);
    _paintTableColumns(canvas);

    // A selected path shows its points and handles instead of a box: the box
    // round a curve is a rectangle nobody drew and cannot be usefully dragged,
    // where the points are the whole of what there is to edit.
    var path = selectedPath;
    if (path != null) {
      _paintPathControls(canvas, path);
      return;
    }

    var bounds = selectionBounds;
    if (bounds == null) return;

    var centre = bounds.center * scale + origin;
    var half = Offset(bounds.width, bounds.height) * scale / 2;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (selectionRotation != 0) canvas.rotate(selectionRotation);
    var box = Rect.fromCenter(
        center: Offset.zero, width: half.dx * 2, height: half.dy * 2);
    canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF3D7EFF));
    // The line out to the rotate ring, so it reads as attached to the
    // selection rather than as a stray dot floating above it.
    if (showHandles) {
      canvas.drawLine(
          Offset(0, -half.dy),
          Offset(0, -half.dy - rotateHandleGap),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFF3D7EFF));
    }
    canvas.restore();

    // The outline alone for something placed by another element: it says what
    // is selected without offering eight squares that would do nothing.
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
  }

  /// _paintPathControls draws a path's points and its handles.
  ///
  /// Handles only where there are any: an unbent node's handles sit exactly on
  /// top of it, and drawing them there would be three overlapping dots that
  /// cannot be told apart or aimed at separately.
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

      // The point itself last, so it is on top of its own handle lines.
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

  /// _paintFraming shows the rest of the picture while it is being moved
  /// about inside its frame.
  ///
  /// Everything outside the frame is drawn faintly and everything inside it is
  /// left alone -- the renderer has already drawn that part properly, and
  /// painting it again half-transparent on top would only muddy it. Without
  /// the ghost, dragging a photograph inside its frame is done blind: what
  /// comes into shot cannot be seen until it has arrived.
  void _paintFraming(Canvas canvas) {
    var it = framing;
    if (it == null || it.dst.isEmpty) return;

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    if (it.rotation != 0) {
      canvas.translate(it.frame.center.dx, it.frame.center.dy);
      canvas.rotate(it.rotation);
      canvas.translate(-it.frame.center.dx, -it.frame.center.dy);
    }

    // The whole picture, faint, with the frame punched out of it -- so the
    // part already on the canvas shows through at full strength and the two
    // are seen as one picture rather than as two overlaid.
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

    // The frame itself, so the edge the picture is being placed against is
    // unmistakable while everything around it is half there.
    canvas.drawRect(
        it.frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = const Color(0xFF3D7EFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(StagePainter old) =>
      !identical(old.framing, framing) ||
      old.document != document ||
      old.frame != frame ||
      old.scale != scale ||
      old.origin != origin ||
      old.page != page ||
      old.view != view ||
      old.showHelpers != showHelpers ||
      old.showHandles != showHandles ||
      !identical(old.selectedPath, selectedPath) ||
      old.editingText != editingText ||
      !identical(old.preview, preview) ||
      old.previewOn != previewOn ||
      old.liveStroke.length != liveStroke.length ||
      old.liveStrokeKeeps != liveStrokeKeeps ||
      old.hoveredButton != hoveredButton ||
      old.selection != selection ||
      old.selectionBounds != selectionBounds ||
      old.marquee != marquee;
}

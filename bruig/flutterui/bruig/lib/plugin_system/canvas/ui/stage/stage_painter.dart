import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe;
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_rulers.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:flutter/material.dart';

export 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

part 'stage_painter_marks.dart';
part 'stage_painter_handles.dart';

// stage_painter.dart is everything the stage draws: the document, the sheet
// it sits on, and the marks for what is selected and what can be taken hold
// of. It is handed values the stage has already decided (the selection's box
// and frame, what a held stroke looks like), grouped by subject in
// stage_painter_inputs.dart, and only draws them.

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

/// StagePainter draws the document, page edge, handles and marquee.
class StagePainter extends CustomPainter {
  /// inputs is everything the stage is drawn from (see StageInputs).
  /// shouldRepaint compares it whole, so nothing in it can be left out.
  final StageInputs inputs;

  StagePainter(this.inputs)
      : super(
            repaint: Listenable.merge([
          // Pictures and the background arrive after the frame that asked
          // for them, and nothing else changes then, so without these a
          // placeholder would stay up.
          if (inputs.live.images is Listenable)
            inputs.live.images as Listenable,
          if (inputs.live.backgrounds case var backgrounds?) backgrounds,
          if (inputs.live.between case var between?) between,
        ]));

  // The next four are read hundreds of times a paint, so worked out once.

  /// _scale is document units to screen pixels: the fitted size times the
  /// reader's zoom.
  late final double _scale = inputs.transform.scale;

  /// _origin is the document's top-left on screen: the page's own.
  late final Offset _origin = inputs.transform.origin;

  /// _page is the frame the canvas is drawn inside; the shadow and border go
  /// outside the clip, keeping the canvas edge visible at every zoom.
  late final Rect _page = inputs.transform.pageRect;

  /// _viewRect is the page plus any overspill shown round it. The clip is
  /// this, not [_page], so an element waiting off the canvas can be taken
  /// hold of.
  late final Rect _viewRect = inputs.transform.viewRect;

  CanvasDocument get _document => inputs.shown.document;
  int get _frame => inputs.shown.frame;
  LiveMotion? get _liveMotion => inputs.live.liveMotion.value;

  @override
  void paint(Canvas canvas, Size size) => CanvasPerf.time(
      "stagePaint",
      () => inputs.shown.directed
          ? directedBy(_document, _liveMotion, () => _paintStage(canvas, size))
          : _paintStage(canvas, size));

  void _paintStage(Canvas canvas, Size size) {
    RasterCache.drafting = inputs.live.drafting;
    betweenFrames = inputs.live.between?.value ?? 0;
    try {
      _paint(canvas, size);
    } finally {
      RasterCache.drafting = false;
      betweenFrames = 0;
    }
  }

  void _paint(Canvas canvas, Size size) {
    // A shadow under the frame, so the canvas reads as a sheet even when its
    // background matches the editor's.
    var shadow = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    if (inputs.shown.previewAt case var at? when inputs.transform.spread) {
      // Only under the leaves there are: a cover stands on its own side.
      var (onLeft, onRight) = bookSides(_document, at);
      var leftLeaf = inputs.transform.facingOnLeft
          ? _page
          : _page.shift(Offset(-_page.width, 0));
      if (onLeft) canvas.drawRect(leftLeaf.shift(const Offset(0, 6)), shadow);
      if (onRight) {
        canvas.drawRect(leftLeaf.shift(Offset(_page.width, 6)), shadow);
      }
    } else {
      canvas.drawRect(
          (inputs.transform.levelShown ? _page : _viewRect)
              .shift(const Offset(0, 6)),
          shadow);
    }

    // Everything the document contributes, handles included, goes inside
    // the frame at any zoom.
    canvas.save();
    canvas.clipRect(_viewRect);

    var docSize = _document.size.size;
    canvas.save();
    canvas.translate(_origin.dx, _origin.dy);
    canvas.scale(_scale);
    // The leaf beside this one. Both backdrops go down first, then both
    // contents, so a picture across the gutter shows without a seam. The
    // neighbour is a document page even while the master is edited:
    // goToScene alone would leave onMaster set and draw the master twice.
    var beside = inputs.shown.facing;
    var over = beside == null
        ? null
        : _document.goToScene(beside.index).copyWith(onMaster: false);
    var aside = inputs.transform.facingOnLeft ? docSize.width : -docSize.width;
    // At the frame it was left on, so a chart on it neither vanishes nor
    // jumps to its end.
    var overFrame = beside?.frame ?? 0;

    if (inputs.shown.previewAt case var at?) {
      // Played as a book, each leaf is drawn in its place in the spread and
      // a transition between spreads moves both (see paintBookFrame).
      if (inputs.transform.spread) {
        paintBookFrame(canvas, _document, at,
            left: inputs.transform.facingOnLeft ? 0.0 : -docSize.width,
            images: inputs.live.images,
            backgrounds: inputs.live.backgrounds,
            audioState: inputs.live.audioState.value,
            videoShow: inputs.live.videoShow.value);
      } else {
        paintSequenceFrame(canvas, _document, at,
            images: inputs.live.images,
            backgrounds: inputs.live.backgrounds,
            audioState: inputs.live.audioState.value,
            videoShow: inputs.live.videoShow.value,
            liveMotion: _liveMotion,
            counterValue: inputs.live.counterValue.value);
      }
      canvas.restore();
      canvas.restore();
      return;
    }
    if (over != null) {
      // This page's paper goes down between the two: the neighbour's
      // backdrop under it, the neighbour's overhang over it.
      if (inputs.transform.spread) {
        canvas.save();
        canvas.translate(aside, 0);
        canvas.clipRect(Offset.zero & docSize);
        paintCanvasDocument(canvas, over,
            frame: overFrame,
            part: CanvasPaintPart.backdrop,
            images: inputs.live.images,
            backgrounds: inputs.live.backgrounds);
        canvas.restore();
      }
      paintCanvasDocument(canvas, _document,
          part: CanvasPaintPart.backdrop,
          images: inputs.live.images,
          backgrounds: inputs.live.backgrounds);
      // On the neighbour's leaf, its own elements go over whatever this page
      // hangs across the gutter, as in the book, whichever leaf is selected.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height));
      _paintContents(canvas, _document, _frame);
      canvas.restore();
      canvas.save();
      canvas.translate(aside, 0);
      paintCanvasDocument(canvas, over,
          frame: overFrame,
          part: CanvasPaintPart.contents,
          images: inputs.live.images);
      canvas.restore();

      // The spine, so two pages edge to edge do not read as one canvas.
      if (inputs.transform.spread) {
        var join = inputs.transform.facingOnLeft ? docSize.width : 0.0;
        canvas.drawRect(
          Rect.fromLTWH(join - docSize.width * 0.003, 0, docSize.width * 0.006,
              docSize.height),
          Paint()..color = const Color(0x22000000),
        );
      }
    }

    if (over != null) {
      // Everywhere but the neighbour's leaf, which drew this page's overhang
      // above.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height),
          clipOp: ui.ClipOp.difference);
      _paintContents(canvas, _document, _frame);
      canvas.restore();
    } else if (inputs.shown.gameChange
        case (var left, var leftAt, var over, var t, var leftLive)?) {
      // A game gone on to another scene: the one it left gives way, framed
      // by its own camera, its elements as their slots had them when left.
      paintTransition(canvas, Offset.zero & docSize, over, t,
          from: () => _paintContents(canvas, left, leftAt,
              part: CanvasPaintPart.all,
              camera: sceneFraming(left, leftAt, live: leftLive),
              live: leftLive),
          to: () => _paintContents(canvas, _document, _frame,
              part: CanvasPaintPart.all, camera: inputs.shown.camera));
    } else {
      _paintContents(canvas, _document, _frame,
          part: CanvasPaintPart.all, camera: inputs.shown.camera);
    }

    // A marker's label while playback holds at it, in canvas units.
    if (inputs.shown.markerNote case var note?) {
      paintMarkerNote(canvas, docSize, note,
          selected: inputs.shown.markerNoteGrip);
    }

    // A line round the leaf being edited, not a dimmed neighbour, which
    // would dim a picture across the gutter too. After the contents, or an
    // element against the edge hides it.
    if (over != null && inputs.transform.spread) {
      canvas.drawRect(
        (Offset.zero & docSize).deflate(docSize.width * 0.002),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = docSize.width * 0.004
          ..color = const Color(0x773D7EFF),
      );
    }
    canvas.restore();

    // The screen the game starts on, within the level round it.
    if (inputs.transform.levelShown) {
      canvas.drawRect(
          _page,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0x99FFFFFF));
    }
    _paintGuides(canvas);
    _paintFraming(canvas);
    // The selection through the scene's camera, as the page is drawn, so a
    // push in does not leave the box behind.
    _throughCamera(canvas, () {
      _paintSelection(canvas);
      _paintAnchors(canvas);
    });
    _paintKnife(canvas);
    if (inputs.tools.caret case (var top, var bottom)?) {
      canvas.drawLine(
          top * _scale + _origin,
          bottom * _scale + _origin,
          Paint()
            ..color = const Color(0xFF3D7EFF)
            ..strokeWidth = 1.5);
    }

    if (inputs.tools.marquee case var marquee?) {
      var box = Rect.fromPoints(marquee.topLeft * _scale + _origin,
          marquee.bottomRight * _scale + _origin);
      canvas.drawRect(box, Paint()..color = const Color(0x223D7EFF));
      canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xAA3D7EFF));
    }

    // What a held stroke would do, drawn from the brush's own output so
    // preview and result cannot drift apart (see strokePreview).
    if (inputs.retouch.preview case var preview?) {
      var to = preview.dst;
      canvas.drawImageRect(
          preview.image,
          preview.src,
          Rect.fromLTRB(
            to.left * _scale + _origin.dx,
            to.top * _scale + _origin.dy,
            to.right * _scale + _origin.dx,
            to.bottom * _scale + _origin.dy,
          ),
          Paint()..filterQuality = FilterQuality.medium);
    }

    // The stroke being drawn, inside the page clip, or it runs over the
    // sidebar when zoomed. A thick round-capped line, not a stamp per point,
    // reads the same as the dabbed brush at any speed.
    var liveStroke = inputs.retouch.stroke.value;
    if (liveStroke.length > 1 && inputs.retouch.radius > 0) {
      var path = Path()
        ..moveTo(liveStroke.first.dx * _scale + _origin.dx,
            liveStroke.first.dy * _scale + _origin.dy);
      for (var point in liveStroke.skip(1)) {
        path.lineTo(
            point.dx * _scale + _origin.dx, point.dy * _scale + _origin.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = inputs.retouch.radius * 2 * _scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = inputs.retouch.keeps
                ? const Color(0x6633DD88)
                : const Color(0x66FF5544));
    }

    canvas.restore();

    // Outside the page dimmed, so the published edge is obvious: four bands
    // rather than a Path.difference.
    if (_viewRect != _page) {
      var shade = Paint()..color = const Color(0x66000000);
      canvas.drawRect(
          Rect.fromLTRB(
              _viewRect.left, _viewRect.top, _viewRect.right, _page.top),
          shade);
      canvas.drawRect(
          Rect.fromLTRB(
              _viewRect.left, _page.bottom, _viewRect.right, _viewRect.bottom),
          shade);
      canvas.drawRect(
          Rect.fromLTRB(_viewRect.left, _page.top, _page.left, _page.bottom),
          shade);
      canvas.drawRect(
          Rect.fromLTRB(_page.right, _page.top, _viewRect.right, _page.bottom),
          shade);
    }

    // The border last and outside the clip, or it is half a line.
    canvas.drawRect(
        _page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x55FFFFFF));

    // A hint that there is more canvas outside the frame.
    if (docSize.width * _scale > _page.width + 1) {
      canvas.drawRect(
        _page,
        Paint()
          ..shader = ui.Gradient.radial(
            _page.center,
            math.max(_page.width, _page.height) * 0.7,
            [const Color(0x00000000), const Color(0x33000000)],
            [0.7, 1.0],
          ),
      );
    }

    // The rulers last, in the widget's pixels and outside the page clip.
    _paintRulers(canvas, size);
  }

  @override
  bool shouldRepaint(StagePainter old) => old.inputs != inputs;
}

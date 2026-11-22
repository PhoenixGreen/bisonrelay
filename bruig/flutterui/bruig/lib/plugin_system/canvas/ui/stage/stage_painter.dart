import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_rulers.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_page.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_retouch.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_selection.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_tools.dart';
import 'package:flutter/material.dart';

export 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';
export 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_selection.dart'
    show chosenOutlines;

// stage_painter.dart is everything the stage draws: the document, the sheet
// it sits on, and the marks for what is selected and what can be taken hold
// of. It is handed values the stage has already decided (the selection's box
// and frame, what a held stroke looks like), grouped by subject in
// stage_painter_inputs.dart, and only draws them. Here is the order things
// are drawn in; how each subject is drawn is in a library of its own, given
// the values it reads: stage_paint_page.dart (the page and what is on it),
// stage_paint_selection.dart, stage_paint_elements.dart (marks on
// elements), stage_paint_tools.dart, stage_paint_retouch.dart,
// stage_paint_guides.dart and stage_rulers.dart, all drawn with the pieces
// in stage_paint_kit.dart.

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
    paintPageShadow(canvas, inputs.transform, inputs.shown, _page, _viewRect);

    // Everything the document contributes, handles included, goes inside
    // the frame at any zoom.
    canvas.save();
    canvas.clipRect(_viewRect);
    // A transition being watched is drawn as it will play, with nothing
    // over it or round it.
    if (paintStagePage(canvas, inputs.transform, inputs.shown, inputs.live,
        inputs.text, _scale, _origin)) {
      canvas.restore();
      return;
    }
    // The screen the game starts on, within the level round it.
    paintLevelFrame(canvas, inputs.transform, _page);
    _paintMarks(canvas);
    canvas.restore();

    // Round the page, outside the clip: the shade, then the border, or it
    // is half a line.
    paintPageSurround(canvas, _page, _viewRect, _document.size.size, _scale);

    // The rulers last, in the widget's pixels and outside the page clip.
    _paintRulers(canvas, size);
  }

  /// _paintMarks draws everything over the page, inside its clip: the
  /// guides, a picture being reframed, the selection and what is marked on
  /// elements, the knife, the caret, the marquee and the retouching brush.
  void _paintMarks(Canvas canvas) {
    paintGuideMarks(
        canvas, inputs.guides, _document.size.size, _scale, _origin);
    paintFraming(canvas, inputs.tools.framing, _scale, _origin);
    // The selection through the scene's camera, as the page is drawn, so a
    // push in does not leave the box behind.
    paintThroughCamera(canvas, inputs.shown.camera, _document.size.rect.center,
        _scale, _origin, () {
      _paintHelpers(canvas);
      paintAnchors(canvas, inputs.selection.anchors, _scale, _origin);
    });
    paintKnife(canvas, inputs.tools.knife, _scale, _origin);
    paintCaret(canvas, inputs.tools.caret, _scale, _origin);
    paintMarquee(canvas, inputs.tools.marquee, _scale, _origin);
    // What a held stroke would do, then the stroke being drawn, inside the
    // page clip, or it runs over the sidebar when zoomed.
    paintRetouchMarks(canvas, inputs.retouch, _scale, _origin);
  }

  /// _paintHelpers draws the marks shown while helpers are: those on
  /// elements, then whichever of a path's points, a picture's layers, a
  /// drawing being edited or the selection's box is shown, in that order of
  /// precedence.
  void _paintHelpers(Canvas canvas) {
    if (!inputs.selection.showHelpers) return;
    var motion = _liveMotion;

    paintCameras(canvas, inputs.elements.camerasShown, inputs.shown, motion,
        _scale, _origin);
    paintKeptBoxes(canvas, inputs.elements.showAllBounds, inputs.selection.ids,
        inputs.shown, motion, _scale, _origin);
    paintFlowLines(canvas, inputs.elements.flowLines);
    paintTouchAreas(canvas, inputs.elements.touchAreas, _scale, _origin);

    paintChartLabels(canvas, inputs.elements.chartLabels, _scale, _origin);
    paintLayoutMarks(canvas, inputs.elements.layout, _scale, _origin);
    paintTableColumns(canvas, inputs.elements.tableColumns, _scale, _origin);
    // A path shows points and handles, not a box: the box round a curve
    // cannot be usefully dragged.
    var path = inputs.elements.selectedPath;
    if (path != null) {
      paintPathControls(canvas, path, _scale, _origin);
      return;
    }
    if (inputs.tools.layers case var layers?) {
      paintLayerBoxes(canvas, layers, inputs.live.images, _scale, _origin);
      return;
    }
    if (inputs.tools.vector case var editing?) {
      paintVectorEditing(canvas, editing, _scale, _origin);
      return;
    }

    var bounds = inputs.selection.bounds;
    if (bounds == null) return;

    // Each element of a multi-selection outlined under the group's box,
    // without handles: the group is what is resized.
    paintChosenBoxes(
        canvas, inputs.selection.ids, inputs.shown, motion, _scale, _origin);
    paintWholeChain(canvas, inputs.shown, inputs.live, _scale, _origin);
    paintTrail(
        canvas, inputs.selection, inputs.shown, inputs.live, _scale, _origin);
    paintCopies(
        canvas, inputs.selection, inputs.shown, motion, _scale, _origin);

    paintSelectionBox(canvas, inputs.selection, bounds, _scale, _origin);
    // The outline alone for something placed by another element.
    if (!inputs.selection.showHandles) return;
    paintFlowGrips(canvas, inputs.elements.flowGrips, inputs.elements.flowDrag);
  }

  /// _paintRulers draws the rulers along the page, unless the page scrolls and
  /// they are left to their own layer (StageTransform.scrolls).
  void _paintRulers(Canvas canvas, Size size) {
    if (inputs.transform.scrolls) return;
    paintStageRulers(
        canvas,
        size,
        inputs.guides.rulers,
        inputs.guides.canvas.gridSize,
        _document.size.size,
        _scale,
        _origin,
        _page);
  }

  @override
  bool shouldRepaint(StagePainter old) => old.inputs != inputs;
}

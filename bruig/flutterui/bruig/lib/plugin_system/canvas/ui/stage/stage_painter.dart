import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe, TimelineAction;
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart'
    show SceneTransition;
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, setEquals;
import 'package:flutter/material.dart';

part 'stage_painter_marks.dart';
part 'stage_painter_handles.dart';

// stage_painter.dart is everything the stage draws: the document, the sheet
// it sits on, and the marks for what is selected and what can be taken hold
// of. It is handed values the stage has already decided (where handles go,
// what a held stroke looks like) and only draws them.

/// shapeTurnReach is how far above a shape's box, in screen pixels, its turn
/// handle sits.
const double shapeTurnReach = 22;

/// StageFraming is a picture being repositioned inside its frame. [src] is
/// the whole picture and [dst] where all of it lands, larger than [frame];
/// drawn faintly, so what is dragged out of shot stays visible.
class StageFraming {
  final ui.Image image;
  final Rect src;
  final Rect dst;

  /// frame is the element's rectangle: the part of [dst] kept, drawn at full
  /// strength by the renderer underneath.
  final Rect frame;

  /// rotation is the element's, in radians.
  final double rotation;

  /// pivot is the middle of the element's frame, which is not the picture's
  /// middle in a frame grown round layers.
  final Offset? pivot;

  final bool flipX;
  final bool flipY;

  const StageFraming(this.image, this.src, this.dst, this.frame, this.rotation,
      {this.pivot, this.flipX = false, this.flipY = false});
}

/// chosenOutlines is every element of a multi-selection, each outlined so
/// overlapping ones can be told apart. Empty for a single selection.
List<CanvasElement> chosenOutlines(
    CanvasDocument document, Set<String> selection, int frame) {
  if (selection.length < 2) return const [];
  return [
    for (var element in document.elements)
      if (selection.contains(element.id) && element.visible) element,
  ];
}

/// StagePainter draws the document, page edge, handles and marquee.
class StagePainter extends CustomPainter {
  final CanvasDocument document;
  final int frame;

  /// between is how far past [frame] the playhead has got while playing (see
  /// scene_renderer's betweenFrames); null when nothing is drawn between.
  final ValueListenable<double>? between;

  /// previewAt is a frame of the whole run while a transition is watched,
  /// drawn with the export's own paintSequenceFrame.
  final int? previewAt;

  /// previewing is the one element being previewed, at its own frame.
  final ({String id, int frame})? previewing;

  /// markerNote is the marker playback holds at, its label drawn on the
  /// canvas (see marker_note.dart); markerNoteGrip shows its drag grip.
  final TimelineAction? markerNote;
  final bool markerNoteGrip;

  /// anchors are the anchor points shown, on the page.
  final List<({Offset at, bool locked})> anchors;

  /// knife is the knife's line, on the page, while being drawn.
  final List<Offset> knife;

  /// caret is a drawing's text caret, top to bottom, on the page.
  final (Offset, Offset)? caret;

  /// scale is document units to screen pixels: the fitted size times the
  /// reader's zoom.
  final double scale;
  final Offset origin;
  final CanvasImageSource images;
  final String? hoveredButton;
  final Set<String> selection;

  /// pickedCopies are the picked copies of a reused element (_paintCopies).
  final Set<String> pickedCopies;

  /// gameChange is the scene a game is leaving while its transition plays
  /// (as seen, its frame, the transition and how far through), drawn giving
  /// way to [document].
  final (CanvasDocument, int, SceneTransition, double, LiveMotion)?
      gameChange;

  /// trail shows the selected element's trail and onion skin while the
  /// Chain is open on its motion (see _paintTrail).
  final bool trail;
  final Rect? selectionBounds;
  final double selectionRotation;

  /// touchAreas are each played element's touch area, drawn while the Game
  /// tab is open (see gameTouchArea).
  final List<Rect> touchAreas;

  /// selectionSkew is the selected element's slant in degrees, across, down.
  final Offset selectionSkew;
  final Offset Function(StageHandle, Rect) handleFor;
  final Rect? marquee;

  /// counterValue is what a live counter shows now, and counterPressed which
  /// of its buttons is under the pointer: session state, not design.
  final double Function(CounterElement)? counterValue;

  /// liveMotion is what plays from slots; motionTick rises as it plays on.
  final LiveMotion? liveMotion;
  final int motionTick;

  /// directed is whether the page is seen through its Camera, which on a 3D
  /// stage is the stage's camera (see camera_3d.dart).
  final bool directed;
  final int Function(CounterElement)? counterPressed;
  final bool Function(CounterElement)? counterRunning;

  /// counterTick changes when a running counter moves, forcing a repaint.
  final int counterTick;

  /// audioState is each speaker's sound; audioRevision changes with it.
  final AudioState Function(AudioElement)? audioState;
  final VideoShow Function(VideoElement)? videoShow;
  final int audioRevision;

  /// keysTick is the controller's keysHeld, changing as a key is pressed or
  /// let go and as a synth's screens tick while a note sounds, which change
  /// nothing else compared here.
  final int keysTick;

  /// flowGrips are the two dots on a selected text box.
  final TextFlowGrips? flowGrips;

  /// flowLines are the links between text boxes worth drawing this frame.
  final List<FlowLine> flowLines;

  /// showAllBounds outlines every element rather than only the selected one.
  final bool showAllBounds;

  /// flowDrag is the link being dragged, from its box to the pointer.
  final FlowLine? flowDrag;

  /// page is the frame the canvas is drawn inside; the shadow and border go
  /// outside the clip, keeping the canvas edge visible at every zoom.
  final Rect page;

  /// view is the page plus any overspill shown round it. The clip is this,
  /// not [page], so an element waiting off the canvas can be taken hold of.
  final Rect view;

  /// levelShown is whether [view] is a game's level reaching past the page:
  /// the shadow goes under the page alone, and the page (the screen the game
  /// starts on) is marked out.
  final bool levelShown;

  /// facing is the index of the page drawn beside the one being edited, or
  /// null. Drawn only, with no handles, guides or selection, so only one
  /// canvas is edited at a time.
  final int? facing;

  /// facingFrame is the frame the neighbour was left at, and is drawn at.
  final int facingFrame;

  /// facingOnLeft is whether the page being edited is the left leaf.
  final bool facingOnLeft;

  /// facingShown is whether the neighbour has room of its own on screen. Off,
  /// it is still drawn (a picture across the gutter is part of this page),
  /// but without its backdrop and half of the frame.
  final bool facingShown;

  /// selectedPath is the selected path, drawn with points and handles.
  final PathElement? selectedPath;

  /// spritePaintTick changes with each stroke on a sprite being painted,
  /// whose pixels are not the document's until the pen lifts.
  final int spritePaintTick;

  /// tilePaintTick changes with each change to a map being painted.
  final int tilePaintTick;

  /// rulersApart leaves the rulers to their own layer (paintStageRulers).
  final bool rulersApart;

  /// editingVector is the drawing being edited point by point, with its
  /// picked shape and point, drawn in place of a selection box.
  final ({
    VectorElement element,
    int shape,
    VectorPick? pick,
    Set<VectorPick> picks,
    bool boxing,
    Set<VectorPick> boxed,
    bool bare,
    ({bool across, bool down})? mirror,
    Rect? shapeBox,
    bool turnable,
    Set<int>? combining,
  })? editingVector;

  /// editingLayers is the layers of the picture being edited.
  final StageLayers? editingLayers;

  /// chartLabels is the boxes of the selected chart's placed labels, in
  /// document units, outlined to show they can be taken hold of.
  final List<Rect> chartLabels;

  /// tableColumns is where a selected table's column rules are, in document
  /// units, each given a drag grip.
  final List<(double, double, double)> tableColumns;

  /// preview is a picture of what a held stroke would do, and previewOn the
  /// placement it is drawn through; both null when nothing is held. A
  /// placement, not a destination: "fill the box" crops the picture, so
  /// stretching the preview into the element would misplace the tint.
  final ui.Image? preview;
  final ImagePlacement? previewOn;

  /// liveStroke is the retouching stroke being drawn, in canvas coordinates,
  /// with liveStrokeRadius its width and liveStrokeKeeps which way it works.
  /// Drawn here because changing the picture reprocesses every pixel; the
  /// picture catches up when the pointer comes up.
  final List<Offset> liveStroke;
  final double liveStrokeRadius;
  final bool liveStrokeKeeps;

  /// editingText is the id of a text element being typed into, whose words
  /// are left to the editor over the top.
  final String? editingText;

  /// editingItem is the piece of that element the editor is on.
  final String? editingItem;

  /// showHandles is false for something whose size and angle belong to
  /// another element (text riding a line): its handles would do nothing.
  final bool showHandles;

  final StageFraming? framing;

  /// backgrounds is the editor's rasterised background, or null in a test.
  final ProceduralCache? backgrounds;

  /// guides is the grid and the reader's guide lines: drawn here, never by
  /// the renderer, so nothing published has a grid.
  final CanvasGuides guides;

  /// snapped is the line or lines a drag is caught on, drawn bright so a
  /// snap is never a mysterious jump.
  final SnapResult? snapped;

  /// showHelpers draws the selection box, handles and rotation ring. A flag
  /// of its own: _paintSelection reads selectionBounds, so emptying the
  /// selection would not hide them.
  final bool showHelpers;

  /// camera is the scene's camera on this frame while it plays, or null.
  /// Never while editing: a press must land where the page looks to be.
  final (double, Offset)? camera;

  /// drafting draws rasterised work (adjustments, effects) smaller during a
  /// gesture; see RasterCache.drafting.
  final bool drafting;

  StagePainter({
    this.between,
    this.drafting = false,
    this.backgrounds,
    required this.page,
    this.levelShown = false,
    required this.view,
    this.facing,
    this.facingFrame = 0,
    this.facingOnLeft = false,
    this.facingShown = false,
    required this.showHandles,
    required this.showHelpers,
    this.camera,
    this.flowGrips,
    this.flowLines = const [],
    this.showAllBounds = false,
    this.flowDrag,
    required this.framing,
    required this.guides,
    required this.snapped,
    required this.selectedPath,
    this.spritePaintTick = -1,
    this.tilePaintTick = -1,
    this.rulersApart = false,
    this.editingVector,
    this.editingLayers,
    required this.chartLabels,
    required this.tableColumns,
    required this.editingText,
    required this.editingItem,
    required this.preview,
    required this.previewOn,
    required this.liveStroke,
    required this.liveStrokeRadius,
    required this.liveStrokeKeeps,
    required this.document,
    required this.frame,
    this.previewAt,
    this.previewing,
    this.markerNote,
    this.markerNoteGrip = false,
    this.anchors = const [],
    this.knife = const [],
    this.caret,
    required this.scale,
    required this.origin,
    required this.images,
    required this.hoveredButton,
    this.counterValue,
    this.liveMotion,
    this.motionTick = 0,
    this.directed = false,
    this.counterPressed,
    this.counterRunning,
    this.counterTick = 0,
    this.audioState,
    this.videoShow,
    this.audioRevision = 0,
    this.keysTick = 0,
    required this.selection,
    this.pickedCopies = const {},
    this.trail = false,
    this.gameChange,
    required this.selectionBounds,
    required this.selectionRotation,
    this.touchAreas = const [],
    this.selectionSkew = Offset.zero,
    required this.handleFor,
    required this.marquee,
  }) : super(
            repaint: Listenable.merge([
          // Pictures and the background arrive after the frame that asked
          // for them, and nothing else changes then, so without these a
          // placeholder would stay up.
          if (images is Listenable) images as Listenable,
          if (backgrounds != null) backgrounds,
          if (between != null) between,
        ]));

  @override
  void paint(Canvas canvas, Size size) => CanvasPerf.time(
      "stagePaint",
      () => directed
          ? directedBy(document, liveMotion, () => _paintStage(canvas, size))
          : _paintStage(canvas, size));

  void _paintStage(Canvas canvas, Size size) {
    RasterCache.drafting = drafting;
    betweenFrames = between?.value ?? 0;
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
    if (previewAt case var at? when facingShown) {
      // Only under the leaves there are: a cover stands on its own side.
      var (onLeft, onRight) = bookSides(document, at);
      var leftLeaf = facingOnLeft ? page : page.shift(Offset(-page.width, 0));
      if (onLeft) canvas.drawRect(leftLeaf.shift(const Offset(0, 6)), shadow);
      if (onRight) {
        canvas.drawRect(leftLeaf.shift(Offset(page.width, 6)), shadow);
      }
    } else {
      canvas.drawRect(
          (levelShown ? page : view).shift(const Offset(0, 6)), shadow);
    }

    // Everything the document contributes, handles included, goes inside
    // the frame at any zoom.
    canvas.save();
    canvas.clipRect(view);

    var docSize = document.size.size;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    // The leaf beside this one. Both backdrops go down first, then both
    // contents, so a picture across the gutter shows without a seam. The
    // neighbour is a document page even while the master is edited:
    // goToScene alone would leave onMaster set and draw the master twice.
    var beside = facing;
    var over = beside == null
        ? null
        : document.goToScene(beside).copyWith(onMaster: false);
    var aside = facingOnLeft ? docSize.width : -docSize.width;
    // At the frame it was left on, so a chart on it neither vanishes nor
    // jumps to its end.
    var overFrame = facingFrame;

    if (previewAt case var at?) {
      // Played as a book, each leaf is drawn in its place in the spread and
      // a transition between spreads moves both (see paintBookFrame).
      if (facingShown) {
        paintBookFrame(canvas, document, at,
            left: facingOnLeft ? 0.0 : -docSize.width,
            images: images,
            backgrounds: backgrounds,
            audioState: audioState,
            videoShow: videoShow);
      } else {
        paintSequenceFrame(canvas, document, at,
            images: images,
            backgrounds: backgrounds,
            audioState: audioState,
            videoShow: videoShow,
            liveMotion: liveMotion,
            counterValue: counterValue);
      }
      canvas.restore();
      canvas.restore();
      return;
    }
    if (over != null) {
      // This page's paper goes down between the two: the neighbour's
      // backdrop under it, the neighbour's overhang over it.
      if (facingShown) {
        canvas.save();
        canvas.translate(aside, 0);
        canvas.clipRect(Offset.zero & docSize);
        paintCanvasDocument(canvas, over,
            frame: overFrame,
            part: CanvasPaintPart.backdrop,
            images: images,
            backgrounds: backgrounds);
        canvas.restore();
      }
      paintCanvasDocument(canvas, document,
          part: CanvasPaintPart.backdrop,
          images: images,
          backgrounds: backgrounds);
      // On the neighbour's leaf, its own elements go over whatever this page
      // hangs across the gutter, as in the book, whichever leaf is selected.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height));
      _paintContents(canvas, document, frame);
      canvas.restore();
      canvas.save();
      canvas.translate(aside, 0);
      paintCanvasDocument(canvas, over,
          frame: overFrame, part: CanvasPaintPart.contents, images: images);
      canvas.restore();

      // The spine, so two pages edge to edge do not read as one canvas.
      if (facingShown) {
        var join = facingOnLeft ? docSize.width : 0.0;
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
      _paintContents(canvas, document, frame);
      canvas.restore();
    } else if (gameChange
        case (var left, var leftAt, var over, var t, var leftLive)?) {
      // A game gone on to another scene: the one it left gives way, framed
      // by its own camera, its elements as their slots had them when left.
      paintTransition(canvas, Offset.zero & docSize, over, t,
          from: () => _paintContents(canvas, left, leftAt,
              part: CanvasPaintPart.all,
              camera: sceneFraming(left, leftAt, live: leftLive),
              live: leftLive),
          to: () => _paintContents(canvas, document, frame,
              part: CanvasPaintPart.all, camera: camera));
    } else {
      _paintContents(canvas, document, frame,
          part: CanvasPaintPart.all, camera: camera);
    }

    // A marker's label while playback holds at it, in canvas units.
    if (markerNote case var note?) {
      paintMarkerNote(canvas, docSize, note, selected: markerNoteGrip);
    }

    // A line round the leaf being edited, not a dimmed neighbour, which
    // would dim a picture across the gutter too. After the contents, or an
    // element against the edge hides it.
    if (over != null && facingShown) {
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
    if (levelShown) {
      canvas.drawRect(
          page,
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
    if (caret case (var top, var bottom)?) {
      canvas.drawLine(
          top * scale + origin,
          bottom * scale + origin,
          Paint()
            ..color = const Color(0xFF3D7EFF)
            ..strokeWidth = 1.5);
    }

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

    // What a held stroke would do, drawn from the brush's own output so
    // preview and result cannot drift apart (see strokePreview).
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

    // The stroke being drawn, inside the page clip, or it runs over the
    // sidebar when zoomed. A thick round-capped line, not a stamp per point,
    // reads the same as the dabbed brush at any speed.
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

    // Outside the page dimmed, so the published edge is obvious: four bands
    // rather than a Path.difference.
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

    // The border last and outside the clip, or it is half a line.
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x55FFFFFF));

    // A hint that there is more canvas outside the frame.
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

    // The rulers last, in the widget's pixels and outside the page clip.
    _paintRulers(canvas, size);
  }

  // ---- stage_painter_handles.dart -----------------------------------------

  @override
  bool shouldRepaint(StagePainter old) =>
      old.drafting != drafting ||
      old.levelShown != levelShown ||
      !listEquals(old.touchAreas, touchAreas) ||
      old.guides != guides ||
      !identical(old.snapped, snapped) ||
      !identical(old.framing, framing) ||
      old.document != document ||
      old.frame != frame ||
      old.motionTick != motionTick ||
      old.directed != directed ||
      old.previewAt != previewAt ||
      old.previewing != previewing ||
      old.markerNote != markerNote ||
      old.markerNoteGrip != markerNoteGrip ||
      !listEquals(old.anchors, anchors) ||
      !identical(old.knife, knife) ||
      old.caret != caret ||
      old.scale != scale ||
      old.origin != origin ||
      old.page != page ||
      old.view != view ||
      old.facing != facing ||
      old.facingFrame != facingFrame ||
      old.facingOnLeft != facingOnLeft ||
      old.facingShown != facingShown ||
      old.showHelpers != showHelpers ||
      old.showHandles != showHandles ||
      old.flowGrips != flowGrips ||
      !listEquals(old.flowLines, flowLines) ||
      old.showAllBounds != showAllBounds ||
      old.flowDrag != flowDrag ||
      !identical(old.selectedPath, selectedPath) ||
      old.spritePaintTick != spritePaintTick ||
      old.tilePaintTick != tilePaintTick ||
      old.rulersApart != rulersApart ||
      old.editingVector != editingVector ||
      old.editingLayers != editingLayers ||
      old.editingText != editingText ||
      old.editingItem != editingItem ||
      !identical(old.preview, preview) ||
      old.previewOn != previewOn ||
      old.liveStroke.length != liveStroke.length ||
      old.liveStrokeKeeps != liveStrokeKeeps ||
      old.hoveredButton != hoveredButton ||
      old.counterTick != counterTick ||
      old.audioRevision != audioRevision ||
      old.keysTick != keysTick ||
      // A new set each build: the same ids are the same selection.
      !setEquals(old.selection, selection) ||
      !setEquals(old.pickedCopies, pickedCopies) ||
      old.trail != trail ||
      old.gameChange != gameChange ||
      old.selectionBounds != selectionBounds ||
      old.selectionSkew != selectionSkew ||
      old.marquee != marquee;
}

/// StageWarp is a warp grid as the stage draws it; see StageLayers.warp.
class StageWarp {
  final List<List<Offset>> lines;
  final List<Offset> points;
  final Set<int> picks;
  final List<Offset>? box;
  final Offset? knob;
  const StageWarp(
      {required this.lines,
      required this.points,
      required this.picks,
      this.box,
      this.knob});
}

/// StageLayers is what the stage draws over a picture whose layers are being
/// edited, in document units: the corners of every layer not picked, and the
/// picked one's corners, handles and knob. A picked base picture has its
/// frame as its corners and no handles: the frame is resized as the element.
class StageLayers {
  final List<List<Offset>> others;
  final List<Offset>? picked;

  /// chosen are the layers picked with [picked], outlined without handles:
  /// they move with it.
  final List<List<Offset>> chosen;
  final List<Offset> handles;
  final Offset? knob;

  /// masking is the layer whose mask a mask tool is working on, and how the
  /// mask is to be shown; ring is the brush, centre and radius.
  final ({ImageElement element, String layer, MaskView view})? masking;
  final (Offset, double)? ring;

  /// trail is a quick-select stroke being drawn: points, radius, and whether
  /// it takes away.
  final (List<Offset>, double, bool)? trail;

  /// marker is where the clone tool copies from.
  final Offset? marker;

  /// lasso is the outline of a lasso being drawn, in document units.
  final List<Offset>? lasso;

  /// warp is a picture's warp grid being worked on, in document units: its
  /// lines, curved as the picture bends, its points and picks, and with two
  /// or more picked the box to size and turn them by.
  final StageWarp? warp;

  const StageLayers(
      {this.others = const [],
      this.picked,
      this.chosen = const [],
      this.handles = const [],
      this.knob,
      this.masking,
      this.ring,
      this.trail,
      this.marker,
      this.lasso,
      this.warp});
}

/// paintStageRulers draws the rulers [guides] asks for along the edges of
/// [page], inside a view [size] across, numbered from the page's top-left
/// (so they agree with the X and Y fields) at [scale] pixels a unit of a
/// [sheet] whose top-left is at [origin]. Over a page that scrolls, the
/// stage calls it in a layer of its own, so rulers stay at the window edges.
void paintStageRulers(Canvas canvas, Size size, CanvasGuides guides, Size sheet,
    double scale, Offset origin, Rect page) {
    if (!guides.rulers.any || !guides.showRulers) return;
    var bands = rulerBandsFor(page, size, guides.rulers);
    var step = rulerStep(scale, guides.gridSize);

    var strip = Paint()..color = const Color(0xF01A1A1E);
    var edge = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x33FFFFFF);
    var tick = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x66FFFFFF);
    // The unnumbered ticks are the grid itself, fainter.
    var fine = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x33FFFFFF);
    var minor = guides.gridSize;
    var showFine = minor > 0 && minor < step && minor * scale >= 6;

    // The page starts at (0, 0) in document units, so its screen origin is
    // [origin]; transforming the frame's corner again would push every tick
    // off the page.
    var zero = origin;

    void number(double at, Offset where, {required bool vertical}) {
      // Shared and kept (see labelPainter): the same few numbers come round
      // on every repaint of the stage.
      var painter = labelPainter("${at.round()}",
          size: 8, colour: const Color(0xAAFFFFFF));
      if (vertical) {
        // Turned on its side, so the numbers read up the strip.
        canvas.save();
        canvas.translate(where.dx, where.dy);
        canvas.rotate(-math.pi / 2);
        painter.paint(canvas, Offset(-painter.width - 2, 0));
        canvas.restore();
      } else {
        painter.paint(canvas, where);
      }
    }

    for (var top in [true, false]) {
      var band = top ? bands.top : bands.bottom;
      if (band == null) continue;
      canvas.drawRect(band, strip);
      canvas.drawLine(Offset(band.left, top ? band.bottom : band.top),
          Offset(band.right, top ? band.bottom : band.top), edge);

      canvas.save();
      canvas.clipRect(band);
      // Only across the page, not the grey round it.
      if (showFine) {
        for (var i = 0; i * minor <= sheet.width; i++) {
          var x = zero.dx + i * minor * scale;
          canvas.drawLine(Offset(x, top ? band.bottom - 3 : band.top),
              Offset(x, top ? band.bottom : band.top + 3), fine);
        }
      }
      for (var i = 0; i * step <= sheet.width; i++) {
        var at = i * step;
        var x = zero.dx + at * scale;
        canvas.drawLine(Offset(x, top ? band.bottom - 6 : band.top),
            Offset(x, top ? band.bottom : band.top + 6), tick);
        number(at, Offset(x + 2, band.top + 3), vertical: false);
      }
      canvas.restore();
    }

    for (var left in [true, false]) {
      var band = left ? bands.left : bands.right;
      if (band == null) continue;
      canvas.drawRect(band, strip);
      canvas.drawLine(Offset(left ? band.right : band.left, band.top),
          Offset(left ? band.right : band.left, band.bottom), edge);

      canvas.save();
      canvas.clipRect(band);
      if (showFine) {
        for (var i = 0; i * minor <= sheet.height; i++) {
          var y = zero.dy + i * minor * scale;
          canvas.drawLine(Offset(left ? band.right - 3 : band.left, y),
              Offset(left ? band.right : band.left + 3, y), fine);
        }
      }
      for (var i = 0; i * step <= sheet.height; i++) {
        var at = i * step;
        var y = zero.dy + at * scale;
        canvas.drawLine(Offset(left ? band.right - 6 : band.left, y),
            Offset(left ? band.right : band.left + 6, y), tick);
        number(at, Offset(band.right - 3, y - 2), vertical: true);
      }
      canvas.restore();
    }
  }

/// cameraTab is where [cam]'s name tab is on the page: in the top-left of
/// [frame], a fixed size on screen at any [scale]. Shared by painter and
/// stage so drawing and hit-testing agree.
Rect cameraTab(CameraElement cam, Rect frame, double scale) {
  var label = TextPainter(
    text: TextSpan(
        text: cam.name,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
  )..layout();
  var w = math.min(label.width + 26, 220.0) / scale;
  var h = 20 / scale;
  var inset = 4 / scale;
  return Rect.fromLTWH(frame.left + inset, frame.top + inset,
      math.min(w, frame.width - inset * 2), math.min(h, frame.height / 3));
}

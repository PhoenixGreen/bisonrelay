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
import 'package:bruig/plugin_system/canvas/ui/marker_note.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart'
    show SceneTransition;
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, setEquals;
import 'package:flutter/material.dart';

// stage_painter.dart is everything the stage draws: the document, the sheet it
// sits on, and the marks over it for what is selected and what can be taken
// hold of. It is handed values the stage has already decided (where handles go,
// which labels are placed, what a held stroke looks like) and only draws them.

/// shapeTurnReach is how far above a shape's box, on screen, the handle
/// that turns it sits.
const double shapeTurnReach = 22;

/// StageFraming is a picture being repositioned inside its frame, worked out
/// by the stage and drawn by [StagePainter]. [src] is the whole picture the
/// frame chooses from and [dst] where all of it would land, larger than
/// [frame] in at least one direction; the painter draws it faintly, so what
/// is dragged out of shot stays visible.
class StageFraming {
  final ui.Image image;
  final Rect src;
  final Rect dst;

  /// frame is the element's own rectangle: the part of [dst] that is kept, drawn
  /// at full strength by the renderer underneath all of this.
  final Rect frame;

  /// rotation is the element's, in radians: the overlay turns with it.
  final double rotation;

  /// pivot is what the element turns about: the middle of its frame, which is
  /// not the picture's middle in a frame grown round layers.
  final Offset? pivot;

  /// flipX and flipY are the picture's own mirror in its place, which the
  /// ghost of the rest of it has too.
  final bool flipX;
  final bool flipY;

  const StageFraming(this.image, this.src, this.dst, this.frame, this.rotation,
      {this.pivot, this.flipX = false, this.flipY = false});
}

/// chosenOutlines is every element of a multi-selection, to be outlined on
/// its own so overlapping selected elements can be told apart (the box round
/// the lot says nothing about what is in it). Empty for a single selection.
List<CanvasElement> chosenOutlines(
    CanvasDocument document, Set<String> selection, int frame) {
  if (selection.length < 2) return const [];
  return [
    for (var element in document.elements)
      if (selection.contains(element.id) && element.visible) element,
  ];
}

/// StagePainter draws the document, the page edge, the handles and the
/// marquee.
class StagePainter extends CustomPainter {
  final CanvasDocument document;
  final int frame;

  /// between is how far past [frame] the playhead has got while it plays,
  /// redrawing the stage as it changes (see scene_renderer's betweenFrames).
  /// Null when nothing is drawn between frames.
  final ValueListenable<double>? between;

  /// previewAt is a frame of the whole run, when a transition is being watched:
  /// the canvas then draws the sequence with the export's own function. See
  /// paintSequenceFrame.
  final int? previewAt;

  /// previewing is the one element being previewed, at its own frame. See
  /// CanvasController.previewing.
  final ({String id, int frame})? previewing;

  /// markerNote is the marker playback holds at, whose label is drawn on
  /// the canvas (see marker_note.dart), and markerNoteGrip whether its grip
  /// shows, for dragging; null while none holds.
  final TimelineAction? markerNote;
  final bool markerNoteGrip;

  /// anchors are the anchor points shown, where they are on the page, and
  /// whether each is locked. See ElementBase.anchorX.
  final List<({Offset at, bool locked})> anchors;

  /// knife is the knife's line, on the page, while it is being drawn.
  final List<Offset> knife;

  /// caret is where the caret of a drawing's text being typed is, top to
  /// bottom, on the page.
  final (Offset, Offset)? caret;

  /// scale is document units to screen pixels: the fitted size times the
  /// reader's zoom.
  final double scale;
  final Offset origin;
  final CanvasImageSource images;
  final String? hoveredButton;
  final Set<String> selection;

  /// pickedCopies are the copies picked of the one element selected, reused:
  /// ringed, every other copy of it outlined faintly. See _paintCopies.
  final Set<String> pickedCopies;

  /// gameChange is the scene a game is leaving while its transition plays
  /// -- as it was seen, its frame, the transition and how far through --
  /// drawn giving way to [document]. See CanvasController.gameChange.
  final (CanvasDocument, int, SceneTransition, double, LiveMotion)?
      gameChange;

  /// trail is whether the one element selected shows its trail and onion
  /// skin: the Chain open on its motion. See _paintTrail.
  final bool trail;
  final Rect? selectionBounds;
  final double selectionRotation;

  /// touchAreas are what a game touches of each element played, on the
  /// canvas, drawn while the Game tab is open (see gameTouchArea).
  final List<Rect> touchAreas;

  /// selectionSkew is the single selected element's slant, in degrees, across
  /// and down (see ElementBase.skewX).
  final Offset selectionSkew;
  final Offset Function(StageHandle, Rect) handleFor;
  final Rect? marquee;

  /// counterValue is what a live counter is showing now, and counterPressed
  /// which of its buttons is under the pointer. Handed in because a running
  /// counter's value is session state, not design (see
  /// CanvasController.counterValue).
  final double Function(CounterElement)? counterValue;

  /// liveMotion is the elements playing from their slots, and motionTick goes
  /// up as they play on (see CanvasController.liveMotion).
  final LiveMotion? liveMotion;
  final int motionTick;

  /// directed is whether the page is seen through its Camera: on a 3D
  /// stage, the Camera is the stage's camera. See camera_3d.dart.
  final bool directed;
  final int Function(CounterElement)? counterPressed;
  final bool Function(CounterElement)? counterRunning;

  /// counterTick changes when a running counter moves, to repaint though the
  /// document has not changed.
  final int counterTick;

  /// audioState is how each speaker's sound is doing, and audioRevision what
  /// changes when any of that does, as for the counters.
  final AudioState Function(AudioElement)? audioState;
  final VideoShow Function(VideoElement)? videoShow;
  final int audioRevision;

  /// flowGrips are the two dots on a selected text box -- see TextFlowGrips.
  final TextFlowGrips? flowGrips;

  /// flowLines are the links between text boxes that are worth drawing on
  /// this frame. See FlowLine.
  final List<FlowLine> flowLines;

  /// showAllBounds outlines every element rather than only the selected one.
  /// See CanvasController.showAllBounds.
  final bool showAllBounds;

  /// flowDrag is the link being dragged, from the box the words leave to
  /// wherever the pointer has got to.
  final FlowLine? flowDrag;

  /// page is the frame the canvas is drawn inside. The document is clipped to
  /// it; the shadow and border are drawn outside the clip, keeping the canvas
  /// edge visible at every zoom.
  final Rect page;

  /// view is everything drawn: the page, plus the overspill round it when that
  /// is showing. The clip is this rather than [page], so an element waiting off
  /// the canvas can be seen and taken hold of.
  final Rect view;

  /// levelShown is whether [view] is a game's level reaching past the page: the
  /// sheet's shadow under the page alone, and the page (the screen the game
  /// starts on) marked out.
  final bool levelShown;

  /// facing is the page drawn beside the one being edited, by index, or null
  /// where it stands alone (see CanvasStage._facingPage). Drawn only: no
  /// handles, guides or selection, so only one canvas is edited at a time.
  final int? facing;

  /// facingFrame is the frame the neighbour is drawn at: where that page was
  /// left (see CanvasController.frameOn).
  final int facingFrame;

  /// facingOnLeft is whether the page being edited is the left leaf, so the
  /// neighbour goes to its right.
  final bool facingOnLeft;

  /// facingShown is whether the neighbour has room of its own on screen. Off
  /// while fitted to the width, with one page in the window: the neighbour is
  /// still drawn then (a picture across the gutter is part of this page), but
  /// without its own backdrop and half of the frame.
  final bool facingShown;

  /// selectedPath is the selected element when it is a path, whose points and
  /// handles are drawn in place of a selection box.
  final PathElement? selectedPath;

  /// spritePaintTick changes with each stroke on a sprite being painted:
  /// its pixels are not the document's until the pen lifts.
  final int spritePaintTick;

  /// tilePaintTick changes with each change to a map being painted: the
  /// stroke under way, the cell under the pointer.
  final int tilePaintTick;

  /// rulersApart leaves the rulers to a layer of their own over the page:
  /// see paintStageRulers.
  final bool rulersApart;


  /// editingVector is the drawing being edited point by point, its picked shape
  /// and point, drawn in place of a selection box.
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

  /// editingLayers is the layers of the picture being edited, drawn in place
  /// of a selection box. See StageLayers.
  final StageLayers? editingLayers;

  /// chartLabels is the boxes of the selected chart's placed labels, in
  /// document units, outlined so a placed title visibly can be taken hold of
  /// and resized.
  final List<Rect> chartLabels;

  /// tableColumns is where a selected table's column rules are, in document
  /// units, so each can be given a grip that says it can be dragged.
  final List<(double, double, double)> tableColumns;

  /// preview is a picture of what a held stroke would do, and previewOn the
  /// placement it is drawn through; both null when nothing is held. The
  /// placement, not just a destination: the picture is not always drawn whole
  /// ("fill the box" crops it), and stretching the preview into the element
  /// would put the tint in the wrong place.
  final ui.Image? preview;
  final ImagePlacement? previewOn;

  /// liveStroke is the retouching stroke being drawn, in canvas coordinates,
  /// with liveStrokeRadius its width and liveStrokeKeeps which way round it
  /// works. Drawn here because changing the picture means reprocessing every
  /// pixel; the picture catches up when the pointer comes up.
  final List<Offset> liveStroke;
  final double liveStrokeRadius;
  final bool liveStrokeKeeps;

  /// editingText is the id of a text element being typed into, whose own words
  /// are left unpainted: the editor over the top draws them.
  final String? editingText;

  /// editingItem is which of that element's pieces has the editor on it, so
  /// the rest of the card goes on being drawn under it.
  final String? editingItem;

  /// showHandles is false for something whose size and angle belong to another
  /// element (text riding a line): the outline is still drawn, but not the
  /// handles and rotate ring, which would do nothing.
  final bool showHandles;

  /// framing is the picture being repositioned inside its frame, if one is.
  final StageFraming? framing;

  /// backgrounds is the editor's rasterised background, or null in a test
  /// that does not want one. See ProceduralCache.
  final ProceduralCache? backgrounds;

  /// guides is the scaffolding: the grid and the lines the reader put down.
  /// Drawn here and never by the renderer, so nothing published has a grid.
  final CanvasGuides guides;

  /// snapped is the line or lines a drag is caught on, drawn bright while the
  /// drag lasts so a snap is never a mysterious jump.
  final SnapResult? snapped;

  /// showHelpers draws the selection box, the handles and the rotation ring.
  /// A flag of its own: _paintSelection reads selectionBounds, so emptying the
  /// selection would not hide them.
  final bool showHelpers;

  /// camera is the scene's camera on this frame while it plays, or null (see
  /// SceneCamera). Never while editing: a press has to land where the page
  /// looks to be.
  final (double, Offset)? camera;

  /// drafting draws what is rasterised (adjustments, effects) at a smaller size
  /// while a gesture is under way; see RasterCache.drafting.
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
          // for them, and nothing else changes when they do, so without
          // these a placeholder stays up until something else repaints.
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
    // A shadow under the frame, so the canvas reads as a sheet on a desk
    // even when its background matches the editor's.
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
    // the frame at any zoom. The frame never moves (see
    // CanvasStage._pageRect).
    canvas.save();
    canvas.clipRect(view);

    var docSize = document.size.size;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    // The leaf beside this one. Both backdrops go down first and both sets
    // of contents over them, so a picture pulled across the gutter shows
    // on the other page without a seam.
    //
    // The neighbour is a page of the document even while the master is
    // being edited: goToScene alone would leave onMaster set and draw the
    // master twice.
    var beside = facing;
    var over = beside == null
        ? null
        : document.goToScene(beside).copyWith(onMaster: false);
    var aside = facingOnLeft ? docSize.width : -docSize.width;
    // The neighbour at the frame it was left on, so a chart on it neither
    // vanishes nor jumps to its end.
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

      // The spine on the join, so two pages edge to edge do not read as one
      // wide canvas. Only with both on screen.
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
      // under its own elements above.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(aside, 0, docSize.width, docSize.height),
          clipOp: ui.ClipOp.difference);
      _paintContents(canvas, document, frame);
      canvas.restore();
    } else if (gameChange
        case (var left, var leftAt, var over, var t, var leftLive)?) {
      // A game gone on to another scene: the one it left giving way -- framed
      // by its own camera, and its elements as their slots had them as it
      // was left (Ken's systems review, 2026-11-08: it jumped to an
      // unframed page, its moves snapped back).
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

    // A marker's label while playback holds at it: on the canvas, in its
    // units, over what is on it.
    if (markerNote case var note?) {
      paintMarkerNote(canvas, docSize, note, selected: markerNoteGrip);
    }

    // The leaf being edited gets a line round it rather than dimming the
    // other, which would dim a picture across the gutter too. Drawn after
    // the contents, or an element against the edge hides it.
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
    // The box and handles round what is selected, through the scene's
    // camera as the page is drawn -- so a push in does not leave the box
    // behind (Ken, 2026-11-08).
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

    // What a held stroke would do, over its picture, drawn from the
    // brush's own output so preview and result cannot drift apart (see
    // strokePreview).
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

    // The stroke being drawn, inside the page clip (unclipped, it runs over
    // the sidebar when zoomed). A thick round-capped line rather than a
    // stamp per point: it reads the same as the dabbed brush at any speed.
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

    // Everything outside the page dimmed, so the published edge stays
    // obvious: four bands rather than a Path.difference.
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

    // The border last and outside the clip, so it is a full-width line
    // rather than half of one on the clip's edge.
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x55FFFFFF));

    // A hint that there is more canvas outside the frame, only when there
    // is.
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

    // The rulers last, in the widget's own pixels and outside the page
    // clip, which would clip them away.
    _paintRulers(canvas, size);
  }

  /// _paintContents is the page being edited, everything on it as the editor
  /// shows it, over its own backdrop, or with [part] all, with it.
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
        // The whole element only while its own paragraph is being typed
        // into; one piece of it while a piece is.
        skipElement: editingItem == null ? editingText : null,
        skipTextItem: editingItem,
        counterValue: counterValue,
        liveMotion: live ?? liveMotion,
        counterPressed: counterPressed,
        counterRunning: counterRunning,
        audioState: audioState,
        videoShow: videoShow,
        // Drawn once and kept while the design and size hold still (see
        // ProceduralCache): the editor repaints on every pointer move.
        backgrounds: backgrounds,
        // Guide paths show only while editing: they are scaffolding.
        editing: true,
        previewing: previewing);
  }

  /// _paintChartLabels outlines a chart's placed title and description, with a
  /// grip on the corner that resizes them, dashed so it does not read as part
  /// of the design.
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

  /// _paintTableColumns puts a grip on each of a table's inner column rules: a
  /// short bar at top and bottom, since the table draws the rule itself.
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

  /// _paintKnife draws the knife's line: a thin dashed cut over a pale edge,
  /// so it shows on anything.
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

  /// _paintAnchors draws each anchor shown: a ring with a cross through it,
  /// greyed where it is locked and cannot be dragged.
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

  /// _paintTouchAreas draws what a game touches of each element, a thin
  /// blue line, as the Game panel says it is.
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

  /// _paintCameras draws each Camera's frame over the page: what will be shown,
  /// where it is now. Not while looking through it, when the page is the frame.
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
      var label = TextPainter(
        text: TextSpan(
            text: cam.name,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF2A33D))),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, box.topLeft + const Offset(6, 5));
    }
  }

  /// _throughCamera paints [marks] -- drawn in the stage's own space, from
  /// the page by [scale] and [origin] -- moved as the scene's [camera] moves
  /// what is on the page (see paintCanvasDocument's framing): the page's
  /// middle to the camera's focus, closer by its zoom.
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
    _paintTableColumns(canvas);
    // A selected path shows its points and handles instead of a box: the
    // box round a curve cannot be usefully dragged.
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
      // Painting (tint, or the pencil with its points hidden): nothing is
      // picked or boxed, the drawing alone.
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

    // Every element of a multi-selection outlined on its own, under the
    // box round the lot (see chosenOutlines). No handles on these: the
    // group is what is resized.
    _paintChosenBoxes(canvas);
    _paintWholeChain(canvas);
    _paintTrail(canvas);
    _paintCopies(canvas);

    var centre = bounds.center * scale + origin;
    var half = Offset(bounds.width, bounds.height) * scale / 2;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    // Turned and slanted as the selection is, so the handles are at its
    // drawn corners and sides.
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

  /// _paintChosenBoxes outlines each element of a multi-selection: brighter
  /// than the kept boxes, thinner than the selection's own.
  void _paintChosenBoxes(Canvas canvas) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x993D7EFF);

    for (var element in chosenOutlines(document, selection, frame)) {
      // Its box as it is laid on the page, turned and slanted.
      var box = element.movedBoundsAt(frame, document, live: liveMotion);
      var corners =
          BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
              .corners(box);
      canvas.drawPath(
          Path()..addPolygon([for (var p in corners) p * scale + origin], true),
          paint);
    }
  }

  /// _paintWholeChain draws the element whose chain is previewed from a
  /// join faintly as its whole chain has it, under where the join leaves
  /// it -- the prototype's faint whole chain, to compare the two.
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

  /// _paintTrail draws the one element selected as it moves, while its
  /// motion is open in the Chain: the path its middle takes three seconds
  /// either side of now, dashed, and faint copies of it where it was a
  /// moment before -- the prototype's trail and onion skin. Nothing for an
  /// element that stands still.
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
    // Dashed: four on, five off, along the whole path.
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

  /// _paintCopies shows the one element selected, reused, as its copies
  /// (Ken, 2026-11-08: each an object): every copy outlined faintly, those
  /// picked ringed and numbered -- what its chain edits.
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
      // The one picked has the selection's box and handles instead (see
      // CanvasStage's _oneCopy): its number on it, no ring under the box.
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

  /// _paintKeptBoxes outlines every element while that is asked for (see
  /// CanvasController.showAllBounds), quieter than the selection and under it.
  void _paintKeptBoxes(Canvas canvas) {
    if (!showAllBounds) return;
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x803D7EFF);

    for (var element in document.elements) {
      if (!element.visible) continue;
      if (selection.contains(element.id)) continue;

      // Its box as it is laid on the page, turned and slanted.
      var box = element.movedBoundsAt(frame, document, live: liveMotion);
      var corners =
          BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
              .corners(box);
      canvas.drawPath(
          Path()..addPolygon([for (var p in corners) p * scale + origin], true),
          paint);
    }
  }

  /// _paintWarp draws a warp grid being worked on: its lines dark under
  /// light, so they show over any picture; its points as small squares,
  /// the picked ones filled; and the box round the picked ones, with its
  /// corners and turning knob.
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

  /// _paintFlowLines draws the links between text boxes, from a list rather
  /// than from the selection, before anything can return early: a link
  /// belongs to two boxes, and a box asked to stay visible is shown whatever
  /// is selected.
  void _paintFlowLines(Canvas canvas) {
    for (var line in flowLines) {
      // Red: the box the words leave has more than it can show, as its grip
      // says.
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

  /// _paintFlowGrips draws the two dots that make a text box a link in a
  /// chain: where words come in, and where the ones that do not fit go.
  void _paintFlowGrips(Canvas canvas) {
    var white = Paint()..color = const Color(0xFFFFFFFF);
    var blue = const Color(0xFF3D7EFF);

    var grips = flowGrips;
    if (grips == null) return;

    // Red is the only thing on the canvas saying there are words the box
    // is not showing.
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
      // An arrow inside the out grip, pointing the way the words go.
      if (!filled) return;
    }

    dot(grips.inAt, blue, grips.receiving);
    dot(grips.outAt, out, grips.overflowing || grips.linked);
  }

  /// _paintShapeBox draws the box round the shape the shapes tool has picked,
  /// in the drawing's units [box], with a handle at each corner and each side's
  /// middle: what moves and resizes it.
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
    // The round handle on a stalk above the box that turns what is in it,
    // as an element's does.
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
  /// outline round each picture layer, so what can be picked can be seen, and
  /// the picked one's box with its handles and its turning knob. The base
  /// picture, picked, is the frame itself.
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
    // The lasso's outline, closed back to where it began, as it is drawn:
    // dark under light so it shows over any picture, and the inside faintly
    // tinted, the area it will take.
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

  /// _paintMirrorLines draws the pencil's mirror lines through the middle of
  /// the drawing [e], dashed and through the whole of it, so what a stroke will
  /// be mirrored across can be seen first.
  void _paintMirrorLines(
      Canvas canvas, VectorElement e, bool across, bool down) {
    if (!across && !down) return;
    var space = VectorSpace(e);
    var v = e.viewBox;
    // A little past the drawing each way, so it reads as a line, not an
    // edge.
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

  /// _paintVectorControls draws a drawing being edited: every shape's outline,
  /// faint; the picked shape's in the handle colour with its points, and the
  /// points of any shape with points picked (a box can pick from several);
  /// and the handles of the one point picked, where exactly one is.
  /// [everyShape] shows every shape's points, while a box is dragged.
  void _paintVectorControls(Canvas canvas, VectorElement e, int picked,
      VectorPick? pick, Set<VectorPick> picks,
      {bool everyShape = false, Set<int>? combining}) {
    var shapes = e.shapes;
    if (shapes == null) return;
    var space = VectorSpace(e);
    var colour = e.handleColor;
    Offset screen(Offset v) => space.toCanvas(v) * scale + origin;

    // Through the same placement and turn the drawing is drawn with, so
    // the outlines lie exactly on it.
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
    // Combining shapes: whole shapes are picked, so outlines are all there
    // is: the picked ones, and every shape combined into them, lit.
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

    // Every shape's points while a box is dragged, and while nothing is
    // picked (how the drawing opens), so there is always something to take
    // hold of.
    if (picked < 0 && picks.isEmpty) everyShape = true;
    var shown = <int>{
      if (everyShape) ...[for (var i = 0; i < shapes.length; i++) i],
      if (picked >= 0 && picked < shapes.length) picked,
      for (var p in picks)
        if (p.shape < shapes.length) p.shape,
    };
    if (shown.isEmpty) return;
    // The box round several picked points, faint: where a press takes hold
    // of them all.
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

    // The picked point's handles first, so the points sit on top of their
    // lines.
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
    // A joint is one point however many lines meet at it: every end lying
    // there is drawn picked, or those drawn over it hide that it is.
    var lit = joinedTo(e, picks);
    for (var showing in shown) {
      var paths = shapes[showing].paths;
      for (var p = 0; p < paths.length; p++) {
        for (var n = 0; n < paths[p].nodes.length; n++) {
          var node = paths[p].nodes[n];
          var at = screen(node.point);
          var chosen = lit.contains(VectorPick(showing, p, n));
          // A smooth point is round, a corner square, since that decides how a
          // handle moves.
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

  /// _paintPathControls draws a path's points and its handles, the handles
  /// only where a node is bent: an unbent node's sit on top of it.
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

  /// _paintFraming shows the rest of the picture while it is moved about inside
  /// its frame: everything outside the frame faint, the inside left to the
  /// renderer, so what comes into shot can be seen.
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

    // The whole picture faint, with the frame punched out, so the part on
    // the canvas shows at full strength and the two read as one picture.
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

    // The frame itself, so the edge being placed against is clear.
    canvas.drawRect(
        it.frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = const Color(0xFF3D7EFF));
    canvas.restore();
  }

  /// _paintGuides draws the grid, the guides, and whatever a drag is caught on:
  /// over the document, so a photograph cannot hide a guide, and under the
  /// selection, so the handles stay findable.
  void _paintGuides(Canvas canvas) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);

    // In document units, the canvas's space after the transform above.
    // [page] is the frame on screen; adding its offset would shift every
    // guide and move them with the window.
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

    // What the drag has caught, over everything, in a colour nothing else
    // uses.
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

  /// _paintRulers draws a strip along each edge asked for, in screen pixels,
  /// ticks placed by putting document coordinates through the same transform.
  /// Laid against the page (see rulerBandsFor) and numbered from its top-left,
  /// so the numbers agree with the X and Y fields; the step lands on the grid
  /// (see rulerStep).
  void _paintRulers(Canvas canvas, Size size) {
    // Over a page that scrolls, the stage draws them in a layer that does
    // not -- see paintStageRulers.
    if (rulersApart) return;
    paintStageRulers(canvas, size, guides, document.size.size, scale, origin, page);
  }

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
      // A new set each build: the same ids are the same selection.
      !setEquals(old.selection, selection) ||
      !setEquals(old.pickedCopies, pickedCopies) ||
      old.trail != trail ||
      old.gameChange != gameChange ||
      old.selectionBounds != selectionBounds ||
      old.selectionSkew != selectionSkew ||
      old.marquee != marquee;
}

/// StageWarp is a warp grid as the stage draws it -- see StageLayers.warp.
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
/// picked one's corners, handles and turning knob. A picked base picture has
/// its frame as its corners and no handles: the frame is resized as the
/// element.
class StageLayers {
  final List<List<Offset>> others;
  final List<Offset>? picked;

  /// chosen are the layers picked with [picked], outlined as it is but with
  /// no handles: they move with it, and are lined up with it.
  final List<List<Offset>> chosen;
  final List<Offset> handles;
  final Offset? knob;

  /// masking is the layer whose mask a mask tool is working on, and how the
  /// mask is to be shown; ring is the brush, centre and radius.
  final ({ImageElement element, String layer, MaskView view})? masking;
  final (Offset, double)? ring;

  /// trail is a quick-select stroke being drawn: its points, its radius,
  /// and whether it takes away.
  final (List<Offset>, double, bool)? trail;

  /// marker is where the clone tool copies from.
  final Offset? marker;

  /// lasso is the outline of a lasso being drawn, in document units: the
  /// shape it will close on, shown as it is drawn.
  final List<Offset>? lasso;

  /// warp is a picture's warp grid being worked on, in document units: its
  /// lines, curved as the picture bends; its points and which are picked; and,
  /// with two or more picked, the box round them to size and turn them by. See
  /// ImageWarp.
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
/// [page], kept inside a view [size] across, numbered from the page's
/// top-left at [scale] screen pixels to a unit of a [sheet] whose top-left
/// is at [origin]. The stage calls it along its page, or in a layer of its
/// own over a page that scrolls, so the rulers stay at the window's edges.
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
    // [origin] as given; putting the frame's corner through the transform
    // again would push every tick off the page.
    var zero = origin;

    void number(double at, Offset where, {required bool vertical}) {
      var painter = TextPainter(
        text: TextSpan(
          text: "${at.round()}",
          style: const TextStyle(fontSize: 8, color: Color(0xAAFFFFFF)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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
      painter.dispose();
    }

    // The horizontal rulers: top and bottom.
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

    // The vertical rulers: left and right.
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

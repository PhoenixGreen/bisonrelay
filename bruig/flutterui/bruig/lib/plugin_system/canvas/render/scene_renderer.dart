import 'dart:typed_data';
import 'package:bruig/plugin_system/canvas/render/model3d/model3d_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/motion.dart'
    show MotionProp, revealFrom, revealTo;
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/character3d_painter.dart';
import 'package:bruig/plugin_system/canvas/render/parallax_painter.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart'
    show MotionDeviceKind;
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/render/edge_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/edge_cleaning.dart';
import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/render/loop_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/element_effects.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/render/video_key.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:flutter/painting.dart';

// scene_renderer.dart draws a whole document at one frame.
//
// It is the single place a canvas becomes pixels: the editing stage, the
// thumbnails, every export and a published canvas replayed in a chat all go
// through it, so what is seen is what is sent.
//
// It draws in the document's own design coordinates and knows nothing about
// zoom, scroll, selection or the widget tree; the caller sets up the
// transform. It takes no BuildContext because the export has no widget tree.

/// CanvasVector is a picture kept as a picture: the drawing itself and the
/// size it was drawn for.
///
/// A vector stays a vector wherever it can, so it is sharp at any size
/// without carrying a bitmap for each.
class CanvasVector {
  final ui.Picture picture;
  final Size size;
  const CanvasVector(this.picture, this.size);
}

/// CanvasImageSource hands the renderer decoded pictures.
///
/// An interface rather than a map because a picture may not be ready: it is
/// decoded off the main thread, and a cut-out is recomputed when its
/// settings change. Null for "not yet" lets the renderer draw a placeholder
/// and the stage redraw a moment later, rather than blocking a frame.
abstract class CanvasImageSource {
  /// resolve returns the picture for [assetId] with [removal] applied, or null
  /// when it is not decoded yet.
  ui.Image? resolve(String assetId, BackgroundRemoval removal);

  /// resolveVector is the same asset kept as a drawing, when it is one.
  ///
  /// Null by default and for every bitmap: a caller that can draw a vector
  /// asks and falls back to [resolve]; one that needs pixels (the background
  /// remover, the export pipeline) does not ask.
  CanvasVector? resolveVector(String assetId) => null;

  /// resolveOutline is where the picture's ink actually is, for text wrapped
  /// round it (the only caller). See ImageSilhouette.
  ///
  /// Null until it has been read from the decoded pixels, since a painter
  /// cannot wait: the box stands in until a later frame.
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;

  /// loading is whether anything asked for is still being read or decoded.
  /// A painter cannot wait for it, and draws a placeholder meanwhile; an
  /// export can, and must -- see drawWhenLoaded.
  bool get loading => false;
}

/// drawWhenLoaded asks [images] for everything [paint] draws, and waits for
/// it to arrive, so that what an export draws next is the pictures rather
/// than their placeholders.
///
/// The picture store reads a picture only when something first asks for it,
/// and an export draws each page once, so without this a picture not yet
/// drawn in the editor is exported as its placeholder. Up to three rounds,
/// since a picture arriving can ask for another (its outline, for text
/// wrapped round it).
Future<void> drawWhenLoaded(
    CanvasImageSource? images, void Function(ui.Canvas canvas) paint) async {
  if (images == null) return;
  for (var round = 0; round < 3; round++) {
    var recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder));
    recorder.endRecording().dispose();
    if (!images.loading) return;
    // Bounded: a picture that never arrives is drawn as missing rather than
    // holding the whole export up for ever.
    for (var waited = 0; images.loading && waited < 300; waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// CanvasPaintPart is how much of a canvas one call draws.
///
/// For facing pages only: both leaves' backdrops go down first and their
/// contents over both, so a picture pulled across the gutter is seen on the
/// other page rather than covered by its backdrop.
enum CanvasPaintPart {
  /// all is a whole canvas, which is what every other caller wants.
  all,

  /// backdrop is the document's background and nothing on it.
  backdrop,

  /// contents is the master canvas and the elements, with no backdrop under
  /// them.
  contents,
}

/// paintCanvasDocument draws [doc] at [frame].
///
/// [hoveredButton] is the id of the button under the pointer, if any: the
/// one piece of interaction state the renderer takes, because hover colours
/// are part of a button's design and must show while they are chosen.
void paintCanvasDocument(
  ui.Canvas canvas,
  CanvasDocument doc, {
  int frame = 0,
  CanvasPaintPart part = CanvasPaintPart.all,
  CanvasImageSource? images,
  String? hoveredButton,
  bool editing = false,

  /// skipElement is left out of the drawing: a text element being typed
  /// into has a real text field over it.
  String? skipElement,

  /// skipTextItem is one of a text element's extra pieces, left out for the
  /// same reason; the rest of the element is still drawn.
  String? skipTextItem,

  /// backgrounds is the editor's cache of generated backgrounds. Null for the
  /// exporter, which renders each frame once and wants exact pixels at a size
  /// of its own choosing. See ProceduralCache.
  ProceduralCache? backgrounds,

  /// counterValue and counterPressed are what a live counter is showing and
  /// which of its buttons is lit -- see paintElement. Null in an export,
  /// where nothing is running.
  double Function(CounterElement)? counterValue,

  /// liveMotion is the elements playing from their slots -- see
  /// motion_player.dart. Null in an export, which draws the timeline.
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,

  /// audioState is how a sound is doing -- playing, muted, how loud -- for the
  /// icon to show it. Null in an export, where nothing is playing.
  AudioState Function(AudioElement)? audioState,

  /// videoShow is where each video has got to -- its frame, its play bar.
  /// Null in an export, which shows the poster.
  VideoShow Function(VideoElement)? videoShow,

  /// backdrop is the background already rasterised, for a caller drawing many
  /// frames of a document whose background does not move. See ExportBackdrop.
  ui.Image? backdrop,

  /// previewing is one element drawn at a frame of its own, while it alone
  /// is being previewed. See CanvasController.previewing.
  ({String id, int frame})? previewing,

  /// camera is the scene's framing on this frame -- a zoom and the point of
  /// the page at the middle of the picture -- or null for the page as it is.
  /// It moves the scene's backdrop and its own elements, and not the
  /// master's: a frame or a watermark on the shared canvas stays where it is
  /// while the shot moves under it. See SceneCamera.
  (double, Offset)? camera,
}) {
  var rect = doc.size.rect;
  var time = frame / (doc.frameRate <= 0 ? 1 : doc.frameRate);
  void framed(void Function() paint) {
    if (camera == null) {
      paint();
      return;
    }
    var (zoom, focus) = camera;
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(zoom);
    canvas.translate(-focus.dx, -focus.dy);
    // A tile map's far layers lag the camera by how far it has moved.
    tileCameraShift = focus - rect.center;
    try {
      paint();
    } finally {
      tileCameraShift = null;
    }
    canvas.restore();
  }

  if (part != CanvasPaintPart.contents) {
    framed(() => _paintDocumentBackground(canvas, rect, doc, time, images,
        backgrounds, doc.frameRate.toDouble(), backdrop, videoShow));
  }
  if (part == CanvasPaintPart.backdrop) return;

  // The shared canvas, under every scene (over it with doc.masterOver). Not
  // while the master is itself being edited, or it would be drawn twice.
  var master = doc.masterScene;
  // The master runs on the whole run's clock, not the scene's, so its
  // animation does not restart at every scene. See
  // CanvasDocument.startOfScene.
  var onMaster = master != null && !doc.editingMaster
      ? {for (var e in master.elements) e.id}
      : const <String>{};
  // Except in a book: its pages are read in any order, and what is on its
  // master (a page number, a running head) belongs to the page it is on.
  var runFrame = doc.hasScenes && !doc.isPages && onMaster.isNotEmpty
      ? doc.startOfScene(doc.at) + frame
      : frame;
  void scene(List<CanvasElement> elements) =>
      _paintScene(canvas, doc, elements, frame,
          onMaster: onMaster,
          runFrame: runFrame,
          images: images,
          editing: editing,
          hoveredButton: hoveredButton,
          skipElement: skipElement,
          skipTextItem: skipTextItem,
          counterValue: counterValue,
          liveMotion: liveMotion,
          counterPressed: counterPressed,
          counterRunning: counterRunning,
          audioState: audioState,
          videoShow: videoShow,
          previewing: previewing,
          backgrounds: backgrounds);
  // With a camera, the master is drawn as it is and the scene through the
  // camera, as two runs rather than one list stacked together.
  if (camera != null) {
    var shared = master != null && !doc.editingMaster;
    if (shared && !doc.masterOver) scene(master.elements);
    framed(() => scene(doc.elements));
    // Over, a HUD: still while the camera moves the level under it.
    if (shared && doc.masterOver) scene(master.elements);
    return;
  }
  // The master under the page, and its page numbers over it -- see
  // stackedWithMaster.
  _paintScene(
      canvas,
      doc,
      master != null && !doc.editingMaster
          ? stackedWithMaster(master.elements, doc.elements,
              over: doc.masterOver)
          : doc.elements,
      frame,
      onMaster: onMaster,
      runFrame: runFrame,
      images: images,
      editing: editing,
      hoveredButton: hoveredButton,
      skipElement: skipElement,
      skipTextItem: skipTextItem,
      counterValue: counterValue,
      liveMotion: liveMotion,
      counterPressed: counterPressed,
      counterRunning: counterRunning,
      audioState: audioState,
      videoShow: videoShow,
      previewing: previewing,
      backgrounds: backgrounds);
}

/// _paintScene draws one canvas's worth of elements: the shared canvas or
/// the scene, with the same rules for what is skipped.
void _paintScene(
  ui.Canvas canvas,
  CanvasDocument doc,
  List<CanvasElement> elements,
  int frame, {
  /// onMaster are the elements of the shared canvas, drawn at [runFrame] --
  /// the frame of the whole run -- rather than at the scene's [frame].
  Set<String> onMaster = const {},
  int? runFrame,
  CanvasImageSource? images,
  bool editing = false,
  String? hoveredButton,
  String? skipElement,
  String? skipTextItem,
  double Function(CounterElement)? counterValue,
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,
  ({String id, int frame})? previewing,
  ProceduralCache? backgrounds,
}) {
  // Lines that only carry a text and are set to stay out of the picture.
  // Collected first because the text that hides a line may be drawn after it.
  var hidden = <String>{
    for (var e in elements)
      if (e is TextElement && e.curve?.hideHost == true) e.curve!.elementId,
  };

  // Figures stood on a map are drawn by it, among the things on it.
  var onMaps = <String>{
    for (var e in elements)
      if (e is TileMapElement && e.visible) ...e.figureIds,
  };

  // Characters standing on a stage are drawn with it, nearest last.
  for (var element in inStageOrder(elements, frame,
      backdrop: doc.drawnBackground, page: doc.size.rect)) {
    if (!element.visible ||
        element.id == skipElement ||
        hidden.contains(element.id) ||
        onMaps.contains(element.id)) {
      continue;
    }
    paintElement(
        canvas,
        element,
        element.id == previewing?.id
            ? previewing!.frame
            : onMaster.contains(element.id)
                ? runFrame ?? frame
                : frame,
        frameRate: doc.frameRate,
        images: images,
        editing: editing,
        document: doc,
        skipTextItem: skipTextItem,
        counterValue: counterValue,
        liveMotion: liveMotion,
        counterPressed: counterPressed,
        counterRunning: counterRunning,
        audioState: audioState,
        videoShow: videoShow,
        backgrounds: backgrounds,
        hovered: element.id == hoveredButton);
  }
}

void _paintDocumentBackground(
    ui.Canvas canvas,
    Rect rect,
    CanvasDocument doc,
    double time,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    double frameRate,
    [ui.Image? backdrop,
    VideoShow Function(VideoElement)? videoShow]) {
  // A backdrop handed in is this document's background, rasterised once for
  // a whole run of frames. See ExportBackdrop.
  if (backdrop != null) {
    // At one pixel to one pixel it is drawn unfiltered, so it matches what
    // the slow road would draw; under a scene's camera it is scaled, and
    // filtered like any scaled picture.
    var m = canvas.getTransform();
    var across = rect.width * math.sqrt(m[0] * m[0] + m[1] * m[1]);
    var exact = (across - backdrop.width).abs() < 0.5;
    canvas.drawImageRect(
        backdrop,
        Rect.fromLTWH(
            0, 0, backdrop.width.toDouble(), backdrop.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = exact ? FilterQuality.none : FilterQuality.medium);
    return;
  }
  // The master's own where the shared canvas is switched on and has one.
  // See CanvasDocument.drawnBackground.
  var bg = doc.drawnBackground;

  // The picture, the drawing and the video are elements stretched to the
  // page, whatever box they were saved with.
  T onPage<T extends CanvasElement>(T e) => e.rebase(ElementBase(
      id: e.id,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height)) as T;

  var picture = bg.shownPicture;
  var decoded = picture == null
      ? null
      : images?.resolve(picture.assetId, picture.removal);
  // A decoded picture covering the whole page with nothing cut out hides the
  // pattern, so the pattern is not generated. Anything else shows the
  // pattern round it or through it.
  var covered = decoded != null &&
      picture!.fit == ImageFit.cover &&
      !picture.removal.active &&
      picture.frame == null &&
      picture.box.padding == 0;
  if (bg.isStage) {
    // The stage in the pattern's place, seen through its camera; whatever
    // stands on it is drawn in front.
    paintStage(canvas, rect, bg.stageOn(rect), (time * frameRate).round(),
        images: images);
  } else if (bg.isParallax) {
    paintParallax(canvas, rect, bg.parallaxOn(rect), (time * frameRate).round(),
        frameRate: frameRate,
        images: images,
        loopFrames: parallaxLoopFrames(doc));
  } else if (!covered) {
    _paintPattern(canvas, rect, bg, time, images, backgrounds, frameRate);
  }
  if (picture != null && decoded != null) {
    _paintImage(canvas, rect, onPage(picture), images);
  }
  if (bg.drawing case var drawing? when drawing.hasDrawing) {
    paintVector(canvas, rect, onPage(drawing), images);
  }
  if (bg.video case var video? when !video.clip.isEmpty) {
    var page = onPage(video);
    _paintVideo(canvas, rect, page,
        videoShow?.call(page) ?? VideoShow.idle(page), images,
        placeholder: false);
  }
}

/// _paintPattern draws a background's generated pattern.
void _paintPattern(
    ui.Canvas canvas,
    Rect rect,
    CanvasBackground bg,
    double time,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    double frameRate) {
  // The cached one where it is the same background at the same size. See
  // ProceduralCache.
  var ready = backgrounds?.imageFor(bg.spec, rect.size, time, images);
  if (ready != null) {
    canvas.drawImageRect(
        ready,
        Rect.fromLTWH(0, 0, ready.width.toDouble(), ready.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.low);
    return;
  }
  // The rate as well as the time: a movement that runs once is counted in
  // frames. See ProceduralSpec.passFrames.
  paintProcedural(canvas, rect, bg.spec,
      time: time, frameRate: frameRate, images: images);
}

/// paintDocumentBackdrop draws a document's background and nothing else.
///
/// For an export, which rasterises it once and draws that picture on every
/// frame. See ExportBackdrop.
void paintDocumentBackdrop(ui.Canvas canvas, CanvasDocument doc,
        {CanvasImageSource? images}) =>
    _paintDocumentBackground(
        canvas, doc.size.rect, doc, 0, images, null, doc.frameRate.toDouble());

/// chartSeriesReveal is how far each of a chart's series is through its own
/// arrival, or null where none has been offset (nearly every chart).
///
/// A series' reveal is the chart's own reveal read ChartSeries.delay
/// seconds earlier, so the offset is a shift in time rather than a change of
/// speed, and a delayed series goes on arriving after the chart's arrival
/// has finished.
///
/// [poseAt] is the chart's pose on a frame, clips included; without it, its
/// legacy track alone.
List<double>? chartSeriesReveal(ChartElement e, int frame, int frameRate,
    {Keyframe Function(int frame)? poseAt}) {
  if (!e.data.series.any((s) => s.delay != 0)) return null;
  var track = e.track;
  var rate = frameRate <= 0 ? 1 : frameRate;
  var pose = poseAt ?? (int f) => track?.at(f) ?? Keyframe.rest;
  double at(int f) => pose(f).values[KeyframeChannel.reveal] ?? 1;
  var whole = at(frame);
  return [
    for (var s in e.data.series)
      s.delay == 0 ? whole : at((frame - s.delay * rate).round()),
  ];
}

/// leavesByItself is whether [element] has an exit of its own chosen to
/// play over its closing stretch, or is a kind with no exits at all. Where
/// neither is true, paintElement fades it instead.
bool leavesByItself(CanvasElement element) => switch (element) {
      TextElement e => e.animation.closes,
      ChartElement e => e.animation.closes,
      ShapeElement e => e.animation.closes,
      ImageElement e => e.animation.closes,
      VectorElement e => e.animation.closes,
      LineElement e => e.animation.closes,
      PathElement e => e.animation.closes,
      TableElement e => e.animation.closes,
      CounterElement e => e.animation.closes,
      ButtonElement e => e.animation.closes,
      VideoElement e => e.animation.closes,
      Character3dElement e => e.animation.closes,
      _ => true,
    };

/// paintElement draws one element, with its animation pose applied.
void paintElement(
  ui.Canvas canvas,
  CanvasElement element,
  int frame, {
  int frameRate = 12,
  CanvasImageSource? images,
  bool hovered = false,

  /// editing is true on the stage and false wherever a document is turned
  /// into a file: a guide path is drawn only while editing (_paintPath).
  bool editing = false,

  /// skipTextItem is the one of this element's pieces not to draw, because it
  /// has an editor open over it. See CanvasTextEditor.
  String? skipTextItem,

  /// document is the element's document, for clips, stages, curves and page
  /// numbers. Null for a lone element (a thumbnail), which then draws from
  /// its own track and box alone.
  CanvasDocument? document,

  /// counterValue is what a live counter is showing at this instant, and
  /// counterPressed which of its buttons is lit. Asked of the caller because
  /// a running counter runs in somebody's window; null, as in an export,
  /// means nothing is running.
  ///
  /// liveMotion, audioState and videoShow: see paintCanvasDocument.
  double Function(CounterElement)? counterValue,
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,

  /// poseOutside leaves the pose's move, turn, scale and fade out, for a
  /// caller that applies them itself: the interactive EPUB, which draws each
  /// element once and moves it with CSS. What the pose pins besides -- how
  /// far an arrival has got, a count, a bow -- is still drawn, because that
  /// is the element's content rather than where it is.
  bool poseOutside = false,

  /// backgrounds is the editor's cache of generated patterns, which a
  /// background element is drawn from as the canvas's own background is.
  ProceduralCache? backgrounds,

  /// instance is which of an element reused to draw (see instances.dart);
  /// null draws every one, and -1 the element as placed, as one.
  int? instance,

  /// blended is set where the element's blend is already being laid on,
  /// so it is drawn into that once.
  bool blended = false,
}) {
  // A camera frames the picture and is never in it: see cameraFrame.
  if (element is CameraElement) return;
  // Laid over what is under it by its Output's blend: drawn on its own,
  // then combined. Every instance together, as the one element it is.
  if (!blended && element.base.blend != LayerBlend.normal) {
    canvas.saveLayer(null, Paint()..blendMode = element.base.blend.flutter);
    paintElement(canvas, element, frame,
        frameRate: frameRate,
        images: images,
        hovered: hovered,
        editing: editing,
        skipTextItem: skipTextItem,
        document: document,
        counterValue: counterValue,
        liveMotion: liveMotion,
        counterPressed: counterPressed,
        counterRunning: counterRunning,
        audioState: audioState,
        videoShow: videoShow,
        poseOutside: poseOutside,
        backgrounds: backgrounds,
        instance: instance,
        blended: true);
    canvas.restore();
    return;
  }
  // An element reused: each of its instances.
  if (instance == null && document != null) {
    if (element.base.motion.instances case var set? when set.count > 0) {
      void one(ui.Canvas on, int which) => paintElement(on, element, frame,
          frameRate: frameRate,
          images: images,
          hovered: hovered,
          editing: editing,
          skipTextItem: skipTextItem,
          document: document,
          counterValue: counterValue,
          liveMotion: liveMotion,
          counterPressed: counterPressed,
          counterRunning: counterRunning,
          audioState: audioState,
          videoShow: videoShow,
          poseOutside: poseOutside,
          backgrounds: backgrounds,
          instance: which,
          blended: true);
      if (stampsCopies(element, liveMotion)) {
        // Alike but for where they are: drawn once, and stamped at each
        // place.
        var rec = ui.PictureRecorder();
        one(ui.Canvas(rec), -1);
        var stamp = rec.endRecording();
        for (var item in set.items) {
          canvas.save();
          canvas.translate(item.dx, item.dy);
          canvas.drawPicture(stamp);
          canvas.restore();
        }
        stamp.dispose();
      } else {
        for (var i = 0; i < set.count; i++) {
          var hue = set.hueOf(i);
          if (hue != 0) {
            canvas.saveLayer(
                null,
                Paint()
                  ..colorFilter = ColorFilter.matrix(colourMatrix(hue, 1, 0)));
          }
          // Its pose left to the caller (an EPUB's CSS moves the element
          // as a whole): its own place, at least, drawn here.
          if (poseOutside) {
            canvas.save();
            canvas.translate(set.items[i].dx, set.items[i].dy);
          }
          one(canvas, i);
          if (poseOutside) canvas.restore();
          if (hue != 0) canvas.restore();
        }
      }
      return;
    }
  }
  // Its clips' moves over any legacy track. See motion_document.dart.
  var pose = poseWithMotion(element, frame, document,
      live: liveMotion, instance: instance, frameRate: frameRate);
  var outer = poseOutside ? Keyframe.rest : pose;
  var alpha = (element.opacity * outer.opacity).clamp(0.0, 1.0);
  // A closing stretch with no exit chosen fades rather than doing nothing:
  // the editor never leaves one, but a preset, a paste or a script can.
  var close = pose.values[KeyframeChannel.close] ?? 0;
  if (!poseOutside && close > 0 && !leavesByItself(element)) {
    alpha *= (1 - close).clamp(0.0, 1.0);
  }
  if (alpha <= 0.002) return;

  // A video is on screen only while its clip is, so the two halves of a cut
  // clip do not cover each other with posters. A master's video in a run of
  // scenes has been handed the run's frame already (paintCanvasDocument), and
  // a book's has its page's.
  if (element is VideoElement &&
      document != null &&
      document.offTimeline(element.clip, frame,
          onMaster: document.isPages &&
              (document.masterScene?.elements.contains(element) ?? false))) {
    return;
  }

  var bounds = element.bounds;

  // Something standing on a stage is drawn where the stage's camera sees it:
  // a 3D model through the camera, anything else as a flat in perspective.
  // Both lit by the stage.
  var spot = element.base.spot;
  if (spot != null && document != null && canStand(element)) {
    var at = stagedIn(document, element, frame);
    if (at == null) {
      // Its stage is there, but the camera cannot see it: behind the lens.
      if (stageNamed(spot.stage, document.elements,
              backdrop: document.drawnBackground, page: document.size.rect) !=
          null) {
        return;
      }
    } else {
      // Its shadow on the floor first, under it -- the fainter the higher
      // it is held off the floor.
      if (at.shadow case var shadow?) {
        var off = (1 - at.spot.lift / 2).clamp(0.25, 1.0);
        canvas.drawPath(
            shadow,
            Paint()
              ..color = Color.fromARGB((60 * off * alpha).round(), 0, 0, 0)
              ..maskFilter = ui.MaskFilter.blur(
                  ui.BlurStyle.normal, math.max(1.0, at.box.height * 0.02)));
      }
      var light = lightFilter(at.stage.light);
      var flat = element is! Character3dElement;
      var layered = light != null || (!flat && alpha < 0.999);
      if (layered) {
        canvas.saveLayer(
            null,
            Paint()
              ..colorFilter = light
              ..color = const Color(0xFFFFFFFF)
                  .withValues(alpha: flat ? 1.0 : alpha));
      }
      if (element is Character3dElement) {
        paintCharacter3d(canvas, at.box, element, frame,
            frameRate: frameRate, editing: editing, images: images, staged: at);
      } else if (element is Object3dElement) {
        paintObject3d(canvas, at.box, element, images,
            plays: modelPlaysAt(element, frame, document, live: liveMotion),
            editing: editing,
            staged: at);
      } else {
        canvas.save();
        canvas.transform(at.matrix!);
        paintElement(canvas, element.withBase(clearSpot: true), frame,
            frameRate: frameRate,
            images: images,
            hovered: hovered,
            editing: editing,
            skipTextItem: skipTextItem,
            document: document,
            counterValue: counterValue,
            liveMotion: liveMotion,
            counterPressed: counterPressed,
            counterRunning: counterRunning,
            audioState: audioState,
            videoShow: videoShow,
            poseOutside: poseOutside,
            backgrounds: backgrounds);
        canvas.restore();
      }
      if (layered) canvas.restore();
      return;
    }
  }

  // A page number on the outside edge of the leaf: mirrored about the middle
  // of a left-hand page, so both sides of a spread match and a centred one
  // stays centred. See CounterElement.mirrored.
  if (element is CounterElement &&
      element.mirrored &&
      element.isPageNumber &&
      document != null &&
      document.pageIsLeftHand) {
    var page = document.size.rect;
    bounds = Rect.fromLTWH(page.left + page.right - bounds.right, bounds.top,
        bounds.width, bounds.height);
  }

  // Nothing to draw in no room -- except a line, whose box has no height
  // when it is level and no width when it is plumb. paintArriving agrees.
  var flat = element is LineElement;
  if (bounds.width <= 0 && bounds.height <= 0) return;
  if (!flat && (bounds.width <= 0 || bounds.height <= 0)) return;

  // Text riding a line has no transform of its own: where it is, its turn
  // and its size are the line's. Its fade is kept, being the text's own.
  if (element is TextElement && _curveFor(element, document, frame) != null) {
    canvas.saveLayer(
        null,
        Paint()
          ..color =
              const Color(0xFF000000).withValues(alpha: alpha.toDouble()));
    _paintText(canvas, bounds, element, document,
        pose: pose, frame: frame, skipItem: skipTextItem);
    canvas.restore();
    return;
  }

  canvas.save();

  // A team linked to a pitch likewise takes its place from the pitch (see
  // team_painter.dart); only its fade is its own.
  if (element is TeamElement && element.linked) {
    if (alpha < 0.999) {
      canvas.saveLayer(null,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
    }
    paintTeam(canvas, bounds, element, frame,
        document: document, images: images);
    if (alpha < 0.999) canvas.restore();
    canvas.restore();
    return;
  }

  // The pose's shift first, in document space, so a moved element turns
  // about where it now is rather than where it was drawn.
  if (outer.dx != 0 || outer.dy != 0) canvas.translate(outer.dx, outer.dy);

  // Squashed along the way it goes, about its middle, across the page: see
  // the Squash device.
  if (outer.values[KeyframeChannel.squash] case var s?
      when (s - 1).abs() > 1e-3 && s > 0) {
    var a = outer.values[KeyframeChannel.squashAngle] ?? 0;
    var c = bounds.center;
    canvas.translate(c.dx, c.dy);
    canvas.rotate(a);
    canvas.scale(s, 1 / s);
    canvas.rotate(-a);
    canvas.translate(-c.dx, -c.dy);
  }

  // Its resting turn and slant about its centre (BoxFrame); then the pose's
  // turn and size about its anchor (ElementBase.anchorX).
  BoxFrame(element.rotation, element.base.skewX, element.base.skewY)
      .applyTo(canvas, bounds.center);
  if (outer.rotate != 0 || outer.scale != 1) {
    var a = element.anchorIn(bounds);
    canvas.translate(a.dx, a.dy);
    if (outer.rotate != 0) canvas.rotate(outer.rotate * math.pi / 180);
    if (outer.scale != 1) canvas.scale(outer.scale);
    canvas.translate(-a.dx, -a.dy);
  }

  // Its moving loop's turn and size about the loop's own pivot: its move
  // and fade are in the pose already (see poseWithMotion), so whatever
  // follows the element sees them.
  if (pose.values[KeyframeChannel.loopTurn] case var turn?) {
    _applyLoopPose(
        canvas,
        bounds,
        LoopPose(
            turn: turn,
            sx: pose.values[KeyframeChannel.loopSx] ?? 1,
            sy: pose.values[KeyframeChannel.loopSy] ?? 1,
            pivot: Offset(pose.values[KeyframeChannel.loopPivotX] ?? 0.5,
                pose.values[KeyframeChannel.loopPivotY] ?? 0.5)),
        anchor: element.anchorCentred
            ? null
            : Offset(element.base.anchorX, element.base.anchorY));
  }

  // A video laid on as light or shade is composited through the same layer
  // its fade is: the blend has to be on the outermost layer, the one that
  // meets what is under the element, or it blends against nothing.
  var blend =
      element is VideoElement ? element.blend.flutter : BlendMode.srcOver;
  var layered = alpha < 0.999 || blend != BlendMode.srcOver;
  // Its looks -- the devices right of its drawing in its Chain -- as its
  // LFOs have them now: see motion_looks.dart.
  // A copy of an element reused with its own values of them.
  var looks = [
    for (var l in element.base.motion.looks)
      withOwnValues(
          motionModulated(l, element.base.motion.devices,
              frame / (frameRate <= 0 ? 1 : frameRate),
              doc: document),
          element.base.motion.instances,
          instance),
  ];
  if (layered) {
    // Grown, because a shadow, an outline or a glow reaches outside the
    // element's bounds and a layer clipped to them would cut it off.
    canvas.saveLayer(
        bounds
            .inflate(math.max(bounds.width, bounds.height) + looksReach(looks)),
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha)
          ..blendMode = blend);
  }

  var time = frame / (frameRate <= 0 ? 1 : frameRate);
  // An arrival grows, spins and flips about the anchor, where it has been
  // moved. See ElementBase.anchorX.
  var pivot = element.anchorCentred ? null : element.anchorIn(bounds);
  void arriving(ui.Canvas canvas, Rect box, ElementAnimation animation,
          Keyframe pose, void Function() what) =>
      paintArriving(canvas, box, animation, pose, what, pivot: pivot);
  void body() {
    switch (element) {
      case TextElement e:
        _paintText(canvas, bounds, e, document,
            pose: pose, frame: frame, images: images, skipItem: skipTextItem);
      case ShapeElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintShape(canvas, bounds, e, images));
      case LineElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintLine(canvas, _bowed(e, pose)));
      case ImageElement e:
        // The time its own drift and its layers' loops go by -- see
        // _imageClock.
        var was = _imageClock;
        _imageClock = (
          frame: frame,
          at: frame + betweenFrames,
          last: (document?.frames ?? (1 << 30)) - 1,
          arrived: arrivalEnd(e, frameRate),
        );
        try {
          if (_layerByLayer(e, pose) case var arrive?) {
            _paintImage(canvas, bounds, e, images, arrive: arrive);
          } else {
            arriving(canvas, bounds, e.animation, pose,
                () => _paintImage(canvas, bounds, e, images));
          }
        } finally {
          _imageClock = was;
        }
      case VectorElement e:
        if (_shapeByShape(e, pose)) {
          _paintVectorInTurn(canvas, bounds, e, pose, frame,
              (document?.frames ?? (1 << 30)) - 1);
        } else {
          arriving(canvas, bounds, e.animation, pose,
              () => paintVector(canvas, bounds, e, images));
        }
      case ChartElement e:
        // How much has arrived (all, with no animation), how much has left,
        // and how far each offset series has got.
        paintChart(canvas, bounds.deflate(bounds.shortestSide * 0.02), e,
            reveal: pose.values[KeyframeChannel.reveal] ?? 1,
            close: pose.values[KeyframeChannel.close] ?? 0,
            seriesReveal: chartSeriesReveal(e, frame, frameRate,
                poseAt: (f) =>
                    poseWithMotion(e, f, document, live: liveMotion)));
      case TableElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => paintTable(canvas, bounds, e, images: images));
      case ButtonElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintButton(canvas, bounds, e, hovered, images));
      case CounterElement e:
        // A page number on a page that has none (a cover) is not drawn.
        if (e.isPageNumber && document?.pageNumber == null) break;
        arriving(
            canvas,
            bounds,
            e.animation,
            pose,
            () => paintCounter(
                canvas,
                bounds,
                e,
                // A page number is read off the page (CounterSource.page);
                // a live counter from whatever runs it, or its start where
                // nothing does; a keyed one from its pose alone, never the
                // live callback, which would answer with its start.
                e.isPageNumber
                    ? (document?.pageNumber ?? 0).toDouble()
                    : e.live
                        ? (counterValue?.call(e) ?? e.from)
                        : (pose.values[KeyframeChannel.count] ?? e.from),
                pressed: counterPressed?.call(e) ?? -1,
                running: counterRunning?.call(e)));
      case SheetElement e:
        arriving(canvas, bounds, const ElementAnimation(), pose,
            () => paintSheetElement(canvas, bounds, e, document, frame));
      case AudioElement e:
        arriving(
            canvas,
            bounds,
            e.animation,
            pose,
            () => paintAudio(
                canvas, bounds, e, audioState?.call(e) ?? AudioState.idle(e),
                images: images));
      case VideoElement e:
        arriving(
            canvas,
            bounds,
            e.animation,
            pose,
            () => paintEdgeMasked(
                canvas,
                bounds,
                e.edges,
                () => _paintVideo(canvas, bounds, e,
                    videoShow?.call(e) ?? VideoShow.idle(e), images)));
      case BackgroundElement e:
        paintEdgeMasked(
            canvas,
            bounds,
            e.mask,
            () => _paintBackgroundElement(canvas, bounds, e, time,
                frameRate.toDouble(), images, backgrounds,
                loopFrames:
                    document == null ? null : parallaxLoopFrames(document)));
      case PathElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintPath(canvas, bounds, e, editing));
      case TeamElement e:
        paintTeam(canvas, bounds, e, frame, document: document, images: images);
      case StageElement e:
        paintStage(canvas, bounds, e, frame, images: images);
      case SpriteElement e:
        paintSprite(canvas, bounds, e, frame,
            frameRate: frameRate,
            images: images,
            editing: editing,
            // Turned the way its clips move it, not only its keyframes --
            // played live from its slots, on their clock: a frame before is
            // a frame's time before.
            dxAt: e.faceTravel &&
                    e.base.motion.clips
                        .any((c) => c.keys.containsKey(MotionProp.x)) &&
                    document != null
                ? switch (liveMotion) {
                    var live? when live.of(e.id) != null => (f) =>
                        poseWithMotion(e, frame, document,
                                live: liveShifted(
                                    live, (f - frame) / math.max(1, frameRate)))
                            .dx,
                    _ => (f) =>
                        poseWithMotion(e, f, document, live: liveMotion).dx,
                  }
                : null);
      case TileMapElement e:
        // Its figures are drawn among the things stood on it, by their
        // feet, rather than where they come in the canvas's order.
        paintTileMap(canvas, bounds, e, frame,
            frameRate: frameRate,
            frames: document?.frames ?? 0,
            images: images,
            editing: editing,
            figures: document == null
                ? null
                : (id) {
                    var f = document.elementById(id);
                    if (f is! SpriteElement || !f.visible) return null;
                    // Where it stands as its clips -- live ones too -- have
                    // it, and drawn as everything else is: figures on a map
                    // are drawn only here.
                    var dy = !movesAtAll(f)
                        ? f.track?.at(frame).dy ?? 0
                        : poseWithMotion(f, frame, document, live: liveMotion)
                            .dy;
                    return (
                      f.bounds.bottom + dy,
                      () => paintElement(canvas, f, frame,
                          frameRate: frameRate,
                          images: images,
                          editing: editing,
                          document: document,
                          counterValue: counterValue,
                          liveMotion: liveMotion,
                          counterPressed: counterPressed,
                          counterRunning: counterRunning,
                          audioState: audioState,
                          videoShow: videoShow)
                    );
                  });
      case Character3dElement e:
        arriving(
            canvas,
            bounds,
            e.animation,
            pose,
            () => paintCharacter3d(canvas, bounds, e, frame,
                frameRate: frameRate, editing: editing, images: images));
      case Object3dElement e:
        paintObject3d(canvas, bounds, e, images,
            plays: document == null
                ? const []
                : modelPlaysAt(e, frame, document, live: liveMotion),
            editing: editing);
      default:
        break;
    }
  }

  // A loop that draws -- light swept through it, its outline run round, a
  // ripple -- draws it itself; anything else, it is simply drawn.
  var looping = wholeLoopOf(element);
  var phase = looping == null || !looping.on || looping.preset.moves
      ? null
      : looping.phaseAt(frame,
          arrived: arrivalEnd(element, frameRate),
          last: (document?.frames ?? (1 << 30)) - 1);
  void drawn() {
    if (looping != null && phase != null) {
      paintLoopEffect(canvas, bounds, looping, phase.$1, phase.$2,
          element.id.hashCode, _loopOutline(element, bounds, frame), body);
    } else {
      body();
    }
  }

  if (looks.isEmpty) {
    drawn();
  } else {
    // How fast it moves, for a Blur's Motion blur: only asked for one.
    var velocity = Offset.zero;
    if (document != null &&
        looks.any(
            (d) => d.kind == MotionDeviceKind.blur && d.value("motion") > 0)) {
      var before = poseWithMotion(element, frame - 1, document,
          live: liveMotion, instance: instance);
      var rate = math.max(1, frameRate).toDouble();
      velocity = Offset(pose.dx - before.dx, pose.dy - before.dy) * rate;
    }
    // Drawn onto whatever the looks hand it -- a recording, laid twice --
    // by pointing this element's canvas there for the while.
    var onto = canvas;
    void drawnOn(ui.Canvas on) {
      canvas = on;
      try {
        drawn();
      } finally {
        canvas = onto;
      }
    }

    paintWithLooks(canvas, bounds, looks, drawnOn,
        turn: element.rotation + pose.rotate,
        scale: pose.scale,
        velocity: velocity);
  }

  if (layered) canvas.restore();
  canvas.restore();
}

// --------------------------------------------------------------------------

void _paintText(
    ui.Canvas canvas, Rect bounds, TextElement e, CanvasDocument? doc,
    {Keyframe pose = Keyframe.rest,
    int frame = 0,
    CanvasImageSource? images,
    String? skipItem}) {
  _paintTextBody(canvas, bounds, e, doc,
      pose: pose, frame: frame, images: images);
  // The extra pieces of writing, over the paragraph in the same box. Out here
  // because the body returns from half a dozen places. Not on a line, which
  // gives them no box.
  if (e.items.isEmpty || _curveFor(e, doc, frame) != null) return;
  var (animation, reveal) = _arrival(e, pose);
  paintTextItems(canvas, bounds, e,
      animation: animation, reveal: reveal, images: images, skip: skipItem);
}

void _paintTextBody(
    ui.Canvas canvas, Rect bounds, TextElement e, CanvasDocument? doc,
    {Keyframe pose = Keyframe.rest, int frame = 0, CanvasImageSource? images}) {
  // Text on a curve has no box of its own to fill or frame.
  var curve = _curveFor(e, doc, frame);
  if (curve != null) {
    // The pose may slide the words along the line (KeyframeChannel.slide):
    // an absolute position, not an offset.
    var on = e.curve!;
    var slide = pose.values[KeyframeChannel.slide];
    // The words still arrive, a letter at a time in each letter's own turned
    // frame. See paintTextOnPath.
    var (curveAnimation, curveReveal) = _arrival(e, pose);
    paintTextOnPath(canvas, e.displayText, e.textSpec, curve,
        slide == null ? on : on.copyWith(offset: slide),
        animation: curveAnimation,
        reveal: curveReveal,
        parts: e.drawnParts,
        timings: _partTimings(e, frame, pose),
        asOne: (pose.values[KeyframeChannel.close] ?? 0) > 0,
        images: images);
    return;
  }

  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) {
    if (!_waitingToArrive(e, pose, e.drawnParts)) {
      paintBox(canvas, bounds, e.box, images);
    }
    return;
  }

  // Given a slot, the element's own words are a block in the box like any
  // piece, so they stack with the pieces. See TextElement.slot.
  inner = textBodyRect(e, bounds) ?? inner;
  if (inner.width <= 0 || inner.height <= 0) {
    if (!_waitingToArrive(e, pose, e.drawnParts)) {
      paintBox(canvas, bounds, e.box, images);
    }
    return;
  }

  var spec = drawnTextSpec(e, bounds);

  // A box may be one of a chain sharing one text, and draws its own share
  // of it. See flowFor.
  var flow = flowFor(e, doc, inner, spec, frame: frame, images: images);
  var words = flow.text;
  // The styled runs for *these* words, counted from this box's first word.
  // See TextFlow.parts.
  var drawn = e.drawnPartsWith(flow.parts);

  // How much has arrived and how much has left: the same two channels a
  // chart uses. See TextAnimation.
  var (animation, reveal) = _arrival(e, pose);
  var timings = _partTimings(e, frame, pose);

  // On the way out the paragraph goes as one: a part has a moment of its own
  // arriving, and there is no second leaving animation for it to have.
  var leaving = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  // Nothing yet, its box included: a slab or a bubble stood empty, waiting
  // for its words, from the start of the scene (found building Ken's
  // privacy video, 2026-11-11). See _waitingToArrive.
  if (_waitingToArrive(e, pose, drawn)) return;
  paintBox(canvas, bounds, e.box, images);

  // Set line by line round whatever is in the way, where asked for. See
  // text_wrap.dart.
  var blocked = wrapObstacles(e, doc, frame, inner, images: images);
  if (e.wrap.on &&
      blocked.isNotEmpty &&
      wrapFits(words, spec, inner, blocked, e.wrap)) {
    // The marks and the arrival apply as a block: set a line at a time,
    // there are no pieces for a per-letter motion to move. The outline and
    // the fill apply as everywhere else (outlineSpecFor, paintThroughText).
    var wrapped = layoutWrapped(words, spec, inner, blocked, e.wrap,
        parts: drawn,
        outlineSpec: outlineSpecFor(spec,
            parts: drawn, animation: animation, reveal: reveal));
    var frameOf = animation.on && (reveal < 1 || animation.keeps)
        ? applyMotionSpec(
            canvas, inner, animation.spec, animation.progressAt(reveal, 0, 1),
            from: animation.spec.from)
        : const MotionFrame(1, 0, false);
    if (frameOf.alpha > 0) {
      if (frameOf.alpha < 1) {
        canvas.saveLayer(inner.inflate(inner.height),
            Paint()..color = Color.fromRGBO(0, 0, 0, frameOf.alpha));
      }
      // The stroke drawn onto the words, where that is the preset: the
      // motion leaves the opacity alone (applyMotion), so it is done here.
      var p = animation.progressAt(reveal, 0, 1);
      var stroke = animation.on &&
          animation.preset.motion == TextMotion.strokeOn &&
          reveal < 1;
      var written = stroke ? p : null;
      var fillAlpha =
          stroke && animation.draw.start == TextDrawStart.fadeText ? p : null;
      if (!spec.fill.on) {
        paintWrapped(canvas, wrapped, spec,
            written: written, fillAlpha: fillAlpha);
      } else {
        paintWrapped(canvas, wrapped, spec,
            phase: TextDrawPhase.behind, written: written);
        paintThroughText(
            canvas,
            inner,
            spec.fill,
            images,
            () => paintWrapped(canvas, wrapped, spec,
                phase: TextDrawPhase.letters,
                written: written,
                fillAlpha: fillAlpha));
      }
      if (frameOf.alpha < 1) canvas.restore();
    }
    for (var r = 0; r < frameOf.depth; r++) {
      canvas.restore();
    }
    return;
  }

  if (e.columns.isSingle) {
    // Clipped to its box at rest, so words that do not fit are hidden (and
    // can run on into another box, see flowFor) -- but not while arriving,
    // since many presets bring the words in from outside the box.
    var arriving = animation.on && (reveal < 1 || animation.keeps);
    paintTextInBox(canvas, words, spec, inner,
        clip: !arriving && !partsAnimate(drawn),
        animation: animation,
        reveal: reveal,
        parts: drawn,
        timings: timings,
        asOne: leaving,
        images: images);
    return;
  }
  // The pieces are worked out once for the whole paragraph and drawn column
  // by column, so a stagger runs on from one column into the next. Whether
  // column tops are tidied is the chain's choice: see TextFlow.tidyStart.
  paintTextInColumns(canvas, words, spec, inner,
      e.columns.copyWith(noBlankStart: flow.tidyStart),
      animation: animation,
      reveal: reveal,
      parts: drawn,
      timings: timings,
      asOne: leaving,
      images: images);
}

/// _waitingToArrive is whether [e] has an arrival still to come on this
/// frame, and so shows nothing yet -- unless the animation is a mark drawn
/// on words that are already there, such as an underline under a finished
/// sentence, or one of its [parts] arrives on its own account, in which
/// case it has a moment of its own and this frame may be it.
bool _waitingToArrive(TextElement e, Keyframe pose, List<TextPart> parts) {
  var (animation, reveal) = _arrival(e, pose);
  return animation.on &&
      reveal <= 0 &&
      !(animation.keeps && animation.draw.start == TextDrawStart.showText) &&
      !partsAnimate(parts);
}

/// _arrival is the animation a text element is playing on this frame, and how
/// far through it is.
///
/// The two channels a chart uses, read the same way; text in a box and text
/// on a line both ask here. See TextAnimation.
(TextAnimation, double) _arrival(TextElement e, Keyframe pose) {
  var animation = e.animation;
  var reveal = pose.values[KeyframeChannel.reveal] ?? 1;
  var close = pose.values[KeyframeChannel.close] ?? 0;
  if (animation.closes && close > 0) {
    return (animation.leaving, 1 - close.clamp(0.0, 1.0));
  }
  return (animation, reveal);
}

/// _arrivalFrames is the stretch [e]'s arrival plays over -- the clip
/// playing it (see revealsIn) -- which its words, layers and shapes are
/// timed against.
(int?, int?) _arrivalFrames(CanvasElement e, Keyframe pose) {
  if (pose.values[revealFrom] case var a?) {
    return (a.round(), (pose.values[revealTo] ?? a).round());
  }
  return (null, null);
}

/// _partTimings is where each of [e]'s parts has got to on [frame].
///
/// Measured from the element's own arrival (_arrivalFrames), so a part's
/// offset moves with it. Everything is simply there while the element is
/// leaving: the paragraph goes as one.
List<PartTiming> _partTimings(TextElement e, int frame, Keyframe pose) {
  // Against drawnParts, which includes the element's own marks, so the list
  // lines up with the one the painter uses.
  var parts = e.drawnParts;
  if (parts.isEmpty) return const [];
  var closing = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  if (closing) return [for (var _ in parts) PartTiming.there];

  var (from, to) = _arrivalFrames(e, pose);
  // No arrival stretch to measure against: every part follows the element.
  if (from == null || to == null || to <= from) {
    var reveal = pose.values[KeyframeChannel.reveal] ?? 1;
    return [
      for (var part in parts)
        PartTiming(
            part.animation.on ? reveal : 1, part.animation.marks ? reveal : 1),
    ];
  }
  return [
    for (var part in parts)
      timingOf(part, frame: frame, from: from, span: to - from),
  ];
}

/// drawnTextSpec is the type a text element is actually drawn in.
///
/// With Fit to box on, the size comes from the room rather than the setting.
/// The editor asks too, so the letters do not change size when a fitted
/// paragraph is clicked into.
///
/// [bounds] is the element's rectangle, padding included; the fit is measured
/// inside it.
TextSpec drawnTextSpec(TextElement e, Rect bounds) {
  var spec = e.textSpec;
  if (!e.autoSize) return spec;

  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return spec;

  // Against one column's width, the width a line is given, but all the
  // columns' room, which is where the text goes.
  var column = Size(e.columns.columnWidth(inner.width), inner.height);
  return spec.copyWith(
      fontSize:
          fitFontSize(e.displayText, spec, column, columns: e.columns.count));
}

/// lineWithPose is [e] with its track's bow on [frame], so the hit test
/// catches the curve where it is drawn. Clips' bows are not included.
LineElement lineWithPose(LineElement e, int frame) =>
    _bowed(e, e.poseAt(frame));

/// _bowed applies a keyed curvature to a line. See KeyframeChannel.bow.
LineElement _bowed(LineElement e, Keyframe pose) {
  var bow = pose.values[KeyframeChannel.bow];
  return bow == null ? e : e.copyWith(curvature: bow);
}

/// visualBoundsOf is where [element] is actually drawn.
///
/// Different from its moved rectangle for something on a stage (where the
/// camera puts it), a bowed line or a path (which bulge outside their box),
/// and text riding a line (drawn wherever the line is). The selection
/// outline, the handles and the on-canvas text editor all use this.
Rect visualBoundsOf(CanvasElement element, CanvasDocument? doc, int frame,
    {LiveMotion? live}) {
  // With its clips' moves on it: see movedBoundsAt.
  Rect moved() => doc == null
      ? element.boundsAt(frame)
      : element.movedBoundsAt(frame, doc, live: live);
  // Where the stage's camera puts something standing on it.
  if (element.base.spot != null && doc != null) {
    if (stagedIn(doc, element, frame) case var at?) return at.box;
  }
  if (element is TextElement) {
    var curve = _curveFor(element, doc, frame);
    if (curve != null) {
      var glyphs = placeTextOnPath(
          element.displayText, element.textSpec, curve, element.curve!);
      var box = textOnPathBounds(glyphs, element.curve!);
      // No letters placed (empty, or slid off the end): the line itself.
      return box ?? _boundsOfPoints(curve) ?? moved();
    }
    return moved();
  }

  if (element is LineElement || element is PathElement) {
    var host = element is LineElement ? lineWithPose(element, frame) : element;
    var curve = curveOfElement(host);
    var box = _boundsOfPoints(curve);
    if (box == null) return moved();
    // Room for the stroke, centred on the path, and for the ends: an
    // arrowhead reaches 3.5 stroke widths past the end point.
    var width = element is LineElement
        ? element.strokeWidth
        : (element as PathElement).strokeWidth;
    var ends = element is LineElement
        ? math.max(element.startEnd.reach, element.endEnd.reach) *
            element.endSize
        : math.max(
                (element as PathElement).startEnd.reach, element.endEnd.reach) *
            element.endSize;
    return box.inflate(math.max(width, 1) * math.max(ends, 1.5));
  }

  return moved();
}

Rect? _boundsOfPoints(List<Offset>? points) {
  if (points == null || points.isEmpty) return null;
  var left = points.first.dx, right = points.first.dx;
  var top = points.first.dy, bottom = points.first.dy;
  for (var p in points) {
    left = math.min(left, p.dx);
    right = math.max(right, p.dx);
    top = math.min(top, p.dy);
    bottom = math.max(bottom, p.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// hasOwnGeometry is whether an element's size and angle are its own to change.
///
/// False for text riding a line, whose place, size and turn are the line's.
bool hasOwnGeometry(CanvasElement element, CanvasDocument? doc, int frame) =>
    !(element is TextElement && _curveFor(element, doc, frame) != null) &&
    // Nor for something standing on a stage: the camera sizes and turns it.
    !(element.base.spot != null &&
        doc != null &&
        stagedIn(doc, element, frame) != null);

/// curveOfElement is [element]'s own line as a polyline in document space, or
/// null when it has none.
///
/// The stage hit-tests against it, since a curved line or path bows outside
/// its own box.
List<Offset>? curveOfElement(CanvasElement element) {
  var points = _curvePoints(element);
  if (points == null) return null;
  return _rotatedWith(element, points);
}

/// curveUnderText is the line a text element is riding, in document space.
List<Offset>? curveUnderText(TextElement e, CanvasDocument? doc, int frame) =>
    _curveFor(e, doc, frame);

/// _rotatedWith turns [points] about [host]'s centre, the way the painter
/// turns the host itself.
List<Offset> _rotatedWith(CanvasElement host, List<Offset> points) {
  if (host.rotation == 0) return points;
  var centre = host.center;
  var cos = math.cos(host.rotationRadians);
  var sin = math.sin(host.rotationRadians);
  return [
    for (var p in points)
      Offset(
        centre.dx + (p.dx - centre.dx) * cos - (p.dy - centre.dy) * sin,
        centre.dy + (p.dx - centre.dx) * sin + (p.dy - centre.dy) * cos,
      ),
  ];
}

/// _curveFor is the line a text element is riding, as a list of points in
/// document space, or null when it is an ordinary paragraph.
///
/// Found by id, so moving or reshaping the line carries its text with it. A
/// deleted line is simply not found, and the text falls back to its box.
/// pathPointsOf is [host] -- a path or a line -- as points along it on the
/// page, turned as it is drawn; null for anything else. For Follow path.
List<Offset>? pathPointsOf(CanvasElement host, int frame) {
  var drawn = host is LineElement ? _bowed(host, host.poseAt(frame)) : host;
  var points = _curvePoints(drawn);
  return points == null ? null : _rotatedWith(drawn, points);
}

List<Offset>? _curveFor(TextElement e, CanvasDocument? doc, int frame) {
  var on = e.curve;
  if (on == null || doc == null) return null;
  var host = doc.elementById(on.elementId);
  // The host's animated bow counts (its track only; clips' bows do not).
  if (host is LineElement) host = _bowed(host, host.poseAt(frame));
  var points = _curvePoints(host);
  if (points == null) return null;

  // Turned with the line about its centre, as the painter turns it.
  return _rotatedWith(host!, points);
}

/// _curvePoints is the host's line as a polyline in its own unrotated
/// coordinates.
List<Offset>? _curvePoints(CanvasElement? host) {
  if (host is PathElement && host.nodes.length >= 2) {
    return [
      for (var i = 0; i < host.segments; i++)
        for (var step = 0; step <= _curveSamplesPerSegment; step++)
          if (i == 0 || step > 0)
            host.pointOnSegment(i, step / _curveSamplesPerSegment),
    ];
  }
  if (host is LineElement) {
    // A bowed line is a quadratic between its ends, so it is sampled, with
    // the painter's own control point (lineControlPoint).
    var a = host.start, b = host.end;
    if (host.curvature == 0) return [a, b];
    var control = lineControlPoint(host);
    return [
      for (var i = 0; i <= _curveSamplesPerSegment * 2; i++)
        _quadratic(a, control, b, i / (_curveSamplesPerSegment * 2)),
    ];
  }
  return null;
}

/// _curveSamplesPerSegment is how finely a curve is walked when text is placed
/// along it: enough to keep letters on the line at any export size.
const int _curveSamplesPerSegment = 16;

Offset _quadratic(Offset a, Offset control, Offset b, double t) {
  var u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
  );
}

void _paintShape(ui.Canvas canvas, Rect bounds, ShapeElement e,
    [CanvasImageSource? images]) {
  var rect = bounds;
  if (e.shape.isRegular) {
    var side = rect.shortestSide;
    rect = Rect.fromCenter(center: rect.center, width: side, height: side);
  }

  var path = shapePath(e.shape, rect,
      points: e.points,
      inner: e.innerRatio,
      cornerRadius: e.cornerRadius,
      corners: e.corners,
      bubble: e.bubble);

  // Across the shape's own bounds, so a gradient runs the length of the
  // shape rather than of the rectangle handed down.
  var area = path.getBounds();
  // A fade of its own counts as a fill: the flat colour may have been turned
  // all the way down on the way to setting one. See PaintSpec.shows.
  var filled = PaintSpec(e.fill, gradient: e.fillFade);
  if (filled.shows) {
    canvas.drawPath(path, filled.into(Paint(), area));
  }
  // A picture or a pattern inside it, cut to the outline. See TextFill.
  if (e.painted.on) {
    paintThroughText(
        canvas, area, e.painted, images, () => canvas.drawPath(path, Paint()));
  }
  var stroked = PaintSpec(e.strokeColor, gradient: e.strokeFade);
  if (e.strokeWidth > 0 && stroked.shows) {
    canvas.drawPath(
        path,
        stroked.into(
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = e.strokeWidth
              ..strokeJoin = StrokeJoin.round,
            area));
  }

  if (e.text.isNotEmpty) {
    paintTextInBox(canvas, e.textSpec.textCase.apply(e.text), e.textSpec,
        labelRoom(e, rect));
  }
}

/// labelRoom is where a shape's label is set: the padding it has been given,
/// or the shape's own sensible inset where it has been given none.
///
/// The fractions are crude on purpose (the alternative is solving for the
/// inscribed rectangle of an arbitrary path) and keep a label in a circle or
/// a triangle off the edge. Padding, when set, replaces them.
Rect labelRoom(ShapeElement e, Rect rect) {
  // A bubble's words go in its body: the box less whatever the tail took.
  if (e.shape == ShapeKind.speechBubble) {
    var body = bubbleBodyRect(rect, e.bubble);
    if (e.padded) return e.pad.inner(body);
    var margin = e.bubble.body == BubbleBody.burst ? 0.22 : 0.1;
    return body.deflate(body.shortestSide * margin);
  }
  if (e.padded) return e.pad.inner(rect);

  var inset = switch (e.shape) {
    ShapeKind.circle || ShapeKind.ellipse => 0.15,
    ShapeKind.triangle => 0.24,
    ShapeKind.diamond || ShapeKind.star => 0.26,
    ShapeKind.pentagon || ShapeKind.hexagon => 0.16,
    _ => 0.06,
  };
  var box = rect.deflate(rect.shortestSide * inset);
  // A triangle's room is not centred in its box: the top is a point.
  if (e.shape == ShapeKind.triangle) {
    box = box.translate(0, rect.height * 0.1);
  }
  return box;
}

/// lineControlPoint is the control point of the quadratic a bowed line is
/// drawn as, in the element's own unrotated coordinates.
///
/// The painter, the hit test and text on the line all use it, so they agree.
/// Pushed out perpendicular to the chord, so the bow is symmetrical whichever
/// way round the line runs.
Offset lineControlPoint(LineElement e) {
  var a = e.start, b = e.end;
  var mid = (a + b) / 2;
  var d = b - a;
  var length = d.distance;
  if (length == 0 || e.curvature == 0) return mid;
  return mid + Offset(-d.dy / length, d.dx / length) * (length * e.curvature);
}

void _paintLine(ui.Canvas canvas, LineElement e) {
  var control = lineControlPoint(e);
  var path = Path()..moveTo(e.start.dx, e.start.dy);
  if (e.curvature == 0) {
    path.lineTo(e.end.dx, e.end.dy);
  } else {
    path.quadraticBezierTo(control.dx, control.dy, e.end.dx, e.end.dy);
  }

  // Across the whole line, so a fade runs end to end whichever way it points.
  var paint = PaintSpec(e.color, gradient: e.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.strokeWidth
        ..strokeCap = e.cap.flutter,
      path.getBounds());

  // A path metric gives the exact position and direction at each end, so the
  // decorations sit square on a bowed line.
  var metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return;
  var metric = metrics.first;
  var length = metric.length;

  var startTangent = metric.getTangentForOffset(0);
  var endTangent = metric.getTangentForOffset(length);
  if (startTangent == null || endTangent == null) return;

  // A decoration is drawn on the line's end, so the stroke is cut back to its
  // base, or a thick stroke pokes out of the sides of the barb.
  var trimStart = _trimFor(e.startEnd, e.strokeWidth, e.endSize);
  var trimEnd = _trimFor(e.endEnd, e.strokeWidth, e.endSize);
  var from = math.min(trimStart, length * 0.45);
  var to = math.max(length - trimEnd, from + 0.01);
  var stroke = metric.extractPath(from, to);

  canvas.drawPath(
      e.dash > 0 ? dashPath(stroke, e.dash, e.dash * 0.8) : stroke, paint);

  // From the vector, never Tangent.angle: that is *minus* atan2(dy, dx), y
  // up, and flips every decoration on a diagonal line in canvas space.
  double heading(ui.Tangent t) => math.atan2(t.vector.dy, t.vector.dx);

  // The start decoration points back out of the line, so its heading is the
  // curve's reversed.
  _paintLineEnd(canvas, e.startEnd, startTangent.position,
      heading(startTangent) + math.pi, e);
  _paintLineEnd(canvas, e.endEnd, endTangent.position, heading(endTangent), e);
}

/// _trimFor is how far back from a line's end its decoration begins.
///
/// Every decoration, not only the pointed ones, so the stroke does not show
/// through a hollow one. See LineEnd.cover.
double _trimFor(LineEnd end, double strokeWidth, double endSize) =>
    end.cover * strokeWidth * endSize;

/// _paintLineEnd draws one decoration, pointing along [angle].
///
/// [angle] is where the line is going at that end, taken from the path metric,
/// so every one of these sits square on the curve however hard it is bent.
void _paintLineEnd(
    ui.Canvas canvas, LineEnd end, Offset at, double angle, LineElement e) {
  if (end == LineEnd.none) return;
  var w = e.strokeWidth * e.endSize;
  var fill = Paint()
    ..style = PaintingStyle.fill
    ..color = e.color;
  var stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = e.strokeWidth
    ..strokeJoin = StrokeJoin.miter
    ..color = e.color;

  // The line's own two directions at this end: along it, and across it.
  var along = Offset(math.cos(angle), math.sin(angle));
  var across = Offset(-along.dy, along.dx);

  switch (end) {
    case LineEnd.none:
      return;
    case LineEnd.arrow:
      arrowHead(canvas, at, angle, w * 3.5, fill);
    case LineEnd.hollowArrow:
      arrowHead(canvas, at, angle, w * 3.5, stroke, filled: false);
    case LineEnd.openArrow:
      // A filled chevron rather than two strokes: thickest at the tip and
      // pointed at each outer end, as an open arrow is drawn by hand.
      var size = w * 4.2;
      var back = angle + math.pi;
      var b1 = at.translate(math.cos(back - arrowSpread) * size,
          math.sin(back - arrowSpread) * size);
      var b2 = at.translate(math.cos(back + arrowSpread) * size,
          math.sin(back + arrowSpread) * size);
      // The notch behind the tip gives it its thickness, as a fraction of
      // the barb so the proportions hold at any end size.
      var notch = at - along * (size * 0.58);
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo(b1.dx, b1.dy)
          ..lineTo(notch.dx, notch.dy)
          ..lineTo(b2.dx, b2.dy)
          ..close(),
        fill,
      );
    case LineEnd.diamond:
    case LineEnd.hollowDiamond:
      // Centred on the line's end, like the circle and the square.
      var long = w * 1.7;
      var wide = w * 1.0;
      canvas.drawPath(
        Path()
          ..moveTo(at.dx + along.dx * long, at.dy + along.dy * long)
          ..lineTo(at.dx + across.dx * wide, at.dy + across.dy * wide)
          ..lineTo(at.dx - along.dx * long, at.dy - along.dy * long)
          ..lineTo(at.dx - across.dx * wide, at.dy - across.dy * wide)
          ..close(),
        end == LineEnd.diamond ? fill : stroke,
      );
    case LineEnd.circle:
      canvas.drawCircle(at, w * 1.2, fill);
    case LineEnd.hollowCircle:
      canvas.drawCircle(at, w * 1.2, stroke);
    case LineEnd.square:
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w * 2.2, height: w * 2.2),
          fill);
      canvas.restore();
    case LineEnd.bar:
      // A tick across the line, which is what a measurement wants at each end.
      canvas.drawLine(at - across * (w * 1.6), at + across * (w * 1.6), stroke);
  }
}

/// _LayerArrive draws one layer of a picture coming in a layer at a time:
/// [draw] as [layer] is at this frame of its own arrival, about [box].
typedef _LayerArrive = void Function(
    ImageLayer layer, Rect box, void Function() draw);

/// _layerByLayer is how [e]'s layers come in one after another, where they
/// do -- its arrival animation played for each layer in its turn, about the
/// layer's own box -- or null where the picture comes in as one, or is on
/// its way out. See layerTimes.
_LayerArrive? _layerByLayer(ImageElement e, Keyframe pose) {
  if (!e.layered || !e.animation.on) return null;
  if ((pose.values[KeyframeChannel.close] ?? 0) > 0) return null;
  var stack = e.stack;
  if (!layersSequenced(stack)) return null;
  var (from, to) = _arrivalFrames(e, pose);
  if (from == null || to == null || to <= from) return null;
  var span = to - from;
  var times = layerTimes(stack, span);
  var through = pose.values[KeyframeChannel.reveal] ?? 1;
  var turns = {
    for (var (i, l) in stack.indexed) l.id: times[i],
  };
  return (layer, box, draw) {
    var (start, length) = turns[layer.id] ?? (0.0, span.toDouble());
    var reveal = ((through * span - start) / length).clamp(0.0, 1.0);
    // Nothing yet: not even a frame of it before its turn.
    if (reveal <= 0 && e.animation.preset != ElementAnimationPreset.none) {
      return;
    }
    paintArriving(
        _arrivingCanvas!,
        box,
        e.animation,
        pose.copyWith(values: {...pose.values, KeyframeChannel.reveal: reveal}),
        draw);
  };
}

/// _arrivingCanvas is the canvas a picture's layers are being drawn on
/// while they arrive in turn -- set round the drawing, so the arrival above
/// draws on whatever canvas the layer is going to.
ui.Canvas? _arrivingCanvas;

void _paintImage(
    ui.Canvas canvas, Rect bounds, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive}) {
  // The border goes over the picture, which would otherwise cover it
  // wherever it runs to its box's edge.
  paintBoxFill(canvas, bounds, e.box, images);
  // A drift on the picture as a whole -- see ElementLoop.driftAt -- zooms
  // or pans everything in it as one: a picture alone inside its frame, as a
  // documentary's camera does; a picture of layers past its frame, where it
  // does not cut them.
  var drift = _drifting(e.animation.loop);
  var steady = adjustSteadily;
  if (drift != null) {
    var inner = e.box.inner(bounds);
    canvas.save();
    if (!e.layered || e.clip) canvas.clipRect(inner);
    _applyDrift(canvas, inner, e.animation.loop, drift);
    // Its adjustments moved with it as pixels, not filtered where they
    // land: see adjustSteadily.
    adjustSteadily = true;
  }
  try {
    _paintImageInside(canvas, bounds, e, images, arrive: arrive);
  } finally {
    adjustSteadily = steady;
  }
  if (drift != null) canvas.restore();
  paintBoxBorder(canvas, bounds, e.box);
}

/// _imageClock is the frame a picture is being drawn on, its scene's last
/// frame and where its arrival ends -- set round the drawing of an image
/// element, for the drift and the loops of what is in it. [at] is the frame
/// with how far past it the playhead has got: see betweenFrames.
({int frame, double at, int last, int? arrived})? _imageClock;

/// betweenFrames is how far past the frame being drawn the editor's playhead
/// has really got, nought to one, while it plays -- and nought otherwise,
/// and always in an export, whose frames are whole.
///
/// Drifts are drawn at the playhead's exact time, so a slow zoom or pan does
/// not step at the frame rate on a faster screen; the stage redraws on every
/// refresh while one plays. Set round the stage's drawing, the way
/// RasterCache.drafting is.
double betweenFrames = 0;

/// _drifting is how far through [loop]'s drift the picture being drawn is,
/// or null for a loop that is not a drift, or no picture being drawn.
double? _drifting(ElementLoop loop) {
  var clock = _imageClock;
  if (clock == null || !loop.preset.drifts) return null;
  return loop.driftAt(clock.at, arrived: clock.arrived, last: clock.last);
}

/// _applyDrift sets [canvas] to draw [box] [t] of the way through [loop]'s
/// drift: closer about its middle, or held closer and panned across. The
/// box itself grows and moves -- what is in it is not cut to it.
void _applyDrift(ui.Canvas canvas, Rect box, ElementLoop loop, double t) {
  var a = (driftPerStrength * loop.strength).clamp(0.0, 1.0);
  double s;
  var shift = Offset.zero;
  switch (loop.preset) {
    case LoopPreset.driftIn:
      s = 1 + a * t;
    case LoopPreset.driftOut:
      s = 1 + a * (1 - t);
    // The camera moves left: the picture slides right under it.
    case LoopPreset.driftLeft:
      s = 1 + a;
      shift = Offset((0.5 - t) * a * box.width, 0);
    case LoopPreset.driftRight:
      s = 1 + a;
      shift = Offset((t - 0.5) * -a * box.width, 0);
    case LoopPreset.driftUp:
      s = 1 + a;
      shift = Offset(0, (0.5 - t) * a * box.height);
    case LoopPreset.driftDown:
      s = 1 + a;
      shift = Offset(0, (t - 0.5) * -a * box.height);
    default:
      return;
  }
  var c = box.center;
  canvas.translate(c.dx + shift.dx, c.dy + shift.dy);
  canvas.scale(s);
  canvas.translate(-c.dx, -c.dy);
}

/// _layerLooped draws a layer of a picture -- [draw] -- by its own loop:
/// drifted, moved, or lit, about [box], its place.
void _layerLooped(ui.Canvas canvas, ImageLayer layer, Rect box, int seed,
    void Function() draw) {
  var clock = _imageClock, loop = layer.loop;
  if (clock == null || !loop.on || !layer.visible) return draw();
  if (loop.preset.drifts) {
    var t = _drifting(loop);
    if (t == null) return draw();
    canvas.save();
    _applyDrift(canvas, box, loop, t);
    var steady = adjustSteadily;
    adjustSteadily = true;
    try {
      draw();
    } finally {
      adjustSteadily = steady;
    }
    canvas.restore();
    return;
  }
  if (loop.preset.moves) {
    var swing =
        loop.poseAt(clock.frame, arrived: clock.arrived, last: clock.last);
    if (swing == null) return draw();
    canvas.save();
    _applyLoopPose(canvas, box, swing);
    var faded = swing.opacity < 0.999;
    if (faded) {
      canvas.saveLayer(box.inflate(box.longestSide),
          Paint()..color = Color.fromRGBO(0, 0, 0, swing.opacity));
    }
    draw();
    if (faded) canvas.restore();
    canvas.restore();
    return;
  }
  var phase =
      loop.phaseAt(clock.frame, arrived: clock.arrived, last: clock.last);
  if (phase == null) return draw();
  paintLoopEffect(
      canvas, box, loop, phase.$1, phase.$2, seed, Path()..addRect(box), draw);
}

/// _throughAdjustments draws [draw] through [adjustments] -- the nearest
/// first -- each at its own strength, blend and mask: the adjustments over
/// a layer worked into that layer, for a picture whose layers move on their
/// own, so each comes in or loops already adjusted.
void _throughAdjustments(ui.Canvas canvas, Rect inner, Rect room,
    List<ImageLayer> adjustments, void Function(ui.Canvas) draw) {
  void through(ui.Canvas c, int k) {
    if (k < 0) return draw(c);
    var adj = adjustments[k];
    var covers =
        adj.opacity >= 1 && adj.blend == LayerBlend.normal && !adj.mask.active;
    if (covers) {
      c.saveLayer(room, _over(adj));
      paintAdjustedLive(c, room, adj.adjust, (a) => through(a, k - 1));
      _frameMasked(c, inner, adj);
      c.restore();
      return;
    }
    // What is under it is drawn once and shown twice -- as it is, and
    // adjusted -- or each adjustment would double the drawing beneath it.
    var recorder = ui.PictureRecorder();
    through(ui.Canvas(recorder), k - 1);
    var below = recorder.endRecording();
    c.drawPicture(below);
    c.saveLayer(room, _over(adj));
    paintAdjustedLive(c, room, adj.adjust, (a) => a.drawPicture(below));
    _frameMasked(c, inner, adj);
    c.restore();
    below.dispose();
  }

  through(canvas, adjustments.length - 1);
}

void _paintImageInside(
    ui.Canvas canvas, Rect bounds, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive}) {
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;

  if (e.layered) {
    _paintLayered(canvas, inner, e, images, arrive: arrive);
    return;
  }

  var image = e.hasImage ? images?.resolve(e.assetId, e.removal) : null;
  if (image == null) {
    _imagePlaceholder(canvas, inner, e);
    return;
  }

  canvas.save();
  // A frame cuts the picture to a shape -- the same shapes an element can be
  // drawn as, so anything added there is a frame here for nothing.
  if (e.frame != null) {
    canvas
        .clipPath(shapePath(e.frame!, inner, bubble: const SpeechBubbleSpec()));
  } else if (e.box.isRounded) {
    // The picture's corners follow the box's, pulled in by the padding so a
    // rounded frame stays concentric with the border drawn round it.
    canvas.clipRRect(e.box.insetRounded(inner));
  } else {
    // Room for an outside outline: a picture that fills its box (Cover, the
    // default) has its edge exactly on the clip. The picture itself stays
    // inside the box.
    canvas.clipRect(inner.inflate(_outlineRoom(e)));
  }
  _paintPicture(canvas, inner, e, image, images);
  canvas.restore();
}

/// _paintPicture draws [image] into [inner] with everything [e] does to it --
/// its fit, crop and framing, its colours, overlay and outline -- and nothing
/// of the frame round it. The base picture and every picture layer are drawn
/// by it.
void _paintPicture(ui.Canvas canvas, Rect inner, ImageElement e, ui.Image image,
    CanvasImageSource? images) {
  if (e.warp.active) {
    _paintWarped(canvas, inner, e, image, images);
    return;
  }
  _paintPictureFlat(canvas, inner, e, image, images);
}

/// _paintWarped draws the picture [e] -- as _paintPictureFlat would, mask,
/// retouching, outline and all -- bent by its warp. The picture is drawn
/// once into pixels, kept while nothing about how it looks changes, and
/// drawn through the warp's mesh on every frame: moving a point of the grid
/// is one mesh drawn, not the picture drawn again.
void _paintWarped(ui.Canvas canvas, Rect inner, ImageElement e, ui.Image image,
    CanvasImageSource? images) {
  var room = inner.inflate(_outlineRoom(e));
  if (room.isEmpty) return;
  var most = math.min(4096 / math.max(room.width, room.height),
      math.sqrt(16e6 / (room.width * room.height)));
  if (RasterCache.drafting) {
    most = math.min(
        most, RasterCache.draftSide / math.max(room.width, room.height));
  }
  var scale = math.max(0.05, math.min(deviceScaleOf(canvas), most));
  var w = math.max(1, (room.width * scale).ceil());
  var h = math.max(1, (room.height * scale).ceil());
  // Kept against everything the picture is drawn from but the warp; and
  // not kept while anything it draws is still loading.
  var key = "warp|${identityHashCode(image)}|${room.size}";
  var from = [room.size, image, ...pictureLookFrom(e)];
  var keep = !(images?.loading ?? false);
  var flat = keep ? RasterCache.instance.sized(key, from, w, h) : null;
  var kept = flat != null;
  if (flat == null) {
    var recorder = ui.PictureRecorder();
    var c = ui.Canvas(recorder);
    c.scale(w / room.width, h / room.height);
    c.translate(-room.left, -room.top);
    _paintPictureFlat(c, inner, e, image, images);
    var picture = recorder.endRecording();
    flat = picture.toImageSync(w, h);
    picture.dispose();
    if (keep) {
      RasterCache.instance.putSized(key, from, flat);
      kept = true;
    }
  }
  var k = flat.width / room.width;
  canvas.drawVertices(
      warpMesh(e.warp, inner, room, k),
      BlendMode.srcOver,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..shader = ui.ImageShader(
            flat,
            TileMode.decal,
            TileMode.decal,
            Float64List.fromList(
                const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
            filterQuality: FilterQuality.medium));
  if (!kept) flat.dispose();
}

void _paintPictureFlat(ui.Canvas canvas, Rect inner, ImageElement e,
    ui.Image image, CanvasImageSource? images) {
  var overlaid = e.blend != OverlayBlend.none && e.overlay.a > 0;

  // The mask, where there is one, over everything the picture draws -- its
  // outline traces what the mask leaves, and an overlay tints only that. A
  // subject still loading is drawn without: the picture whole for a moment
  // rather than gone.
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var maskSubject = e.mask.subject.isEmpty
      ? null
      : images?.resolve(e.mask.subject, const BackgroundRemoval());
  var masking =
      e.mask.active && (e.mask.subject.isEmpty || maskSubject != null);
  void masked(void Function() draw) {
    if (!masking) {
      draw();
      return;
    }
    // The picture never reaches past its frame, so neither need the layer.
    canvas.saveLayer(inner, Paint());
    draw();
    paintMaskLayer(canvas, e.mask, size, maskSubject,
        placeImage(size, inner, e.fit, crop: e.crop, framing: e.framing));
    canvas.restore();
  }

  void shape(Color colour) =>
      masked(() => _drawImage(canvas, image, inner, e.fit,
          crop: e.crop, framing: e.framing, silhouette: colour));

  // Behind the picture, so the band only shows where the picture is not.
  if (e.outline.on &&
      (e.outline.style == OutlineStyle.outside ||
          e.outline.style == OutlineStyle.glow)) {
    _paintOutline(canvas, shape, inner, e, outward: true);
  }

  // The picture with the background's colour taken out of its edge, where
  // its mask asks for that and it has been worked out (edge_cleaning.dart).
  // Only its colours: its shape is the picture's.
  var shown = masking ? cleanedFor(images, e, image) : image;
  masked(() {
    // With an overlay, the picture goes into a layer of its own, so the
    // overlay's blend mode blends with the picture alone and not with every
    // element painted before it.
    if (overlaid) canvas.saveLayer(inner, Paint());

    _drawImage(canvas, shown, inner, e.fit,
        retouch: e.retouch,
        tint: e.tint,
        saturation: e.saturation,
        brightness: e.brightness,
        crop: e.crop,
        framing: e.framing,
        filter: e.filter);

    if (overlaid) {
      canvas.drawRect(
          inner,
          Paint()
            ..color = e.overlay
            ..blendMode = e.blend.flutter);

      // Then cut back to the picture's own shape: a blend mode leaves its
      // colour on transparent pixels, which would fill a removed background.
      _drawImage(canvas, image, inner, e.fit,
          crop: e.crop, framing: e.framing, maskOnly: true);
      canvas.restore();
    }
  });

  // Over the picture and after the overlay, so the overlay does not tint an
  // inside band.
  if (e.outline.on &&
      (e.outline.style == OutlineStyle.inside ||
          e.outline.style == OutlineStyle.centred)) {
    _paintOutline(canvas, shape, inner, e, outward: false);
  }
}

/// _paintLayered draws a picture made of layers into its frame [inner].
///
/// The frame's shape clips the whole composite, as it clips a single
/// picture, and the composite is drawn in a layer of its own, so a layer's
/// blend mode blends with the layers below it and not with the canvas.
void _paintLayered(
    ui.Canvas canvas, Rect inner, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive}) {
  var stack = e.stack;
  // Nothing in it at all is an empty picture, and says so. An adjustment
  // alone has nothing to adjust.
  var anything = stack.any((l) => switch (l.kind) {
        LayerKind.base => e.hasImage,
        LayerKind.picture => l.look?.hasImage ?? false,
        LayerKind.fill || LayerKind.texture => true,
        LayerKind.paint => l.strokes.isNotEmpty,
        LayerKind.adjustment => false,
      });
  if (!anything) {
    _imagePlaceholder(canvas, inner, e);
    return;
  }

  canvas.save();
  Rect room;
  if (!e.clip) {
    // Nothing cut: what runs past the frame (a layer dragged out, a stroke
    // not yet taken in, a shadow) is drawn where it is. See
    // ImageElement.grownToFit.
    room = inner
        .expandToInclude(contentRectOf(e, inner) ?? inner)
        .inflate(math.max(_outlineRoom(e), _effectsReach(e, inner)));
  } else {
    if (e.frame != null) {
      canvas.clipPath(
          shapePath(e.frame!, inner, bubble: const SpeechBubbleSpec()));
    } else if (e.box.isRounded) {
      canvas.clipRRect(e.box.insetRounded(inner));
    } else {
      canvas.clipRect(inner.inflate(_outlineRoom(e)));
    }
    room = inner.inflate(_outlineRoom(e));
  }
  canvas.saveLayer(room, Paint());
  var watched = _Watched(images);
  _paintStack(canvas, inner, e, stack, watched, room, arrive);
  canvas.restore();
  canvas.restore();
}

Paint _over(ImageLayer layer) => Paint()
  ..blendMode = layer.blend.flutter
  ..color = Color.fromRGBO(0, 0, 0, layer.opacity);

/// _record is whatever [draw] draws, as a picture.
ui.Picture _record(void Function(ui.Canvas) draw) {
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  return recorder.endRecording();
}

/// _paintStack draws [stack], back to front.
///
/// An adjustment layer changes everything under it, so the topmost one is
/// found first and the stack is split there: what is under it is drawn --
/// as itself, and again through the adjustment, blended over at the
/// adjustment's own opacity and blend -- and what is over it after. The part
/// under may hold adjustments of its own, and is drawn the same way.
void _paintStack(ui.Canvas canvas, Rect inner, ImageElement e,
    List<ImageLayer> stack, _Watched images, Rect room, _LayerArrive? arrive) {
  // Layers arriving in turn or looping on their own: each is drawn with the
  // adjustments over it worked in, so it arrives or moves already adjusted.
  if (arrive != null || stack.any((l) => l.visible && l.loop.on)) {
    _paintGroups(canvas, inner, e, stack, images, room, arrive,
        adjustEach: true);
    return;
  }
  var at = -1;
  for (var i = stack.length - 1; i >= 0; i--) {
    var l = stack[i];
    // A clipped adjustment changes only the layer it is clipped to, and is
    // drawn with it -- see _paintGroups. A paint layer retouching what is
    // under it works on everything under it, as an adjustment does.
    if (l.visible &&
        (l.kind == LayerKind.adjustment && !(l.clip && i > 0) ||
            l.retouchesUnder)) {
      at = i;
      break;
    }
  }
  if (at < 0) {
    _paintGroups(canvas, inner, e, stack, images, room, arrive);
    return;
  }
  var misses = images.misses;
  var below = _record((c) =>
      _paintStack(c, inner, e, stack.sublist(0, at), images, room, arrive));
  // What is under it changes frame by frame while layers arrive, so the
  // adjusted picture is not kept then.
  var complete = images.misses == misses && arrive == null;
  // What is under is drawn as it is only where it can show through the
  // adjusted picture (part strength, blended, masked or arriving); an
  // adjustment that wholly covers it skips that.
  var top = stack[at];
  var covers = !top.retouchesUnder &&
      top.opacity >= 1 &&
      top.blend == LayerBlend.normal &&
      !top.mask.active &&
      arrive == null &&
      AdjustShader.ready.value;
  if (!covers) canvas.drawPicture(below);
  if (stack[at].retouchesUnder) {
    // The clone, the heal, the dodge, worked on everything under the layer
    // as one picture -- across the whole frame, not one picture's pixels --
    // and the layer's own paint over that.
    var layer = stack[at];
    canvas.saveLayer(room, _over(layer));
    _arriving(canvas, arrive, layer, room, () {
      paintRetouchUnder(canvas, inner, below, layer.strokes,
          key: complete ? "${e.id}|${layer.id}|under" : null,
          from: layersFrom(e, stack.sublist(0, at)));
      paintPaintLayer(canvas, inner, layer.strokes, "${e.id}|${layer.id}");
      _frameMasked(canvas, inner, layer);
    });
    canvas.restore();
    below.dispose();
    _paintGroups(canvas, inner, e, stack.sublist(at + 1), images, room, arrive);
    return;
  }
  var adjustment = stack[at];
  canvas.saveLayer(room, _over(adjustment));
  _arriving(canvas, arrive, adjustment, room, () {
    paintAdjusted(canvas, room, adjustment.adjust, below,
        // Kept only once everything under it has loaded: kept earlier, the
        // picture that arrived late would never be adjusted.
        key: complete ? "${e.id}|${adjustment.id}|$at" : null,
        from: layersFrom(e, stack.sublist(0, at)));
    _frameMasked(canvas, inner, adjustment);
  });
  canvas.restore();
  below.dispose();
  _paintGroups(canvas, inner, e, stack.sublist(at + 1), images, room, arrive);
}

/// _arriving draws [draw] for [layer] as its turn to arrive says, where the
/// picture's layers arrive in turn -- or just draws it.
void _arriving(ui.Canvas canvas, _LayerArrive? arrive, ImageLayer layer,
    Rect box, void Function() draw) {
  if (arrive == null) return draw();
  var was = _arrivingCanvas;
  _arrivingCanvas = canvas;
  try {
    arrive(layer, box, draw);
  } finally {
    _arrivingCanvas = was;
  }
}

/// renderUnder is what is under the layer [layerId] of [e] -- every layer
/// below it, drawn as they are drawn -- as a [w] x [h] picture of the frame:
/// what an adjustment there is working on, for its histogram. Null where
/// there is no such layer.
Future<ui.Image?> renderUnder(ImageElement e, String layerId,
    CanvasImageSource? images, int w, int h) async {
  var stack = e.stack;
  var at = stack.indexWhere((l) => l.id == layerId);
  if (at < 0) return null;
  var inner = e.box.inner(e.bounds);
  if (inner.width <= 0 || inner.height <= 0) return null;
  var picture = _record((c) {
    c.scale(w / inner.width, h / inner.height);
    c.translate(-inner.left, -inner.top);
    c.clipRect(inner);
    _paintStack(
        c, inner, e, stack.sublist(0, at), _Watched(images), inner, null);
  });
  try {
    return await picture.toImage(w, h);
  } finally {
    picture.dispose();
  }
}

/// _paintFrameMaskView is paintMaskView for a frame-masked layer: its mask
/// over the whole frame.
void _paintFrameMaskView(ui.Canvas canvas, ImageElement e, ImageLayer layer,
    {required bool overlay}) {
  canvas.save();
  var bounds = e.bounds;
  // Turned and slanted as the picture is drawn -- see BoxFrame.
  BoxFrame(e.rotation, e.base.skewX, e.base.skewY)
      .applyTo(canvas, bounds.center);
  var inner = e.box.inner(bounds);
  var size = Size(inner.width, inner.height);
  var placement = placeImage(size, inner, ImageFit.stretch);
  canvas.saveLayer(inner, Paint());
  if (overlay) {
    canvas.drawRect(inner, Paint()..color = const Color(0x88FF2020));
    if (!layer.mask.empty) {
      paintMaskLayer(canvas, layer.mask, size, null, placement,
          blend: BlendMode.dstOut);
    } else {
      canvas.drawRect(inner, Paint()..blendMode = BlendMode.clear);
    }
  } else {
    canvas.drawRect(inner, Paint()..color = const Color(0xFF000000));
    canvas.saveLayer(inner, Paint());
    canvas.drawRect(inner, Paint()..color = const Color(0xFFFFFFFF));
    if (!layer.mask.empty) {
      paintMaskLayer(canvas, layer.mask, size, null, placement);
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// _frameMasked cuts what has just been drawn of [layer] in the current
/// layer back to its frame mask -- see ImageLayer.mask -- where it has one.
void _frameMasked(ui.Canvas canvas, Rect inner, ImageLayer layer) {
  if (!layer.framed || !layer.mask.active) return;
  var size = Size(inner.width, inner.height);
  paintMaskLayer(canvas, layer.mask, size, null,
      placeImage(size, inner, ImageFit.stretch));
}

/// _layerBox is where [layer] is in a frame drawn at [inner]: a picture
/// layer's place, and the whole frame for the rest.
Rect _layerBox(Rect inner, ImageLayer layer) =>
    layer.kind == LayerKind.picture ? layerRect(inner, layer.place) : inner;

/// _paintGroups draws [stack], which holds no adjustment over everything
/// under it, a layer and the layers clipped to it at a time.
void _paintGroups(ui.Canvas canvas, Rect inner, ImageElement e,
    List<ImageLayer> stack, _Watched images, Rect room, _LayerArrive? arrive,
    {bool adjustEach = false}) {
  var i = 0;
  while (i < stack.length) {
    var layer = stack[i];
    // Worked into each layer instead, an adjustment over everything under
    // it draws nothing of its own -- see _paintStack.
    if (adjustEach &&
        layer.kind == LayerKind.adjustment &&
        !(layer.clip && i > 0)) {
      i++;
      continue;
    }
    var over = !adjustEach
        ? const <ImageLayer>[]
        : [
            for (var (k, l) in stack.indexed)
              if (k > i &&
                  l.visible &&
                  l.kind == LayerKind.adjustment &&
                  !l.clip)
                l
          ];
    // The layers clipped to this one, which go wherever it goes.
    var j = i + 1;
    while (j < stack.length && stack[j].clip) {
      j++;
    }
    var clipped = [
      for (var c in stack.sublist(i + 1, j))
        if (c.visible) c
    ];
    // A clipped layer at the very bottom has nothing to clip to, and is
    // drawn as an ordinary one.
    if (layer.visible) {
      canvas.saveLayer(room, _over(layer));
      var box = _layerBox(inner, layer);
      _arriving(canvas, arrive, layer, box, () {
        _layerLooped(canvas, layer, box, Object.hash(e.id, layer.id), () {
          void dressed(ui.Canvas c) {
            _paintDressed(c, inner, e, layer, images, room);
            _frameMasked(c, inner, layer);
          }

          if (over.isEmpty) {
            dressed(canvas);
          } else {
            _throughAdjustments(canvas, inner, room, over, dressed);
          }
        });
      });
      for (var c in clipped) {
        canvas.saveLayer(room, _over(c));
        if (c.kind == LayerKind.adjustment) {
          // Clipped, an adjustment changes the one layer under it.
          var misses = images.misses;
          var base = _record((r) => _paintLayer(r, inner, e, layer, images));
          _arriving(canvas, arrive, c, room, () {
            paintAdjusted(canvas, room, c.adjust, base,
                key: images.misses == misses && arrive == null
                    ? "${e.id}|${c.id}|clip"
                    : null,
                from: layersFrom(e, [layer]));
            _frameMasked(canvas, inner, c);
          });
          base.dispose();
        } else {
          _arriving(canvas, arrive, c, _layerBox(inner, c), () {
            _paintDressed(canvas, inner, e, c, images, room);
            _frameMasked(canvas, inner, c);
          });
        }
        // Cut back to the layer it is clipped to: its own shape, drawn again
        // as a mask over the clipped layer before it is blended down.
        canvas.saveLayer(room, Paint()..blendMode = BlendMode.dstIn);
        _paintLayer(canvas, inner, e, layer, images);
        _frameMasked(canvas, inner, layer);
        canvas.restore();
        canvas.restore();
      }
      canvas.restore();
    }
    i = j;
  }
}

/// _paintDressed draws [layer] with its effects -- shadows, glows, blurs --
/// or, with none switched on, as it is.
void _paintDressed(ui.Canvas canvas, Rect inner, ImageElement e,
    ImageLayer layer, _Watched images, Rect room) {
  if (!layer.effects.any((f) => f.on)) {
    _paintLayer(canvas, inner, e, layer, images);
    return;
  }
  var misses = images.misses;
  var content = _record((r) => _paintLayer(r, inner, e, layer, images));
  paintWithEffects(canvas, room, math.min(inner.width, inner.height) / 1000,
      layer.effects, content,
      key: images.misses == misses ? "${e.id}|${layer.id}|fx" : null,
      from: layersFrom(e, [layer]),
      lightening: layer.blend.lightens ? layer.blend.flutter : null);
  content.dispose();
}

/// _Watched is a picture source that counts what it could not hand over
/// yet, so an adjustment drawn over a picture still loading is not kept.
class _Watched extends CanvasImageSource implements CleansEdges {
  final CanvasImageSource? source;
  int misses = 0;
  _Watched(this.source);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) {
    var image = source?.resolve(assetId, removal);
    if (image == null) {
      misses++;
      CanvasPerf.count("miss $assetId");
    }
    return image;
  }

  @override
  CanvasVector? resolveVector(String assetId) => source?.resolveVector(assetId);

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      source?.resolveOutline(assetId, removal);

  @override
  bool get loading => source?.loading ?? false;

  @override
  ui.Image? cleaned(ImageElement look, ui.Image picture) {
    var s = source;
    if (s is CleansEdges) {
      var image = (s as CleansEdges).cleaned(look, picture);
      if (image == null) {
        misses++;
        CanvasPerf.count("miss cleaned ${look.assetId}");
      }
      return image;
    }
    return null;
  }
}

/// paintMaskView draws the mask of the layer [layerId] of [e] where the
/// picture is, in document units, for seeing it while it is worked on: what
/// it hides in translucent red over everything ([overlay]), or the mask alone
/// in black and white. See MaskView.
void paintMaskView(
    ui.Canvas canvas, ImageElement e, String layerId, CanvasImageSource? images,
    {required bool overlay}) {
  var layer = e.layerById(layerId);
  if (layer == null) return;
  if (layer.framed) {
    _paintFrameMaskView(canvas, e, layer, overlay: overlay);
    return;
  }
  var look = switch (layer.kind) {
    LayerKind.base => e,
    LayerKind.picture => layer.look,
    LayerKind.fill ||
    LayerKind.adjustment ||
    LayerKind.texture ||
    LayerKind.paint =>
      null,
  };
  if (look == null || !look.hasImage) return;
  var image = images?.resolve(look.assetId, look.removal);
  if (image == null) return;
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var subject = look.mask.subject.isEmpty
      ? null
      : images?.resolve(look.mask.subject, const BackgroundRemoval());

  canvas.save();
  var bounds = e.bounds;
  // Turned and slanted as the picture is drawn -- see BoxFrame.
  BoxFrame(e.rotation, e.base.skewX, e.base.skewY)
      .applyTo(canvas, bounds.center);
  var inner = e.box.inner(bounds);
  var rect = layerRect(inner, layer.place);
  if (!layer.isBase || layer.flipX || layer.flipY) {
    canvas.translate(rect.center.dx, rect.center.dy);
    if (layer.turn != 0) canvas.rotate(layer.turn * math.pi / 180);
    if (layer.flipX || layer.flipY) {
      canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
    }
    canvas.translate(-rect.center.dx, -rect.center.dy);
  }
  var placement =
      placeImage(size, rect, look.fit, crop: look.crop, framing: look.framing);
  var dst = placement.dst;
  canvas.saveLayer(dst, Paint());
  if (overlay) {
    canvas.drawRect(dst, Paint()..color = const Color(0x88FF2020));
    if (!look.mask.empty) {
      paintMaskLayer(canvas, look.mask, size, subject, placement,
          blend: BlendMode.dstOut);
    } else {
      canvas.drawRect(dst, Paint()..blendMode = BlendMode.clear);
    }
  } else {
    canvas.drawRect(dst, Paint()..color = const Color(0xFF000000));
    canvas.saveLayer(dst, Paint());
    canvas.drawRect(dst, Paint()..color = const Color(0xFFFFFFFF));
    if (!look.mask.empty) {
      paintMaskLayer(canvas, look.mask, size, subject, placement);
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// _paintLayer draws one layer of [e] at full strength; its blend and
/// opacity are the caller's.
void _paintLayer(ui.Canvas canvas, Rect inner, ImageElement e, ImageLayer layer,
    CanvasImageSource? images) {
  switch (layer.kind) {
    case LayerKind.base:
      var image = e.hasImage ? images?.resolve(e.assetId, e.removal) : null;
      // In its own place: the frame, until it is moved or sized on its own
      // -- mirrored there, where it is flipped.
      if (image != null) {
        var rect = layerRect(inner, layer.place);
        var flipped = layer.flipX || layer.flipY;
        if (flipped) {
          canvas.save();
          canvas.translate(rect.center.dx, rect.center.dy);
          canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
          canvas.translate(-rect.center.dx, -rect.center.dy);
        }
        _paintPicture(canvas, rect, e, image, images);
        if (flipped) canvas.restore();
      }
    case LayerKind.fill:
      canvas.drawRect(inner, layer.fill.into(Paint(), inner));
    case LayerKind.adjustment:
      // Drawn by what is under it -- see _paintStack.
      break;
    case LayerKind.texture:
      paintTexture(canvas, inner, layer.texture);
    case LayerKind.paint:
      paintPaintLayer(canvas, inner, layer.strokes, "${e.id}|${layer.id}");
    case LayerKind.picture:
      var look = layer.look;
      if (look == null || !look.hasImage) return;
      var image = images?.resolve(look.assetId, look.removal);
      if (image == null) return;
      var rect = layerRect(inner, layer.place);
      if (rect.width <= 0 || rect.height <= 0) return;
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      if (layer.turn != 0) canvas.rotate(layer.turn * math.pi / 180);
      if (layer.flipX || layer.flipY) {
        canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
      }
      canvas.translate(-rect.center.dx, -rect.center.dy);
      if (look.frame != null) {
        canvas.clipPath(
            shapePath(look.frame!, rect, bubble: const SpeechBubbleSpec()));
      }
      _paintPicture(canvas, rect, look, image, images);
      canvas.restore();
  }
}

/// _frameId is what the frame being drawn is called while the image painter
/// draws it -- see _paintVideo.
const _frameId = "\u0000video-frame";

/// _OneFrame is the picture store with one more picture in it: the video's
/// frame, under [_frameId]. Everything else -- a picture painted into the
/// box, say -- is asked of the store as usual.
class _OneFrame extends CanvasImageSource {
  final ui.Image frame;
  final CanvasImageSource? store;
  _OneFrame(this.frame, this.store);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId == _frameId ? frame : store?.resolve(assetId, removal);

  @override
  CanvasVector? resolveVector(String assetId) =>
      assetId == _frameId ? null : store?.resolveVector(assetId);
}

/// _paintVideo draws a video: its frame, or its poster while it has none,
/// keyed and then drawn with its look exactly as a picture is, and its
/// controls over the top.
void _paintVideo(ui.Canvas canvas, Rect bounds, VideoElement e, VideoShow show,
    CanvasImageSource? images,
    {bool placeholder = true}) {
  if (show.hidden) return;
  var poster = e.isLink ? e.look.assetId : show.poster;
  var frame = show.frame ??
      (poster.isEmpty
          ? null
          : images?.resolve(poster, const BackgroundRemoval()));

  // A background video with nothing to show yet shows nothing, and the
  // pattern under it is the page in the meantime.
  if (frame == null && !placeholder) return;
  if (frame == null) {
    paintBox(canvas, bounds, e.look.box, images);
    var inner = e.look.box.inner(bounds);
    if (inner.width > 0 && inner.height > 0) {
      // A ground of its own while there is nothing to show, so an empty video
      // reads as a screen rather than as a hole in the canvas.
      canvas.drawRect(inner, Paint()..color = const Color(0xFF101418));
      paintTextInBox(
          canvas,
          e.isLink
              ? VideoHost.of(e.link).label
              : e.clip.isEmpty
                  ? "No video yet"
                  : "Loading…",
          TextSpec(
              fontSize: math.max(9, inner.shortestSide * 0.08),
              weight: 500,
              color: const Color(0xAAFFFFFF)),
          inner,
          clip: true);
    }
    if (show.controls) {
      paintVideoControls(canvas, e, videoParts(e, bounds), show);
    }
    return;
  }

  // Keyed before the look: the look grades what is left of the picture, the
  // same as it grades a photograph with its background taken out.
  if (!e.isLink && e.key.on) frame = VideoKey.keyed(frame, e.key);

  var fading = show.opacity < 1;
  if (fading) {
    canvas.saveLayer(bounds.inflate(bounds.shortestSide),
        Paint()..color = Color.fromRGBO(0, 0, 0, show.opacity.clamp(0.0, 1.0)));
  }
  _paintImage(
      canvas,
      bounds,
      e.picture.copyWith(assetId: _frameId, removal: const BackgroundRemoval()),
      _OneFrame(frame, images));
  if (fading) canvas.restore();

  if (show.controls) {
    paintVideoControls(canvas, e, videoParts(e, bounds), show);
  }
}

/// _effectsReach is how far past what they are on [e]'s layers' effects
/// reach -- a shadow thrown and blurred, a glow, a smear -- in a frame at
/// [inner].
double _effectsReach(ImageElement e, Rect inner) {
  var unit = math.min(inner.width, inner.height) / 1000;
  var most = 0.0;
  for (var l in e.stack) {
    for (var f in l.effects) {
      if (!f.on) continue;
      var reach = 0.0;
      for (var name in const ["distance", "blur", "size", "spread", "amount"]) {
        if (f.kind.params.any((p) => p.key == name)) {
          // Blurs are a sigma of half the figure, and fade out by about
          // three of those.
          reach += f.value(name) * (name == "blur" || name == "size" ? 1.5 : 1);
        }
      }
      // A zoom's amount is how much bigger its last copy is: of the whole
      // frame, not of a thousandth of it.
      if (f.kind == EffectKind.zoomBlur) reach = f.value("amount") * 1000;
      most = math.max(most, reach);
    }
  }
  return most * unit;
}

/// _outlineRoom is how far outside its box a picture's outline may reach.
double _outlineRoom(ImageElement e) {
  if (!e.outline.on) return 0;
  switch (e.outline.style) {
    case OutlineStyle.inside:
      return 0;
    case OutlineStyle.centred:
      return e.outline.width / 2 * 1.3;
    case OutlineStyle.glow:
      // Blur reaches well past the spread that fed it.
      return e.outline.width * 2;
    case OutlineStyle.outside:
      // The fade happens within the width, but a blur's tail runs a little
      // past where it is meant to stop.
      return e.outline.width * 1.3;
  }
}

/// _paintOutline traces the edge of the picture's alpha channel.
///
/// Done with the compositor (a dilate on a layer) rather than as a bitmap, so
/// it is drawn at the canvas's resolution, not the picture's, and is not
/// recomputed when a colour changes.
///
/// An outward band takes two passes: one blurred pass fades at both edges,
/// and the inner edge shows through a cut-out's soft rim. So the fade is one
/// pass and a solid band is laid over its inside, leaving only the outer
/// edge.
void _paintOutline(
    ui.Canvas canvas, void Function(Color) shape, Rect inner, ImageElement e,
    {required bool outward}) {
  var outline = e.outline;
  // Centred splits the band between the two sides.
  var width =
      outline.style == OutlineStyle.centred ? outline.width / 2 : outline.width;
  if (width <= 0) return;

  void silhouette(Color colour, ui.ImageFilter? filter) {
    canvas.saveLayer(
        inner, filter == null ? Paint() : (Paint()..imageFilter = filter));
    shape(colour);
    canvas.restore();
  }

  if (outward) {
    // A glow is all fade and no band.
    var glow = outline.style == OutlineStyle.glow;
    // Otherwise never all fade, however far the feather is pushed: the band
    // must meet the subject at full strength.
    var solid = glow ? 0.0 : width * (1 - outline.feather * 0.8);
    var fade = width - solid;

    if (glow || fade > 0) {
      // Dilate to the middle of the fade and blur across it, so the feather
      // does not make the outline wider than asked.
      var spread = glow ? width * 0.35 : solid + fade / 2;
      var sigma = glow ? width * (0.25 + outline.feather * 0.4) : fade / 4;
      silhouette(
          outline.color,
          ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
            inner: ui.ImageFilter.dilate(radiusX: spread, radiusY: spread),
          ));
    }

    // The solid part, over the inside of the fade. Drawn even with no width
    // (a glow) to back the subject's soft rim with the outline's colour, or
    // the rim shows as a second, dimmer line.
    silhouette(
        outline.color,
        solid > 0
            ? ui.ImageFilter.dilate(radiusX: solid, radiusY: solid)
            : null);
    return;
  }

  // A band that touches the picture is drawn over it as one ring, not as two
  // halves, whose join over the soft rim would show as a gap. The ring is the
  // silhouette grown by `grow` with a copy shrunk by `shrink` punched out.
  var grow = outline.style == OutlineStyle.centred ? width : 0.0;
  var shrink = width;
  var blur = width * outline.feather / 2;

  canvas.saveLayer(inner, Paint());

  // Feathering fades the edge facing away from the subject (outwards for a
  // centred band, inwards for an inside one); the traced edge stays crisp.
  var fill = <ui.ImageFilter>[
    if (grow > 0) ui.ImageFilter.dilate(radiusX: grow, radiusY: grow),
    if (grow > 0 && blur > 0)
      ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
  ];
  silhouette(
      outline.color,
      fill.isEmpty
          ? null
          : fill.length == 1
              ? fill.first
              : ui.ImageFilter.compose(outer: fill.last, inner: fill.first));

  var punch = ui.ImageFilter.erode(radiusX: shrink, radiusY: shrink);
  canvas.saveLayer(
      inner,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..imageFilter = grow == 0 && blur > 0
            ? ui.ImageFilter.compose(
                outer: ui.ImageFilter.blur(
                    sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
                inner: punch)
            : punch);
  shape(const Color(0xFF000000));
  canvas.restore();
  canvas.restore();
}

void _imagePlaceholder(ui.Canvas canvas, Rect rect, ImageElement e) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(e.box.borderRadius)),
    Paint()..color = const Color(0x1AFFFFFF),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(e.box.borderRadius)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF),
  );
  paintTextInBox(
      canvas,
      e.hasImage ? "Loading…" : "No picture yet",
      TextSpec(
          fontSize: math.max(9, rect.shortestSide * 0.09),
          weight: 500,
          color: const Color(0xAAFFFFFF)),
      rect,
      clip: true);
}

/// _drawImage covers or contains [image] in [rect], with the colour
/// adjustments applied through a matrix rather than by touching the pixels.
void _drawImage(ui.Canvas canvas, ui.Image image, Rect rect, ImageFit fit,
    {Color tint = const Color(0x00000000),
    double saturation = 1,
    double brightness = 1,
    ImageCrop crop = const ImageCrop(),
    ImageFraming framing = const ImageFraming(),
    ImageFilterPreset filter = ImageFilterPreset.none,

    /// retouch is cloning, healing and the like done to the picture, drawn
    /// over it in its own pixels -- see brush_painter.dart.
    List<StrokeMark> retouch = const [],

    /// maskOnly draws the picture's *shape*, composited with dstIn, so what
    /// is already in the layer survives only where the picture has pixels.
    /// _paintPictureFlat uses it to keep an overlay off a removed background.
    bool maskOnly = false,

    /// silhouette draws the picture's shape filled with one colour, keeping
    /// its alpha and throwing its own colours away. What an outline traces.
    Color? silhouette}) {
  // Shared with the retouching brush, which maps it backwards: see
  // ImagePlacement.toImage.
  var placement = placeImage(
      Size(image.width.toDouble(), image.height.toDouble()), rect, fit,
      crop: crop, framing: framing);
  var src = placement.src;
  var dst = placement.dst;

  var paint = Paint()..filterQuality = FilterQuality.high;

  if (maskOnly) {
    canvas.drawImageRect(image, src, dst, paint..blendMode = BlendMode.dstIn);
    return;
  }

  // srcIn keeps the source's alpha and takes the colour from the filter, so a
  // half-transparent strand of hair gives a half-transparent piece of outline.
  if (silhouette != null) {
    canvas.drawImageRect(image, src, dst,
        paint..colorFilter = ColorFilter.mode(silhouette, BlendMode.srcIn));
    return;
  }

  // One colour matrix for the preset and both sliders, not a layer each.
  var matrix = combineMatrices(
      presetMatrix(filter), colorMatrix(saturation, brightness));
  if (matrix != null) paint.colorFilter = ColorFilter.matrix(matrix);
  canvas.drawImageRect(image, src, dst, paint);

  if (retouch.isNotEmpty) {
    var m = pictureToPlacement(placement);
    canvas.save();
    canvas.clipRect(dst);
    canvas.translate(m.dx, m.dy);
    canvas.scale(m.sx, m.sy);
    paintRetouchKept(
        canvas,
        image,
        Size(image.width.toDouble(), image.height.toDouble()),
        retouch,
        paint.colorFilter);
    canvas.restore();
  }

  if (tint.a > 0) {
    canvas.drawRect(
        dst,
        Paint()
          ..color = tint
          ..blendMode = BlendMode.modulate);
  }
}

void _paintButton(ui.Canvas canvas, Rect bounds, ButtonElement e, bool hovered,
    CanvasImageSource? images) {
  var box = e.box;
  if (hovered && e.hoverFill.a > 0) box = box.copyWith(fill: e.hoverFill);
  paintBox(canvas, bounds, box, images);

  var spec = e.textSpec;
  if (hovered && e.hoverTextColor.a > 0) {
    spec = spec.copyWith(color: e.hoverTextColor);
  }
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;
  paintTextInBox(canvas, spec.textCase.apply(e.label), spec, inner, clip: true);
}

void _paintBackgroundElement(
    ui.Canvas canvas,
    Rect bounds,
    BackgroundElement e,
    double time,
    double frameRate,
    CanvasImageSource? images,
    ProceduralCache? backgrounds,
    {int? loopFrames}) {
  if (e.cornerRadius > 0) {
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(e.cornerRadius)));
  }
  if (e.isStage || e.isParallax) {
    var frame = (time * frameRate).round();
    if (e.isStage) {
      paintStage(canvas, bounds, e.staged, frame, images: images);
    } else {
      paintParallax(canvas, bounds, e.parallaxed, frame,
          frameRate: frameRate, images: images, loopFrames: loopFrames);
    }
    if (e.cornerRadius > 0) canvas.restore();
    return;
  }
  // From the editor's cache where it can be, as the canvas's own background
  // is. During a gesture (the panel being resized) the last one made is
  // stretched, and a new one is made when the gesture ends.
  var ready = backgrounds?.imageFor(
          e.spec, bounds.size, time, images, !RasterCache.drafting, false) ??
      (RasterCache.drafting ? backgrounds?.latestFor(e.spec) : null);
  if (ready != null) {
    canvas.drawImageRect(
        ready,
        Rect.fromLTWH(0, 0, ready.width.toDouble(), ready.height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.low);
  } else {
    paintProcedural(canvas, bounds, e.spec,
        time: time, frameRate: frameRate, images: images);
  }
  if (e.cornerRadius > 0) canvas.restore();
}

/// withoutGuides is [doc] with its guide paths -- and the master's -- not
/// drawn, for the stage while the canvas plays or a game runs: they are
/// scaffolding, and a bat's flight drawn across a game is not part of it.
/// Hidden rather than taken out: what follows one (a Follow path, words on
/// a curve) still finds it by its id -- taken out, Ember Vale's bat stood
/// still. [doc] itself where it has none.
CanvasDocument withoutGuides(CanvasDocument doc) {
  bool guide(CanvasElement e) => e is PathElement && e.guide && e.visible;
  List<CanvasElement> hidden(List<CanvasElement> list) => [
        for (var e in list)
          if (guide(e)) e.withBase(visible: false) else e,
      ];
  var here = doc.elements.any(guide);
  var master = doc.master;
  var there = master != null && master.elements.any(guide);
  if (!here && !there) return doc;
  var out = here ? doc.copyWith(elements: hidden(doc.elements)) : doc;
  if (there && !doc.editingMaster) {
    out = out.withMaster(master.copyWith(elements: hidden(master.elements)));
  }
  return out;
}

/// _paintPath draws a bezier curve.
///
/// A guide path (PathElement.guide) is scaffolding: drawn only while
/// [editing], and left out of anything published.
void _paintPath(ui.Canvas canvas, Rect bounds, PathElement e, bool editing) {
  if (e.nodes.length < 2) return;
  if (e.guide && !editing) return;

  var path = ui.Path();
  Offset at(PathNode n) => Offset(
      bounds.left + n.x * bounds.width, bounds.top + n.y * bounds.height);
  Offset handle(PathNode n, double dx, double dy) => Offset(
      bounds.left + (n.x + dx) * bounds.width,
      bounds.top + (n.y + dy) * bounds.height);

  path.moveTo(at(e.nodes.first).dx, at(e.nodes.first).dy);
  for (var i = 0; i < e.segments; i++) {
    var a = e.nodes[i % e.nodes.length];
    var b = e.nodes[(i + 1) % e.nodes.length];
    var c1 = a.outDx == 0 && a.outDy == 0 ? at(a) : handle(a, a.outDx, a.outDy);
    var c2 = b.inDx == 0 && b.inDy == 0 ? at(b) : handle(b, b.inDx, b.inDy);
    var end = at(b);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  }
  if (e.closed) path.close();

  // Across the whole path, so a fade runs along its length.
  var paint = PaintSpec(e.color, gradient: e.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.strokeWidth
        ..strokeCap = e.cap.flutter,
      path.getBounds());

  canvas.drawPath(e.dash > 0 ? dashPath(path, e.dash, e.dash) : path, paint);

  // The arrowhead points along the last segment's own direction, not the
  // chord between the last two nodes, which can point backwards.
  if (e.endEnd != LineEnd.none && !e.closed) {
    var last = e.segments - 1;
    var tip = e.pointOnSegment(last, 1);
    var just = e.pointOnSegment(last, 0.94);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
  if (e.startEnd != LineEnd.none && !e.closed) {
    var tip = e.pointOnSegment(0, 0);
    var just = e.pointOnSegment(0, 0.06);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
}

/// _paintArrowHead draws a solid head at [tip], pointing away from [from].
void _paintArrowHead(
    ui.Canvas canvas, Offset from, Offset tip, double width, Color color) {
  var direction = tip - from;
  if (direction.distance < 0.001) return;
  var angle = math.atan2(direction.dy, direction.dx);
  var size = math.max(6.0, width * 3);
  var head = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - size * math.cos(angle - 0.4),
        tip.dy - size * math.sin(angle - 0.4))
    ..lineTo(tip.dx - size * math.cos(angle + 0.4),
        tip.dy - size * math.sin(angle + 0.4))
    ..close();
  canvas.drawPath(head, Paint()..color = color);
}

/// _ownShapes is whether any of [e]'s shapes has an animation of its own.
bool _ownShapes(VectorElement e) => vectorDrawn(e.shapes ?? const [])
    .any((d) => d.style.animation != null && d.style.owns.isNotEmpty);

/// wholeLoopOf is [element]'s loop where it loops as one -- for a drawing
/// with shapes of their own, each shape loops on its own instead, those
/// left as the drawing with the drawing's loop. See _paintVectorInTurn.
ElementLoop? wholeLoopOf(CanvasElement element) {
  if (element is VectorElement && _ownShapes(element)) return null;
  // The words' and a chart's are in animations of their own.
  if (element is TextElement) return element.animation.loop;
  if (element is ChartElement) return element.animation.loop;
  return _animationOf(element)?.loop;
}

/// _shapeByShape is whether a drawing is drawn a shape at a time rather
/// than as one: where a shape has an animation of its own -- coming in,
/// looping and leaving -- or the drawing's arrival brings its shapes in one
/// after another, and it is not on its way out. See VectorCue.
bool _shapeByShape(VectorElement e, Keyframe pose) {
  var shapes = e.shapes;
  if (shapes == null || shapes.isEmpty) return false;
  if (_ownShapes(e)) return true;
  if ((pose.values[KeyframeChannel.close] ?? 0) > 0) return false;
  return e.animation.on && sequenced(shapes) && _vectorArrival(e, pose) != null;
}

/// _vectorArrival is where a drawing's arrival starts and how many frames
/// it takes: the stretch _arrivalFrames finds.
(int, int)? _vectorArrival(VectorElement e, Keyframe pose) {
  var (from, to) = _arrivalFrames(e, pose);
  if (from == null || to == null || to <= from) return null;
  return (from, to - from);
}

/// _paintVectorInTurn draws a drawing a shape at a time: each shape, with
/// whatever is combined into it, animated as its own animation says or as
/// the drawing's does. Coming in, in its own box, where its cue puts it and
/// for its own length; looping, from when it has come in; leaving, with the
/// drawing's closing stretch. A shape left as the drawing loops and leaves
/// about the whole drawing. [last] is the scene's last frame.
void _paintVectorInTurn(ui.Canvas canvas, Rect bounds, VectorElement e,
    Keyframe pose, int frame, int last) {
  var shapes = e.shapes!;
  var arrival = _vectorArrival(e, pose);
  var times = arrival == null ? null : cueTimes(shapes, arrival.$2);
  var own = _ownShapes(e);
  var leaving = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  // How far through its arrival the drawing is, easing included: the clock
  // every shape's turn is read off.
  var through = pose.values[KeyframeChannel.reveal] ?? 1;
  for (var (i, d) in vectorDrawn(shapes).indexed) {
    var box = vectorGroupBox(bounds, e, d);
    var owns =
        d.style.animation == null ? const <ShapeAnimationPart>{} : d.style.owns;
    var animation = animatedAs(e.animation, d.style.animation, owns);
    // How far in it is, and when it is all in: with no arrival on the
    // drawing, it is there from the start.
    var reveal = 1.0;
    int? arrived;
    var loopsOwn = owns.contains(ShapeAnimationPart.looping);
    if (arrival != null && times != null) {
      var (at, span) = arrival;
      var (start, length) = times[i];
      reveal = ((through * span - start) / length).clamp(0.0, 1.0);
      arrived = loopsOwn ? (at + start + length).round() : at + span;
    }
    // A loop of its own about its own box; the drawing's, where the drawing
    // is not looping as one, about the drawing's.
    var loop = loopsOwn
        ? animation.loop
        : (own ? e.animation.loop : const ElementLoop());
    void draw() => _paintGroupLooped(canvas, bounds, loopsOwn ? box : bounds, e,
        d, i, loop, frame, arrived, last);
    if (leaving) {
      paintArriving(
          canvas,
          owns.contains(ShapeAnimationPart.leaving) ? box : bounds,
          animation,
          pose,
          draw);
      continue;
    }
    if (!animation.on) {
      // Nothing to play coming in: there from its turn.
      if (reveal > 0) draw();
      continue;
    }
    paintArriving(
        canvas,
        box,
        animation,
        pose.copyWith(values: {...pose.values, KeyframeChannel.reveal: reveal}),
        draw);
  }
}

/// _paintGroupLooped draws one shape of a drawing with [loop], about [box]
/// and along its own outline, from [arrived] -- when it has come in -- or
/// the loop's own start.
void _paintGroupLooped(
    ui.Canvas canvas,
    Rect bounds,
    Rect box,
    VectorElement e,
    VectorDrawn d,
    int index,
    ElementLoop loop,
    int frame,
    int? arrived,
    int last) {
  void plain() => paintVectorGroup(canvas, bounds, e, d);
  if (!loop.on) return plain();
  if (loop.preset.moves) {
    var swing = loop.poseAt(frame, arrived: arrived, last: last);
    if (swing == null) return plain();
    canvas.save();
    _applyLoopPose(canvas, box, swing);
    var faded = swing.opacity < 0.999;
    if (faded) {
      canvas.saveLayer(box.inflate(box.longestSide),
          Paint()..color = Color.fromRGBO(0, 0, 0, swing.opacity));
    }
    plain();
    if (faded) canvas.restore();
    canvas.restore();
    return;
  }
  var phase = loop.phaseAt(frame, arrived: arrived, last: last);
  if (phase == null) return plain();
  var p = e.placement(bounds, e.viewBox);
  var outline = d.outline.transform(Float64List.fromList([
    p.sx, 0, 0, 0, //
    0, p.sy, 0, 0, //
    0, 0, 1, 0, //
    p.dx, p.dy, 0, 1,
  ]));
  paintLoopEffect(canvas, box, loop, phase.$1, phase.$2,
      Object.hash(e.id, index), outline, plain);
}

/// _applyLoopPose moves, turns and sizes the canvas as [swing] says, for
/// something drawn in [box]: shifted by shares of it, turned and sized about
/// its pivot -- or [anchor], shares of [box], where given. Its fading is
/// the caller's.
void _applyLoopPose(ui.Canvas canvas, Rect box, LoopPose swing,
    {Offset? anchor}) {
  canvas.translate(swing.dx * box.width, swing.dy * box.height);
  if (swing.turn != 0 || swing.sx != 1 || swing.sy != 1) {
    // About the element's anchor where it has been moved; otherwise where
    // the loop itself turns -- a swing hangs from its top.
    var at = anchor ?? swing.pivot;
    var pivot =
        Offset(box.left + box.width * at.dx, box.top + box.height * at.dy);
    canvas.translate(pivot.dx, pivot.dy);
    if (swing.turn != 0) canvas.rotate(swing.turn * math.pi / 180);
    if (swing.sx != 1 || swing.sy != 1) canvas.scale(swing.sx, swing.sy);
    canvas.translate(-pivot.dx, -pivot.dy);
  }
}

/// _animationOf is [element]'s arrival, exit and loop, for the kinds that
/// have them -- see CanvasController.animates -- or null.
ElementAnimation? _animationOf(CanvasElement element) => switch (element) {
      ShapeElement e => e.animation,
      ImageElement e => e.animation,
      VectorElement e => e.animation,
      LineElement e => e.animation,
      PathElement e => e.animation,
      TableElement e => e.animation,
      CounterElement e => e.animation,
      ButtonElement e => e.animation,
      AudioElement e => e.animation,
      VideoElement e => e.animation,
      Character3dElement e => e.animation,
      _ => null,
    };

/// _loopOutline is [element]'s own outline, where it is drawn, for the loops
/// that run along it: a shape's, a drawing's shapes', a line's -- and for
/// anything else its box.
Path _loopOutline(CanvasElement element, Rect bounds, int frame) {
  switch (element) {
    case ShapeElement e:
      var rect = bounds;
      if (e.shape.isRegular) {
        var side = rect.shortestSide;
        rect = Rect.fromCenter(center: rect.center, width: side, height: side);
      }
      return shapePath(e.shape, rect,
          points: e.points,
          inner: e.innerRatio,
          cornerRadius: e.cornerRadius,
          corners: e.corners,
          bubble: e.bubble);
    case VectorElement e when e.shapes != null:
      var p = e.placement(bounds, e.viewBox);
      var matrix = Float64List.fromList([
        p.sx, 0, 0, 0, //
        0, p.sy, 0, 0, //
        0, 0, 1, 0, //
        p.dx, p.dy, 0, 1,
      ]);
      var out = Path();
      for (var d in vectorDrawn(e.shapes!)) {
        out.addPath(d.outline.transform(matrix), Offset.zero);
      }
      return out;
    case LineElement e:
      var points = _curvePoints(lineWithPose(e, frame));
      if (points != null && points.length > 1) return _polyline(points);
    case PathElement e:
      var points = _curvePoints(e);
      if (points != null && points.length > 1) return _polyline(points);
    default:
      break;
  }
  return Path()..addRect(bounds);
}

Path _polyline(List<Offset> points) {
  var out = Path()..moveTo(points.first.dx, points.first.dy);
  for (var q in points.skip(1)) {
    out.lineTo(q.dx, q.dy);
  }
  return out;
}

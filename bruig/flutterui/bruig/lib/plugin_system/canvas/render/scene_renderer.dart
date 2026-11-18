import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/synth_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
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
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/chart_story.dart';
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
    show MotionDevice, MotionDeviceKind;
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
import 'package:bruig/plugin_system/canvas/render/chart_morph.dart';
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

part 'scene_renderer_backdrop.dart';
part 'scene_renderer_text.dart';
part 'scene_renderer_shapes.dart';
part 'scene_renderer_image.dart';
part 'scene_renderer_image_layers.dart';
part 'scene_renderer_in_turn.dart';

// scene_renderer.dart draws a whole document at one frame. It is the one
// place a canvas becomes pixels -- the stage, thumbnails, every export and a
// published canvas replayed in a chat -- so what is seen is what is sent. It
// draws in the document's design coordinates, knowing nothing of zoom,
// scroll, selection or widgets (the caller sets the transform), and takes no
// BuildContext because an export has no widget tree.

/// CanvasVector is a picture kept as a drawing, with the size it was drawn
/// for, so it stays sharp at any size without a bitmap for each.
class CanvasVector {
  final ui.Picture picture;
  final Size size;
  const CanvasVector(this.picture, this.size);
}

/// CanvasImageSource hands the renderer decoded pictures. A picture may not
/// be ready (decoded off the main thread, a cut-out recomputed): null draws a
/// placeholder and the stage redraws later, rather than blocking a frame.
abstract class CanvasImageSource {
  /// resolve is [assetId] with [removal] applied, or null until decoded.
  ui.Image? resolve(String assetId, BackgroundRemoval removal);

  /// resolveVector is the asset as a drawing, or null for a bitmap. Callers
  /// that need pixels never ask; others fall back to [resolve].
  CanvasVector? resolveVector(String assetId) => null;

  /// resolveOutline is where the picture's ink is, for wrapped text; null
  /// until read from the pixels (a painter cannot wait), the box standing in.
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;

  /// loading is whether anything asked for is still being decoded: painters
  /// draw placeholders meanwhile, an export waits (drawWhenLoaded).
  bool get loading => false;
}

/// drawWhenLoaded asks [images] for everything [paint] draws and waits for
/// it: the store reads a picture only when first asked, and an export draws
/// each page once, so it would otherwise export placeholders. Up to three
/// rounds, as a picture arriving can ask for another (its outline).
Future<void> drawWhenLoaded(
    CanvasImageSource? images, void Function(ui.Canvas canvas) paint) async {
  if (images == null) return;
  for (var round = 0; round < 3; round++) {
    var recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder));
    recorder.endRecording().dispose();
    if (!images.loading) return;
    // Bounded: a picture that never arrives is drawn missing, not waited for.
    for (var waited = 0; images.loading && waited < 300; waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// CanvasPaintPart is how much of a canvas one call draws. Split for facing
/// pages only: both backdrops go down first and contents over both, so a
/// picture across the gutter is not covered by the other page's backdrop.
enum CanvasPaintPart {
  /// all is a whole canvas, which is what every other caller wants.
  all,

  /// backdrop is the document's background and nothing on it.
  backdrop,

  /// contents is the master canvas and the elements, with no backdrop.
  contents,
}

/// paintCanvasDocument draws [doc] at [frame]. [hoveredButton] is the button
/// under the pointer: the one piece of interaction state taken, since hover
/// colours are part of a button's design and must show while chosen.
void paintCanvasDocument(
  ui.Canvas canvas,
  CanvasDocument doc, {
  int frame = 0,
  CanvasPaintPart part = CanvasPaintPart.all,
  CanvasImageSource? images,
  String? hoveredButton,
  bool editing = false,

  /// skipTextItem is the words of one piece of a text element (or its own
  /// words: textBodyWords) shown by an open editor; the rest is drawn.
  String? skipTextItem,

  /// backgrounds is the editor's pattern cache; null for an exact export.
  ProceduralCache? backgrounds,

  /// counterValue and counterPressed are what a live counter shows and which
  /// button is lit (see paintElement); null in an export, where none runs.
  double Function(CounterElement)? counterValue,

  /// liveMotion is what plays from slots (motion_player.dart); null in export.
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,

  /// audioState is how each sound is doing, for its icon; null in an export.
  AudioState Function(AudioElement)? audioState,

  /// videoShow is each video's frame and play bar; null in an export.
  VideoShow Function(VideoElement)? videoShow,

  /// backdrop is the background already rasterised, for a caller drawing many
  /// frames of a document whose background does not move. See ExportBackdrop.
  ui.Image? backdrop,

  /// previewing is one element drawn at its own frame while it is previewed.
  ({String id, int frame})? previewing,

  /// camera is the scene's framing (zoom, and the page point at the middle),
  /// or null. It moves the scene's backdrop and elements, not the master's,
  /// so a frame or watermark stays put under the shot. See SceneCamera.
  (double, Offset)? camera,
}) {
  var rect = doc.size.rect;
  var time = frame / (doc.frameRate <= 0 ? 1 : doc.frameRate);
  // The Camera's lens where it is looked through: roll, depth of field,
  // parallax, vignette and motion blur. A slow move (SceneCamera) has none.
  var cam = camera == null || isStageScene(doc) ? null : cameraOf(doc);
  var look =
      cam == null ? null : cameraLookAt(cam, frame, doc, live: liveMotion);
  void through(ui.Canvas cv, double zoom, Offset focus, double roll) {
    cv.translate(rect.center.dx, rect.center.dy);
    if (roll != 0) cv.rotate(-roll * math.pi / 180);
    cv.scale(zoom);
    cv.translate(-focus.dx, -focus.dy);
  }

  void framed(void Function(ui.Canvas cv) paint) {
    if (camera == null) {
      paint(canvas);
      return;
    }
    var (zoom, focus) = camera;
    var roll = look?.roll ?? 0;
    canvas.save();
    canvas.clipRect(rect);
    // A tile map's far layers lag the camera by how far it has moved.
    tileCameraShift = focus - rect.center;
    try {
      // Motion blur: the picture laid down along the camera's move since the
      // last frame, for the share the shutter is open, and averaged.
      var smear =
          look != null && look.motionBlur > 0 && frame > 0 && cam != null
              ? _cameraMove(cam, frame, doc, liveMotion, zoom, focus, roll)
              : null;
      if (smear == null) {
        through(canvas, zoom, focus, roll);
        paint(canvas);
      } else {
        var recorder = ui.PictureRecorder();
        paint(ui.Canvas(recorder));
        var picture = recorder.endRecording();
        const samples = 6;
        var (z0, f0, r0) = smear;
        canvas.saveLayer(rect, Paint());
        for (var i = 0; i < samples; i++) {
          var t = 1 - look!.motionBlur * i / (samples - 1);
          canvas.saveLayer(
              rect,
              Paint()
                ..blendMode = BlendMode.plus
                ..color = const Color.fromRGBO(255, 255, 255, 1 / samples));
          through(canvas, z0 + (zoom - z0) * t, Offset.lerp(f0, focus, t)!,
              r0 + (roll - r0) * t);
          canvas.drawPicture(picture);
          canvas.restore();
        }
        canvas.restore();
        picture.dispose();
      }
    } finally {
      tileCameraShift = null;
    }
    canvas.restore();
  }

  if (part != CanvasPaintPart.contents) {
    framed((cv) => _paintDocumentBackground(cv, rect, doc, time, images,
        backgrounds, doc.frameRate.toDouble(), backdrop, videoShow));
  }
  if (part == CanvasPaintPart.backdrop) return;

  // The shared canvas, under every scene (over it with doc.masterOver). Not
  // while the master is itself being edited, or it would be drawn twice.
  var master = doc.masterScene;
  // The master runs on the whole run's clock, so its animation does not
  // restart each scene. See CanvasDocument.startOfScene.
  var onMaster = master != null && !doc.editingMaster
      ? {for (var e in master.elements) e.id}
      : const <String>{};
  // Except in a book: its pages are read in any order, and what is on its
  // master (a page number, a running head) belongs to the page it is on.
  var runFrame = doc.hasScenes && !doc.isPages && onMaster.isNotEmpty
      ? doc.startOfScene(doc.at) + frame
      : frame;
  void scene(List<CanvasElement> elements, {ui.Canvas? on, _Lens? lens}) =>
      _paintScene(on ?? canvas, doc, elements, frame,
          lens: lens,
          onMaster: onMaster,
          runFrame: runFrame,
          images: images,
          editing: editing,
          hoveredButton: hoveredButton,
          skipTextItem: skipTextItem,
          counterValue: counterValue,
          liveMotion: liveMotion,
          counterPressed: counterPressed,
          counterRunning: counterRunning,
          audioState: audioState,
          videoShow: videoShow,
          previewing: previewing,
          backgrounds: backgrounds);
  // With a camera, the master and the scene through it are two runs.
  if (camera != null) {
    var shared = master != null && !doc.editingMaster;
    if (shared && !doc.masterOver) scene(master.elements);
    var (zoom, focus) = camera;
    framed((cv) => scene(doc.elements,
        on: cv, lens: look == null ? null : _Lens(look, zoom, focus, rect)));
    if (look != null && look.vignette > 0) {
      _paintVignette(canvas, rect, look.vignette, look.vignetteSoft);
    }
    // Over, a HUD: still while the camera moves the level under it.
    if (shared && doc.masterOver) scene(master.elements);
    return;
  }
  // The master under the page, its page numbers over (stackedWithMaster).
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

/// _paintScene draws the shared canvas or a scene, by the same skip rules.
void _paintScene(
  ui.Canvas canvas,
  CanvasDocument doc,
  List<CanvasElement> elements,
  int frame, {
  /// onMaster are the shared canvas's elements, drawn at the run's [runFrame].
  Set<String> onMaster = const {},
  int? runFrame,
  CanvasImageSource? images,
  bool editing = false,
  String? hoveredButton,
  String? skipTextItem,
  double Function(CounterElement)? counterValue,
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,
  ({String id, int frame})? previewing,
  ProceduralCache? backgrounds,

  /// lens is the Camera's, blurring by focus distance and moving by depth.
  _Lens? lens,
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
        hidden.contains(element.id) ||
        onMaps.contains(element.id)) {
      continue;
    }
    var drawnAt = element.id == previewing?.id
        ? previewing!.frame
        : onMaster.contains(element.id)
            ? runFrame ?? frame
            : frame;
    var lensed = lens?.on(canvas, element, drawnAt, doc, liveMotion) ?? 0;
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
    for (var i = 0; i < lensed; i++) {
      canvas.restore();
    }
  }
  // Synth cables over every module, as they hang over a rack.
  if (elements.any((e) => e is SynthModuleElement)) {
    paintSynthCables(canvas, elements);
  }
}

/// _Lens is a Camera's lens on this frame: its look and its framing.
class _Lens {
  final CameraLook look;
  final double zoom;
  final Offset focus;
  final Rect page;
  const _Lens(this.look, this.zoom, this.focus, this.page);

  /// on sets [canvas] up for [e]: moved by its depth (parallax), softened by
  /// its distance from the focus. Returns how many saves to restore.
  int on(ui.Canvas canvas, CanvasElement e, int frame, CanvasDocument doc,
      LiveMotion? live) {
    var depth = e.base.depth;
    var saves = 0;
    if (look.sways(depth)) {
      // Framed as the camera frames the page, through its own depth: the
      // camera's framing undone, its own put on (see parallaxed).
      var (z, c) = parallaxed(zoom, focus, page, depth, look.parallax);
      var by = z / zoom;
      canvas.save();
      saves++;
      canvas.translate(focus.dx - by * c.dx, focus.dy - by * c.dy);
      canvas.scale(by);
    }
    var sigma = look.blurAt(depth);
    if (sigma > 0.25) {
      var bounds = e.movedBoundsAt(frame, doc, live: live).inflate(sigma * 3);
      canvas.saveLayer(
          bounds,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal));
      saves++;
    }
    return saves;
  }
}

/// _cameraMove is where [cam] looked the frame before [frame] (zoom, focus,
/// roll), or null where it has not moved and there is nothing to smear.
(double, Offset, double)? _cameraMove(
    CameraElement cam,
    int frame,
    CanvasDocument doc,
    LiveMotion? live,
    double zoom,
    Offset focus,
    double roll) {
  var (z0, f0) = cameraFraming(cam, frame - 1, doc, live: live);
  var r0 = cameraLookAt(cam, frame - 1, doc, live: live).roll;
  if ((z0 - zoom).abs() < 1e-4 &&
      (f0 - focus).distance < 0.05 &&
      (r0 - roll).abs() < 0.01) {
    return null;
  }
  return (z0, f0, r0);
}

/// _paintVignette darkens [rect]'s corners by [amount], reaching in [soft].
void _paintVignette(ui.Canvas canvas, Rect rect, double amount, double soft) {
  var r = rect.longestSide * 0.75;
  var inner = (1 - soft.clamp(0.0, 1.0)) * 0.7;
  canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(rect.center, r, [
          const Color(0x00000000),
          const Color(0x00000000),
          Color.fromRGBO(0, 0, 0, amount.clamp(0.0, 1.0)),
        ], [
          0,
          inner,
          1
        ]));
}

/// chartSeriesReveal is how far each chart series is through its arrival, or
/// null where none is offset. A series reads the chart's reveal
/// ChartSeries.delay seconds earlier (a shift, not a speed change). [poseAt]
/// is the chart's pose with clips; without it, its track.
List<double>? chartSeriesReveal(ChartElement e, int frame, int frameRate,
    {Keyframe Function(int frame)? poseAt}) {
  var series = e.data.series;
  var inTurn = e.animation.seriesInTurn && series.length > 1;
  if (!inTurn && !series.any((s) => s.delay != 0)) return null;
  var track = e.track;
  var rate = frameRate <= 0 ? 1 : frameRate;
  var pose = poseAt ?? (int f) => track?.at(f) ?? Keyframe.rest;
  double at(int f) => pose(f).values[KeyframeChannel.reveal] ?? 1;
  var whole = at(frame);
  return [
    for (var (i, s) in series.indexed)
      // Its own offset, then -- in turn -- its share of the arrival.
      switch (s.delay == 0 ? whole : at((frame - s.delay * rate).round())) {
        var r when inTurn => seriesInTurnReveal(r, i, series.length),
        var r => r,
      },
  ];
}

/// leavesByItself is whether [element] has its own exit over its closing
/// stretch, or has no exits at all; otherwise paintElement fades it.
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

/// _chartArea is where a chart in [bounds] is drawn: a little inside them,
/// so it is not flush with its edges, or all of them for one on a card,
/// whose padding keeps that room (ChartElement.box).
Rect _chartArea(ChartElement e, Rect bounds) => chartBoxIsPlain(e.box)
    ? bounds.deflate(bounds.shortestSide * 0.02)
    : bounds;

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

  /// skipTextItem is the piece not to draw, under an open CanvasTextEditor.
  String? skipTextItem,

  /// document is for clips, stages, curves and page numbers; null for a lone
  /// element (a thumbnail), drawn from its own track and box.
  CanvasDocument? document,

  /// counterValue and counterPressed are a live counter's value and lit
  /// button, asked of the caller whose window runs it; null means none runs.
  /// liveMotion, audioState and videoShow: see paintCanvasDocument.
  double Function(CounterElement)? counterValue,
  LiveMotion? liveMotion,
  int Function(CounterElement)? counterPressed,
  bool Function(CounterElement)? counterRunning,
  AudioState Function(AudioElement)? audioState,
  VideoShow Function(VideoElement)? videoShow,

  /// poseOutside leaves the pose's move, turn, scale and fade to the caller
  /// (the interactive EPUB moves elements with CSS). What else the pose pins
  /// (an arrival's progress, a count, a bow) is content, and still drawn.
  bool poseOutside = false,

  /// backgrounds is the pattern cache a background element draws from.
  ProceduralCache? backgrounds,

  /// instance is which of an element reused to draw (see instances.dart);
  /// null draws every one, and -1 the element as placed, as one.
  int? instance,

  /// blended is set where the element's blend is already being laid on.
  bool blended = false,
}) {
  // A camera frames the picture and is never in it: see cameraFrame.
  if (element is CameraElement) return;
  // A text's fields, filled by the page it is drawn on (text_fields.dart).
  if (element is TextElement && document != null) {
    element = textWithFields(element, document);
  }
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
        // Alike but for where they are: drawn once, stamped at each place.
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
          // Pose left to the caller (EPUB CSS); its own place drawn here.
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
  // Its own settings as its Design has them on this frame (design_device).
  element = designedNow(element, frame, document,
      live: liveMotion, frameRate: frameRate);
  var outer = poseOutside ? Keyframe.rest : pose;
  var alpha = (element.opacity * outer.opacity).clamp(0.0, 1.0);
  // A closing stretch with no exit chosen fades rather than doing nothing:
  // the editor never leaves one, but a preset, a paste or a script can.
  var close = pose.values[KeyframeChannel.close] ?? 0;
  if (!poseOutside && close > 0 && !leavesByItself(element)) {
    alpha *= (1 - close).clamp(0.0, 1.0);
  }
  if (alpha <= 0.002) return;

  // A video shows only while its clip does, so the halves of a cut clip do
  // not cover each other with posters. A master's video in a run of scenes
  // already has the run's frame (paintCanvasDocument); a book's, its page's.
  if (element is VideoElement &&
      document != null &&
      document.offTimeline(element.clip, frame,
          onMaster: document.isPages &&
              (document.masterScene?.elements.contains(element) ?? false))) {
    return;
  }

  var bounds = element.bounds;

  // Something on a stage is drawn where the stage's camera sees it, lit by
  // the stage: a 3D model through the camera, else a flat in perspective.
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
      // Its shadow on the floor first, fainter the higher it is held.
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

  // A page number on the leaf's outside edge: mirrored on a left-hand page
  // so a spread matches and centred stays centred (CounterElement.mirrored).
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
    // Its words' own looks stay; a look on all of it has no box to go on.
    _paintText(canvas, bounds, element, document,
        pose: pose,
        frame: frame,
        skipItem: skipTextItem,
        onLayer: _layerPainter(
            _looksNow(element, frame, frameRate, document, instance),
            turn: element.rotation + pose.rotate,
            scale: pose.scale,
            time: frame / (frameRate <= 0 ? 1 : frameRate)));
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
  // about where it is moved to, not where it was placed.
  if (outer.dx != 0 || outer.dy != 0) canvas.translate(outer.dx, outer.dy);

  // Squashed along its travel, about its middle: see the Squash device.
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

  // Its moving loop's turn and size about the loop's pivot; its move and
  // fade are in the pose already (poseWithMotion), for whatever follows it.
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
  // Its looks (the devices right of its drawing in its Chain) as its LFOs
  // set them on this frame, and as a reused copy has its own values of them.
  var looks = _looksNow(element, frame, frameRate, document, instance);
  // Those on one layer of a text are laid on it as it is drawn, and the
  // rest on all of it, here. See MotionDevice.layer.
  var presence = ((pose.values[KeyframeChannel.reveal] ?? 1) *
          (1 - (pose.values[KeyframeChannel.close] ?? 0)))
      .clamp(0.0, 1.0)
      .toDouble();
  var onLayer = _layerPainter(looks,
      turn: element.rotation + pose.rotate,
      scale: pose.scale,
      time: frame / (frameRate <= 0 ? 1 : frameRate),
      presence: presence);
  var whole = [
    for (var l in looks)
      if (l.layer.isEmpty) l
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
  // An arrival grows, spins and flips about the anchor (ElementBase.anchorX).
  var pivot = element.anchorCentred ? null : element.anchorIn(bounds);
  void arriving(ui.Canvas canvas, Rect box, ElementAnimation animation,
          Keyframe pose, void Function() what) =>
      paintArriving(canvas, box, animation, pose, what, pivot: pivot);
  void body() {
    switch (element) {
      case TextElement e:
        _paintText(canvas, bounds, e, document,
            pose: pose,
            frame: frame,
            images: images,
            skipItem: skipTextItem,
            onLayer: onLayer);
      case ShapeElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintShape(canvas, bounds, e, images));
      case LineElement e:
        arriving(canvas, bounds, e.animation, pose,
            () => _paintLine(canvas, _bowed(e, pose)));
      case ImageElement e:
        // The time its drift and its layers' loops go by: see _imageClock.
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
        // At its step or part-way through its dates: chartShownAt
        // (chart_story.dart), which a camera aimed at it reads too.
        e = chartShownAt(e, document, frame, between: betweenFrames);
        // In the editor, numbers just changed ease to their new values.
        if (editing && chartGlides.isNotEmpty) {
          e = e.copyWith(data: glided(e.id, e.data));
        }
        // How much has arrived (all, with no animation) and left, how far
        // each series is; arriving out of the chart before (chart_morph.dart).
        var arrived = pose.values[KeyframeChannel.reveal] ?? 1;
        if (e.animation.preset == ChartAnimationPreset.morph &&
            arrived < 1 &&
            document != null) {
          if (morphFrom(e, document) case var from?) {
            paintMorph(canvas, _chartArea(e, bounds), e, from,
                _chartArea(from, from.bounds), arrived);
            break;
          }
        }
        paintChart(canvas, _chartArea(e, bounds), e,
            reveal: arrived,
            close: pose.values[KeyframeChannel.close] ?? 0,
            seriesReveal: chartSeriesReveal(e, frame, frameRate,
                poseAt: (f) =>
                    poseWithMotion(e, f, document, live: liveMotion)));
      case TableElement e:
        if (_tableInTurn(e, pose)) {
          paintTableInTurn(canvas, bounds, e, pose, images);
        } else {
          arriving(canvas, bounds, e.animation, pose,
              () => paintTable(canvas, bounds, e, images: images));
        }
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
      case MetronomeElement e:
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintMetronome(canvas, bounds, e,
                show: metronomeShowOf?.call(e) ?? const MetronomeShow()));
      case CodeElement e:
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintCode(canvas, bounds, e,
                seconds: frame / frameRate,
                show: codeShowOf?.call(e) ?? const CodeShow()));
      case CodeTaskElement e:
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintCodeTask(canvas, bounds, e, document,
                show: codeTaskShowOf?.call(e) ?? const CodeTaskShow()));
      case PlayTaskElement e:
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintPlayTask(canvas, bounds, e,
                show: playTaskShowOf?.call(e) ?? const PlayTaskShow(),
                images: images));
      case CodeRunElement e:
        var code = document?.elementById(e.code);
        var preview = e.result?.preview ?? "";
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintCodeRun(
                canvas, bounds, e, code is CodeElement ? code : null,
                seconds: frame / frameRate,
                image: preview.isEmpty
                    ? null
                    : images?.resolve(preview, const BackgroundRemoval()),
                show: codeRunShowOf?.call(e) ?? const CodeRunShow()));
      case SynthTaskElement e:
        arriving(canvas, bounds, const ElementAnimation(), pose,
            () => paintSynthTask(canvas, bounds, e, document));
      case SynthModuleElement e:
        arriving(
            canvas,
            bounds,
            const ElementAnimation(),
            pose,
            () => paintSynthModule(canvas, bounds, e,
                show: synthShowOf?.call(e, frame) ??
                    SynthShow(seconds: frame / (document?.frameRate ?? 24))));
      case AudioElement e:
        arriving(
            canvas,
            bounds,
            e.animation,
            pose,
            () => paintAudio(
                canvas,
                bounds,
                e,
                audioState?.call(e) ??
                    AudioState.atFrame(e, frame, document?.frameRate ?? 24,
                        doc: document),
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
            // Turned the way its clips move it, live slots included, on
            // their clock: a frame before is a frame's time before.
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
        // Its figures are drawn among what stands on it, by their feet.
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
                    // Where its clips, live ones too, stand it; figures on a
                    // map are drawn only here.
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

  if (whole.isEmpty) {
    drawn();
  } else {
    // How fast it moves, for a Blur's Motion blur: only asked for one.
    var velocity = Offset.zero;
    if (document != null &&
        whole.any(
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

    paintWithLooks(canvas, bounds, whole, drawnOn,
        turn: element.rotation + pose.rotate,
        scale: pose.scale,
        velocity: velocity,
        time: time,
        // How much of it is there: arrived, and not yet gone.
        presence: presence);
  }

  if (layered) canvas.restore();
  canvas.restore();
}

// --------------------------------------------------------------------------

/// _looksNow are [element]'s looks as they are on [frame]: as its LFOs move
/// them, and as copy [instance] has its own values of them.
List<MotionDevice> _looksNow(CanvasElement element, int frame, num frameRate,
        CanvasDocument? document, int? instance) =>
    [
      for (var l in element.base.motion.looks)
        withOwnValues(
            motionModulated(l, element.base.motion.devices,
                frame / (frameRate <= 0 ? 1 : frameRate),
                doc: document, spans: phaseSpansOf(element, document)),
            element.base.motion.instances,
            instance),
    ];

/// _layerPainter lays per-layer looks (MotionDevice.layer) as each is drawn.
LayerPainter? _layerPainter(List<MotionDevice> looks,
    {double turn = 0, double scale = 1, double time = 0, double presence = 1}) {
  if (!looks.any((l) => l.layer.isNotEmpty)) return null;
  return (canvas, box, layer, draw) {
    var mine = [
      for (var l in looks)
        if (l.layer == layer) l
    ];
    if (mine.isEmpty) return draw(canvas);
    paintWithLooks(canvas, box, mine, draw,
        turn: turn, scale: scale, time: time, presence: presence);
  };
}

/// _arrivalFrames is the stretch [e]'s arrival plays over (the clip playing
/// it, see revealsIn), which its words, layers and shapes are timed against.
(int?, int?) _arrivalFrames(CanvasElement e, Keyframe pose) {
  if (pose.values[revealFrom] case var a?) {
    return (a.round(), (pose.values[revealTo] ?? a).round());
  }
  return (null, null);
}

/// withoutGuides is [doc] with its and the master's guide paths hidden, for
/// the stage while the canvas plays or a game runs: they are scaffolding.
/// Hidden, not removed, so what follows one by id (a Follow path, words on a
/// curve) still finds it. [doc] itself where it has none.
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

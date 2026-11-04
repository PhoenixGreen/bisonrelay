import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/camera_3d.dart';
import 'package:bruig/plugin_system/canvas/export/audio_export.dart'
    show estimateAudioBytes;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraMostZoom, cameraOf, sceneFraming;
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/plugin_system/canvas/export/gif_encoder.dart';
import 'package:bruig/plugin_system/canvas/export/pdf_writer.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:flutter/foundation.dart';

// canvas_export.dart turns a document into bytes somebody can be sent.
//
// Everything renders through scene_renderer.dart, the code the editing stage
// draws with, so what is exported is what was on screen. Compression goes
// through prepareEmbed, the same path as any picture attached to a post.

/// maxExportScale bounds how far past the document's own width an export may
/// go. Past four the memory for one frame starts to matter: a 4096-wide 16:9
/// frame at 4x is 1.5GB of RGBA.
const double maxExportScale = 4;

/// CanvasExport is one finished file.
class CanvasExport {
  final Uint8List data;
  final String mime;
  final int width;
  final int height;

  const CanvasExport(this.data, this.mime,
      {required this.width, required this.height});

  int get bytes => data.length;
}

/// ExportBackdrop is a document's background, rasterised once for a whole run
/// of frames.
///
/// Generating a background is the most expensive thing on a canvas (about a
/// tenth of a second a frame for Metal at 2048). Kept only where it is still
/// for the whole run: in a document of scenes, only where every scene shows
/// the same still background.
class ExportBackdrop {
  final ui.Image image;
  ExportBackdrop._(this.image);

  /// prepare rasterises [document]'s background at the export's pixel size
  /// (not the design's, which would blur), or returns null where there is
  /// nothing to keep.
  static Future<ExportBackdrop?> prepare(
    CanvasDocument document, {
    double scale = 1,
    CanvasImageSource? images,
  }) async {
    // The canvas whose background is drawn: a scene, never the master that
    // happened to be open when the document was saved.
    var drawn = document.hasScenes
        ? document.goToScene(0).copyWith(onMaster: false)
        : document;
    var background = drawn.drawnBackground;
    // A zooming camera blows the backdrop up with the scene, so it is drawn
    // larger by the most any scene zooms -- see SceneCamera -- and sharp
    // under the closest of them.
    var zoom = 1.0;
    if (document.hasScenes) {
      var shared = jsonEncode(background.toJson());
      for (var (i, scene) in document.allScenes.indexed) {
        if (scene.backgroundOff) return null;
        if (jsonEncode(document.backgroundOf(i).toJson()) != shared) {
          return null;
        }
        if (scene.camera case var c?) {
          zoom = math.max(zoom, math.max(c.fromZoom, c.toZoom));
        }
        zoom = math.max(zoom, cameraMostZoom(document.goToScene(i)));
      }
    } else {
      // A Camera element, which takes over: see cameraMostZoom.
      zoom = cameraMostZoom(document);
    }
    if (!background.isStage &&
        !background.isParallax &&
        background.spec.animated) {
      return null;
    }
    if (background.isParallax &&
        background.parallaxOn(document.size.rect).moves) {
      return null;
    }
    // A stage whose camera moves is a different picture every frame too --
    // keyed, or a Camera's.
    if (background.isStage &&
        ((background.stage?.track?.keys.isNotEmpty ?? false) ||
            cameraOf(drawn) != null)) {
      return null;
    }
    // A video on the timeline behind everything is a different picture every
    // frame, like a moving pattern.
    if (background.video?.clip.timed == true) return null;

    var asked = scale.clamp(0.05, maxExportScale) * zoom;
    var s = asked * document.size.exportScale;
    var width = math.max(1, (document.size.exportSize.width * asked).round());
    var height = math.max(1, (document.size.exportSize.height * asked).round());

    void draw(ui.Canvas canvas) {
      canvas.scale(s);
      paintDocumentBackdrop(canvas, drawn, images: images);
    }

    await drawWhenLoaded(images, draw);
    var recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    var picture = recorder.endRecording();
    try {
      return ExportBackdrop._(await picture.toImage(width, height));
    } finally {
      picture.dispose();
    }
  }

  void dispose() => image.dispose();
}

/// renderFrame draws one frame into a ui.Image at [scale] times the size the
/// canvas is published at (the design scaled by CanvasSize.exportScale, so a
/// bigger export width is the same picture with more pixels).
///
/// The caller owns the image and must dispose it.
Future<ui.Image> renderFrame(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,

  /// backdrop is the background rasterised once for the whole run (see
  /// ExportBackdrop). Null draws it the slow way, right for a single still.
  ExportBackdrop? backdrop,

  /// videoShow is the frame each video on the timeline shows on this frame
  /// -- see ExportMedia. Null shows every video as its poster.
  VideoShow Function(VideoElement)? videoShow,
}) async {
  // Adjustment layers need their shader before anything is drawn: drawn
  // without it, they would come out of an export unadjusted.
  await AdjustShader.load();
  await TextureShader.load();
  await SharpenShader.load();
  await HealShader.load();
  // Only the caller's multiplier is clamped: exportScale is what makes the
  // file its declared size, and clamping it would draw a small scene into a
  // large image.
  var asked = scale.clamp(0.05, maxExportScale);
  var s = asked * document.size.exportScale;
  var width = math.max(1, (document.size.exportSize.width * asked).round());
  var height = math.max(1, (document.size.exportSize.height * asked).round());

  void drawNow(ui.Canvas canvas) {
    canvas.scale(s);
    // A document of scenes publishes as the sequence it plays, drawn by the
    // preview's own paintSequenceFrame.
    if (document.hasScenes) {
      paintSequenceFrame(canvas, document, frame,
          images: images, videoShow: videoShow, backdrop: backdrop?.image);
    } else {
      paintCanvasDocument(canvas, document,
          frame: frame,
          // A document of one scene moves its camera too: its Camera, or
          // its slow move -- see sceneFraming.
          camera: sceneFraming(document, frame),
          images: images,
          backdrop: backdrop?.image,
          videoShow: videoShow);
    }
  }

  // In a scene on a 3D stage, its Camera is the stage's: see camera_3d.
  void draw(ui.Canvas canvas) =>
      directedBy(document, null, () => drawNow(canvas));

  // Its pictures read, not their placeholders -- see drawWhenLoaded.
  await drawWhenLoaded(images, draw);
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));

  var picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// renderPng is one frame as a PNG.
Future<CanvasExport?> renderPng(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,
}) async {
  ui.Image? image;
  try {
    image =
        await renderFrame(document, frame: frame, scale: scale, images: images);
    var data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return CanvasExport(data.buffer.asUint8List(), "image/png",
        width: image.width, height: image.height);
  } catch (exception) {
    debugPrint("Unable to render the canvas: $exception");
    return null;
  } finally {
    image?.dispose();
  }
}

/// renderImage is one frame as a PNG or a JPEG, compressed with the same
/// [options] every attached picture goes through.
Future<CanvasExport?> renderImage(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,
  EmbedOptions options = const EmbedOptions(),
}) async {
  var png =
      await renderPng(document, frame: frame, scale: scale, images: images);
  if (png == null) return null;
  if (!options.changesAnything && options.format != EmbedFormat.jpeg) {
    return png;
  }

  var prepared = await prepareEmbed(png.data, png.mime, options);
  return CanvasExport(prepared.data, prepared.mime,
      width: prepared.width ?? png.width,
      height: prepared.height ?? png.height);
}

/// renderPdf is the document as pages: one page per scene, or [frame] alone
/// for a document without scenes.
///
/// [scale] is the print resolution, not the page size ([paper] decides the
/// sheet). At 1 a canvas prints at roughly 96 to the inch, soft on paper.
Future<CanvasExport?> renderPdf(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,
  PdfPaper paper = PdfPaper.canvas,
  PdfOrientation orientation = PdfOrientation.auto,
}) async {
  try {
    // Rendered and converted one at a time, so only one ui.Image is alive at
    // once; the raw pixels of every page are still held until writePdf.
    var starts = document.hasScenes
        ? [
            for (var i = 0; i < document.allScenes.length; i++)
              document.startOfScene(i),
          ]
        : [frame];

    var pictures = <PdfPicture>[];
    for (var at in starts) {
      ui.Image? image;
      try {
        image = await renderFrame(document,
            frame: at, scale: scale, images: images);
        // Straight rather than premultiplied: a PDF keeps colour and alpha as
        // separate images, and un-premultiplying loses precision.
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (raw == null) return null;
        pictures.add(PdfPicture(raw.buffer.asUint8List(),
            width: image.width, height: image.height));
      } finally {
        image?.dispose();
      }
    }
    if (pictures.isEmpty) return null;

    var page = pageFor(paper, document.size.size, orientation: orientation);
    var bytes = writePdf(pictures, page: page);
    return CanvasExport(bytes, "application/pdf",
        width: page.width.round(), height: page.height.round());
  } catch (exception) {
    debugPrint("Unable to write the canvas as a PDF: $exception");
    return null;
  }
}

/// GifProgress reports how far an animation export has got, so a long one can
/// show something moving rather than appearing to have hung.
typedef GifProgress = void Function(int done, int total);

/// renderGif draws every frame and encodes them.
///
/// Each frame is converted to raw bytes at once, so only one ui.Image is
/// alive at a time; the raw RGBA of every frame is still held until
/// encodeGif runs.
Future<CanvasExport?> renderGif(
  CanvasDocument document, {
  double scale = 1,
  CanvasImageSource? images,
  bool dither = true,
  int maxColors = gifMaxColors,
  int loop = 0,
  GifProgress? onProgress,
}) async {
  var frames = <GifFrame>[];
  // GIF delays are in hundredths of a second. Rounded once here so 12fps is
  // a steady 8/100 rather than alternating 8 and 9, which stutters.
  var delayMs = (1000 / document.frameRate).round().clamp(10, 65535);

  ExportBackdrop? backdrop;
  // The videos on the timeline, frame by frame; a GIF carries no sound.
  var media = ExportMedia.of(document, scale: scale);
  try {
    backdrop =
        await ExportBackdrop.prepare(document, scale: scale, images: images);
    for (var i = 0; i < document.playFrames; i++) {
      ui.Image? image;
      try {
        image = await renderFrame(document,
            frame: i,
            scale: scale,
            images: images,
            backdrop: backdrop,
            videoShow: await media?.at(i));
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (raw == null) return null;
        frames.add(GifFrame(
          rgba: raw.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          delayMs: delayMs,
        ));
      } finally {
        image?.dispose();
      }
      onProgress?.call(i + 1, document.playFrames);
      // Yield so the window stays responsive and progress can be drawn.
      await Future<void>.delayed(Duration.zero);
    }

    if (frames.isEmpty) return null;
    var bytes =
        encodeGif(frames, loop: loop, dither: dither, maxColors: maxColors);
    return CanvasExport(bytes, "image/gif",
        width: frames.first.width, height: frames.first.height);
  } catch (exception) {
    debugPrint("Unable to render the canvas animation: $exception");
    return null;
  } finally {
    backdrop?.dispose();
    media?.dispose();
  }
}

/// estimateBytes is what publishing this canvas would cost, in the file it
/// would be published as. An estimate, and labelled one on screen: rendering
/// the real thing on every edit would make the editor unusable.
int estimateBytes(CanvasDocument document, CanvasEstimate spec,
    {double scale = 1}) {
  if (spec.format == EstimateAs.audio) {
    return estimateAudioBytes(document, document.audio.export);
  }
  if (spec.format.moving) {
    var frames = spec.format == EstimateAs.video
        ? _oldAnimationBytes(document, scale: scale)
        : estimateAnimationBytes(document, scale: scale);
    // Measured on the presets, an MP4 lands at about a fifth of the
    // undifferenced GIF estimate (see _oldAnimationBytes).
    return spec.format == EstimateAs.video
        ? math.max(4096, (frames * 0.2 * _quality(spec.quality)).round())
        : frames;
  }

  var png = estimateStillBytes(document, scale: scale);
  return switch (spec.format) {
    EstimateAs.png => png,
    // WebP is about a quarter smaller than JPEG at the same quality.
    EstimateAs.jpeg =>
      math.max(2048, (png * 0.55 * _quality(spec.quality)).round()),
    EstimateAs.webp =>
      math.max(2048, (png * 0.42 * _quality(spec.quality)).round()),
    _ => png,
  };
}

/// _quality is how much of the full-quality size a setting keeps: a curve,
/// one at 100, a third at 85, a tenth at 40.
double _quality(int quality) {
  var q = quality.clamp(1, 100) / 100;
  return 0.06 + 0.94 * math.pow(q, 4.5).toDouble();
}

/// estimateStillBytes is a fast, rough guess at what a PNG of this document
/// will weigh: enough to tell a canvas that fits in a message from one that
/// does not.
int estimateStillBytes(CanvasDocument document, {double scale = 1}) {
  // The export size, not the design's: a 720p design published at 4K is a 4K
  // file.
  var pixels = document.size.exportSize.width *
      document.size.exportSize.height *
      scale *
      scale;

  // Bytes per pixel after PNG compression, by how much is going on; the
  // bands come from measuring the presets.
  var complexity = 0.06;
  for (var e in document.elements) {
    complexity += switch (e.kind) {
      ElementKind.image => 0.35,
      ElementKind.background => 0.30,
      ElementKind.chart || ElementKind.table => 0.05,
      _ => 0.015,
    };
  }
  if (document.background.isImage) {
    complexity += 0.35;
  } else {
    complexity += _backgroundWeight(document.background.spec.style);
  }

  return (pixels * complexity.clamp(0.02, 1.2)).round() + 1024;
}

/// _backgroundWeight is how badly a generated background compresses: large
/// flat areas pack to almost nothing, a different colour every few pixels
/// barely packs at all.
double _backgroundWeight(ProceduralStyle style) => switch (style) {
      ProceduralStyle.plain => 0.0,
      ProceduralStyle.lineGrid ||
      ProceduralStyle.hexGrid ||
      ProceduralStyle.pitch ||
      ProceduralStyle.rings =>
        0.08,
      // Ink on a flat ground.
      ProceduralStyle.splatter || ProceduralStyle.flames => 0.10,
      ProceduralStyle.speedLines => 0.12,
      // A dot or a stroke every few pixels, everywhere.
      ProceduralStyle.halftone || ProceduralStyle.crosshatch => 0.34,
      ProceduralStyle.gradientMesh ||
      ProceduralStyle.dotGrid ||
      ProceduralStyle.contours =>
        0.18,
      ProceduralStyle.bokeh ||
      ProceduralStyle.flowWaves ||
      ProceduralStyle.starfield ||
      ProceduralStyle.circuit ||
      ProceduralStyle.blockchain =>
        0.30,
      ProceduralStyle.ledGrid ||
      ProceduralStyle.rain ||
      ProceduralStyle.symbolField =>
        0.45,
      // Noise in every pixel, by design.
      ProceduralStyle.metal || ProceduralStyle.surface => 0.55,
    };

/// estimateAnimationBytes is the same guess for a GIF.
///
/// Later frames cost only the rectangle that changed (see encodeGif). The
/// 0.12 is a guess at how much of a frame moves, on the high side of what the
/// presets measure.
int estimateAnimationBytes(CanvasDocument document, {double scale = 1}) {
  var first = estimateStillBytes(document, scale: scale) * 0.7;
  return (first + first * 0.12 * (document.playFrames - 1)).round();
}

/// _oldAnimationBytes is a GIF's weight without frame differencing. Kept only
/// because the video estimate was measured as a fraction of it.
int _oldAnimationBytes(CanvasDocument document, {double scale = 1}) {
  var first = estimateStillBytes(document, scale: scale) * 0.7;
  return (first + first * 0.35 * (document.playFrames - 1)).round();
}

/// formatBytes prints a size the way the rest of the app does.
String formatBytes(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KiB";
  return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB";
}

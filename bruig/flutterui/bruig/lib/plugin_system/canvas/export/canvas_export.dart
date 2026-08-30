import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/plugin_system/canvas/export/gif_encoder.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';

// canvas_export.dart turns a document into bytes somebody can be sent.
//
// Everything here renders through the same scene_renderer.dart the editing
// stage draws with, at whatever size was asked for. That is the guarantee the
// whole feature rests on: what is exported is what was on screen, because it
// is the same code drawing the same document -- there is no second renderer to
// drift from the first.
//
// The compression is not reimplemented either. A rendered frame goes through
// prepareEmbed, which is what every picture attached to a post already goes
// through, so a canvas published into a chat is compressed by the same code,
// with the same quality control, as a photograph dropped into one.

/// maxExportScale bounds how far past the document's own width an export may
/// go.
///
/// The design width is already the intended size; the scale is for the case
/// where somebody wants a retina copy of a canvas laid out at a comfortable
/// editing size. Four is generous, and past it the memory for one frame starts
/// to matter: a 4096-wide 16:9 frame at 4x is 1.5GB of RGBA.
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

/// renderFrame draws one frame into a ui.Image at [scale] times the
/// document's own size.
///
/// The caller owns the image and must dispose it. Made explicit rather than
/// hidden behind a convenience, because a GIF export holds every frame at once
/// and leaking them is how a two hundred frame export runs a machine out of
/// memory.
Future<ui.Image> renderFrame(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,
}) async {
  var s = scale.clamp(0.05, maxExportScale);
  var width = math.max(1, (document.size.width * s).round());
  var height = math.max(1, (document.size.height * s).round());

  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.scale(s);
  paintCanvasDocument(canvas, document, frame: frame, images: images);

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
    image = await renderFrame(document,
        frame: frame, scale: scale, images: images);
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

/// renderImage is one frame as a PNG or a JPEG, with the quality control the
/// publish dialog offers.
///
/// [options] is the same EmbedOptions every attached picture goes through, so
/// "JPEG at 70" means exactly what it means everywhere else in the app.
Future<CanvasExport?> renderImage(
  CanvasDocument document, {
  int frame = 0,
  double scale = 1,
  CanvasImageSource? images,
  EmbedOptions options = const EmbedOptions(),
}) async {
  var png = await renderPng(document,
      frame: frame, scale: scale, images: images);
  if (png == null) return null;
  if (!options.changesAnything && options.format != EmbedFormat.jpeg) {
    return png;
  }

  var prepared = await prepareEmbed(png.data, png.mime, options);
  return CanvasExport(prepared.data, prepared.mime,
      width: prepared.width ?? png.width, height: prepared.height ?? png.height);
}

/// GifProgress reports how far an animation export has got, so a long one can
/// show something moving rather than appearing to have hung.
typedef GifProgress = void Function(int done, int total);

/// renderGif draws every frame and encodes them.
///
/// The frames are rendered one at a time and converted to raw bytes
/// immediately, so only one decoded ui.Image is alive at once. Rendering them
/// all first and encoding afterwards is the obvious shape and is what makes a
/// long export run out of memory.
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
  // GIF stores delays in hundredths of a second, so anything that does not
  // divide into 100 is approximated. The rounding happens once here rather
  // than per frame, so a 12fps animation is a consistent 8/100 throughout
  // instead of alternating 8 and 9 and visibly stuttering.
  var delayMs = (1000 / document.frameRate).round().clamp(10, 65535);

  try {
    for (var i = 0; i < document.frames; i++) {
      ui.Image? image;
      try {
        image = await renderFrame(document,
            frame: i, scale: scale, images: images);
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
      onProgress?.call(i + 1, document.frames);
      // Yielding between frames keeps the window responsive during a long
      // export. Without it the whole thing runs in one turn of the event loop
      // and the progress the caller is drawing never gets a chance to appear.
      await Future<void>.delayed(Duration.zero);
    }

    if (frames.isEmpty) return null;
    var bytes = encodeGif(frames,
        loop: loop, dither: dither, maxColors: maxColors);
    return CanvasExport(bytes, "image/gif",
        width: frames.first.width, height: frames.first.height);
  } catch (exception) {
    debugPrint("Unable to render the canvas animation: $exception");
    return null;
  }
}

/// estimateStillBytes is a fast guess at what a PNG of this document will
/// weigh, for the "Estimated size" line under the canvas.
///
/// A guess rather than a render, because the line updates as the design is
/// edited and rendering a full-size PNG on every change would make the editor
/// unusable. It is deliberately rough and deliberately says so on screen: what
/// it is for is telling the difference between a canvas that will fit in a
/// message and one that will not, which is a question about orders of
/// magnitude.
int estimateStillBytes(CanvasDocument document, {double scale = 1}) {
  var pixels = document.size.width * document.size.height * scale * scale;

  // Bytes per pixel after PNG compression, by how much is going on. Flat
  // colour and a few shapes pack extremely well; a dense procedural background
  // with a photograph on it barely packs at all. The bands come from measuring
  // the presets.
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

/// _backgroundWeight is how badly a generated background compresses.
///
/// The split is between styles that leave large flat areas -- which PNG's
/// filters reduce almost to nothing -- and styles that put a different colour
/// in every few pixels, which defeat them entirely. Matrix rain over a black
/// field is the worst case in the list and is also one of the most likely
/// things somebody makes with this.
double _backgroundWeight(ProceduralStyle style) => switch (style) {
      ProceduralStyle.plain => 0.0,
      ProceduralStyle.lineGrid ||
      ProceduralStyle.hexGrid ||
      ProceduralStyle.pitch ||
      ProceduralStyle.rings =>
        0.08,
      ProceduralStyle.gradientMesh ||
      ProceduralStyle.dotGrid ||
      ProceduralStyle.contours =>
        0.18,
      ProceduralStyle.bokeh ||
      ProceduralStyle.flowWaves ||
      ProceduralStyle.starfield ||
      ProceduralStyle.circuit =>
        0.30,
      ProceduralStyle.ledGrid ||
      ProceduralStyle.rain ||
      ProceduralStyle.symbolField =>
        0.45,
    };

/// estimateAnimationBytes is the same guess for a GIF.
///
/// A GIF's later frames are far cheaper than its first, because most of a
/// frame is usually identical to the one before it and LZW says so in very few
/// bytes. The 0.35 is that, measured across the presets; a document where
/// everything moves at once will beat it, and the line is marked as an
/// estimate for exactly that reason.
int estimateAnimationBytes(CanvasDocument document, {double scale = 1}) {
  var first = estimateStillBytes(document, scale: scale) * 0.7;
  return (first + first * 0.35 * (document.frames - 1)).round();
}

/// formatBytes prints a size the way the rest of the app does.
String formatBytes(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KiB";
  return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB";
}

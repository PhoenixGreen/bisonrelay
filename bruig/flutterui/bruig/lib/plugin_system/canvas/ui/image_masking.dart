import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_mask_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/segmentation.dart';
import 'package:bruig/plugin_system/canvas/render/matting.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

// image_masking.dart is the work behind the mask tools: finding a subject,
// putting masks together, and turning a point on the canvas into a point of
// the picture a layer shows.

/// lookOf is the picture the layer [layerId] of [e] shows, with everything
/// done to it: the element itself for the base layer, a picture layer's look
/// for one of those, and null for a layer with no picture.
ImageElement? lookOf(ImageElement e, String layerId) {
  var layer = e.layerById(layerId);
  if (layer == null) return null;
  return switch (layer.kind) {
    LayerKind.base => e,
    LayerKind.picture => layer.look,
    LayerKind.fill ||
    LayerKind.adjustment ||
    LayerKind.texture ||
    LayerKind.paint =>
      null,
  };
}

/// withLook is [e] with the layer [layerId]'s picture replaced by [look] --
/// see lookOf.
ImageElement withLook(ImageElement e, String layerId, ImageElement look) {
  var layer = e.layerById(layerId);
  if (layer == null) return e;
  return switch (layer.kind) {
    // The base layer's look is the element: whatever was changed in it is
    // changed in the element, layers and all.
    LayerKind.base => look,
    LayerKind.picture => e.withLayer(layerId, (l) => l.copyWith(look: look)),
    LayerKind.fill ||
    LayerKind.adjustment ||
    LayerKind.texture ||
    LayerKind.paint =>
      e,
  };
}

/// LayerPicture is where a layer's picture is drawn, for turning points on
/// the canvas into points of the picture and back.
class LayerPicture {
  final LayerSpace space;
  final ImageLayer layer;
  final Size size;
  final ImagePlacement placement;

  /// _inFrame is whether points are measured in the element's own frame --
  /// the base picture's, and a frame-masked layer's -- rather than in a
  /// picture layer's own turned box.
  final bool _inFrame;

  LayerPicture._(this.space, this.layer, this.size, this.placement,
      {bool inFrame = false})
      : _inFrame = inFrame || layer.isBase;

  /// frame is where a frame-masked layer of [e] -- an adjustment, a texture,
  /// a colour or paint layer -- lies: the whole frame, measured as a picture
  /// the frame's own size, so its mask's marks are fractions of the frame.
  static LayerPicture frame(ImageElement e, ImageLayer layer) {
    var space = LayerSpace(e, ImageLayer.base);
    var size = Size(space.inner.width, space.inner.height);
    return LayerPicture._(
        space, layer, size, placeImage(size, space.inner, ImageFit.stretch),
        inFrame: true);
  }

  /// of is where the layer [layerId] of [e] draws its picture of [size]
  /// pixels, or null for a layer with none.
  static LayerPicture? of(ImageElement e, String layerId, Size size) {
    var layer = e.layerById(layerId);
    var look = lookOf(e, layerId);
    if (layer == null || look == null) return null;
    var space = LayerSpace(e, layer);
    // The base picture's place is its own now, as a picture layer's is.
    var rect = space.rect;
    var placement = placeImage(size, rect, look.fit,
        crop: look.crop, framing: look.framing);
    return LayerPicture._(space, layer, size, placement);
  }

  /// toPicture is [canvasPoint] as a fraction of the picture across and down
  /// -- not held to the picture, so a stroke that runs off its edge stays one
  /// stroke.
  Offset toPicture(Offset canvasPoint) {
    var local =
        _inFrame ? space.toFrame(canvasPoint) : space.toLayer(canvasPoint);
    // A picture -- a layer's or the base -- mirrored in its place is
    // mirrored back, so a stroke lands on the pixels under the pointer.
    if (!layer.framed) {
      var r = space.rect;
      if (layer.flipX) local = Offset(r.left + r.right - local.dx, local.dy);
      if (layer.flipY) local = Offset(local.dx, r.top + r.bottom - local.dy);
    }
    var src = placement.src, dst = placement.dst;
    var fx = dst.width == 0 ? 0.0 : (local.dx - dst.left) / dst.width;
    var fy = dst.height == 0 ? 0.0 : (local.dy - dst.top) / dst.height;
    return Offset((src.left + fx * src.width) / size.width,
        (src.top + fy * src.height) / size.height);
  }

  /// fromPicture is the other way: a fraction of the picture, on the canvas.
  Offset fromPicture(Offset f) {
    var src = placement.src, dst = placement.dst;
    var px = Offset(f.dx * size.width, f.dy * size.height);
    var local = Offset(dst.left + (px.dx - src.left) / src.width * dst.width,
        dst.top + (px.dy - src.top) / src.height * dst.height);
    // A picture -- a layer's or the base -- mirrored in its place is
    // mirrored back, so a stroke lands on the pixels under the pointer.
    if (!layer.framed) {
      var r = space.rect;
      if (layer.flipX) local = Offset(r.left + r.right - local.dx, local.dy);
      if (layer.flipY) local = Offset(local.dx, r.top + r.bottom - local.dy);
    }
    return _inFrame ? space.fromFrame(local) : space.fromLayer(local);
  }

  /// canvasPerPixel is how many canvas units one of the picture's pixels is
  /// drawn across.
  double get canvasPerPixel =>
      placement.src.width == 0 ? 1 : placement.dst.width / placement.src.width;

  /// shortSide is the picture's shorter side, in its own pixels -- what a
  /// brush's radius is a fraction of.
  double get shortSide => math.min(size.width, size.height);
}

/// MaskCombine is how a subject that has been found goes into a mask that
/// may have one already.
enum MaskCombine { replace, add, subtract }

/// SubjectFinder asks the operating system for a picture's subject -- see
/// VisionBridge in macos/Runner/MainFlutterWindow.swift.
class SubjectFinder {
  static const _channel = MethodChannel("bruig/vision");
  static bool? _available;

  /// available is whether this machine can find a subject: macOS 14 or
  /// later. Asked once.
  /// known is the answer [available] has already had, if it has had one --
  /// for drawing the button straight away rather than a frame later.
  static bool? get known => _available;

  static Future<bool> available() async {
    var known = _available;
    if (known != null) return known;
    if (kIsWeb || !Platform.isMacOS) return _available = false;
    try {
      return _available =
          await _channel.invokeMethod<bool>("available") ?? false;
    } catch (_) {
      return _available = false;
    }
  }

  /// find is the subject of the picture [assetId] -- every subject, or the
  /// one at [at], a fraction of the picture -- as a grey PNG; null where
  /// there is none to be found. Throws a message fit to show where finding
  /// failed rather than found nothing.
  static Future<Uint8List?> find(String assetId, {Offset? at}) async {
    var path = await CanvasAssets.pathOf(assetId);
    if (path == null) throw "The picture's file could not be found";
    try {
      var found = await _channel.invokeMapMethod<String, dynamic>("subject", {
        "path": path,
        if (at != null) "x": at.dx,
        if (at != null) "y": at.dy,
      });
      var mask = found?["mask"];
      return mask is Uint8List ? mask : null;
    } on PlatformException catch (e) {
      throw e.message ?? "The subject could not be found";
    } on MissingPluginException {
      throw "Finding a subject needs macOS 14 or later";
    }
  }
}

/// decodeMask turns a stored mask's bytes into a picture.
Future<ui.Image> decodeMask(Uint8List bytes) async {
  var codec = await ui.instantiateImageCodec(bytes);
  var frame = await codec.getNextFrame();
  return frame.image;
}

/// _subjectAlpha reads a grey mask as alpha, as image_mask_painter does.
const _greyToAlpha = ColorFilter.matrix([
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  1, 0, 0, 0, 0, //
]);

/// _alphaToGrey writes alpha back out as grey, opaque, which is how a mask
/// is stored: the same file whichever way a viewer treats transparency.
const _alphaToGrey = ColorFilter.matrix([
  0, 0, 0, 1, 0, //
  0, 0, 0, 1, 0, //
  0, 0, 0, 1, 0, //
  0, 0, 0, 0, 255, //
]);

/// maskPng renders whatever [draw] puts down as alpha, over a picture of
/// [size] pixels, into a grey PNG.
Future<Uint8List?> maskPng(Size size, void Function(ui.Canvas) draw) async {
  var w = size.width.round(), h = size.height.round();
  if (w <= 0 || h <= 0) return null;
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
  canvas.saveLayer(null, Paint()..colorFilter = _alphaToGrey);
  draw(canvas);
  canvas.restore();
  var image = await recorder.endRecording().toImage(w, h);
  try {
    var data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// drawGreyAsAlpha draws a grey mask picture as alpha across [size].
void drawGreyAsAlpha(ui.Canvas canvas, ui.Image grey, Size size,
    {BlendMode blend = BlendMode.srcOver}) {
  canvas.drawImageRect(
      grey,
      Offset.zero & Size(grey.width.toDouble(), grey.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = _greyToAlpha
        ..blendMode = blend);
}

/// combinedSubject is [found] put into [mask]'s subject as [how] says, as a
/// grey PNG for a picture of [size] pixels. [current] is the mask's subject
/// decoded, where it has one; where it has none, the whole picture is its
/// subject, as it is drawn.
Future<Uint8List?> combinedSubject(ImageMask mask, ui.Image? current,
    ui.Image found, Size size, MaskCombine how) {
  return maskPng(size, (canvas) {
    if (how != MaskCombine.replace) {
      if (current != null) {
        drawGreyAsAlpha(canvas, current, size);
      } else {
        canvas.drawRect(
            Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
      }
    }
    drawGreyAsAlpha(canvas, found, size,
        blend:
            how == MaskCombine.subtract ? BlendMode.dstOut : BlendMode.srcOver);
  });
}

/// _pixelsOf renders [draw] into a [w] x [h] picture and reads it back as
/// RGBA bytes.
Future<Uint8List> _pixelsOf(int w, int h, void Function(ui.Canvas) draw,
    {bool straight = false}) async {
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  var image = await recorder.endRecording().toImage(w, h);
  try {
    var data = await image.toByteData(
        format: straight
            ? ui.ImageByteFormat.rawStraightRgba
            : ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// _maskSide is the longest a mask made by cutting is kept at. A subject
/// found by the operating system is the picture's own size; one cut here is
/// no sharper than the cut, and a camera's twelve megapixels of it is a
/// slow file for nothing.
const int _maskSide = 3000;

Size _maskSizeFor(Size picture) {
  var longest = math.max(picture.width, picture.height);
  if (longest <= _maskSide) return picture;
  var k = _maskSide / longest;
  return Size((picture.width * k).roundToDouble(),
      (picture.height * k).roundToDouble());
}

/// _cutInto runs [job] off the main thread and lays its answer into a new
/// mask for a picture of [size]: over [base] (drawn first) at [region] of
/// the picture, adding what was found -- or, with [subtract], taking away
/// what was found not to be the subject.
Future<Uint8List?> _cutInto(SegmentJob job, Size size, Rect region,
    {required void Function(ui.Canvas, Size) base,
    required bool subtract}) async {
  var labels = await compute(segment, job);
  var rgba = Uint8List(job.width * job.height * 4);
  for (var i = 0; i < labels.length; i++) {
    var keep = subtract ? 255 - labels[i] : labels[i];
    // White at that alpha, premultiplied: the alpha in every channel.
    rgba[i * 4] = keep;
    rgba[i * 4 + 1] = keep;
    rgba[i * 4 + 2] = keep;
    rgba[i * 4 + 3] = keep;
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, job.width, job.height, ui.PixelFormat.rgba8888, done.complete);
  var found = await done.future;
  var out = _maskSizeFor(size);
  var sx = out.width / size.width, sy = out.height / size.height;
  var into = Rect.fromLTRB(
      region.left * sx, region.top * sy, region.right * sx, region.bottom * sy);
  try {
    return await maskPng(out, (canvas) {
      base(canvas, out);
      // A touch of blur as it is scaled up, so the cut's pixel steps come
      // out as an edge rather than a staircase.
      var soften = math.max(0.5, into.width / job.width * 0.6);
      canvas.saveLayer(
          into.inflate(soften * 3),
          Paint()
            ..blendMode = subtract ? BlendMode.dstOut : BlendMode.srcOver
            ..imageFilter = ui.ImageFilter.blur(
                sigmaX: soften, sigmaY: soften, tileMode: TileMode.decal));
      canvas.drawImageRect(
          found,
          Rect.fromLTWH(0, 0, job.width.toDouble(), job.height.toDouble()),
          into,
          Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    });
  } finally {
    found.dispose();
  }
}

/// quickSelectMask is [mask] with what a quick-select stroke along [stroke]
/// (fractions of [picture]) found added to it -- or, with [subtract], taken
/// out of it -- as a grey PNG: the new subject, with every mark the old mask
/// had worked into it.
///
/// The cut is made round the stroke only, a little more than the stroke's
/// reach either way, as every quick-select brush works: what is brushed is
/// grown to the edges near it, not to the whole picture. A picture whose
/// mask is empty starts with nothing kept, so the first stroke keeps what it
/// went over and its like and nothing else.
Future<Uint8List?> quickSelectMask(ui.Image picture, ImageMask mask,
    ui.Image? subject, List<Offset> stroke, double radius,
    {required bool subtract}) async {
  if (stroke.isEmpty) return null;
  var size = Size(picture.width.toDouble(), picture.height.toDouble());
  var short = math.min(size.width, size.height);
  var reach = radius * short;
  var points = [
    for (var f in stroke) Offset(f.dx * size.width, f.dy * size.height)
  ];
  var box = Rect.fromPoints(points.first, points.first);
  for (var p in points) {
    box = box.expandToInclude(Rect.fromCircle(center: p, radius: reach));
  }
  var region = box
      // Far enough that the thing brushed is usually all inside it: where
      // it is not, the cut stops in a straight line at the region's edge.
      .inflate(math.max(reach * 10, short * 0.3))
      .intersect(Offset.zero & size);
  if (region.isEmpty) return null;
  // Worked on at no more than about four hundred pixels square: a cut's
  // time grows faster than its size, and a brush has to answer at once.
  var k = math.min(1.0, math.sqrt(160000 / (region.width * region.height)));
  var w = math.max(8, (region.width * k).round());
  var h = math.max(8, (region.height * k).round());
  var into = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

  var rgba = await _pixelsOf(w, h, (canvas) {
    canvas.drawImageRect(
        picture, region, into, Paint()..filterQuality = FilterQuality.medium);
  });
  var picked = !mask.empty;
  var current = picked
      ? await _pixelsOf(w, h, (canvas) {
          canvas.scale(w / region.width, h / region.height);
          canvas.translate(-region.left, -region.top);
          canvas.drawPicture(maskPicture(mask, size, subject));
        })
      : null;
  var brushed = await _pixelsOf(w, h, (canvas) {
    canvas.scale(w / region.width, h / region.height);
    canvas.translate(-region.left, -region.top);
    var paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = reach * 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawCircle(
          points.first, reach * 0.6, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(Path()..addPolygon(points, false), paint);
    }
  });

  var n = w * h;
  var seeds = Uint8List(n);
  var prior = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      var kept = current == null ? 0 : current[i * 4 + 3];
      prior[i] = kept;
      var border = x < 2 || y < 2 || x >= w - 2 || y >= h - 2;
      if (brushed[i * 4 + 3] > 127) {
        seeds[i] = subtract ? Seed.background : Seed.subject;
      } else if (border) {
        // The region's edge is held as it is, so the cut cannot run off
        // across the rest of the picture: background where nothing is kept
        // -- and, taking away, the subject where something is.
        seeds[i] = subtract
            ? (kept > 127 ? Seed.subject : Seed.background)
            : (kept > 127 ? Seed.unknown : Seed.background);
      }
    }
  }
  var job = SegmentJob(
      rgba: rgba,
      width: w,
      height: h,
      seeds: seeds,
      prior: picked ? prior : null,
      rounds: 2);
  return _cutInto(job, size, region, subtract: subtract, base: (canvas, out) {
    if (!picked) {
      if (subtract) {
        canvas.drawRect(
            Offset.zero & out, Paint()..color = const Color(0xFFFFFFFF));
      }
      return;
    }
    canvas.save();
    canvas.scale(out.width / size.width, out.height / size.height);
    canvas.drawPicture(maskPicture(mask, size, subject));
    canvas.restore();
  });
}

/// guessSubjectMask finds a picture's subject by colour and edge alone, for
/// a machine whose operating system cannot: the picture's border taken to
/// be background and its middle to be the subject, and the cut left to work
/// out where between the two the edge is -- or, given [at], the subject
/// taken to be what is there. Rougher than the operating system's, and
/// meant to be finished with the brush.
Future<Uint8List?> guessSubjectMask(ui.Image picture, {Offset? at}) async {
  var size = Size(picture.width.toDouble(), picture.height.toDouble());
  var k = math.min(1.0, math.sqrt(90000 / (size.width * size.height)));
  var w = math.max(8, (size.width * k).round());
  var h = math.max(8, (size.height * k).round());
  var rgba = await _pixelsOf(w, h, (canvas) {
    canvas.drawImageRect(
        picture,
        Offset.zero & size,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.medium);
  });
  var n = w * h;
  var seeds = Uint8List(n);
  var prior = Uint8List(n);
  var band = math.max(2, (math.min(w, h) * 0.03).round());
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      if (x < band || y < band || x >= w - band || y >= h - band) {
        seeds[i] = Seed.background;
        continue;
      }
      if (at != null) {
        var d = Offset(x / w - at.dx, y / h - at.dy).distance;
        if (d < 0.04) seeds[i] = Seed.subject;
        prior[i] = d < 0.25 ? 255 : 0;
      } else {
        var inset = x > w * 0.2 && x < w * 0.8 && y > h * 0.15 && y < h * 0.95;
        prior[i] = inset ? 255 : 0;
      }
    }
  }
  var job = SegmentJob(
      rgba: rgba, width: w, height: h, seeds: seeds, prior: prior, rounds: 5);
  return _cutInto(job, size, Offset.zero & size,
      subtract: false, base: (_, __) {});
}

/// _alphaImage is one byte a pixel of alpha as a picture -- white at that
/// alpha -- for drawing back into a mask.
Future<ui.Image> _alphaImage(Uint8List alpha, int w, int h) {
  var rgba = Uint8List(w * h * 4);
  for (var i = 0; i < alpha.length; i++) {
    var a = alpha[i];
    rgba[i * 4] = a;
    rgba[i * 4 + 1] = a;
    rgba[i * 4 + 2] = a;
    rgba[i * 4 + 3] = a;
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// refineEdgeMask is [mask] with its edge worked out afresh wherever a
/// refining stroke along [stroke] (fractions of [picture]) went -- hair
/// strands and soft edges given the alpha their colours say they have -- as
/// a grey PNG: the new subject, with the old mask's marks worked into it.
/// Nothing outside the stroke changes, at whatever size the mask is kept.
Future<Uint8List?> refineEdgeMask(ui.Image picture, ImageMask mask,
    ui.Image? subject, List<Offset> stroke, double radius) async {
  if (stroke.isEmpty) return null;
  var size = Size(picture.width.toDouble(), picture.height.toDouble());
  var short = math.min(size.width, size.height);
  var reach = radius * short;
  var points = [
    for (var f in stroke) Offset(f.dx * size.width, f.dy * size.height)
  ];
  var box = Rect.fromCircle(center: points.first, radius: reach);
  for (var p in points) {
    box = box.expandToInclude(Rect.fromCircle(center: p, radius: reach));
  }
  var region = box.inflate(reach * 3).intersect(Offset.zero & size);
  if (region.isEmpty) return null;
  // Finer than a cut: hair is a pixel or two across.
  var k = math.min(1.0, math.sqrt(360000 / (region.width * region.height)));
  var w = math.max(8, (region.width * k).round());
  var h = math.max(8, (region.height * k).round());
  void inRegion(ui.Canvas canvas) {
    canvas.scale(w / region.width, h / region.height);
    canvas.translate(-region.left, -region.top);
  }

  var rgba = await _pixelsOf(w, h, (canvas) {
    inRegion(canvas);
    canvas.drawImage(
        picture, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
  }, straight: true);
  var current = await _pixelsOf(w, h, (canvas) {
    inRegion(canvas);
    canvas.drawPicture(maskPicture(mask, size, subject));
  });
  var brushed = await _pixelsOf(w, h, (canvas) {
    inRegion(canvas);
    var paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = reach * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      // Soft at its rim, so the refined band blends into the rest.
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, reach * 0.15);
    if (points.length == 1) {
      canvas.drawCircle(points.first, reach, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(Path()..addPolygon(points, false), paint);
    }
  });
  var n = w * h;
  var alpha = Uint8List(n), band = Uint8List(n);
  for (var i = 0; i < n; i++) {
    alpha[i] = current[i * 4 + 3];
    band[i] = brushed[i * 4 + 3];
  }
  var refined = await compute(
      refineAlpha,
      RefineJob(
          rgba, alpha, band, w, h, math.max(3, (reach * k * 1.5).round())));
  // What goes back in: the new alpha's share of each pixel, the brush's
  // share of it -- the rest is the mask as it was, at its own sharpness.
  var share = Uint8List(n);
  for (var i = 0; i < n; i++) {
    var b = band[i] / 255;
    share[i] = (refined[i] - alpha[i] * (1 - b)).round().clamp(0, 255);
  }
  var bandImage = await _alphaImage(band, w, h);
  var shareImage = await _alphaImage(share, w, h);
  var out = _maskSizeFor(size);
  var sx = out.width / size.width, sy = out.height / size.height;
  var into = Rect.fromLTRB(
      region.left * sx, region.top * sy, region.right * sx, region.bottom * sy);
  var from = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  try {
    return await maskPng(out, (canvas) {
      canvas.save();
      canvas.scale(sx, sy);
      canvas.drawPicture(maskPicture(mask, size, subject));
      canvas.restore();
      var paint = Paint()..filterQuality = FilterQuality.medium;
      canvas.drawImageRect(
          bandImage, from, into, paint..blendMode = BlendMode.dstOut);
      canvas.drawImageRect(
          shareImage, from, into, paint..blendMode = BlendMode.plus);
    });
  } finally {
    bandImage.dispose();
    shareImage.dispose();
  }
}

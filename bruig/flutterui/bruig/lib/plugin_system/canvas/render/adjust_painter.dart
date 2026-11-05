import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// adjust_painter.dart draws what is under an adjustment layer through it --
// see image_adjustment.dart and shaders/adjust.frag.
//
// Where the engine can (Impeller), the shader is an image filter over the
// layers below as they are drawn. Otherwise the layers below are rasterised
// at the canvas's drawing scale, drawn through the shader, and the result
// kept in the RasterCache.

/// AdjustShader is the adjustment layers' shader, loaded once.
class AdjustShader {
  static ui.FragmentProgram? _program;
  static bool _unloadable = false;

  /// ready says the shader is loaded. Until it is, adjustment layers draw
  /// what is under them unadjusted.
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  /// load reads the shader, once.
  static Future<void> load() async {
    // The program, not the loading, is what is kept: a load begun
    // where it never finishes (a test's own time, gone) would leave
    // every later wait for it waiting for ever.
    if (_program != null || _unloadable) return;
    try {
      _program = await ui.FragmentProgram.fromAsset("shaders/adjust.frag");
      ready.value = true;
    } catch (exception) {
      _unloadable = true;
      debugPrint("The adjustment shader did not load: $exception");
    }
  }
}

/// _lutOf is the 256-across strip a curve or a gradient map is read from.
/// Only the last [_lutsKept] are kept, disposed as they fall out: a slider
/// drag makes a new adjustment every step.
final List<(ImageAdjustment, ui.Image)> _luts = [];
const int _lutsKept = 6;

ui.Image _lutOf(ImageAdjustment adjust) {
  for (var (a, image) in _luts) {
    if (identical(a, adjust)) return image;
  }
  CanvasPerf.count("lut");
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  Color at(double x) {
    switch (adjust.kind) {
      case AdjustKind.curves:
        // Each channel through the whole-picture curve, then its own.
        var master = curveAt(adjust.curve(CurveChannel.rgb), x);
        double channel(CurveChannel c) =>
            curveAt(adjust.curve(c), master).clamp(0.0, 1.0);
        return Color.from(
            alpha: 1,
            red: channel(CurveChannel.red),
            green: channel(CurveChannel.green),
            blue: channel(CurveChannel.blue));
      case AdjustKind.gradientMap:
        var fade = adjust.fade;
        if (!fade.fades) return fade.color;
        var (colours, places) = fade.rampFor();
        for (var i = 0; i < places.length - 1; i++) {
          if (x <= places[i + 1]) {
            var span = places[i + 1] - places[i];
            var t = span <= 0 ? 0.0 : (x - places[i]) / span;
            return Color.lerp(colours[i], colours[i + 1], t.clamp(0.0, 1.0))!;
          }
        }
        return colours.last;
      default:
        return Color.from(alpha: 1, red: x, green: x, blue: x);
    }
  }

  for (var i = 0; i < 256; i++) {
    canvas.drawRect(
        Rect.fromLTWH(i.toDouble(), 0, 1, 1), Paint()..color = at(i / 255));
  }
  var picture = recorder.endRecording();
  var image = picture.toImageSync(256, 1);
  picture.dispose();
  _luts.add((adjust, image));
  while (_luts.length > _lutsKept) {
    _luts.removeAt(0).$2.dispose();
  }
  return image;
}

/// _uniforms is [adjust] as the shader's three vectors.
List<double> _uniforms(ImageAdjustment a) {
  double v(String key) => a.value(key);
  var c = a.colour;
  switch (a.kind) {
    case AdjustKind.brightness:
      return [v("brightness"), v("contrast"), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.levels:
      return [
        v("inBlack"), v("inWhite"), v("gamma"), 0, //
        v("outBlack"), v("outWhite"), 0, 0, //
        0, 0, 0, 0,
      ];
    case AdjustKind.exposure:
      return [v("stops"), v("offset"), v("gamma"), 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.hueSaturation:
      return [
        v("hue") / 360, v("saturation"), v("lightness"), v("colourise"), //
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
    case AdjustKind.vibrance:
      return [v("vibrance"), v("saturation"), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.temperature:
      return [v("warmth"), v("tint"), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.photoFilter:
      return [
        // Keeping the brightness is where a photo filter starts.
        v("density"), a.values["keepLight"] ?? 1, 0, 0, //
        c.r, c.g, c.b, 0, //
        0, 0, 0, 0,
      ];
    case AdjustKind.keepColour:
      return [
        HSLColor.fromColor(c).hue / 360, v("width"), v("softness"),
        v("amount"), //
        0, 0, 0, 0, 0, 0, 0, 0,
      ];
    case AdjustKind.blackWhite:
      return [
        v("red"), v("green"), v("blue"), 0, //
        c.r, c.g, c.b, v("tint"), //
        0, 0, 0, 0,
      ];
    case AdjustKind.posterise:
      return [v("levels"), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.threshold:
      return [v("level"), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    case AdjustKind.curves || AdjustKind.gradientMap || AdjustKind.invert:
      return List.filled(12, 0);
  }
}

/// paintAdjusted draws [below] -- a picture of what is under the adjustment,
/// covering [room] in [canvas]'s units -- through [adjust]. [key] names the
/// result so it can be kept, drawn from [from] -- see raster_cache.dart;
/// null keeps nothing, for a picture still waiting on something to load.
void paintAdjusted(
    ui.Canvas canvas, Rect room, ImageAdjustment adjust, ui.Picture below,
    {String? key, List<Object?> from = const []}) {
  var program = AdjustShader._program;
  if (program == null || room.isEmpty) {
    canvas.drawPicture(below);
    return;
  }
  // A filter where the engine can: far cheaper than rasterising what is
  // under.
  if (_adjustFilter(program, adjust) case var filter?) {
    CanvasPerf.count("adjust (filter)");
    canvas.saveLayer(room, Paint()..imageFilter = filter);
    canvas.drawPicture(below);
    canvas.restore();
    return;
  }
  CanvasPerf.count(key == null ? "adjust (not kept)" : "adjust");
  var scale = deviceScaleOf(canvas);
  // At most 4096 on a side and 16 megapixels.
  var most = math.min(4096 / math.max(room.width, room.height),
      math.sqrt(16e6 / (room.width * room.height)));
  if (RasterCache.drafting) {
    most = math.min(
        most, RasterCache.draftSide / math.max(room.width, room.height));
  }
  scale = math.max(0.05, math.min(scale, most));
  var w = math.max(1, (room.width * scale).ceil());
  var h = math.max(1, (room.height * scale).ceil());
  // Keyed by layer, not position, so moving does not re-rasterise.
  var made = key == null
      ? null
      : RasterCache.instance.sized(key, [adjust, room.size, ...from], w, h);
  if (made == null) {
    // What is under is cached separately, so dragging a slider does not
    // redraw it.
    var underFrom = [room.size, ...from];
    var under = key == null
        ? null
        : RasterCache.instance.sized("$key|under", underFrom, w, h);
    var keptUnder = under != null;
    if (under == null) {
      CanvasPerf.count("adjustUnder ${w}x$h");
      var recorder = ui.PictureRecorder();
      var raster = ui.Canvas(recorder);
      raster.scale(w / room.width, h / room.height);
      raster.translate(-room.left, -room.top);
      raster.drawPicture(below);
      var picture = recorder.endRecording();
      under = picture.toImageSync(w, h);
      picture.dispose();
      if (key != null) {
        RasterCache.instance.putSized("$key|under", underFrom, under);
        keptUnder = true;
      }
    }

    CanvasPerf.count("adjustMade");
    var u = _uniforms(adjust);
    var shader = program.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setFloat(2, 0)
      ..setFloat(3, 0)
      ..setFloat(4, adjust.kind.mode.toDouble());
    for (var i = 0; i < 12; i++) {
      shader.setFloat(5 + i, u[i]);
    }
    shader
      ..setImageSampler(0, under)
      ..setImageSampler(1, _lutOf(adjust));
    var out = ui.PictureRecorder();
    ui.Canvas(out).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..shader = shader);
    var adjusted = out.endRecording();
    made = adjusted.toImageSync(w, h);
    adjusted.dispose();
    shader.dispose();
    if (!keptUnder) under.dispose();
    if (key != null) {
      RasterCache.instance.putSized(key, [adjust, room.size, ...from], made);
    } else {
      _loose.add(made);
      while (_loose.length > 8) {
        _loose.removeAt(0).dispose();
      }
    }
  }
  canvas.drawImageRect(
      made,
      Rect.fromLTWH(0, 0, made.width.toDouble(), made.height.toDouble()),
      room,
      Paint()..filterQuality = FilterQuality.medium);
}

/// paintAdjustedLive draws what [body] draws through [adjust], over [room],
/// caching nothing: for a moving layer whose picture changes every frame.
void paintAdjustedLive(ui.Canvas canvas, Rect room, ImageAdjustment adjust,
    void Function(ui.Canvas) body) {
  var program = AdjustShader._program;
  if (program != null) {
    if (_adjustFilter(program, adjust) case var filter?) {
      canvas.saveLayer(room, Paint()..imageFilter = filter);
      body(canvas);
      canvas.restore();
      return;
    }
  }
  var recorder = ui.PictureRecorder();
  body(ui.Canvas(recorder));
  var picture = recorder.endRecording();
  paintAdjusted(canvas, room, adjust, picture);
  picture.dispose();
}

/// _filters is the last few adjustment filters made, by adjustment.
final List<(ImageAdjustment, ui.ImageFilter)> _filters = [];

/// adjustsByFilter is whether adjustments are being drawn as image filters
/// -- nothing rasterised, nothing kept -- rather than into kept pictures.
bool get adjustsByFilter => _filtering == true;

/// adjustSteadily is set while a picture is drawn moving (drifting closer or
/// across), so adjustments are rasterised and the pixels moved instead of
/// using a filter. A filter snaps to whole screen pixels, so under a
/// changing zoom it shakes by a pixel.
bool adjustSteadily = false;

/// _filtering is whether the engine can draw a shader as an image filter
/// (Impeller can), found out the first time it is asked.
bool? _filtering;

/// _adjustFilter is [adjust] as an image filter, or null where the engine
/// cannot draw one and the adjustment is drawn into a picture instead.
ui.ImageFilter? _adjustFilter(
    ui.FragmentProgram program, ImageAdjustment adjust) {
  if (_filtering == false || adjustSteadily) return null;
  for (var (a, f) in _filters) {
    if (identical(a, adjust)) return f;
  }
  var u = _uniforms(adjust);
  // The size, floats 0 and 1, and the picture under, sampler 0, are the
  // engine's to set.
  var shader = program.fragmentShader()
    ..setFloat(2, 0)
    ..setFloat(3, 0)
    ..setFloat(4, adjust.kind.mode.toDouble());
  for (var i = 0; i < 12; i++) {
    shader.setFloat(5 + i, u[i]);
  }
  shader.setImageSampler(1, _lutOf(adjust));
  ui.ImageFilter filter;
  try {
    filter = ui.ImageFilter.shader(shader);
  } on UnsupportedError {
    _filtering = false;
    shader.dispose();
    return null;
  }
  _filtering = true;
  _filters.add((adjust, filter));
  // Not disposed: drawn pictures may still use them.
  while (_filters.length > _lutsKept) {
    _filters.removeAt(0);
  }
  return filter;
}

/// _loose is adjusted pictures with no cache key (drawn over things still
/// loading), held briefly until drawn.
final List<ui.Image> _loose = [];

/// clearAdjustedRasters lets go of the adjustments' unkeyed pictures.
void clearAdjustedRasters() {
  for (var image in _loose) {
    image.dispose();
  }
  _loose.clear();
}

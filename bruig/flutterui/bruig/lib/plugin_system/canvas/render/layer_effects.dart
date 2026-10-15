import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// layer_effects.dart draws a texture layer -- see shaders/texture.frag -- and
// a layer with its effects: a shadow and a glow under it, a blur through it,
// an inner shadow over it. See image_effects.dart for the settings.
//
// Shadows, glows and plain blurs are the compositor's: a layer with a blur
// on it. Motion and zoom blurs and the colour fringe are the same picture
// drawn several times, shifted or scaled, so the layer is rasterised once
// for them -- at the size the canvas is drawn at -- and kept against the
// element, as an adjustment's result is.

class TextureShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  static Future<void> load() => _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset("shaders/texture.frag");
          ready.value = true;
        } catch (exception) {
          debugPrint("The texture shader did not load: $exception");
        }
      }();
}

/// paintTexture draws [spec] across [frame].
void paintTexture(ui.Canvas canvas, Rect frame, TextureSpec spec) {
  var program = TextureShader._program;
  if (program == null || frame.isEmpty) return;
  var unit = math.min(frame.width, frame.height) / 1000;
  var a = [for (var p in spec.kind.params) spec.value(p.key)];
  while (a.length < 4) {
    a.add(0);
  }
  var c = spec.colour, s = spec.second;
  var floats = <double>[
    frame.left, frame.top, frame.width, frame.height, //
    spec.kind.mode.toDouble(),
    // Never a whole number: a hash fed whole numbers repeats itself.
    spec.seed * 1.618 + 0.37,
    unit,
    ...a.take(4),
    c.r, c.g, c.b, c.a, //
    s.r, s.g, s.b, s.a,
  ];
  var shader = program.fragmentShader();
  for (var (i, v) in floats.indexed) {
    shader.setFloat(i, v);
  }
  canvas.drawRect(frame, Paint()..shader = shader);
  shader.dispose();
}

/// _scaleOf is how many device pixels one unit of [canvas] is drawn across.
double _scaleOf(ui.Canvas canvas) {
  var m = canvas.getTransform();
  var sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  var sy = math.sqrt(m[4] * m[4] + m[5] * m[5]);
  var dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
  return math.max(sx, sy) * math.max(1.0, dpr);
}

final Expando<Map<String, ui.Image>> _rasters = Expando("effectRasters");
final List<ui.Image> _loose = [];

/// _raster is [content] -- covering [room] -- as pixels at the size [canvas]
/// is drawn at, kept against [owner] under [key] where there is an owner.
(ui.Image, Rect) _raster(ui.Canvas canvas, Rect room, ui.Picture content,
    Object? owner, String key) {
  var scale = _scaleOf(canvas);
  var most = math.min(4096 / math.max(room.width, room.height),
      math.sqrt(16e6 / (room.width * room.height)));
  scale = math.max(0.05, math.min(scale, most));
  var w = math.max(1, (room.width * scale).ceil());
  var h = math.max(1, (room.height * scale).ceil());
  var src = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  var name = "$key|$w|$h|$room";
  var cache = owner == null ? null : (_rasters[owner] ??= {});
  var made = cache?[name];
  if (made != null) return (made, src);
  var recorder = ui.PictureRecorder();
  var raster = ui.Canvas(recorder);
  raster.scale(w / room.width, h / room.height);
  raster.translate(-room.left, -room.top);
  raster.drawPicture(content);
  made = recorder.endRecording().toImageSync(w, h);
  if (cache != null) {
    if (cache.length > 6) cache.remove(cache.keys.first)?.dispose();
    cache[name] = made;
  } else {
    _loose.add(made);
    while (_loose.length > 8) {
      _loose.removeAt(0).dispose();
    }
  }
  return (made, src);
}

/// _towards is the offset [distance] along [angle] degrees -- the way a
/// light at that angle throws a shadow: 135 is a light up and to the left,
/// and a shadow down and to the right.
Offset _towards(double angle, double distance) {
  var t = angle * math.pi / 180;
  return Offset(-math.cos(t) * distance, math.sin(t) * distance);
}

ui.ImageFilter? _chain(List<ui.ImageFilter> filters) {
  if (filters.isEmpty) return null;
  var f = filters.first;
  for (var next in filters.skip(1)) {
    f = ui.ImageFilter.compose(outer: next, inner: f);
  }
  return f;
}

/// paintWithEffects draws [content] -- a layer, covering [room] -- with
/// [effects], [unit] canvas units to a thousandth of the frame's shorter
/// side. [owner] and [key] name what is rasterised, so it is kept.
void paintWithEffects(ui.Canvas canvas, Rect room, double unit,
    List<LayerEffect> effects, ui.Picture content,
    {Object? owner, String key = ""}) {
  var on = [
    for (var f in effects)
      if (f.on) f
  ];
  var reach = room.inflate(room.shortestSide);

  // Under the layer: its shadow and its glow, its own shape in one colour.
  for (var f in on.where((f) => f.kind.behind)) {
    var colour = f.colour.withValues(alpha: f.colour.a * f.value("opacity"));
    var spread = f.value("spread") * unit;
    var sigma =
        (f.kind == EffectKind.dropShadow ? f.value("blur") : f.value("size")) *
            unit /
            2;
    canvas.saveLayer(
        reach,
        Paint()
          ..colorFilter = ColorFilter.mode(colour, BlendMode.srcIn)
          ..imageFilter = _chain([
            if (spread > 0.05)
              ui.ImageFilter.dilate(radiusX: spread, radiusY: spread),
            if (sigma > 0.05)
              ui.ImageFilter.blur(
                  sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          ]));
    if (f.kind == EffectKind.dropShadow) {
      var d = _towards(f.value("angle"), f.value("distance") * unit);
      canvas.translate(d.dx, d.dy);
    }
    canvas.drawPicture(content);
    canvas.restore();
  }

  // The layer itself, blurred if it is, in a layer of its own so an inner
  // shadow lands on it and not on the shadow under it.
  var blur = on
      .where((f) => f.kind == EffectKind.blur)
      .fold<double>(0, (s, f) => s + f.value("amount") * unit / 2);
  canvas.saveLayer(
      reach,
      Paint()
        ..imageFilter = blur > 0.05
            ? ui.ImageFilter.blur(
                sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal)
            : null);
  var copies = on.where((f) =>
      f.kind == EffectKind.motionBlur ||
      f.kind == EffectKind.zoomBlur ||
      f.kind == EffectKind.fringe);
  if (copies.isEmpty) {
    canvas.drawPicture(content);
  } else {
    var (image, src) = _raster(canvas, room, content, owner, key);
    _paintCopies(canvas, room, unit, copies.toList(), image, src);
  }
  for (var f in on.where((f) => f.kind == EffectKind.innerShadow)) {
    var colour = f.colour.withValues(alpha: f.colour.a * f.value("opacity"));
    var d = _towards(f.value("angle"), f.value("distance") * unit);
    var sigma = f.value("blur") * unit / 2;
    // Only on the layer: the colour everywhere, with the layer's own shape
    // -- moved and softened -- cut out of it, laid on where the layer is.
    canvas.saveLayer(reach, Paint()..blendMode = BlendMode.srcATop);
    canvas.drawRect(reach, Paint()..color = colour);
    canvas.saveLayer(
        reach,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..imageFilter = sigma > 0.05
              ? ui.ImageFilter.blur(
                  sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal)
              : null);
    canvas.translate(d.dx, d.dy);
    canvas.drawPicture(content);
    canvas.restore();
    canvas.restore();
  }
  canvas.restore();
}

/// _paintCopies draws [image] -- the layer, rasterised over [room] -- as
/// the copies its motion blur, zoom blur and fringe make of it, averaged.
void _paintCopies(ui.Canvas canvas, Rect room, double unit,
    List<LayerEffect> effects, ui.Image image, Rect src) {
  // Every copy of each effect, as where it goes and how it is coloured.
  var copies = <(Rect, ColorFilter?)>[(room, null)];
  for (var f in effects) {
    var next = <(Rect, ColorFilter?)>[];
    switch (f.kind) {
      case EffectKind.motionBlur:
        var d = _towards(f.value("angle") + 180, f.value("distance") * unit);
        var n = (d.distance / (unit * 4)).clamp(6, 32).round();
        for (var (r, c) in copies) {
          for (var i = 0; i < n; i++) {
            var t = n == 1 ? 0.0 : i / (n - 1) - 0.5;
            next.add((r.shift(d * t), c));
          }
        }
      case EffectKind.zoomBlur:
        var amount = f.value("amount");
        var centre = Offset(room.left + room.width * f.value("x"),
            room.top + room.height * f.value("y"));
        var n = (amount * 60).clamp(6, 32).round();
        for (var (r, c) in copies) {
          for (var i = 0; i < n; i++) {
            var k = 1 + amount * i / math.max(1, n - 1);
            next.add((
              Rect.fromLTRB(
                  centre.dx + (r.left - centre.dx) * k,
                  centre.dy + (r.top - centre.dy) * k,
                  centre.dx + (r.right - centre.dx) * k,
                  centre.dy + (r.bottom - centre.dy) * k),
              c
            ));
          }
        }
      case EffectKind.fringe:
        var d = _towards(f.value("angle"), f.value("distance") * unit);
        for (var (r, _) in copies) {
          next.add((r.shift(d), _channel(0)));
          next.add((r, _channel(1)));
          next.add((r.shift(-d), _channel(2)));
        }
      default:
        next = copies;
    }
    copies = next;
  }
  // A fringe's three copies add up to one picture; the blurs' copies are
  // averaged. Plus blending sums them; each blur copy brings its share.
  var fringes = effects.where((f) => f.kind == EffectKind.fringe).length;
  var share = 1 / (copies.length / math.pow(3, fringes));
  canvas.saveLayer(room.inflate(room.shortestSide), Paint());
  for (var (r, c) in copies) {
    canvas.drawImageRect(
        image,
        src,
        r,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.plus
          ..colorFilter = c
          ..color = Color.fromRGBO(0, 0, 0, share.clamp(0.0, 1.0)));
  }
  canvas.restore();
}

/// _channel keeps one colour channel of a picture, with all of its alpha:
/// a colour at no alpha is no colour at all once it is premultiplied. Laid
/// back together, the three are the picture again where it is solid; at a
/// soft edge their alphas add, which the plus blend holds at one.
ColorFilter _channel(int which) => ColorFilter.matrix([
      which == 0 ? 1 : 0, 0, 0, 0, 0, //
      0, which == 1 ? 1 : 0, 0, 0, 0, //
      0, 0, which == 2 ? 1 : 0, 0, 0, //
      0, 0, 0, 1, 0, //
    ]);

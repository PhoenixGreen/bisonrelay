import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// brush_painter.dart draws brushwork -- see image_strokes.dart: a paint
// layer's strokes, and the retouching done to a picture.
//
// Every stroke is dabs: a soft round mark every fifth of the brush along the
// path, each as wide as the pen was pressed there. Paint is the dabs in its
// colour; every retouching stroke is something drawn -- the picture moved,
// blurred, lightened -- and kept only where the dabs are.

/// paintDabs lays [points] (in [canvas]'s units) down as dabs, [radius]
/// across at full pressure, with [paint]'s colour, in the shape and the way
/// [tip] says -- see BrushTip. [tilt] is the pen's lean at each point;
/// [seed] fixes the scatter and the grain, so a stroke drawn again comes out
/// the same.
void paintDabs(ui.Canvas canvas, List<Offset> points, List<double> pressure,
    double radius, double hardness, Paint paint,
    {BrushTip tip = const BrushTip(),
    List<Offset> tilt = const [],
    int seed = 0}) {
  if (points.isEmpty || radius <= 0) return;
  var soft = (1 - hardness).clamp(0.0, 1.0);
  double pressureAt(int i) {
    if (pressure.isEmpty) return 1;
    var p = pressure[math.min(i, pressure.length - 1)];
    return tip.pressureCurve == 1
        ? p
        : math.pow(p.clamp(0.0, 1.0), tip.pressureCurve).toDouble();
  }

  Offset tiltAt(int i) =>
      tilt.isEmpty ? Offset.zero : tilt[math.min(i, tilt.length - 1)];

  // The size a dab is at a pressure and a lean: a light touch thins it by
  // as much as the tip says, a pen laid over widens it.
  double sizeAt(double p, Offset t) =>
      radius *
      (1 - tip.pressureSize * (1 - p)) *
      (1 + tip.tiltSize * math.min(1.0, t.distance));

  // A number in 0..1 for the n-th dab, the same every time for one seed.
  double noise(int n, int salt) {
    var v = math.sin(n * 12.9898 + salt * 78.233 + seed * 0.618) * 43758.5453;
    return v - v.floorToDouble();
  }

  var n = 0;
  void dab(Offset c, double p, Offset t) {
    n++;
    var r = sizeAt(p, t);
    if (r <= 0.2) return;
    var alpha = 1 - tip.pressureOpacity * (1 - p);
    if (tip.pressureOpacity > 0 && alpha < 1) {
      // Dabs overlap -- about two over the spacing of them at any spot --
      // and overlapping, a light dab builds back to solid. Each is laid
      // down as strong as it must be for the ones over a spot to come to
      // what the touch asked for: what a paint program calls flow.
      var over = (2 / tip.spacing).clamp(1.0, 60.0);
      alpha = 1 - math.pow(1 - alpha, 1 / over).toDouble();
    }
    var at = c;
    if (tip.scatter > 0) {
      var a = noise(n, 3) * math.pi * 2;
      var d = noise(n, 4) * tip.scatter * r;
      at = c + Offset(math.cos(a), math.sin(a)) * d;
    }
    var sigma = r * soft * 0.35;
    var dabPaint = Paint()
      ..color = paint.color.withValues(alpha: paint.color.a * alpha)
      ..blendMode = paint.blendMode;
    if (sigma > 0.3) {
      dabPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    var body = math.max(0.5, r - sigma);
    if (tip.grain > 0) {
      // Grain: the dab as specks where the paper's tooth catches it, fewer
      // the coarser the grain -- a solid dab under its neighbours left no
      // gaps however many were dropped.
      // How much of a dab is specks: enough that, with the dabs over a spot
      // -- about two over the spacing -- the paper shows through as much as
      // the grain says, whatever size the stroke is drawn at.
      var over = (2 / tip.spacing).clamp(1.0, 60.0);
      var paper = tip.grain * 0.8;
      var share = 1 - math.pow(paper, 1 / over).toDouble();
      var area = share * body * body * tip.roundness;
      var specks = (area / 0.36).floor().clamp(1, 40);
      var speck = math.sqrt(area / specks);
      var lean = t.distance;
      var angle = tip.followTilt && lean > 0.05
          ? math.atan2(t.dy, t.dx) + math.pi / 2
          : tip.angle * math.pi / 180;
      var ca = math.cos(angle), sa = math.sin(angle);
      for (var k = 0; k < specks; k++) {
        var a = noise(n * 97 + k, 5) * math.pi * 2;
        var d = math.sqrt(noise(n * 97 + k, 6)) * body;
        var x = math.cos(a) * d, y = math.sin(a) * d * tip.roundness;
        canvas.drawCircle(
            at + Offset(x * ca - y * sa, x * sa + y * ca), speck, dabPaint);
      }
      return;
    }
    if (tip.roundness >= 0.999) {
      canvas.drawCircle(at, body, dabPaint);
      return;
    }
    // A flat nib: an oval, laid at the tip's angle -- or the way the pen
    // leans, where it follows the pen and the pen says.
    var lean = t.distance;
    var angle = tip.followTilt && lean > 0.05
        ? math.atan2(t.dy, t.dx) + math.pi / 2
        : tip.angle * math.pi / 180;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset.zero,
            width: body * 2,
            height: math.max(1.0, body * 2 * tip.roundness)),
        dabPaint);
    canvas.restore();
  }

  dab(points.first, pressureAt(0), tiltAt(0));
  for (var i = 1; i < points.length; i++) {
    var a = points[i - 1], b = points[i];
    var pa = pressureAt(i - 1), pb = pressureAt(i);
    var ta = tiltAt(i - 1), tb = tiltAt(i);
    var least = math.min(sizeAt(pa, ta), sizeAt(pb, tb));
    // A flat nib is spaced by its thin side, or it leaves a dotted line.
    var across = least * math.min(1.0, math.max(tip.roundness, 0.15));
    var gap = math.max(0.5, across * tip.spacing);
    var steps = ((b - a).distance / gap).ceil();
    for (var s = 1; s <= steps; s++) {
      var t = s / steps;
      dab(Offset.lerp(a, b, t)!, pa + (pb - pa) * t, Offset.lerp(ta, tb, t)!);
    }
  }
}

/// _strokeBounds is the area a stroke can touch, in the units its points
/// are given in.
Rect _strokeBounds(List<Offset> points, double radius) {
  var box = Rect.fromCircle(center: points.first, radius: radius);
  for (var p in points) {
    box = box.expandToInclude(Rect.fromCircle(center: p, radius: radius));
  }
  return box.inflate(radius * 0.5);
}

/// _paintStroke draws one paint or erase stroke into a space of [size].
void _paintStroke(ui.Canvas canvas, StrokeMark s, Size size) {
  if (s.points.isEmpty) return;
  var short = math.min(size.width, size.height);
  var points = [
    for (var p in s.points) Offset(p.dx * size.width, p.dy * size.height)
  ];
  var radius = s.radius * short;
  // What the tip can reach beyond the brush's own size: leant over, and
  // thrown off the line.
  var reach = radius * (1 + s.tip.tiltSize) * (1 + s.tip.scatter);
  // A layer per stroke: its opacity is the layer's, so its dabs build up to
  // it and no further.
  canvas.saveLayer(
      _strokeBounds(points, reach),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, s.strength)
        ..blendMode =
            s.kind == StrokeKind.erase ? BlendMode.dstOut : BlendMode.srcOver);
  paintDabs(
      canvas,
      points,
      s.pressure,
      radius,
      s.hardness,
      Paint()
        ..color =
            s.kind == StrokeKind.erase ? const Color(0xFFFFFFFF) : s.colour,
      tip: s.tip,
      tilt: s.tilt,
      seed: (s.points.first.dx * 100003 + s.points.first.dy * 7919).round());
  canvas.restore();
}

/// _Painted is a paint layer's strokes as they were last drawn: all but the
/// last flattened into a picture, so the stroke being drawn costs its own
/// dabs and nothing more.
class _Painted {
  final List<StrokeMark> settled;
  final Size size;
  final ui.Picture picture;
  final ui.Image? raster;
  _Painted(this.settled, this.size, this.picture, this.raster);
}

final Map<String, _Painted> _painted = {};

/// _side is how big a paint layer is flattened at, on its longer side.
const double _side = 2048;

/// paintPaintLayer draws [strokes] -- a paint layer's, in fractions of the
/// frame -- across [frame]. [key] names the layer, so what is drawn can be
/// kept for the next frame.
void paintPaintLayer(
    ui.Canvas canvas, Rect frame, List<StrokeMark> strokes, String key) {
  // Retouching on a paint layer is drawn from what is under it -- see
  // paintRetouchUnder -- not laid down as colour.
  if (strokes.any((s) => s.kind.retouches)) {
    strokes = [
      for (var s in strokes)
        if (!s.kind.retouches) s
    ];
  }
  if (strokes.isEmpty || frame.isEmpty) return;
  var aspect = frame.width / frame.height;
  var size = aspect >= 1
      ? Size(_side, (_side / aspect).roundToDouble())
      : Size((_side * aspect).roundToDouble(), _side);
  var settled = strokes.sublist(0, strokes.length - 1);
  var kept = _painted[key];
  var reusable = kept != null &&
      kept.size == size &&
      kept.settled.length <= settled.length &&
      _samePrefix(kept.settled, settled);
  if (!reusable || kept.settled.length != settled.length) {
    var recorder = ui.PictureRecorder();
    var c = ui.Canvas(recorder);
    var from = 0;
    if (reusable) {
      c.drawPicture(kept.picture);
      from = kept.settled.length;
    }
    for (var s in settled.sublist(from)) {
      _paintStroke(c, s, size);
    }
    var picture = recorder.endRecording();
    ui.Image? raster;
    // Every so often the pile of strokes is flattened into pixels, so a
    // picture of a thousand strokes is not a thousand strokes to draw.
    if (settled.length % 24 == 0 && settled.isNotEmpty) {
      raster = picture.toImageSync(size.width.round(), size.height.round());
      var flat = ui.PictureRecorder();
      // Smoothed as it is shrunk: sampled nearest, a 2048-pixel copy drawn a
      // few hundred across came out with every edge jagged.
      ui.Canvas(flat).drawImage(
          raster, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
      picture = flat.endRecording();
    }
    var was = _painted[key];
    kept = _Painted(List.of(settled), size, picture, raster);
    _painted[key] = kept;
    // What it replaced is let go of now rather than whenever the collector
    // gets to it: drawn into the new picture, it is held there by the
    // engine, and its own pixels are nobody's.
    was?.picture.dispose();
    was?.raster?.dispose();
    while (_painted.length > 24) {
      var gone = _painted.remove(_painted.keys.first);
      gone?.picture.dispose();
      gone?.raster?.dispose();
    }
  }
  canvas.save();
  canvas.clipRect(frame);
  canvas.translate(frame.left, frame.top);
  canvas.scale(frame.width / size.width, frame.height / size.height);
  // The layer the strokes are laid in: an eraser takes paint away, not
  // whatever is under the paint layer.
  canvas.saveLayer(Offset.zero & size, Paint());
  canvas.drawPicture(kept.picture);
  _paintStroke(canvas, strokes.last, size);
  canvas.restore();
  canvas.restore();
}

bool _samePrefix(List<StrokeMark> a, List<StrokeMark> b) {
  if (a.length > b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

/// _alphaToOne makes every pixel opaque, keeping its colour as it was before
/// its alpha: a blur of the picture with a hole cut in it is, unmultiplied,
/// the average colour of what is round the hole -- which is what fills it.
const _alphaToOne = ColorFilter.matrix([
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 0, 255, //
]);

class SharpenShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  static Future<void> load() => _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset("shaders/sharpen.frag");
          ready.value = true;
        } catch (exception) {
          debugPrint("The sharpening shader did not load: $exception");
        }
      }();
}

/// _healFill draws a heal stroke's fill: what is round the spot, blurred
/// across it, with the spot itself cut out first so none of it is averaged
/// in -- the light and colour the healed spot should have.
///
/// In passes, the widest first: a blur as wide as the brush cannot reach the
/// middle of a stroke wider than it, where there is nothing round to average
/// -- and what little reached it, made whole, was a black hole with coloured
/// edges. Each narrower pass is laid over the wider ones only as much as it
/// reached, so near the edge the detail is close by and in the middle it
/// comes from further off; every spot is filled, however wide.
void _healFill(ui.Canvas canvas, ui.Image image, Paint picturePaint,
    List<Offset> points, StrokeMark s, double radius, Rect reach) {
  var stroke = _strokeBounds(points, radius * 1.1);
  var widest = math.max(stroke.width, stroke.height);
  var sigmas = <double>[];
  for (var sigma = math.max(1.0, radius * 0.9);; sigma *= 2) {
    sigmas.add(sigma);
    if (sigma >= widest || sigmas.length >= 8) break;
  }
  canvas.saveLayer(reach, Paint()..colorFilter = _alphaToOne);
  for (var sigma in sigmas.reversed) {
    // Room for the blur to reach in from outside the stroke.
    var room = reach.inflate(sigma * 3);
    canvas.saveLayer(
        room,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal));
    canvas.drawImage(image, Offset.zero, picturePaint);
    // The spot itself cut out first, so none of it is averaged in.
    canvas.saveLayer(room, Paint()..blendMode = BlendMode.dstOut);
    paintDabs(canvas, points, s.pressure, radius * 1.1, 1,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.restore();
    canvas.restore();
  }
  canvas.restore();
}

/// HealShader is the healing brush's shader, loaded once -- see heal.frag.
class HealShader {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset("shaders/heal.frag");
        } catch (exception) {
          debugPrint("The healing shader did not load: $exception");
        }
      }();
}

/// healSource is where a heal stroke started at [f] -- a fraction of a
/// picture of [size] -- takes its texture from, as a distance across the
/// picture: a couple of brush widths to the side, towards the picture's
/// middle so it stays inside it.
Offset healSource(Offset f, double radius, Size size) {
  var short = math.min(size.width, size.height);
  var reach = 2.4 * radius * short;
  var sideways = f.dx > 0.5 ? -1.0 : 1.0;
  return Offset(sideways * reach / size.width, 0);
}

/// _blurred is [image] blurred by [sigma] of its own pixels, made once and
/// kept with it: what sharpening pushes the picture away from.
///
/// A few in all, the most recently used, whatever picture they are of: each
/// is a whole picture's worth of pixels. Kept a few a picture, they were
/// never let go of with the picture -- and a whole-frame retouch makes a new
/// picture to work on whenever what is under it changes.
final _blurs = <(ui.Image, double), ui.Image>{};
const int _blursKept = 4;
ui.Image _blurred(ui.Image image, double sigma) {
  var kept = _blurs;
  var made = kept.remove((image, sigma));
  if (made != null) return kept[(image, sigma)] = made;
  var recorder = ui.PictureRecorder();
  var c = ui.Canvas(recorder);
  c.saveLayer(
      null,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
  c.drawImage(image, Offset.zero, Paint());
  c.restore();
  var picture = recorder.endRecording();
  made = picture.toImageSync(image.width, image.height);
  picture.dispose();
  kept[(image, sigma)] = made;
  while (kept.length > _blursKept) {
    kept.remove(kept.keys.first)!.dispose();
  }
  return made;
}

/// _alongPath is [points] walked at [spacing], each with its pressure.
List<(Offset, double)> _alongPath(
    List<Offset> points, List<double> pressure, double spacing) {
  double at(int i) =>
      pressure.isEmpty ? 1 : pressure[math.min(i, pressure.length - 1)];
  var out = <(Offset, double)>[(points.first, at(0))];
  for (var i = 1; i < points.length; i++) {
    var a = points[i - 1], b = points[i];
    var steps = math.max(1, ((b - a).distance / spacing).ceil());
    for (var s = 1; s <= steps; s++) {
      var t = s / steps;
      out.add((Offset.lerp(a, b, t)!, at(i - 1) + (at(i) - at(i - 1)) * t));
    }
  }
  return out;
}

/// _paintSmudge drags the picture along [s], as a finger through wet paint:
/// each dab is what the brush is carrying -- the picture from further and
/// further back along the stroke, each step back counting for less -- laid
/// where the brush now is. At full strength colour is carried the whole
/// way; weaker, it is let go of sooner.
void _paintSmudge(ui.Canvas canvas, ui.Image image, Paint picturePaint,
    StrokeMark s, List<Offset> points, double radius) {
  // A dab every quarter of the brush, but never more than a hundred and
  // fifty: each is a layer of its own.
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += (points[i] - points[i - 1]).distance;
  }
  var spacing = math.max(math.max(0.5, radius * 0.25), length / 150);
  var dabs = _alongPath(points, s.pressure, spacing);
  // Each step back is most of a brush; how much each counts falls away by
  // [keep], more slowly the stronger the smudge.
  var step = math.max(1, (radius * 0.8 / spacing).round());
  var keep = 0.55 + 0.4 * s.strength;
  const copies = 16;
  var soft = (1 - s.hardness).clamp(0.0, 1.0);
  for (var (i, (at, p)) in dabs.indexed) {
    var r = radius * (0.25 + 0.75 * p);
    var dab = Rect.fromCircle(center: at, radius: r);
    var weights = <(Offset, double)>[];
    var total = 0.0;
    var w = 1.0;
    for (var k = 1; k <= copies; k++) {
      var j = i - k * step;
      var from = dabs[math.max(0, j)].$1;
      weights.add((at - from, w));
      total += w;
      w *= keep;
      if (j <= 0) break;
    }
    canvas.saveLayer(dab, Paint());
    canvas.clipRect(dab);
    for (var (shift, weight) in weights) {
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      // Summed, the copies are their weighted average.
      canvas.drawImage(
          image,
          Offset.zero,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = picturePaint.colorFilter
            ..blendMode = BlendMode.plus
            ..color = Color.fromRGBO(0, 0, 0, weight / total));
      canvas.restore();
    }
    var sigma = r * soft * 0.35;
    var mask = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..blendMode = BlendMode.dstIn;
    if (sigma > 0.3) mask.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawCircle(at, math.max(0.5, r - sigma), mask);
    canvas.restore();
  }
}

/// paintRetouchUnder draws the retouching among [strokes] -- in fractions of
/// the frame -- worked on [below], everything under the layer they are on,
/// drawn into [frame]. What is under is made into pixels to work on, kept as
/// [key] while what it is drawn [from] is the same: a stroke being drawn
/// does not draw everything under it again on every frame.
void paintRetouchUnder(
    ui.Canvas canvas, Rect frame, ui.Picture below, List<StrokeMark> strokes,
    {String? key, List<Object?> from = const []}) {
  var marks = [
    for (var s in strokes)
      if (s.kind.retouches) s
  ];
  if (marks.isEmpty || frame.isEmpty) return;
  var most = math.min(4096 / math.max(frame.width, frame.height),
      math.sqrt(16e6 / (frame.width * frame.height)));
  if (RasterCache.drafting) {
    most = math.min(
        most, RasterCache.draftSide / math.max(frame.width, frame.height));
  }
  var scale = math.max(0.05, math.min(deviceScaleOf(canvas), most));
  var w = math.max(1, (frame.width * scale).ceil());
  var h = math.max(1, (frame.height * scale).ceil());
  var made = key == null
      ? null
      : RasterCache.instance.sized(key, [frame.size, ...from], w, h);
  var kept = made != null;
  if (made == null) {
    var recorder = ui.PictureRecorder();
    var raster = ui.Canvas(recorder);
    raster.scale(w / frame.width, h / frame.height);
    raster.translate(-frame.left, -frame.top);
    raster.drawPicture(below);
    var picture = recorder.endRecording();
    made = picture.toImageSync(w, h);
    picture.dispose();
    if (key != null) {
      RasterCache.instance.putSized(key, [frame.size, ...from], made);
      kept = true;
    }
  }
  var size = Size(made.width.toDouble(), made.height.toDouble());
  canvas.save();
  canvas.clipRect(frame);
  canvas.translate(frame.left, frame.top);
  canvas.scale(frame.width / size.width, frame.height / size.height);
  paintRetouchKept(canvas, made, size, marks, null);
  canvas.restore();
  if (!kept) made.dispose();
}

/// paintRetouchKept is paintRetouch with every stroke but the last kept as
/// pixels, so only the last is drawn again on each frame.
///
/// Every stroke drawn afresh on every frame was every blur, every heal, every
/// clone redone each time the pointer moved -- a picture slower with each
/// stroke put on it. The strokes before the last change only when a stroke
/// is taken back, so they are drawn once, with the picture under them, and
/// kept; the last is the one being drawn, and works on that -- the picture
/// as the strokes before it left it. See retouchedPicture.
void paintRetouchKept(ui.Canvas canvas, ui.Image image, Size size,
    List<StrokeMark> marks, ColorFilter? colour) {
  var strokes = [
    for (var s in marks)
      if (s.points.isNotEmpty && s.kind.retouches) s
  ];
  if (strokes.length < 2 || size.isEmpty) {
    paintRetouch(canvas, image, size, strokes, colour);
    return;
  }
  var settled = strokes.sublist(0, strokes.length - 1);
  // Named by the picture and the first stroke on it, which stay the same
  // object while strokes are added after it: unique to the picture, with
  // nothing to thread through to here.
  var key = "retouch|${identityHashCode(image)}|"
      "${identityHashCode(settled.first)}";
  var from = <Object?>[image, size, ...settled];
  var most = math.min(
      1.0,
      math.min(4096 / math.max(size.width, size.height),
          math.sqrt(16e6 / (size.width * size.height))));
  if (RasterCache.drafting) {
    most = math.min(
        most, RasterCache.draftSide / math.max(size.width, size.height));
  }
  var w = math.max(1, (size.width * most).ceil());
  var h = math.max(1, (size.height * most).ceil());
  var kept = RasterCache.instance.sized(key, from, w, h);
  if (kept == null) {
    // A stroke just added: the strokes before it are most likely still kept
    // under the same name, and only it need be worked on to them.
    var before = RasterCache.instance.sized(
        key, [image, size, ...settled.sublist(0, settled.length - 1)], w, h);
    kept = before != null && before.width == w && before.height == h
        ? retouchedPicture(before, [settled.last])
        : retouchedPicture(image, settled, width: w, height: h);
    RasterCache.instance.putSized(key, from, kept);
  }
  // What the kept strokes changed, and only that: the rest of the picture
  // is as it was drawn, at its own sharpness.
  var touched = Path();
  for (var s in settled) {
    touched.addRect(_reachOf(s, size));
  }
  canvas.save();
  canvas.clipPath(touched);
  canvas.drawImageRect(
      kept,
      Rect.fromLTWH(0, 0, kept.width.toDouble(), kept.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = colour);
  canvas.restore();
  // The last stroke works on the picture as the ones before left it --
  // unless it is nowhere near them, when the picture itself is as good and
  // sharper.
  var last = strokes.last;
  var near = settled.any(
      (s) => _reachOf(s, size).overlaps(_reachOf(last, size, sampling: true)));
  if (!near) {
    paintRetouch(canvas, image, size, [last], colour);
    return;
  }
  canvas.save();
  canvas.scale(size.width / kept.width, size.height / kept.height);
  paintRetouch(canvas, kept,
      Size(kept.width.toDouble(), kept.height.toDouble()), [last], colour);
  canvas.restore();
}

/// _reachOf is the part of a picture of [size] that [s] changes -- or, with
/// [sampling], the part it reads from: where it clones or heals from too.
Rect _reachOf(StrokeMark s, Size size, {bool sampling = false}) {
  var short = math.min(size.width, size.height);
  var radius = s.radius * short;
  var points = [
    for (var p in s.points) Offset(p.dx * size.width, p.dy * size.height)
  ];
  var bounds = _strokeBounds(points, radius);
  if (!sampling) return bounds;
  // A blur or heal reads round the spot as far as its widest blur reaches.
  var reach = bounds.inflate(math.max(bounds.width, bounds.height) * 3);
  // A clone or a heal reads the patch its source puts it beside, too.
  if (s.source != Offset.zero &&
      (s.kind == StrokeKind.clone || s.kind == StrokeKind.heal)) {
    reach = reach.expandToInclude(bounds
        .shift(Offset(s.source.dx * size.width, s.source.dy * size.height))
        .inflate(radius * 2));
  }
  return reach;
}

/// retouchedPicture is [image] with [strokes] worked on it in turn, each on the
/// picture as the strokes before it left it -- so a spot healed away stays
/// away when it is gone over again, rather than being healed back from the
/// picture as it first was. [width] by [height] pixels, or [image]'s own
/// size. Strokes that read nothing another of their run changed are worked
/// together, in one pass.
ui.Image retouchedPicture(ui.Image image, List<StrokeMark> strokes,
    {int? width, int? height}) {
  var w = width ?? image.width, h = height ?? image.height;
  var size = Size(w.toDouble(), h.toDouble());
  var current = image;
  var start = 0;
  while (start < strokes.length) {
    // A run: strokes that read nothing a stroke earlier in it changes.
    var end = start + 1;
    while (end < strokes.length) {
      var reads = _reachOf(strokes[end], size, sampling: true);
      if (strokes
          .sublist(start, end)
          .any((s) => _reachOf(s, size).overlaps(reads))) {
        break;
      }
      end++;
    }
    var recorder = ui.PictureRecorder();
    var c = ui.Canvas(recorder);
    var drawn = current;
    if (drawn.width != w || drawn.height != h) {
      // The picture first, at the size the strokes are worked at.
      var r = ui.PictureRecorder();
      ui.Canvas(r).drawImageRect(
          drawn,
          Rect.fromLTWH(0, 0, drawn.width.toDouble(), drawn.height.toDouble()),
          Offset.zero & size,
          Paint()..filterQuality = FilterQuality.medium);
      var p = r.endRecording();
      drawn = p.toImageSync(w, h);
      p.dispose();
      if (!identical(current, image)) current.dispose();
      current = drawn;
    }
    c.drawImage(drawn, Offset.zero, Paint());
    paintRetouch(c, drawn, size, strokes.sublist(start, end), null);
    var picture = recorder.endRecording();
    var next = picture.toImageSync(w, h);
    picture.dispose();
    if (!identical(current, image)) current.dispose();
    current = next;
    start = end;
  }
  return current;
}

/// paintRetouch draws [marks] -- retouching, in fractions of the picture --
/// over [image] already drawn at its own pixel size [size] in [canvas].
/// [colour] is the colour filter the picture was drawn with, so what is
/// cloned or blurred matches it.
void paintRetouch(ui.Canvas canvas, ui.Image image, Size size,
    List<StrokeMark> marks, ColorFilter? colour) {
  var short = math.min(size.width, size.height);
  var picturePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = colour;
  for (var s in marks) {
    if (s.points.isEmpty || !s.kind.retouches) continue;
    var points = [
      for (var p in s.points) Offset(p.dx * size.width, p.dy * size.height)
    ];
    var radius = s.radius * short;
    var bounds = _strokeBounds(points, radius);
    var reach = bounds.inflate(radius * 3);
    canvas.saveLayer(
        bounds, Paint()..color = Color.fromRGBO(0, 0, 0, s.strength));
    // What the stroke puts down, over the whole of its reach...
    switch (s.kind) {
      case StrokeKind.clone:
        canvas.save();
        canvas.translate(-s.source.dx * size.width, -s.source.dy * size.height);
        canvas.drawImage(image, Offset.zero, picturePaint);
        canvas.restore();
      case StrokeKind.heal:
        var program = HealShader._program;
        if (s.source == Offset.zero || program == null) {
          // A spot filled with a blur of what is round it: a heal from
          // before heals took texture, or with no shader to take it.
          _healFill(canvas, image, picturePaint, points, s, radius, reach);
          break;
        }
        // The fill, drawn into pixels of its own: the light and colour the
        // spot should have.
        var area = reach.intersect(Offset.zero & size);
        if (area.isEmpty) break;
        var fw = math.max(1, area.width.ceil()),
            fh = math.max(1, area.height.ceil());
        var recorder = ui.PictureRecorder();
        var fc = ui.Canvas(recorder);
        fc.translate(-area.left, -area.top);
        _healFill(fc, image, picturePaint, points, s, radius, reach);
        var drawn = recorder.endRecording();
        var fill = drawn.toImageSync(fw, fh);
        drawn.dispose();
        // And the texture of the patch beside it laid over that: its fine
        // detail, without its own colour. See heal.frag.
        var shader = program.fragmentShader()
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, s.source.dx * size.width)
          ..setFloat(3, s.source.dy * size.height)
          ..setFloat(4, area.left)
          ..setFloat(5, area.top)
          ..setFloat(6, fw.toDouble())
          ..setFloat(7, fh.toDouble())
          ..setImageSampler(0, image)
          ..setImageSampler(1, _blurred(image, math.max(1.2, radius * 0.45)))
          ..setImageSampler(2, fill);
        canvas.drawRect(
            area,
            Paint()
              ..shader = shader
              ..colorFilter = colour);
        shader.dispose();
        fill.dispose();
      case StrokeKind.dodge || StrokeKind.burn:
        var k = s.kind == StrokeKind.dodge ? 1 + 0.8 : 1 - 0.6;
        var lift = s.kind == StrokeKind.dodge ? 12.0 : 0.0;
        canvas.saveLayer(
            reach,
            Paint()
              ..colorFilter = ColorFilter.matrix([
                k, 0, 0, 0, lift, //
                0, k, 0, 0, lift, //
                0, 0, k, 0, lift, //
                0, 0, 0, 1, 0, //
              ]));
        canvas.drawImage(image, Offset.zero, picturePaint);
        canvas.restore();
      case StrokeKind.smudge:
        _paintSmudge(canvas, image, picturePaint, s, points, radius);
        // Each dab is cut to itself already.
        canvas.restore();
        continue;
      case StrokeKind.sharpen:
        var program = SharpenShader._program;
        if (program == null) break;
        // An unsharp mask's usual radius, a pixel or so -- detail, not
        // halos -- and up to two and a half times at full strength.
        var sigma = math.max(1.2, short / 350);
        var shader = program.fragmentShader()
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, 1 + 1.5 * s.strength)
          ..setImageSampler(0, image)
          ..setImageSampler(1, _blurred(image, sigma));
        canvas.drawRect(
            reach,
            Paint()
              ..shader = shader
              ..colorFilter = colour);
        shader.dispose();
      case StrokeKind.blur:
        canvas.saveLayer(
            reach,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: radius * 0.5,
                  sigmaY: radius * 0.5,
                  tileMode: TileMode.decal));
        canvas.drawImage(image, Offset.zero, picturePaint);
        canvas.restore();
      default:
        break;
    }
    // ...kept only where the brush went.
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    paintDabs(canvas, points, s.pressure, radius, s.hardness,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.restore();
    canvas.restore();
  }
}

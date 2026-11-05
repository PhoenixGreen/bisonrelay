import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_effects.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/blockchain.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:flutter/painting.dart';

part 'light.dart';
part 'marks.dart';
part 'metals.dart';
part 'surfaces.dart';
part 'tech.dart';

// generators.dart draws every procedural background.
//
// One function per style, each a pure function of (rect, spec, time) with no
// state and no Random(), so a background is the same picture everywhere (see
// noise.dart).
//
// Every style interprets the same five shared controls:
//
//   density    how much of the frame it fills, 0 to 1
//   scale      the size of its repeating unit, as a fraction of the short side
//   intensity  how bright the brightest parts get
//   variation  how much it differs from itself
//   seed       which version of it this is
//
// so the sliders and shuffle work without the settings bar knowing the style.
// Each generator should make all five do something wherever it can.

/// proceduralPass is one turn of a pattern's own clock, in seconds.
///
/// One number for every style, since most (rain, flow) have no natural
/// cycle. It is one ring's life, the one style that does.
const double proceduralPass = 1 / 0.15;

/// proceduralRunSeconds is how long a complete run of [spec] takes in the
/// pattern's own time: from the first thing happening to the last thing
/// being over.
///
/// For rings that is until the last ring has dissolved: it is born nearly a
/// life after the first, so the run is close to two lives, whether or not
/// the set builds up. Other styles run for one [proceduralPass].
double proceduralRunSeconds(ProceduralSpec spec) {
  if (spec.style != ProceduralStyle.rings) return proceduralPass;
  var many = spec.rings.count.clamp(1, 200);
  var last = (many - 1) / many;
  return proceduralPass * (1 + last);
}

/// pausedFrame is the frame the pattern is showing, given the document's
/// [frame] and the spec's rest (pauseAt, pauseFor, pauseEase).
///
/// The pattern's clock stops while the document's goes on, so nothing is
/// skipped or repeated after the rest. Each ease covers half the ground it
/// would have at full speed (the integral of a smooth step).
double pausedFrame(double frame, ProceduralSpec spec) {
  var hold = spec.pauseFor.toDouble();
  if (hold <= 0) return frame;
  var ease = spec.pauseEase.toDouble().clamp(0.0, hold * 4);
  var stops = spec.pauseAt.toDouble();

  var slowing = stops - ease;
  var still = stops;
  var going = stops + hold;
  var upToSpeed = going + ease;

  // Distance through a ramp of length one whose speed eases from one to
  // nought: x minus the integral of smoothstep (x^3 - x^4 / 2).
  double slowed(double x) => x - (x * x * x - x * x * x * x / 2);
  double sped(double x) => x * x * x - x * x * x * x / 2;

  if (frame <= slowing) return frame;
  if (frame <= still) {
    return slowing + ease * slowed((frame - slowing) / (ease <= 0 ? 1 : ease));
  }
  var atRest = slowing + ease * 0.5;
  if (frame <= going) return atRest;
  if (frame <= upToSpeed) {
    return atRest + ease * sped((frame - going) / (ease <= 0 ? 1 : ease));
  }
  // Afterwards, late by everything the rest cost.
  return frame - hold - ease;
}

/// latticeDetail is how many lattice points per pixel the lit surfaces
/// (metal and materials) use: 1 for the canvas and export, less for a
/// thumbnail, which is a big frame drawn shrunk.
double latticeDetail = 1;

/// paintProcedural draws [spec] into [rect].
///
/// [time] is in seconds; zero is a still.
void paintProcedural(ui.Canvas canvas, Rect rect, ProceduralSpec input,
    {double time = 0, double frameRate = 0, CanvasImageSource? images}) {
  if (rect.width <= 0 || rect.height <= 0) return;
  if (!input.seamless) {
    return _paintOnce(canvas, rect, input, time, frameRate, images);
  }

  // A seamless loop. Few movements return to where they began, so over the
  // last part of the loop the picture from one loop earlier is faded in; at
  // the end it is all that earlier picture, which runs straight into frame
  // one. The whole background is drawn twice, so layers and grain loop too.
  var rate = frameRate > 0 ? frameRate : 30.0;
  var length = input.loopFrames / rate;
  var at = time % length;
  var blend = (input.loopBlend * length).clamp(1 / rate, length);
  var into = at - (length - blend);
  _paintOnce(canvas, rect, input, at, frameRate, images);
  if (into <= 0) return;
  var w = (into / blend).clamp(0.0, 1.0);
  // Eased, so the weight has no corner either.
  w = w * w * (3 - 2 * w);
  canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, w));
  _paintOnce(canvas, rect, input, at - length, frameRate, images);
  canvas.restore();
}

/// _paintOnce draws the background at one moment. See paintProcedural.
void _paintOnce(ui.Canvas canvas, Rect rect, ProceduralSpec input, double time,
    double frameRate, CanvasImageSource? images) {
  var spec = input;
  var fx = spec.effects;

  // The grade covers base, pattern, light and lens, but not the grain (the
  // film, not the scene).
  if (fx.grades) {
    canvas.saveLayer(rect, Paint()..colorFilter = gradeFilter(fx));
  }

  // The clip keeps the overspill of a turned pattern (see _patternLayer)
  // off the canvas.
  canvas.save();
  canvas.clipRect(rect);

  _paintBase(canvas, rect, spec);

  // A rest, taken first so speed and pass length are measured in the
  // pattern's own time rather than the document's.
  var moment = time;
  if (spec.animated && spec.pauseFor > 0 && frameRate > 0) {
    moment = pausedFrame(time * frameRate, spec) / frameRate;
  }

  var t = spec.animated ? moment * spec.speed : 0.0;
  // Which run the movement is on. See RingIcon.firstRunOnly.
  var round = 0;
  if (spec.inRuns) {
    // Counted in runs, timed in frames (passFrames); speed is ignored.
    var run = proceduralRunSeconds(spec);
    var frames = spec.passFrames.clamp(1, 100000).toDouble();
    var at = frameRate > 0 ? moment * frameRate : moment;

    // One run of `frames`, then `loopGap` frames of the finished picture.
    var cycle = frames + spec.loopGap.clamp(0, 100000);
    round = (at / cycle).floor();
    var done = spec.loopTimes > 0 && round >= spec.loopTimes;
    // Held at the end after the last run and through each gap.
    var within = done ? frames : at - round * cycle;
    var through = within / frames;
    // A whole life past the end, not exactly on it: roughened spacing can
    // leave a ring at the last instant of its life, which with a hard edge
    // is a ring at full strength held for the rest of the canvas.
    t = through >= 1 ? run + proceduralPass : through * run;
    if (done) round = spec.loopTimes - 1;
  } else if (spec.animated) {
    // Looping for ever still has runs, for firstRunOnly.
    var run = proceduralRunSeconds(spec);
    if (run > 0) round = (t / run).floor();
  }
  _patternLayer(canvas, rect, spec, t, round, images);

  // The layers over it, each through its own saveLayer so its opacity and
  // blend apply to it as a whole. A plain layer is a wash of its colour.
  for (var layer in input.layers) {
    if (!layer.visible || layer.opacity <= 0) continue;
    var ls = layer.spec;
    canvas.saveLayer(
        rect,
        Paint()
          ..blendMode = layer.blend.flutter
          ..color = Color.fromRGBO(0, 0, 0, layer.opacity.clamp(0.0, 1.0)));
    if (ls.style == ProceduralStyle.plain) _paintBase(canvas, rect, ls);
    // On the background's clock, at the layer's own pace.
    _patternLayer(
        canvas, rect, ls, spec.animated ? moment * ls.speed : 0, round, images);
    canvas.restore();
  }

  canvas.restore();

  // The light is part of the scene; the vignette is the lens, so it goes
  // after.
  if (spec.light.on) paintLight(canvas, rect, spec.light);

  if (spec.vignette > 0) _vignette(canvas, rect, spec.vignette);

  if (fx.scanlines > 0) _scanlines(canvas, rect, fx);

  if (fx.grades) canvas.restore();

  if (fx.grain > 0) {
    var frame = spec.animated && fx.grainMoves
        ? (time * (frameRate > 0 ? frameRate : 24)).floor()
        : 0;
    _grain(canvas, rect, fx, spec.seed * 7919 + frame);
  }
}

/// _patternLayer draws [spec]'s pattern, turned, faded and finished by its
/// own effects, over what is on [canvas] at time [t]. Called for the
/// background's pattern and for each layer.
void _patternLayer(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t,
    int round, CanvasImageSource? images) {
  var fx = spec.effects;
  var area = rect;
  // The size as set, before any allowance for a turn. See the pitch below.
  var givenScale = spec.scale;
  if (spec.rotation != 0) {
    // Drawn in a rectangle grown so its shorter side is the page's
    // diagonal, the least that covers every corner at every angle.
    var diagonal =
        math.sqrt(rect.width * rect.width + rect.height * rect.height);
    area = rect.inflate((diagonal - math.min(rect.width, rect.height)) / 2);
    // Generators size their unit from the short side of what they are
    // given, so scale is reduced to match or a turn would zoom in.
    var grown =
        math.min(area.width, area.height) / math.min(rect.width, rect.height);
    if (grown > 0) spec = spec.copyWith(scale: spec.scale / grown);
  }

  void pattern(ui.Canvas canvas, ProceduralSpec s) {
    switch (s.style) {
      case ProceduralStyle.plain:
        break;
      case ProceduralStyle.gradientMesh:
        _gradientMesh(canvas, area, s, t);
      case ProceduralStyle.dotGrid:
        _dotGrid(canvas, area, s, t);
      case ProceduralStyle.lineGrid:
        _lineGrid(canvas, area, s, t);
      case ProceduralStyle.hexGrid:
        _hexGrid(canvas, area, s, t);
      case ProceduralStyle.contours:
        _contours(canvas, area, s, t);
      case ProceduralStyle.flowWaves:
        _flowWaves(canvas, area, s, t);
      case ProceduralStyle.bokeh:
        _bokeh(canvas, area, s, t);
      case ProceduralStyle.starfield:
        _starfield(canvas, area, s, t);
      case ProceduralStyle.ledGrid:
        _ledGrid(canvas, area, s, t);
      case ProceduralStyle.circuit:
        _circuit(canvas, area, s, t);
      case ProceduralStyle.rain:
        _rain(canvas, area, s, t);
      case ProceduralStyle.symbolField:
        _symbolField(canvas, area, s, t);
      case ProceduralStyle.blockchain:
        paintBlockchain(canvas, area, s, t);
      case ProceduralStyle.rings:
        _rings(canvas, area, rect, s, t, round, images);
      case ProceduralStyle.halftone:
        _halftone(canvas, area, s, t);
      case ProceduralStyle.speedLines:
        _speedLines(canvas, area, s, t);
      case ProceduralStyle.crosshatch:
        _crosshatch(canvas, area, s);
      case ProceduralStyle.splatter:
        _splatter(canvas, area, s, t);
      case ProceduralStyle.flames:
        _flames(canvas, area, s, t);
      case ProceduralStyle.pitch:
        // Fitted to the page, not the grown area: a pitch is one object
        // and would jump bigger when turned. Its Size is a zoom at the scale
        // as set; only its ground fills the grown area ([cover]).
        paintPitch(canvas, rect, s.copyWith(scale: givenScale), cover: area);
      case ProceduralStyle.metal:
        // Brushed is drawn here; the other finishes are in metals.dart.
        if (s.choice("finish") == MetalFinish.brushed) {
          _metal(canvas, area, s);
        } else {
          _metalFinish(canvas, area, s);
        }
      case ProceduralStyle.surface:
        _surface(canvas, area, s);
    }
  }

  // A faded foreground or accent is drawn on its own layer: the pattern with
  // that colour white and the other clear, then the fade painted through it
  // (srcIn). Generators draw flat colours and know nothing of fades.
  void drawPattern(ui.Canvas canvas) {
    canvas.save();
    if (spec.rotation != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(spec.rotation * math.pi / 180);
      canvas.translate(-rect.center.dx, -rect.center.dy);
    }
    var fg = spec.foregroundFade, ac = spec.accentFade;
    if (fg == null && ac == null) {
      pattern(canvas, spec);
    } else {
      const clear = Color(0x00000000);
      Color white(Color c) => Color.fromRGBO(255, 255, 255, c.a);
      void through(ProceduralSpec masked, Color colour, GradientSpec fade) {
        canvas.saveLayer(area, Paint());
        pattern(canvas, masked);
        canvas.drawRect(
            area,
            Paint()
              ..blendMode = BlendMode.srcIn
              ..shader = PaintSpec(colour, gradient: fade).shaderFor(rect));
        canvas.restore();
      }

      if (fg != null) {
        through(
            spec.copyWith(foreground: white(spec.foreground), accent: clear),
            spec.foreground,
            fg);
      } else {
        pattern(canvas, spec.copyWith(accent: clear));
      }
      if (ac != null) {
        through(spec.copyWith(accent: white(spec.accent), foreground: clear),
            spec.accent, ac);
      } else {
        pattern(canvas, spec.copyWith(foreground: clear));
      }
    }
    canvas.restore();
  }

  // Drawn straight on when no effect applies. Otherwise it is recorded once
  // and laid through a layer that masks, blurs and fades it without
  // touching the base: once for itself and again for each unit of glow.
  var short = math.min(rect.width, rect.height);
  if (fx.opacity >= 1 && !fx.masks && fx.blur <= 0 && fx.glow <= 0) {
    drawPattern(canvas);
  } else if (fx.opacity > 0) {
    var recorder = ui.PictureRecorder();
    drawPattern(ui.Canvas(recorder));
    var picture = recorder.endRecording();
    void lay(Paint paint) {
      canvas.saveLayer(rect, paint);
      canvas.drawPicture(picture);
      if (fx.masks) _masks(canvas, rect, fx);
      canvas.restore();
    }

    var soft = fx.blur * short * 0.02;
    lay(Paint()
      ..color = Color.fromRGBO(0, 0, 0, fx.opacity.clamp(0.0, 1.0))
      ..imageFilter =
          soft > 0.05 ? ui.ImageFilter.blur(sigmaX: soft, sigmaY: soft) : null);
    // Glow: the pattern blurred wide and added, so it only brightens. Each
    // whole unit of glow is another pass.
    var spread = math.max(0.5, short * (0.004 + fx.glowSize * 0.04));
    for (var left = fx.glow * fx.opacity; left > 0.001; left -= 1) {
      lay(Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(0, 0, 0, left.clamp(0.0, 1.0))
        ..imageFilter = ui.ImageFilter.blur(sigmaX: spread, sigmaY: spread));
    }
    picture.dispose();
  }
}

/// gradeFilter is the colour grade as one matrix: hue turned, then
/// saturation, then contrast and brightness.
ui.ColorFilter gradeFilter(EffectsSpec fx) {
  // Hue rotation about the grey axis, luminance-weighted so lightness is
  // kept.
  var a = fx.hue * math.pi / 180, c = math.cos(a), s = math.sin(a);
  const lr = 0.213, lg = 0.715, lb = 0.072;
  var hue = [
    [
      lr + c * (1 - lr) - s * lr,
      lg - c * lg - s * lg,
      lb - c * lb + s * (1 - lb)
    ],
    [
      lr - c * lr + s * 0.143,
      lg + c * (1 - lg) + s * 0.140,
      lb - c * lb - s * 0.283
    ],
    [
      lr - c * lr - s * (1 - lr),
      lg - c * lg + s * lg,
      lb + c * (1 - lb) + s * lb
    ],
  ];
  var k = 1 + fx.saturation;
  var sr = (1 - k) * 0.2126, sg = (1 - k) * 0.7152, sb = (1 - k) * 0.0722;
  var sat = [
    [sr + k, sg, sb],
    [sr, sg + k, sb],
    [sr, sg, sb + k],
  ];
  List<List<double>> times(List<List<double>> x, List<List<double>> y) => [
        for (var i = 0; i < 3; i++)
          [
            for (var j = 0; j < 3; j++)
              x[i][0] * y[0][j] + x[i][1] * y[1][j] + x[i][2] * y[2][j],
          ],
      ];
  var m = times(sat, hue);
  // Contrast pivots on middle grey; brightness slides everything.
  var gain = fx.contrast >= 0 ? 1 + fx.contrast * 2 : 1 + fx.contrast;
  var offset = (0.5 * (1 - gain) + fx.brightness * 0.5) * 255;
  return ui.ColorFilter.matrix([
    for (var i = 0; i < 3; i++) ...[
      m[i][0] * gain,
      m[i][1] * gain,
      m[i][2] * gain,
      0,
      offset,
    ],
    0,
    0,
    0,
    1,
    0,
  ]);
}

/// _masks removes the pattern away from the focus and from the clear area.
void _masks(ui.Canvas canvas, Rect rect, EffectsSpec fx) {
  var long = math.max(rect.width, rect.height);
  if (fx.focus > 0) {
    var centre = Offset(
        rect.left + rect.width * fx.focusX, rect.top + rect.height * fx.focusY);
    var inner = long * fx.focusSize;
    var outer = inner + long * 0.65;
    canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.radial(centre, outer, [
            const Color(0xFFFFFFFF),
            const Color(0xFFFFFFFF),
            Color.fromRGBO(255, 255, 255, 1 - fx.focus),
          ], [
            0,
            inner / outer,
            1
          ]));
  }

  if (fx.clear == ClearArea.none || fx.clearAmount <= 0) return;
  var gone = Color.fromRGBO(0, 0, 0, fx.clearAmount);
  var none = const Color(0x00000000);
  // Softness spreads the change across the area's edge rather than moving
  // the edge.
  var soft = fx.clearSoftness.clamp(0.0, 1.0);
  var size = fx.clearSize.clamp(0.0, 1.0);
  var hard = size * (1 - soft * 0.6), fade = size * (1 + soft * 0.4) + 1e-4;
  var paint = Paint()..blendMode = BlendMode.dstOut;

  // From an edge, across a fraction of the frame.
  Shader fromEdge(Offset edge, Offset across) => ui.Gradient.linear(
      edge, edge + across * fade, [gone, gone, none], [0, hard / fade, 1]);
  // Out from the middle line, both ways.
  Shader fromMiddle(Offset middle, Offset across) {
    var half = across * (fade / 2);
    var h = hard / fade;
    return ui.Gradient.linear(middle - half, middle + half,
        [none, gone, gone, none], [0, 0.5 - h / 2, 0.5 + h / 2, 1]);
  }

  var w = Offset(rect.width, 0), h = Offset(0, rect.height);
  switch (fx.clear) {
    case ClearArea.none:
      return;
    case ClearArea.centre:
      // An oval the shape of the frame, not a circle.
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(1, rect.height / rect.width);
      var r = rect.width * 0.7 * fade;
      paint.shader = ui.Gradient.radial(
          Offset.zero, r, [gone, gone, none], [0, hard / fade, 1]);
      canvas.drawCircle(Offset.zero, r, paint);
      canvas.restore();
      return;
    case ClearArea.left:
      paint.shader = fromEdge(rect.centerLeft, w);
    case ClearArea.right:
      paint.shader = fromEdge(rect.centerRight, -w);
    case ClearArea.top:
      paint.shader = fromEdge(rect.topCenter, h);
    case ClearArea.bottom:
      paint.shader = fromEdge(rect.bottomCenter, -h);
    case ClearArea.band:
      paint.shader = fromMiddle(rect.center, h);
    case ClearArea.column:
      paint.shader = fromMiddle(rect.center, w);
  }
  canvas.drawRect(rect, paint);
}

/// _scanlines darkens every other line of the frame, as a screen does.
void _scanlines(ui.Canvas canvas, Rect rect, EffectsSpec fx) {
  var short = math.min(rect.width, rect.height);
  var step = math.max(2.0, short * fx.scanlineSize / 1000);
  var paint = Paint()
    ..color = Color.fromRGBO(0, 0, 0, (fx.scanlines * 0.6).clamp(0.0, 1.0));
  for (var y = rect.top; y < rect.bottom; y += step) {
    canvas.drawRect(
        Rect.fromLTWH(rect.left, y, rect.width, step * 0.45), paint);
  }
}

/// _grain is film grain: a speck in every few pixels, lighter or darker than
/// what is under it. Points rather than a noise image, so it is sized to the
/// frame at any export size.
void _grain(ui.Canvas canvas, Rect rect, EffectsSpec fx, int seed) {
  var short = math.min(rect.width, rect.height);
  var dot = math.max(0.6, short * fx.grainSize / 1000);
  var cell = dot * 1.6;
  // Capped at 260k specks: past that the grain is coarsened instead.
  var cells = rect.width * rect.height / (cell * cell);
  if (cells > 260000) {
    cell *= math.sqrt(cells / 260000);
    dot = cell / 1.6;
  }
  var cols = (rect.width / cell).ceil(), rows = (rect.height / cell).ceil();
  var buckets = List.generate(4, (_) => <double>[]);
  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var v = hash(seed, ix, iy);
      var b = v < 0.25 ? 0 : (v < 0.5 ? 1 : (v < 0.75 ? 2 : 3));
      buckets[b]
        ..add(rect.left + (ix + hash(seed + 1, ix, iy)) * cell)
        ..add(rect.top + (iy + hash(seed + 2, ix, iy)) * cell);
    }
  }
  var a = fx.grain.clamp(0.0, 1.0);
  const tones = [
    (Color(0xFF000000), 0.30),
    (Color(0xFF000000), 0.12),
    (Color(0xFFFFFFFF), 0.10),
    (Color(0xFFFFFFFF), 0.24),
  ];
  for (var (i, (colour, strength)) in tones.indexed) {
    canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(buckets[i]),
        Paint()
          ..strokeWidth = dot
          ..strokeCap = StrokeCap.square
          ..color = colour.withValues(alpha: strength * a));
  }
}

/// paintLight throws one light across the finished background, so it works
/// on every style without lighting code in each generator.
///
/// Added (BlendMode.plus) rather than alpha-blended, so it lifts the pattern
/// instead of covering it with a flat disc.
void paintLight(ui.Canvas canvas, Rect rect, LightSpec light) {
  if (rect.width <= 0 || rect.height <= 0 || light.brightness <= 0) return;

  var radius = math.max(rect.width, rect.height) * light.size.clamp(0.01, 3.0);
  if (radius <= 0) return;

  // Past full, the light burns towards white, as an overexposed light does.
  var over = (light.brightness - 1).clamp(0.0, 1.0);
  var colour = Color.lerp(light.color, const Color(0xFFFFFFFF), over)!;
  var alpha = (light.brightness.clamp(0.0, 1.0) * colour.a).clamp(0.0, 1.0);

  // Where the falloff starts: nought fades from the middle, one is a hard
  // circle with a thin soft edge against aliasing.
  var hard = light.falloff.clamp(0.0, 1.0);

  var centre = Offset(
    rect.left + rect.width * light.x,
    rect.top + rect.height * light.y,
  );

  canvas.save();
  canvas.clipRect(rect);
  canvas.translate(centre.dx, centre.dy);
  // Compass degrees, like every direction in a canvas: 0 is up the page.
  canvas.rotate(light.direction * math.pi / 180);

  // A raking light lands as a long pool. Scaling the canvas rather than
  // using an elliptical gradient keeps the falloff's shape when stretched.
  var stretch = 1 + light.reach.clamp(0.0, 1.0) * 2.4;
  canvas.scale(1, stretch);
  // Thrown forward, so the light's position is the pool's near edge, not
  // its middle.
  var along = -radius * (stretch - 1) / stretch;

  canvas.drawCircle(
    Offset(0, along),
    radius,
    Paint()
      ..blendMode = ui.BlendMode.plus
      ..shader = ui.Gradient.radial(
        Offset(0, along),
        radius,
        [
          colour.withValues(alpha: alpha),
          colour.withValues(alpha: alpha),
          colour.withValues(alpha: 0),
        ],
        [0, hard * 0.92, 1.0],
      ),
  );
  canvas.restore();
}

/// _metal draws a brushed metal sheet: a surface rather than marks on a
/// ground.
///
/// It is a height field lit from one side, so nothing draws a scratch or a
/// highlight directly: scratches are low places that show because the
/// surface tilts there, and highlights land on slopes (dent rims, brushing
/// ridges) and not on rust, which is matt.
///
/// Brushing is stretched smooth noise (Roughness sets how tight), dents are
/// [worley] and scratches are [ridged]. Size is feature size, Brightness the
/// light, Variation the brushing's stretch, Density how strongly the relief
/// tilts the surface.
void _metal(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var m = spec.metal;
  var short = math.min(rect.width, rect.height);
  if (short <= 0) return;

  // A lattice point per pixel (see latticeDetail), capped at 448 a side.
  // Not coarser: nothing under two cells across can be represented, so the
  // lattice limits how fine the brushing can be.
  var cols = (rect.width * latticeDetail).round().clamp(8, 448);
  var rows = (rect.height * latticeDetail).round().clamp(8, 448);
  var stepX = rect.width / cols, stepY = rect.height / rows;

  // Everything below works in units of the shorter side, so the sheet is
  // the same at any size. Feature size relative to the Size control's
  // middle; the low floor reaches a blasted, granular finish.
  var size = math.max(0.06, spec.scale / 0.05);

  // No frequency may exceed what the lattice can carry (about two cells a
  // feature), or it aliases into pebbles at small Size. Every frequency
  // below goes through carried().
  var ceiling = math.min(cols, rows) / 2.2;
  double carried(double frequency) => math.min(frequency, ceiling);

  var brush = ValueNoise(spec.seed);
  var crease = ValueNoise(spec.seed + 4099);
  var crust = ValueNoise(spec.seed + 7717);
  var patch = ValueNoise(spec.seed + 1229);
  var sheen = ValueNoise(spec.seed + 3313);

  // Every relief is given as the slope it should reach, not a depth: slope
  // is depth times frequency, and the light only sees slope. A fixed depth
  // at fine frequencies turns brushing into corrugated iron.
  double depthFor(double slope, double frequency) =>
      slope / math.max(1.0, frequency);

  // Brushing frequency across the sheet, from broad at nought roughness to
  // fine at one.
  var across = carried(math.max(3.0, (10 + m.roughness * 110) / size));
  // And its stretch along the sheet: 1 (the same both ways) is a blasted
  // finish, up to a long hairline drag.
  var stretch = 1 + spec.variation * 26;
  var along = math.max(0.6, across / stretch);
  var grainDepth = depthFor(0.2 + m.roughness * 1.0, across);

  // The slow unevenness of the sheet under the brushing. Its depth must use
  // its real frequency or it drowns the grain at small Size.
  var swellAlong = carried(1.7 / size), swellAcross = carried(2.3 / size);
  var swellDepth = depthFor(0.18, math.max(swellAlong, swellAcross));

  // Rust threshold. Smooth noise clusters round its middle, so these are
  // levels the field actually crosses, not a fraction of 0..1.
  var rustLevel = 0.72 - m.rust * 0.38;

  var dentSize = carried(13 / size);
  var dentDepth = depthFor(0.16 * m.damage, dentSize);
  // Scratches long and thin: nearer isotropic, the creases join into a web
  // that looks like cracked paint.
  var scratchAcross = carried(150 / size), scratchAlong = 0.5 / size;
  var scratchDepth = depthFor(0.5 + m.damage * 0.8, scratchAcross);
  var crustAcross = carried(across * 1.6);
  var crustDepth = depthFor(0.9, crustAcross);

  var count = (cols + 1) * (rows + 1);
  var height = Float64List(count);
  var rusted = Float64List(count);
  var shine = Float64List(count);

  for (var iy = 0; iy <= rows; iy++) {
    for (var ix = 0; ix <= cols; ix++) {
      var u = (ix * stepX) / short;
      var v = (iy * stepY) / short;
      var at = iy * (cols + 1) + ix;

      // Brushing: one octave, since lower octaves add a slow swell that
      // reads as water rather than steel.
      var h = (brush.at(u * along, v * across) - 0.5) * grainDepth;
      // The swell under it: without it the sheet reads as printed paper.
      h += (brush.at(u * swellAlong, v * swellAcross) - 0.5) * swellDepth;

      if (m.damage > 0) {
        // Dents: only the cells the damage keeps (all of them is a golf
        // ball), each a different size (all one size is perforations).
        var (distance, which) =
            worley(spec.seed + 31, u * dentSize, v * dentSize);
        var keep = m.damage * 0.22;
        if (which < keep) {
          var spread = which / math.max(0.0001, keep);
          // A radius inside the cell, so each dent has flat metal round it;
          // dents meeting at cell walls look like flaking paint.
          var radius = 0.3 + spread * 0.45;
          // Smoothstep, not a cube: a cube's point and rim crease light up
          // as arrowheads.
          var dish = (1 - distance / radius).clamp(0.0, 1.0);
          h -= dish * dish * (3 - 2 * dish) * dentDepth * (0.45 + spread);
        }
        // Scratches: one octave, since a second adds short marks across the
        // long ones and makes dashes.
        var creased =
            ridged(crease, u * scratchAlong, v * scratchAcross, octaves: 1);
        // A high, narrow threshold keeps only the sharpest creases.
        var cut = ((creased - (0.93 - m.damage * 0.10)) / 0.05).clamp(0.0, 1.0);
        h -= cut * scratchDepth;
      }

      // Rust: a threshold on a smooth field, ragged at the edge and deeper
      // in the middle.
      var r = 0.0;
      if (m.rust > 0) {
        var n = patch.fbm(u * 4.2, v * 4.2, octaves: 3);
        if (n > rustLevel) {
          r = ((n - rustLevel) / math.max(0.0001, 0.85 - rustLevel))
              .clamp(0.0, 1.0);
          // Crust stands proud and is rough at its own scale.
          h += (crust.fbm(u * crustAcross, v * crustAcross, octaves: 2) - 0.4) *
              crustDepth *
              r;
        }
      }

      height[at] = h;
      rusted[at] = r;
      // How polished the sheet is here: wear varies slowly, so one octave.
      shine[at] = 0.5 + sheen.at(u * 1.1, v * 1.1);
    }
  }

  // How hard the relief tilts the surface, divided by the lattice spacing
  // so a finer lattice gives the same slopes.
  var gain = 0.35 + spec.density * 1.1;
  var slopeX = gain / math.max(0.0001, 2 * stepX / short);
  var slopeY = gain / math.max(0.0001, 2 * stepY / short);

  // Light from the upper left, as everywhere in the app. A turned
  // background turns it too (see _patternLayer).
  const lx = -0.42, ly = -0.58, lz = 0.70;
  // The half vector between light and eye, for the specular term.
  var hx = lx, hy = ly, hz = lz + 1;
  var hlen = math.sqrt(hx * hx + hy * hy + hz * hz);
  hx /= hlen;
  hy /= hlen;
  hz /= hlen;

  // Power makes the highlight small, force makes it bright: high Shine is
  // both, a mirror; low is broad and weak, bead-blasted.
  var power = 4 + m.shine * m.shine * 70;
  var force = 0.10 + m.shine * 0.95;

  // Plain numbers, so the loop does not allocate Colors per point.
  var mr = spec.background.r, mg = spec.background.g, mb = spec.background.b;
  var lr = spec.foreground.r, lg = spec.foreground.g, lb = spec.foreground.b;
  var or_ = spec.accent.r, og = spec.accent.g, ob = spec.accent.b;
  var bright = 0.6 + spec.intensity * 0.6;

  // The highlight curve as a lookup table, read between entries: math.pow
  // with a fractional exponent per lattice point is too slow.
  const steps = 1024;
  var curve = Float64List(steps + 1);
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    // Two lobes, a tight glint over a broad sheen: one tight lobe is so
    // small the lattice mostly misses it, so high Shine looked duller.
    curve[i] = 0.72 * math.pow(t, power).toDouble() +
        0.28 * math.pow(t, power * 0.18).toDouble();
  }

  var colours = Int32List(count);
  for (var iy = 0; iy <= rows; iy++) {
    for (var ix = 0; ix <= cols; ix++) {
      var at = iy * (cols + 1) + ix;
      var left = height[iy * (cols + 1) + math.max(0, ix - 1)];
      var right = height[iy * (cols + 1) + math.min(cols, ix + 1)];
      var up = height[math.max(0, iy - 1) * (cols + 1) + ix];
      var down = height[math.min(rows, iy + 1) * (cols + 1) + ix];

      // The surface normal, from the height differences.
      var nx = -(right - left) * slopeX;
      var ny = -(down - up) * slopeY;
      var len = math.sqrt(nx * nx + ny * ny + 1);
      nx /= len;
      ny /= len;
      var nz = 1 / len;

      var diffuse = (nx * lx + ny * ly + nz * lz).clamp(0.0, 1.0);
      var toEye = (nx * hx + ny * hy + nz * hz).clamp(0.0, 1.0);
      var slot = toEye * steps;
      // One short of the end so low + 1 is in the table: toEye is exactly
      // one wherever the surface is flat.
      var low = slot.floor().clamp(0, steps - 1);
      var lift = slot - low;
      var highlight = (curve[low] + (curve[low + 1] - curve[low]) * lift) *
          force *
          shine[at];

      var r = rusted[at];
      // Rust is matt: the highlight fades out across a patch.
      highlight *= 1 - r * 0.95;
      // Rough grain dulls it too.
      highlight *= 1 - m.roughness * 0.3;

      // Rust is the accent colour darkened towards a patch's middle, never
      // mixed towards brown, so a grey accent stays grey.
      var dark = 1 - r * 0.5;
      var sr = mr + (or_ * dark - mr) * r;
      var sg = mg + (og * dark - mg) * r;
      var sb = mb + (ob * dark - mb) * r;
      // Well off black: metal in shadow is still metal.
      var shade = (0.52 + diffuse * 0.62) * bright;

      var red = sr * shade + lr * highlight;
      var green = sg * shade + lg * highlight;
      var blue = sb * shade + lb * highlight;

      colours[at] = 0xFF000000 |
          ((red.clamp(0.0, 1.0) * 255).round() << 16) |
          ((green.clamp(0.0, 1.0) * 255).round() << 8) |
          (blue.clamp(0.0, 1.0) * 255).round();
    }
  }

  // One triangle strip per lattice row, coloured at the corners, rather
  // than one huge Vertices for the whole sheet.
  var paint = Paint();
  var positions = Float32List((cols + 1) * 4);
  var strip = Int32List((cols + 1) * 2);
  for (var iy = 0; iy < rows; iy++) {
    var top = rect.top + iy * stepY;
    var bottom = top + stepY;
    for (var ix = 0; ix <= cols; ix++) {
      var x = rect.left + ix * stepX;
      positions[ix * 4] = x;
      positions[ix * 4 + 1] = top;
      positions[ix * 4 + 2] = x;
      positions[ix * 4 + 3] = bottom;
      strip[ix * 2] = colours[iy * (cols + 1) + ix];
      strip[ix * 2 + 1] = colours[(iy + 1) * (cols + 1) + ix];
    }
    var vertices = ui.Vertices.raw(
      ui.VertexMode.triangleStrip,
      Float32List.fromList(positions),
      colors: Int32List.fromList(strip),
    );
    // Modulated with a white paint, so the vertex colours draw unchanged.
    canvas.drawVertices(vertices, ui.BlendMode.modulate,
        paint..color = const Color(0xFFFFFFFF));
    vertices.dispose();
  }
}

/// _paintBase fills the frame before the generator runs.
void _paintBase(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  // Through PaintSpec, so the background gets the app's gradients.
  var shader =
      PaintSpec(spec.background, gradient: spec.gradient).shaderFor(rect);
  canvas.drawRect(
      rect,
      shader == null
          ? (Paint()..color = spec.background)
          : (Paint()..shader = shader));
}

/// _vignette darkens the edges by [amount].
void _vignette(ui.Canvas canvas, Rect rect, double amount) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        math.max(rect.width, rect.height) * 0.72,
        [const Color(0x00000000), Color.fromRGBO(0, 0, 0, amount)],
        [0.45, 1.0],
      ),
  );
}

/// _unit is the generator's repeating unit in pixels (a grid cell, a rain
/// glyph): [ProceduralSpec.scale] of the shorter side, at least 2.
double _unit(Rect rect, ProceduralSpec spec) =>
    math.max(2, math.min(rect.width, rect.height) * spec.scale);

/// _fade is [c] with its alpha multiplied by [a].
Color _fade(Color c, double a) => c.withValues(alpha: (c.a * a).clamp(0, 1));

// --------------------------------------------------------------------------
// The generators
// --------------------------------------------------------------------------

/// _contours draws iso-lines through a noise field, by marching squares.
///
/// Marching squares samples the field once per cell corner, not per pixel,
/// and gives line segments that stay crisp at export resolution.
void _contours(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var cell = math.max(4.0, _unit(rect, spec) * 0.6);
  var cols = (rect.width / cell).ceil();
  var rows = (rect.height / cell).ceil();
  if (cols <= 0 || rows <= 0) return;

  var levels = 3 + (spec.density * 14).round();
  var freq = 0.06 * (1 + spec.variation * 2);

  // Sampled once; every level walks the same grid.
  var field = List.generate(
    rows + 1,
    (iy) => List.generate(
        cols + 1,
        (ix) =>
            noise.fbm(ix * cell * freq / 10 + t * 0.3, iy * cell * freq / 10)),
    growable: false,
  );

  // Terrain fills the bands between the lines. See _terrain.
  if (spec.choice("contourKind") == 1) {
    _terrain(canvas, rect, spec, field, cols, rows, cell, levels);
  }
  var weight = spec.p("weight");
  var every = spec.p("major").round();

  for (var l = 1; l < levels; l++) {
    var level = l / levels;
    var path = Path();
    for (var iy = 0; iy < rows; iy++) {
      for (var ix = 0; ix < cols; ix++) {
        _marchCell(
            path, field, ix, iy, level, cell, Offset(rect.left, rect.top));
      }
    }
    var mid = (l - levels / 2).abs() / (levels / 2);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, cell * 0.05) *
              weight *
              (every > 0 && l % every == 0 ? 2 : 1)
          ..color = _fade(
              every > 0
                  ? (l % every == 0 ? spec.accent : spec.foreground)
                  : (l.isEven ? spec.foreground : spec.accent),
              spec.intensity * (1 - mid * 0.6)));
  }
}

/// _marchCell adds the segment (or two) crossing one cell at [level].
///
/// The sixteen cases folded by symmetry, interpolated along each edge
/// (midpoints give staircases).
void _marchCell(Path path, List<List<double>> f, int ix, int iy, double level,
    double cell, Offset origin) {
  var tl = f[iy][ix], tr = f[iy][ix + 1];
  var br = f[iy + 1][ix + 1], bl = f[iy + 1][ix];

  var code = (tl > level ? 8 : 0) |
      (tr > level ? 4 : 0) |
      (br > level ? 2 : 0) |
      (bl > level ? 1 : 0);
  if (code == 0 || code == 15) return;

  var x0 = origin.dx + ix * cell, y0 = origin.dy + iy * cell;
  Offset top() => Offset(x0 + cell * _mix(tl, tr, level), y0);
  Offset right() => Offset(x0 + cell, y0 + cell * _mix(tr, br, level));
  Offset bottom() => Offset(x0 + cell * _mix(bl, br, level), y0 + cell);
  Offset left() => Offset(x0, y0 + cell * _mix(tl, bl, level));

  void seg(Offset a, Offset b) {
    path.moveTo(a.dx, a.dy);
    path.lineTo(b.dx, b.dy);
  }

  switch (code) {
    case 1:
    case 14:
      seg(left(), bottom());
    case 2:
    case 13:
      seg(bottom(), right());
    case 3:
    case 12:
      seg(left(), right());
    case 4:
    case 11:
      seg(top(), right());
    case 6:
    case 9:
      seg(top(), bottom());
    case 7:
    case 8:
      seg(left(), top());
    // The two ambiguous saddles: both segments are drawn, so no contour is
    // left open.
    case 5:
      seg(left(), top());
      seg(bottom(), right());
    case 10:
      seg(top(), right());
      seg(left(), bottom());
  }
}

double _mix(double a, double b, double level) =>
    (b - a).abs() < 1e-9 ? 0.5 : ((level - a) / (b - a)).clamp(0.0, 1.0);

/// _rings is concentric rings travelling out of, or into, a point.
///
/// Each ring has a life: born at [RingSpec.from], travelling to [RingSpec.to]
/// (one is the far corner of the page), with the set spread evenly through
/// that life so it reads as a procession.
///
/// [page] is the canvas, not the painted [area], which is larger when the
/// pattern is turned: "the edge of the page" must mean the page.
void _rings(ui.Canvas canvas, Rect area, Rect page, ProceduralSpec spec,
    double t, int round, CanvasImageSource? images) {
  var ring = spec.rings;
  var count = ring.count.clamp(1, 200);
  var centre = Offset(
    page.left + page.width * ring.centreX,
    page.top + page.height * ring.centreY,
  );
  // The distance to the farthest corner, so a ring set off-centre still
  // crosses the whole page.
  var reach = [
    (centre - page.topLeft).distance,
    (centre - page.topRight).distance,
    (centre - page.bottomLeft).distance,
    (centre - page.bottomRight).distance,
  ].reduce(math.max);
  var unit = math.min(page.width, page.height);
  // One life per [proceduralPass] at speed one.
  var moving = spec.animated ? t * 0.15 : 0.0;

  for (var i = 0; i < count; i++) {
    // Per-ring numbers come from the seed and index, so a ring keeps its
    // width and colour as it travels.
    var jitter = (hash(spec.seed + 11, i, 0) - 0.5) * ring.spacingJitter;
    // Age always runs forwards: shrinking rings are born at the outside,
    // not played backwards. Negative is not yet born (see RingSpec.buildUp).
    var age = ring.ageOf(i, moving, jitter: jitter);
    // Whether something of age [at] is born and not yet gone. Also asked of
    // the pictures a ring carries, which can be offset in age from it and so
    // outlive it.
    bool alive(double at) =>
        !(ring.buildUp && spec.animated && at < 0) && !(spec.inRuns && at > 1);
    var through = ring.spread(i, moving, jitter: jitter);

    // Spacing bunches rings towards one end (a half is even). A function of
    // age because a carried icon may be ahead or behind the ring (see
    // RingIcon.driftWhen) and must follow the same journey.
    var bias = ring.spacing.clamp(0.05, 0.95);
    double radiusAt(double at) {
      var eased = math.pow(at, bias <= 0 ? 1 : (0.5 / bias)).toDouble();
      var place = ring.inward ? 1 - eased : eased;
      return reach * (ring.from + (ring.to - ring.from) * place);
    }

    // The fade follows the life, not the place on the page.
    var fade = ring.alphaAt(through);
    var alpha = fade * spec.intensity.clamp(0.0, 1.0);
    // An invisible ring may still carry a visible picture (see
    // RingIcon.opacity and holdIn), so only skip it when it carries none.
    var showRing = alpha > 0.004 && alive(age);
    var carries = ring.icons
        .any((carried) => carried.ring - 1 == i && carried.asset.isNotEmpty);
    if (!showRing && !carries) continue;
    if (hash(spec.seed, i, 3) > spec.density * 1.6) continue;

    var radius = radiusAt(through);
    if (radius <= 0.5) continue;

    var width = math.max(
        0.4,
        unit *
            ring.width *
            (1 + (hash(spec.seed + 3, i, 1) - 0.5) * 2 * ring.widthJitter));
    // A soft edge fades the width as well as the alpha: a hairline at a
    // fifth of its strength looks much like one at half, so alpha alone does
    // not read as arriving.
    if (ring.edge == RingEdge.soft) width *= 0.25 + 0.75 * fade;

    // Every accentEvery-th ring in the accent, so the set has a rhythm
    // rather than looking like a target, with colorJitter towards the other.
    var accent = ring.accentEvery > 0 && i % ring.accentEvery == 0;
    var mix = hash(spec.seed + 7, i, 2) * ring.colorJitter;
    var color = Color.lerp(accent ? spec.accent : spec.foreground,
        accent ? spec.foreground : spec.accent, mix)!;

    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = _fade(color, alpha);

    if (showRing) _drawRing(canvas, centre, radius, spec, ring, i, paint, area);

    // Icons after the ring so they sit on the line, at the ring's strength.
    for (var icon in ring.icons) {
      if (icon.ring - 1 != i || icon.asset.isEmpty) continue;
      _drawRingIcons(canvas, images, icon, spec, ring, i, centre, age, alive,
          radiusAt, spec.intensity.clamp(0.0, 1.0), unit, round);
    }
  }

  // Icons on no ring (RingIcon.ring 0). See _drawLooseIcon.
  for (var icon in ring.icons) {
    if (icon.ring > 0 || icon.asset.isEmpty) continue;
    var span = proceduralRunSeconds(spec);
    var over = !spec.animated || span <= 0 ? 0.0 : t / span;
    if (spec.inRuns && over > 1) continue;
    var within = over % 1;
    _drawLooseIcon(
        canvas,
        images,
        icon,
        spec,
        ring,
        centre,
        within < 0 ? within + 1 : within,
        spec.intensity.clamp(0.0, 1.0),
        unit,
        round);
  }
}

/// _Pictures is the weighted set of pictures an icon may be drawn as (weight
/// two is picked twice as often as one; nought never). Each asset is
/// resolved once.
class _Pictures {
  final CanvasImageSource images;
  final List<(String, double)> choices;
  final double weighed;
  final Map<String, (CanvasVector?, ui.Image?, Size)?> made = {};

  _Pictures._(this.images, this.choices, this.weighed);

  static _Pictures? of(CanvasImageSource? images, RingIcon icon) {
    if (images == null) return null;
    var choices = <(String, double)>[
      if (icon.asset.isNotEmpty) (icon.asset, icon.weight.clamp(0.0, 100.0)),
      for (var pick in icon.also)
        if (pick.asset.isNotEmpty) (pick.asset, pick.weight.clamp(0.0, 100.0)),
    ];
    var weighed = choices.fold(0.0, (sum, c) => sum + c.$2);
    if (choices.isEmpty || weighed <= 0) return null;
    return _Pictures._(images, choices, weighed);
  }

  /// chosen is the picture for one place, by weight.
  String chosen(double roll) {
    var want = roll.clamp(0.0, 0.999999) * weighed;
    for (var (asset, weight) in choices) {
      want -= weight;
      if (want < 0) return asset;
    }
    return choices.last.$1;
  }

  (CanvasVector?, ui.Image?, Size)? drawing(String asset) =>
      made.putIfAbsent(asset, () {
        var vector = images.resolveVector(asset);
        var bitmap = vector == null
            ? images.resolve(asset, const BackgroundRemoval())
            : null;
        var natural = vector?.size ??
            (bitmap == null
                ? Size.zero
                : Size(bitmap.width.toDouble(), bitmap.height.toDouble()));
        if (natural.width <= 0 || natural.height <= 0) return null;
        return (vector, bitmap, natural);
      });
}

/// _stamp draws one picture at one place.
void _stamp(ui.Canvas canvas, _Pictures from, RingIcon icon, String asset,
    Offset at, double turn, double side, double alpha) {
  if (side < 1 || alpha <= 0.004) return;
  var drawing = from.drawing(asset);
  if (drawing == null) return;
  var (vector, bitmap, natural) = drawing;

  var paint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
  if (icon.tinted) {
    // srcIn keeps the shape and replaces the colour. The fade stays in the
    // paint only: filter and paint alphas multiply.
    paint.colorFilter = ui.ColorFilter.mode(icon.tint, BlendMode.srcIn);
  }
  // Fitted in proportion to a square of [side], so different shapes look
  // the same size.
  var scale = side / math.max(natural.width, natural.height);

  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (turn != 0) canvas.rotate(turn);
  canvas.scale(scale);
  canvas.translate(-natural.width / 2, -natural.height / 2);
  if (vector != null) {
    // A vector has its own colours and alpha, so the paint goes on a layer.
    canvas.saveLayer(Rect.fromLTWH(0, 0, natural.width, natural.height), paint);
    canvas.drawPicture(vector.picture);
    canvas.restore();
  } else {
    canvas.drawImage(bitmap!, Offset.zero, paint);
  }
  canvas.restore();
}

/// _iconStrength is how strongly an icon is drawn at [at] in the ring's
/// life: its own opacity if set, otherwise the ring's, skipping the fades
/// it holds (holdIn, holdOut).
double _iconStrength(RingIcon icon, RingSpec ring, double at) =>
    icon.opacity ??
    ring.alphaAt(at, arriving: !icon.holdIn, leaving: !icon.holdOut);

/// _iconSide clamps [side] to the icon's smallest and largest, which are
/// fractions of the page ([unit]) so a growing ring cannot grow it off the
/// page.
double _iconSide(RingIcon icon, double side, double unit) {
  if (icon.smallest != null) side = math.max(side, icon.smallest! * unit);
  if (icon.largest != null) side = math.min(side, icon.largest! * unit);
  return side;
}

/// _drawLooseIcon draws a picture that is on no ring.
///
/// Its moment is how far through a run the pattern is, its size a fraction
/// of the page, and it sits at the rings' centre. With both fades held it is
/// a badge there for the whole animation.
void _drawLooseIcon(
    ui.Canvas canvas,
    CanvasImageSource? images,
    RingIcon icon,
    ProceduralSpec spec,
    RingSpec ring,
    Offset centre,
    double through,
    double strength,
    double unit,
    int round) {
  if (icon.firstRunOnly && round > 0) return;
  var from = _Pictures.of(images, icon);
  if (from == null) return;

  var alpha = (_iconStrength(icon, ring, through) * strength).clamp(0.0, 1.0);
  var side = _iconSide(icon, unit * icon.size.clamp(0.01, 4.0), unit);
  _stamp(canvas, from, icon, from.chosen(hash(spec.seed + 23, 0, 99)), centre,
      icon.turn * math.pi / 180, side, alpha);
}

/// _drawRingIcons puts one icon setting's pictures on a ring.
///
/// In the middle: one picture at the centre, sized against the ring so it
/// grows with it. Around: several spaced along the ring, each turned to face
/// out and drifted on its own (see RingDrift).
void _drawRingIcons(
    ui.Canvas canvas,
    CanvasImageSource? images,
    RingIcon icon,
    ProceduralSpec spec,
    RingSpec ring,
    int index,
    Offset centre,
    double age,
    bool Function(double) alive,
    double Function(double) radiusAt,
    double strength,
    double unit,
    int round) {
  if (strength <= 0.004) return;
  if (icon.firstRunOnly && round > 0) return;
  var from = _Pictures.of(images, icon);
  if (from == null) return;

  /// moment is where a picture offset by [drift] is in the ring's life, or
  /// null when not yet born or already gone. Wrapped rather than clamped,
  /// or a picture drifted back would sit frozen at the start.
  double? moment(double drift) {
    var at = age + drift;
    if (!alive(at)) return null;
    var wrapped = at % 1;
    return wrapped < 0 ? wrapped + 1 : wrapped;
  }

  if (icon.place == RingIconPlace.middle) {
    var mine = moment(0);
    if (mine == null) return;
    var side =
        _iconSide(icon, radiusAt(mine) * icon.size.clamp(0.01, 4.0), unit);
    var alpha = (_iconStrength(icon, ring, mine) * strength).clamp(0.0, 1.0);
    _stamp(canvas, from, icon, from.chosen(hash(spec.seed + 23, index, 99)),
        centre, icon.turn * math.pi / 180, side, alpha);
    return;
  }

  var many = icon.count.clamp(1, 60);
  for (var n = 0; n < many; n++) {
    // A roll per picture and per property, so they do not move together.
    double roll(int of) => hash(spec.seed + 23, index * 64 + of, n);

    // Drifted ahead of or behind its ring in age: it sits at the radius the
    // ring had then, and arrives and leaves then too.
    var mine = moment(icon.driftWhen.at(roll(0)));
    if (mine == null) continue;
    var radius = radiusAt(mine);
    if (radius <= 0.5) continue;

    // Scatter in gaps between pictures, so it is the same whatever the
    // count.
    var gap = 2 * math.pi / many;
    var angle = n * gap + icon.driftWhere.at(roll(1)) * gap;

    var side = _iconSide(
        icon,
        radius *
            (icon.size * (1 + icon.driftSize.at(roll(2)))).clamp(0.01, 4.0),
        unit);

    // A share of the icon's strength (driftFade).
    var alpha = (_iconStrength(icon, ring, mine) *
            strength *
            icon.driftFade.at(roll(4)))
        .clamp(0.0, 1.0);

    _stamp(
        canvas,
        from,
        icon,
        from.chosen(roll(5)),
        centre + Offset(math.cos(angle), math.sin(angle)) * radius,
        angle +
            math.pi / 2 +
            (icon.turn + icon.driftTurn.at(roll(3))) * math.pi / 180,
        side,
        alpha);
  }
}

/// _drawRing draws one ring. A clean or only distorted ring is one call; one
/// with noise, glitch or grunge is walked round in steps.
void _drawRing(ui.Canvas canvas, Offset centre, double radius,
    ProceduralSpec spec, RingSpec ring, int index, Paint paint, Rect area) {
  var wobbly = ring.noise > 0 || ring.grunge > 0;
  var broken = ring.glitch > 0;

  if (!wobbly && !broken) {
    if (ring.distortion <= 0) {
      canvas.drawCircle(centre, radius, paint);
      return;
    }
    // Distortion alone is a squashed, leaned oval.
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(hash(spec.seed + 5, index, 4) * math.pi);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset.zero,
            width: radius * 2 * (1 - ring.distortion * 0.5),
            height: radius * 2 * (1 + ring.distortion * 0.35)),
        paint);
    canvas.restore();
    return;
  }

  // Enough steps that the wobble is not a polygon, few enough to be cheap.
  var steps = (36 + radius * 0.35).clamp(36, 220).round();
  var lean = hash(spec.seed + 5, index, 4) * math.pi;
  var squashX = 1 - ring.distortion * 0.5;
  var squashY = 1 + ring.distortion * 0.35;
  var full = paint.strokeWidth;

  Offset at(double turn, double wobble) {
    var x = math.cos(turn) * radius * squashX * wobble;
    var y = math.sin(turn) * radius * squashY * wobble;
    // Leaned about the centre, so a squashed ring lies at an angle.
    return centre +
        Offset(x * math.cos(lean) - y * math.sin(lean),
            x * math.sin(lean) + y * math.cos(lean));
  }

  var path = ui.Path();
  var open = false;
  for (var s = 0; s <= steps; s++) {
    var f = s / steps;
    var turn = f * 2 * math.pi;

    // The outline's wander: jitter plus a slow three-lobed swell.
    var wobble = 1 +
        (hash(spec.seed + 13, index, s % 17) - 0.5) * ring.noise * 0.12 +
        math.sin(turn * 3 + index) * ring.noise * 0.03;

    // Glitch: whole slices knocked out of place, their neighbours not.
    if (broken) {
      var slice = (f * 12).floor();
      if (hash(spec.seed + 17, index, slice) < ring.glitch * 0.5) {
        wobble += (hash(spec.seed + 19, index, slice) - 0.5) * ring.glitch;
      }
    }

    var gone =
        ring.grunge > 0 && hash(spec.seed + 23, index, s) < ring.grunge * 0.45;
    if (gone) {
      open = false;
      continue;
    }

    var spot = at(turn, wobble);
    if (!open) {
      path.moveTo(spot.dx, spot.dy);
      open = true;
    } else {
      path.lineTo(spot.dx, spot.dy);
    }
  }

  if (ring.grunge > 0) {
    // Grunge thins the line as well as breaking it.
    paint.strokeWidth = math.max(0.4, full * (1 - ring.grunge * 0.35));
  }
  canvas.drawPath(path, paint);
  paint.strokeWidth = full;
}

// --------------------------------------------------------------------------
// Glyph drawing
// --------------------------------------------------------------------------

/// _glyphCache holds laid-out single characters.
///
/// A dense rain draws thousands of glyphs a frame, and laying each out is the
/// most expensive thing in this file. Alpha is quantised to sixteen steps so
/// a fading tail reuses painters and the cache stays bounded.
final Map<String, TextPainter> _glyphCache = {};

/// clearGlyphs lets go of every glyph laid out and kept.
void clearGlyphs() {
  for (var painter in _glyphCache.values) {
    painter.dispose();
  }
  _glyphCache.clear();
}

/// _maxGlyphCache is where the cache is emptied wholesale: rare, and cheaper
/// than tracking ages on every lookup.
const int _maxGlyphCache = 4096;

void _drawGlyph(
    ui.Canvas canvas, String glyph, Offset at, double size, Color color,
    [String? family]) {
  if (color.a <= 0.004 || size < 1) return;

  var bucket = (color.a * 15).round();
  var key = "$glyph|$family|${size.round()}|"
      "${(color.r * 255).round()},${(color.g * 255).round()},"
      "${(color.b * 255).round()}|$bucket";

  var painter = _glyphCache[key];
  if (painter == null) {
    if (_glyphCache.length >= _maxGlyphCache) _glyphCache.clear();
    painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          height: 1,
          color: color.withValues(alpha: bucket / 15),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _glyphCache[key] = painter;
  }
  painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
}

/// _halftone is the comic-book dot screen: a rotated grid of dots whose size
/// says how much ink is on the page there.
///
/// Tilted at least fifteen degrees, which makes the eye see tone rather than
/// a dot grid.
void _halftone(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var step = math.max(3.0, _unit(rect, spec) * 1.2);
  var noise = ValueNoise(spec.seed);
  var paint = Paint();

  // The screen angle, tilted a little further by the variation.
  var angle = (15 + spec.variation * 30) * math.pi / 180;
  var cos = math.cos(angle), sin = math.sin(angle);

  var reach = (rect.width + rect.height);
  var cols = (reach / step).ceil();
  var rows = (reach / step).ceil();
  var centre = rect.center;
  var shape = spec.choice("dotShape");
  var inkKind = spec.choice("ink");
  var far = math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2;

  for (var iy = -rows; iy <= rows; iy++) {
    for (var ix = -cols; ix <= cols; ix++) {
      var gx = ix * step, gy = iy * step;
      var p = Offset(
        centre.dx + gx * cos - gy * sin,
        centre.dy + gx * sin + gy * cos,
      );
      if (!rect.inflate(step).contains(p)) continue;

      // Ink: by default a smooth field, so dots swell in drifts rather than
      // an even stipple; 1 is a fade across, 2 a fade from the centre.
      var ink = switch (inkKind) {
        1 => ((p.dx - rect.left) / rect.width * 0.95 +
                (noise.fbm(p.dx / rect.width * 4, p.dy / rect.height * 4,
                            octaves: 2) -
                        0.5) *
                    0.15 *
                    spec.variation)
            .clamp(0.0, 1.0),
        2 => (1 - (p - rect.center).distance / far).clamp(0.0, 1.0),
        _ => noise.fbm(
            (p.dx / rect.width) * 3 + t * 0.15, (p.dy / rect.height) * 3,
            octaves: 3),
      };
      var size = step * 0.62 * ink * (0.35 + spec.density * 1.3);
      if (size <= 0.15) continue;

      // Accent where the drifted ink is heaviest; not on fades, where it
      // would be a hard-edged blob.
      paint.color = _fade(
          inkKind == 0 && ink > 0.72 ? spec.accent : spec.foreground,
          spec.intensity.clamp(0.0, 1.0));
      if (shape == 0) {
        canvas.drawCircle(p, size, paint);
      } else {
        _screenDot(canvas, p, size, step, shape, cos, sin, paint);
      }
    }
  }
}

/// _speedLines is the ray burst: tapered wedges thrown out from a point.
///
/// Wedges rather than strokes: inked speed lines are thick at the frame
/// edge and come to nothing at the middle.
void _speedLines(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  if (spec.choice("burstKind") == 1) {
    return _parallelLines(canvas, rect, spec, t);
  }
  // By default the point wanders with the seed but stays near the middle (a
  // burst on a corner is a fan); "aim" can centre it or place it.
  var from = switch (spec.choice("aim")) {
    1 => rect.center,
    2 => Offset(rect.left + rect.width * spec.p("aimX"),
        rect.top + rect.height * spec.p("aimY")),
    _ => Offset(
        rect.center.dx + (hash(spec.seed, 3, 1) - 0.5) * rect.width * 0.4,
        rect.center.dy + (hash(spec.seed, 5, 2) - 0.5) * rect.height * 0.4,
      ),
  };
  var reach = (rect.width + rect.height) * 0.9;
  var count = (12 + spec.density * 90).round();
  var paint = Paint();

  for (var i = 0; i < count; i++) {
    // Spread unevenly, or the rays comb into a moiré where they meet.
    var about = (i / count) * 2 * math.pi +
        (hash(spec.seed + 11, i, 0) - 0.5) * spec.variation * 0.7 +
        t * 0.05;
    var width =
        (0.004 + hash(spec.seed + 17, i, 1) * 0.03 * (0.4 + spec.variation)) *
            2 *
            math.pi;
    // A gap in the middle, so the burst has an eye to it.
    var near =
        reach * (0.03 + hash(spec.seed + 23, i, 2) * 0.35 * spec.variation);
    var far = reach * (0.7 + hash(spec.seed + 29, i, 3) * 0.5);

    Offset at(double a, double d) =>
        Offset(from.dx + math.cos(a) * d, from.dy + math.sin(a) * d);

    var path = ui.Path()
      ..moveTo(at(about, near).dx, at(about, near).dy)
      ..lineTo(at(about - width, far).dx, at(about - width, far).dy)
      ..lineTo(at(about + width, far).dx, at(about + width, far).dy)
      ..close();

    paint.color = _fade(
        i % 7 == 0 ? spec.accent : spec.foreground,
        (spec.intensity * (0.55 + hash(spec.seed + 31, i, 4) * 0.45))
            .clamp(0.0, 1.0));
    canvas.drawPath(path, paint);
  }
}

/// _crosshatch is inked hatching: one to three crossed passes of lines, more
/// with density.
void _crosshatch(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var step = math.max(2.0, _unit(rect, spec) * 0.9);
  var shaded = spec.choice("tone") == 1;
  var wobble = spec.p("wobble");
  var noise = ValueNoise(spec.seed + 3);
  var reach = rect.width + rect.height;
  var passes = spec.density > 0.66 ? 3 : (spec.density > 0.33 ? 2 : 1);

  for (var pass = 0; pass < passes; pass++) {
    var angle = (30 + pass * 55 + spec.variation * 25) * math.pi / 180;
    var paint = Paint()
      ..color = _fade(pass == 2 ? spec.accent : spec.foreground,
          (spec.intensity * (0.75 - pass * 0.18)).clamp(0.0, 1.0))
      ..strokeWidth = math.max(0.6, step * 0.1 * (1 + spec.density))
      ..strokeCap = StrokeCap.round;

    var across = Offset(math.cos(angle), math.sin(angle));
    var along = Offset(-across.dy, across.dx);
    var lines = (reach / step).ceil();
    for (var i = -lines; i <= lines; i++) {
      // Hand-inked: unevenly spaced, uneven lengths.
      var off =
          i * step + hashRange(spec.seed + pass, i, 0, -1, 1) * step * 0.3;
      var mid = rect.center + along * off;
      var half = reach /
          2 *
          (0.75 +
              hash(spec.seed + pass * 7, i, 3) * 0.5 * (0.3 + spec.variation));
      if (!shaded && wobble <= 0) {
        canvas.drawLine(mid - across * half, mid + across * half, paint);
      } else {
        _hatchLine(canvas, rect, mid, across, along, half, step, pass, i,
            shaded, wobble, noise, spec.seed, paint);
      }
    }
  }
}

/// _splatter is thrown ink: blobs, satellite droplets round them, and drips
/// off some. Other splatKinds are in marks.dart.
void _splatter(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  switch (spec.choice("splatKind")) {
    case 1:
      return _drips(canvas, rect, spec, t);
    case 2:
      return _spray(canvas, rect, spec, t);
    case 3:
      return _splash(canvas, rect, spec, t);
    case 4:
      return _watercolour(canvas, rect, spec, t);
  }
  var unit = _unit(rect, spec);
  var blobs = (2 + spec.density * 22).round();
  var paint = Paint();

  for (var i = 0; i < blobs; i++) {
    var at = Offset(
      rect.left + hash(spec.seed + 3, i, 0) * rect.width,
      rect.top + hash(spec.seed + 5, i, 1) * rect.height,
    );
    var size = unit * (0.6 + hash(spec.seed + 7, i, 2) * 2.4);
    paint.color = _fade(i % 5 == 0 ? spec.accent : spec.foreground,
        spec.intensity.clamp(0.0, 1.0));

    // The blob: a wobbling closed curve, not a circle.
    var path = ui.Path();
    const steps = 18;
    for (var s = 0; s <= steps; s++) {
      var a = s / steps * 2 * math.pi;
      var r = size *
          (0.6 +
              0.55 *
                  hash(spec.seed + 11, i, s % steps) *
                  (0.5 + spec.variation) +
              0.12 * math.sin(a * 3 + t));
      var p = Offset(at.dx + math.cos(a) * r, at.dy + math.sin(a) * r);
      s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);

    // Satellites, which are most of what makes it read as a splash.
    var drops = (3 + spec.variation * 14).round();
    for (var d = 0; d < drops; d++) {
      var away = size * (1.3 + hash(spec.seed + 13, i, d) * 4);
      var about = hash(spec.seed + 17, i, d + 40) * 2 * math.pi;
      var r = size * 0.08 * (0.4 + hash(spec.seed + 19, i, d + 80) * 1.8);
      canvas.drawCircle(
          Offset(
              at.dx + math.cos(about) * away, at.dy + math.sin(about) * away),
          r,
          paint);
    }

    // A drip on some blobs.
    if (hash(spec.seed + 23, i, 9) < 0.4) {
      var run = size * (1 + hash(spec.seed + 29, i, 10) * 3);
      var wide = size * 0.22;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(at.dx - wide / 2, at.dy, wide, run),
              Radius.circular(wide / 2)),
          paint);
      canvas.drawCircle(Offset(at.dx, at.dy + run), wide * 0.8, paint);
    }
  }
}

/// _flames is fire: tongues rising from the bottom edge, each bent by a slow
/// field so it licks rather than points.
void _flames(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  if (spec.p("embers") > 0) _embers(canvas, rect, spec, t);
  if (spec.choice("flameKind") == 1) return _softFire(canvas, rect, spec, t);
  var noise = ValueNoise(spec.seed);
  var tall = spec.p("height");
  var tongues = (3 + spec.density * 26).round();

  for (var i = 0; i < tongues; i++) {
    var x = rect.left +
        (i + 0.5) / tongues * rect.width +
        hashRange(spec.seed + 3, i, 0, -1, 1) * rect.width / tongues * 0.4;
    var height = rect.height *
        (0.25 + hash(spec.seed + 5, i, 1) * 0.85 * (0.4 + spec.density)) *
        tall;
    var wide = rect.width / tongues * (0.45 + hash(spec.seed + 7, i, 2) * 0.7);

    // Both edges bent by the same field so they lean together rather than
    // cross.
    var left = ui.Path();
    var right = <Offset>[];
    const steps = 14;
    for (var s = 0; s <= steps; s++) {
      var up = s / steps;
      // Narrowing to nothing at the tip, fattest below the middle.
      var w = wide * math.sin((1 - up) * math.pi * 0.85) * (1 - up * 0.15);
      var sway = noise.fbm(i * 1.7 + up * 2.2, t * 0.6 + up * 1.1, octaves: 2);
      var lean = (sway - 0.5) * wide * 2.4 * (0.3 + spec.variation) * up;
      var y = rect.bottom - height * up;
      var cx = x + lean;
      var p = Offset(cx - w / 2, y);
      s == 0 ? left.moveTo(p.dx, p.dy) : left.lineTo(p.dx, p.dy);
      right.add(Offset(cx + w / 2, y));
    }
    for (var p in right.reversed) {
      left.lineTo(p.dx, p.dy);
    }
    left.close();

    // The body, and an accent heart inside it.
    canvas.drawPath(
        left,
        Paint()
          ..color =
              _fade(spec.foreground, (spec.intensity * 0.85).clamp(0.0, 1.0)));
    canvas.save();
    canvas.translate(x, rect.bottom);
    canvas.scale(0.5, 0.55);
    canvas.translate(-x, -rect.bottom);
    canvas.drawPath(left,
        Paint()..color = _fade(spec.accent, spec.intensity.clamp(0.0, 1.0)));
    canvas.restore();
  }
}

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
part 'surfaces.dart';
part 'tech.dart';

// generators.dart draws every procedural background.
//
// One function per style, all with the same shape: given a rectangle, a spec
// and a time, draw. None of them holds state, none of them calls Random(), and
// every one of them is a pure function of (rect, spec, time) -- so the same
// background is the same picture on the stage, in the export and on somebody
// else's machine. See noise.dart on why that matters.
//
// The controls are shared rather than per style, and each generator is written
// to interpret the same five numbers in whatever way is true of it:
//
//   density    how much of the frame it fills, 0 to 1
//   scale      the size of its repeating unit, as a fraction of the short side
//   intensity  how bright the brightest parts get
//   variation  how much it differs from itself
//   seed       which of the infinitely many versions of it this is
//
// That is what makes the shuffle button and the sliders work on every style
// without the settings bar knowing which one is showing. It is also a real
// constraint on the generators: a control that does nothing on some style is a
// control somebody will drag while wondering why nothing happens, so each of
// them is written to make all five do *something* wherever it can.

/// proceduralPass is one turn of a pattern's own clock, in seconds.
///
/// One number for every style, because "how long until this has been round
/// once" is not a question most of them can answer -- a rain falls, a flow
/// flows, and neither has a length. Six and two thirds seconds is one ring's
/// life, which is the one style that does have a cycle.
const double proceduralPass = 1 / 0.15;

/// proceduralRunSeconds is how long a complete run of [spec] takes in the
/// pattern's own time: from the first thing happening to the last thing
/// being over.
///
/// For rings that is every ring born, travelled and dissolved, with nothing
/// left on the page: the last of the set is born very nearly a life after the
/// first and then has its own life to live, so the run is close to two of
/// them. That holds whether or not the set builds up -- a set that opens full
/// is only spread across its lives at the first frame; the one at the back
/// still dies last.
double proceduralRunSeconds(ProceduralSpec spec) {
  if (spec.style != ProceduralStyle.rings) return proceduralPass;
  var many = spec.rings.count.clamp(1, 200);
  var last = (many - 1) / many;
  return proceduralPass * (1 + last);
}

/// pausedFrame is the frame the pattern is showing, given the frame the
/// document is on and a rest in the middle of the movement.
///
/// The pattern's own clock is held still while the document's goes on, so
/// what comes after the rest is exactly what would have come next: nothing
/// is skipped and nothing repeats. The easing either side is a slowing down
/// and a speeding up rather than a stop: over the frames it is given, the
/// movement covers half the ground it would have, which is what the integral
/// of a smooth step comes to.
double pausedFrame(double frame, ProceduralSpec spec) {
  var hold = spec.pauseFor.toDouble();
  if (hold <= 0) return frame;
  var ease = spec.pauseEase.toDouble().clamp(0.0, hold * 4);
  var stops = spec.pauseAt.toDouble();

  // The four moments: begins slowing, is still, begins moving, is up to
  // speed again.
  var slowing = stops - ease;
  var still = stops;
  var going = stops + hold;
  var upToSpeed = going + ease;

  // How far the pattern has moved through a ramp of length one, where the
  // speed runs smoothly from one to nought: x minus the integral of the
  // smooth step, which is x cubed less a quarter of x to the fourth.
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
  // And afterwards, running as before, later by everything the rest cost.
  return frame - hold - ease;
}

/// paintProcedural draws [spec] into [rect].
///
/// [time] is in seconds and is what animation advances. Passing zero is a
/// still, which is what an unanimated background and the first frame both are.
void paintProcedural(ui.Canvas canvas, Rect rect, ProceduralSpec input,
    {double time = 0, double frameRate = 0, CanvasImageSource? images}) {
  if (rect.width <= 0 || rect.height <= 0) return;
  if (!input.seamless) {
    return _paintOnce(canvas, rect, input, time, frameRate, images);
  }

  // A seamless loop. Hardly any of these movements comes back to where it
  // began of its own accord -- a flow field flows, rain falls -- so instead
  // the end of each loop is blended into its start: over the last part of
  // the loop, what the movement is doing now is faded out and what it was
  // doing one loop earlier faded in. At the end of the loop that is all the
  // earlier picture -- which is the moment just before the first frame, so
  // the last frame runs into the first without a jump. And it is the whole
  // background drawn twice, so the layers, the grain and everything else
  // loop with it.
  var rate = frameRate > 0 ? frameRate : 30.0;
  var length = input.loopFrames / rate;
  var at = time % length;
  var blend = (input.loopBlend * length).clamp(1 / rate, length);
  var into = at - (length - blend);
  _paintOnce(canvas, rect, input, at, frameRate, images);
  if (into <= 0) return;
  var w = (into / blend).clamp(0.0, 1.0);
  // Eased, so the change of weight has no corner in it either.
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

  // The colour grade is over everything the background is -- base, pattern,
  // light and lens -- and under the grain, which is the film it was shot on
  // rather than part of what was in front of the camera.
  if (fx.grades) {
    canvas.saveLayer(rect, Paint()..colorFilter = gradeFilter(fx));
  }

  canvas.save();
  canvas.clipRect(rect);

  _paintBase(canvas, rect, spec);

  // The pattern is drawn rotated inside a rectangle grown to cover the
  // corners, so turning it does not sweep an empty wedge into view. The clip
  // above keeps the overspill off the canvas.
  // A rest in the middle of the movement, if it has been asked for. Taken
  // before anything else, so that everything after it -- how fast, how many
  // frames a single pass takes -- is measured in the pattern's own time
  // rather than the document's.
  var moment = time;
  if (spec.animated && spec.pauseFor > 0 && frameRate > 0) {
    moment = pausedFrame(time * frameRate, spec) / frameRate;
  }

  var t = spec.animated ? moment * spec.speed : 0.0;
  // Which time round the movement is on, for the things that are shown on
  // the first run and not the ones after it. See RingIcon.firstRunOnly.
  var round = 0;
  if (spec.inRuns) {
    // Counted in runs rather than simply going round. Speed says nothing
    // here: a movement measured in runs is timed against the thing it is
    // under, which is counted in frames rather than in how fast it goes.
    var run = proceduralRunSeconds(spec);
    var frames = spec.passFrames.clamp(1, 100000).toDouble();
    var at = frameRate > 0 ? moment * frameRate : moment;

    // Runs with a rest between them: one run of `frames`, then `loopGap`
    // frames of the finished picture, then the next run from the start.
    var cycle = frames + spec.loopGap.clamp(0, 100000);
    round = (at / cycle).floor();
    var done = spec.loopTimes > 0 && round >= spec.loopTimes;
    // Held at the end once the last run is over, and held at the end through
    // each gap -- which for rings is an empty page.
    var within = done ? frames : at - round * cycle;
    var through = within / frames;
    // Past the end rather than exactly on it. A run that is over has to be
    // over for every ring in the set, and roughened spacing moves where a
    // ring sits in it: one left at the very last instant of its life is, with
    // a hard edge, a ring at full strength -- and it stays there, with
    // whatever it was carrying, for the rest of the canvas. A whole life
    // beyond the end is past the last of them however they are spread.
    t = through >= 1 ? run + proceduralPass : through * run;
    if (done) round = spec.loopTimes - 1;
  } else if (spec.animated) {
    // Going round for ever has runs too, even without anybody counting them:
    // one is however long the pattern takes to come back to where it began.
    var run = proceduralRunSeconds(spec);
    if (run > 0) round = (t / run).floor();
  }
  _patternLayer(canvas, rect, spec, t, round, images);

  // The layers over it, each its own pattern with its own effects, laid on
  // through a layer of its own so that its opacity and its blend apply to
  // all of it at once. A plain layer is its colour: a wash, or a fade laid
  // over everything under it.
  for (var layer in input.layers) {
    if (!layer.visible || layer.opacity <= 0) continue;
    var ls = layer.spec;
    canvas.saveLayer(
        rect,
        Paint()
          ..blendMode = layer.blend.mode
          ..color = Color.fromRGBO(0, 0, 0, layer.opacity.clamp(0.0, 1.0)));
    if (ls.style == ProceduralStyle.plain) _paintBase(canvas, rect, ls);
    // On the background's clock, at the layer's own pace.
    _patternLayer(
        canvas, rect, ls, spec.animated ? moment * ls.speed : 0, round, images);
    canvas.restore();
  }

  canvas.restore();

  // The light, then the vignette. The light is part of the scene -- something
  // shining on the pattern -- and the vignette is the lens it is all being
  // looked at through, so the lens goes last.
  if (spec.light.on) paintLight(canvas, rect, spec.light);

  if (spec.vignette > 0) _vignette(canvas, rect, spec.vignette);

  if (fx.scanlines > 0) _scanlines(canvas, rect, fx);

  if (fx.grades) canvas.restore();

  if (fx.grain > 0) {
    // Moving grain is a new draw of it every frame, as film is.
    var frame = spec.animated && fx.grainMoves
        ? (time * (frameRate > 0 ? frameRate : 24)).floor()
        : 0;
    _grain(canvas, rect, fx, spec.seed * 7919 + frame);
  }
}

/// _patternLayer draws [spec]'s pattern -- turned, faded and finished by its
/// own effects -- over whatever is already on [canvas], at time [t].
///
/// Once for the background's own pattern and once for each layer over it.
void _patternLayer(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t,
    int round, CanvasImageSource? images) {
  var fx = spec.effects;
  var area = rect;
  if (spec.rotation != 0) {
    // Grown until its own shorter side is the page's diagonal, which is the
    // least that covers every corner at every angle. Half the width plus
    // half the height, as it was, is several times that.
    var diagonal =
        math.sqrt(rect.width * rect.width + rect.height * rect.height);
    area = rect.inflate((diagonal - math.min(rect.width, rect.height)) / 2);
    // And the pattern's unit held to what it was. Every generator sizes its
    // cell, its glyph or its disc as a fraction of the shorter side of what
    // it is given -- so growing that rectangle to make room for the turn
    // scaled the whole pattern up with it, and turning a background by a
    // degree zoomed into it.
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
        paintPitch(canvas, area, s);
      case ProceduralStyle.metal:
        _metal(canvas, area, s);
      case ProceduralStyle.surface:
        _surface(canvas, area, s);
    }
  }

  // A colour of the generator's own that fades is drawn on a layer of its
  // own: the pattern with that colour white and the other one clear -- which
  // is where that colour falls, and how much -- and the fade painted through
  // it. Each generator goes on drawing in flat colours and knows nothing of
  // the fade. A layer per faded colour, and only where one fades.
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

  // Drawn straight onto the canvas where nothing is done to it afterwards,
  // which is most backgrounds. Otherwise the pattern is recorded once and
  // laid down as many times as the effects need it -- once for itself and
  // once more for a glow -- through a layer that masks, softens and fades
  // it without touching the base underneath.
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
    // A bloom is the pattern again, spread wide and added over itself, so
    // that it brightens what is around the bright parts and never darkens
    // anything. Past one it is laid twice.
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
  // Turning the hue round the grey axis, weighted by how bright each primary
  // looks, so that a turn keeps the picture as light as it was.
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

/// _masks takes the pattern away where the effects say it should not be:
/// away from the focus, and out of the area kept clear.
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
  // Full strength out to a little short of the edge of the area, and nothing
  // a little past it: softness spreads the change across the edge rather
  // than moving the edge.
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
      // An oval the shape of the frame, so a wide banner keeps a wide space
      // clear in its middle rather than a circle.
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
/// what is under it.
///
/// Points rather than a noise picture, so it is as fine at an export four
/// times the width as it is on the stage -- grain is measured against the
/// frame, like everything else, and a picture of it would have to be made
/// again at every size anyway.
void _grain(ui.Canvas canvas, Rect rect, EffectsSpec fx, int seed) {
  var short = math.min(rect.width, rect.height);
  var dot = math.max(0.6, short * fx.grainSize / 1000);
  var cell = dot * 1.6;
  // No more than a few hundred thousand specks, however big the frame: past
  // that the grain is coarsened rather than the export slowed to a crawl.
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

/// paintLight throws one light across the finished background.
///
/// Drawn over the pattern rather than known about by each generator, which is
/// what makes it work on all twenty-odd of them and what means adding a style
/// does not mean writing lighting code again.
///
/// Added rather than painted over: light is what a surface sends back on top
/// of what it was already sending back, so a pool of it over a pattern lifts
/// the pattern instead of hiding it. Painted over -- which is what a plain
/// alpha blend does -- a bright light is a flat disc of colour with the
/// pattern lost underneath it.
void paintLight(ui.Canvas canvas, Rect rect, LightSpec light) {
  if (rect.width <= 0 || rect.height <= 0 || light.brightness <= 0) return;

  var radius = math.max(rect.width, rect.height) * light.size.clamp(0.01, 3.0);
  if (radius <= 0) return;

  // Past full, the light burns towards white rather than simply becoming more
  // of its own colour, which is what an overexposed light does.
  var over = (light.brightness - 1).clamp(0.0, 1.0);
  var colour = Color.lerp(light.color, const Color(0xFFFFFFFF), over)!;
  var alpha = (light.brightness.clamp(0.0, 1.0) * colour.a).clamp(0.0, 1.0);

  // Where the light stops falling off. At nought it fades the whole way from
  // the middle; at one it is a hard-edged circle with a thin edge left so it
  // is not aliased into a saucer.
  var hard = light.falloff.clamp(0.0, 1.0);

  var centre = Offset(
    rect.left + rect.width * light.x,
    rect.top + rect.height * light.y,
  );

  canvas.save();
  canvas.clipRect(rect);
  canvas.translate(centre.dx, centre.dy);
  // Off a compass, like every other direction in a canvas: 0 up the page.
  canvas.rotate(light.direction * math.pi / 180);

  // A raking light lands as a long pool rather than a round one, thrown
  // forward from where the light is. Scaling the canvas rather than building
  // an elliptical gradient keeps the falloff the same shape however far it
  // is stretched.
  var stretch = 1 + light.reach.clamp(0.0, 1.0) * 2.4;
  canvas.scale(1, stretch);
  // Forward, so that moving the light moves the near edge of the pool and not
  // its middle: a light high on the page with a reach on it should look like
  // it is coming in from off the page rather than hanging in the middle of
  // its own glow.
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

/// _metal draws a sheet of metal.
///
/// A surface rather than a pattern, which is the thing this list did not
/// have: every other style is marks on a ground, and a title plate or a panel
/// behind a logo wants the ground itself to be the thing.
///
/// It is built the way a surface is built rather than drawn the way a picture
/// is drawn -- a height field, and then a light shone across it. That is the
/// whole difference between this and what it replaced, which laid horizontal
/// lines and little dark ellipses over a gradient and looked like exactly
/// that. Nothing here draws a scratch; the scratches are low places in the
/// field, and what makes them visible is that the surface tilts there.
///
/// Which is also what makes the shine behave. A highlight is the light coming
/// back off a slope towards the eye, so it lands on the edges of the dents,
/// along the ridges of the brushing and nowhere on the rust -- rust scatters
/// -- without any of that being arranged. It could not be arranged with a
/// gradient band across the sheet, which is what the shine setting used to be.
///
/// Three kinds of noise, because they make three different things:
///   - the brushing is smooth noise, stretched along the sheet, so it is long
///     one way and short the other. Roughness is how tight it is: sparse and
///     nearly flat at nought, finely ground at one.
///   - the dents are cellular noise -- the distance to the nearest of a set of
///     scattered points -- which is the only one of the three that makes
///     rounded things at random intervals.
///   - the scratches are ridged noise, which is smooth noise folded at its
///     middle so that every crossing comes to a crease. Thresholded high, what
///     is left is long thin wandering lines.
///
/// The shared controls mean what they mean everywhere else: Size is how big
/// the features are, Brightness is how hard the light is, Variation is how far
/// the brushing is stretched, and Density is how deep the relief goes -- a
/// sheet at nought density is a photograph of one, flat.
void _metal(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var m = spec.metal;
  var short = math.min(rect.width, rect.height);
  if (short <= 0) return;

  // The lattice the surface is shaded on: a point per pixel, capped so that a
  // wall-sized export does not shade half a million of them. A point per
  // pixel and not one per two, because the lattice is a hard ceiling on how
  // fine the brushing can be -- nothing smaller than two cells across can be
  // represented at all, and brushing that cannot be fine is ripples.
  var cols = rect.width.round().clamp(8, 448);
  var rows = rect.height.round().clamp(8, 448);
  var stepX = rect.width / cols, stepY = rect.height / rows;

  // Everything below works in units of the shorter side, so the same spec is
  // the same sheet on the stage at 400px and in an export at 2400.
  // How big the features are, against the Size control's own middle. The
  // floor is low enough to reach a blasted, granular finish -- grain a couple
  // of pixels across -- rather than stopping at "finely brushed", which is
  // where a floor of a quarter left it.
  var size = math.max(0.06, spec.scale / 0.05);

  // Nothing may repeat faster than the lattice can carry it. Past about two
  // cells a feature is not fine, it is aliased -- which is what turning the
  // Size right down used to do: the grain stopped getting finer at its own
  // ceiling while the dents and the scratches ran straight past theirs, and a
  // sheet asked for granular came back covered in pebbles.
  var ceiling = math.min(cols, rows) / 2.2;
  double carried(double frequency) => math.min(frequency, ceiling);

  var brush = ValueNoise(spec.seed);
  var crease = ValueNoise(spec.seed + 4099);
  var crust = ValueNoise(spec.seed + 7717);
  var patch = ValueNoise(spec.seed + 1229);
  var sheen = ValueNoise(spec.seed + 3313);

  // Every relief below is given as the slope it should reach rather than as a
  // depth, and its depth worked out from that. They are not the same thing:
  // the steepness of a wave is its height times how often it happens, so a
  // fixed depth at ten times the frequency is ten times the slope -- which is
  // why grain fine enough to look like brushing, given a depth, came out as a
  // sheet of corrugated iron. The light only ever sees the slope.
  double depthFor(double slope, double frequency) =>
      slope / math.max(1.0, frequency);

  // How often the brushing repeats across the sheet. Sparse and broad at
  // nought, tight and fine at one -- and held under what the lattice can
  // actually carry, since anything finer than two cells is not fine, it is
  // noise.
  var across = carried(math.max(3.0, (10 + m.roughness * 110) / size));
  // And how far it is stretched along the sheet. A hairline finish and a
  // coarse orbital sanding differ in exactly this and in nothing else. From
  // one -- the same in both directions, which is a blasted or granular
  // finish rather than a brushed one -- up to a long hairline drag.
  var stretch = 1 + spec.variation * 26;
  var along = math.max(0.6, across / stretch);
  var grainDepth = depthFor(0.2 + m.roughness * 1.0, across);

  // The slow unevenness in the metal itself, under the brushing: rolling
  // marks, the sheet not being quite flat. Its own frequency, worked out the
  // same way everything else is -- given the depth for a frequency of two
  // while actually running at seven times that, it got seven times steeper as
  // the Size came down, and drowned the grain it was supposed to sit under.
  var swellAlong = carried(1.7 / size), swellAcross = carried(2.3 / size);
  var swellDepth = depthFor(0.18, math.max(swellAlong, swellAcross));

  // Where the rust has taken hold. Smooth noise piles up around its middle and
  // almost never reaches its ends, so these are the levels the field actually
  // crosses rather than a fraction of its nominal range.
  var rustLevel = 0.72 - m.rust * 0.38;

  var dentSize = carried(13 / size);
  var dentDepth = depthFor(0.16 * m.damage, dentSize);
  // Long and thin: a scratch is something dragged, so it runs a long way in
  // one direction and hardly wanders across it at all. Nearer isotropic, the
  // creases of a folded field join into a web and the sheet comes out looking
  // like cracked paint rather than scratched steel.
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

      // Brushed: long one way, short the other.
      // One octave rather than a stack of them: the octaves under the top one
      // are the same shape at half the frequency, which on a brushed finish is
      // a slow swell running through the grain -- and a slow swell in a
      // reflective surface reads as water, not as steel.
      var h = (brush.at(u * along, v * across) - 0.5) * grainDepth;
      // And a slow unevenness in the metal itself, under the brushing --
      // rolling marks, the sheet not being quite flat. Without it there is
      // nothing between the grain but a plane, which reads as paper with a
      // texture printed on it.
      h += (brush.at(u * swellAlong, v * swellAcross) - 0.5) * swellDepth;

      if (m.damage > 0) {
        // Dents: a dish in the surface at a scattered point. Only the ones the
        // damage keeps -- every cell of the lattice having one is a golf ball,
        // not a sheet that has been knocked about.
        var (distance, which) =
            worley(spec.seed + 31, u * dentSize, v * dentSize);
        // Only some of them, and no two the same. Every cell of the lattice
        // having a dent is a golf ball, and dents all of one size are
        // perforations -- what makes a sheet look knocked about is that no
        // two knocks were alike.
        var keep = m.damage * 0.22;
        if (which < keep) {
          var spread = which / math.max(0.0001, keep);
          // Measured against a radius smaller than the cell, so a dent is a
          // round thing with flat metal around it. Run all the way out to the
          // cell wall, it meets the next cell's dent along a straight line,
          // and a sheet of dents sharing their edges is not a dented sheet --
          // it is flaking paint, which is what this looked like.
          var radius = 0.3 + spread * 0.45;
          // Eased at both ends rather than cubed. A cube comes to a point in
          // the middle and meets the flat with a crease at the rim, and the
          // light finds both: the dents came out as little arrowheads.
          var dish = (1 - distance / radius).clamp(0.0, 1.0);
          h -= dish * dish * (3 - 2 * dish) * dentDepth * (0.45 + spread);
        }
        // Scratches: the sharpest creases of a folded field, which wander the
        // way something dragged across a sheet wanders.
        //
        // One octave: the second is the same creases at twice the frequency,
        // and what it adds is short marks *across* the long ones -- which is
        // what turned the scratches into a field of dashes.
        var creased =
            ridged(crease, u * scratchAlong, v * scratchAcross, octaves: 1);
        // High up the field and narrow, so what is left is the few sharpest
        // creases rather than every ridge in it.
        var cut = ((creased - (0.93 - m.damage * 0.10)) / 0.05).clamp(0.0, 1.0);
        h -= cut * scratchDepth;
      }

      // Rust: a threshold on a smooth field, because rust creeps. Its edge is
      // ragged at every scale and its middle is deeper than its edge.
      var r = 0.0;
      if (m.rust > 0) {
        var n = patch.fbm(u * 4.2, v * 4.2, octaves: 3);
        if (n > rustLevel) {
          r = ((n - rustLevel) / math.max(0.0001, 0.85 - rustLevel))
              .clamp(0.0, 1.0);
          // Crust stands proud of the metal and is rough at a scale of its
          // own, which is why rust catches no highlight: there is no flat left
          // on it to catch one with.
          h += (crust.fbm(u * crustAcross, v * crustAcross, octaves: 2) - 0.4) *
              crustDepth *
              r;
        }
      }

      height[at] = h;
      rusted[at] = r;
      // How polished this part of the sheet is. A real sheet is not equally
      // polished everywhere -- it is worn where it has been handled -- and a
      // highlight of one strength everywhere is the flat band across the sheet
      // that this setting used to be.
      // One octave, and a slow one: this is how worn the sheet is here,
      // which is a thing that changes over a hand's width and not over a
      // pixel. Stacking octaves on it was eight hashes a point for a field
      // nobody can see the detail of.
      shine[at] = 0.5 + sheen.at(u * 1.1, v * 1.1);
    }
  }

  // How hard the relief tilts the surface overall. Divided by the lattice
  // spacing so that shading the same sheet on a finer lattice gives the same
  // slopes rather than a flatter picture.
  var gain = 0.35 + spec.density * 1.1;
  var slopeX = gain / math.max(0.0001, 2 * stepX / short);
  var slopeY = gain / math.max(0.0001, 2 * stepY / short);

  // The light on the sheet. From up and to the left, which is where a reader
  // assumes light comes from and where every shaded control in the app puts
  // it. Turning the background turns this with everything else, since the
  // whole pattern is drawn rotated -- see paintProcedural.
  const lx = -0.42, ly = -0.58, lz = 0.70;
  // The halfway direction between the light and the eye, which is the
  // direction a surface has to face for the light to come straight back.
  var hx = lx, hy = ly, hz = lz + 1;
  var hlen = math.sqrt(hx * hx + hy * hy + hz * hz);
  hx /= hlen;
  hy /= hlen;
  hz /= hlen;

  // Tight and hard on a mirror, broad and weak on a bead-blasted panel. The
  // power is what makes a highlight small and the strength is what makes it
  // bright; a mirror needs both.
  var power = 4 + m.shine * m.shine * 70;
  var force = 0.10 + m.shine * 0.95;

  // Pulled apart into plain numbers before the loop. Color.lerp allocates,
  // and allocating two colours per lattice point is a quarter of a million
  // objects for one sheet.
  var mr = spec.background.r, mg = spec.background.g, mb = spec.background.b;
  var lr = spec.foreground.r, lg = spec.foreground.g, lb = spec.foreground.b;
  var or_ = spec.accent.r, og = spec.accent.g, ob = spec.accent.b;
  var bright = 0.6 + spec.intensity * 0.6;

  // The highlight's curve, worked out once. math.pow with a fractional
  // exponent is one of the most expensive calls there is and this wants one
  // per lattice point; a table with the answers in it, read between its
  // entries, is the same curve for a fraction of the cost.
  const steps = 1024;
  var curve = Float64List(steps + 1);
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    // Two lobes rather than one: a tight glint, and a much broader sheen
    // under it. A single tight lobe is what a polished sheet has in theory,
    // and in practice it is a highlight so small that a surface sampled at a
    // point per pixel mostly misses it -- which is why turning Shine up used
    // to make the sheet *duller* than the middle of the range.
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

      // The surface's own direction, from how fast it is rising either way.
      var nx = -(right - left) * slopeX;
      var ny = -(down - up) * slopeY;
      var len = math.sqrt(nx * nx + ny * ny + 1);
      nx /= len;
      ny /= len;
      var nz = 1 / len;

      var diffuse = (nx * lx + ny * ly + nz * lz).clamp(0.0, 1.0);
      var toEye = (nx * hx + ny * hy + nz * hz).clamp(0.0, 1.0);
      var slot = toEye * steps;
      // One short of the end, so that reading the entry after it is always
      // inside the table: toEye reaches exactly one wherever the surface is
      // flat, which is most of a polished sheet.
      var low = slot.floor().clamp(0, steps - 1);
      var lift = slot - low;
      var highlight = (curve[low] + (curve[low + 1] - curve[low]) * lift) *
          force *
          shine[at];

      var r = rusted[at];
      // Rust scatters what it is given back in every direction, which is what
      // matt means. So the highlight dies where the rust is, and along the
      // edge of a patch it goes out gradually -- which is the thing anybody
      // looking at rusted steel actually sees.
      highlight *= 1 - r * 0.95;
      // And the grain dulls it: a ground surface is a great many small faces,
      // and only some of them are ever pointed the right way.
      highlight *= 1 - m.roughness * 0.3;

      // The rust is the accent colour, darkened towards the middle of a
      // patch rather than towards a brown: the middle of one is scale rather
      // than fresh oxide, and it is darker for that reason and not because
      // rust happens to be brown. Mixed towards a brown, a grey accent came
      // out brown, which is not the colour anybody chose.
      var dark = 1 - r * 0.5;
      var sr = mr + (or_ * dark - mr) * r;
      var sg = mg + (og * dark - mg) * r;
      var sb = mb + (ob * dark - mb) * r;
      // Well off black at the bottom: a groove in a sheet of steel is a darker
      // grey, not a hole. Metal in shadow is still metal.
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

  // Drawn as one strip of triangles per row of the lattice, with a colour at
  // every corner. A strip a row at a time rather than the whole sheet in one
  // call: the whole sheet is a million vertices at export sizes, and a row is
  // a few hundred.
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
    // Modulated against a white paint, which is how a mesh's own colours are
    // drawn unchanged: the paint has no shader, so its colour is what the
    // vertex colours are combined with.
    canvas.drawVertices(vertices, ui.BlendMode.modulate,
        paint..color = const Color(0xFFFFFFFF));
    vertices.dispose();
  }
}

/// _paintBase fills the frame before the generator runs.
void _paintBase(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  // Through the same PaintSpec every other colour in the app fades with, so
  // the background gets radial fades and movable stops without the generator
  // knowing anything about them.
  var shader =
      PaintSpec(spec.background, gradient: spec.gradient).shaderFor(rect);
  canvas.drawRect(
      rect,
      shader == null
          ? (Paint()..color = spec.background)
          : (Paint()..shader = shader));
}

/// _vignette darkens the edges, which is what makes most of these read as a
/// background rather than as a pattern competing with what is on top of it.
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

/// _unit is the generator's repeating unit in pixels: the cell of a grid, the
/// glyph of the rain. Derived from the shorter side so the same spec looks the
/// same in a wide banner and a tall story.
double _unit(Rect rect, ProceduralSpec spec) =>
    math.max(2, math.min(rect.width, rect.height) * spec.scale);

/// _withOpacity is Color.withValues under a shorter name, since the
/// generators below do it several hundred times each.
Color _fade(Color c, double a) => c.withValues(alpha: (c.a * a).clamp(0, 1));

// --------------------------------------------------------------------------
// The generators
// --------------------------------------------------------------------------

/// _contours draws iso-lines through a noise field, by marching squares.
///
/// Marching squares rather than sampling every pixel: the field is evaluated
/// once per cell corner rather than once per pixel, which is two orders of
/// magnitude fewer noise lookups, and the result is line segments -- which is
/// what a contour is, and what draws crisply at export resolution.
void _contours(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var cell = math.max(4.0, _unit(rect, spec) * 0.6);
  var cols = (rect.width / cell).ceil();
  var rows = (rect.height / cell).ceil();
  if (cols <= 0 || rows <= 0) return;

  var levels = 3 + (spec.density * 14).round();
  var freq = 0.06 * (1 + spec.variation * 2);

  // The field is sampled once into a grid, then every level walks that same
  // grid. Sampling per level instead would multiply the cost by the number of
  // contours for no benefit.
  var field = List.generate(
    rows + 1,
    (iy) => List.generate(
        cols + 1,
        (ix) =>
            noise.fbm(ix * cell * freq / 10 + t * 0.3, iy * cell * freq / 10)),
    growable: false,
  );

  // Terrain: the bands between the lines filled, low ground in the base
  // colour rising through the main colour to the accent at the peaks.
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
/// The classic sixteen cases, folded to the six distinct ones by symmetry.
/// Interpolated along each edge rather than taken at the midpoint, which is
/// the difference between smooth contours and staircases.
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
    // The two ambiguous saddles. Both diagonals are drawn, which is the
    // choice that never leaves a contour open -- an open contour is the one
    // artefact the eye picks out immediately.
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

/// _rings is concentric rings travelling out of -- or into -- a point.
///
/// Rewritten from a set of circles whose radii were shifted by up to one gap
/// and wrapped, which is why they expanded a little and snapped back: every
/// ring was drawn at the same handful of radii on every frame, and the only
/// thing that moved was the offset between them.
///
/// Each ring now has a life of its own: it is born where [RingSpec.from]
/// says, travels to where [RingSpec.to] says -- one being the far corner of
/// the page, so a ring that goes there has left it -- and another takes its
/// place behind it. The set is evenly spread through that life, so what is
/// seen is a procession rather than a flicker.
///
/// [page] is the canvas itself rather than the area being painted. The two
/// differ when the pattern is turned, and rings measured against the turned
/// area grew with it: a ring "at the edge of the page" has to mean the page.
void _rings(ui.Canvas canvas, Rect area, Rect page, ProceduralSpec spec,
    double t, int round, CanvasImageSource? images) {
  var ring = spec.rings;
  var count = ring.count.clamp(1, 200);
  var centre = Offset(
    page.left + page.width * ring.centreX,
    page.top + page.height * ring.centreY,
  );
  // The far corner from wherever the middle is: what "off the page" means
  // depends on which corner is furthest away, or a ring set going from one
  // corner would stop before it had crossed.
  var reach = [
    (centre - page.topLeft).distance,
    (centre - page.topRight).distance,
    (centre - page.bottomLeft).distance,
    (centre - page.bottomRight).distance,
  ].reduce(math.max);
  var unit = math.min(page.width, page.height);
  // One life every six or seven seconds at the default speed, which is a
  // ring crossing the page rather than a pulse.
  var moving = spec.animated ? t * 0.15 : 0.0;

  for (var i = 0; i < count; i++) {
    // Its own numbers, from the seed and its place in the set, so a ring
    // keeps its width and its colour as it travels rather than flickering
    // through everybody else's.
    var jitter = (hash(spec.seed + 11, i, 0) - 0.5) * ring.spacingJitter;
    // How far through its life this ring is, which always runs forwards:
    // shrinking is a ring born at the outside that dies in the middle, not a
    // life played backwards. Running the clock back as well as the journey
    // left the two the same picture.
    //
    // Not yet born is a ring the set has not reached: at the first frame the
    // whole set used to be spread across its life already, so a canvas
    // opened -- and looped -- on rings that were simply there. See
    // RingSpec.buildUp.
    var age = ring.ageOf(i, moving, jitter: jitter);
    // Whether something of this ring's age is alive: born, and not yet gone.
    // Asked of the pictures it carries as well as of the ring, because a
    // picture moved through the life has an age of its own -- one moved back
    // is still going when the ring that carries it has gone, and cutting it
    // off there is a picture that never fades out.
    bool alive(double at) =>
        !(ring.buildUp && spec.animated && at < 0) && !(spec.inRuns && at > 1);
    var through = ring.spread(i, moving, jitter: jitter);

    // Bunched towards one end or the other. A half is even. Written as a
    // function of how far through a life something is, because an icon
    // carried by this ring may be a little ahead of it or behind it -- see
    // RingIcon.driftWhen -- and has to be placed by the same journey.
    var bias = ring.spacing.clamp(0.05, 0.95);
    double radiusAt(double at) {
      var eased = math.pow(at, bias <= 0 ? 1 : (0.5 / bias)).toDouble();
      // Where it sits between its two ends. Shrinking starts it at the far
      // one and walks it back.
      var place = ring.inward ? 1 - eased : eased;
      return reach * (ring.from + (ring.to - ring.from) * place);
    }

    // The fade is about the life rather than the place: a ring fades in when
    // it is born and out when it dies, wherever on the page that happens.
    var fade = ring.alphaAt(through);
    var alpha = fade * spec.intensity.clamp(0.0, 1.0);
    // A ring too faint to see is not drawn -- but a picture it carries may
    // have been told to keep its own strength, or to sit out the ring's
    // arrival, and then the ring being invisible says nothing about the
    // picture. See RingIcon.opacity and holdIn.
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
    // A soft edge rolls the line in as well as up. A ring is a hairline --
    // four thousandths of the page, which is a pixel or two -- and a hairline
    // drawn at a fifth of its strength looks very much like a hairline drawn
    // at half of it, because what the screen shows either way is one faint
    // line. Rolling the width with it is what makes the arrival read as an
    // arrival, and it is what "soft" means as against "hard".
    if (ring.edge == RingEdge.soft) width *= 0.25 + 0.75 * fade;

    // Which of the two colours, and how far towards the other one. Every
    // fifth ring in the accent by default, because a set of rings all one
    // colour is a target and the thing that stops it being one is a rhythm.
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

    // And whatever this ring is carrying. Drawn after it, so an icon sits on
    // the line rather than under it, and at the ring's own strength, so it
    // arrives, swells and dissolves with the ring around it.
    for (var icon in ring.icons) {
      if (icon.ring - 1 != i || icon.asset.isEmpty) continue;
      _drawRingIcons(canvas, images, icon, spec, ring, i, centre, age, alive,
          radiusAt, spec.intensity.clamp(0.0, 1.0), unit, round);
    }
  }

  // And whatever is on no ring at all, which is tied to the movement
  // instead: it lives the length of one run rather than of a ring, is sized
  // against the page rather than against a radius, and sits where the rings
  // come from. Told to keep both of its fades, it is simply there --
  // a badge behind a set of rings that come and go. See RingIcon.ring.
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

/// _pictures is what an icon may be drawn as, ready to stamp.
///
/// Several of them, with how often each comes up: a picture at two against
/// one is taken twice as often, and one at nought never. Each asset is
/// resolved once however many places take it.
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

  // One colour rather than its own, where that has been asked for: a line
  // drawing carried by a ring usually wants to be the colour of the ring
  // rather than whatever it was drawn in. srcIn keeps the picture's shape and
  // replaces everything inside it.
  var paint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
  if (icon.tinted) {
    // The colour at its own strength, not at the picture's. Both the filter
    // and the paint carry an alpha, and they multiply: putting the fade in
    // the filter as well drew a tinted picture at the square of it -- half
    // strength came out a quarter, and anywhere a ring was faint the colour
    // switched the picture off.
    paint.colorFilter = ui.ColorFilter.mode(icon.tint, BlendMode.srcIn);
  }
  // Kept in proportion and fitted to a square of the wanted size, which is
  // what makes two icons of different shapes look like the same size.
  var scale = side / math.max(natural.width, natural.height);

  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (turn != 0) canvas.rotate(turn);
  canvas.scale(scale);
  canvas.translate(-natural.width / 2, -natural.height / 2);
  if (vector != null) {
    // A drawing has its own colours and its own transparency, so the strength
    // and the tint are applied to the layer it is drawn into.
    canvas.saveLayer(Rect.fromLTWH(0, 0, natural.width, natural.height), paint);
    canvas.drawPicture(vector.picture);
    canvas.restore();
  } else {
    canvas.drawImage(bitmap!, Offset.zero, paint);
  }
  canvas.restore();
}

/// _iconStrength is how strongly one of a ring's pictures is drawn at a
/// moment of the ring's life: its own if it has been given one, and
/// otherwise the ring's, with whichever of the two ends it has been told to
/// sit out.
double _iconStrength(RingIcon icon, RingSpec ring, double at) =>
    icon.opacity ??
    ring.alphaAt(at, arriving: !icon.holdIn, leaving: !icon.holdOut);

/// _iconSide is a wanted size held between whatever limits it has been
/// given, as fractions of the page rather than of the ring it is on: a
/// picture grows with its ring, and what that means without a limit is that
/// it grows out of the picture.
double _iconSide(RingIcon icon, double side, double unit) {
  if (icon.smallest != null) side = math.max(side, icon.smallest! * unit);
  if (icon.largest != null) side = math.min(side, icon.largest! * unit);
  return side;
}

/// _drawLooseIcon draws a picture that is on no ring.
///
/// Everything a ring would have lent it comes from the movement instead: its
/// moment is how far through a run the pattern is, and its size is a fraction
/// of the page. Which is what makes "on ring: none", with both of its fades
/// held, a picture that is simply there for the whole animation -- a badge
/// behind rings that come and go.
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
/// In the middle, it is one picture at the middle of the rings, sized
/// against the ring that carries it -- so it grows as that ring grows.
/// Around, it is several spaced along the ring itself, each turned to face
/// out of it, and each with its own place in whatever it has been allowed to
/// differ by. See RingDrift.
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
  // Said once. A picture that belongs to the opening of a thing is wrong on
  // every run after it.
  if (icon.firstRunOnly && round > 0) return;
  var from = _Pictures.of(images, icon);
  if (from == null) return;

  /// moment is where a picture of this age is in the ring's life, or null
  /// where it is not yet born or already gone. A picture moved through the
  /// life has an age of its own: held at the two ends instead, one moved back
  /// sat at the first instant of the life for as long as its offset lasted,
  /// which is a picture that never arrives and never leaves.
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
    // Its own roll for each of them, and a different one per picture: rolled
    // once for the set, every picture would move together, which is the thing
    // being fixed rather than a cheaper way of doing it.
    double roll(int of) => hash(spec.seed + 23, index * 64 + of, n);

    // Ahead of its ring or behind it, which is what takes a picture off the
    // line: it is placed by the ring's own journey at its own moment, so it
    // sits at the radius the ring had then -- and arrives and leaves at that
    // moment too.
    var mine = moment(icon.driftWhen.at(roll(0)));
    if (mine == null) continue;
    var radius = radiusAt(mine);
    if (radius <= 0.5) continue;

    // Round from where it would have sat, in gaps between one and the next,
    // so the scatter is the same whatever the count.
    var gap = 2 * math.pi / many;
    var angle = n * gap + icon.driftWhere.at(roll(1)) * gap;

    var side = _iconSide(
        icon,
        radius *
            (icon.size * (1 + icon.driftSize.at(roll(2)))).clamp(0.01, 4.0),
        unit);

    // A share of what the ring is drawn at, so a picture never outlives the
    // ring carrying it: whatever share of nothing is nothing.
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

/// _drawRing puts one ring on the page, with whatever has been done to it.
///
/// A plain ring is one call; a ring with any of noise, distortion, glitch or
/// grunge on it is walked round in steps, because all four of them are ways
/// of saying that the radius, the centre or the ink is not the same all the
/// way round.
void _drawRing(ui.Canvas canvas, Offset centre, double radius,
    ProceduralSpec spec, RingSpec ring, int index, Paint paint, Rect area) {
  var wobbly = ring.noise > 0 || ring.grunge > 0;
  var broken = ring.glitch > 0;

  if (!wobbly && !broken) {
    if (ring.distortion <= 0) {
      canvas.drawCircle(centre, radius, paint);
      return;
    }
    // Squashed and leaned over: an ellipse is the whole of what distortion
    // does to a ring that is otherwise clean, and an oval is one call.
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

  // Enough steps that the wobble reads as a wobble rather than as a polygon,
  // and not so many that a page of rings costs a frame.
  var steps = (36 + radius * 0.35).clamp(36, 220).round();
  var lean = hash(spec.seed + 5, index, 4) * math.pi;
  var squashX = 1 - ring.distortion * 0.5;
  var squashY = 1 + ring.distortion * 0.35;
  var full = paint.strokeWidth;

  Offset at(double turn, double wobble) {
    var x = math.cos(turn) * radius * squashX * wobble;
    var y = math.sin(turn) * radius * squashY * wobble;
    // Leaned over about the middle, which is what turns a squashed ring from
    // a ring drawn wide into one lying at an angle.
    return centre +
        Offset(x * math.cos(lean) - y * math.sin(lean),
            x * math.sin(lean) + y * math.cos(lean));
  }

  var path = ui.Path();
  var open = false;
  for (var s = 0; s <= steps; s++) {
    var f = s / steps;
    var turn = f * 2 * math.pi;

    // The outline's own wander: two turns of it round the ring, so it reads
    // as a hand rather than as a ripple.
    var wobble = 1 +
        (hash(spec.seed + 13, index, s % 17) - 0.5) * ring.noise * 0.12 +
        math.sin(turn * 3 + index) * ring.noise * 0.03;

    // Slices knocked sideways. A glitch is not a wobble: it is a piece of the
    // ring in the wrong place, with the pieces either side of it where they
    // were.
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
    // Where the ink ran out it also ran thin, which is the difference
    // between a broken line and a dotted one.
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
/// A dense rain draws several thousand glyphs a frame and laying each one out
/// from scratch is by far the most expensive thing in this file -- it was the
/// difference between the stage running at sixty frames a second and at eight.
/// The alpha is quantised into sixteen steps so that a fading tail reuses
/// sixteen painters rather than needing a new one for every step, which is
/// invisible at any size a glyph is drawn and is what makes the cache bounded.
final Map<String, TextPainter> _glyphCache = {};

/// _maxGlyphCache is where the cache is emptied. Reached only by a document
/// that has changed its glyph set or its size many times over; dropping the
/// lot and rebuilding is a frame of extra work in a session, against tracking
/// per-entry ages on every one of thousands of lookups per frame.
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
/// Rotated, because a halftone screen always is -- printed square it reads as
/// a dot grid, and it is the fifteen-degree tilt that makes the eye see tone
/// rather than dots. The size comes from a smooth field, so the dots swell
/// into drifts of shadow instead of being an even stipple: that difference is
/// the whole look.
void _halftone(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var step = math.max(3.0, _unit(rect, spec) * 1.2);
  var noise = ValueNoise(spec.seed);
  var paint = Paint();

  // The screen angle, tilted a little further by the variation.
  var angle = (15 + spec.variation * 30) * math.pi / 180;
  var cos = math.cos(angle), sin = math.sin(angle);

  // Enough of the grid to cover the rectangle once it has been turned.
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

      // How much ink is here: a smooth field, so the dots grow and shrink in
      // drifts rather than at random.
      var ink = switch (inkKind) {
        // Heavy at one side and nothing at the other: the classic comic
        // fade, which is a gradient drawn in dots.
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

      // The accent where the ink is heaviest, in drifts. A fade is one ink
      // getting heavier, and an accent switched in part way along it is a
      // hard-edged blob.
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
/// Wedges rather than strokes, because the lines a comic artist inks are
/// thick where they leave the frame and come to nothing at the middle -- a
/// constant-width ray reads as a starburst clip-art, which is the wrong
/// decade.
void _speedLines(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  if (spec.choice("burstKind") == 1)
    return _parallelLines(canvas, rect, spec, t);
  // The vanishing point wanders with the seed, but stays near the middle: a
  // burst centred on a corner is a fan, not a burst. Unless it is put
  // somewhere, which is what a burst behind a figure off to one side wants.
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

/// _crosshatch is inked hatching: two sets of lines crossed at an angle, with
/// a third where it is laid on heavily.
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
      // A hand-inked line is not quite straight and does not quite reach.
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

/// _splatter is thrown ink: heavy blobs, satellite droplets around them, and
/// a drip or two running off the big ones.
void _splatter(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  switch (spec.choice("splatKind")) {
    case 1:
      return _drips(canvas, rect, spec, t);
    case 2:
      return _spray(canvas, rect, spec, t);
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

    // The blob itself, as a wobbling closed curve rather than a circle -- a
    // circle is a dot, and thrown ink has no circles in it.
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

    // Satellites: the small stuff that lands around a splash and is most of
    // what makes it read as one.
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

    // And a drip, on the heavier blobs.
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

/// _flames is fire: tongues rising from the bottom edge, each a teardrop bent
/// by a slow field so it licks rather than points.
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

    // Up one side and down the other, both bent by the same field so the two
    // edges of a tongue lean together rather than crossing.
    var left = ui.Path();
    var right = <Offset>[];
    const steps = 14;
    for (var s = 0; s <= steps; s++) {
      var up = s / steps;
      // Narrowing to nothing at the tip, fattest a third of the way up.
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

    // The body, and a brighter heart inside it -- fire is two colours or it
    // is a leaf.
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:flutter/painting.dart';

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

/// paintProcedural draws [spec] into [rect].
///
/// [time] is in seconds and is what animation advances. Passing zero is a
/// still, which is what an unanimated background and the first frame both are.
void paintProcedural(ui.Canvas canvas, Rect rect, ProceduralSpec spec,
    {double time = 0}) {
  if (rect.width <= 0 || rect.height <= 0) return;

  canvas.save();
  canvas.clipRect(rect);

  _paintBase(canvas, rect, spec);

  // The pattern is drawn rotated inside a rectangle grown to cover the
  // corners, so turning it does not sweep an empty wedge into view. The clip
  // above keeps the overspill off the canvas.
  var t = spec.animated ? time * spec.speed : 0.0;
  var area = rect;
  if (spec.rotation != 0) {
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(spec.rotation * math.pi / 180);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    var grow = (rect.width + rect.height) / 2;
    area = rect.inflate(grow);
  }

  switch (spec.style) {
    case ProceduralStyle.plain:
      break;
    case ProceduralStyle.gradientMesh:
      _gradientMesh(canvas, area, spec, t);
    case ProceduralStyle.dotGrid:
      _dotGrid(canvas, area, spec, t);
    case ProceduralStyle.lineGrid:
      _lineGrid(canvas, area, spec);
    case ProceduralStyle.hexGrid:
      _hexGrid(canvas, area, spec);
    case ProceduralStyle.contours:
      _contours(canvas, area, spec, t);
    case ProceduralStyle.flowWaves:
      _flowWaves(canvas, area, spec, t);
    case ProceduralStyle.bokeh:
      _bokeh(canvas, area, spec, t);
    case ProceduralStyle.starfield:
      _starfield(canvas, area, spec, t);
    case ProceduralStyle.ledGrid:
      _ledGrid(canvas, area, spec, t);
    case ProceduralStyle.circuit:
      _circuit(canvas, area, spec, t);
    case ProceduralStyle.rain:
      _rain(canvas, area, spec, t);
    case ProceduralStyle.symbolField:
      _symbolField(canvas, area, spec, t);
    case ProceduralStyle.rings:
      _rings(canvas, area, spec, t);
    case ProceduralStyle.halftone:
      _halftone(canvas, area, spec, t);
    case ProceduralStyle.speedLines:
      _speedLines(canvas, area, spec, t);
    case ProceduralStyle.crosshatch:
      _crosshatch(canvas, area, spec);
    case ProceduralStyle.splatter:
      _splatter(canvas, area, spec, t);
    case ProceduralStyle.flames:
      _flames(canvas, area, spec, t);
    case ProceduralStyle.pitch:
      paintPitch(canvas, area, spec);
  }

  canvas.restore();

  if (spec.vignette > 0) _vignette(canvas, rect, spec.vignette);
}

/// _paintBase fills the frame before the generator runs.
void _paintBase(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  if (!spec.gradient) {
    canvas.drawRect(rect, Paint()..color = spec.background);
    return;
  }
  var a = spec.gradientAngle * math.pi / 180;
  // The gradient's endpoints are pushed out to the corners along the chosen
  // angle, so a diagonal gradient runs corner to corner rather than fading out
  // inside the frame the way a naive centre-plus-radius one does.
  var half = math.max(rect.width, rect.height);
  var c = rect.center;
  var from =
      Offset(c.dx - math.cos(a) * half / 2, c.dy - math.sin(a) * half / 2);
  var to = Offset(c.dx + math.cos(a) * half / 2, c.dy + math.sin(a) * half / 2);
  canvas.drawRect(
      rect,
      Paint()
        ..shader =
            ui.Gradient.linear(from, to, [spec.background, spec.gradientTo]));
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

/// _gradientMesh is a handful of soft radial blooms, blended additively.
///
/// Additive rather than alpha-blended: overlapping blooms should get brighter
/// where they meet, which is what makes it read as light rather than as
/// several coloured circles lying on top of one another.
void _gradientMesh(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var rnd = SeededRandom(spec.seed);
  var count = 3 + (spec.density * 9).round();
  var maxR = math.max(rect.width, rect.height) * (0.3 + spec.scale * 4);

  canvas.saveLayer(rect, Paint());
  for (var i = 0; i < count; i++) {
    var px = rnd.next(), py = rnd.next(), pick = rnd.next();
    var drift = rnd.range(0.2, 1.0);
    var c = Offset(
      rect.left +
          rect.width * px +
          math.sin(t * drift + i) * rect.width * 0.05 * spec.variation,
      rect.top +
          rect.height * py +
          math.cos(t * drift * 0.8 + i) * rect.height * 0.05 * spec.variation,
    );
    var r = maxR * rnd.range(0.4, 1.0);
    var color = pick < 0.5 ? spec.foreground : spec.accent;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r, [
          _fade(color, spec.intensity * 0.7),
          _fade(color, 0),
        ], [
          0.0,
          1.0
        ]),
    );
  }
  canvas.restore();
}

/// _dotGrid is an even field of dots, jittered and sized by the noise so it
/// does not read as graph paper.
void _dotGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var step = _unit(rect, spec) * 2;
  var noise = ValueNoise(spec.seed);
  var paint = Paint();
  var cols = (rect.width / step).ceil() + 1;
  var rows = (rect.height / step).ceil() + 1;

  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var h = hash(spec.seed, ix, iy);
      if (h > spec.density) continue;

      var jx = (hash(spec.seed + 7, ix, iy) - 0.5) * step * spec.variation;
      var jy = (hash(spec.seed + 13, ix, iy) - 0.5) * step * spec.variation;
      var p = Offset(rect.left + ix * step + jx, rect.top + iy * step + jy);

      // The field decides brightness rather than the per-dot hash, so the
      // dots cluster into drifts of light instead of being uniform static.
      var f = noise.fbm(ix * 0.15 + t * 0.2, iy * 0.15, octaves: 3);
      var alpha = (f * spec.intensity).clamp(0.0, 1.0);
      paint.color =
          _fade(h < spec.density * 0.15 ? spec.accent : spec.foreground, alpha);
      canvas.drawCircle(p, step * 0.12 * (0.5 + f), paint);
    }
  }
}

/// _lineGrid is ruled lines, with every fourth one heavier.
void _lineGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var step = _unit(rect, spec) * 2;
  var thin = Paint()
    ..color = _fade(spec.foreground, spec.intensity * 0.35)
    ..strokeWidth = math.max(0.5, step * 0.012);
  var thick = Paint()
    ..color = _fade(spec.accent, spec.intensity * 0.6)
    ..strokeWidth = math.max(1, step * 0.03);

  var cols = (rect.width / step).ceil() + 1;
  for (var i = 0; i <= cols; i++) {
    var x = rect.left + i * step;
    canvas.drawLine(
        Offset(x, rect.top), Offset(x, rect.bottom), i % 4 == 0 ? thick : thin);
  }
  var rows = (rect.height / step).ceil() + 1;
  for (var i = 0; i <= rows; i++) {
    var y = rect.top + i * step;
    canvas.drawLine(
        Offset(rect.left, y), Offset(rect.right, y), i % 4 == 0 ? thick : thin);
  }
}

/// _hexGrid is a honeycomb of outlined cells, with a share of them filled.
void _hexGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var r = _unit(rect, spec) * 1.5;
  var w = r * math.sqrt(3);
  var h = r * 1.5;
  var stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, r * 0.04)
    ..color = _fade(spec.foreground, spec.intensity * 0.5);

  var rows = (rect.height / h).ceil() + 2;
  var cols = (rect.width / w).ceil() + 2;
  for (var iy = -1; iy < rows; iy++) {
    for (var ix = -1; ix < cols; ix++) {
      var cx = rect.left + ix * w + (iy.isOdd ? w / 2 : 0);
      var cy = rect.top + iy * h;
      var path = Path();
      for (var k = 0; k < 6; k++) {
        var a = math.pi / 180 * (60 * k - 90);
        var p = Offset(cx + math.cos(a) * r, cy + math.sin(a) * r);
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      if (hash(spec.seed, ix, iy) < spec.density * 0.4) {
        canvas.drawPath(
            path,
            Paint()
              ..color = _fade(spec.accent,
                  spec.intensity * hash(spec.seed + 3, ix, iy) * 0.5));
      }
      canvas.drawPath(path, stroke);
    }
  }
}

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
          ..strokeWidth = math.max(0.6, cell * 0.05)
          ..color = _fade(l.isEven ? spec.foreground : spec.accent,
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

/// _flowWaves traces ribbons through a flow field, glowing where they bunch.
///
/// This is the one the reference images called "waves": long smooth strands
/// that bend together and apart. They are drawn in bands of neighbouring
/// start points so that a band stays together as it flows, which is what makes
/// the ribbons read as ribbons rather than as unrelated strands.
void _flowWaves(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var bands = 3 + (spec.density * 9).round();
  var perBand = 6 + (spec.density * 22).round();
  var stepLen = math.max(3.0, _unit(rect, spec) * 0.5);
  var steps = (rect.width / stepLen * 1.4).round().clamp(20, 900);
  var turns = 0.6 + spec.variation * 2.2;
  var freq = 0.0012 * (1 + spec.scale * 6);

  canvas.saveLayer(rect, Paint());
  var rnd = SeededRandom(spec.seed);
  for (var b = 0; b < bands; b++) {
    var bandY = rnd.next();
    var spread = rnd.range(0.02, 0.14);
    var color = rnd.next() < 0.35 ? spec.accent : spec.foreground;
    var width = math.max(0.7, _unit(rect, spec) * rnd.range(0.03, 0.12));

    // The band's strands are built once and drawn twice: the glow blurs a
    // layer holding all of them, and the filament goes over the top.
    //
    // One blur for the band rather than one for each strand, which is what
    // this did and is why a banner took the best part of a second to draw.
    // A blur is the most expensive thing there is on a canvas and there were
    // a hundred and forty of them; a band shares its width, so its strands
    // share a blur and the picture is the same picture.
    var strands = <Path>[];
    for (var s = 0; s < perBand; s++) {
      var frac = perBand == 1 ? 0.5 : s / (perBand - 1);
      var y = rect.top +
          rect.height * (bandY + (frac - 0.5) * spread).clamp(-0.2, 1.2);
      var p = Offset(rect.left - stepLen * 4, y);

      var path = Path()..moveTo(p.dx, p.dy);
      for (var i = 0; i < steps; i++) {
        var a = angleNoise(noise, p.dx * freq + t * 0.15, p.dy * freq, turns);
        // Biased strongly to the right so the strands cross the frame rather
        // than curling up in one corner, which is what an unbiased flow field
        // does almost every time.
        var dir = Offset(math.cos(a) * 0.45 + 0.9, math.sin(a) * 0.85);
        p = p + dir * stepLen;
        path.lineTo(p.dx, p.dy);
        if (p.dx > rect.right + stepLen * 4) break;
      }

      strands.add(path);
    }

    // Two passes: a wide soft one for the glow, a thin bright one for the
    // strand. A single stroke with a blur gives the glow but loses the
    // filament in the middle, and it is the filament that reads as light.
    canvas.saveLayer(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: width * 3, sigmaY: width * 3, tileMode: TileMode.decal));
    var glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 5
      ..strokeCap = StrokeCap.round
      ..color = _fade(color, spec.intensity * 0.10);
    for (var path in strands) {
      canvas.drawPath(path, glow);
    }
    canvas.restore();

    var filament = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..color = _fade(color, spec.intensity * 0.5);
    for (var path in strands) {
      canvas.drawPath(path, filament);
    }
  }
  canvas.restore();
}

/// _bokeh is out-of-focus discs of light.
///
/// Each disc is brighter at its rim than at its centre, which is what an
/// out-of-focus highlight actually looks like through a real lens and is the
/// difference between this and a picture of some circles.
void _bokeh(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var rnd = SeededRandom(spec.seed);
  var count = 8 + (spec.density * 90).round();
  var base = _unit(rect, spec) * 3;

  canvas.saveLayer(rect, Paint());
  for (var i = 0; i < count; i++) {
    var px = rnd.next(), py = rnd.next();
    var sizeF = rnd.range(0.25, 1.0 + spec.variation * 1.6);
    var pick = rnd.next();
    var drift = rnd.range(-1, 1);

    var r = base * sizeF;
    var c = Offset(
      rect.left +
          rect.width * px +
          math.sin(t * 0.4 + i) * r * 0.3 * spec.variation,
      rect.top + rect.height * py + drift * t * 6,
    );
    var color = pick < 0.3 ? spec.accent : spec.foreground;
    var alpha = spec.intensity * (0.10 + 0.35 * (1 - sizeF).abs());

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r, [
          _fade(color, alpha * 0.55),
          _fade(color, alpha * 0.75),
          _fade(color, 0),
        ], [
          0.0,
          0.82,
          1.0
        ]),
    );
  }
  canvas.restore();
}

/// _starfield is scattered points of light, densest and brightest in the
/// middle so the frame has somewhere to look.
void _starfield(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var rnd = SeededRandom(spec.seed);
  var count = 40 + (spec.density * 700).round();
  var unit = _unit(rect, spec);

  for (var i = 0; i < count; i++) {
    var px = rnd.next(), py = rnd.next();
    var mag = rnd.next();
    var twinkle = rnd.range(0.5, 3.0);
    var p = Offset(rect.left + rect.width * px, rect.top + rect.height * py);

    var d =
        (p - rect.center).distance / (math.max(rect.width, rect.height) * 0.7);
    var falloff = (1 - d * spec.variation).clamp(0.05, 1.0);
    var flicker =
        spec.animated ? 0.6 + 0.4 * math.sin(t * twinkle + i.toDouble()) : 1.0;
    var alpha = spec.intensity * falloff * flicker * (0.2 + mag * 0.8);
    var r = unit * 0.08 * (0.4 + mag * 1.6);

    canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = _fade(mag > 0.93 ? spec.accent : spec.foreground, alpha));
    // The brightest few get a cross of light, which is what makes a starfield
    // read as stars rather than as noise.
    if (mag > 0.96) {
      var arm = r * 6;
      var paint = Paint()
        ..strokeWidth = r * 0.5
        ..color = _fade(spec.accent, alpha * 0.5);
      canvas.drawLine(p.translate(-arm, 0), p.translate(arm, 0), paint);
      canvas.drawLine(p.translate(0, -arm), p.translate(0, arm), paint);
    }
  }
}

/// _ledGrid is a dot-matrix wall: cells lit in clusters rather than at random.
///
/// The clustering is what the reference image has and what a plain per-cell
/// hash does not: lit cells form blocks and runs, because a noise field
/// decides the region's brightness and the per-cell hash only decides whether
/// this cell reaches it.
void _ledGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var cell = _unit(rect, spec);
  var cols = (rect.width / cell).ceil() + 1;
  var rows = (rect.height / cell).ceil() + 1;
  var noise = ValueNoise(spec.seed);
  var dot = cell * 0.34;

  canvas.saveLayer(rect, Paint());
  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var region = noise.fbm(ix * 0.08, iy * 0.08 + t * 0.25, octaves: 3);
      var h = hash(spec.seed, ix, iy);
      var lit = h < region * spec.density * 1.8;
      if (!lit) continue;

      var p =
          Offset(rect.left + (ix + 0.5) * cell, rect.top + (iy + 0.5) * cell);
      var hot = hash(spec.seed + 91, ix, iy);
      var color = hot > 0.86 ? spec.accent : spec.foreground;
      var alpha = spec.intensity * (0.25 + region * 0.75);

      // A diamond for a share of the cells, which is what breaks the grid up
      // in the reference and costs one branch.
      var diamond = hash(spec.seed + 41, ix, iy) < spec.variation * 0.45;
      var paint = Paint()
        ..blendMode = BlendMode.plus
        ..color = _fade(color, alpha);
      if (diamond) {
        canvas.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - dot)
              ..lineTo(p.dx + dot, p.dy)
              ..lineTo(p.dx, p.dy + dot)
              ..lineTo(p.dx - dot, p.dy)
              ..close(),
            paint);
      } else {
        canvas.drawCircle(p, dot, paint);
      }

      if (hot > 0.97) {
        canvas.drawCircle(
            p,
            dot * 3.2,
            Paint()
              ..blendMode = BlendMode.plus
              ..shader = ui.Gradient.radial(p, dot * 3.2, [
                _fade(spec.accent, alpha * 0.5),
                _fade(spec.accent, 0),
              ]));
      }
    }
  }
  canvas.restore();
}

/// _circuit is right-angled traces with pads where they turn.
void _circuit(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var cell = _unit(rect, spec) * 1.6;
  var cols = math.max(2, (rect.width / cell).ceil());
  var rows = math.max(2, (rect.height / cell).ceil());
  var rnd = SeededRandom(spec.seed);
  var traces = 4 + (spec.density * 60).round();
  var stroke = math.max(0.8, cell * 0.06);

  var glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  for (var i = 0; i < traces; i++) {
    var x = rnd.intRange(0, cols);
    var y = rnd.intRange(0, rows);
    var len = 3 + rnd.intRange(0, 6 + (spec.variation * 14).round());
    var path = Path()..moveTo(rect.left + x * cell, rect.top + y * cell);
    var pads = <Offset>[];

    var horizontal = rnd.next() < 0.5;
    for (var s = 0; s < len; s++) {
      var run = 1 + rnd.intRange(0, 4);
      if (horizontal) {
        x += rnd.next() < 0.5 ? run : -run;
      } else {
        y += rnd.next() < 0.5 ? run : -run;
      }
      x = x.clamp(0, cols);
      y = y.clamp(0, rows);
      var p = Offset(rect.left + x * cell, rect.top + y * cell);
      path.lineTo(p.dx, p.dy);
      pads.add(p);
      horizontal = !horizontal;
    }

    // A slow pulse along the traces when animated, so the board looks powered
    // rather than printed. Each trace gets its own phase from the sequence, so
    // they do not all breathe together.
    var phase = rnd.next() * math.pi * 2;
    var pulse = spec.animated ? 0.55 + 0.45 * math.sin(t * 1.6 + phase) : 1.0;
    glow.color = _fade(spec.foreground, spec.intensity * 0.45 * pulse);
    canvas.drawPath(path, glow);

    var padPaint = Paint()
      ..color = _fade(spec.accent, spec.intensity * 0.7 * pulse);
    for (var p in pads) {
      canvas.drawCircle(p, stroke * 1.8, padPaint);
    }
  }
}

/// _rain is columns of falling glyphs, brightest at the head of each column.
void _rain(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var glyphs = spec.glyphs.isEmpty ? defaultGlyphs : spec.glyphs;
  var size = _unit(rect, spec);
  var colWidth = size * 0.9;
  var cols = (rect.width / colWidth).ceil() + 1;
  var rowsOnScreen = (rect.height / size).ceil() + 2;

  for (var ix = 0; ix < cols; ix++) {
    if (hash(spec.seed + 5, ix, 0) > spec.density * 1.4) continue;

    var speed =
        0.4 + hash(spec.seed + 11, ix, 1) * (0.6 + spec.variation * 2.5);
    var tail =
        4 + (hash(spec.seed + 17, ix, 2) * (6 + spec.variation * 26)).round();
    // The head is measured in rows and advances with time. Offsetting by the
    // column's own hash is what stops every column starting level, which is
    // the single most obvious giveaway that a rain effect is generated.
    var head = (hash(spec.seed + 23, ix, 3) * rowsOnScreen * 3) +
        (spec.animated ? t * speed * 6 : 0);

    var x = rect.left + ix * colWidth;
    for (var k = 0; k < tail; k++) {
      var row = (head - k) % (rowsOnScreen + tail);
      var y = rect.top + row * size;
      if (y < rect.top - size || y > rect.bottom + size) continue;

      // The glyph is chosen from the *cell*, not from the position in the
      // tail, so a column's characters stay put while the light runs down
      // through them -- which is what the film does and what makes it read as
      // falling light rather than as scrolling text.
      var cellRow = row.floor();
      var gi = (hash(spec.seed + 31, ix,
                  cellRow + (spec.animated ? (t * speed).floor() : 0)) *
              glyphs.length)
          .floor()
          .clamp(0, glyphs.length - 1);

      var fade = k == 0 ? 1.0 : (1 - k / tail);
      var color = k == 0 ? spec.accent : spec.foreground;
      _drawGlyph(canvas, glyphs[gi], Offset(x, y), size,
          _fade(color, spec.intensity * fade * fade));
    }
  }
}

/// _symbolField scatters glyphs at varying size and angle.
void _symbolField(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var glyphs = spec.glyphs.isEmpty ? defaultGlyphs : spec.glyphs;
  var rnd = SeededRandom(spec.seed);
  var base = _unit(rect, spec);
  var count = 10 + (spec.density * 400).round();

  for (var i = 0; i < count; i++) {
    var px = rnd.next(), py = rnd.next();
    var sizeF = rnd.range(0.4, 1 + spec.variation * 2.5);
    var angle = rnd.range(-1, 1) * spec.variation * math.pi;
    var gi = rnd.intRange(0, glyphs.length);
    var pick = rnd.next();
    var bob = rnd.range(0.3, 1.6);

    var p = Offset(
      rect.left + rect.width * px,
      rect.top +
          rect.height * py +
          (spec.animated ? math.sin(t * bob + i) * base * 0.4 : 0),
    );
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle);
    _drawGlyph(
        canvas,
        glyphs[gi],
        Offset.zero,
        base * sizeF,
        _fade(pick < 0.2 ? spec.accent : spec.foreground,
            spec.intensity * rnd.range(0.15, 0.9)));
    canvas.restore();
  }
}

/// _rings is concentric circles radiating from an off-centre point.
void _rings(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var rnd = SeededRandom(spec.seed);
  var origin = Offset(
    rect.left + rect.width * rnd.range(0.2, 0.8),
    rect.top + rect.height * rnd.range(0.2, 0.8),
  );
  var maxR = math.max(rect.width, rect.height) * 1.2;
  var gap = _unit(rect, spec) * 1.4;
  var count = (maxR / gap).ceil();
  var offset = spec.animated ? (t * gap * 0.6) % gap : 0.0;

  for (var i = 0; i < count; i++) {
    var r = i * gap + offset;
    if (r <= 0) continue;
    var frac = r / maxR;
    if (hash(spec.seed, i, 0) > spec.density * 1.6) continue;
    canvas.drawCircle(
        origin,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6,
              gap * 0.08 * (1 + hash(spec.seed + 3, i, 1) * spec.variation * 4))
          ..color = _fade(i % 5 == 0 ? spec.accent : spec.foreground,
              spec.intensity * (1 - frac).clamp(0.0, 1.0)));
  }
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
    ui.Canvas canvas, String glyph, Offset at, double size, Color color) {
  if (color.a <= 0.004 || size < 1) return;

  var bucket = (color.a * 15).round();
  var key = "$glyph|${size.round()}|"
      "${(color.r * 255).round()},${(color.g * 255).round()},"
      "${(color.b * 255).round()}|$bucket";

  var painter = _glyphCache[key];
  if (painter == null) {
    if (_glyphCache.length >= _maxGlyphCache) _glyphCache.clear();
    painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
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
      var ink = noise.fbm(
          (p.dx / rect.width) * 3 + t * 0.15, (p.dy / rect.height) * 3,
          octaves: 3);
      var size = step * 0.62 * ink * (0.35 + spec.density * 1.3);
      if (size <= 0.15) continue;

      paint.color = _fade(ink > 0.72 ? spec.accent : spec.foreground,
          spec.intensity.clamp(0.0, 1.0));
      canvas.drawCircle(p, size, paint);
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
  // The vanishing point wanders with the seed, but stays near the middle: a
  // burst centred on a corner is a fan, not a burst.
  var from = Offset(
    rect.center.dx + (hash(spec.seed, 3, 1) - 0.5) * rect.width * 0.4,
    rect.center.dy + (hash(spec.seed, 5, 2) - 0.5) * rect.height * 0.4,
  );
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
      canvas.drawLine(mid - across * half, mid + across * half, paint);
    }
  }
}

/// _splatter is thrown ink: heavy blobs, satellite droplets around them, and
/// a drip or two running off the big ones.
void _splatter(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
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
  var noise = ValueNoise(spec.seed);
  var tongues = (3 + spec.density * 26).round();

  for (var i = 0; i < tongues; i++) {
    var x = rect.left +
        (i + 0.5) / tongues * rect.width +
        hashRange(spec.seed + 3, i, 0, -1, 1) * rect.width / tongues * 0.4;
    var height = rect.height *
        (0.25 + hash(spec.seed + 5, i, 1) * 0.85 * (0.4 + spec.density));
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:flutter/painting.dart';

// loop_effects.dart draws the loops that are more than a move: light swept
// through an element, its colours turned, a glow, sparkles, its outline
// drawn and run round, a ripple, a glitch. Each is given the element as a
// closure -- [body] draws it, as many times as the effect needs -- so one
// implementation serves a shape, a picture, a drawing and a table alike.

/// paintLoopEffect draws [body] -- an element in [bounds] -- with [loop]
/// at [p] of the way round its [round]th go. [outline] is the element's own
/// outline, for the loops that run along it; [seed] keeps its sparkles and
/// glitches its own.
void paintLoopEffect(ui.Canvas canvas, Rect bounds, ElementLoop loop, double p,
    int round, int seed, Path outline, void Function() body) {
  var room = bounds.inflate(math.max(bounds.width, bounds.height));
  var s = loop.strength;
  var colour = loop.colour.color;
  var short = math.max(1.0, bounds.shortestSide);
  switch (loop.preset) {
    case LoopPreset.shimmer || LoopPreset.colourWave:
      canvas.saveLayer(room, Paint());
      body();
      _sweep(canvas, room, bounds, loop, p);
      canvas.restore();
    case LoopPreset.colourCycle:
      canvas.saveLayer(
          room,
          Paint()
            ..colorFilter =
                ColorFilter.matrix(_hueTurn(360 * p * (s < 0 ? -1 : 1))));
      body();
      canvas.restore();
    case LoopPreset.glowPulse:
      var glow = math.sin(math.pi * p) * math.min(1.5, s);
      if (glow > 0.01) {
        canvas.saveLayer(
            room,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: short * (0.04 + 0.08 * glow),
                  sigmaY: short * (0.04 + 0.08 * glow))
              ..colorFilter = ColorFilter.mode(
                  colour.withValues(alpha: (0.9 * glow).clamp(0.0, 1.0)),
                  BlendMode.srcIn));
        body();
        canvas.restore();
      }
      body();
    case LoopPreset.sparkle:
      body();
      _sparkles(canvas, bounds, colour, p, round, seed, s);
    case LoopPreset.neonFlicker:
      // Mostly lit, now and then a stutter: a few frames' worth of the cycle
      // in which it drops low and comes back, different each go round.
      var step = (p * 30).floor();
      var noise = _noise(seed, round * 31 + step);
      var lit = noise > 0.22 * math.min(2, s) ? 1.0 : 0.25 + noise;
      canvas.saveLayer(
          room,
          Paint()
            ..imageFilter =
                ui.ImageFilter.blur(sigmaX: short * 0.06, sigmaY: short * 0.06)
            ..colorFilter = ColorFilter.mode(
                colour.withValues(alpha: 0.7 * lit), BlendMode.srcIn));
      body();
      canvas.restore();
      canvas.saveLayer(
          room, Paint()..color = Color.fromRGBO(0, 0, 0, lit.clamp(0.0, 1.0)));
      body();
      canvas.restore();
    case LoopPreset.drawOn:
      // On over the first half, off over the second: the outline drawn
      // along, and the inside filling in behind it.
      var q = p < 0.5 ? p * 2 : 1 - (p - 0.5) * 2;
      canvas.saveLayer(room, Paint());
      body();
      canvas.saveLayer(room, Paint()..blendMode = BlendMode.dstIn);
      canvas.drawPath(outline, Paint()..color = Color.fromRGBO(0, 0, 0, q * q));
      canvas.drawPath(
          _trimmed(outline, q),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, short * 0.08)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF000000));
      canvas.restore();
      canvas.restore();
    case LoopPreset.marchingAnts:
      body();
      var dash = math.max(3.0, short * 0.06);
      var ants = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, short * 0.02 * math.min(2, s))
        ..color = colour;
      for (var m in outline.computeMetrics()) {
        var period = dash * 2;
        for (var d = -period + (p * period); d < m.length; d += period) {
          var from = math.max(0.0, d), to = math.min(m.length, d + dash);
          if (to > from) canvas.drawPath(m.extractPath(from, to), ants);
        }
      }
    case LoopPreset.trace:
      body();
      var width = math.max(2.0, short * 0.03 * math.min(2, s));
      for (var m in outline.computeMetrics()) {
        var head = m.length * p;
        var tail = m.length * 0.18;
        // The tail in eight pieces, fading towards its end; the head with
        // a glow round it.
        for (var i = 0; i < 8; i++) {
          var a = head - tail * (i + 1) / 8, b = head - tail * i / 8;
          var piece = _wrapped(m, a, b);
          canvas.drawPath(
              piece,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = width * (1 - i / 10)
                ..color = colour.withValues(alpha: 1 - i / 8));
        }
        var at = m.getTangentForOffset(head % math.max(1e-6, m.length));
        if (at != null) {
          canvas.drawCircle(
              at.position,
              width * 1.6,
              Paint()
                ..color = colour
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, width));
        }
      }
    case LoopPreset.ripple:
      // Drawn in thin slices, each shifted by a wave travelling down it.
      var amp = short * 0.04 * s;
      const slices = 28;
      var top = bounds.top - amp, height = bounds.height + amp * 2;
      for (var i = 0; i < slices; i++) {
        var y0 = top + height * i / slices,
            y1 = top + height * (i + 1) / slices;
        var dx = math.sin(2 * math.pi * (i / slices * 1.5 - p)) * amp;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(room.left, y0, room.right, y1 + 0.5));
        canvas.translate(dx, 0);
        body();
        canvas.restore();
      }
    case LoopPreset.glitch:
      // Quiet for most of the cycle; for the first fifth, torn and split.
      if (p > 0.2) {
        body();
        break;
      }
      var step = (p * 60).floor();
      var shift = short * 0.04 * s;
      for (var (tint, way) in [
        (const Color(0xFFFF2A55), 1.0),
        (const Color(0xFF2AE6FF), -1.0),
      ]) {
        canvas.saveLayer(
            room,
            Paint()
              ..blendMode = BlendMode.plus
              ..colorFilter = ColorFilter.mode(
                  tint.withValues(alpha: 0.55), BlendMode.srcIn));
        canvas.translate(shift * way, 0);
        body();
        canvas.restore();
      }
      var bands = 7;
      for (var i = 0; i < bands; i++) {
        var y0 = bounds.top + bounds.height * i / bands;
        var y1 = bounds.top + bounds.height * (i + 1) / bands;
        var dx = (_noise(seed, round * 997 + step * 13 + i) - 0.5) *
            short *
            0.25 *
            s;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(room.left, y0, room.right, y1));
        canvas.translate(dx, 0);
        body();
        canvas.restore();
      }
    default:
      body();
  }
}

/// _sweep lays the loop's band across the layer, over what is in it only:
/// a bright soft band for a shimmer, a band of its colour -- or its
/// gradient's colours -- for a wave.
void _sweep(
    ui.Canvas canvas, Rect room, Rect bounds, ElementLoop loop, double p) {
  var a = loop.angle * math.pi / 180;
  // The way it travels: across, leaning as the band leans.
  var u = Offset(math.cos(a), math.sin(a));
  double along(Offset q) => q.dx * u.dx + q.dy * u.dy;
  var corners = [
    bounds.topLeft,
    bounds.topRight,
    bounds.bottomLeft,
    bounds.bottomRight
  ];
  var lo = corners.map(along).reduce(math.min);
  var hi = corners.map(along).reduce(math.max);
  var half = (hi - lo) * loop.band.clamp(0.02, 1.0) / 2;
  // From wholly before the element to wholly past it.
  var at = lo - half + (hi - lo + half * 2) * p;
  var centre = bounds.center + u * (at - along(bounds.center));
  var from = centre - u * half, to = centre + u * half;
  var c = loop.colour.color;
  List<Color> colours;
  List<double> stops;
  if (loop.preset == LoopPreset.shimmer) {
    var peak = c.withValues(alpha: (c.a * 0.85 * math.min(1, loop.strength)));
    colours = [c.withValues(alpha: 0), peak, c.withValues(alpha: 0)];
    stops = [0, 0.5, 1];
  } else if (loop.colour.fades) {
    var (ramp, places) = loop.colour.rampFor();
    colours = [
      ramp.first.withValues(alpha: 0),
      ...ramp,
      ramp.last.withValues(alpha: 0)
    ];
    stops = [0, for (var x in places) 0.1 + x * 0.8, 1];
  } else {
    colours = [c.withValues(alpha: 0), c, c, c.withValues(alpha: 0)];
    stops = [0, 0.2, 0.8, 1];
  }
  canvas.drawRect(
      room,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = ui.Gradient.linear(from, to, colours, stops));
}

/// _sparkles draws twinkling four-pointed glints over [bounds]: their
/// places new each go round, each glint with a moment of its own to shine.
void _sparkles(ui.Canvas canvas, Rect bounds, Color colour, double p, int round,
    int seed, double s) {
  var count = (5 + 3 * s).round().clamp(2, 14);
  var size = bounds.shortestSide * 0.09 * math.min(2, s);
  for (var i = 0; i < count; i++) {
    var x = bounds.left + bounds.width * _noise(seed, round * 101 + i * 3);
    var y = bounds.top + bounds.height * _noise(seed, round * 101 + i * 3 + 1);
    var start = _noise(seed, round * 101 + i * 3 + 2) * 0.6;
    var t = ((p - start) / 0.4).clamp(0.0, 1.0);
    var shine = math.sin(math.pi * t);
    if (shine <= 0.01) continue;
    var r = size * shine;
    var c = Offset(x, y);
    var star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawCircle(
        c,
        r * 0.6,
        Paint()
          ..color = colour.withValues(alpha: 0.35 * shine)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.4));
    canvas.drawPath(star, Paint()..color = colour.withValues(alpha: shine));
  }
}

/// _trimmed is the first [q] of every run of [path], as a pen drawing it
/// would have got.
Path _trimmed(Path path, double q) {
  var out = Path();
  for (var m in path.computeMetrics()) {
    if (q <= 0) break;
    out.addPath(m.extractPath(0, m.length * q.clamp(0.0, 1.0)), Offset.zero);
  }
  return out;
}

/// _wrapped is the stretch of [m] from [a] to [b], round again from its
/// start where [a] is before it -- a closed outline's tail running back
/// past where it began.
Path _wrapped(ui.PathMetric m, double a, double b) {
  var out = Path();
  if (b <= 0 && !m.isClosed) return out;
  var len = m.length;
  if (a >= 0) {
    out.addPath(m.extractPath(a, b), Offset.zero);
  } else if (m.isClosed) {
    out.addPath(m.extractPath(len + a, len), Offset.zero);
    out.addPath(m.extractPath(0, math.max(0, b)), Offset.zero);
  } else {
    out.addPath(m.extractPath(0, math.max(0, b)), Offset.zero);
  }
  return out;
}

/// _noise is a number from 0 to 1 that stays the same for the same [seed]
/// and [n] -- the same sparkle in the same place every time the frame is
/// drawn.
double _noise(int seed, int n) {
  var x = (seed * 374761393 + n * 668265263) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return (x ^ (x >> 16)) / 0x7fffffff;
}

/// _hueTurn is the colour matrix that turns every hue [degrees] round the
/// wheel, keeping how light each colour is.
List<double> _hueTurn(double degrees) {
  var a = degrees * math.pi / 180;
  var c = math.cos(a), s = math.sin(a);
  const r = 0.213, g = 0.715, b = 0.072;
  return [
    r + c * (1 - r) + s * -r, g + c * -g + s * -g, b + c * -b + s * (1 - b), 0,
    0, //
    r + c * -r + s * 0.143, g + c * (1 - g) + s * 0.140,
    b + c * -b + s * -0.283, 0, 0, //
    r + c * -r + s * -(1 - r), g + c * -g + s * g, b + c * (1 - b) + s * b, 0,
    0, //
    0, 0, 0, 1, 0, //
  ];
}

part of 'generators.dart';

// tech.dart is the Grids & tech family: dots, ruled lines, a honeycomb, a
// circuit board and falling symbols. (Blockchain is in blockchain.dart.)
//
// Each style's own settings default to what it drew before it had any, so
// that a document saved then is the same picture now; the new ones are all
// things a default leaves off.

/// _dot draws one dot of radius [r] at [p] in the shape [shape] -- circle,
/// square, diamond or cross.
void _dot(ui.Canvas canvas, Offset p, double r, int shape, Paint paint) {
  switch (shape) {
    case 1:
      canvas.drawRect(
          Rect.fromCenter(center: p, width: r * 1.8, height: r * 1.8), paint);
    case 2:
      canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - r * 1.25)
            ..lineTo(p.dx + r * 1.25, p.dy)
            ..lineTo(p.dx, p.dy + r * 1.25)
            ..lineTo(p.dx - r * 1.25, p.dy)
            ..close(),
          paint);
    case 3:
      var arm = r * 1.3, thick = r * 0.55;
      canvas.drawRect(
          Rect.fromCenter(center: p, width: arm * 2, height: thick), paint);
      canvas.drawRect(
          Rect.fromCenter(center: p, width: thick, height: arm * 2), paint);
    default:
      canvas.drawCircle(p, r, paint);
  }
}

/// _shade is how lit a cell at [p] is, nought to one, by one of the shared
/// ways of lighting a grid: drifting patches, evenly, a ripple out from the
/// middle, or a band sweeping across.
double _shade(int how, ValueNoise noise, double ix, double iy, Offset p,
    Rect rect, double unit, double t) {
  switch (how) {
    case 1:
      return 0.75;
    case 2:
      var d = (p - rect.center).distance / unit;
      return 0.5 + 0.5 * math.sin(d * 0.55 - t * 3);
    case 3:
      var x = (p.dx - rect.left) / rect.width;
      return math
          .pow(0.5 + 0.5 * math.sin(x * math.pi * 2 - t * 2), 2)
          .toDouble();
    default:
      return noise.fbm(ix * 0.15 + t * 0.2, iy * 0.15, octaves: 3);
  }
}

/// _dotGrid is an even field of dots, jittered and lit by a field so it does
/// not read as graph paper -- or, as an LED wall, cells lit in clusters.
void _dotGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  if (spec.choice("dotKind") == 1) return _ledGrid(canvas, rect, spec, t);
  var step = _unit(rect, spec) * 2;
  var noise = ValueNoise(spec.seed);
  var paint = Paint();
  var cols = (rect.width / step).ceil() + 2;
  var rows = (rect.height / step).ceil() + 1;
  var shape = spec.choice("dotShape");
  var size = spec.p("dotSize");
  var staggered = spec.choice("layout") == 1;
  var shading = spec.choice("shading");

  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var h = hash(spec.seed, ix, iy);
      if (h > spec.density) continue;

      var jx = (hash(spec.seed + 7, ix, iy) - 0.5) * step * spec.variation;
      var jy = (hash(spec.seed + 13, ix, iy) - 0.5) * step * spec.variation;
      var p = Offset(
          rect.left + ix * step + jx - (staggered && iy.isOdd ? step / 2 : 0),
          rect.top + iy * step + jy);

      // The field decides brightness rather than the per-dot hash, so the
      // dots cluster into drifts of light instead of being uniform static.
      var f = _shade(
          shading, noise, ix.toDouble(), iy.toDouble(), p, rect, step, t);
      var alpha = (f * spec.intensity).clamp(0.0, 1.0);
      paint.color =
          _fade(h < spec.density * 0.15 ? spec.accent : spec.foreground, alpha);
      _dot(canvas, p, step * size * (0.5 + f), shape, paint);
    }
  }
}

/// _ledGrid is a dot-matrix wall: cells lit in clusters rather than at random.
///
/// The clustering is what a plain per-cell hash does not give: lit cells form
/// blocks and runs, because a noise field decides the region's brightness and
/// the per-cell hash only decides whether this cell reaches it.
void _ledGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var cell = _unit(rect, spec);
  var cols = (rect.width / cell).ceil() + 1;
  var rows = (rect.height / cell).ceil() + 1;
  var noise = ValueNoise(spec.seed);
  var dot = cell * 0.34;
  var unlit = spec.on("unlit");
  var off = Paint()..color = _fade(spec.foreground, 0.07);

  canvas.saveLayer(rect, Paint());
  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      var p =
          Offset(rect.left + (ix + 0.5) * cell, rect.top + (iy + 0.5) * cell);
      var region = noise.fbm(ix * 0.08, iy * 0.08 + t * 0.25, octaves: 3);
      var h = hash(spec.seed, ix, iy);
      var lit = h < region * spec.density * 1.8;
      if (!lit) {
        // The dark cells of a real panel, which are what make it read as a
        // panel rather than as dots on a wall.
        if (unlit) canvas.drawCircle(p, dot, off);
        continue;
      }

      var hot = hash(spec.seed + 91, ix, iy);
      var color = hot > 0.86 ? spec.accent : spec.foreground;
      var alpha = spec.intensity * (0.25 + region * 0.75);

      // A diamond for a share of the cells, which breaks the grid up and
      // costs one branch.
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

/// _major is whether line [i] is one of the heavier ones, every [every].
bool _major(int i, int every) =>
    every > 0 && ((i % every) + every) % every == 0;

/// _lineGrid is ruled lines -- square, isometric, or a floor running away to
/// a horizon -- with every few of them heavier.
void _lineGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var step = _unit(rect, spec) * 2;
  var weight = spec.p("weight");
  var every = spec.p("major").round();
  var thin = Paint()
    ..color = _fade(spec.foreground, spec.intensity * 0.35)
    ..strokeWidth = math.max(0.5, step * 0.012) * weight;
  var thick = Paint()
    ..color = _fade(spec.accent, spec.intensity * 0.6)
    ..strokeWidth = math.max(1, step * 0.03) * weight;

  switch (spec.choice("gridLayout")) {
    case GridLayout.perspective:
      return _floorGrid(canvas, rect, spec, t, step, every, thin, thick);
    case GridLayout.isometric:
      // Three sets of lines at sixty degrees to one another: a grid of
      // triangles, which is what isometric drawing paper is.
      var gap = step * math.sqrt(3) / 2;
      var reach = rect.width + rect.height;
      var drift = spec.animated ? t * gap * 0.3 : 0.0;
      for (var a in [0.0, 60.0, 120.0]) {
        var r = a * math.pi / 180;
        var along = Offset(math.cos(r), math.sin(r));
        var across = Offset(-along.dy, along.dx);
        var n = (reach / gap).ceil();
        var shift = drift % gap;
        var first = (drift / gap).floor();
        for (var k = -n; k <= n; k++) {
          var c = rect.center + across * (k * gap + shift);
          canvas.drawLine(c - along * reach, c + along * reach,
              _major(k - first, every) ? thick : thin);
        }
      }
      return;
    default:
      // Drifting, where it moves, a cell's width a few seconds -- slowly, so
      // it is a background that is alive rather than one that is going
      // somewhere.
      var drift = spec.animated ? t * step * 0.25 : 0.0;
      var first = (drift / step).floor();
      var shift = drift - first * step;
      var cols = (rect.width / step).ceil() + 1;
      for (var i = -1; i <= cols; i++) {
        var x = rect.left + i * step - shift;
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom),
            _major(i + first, every) ? thick : thin);
      }
      var rows = (rect.height / step).ceil() + 1;
      for (var i = -1; i <= rows; i++) {
        var y = rect.top + i * step - shift;
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y),
            _major(i + first, every) ? thick : thin);
      }
  }
}

/// _floorGrid is the grid laid flat and seen from just above it: lines
/// running away to a point on the horizon, and lines across that crowd
/// together as they get further off -- and, where asked, a sun setting
/// behind it all.
void _floorGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t,
    double step, int every, Paint thin, Paint thick) {
  var horizon = rect.top + rect.height * spec.p("horizon");
  var depth = rect.bottom - horizon;
  var vanish = Offset(rect.center.dx, horizon);

  if (spec.on("sun")) _sun(canvas, rect, spec, horizon);

  // Faded towards the horizon, where the lines are packed too close to be
  // lines and would otherwise be a solid bar.
  Paint faded(Paint p) => Paint()
    ..strokeWidth = p.strokeWidth
    ..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, rect.bottom),
        [p.color.withValues(alpha: 0), p.color, p.color], [0, 0.45, 1]);

  canvas.save();
  canvas.clipRect(Rect.fromLTRB(rect.left, horizon, rect.right, rect.bottom));
  var fThin = faded(thin), fThick = faded(thick);

  // Running away: spaced a cell apart along the bottom edge, and far enough
  // either side that the ones leaving at a slant reach the corners.
  var spread = step * 1.6;
  var n = (rect.width * 3 / spread).ceil();
  for (var i = -n; i <= n; i++) {
    var foot = Offset(rect.center.dx + i * spread, rect.bottom);
    canvas.drawLine(vanish, foot, _major(i, every) ? fThick : fThin);
  }

  // Across: equally spaced on the floor, which on the page is one over the
  // distance. Coming forwards, where it moves.
  var travel = spec.animated ? t * 0.8 : 0.0;
  var near = (travel).floor();
  var frac = travel - near;
  for (var k = 1; k < 400; k++) {
    var z = k - frac;
    if (z <= 0.05) continue;
    var y = horizon + depth * 0.9 / z;
    if (y > rect.bottom + 2) continue;
    if (y - horizon < 0.8) break;
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y),
        _major(k + near, every) ? fThick : fThin);
  }
  canvas.restore();
}

/// _sun is the striped sun of a retro horizon: a disc fading from the accent
/// down to the main colour, with slots cut out of its lower half that widen
/// towards the horizon.
void _sun(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double horizon) {
  var r = math.min(rect.width * 0.17, (horizon - rect.top) * 0.62);
  if (r <= 2) return;
  var c = Offset(rect.center.dx, horizon - r * 0.55);
  var box = Rect.fromCircle(center: c, radius: r);
  canvas.saveLayer(box, Paint());
  canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(box.topCenter, box.bottomCenter, [
          _fade(spec.accent, spec.intensity),
          _fade(spec.foreground, spec.intensity),
        ]));
  var cut = Paint()..blendMode = BlendMode.clear;
  for (var k = 0; k < 7; k++) {
    var y = c.dy + r * (0.05 + k * 0.15);
    var h = r * (0.02 + k * 0.016);
    canvas.drawRect(Rect.fromLTWH(box.left, y, box.width, h), cut);
  }
  canvas.restore();
  // And the glow round it.
  canvas.drawCircle(
      c,
      r * 1.8,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(c, r * 1.8, [
          _fade(spec.accent, spec.intensity * 0.35),
          _fade(spec.accent, 0),
        ], [
          0.5,
          1
        ]));
}

/// _hexGrid is a honeycomb: outlined cells, tiles, or raised tiles lit from
/// above, with some of them lit up.
void _hexGrid(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var r = _unit(rect, spec) * 1.5;
  var w = r * math.sqrt(3);
  var h = r * 1.5;
  var style = spec.choice("hexStyle");
  var inner = r * (1 - spec.p("gap"));
  var weight = spec.p("weight");
  var shading = spec.choice("shading");
  var noise = ValueNoise(spec.seed);
  var stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, r * 0.04) * weight
    ..color = _fade(spec.foreground, spec.intensity * 0.5);

  var rows = (rect.height / h).ceil() + 2;
  var cols = (rect.width / w).ceil() + 2;
  for (var iy = -1; iy < rows; iy++) {
    for (var ix = -1; ix < cols; ix++) {
      var cx = rect.left + ix * w + (iy.isOdd ? w / 2 : 0);
      var cy = rect.top + iy * h;
      var corners = [
        for (var k = 0; k < 6; k++)
          Offset(cx + math.cos(math.pi / 180 * (60 * k - 90)) * inner,
              cy + math.sin(math.pi / 180 * (60 * k - 90)) * inner),
      ];
      var path = Path()..addPolygon(corners, true);

      // How lit this cell is: nought is not lit at all.
      double lit;
      switch (shading) {
        case 1:
          var f = noise.fbm(ix * 0.12 + t * 0.15, iy * 0.12, octaves: 3);
          lit = ((f - (1 - spec.density * 0.8)) * 3).clamp(0.0, 1.0);
        case 2:
          var d = (Offset(cx, cy) - rect.center).distance / r;
          var wave = 0.5 + 0.5 * math.sin(d * 0.6 - t * 2.5);
          lit = math.pow(wave, 4) * spec.density * 1.6;
        default:
          lit = hash(spec.seed, ix, iy) < spec.density * 0.4
              ? hash(spec.seed + 3, ix, iy) *
                  (spec.animated
                      ? 0.5 +
                          0.5 *
                              math.sin(
                                  t * 1.5 + hash(spec.seed + 5, ix, iy) * 6.3)
                      : 1)
              : 0;
      }

      if (style != 0) {
        // A tile under every cell, so the honeycomb is a surface.
        canvas.drawPath(
            path,
            Paint()
              ..color = _fade(
                  spec.foreground,
                  spec.intensity *
                      ((style == 2 ? 0.2 : 0.1) +
                          0.08 * hash(spec.seed + 9, ix, iy))));
      }
      if (lit > 0) {
        canvas.drawPath(
            path,
            Paint()
              ..color = _fade(
                  spec.accent,
                  (spec.intensity * lit * (style == 0 ? 0.5 : 0.8))
                      .clamp(0.0, 1.0)));
      }
      if (style == 2) {
        // Raised: the edges facing up catch the light and the ones facing
        // down are in shadow.
        var bevel = math.max(0.8, inner * 0.09) * weight;
        var light = Paint()
          ..strokeWidth = bevel
          ..strokeCap = StrokeCap.round
          ..color = _fade(const Color(0xFFFFFFFF), 0.22 * spec.intensity);
        var dark = Paint()
          ..strokeWidth = bevel
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x66000000);
        for (var k = 0; k < 6; k++) {
          var a = corners[k], b = corners[(k + 1) % 6];
          // Corner nought is the top; the three edges after it face right
          // and down, the three before it left and up.
          var down = k >= 1 && k <= 3;
          canvas.drawLine(a, b, down ? dark : light);
        }
      } else if (style == 0) {
        canvas.drawPath(path, stroke);
      }
    }
  }
}

/// _pulseDot is something travelling along a trace: a bright point with a
/// soft halo round it.
void _pulseDot(ui.Canvas canvas, Offset at, double r, Color color) {
  canvas.drawCircle(
      at,
      r * 4,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(at, r * 4, [
          _fade(color, 0.5),
          _fade(color, 0),
        ]));
  canvas.drawCircle(at, r, Paint()..color = color);
}

/// _along is the point [d] along the polyline [pts].
Offset _along(List<Offset> pts, double d) {
  for (var i = 0; i + 1 < pts.length; i++) {
    var seg = (pts[i + 1] - pts[i]).distance;
    if (d <= seg) {
      return seg == 0 ? pts[i] : Offset.lerp(pts[i], pts[i + 1], d / seg)!;
    }
    d -= seg;
  }
  return pts.last;
}

/// _circuit is right-angled traces with pads where they turn -- or, angled,
/// traces cut across their corners the way a board is routed -- with chips
/// sitting over them and data running along them.
void _circuit(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var cell = _unit(rect, spec) * 1.6;
  var cols = math.max(2, (rect.width / cell).ceil());
  var rows = math.max(2, (rect.height / cell).ceil());
  var rnd = SeededRandom(spec.seed);
  var traces = 4 + (spec.density * 60).round();
  var stroke = math.max(0.8, cell * 0.06) * spec.p("weight");
  var angled = spec.choice("corners") == 1;
  var pads = spec.choice("pads");
  var pulses = spec.p("pulses");

  var glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  for (var i = 0; i < traces; i++) {
    var x = rnd.intRange(0, cols);
    var y = rnd.intRange(0, rows);
    var len = 3 + rnd.intRange(0, 6 + (spec.variation * 14).round());
    var pts = <Offset>[Offset(rect.left + x * cell, rect.top + y * cell)];

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
      pts.add(Offset(rect.left + x * cell, rect.top + y * cell));
      horizontal = !horizontal;
    }

    // A slow pulse along the traces when animated, so the board looks powered
    // rather than printed. Each trace gets its own phase from the sequence, so
    // they do not all breathe together.
    var phase = rnd.next() * math.pi * 2;
    var pulse = spec.animated ? 0.55 + 0.45 * math.sin(t * 1.6 + phase) : 1.0;

    // Angled, each corner is cut across at forty-five degrees, which is
    // what makes a board look routed rather than drawn on squared paper.
    var route = pts;
    if (angled && pts.length > 2) {
      var cut = cell * 0.45;
      route = [pts.first];
      for (var k = 1; k + 1 < pts.length; k++) {
        var p = pts[k], a = pts[k - 1], b = pts[k + 1];
        var toA = a - p, toB = b - p;
        if (toA.distance < 1e-6 || toB.distance < 1e-6) continue;
        var c = math.min(cut, math.min(toA.distance, toB.distance) / 2);
        route.add(p + toA / toA.distance * c);
        route.add(p + toB / toB.distance * c);
      }
      route.add(pts.last);
    }
    var path = Path()..addPolygon(route, false);
    glow.color = _fade(spec.foreground, spec.intensity * 0.45 * pulse);
    canvas.drawPath(path, glow);

    if (pads != 2) {
      var padPaint = Paint()
        ..color = _fade(spec.accent, spec.intensity * 0.7 * pulse);
      var ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.9
        ..color = padPaint.color;
      // Square corners have a pad on every turn; routed traces only end in
      // one -- a via -- since a cut corner has nothing to land a pad on.
      var at = angled ? [pts.first, pts.last] : pts.skip(1);
      for (var p in at) {
        if (pads == 1) {
          canvas.drawCircle(p, stroke * 2.2, ring);
        } else {
          canvas.drawCircle(p, stroke * 1.8, padPaint);
        }
      }
    }

    // Data on its way along the trace.
    if (pulses > 0 && hash(spec.seed + 61, i, 0) < pulses) {
      var total = 0.0;
      for (var k = 0; k + 1 < route.length; k++) {
        total += (route[k + 1] - route[k]).distance;
      }
      if (total > 0) {
        var speed = 0.15 + hash(spec.seed + 67, i, 1) * 0.25;
        var f = t * speed + hash(spec.seed + 71, i, 2);
        f -= f.floorToDouble();
        _pulseDot(canvas, _along(route, f * total), stroke * 1.3,
            _fade(spec.accent, spec.intensity));
      }
    }
  }

  // Chips over the traces, as if the traces ran underneath to their pins.
  var chips =
      (spec.p("chips") * rect.width * rect.height / (cell * cell * 40)).round();
  for (var i = 0; i < chips; i++) {
    var wide = 3 + (hash(spec.seed + 81, i, 0) * 5).floor();
    var tall = 2 + (hash(spec.seed + 83, i, 1) * 3).floor();
    var cx = (hash(spec.seed + 87, i, 2) * cols).floor();
    var cy = (hash(spec.seed + 89, i, 3) * rows).floor();
    var body = Rect.fromLTWH(
        rect.left + cx * cell + cell * 0.15,
        rect.top + cy * cell + cell * 0.15,
        wide * cell - cell * 0.3,
        tall * cell - cell * 0.3);
    var pin = Paint()
      ..strokeWidth = math.max(0.8, stroke * 0.8)
      ..color = _fade(spec.foreground, spec.intensity * 0.7);
    var pitch = cell * 0.35;
    for (var x = body.left + pitch / 2; x < body.right; x += pitch) {
      canvas.drawLine(
          Offset(x, body.top - cell * 0.18), Offset(x, body.top), pin);
      canvas.drawLine(
          Offset(x, body.bottom), Offset(x, body.bottom + cell * 0.18), pin);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(cell * 0.06)),
        Paint()
          ..color =
              Color.lerp(spec.background, const Color(0xFF000000), 0.35)!);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(cell * 0.06)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, stroke * 0.7)
          ..color = _fade(spec.foreground, spec.intensity * 0.6));
    // The dot that says which way round it goes.
    canvas.drawCircle(
        body.topLeft + Offset(cell * 0.2, cell * 0.2),
        cell * 0.06,
        Paint()..color = _fade(spec.foreground, spec.intensity * 0.5));
  }
}

/// _rain is columns of falling glyphs, brightest at the head of each column
/// -- or, as a field, glyphs scattered at varying size and angle.
void _rain(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  if (spec.choice("mode") == 1) return _symbolField(canvas, rect, spec, t);
  var glyphs = spec.glyphs.isEmpty ? defaultGlyphs : spec.glyphs;
  var size = _unit(rect, spec);
  var colWidth = size * 0.9 * spec.p("spacing");
  var cols = (rect.width / colWidth).ceil() + 1;
  var rowsOnScreen = (rect.height / size).ceil() + 2;
  var trail = spec.p("trail");
  var up = spec.choice("direction") == 1;
  var heads = spec.on("headGlow");

  for (var ix = 0; ix < cols; ix++) {
    if (hash(spec.seed + 5, ix, 0) > spec.density * 1.4) continue;

    var speed =
        0.4 + hash(spec.seed + 11, ix, 1) * (0.6 + spec.variation * 2.5);
    var tail = (4 +
            (hash(spec.seed + 17, ix, 2) * (6 + spec.variation * 26)).round()) *
        trail;
    var tailLen = math.max(1, tail.round());
    // The head is measured in rows and advances with time. Offsetting by the
    // column's own hash is what stops every column starting level, which is
    // the single most obvious giveaway that a rain effect is generated.
    var head = (hash(spec.seed + 23, ix, 3) * rowsOnScreen * 3) +
        (spec.animated ? t * speed * 6 : 0);

    var x = rect.left + ix * colWidth;
    for (var k = 0; k < tailLen; k++) {
      var row = (head - k) % (rowsOnScreen + tailLen);
      var y = up ? rect.bottom - row * size : rect.top + row * size;
      if (y < rect.top - size || y > rect.bottom + size) continue;

      // The glyph is chosen from the *cell*, not from the position in the
      // tail, so a column's characters stay put while the light runs down
      // through them -- which is what makes it read as falling light rather
      // than as scrolling text.
      var cellRow = row.floor();
      var gi = (hash(spec.seed + 31, ix,
                  cellRow + (spec.animated ? (t * speed).floor() : 0)) *
              glyphs.length)
          .floor()
          .clamp(0, glyphs.length - 1);

      var fade = k == 0 ? 1.0 : (1 - k / tailLen);
      var color = k == 0 ? spec.accent : spec.foreground;
      if (k == 0 && heads) {
        canvas.drawCircle(
            Offset(x, y),
            size * 1.1,
            Paint()
              ..blendMode = BlendMode.plus
              ..shader = ui.Gradient.radial(Offset(x, y), size * 1.1, [
                _fade(spec.accent, spec.intensity * 0.5),
                _fade(spec.accent, 0),
              ]));
      }
      _drawGlyph(canvas, glyphs[gi], Offset(x, y), size,
          _fade(color, spec.intensity * fade * fade), _glyphFont(spec));
    }
  }
}

/// _glyphFont is the face the symbols are drawn in: the system's own, which
/// has the most characters, or one of the app's.
String? _glyphFont(ProceduralSpec spec) => switch (spec.choice("glyphFont")) {
      1 => "RobotoMono",
      2 => "PTSerif",
      _ => null,
    };

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
            spec.intensity * rnd.range(0.15, 0.9)),
        _glyphFont(spec));
    canvas.restore();
  }
}

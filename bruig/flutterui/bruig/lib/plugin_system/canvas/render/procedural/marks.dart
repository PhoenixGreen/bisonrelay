part of 'generators.dart';

// marks.dart is the new kinds the Organic and Graphic & comic styles were
// given: filled terrain, soft fire and embers, halftone dots that are not
// circles, parallel speed lines, shaded hatching, drips and spray.
//
// The styles themselves are still in generators.dart, each drawing what it
// always drew by default and handing over to one of these when asked.

/// _terrain fills the bands between contour lines, low ground in the base
/// colour rising through the main colour to the accent at the peaks -- the
/// colours of a relief map.
void _terrain(ui.Canvas canvas, Rect rect, ProceduralSpec spec,
    List<List<double>> field, int cols, int rows, double cell, int levels) {
  // The field's own grid, so each corner is a value already worked out.
  var area = Rect.fromLTWH(rect.left, rect.top, cols * cell, rows * cell);
  _colourGrid(canvas, area, cols, rows, (u, v) {
    var f = field[(v * rows).round()][(u * cols).round()];
    // Stepped, so that each band is one colour, as a printed map is.
    var band = (f * levels).floor() / levels;
    var c = band < 0.5
        ? Color.lerp(spec.background, spec.foreground, band * 2)!
        : Color.lerp(spec.foreground, spec.accent, (band - 0.5) * 2)!;
    return _argb(c, spec.intensity.clamp(0.0, 1.0) * 0.85);
  });
}

/// _screenDot is one dot of a halftone screen that is not a circle: a
/// square or a diamond turned to the screen, or a short bar -- which, side
/// by side, are the lines of a line screen.
void _screenDot(ui.Canvas canvas, Offset p, double size, double step, int shape,
    double cos, double sin, Paint paint) {
  Offset turned(double x, double y) =>
      Offset(p.dx + x * cos - y * sin, p.dy + x * sin + y * cos);
  List<Offset> corners;
  switch (shape) {
    case 1:
      var h = size * 0.9;
      corners = [turned(-h, -h), turned(h, -h), turned(h, h), turned(-h, h)];
    case 2:
      var h = size * 1.2;
      corners = [turned(0, -h), turned(h, 0), turned(0, h), turned(-h, 0)];
    default:
      // A bar the full width of its cell, as thick as the ink is heavy.
      var w = step / 2 + 0.5, h = size * 0.8;
      corners = [turned(-w, -h), turned(w, -h), turned(w, h), turned(-w, h)];
  }
  canvas.drawPath(Path()..addPolygon(corners, true), paint);
}

/// _parallelLines is speed lines that all run one way: a streak of motion
/// across the frame rather than a burst out of a point.
void _parallelLines(
    ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var count = (12 + spec.density * 90).round();
  var paint = Paint();
  // Turned by the pattern's own rotation like everything else; across the
  // frame by default.
  for (var i = 0; i < count; i++) {
    var y = rect.top + hash(spec.seed + 3, i, 0) * rect.height;
    var thick = rect.height *
        (0.002 + hash(spec.seed + 5, i, 1) * 0.012 * (0.4 + spec.variation));
    var len = rect.width * (0.25 + hash(spec.seed + 7, i, 2) * 0.6);
    // Each streak travelling at its own pace, coming round again once it is
    // off the far side.
    var speed = 0.2 + hash(spec.seed + 9, i, 3) * 0.6;
    var x0 = hash(spec.seed + 11, i, 4) + (spec.animated ? t * speed : 0);
    x0 = (x0 - x0.floorToDouble()) * (rect.width + len) - len;
    var a = Offset(rect.left + x0, y), b = Offset(rect.left + x0 + len, y);
    paint.shader = ui.Gradient.linear(a, b, [
      _fade(i % 7 == 0 ? spec.accent : spec.foreground, 0),
      _fade(i % 7 == 0 ? spec.accent : spec.foreground, spec.intensity),
    ]);
    // Tapered: thick at the leading end and nothing at the tail.
    canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy - thick)
          ..lineTo(b.dx, b.dy + thick)
          ..close(),
        paint);
  }
}

/// _hatchLine is one stroke of hatching drawn by hand: wavering a little
/// where it is asked to, and -- shaded -- laid only where the tone is dark
/// enough for this pass of strokes to be there.
void _hatchLine(
    ui.Canvas canvas,
    Rect rect,
    Offset mid,
    Offset across,
    Offset along,
    double half,
    double step,
    int pass,
    int line,
    bool shaded,
    double wobble,
    ValueNoise noise,
    int seed,
    Paint paint) {
  var pieces = math.max(4, (half * 2 / (step * 1.5)).ceil());
  // Each pass of strokes is only laid where the tone is darker than the
  // last: the first everywhere but the lightest places, the third only in
  // the deepest shadow. Which is how hatching makes a tone at all.
  var threshold = 0.35 + pass * 0.15;
  Path? run;
  var path = Path();
  for (var k = 0; k <= pieces; k++) {
    var f = k / pieces;
    var p = mid + across * (half * (f * 2 - 1));
    if (wobble > 0) {
      var w = (noise.fbm(p.dx / step * 0.15, p.dy / step * 0.15 + line,
                  octaves: 2) -
              0.5) *
          step *
          wobble *
          1.6;
      p += along * w;
    }
    var dark = !shaded ||
        noise.fbm((p.dx - rect.left) / rect.width * 3,
                (p.dy - rect.top) / rect.height * 3,
                octaves: 3) >
            threshold;
    if (dark) {
      if (run == null) {
        run = path..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    } else {
      run = null;
    }
  }
  canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..strokeWidth = paint.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke);
}

/// _drips is paint running down from the top edge: a wet band along the
/// top, and runs of it hanging down at different lengths, each ending in a
/// drop.
void _drips(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var unit = _unit(rect, spec);
  var runs = (6 + spec.density * 40).round();
  var band = rect.height * (0.04 + spec.density * 0.08);
  for (var layer = 0; layer < 2; layer++) {
    var colour = layer == 0 ? spec.foreground : spec.accent;
    var paint = Paint()..color = _fade(colour, spec.intensity.clamp(0.0, 1.0));
    var seed = spec.seed + layer * 101;
    var top = rect.top + (layer == 0 ? 0 : band * 0.4);
    var depth = layer == 0 ? band : band * 0.55;
    // The band along the top, its lower edge wavering.
    var edge = Path()..moveTo(rect.left, top);
    var steps = 40;
    for (var k = 0; k <= steps; k++) {
      var x = rect.left + rect.width * k / steps;
      edge.lineTo(x, top + depth * (0.7 + 0.3 * hash(seed, k, 0)));
    }
    edge
      ..lineTo(rect.right, top)
      ..close();
    canvas.drawPath(edge, paint);
    var many = layer == 0 ? runs : runs ~/ 3;
    for (var i = 0; i < many; i++) {
      var x = rect.left + hash(seed, i, 1) * rect.width;
      var w = unit * (0.25 + hash(seed, i, 2) * 0.9 * (0.4 + spec.variation));
      var full = rect.height * (0.08 + hash(seed, i, 3) * 0.7);
      // Still running, where it moves: each run creeps down to its full
      // length over a few seconds and stays there.
      var grown = spec.animated
          ? (t * (0.15 + hash(seed, i, 4) * 0.3)).clamp(0.0, 1.0)
          : 1.0;
      var len = full * (1 - math.pow(1 - grown, 2));
      var y0 = top + depth * 0.5;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x - w / 2, y0, w, len), Radius.circular(w / 2)),
          paint);
      canvas.drawCircle(Offset(x, y0 + len), w * 0.75, paint);
    }
  }
}

/// _spray is paint from an airbrush: clouds of fine specks, thick in the
/// middle of each and thinning out to nothing.
void _spray(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var unit = _unit(rect, spec);
  var clouds = (2 + spec.density * 10).round();
  var rnd = SeededRandom(spec.seed);
  for (var c = 0; c < clouds; c++) {
    var centre = Offset(rect.left + rnd.next() * rect.width,
        rect.top + rnd.next() * rect.height);
    var r = unit * (3 + rnd.next() * 8);
    var colour = c % 3 == 2 ? spec.accent : spec.foreground;
    var specks = (r * r / (unit * unit) * 45).round().clamp(80, 12000);
    var points = Float32List(specks * 2);
    for (var k = 0; k < specks; k++) {
      // Gathered towards the middle: the square of a random number is
      // small far more often than it is large.
      var d = r * math.pow(rnd.next(), 1.6 - spec.variation * 0.6);
      var a = rnd.next() * math.pi * 2;
      points[k * 2] = centre.dx + math.cos(a) * d;
      points[k * 2 + 1] = centre.dy + math.sin(a) * d;
    }
    canvas.drawRawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..strokeWidth = math.max(1.0, unit * 0.09)
          ..strokeCap = StrokeCap.round
          ..color = _fade(colour, spec.intensity * 0.9));
  }
}

/// _softFire is fire as light rather than as shapes: tongues filled from a
/// hot core at the bottom, through the main colour, to nothing at the tips,
/// laid over one another additively and softened.
void _softFire(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var tongues = (6 + spec.density * 30).round();
  var tall = spec.p("height");
  canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
            sigmaX: rect.width * 0.004, sigmaY: rect.width * 0.004));
  for (var i = 0; i < tongues; i++) {
    var x = rect.left +
        (i + 0.5) / tongues * rect.width +
        hashRange(spec.seed + 3, i, 0, -1, 1) * rect.width / tongues;
    // Flickering: a tongue's height swells and falls of its own accord.
    var flicker =
        0.8 + 0.2 * math.sin(t * (3 + hash(spec.seed + 4, i, 0) * 4) + i * 1.3);
    var height = rect.height *
        (0.3 + hash(spec.seed + 5, i, 1) * 0.7) *
        (0.4 + spec.density * 0.6) *
        tall *
        (spec.animated ? flicker : 1);
    var wide = rect.width / tongues * (1.2 + hash(spec.seed + 7, i, 2) * 1.4);
    var left = <Offset>[], right = <Offset>[];
    const steps = 18;
    for (var s = 0; s <= steps; s++) {
      var up = s / steps;
      var w =
          wide * math.pow(1 - up, 0.8) * (0.6 + 0.4 * math.sin((1 - up) * 2.6));
      var sway = noise.fbm(i * 1.7 + up * 2.2, t * 0.9 - up * 1.4, octaves: 3);
      var lean = (sway - 0.5) * wide * 2.6 * (0.3 + spec.variation) * up;
      var y = rect.bottom - height * up;
      left.add(Offset(x + lean - w / 2, y));
      right.add(Offset(x + lean + w / 2, y));
    }
    var path = Path()..addPolygon([...left, ...right.reversed], true);
    canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
              Offset(x, rect.bottom), Offset(x, rect.bottom - height), [
            _fade(spec.accent, spec.intensity * 0.9),
            _fade(spec.foreground, spec.intensity * 0.7),
            _fade(spec.foreground, 0),
          ], [
            0,
            0.35,
            1
          ]));
  }
  canvas.restore();
}

/// _embers is sparks rising from the fire, each drifting as it climbs and
/// fading out before it reaches the top.
void _embers(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var many = (spec.p("embers") * 80).round();
  var unit = _unit(rect, spec);
  for (var i = 0; i < many; i++) {
    var speed = 0.08 + hash(spec.seed + 13, i, 0) * 0.15;
    var life = hash(spec.seed + 14, i, 1) + t * speed;
    life -= life.floorToDouble();
    var x = rect.left +
        hash(spec.seed + 15, i, 2) * rect.width +
        math.sin(life * 9 + i) * unit * 0.8;
    var y = rect.bottom - life * rect.height * 0.9;
    var a = spec.intensity *
        math.sin(life * math.pi) *
        (0.5 + hash(spec.seed + 16, i, 3) * 0.5);
    var r = math.max(0.8, unit * 0.06 * (0.6 + hash(spec.seed + 17, i, 4)));
    canvas.drawCircle(
        Offset(x, y),
        r * 3,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(Offset(x, y), r * 3, [
            _fade(spec.accent, a * 0.8),
            _fade(spec.accent, 0),
          ]));
    canvas.drawCircle(Offset(x, y), r, Paint()..color = _fade(spec.accent, a));
  }
}

/// _smoothClosed is a closed curve passing smoothly through [pts]: a
/// Catmull-Rom spline, turned into the cubic curves a Path takes.
Path _smoothClosed(List<Offset> pts) {
  var path = Path();
  var n = pts.length;
  if (n < 3) return path;
  path.moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    var p0 = pts[(i - 1 + n) % n], p1 = pts[i];
    var p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    var c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// _splash is paint thrown hard at a wall: a smooth body, spikes shot out
/// from it with drops pinching off their tips, teardrops flung further, and
/// a fine mist round it all.
void _splash(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var unit = _unit(rect, spec);
  var splats = (1 + spec.density * 9).round();
  var short = math.min(rect.width, rect.height);
  for (var k = 0; k < splats; k++) {
    var seed = spec.seed * 31 + k * 977;
    var c = Offset(rect.left + hash(seed, 1, 0) * rect.width,
        rect.top + hash(seed, 2, 0) * rect.height);
    var r = short * (0.04 + hash(seed, 3, 0) * 0.08) * (unit / (short * 0.05));
    var colour = hash(seed, 4, 0) < 0.25 ? spec.accent : spec.foreground;
    var paint = Paint()
      ..color = _fade(colour, spec.intensity.clamp(0.0, 1.0))
      ..isAntiAlias = true;
    var wild = 0.4 + spec.variation;

    // The body: lumpy, but smooth -- liquid has no corners.
    const around = 28;
    var body = [
      for (var i = 0; i < around; i++)
        (() {
          var a = i / around * math.pi * 2;
          var lump = 0.78 +
              0.3 * hash(seed, i, 5) * wild +
              0.12 * math.sin(a * 3 + hash(seed, 6, 0) * 6);
          return c + Offset(math.cos(a), math.sin(a)) * r * lump;
        })(),
    ];
    canvas.drawPath(_smoothClosed(body), paint);

    // The spikes: tapering from the edge of the body to a point, and some
    // with a drop pinched off the end.
    var spikes = (6 + wild * 12).round();
    for (var i = 0; i < spikes; i++) {
      var a = hash(seed, i, 7) * math.pi * 2;
      var dir = Offset(math.cos(a), math.sin(a));
      var side = Offset(-dir.dy, dir.dx);
      var len = r * (0.5 + hash(seed, i, 8) * 1.4 * wild);
      var w = r * (0.08 + hash(seed, i, 9) * 0.14);
      var base = c + dir * r * 0.7;
      var tip = base + dir * (r * 0.3 + len);
      var path = Path()
        ..moveTo((base + side * w).dx, (base + side * w).dy)
        ..quadraticBezierTo((base + dir * len * 0.5 + side * w * 0.35).dx,
            (base + dir * len * 0.5 + side * w * 0.35).dy, tip.dx, tip.dy)
        ..quadraticBezierTo(
            (base + dir * len * 0.5 - side * w * 0.35).dx,
            (base + dir * len * 0.5 - side * w * 0.35).dy,
            (base - side * w).dx,
            (base - side * w).dy)
        ..close();
      canvas.drawPath(path, paint);
      if (hash(seed, i, 10) < 0.55) {
        var drop = tip + dir * w * (1.2 + hash(seed, i, 11) * 2);
        canvas.drawCircle(drop, w * (0.5 + hash(seed, i, 12) * 0.6), paint);
      }
    }

    // Teardrops flung further, each pointing back the way it came.
    var drops = (8 + wild * 22).round();
    for (var i = 0; i < drops; i++) {
      var a = hash(seed, i, 13) * math.pi * 2;
      var dir = Offset(math.cos(a), math.sin(a));
      var far = r * (1.5 + math.pow(hash(seed, i, 14), 1.5) * 3.5 * wild);
      var size = r *
          0.12 *
          (1.2 - far / (r * 5.5)).clamp(0.15, 1.0) *
          (0.5 + hash(seed, i, 15));
      var at = c + dir * far;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(a);
      canvas.drawPath(
          Path()
            ..addOval(Rect.fromCenter(
                center: Offset.zero, width: size * 2.6, height: size * 1.6))
            ..moveTo(-size * 1.1, -size * 0.45)
            ..quadraticBezierTo(-size * 2.8, 0, -size * 1.1, size * 0.45)
            ..close(),
          paint);
      canvas.restore();
    }

    // And the mist: specks too small to have a shape.
    var mist = (40 + wild * 160).round();
    var points = Float32List(mist * 2);
    for (var i = 0; i < mist; i++) {
      var a = hash(seed, i, 16) * math.pi * 2;
      var d = r * (1.1 + math.pow(hash(seed, i, 17), 0.7) * 3.2);
      points[i * 2] = c.dx + math.cos(a) * d;
      points[i * 2 + 1] = c.dy + math.sin(a) * d;
    }
    canvas.drawRawPoints(
        ui.PointMode.points,
        points,
        Paint()
          ..color = paint.color
          ..strokeWidth = math.max(1.0, r * 0.03)
          ..strokeCap = StrokeCap.round);
  }
}

/// _watercolour is washes of paint on paper: each a few thin layers that
/// do not quite line up, darker at the edges where the pigment gathered as
/// it dried.
void _watercolour(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var unit = _unit(rect, spec);
  var short = math.min(rect.width, rect.height);
  var washes = (2 + spec.density * 9).round();
  var noise = ValueNoise(spec.seed + 3);
  for (var k = 0; k < washes; k++) {
    var seed = spec.seed * 17 + k * 613;
    var c = Offset(rect.left + hash(seed, 1, 0) * rect.width,
        rect.top + hash(seed, 2, 0) * rect.height);
    var r = short * (0.12 + hash(seed, 3, 0) * 0.2) * (unit / (short * 0.05));
    // Each wash one paint or the other, with a little of the second run
    // into it -- as colours bleed on wet paper. Mixed half and half they
    // are mud.
    var pick = hash(seed, 4, 0);
    var colour = pick < 0.55
        ? Color.lerp(spec.foreground, spec.accent, pick * 0.25)!
        : Color.lerp(spec.accent, spec.foreground, (1 - pick) * 0.25)!;
    for (var layer = 0; layer < 4; layer++) {
      const around = 56;
      var pts = [
        for (var i = 0; i < around; i++)
          (() {
            var a = i / around * math.pi * 2;
            var n = noise.fbm(math.cos(a) * 1.8 + k * 7 + layer * 0.9,
                math.sin(a) * 1.8 + layer * 1.7,
                octaves: 5);
            var fine = (hash(seed + layer, i, 9) - 0.5) * 0.06;
            var reach = r * (0.3 + (n + fine) * 1.4 * (0.5 + spec.variation));
            return c +
                Offset(layer * r * 0.09, -layer * r * 0.06) +
                Offset(math.cos(a), math.sin(a)) * reach;
          })(),
      ];
      var path = _smoothClosed(pts);
      var a = spec.intensity * 0.14;
      var tint = colour;
      canvas.drawPath(path, Paint()..color = _fade(tint, a));
      // The edge, where the pigment collected as it dried.
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, r * 0.018)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.01)
            ..color = _fade(tint, a * 2.2));
      // And the grain of the pigment settling into the paper.
      if (layer == 0) {
        canvas.save();
        canvas.clipPath(path);
        var box = path.getBounds();
        var specks =
            (box.width * box.height / (r * r) * 260).round().clamp(50, 9000);
        var dots = Float32List(specks * 2);
        for (var i = 0; i < specks; i++) {
          dots[i * 2] = box.left + hash(seed, i, 21) * box.width;
          dots[i * 2 + 1] = box.top + hash(seed, i, 22) * box.height;
        }
        canvas.drawRawPoints(
            ui.PointMode.points,
            dots,
            Paint()
              ..strokeWidth = math.max(1.0, r * 0.008)
              ..strokeCap = StrokeCap.round
              ..color = _fade(tint, a * 1.2));
        canvas.restore();
      }
    }
  }
}

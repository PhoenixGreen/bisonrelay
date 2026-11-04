part of 'generators.dart';

// marks.dart is the extra kinds of mark the Organic and Graphic & comic
// styles can draw: terrain, soft fire and embers, non-round halftone dots,
// parallel speed lines, shaded hatching, drips, spray, splashes and
// watercolour. The styles themselves are in generators.dart and call these
// when the matching kind is chosen.

/// _terrain fills the bands between contour lines like a relief map:
/// background at the lowest, through foreground, to accent at the peaks.
void _terrain(ui.Canvas canvas, Rect rect, ProceduralSpec spec,
    List<List<double>> field, int cols, int rows, double cell, int levels) {
  // The field's own grid, so each corner samples an existing value.
  var area = Rect.fromLTWH(rect.left, rect.top, cols * cell, rows * cell);
  _colourGrid(canvas, area, cols, rows, (u, v) {
    var f = field[(v * rows).round()][(u * cols).round()];
    // Stepped, so each band is one colour.
    var band = (f * levels).floor() / levels;
    var c = band < 0.5
        ? Color.lerp(spec.background, spec.foreground, band * 2)!
        : Color.lerp(spec.foreground, spec.accent, (band - 0.5) * 2)!;
    return _argb(c, spec.intensity.clamp(0.0, 1.0) * 0.85);
  });
}

/// _screenDot is one non-round halftone dot turned to the screen: [shape] 1
/// is a square, 2 a diamond, anything else a bar the width of its cell
/// (side by side, a line screen).
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
      var w = step / 2 + 0.5, h = size * 0.8;
      corners = [turned(-w, -h), turned(w, -h), turned(w, h), turned(-w, h)];
  }
  canvas.drawPath(Path()..addPolygon(corners, true), paint);
}

/// _parallelLines is speed lines that all run one way, rather than a burst
/// out of a point.
void _parallelLines(
    ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var count = (12 + spec.density * 90).round();
  var paint = Paint();
  // Horizontal here; the pattern's own rotation turns them.
  for (var i = 0; i < count; i++) {
    var y = rect.top + hash(spec.seed + 3, i, 0) * rect.height;
    var thick = rect.height *
        (0.002 + hash(spec.seed + 5, i, 1) * 0.012 * (0.4 + spec.variation));
    var len = rect.width * (0.25 + hash(spec.seed + 7, i, 2) * 0.6);
    // Each streak at its own pace, wrapping once off the far side.
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

/// _hatchLine is one hand-drawn stroke of hatching, wavering by [wobble]
/// and, when [shaded], laid only where the tone is dark enough for [pass].
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
  // Each later pass needs a darker tone, so the third pass lands only in
  // the deepest shadow: that is how hatching makes a tone.
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

/// _drips is paint running down from the top edge: a wet band, and runs of
/// different lengths hanging from it, each ending in a drop.
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
      // Animated, each run creeps down to its full length and stays there.
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

/// _spray is airbrushed paint: clouds of fine specks, thick in the middle
/// and thinning out.
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
      // Gathered towards the middle: a power above 1 of a random number is
      // small more often than large.
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

/// _softFire is fire as light rather than shapes: tongues graded from an
/// accent core through foreground to nothing at the tips, added together
/// and blurred.
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

/// _embers is sparks rising and drifting, fading out before the top.
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

/// _smoothClosed is a closed Catmull-Rom curve through [pts], as cubics.
/// Fewer than three points gives an empty path.
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

/// _splash is paint thrown at a wall: a smooth body, spikes with drops off
/// their tips, teardrops flung further, and a fine mist.
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

    // The body: lumpy but smooth.
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

    // The mist.
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

/// _watercolour is washes on paper: each four thin layers slightly out of
/// line, darker at the edges where the pigment gathered.
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
    // Mostly one colour with at most a quarter of the other: half and half
    // is mud.
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
      // The darker edge.
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, r * 0.018)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.01)
            ..color = _fade(tint, a * 2.2));
      // Pigment grain, on the first layer only.
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

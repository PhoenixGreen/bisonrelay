part of 'generators.dart';

// light.dart is the Gradient & light family: colour that blends, waves of
// light, out-of-focus discs, and stars. (Rings are in generators.dart, and
// a plain fill is just the base.)
//
// What each style drew before it had settings of its own is its first kind,
// and the default, so that a document saved then is the same picture now.

/// _colourGrid draws a lattice of [cols] by [rows] cells over [rect], the
/// colour at each corner given by [at] as 0xAARRGGBB and blended smoothly
/// across each cell.
///
/// Colour that changes smoothly over the whole frame -- a mesh gradient, a
/// nebula -- is a few hundred corners rather than a million pixels: the
/// blending between them is done by the graphics card for nothing.
void _colourGrid(ui.Canvas canvas, Rect rect, int cols, int rows,
    int Function(double u, double v) at) {
  var colours = Int32List((cols + 1) * (rows + 1));
  for (var iy = 0; iy <= rows; iy++) {
    for (var ix = 0; ix <= cols; ix++) {
      colours[iy * (cols + 1) + ix] = at(ix / cols, iy / rows);
    }
  }
  var paint = Paint()..color = const Color(0xFFFFFFFF);
  var positions = Float32List((cols + 1) * 4);
  var strip = Int32List((cols + 1) * 2);
  var stepX = rect.width / cols, stepY = rect.height / rows;
  for (var iy = 0; iy < rows; iy++) {
    var top = rect.top + iy * stepY;
    for (var ix = 0; ix <= cols; ix++) {
      var x = rect.left + ix * stepX;
      positions[ix * 4] = x;
      positions[ix * 4 + 1] = top;
      positions[ix * 4 + 2] = x;
      positions[ix * 4 + 3] = top + stepY;
      strip[ix * 2] = colours[iy * (cols + 1) + ix];
      strip[ix * 2 + 1] = colours[(iy + 1) * (cols + 1) + ix];
    }
    var vertices = ui.Vertices.raw(
        ui.VertexMode.triangleStrip, Float32List.fromList(positions),
        colors: Int32List.fromList(strip));
    canvas.drawVertices(vertices, ui.BlendMode.modulate, paint);
    vertices.dispose();
  }
}

/// _argb packs [c] at [alpha] of its own opacity.
int _argb(Color c, [double alpha = 1]) =>
    (((c.a * alpha).clamp(0.0, 1.0) * 255).round() << 24) |
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();

// --------------------------------------------------------------------------
// Gradient mesh
// --------------------------------------------------------------------------

/// _gradientMesh is colour blended across the frame: soft blooms of light,
/// a mesh gradient, or the curtains of an aurora.
void _gradientMesh(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  switch (spec.choice("meshKind")) {
    case 1:
      return _mesh(canvas, rect, spec, t);
    case 2:
      return _aurora(canvas, rect, spec, t);
    default:
      return _blooms(canvas, rect, spec, t);
  }
}

/// _blooms is a handful of soft radial blooms, blended additively.
///
/// Additive rather than alpha-blended: overlapping blooms should get brighter
/// where they meet, which is what makes it read as light rather than as
/// several coloured circles lying on top of one another.
void _blooms(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
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

/// _mesh is a mesh gradient: a few points of colour scattered over the
/// frame, every place in between a blend of the nearest of them, the whole
/// thing gently bent.
///
/// The colours are the base, the main and the accent, and the blends between
/// them -- so a palette chosen for the background is the palette of the
/// mesh.
void _mesh(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var count = spec.p("points").round().clamp(2, 9);
  // The steeper each point's pull falls off, the more the frame is patches
  // of one colour; soft is shallow, and blends the whole way across.
  var soft = 0.8 + (1 - spec.p("softness")) * 2.5;
  var warp = spec.p("warp");
  var noise = ValueNoise(spec.seed + 5);
  var palette = [
    spec.foreground,
    spec.accent,
    spec.background,
    Color.lerp(spec.foreground, spec.accent, 0.5)!,
    Color.lerp(spec.background, spec.foreground, 0.5)!,
    Color.lerp(spec.background, spec.accent, 0.4)!,
  ];
  var aspect = rect.width / rect.height;
  var points = <(double, double, Color)>[];
  for (var i = 0; i < count; i++) {
    var x = hash(spec.seed, i, 1), y = hash(spec.seed, i, 2);
    var speed = 0.15 + hash(spec.seed, i, 3) * 0.2;
    x += math.sin(t * speed + i * 1.7) * 0.12 * spec.variation;
    y += math.cos(t * speed * 0.8 + i * 2.3) * 0.12 * spec.variation;
    points.add((x * aspect, y, palette[i % palette.length]));
  }
  var cols = (24 + rect.width / 24).round().clamp(16, 96);
  var rows = (cols / aspect).round().clamp(9, 96);
  var a = spec.intensity.clamp(0.0, 1.0);
  _colourGrid(canvas, rect, cols, rows, (u, v) {
    // Bent by a slow field before the nearest points are found, which is
    // what turns circles of colour into folds of it.
    var bx = u * aspect, by = v;
    if (warp > 0) {
      bx += (noise.fbm(u * 2 + t * 0.05, v * 2, octaves: 2) - 0.5) * warp * 0.8;
      by += (noise.fbm(u * 2 + 9, v * 2 + t * 0.05, octaves: 2) - 0.5) *
          warp *
          0.8;
    }
    double r = 0, g = 0, b = 0, sum = 0;
    for (var (px, py, c) in points) {
      var d2 = (bx - px) * (bx - px) + (by - py) * (by - py);
      var w = 1 / math.pow(d2 + 0.002, soft);
      r += c.r * w;
      g += c.g * w;
      b += c.b * w;
      sum += w;
    }
    return _argb(
        Color.from(alpha: 1, red: r / sum, green: g / sum, blue: b / sum), a);
  });
}

/// _aurora is curtains of light hanging in the sky: bright along a wavering
/// lower edge and fading upwards, folding as they go.
void _aurora(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed + 11);
  var curtains = 2 + (spec.density * 4).round();
  var steps = (rect.width / 6).round().clamp(24, 320);
  canvas.saveLayer(rect, Paint());
  for (var k = 0; k < curtains; k++) {
    var base = rect.top + rect.height * (0.45 + hash(spec.seed, k, 1) * 0.35);
    var tall = rect.height * (0.25 + hash(spec.seed, k, 2) * 0.45);
    var colour = k.isEven ? spec.foreground : spec.accent;
    var tip =
        Color.lerp(colour, k.isEven ? spec.accent : spec.foreground, 0.6)!;
    var wave = rect.height * 0.12 * (0.4 + spec.variation);
    var positions = <double>[];
    var colours = <int>[];
    // And a short fade below the bright edge, which a real curtain has: the
    // glow does not stop at a line.
    var below = <double>[];
    var belowColours = <int>[];
    for (var i = 0; i <= steps; i++) {
      var u = i / steps;
      var x = rect.left + rect.width * u;
      var n =
          noise.fbm(u * 3 + k * 7 + t * 0.06, k * 3.1 + t * 0.04, octaves: 3);
      var y = base + (n - 0.5) * wave * 2;
      // Brighter in folds, as a curtain is where it turns towards the eye.
      var fold = noise.fbm(u * 9 + k * 13 - t * 0.12, k + 0.5, octaves: 2);
      var a = spec.intensity * (0.25 + fold * 0.75);
      positions
        ..add(x)
        ..add(y)
        ..add(x)
        ..add(y - tall * (0.6 + fold * 0.6));
      colours
        ..add(_argb(colour, a * 0.85))
        ..add(_argb(tip, 0));
      below
        ..add(x)
        ..add(y)
        ..add(x)
        ..add(y + tall * 0.08);
      belowColours
        ..add(_argb(colour, a * 0.85))
        ..add(_argb(colour, 0));
    }
    for (var (pos, col) in [(below, belowColours)]) {
      var v = ui.Vertices.raw(
          ui.VertexMode.triangleStrip, Float32List.fromList(pos),
          colors: Int32List.fromList(col));
      canvas.drawVertices(
          v,
          ui.BlendMode.modulate,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..blendMode = BlendMode.plus);
      v.dispose();
    }
    var vertices = ui.Vertices.raw(
        ui.VertexMode.triangleStrip, Float32List.fromList(positions),
        colors: Int32List.fromList(colours));
    canvas.drawVertices(
        vertices,
        ui.BlendMode.modulate,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..blendMode = BlendMode.plus);
    vertices.dispose();
  }
  canvas.restore();
}

// --------------------------------------------------------------------------
// Flow waves
// --------------------------------------------------------------------------

/// _flowWaves is waves of light across the frame: strands bunched into
/// ribbons, wide translucent ribbons of silk, or many fine lines flowing
/// together.
void _flowWaves(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  switch (spec.choice("waveKind")) {
    case 1:
      return _silk(canvas, rect, spec, t);
    case 2:
      return _waveLines(canvas, rect, spec, t);
    default:
      return _strands(canvas, rect, spec, t);
  }
}

/// _strands traces ribbons through a flow field, glowing where they bunch.
///
/// They are drawn in bands of neighbouring start points so that a band
/// stays together as it flows, which is what makes the ribbons read as
/// ribbons rather than as unrelated strands.
void _strands(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
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
    // layer holding all of them, and the filament goes over the top. One
    // blur for the band rather than one for each strand.
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
        // than curling up in one corner.
        var dir = Offset(math.cos(a) * 0.45 + 0.9, math.sin(a) * 0.85);
        p = p + dir * stepLen;
        path.lineTo(p.dx, p.dy);
        if (p.dx > rect.right + stepLen * 4) break;
      }

      strands.add(path);
    }

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

/// _waveY is the height of wave [k] of [count] at [u] across the frame, as
/// a fraction of its height: a sum of slow sines, shifted a little for each
/// wave so that neighbours run together and drift apart.
double _waveY(ProceduralSpec spec, int k, int count, double u, double t,
    ValueNoise noise) {
  var amp = spec.p("amplitude");
  var twist = spec.p("twist");
  var f = k / math.max(1, count - 1);
  var phase = f * twist * math.pi * 2;
  var y = 0.5 +
      (f - 0.5) * spec.p("spread") +
      amp * 0.18 * math.sin(u * math.pi * 2 * 0.9 + phase + t * 0.25) +
      amp * 0.10 * math.sin(u * math.pi * 2 * 1.7 - phase * 0.6 - t * 0.18) +
      amp *
          0.12 *
          (noise.fbm(u * 2.5 + t * 0.05, f * 1.5, octaves: 2) - 0.5) *
          (0.5 + spec.variation);
  return y;
}

/// _silk is wide translucent ribbons laid over one another, each brighter
/// along its edges, the way light catches folds of cloth.
void _silk(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var count = spec.p("waves").round().clamp(1, 40);
  var thick = spec.p("thickness");
  var steps = (rect.width / 8).round().clamp(32, 260);
  canvas.saveLayer(rect, Paint());
  for (var k = 0; k < count; k++) {
    var f = k / math.max(1, count - 1);
    var colour = Color.lerp(spec.foreground, spec.accent, f)!;
    var width = rect.height *
        (0.04 + thick * 0.22) *
        (0.6 + hash(spec.seed, k, 3) * 0.8);
    var top = <Offset>[], bottom = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      var u = i / steps;
      var x = rect.left + rect.width * u;
      var y = rect.top + rect.height * _waveY(spec, k, count, u, t, noise);
      // Narrower and wider along its length, as a ribbon turns.
      var w =
          width * (0.35 + 0.65 * (0.5 + 0.5 * math.sin(u * 5 + k + t * 0.3)));
      top.add(Offset(x, y - w / 2));
      bottom.add(Offset(x, y + w / 2));
    }
    var body = Path()..addPolygon([...top, ...bottom.reversed], true);
    var box = body.getBounds();
    canvas.drawPath(
        body,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(box.topCenter, box.bottomCenter, [
            _fade(colour, spec.intensity * 0.35),
            _fade(colour, spec.intensity * 0.06),
            _fade(colour, spec.intensity * 0.30),
          ], [
            0,
            0.5,
            1
          ]));
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, rect.height * 0.003)
      ..blendMode = BlendMode.plus
      ..color = _fade(colour, spec.intensity * 0.6);
    canvas.drawPath(Path()..addPolygon(top, false), edge);
    canvas.drawPath(Path()..addPolygon(bottom, false),
        edge..color = _fade(colour, spec.intensity * 0.3));
  }
  canvas.restore();
}

/// _waveLines is many fine lines flowing across the frame together, each a
/// little out of step with the one before it.
void _waveLines(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var noise = ValueNoise(spec.seed);
  var count = spec.p("waves").round().clamp(1, 40) * 3;
  var steps = (rect.width / 6).round().clamp(32, 320);
  var weight =
      math.max(0.6, rect.height * 0.002 * (0.5 + spec.p("thickness") * 3));
  for (var k = 0; k < count; k++) {
    var f = k / math.max(1, count - 1);
    var colour = Color.lerp(spec.foreground, spec.accent, f)!;
    var pts = <Offset>[
      for (var i = 0; i <= steps; i++)
        Offset(
            rect.left + rect.width * i / steps,
            rect.top +
                rect.height * _waveY(spec, k, count, i / steps, t, noise)),
    ];
    // Brightest in the middle of the set, fading at its two edges.
    var edge = math.sin(f * math.pi);
    canvas.drawPath(
        Path()..addPolygon(pts, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = weight
          ..color = _fade(colour, spec.intensity * (0.25 + 0.75 * edge)));
  }
}

// --------------------------------------------------------------------------
// Bokeh
// --------------------------------------------------------------------------

/// _aperture is the outline of a disc of out-of-focus light: round, or the
/// shape of a lens's blades.
Path _aperture(Offset c, double r, int sides, double turn) {
  if (sides < 3) return Path()..addOval(Rect.fromCircle(center: c, radius: r));
  return Path()
    ..addPolygon([
      for (var k = 0; k < sides; k++)
        c +
            Offset(math.cos(turn + k * 2 * math.pi / sides),
                    math.sin(turn + k * 2 * math.pi / sides)) *
                r,
    ], true);
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
  var sides = const [0, 6, 8][spec.choice("aperture").clamp(0, 2)];
  var rim = spec.p("rim");
  var depth = spec.on("depth");

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

    // Near and far: the big ones further out of focus and dimmer, the small
    // ones sharper and brighter, which is what puts space between them.
    var far = depth && sizeF > 0.9;
    if (depth && !far) alpha *= 1.5;
    if (far) alpha *= 0.6;

    var paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(c, r, [
        _fade(color, alpha * (0.75 - rim * 0.4)),
        _fade(color, alpha * 0.75),
        _fade(color, 0),
      ], [
        0.0,
        0.82,
        1.0
      ]);
    if (far) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25);
    if (sides == 0) {
      canvas.drawCircle(c, r, paint);
    } else {
      canvas.drawPath(_aperture(c, r, sides, 0.3), paint);
    }
  }
  canvas.restore();
}

// --------------------------------------------------------------------------
// Starfield
// --------------------------------------------------------------------------

/// _starfield is scattered points of light, densest and brightest in the
/// middle so the frame has somewhere to look -- with clouds of nebula behind
/// them, stars streaking past at warp speed, and the odd shooting star.
void _starfield(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var nebula = spec.p("nebula");
  if (nebula > 0) _nebula(canvas, rect, spec, t, nebula);
  if (spec.on("warp")) return _warp(canvas, rect, spec, t);

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
    if (mag > 1 - spec.p("spikes")) {
      var arm = r * 6;
      var paint = Paint()
        ..strokeWidth = r * 0.5
        ..color = _fade(spec.accent, alpha * 0.5);
      canvas.drawLine(p.translate(-arm, 0), p.translate(arm, 0), paint);
      canvas.drawLine(p.translate(0, -arm), p.translate(0, arm), paint);
    }
  }

  // Shooting stars: each crosses the frame in a moment and is gone, at its
  // own time in a cycle of a few seconds.
  var shooting = spec.p("shooting");
  if (shooting > 0 && spec.animated) {
    var many = (shooting * 6).ceil();
    for (var k = 0; k < many; k++) {
      var cycle = 3 + hash(spec.seed + 7, k, 0) * 5;
      var at = (t + hash(spec.seed + 7, k, 1) * cycle) / cycle;
      var round = at.floor();
      var f = (at - round) * cycle / 0.9;
      if (f > 1) continue;
      var from = Offset(rect.left + rect.width * hash(spec.seed + 8, k, round),
          rect.top + rect.height * hash(spec.seed + 9, k, round) * 0.6);
      var a = math.pi * (0.15 + hash(spec.seed + 10, k, round) * 0.25);
      var dir = Offset(math.cos(a), math.sin(a));
      var len = math.max(rect.width, rect.height) * 0.25;
      var head = from + dir * len * f * 1.6;
      var tail = head - dir * len * 0.5 * math.sin(f * math.pi);
      canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = math.max(1.0, unit * 0.06)
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(tail, head, [
              _fade(spec.accent, 0),
              _fade(spec.accent, spec.intensity),
            ]));
    }
  }
}

/// _nebula is clouds of coloured gas behind the stars: a slow field in the
/// main colour, shot through with the accent where it is thickest.
void _nebula(
    ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t, double amount) {
  var noise = ValueNoise(spec.seed + 31);
  var aspect = rect.width / rect.height;
  var cols = (rect.width / 10).round().clamp(24, 160);
  var rows = (cols / aspect).round().clamp(12, 120);
  canvas.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
  _colourGrid(canvas, rect, cols, rows, (u, v) {
    var x = u * aspect * 2.2, y = v * 2.2;
    var f = noise.fbm(x + t * 0.02, y, octaves: 5);
    var g = noise.fbm(x * 1.7 + 5, y * 1.7 - t * 0.015, octaves: 4);
    var thick = ((f - 0.42) * 2.6).clamp(0.0, 1.0);
    var c = Color.lerp(
        spec.foreground, spec.accent, ((g - 0.35) * 2.2).clamp(0.0, 1.0))!;
    return _argb(c, thick * thick * amount * spec.intensity);
  });
  canvas.restore();
}

/// _warp is stars streaming out of the middle of the frame, as if it were
/// flying through them: each a streak that lengthens as it nears the edge.
void _warp(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var count = 60 + (spec.density * 500).round();
  var reach =
      math.sqrt(rect.width * rect.width + rect.height * rect.height) / 2;
  var unit = _unit(rect, spec);
  var speed = spec.animated ? 0.35 : 0.0;
  for (var i = 0; i < count; i++) {
    var a = hash(spec.seed, i, 1) * math.pi * 2;
    var dir = Offset(math.cos(a), math.sin(a));
    // How far out it is, going round: each star comes back into the middle
    // once it has left the frame.
    var z = hash(spec.seed, i, 2) + t * speed * (0.6 + hash(spec.seed, i, 3));
    z -= z.floorToDouble();
    var d = reach * z * z;
    var len = reach * 0.05 * (0.2 + z * 3) * (0.5 + spec.variation);
    var head = rect.center + dir * d;
    var tail = rect.center + dir * math.max(0, d - len);
    var colour = hash(spec.seed, i, 4) < 0.15 ? spec.accent : spec.foreground;
    canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = math.max(0.6, unit * 0.06 * (0.3 + z))
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [
            _fade(colour, 0),
            _fade(colour, spec.intensity * (0.2 + z * 0.8)),
          ]));
  }
}

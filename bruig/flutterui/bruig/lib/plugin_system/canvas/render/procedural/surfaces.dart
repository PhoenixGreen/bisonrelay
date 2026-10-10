part of 'generators.dart';

// surfaces.dart is the Surface style: paper, concrete, wood, marble, carbon
// fibre, fabric and leather.
//
// Built the way the metal is -- see _metal -- rather than drawn: each kind is
// a height and a colour at every point of a lattice, and a light shone
// across the heights does the rest. That is what makes a weave look woven and
// wood look like it has a grain rather than stripes: the light finds the
// slopes. And like the metal, every relief is asked for as the slope it
// should reach rather than as a depth, since fine detail given a depth comes
// out as corrugated iron.

/// SurfaceKind is [ProceduralStyle.surface]'s "surfaceKind" setting.
abstract final class SurfaceKind {
  static const paper = 0;
  static const concrete = 1;
  static const wood = 2;
  static const marble = 3;
  static const carbon = 4;
  static const fabric = 5;
  static const leather = 6;
}

/// _smooth is the smooth step from nought at [a] to one at [b].
double _smooth(double a, double b, double x) {
  var t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// _worley2 is cellular noise with the second-nearest point as well: the
/// difference between the two is nought along the walls between cells, which
/// is where a crease in leather runs.
(double, double, double) _worley2(int seed, double x, double y) {
  var cx = x.floor(), cy = y.floor();
  var f1 = 8.0, f2 = 8.0, id = 0.0;
  for (var oy = -1; oy <= 1; oy++) {
    for (var ox = -1; ox <= 1; ox++) {
      var gx = cx + ox, gy = cy + oy;
      var dx = x - (gx + hash(seed, gx, gy));
      var dy = y - (gy + hash(seed + 9277, gx, gy));
      var d = math.sqrt(dx * dx + dy * dy);
      if (d < f1) {
        f2 = f1;
        f1 = d;
        id = hash(seed + 5501, gx, gy);
      } else if (d < f2) {
        f2 = d;
      }
    }
  }
  return (f1, f2, id);
}

/// _surface draws one of the surfaces.
void _surface(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var short = math.min(rect.width, rect.height);
  if (short <= 0) return;
  // A point a pixel, capped, as the metal's lattice is: the lattice is a
  // ceiling on how fine anything can be.
  var cols = rect.width.round().clamp(8, 448);
  var rows = rect.height.round().clamp(8, 448);
  var stepX = rect.width / cols, stepY = rect.height / rows;
  var size = math.max(0.08, spec.scale / 0.05);
  var ceiling = math.min(cols, rows) / 2.2;
  double carried(double f) => math.min(f, ceiling);
  double depthFor(double slope, double f) => slope / math.max(1.0, f);

  var kind = spec.choice("surfaceKind");
  var relief = spec.p("relief");
  var polish = spec.p("polish");
  var n1 = ValueNoise(spec.seed);
  var n2 = ValueNoise(spec.seed + 4099);
  var n3 = ValueNoise(spec.seed + 7717);

  var bR = spec.background.r, bG = spec.background.g, bB = spec.background.b;
  var mR = spec.foreground.r, mG = spec.foreground.g, mB = spec.foreground.b;
  var aR = spec.accent.r, aG = spec.accent.g, aB = spec.accent.b;

  var count = (cols + 1) * (rows + 1);
  var height = Float64List(count);
  var red = Float64List(count), green = Float64List(count);
  var blue = Float64List(count);
  var gloss = Float64List(count);

  // Each point's colour as a mix of the three: how much of the main colour
  // over the base, and then how much of the accent over that.
  void paint(int at, double main, double accent) {
    main = main.clamp(0.0, 1.0);
    accent = accent.clamp(0.0, 1.0);
    var r = bR + (mR - bR) * main, g = bG + (mG - bG) * main;
    var b = bB + (mB - bB) * main;
    red[at] = r + (aR - r) * accent;
    green[at] = g + (aG - g) * accent;
    blue[at] = b + (aB - b) * accent;
  }

  for (var iy = 0; iy <= rows; iy++) {
    for (var ix = 0; ix <= cols; ix++) {
      var at = iy * (cols + 1) + ix;
      var u = ix * stepX / short, v = iy * stepY / short;
      var h = 0.0;
      double main = 0, accent = 0, shine = polish;

      switch (kind) {
        case SurfaceKind.concrete:
          // Cloudy: big soft patches of a different shade, then the grit.
          var cloud = n1.fbm(u * 1.6 / size, v * 1.6 / size, octaves: 4);
          main = (cloud - 0.35) * (0.6 + spec.variation * 0.8);
          var gf = carried(70 / size);
          h += (n2.at(u * gf, v * gf) - 0.5) * depthFor(0.5 * relief, gf);
          // Pores: small round pits, some of them, where air was trapped.
          var pf = carried(28 / size);
          var (d, which) = worley(spec.seed + 31, u * pf, v * pf);
          if (which < 0.15 + spec.density * 0.4) {
            var r = 0.12 + which * 0.25;
            var pit = (1 - math.sqrt(d) / r).clamp(0.0, 1.0);
            h -= pit * pit * depthFor(1.2 * relief, pf);
            main += pit * 0.5;
          }
          // Aggregate: specks of stone in the mix.
          var sf = carried(55 / size);
          var (sd, sid) = worley(spec.seed + 77, u * sf, v * sf);
          if (sid < 0.25 && sd < 0.04) accent = 0.35;
          if (spec.on("panels")) {
            // Formwork: the seams between the boards the concrete was poured
            // against, and the holes the ties left.
            var pw = 1.6 * size, ph = 0.8 * size;
            var px = u / pw, py = v / ph;
            var fx = px - px.floorToDouble(), fy = py - py.floorToDouble();
            var seam =
                math.min(math.min(fx, 1 - fx) * pw, math.min(fy, 1 - fy) * ph);
            var groove = (1 - seam / (0.006 * size)).clamp(0.0, 1.0);
            h -= groove * depthFor(0.6 * relief, 40);
            main += groove * 0.4;
            for (var (tx, ty) in [
              (0.15, 0.25),
              (0.85, 0.25),
              (0.15, 0.75),
              (0.85, 0.75)
            ]) {
              var dx = (fx - tx) * pw, dy = (fy - ty) * ph;
              var r = math.sqrt(dx * dx + dy * dy) / (0.025 * size);
              if (r < 1) {
                h -= (1 - r * r) * depthFor(1.5 * relief, 30);
                main += (1 - r) * 0.8;
              }
            }
          }
          shine = polish * 0.4;
        case SurfaceKind.wood:
          var x = u, y = v;
          var plank = 0;
          var seamShade = 0.0;
          if (spec.on("planks")) {
            // Boards laid along the grain, each its own piece of tree, ending
            // at its own place.
            var ph = 0.32 * size;
            plank = (y / ph).floor();
            var fy = y / ph - plank;
            var offset = hash(spec.seed + 3, plank, 0) * 4;
            var len = 2.2 * size;
            var along = (x + offset) / len;
            var end = along - along.floorToDouble();
            var butt = math.min(end, 1 - end) * len;
            var edge = math.min(fy, 1 - fy) * ph;
            var gap = math.min(edge, butt);
            seamShade = (1 - gap / (0.006 * size)).clamp(0.0, 1.0);
            x += offset * 7 + along.floorToDouble() * 3.7;
            y = fy * ph + plank * 11.3;
          }
          // Rings: lines of equal age through the trunk, bent by how the
          // tree grew, and seen cut lengthways -- long arcs along the board.
          var warp = n1.fbm(x * 0.5 / size, y * 2.2 / size, octaves: 3);
          var rings = (y * (14 + spec.variation * 30) / size) + warp * 6;
          // Knots: where a branch left the trunk, the rings bend round it.
          var kf = 1.4 / size;
          var (kd, kid) = worley(spec.seed + 51 + plank, x * kf, y * kf * 2);
          var knot = 0.0;
          if (kid < spec.density * 0.35) {
            knot = (1 - math.sqrt(kd) / 0.35).clamp(0.0, 1.0);
            rings += knot * knot * 2.5;
          }
          var ring = rings - rings.floorToDouble();
          // Latewood: the dark, dense part at the end of each year's growth.
          var late = _smooth(0.7, 0.93, ring) * (1 - _smooth(0.93, 1, ring));
          var gf = carried(110 / size);
          var streak = n2.at(x * 1.2 / size, y * gf);
          // And the fine pores running along the grain, which are most of
          // what makes a board read as wood close up.
          var pore =
              math.pow(n3.at(x * 0.9 / size, y * gf * 1.7), 3).toDouble();
          main = late * 0.55 +
              (streak - 0.5) * 0.45 +
              pore * 0.35 +
              knot * 0.6 +
              (n3.fbm(x * 0.6 / size, y * 0.6 / size, octaves: 2) - 0.5) * 0.25;
          h += (streak - 0.5) * depthFor(0.45 * relief, gf);
          h -= late * depthFor(0.12 * relief, 30 / size);
          h -= seamShade * depthFor(1.5 * relief, 40);
          main += seamShade * 0.9;
          accent = knot * 0.25;
        case SurfaceKind.marble:
          // Veins: the creases of a turbulent field, thin and sharp, running
          // diagonally through clouded stone.
          var turb = n1.fbm(u * 1.8 / size, v * 1.8 / size, octaves: 5);
          // Mostly the diagonal, bent by the turbulence rather than made of
          // it: bent too far, the veins follow the field's own contours and
          // the stone reads as a map.
          var x = (u * 0.8 + v * 0.6) * (1.2 + spec.density * 2.5) / size +
              (turb - 0.5) * (1.2 + spec.variation * 2.4) +
              (n2.fbm(u * 6 / size, v * 6 / size, octaves: 3) - 0.5) * 0.35;
          // Sharper in some places than others, and with a soft haze round
          // it, as a vein that has bled into the stone has: one width all
          // along reads as a line drawn on it.
          var near = 1 - (math.sin(x * math.pi)).abs();
          var sharp = 5 + n3.at(u * 2.2 / size, v * 2.2 / size) * 28;
          var vein = math.pow(near, sharp).toDouble() * 0.85 +
              math.pow(near, 2.2).toDouble() * 0.12;
          // Fainter veins crossing the main ones at another angle, and a
          // few of the accent -- gold, in a Calacatta -- that come and go
          // along their length. Veins rather than the creases of a field:
          // creases of value noise line up with its lattice and come out as
          // little crosses.
          var y2 = (v * 0.9 - u * 0.45) * (2.2 + spec.density * 3) / size +
              (turb - 0.5) * 2.2;
          var fine = math.pow(1 - math.sin(y2 * math.pi).abs(), 30).toDouble() *
              (0.3 + n2.at(u * 1.5 / size, v * 1.5 / size) * 0.7);
          main = vein + (turb - 0.5) * 0.35 + fine * 0.3;
          var y3 = (u * 0.35 + v * 0.95) * 1.4 / size + (turb - 0.5) * 3;
          var gold = math.pow(1 - math.sin(y3 * math.pi).abs(), 40).toDouble() *
              _smooth(0.45, 0.7, n3.at(u * 1.2 / size + 4, v * 1.2 / size));
          accent = gold * 0.9;
          h += (turb - 0.5) * depthFor(0.05 * relief, 3);
        case SurfaceKind.carbon:
          // A two-by-two twill: each tow passes over two and under two, the
          // next one along a step later, which is what draws the diagonal.
          var c = 0.06 * size;
          var i = (u / c).floor(), j = (v / c).floor();
          var fx = u / c - i, fy = v / c - j;
          var across = ((i - j) % 4 + 4) % 4 < 2;
          // A tow is rounded across its width, and made of fibres along it.
          var w = across ? fy : fx;
          var l = across ? u : v;
          var profile = math.sin(w * math.pi);
          var fibre =
              n2.at(l * carried(220 / size), (across ? j : i) * 3.1 + w * 6);
          h += profile * depthFor(1.2 * relief, 1 / c) +
              (fibre - 0.5) * depthFor(0.3 * relief, 220 / size);
          // The tows running across catch the light and the ones running
          // down do not, which is the whole of carbon fibre's look: a
          // checker of light and dark that steps diagonally.
          main = (across ? 0.55 : 0.12) + profile * 0.2 + (fibre - 0.5) * 0.15;
        case SurfaceKind.fabric:
          // Threads: up and down in the main colour, across in the accent,
          // each passing over and under the other in turn -- or, as twill,
          // over three and under one, which is denim.
          var p = 0.022 * size;
          var i = (u / p).floor(), j = (v / p).floor();
          var fx = u / p - i, fy = v / p - j;
          var twill = spec.choice("weave") == 1;
          var warpUp = twill ? ((i + j) % 4 + 4) % 4 != 0 : (i + j).isEven;
          var w = warpUp ? fx : fy;
          var along = warpUp ? fy : fx;
          var profile = math.sin(w * math.pi);
          var hump = 0.55 + 0.45 * math.sin(along * math.pi);
          var fuzz = n2.at(u * carried(160 / size), v * carried(160 / size));
          h += profile * hump * depthFor(1.1 * relief, 1 / p) +
              (fuzz - 0.5) * depthFor(0.2 * relief, 160 / size);
          var thread = hash(spec.seed + 9, warpUp ? i : j, warpUp ? 1 : 2);
          var shade = 0.75 +
              profile * 0.25 +
              (thread - 0.5) * 0.2 * (0.4 + spec.variation);
          main = warpUp ? shade : 0;
          accent = warpUp ? 0 : shade;
          // The gap between threads, where the base shows through.
          if (profile < 0.2) {
            main *= profile / 0.2;
            accent *= profile / 0.2;
          }
        case SurfaceKind.leather:
          // Pebbled: little domes, with creases along the walls between them,
          // and long folds across the hide.
          var pf = carried(32 / size);
          var (f1, f2, id) = _worley2(spec.seed + 11, u * pf, v * pf);
          var wall = (f2 - f1);
          var dome = _smooth(0, 0.35, wall);
          var fold = ridged(n1, u * 2 / size, v * 2 / size, octaves: 2);
          var crease = _smooth(0.9, 0.99, fold) * (0.2 + spec.density * 0.5);
          h += dome * depthFor(0.9 * relief, pf) -
              crease * depthFor(0.8 * relief, 8);
          main = (1 - dome) * 0.5 +
              crease * 0.3 +
              (n2.fbm(u * 1.2 / size, v * 1.2 / size, octaves: 3) - 0.5) *
                  0.4 *
                  spec.variation +
              (id - 0.5) * 0.08;
        default:
          // Paper: fibres lying every which way, the tooth of the surface,
          // and the odd fleck.
          var ff = carried(60 / size);
          var fib = n1.at(u * ff, v * ff * 0.18) + n2.at(u * ff * 0.18, v * ff);
          h += (fib - 1) * depthFor(0.35 * relief, ff);
          var tf = carried(140 / size);
          h += (n3.at(u * tf, v * tf) - 0.5) * depthFor(0.45 * relief, tf);
          main = (n1.fbm(u * 2.5 / size, v * 2.5 / size, octaves: 3) - 0.5) *
                  0.25 *
                  (0.3 + spec.variation) +
              (fib - 1) * 0.12;
          if (spec.on("laid")) {
            // Laid paper: the fine lines of the wires it was made on, and
            // the wider-spaced chain lines across them.
            var lf = 90 / size;
            h += math.sin(v * lf * math.pi * 2) * depthFor(0.25 * relief, lf);
            var chain = (u / (0.25 * size));
            var cd = (chain - chain.roundToDouble()).abs() * 0.25 * size;
            main += (1 - cd / 0.004).clamp(0.0, 1.0) * 0.15;
          }
          var kf = carried(40 / size);
          var (d, which) = worley(spec.seed + 61, u * kf, v * kf);
          if (which < spec.density * 0.12 && d < 0.02) accent = 0.7;
          shine = polish * 0.3;
      }
      height[at] = h;
      gloss[at] = shine;
      paint(at, main, accent);
    }
  }

  _shadeLattice(
      canvas, rect, spec, cols, rows, height, red, green, blue, gloss);
}

/// _shadeLattice lights a lattice of heights and colours and draws it.
///
/// Lit from up and to the left, as the metal is: a diffuse light lifted so
/// the side away from it is shaded rather than black, and a highlight as
/// tight as each point's gloss. [metal] is how much each point mirrors its
/// surroundings rather than scattering the light -- which, more than any
/// highlight, is what makes a surface read as metal: a mirror shows the room
/// it is in, tinted by its own colour.
void _shadeLattice(
    ui.Canvas canvas,
    Rect rect,
    ProceduralSpec spec,
    int cols,
    int rows,
    Float64List height,
    Float64List red,
    Float64List green,
    Float64List blue,
    Float64List gloss,
    {Float64List? metal,
    double gain = 0}) {
  var short = math.min(rect.width, rect.height);
  var stepX = rect.width / cols, stepY = rect.height / rows;
  var g0 = gain > 0 ? gain : 0.6 + spec.density * 0.2;
  var slopeX = g0 / math.max(0.0001, 2 * stepX / short);
  var slopeY = g0 / math.max(0.0001, 2 * stepY / short);
  const lx = -0.42, ly = -0.58, lz = 0.70;
  var hx = lx, hy = ly, hz = lz + 1;
  var hl = math.sqrt(hx * hx + hy * hy + hz * hz);
  hx /= hl;
  hy /= hl;
  hz /= hl;
  var bright = 0.55 + spec.intensity * 0.6;

  // The highlight's curve, worked out once for each gloss the surface uses
  // and read from a table: a fractional power at every point of the
  // lattice is the most expensive thing in it.
  const steps = 1024;
  var curves = <double, Float64List>{};
  Float64List curveFor(double g) => curves.putIfAbsent(g, () {
        var c = Float64List(steps + 1);
        for (var i = 0; i <= steps; i++) {
          c[i] = math.pow(i / steps, 6 + g * g * 120).toDouble() * g * 0.9;
        }
        return c;
      });

  _colourGrid(canvas, rect, cols, rows, (fu, fv) {
    var ix = (fu * cols).round(), iy = (fv * rows).round();
    var at = iy * (cols + 1) + ix;
    var left = height[iy * (cols + 1) + math.max(0, ix - 1)];
    var right = height[iy * (cols + 1) + math.min(cols, ix + 1)];
    var up = height[math.max(0, iy - 1) * (cols + 1) + ix];
    var down = height[math.min(rows, iy + 1) * (cols + 1) + ix];
    var nx = -(right - left) * slopeX, ny = -(down - up) * slopeY;
    var len = math.sqrt(nx * nx + ny * ny + 1);
    nx /= len;
    ny /= len;
    var nz = 1 / len;
    var diffuse = 0.45 + 0.55 * (nx * lx + ny * ly + nz * lz) / 0.70;
    var g = gloss[at];
    var hDot = (nx * hx + ny * hy + nz * hz).clamp(0.0, 1.0);
    var spec_ = g <= 0 ? 0.0 : curveFor(g)[(hDot * steps).round()];
    var m = metal == null ? 0.0 : metal[at];
    var env = 0.0;
    if (m > 0) {
      // What the surface sees, reflected: a bright sky above a dark
      // horizon, swept down the sheet and bent by every slope in it.
      var t = fv * 0.9 + fu * 0.15 + ny * 2.2 + nx * 0.6;
      env = 0.62 +
          0.38 * math.cos(t * math.pi * 1.4) -
          0.55 * math.exp(-math.pow((t - 0.52) / 0.07, 2));
    }
    double ch(double c) {
      var lit = c * diffuse * bright;
      var mirrored = c * env * bright * 1.15;
      return (lit * (1 - m) + mirrored * m + spec_).clamp(0.0, 1.0);
    }

    return 0xFF000000 |
        ((ch(red[at]) * 255).round() << 16) |
        ((ch(green[at]) * 255).round() << 8) |
        (ch(blue[at]) * 255).round();
  });
}

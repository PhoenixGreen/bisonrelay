part of 'generators.dart';

// metals.dart is the Metal texture's finishes other than the original
// brushing: fine hairline brushing, polished chrome, diamond plate,
// hammered, corrugated, perforated and riveted panels.
//
// Built like the surfaces -- a height and a colour at every point of a
// lattice, lit -- with one thing a surface does not have: they mirror what is
// round them. See _shadeLattice. Rust and damage work on every finish.

/// MetalFinish is the Metal texture's "finish" setting.
abstract final class MetalFinish {
  static const brushed = 0;
  static const fine = 1;
  static const polished = 2;
  static const diamond = 3;
  static const hammered = 4;
  static const corrugated = 5;
  static const perforated = 6;
  static const riveted = 7;
}

void _metalFinish(ui.Canvas canvas, Rect rect, ProceduralSpec spec) {
  var m = spec.metal;
  var short = math.min(rect.width, rect.height);
  if (short <= 0) return;
  var cols = rect.width.round().clamp(8, 448);
  var rows = rect.height.round().clamp(8, 448);
  var stepX = rect.width / cols, stepY = rect.height / rows;
  var size = math.max(0.08, spec.scale / 0.05);
  var ceiling = math.min(cols, rows) / 2.2;
  double carried(double f) => math.min(f, ceiling);
  double depthFor(double slope, double f) => slope / math.max(1.0, f);

  var finish = spec.choice("finish");
  var n1 = ValueNoise(spec.seed);
  var n2 = ValueNoise(spec.seed + 4099);
  var patch = ValueNoise(spec.seed + 1229);
  var crust = ValueNoise(spec.seed + 7717);

  var bR = spec.background.r, bG = spec.background.g, bB = spec.background.b;
  var sR = spec.foreground.r, sG = spec.foreground.g, sB = spec.foreground.b;
  var rR = spec.accent.r, rG = spec.accent.g, rB = spec.accent.b;

  var count = (cols + 1) * (rows + 1);
  var height = Float64List(count);
  var red = Float64List(count), green = Float64List(count);
  var blue = Float64List(count);
  var gloss = Float64List(count);
  var mirror = Float64List(count);

  // How mirror-like the bare metal is: a brushed sheet scatters most of what
  // it reflects, chrome hardly any.
  var shine = m.shine;
  var bare = switch (finish) {
    MetalFinish.polished => 0.85 + shine * 0.15,
    MetalFinish.fine => 0.2 + shine * 0.35,
    _ => 0.3 + shine * 0.5,
  };
  var rustLevel = 0.72 - m.rust * 0.38;

  for (var iy = 0; iy <= rows; iy++) {
    for (var ix = 0; ix <= cols; ix++) {
      var at = iy * (cols + 1) + ix;
      var u = ix * stepX / short, v = iy * stepY / short;
      var h = 0.0;
      // How much of the sheen colour over the metal, and how dark: a hole
      // or a seam is nought.
      var sheen = 0.0, dark = 1.0, mir = bare;

      switch (finish) {
        case MetalFinish.polished:
          // Very nearly flat: what little unevenness there is shows only in
          // the reflection, which it bends.
          h += (n1.fbm(u * 0.8 / size, v * 0.8 / size, octaves: 2) - 0.5) *
              depthFor(0.04, 2);
        case MetalFinish.diamond:
          // Tread plate: raised lens-shaped bars, alternately turned one way
          // and the other, on a lightly brushed sheet.
          var c = 0.14 * size;
          var i = (u / c).floor(), j = (v / c).floor();
          var fx = u / c - i - 0.5, fy = v / c - j - 0.5;
          var turn = (i + j).isEven ? 1.0 : -1.0;
          var a = (fx + turn * fy) * 0.7071, b = (fx - turn * fy) * 0.7071;
          var lens = 1 - (a * a) / 0.16 - (b * b) / 0.0081;
          var bump = lens > 0 ? math.sqrt(lens) : 0.0;
          h += bump * depthFor(1.6, 1 / c);
          var bf = carried(160 / size);
          h += (n1.at(u * bf * 0.05, v * bf) - 0.5) * depthFor(0.05, bf);
          sheen = bump * 0.25;
        case MetalFinish.hammered:
          // Dimpled all over by a hammer: overlapping shallow dishes, no two
          // the same.
          var f = carried(18 / size);
          // Every point is in one dish or another: the depth is the
          // distance to the middle of whichever blow landed nearest.
          var (d, id) = worley(spec.seed + 13, u * f, v * f);
          h += math.sqrt(d) * (0.8 + id * 0.4) * depthFor(1.6, f);
        case MetalFinish.corrugated:
          // Corrugated sheet: one smooth wave after another.
          var f = 7 / size;
          h += math.sin(v * f * math.pi * 2) * depthFor(2.2, f);
          var bf = carried(140 / size);
          h += (n1.at(u * bf * 0.06, v * bf) - 0.5) * depthFor(0.1, bf);
        case MetalFinish.perforated:
          // Perforated: round holes on a staggered grid, each with a lip.
          var c = 0.06 * size;
          var j = (v / c).floor();
          var shift = j.isOdd ? 0.5 : 0.0;
          var fx = u / c + shift, fy = v / c;
          var dx = fx - fx.floorToDouble() - 0.5,
              dy = fy - fy.floorToDouble() - 0.5;
          var r = math.sqrt(dx * dx + dy * dy);
          if (r < 0.28) {
            dark = 0.08;
            mir = 0;
          } else if (r < 0.34) {
            h -= (0.34 - r) / 0.06 * depthFor(0.8, 1 / c);
          }
          var bf = carried(160 / size);
          h += (n1.at(u * bf * 0.05, v * bf) - 0.5) * depthFor(0.1, bf);
        case MetalFinish.riveted:
          // Panels: seams between plates, and a row of rivets along each.
          var pw = 0.55 * size, ph = 0.38 * size;
          var px = u / pw, py = v / ph;
          var fx = px - px.floorToDouble(), fy = py - py.floorToDouble();
          var ex = math.min(fx, 1 - fx) * pw, ey = math.min(fy, 1 - fy) * ph;
          var seam = math.min(ex, ey);
          if (seam < 0.0025 * size) {
            dark = 0.45;
            h -= depthFor(0.6, 60);
          }
          // Rivets a little in from each seam.
          var pitch = 0.05 * size, inset = 0.022 * size;
          double rivet(double along, double off) {
            var k = along / pitch;
            var d = math.sqrt(math.pow((k - k.roundToDouble()) * pitch, 2) +
                math.pow(off - inset, 2));
            var r = 0.0085 * size;
            return d < r ? math.sqrt(1 - (d / r) * (d / r)) : 0.0;
          }
          var dome = math.max(math.max(rivet(u, ey), rivet(u, ph - ey)),
              math.max(rivet(v, ex), rivet(v, pw - ex)));
          h += dome * depthFor(1.2, 1 / (0.0085 * size));
          var plate = hash(spec.seed, px.floor(), py.floor());
          sheen = (plate - 0.5) * 0.25 + dome * 0.2;
          var bf = carried(150 / size);
          h += (n1.at(u * bf * 0.05, v * bf) - 0.5) *
              depthFor(0.15, bf) *
              (0.5 + plate);
        default:
          // Fine brushing: hairlines as fine as the lattice can carry, long
          // along the sheet and hardly any across it, under a broad, soft
          // sheen that follows the grain.
          var across = carried(ceiling * (0.6 + m.roughness * 0.4));
          var along = across / (40 + spec.variation * 120);
          h += (n1.at(u * along, v * across) - 0.5) * depthFor(0.14, across);
          h += (n2.at(u * along * 2.3, v * across * 0.55) - 0.5) *
              depthFor(0.07, across * 0.55);
          sheen =
              (n2.fbm(u * 0.6 / size, v * 3 / size, octaves: 2) - 0.5) * 0.4;
      }

      // Knocks: a few scratches across the grain, wherever there is grain.
      // Long, thin and at a slant, and only the sharpest few: a sheet is
      // scratched in a handful of places, not hatched all over.
      if (m.damage > 0.2) {
        var a = (u + v) * 0.7071, b = (v - u) * 0.7071;
        var creased = ridged(n2, a * 0.6 / size, b * 90 / size, octaves: 1);
        var cut =
            ((creased - (0.995 - m.damage * 0.04)) / 0.006).clamp(0.0, 1.0);
        h -= cut * depthFor(0.4 + m.damage, 90 / size);
      }
      // Rust: creeping in from a threshold on a smooth field, rough and
      // matt where it has taken hold.
      var rust = 0.0;
      if (m.rust > 0) {
        var n = patch.fbm(u * 4.2, v * 4.2, octaves: 3);
        if (n > rustLevel) {
          rust = ((n - rustLevel) / math.max(0.0001, 0.85 - rustLevel))
              .clamp(0.0, 1.0);
          var cf = carried(90 / size);
          h += (crust.fbm(u * cf, v * cf, octaves: 2) - 0.4) *
              depthFor(0.9, cf) *
              rust;
        }
      }

      var s = sheen.clamp(-1.0, 1.0);
      double mixC(double b, double sh, double r) {
        var c = s >= 0 ? b + (sh - b) * s : b * (1 + s);
        return (c + (r - c) * rust) * dark;
      }

      red[at] = mixC(bR, sR, rR);
      green[at] = mixC(bG, sG, rG);
      blue[at] = mixC(bB, sB, rB);
      gloss[at] = (shine * (1 - rust)).clamp(0.0, 1.0);
      mirror[at] = mir * (1 - rust) * (dark < 0.5 ? 0 : 1);
      height[at] = h;
    }
  }
  _shadeLattice(canvas, rect, spec, cols, rows, height, red, green, blue, gloss,
      metal: mirror, gain: 0.35 + spec.density * 1.1);
}

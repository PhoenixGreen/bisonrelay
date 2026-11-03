import 'dart:math' as math;
import 'dart:typed_data';

// vrm_colour.dart changes a material's picture for how a new 3D character
// is drawn: in grey, to be coloured by the material (hair, skin and eyes in
// a colour picked for them), and in fewer, flatter tones (a look's flat
// fill). Plain Dart over RGBA bytes, so it runs off the main isolate.

double _lum(int r, int g, int b) => 0.299 * r + 0.587 * g + 0.114 * b;

/// greyPixels is [rgba] in grey, its average lightness brought to 215, so a
/// colour laid over it comes out as itself with the picture's shading.
/// Its transparency is kept.
Uint8List greyPixels(Uint8List rgba) {
  var sum = 0.0, n = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] > 128) {
      sum += _lum(rgba[i], rgba[i + 1], rgba[i + 2]);
      n++;
    }
  }
  final avg = math.max(8.0, sum / math.max(1, n));
  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < out.length; i += 4) {
    final l = _lum(out[i], out[i + 1], out[i + 2]);
    final v = math.min(255.0, 215 * math.pow(l / avg, 0.75)).round();
    out[i] = out[i + 1] = out[i + 2] = v;
  }
  return out;
}

/// flatPixels is [rgba] in flat tones: each pixel's lightness snapped toward
/// the nearest of [steps] tones, but never far from its own, so pale skin
/// stays pale rather than dropping a whole step. Its details are kept.
Uint8List flatPixels(Uint8List rgba, int steps) {
  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < out.length; i += 4) {
    final r = out[i] / 255, g = out[i + 1] / 255, b = out[i + 2] / 255;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final l = (mx + mn) / 2;
    var h = 0.0, s = 0.0;
    if (mx != mn) {
      final d = mx - mn;
      s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
      h = mx == r
          ? (g - b) / d + (g < b ? 6 : 0)
          : mx == g
              ? (b - r) / d + 2
              : (r - g) / d + 4;
      h /= 6;
    }
    final q = (l * steps).round() / steps;
    final l2 = (l + (q - l).clamp(-0.06, 0.06)).clamp(0.05, 0.97);
    final (r2, g2, b2) = _hsl(h, math.min(1.0, s * 1.08), l2);
    out[i] = (r2 * 255).round();
    out[i + 1] = (g2 * 255).round();
    out[i + 2] = (b2 * 255).round();
  }
  return out;
}

(double, double, double) _hsl(double h, double s, double l) {
  if (s == 0) return (l, l, l);
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  double hue(double t) {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  }

  return (hue(h + 1 / 3), hue(h), hue(h - 1 / 3));
}

/// averageColour is the colour [rgba] is mostly, 0xRRGGBB, from its solid
/// pixels: for strands of hair from another model to take this one's
/// colour.
int averageColour(Uint8List rgba) {
  var r = 0, g = 0, b = 0, n = 0;
  final step = math.max(1, rgba.length ~/ 4 ~/ 4096) * 4;
  for (var i = 0; i < rgba.length; i += step) {
    if (rgba[i + 3] > 128) {
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      n++;
    }
  }
  if (n == 0) return 0xffffff;
  return ((r ~/ n) << 16) | ((g ~/ n) << 8) | (b ~/ n);
}

/// mixColour is [a] [t] of the way to [b], both 0xRRGGBB.
int mixColour(int a, int b, double t) {
  int c(int shift) {
    final x = (a >> shift) & 0xff, y = (b >> shift) & 0xff;
    return (x + (y - x) * t).round().clamp(0, 255);
  }

  return (c(16) << 16) | (c(8) << 8) | c(0);
}

/// linearOf is 0xRRGGBB as the linear colour a material is coloured with.
(double, double, double) linearOf(int c) {
  double l(int shift) => math.pow(((c >> shift) & 0xff) / 255, 2.2).toDouble();
  return (l(16), l(8), l(0));
}

/// timesColour is [c], 0xRRGGBB, multiplied by the linear colour [r], [g],
/// [b] a material is coloured with: what a picture averaging [c] looks like
/// drawn in that material. VRoid draws hair in grey, coloured this way.
int timesColour(int c, double r, double g, double b) {
  int ch(int shift, double k) {
    final lin = math.pow(((c >> shift) & 0xff) / 255, 2.2) * k;
    return (255 * math.pow(lin.clamp(0.0, 1.0), 1 / 2.2)).round();
  }

  return (ch(16, r) << 16) | (ch(8, g) << 8) | ch(0, b);
}

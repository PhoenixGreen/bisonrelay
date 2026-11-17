import 'dart:math' as math;
import 'dart:typed_data';

// matting.dart is the fine work at a cut-out's edge, where a mask cannot be
// simply in or out: hair, fur, a soft shoulder. An edge pixel is a mix of
// the mean surely-subject (F) and surely-background (B) colours near it:
// where its colour sits from B to F is its alpha, and moving it towards F
// removes the background's share. Summed-area tables make any window cost
// the same. Pure Dart over plain lists, so it runs in an isolate.

/// _Sums is a summed-area table of a weight and of the weighted colour, for
/// the mean colour of whatever the weight picks in any rectangle.
class _Sums {
  final int w, h;
  final Float64List weight, r, g, b;

  _Sums(this.w, this.h)
      : weight = Float64List((w + 1) * (h + 1)),
        r = Float64List((w + 1) * (h + 1)),
        g = Float64List((w + 1) * (h + 1)),
        b = Float64List((w + 1) * (h + 1));

  /// of builds the table of [rgba] (straight colour) weighted by [pick].
  static _Sums of(Uint8List rgba, int w, int h, double Function(int) pick) {
    var s = _Sums(w, h);
    var stride = w + 1;
    for (var y = 0; y < h; y++) {
      double rowW = 0, rowR = 0, rowG = 0, rowB = 0;
      for (var x = 0; x < w; x++) {
        var i = y * w + x;
        var k = pick(i);
        rowW += k;
        rowR += k * rgba[i * 4];
        rowG += k * rgba[i * 4 + 1];
        rowB += k * rgba[i * 4 + 2];
        var at = (y + 1) * stride + x + 1;
        var above = y * stride + x + 1;
        s.weight[at] = s.weight[above] + rowW;
        s.r[at] = s.r[above] + rowR;
        s.g[at] = s.g[above] + rowG;
        s.b[at] = s.b[above] + rowB;
      }
    }
    return s;
  }

  /// mean is the picked pixels' mean colour within [radius], and their count.
  (double, double, double, double) mean(int x, int y, int radius) {
    var x0 = math.max(0, x - radius), x1 = math.min(w, x + radius + 1);
    var y0 = math.max(0, y - radius), y1 = math.min(h, y + radius + 1);
    var stride = w + 1;
    double box(Float64List t) =>
        t[y1 * stride + x1] -
        t[y0 * stride + x1] -
        t[y1 * stride + x0] +
        t[y0 * stride + x0];
    var n = box(weight);
    if (n <= 1e-6) return (0, 0, 0, 0);
    return (box(r) / n, box(g) / n, box(b) / n, n);
  }
}

/// RefineJob is an edge to refine: [rgba] the picture's straight colour,
/// [alpha] the mask, and [band] how strongly each pixel was brushed with
/// the refining brush, all [width] x [height], one byte a pixel for [alpha]
/// and [band]. [radius] is how far to look for sure subject and background.
class RefineJob {
  final Uint8List rgba;
  final Uint8List alpha;
  final Uint8List band;
  final int width, height;
  final int radius;
  const RefineJob(
      this.rgba, this.alpha, this.band, this.width, this.height, this.radius);
}

/// refineAlpha is [job]'s mask with its alpha worked out afresh along its
/// edge where the band reaches, within half the radius of where the mask
/// changes: the brush says where to look, the edge what is in doubt.
/// Changing all brushed would wash out dark hair measured against a face.
Uint8List refineAlpha(RefineJob job) {
  var w = job.width, h = job.height, n = w * h;
  var out = Uint8List.fromList(job.alpha);
  var zone = math.max(2, job.radius ~/ 2);
  // How many kept pixels round each one, for whether it is near the edge.
  var kept = _Sums.of(job.rgba, w, h, (i) => job.alpha[i] > 127 ? 1.0 : 0.0);

  /// within is whether there is an edge within [reach] of a pixel.
  Uint8List within(int reach) {
    var near = Uint8List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var (_, _, _, count) = kept.mean(x, y, reach);
        var x0 = math.max(0, x - reach), x1 = math.min(w, x + reach + 1);
        var y0 = math.max(0, y - reach), y1 = math.min(h, y + reach + 1);
        var area = (x1 - x0) * (y1 - y0);
        if (count > 0.5 && count < area - 0.5) near[y * w + x] = 1;
      }
    }
    return near;
  }

  var nearEdge = within(zone);
  // F and B are sampled from a thin ring just outside the zone, so F is the
  // subject's colour at its edge (the hair) rather than its average (mostly
  // face). A wider ring reaches the face.
  var ring = within(zone + math.max(2, zone ~/ 3));
  var fg = _Sums.of(
      job.rgba,
      w,
      h,
      (i) =>
          ring[i] == 1 && nearEdge[i] == 0 && job.alpha[i] > 230 ? 1.0 : 0.0);
  var bg = _Sums.of(job.rgba, w, h,
      (i) => ring[i] == 1 && nearEdge[i] == 0 && job.alpha[i] < 25 ? 1.0 : 0.0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      var b = job.band[i];
      if (b == 0 || nearEdge[i] == 0) continue;
      var (fr, fgr, fb, fn) = fg.mean(x, y, job.radius);
      var (br, bgr, bb, bn) = bg.mean(x, y, job.radius);
      // Not enough near to go on: look further.
      if (fn < 4) (fr, fgr, fb, fn) = fg.mean(x, y, job.radius * 3);
      if (bn < 4) (br, bgr, bb, bn) = bg.mean(x, y, job.radius * 3);
      if (fn < 4 || bn < 4) continue;
      var dr = fr - br, dg = fgr - bgr, db = fb - bb;
      var span = dr * dr + dg * dg + db * db;
      // Subject and background too alike here for colour to tell them
      // apart: the mask knows better than a guess.
      if (span < 900) continue;
      var cr = job.rgba[i * 4] - br;
      var cg = job.rgba[i * 4 + 1] - bgr;
      var cb = job.rgba[i * 4 + 2] - bb;
      var a = ((cr * dr + cg * dg + cb * db) / span).clamp(0.0, 1.0);
      var k = b / 255;
      out[i] = (job.alpha[i] * (1 - k) + a * 255 * k).round().clamp(0, 255);
    }
  }
  return out;
}

/// DeconJob is a picture whose edge colours are to be cleaned: [rgba] its
/// straight colour, [alpha] its mask, [amount] how far to go, 0 to 1, and
/// [radius] how far to look for the subject's own colour.
class DeconJob {
  final Uint8List rgba;
  final Uint8List alpha;
  final int width, height;
  final double amount;
  final int radius;
  const DeconJob(
      this.rgba, this.alpha, this.width, this.height, this.amount, this.radius);
}

/// decontaminate is [job]'s picture, premultiplied, with the background's
/// colour taken out of its edge, alpha untouched: each partly shown pixel
/// moved towards the subject's colour near it, the more the more hidden.
Uint8List decontaminate(DeconJob job) {
  var w = job.width, h = job.height, n = w * h;
  var out = Uint8List(n * 4);
  var fg = _Sums.of(job.rgba, w, h, (i) => job.alpha[i] > 235 ? 1.0 : 0.0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      var a = job.alpha[i];
      var r = job.rgba[i * 4].toDouble();
      var g = job.rgba[i * 4 + 1].toDouble();
      var b = job.rgba[i * 4 + 2].toDouble();
      if (a > 3 && a < 250) {
        var (fr, fgr, fb, fn) = fg.mean(x, y, job.radius);
        if (fn < 2) (fr, fgr, fb, fn) = fg.mean(x, y, job.radius * 4);
        if (fn >= 2) {
          var t = job.amount * math.min(1.0, (1 - a / 255) * 1.5);
          r += (fr - r) * t;
          g += (fgr - g) * t;
          b += (fb - b) * t;
        }
      }
      var pa = job.rgba[i * 4 + 3] / 255;
      out[i * 4] = (r * pa).round().clamp(0, 255);
      out[i * 4 + 1] = (g * pa).round().clamp(0, 255);
      out[i * 4 + 2] = (b * pa).round().clamp(0, 255);
      out[i * 4 + 3] = job.rgba[i * 4 + 3];
    }
  }
  return out;
}

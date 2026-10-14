import 'dart:math' as math;
import 'dart:typed_data';

// segmentation.dart separates a subject from its background by colour and
// by edge: the engine behind Quick select, and behind Select subject where
// the operating system cannot find one itself.
//
// It is GrabCut, more or less. Two colour models -- what the subject is made
// of, and what the background is made of -- are learnt from pixels known to
// be one or the other; every other pixel is then given to whichever side
// costs least, where a pixel costs what its colour is unlikely to be on that
// side, and cutting between two neighbours costs more the more alike they
// are. The cheapest cut is a minimum cut of a graph, found as a maximum flow.
// So the boundary runs where the picture has an edge, and nowhere it does
// not, which is the whole of what threshold-and-flood removal could never
// promise.
//
// Pure Dart over plain lists, so it runs in an isolate.

/// Seed is what a pixel is known to be before the cut.
abstract final class Seed {
  static const int unknown = 0;
  static const int subject = 1;
  static const int background = 2;
}

/// SegmentJob is one cut to make: [rgba] is [width] x [height] pixels, four
/// bytes each (straight or premultiplied -- only colour is compared, and the
/// pictures cut are opaque), and [seeds] says what is known of each, one
/// byte each. [prior], where given, is how sure each pixel already was of
/// being the subject, 0 to 255: it does not decide anything, but it gives the
/// colour models more to learn from than the seeds alone.
class SegmentJob {
  final Uint8List rgba;
  final int width;
  final int height;
  final Uint8List seeds;
  final Uint8List? prior;

  /// rounds is how many times the models are relearnt from the last cut and
  /// the cut made again. One for a brush stroke, where the seeds say most of
  /// it; a few for a whole picture with little to go on.
  final int rounds;

  /// smoothness is how much an edge between alike pixels costs, against what
  /// a pixel's own colour costs: higher follows the picture's edges more
  /// closely and leaves fewer stray specks.
  final double smoothness;

  const SegmentJob({
    required this.rgba,
    required this.width,
    required this.height,
    required this.seeds,
    this.prior,
    this.rounds = 1,
    this.smoothness = 50,
  });
}

/// segment makes [job]'s cut and returns 255 for each subject pixel and 0
/// for each background one. A top-level function, for compute().
Uint8List segment(SegmentJob job) {
  var n = job.width * job.height;
  var labels = Uint8List(n);
  // To begin with, what is known, and -- where a prior says -- what was
  // thought; nothing else is the subject.
  for (var i = 0; i < n; i++) {
    var s = job.seeds[i];
    labels[i] = s == Seed.subject ||
            (s == Seed.unknown && (job.prior?[i] ?? 0) >= 128)
        ? 255
        : 0;
  }
  var prior = job.prior;
  for (var round = 0; round < math.max(1, job.rounds); round++) {
    // The first models are learnt from what is known -- the seeds, and what
    // a prior is sure of -- and from nothing guessed. Learnt from every
    // pixel not yet called the subject, the background's model took in most
    // of the subject itself, and a subject a shade off its background then
    // looked like background everywhere but under the stroke.
    bool first = round == 0;
    bool known(int i, bool subject) {
      var s = job.seeds[i];
      if (s != Seed.unknown) return s == (subject ? Seed.subject : Seed.background);
      if (first) {
        if (prior == null) return false;
        return subject ? prior[i] >= 192 : prior[i] < 64;
      }
      return (labels[i] == 255) == subject;
    }

    var fg = _Gmm.fit(job.rgba, n, (i) => known(i, true));
    var bg = _Gmm.fit(job.rgba, n, (i) => known(i, false));
    // With nothing known of one side, its model is everything that is not
    // the other's: better than no model, and the next round does better.
    fg ??= _Gmm.fit(job.rgba, n, (i) => labels[i] == 255);
    bg ??= _Gmm.fit(job.rgba, n, (i) => labels[i] == 0);
    if (fg == null || bg == null) return labels;
    labels = _cut(job, fg, bg);
  }
  return labels;
}

/// _Gmm is a handful of colour clusters, each a mean and a spread in each
/// channel and a share of the whole: a model of what one side is made of.
class _Gmm {
  final List<Float64List> means;
  final List<Float64List> spreads;
  final Float64List weights;
  _Gmm(this.means, this.spreads, this.weights);

  static const int _k = 5;

  /// fit learns a model from the pixels [take] picks, or null where it picks
  /// none. Sampled down to a few thousand: more teach it nothing.
  static _Gmm? fit(Uint8List rgba, int n, bool Function(int) take) {
    var picked = <int>[];
    for (var i = 0; i < n; i++) {
      if (take(i)) picked.add(i);
    }
    if (picked.isEmpty) return null;
    var step = math.max(1, picked.length ~/ 6000);
    var samples = <Float64List>[
      for (var j = 0; j < picked.length; j += step)
        Float64List.fromList([
          rgba[picked[j] * 4].toDouble(),
          rgba[picked[j] * 4 + 1].toDouble(),
          rgba[picked[j] * 4 + 2].toDouble(),
        ])
    ];
    var k = math.min(_k, samples.length);
    // Started from samples spread through the list, then a few rounds of
    // k-means. Deterministic: the same strokes give the same cut.
    var means = [
      for (var c = 0; c < k; c++)
        Float64List.fromList(samples[(c * samples.length) ~/ k])
    ];
    var owner = Int32List(samples.length);
    for (var iter = 0; iter < 8; iter++) {
      for (var s = 0; s < samples.length; s++) {
        var best = 0;
        var bestD = double.infinity;
        for (var c = 0; c < k; c++) {
          var d = _d2(samples[s], means[c]);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        owner[s] = best;
      }
      for (var c = 0; c < k; c++) {
        var sum = Float64List(3);
        var count = 0;
        for (var s = 0; s < samples.length; s++) {
          if (owner[s] != c) continue;
          count++;
          for (var ch = 0; ch < 3; ch++) {
            sum[ch] += samples[s][ch];
          }
        }
        if (count > 0) {
          for (var ch = 0; ch < 3; ch++) {
            means[c][ch] = sum[ch] / count;
          }
        }
      }
    }
    var spreads = [for (var c = 0; c < k; c++) Float64List(3)];
    var weights = Float64List(k);
    for (var s = 0; s < samples.length; s++) {
      var c = owner[s];
      weights[c]++;
      for (var ch = 0; ch < 3; ch++) {
        var d = samples[s][ch] - means[c][ch];
        spreads[c][ch] += d * d;
      }
    }
    for (var c = 0; c < k; c++) {
      for (var ch = 0; ch < 3; ch++) {
        // Never narrower than a few levels: a flat colour would otherwise
        // be a spike that nothing a shade off it could ever belong to.
        spreads[c][ch] =
            math.max(30, weights[c] == 0 ? 900 : spreads[c][ch] / weights[c]);
      }
      weights[c] = (weights[c] + 1) / (samples.length + k);
    }
    return _Gmm(means, spreads, weights);
  }

  static double _d2(Float64List a, Float64List b) {
    var dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
    return dr * dr + dg * dg + db * db;
  }

  /// cost is how unlikely a colour is under this model, as a negative log.
  double cost(double r, double g, double b) {
    var p = 0.0;
    for (var c = 0; c < weights.length; c++) {
      var m = means[c], s = spreads[c];
      var dr = r - m[0], dg = g - m[1], db = b - m[2];
      var e = dr * dr / s[0] + dg * dg / s[1] + db * db / s[2];
      p += weights[c] * math.exp(-0.5 * e) / math.sqrt(s[0] * s[1] * s[2]);
    }
    return -math.log(math.max(p, 1e-30));
  }
}

const double _hard = 1e7;

/// _cut is one minimum cut with the models [fg] and [bg].
Uint8List _cut(SegmentJob job, _Gmm fg, _Gmm bg) {
  var w = job.width, h = job.height, n = w * h;
  var rgba = job.rgba;
  var flow = GridFlow(w, h);

  // beta scales colour differences to the picture's own: the average squared
  // difference between neighbours, so a low-contrast picture's edges count
  // for as much as a high-contrast one's.
  var sum = 0.0;
  var count = 0;
  double diff(int i, int j) {
    var dr = rgba[i * 4] - rgba[j * 4];
    var dg = rgba[i * 4 + 1] - rgba[j * 4 + 1];
    var db = rgba[i * 4 + 2] - rgba[j * 4 + 2];
    return (dr * dr + dg * dg + db * db).toDouble();
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      if (x + 1 < w) {
        sum += diff(i, i + 1);
        count++;
      }
      if (y + 1 < h) {
        sum += diff(i, i + w);
        count++;
      }
    }
  }
  var beta = count == 0 || sum == 0 ? 0.0 : 1 / (2 * sum / count);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var i = y * w + x;
      switch (job.seeds[i]) {
        case Seed.subject:
          flow.sCap[i] = _hard;
        case Seed.background:
          flow.tCap[i] = _hard;
        default:
          var r = rgba[i * 4].toDouble();
          var g = rgba[i * 4 + 1].toDouble();
          var b = rgba[i * 4 + 2].toDouble();
          // Joining the source is being the subject, so the source's edge
          // is cut -- and paid -- by a pixel that ends up background.
          flow.sCap[i] = bg.cost(r, g, b);
          flow.tCap[i] = fg.cost(r, g, b);
      }
      if (x + 1 < w) {
        var weight = job.smoothness * math.exp(-beta * diff(i, i + 1));
        flow.link(i, 0, weight);
      }
      if (y + 1 < h) {
        var weight = job.smoothness * math.exp(-beta * diff(i, i + w));
        flow.link(i, 2, weight);
      }
    }
  }
  flow.solve();
  var side = flow.sourceSide();
  var out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = side[i] == 1 ? 255 : 0;
  }
  return out;
}

/// GridFlow is a maximum flow over a grid of pixels, each joined to its four
/// neighbours, to a source and to a sink. Dinic's method: layer the graph by
/// distance from the source, push flow along the layers until none gets
/// through, and again until the sink cannot be reached.
class GridFlow {
  final int w, h, n;

  /// sCap and tCap are what is left of each pixel's edge from the source and
  /// to the sink; cap[d] its edge to its neighbour in direction d -- right,
  /// left, down, up.
  final Float64List sCap, tCap;
  final List<Float64List> cap;
  final Int32List _level, _arc;
  int _sinkLevel = -1;
  double flowed = 0;

  static const _eps = 1e-9;

  GridFlow(this.w, this.h)
      : n = w * h,
        sCap = Float64List(w * h),
        tCap = Float64List(w * h),
        cap = List.generate(4, (_) => Float64List(w * h)),
        _level = Int32List(w * h),
        _arc = Int32List(w * h);

  /// link joins pixel [i] to its neighbour in direction [d] (0 right, 2
  /// down), both ways, with [weight].
  void link(int i, int d, double weight) {
    var j = _next(i, d);
    if (j < 0) return;
    cap[d][i] += weight;
    cap[d ^ 1][j] += weight;
  }

  int _next(int i, int d) {
    switch (d) {
      case 0:
        return (i % w) + 1 < w ? i + 1 : -1;
      case 1:
        return i % w > 0 ? i - 1 : -1;
      case 2:
        return i + w < n ? i + w : -1;
      default:
        return i - w >= 0 ? i - w : -1;
    }
  }

  /// solve pushes as much as will go from the source to the sink.
  void solve() {
    // What goes straight through a pixel, source to sink, needs no search.
    for (var i = 0; i < n; i++) {
      var m = math.min(sCap[i], tCap[i]);
      sCap[i] -= m;
      tCap[i] -= m;
      flowed += m;
    }
    var stack = Int32List(n + 1);
    var dirs = Int32List(n + 1);
    while (_layer()) {
      _arc.fillRange(0, n, 0);
      for (var start = 0; start < n; start++) {
        if (_level[start] != 1) continue;
        while (sCap[start] > _eps) {
          var pushed = _augment(start, stack, dirs);
          if (pushed <= 0) break;
        }
      }
    }
  }

  /// _layer gives every pixel its distance from the source, and says whether
  /// the sink can be reached at all.
  bool _layer() {
    _level.fillRange(0, n, -1);
    var queue = Int32List(n);
    var head = 0, tail = 0;
    for (var i = 0; i < n; i++) {
      if (sCap[i] > _eps) {
        _level[i] = 1;
        queue[tail++] = i;
      }
    }
    _sinkLevel = -1;
    while (head < tail) {
      var u = queue[head++];
      if (tCap[u] > _eps && _sinkLevel < 0) _sinkLevel = _level[u] + 1;
      // Nothing further from the source than the sink is needed this round.
      if (_sinkLevel >= 0 && _level[u] + 1 >= _sinkLevel) continue;
      for (var d = 0; d < 4; d++) {
        if (cap[d][u] <= _eps) continue;
        var v = _next(u, d);
        if (v < 0 || _level[v] >= 0) continue;
        _level[v] = _level[u] + 1;
        queue[tail++] = v;
      }
    }
    return _sinkLevel >= 0;
  }

  /// _augment finds one path along the layers from the source through
  /// [start] to the sink and pushes what it will carry; nought where there
  /// is none left through [start].
  double _augment(int start, Int32List stack, Int32List dirs) {
    var depth = 0;
    stack[0] = start;
    while (depth >= 0) {
      var u = stack[depth];
      if (tCap[u] > _eps && _level[u] + 1 == _sinkLevel) {
        // Found: the least of what each edge on the way has left.
        var amount = math.min(sCap[start], tCap[u]);
        for (var k = 0; k < depth; k++) {
          amount = math.min(amount, cap[dirs[k]][stack[k]]);
        }
        sCap[start] -= amount;
        tCap[u] -= amount;
        for (var k = 0; k < depth; k++) {
          var d = dirs[k];
          cap[d][stack[k]] -= amount;
          cap[d ^ 1][stack[k + 1]] += amount;
        }
        flowed += amount;
        return amount;
      }
      var advanced = false;
      while (_arc[u] < 4) {
        var d = _arc[u];
        var v = _next(u, d);
        if (v >= 0 &&
            cap[d][u] > _eps &&
            _level[v] == _level[u] + 1 &&
            _level[v] < _sinkLevel) {
          dirs[depth] = d;
          stack[++depth] = v;
          advanced = true;
          break;
        }
        _arc[u]++;
      }
      if (advanced) continue;
      // A dead end: nothing more goes through it this round.
      _level[u] = -1;
      depth--;
      if (depth >= 0) _arc[stack[depth]]++;
    }
    return 0;
  }

  /// sourceSide is 1 for each pixel the source can still reach once the
  /// flow is done -- the subject's side of the cut -- and 0 for the rest.
  Uint8List sourceSide() {
    var seen = Uint8List(n);
    var queue = Int32List(n);
    var head = 0, tail = 0;
    for (var i = 0; i < n; i++) {
      if (sCap[i] > _eps) {
        seen[i] = 1;
        queue[tail++] = i;
      }
    }
    while (head < tail) {
      var u = queue[head++];
      for (var d = 0; d < 4; d++) {
        if (cap[d][u] <= _eps) continue;
        var v = _next(u, d);
        if (v < 0 || seen[v] == 1) continue;
        seen[v] = 1;
        queue[tail++] = v;
      }
    }
    return seen;
  }
}

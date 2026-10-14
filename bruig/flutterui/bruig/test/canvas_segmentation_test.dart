import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/render/segmentation.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_segmentation_test.dart is the cut behind Quick select: the maximum
// flow checked against every possible cut of a small grid, and the whole
// thing against pictures whose answer is known.

/// _disc is a [size] square picture of [inside] in a disc of [radius] in the
/// middle, on [outside], with a little noise so no colour is exact.
(Uint8List, Uint8List) _disc(int size, double radius, List<int> inside,
    List<int> outside,
    {int noise = 12, int seed = 1}) {
  var random = math.Random(seed);
  var rgba = Uint8List(size * size * 4);
  var truth = Uint8List(size * size);
  var c = size / 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var i = y * size + x;
      var inDisc = math.pow(x + 0.5 - c, 2) + math.pow(y + 0.5 - c, 2) <
          radius * radius;
      truth[i] = inDisc ? 255 : 0;
      var colour = inDisc ? inside : outside;
      for (var ch = 0; ch < 3; ch++) {
        rgba[i * 4 + ch] =
            (colour[ch] + random.nextInt(2 * noise + 1) - noise).clamp(0, 255);
      }
      rgba[i * 4 + 3] = 255;
    }
  }
  return (rgba, truth);
}

/// _overlap is the intersection over union of two masks.
double _overlap(Uint8List a, Uint8List b) {
  var both = 0, either = 0;
  for (var i = 0; i < a.length; i++) {
    var x = a[i] > 127, y = b[i] > 127;
    if (x && y) both++;
    if (x || y) either++;
  }
  return either == 0 ? 1 : both / either;
}

void main() {
  group("the maximum flow", () {
    test("is the minimum cut, on every small grid tried", () {
      var random = math.Random(7);
      for (var trial = 0; trial < 40; trial++) {
        const w = 3, h = 3, n = w * h;
        var s = [for (var i = 0; i < n; i++) random.nextDouble() * 5];
        var t = [for (var i = 0; i < n; i++) random.nextDouble() * 5];
        var right = [for (var i = 0; i < n; i++) random.nextDouble() * 3];
        var down = [for (var i = 0; i < n; i++) random.nextDouble() * 3];

        var flow = GridFlow(w, h);
        for (var i = 0; i < n; i++) {
          flow.sCap[i] = s[i];
          flow.tCap[i] = t[i];
          if (i % w + 1 < w) flow.link(i, 0, right[i]);
          if (i + w < n) flow.link(i, 2, down[i]);
        }
        flow.solve();

        // Every way of dividing nine pixels, and what each costs.
        var best = double.infinity;
        for (var set = 0; set < 1 << n; set++) {
          bool source(int i) => set & (1 << i) != 0;
          var cost = 0.0;
          for (var i = 0; i < n; i++) {
            cost += source(i) ? t[i] : s[i];
            if (i % w + 1 < w && source(i) != source(i + 1)) cost += right[i];
            if (i + w < n && source(i) != source(i + w)) cost += down[i];
          }
          best = math.min(best, cost);
        }
        expect(flow.flowed, closeTo(best, 1e-6), reason: "trial $trial");

        // And the side it reports is a cut that costs exactly that.
        var side = flow.sourceSide();
        var cost = 0.0;
        for (var i = 0; i < n; i++) {
          var a = side[i] == 1;
          cost += a ? t[i] : s[i];
          if (i % w + 1 < w && a != (side[i + 1] == 1)) cost += right[i];
          if (i + w < n && a != (side[i + w] == 1)) cost += down[i];
        }
        expect(cost, closeTo(best, 1e-6), reason: "trial $trial's cut");
      }
    });
  });

  group("a cut", () {
    test("a stroke on the subject finds all of it, and no more", () {
      const size = 80;
      var (rgba, truth) =
          _disc(size, 24, const [200, 40, 40], const [40, 60, 200]);
      var seeds = Uint8List(size * size);
      // A short stroke across the middle, and the picture's border known to
      // be background -- what Quick select's region gives it.
      for (var x = 34; x < 46; x++) {
        seeds[40 * size + x] = Seed.subject;
      }
      for (var i = 0; i < size; i++) {
        seeds[i] = Seed.background;
        seeds[(size - 1) * size + i] = Seed.background;
        seeds[i * size] = Seed.background;
        seeds[i * size + size - 1] = Seed.background;
      }
      var cut = segment(SegmentJob(
          rgba: rgba, width: size, height: size, seeds: seeds, rounds: 2));
      expect(_overlap(cut, truth), greaterThan(0.95));
    });

    test("a whole picture with only its border to go on", () {
      // GrabCut's case: nothing is known of the subject, only that the edge
      // of the picture is not it.
      const size = 80;
      var (rgba, truth) =
          _disc(size, 22, const [230, 200, 60], const [60, 70, 80]);
      var seeds = Uint8List(size * size);
      var prior = Uint8List(size * size);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          var edge = x < 4 || y < 4 || x >= size - 4 || y >= size - 4;
          seeds[y * size + x] = edge ? Seed.background : Seed.unknown;
          prior[y * size + x] = edge ? 0 : 255;
        }
      }
      var cut = segment(SegmentJob(
          rgba: rgba,
          width: size,
          height: size,
          seeds: seeds,
          prior: prior,
          rounds: 4));
      expect(_overlap(cut, truth), greaterThan(0.9));
    });

    test("noise does not leave specks", () {
      const size = 60;
      var (rgba, truth) = _disc(
          size, 18, const [150, 120, 100], const [90, 100, 120],
          noise: 40, seed: 3);
      var seeds = Uint8List(size * size);
      for (var y = 27; y < 33; y++) {
        for (var x = 27; x < 33; x++) {
          seeds[y * size + x] = Seed.subject;
        }
      }
      for (var i = 0; i < size; i++) {
        seeds[i] = Seed.background;
        seeds[(size - 1) * size + i] = Seed.background;
        seeds[i * size] = Seed.background;
        seeds[i * size + size - 1] = Seed.background;
      }
      var cut = segment(SegmentJob(
          rgba: rgba, width: size, height: size, seeds: seeds, rounds: 3));
      expect(_overlap(cut, truth), greaterThan(0.85));
    });

    test("is quick enough for a brush", () {
      const size = 300;
      var (rgba, _) = _disc(size, 90, const [200, 40, 40], const [40, 60, 200]);
      var seeds = Uint8List(size * size);
      for (var x = 140; x < 160; x++) {
        seeds[150 * size + x] = Seed.subject;
      }
      for (var i = 0; i < size; i++) {
        seeds[i] = Seed.background;
        seeds[(size - 1) * size + i] = Seed.background;
      }
      var clock = Stopwatch()..start();
      segment(SegmentJob(rgba: rgba, width: size, height: size, seeds: seeds));
      expect(clock.elapsedMilliseconds, lessThan(3000));
    });
  });
}

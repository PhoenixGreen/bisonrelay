import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// reference_sheet.dart reads a model sheet for the Character Studio: where
// its figures are -- found by the plain background between them -- how a
// figure measures -- its top, its chin, its feet, and so how many heads tall
// it stands -- and the colours it is drawn in. Plain functions over a
// picture's RGBA bytes, so a sheet is read the same in a test as in the app.

/// SheetPixels is a picture's pixels: RGBA, a row at a time.
class SheetPixels {
  final Uint8List rgba;
  final int width;
  final int height;
  const SheetPixels(this.rgba, this.width, this.height);

  Color at(int x, int y) {
    var i = (y * width + x) * 4;
    return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  /// sample is the colour at ([x], [y]) -- pixel centres at the halves --
  /// blended from the four pixels round it.
  Color sample(double x, double y) {
    var fx = (x - 0.5).clamp(0.0, width - 1.0),
        fy = (y - 0.5).clamp(0.0, height - 1.0);
    var ax = fx.floor(), ay = fy.floor();
    var bx = math.min(ax + 1, width - 1), by = math.min(ay + 1, height - 1);
    var tx = fx - ax, ty = fy - ay;
    double ch(int k) {
      double v(int px, int py) => rgba[(py * width + px) * 4 + k].toDouble();
      var top = v(ax, ay) * (1 - tx) + v(bx, ay) * tx;
      var bottom = v(ax, by) * (1 - tx) + v(bx, by) * tx;
      return top * (1 - ty) + bottom * ty;
    }

    return Color.fromARGB(
        ch(3).round(), ch(0).round(), ch(1).round(), ch(2).round());
  }

  /// background is the sheet's own colour: the commonest along its top
  /// and its sides -- not its bottom, where a sheet often carries a strip
  /// of its own: a caption, a mark.
  Color get background {
    var counts = <int, (int, double, double, double)>{};
    void count(int x, int y) {
      var c = at(x, y);
      var k = ((c.r * 15).round() << 8) |
          ((c.g * 15).round() << 4) |
          (c.b * 15).round();
      var (n, r, g, b) = counts[k] ?? (0, 0.0, 0.0, 0.0);
      counts[k] = (n + 1, r + c.r, g + c.g, b + c.b);
    }

    for (var x = 0; x < width; x += 2) {
      count(x, 1.clamp(0, height - 1));
    }
    for (var y = 0; y < height * 0.8; y += 2) {
      count(1.clamp(0, width - 1), y);
      count((width - 2).clamp(0, width - 1), y);
    }
    var (n, r, g, b) = counts.values.reduce((a, b) => a.$1 >= b.$1 ? a : b);
    return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  }
}

double _distance(Color a, Color b) {
  var dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

/// SheetCut is a part of a sheet found to hold something: a figure, tall
/// and narrow, or not -- a panel of faces, a title.
class SheetCut {
  final Rect rect;
  final bool figure;
  const SheetCut(this.rect, this.figure);
}

/// _inked is whether a pixel is drawn on, not the sheet's background.
bool _inked(SheetPixels p, int x, int y, Color ground, double tolerance) {
  var c = p.at(x, y);
  return c.a > 0.1 && _distance(c, ground) > tolerance;
}

/// findCuts is what is drawn on [p], left to right: each run of columns
/// with something on it, between gaps of the background at least [gap]
/// pixels wide, trimmed to what is on it. A cut more than [tall] times as
/// high as it is wide is a figure. Specks are passed by.
List<SheetCut> findCuts(SheetPixels p,
    {double tolerance = 0.12, int gap = 3, double tall = 1.6}) {
  var ground = p.background;
  // A band drawn nearly all the way across -- a frame, a caption strip --
  // is no figure, and would join every column to the next: left out.
  var band = List<bool>.filled(p.height, false);
  for (var y = 0; y < p.height; y++) {
    var n = 0;
    for (var x = 0; x < p.width; x++) {
      if (_inked(p, x, y, ground, tolerance)) n++;
    }
    band[y] = n > p.width * 0.85;
  }
  var count = List<int>.filled(p.width, 0);
  for (var x = 0; x < p.width; x++) {
    for (var y = 0; y < p.height; y++) {
      if (!band[y] && _inked(p, x, y, ground, tolerance)) count[x]++;
    }
  }
  // A column is drawn on where more than a speck is.
  var least = math.max(2, p.height ~/ 100);
  var runs = <(int, int)>[];
  int? start;
  var empty = 0;
  for (var x = 0; x <= p.width; x++) {
    var on = x < p.width && count[x] >= least;
    if (on) {
      start ??= x;
      empty = 0;
    } else if (start != null) {
      empty++;
      if (empty >= gap || x == p.width) {
        runs.add((start, x - empty + 1));
        start = null;
        empty = 0;
      }
    }
  }
  var cuts = <SheetCut>[];
  for (var (x0, x1) in runs) {
    if (x1 - x0 < math.max(4, p.width ~/ 60)) continue;
    int? top, bottom;
    for (var y = 0; y < p.height; y++) {
      if (band[y]) continue;
      var n = 0;
      for (var x = x0; x < x1; x++) {
        if (_inked(p, x, y, ground, tolerance)) n++;
      }
      if (n >= math.max(1, (x1 - x0) ~/ 40)) {
        top ??= y;
        bottom = y + 1;
      }
    }
    if (top == null || bottom == null) continue;
    var r = Rect.fromLTRB(
        x0.toDouble(), top.toDouble(), x1.toDouble(), bottom.toDouble());
    cuts.add(SheetCut(r, r.height > r.width * tall));
  }
  return cuts;
}

/// FigureMeasure is how a figure stands: its top, its chin and its feet,
/// in the sheet's pixels, and so how many heads tall it is.
class FigureMeasure {
  final double top;
  final double chin;
  final double bottom;

  /// widest is the head's widest row: about its middle, for a round head.
  final double widest;
  const FigureMeasure(this.top, this.chin, this.bottom, this.widest);

  /// skull is where the head's own top is: as far above its widest as the
  /// chin is below -- under a bun, a quiff, a hat, which the figure's top
  /// counts.
  double get skull {
    var r = chin - widest;
    if (r <= 0) return top;
    return math.max(top, widest - r);
  }

  /// headsTall is how many heads tall it stands, a head from its skull to
  /// its chin, as the rig counts; withHair, from the top of whatever is on
  /// it.
  double get headsTall => chin <= skull ? 0 : (bottom - skull) / (chin - skull);
  double get withHair => chin <= top ? 0 : (bottom - top) / (chin - top);

  /// at is where [fraction] of the way down the figure is, in the sheet.
  double at(double fraction) => top + (bottom - top) * fraction;
}

/// measureFigure finds, within [cut] of [p], the figure's top, its feet
/// and its chin: the neck is where it is narrowest below the widest part of
/// the head, in the top third, and the chin a little above it.
FigureMeasure? measureFigure(SheetPixels p, Rect cut,
    {double tolerance = 0.12}) {
  var ground = p.background;
  var x0 = cut.left.floor().clamp(0, p.width - 1);
  var x1 = cut.right.ceil().clamp(1, p.width);
  var y0 = cut.top.floor().clamp(0, p.height - 1);
  var y1 = cut.bottom.ceil().clamp(1, p.height);
  var widths = <int>[];
  for (var y = y0; y < y1; y++) {
    int? l, r;
    for (var x = x0; x < x1; x++) {
      if (_inked(p, x, y, ground, tolerance)) {
        l ??= x;
        r = x;
      }
    }
    widths.add(l == null ? 0 : r! - l + 1);
  }
  var first = widths.indexWhere((w) => w > 0);
  var last = widths.lastIndexWhere((w) => w > 0);
  if (first < 0 || last <= first) return null;
  var height = last - first + 1;
  // The head: the widest rows in the top quarter.
  var headEnd = first + (height * 0.28).round();
  var widest = first, most = 0;
  for (var y = first; y <= headEnd && y < widths.length; y++) {
    if (widths[y] > most) {
      most = widths[y];
      widest = y;
    }
  }
  // The neck: the narrowest below it, before the shoulders spread.
  var neckEnd = first + (height * 0.36).round();
  var neck = widest, least = most;
  for (var y = widest; y <= neckEnd && y < widths.length; y++) {
    if (widths[y] > 0 && widths[y] < least) {
      least = widths[y];
      neck = y;
    }
  }
  if (neck <= widest) neck = first + (height / 5.5).round();
  var chin = neck - (neck - first) * 0.06;
  return FigureMeasure((y0 + first).toDouble(), y0 + chin,
      (y0 + last + 1).toDouble(), (y0 + widest).toDouble());
}

/// facesRight is whether the figure in [cut] -- seen from the side --
/// faces right: its feet reach further forward than its shins, toes first.
/// Null where it cannot tell: the two are level, or nothing is drawn.
bool? facesRight(SheetPixels p, Rect cut, {double tolerance = 0.12}) {
  var ground = p.background;
  double? middle(double from, double to) {
    var sum = 0.0, n = 0;
    for (var y = (cut.top + cut.height * from).floor();
        y < (cut.top + cut.height * to).ceil() && y < p.height;
        y++) {
      for (var x = cut.left.floor(); x < cut.right.ceil() && x < p.width; x++) {
        if (x < 0 || y < 0) continue;
        if (_inked(p, x, y, ground, tolerance)) {
          sum += x;
          n++;
        }
      }
    }
    return n == 0 ? null : sum / n;
  }

  // The shoes: the last few hundredths down; the shins, above them.
  var feet = middle(0.95, 1.0), shins = middle(0.78, 0.88);
  if (feet == null || shins == null) return null;
  var lean = (feet - shins) / math.max(1.0, cut.width);
  if (lean.abs() < 0.03) return null;
  return lean > 0;
}

/// paletteOf is the colours [p] is drawn in within [cuts] -- the
/// background left out -- the most used first: at most [most], each a
/// distinct colour, not one shaded twice.
List<Color> paletteOf(SheetPixels p, List<Rect> cuts,
    {int most = 9, double tolerance = 0.12, double apart = 0.16}) {
  var ground = p.background;
  // Counted on a coarse grid of colour: a few shades of one paint are one
  // paint.
  var bins = <int, (int, double, double, double)>{};
  for (var cut in cuts) {
    var step = math.max(1, (cut.width * cut.height / 40000).sqrt().floor());
    for (var y = cut.top.floor(); y < cut.bottom.ceil(); y += step) {
      for (var x = cut.left.floor(); x < cut.right.ceil(); x += step) {
        if (x < 0 || y < 0 || x >= p.width || y >= p.height) continue;
        var c = p.at(x, y);
        if (c.a < 0.5 || _distance(c, ground) <= tolerance) continue;
        var k = ((c.r * 7).round() << 6) |
            ((c.g * 7).round() << 3) |
            (c.b * 7).round();
        var (n, r, g, b) = bins[k] ?? (0, 0.0, 0.0, 0.0);
        bins[k] = (n + 1, r + c.r, g + c.g, b + c.b);
      }
    }
  }
  var ranked = bins.values.toList()..sort((a, b) => b.$1.compareTo(a.$1));
  var out = <Color>[];
  for (var (n, r, g, b) in ranked) {
    var c = Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
    if (out.any((o) => _distance(o, c) < apart)) continue;
    // Not a paint: an edge's blend of one already found and the sheet.
    if (_blendOfAny(c, ground, out)) continue;
    out.add(c);
    if (out.length >= most) break;
  }
  return out;
}

/// _blendOfAny is whether [c] lies between [ground] and one of [paints],
/// well inside: an edge softened into the sheet.
bool _blendOfAny(Color c, Color ground, List<Color> paints) {
  for (var s in paints) {
    var pr = s.r - ground.r, pg = s.g - ground.g, pb = s.b - ground.b;
    var len = pr * pr + pg * pg + pb * pb;
    if (len < 0.01) continue;
    var cr = c.r - ground.r, cg = c.g - ground.g, cb = c.b - ground.b;
    var t = (cr * pr + cg * pg + cb * pb) / len;
    if (t <= 0.15 || t >= 0.85) continue;
    var dr = cr - t * pr, dg = cg - t * pg, db = cb - t * pb;
    if (math.sqrt(dr * dr + dg * dg + db * db) < 0.035) return true;
  }
  return false;
}

extension on num {
  double sqrt() => math.sqrt(toDouble());
}

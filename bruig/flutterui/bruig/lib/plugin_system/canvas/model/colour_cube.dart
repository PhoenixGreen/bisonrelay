import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

// colour_cube.dart is a colour table (a "3D LUT"): for every colour, the
// colour it becomes, given at n points a side and read between them. It is
// how film looks and colour grades travel between programs: .cube files
// (Adobe's, which most programs write) and HaldCLUT pictures.
//
// A table is kept small -- at most [maxCubeSize] points a side, 8 bits a
// channel -- so one can live inside a document or an action and go where it
// goes: a film look is smooth, and 25 points hold it.

/// maxCubeSize is the most points a side a table keeps; larger ones are
/// resampled down when read in.
const int maxCubeSize = 25;

/// maxCubeFileBytes is the largest table file read: a 65-point .cube is
/// about 8 MB of text.
const int maxCubeFileBytes = 12 * 1024 * 1024;

class ColourCube {
  /// n is the points a side, 2 to [maxCubeSize].
  final int n;

  /// rgb is n³ colours, three bytes each, red changing fastest and blue
  /// slowest.
  final Uint8List rgb;

  ColourCube(this.n, this.rgb)
      : assert(n >= 2 && n <= maxCubeSize && rgb.length == n * n * n * 3);

  /// identity is the table that changes nothing.
  factory ColourCube.identity([int n = 17]) => ColourCube.sampled(
      n, (r, g, b) => (r, g, b));

  /// sampled is the table of [n] points a side whose colour at red [r],
  /// green [g] and blue [b] (0 to 1) is [at]'s.
  factory ColourCube.sampled(
      int n, (double, double, double) Function(double r, double g, double b) at) {
    var rgb = Uint8List(n * n * n * 3);
    var i = 0;
    for (var b = 0; b < n; b++) {
      for (var g = 0; g < n; g++) {
        for (var r = 0; r < n; r++) {
          var (cr, cg, cb) = at(r / (n - 1), g / (n - 1), b / (n - 1));
          rgb[i++] = _byte(cr);
          rgb[i++] = _byte(cg);
          rgb[i++] = _byte(cb);
        }
      }
    }
    return ColourCube(n, rgb);
  }

  /// at is the colour [r], [g], [b] (0 to 1) becomes, read between the
  /// points (trilinear).
  (double, double, double) at(double r, double g, double b) =>
      _trilinear(n, (i) => rgb[i] / 255, r, g, b);

  Map<String, dynamic> toJson() => {"n": n, "d": base64.encode(rgb)};

  /// fromJson is the table [json] holds, or null for one that is not whole.
  static ColourCube? fromJson(Object? json) {
    if (json is! Map) return null;
    var n = json["n"];
    var d = json["d"];
    if (n is! int || n < 2 || n > maxCubeSize || d is! String) return null;
    try {
      var rgb = base64.decode(d);
      if (rgb.length != n * n * n * 3) return null;
      return ColourCube(n, rgb);
    } catch (_) {
      return null;
    }
  }
}

int _byte(double v) => (v.clamp(0.0, 1.0) * 255).round();

/// _trilinear reads a table of [n] points a side, its values got by index
/// from [value] (n³ × 3, red fastest), at [r], [g], [b].
(double, double, double) _trilinear(
    int n, double Function(int) value, double r, double g, double b) {
  double place(double v) => v.clamp(0.0, 1.0) * (n - 1);
  var fr = place(r), fg = place(g), fb = place(b);
  var r0 = fr.floor(), g0 = fg.floor(), b0 = fb.floor();
  var r1 = math.min(r0 + 1, n - 1),
      g1 = math.min(g0 + 1, n - 1),
      b1 = math.min(b0 + 1, n - 1);
  var tr = fr - r0, tg = fg - g0, tb = fb - b0;
  var out = [0.0, 0.0, 0.0];
  for (var (bi, wb) in [(b0, 1 - tb), (b1, tb)]) {
    for (var (gi, wg) in [(g0, 1 - tg), (g1, tg)]) {
      for (var (ri, wr) in [(r0, 1 - tr), (r1, tr)]) {
        var w = wr * wg * wb;
        if (w == 0) continue;
        var i = (ri + gi * n + bi * n * n) * 3;
        out[0] += value(i) * w;
        out[1] += value(i + 1) * w;
        out[2] += value(i + 2) * w;
      }
    }
  }
  return (out[0], out[1], out[2]);
}

/// _resampled is a table of at most [maxCubeSize] points from one of [n]
/// points whose values are [value] (0 to 1).
ColourCube _resampled(int n, double Function(int) value) {
  var size = math.min(n, maxCubeSize);
  return ColourCube.sampled(
      size, (r, g, b) => _trilinear(n, value, r, g, b));
}

/// CubeFile is a table read from a file, with the name it gave itself.
class CubeFile {
  final String title;
  final ColourCube cube;
  const CubeFile(this.title, this.cube);
}

/// parseCubeFile is the table in [text], a .cube file (3D, or 1D made
/// into 3D), or why there is none.
(CubeFile?, String?) parseCubeFile(String text) {
  var size3 = 0, size1 = 0;
  var title = "";
  var min = [0.0, 0.0, 0.0], max = [1.0, 1.0, 1.0];
  var values = <double>[];
  for (var raw in const LineSplitter().convert(text)) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith("#")) continue;
    var parts = line.split(RegExp(r"\s+"));
    switch (parts.first.toUpperCase()) {
      case "TITLE":
        title = line.substring(5).trim().replaceAll('"', "");
        if (title.length > 80) title = title.substring(0, 80);
      case "LUT_3D_SIZE":
        size3 = int.tryParse(parts.elementAtOrNull(1) ?? "") ?? 0;
      case "LUT_1D_SIZE":
        size1 = int.tryParse(parts.elementAtOrNull(1) ?? "") ?? 0;
      case "DOMAIN_MIN" || "DOMAIN_MAX":
        var v = [for (var p in parts.skip(1).take(3)) double.tryParse(p) ?? 0];
        if (v.length == 3) {
          parts.first.toUpperCase() == "DOMAIN_MIN" ? min = v : max = v;
        }
      case "LUT_3D_INPUT_RANGE" || "LUT_1D_INPUT_RANGE":
        var lo = double.tryParse(parts.elementAtOrNull(1) ?? "");
        var hi = double.tryParse(parts.elementAtOrNull(2) ?? "");
        if (lo != null && hi != null) {
          min = [lo, lo, lo];
          max = [hi, hi, hi];
        }
      default:
        if (parts.length != 3) continue;
        var v = [for (var p in parts) double.tryParse(p)];
        if (v.any((x) => x == null || !x.isFinite)) continue;
        values.addAll(v.cast<double>());
    }
  }
  double norm(int i, double v) =>
      max[i] == min[i] ? v : (v - min[i]) / (max[i] - min[i]);
  if (size3 >= 2 && size3 <= 256) {
    if (values.length != size3 * size3 * size3 * 3) {
      return (null, "That table is not whole.");
    }
    var cube = _resampled(size3, (i) => values[i]);
    // The domain is the input's; the outputs are read as given.
    if (min.any((m) => m != 0) || max.any((m) => m != 1)) {
      var given = cube;
      cube = ColourCube.sampled(given.n, (r, g, b) {
        return given.at(norm(0, r), norm(1, g), norm(2, b));
      });
    }
    return (CubeFile(title, cube), null);
  }
  if (size1 >= 2 && size1 <= 65536) {
    if (values.length != size1 * 3) return (null, "That table is not whole.");
    double curve(int channel, double v) {
      var x = norm(channel, v).clamp(0.0, 1.0) * (size1 - 1);
      var i = x.floor(), j = math.min(i + 1, size1 - 1);
      var t = x - i;
      return values[i * 3 + channel] * (1 - t) + values[j * 3 + channel] * t;
    }

    return (
      CubeFile(
          title,
          ColourCube.sampled(17,
              (r, g, b) => (curve(0, r), curve(1, g), curve(2, b)))),
      null
    );
  }
  return (null, "That is not a colour table.");
}

/// haldCube is the table in a HaldCLUT picture of [width] by [height]
/// pixels, [rgba] four bytes each, or why there is none.
(ColourCube?, String?) haldCube(Uint8List rgba, int width, int height) {
  var level = (math.pow(width, 1 / 3) as double).round();
  if (width != height ||
      level < 2 ||
      level * level * level != width ||
      rgba.length < width * height * 4) {
    return (null, "That picture is not a HaldCLUT.");
  }
  var n = level * level;
  // Pixel k is the colour for red k % n, green k / n % n, blue k / n².
  return (
    _resampled(n, (i) {
      var pixel = i ~/ 3, channel = i % 3;
      return rgba[pixel * 4 + channel] / 255;
    }),
    null
  );
}

/// readFilmTables is the tables in a bundle as the app keeps them (see
/// assets/canvas/luts/SOURCES.md), by name.
Map<String, ColourCube> readFilmTables(Uint8List gzipped) {
  var bytes = Uint8List.fromList(const GZipDecoder().decodeBytes(gzipped));
  var out = <String, ColourCube>{};
  if (bytes.length < 8 || utf8.decode(bytes.sublist(0, 6)) != "BRLUT2") {
    return out;
  }
  var data = ByteData.sublistView(bytes);
  var count = data.getUint16(6, Endian.little);
  var at = 8;
  for (var t = 0; t < count && at < bytes.length; t++) {
    var length = bytes[at++];
    var name = utf8.decode(bytes.sublist(at, at + length));
    at += length;
    var n = bytes[at++];
    var size = n * n * n;
    if (n < 2 || n > maxCubeSize || at + size * 3 > bytes.length) break;
    var rgb = Uint8List(size * 3);
    for (var channel = 0; channel < 3; channel++) {
      var before = 0;
      for (var i = 0; i < size; i++) {
        if (i % n == 0) before = 0;
        before = (before + bytes[at + channel * size + i]) & 255;
        rgb[i * 3 + channel] = before;
      }
    }
    at += size * 3;
    out[name] = ColourCube(n, rgb);
  }
  return out;
}

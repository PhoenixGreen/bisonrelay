import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// image_adjustment.dart is what an adjustment layer does to the layers under
// it: a grade, a curve, a colour kept while the rest goes grey. Drawn by
// shaders/adjust.frag -- see adjust_painter.dart.
//
// Each kind lists its own settings as AdjustParams, so the panel is built
// from the list and a saved document holds only the settings that were
// moved: a name and a number each, readable in the file.

/// AdjustParam is one number an adjustment is set by.
class AdjustParam {
  final String key;
  final String label;
  final double min, max, initial;
  final int decimals;

  /// percent shows it a hundred times bigger than it is kept: a fraction
  /// read and typed as a percentage.
  final bool percent;

  const AdjustParam(this.key, this.label, this.min, this.max, this.initial,
      {this.decimals = 0, this.percent = true});
}

/// AdjustKind is what an adjustment layer does. The shader's mode is the
/// kind's [mode], not its index, so the list can be put in a sensible order
/// for reading and grow in the middle.
enum AdjustKind {
  brightness("Brightness and contrast", 0, [
    AdjustParam("brightness", "Brightness", -1, 1, 0),
    AdjustParam("contrast", "Contrast", -1, 1, 0),
  ]),
  levels("Levels", 1, [
    AdjustParam("inBlack", "Black in", 0, 1, 0),
    AdjustParam("inWhite", "White in", 0, 1, 1),
    AdjustParam("gamma", "Midtones", 0.1, 4, 1, decimals: 2, percent: false),
    AdjustParam("outBlack", "Black out", 0, 1, 0),
    AdjustParam("outWhite", "White out", 0, 1, 1),
  ]),
  curves("Curves", 2, []),
  exposure("Exposure", 10, [
    AdjustParam("stops", "Stops", -5, 5, 0, decimals: 2, percent: false),
    AdjustParam("offset", "Offset", -0.5, 0.5, 0),
    AdjustParam("gamma", "Gamma", 0.1, 4, 1, decimals: 2, percent: false),
  ]),
  hueSaturation("Hue and saturation", 3, [
    AdjustParam("hue", "Hue", -180, 180, 0, percent: false),
    AdjustParam("saturation", "Saturation", -1, 1, 0),
    AdjustParam("lightness", "Lightness", -1, 1, 0),
  ]),
  vibrance("Vibrance", 4, [
    AdjustParam("vibrance", "Vibrance", -1, 1, 0),
    AdjustParam("saturation", "Saturation", -1, 1, 0),
  ]),
  temperature("Warmth and tint", 5, [
    AdjustParam("warmth", "Warmth", -1, 1, 0),
    AdjustParam("tint", "Tint", -1, 1, 0),
  ]),
  photoFilter("Photo filter", 6, [
    AdjustParam("density", "Density", 0, 1, 0.25),
  ]),
  keepColour("Keep one colour", 7, [
    AdjustParam("width", "Range", 0, 0.5, 0.06),
    AdjustParam("softness", "Softness", 0, 0.5, 0.06),
    AdjustParam("amount", "Grey the rest", 0, 1, 1),
  ]),
  blackWhite("Black and white", 8, [
    AdjustParam("red", "Reds", -2, 3, 0.3),
    AdjustParam("green", "Greens", -2, 3, 0.59),
    AdjustParam("blue", "Blues", -2, 3, 0.11),
    AdjustParam("tint", "Tint", 0, 1, 0),
  ]),
  gradientMap("Gradient map", 9, []),
  posterise("Posterise", 11, [
    AdjustParam("levels", "Levels", 2, 32, 4, percent: false),
  ]),
  threshold("Threshold", 12, [
    AdjustParam("level", "Level", 0, 1, 0.5),
  ]),
  invert("Invert", 13, []);

  final String label;
  final int mode;
  final List<AdjustParam> params;
  const AdjustKind(this.label, this.mode, this.params);

  static AdjustKind fromName(String? name) => values.firstWhere(
      (k) => k.name == name,
      orElse: () => AdjustKind.hueSaturation);

  /// usesColour is whether the kind is set by a colour as well as numbers:
  /// a photo filter's, the one colour kept, a black and white's tint.
  bool get usesColour =>
      this == photoFilter || this == keepColour || this == blackWhite;
}

/// CurveChannel is which curve of the four is meant: all three channels at
/// once, or one of them.
enum CurveChannel {
  rgb("RGB"),
  red("Red"),
  green("Green"),
  blue("Blue");

  final String label;
  const CurveChannel(this.label);
}

/// ImageAdjustment is one adjustment layer's settings.
class ImageAdjustment {
  final AdjustKind kind;

  /// values are the numbers moved from where the kind starts them.
  final Map<String, double> values;

  /// colour is a photo filter's colour, the colour a "keep one colour"
  /// keeps, and a black and white's tint.
  final Color colour;

  /// fade is a gradient map's gradient: dark to light.
  final PaintSpec fade;

  /// curves are each channel's curve, points 0 to 1 across and up, sorted
  /// across. An absent channel is the straight line.
  final Map<CurveChannel, List<Offset>> curves;

  const ImageAdjustment({
    this.kind = AdjustKind.hueSaturation,
    this.values = const {},
    this.colour = const Color(0xFFF2B33D),
    this.fade = const PaintSpec(Color(0xFF14213D),
        gradient: GradientSpec(to: Color(0xFFF2D06B))),
    this.curves = const {},
  });

  /// value is the setting [key] as it is, or as the kind starts it.
  double value(String key) {
    var given = values[key];
    if (given != null) return given;
    for (var p in kind.params) {
      if (p.key == key) return p.initial;
    }
    return 0;
  }

  /// curve is [channel]'s curve, the straight line where it has none.
  List<Offset> curve(CurveChannel channel) =>
      curves[channel] ?? const [Offset(0, 0), Offset(1, 1)];

  ImageAdjustment copyWith({
    AdjustKind? kind,
    Map<String, double>? values,
    Color? colour,
    PaintSpec? fade,
    Map<CurveChannel, List<Offset>>? curves,
  }) =>
      ImageAdjustment(
        kind: kind ?? this.kind,
        values: values ?? this.values,
        colour: colour ?? this.colour,
        fade: fade ?? this.fade,
        curves: curves ?? this.curves,
      );

  /// withValue is this with [key] set to [v], within its kind's range.
  ImageAdjustment withValue(String key, double v) {
    for (var p in kind.params) {
      if (p.key == key) v = v.clamp(p.min, p.max).toDouble();
    }
    return copyWith(values: {...values, key: v});
  }

  /// withCurve is this with [channel]'s curve set to [points], sorted and
  /// held to the square.
  ImageAdjustment withCurve(CurveChannel channel, List<Offset> points) {
    var sorted = [
      for (var p in points)
        Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0))
    ]..sort((a, b) => a.dx.compareTo(b.dx));
    return copyWith(curves: {...curves, channel: sorted});
  }

  Map<String, dynamic> toJson() => {
        "k": kind.name,
        if (values.isNotEmpty) "v": values,
        if (kind.usesColour) "c": colorToJson(colour),
        if (kind == AdjustKind.gradientMap) "fade": fade.toJson(),
        if (curves.isNotEmpty)
          "curves": {
            for (var e in curves.entries)
              e.key.name: [
                for (var p in e.value) ...[p.dx, p.dy]
              ]
          },
      };

  factory ImageAdjustment.fromJson(Map<String, dynamic> json) {
    var values = <String, double>{};
    if (json["v"] case Map raw) {
      for (var e in raw.entries) {
        if (e.key is String && e.value is num) {
          values[e.key as String] = (e.value as num).toDouble();
        }
      }
    }
    var curves = <CurveChannel, List<Offset>>{};
    if (json["curves"] case Map raw) {
      for (var e in raw.entries) {
        var channel = CurveChannel.values
            .where((c) => c.name == e.key)
            .firstOrNull;
        if (channel == null || e.value is! List) continue;
        var flat = e.value as List;
        var points = <Offset>[];
        for (var i = 0; i + 1 < flat.length; i += 2) {
          if (flat[i] is num && flat[i + 1] is num) {
            points.add(Offset(
                (flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble()));
          }
        }
        if (points.length >= 2) curves[channel] = points;
      }
    }
    return ImageAdjustment(
      kind: AdjustKind.fromName(json["k"] as String?),
      values: values,
      colour: colorFromJson(json["c"], const Color(0xFFF2B33D)),
      fade: json["fade"] == null
          ? const ImageAdjustment().fade
          : PaintSpec.fromJson(json["fade"], const Color(0xFF14213D)),
      curves: curves,
    );
  }
}

/// curveAt is [points]'s curve at [x]: a smooth curve through every point
/// that never overshoots between two of them -- Fritsch and Carlson's
/// monotone cubic, the curve an image editor draws -- so a gentle S stays an
/// S and never rings into the shadows.
double curveAt(List<Offset> points, double x) {
  if (points.isEmpty) return x;
  if (points.length == 1) return points.single.dy;
  if (x <= points.first.dx) return points.first.dy;
  if (x >= points.last.dx) return points.last.dy;
  var n = points.length;
  var slopes = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    var dx = points[i + 1].dx - points[i].dx;
    slopes[i] = dx <= 0 ? 0 : (points[i + 1].dy - points[i].dy) / dx;
  }
  var tangents = List<double>.filled(n, 0);
  tangents[0] = slopes[0];
  tangents[n - 1] = slopes[n - 2];
  for (var i = 1; i < n - 1; i++) {
    tangents[i] = slopes[i - 1] * slopes[i] <= 0
        ? 0
        : (slopes[i - 1] + slopes[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (slopes[i] == 0) {
      tangents[i] = 0;
      tangents[i + 1] = 0;
      continue;
    }
    var a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i];
    var h = math.sqrt(a * a + b * b);
    if (h > 3) {
      tangents[i] = 3 / h * a * slopes[i];
      tangents[i + 1] = 3 / h * b * slopes[i];
    }
  }
  var i = 0;
  while (i < n - 2 && x > points[i + 1].dx) {
    i++;
  }
  var p0 = points[i], p1 = points[i + 1];
  var h = p1.dx - p0.dx;
  if (h <= 0) return p0.dy;
  var t = (x - p0.dx) / h;
  var t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * p0.dy +
      (t3 - 2 * t2 + t) * h * tangents[i] +
      (-2 * t3 + 3 * t2) * p1.dy +
      (t3 - t2) * h * tangents[i + 1];
}

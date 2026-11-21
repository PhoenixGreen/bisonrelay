import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';

// image_adjustment.dart is what an adjustment layer does to the layers under
// it, drawn by shaders/adjust.frag (see adjust_painter.dart). Each kind lists
// its settings as AdjustParams, so the panel is built from the list and a
// document holds only the settings that were moved.

class AdjustParam {
  final String key;
  final String label;
  final double min, max, initial;
  final int decimals;

  /// percent is whether the stored fraction is shown and typed as a percent.
  final bool percent;

  const AdjustParam(this.key, this.label, this.min, this.max, this.initial,
      {this.decimals = 0, this.percent = true});
}

/// AdjustKind is what an adjustment layer does. The shader is told [mode],
/// not the index, so the list can be reordered and grow in the middle.
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
  shadowsHighlights("Shadows and highlights", 17, [
    AdjustParam("shadows", "Shadows", 0, 1, 0.35),
    AdjustParam("highlights", "Highlights", 0, 1, 0),
    AdjustParam("radius", "Radius", 1, 200, 30, percent: false),
  ]),
  clarity("Clarity and haze", 18, [
    AdjustParam("clarity", "Clarity", -1, 1, 0.3),
    AdjustParam("dehaze", "Clear haze", -1, 1, 0),
    AdjustParam("radius", "Radius", 1, 200, 40, percent: false),
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
  colourMixer("Colour mixer", 16, [
    AdjustParam("redHue", "Red hue", -1, 1, 0),
    AdjustParam("redSat", "Red saturation", -1, 1, 0),
    AdjustParam("redLum", "Red lightness", -1, 1, 0),
    AdjustParam("orangeHue", "Orange hue", -1, 1, 0),
    AdjustParam("orangeSat", "Orange saturation", -1, 1, 0),
    AdjustParam("orangeLum", "Orange lightness", -1, 1, 0),
    AdjustParam("yellowHue", "Yellow hue", -1, 1, 0),
    AdjustParam("yellowSat", "Yellow saturation", -1, 1, 0),
    AdjustParam("yellowLum", "Yellow lightness", -1, 1, 0),
    AdjustParam("greenHue", "Green hue", -1, 1, 0),
    AdjustParam("greenSat", "Green saturation", -1, 1, 0),
    AdjustParam("greenLum", "Green lightness", -1, 1, 0),
    AdjustParam("aquaHue", "Aqua hue", -1, 1, 0),
    AdjustParam("aquaSat", "Aqua saturation", -1, 1, 0),
    AdjustParam("aquaLum", "Aqua lightness", -1, 1, 0),
    AdjustParam("blueHue", "Blue hue", -1, 1, 0),
    AdjustParam("blueSat", "Blue saturation", -1, 1, 0),
    AdjustParam("blueLum", "Blue lightness", -1, 1, 0),
    AdjustParam("purpleHue", "Purple hue", -1, 1, 0),
    AdjustParam("purpleSat", "Purple saturation", -1, 1, 0),
    AdjustParam("purpleLum", "Purple lightness", -1, 1, 0),
    AdjustParam("magentaHue", "Magenta hue", -1, 1, 0),
    AdjustParam("magentaSat", "Magenta saturation", -1, 1, 0),
    AdjustParam("magentaLum", "Magenta lightness", -1, 1, 0),
  ]),
  temperature("Warmth and tint", 5, [
    AdjustParam("warmth", "Warmth", -1, 1, 0),
    AdjustParam("tint", "Tint", -1, 1, 0),
  ]),
  colourBalance("Colour balance", 15, [
    AdjustParam("shadowsRed", "Shadows: cyan to red", -1, 1, 0),
    AdjustParam("shadowsGreen", "Shadows: magenta to green", -1, 1, 0),
    AdjustParam("shadowsBlue", "Shadows: yellow to blue", -1, 1, 0),
    AdjustParam("midsRed", "Midtones: cyan to red", -1, 1, 0),
    AdjustParam("midsGreen", "Midtones: magenta to green", -1, 1, 0),
    AdjustParam("midsBlue", "Midtones: yellow to blue", -1, 1, 0),
    AdjustParam("highsRed", "Highlights: cyan to red", -1, 1, 0),
    AdjustParam("highsGreen", "Highlights: magenta to green", -1, 1, 0),
    AdjustParam("highsBlue", "Highlights: yellow to blue", -1, 1, 0),
  ]),
  channelMixer("Channel mixer", 14, [
    AdjustParam("rr", "Red from Red", -2, 2, 1),
    AdjustParam("rg", "Red from Green", -2, 2, 0),
    AdjustParam("rb", "Red from Blue", -2, 2, 0),
    AdjustParam("gr", "Green from Red", -2, 2, 0),
    AdjustParam("gg", "Green from Green", -2, 2, 1),
    AdjustParam("gb", "Green from Blue", -2, 2, 0),
    AdjustParam("br", "Blue from Red", -2, 2, 0),
    AdjustParam("bg", "Blue from Green", -2, 2, 0),
    AdjustParam("bb", "Blue from Blue", -2, 2, 1),
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
  invert("Invert", 13, []),
  colourTable("Colour table", 27, [
    AdjustParam("amount", "Strength", 0, 1, 1),
  ]),
  sharpen("Sharpen", 19, [
    AdjustParam("amount", "Amount", 0, 3, 0.8),
    AdjustParam("radius", "Radius", 0.5, 20, 1.5, decimals: 1, percent: false),
  ]),
  highPass("High pass", 20, [
    AdjustParam("radius", "Radius", 0.5, 100, 3, decimals: 1, percent: false),
    AdjustParam("strength", "Strength", 0, 4, 1),
  ]),
  noise("Noise", 21, [
    AdjustParam("amount", "Amount", 0, 1, 0.15),
    AdjustParam("colourful", "Colour", 0, 1, 0),
    AdjustParam("size", "Size", 0.5, 20, 1, decimals: 1, percent: false),
  ]),
  pixelate("Pixelate", 22, [
    AdjustParam("cell", "Cell", 2, 200, 20, percent: false),
  ]),
  findEdges("Find edges", 23, [
    AdjustParam("strength", "Strength", 0, 4, 1),
    AdjustParam("width", "Width", 0.5, 20, 1, decimals: 1, percent: false),
    AdjustParam("colour", "Colour", 0, 1, 1),
  ]),
  emboss("Emboss", 24, [
    AdjustParam("angle", "Angle", 0, 360, 135, percent: false),
    AdjustParam("height", "Height", 0.5, 20, 2, decimals: 1, percent: false),
    AdjustParam("amount", "Amount", 0, 4, 1),
    AdjustParam("colour", "Colour", 0, 1, 0),
  ]),
  oilPaint("Oil paint", 25, [
    AdjustParam("radius", "Brush", 1, 100, 14, percent: false),
  ]),
  ripple("Ripple", 26, [
    AdjustParam("amount", "Amount", 0, 100, 10, percent: false),
    AdjustParam("wavelength", "Wavelength", 5, 500, 60, percent: false),
    AdjustParam("angle", "Angle", 0, 360, 0, percent: false),
  ]);

  final String label;
  final int mode;
  final List<AdjustParam> params;
  const AdjustKind(this.label, this.mode, this.params);

  static AdjustKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name,
          orElse: () => AdjustKind.hueSaturation);

  /// neighbours is whether the kind reads the pixels round each one, not
  /// only the one: such a kind's sizes are thousandths of the frame's
  /// shorter side, so it looks the same however large it is drawn.
  bool get neighbours => switch (this) {
        shadowsHighlights ||
        clarity ||
        sharpen ||
        highPass ||
        pixelate ||
        findEdges ||
        emboss ||
        oilPaint ||
        ripple =>
          true,
        _ => false,
      };

  /// usesColour is whether the kind is set by a colour as well as numbers:
  /// a photo filter's, the one colour kept, a black and white's tint.
  bool get usesColour =>
      this == photoFilter || this == keepColour || this == blackWhite;
}

/// MixerBand is one of the colour mixer's colours: its name, and the hue
/// it sits at, in degrees.
class MixerBand {
  final String key;
  final String label;
  final double hue;
  const MixerBand(this.key, this.label, this.hue);
}

const mixerBands = [
  MixerBand("red", "Red", 0),
  MixerBand("orange", "Orange", 30),
  MixerBand("yellow", "Yellow", 60),
  MixerBand("green", "Green", 120),
  MixerBand("aqua", "Aqua", 180),
  MixerBand("blue", "Blue", 240),
  MixerBand("purple", "Purple", 270),
  MixerBand("magenta", "Magenta", 300),
];

/// mixerAt is what the colour mixer [a] does at hue [hue] (0 to 1): the hue
/// turned by (degrees), the saturation times, the lightness moved by --
/// each band's setting, shared with its neighbours between them.
(double, double, double) mixerAt(ImageAdjustment a, double hue) {
  var deg = (hue % 1) * 360;
  var n = mixerBands.length;
  for (var i = 0; i < n; i++) {
    var from = mixerBands[i], to = mixerBands[(i + 1) % n];
    var span = (to.hue - from.hue + 360) % 360;
    var into = (deg - from.hue + 360) % 360;
    if (into > span) continue;
    var t = span == 0 ? 0.0 : into / span;
    // Eased, so a band's own hue takes its setting whole.
    t = t * t * (3 - 2 * t);
    double mix(String suffix) =>
        a.value("${from.key}$suffix") * (1 - t) +
        a.value("${to.key}$suffix") * t;
    return (mix("Hue") * 30, 1 + mix("Sat"), mix("Lum"));
  }
  return (0, 1, 0);
}

/// CurveChannel is which curve: all three channels at once, or one.
enum CurveChannel {
  rgb("RGB"),
  red("Red"),
  green("Green"),
  blue("Blue");

  final String label;
  const CurveChannel(this.label);
}

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

  /// table is a colour table's: one of the app's film tables by name
  /// (presets/film_tables.dart), or empty for [cube].
  final String table;

  /// cube is a colour table read in from a file, kept with the adjustment
  /// so it goes wherever the picture goes.
  final ColourCube? cube;

  /// tableName is what a table read in called itself.
  final String tableName;

  const ImageAdjustment({
    this.kind = AdjustKind.hueSaturation,
    this.values = const {},
    this.colour = const Color(0xFFF2B33D),
    this.fade = const PaintSpec(Color(0xFF14213D),
        gradient: GradientSpec(to: Color(0xFFF2D06B))),
    this.curves = const {},
    this.table = "",
    this.cube,
    this.tableName = "",
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = ImageAdjustment();

  /// value is setting [key] as it is, or as the kind starts it.
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
    String? table,
    ColourCube? cube,
    bool clearCube = false,
    String? tableName,
  }) =>
      ImageAdjustment(
        kind: kind ?? this.kind,
        values: values ?? this.values,
        colour: colour ?? this.colour,
        fade: fade ?? this.fade,
        curves: curves ?? this.curves,
        table: table ?? this.table,
        cube: clearCube ? null : cube ?? this.cube,
        tableName: tableName ?? this.tableName,
      );

  /// withValue is this with [key] set to [v], within its kind's range.
  ImageAdjustment withValue(String key, double v) {
    for (var p in kind.params) {
      if (p.key == key) v = v.clamp(p.min, p.max).toDouble();
    }
    return copyWith(values: {...values, key: v});
  }

  /// withCurve is this with [channel]'s curve [points], sorted, in the square.
  ImageAdjustment withCurve(CurveChannel channel, List<Offset> points) {
    var sorted = [
      for (var p in points) Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0))
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
        if (kind == AdjustKind.colourTable && table.isNotEmpty) "table": table,
        if (kind == AdjustKind.colourTable && cube != null)
          "cube": cube!.toJson(),
        if (kind == AdjustKind.colourTable && tableName.isNotEmpty)
          "tableName": tableName,
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
        var channel =
            CurveChannel.values.where((c) => c.name == e.key).firstOrNull;
        if (channel == null || e.value is! List) continue;
        var flat = e.value as List;
        // On the unit square, left to right, and only so many: a curve is
        // sampled a thousand times to be drawn, each sample a walk along it.
        var points = <Offset>[];
        for (var i = 0; i + 1 < flat.length && points.length < 64; i += 2) {
          if (flat[i] is num && flat[i + 1] is num) {
            points.add(Offset((flat[i] as num).toDouble().clamp(0.0, 1.0),
                (flat[i + 1] as num).toDouble().clamp(0.0, 1.0)));
          }
        }
        points.sort((a, b) => a.dx.compareTo(b.dx));
        if (points.length >= 2) curves[channel] = points;
      }
    }
    return ImageAdjustment(
      kind: AdjustKind.fromName(jsonStr(json["k"])),
      values: values,
      colour: colorFromJson(json["c"], _defaults.colour),
      fade: json["fade"] == null
          ? const ImageAdjustment().fade
          : PaintSpec.fromJson(json["fade"], const Color(0xFF14213D)),
      curves: curves,
      table: jsonString(json["table"], _defaults.table),
      cube: ColourCube.fromJson(json["cube"]),
      tableName: _short(jsonString(json["tableName"], _defaults.tableName)),
    );
  }
}

String _short(String s) => s.length <= 80 ? s : s.substring(0, 80);

/// curveAt is [points]'s curve at [x]: Fritsch-Carlson monotone cubic, so
/// it never overshoots between two points.
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
    tangents[i] =
        slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2;
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

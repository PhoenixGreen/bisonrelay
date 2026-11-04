import 'dart:ui';

// canvas_geometry.dart is the one place that answers "how big is this
// document, really".
//
// A canvas has two sizes. The *design size* is the coordinate space every
// element's x, y, width and height are written in. The *export size* is how
// many pixels come out. Keeping them apart makes a canvas resolution
// independent: the same document renders at any width without resampling.

/// CanvasRatio is the shape of the canvas. [custom] is the only value that
/// reads [CanvasSize.customRatio].
enum CanvasRatio {
  wide("16:9", 16 / 9),
  tall("9:16", 9 / 16),
  classic("4:3", 4 / 3),
  portrait("3:4", 3 / 4),
  square("1:1", 1),

  // The tallest shape a feed shows without cropping.
  feedAd("4:5 · Feed ad", 4 / 5),
  banner("21:9", 21 / 9),
  wideBanner("3:1", 3),

  // Print shapes, named for what they are for.
  poster("2:3 · Poster", 2 / 3),
  photo("3:2 · Photo print", 3 / 2),
  wideStrip("5:2 · Banner", 5 / 2),

  // Paper. A3, A4 and A5 are one shape; they differ only in width.
  a4("A4 · A3 · A5", 210 / 297),
  a4Wide("A4 landscape", 297 / 210),
  custom("Custom", 16 / 9);

  /// isPaper is whether this shape is a page rather than a screen, which
  /// changes the default frame rate: see defaultFrameRateFor.
  bool get isPaper => this == a4 || this == a4Wide;

  /// label is what the dropdown shows.
  final String label;

  /// value is width divided by height. For [custom] this is only the value
  /// used until the document says otherwise.
  final double value;

  const CanvasRatio(this.label, this.value);

  static CanvasRatio fromName(String? name) => values.firstWhere(
        (r) => r.name == name,
        orElse: () => CanvasRatio.wide,
      );
}

/// CanvasSizePreset is a named size: a shape and a width together, since a
/// name like "1080p" is true of one shape only.
class CanvasSizePreset {
  final CanvasRatio ratio;
  final int width;

  /// label is what it is called, without the number (the dropdown adds the
  /// pixels).
  final String label;

  const CanvasSizePreset(this.ratio, this.width, this.label);

  /// height is this preset's height in pixels.
  int get height => (width / ratio.value).round();
}

/// canvasSizePresets are the sizes worth having a name for, by shape: the
/// usual screen sizes, and paper at 150 and 300 dots to the inch.
const List<CanvasSizePreset> canvasSizePresets = [
  CanvasSizePreset(CanvasRatio.wide, 3840, "4K"),
  CanvasSizePreset(CanvasRatio.wide, 2560, "1440p"),
  CanvasSizePreset(CanvasRatio.wide, 1920, "1080p"),
  CanvasSizePreset(CanvasRatio.wide, 1280, "720p"),
  CanvasSizePreset(CanvasRatio.wide, 854, "480p"),

  CanvasSizePreset(CanvasRatio.tall, 1080, "1080p portrait"),
  CanvasSizePreset(CanvasRatio.tall, 720, "720p portrait"),

  CanvasSizePreset(CanvasRatio.square, 2048, "Large square"),
  CanvasSizePreset(CanvasRatio.square, 1080, "Square post"),

  CanvasSizePreset(CanvasRatio.classic, 2048, "Large"),
  CanvasSizePreset(CanvasRatio.classic, 1024, "Standard"),
  CanvasSizePreset(CanvasRatio.portrait, 1536, "Large"),
  CanvasSizePreset(CanvasRatio.portrait, 1024, "Standard"),

  CanvasSizePreset(CanvasRatio.banner, 2560, "Wide banner"),
  CanvasSizePreset(CanvasRatio.banner, 1500, "Header"),
  CanvasSizePreset(CanvasRatio.wideBanner, 1500, "Header"),

  // Paper, by the width of the sheet. A3 at 300dpi is the largest within
  // maxCanvasWidth.
  CanvasSizePreset(CanvasRatio.a4, 3508, "A3 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4, 2480, "A4 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4, 1754, "A3 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4, 1240, "A4 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4, 874, "A5 at 150dpi"),
  // Landscape: the long edge is the width.
  CanvasSizePreset(CanvasRatio.a4Wide, 3508, "A4 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 2480, "A3 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 1754, "A4 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 1240, "A5 at 150dpi"),
];

/// sizePresetsFor is the named sizes that belong to one shape; empty for a
/// custom ratio.
List<CanvasSizePreset> sizePresetsFor(CanvasRatio ratio) => [
      for (var p in canvasSizePresets)
        if (p.ratio == ratio) p
    ];

/// canvasFrameRates are the rates offered in the settings bar; its Custom
/// entry takes any other.
const List<int> canvasFrameRates = [1, 12, 24, 30, 60];

/// a4PageWidth is how many pixels across one A4 page is by default: 150
/// dots to the inch. 300dpi is four times the pixels for every page, so it
/// is left for whoever prints to raise.
const int a4PageWidth = 1240;

/// minFrameRate and maxFrameRate bound a rate typed by hand.
const int minFrameRate = 1;
const int maxFrameRate = 120;

/// defaultFrameRateFor is the rate a new canvas of [ratio] starts at: one
/// for paper, 24 for a screen.
int defaultFrameRateFor(CanvasRatio ratio) => ratio.isPaper ? 1 : 24;

/// minCanvasWidth and maxCanvasWidth bound the design and export widths.
/// The ceiling is set by the size limit on a chat or post payload: a much
/// wider PNG would be refused after the wait to encode it.
const int minCanvasWidth = 64;
const int maxCanvasWidth = 4096;

/// defaultCanvasWidth is what a new document starts at.
const int defaultCanvasWidth = 1280;

/// CanvasSize is a ratio and a width, and the height that follows from them
/// (derived, never stored, so it cannot drift from the ratio).
class CanvasSize {
  final CanvasRatio ratio;

  /// width is the width of the design space. It does not change with
  /// [exportWidth] while [scalesDesign] is on, so publishing larger gives the
  /// same picture with more pixels.
  final int width;

  /// exportWidth is the published width in pixels; equal to [width] for a
  /// canvas saved before the two were separate.
  final int exportWidth;

  /// scalesDesign is what changing [exportWidth] does. On, it is a
  /// resolution: the scene is scaled on the way out. Off, it is a page: the
  /// design width follows the export width, so there is more room around the
  /// design at the same scale.
  final bool scalesDesign;

  /// customRatio is width/height when [ratio] is [CanvasRatio.custom], and
  /// ignored otherwise.
  final double customRatio;

  const CanvasSize({
    this.ratio = CanvasRatio.wide,
    this.width = defaultCanvasWidth,
    int? exportWidth,
    this.scalesDesign = true,
    this.customRatio = 16 / 9,
  }) : exportWidth = exportWidth ?? width;

  double get aspect => ratio == CanvasRatio.custom ? customRatio : ratio.value;

  /// height is the design height, rounded rather than truncated: truncating
  /// leaves a half-pixel of background along the bottom of an export.
  int get height => (width / aspect).round().clamp(1, 1 << 20);

  /// exportHeight is the same arithmetic on the published width.
  int get exportHeight => (exportWidth / aspect).round().clamp(1, 1 << 20);

  /// size is the design space, which everything in the editor works in.
  Size get size => Size(width.toDouble(), height.toDouble());

  /// exportSize is what comes out: the design at [exportScale].
  Size get exportSize => Size(exportWidth.toDouble(), exportHeight.toDouble());

  /// exportScale is how much bigger the file is than the design space.
  double get exportScale => width <= 0 ? 1 : exportWidth / width.toDouble();

  Rect get rect => Offset.zero & size;

  /// copyWith keeps the invariant that in page mode (no [scalesDesign]) the
  /// design width is the export width.
  CanvasSize copyWith({
    CanvasRatio? ratio,
    int? width,
    int? exportWidth,
    bool? scalesDesign,
    double? customRatio,
  }) {
    var scales = scalesDesign ?? this.scalesDesign;
    var design = (width ?? this.width).clamp(minCanvasWidth, maxCanvasWidth);
    var out =
        (exportWidth ?? this.exportWidth).clamp(minCanvasWidth, maxCanvasWidth);
    // Page mode, or a canvas being put into it: the design follows the file.
    if (!scales) design = out;
    return CanvasSize(
      ratio: ratio ?? this.ratio,
      width: design,
      exportWidth: out,
      scalesDesign: scales,
      customRatio: customRatio ?? this.customRatio,
    );
  }

  Map<String, dynamic> toJson() => {
        "ratio": ratio.name,
        "width": width,
        if (exportWidth != width) "exportWidth": exportWidth,
        if (!scalesDesign) "pageGrows": true,
        if (ratio == CanvasRatio.custom) "customRatio": customRatio,
      };

  factory CanvasSize.fromJson(Map<String, dynamic> json) {
    num? n(Object? v) => v is num && v.isFinite ? v : null;
    var width =
        n(json["width"])?.round().clamp(minCanvasWidth, maxCanvasWidth) ??
            defaultCanvasWidth;
    var ratio = json["ratio"];
    return CanvasSize(
      ratio: CanvasRatio.fromName(ratio is String ? ratio : null),
      width: width,
      // The design width itself for anything saved before the two were told
      // apart: it was laid out in the space it was published at.
      exportWidth: n(json["exportWidth"])
              ?.round()
              .clamp(minCanvasWidth, maxCanvasWidth) ??
          width,
      scalesDesign: json["pageGrows"] != true,
      // Within the Aspect field's range: nought would make the height infinite,
      // and a sliver a page millions of pixels tall.
      customRatio:
          n(json["customRatio"])?.toDouble().clamp(0.05, 20.0) ?? 16 / 9,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasSize &&
      other.ratio == ratio &&
      other.width == width &&
      other.exportWidth == exportWidth &&
      other.scalesDesign == scalesDesign &&
      other.customRatio == customRatio;

  @override
  int get hashCode =>
      Object.hash(ratio, width, exportWidth, scalesDesign, customRatio);
}

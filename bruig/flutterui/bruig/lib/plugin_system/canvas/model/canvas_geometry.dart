import 'dart:ui';

// canvas_geometry.dart is the one place that answers "how big is this
// document, really".
//
// A canvas has two sizes and they are deliberately not the same thing. The
// *design size* is the coordinate space every element's x, y, width and
// height are written in -- it is what the user drags things around in, and
// it never changes while a document is open. The *export size* is how many
// pixels come out the other end, and it is the design size scaled by
// whatever the publish dialog asked for.
//
// Keeping them separate is what makes a canvas resolution independent. Every
// element is a shape and a number, never a bitmap, so the same document
// renders at 800px for a chat message and 2400px for a poster without
// anything being resampled. It is also why the pitch, the charts and the
// procedural backgrounds are all drawn rather than shipped as images.

/// CanvasRatio is the shape of the canvas.
///
/// A fixed list rather than two free numbers, because the ratio is a decision
/// about where the work is going -- a chat message, a story, a banner -- and
/// those have conventional shapes. [custom] is the escape hatch and is the
/// only value that reads [CanvasSize.customRatio].
enum CanvasRatio {
  wide("16:9", 16 / 9),
  tall("9:16", 9 / 16),
  classic("4:3", 4 / 3),
  portrait("3:4", 3 / 4),
  square("1:1", 1),
  banner("21:9", 21 / 9),
  wideBanner("3:1", 3),

  // Print shapes, named for what they are for rather than for their numbers:
  // somebody looking for a poster is not looking for 2:3.
  poster("2:3 · Poster", 2 / 3),
  photo("3:2 · Photo print", 3 / 2),
  wideStrip("5:2 · Banner", 5 / 2),

  // Paper. A3, A4 and A5 are the same shape -- halving an A-size folds it in
  // half, which is the whole point of the series -- so they are one ratio and
  // the difference between them is a width. The names are all in the label
  // because that is what somebody looking for A4 will read.
  a4("A4 · A3 · A5", 210 / 297),
  a4Wide("A4 landscape", 297 / 210),
  custom("Custom", 16 / 9);

  /// isPaper is whether this shape is a page rather than a screen.
  ///
  /// Worth asking because the answer changes what the rest of the document
  /// wants: a page is one frame at one frame a second, and a screen is
  /// twenty-four of them. See canvasFrameRates.
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

/// CanvasSizePreset is a named size: a shape and a width together.
///
/// Together, because a width on its own does not name anything. "1080p" is
/// 1920 across *at sixteen by nine*; 1920 across on an A4 page is 1920 by
/// 2716, which is not 1080p and is not any other name either. Offering every
/// width for every shape was offering names that were not true.
class CanvasSizePreset {
  final CanvasRatio ratio;
  final int width;

  /// label is what it is called, without the number: the dropdown adds the
  /// pixels, and the readout beside it says what they come to.
  final String label;

  const CanvasSizePreset(this.ratio, this.width, this.label);

  /// height is what this preset comes to, which is the other half of the name
  /// and is worth showing.
  int get height => (width / ratio.value).round();
}

/// canvasSizePresets are the sizes worth having a name for, by shape.
///
/// The screen sizes people publish at, and the paper sizes at a print
/// resolution -- A4 at 150 dots to the inch is 1240 pixels across, which is
/// what a page looks like on a screen and is small enough to send.
const List<CanvasSizePreset> canvasSizePresets = [
  // Sixteen by nine, which is what "1080p" and the rest of them mean.
  CanvasSizePreset(CanvasRatio.wide, 3840, "4K"),
  CanvasSizePreset(CanvasRatio.wide, 2560, "1440p"),
  CanvasSizePreset(CanvasRatio.wide, 1920, "1080p"),
  CanvasSizePreset(CanvasRatio.wide, 1280, "720p"),
  CanvasSizePreset(CanvasRatio.wide, 854, "480p"),

  // The same sizes stood on end, which is what a phone screen is.
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

  // Paper, by the width of the sheet. A3 at 300 dots to the inch is the
  // largest that fits inside maxCanvasWidth, which is why the list stops
  // there.
  CanvasSizePreset(CanvasRatio.a4, 3508, "A3 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4, 2480, "A4 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4, 1754, "A3 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4, 1240, "A4 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4, 874, "A5 at 150dpi"),
  // Landscape: the same sheets, turned, so the long edge is the width.
  CanvasSizePreset(CanvasRatio.a4Wide, 3508, "A4 at 300dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 2480, "A3 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 1754, "A4 at 150dpi"),
  CanvasSizePreset(CanvasRatio.a4Wide, 1240, "A5 at 150dpi"),
];

/// sizePresetsFor is the named sizes that belong to one shape.
///
/// Empty for a custom ratio, where there is nothing to name: the width box
/// beside the list is the answer for every shape nobody has a word for.
List<CanvasSizePreset> sizePresetsFor(CanvasRatio ratio) => [
      for (var p in canvasSizePresets)
        if (p.ratio == ratio) p
    ];

/// canvasFrameRates are the rates offered in the settings bar, and
/// defaultFrameRateFor is which of them a shape starts at.
///
/// Offered as a short list rather than a number on its own, because the
/// numbers that matter are four: twelve for something light, twenty-four for
/// film, thirty for a screen recording and sixty for something smooth. The
/// box beside the list still takes any other number -- a canvas is somebody
/// else's to make.
const List<int> canvasFrameRates = [1, 12, 24, 30, 60];

/// A page is a page: one frame a second, because a printed sheet has no
/// frames to have a rate between. A screen starts at twenty-four, which is
/// what film runs at and what almost every canvas that moves wants.
int defaultFrameRateFor(CanvasRatio ratio) => ratio.isPaper ? 1 : 24;

/// minCanvasWidth and maxCanvasWidth bound the output width.
///
/// The ceiling is not arbitrary. A canvas is published into a chat or a post,
/// where the whole payload has a hard size limit, and a 8000px PNG would be
/// refused after the user had waited for it to encode. 4096 is generous for
/// anything that ends up on a screen and still encodes in well under a
/// second.
const int minCanvasWidth = 64;
const int maxCanvasWidth = 4096;

/// defaultCanvasWidth is what a new document starts at: large enough to look
/// sharp on a high-density display, small enough that the PNG is a sensible
/// thing to send somebody.
const int defaultCanvasWidth = 1280;

/// CanvasSize is a ratio and a width, and the height that follows from them.
///
/// Immutable and cheap, so it is recomputed rather than cached. The height is
/// derived rather than stored because a stored height is a second source of
/// truth that drifts the moment the ratio changes.
class CanvasSize {
  final CanvasRatio ratio;

  /// width is the width of the space the design is laid out in: where an
  /// element is, how big it is, what a grid line is spaced at.
  ///
  /// Not, on its own, the size of the file that comes out -- see
  /// [exportWidth], and the difference between the two is what this pair
  /// exists for. It stays what it is when the export size changes, which is
  /// what makes publishing at 4K give the same picture with more pixels in it
  /// rather than the same picture in the corner of a bigger one.
  final int width;

  /// exportWidth is the published width in pixels.
  ///
  /// The two used to be one number, and that made it mean two things at once.
  /// Raising it gave the design *more room* -- every element kept its
  /// coordinates and so covered less of a larger page -- while a newly added
  /// element was sized from the canvas and arrived at the new, larger scale.
  /// So the same chart was two sizes on one canvas depending on when it was
  /// put there.
  ///
  /// Equal to [width] for every canvas saved before this existed, so nothing
  /// already made has moved.
  final int exportWidth;

  /// scalesDesign is what changing [exportWidth] does.
  ///
  /// On, it is a resolution: the design is drawn in its own space and the
  /// whole scene is scaled on the way out, so the picture is the same and
  /// there is more of it. Off, it is a page: the design keeps its scale and
  /// there is more room around it, which is what this did before there was a
  /// choice and is right when what somebody wants is a bigger sheet rather
  /// than a sharper one.
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

  /// height is the design height, rounded rather than truncated. A 1281px-wide
  /// 16:9 canvas is 720.5px tall and truncating it puts a half-pixel of
  /// background along the bottom edge of every export.
  int get height => (width / aspect).round().clamp(1, 1 << 20);

  /// exportHeight is the same arithmetic on the published width.
  int get exportHeight => (exportWidth / aspect).round().clamp(1, 1 << 20);

  /// size is the design space, which is what everything in the editor works
  /// in. Only the exporter and the size on the settings band are in published
  /// pixels.
  Size get size => Size(width.toDouble(), height.toDouble());

  /// exportSize is what comes out: the design at [exportScale].
  Size get exportSize => Size(exportWidth.toDouble(), exportHeight.toDouble());

  /// exportScale is how much bigger the file is than the design space. One
  /// for every canvas that has not been given a different export width.
  double get exportScale => width <= 0 ? 1 : exportWidth / width.toDouble();

  Rect get rect => Offset.zero & size;

  /// copyWith keeps the two widths in step where they are meant to move
  /// together.
  ///
  /// The invariant is the type's rather than the caller's: in page mode the
  /// design width *is* the export width, and a caller that set one without
  /// the other would leave a canvas in a state this class says cannot happen.
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
    var width = (json["width"] as num?)?.round().clamp(
              minCanvasWidth,
              maxCanvasWidth,
            ) ??
        defaultCanvasWidth;
    return CanvasSize(
      ratio: CanvasRatio.fromName(json["ratio"] as String?),
      width: width,
      // The design width itself for anything saved before the two were told
      // apart, which is every canvas already made: it was laid out in the
      // space it was published at.
      exportWidth: (json["exportWidth"] as num?)
              ?.round()
              .clamp(minCanvasWidth, maxCanvasWidth) ??
          width,
      scalesDesign: !((json["pageGrows"] as bool?) ?? false),
      customRatio: (json["customRatio"] as num?)?.toDouble() ?? 16 / 9,
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

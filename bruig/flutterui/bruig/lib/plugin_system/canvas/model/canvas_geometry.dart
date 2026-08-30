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
  custom("Custom", 16 / 9);

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

  /// width is the export width in pixels, and also the width of the design
  /// coordinate space. The two being equal is what makes "1 unit is 1 pixel"
  /// true at 100% zoom and 100% export scale, which is the only mental model
  /// worth having.
  final int width;

  /// customRatio is width/height when [ratio] is [CanvasRatio.custom], and
  /// ignored otherwise.
  final double customRatio;

  const CanvasSize({
    this.ratio = CanvasRatio.wide,
    this.width = defaultCanvasWidth,
    this.customRatio = 16 / 9,
  });

  double get aspect => ratio == CanvasRatio.custom ? customRatio : ratio.value;

  /// height is rounded, not truncated. A 1281px-wide 16:9 canvas is 720.5px
  /// tall and truncating it puts a half-pixel of background along the bottom
  /// edge of every export.
  int get height => (width / aspect).round().clamp(1, 1 << 20);

  Size get size => Size(width.toDouble(), height.toDouble());

  Rect get rect => Offset.zero & size;

  CanvasSize copyWith({CanvasRatio? ratio, int? width, double? customRatio}) =>
      CanvasSize(
        ratio: ratio ?? this.ratio,
        width: (width ?? this.width).clamp(minCanvasWidth, maxCanvasWidth),
        customRatio: customRatio ?? this.customRatio,
      );

  Map<String, dynamic> toJson() => {
        "ratio": ratio.name,
        "width": width,
        if (ratio == CanvasRatio.custom) "customRatio": customRatio,
      };

  factory CanvasSize.fromJson(Map<String, dynamic> json) => CanvasSize(
        ratio: CanvasRatio.fromName(json["ratio"] as String?),
        width: (json["width"] as num?)?.round().clamp(
                  minCanvasWidth,
                  maxCanvasWidth,
                ) ??
            defaultCanvasWidth,
        customRatio: (json["customRatio"] as num?)?.toDouble() ?? 16 / 9,
      );

  @override
  bool operator ==(Object other) =>
      other is CanvasSize &&
      other.ratio == ratio &&
      other.width == width &&
      other.customRatio == customRatio;

  @override
  int get hashCode => Object.hash(ratio, width, customRatio);
}

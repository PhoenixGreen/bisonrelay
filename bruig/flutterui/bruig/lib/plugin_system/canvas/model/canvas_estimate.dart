import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_estimate.dart is which file a canvas is meant to become.
//
// Here rather than with the arithmetic that works the size out, because it is
// a decision about the canvas -- "this one is a JPEG at 85" -- and it is
// saved with it. What that costs is export/canvas_export.dart's business; see
// estimateBytes.

/// EstimateAs is the file the size is worked out for.
///
/// The estimate has to name a format or it is not an estimate of anything: the
/// same canvas is four hundred kilobytes as a PNG and forty as a JPEG, and
/// which of those matters depends entirely on what somebody is about to do
/// with it.
enum EstimateAs {
  png("PNG", "Lossless, and see-through where the canvas is"),
  jpeg("JPEG", "Much smaller, and no transparency"),
  webp("WebP", "Smaller again than JPEG at the same quality"),
  gif("GIF", "Every frame, at 256 colours"),
  video("MP4 or WebM", "Every frame, at full colour");

  final String label;
  final String description;
  const EstimateAs(this.label, this.description);

  static EstimateAs fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => png);

  /// lossy is whether the quality setting means anything. PNG packs harder or
  /// less hard and never looks different, so a quality control on one would
  /// be a control that changes the answer to a question nobody asked.
  bool get lossy => this == jpeg || this == webp || this == video;

  /// moving is whether this is a file with every frame in it.
  bool get moving => this == gif || this == video;
}

/// CanvasEstimate is which file the size on the settings band is for.
class CanvasEstimate {
  final EstimateAs format;

  /// quality is 1 to 100, and is what the lossy formats are squeezed to.
  final int quality;

  const CanvasEstimate({this.format = EstimateAs.png, this.quality = 85});

  CanvasEstimate copyWith({EstimateAs? format, int? quality}) => CanvasEstimate(
        format: format ?? this.format,
        quality: quality ?? this.quality,
      );

  Map<String, dynamic> toJson() => {
        if (format != EstimateAs.png) "as": format.name,
        if (quality != 85) "q": quality,
      };

  factory CanvasEstimate.fromJson(Map<String, dynamic> json) => CanvasEstimate(
        format: EstimateAs.fromName(json["as"] as String?),
        quality: jsonInt(json["q"], 85).clamp(1, 100),
      );
}

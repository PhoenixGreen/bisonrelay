import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_estimate.dart is which file a canvas is meant to become, saved with
// the canvas. The size arithmetic is estimateBytes in
// export/canvas_export.dart.

/// EstimateAs is the file format the size estimate is worked out for.
enum EstimateAs {
  png("PNG", "Lossless, and see-through where the canvas is"),
  jpeg("JPEG", "Much smaller, and no transparency"),
  webp("WebP", "Smaller again than JPEG at the same quality"),
  gif("GIF", "Every frame, at 256 colours"),
  video("MP4 or WebM", "Every frame, at full colour"),
  audio("Audio", "The sound alone, as it is set to be written under Audio");

  final String label;
  final String description;
  const EstimateAs(this.label, this.description);

  static EstimateAs fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => png);

  /// lossy is whether the quality setting means anything for this format.
  bool get lossy => this == jpeg || this == webp || this == video;

  /// moving is whether this is a file with every frame in it.
  bool get moving => this == gif || this == video;
}

/// CanvasEstimate is which file the size on the settings band is for.
class CanvasEstimate {
  final EstimateAs format;

  /// quality is 1 to 100, for the lossy formats.
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
        format: EstimateAs.fromName(jsonStr(json["as"])),
        quality: jsonInt(json["q"], 85).clamp(1, 100),
      );
}

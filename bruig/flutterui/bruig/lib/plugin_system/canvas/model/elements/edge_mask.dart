import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// edge_mask.dart is a mask an element's box wears with nothing drawn by hand:
// softened edges and a fade from a side or the middle. It is for moving
// pictures in a box (video, generated patterns); a picture has the full,
// brush-drawn mask in image_mask.dart.

/// EdgeFade is where an edge mask fades the box out.
enum EdgeFade {
  none("None"),
  left("From the left"),
  right("From the right"),
  top("From the top"),
  bottom("From the bottom"),
  sides("Both sides"),
  topBottom("Top and bottom"),
  middle("Round the middle");

  final String label;
  const EdgeFade(this.label);

  static EdgeFade fromName(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => none);
}

/// EdgeMask is an element's box softened and faded.
class EdgeMask {
  /// feather is how soft the edges are, as a share of the box's shorter
  /// side: 0.1 is a tenth of it fading away all round.
  final double feather;

  /// fade is which way it fades, and reach how far in: a share of the box
  /// across the way it fades -- of half of it for the fades from two sides
  /// and from the middle.
  final EdgeFade fade;
  final double reach;

  const EdgeMask(
      {this.feather = 0, this.fade = EdgeFade.none, this.reach = 0.5});

  bool get on => feather > 0 || fade != EdgeFade.none;

  EdgeMask copyWith({double? feather, EdgeFade? fade, double? reach}) =>
      EdgeMask(
          feather: (feather ?? this.feather).clamp(0.0, 0.5),
          fade: fade ?? this.fade,
          reach: (reach ?? this.reach).clamp(0.01, 1.0));

  Map<String, dynamic> toJson() => {
        if (feather > 0) "feather": feather,
        if (fade != EdgeFade.none) "fade": fade.name,
        "reach": reach,
      };

  factory EdgeMask.fromJson(Map<String, dynamic> json) => EdgeMask(
      feather: jsonDouble(json["feather"], 0).clamp(0.0, 0.5),
      fade: EdgeFade.fromName(jsonStr(json["fade"])),
      reach: jsonDouble(json["reach"], 0.5).clamp(0.01, 1.0));
}

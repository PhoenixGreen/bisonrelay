import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// edge_mask.dart is a mask an element's box wears with nothing drawn by
// hand: softened edges and a fade from a side or the middle, for moving
// pictures in a box (video, generated patterns). A picture has the full,
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

class EdgeMask {
  /// feather is how soft the edges are, as a share of the box's shorter
  /// side: 0.1 is a tenth of it fading away all round.
  final double feather;

  /// fade is which way it fades, and reach how far in: a share of the box
  /// across the fade (of half of it for fades from two sides or the middle).
  final EdgeFade fade;
  final double reach;

  const EdgeMask(
      {this.feather = 0, this.fade = EdgeFade.none, this.reach = 0.5});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = EdgeMask();

  bool get on => feather > 0 || fade != EdgeFade.none;

  EdgeMask copyWith({double? feather, EdgeFade? fade, double? reach}) =>
      EdgeMask(
          feather: (feather ?? this.feather).clamp(0.0, 0.5),
          fade: fade ?? this.fade,
          reach: (reach ?? this.reach).clamp(0.01, 1.0));

  Map<String, dynamic> toJson() => {
        if (feather > 0) "feather": feather,
        if (fade != _defaults.fade) "fade": fade.name,
        "reach": reach,
      };

  factory EdgeMask.fromJson(Map<String, dynamic> json) => EdgeMask(
      feather: jsonDouble(json["feather"], _defaults.feather).clamp(0.0, 0.5),
      fade: EdgeFade.fromName(jsonStr(json["fade"])),
      reach: jsonDouble(json["reach"], _defaults.reach).clamp(0.01, 1.0));
}

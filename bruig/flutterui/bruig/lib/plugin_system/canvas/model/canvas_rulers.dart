import 'package:bruig/plugin_system/canvas/model/json_read.dart';

// canvas_rulers.dart is the rulers along the edges of the stage: which edges
// carry one, and whether they show.
//
// They belong to the person editing, not to the canvas: kept in the app's
// preferences (CanvasPreferences.rulers), so a canvas sent to somebody opens
// with that person's rulers, not its sender's. The grid, the guides and what
// snaps to them are the canvas's own: see canvas_guides.dart.

/// CanvasRulers is which edges of the stage carry a ruler (none to begin
/// with), and whether they show.
class CanvasRulers {
  /// shown hides the rulers without forgetting their edges.
  final bool shown;

  final bool top;
  final bool left;
  final bool right;
  final bool bottom;

  const CanvasRulers({
    this.shown = true,
    this.top = false,
    this.left = false,
    this.right = false,
    this.bottom = false,
  });

  /// _defaults is one as made: what a stored one means by leaving a field
  /// out.
  static const _defaults = CanvasRulers();

  /// any is whether an edge is asked for, shown or not.
  bool get any => top || left || right || bottom;

  /// drawn is whether any ruler is drawn: an edge asked for, and the rulers
  /// not hidden.
  bool get drawn => shown && any;

  CanvasRulers copyWith(
          {bool? shown, bool? top, bool? left, bool? right, bool? bottom}) =>
      CanvasRulers(
        shown: shown ?? this.shown,
        top: top ?? this.top,
        left: left ?? this.left,
        right: right ?? this.right,
        bottom: bottom ?? this.bottom,
      );

  /// toJson writes only what differs from rulers as made.
  Map<String, dynamic> toJson() => {
        if (shown != _defaults.shown) "hidden": !shown,
        if (top != _defaults.top) "t": top,
        if (left != _defaults.left) "l": left,
        if (right != _defaults.right) "r": right,
        if (bottom != _defaults.bottom) "b": bottom,
      };

  factory CanvasRulers.fromJson(Map<String, dynamic> json) => CanvasRulers(
        shown: !jsonBool(json["hidden"], !_defaults.shown),
        top: jsonBool(json["t"], _defaults.top),
        left: jsonBool(json["l"], _defaults.left),
        right: jsonBool(json["r"], _defaults.right),
        bottom: jsonBool(json["b"], _defaults.bottom),
      );

  @override
  bool operator ==(Object other) =>
      other is CanvasRulers &&
      other.shown == shown &&
      other.top == top &&
      other.left == left &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(shown, top, left, right, bottom);
}

part of 'scene_renderer.dart';

// A button's painter: its box, lit while the pointer is over it, and its
// label in the room the box leaves. What pressing it does is the
// controller's (ui/controller/button_actions.dart). Part of
// scene_renderer.dart.

/// _paintButton draws [e] in [bounds], with its hover colours where
/// [hovered].
void _paintButton(ui.Canvas canvas, Rect bounds, ButtonElement e, bool hovered,
    CanvasImageSource? images) {
  var box = e.box;
  if (hovered && e.hoverFill.a > 0) box = box.copyWith(fill: e.hoverFill);
  paintBox(canvas, bounds, box, images);

  var spec = e.textSpec;
  if (hovered && e.hoverTextColor.a > 0) {
    spec = spec.copyWith(color: e.hoverTextColor);
  }
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;
  // As typed: the layout puts the words in their case.
  paintTextInBox(canvas, e.label, spec, inner, clip: true);
}

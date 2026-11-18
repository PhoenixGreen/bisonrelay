import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';

// layout_sync.dart keeps docked elements with their Layout: when the whole
// layout is moved, what is docked in it goes with it. Editing the layout
// itself -- a cut dragged or tilted, a gutter widened, a column resized --
// leaves what is docked exactly as it was, never shrunk or cropped: what
// ends up over a cell's edge is hidden by the cell, and shows again when
// the layout is hidden (dockedCell) to be moved back in. Ken, 2026-11-18.

/// layoutsSynced is [now] with every element docked in a layout whose box
/// moved since [was] moved the same way. One moved in the same change is
/// left where it was put.
CanvasDocument layoutsSynced(CanvasDocument was, CanvasDocument now) {
  if (identical(was.elements, now.elements)) return now;
  var next = now;
  for (var e in now.elements) {
    if (e is! LayoutElement) continue;
    var old = was.elementById(e.id);
    if (old is! LayoutElement || identical(old, e)) continue;
    // By its top left: moved, or resized from the top or left.
    var dx = e.x - old.x, dy = e.y - old.y;
    if (dx == 0 && dy == 0) continue;
    var prefix = "${e.id}:";
    for (var el in now.elements) {
      if (!el.base.dock.startsWith(prefix)) continue;
      // Moved by hand in this same change: where it was put stands.
      if (!identical(was.elementById(el.id), el)) continue;
      next = next.withElement(el.withBase(x: el.x + dx, y: el.y + dy));
    }
  }
  return next;
}

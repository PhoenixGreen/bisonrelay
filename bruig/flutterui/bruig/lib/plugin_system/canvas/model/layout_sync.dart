import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';

// layout_sync.dart keeps docked elements with their Layout: when the whole
// layout is moved, what is docked in it goes with it. Editing the layout
// itself -- a cut dragged or tilted, a gutter widened, a column resized --
// leaves what is docked exactly as it was, never shrunk or cropped: what
// ends up over a cell's edge is hidden by the cell, and shows again when
// the layout is hidden (dockedCell) to be moved back in. A cell that goes
// (a preset chosen, a cell removed) lets go of what was docked in it, where
// it is: docked in nothing, it would be neither drawn in a cell nor offered
// as docked, yet still be carried with the layout.

/// layoutsSynced is [now] with every element docked in a layout whose box
/// moved since [was] moved the same way, and every element docked in a cell
/// a layout has lost since [was] let go (_docksLetGo). One moved in the same
/// change is left where it was put.
CanvasDocument layoutsSynced(CanvasDocument was, CanvasDocument now) {
  if (identical(was.elements, now.elements)) return now;
  var next = now;
  for (var e in now.elements) {
    if (e is! LayoutElement) continue;
    var old = was.elementById(e.id);
    if (old is! LayoutElement || identical(old, e)) continue;
    next = _docksLetGo(next, old, e);
    // By its top left: moved, or resized from the top or left.
    var dx = e.x - old.x, dy = e.y - old.y;
    if (dx == 0 && dy == 0) continue;
    var cells = {for (var c in e.shownCells) c.id};
    for (var el in next.elements) {
      var dock = el.base.docked;
      if (dock == null || dock.layout != e.id || !cells.contains(dock.cell)) {
        continue;
      }
      // Moved by hand in this same change: where it was put stands.
      if (!identical(was.elementById(el.id), now.elementById(el.id))) continue;
      next = next.withElement(el.withBase(x: el.x + dx, y: el.y + dy));
    }
  }
  return next;
}

/// _docksLetGo is [doc] with every element docked in a cell layout [was] had
/// and [now] has not (its id gone: a preset chosen, the cell removed)
/// docked in nothing, left where it is.
CanvasDocument _docksLetGo(
    CanvasDocument doc, LayoutElement was, LayoutElement now) {
  var kept = {for (var c in now.shownCells) c.id};
  var gone = {
    for (var c in was.shownCells)
      if (!kept.contains(c.id)) c.id
  };
  if (gone.isEmpty) return doc;
  var next = doc;
  for (var el in doc.elements) {
    var dock = el.base.docked;
    if (dock == null || dock.layout != now.id || !gone.contains(dock.cell)) {
      continue;
    }
    next = next.withElement(el.withBase(dock: "", dockOut: false));
  }
  return next;
}

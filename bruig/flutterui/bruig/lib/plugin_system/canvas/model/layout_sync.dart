import 'dart:ui' show Rect;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';

// layout_sync.dart keeps docked elements in their cells: when a Layout
// changes -- a cut dragged, a column widened, the whole layout moved or
// resized -- each element docked in one of its cells is moved and sized as
// its cell was (ElementBase.dock), keeping its place in the cell.

/// layoutsSynced is [now] with every element docked in a layout that
/// changed since [was] carried with its cell. One moved in the same change
/// is left where it was put.
CanvasDocument layoutsSynced(CanvasDocument was, CanvasDocument now) {
  if (identical(was.elements, now.elements)) return now;
  var changed = <(LayoutElement, LayoutElement)>[];
  for (var e in now.elements) {
    if (e is! LayoutElement) continue;
    var old = was.elementById(e.id);
    if (old is LayoutElement && !identical(old, e)) changed.add((old, e));
  }
  if (changed.isEmpty) return now;

  var next = now;
  for (var (old, e) in changed) {
    Map<String, Rect> places(LayoutElement l) =>
        {for (var p in layoutPlaces(l, l.bounds)) p.cell.id: p.bounds};
    var before = places(old), after = places(e);
    var prefix = "${e.id}:";
    for (var el in now.elements) {
      if (!el.base.dock.startsWith(prefix)) continue;
      // Moved by hand in this same change: where it was put stands.
      if (!identical(was.elementById(el.id), el)) continue;
      var cell = el.base.dock.substring(prefix.length);
      var o = before[cell], n = after[cell];
      if (o == null || n == null || o == n) continue;
      if (o.width <= 0 || o.height <= 0) continue;
      var sx = n.width / o.width, sy = n.height / o.height;
      next = next.withElement(el.withBase(
          x: n.left + (el.x - o.left) * sx,
          y: n.top + (el.y - o.top) * sy,
          width: el.width * sx,
          height: el.height * sy));
    }
  }
  return next;
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/vector_cut.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';

// vector_items.dart is what the select shapes tool picks: a whole shape --
// with whatever is combined into it -- or one piece of a shape the knife
// has cut. Each is moved, sized and turned by a box round it, as an element
// is, and lined up with the others by the align tool. See VectorItem.

/// VectorItem is one thing the select shapes tool picks: shape [shape] --
/// the first of its run of combined shapes, where it is whole -- and, where
/// it has been cut, which of its pieces.
typedef VectorItem = ({int shape, int part});

/// _cut is whether [s] is in pieces, each its own item.
bool _cut(VectorShape s) => partsOf(s).length > 1;

/// itemRuns is every shape the item moves and, for each, which of its runs:
/// all of a whole shape's group, or one piece of a cut one.
List<(int, bool Function(VectorPath))> _itemRuns(
    VectorElement e, VectorItem item) {
  var shapes = e.shapes ?? const <VectorShape>[];
  if (item.shape < 0 || item.shape >= shapes.length) return const [];
  var s = shapes[item.shape];
  if (_cut(s)) return [(item.shape, (r) => r.part == item.part)];
  return [for (var i in groupMembers(e, item.shape)) (i, (_) => true)];
}

/// itemAt is the item at [canvasPoint] -- the piece of a cut shape under
/// it, or the whole shape -- or null.
VectorItem? itemAt(VectorElement e, Offset canvasPoint, double reach) {
  var under = shapeAt(e, canvasPoint, reach);
  if (under < 0) return null;
  var s = e.shapes![under];
  if (_cut(s)) {
    var space = VectorSpace(e);
    var part = partAt(s, space.toDrawing(canvasPoint), reach * space.unitsPer);
    if (part != null) return (shape: under, part: part);
  }
  return (shape: groupOf(e, under), part: 0);
}

/// itemExtent is the box round [item], in the drawing's units.
Rect? itemExtent(VectorElement e, VectorItem item) {
  Rect? box;
  for (var (i, keep) in _itemRuns(e, item)) {
    var s = e.shapes![i];
    var b = shapeExtent(s.copyWith(paths: [
      for (var r in s.paths)
        if (keep(r)) r
    ]));
    if (b == null) continue;
    box = box == null ? b : box.expandToInclude(b);
  }
  return box;
}

/// itemsExtent is the box round all of [items].
Rect? itemsExtent(VectorElement e, Iterable<VectorItem> items) {
  Rect? box;
  for (var item in items) {
    var b = itemExtent(e, item);
    if (b == null) continue;
    box = box == null ? b : box.expandToInclude(b);
  }
  return box;
}

/// withItemsMapped is [e] with [items] moved as [point] says -- and their
/// handles, which are directions rather than places, as [vector] says.
VectorElement withItemsMapped(VectorElement e, Iterable<VectorItem> items,
    Offset Function(Offset) point, Offset Function(Offset) vector,
    {double width = 1}) {
  var shapes = [...?e.shapes];
  for (var item in items) {
    for (var (i, keep) in _itemRuns(e, item)) {
      var s = shapes[i];
      var whole = s.paths.every(keep);
      shapes[i] = s.copyWith(
        paths: [
          for (var run in s.paths)
            if (!keep(run))
              run
            else
              run.copyWith(nodes: [
                for (var n in run.nodes)
                  (() {
                    var at = point(n.point);
                    var inH = vector(Offset(n.inX, n.inY));
                    var outH = vector(Offset(n.outX, n.outY));
                    return n.copyWith(
                        x: at.dx,
                        y: at.dy,
                        inX: inH.dx,
                        inY: inH.dy,
                        outX: outH.dx,
                        outY: outH.dy);
                  })(),
              ]),
        ],
        // What is painted on a shape goes with it, where all of it moves.
        tints: whole ? [for (var t in s.tints) t.mapped(point)] : null,
        erasures: whole ? [for (var t in s.erasures) t.mapped(point)] : null,
      );
    }
  }
  return e.copyWith(shapes: shapes);
}

/// withItemsFitted is [items] taken from the box [from] to [to]: moved,
/// and stretched as it is.
VectorElement withItemsFitted(
    VectorElement e, Iterable<VectorItem> items, Rect from, Rect to) {
  var sx = from.width == 0 ? 1.0 : to.width / from.width;
  var sy = from.height == 0 ? 1.0 : to.height / from.height;
  return withItemsMapped(
      e,
      items,
      (p) => Offset(
          to.left + (p.dx - from.left) * sx, to.top + (p.dy - from.top) * sy),
      (v) => Offset(v.dx * sx, v.dy * sy));
}

/// withItemsTurned is [items] turned [radians] about [centre].
VectorElement withItemsTurned(VectorElement e, Iterable<VectorItem> items,
    Offset centre, double radians) {
  var c = math.cos(radians), s = math.sin(radians);
  Offset turn(Offset v) => Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  return withItemsMapped(e, items, (p) => centre + turn(p - centre), turn);
}

/// withItemsAligned lines [items] up as [how] says -- each by its box, to
/// the edge or middle of the box round them all, or spread evenly between
/// the outermost two by their middles.
VectorElement withItemsAligned(
    VectorElement e, List<VectorItem> items, VectorAlign how) {
  var boxes = <(VectorItem, Rect)>[
    for (var item in items)
      if (itemExtent(e, item) case var b?) (item, b),
  ];
  if (boxes.length < 2) return e;
  var all =
      boxes.skip(1).fold(boxes.first.$2, (r, b) => r.expandToInclude(b.$2));
  Map<VectorItem, Offset> spread(bool across) {
    var order = [...boxes]..sort((a, b) => across
        ? a.$2.center.dx.compareTo(b.$2.center.dx)
        : a.$2.center.dy.compareTo(b.$2.center.dy));
    var first = order.first.$2.center, last = order.last.$2.center;
    var n = order.length - 1;
    return {
      for (var (k, (item, b)) in order.indexed)
        item: across
            ? Offset(first.dx + (last.dx - first.dx) * k / n - b.center.dx, 0)
            : Offset(0, first.dy + (last.dy - first.dy) * k / n - b.center.dy),
    };
  }

  var by = switch (how) {
    VectorAlign.left => {
        for (var (i, b) in boxes) i: Offset(all.left - b.left, 0)
      },
    VectorAlign.centreX => {
        for (var (i, b) in boxes) i: Offset(all.center.dx - b.center.dx, 0)
      },
    VectorAlign.right => {
        for (var (i, b) in boxes) i: Offset(all.right - b.right, 0)
      },
    VectorAlign.top => {
        for (var (i, b) in boxes) i: Offset(0, all.top - b.top)
      },
    VectorAlign.centreY => {
        for (var (i, b) in boxes) i: Offset(0, all.center.dy - b.center.dy)
      },
    VectorAlign.bottom => {
        for (var (i, b) in boxes) i: Offset(0, all.bottom - b.bottom)
      },
    VectorAlign.spreadX => spread(true),
    VectorAlign.spreadY => spread(false),
  };
  var next = e;
  for (var (item, _) in boxes) {
    var d = by[item]!;
    if (d == Offset.zero) continue;
    next = withItemsMapped(next, [item], (p) => p + d, (v) => v);
  }
  return next;
}

/// liveItems is [items] that are still in [e]: a shape taken out, or put
/// back together, leaves nothing to pick.
Set<VectorItem> liveItems(VectorElement e, Set<VectorItem> items) {
  var shapes = e.shapes ?? const <VectorShape>[];
  return {
    for (var item in items)
      if (item.shape < shapes.length &&
          (!_cut(shapes[item.shape])
              ? item.part == 0 && groupOf(e, item.shape) == item.shape
              : partsOf(shapes[item.shape]).contains(item.part)))
        item,
  };
}

/// itemPicks is every point of [items]: what copying them copies.
Set<VectorPick> itemPicks(VectorElement e, Iterable<VectorItem> items) => {
      for (var item in items)
        for (var (i, keep) in _itemRuns(e, item))
          for (var (p, run) in e.shapes![i].paths.indexed)
            if (keep(run))
              for (var n = 0; n < run.nodes.length; n++) VectorPick(i, p, n),
    };

/// itemsOf is the items [picks] are points of: the shapes, or pieces, they
/// make up.
Set<VectorItem> itemsOf(VectorElement e, Iterable<VectorPick> picks) {
  var shapes = e.shapes ?? const <VectorShape>[];
  return {
    for (var p in picks)
      if (p.shape < shapes.length && p.path < shapes[p.shape].paths.length)
        _cut(shapes[p.shape])
            ? (shape: p.shape, part: shapes[p.shape].paths[p.path].part)
            : (shape: groupOf(e, p.shape), part: 0),
  };
}

/// allItems is every shape of [e], and every piece of the cut ones.
Set<VectorItem> allItems(VectorElement e) {
  var shapes = e.shapes ?? const <VectorShape>[];
  return {
    for (var (i, s) in shapes.indexed)
      if (_cut(s))
        for (var part in partsOf(s)) (shape: i, part: part)
      else if (groupOf(e, i) == i)
        (shape: i, part: 0),
  };
}

/// itemsIn is every item of [e] whose box, on the canvas, overlaps
/// [canvasRect].
Set<VectorItem> itemsIn(VectorElement e, Rect canvasRect) {
  var space = VectorSpace(e);
  return {
    for (var item in allItems(e))
      if (itemExtent(e, item) case var b?)
        if (_onCanvas(space, b).overlaps(canvasRect)) item,
  };
}

Rect _onCanvas(VectorSpace space, Rect b) {
  var pts = [
    for (var c in [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
      space.toCanvas(c),
  ];
  var r = Rect.fromPoints(pts[0], pts[0]);
  for (var p in pts.skip(1)) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}

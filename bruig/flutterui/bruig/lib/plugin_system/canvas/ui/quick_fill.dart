import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/painting.dart';

// quick_fill.dart is the paint bucket: a click inside an area that lines
// close round -- any lines, from any number of strokes, crossing or touching
// -- fills it, as a shape of its own laid under them.
//
// Found the way a bucket in a painting program finds it: the lines are drawn
// into a picture, the area is flooded out from the click until it meets
// them, and the edge of what was flooded is traced back into a shape. Lines
// that nearly meet count as meeting, within the gap allowed, so a sketch
// whose strokes stop a hair short of each other still fills.

/// quickFilled is [e] with the area round [canvasPoint] filled with
/// [colour], or null where the lines do not close round it -- the flood
/// reached the drawing's edge -- or there are no lines to close it. [gap]
/// is the widest opening, in the drawing's units, still counted as closed.
///
/// The fill goes under every shape with a line, and over the fills that
/// have none: under the ink, over a background.
Future<VectorElement?> quickFilled(
    VectorElement e, Offset canvasPoint, Color colour,
    {double gap = 0}) async {
  var shapes = e.shapes;
  if (shapes == null || shapes.isEmpty) return null;
  var lined = [
    for (var d in vectorDrawn(shapes))
      if ((d.style.stroke?.a ?? 0) > 0 && d.style.strokeWidth > 0) d,
  ];
  if (lined.isEmpty) return null;

  // The grid: everything drawn, and a margin round it, about twelve
  // hundred cells across its longer side -- fine enough for a hairline,
  // quick to flood. Everything drawn and not only the drawing's box: while
  // it is edited, strokes go where the pen goes, and the box is only fitted
  // round them when the editing is done. A box that cut through a shape
  // would let the flood out through the cut.
  Rect? reach;
  for (var d in lined) {
    var b = d.combined ? d.outline.getBounds() : shapeExtent(d.style);
    if (b == null) continue;
    b = b.inflate(d.style.strokeWidth);
    reach = reach == null ? b : reach.expandToInclude(b);
  }
  var view = e.viewBox;
  var all = reach == null ? view : reach.expandToInclude(view);
  var margin = math.max(all.width, all.height) * 0.02 + gap;
  var area = all.inflate(margin);
  var scale = 1200 / math.max(area.width, area.height);
  var w = (area.width * scale).ceil(), h = (area.height * scale).ceil();
  if (w < 3 || h < 3) return null;

  // The lines, drawn solid, each thickened by the gap: an opening narrower
  // than the gap closes up.
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  canvas.scale(scale);
  canvas.translate(-area.left, -area.top);
  var ink = Paint()
    ..color = const Color(0xFF000000)
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false;
  for (var d in lined) {
    var s = d.style;
    if (!d.combined && s.ownLine) {
      canvas.drawPath(
          vectorLinePath(s), Paint()..color = const Color(0xFF000000));
      if (gap > 0) {
        canvas.drawPath(vectorLinePath(s), ink..strokeWidth = gap * 2);
      }
    } else {
      canvas.drawPath(
          d.combined ? d.outline : vectorShapePath(s),
          ink
            ..strokeWidth = s.strokeWidth + gap * 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
  }
  var image = await rec.endRecording().toImage(w, h);
  var bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  var wall = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (bytes[i * 4 + 3] > 0) wall[i] = 1;
  }

  // Flooded out from the click.
  var at = VectorSpace(e).toDrawing(canvasPoint);
  var sx = ((at.dx - area.left) * scale).floor();
  var sy = ((at.dy - area.top) * scale).floor();
  if (sx < 0 || sy < 0 || sx >= w || sy >= h || wall[sy * w + sx] == 1) {
    return null;
  }
  var region = Uint8List(w * h);
  var stack = <int>[sy * w + sx];
  region[sy * w + sx] = 1;
  while (stack.isNotEmpty) {
    var i = stack.removeLast();
    var x = i % w, y = i ~/ w;
    // At the edge, it has got out: the lines do not close round the click.
    if (x == 0 || y == 0 || x == w - 1 || y == h - 1) return null;
    for (var n in [i - 1, i + 1, i - w, i + w]) {
      if (region[n] == 0 && wall[n] == 0) {
        region[n] = 1;
        stack.add(n);
      }
    }
  }

  // Grown back out by the gap and two cells more, so the fill tucks under the
  // lines it met rather than stopping a hair short of them.
  var grow = (gap * scale).ceil() + 2;
  for (var k = 0; k < grow; k++) {
    var next = Uint8List.fromList(region);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var i = y * w + x;
        if (region[i] == 1) continue;
        if (region[i - 1] == 1 ||
            region[i + 1] == 1 ||
            region[i - w] == 1 ||
            region[i + w] == 1) {
          next[i] = 1;
        }
      }
    }
    region = next;
  }

  var loops = _traced(region, w, h);
  if (loops.isEmpty) return null;
  Offset toDrawing(Offset cell) =>
      Offset(cell.dx / scale + area.left, cell.dy / scale + area.top);
  var runs = <VectorPath>[
    for (var loop in loops)
      if (_thinned(loop, 0.9) case var kept when kept.length >= 3)
        VectorPath([
          for (var p in kept)
            (() {
              var d = toDrawing(p);
              return VectorNode(d.dx, d.dy);
            })(),
        ], closed: true),
  ];
  if (runs.isEmpty) return null;

  var fill = VectorShape(paths: runs, fill: colour, evenOdd: true);
  // Under the lines: before the first shape with one -- and before any run
  // of shapes combined into it, which goes with it.
  var under =
      shapes.indexWhere((s) => (s.stroke?.a ?? 0) > 0 && s.strokeWidth > 0);
  if (under < 0) under = shapes.length;
  under = groupOf(e, under);
  return e.copyWith(shapes: [
    ...shapes.sublist(0, under),
    fill,
    ...shapes.sublist(under),
  ]);
}

/// _traced is the edges of the cells set in [region] (w by h), as closed
/// loops of cell corners -- the outside of the area and the edge of every
/// hole in it. Each cell edge between a set cell and an unset one is one
/// step, all of them taken the same way round, and joined end to end.
List<List<Offset>> _traced(Uint8List region, int w, int h) {
  bool set(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && region[y * w + x] == 1;
  int key(int x, int y) => y * (w + 1) + x;
  var next = <int, List<int>>{};
  void edge(int ax, int ay, int bx, int by) =>
      (next[key(ax, ay)] ??= []).add(key(bx, by));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!set(x, y)) continue;
      if (!set(x, y - 1)) edge(x + 1, y, x, y);
      if (!set(x, y + 1)) edge(x, y + 1, x + 1, y + 1);
      if (!set(x - 1, y)) edge(x, y, x, y + 1);
      if (!set(x + 1, y)) edge(x + 1, y + 1, x + 1, y);
    }
  }
  var loops = <List<Offset>>[];
  Offset point(int k) =>
      Offset((k % (w + 1)).toDouble(), (k ~/ (w + 1)).toDouble());
  while (next.isNotEmpty) {
    var start = next.keys.first;
    var loop = <Offset>[];
    var at = start;
    while (true) {
      var outs = next[at];
      if (outs == null || outs.isEmpty) break;
      var to = outs.removeLast();
      if (outs.isEmpty) next.remove(at);
      loop.add(point(at));
      at = to;
      if (at == start) break;
    }
    if (loop.length >= 4) loops.add(loop);
  }
  return loops;
}

/// _thinned is [loop] with the points it does not need, within [tolerance]
/// (in cells), taken out: the staircase of cell corners straightened into
/// the edge it stands for. Douglas and Peucker's, on a closed loop split at
/// its two farthest-apart points.
List<Offset> _thinned(List<Offset> loop, double tolerance) {
  if (loop.length < 4) return loop;
  var far = 0;
  var most = 0.0;
  for (var (i, p) in loop.indexed) {
    var d = (p - loop[0]).distance;
    if (d > most) {
      most = d;
      far = i;
    }
  }
  List<Offset> line(List<Offset> pts) {
    if (pts.length < 3) return pts;
    var keep = List<bool>.filled(pts.length, false);
    keep[0] = keep[pts.length - 1] = true;
    var stack = [(0, pts.length - 1)];
    while (stack.isNotEmpty) {
      var (a, b) = stack.removeLast();
      var idx = -1;
      var worst = tolerance;
      var ab = pts[b] - pts[a];
      var len = ab.distance;
      for (var i = a + 1; i < b; i++) {
        var v = pts[i] - pts[a];
        var d =
            len == 0 ? v.distance : (v.dx * ab.dy - v.dy * ab.dx).abs() / len;
        if (d > worst) {
          worst = d;
          idx = i;
        }
      }
      if (idx >= 0) {
        keep[idx] = true;
        stack.add((a, idx));
        stack.add((idx, b));
      }
    }
    return [
      for (var i = 0; i < pts.length; i++)
        if (keep[i]) pts[i]
    ];
  }

  var first = line(loop.sublist(0, far + 1));
  var second = line([...loop.sublist(far), loop[0]]);
  return [...first, ...second.sublist(1, second.length - 1)];
}

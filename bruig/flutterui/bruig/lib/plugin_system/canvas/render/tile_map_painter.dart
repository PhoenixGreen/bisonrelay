import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';

// tile_map_painter.dart draws a Tile map element: each layer's cells, the
// first layer at the bottom, inside the element's box -- see
// tile_map_element.dart. The tiles as they are on their sheet go in one
// draw a set; a turned or flipped one is drawn on its own. A tile that
// plays shows the frame its animation has got to. On an objects layer the
// things stood on it and the figures among them are drawn by where their
// feet are, the furthest up the page first, so the nearer stand in front.

/// TileEditView is what the renderer shows of a map being painted: the
/// map as the stroke under way has it, the grid, the cell under the
/// pointer with the tiles that would go there -- or the thing that would
/// be stood there -- and a box being dragged out to pick tiles up from.
/// See tile_painting.dart.
typedef TileEditView = ({
  TileMapElement? working,
  bool grid,
  (int, int)? hover,
  List<(int, int, TileRef)> ghost,
  TileObject? standing,
  (int, int, int, int)? box,
});

/// tileMapEditingOf is how a map being painted in the editor is shown, set
/// by it; null for one not being painted.
TileEditView? Function(TileMapElement e)? tileMapEditingOf;

/// tileCameraShift is how far the scene's camera has moved off the middle
/// of the page while a scene is drawn through it, in the page's own units
/// -- set by the renderer -- or null when it is drawn as it is. A layer
/// with less parallax than the map lags behind it. See paintCanvasDocument.
Offset? tileCameraShift;

/// TileFigure is a figure on a map, found by its id: where its feet are,
/// down the canvas, and how it is drawn -- or null, when there is none.
typedef TileFigure = (double, void Function())? Function(String id);

/// paintTileMap draws [e] in [box] on [frame]; [figures] finds the figures
/// on its objects layers. [editing], one being painted is shown as its
/// painter has it, ruled into cells.
///
/// [frames] is how long the scene is, for a light that changes over it.
void paintTileMap(Canvas canvas, Rect box, TileMapElement e, int frame,
    {int frameRate = 12, int frames = 0, CanvasImageSource? images, bool editing = false, TileFigure? figures}) {
  var view = editing ? tileMapEditingOf?.call(e) : null;
  var m = view?.working ?? e;
  if (m.tileCount == 0 && m.figureIds.isEmpty && view == null) {
    _paintEmpty(canvas, box);
    return;
  }
  var seconds = frame / math.max(1, frameRate);
  var sheets = [for (var s in m.sources) images?.resolve(s.sheet, const BackgroundRemoval())];
  var light = m.lightAt(frames > 1 ? frame / (frames - 1) : 0);
  // Lit, the whole map is drawn into a layer of its own and the light laid
  // over it: what is under the map is not lit by it.
  if (light != null) canvas.saveLayer(null, Paint());
  var cs = m.cellSize;
  for (var layer in m.layers) {
    if (!layer.visible) continue;
    var layered = layer.opacity < 1;
    if (layered) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity));
    }
    // How far it has moved: lagging the camera, and drifting by itself.
    var shift = (tileCameraShift ?? Offset.zero) * (1 - layer.parallax) +
        Offset(layer.drift.dx * cs.width, layer.drift.dy * cs.height) * seconds;
    if (layer.cells.isNotEmpty) {
      canvas.save();
      canvas.clipRect(box);
      var extent = layer.extent!;
      var (c0, r0, c1, r1) = extent;
      var period = Offset((c1 - c0 + 1) * cs.width, (r1 - r0 + 1) * cs.height);
      // A layer that goes on for ever is drawn again a whole of it along,
      // as many times as it takes to fill the box.
      int from(double at, double first, double each) => ((at - first) / each).floor() - 1;
      var kx = layer.repeat.x ? (from(box.left, box.left + shift.dx + c0 * cs.width, period.dx), from(box.right, box.left + shift.dx + c0 * cs.width, period.dx) + 1) : (0, 0);
      var ky = layer.repeat.y ? (from(box.top, box.top + shift.dy + r0 * cs.height, period.dy), from(box.bottom, box.top + shift.dy + r0 * cs.height, period.dy) + 1) : (0, 0);
      for (var i = kx.$1; i <= kx.$2; i++) {
        for (var j = ky.$1; j <= ky.$2; j++) {
          var at = box.shift(shift + Offset(i * period.dx, j * period.dy));
          paintTileCells(canvas, at, m, layer.cells, sheets,
              tint: layer.tint,
              seconds: seconds,
              window: shift == Offset.zero && i == 0 && j == 0 ? null : extent);
        }
      }
      canvas.restore();
    }
    if (layer.isObjects) {
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      _paintObjects(canvas, box.shift(-shift), m, layer, sheets, seconds, figures, unshift: shift);
      canvas.restore();
    }
    if (layered) canvas.restore();
  }
  if (light != null) {
    canvas.drawRect(
        box.inflate(math.max(box.width, box.height)),
        Paint()
          ..color = light
          ..blendMode = BlendMode.modulate);
    canvas.restore();
  }
  if (view != null) {
    canvas.save();
    canvas.clipRect(box);
    if (view.ghost.isNotEmpty) {
      canvas.saveLayer(box, Paint()..color = const Color(0x99000000));
      paintTileCells(canvas, box, m, {for (var (c, r, t) in view.ghost) cellKey(c, r): t.word}, sheets);
      canvas.restore();
    }
    if (view.standing case var o?) {
      canvas.saveLayer(box, Paint()..color = const Color(0x99000000));
      _paintObject(canvas, m, o, sheets, seconds, null);
      canvas.restore();
    }
    if (view.grid) _paintGrid(canvas, box, m);
    if (view.box case (var c0, var r0, var c1, var r1)) {
      var r = m.cellRect(c0, r0).expandToInclude(m.cellRect(c1, r1));
      canvas.drawRect(r, Paint()..color = const Color(0x223D7EFF));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xCC3D7EFF));
    } else if (view.hover case (var c, var r) when view.standing == null) {
      canvas.drawRect(
          m.cellRect(c, r),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xCC3D7EFF));
    }
    canvas.restore();
  }
}

/// _paintObjects draws [layer]'s things and figures, the furthest up the
/// page first. Its things are cut to the map's box; a figure is not -- it
/// is an element of the canvas, walking where it likes.
///
/// [unshift] is how far the layer has been moved: its figures, elements of
/// the canvas, are drawn where they are all the same.
void _paintObjects(Canvas canvas, Rect box, TileMapElement m, TileLayer layer, List<ui.Image?> sheets,
    double seconds, TileFigure? figures, {Offset unshift = Offset.zero}) {
  var drawn = <(double, void Function())>[
    for (var o in layer.objects)
      (
        m.objectRect(o).bottom,
        () {
          canvas.save();
          canvas.clipRect(box);
          _paintObject(canvas, m, o, sheets, seconds, layer.tint);
          canvas.restore();
        }
      ),
    if (figures != null)
      for (var id in layer.figures)
        if (figures(id) case (var feet, var draw))
          (
            feet - unshift.dy,
            () {
              canvas.save();
              canvas.translate(-unshift.dx, -unshift.dy);
              draw();
              canvas.restore();
            }
          ),
  ];
  // Stable: two at the same height keep the order they were put down in.
  var order = [for (var i = 0; i < drawn.length; i++) i]
    ..sort((a, b) {
      var by = drawn[a].$1.compareTo(drawn[b].$1);
      return by != 0 ? by : a.compareTo(b);
    });
  for (var i in order) {
    drawn[i].$2();
  }
}

/// _paintObject draws [o], standing where it stands.
void _paintObject(Canvas canvas, TileMapElement m, TileObject o, List<ui.Image?> sheets, double seconds, Color? tint) {
  var r = m.objectRect(o);
  var cs = m.cellSize;
  paintTileCells(canvas, r, m, {for (var (c, row, t) in o.stamp.cells) cellKey(c, row): t.word}, sheets,
      tint: tint, seconds: seconds, window: (0, 0, o.stamp.width - 1, o.stamp.height - 1), cell: cs);
}

/// paintTileCells draws [cells] of [m] -- by [cellKey], each a [TileRef]
/// word -- from [sheets], one for each of its sets, in [box]; those whose
/// sheet is not read yet left out.
///
/// [seconds] in, a tile that plays shows the frame it has got to. The
/// cells drawn are those in the map's window, or in [window] -- first and
/// last column and row -- counted from [box]'s top left.
void paintTileCells(Canvas canvas, Rect box, TileMapElement m, Map<int, int> cells, List<ui.Image?> sheets,
    {Color? tint, double seconds = 0, (int, int, int, int)? window, Size? cell}) {
  var paint = Paint()..filterQuality = m.pixelArt ? FilterQuality.none : FilterQuality.medium;
  if (tint != null) paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
  var k = m.scale, cs = cell ?? m.cellSize;
  var (c0, r0, c1, r1) = window ?? m.window;
  // Plain tiles, gathered by their set, to be drawn in one go each.
  var plain = <int, (List<RSTransform>, List<Rect>)>{};
  for (var entry in cells.entries) {
    var col = colOf(entry.key), row = rowOf(entry.key);
    // A tile taller than its cell stands up into the ones above: those
    // below the window can still show, and are drawn.
    if (col < c0 - 1 || col > c1 + 1 || row < r0 || row > r1 + 8) continue;
    var t = TileRef(entry.value);
    if (t.source >= m.sources.length) continue;
    var sheet = sheets[t.source];
    if (sheet == null) continue;
    var s = m.sources[t.source];
    var src = _onSheet(s, s.tileRect(s.shownAt(t.index, seconds)), sheet);
    if (src.isEmpty) continue;
    var w = s.tileW * k, h = s.tileH * k;
    // On the cell's bottom, in the middle across: a tile of the cell's own
    // size fills it.
    var left = box.left + col * cs.width + (cs.width - w) / 2;
    var top = box.top + (row + 1) * cs.height - h;
    if (!t.turned) {
      var (xs, rs) = plain.putIfAbsent(t.source, () => ([], []));
      xs.add(RSTransform.fromComponents(
          rotation: 0, scale: w / src.width, anchorX: 0, anchorY: 0, translateX: left, translateY: top));
      rs.add(src);
      continue;
    }
    var (a, b, c, d) = t.matrix;
    var centre = Offset(left + w / 2, top + h / 2);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.transform(Float64List.fromList([
      a.toDouble(), c.toDouble(), 0, 0, //
      b.toDouble(), d.toDouble(), 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1,
    ]));
    // Swapped, a tile not square is drawn its other way round.
    var (dw, dh) = t.swap ? (h, w) : (w, h);
    canvas.drawImageRect(sheet, src, Rect.fromCenter(center: Offset.zero, width: dw, height: dh), paint);
    canvas.restore();
  }
  for (var e in plain.entries) {
    var (xs, rs) = e.value;
    canvas.drawAtlas(sheets[e.key]!, xs, rs, null, null, null, paint);
  }
}

/// _onSheet is [r], a place on [s]'s sheet as it was measured, on the
/// picture as stored: one stored at another size is sliced the same.
Rect _onSheet(TileSource s, Rect r, ui.Image sheet) {
  var sx = sheet.width / math.max(1, s.sheetW), sy = sheet.height / math.max(1, s.sheetH);
  return Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy)
      .intersect(Rect.fromLTWH(0, 0, sheet.width.toDouble(), sheet.height.toDouble()));
}

void _paintGrid(Canvas canvas, Rect box, TileMapElement m) {
  var cs = m.cellSize;
  // Too fine to see between, it is left off.
  if (cs.width < 4 || cs.height < 4) return;
  var rule = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x333D7EFF);
  for (var x = box.left + cs.width; x < box.right; x += cs.width) {
    canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), rule);
  }
  for (var y = box.top + cs.height; y < box.bottom; y += cs.height) {
    canvas.drawLine(Offset(box.left, y), Offset(box.right, y), rule);
  }
  canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x553D7EFF));
}

/// _paintEmpty is a map with nothing painted yet: dashes round its box,
/// and a few tiles in the middle.
void _paintEmpty(Canvas canvas, Rect box) {
  var colour = const Color(0x998A8F99);
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, box.shortestSide * 0.008)
    ..color = colour;
  var path = Path()..addRect(box.deflate(2));
  for (var m in path.computeMetrics()) {
    var dash = math.max(4.0, box.shortestSide * 0.03);
    for (var d = 0.0; d < m.length; d += dash * 2) {
      canvas.drawPath(m.extractPath(d, d + dash), line);
    }
  }
  var u = box.shortestSide * 0.06;
  var fill = Paint()..color = colour;
  for (var (x, y) in const [(-1, 0), (0, 0), (1, 0), (0, -1), (1, -1), (1, -2)]) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(box.center.dx + (x - 0.5) * u * 1.08, box.center.dy + (y + 0.5) * u * 1.08 - u * 0.4, u, u),
            Radius.circular(u * 0.12)),
        fill);
  }
}

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
// draw a set; a turned or flipped one is drawn on its own.

/// TileEditView is what the renderer shows of a map being painted: the
/// map as the stroke under way has it, the grid, and the cell under the
/// pointer with the tile that would go there. See tile_painting.dart.
typedef TileEditView = ({TileMapElement? working, bool grid, (int, int)? hover, List<(int, int, TileRef)> ghost});

/// tileMapEditingOf is how a map being painted in the editor is shown, set
/// by it; null for one not being painted.
TileEditView? Function(TileMapElement e)? tileMapEditingOf;

/// paintTileMap draws [e] in [box]. [editing], one being painted is shown
/// as its painter has it, ruled into cells.
void paintTileMap(Canvas canvas, Rect box, TileMapElement e, int frame,
    {int frameRate = 12, CanvasImageSource? images, bool editing = false}) {
  var view = editing ? tileMapEditingOf?.call(e) : null;
  var m = view?.working ?? e;
  if (m.tileCount == 0 && view == null) {
    _paintEmpty(canvas, box);
    return;
  }
  var sheets = [for (var s in m.sources) images?.resolve(s.sheet, const BackgroundRemoval())];
  canvas.save();
  canvas.clipRect(box);
  for (var layer in m.layers) {
    if (!layer.visible || layer.cells.isEmpty) continue;
    var layered = layer.opacity < 1;
    if (layered) {
      canvas.saveLayer(box, Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity));
    }
    paintTileCells(canvas, box, m, layer.cells, sheets, tint: layer.tint);
    if (layered) canvas.restore();
  }
  if (view != null) {
    if (view.ghost.isNotEmpty) {
      canvas.saveLayer(box, Paint()..color = const Color(0x99000000));
      paintTileCells(canvas, box, m, {for (var (c, r, t) in view.ghost) cellKey(c, r): t.word}, sheets);
      canvas.restore();
    }
    if (view.grid) _paintGrid(canvas, box, m);
    if (view.hover case (var c, var r)) {
      canvas.drawRect(
          m.cellRect(c, r),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xCC3D7EFF));
    }
  }
  canvas.restore();
}

/// paintTileCells draws [cells] of [m] -- by [cellKey], each a [TileRef]
/// word -- from [sheets], one for each of its sets, in [box]; those whose
/// sheet is not read yet left out.
void paintTileCells(Canvas canvas, Rect box, TileMapElement m, Map<int, int> cells, List<ui.Image?> sheets,
    {Color? tint}) {
  var paint = Paint()..filterQuality = m.pixelArt ? FilterQuality.none : FilterQuality.medium;
  if (tint != null) paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
  var k = m.scale, cs = m.cellSize;
  var (c0, r0, c1, r1) = m.window;
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
    var src = _onSheet(s, s.tileRect(t.index), sheet);
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

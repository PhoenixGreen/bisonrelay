import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/render/tile_map_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/foundation.dart';

// tile_painting.dart is painting a Tile map element on the canvas, as
// Godot's tile map editor does: a tile picked from a set, laid in the cells
// the pen goes over, along a line, over a box, or poured into the cells
// like the one pressed; rubbed out; or picked up off the map. The tile to
// be laid shows faintly under the pointer. Each stroke is one undo.

/// TileTool is what painting a map does with the pen.
enum TileTool {
  paint("Paint"),
  erase("Rubber"),
  line("Line"),
  rect("Box"),
  fill("Fill"),
  picker("Pick a tile");

  final String label;
  const TileTool(this.label);
}

/// pickedTileLayer is the layer picked in each map, by its id: the one
/// painted on, and the one its settings show.
final Map<String, int> pickedTileLayer = {};

/// TilePaintSession is one map being painted.
class TilePaintSession extends ChangeNotifier {
  final CanvasController controller;
  final String id;
  TilePaintSession(this.controller, this.id);

  TileTool tool = TileTool.paint;

  /// brush is the tile laid: from the set and turned as picked.
  TileRef brush = TileRef.of(0, 0);
  bool grid = true;

  /// hover is the cell under the pointer, when it is over the map.
  (int, int)? hover;

  /// tick counts the changes to what is shown, for the stage to draw again.
  int tick = 0;

  TileMapElement? get map => switch (controller.document.elementById(id)) {
        TileMapElement e => e,
        _ => null,
      };

  int get layer {
    var m = map;
    var i = pickedTileLayer[id] ?? (m == null ? 0 : m.layers.length - 1);
    return m == null ? 0 : i.clamp(0, math.max(0, m.layers.length - 1)).toInt();
  }

  void set({TileTool? tool, TileRef? brush, bool? grid}) {
    if (tool != null) this.tool = tool;
    if (brush != null) this.brush = brush;
    if (grid != null) this.grid = grid;
    _shown();
  }

  void _shown() {
    tick++;
    notifyListeners();
  }

  /// _working is the map as the stroke under way has it, and _cells the
  /// layer painted, being changed; _before the layer as the stroke found it.
  TileMapElement? _working;
  Map<int, int>? _cells;
  Map<int, int> _before = const {};
  (int, int)? _from;

  /// view is what the renderer shows of [e] while it is painted.
  TileEditView view(TileMapElement e) {
    var ghost = <(int, int, TileRef)>[];
    if (hover case (var c, var r) when _from == null && tool == TileTool.paint) {
      ghost.add((c, r, brush));
    }
    return (working: _working, grid: grid, hover: hover, ghost: ghost);
  }

  /// hoverAt follows the pointer at [doc]: the cell under it lit.
  void hoverAt(ui.Offset? doc) {
    var m = map;
    (int, int)? next;
    if (m != null && doc != null && m.bounds.contains(doc)) next = m.cellAt(doc);
    if (next == hover) return;
    hover = next;
    _shown();
  }

  /// strokeStart puts the pen down at [doc].
  void strokeStart(ui.Offset doc) {
    var m = map;
    if (m == null || m.layers.isEmpty) return;
    var l = m.layers[layer];
    var at = m.cellAt(doc);
    if (tool == TileTool.picker) {
      // The top tile showing there, on whichever layer.
      for (var layer in m.layers.reversed) {
        var t = layer.visible ? layer.at(at.$1, at.$2) : null;
        if (t != null) {
          brush = t;
          tool = TileTool.paint;
          break;
        }
      }
      _shown();
      return;
    }
    if (l.locked) return;
    _before = l.cells;
    _cells = Map.of(l.cells);
    _from = at;
    _lay(m, at, at);
  }

  /// strokeTo carries the pen on to [doc].
  void strokeTo(ui.Offset doc) {
    var m = map, from = _from;
    if (m == null || from == null || _cells == null) return;
    var at = m.cellAt(doc);
    hover = at;
    switch (tool) {
      case TileTool.paint || TileTool.erase:
        for (var (c, r) in cellsAlong(from, at)) {
          _put(c, r);
        }
        _from = at;
        _show(m);
      case TileTool.line || TileTool.rect:
        _lay(m, from, at);
      case TileTool.fill || TileTool.picker:
        return;
    }
  }

  /// _lay lays the tool's tiles from [from] to [at]: a line or a box drawn
  /// again over the layer as the stroke found it; anything else, one cell.
  void _lay(TileMapElement m, (int, int) from, (int, int) at) {
    var cells = _cells!;
    switch (tool) {
      case TileTool.line:
        cells
          ..clear()
          ..addAll(_before);
        for (var (c, r) in cellsAlong(from, at)) {
          _put(c, r);
        }
      case TileTool.rect:
        cells
          ..clear()
          ..addAll(_before);
        for (var r = math.min(from.$2, at.$2); r <= math.max(from.$2, at.$2); r++) {
          for (var c = math.min(from.$1, at.$1); c <= math.max(from.$1, at.$1); c++) {
            _put(c, r);
          }
        }
      case TileTool.fill:
        var (c0, r0, c1, r1) = m.window;
        for (var k in floodCells(cells, at, (c0, r0, c1, r1))) {
          _put(colOf(k), rowOf(k));
        }
      case TileTool.paint || TileTool.erase:
        _put(at.$1, at.$2);
      case TileTool.picker:
        break;
    }
    _show(m);
  }

  void _put(int c, int r) {
    if (tool == TileTool.erase) {
      _cells!.remove(cellKey(c, r));
    } else {
      _cells![cellKey(c, r)] = brush.word;
    }
  }

  void _show(TileMapElement m) {
    _working = m.withLayer(layer, m.layers[layer].copyWith(cells: Map.unmodifiable(_cells!)));
    _shown();
  }

  /// strokeEnd lifts the pen: what was laid kept, as one change.
  void strokeEnd() {
    var done = _working;
    _working = null;
    _cells = null;
    _from = null;
    _before = const {};
    if (done != null && !mapEquals(done.layers[layer].cells, map?.layers[layer].cells)) {
      controller.beginInteraction();
      controller.replaceElement(done);
      controller.endInteraction();
    }
    _shown();
  }
}

/// cellsAlong is the cells a straight line from [a] to [b] goes through,
/// each touching the last: Bresenham's.
List<(int, int)> cellsAlong((int, int) a, (int, int) b) {
  var (x0, y0) = a;
  var (x1, y1) = b;
  var dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
  var sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  var err = dx + dy;
  var out = <(int, int)>[];
  while (true) {
    out.add((x0, y0));
    if (x0 == x1 && y0 == y1) break;
    var e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
  return out;
}

/// floodCells is the cells joined to [start] side by side that hold what
/// it holds -- the same tile, or nothing -- within [within]: the first and
/// last column and row. A map goes on for ever; a fill stops at the window.
Set<int> floodCells(Map<int, int> cells, (int, int) start, (int, int, int, int) within) {
  var (c0, r0, c1, r1) = within;
  var (sc, sr) = start;
  if (sc < c0 || sc > c1 || sr < r0 || sr > r1) return const {};
  var like = cells[cellKey(sc, sr)];
  var seen = <int>{};
  var queue = Queue<(int, int)>()..add(start);
  while (queue.isNotEmpty) {
    var (c, r) = queue.removeFirst();
    if (c < c0 || c > c1 || r < r0 || r > r1) continue;
    var k = cellKey(c, r);
    if (seen.contains(k) || cells[k] != like) continue;
    seen.add(k);
    queue.addAll([(c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)]);
  }
  return seen;
}

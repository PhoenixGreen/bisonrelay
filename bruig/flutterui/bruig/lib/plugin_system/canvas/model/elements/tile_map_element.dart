import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// tile_map_element.dart is the Tile map element: a scene painted from tile
// sets -- sheets of tiles, each sliced by a grid -- onto a grid of cells,
// as Godot's TileMapLayer and Tiled paint a game's levels. It has layers,
// one over another -- the ground, the paths on it, the walls -- each a
// sparse map of the cells painted, and each cell a tile: which set, which
// tile in it, and whether flipped or turned. The element's box is a window
// onto the map: made bigger it shows more of it, not the tiles bigger.

/// TileRef is a tile as painted in a cell: the set it is from, its number
/// in the set, and how it is turned -- flipped across, flipped down, and
/// its across and down swapped, the three Tiled and Godot turn a tile with;
/// together they make its eight ways round.
extension type const TileRef(int word) {
  static const int _flipX = 1 << 28, _flipY = 1 << 29, _swap = 1 << 30;

  factory TileRef.of(int source, int index, {bool flipX = false, bool flipY = false, bool swap = false}) =>
      TileRef((source & 0xFF) << 20 |
          (index & 0xFFFFF) |
          (flipX ? _flipX : 0) |
          (flipY ? _flipY : 0) |
          (swap ? _swap : 0));

  int get source => (word >> 20) & 0xFF;
  int get index => word & 0xFFFFF;
  bool get flipX => word & _flipX != 0;
  bool get flipY => word & _flipY != 0;
  bool get swap => word & _swap != 0;

  /// turned is whether it is drawn other than as it is on its sheet.
  bool get turned => word & (_flipX | _flipY | _swap) != 0;

  /// plain is the tile, as it is on its sheet.
  TileRef get plain => TileRef(word & 0x0FFFFFFF);

  TileRef flippedX() => TileRef(word ^ _flipX);
  TileRef flippedY() => TileRef(word ^ _flipY);

  /// matrix is how a tile's pixels are moved about its middle: across and
  /// down swapped first, then flipped -- [[a, b], [c, d]] as (a, b, c, d).
  (int, int, int, int) get matrix {
    var fx = flipX ? -1 : 1, fy = flipY ? -1 : 1;
    return swap ? (0, fx, fy, 0) : (fx, 0, 0, fy);
  }

  /// turnedRight is it turned a quarter round clockwise, flipped or not as
  /// it was.
  TileRef turnedRight() {
    var (a, b, c, d) = matrix;
    // A quarter round, down the page being y: (x, y) to (-y, x).
    var (na, nb, nc, nd) = (-c, -d, a, b);
    var swapped = na == 0;
    var fx = swapped ? nb : na, fy = swapped ? nc : nd;
    return TileRef.of(source, index, flipX: fx < 0, flipY: fy < 0, swap: swapped);
  }
}

/// cellKey is cell ([col], [row]) as a map key; colOf and rowOf it back.
/// A map runs from -32768 to 32767 each way.
int cellKey(int col, int row) => ((row + 0x8000) & 0xFFFF) << 16 | ((col + 0x8000) & 0xFFFF);
int colOf(int key) => (key & 0xFFFF) - 0x8000;
int rowOf(int key) => ((key >> 16) & 0xFFFF) - 0x8000;

/// TileSource is a tile set: a stored sheet of tiles and the grid it is
/// sliced by -- each tile so many pixels across and down, so far in from
/// the sheet's edge, so far apart.
class TileSource {
  final String sheet;
  final String name;
  final int sheetW, sheetH;
  final int tileW, tileH;
  final int margin, spacing;

  const TileSource({
    required this.sheet,
    this.name = "",
    required this.sheetW,
    required this.sheetH,
    required this.tileW,
    required this.tileH,
    this.margin = 0,
    this.spacing = 0,
  });

  int get columns => math.max(1, (sheetW - 2 * margin + spacing) ~/ math.max(1, tileW + spacing));
  int get rows => math.max(1, (sheetH - 2 * margin + spacing) ~/ math.max(1, tileH + spacing));
  int get count => columns * rows;

  /// tileRect is where tile [i] is on the sheet, in its pixels.
  Rect tileRect(int i) {
    var col = i % columns, row = i ~/ columns;
    return Rect.fromLTWH((margin + col * (tileW + spacing)).toDouble(),
        (margin + row * (tileH + spacing)).toDouble(), tileW.toDouble(), tileH.toDouble());
  }

  /// tileAt is the tile at [p] on the sheet, or null between them or off it.
  int? tileAt(Offset p) {
    var col = ((p.dx - margin) / (tileW + spacing)).floor();
    var row = ((p.dy - margin) / (tileH + spacing)).floor();
    if (col < 0 || row < 0 || col >= columns || row >= rows) return null;
    var i = row * columns + col;
    return tileRect(i).contains(p) ? i : null;
  }

  TileSource copyWith({String? sheet, String? name, int? sheetW, int? sheetH, int? tileW, int? tileH,
          int? margin, int? spacing}) =>
      TileSource(
        sheet: sheet ?? this.sheet,
        name: name ?? this.name,
        sheetW: sheetW ?? this.sheetW,
        sheetH: sheetH ?? this.sheetH,
        tileW: math.max(1, tileW ?? this.tileW),
        tileH: math.max(1, tileH ?? this.tileH),
        margin: math.max(0, margin ?? this.margin),
        spacing: math.max(0, spacing ?? this.spacing),
      );

  Map<String, dynamic> toJson() => {
        "sheet": sheet,
        if (name.isNotEmpty) "name": name,
        "w": sheetW,
        "h": sheetH,
        "tw": tileW,
        "th": tileH,
        if (margin != 0) "margin": margin,
        if (spacing != 0) "spacing": spacing,
      };

  static TileSource? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var sheet = json["sheet"];
    if (sheet is! String || sheet.isEmpty) return null;
    int n(String k, int or) => jsonDouble(json[k], or.toDouble()).round();
    return TileSource(
      sheet: sheet,
      name: json["name"] as String? ?? "",
      sheetW: n("w", 1).clamp(1, 1 << 15),
      sheetH: n("h", 1).clamp(1, 1 << 15),
      tileW: n("tw", 16).clamp(1, 4096),
      tileH: n("th", 16).clamp(1, 4096),
      margin: n("margin", 0).clamp(0, 4096),
      spacing: n("spacing", 0).clamp(0, 4096),
    );
  }
}

/// TileLayer is one layer of a map: its cells painted, and how it is laid
/// over the ones under it.
class TileLayer {
  final String name;

  /// cells is the cells painted, by [cellKey], each its tile's [TileRef]
  /// word.
  final Map<int, int> cells;
  final bool visible;
  final bool locked;
  final double opacity;
  final Color? tint;

  const TileLayer({
    this.name = "Layer",
    this.cells = const {},
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.tint,
  });

  TileRef? at(int col, int row) {
    var w = cells[cellKey(col, row)];
    return w == null ? null : TileRef(w);
  }

  TileLayer copyWith({
    String? name,
    Map<int, int>? cells,
    bool? visible,
    bool? locked,
    double? opacity,
    Color? tint,
    bool noTint = false,
  }) =>
      TileLayer(
        name: name ?? this.name,
        cells: cells ?? this.cells,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
        tint: noTint ? null : (tint ?? this.tint),
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        // Flat, three numbers a cell: column, row, tile.
        "cells": [
          for (var e in cells.entries) ...[colOf(e.key), rowOf(e.key), e.value]
        ],
        if (!visible) "hidden": true,
        if (locked) "locked": true,
        if (opacity != 1) "opacity": opacity,
        if (tint != null) "tint": colorToJson(tint!),
      };

  static TileLayer fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const TileLayer();
    var cells = <int, int>{};
    if (json["cells"] case List raw) {
      for (var i = 0; i + 2 < raw.length; i += 3) {
        var (c, r, w) = (raw[i], raw[i + 1], raw[i + 2]);
        if (c is num && r is num && w is num) cells[cellKey(c.toInt(), r.toInt())] = w.toInt();
      }
    }
    return TileLayer(
      name: json["name"] as String? ?? "Layer",
      cells: cells,
      visible: !jsonBool(json["hidden"], false),
      locked: jsonBool(json["locked"], false),
      opacity: jsonDouble(json["opacity"], 1).clamp(0.0, 1.0),
      tint: json["tint"] is num ? colorFromJson(json["tint"]) : null,
    );
  }
}

/// TileMapElement is a map of tiles on the canvas.
class TileMapElement extends CanvasElement {
  final List<TileSource> sources;

  /// layers is its layers, the first at the bottom.
  final List<TileLayer> layers;

  /// cell is how wide a cell is on the canvas; its height is in the first
  /// set's tiles' shape. A bigger tile than that stands up out of its cell,
  /// on the cell's bottom, as Godot draws one.
  final double cell;

  /// pixelArt draws the tiles' pixels square, not smoothed.
  final bool pixelArt;

  const TileMapElement(
    super.base, {
    this.sources = const [],
    this.layers = const [TileLayer(name: "Ground")],
    this.cell = 32,
    this.pixelArt = true,
  });

  @override
  ElementKind get kind => ElementKind.tileMap;

  @override
  Set<String> get assetIds => {for (var s in sources) s.sheet};

  @override
  CanvasElement rebase(ElementBase base) =>
      TileMapElement(base, sources: sources, layers: layers, cell: cell, pixelArt: pixelArt);

  /// scale is how many of the canvas's pixels a tile's pixel is drawn.
  double get scale => sources.isEmpty ? 1 : cell / sources.first.tileW;

  /// cellSize is a cell's size on the canvas.
  Size get cellSize => sources.isEmpty ? Size(cell, cell) : Size(cell, sources.first.tileH * scale);

  /// cellAt is the cell under [p], a point on the canvas.
  (int, int) cellAt(Offset p) {
    var s = cellSize, b = bounds;
    return (((p.dx - b.left) / s.width).floor(), ((p.dy - b.top) / s.height).floor());
  }

  /// cellRect is cell ([col], [row]) on the canvas.
  Rect cellRect(int col, int row) {
    var s = cellSize, b = bounds;
    return Rect.fromLTWH(b.left + col * s.width, b.top + row * s.height, s.width, s.height);
  }

  /// window is the cells the box shows, as the first and last column and
  /// row: those any part of is inside it.
  (int, int, int, int) get window {
    var s = cellSize, b = bounds;
    return (0, 0, math.max(0, (b.width / s.width).ceil() - 1), math.max(0, (b.height / s.height).ceil() - 1));
  }

  /// extent is the cells painted on any layer, first and last column and
  /// row, or null with none.
  (int, int, int, int)? get extent {
    int? c0, r0, c1, r1;
    for (var l in layers) {
      for (var k in l.cells.keys) {
        var c = colOf(k), r = rowOf(k);
        c0 = c0 == null ? c : math.min(c0, c);
        c1 = c1 == null ? c : math.max(c1, c);
        r0 = r0 == null ? r : math.min(r0, r);
        r1 = r1 == null ? r : math.max(r1, r);
      }
    }
    return c0 == null ? null : (c0, r0!, c1!, r1!);
  }

  /// tileCount is how many cells are painted, on every layer.
  int get tileCount => layers.fold(0, (n, l) => n + l.cells.length);

  TileMapElement copyWith({List<TileSource>? sources, List<TileLayer>? layers, double? cell, bool? pixelArt}) =>
      TileMapElement(base,
          sources: sources ?? this.sources,
          layers: layers ?? this.layers,
          cell: (cell ?? this.cell).clamp(2.0, 512.0),
          pixelArt: pixelArt ?? this.pixelArt);

  TileMapElement withLayer(int i, TileLayer layer) =>
      copyWith(layers: [for (var (k, l) in layers.indexed) k == i ? layer : l]);

  /// withoutSource is it with tile set [s] taken out, and every tile of it
  /// rubbed out; the sets after it move up one.
  TileMapElement withoutSource(int s) {
    return copyWith(
      sources: [for (var (k, x) in sources.indexed) if (k != s) x],
      layers: [
        for (var l in layers)
          l.copyWith(cells: {
            for (var e in l.cells.entries)
              if (TileRef(e.value).source != s)
                e.key: TileRef(e.value).source > s ? e.value - (1 << 20) : e.value,
          }),
      ],
    );
  }

  @override
  Map<String, dynamic> props() => {
        "sources": [for (var s in sources) s.toJson()],
        "layers": [for (var l in layers) l.toJson()],
        "cell": cell,
        if (!pixelArt) "pixelArt": false,
      };

  factory TileMapElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    var layers = [
      if (json["layers"] case List raw)
        for (var l in raw) TileLayer.fromJson(l),
    ];
    return TileMapElement(
      b,
      sources: [
        if (json["sources"] case List raw)
          for (var s in raw)
            if (TileSource.fromJson(s) case var source?) source,
      ],
      layers: layers.isEmpty ? const [TileLayer(name: "Ground")] : layers,
      cell: jsonDouble(json["cell"], 32).clamp(2.0, 512.0),
      pixelArt: jsonBool(json["pixelArt"], true),
    );
  }
}

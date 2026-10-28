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

  /// animations is the tiles that play, by the tile painted: the tiles it
  /// shows in turn, and how many a second -- water, a torch, a flag.
  final Map<int, TileAnimation> animations;

  /// terrains is its terrain sets: tiles told apart by what they are at
  /// their corners and sides, so a terrain painted finds its own edges.
  final List<TerrainSet> terrains;

  const TileSource({
    required this.sheet,
    this.name = "",
    required this.sheetW,
    required this.sheetH,
    required this.tileW,
    required this.tileH,
    this.margin = 0,
    this.spacing = 0,
    this.animations = const {},
    this.terrains = const [],
  });

  /// shownAt is the tile [index] shows [seconds] in: itself, or the frame
  /// of its animation it has got to.
  int shownAt(int index, double seconds) {
    var a = animations[index];
    if (a == null || a.frames.length < 2) return index;
    return a.frames[(seconds * a.fps).floor() % a.frames.length];
  }

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

  TileSource copyWith(
          {String? sheet,
          String? name,
          int? sheetW,
          int? sheetH,
          int? tileW,
          int? tileH,
          int? margin,
          int? spacing,
          Map<int, TileAnimation>? animations,
          List<TerrainSet>? terrains}) =>
      TileSource(
        animations: animations ?? this.animations,
        terrains: terrains ?? this.terrains,
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
        if (animations.isNotEmpty)
          "animations": {for (var e in animations.entries) "${e.key}": e.value.toJson()},
        if (terrains.isNotEmpty) "terrains": [for (var t in terrains) t.toJson()],
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
      animations: {
        if (json["animations"] case Map raw)
          for (var e in raw.entries)
            if ((int.tryParse("${e.key}"), TileAnimation.fromJson(e.value)) case (var k?, var a?)) k: a,
      },
      terrains: [
        if (json["terrains"] case List raw)
          for (var t in raw)
            if (TerrainSet.fromJson(t) case var set?) set,
      ],
    );
  }
}

/// TerrainMode is what a terrain set's tiles are told apart by, as Godot's
/// are: their corners -- ponds, patches, the grass round them -- their
/// sides -- a path, a fence -- or both, a set of 47 that join every way.
enum TerrainMode {
  corners("Corners"),
  sides("Sides"),
  both("Corners and sides");

  final String label;
  const TerrainMode(this.label);
}

/// The places on a tile a terrain is told by, in a tag: its middle, then
/// round it from the top, clockwise.
const int tagCentre = 0, tagTop = 1, tagTopRight = 2, tagRight = 3, tagBottomRight = 4;
const int tagBottom = 5, tagBottomLeft = 6, tagLeft = 7, tagTopLeft = 8;

/// tagCorners and tagSides are the corners and the sides, clockwise from
/// the top; tagStep is the way to the cell each one looks to.
const List<int> tagCorners = [tagTopRight, tagBottomRight, tagBottomLeft, tagTopLeft];
const List<int> tagSides = [tagTop, tagRight, tagBottom, tagLeft];
const List<(int, int)> tagStep = [(0, 0), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)];

/// Terrain is one terrain of a set: grass, water, a path; and the tile that
/// is all of it, its colour told from.
class Terrain {
  final String name;
  final Color color;
  final int? sample;
  const Terrain(this.name, this.color, {this.sample});

  Map<String, dynamic> toJson() => {"name": name, "color": colorToJson(color), if (sample != null) "sample": sample};

  static Terrain? fromJson(Object? json) {
    if (json is! Map) return null;
    return Terrain(json["name"] as String? ?? "Terrain",
        json["color"] is num ? colorFromJson(json["color"]) : const Color(0xFF888888),
        sample: (json["sample"] as num?)?.toInt());
  }
}

/// TerrainSet is terrains whose tiles join one another, and what each
/// tile of them is where: by the tile, nine terrains -- its middle, then
/// round it from the top, clockwise; -1 where it is nothing.
class TerrainSet {
  final String name;
  final TerrainMode mode;
  final List<Terrain> terrains;
  final Map<int, List<int>> tags;
  const TerrainSet(this.name, {this.mode = TerrainMode.corners, this.terrains = const [], this.tags = const {}});

  /// places is the places on a tile its mode tells tiles apart by.
  List<int> get places => switch (mode) {
        TerrainMode.corners => tagCorners,
        TerrainMode.sides => [tagCentre, ...tagSides],
        TerrainMode.both => [tagCentre, ...tagSides, ...tagCorners],
      };

  TerrainSet copyWith({String? name, TerrainMode? mode, List<Terrain>? terrains, Map<int, List<int>>? tags}) =>
      TerrainSet(name ?? this.name,
          mode: mode ?? this.mode, terrains: terrains ?? this.terrains, tags: tags ?? this.tags);

  /// tagged is it with tile [tile]'s place [place] made terrain [t] -- or,
  /// with every place nothing, the tile untagged.
  TerrainSet tagged(int tile, int place, int t) {
    var tag = [...(tags[tile] ?? List.filled(9, -1))];
    tag[place] = t;
    var next = {...tags};
    if (tag.every((x) => x < 0)) {
      next.remove(tile);
    } else {
      next[tile] = tag;
    }
    return copyWith(tags: next);
  }

  Map<String, dynamic> toJson() => {
        "name": name,
        "mode": mode.name,
        "terrains": [for (var t in terrains) t.toJson()],
        "tags": {for (var e in tags.entries) "${e.key}": e.value},
      };

  static TerrainSet? fromJson(Object? json) {
    if (json is! Map) return null;
    return TerrainSet(
      json["name"] as String? ?? "Terrain",
      mode: TerrainMode.values.where((m) => m.name == json["mode"]).firstOrNull ?? TerrainMode.corners,
      terrains: [
        if (json["terrains"] case List raw)
          for (var t in raw)
            if (Terrain.fromJson(t) case var terrain?) terrain,
      ],
      tags: {
        if (json["tags"] case Map raw)
          for (var e in raw.entries)
            if ((int.tryParse("${e.key}"), e.value) case (var k?, List v) when v.length == 9)
              k: [for (var x in v) x is num ? x.toInt() : -1],
      },
    );
  }
}

/// TileAnimation is a tile that plays: the tiles shown in turn, and how
/// many a second.
class TileAnimation {
  final List<int> frames;
  final double fps;
  const TileAnimation(this.frames, {this.fps = 4});

  Map<String, dynamic> toJson() => {"frames": frames, "fps": fps};

  static TileAnimation? fromJson(Object? json) {
    if (json is! Map) return null;
    var frames = [
      if (json["frames"] case List raw)
        for (var f in raw)
          if (f is num) f.toInt(),
    ];
    if (frames.isEmpty) return null;
    return TileAnimation(frames, fps: jsonDouble(json["fps"], 4).clamp(0.25, 60.0));
  }
}

/// TileObject is a thing stood on an objects layer anywhere, not in a
/// cell: a tree, a rock, a lamp post -- a stamp, standing with the middle
/// of its bottom at ([x], [y]), counted in cells from the map's top left.
class TileObject {
  final double x, y;
  final TileStamp stamp;
  const TileObject(this.x, this.y, this.stamp);

  TileObject movedTo(double x, double y) => TileObject(x, y, stamp);

  /// toJson is its place, then its stamp, flat.
  List<num> toJson() => [x, y, ...stamp.toJson()];

  static TileObject? fromJson(Object? json) {
    if (json is! List || json.length < 5 || json[0] is! num || json[1] is! num) return null;
    var stamp = TileStamp.fromJson(json.sublist(2));
    if (stamp == null) return null;
    return TileObject((json[0] as num).toDouble(), (json[1] as num).toDouble(), stamp);
  }
}

/// TileStamp is tiles laid together -- a pattern: a doorway, a tree of
/// four tiles, a stretch of fence -- each at its place from the stamp's top
/// left; or, painted at random, the tiles picked from.
class TileStamp {
  final List<(int, int, TileRef)> cells;
  const TileStamp(this.cells);

  TileStamp.one(TileRef t) : cells = [(0, 0, t)];

  int get width => cells.isEmpty ? 1 : cells.map((c) => c.$1).reduce(math.max) + 1;
  int get height => cells.isEmpty ? 1 : cells.map((c) => c.$2).reduce(math.max) + 1;
  TileRef get first => cells.isEmpty ? TileRef.of(0, 0) : cells.first.$3;

  TileRef? at(int col, int row) {
    for (var (c, r, t) in cells) {
      if (c == col && r == row) return t;
    }
    return null;
  }

  /// of is the tiles in [cells] -- by [cellKey] -- from column [c0] to
  /// [c1] and row [r0] to [r1], as a stamp from its first painted cell's
  /// row and column; null with none.
  static TileStamp? of(Map<int, int> cells, int c0, int r0, int c1, int r1) {
    var found = <(int, int, TileRef)>[];
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (cells[cellKey(c, r)] case var w?) found.add((c, r, TileRef(w)));
      }
    }
    if (found.isEmpty) return null;
    var left = found.map((f) => f.$1).reduce(math.min), top = found.map((f) => f.$2).reduce(math.min);
    return TileStamp([for (var (c, r, t) in found) (c - left, r - top, t)]);
  }

  TileStamp flippedX() {
    var w = width;
    return TileStamp([for (var (c, r, t) in cells) (w - 1 - c, r, t.flippedX())]);
  }

  TileStamp flippedY() {
    var h = height;
    return TileStamp([for (var (c, r, t) in cells) (c, h - 1 - r, t.flippedY())]);
  }

  /// turnedRight is the stamp turned a quarter round clockwise, each tile
  /// in it turned with it.
  TileStamp turnedRight() {
    var h = height;
    return TileStamp([for (var (c, r, t) in cells) (h - 1 - r, c, t.turnedRight())]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! TileStamp || other.cells.length != cells.length) return false;
    for (var i = 0; i < cells.length; i++) {
      if (other.cells[i] != cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(cells);

  /// toJson is flat, three numbers a tile: column, row, tile.
  List<int> toJson() => [
        for (var (c, r, t) in cells) ...[c, r, t.word]
      ];

  static TileStamp? fromJson(Object? json) {
    if (json is! List) return null;
    var cells = <(int, int, TileRef)>[];
    for (var i = 0; i + 2 < json.length; i += 3) {
      var (c, r, w) = (json[i], json[i + 1], json[i + 2]);
      if (c is num && r is num && w is num) cells.add((c.toInt(), r.toInt(), TileRef(w.toInt())));
    }
    return cells.isEmpty ? null : TileStamp(cells);
  }
}

/// TileLayer is one layer of a map: its cells painted, and how it is laid
/// over the ones under it.
class TileLayer {
  final String name;

  /// cells is the cells painted, by [cellKey], each its tile's [TileRef]
  /// word.
  final Map<int, int> cells;

  /// isObjects is whether it is an objects layer: things stood anywhere --
  /// [objects] -- and figures, Sprite elements of the canvas drawn among
  /// them, each by where its feet are, the nearer the reader in front.
  final bool isObjects;
  final List<TileObject> objects;

  /// figures is the ids of the Sprite elements on the layer.
  final List<String> figures;
  final bool visible;
  final bool locked;
  final double opacity;
  final Color? tint;

  const TileLayer({
    this.name = "Layer",
    this.cells = const {},
    this.isObjects = false,
    this.objects = const [],
    this.figures = const [],
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
    List<TileObject>? objects,
    List<String>? figures,
    bool? visible,
    bool? locked,
    double? opacity,
    Color? tint,
    bool noTint = false,
  }) =>
      TileLayer(
        name: name ?? this.name,
        cells: cells ?? this.cells,
        isObjects: isObjects,
        objects: objects ?? this.objects,
        figures: figures ?? this.figures,
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
        if (isObjects) "kind": "objects",
        if (objects.isNotEmpty) "objects": [for (var o in objects) o.toJson()],
        if (figures.isNotEmpty) "figures": figures,
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
      isObjects: json["kind"] == "objects",
      objects: [
        if (json["objects"] case List raw)
          for (var o in raw)
            if (TileObject.fromJson(o) case var object?) object,
      ],
      figures: [
        if (json["figures"] case List raw)
          for (var f in raw)
            if (f is String) f,
      ],
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

  /// patterns is the stamps kept with the map, to paint with again.
  final List<TileStamp> patterns;

  const TileMapElement(
    super.base, {
    this.sources = const [],
    this.layers = const [TileLayer(name: "Ground")],
    this.cell = 32,
    this.pixelArt = true,
    this.patterns = const [],
  });

  @override
  ElementKind get kind => ElementKind.tileMap;

  @override
  Set<String> get assetIds => {for (var s in sources) s.sheet};

  @override
  CanvasElement rebase(ElementBase base) =>
      TileMapElement(base, sources: sources, layers: layers, cell: cell, pixelArt: pixelArt, patterns: patterns);

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

  /// tileCount is how many cells are painted and things stood, on every
  /// layer.
  int get tileCount => layers.fold(0, (n, l) => n + l.cells.length + l.objects.length);

  /// figureIds is the Sprite elements stood on its objects layers.
  Set<String> get figureIds => {
        for (var l in layers)
          if (l.visible) ...l.figures,
      };

  /// objectRect is where [o] stands on the canvas.
  Rect objectRect(TileObject o) {
    var cs = cellSize, b = bounds;
    var w = o.stamp.width * cs.width, h = o.stamp.height * cs.height;
    var foot = Offset(b.left + o.x * cs.width, b.top + o.y * cs.height);
    return Rect.fromLTWH(foot.dx - w / 2, foot.dy - h, w, h);
  }

  /// inCells is canvas point [p] counted in cells from the map's top left.
  Offset inCells(Offset p) {
    var cs = cellSize, b = bounds;
    return Offset((p.dx - b.left) / cs.width, (p.dy - b.top) / cs.height);
  }

  TileMapElement copyWith(
          {List<TileSource>? sources,
          List<TileLayer>? layers,
          double? cell,
          bool? pixelArt,
          List<TileStamp>? patterns}) =>
      TileMapElement(base,
          sources: sources ?? this.sources,
          layers: layers ?? this.layers,
          cell: (cell ?? this.cell).clamp(2.0, 512.0),
          pixelArt: pixelArt ?? this.pixelArt,
          patterns: patterns ?? this.patterns);

  TileMapElement withLayer(int i, TileLayer layer) =>
      copyWith(layers: [for (var (k, l) in layers.indexed) k == i ? layer : l]);

  /// withoutSource is it with tile set [s] taken out, and every tile of it
  /// rubbed out; the sets after it move up one.
  TileMapElement withoutSource(int s) {
    TileRef moved(TileRef t) => t.source > s ? TileRef(t.word - (1 << 20)) : t;
    return copyWith(
      sources: [for (var (k, x) in sources.indexed) if (k != s) x],
      patterns: [
        for (var p in patterns)
          if (p.cells.every((c) => c.$3.source != s)) TileStamp([for (var (c, r, t) in p.cells) (c, r, moved(t))]),
      ],
      layers: [
        for (var l in layers)
          l.copyWith(cells: {
            for (var e in l.cells.entries)
              if (TileRef(e.value).source != s)
                e.key: TileRef(e.value).source > s ? e.value - (1 << 20) : e.value,
          }, objects: [
            for (var o in l.objects)
              if (o.stamp.cells.every((c) => c.$3.source != s))
                TileObject(o.x, o.y, TileStamp([for (var (c, r, t) in o.stamp.cells) (c, r, moved(t))])),
          ]),
      ],
    );
  }

  @override
  Map<String, dynamic> props() => {
        "sources": [for (var s in sources) s.toJson()],
        "layers": [for (var l in layers) l.toJson()],
        "cell": cell,
        if (!pixelArt) "pixelArt": false,
        if (patterns.isNotEmpty) "patterns": [for (var p in patterns) p.toJson()],
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
      patterns: [
        if (json["patterns"] case List raw)
          for (var p in raw)
            if (TileStamp.fromJson(p) case var stamp?) stamp,
      ],
    );
  }
}

import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// layout_element.dart is a Layout: one element that divides its box into
// cells, three ways (Ken, 2026-11-18):
//
//  - Panels, a comic page's way: cells made by cutting a cell in two, again
//    and again. Each cut has its own place, tilt and gutter; moving a cut
//    moves both cells beside it.
//  - Grid, a page of cards: columns and rows of any weight, the gaps
//    between them, and cells spanning several.
//  - Free: cells of any of a few shapes, put anywhere.
//
// Each cell is styled on its own (a BoxSpec: fill, picture, border,
// corners), or by the layout's cell style. What is round the cells -- the
// gutters and the margin -- is clear unless given a colour, so what is
// behind the layout shows. Other elements can be docked into a cell
// (ElementBase.dock): drawn clipped to it, and moved and sized with it.
// Where the cells fall is layout_geometry.dart.

enum LayoutMode {
  panels("Panels"),
  grid("Grid"),
  free("Free");

  final String label;
  const LayoutMode(this.label);

  static LayoutMode fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => panels);
}

/// LayoutCellShape is a free cell's outline.
enum LayoutCellShape {
  rectangle("Rectangle"),
  ellipse("Ellipse"),
  triangle("Triangle"),
  diamond("Diamond"),
  hexagon("Hexagon"),
  star("Star");

  final String label;
  const LayoutCellShape(this.label);

  static LayoutCellShape fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => rectangle);
}

/// LayoutNode is a node of a Panels layout's tree of cuts: a cell, or a cut
/// across the box it is given into two more nodes.
class LayoutNode {
  /// cell is a leaf's cell, by id; empty for a cut.
  final String cell;

  /// vertical is a cut from top to bottom, putting [a] on the left and [b]
  /// on the right; otherwise across, [a] above and [b] below.
  final bool vertical;

  /// at is where the cut crosses its box, from the left (or top), 0..1.
  final double at;

  /// tilt turns the cut about its middle, in degrees, for a comic page's
  /// slanted gutters.
  final double tilt;

  /// gutter is this cut's own gap, or null for the layout's.
  final double? gutter;

  final LayoutNode? a, b;

  const LayoutNode.leaf(this.cell)
      : vertical = false,
        at = 0.5,
        tilt = 0,
        gutter = null,
        a = null,
        b = null;

  const LayoutNode.cut(
      {required this.vertical,
      this.at = 0.5,
      this.tilt = 0,
      this.gutter,
      required LayoutNode this.a,
      required LayoutNode this.b})
      : cell = "";

  bool get isLeaf => a == null || b == null;

  LayoutNode withCut(
          {double? at,
          double? tilt,
          double? gutter,
          bool? vertical,
          bool clearGutter = false}) =>
      isLeaf
          ? this
          : LayoutNode.cut(
              vertical: vertical ?? this.vertical,
              at: (at ?? this.at).clamp(0.02, 0.98),
              tilt: (tilt ?? this.tilt).clamp(-60.0, 60.0),
              gutter: clearGutter ? null : (gutter ?? this.gutter),
              a: a!,
              b: b!);

  /// cells is every cell under this node, left to right, top to bottom.
  List<String> get cells => isLeaf ? [cell] : [...a!.cells, ...b!.cells];

  /// pathTo is the way down to [cell] (false for [a], true for [b]), or
  /// null where it is not under this node.
  List<bool>? pathTo(String cell) {
    if (isLeaf) return this.cell == cell ? [] : null;
    var left = a!.pathTo(cell);
    if (left != null) return [false, ...left];
    var right = b!.pathTo(cell);
    if (right != null) return [true, ...right];
    return null;
  }

  /// at follows [path] down.
  LayoutNode? nodeAt(List<bool> path) {
    var n = this;
    for (var step in path) {
      if (n.isLeaf) return null;
      n = step ? n.b! : n.a!;
    }
    return n;
  }

  /// replaced is this tree with the node at [path] made [next].
  LayoutNode replaced(List<bool> path, LayoutNode next) {
    if (path.isEmpty) return next;
    if (isLeaf) return this;
    var rest = path.sublist(1);
    return LayoutNode.cut(
        vertical: vertical,
        at: at,
        tilt: tilt,
        gutter: gutter,
        a: path.first ? a! : a!.replaced(rest, next),
        b: path.first ? b!.replaced(rest, next) : b!);
  }

  Map<String, dynamic> toJson() => isLeaf
      ? {"cell": cell}
      : {
          if (vertical) "v": true,
          "at": at,
          if (tilt != 0) "tilt": tilt,
          if (gutter != null) "gutter": gutter,
          "a": a!.toJson(),
          "b": b!.toJson(),
        };

  /// fromJson reads a tree at most [depth] deep: a received file's tree of
  /// a million cuts would be walked on every frame.
  static LayoutNode fromJson(Object? j, {int depth = 12}) {
    if (j is! Map) return LayoutNode.leaf(newElementId());
    var a = j["a"], b = j["b"];
    if (depth <= 0 || a == null || b == null) {
      return LayoutNode.leaf(jsonId(j["cell"], newElementId()));
    }
    return LayoutNode.cut(
      vertical: jsonBool(j["v"], false),
      at: jsonDouble(j["at"], 0.5).clamp(0.02, 0.98),
      tilt: jsonDouble(j["tilt"], 0).clamp(-60.0, 60.0),
      gutter: j["gutter"] is num
          ? jsonDouble(j["gutter"], 0).clamp(0.0, 2000.0)
          : null,
      a: fromJson(a, depth: depth - 1),
      b: fromJson(b, depth: depth - 1),
    );
  }
}

/// LayoutCell is one cell: its name and style, and where it is in a Grid or
/// a Free layout (a Panels cell is placed by the tree).
class LayoutCell {
  final String id;
  final String name;

  /// style is this cell's own, or null for the layout's [LayoutElement.cellStyle].
  final BoxSpec? style;

  /// col, row and their spans place a Grid cell, counting from 0.
  final int col, row, colSpan, rowSpan;

  /// x, y, width and height place a Free cell, as shares of the layout's
  /// box; [turn] in degrees, [shape] its outline.
  final double x, y, width, height, turn;
  final LayoutCellShape shape;

  const LayoutCell({
    required this.id,
    this.name = "",
    this.style,
    this.col = 0,
    this.row = 0,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.x = 0.1,
    this.y = 0.1,
    this.width = 0.3,
    this.height = 0.3,
    this.turn = 0,
    this.shape = LayoutCellShape.rectangle,
  });

  LayoutCell copyWith({
    String? id,
    String? name,
    BoxSpec? style,
    bool clearStyle = false,
    int? col,
    int? row,
    int? colSpan,
    int? rowSpan,
    double? x,
    double? y,
    double? width,
    double? height,
    double? turn,
    LayoutCellShape? shape,
  }) =>
      LayoutCell(
        id: id ?? this.id,
        name: name ?? this.name,
        style: clearStyle ? null : (style ?? this.style),
        col: (col ?? this.col).clamp(0, LayoutElement.maxTracks - 1),
        row: (row ?? this.row).clamp(0, LayoutElement.maxTracks - 1),
        colSpan: (colSpan ?? this.colSpan).clamp(1, LayoutElement.maxTracks),
        rowSpan: (rowSpan ?? this.rowSpan).clamp(1, LayoutElement.maxTracks),
        x: x ?? this.x,
        y: y ?? this.y,
        width: (width ?? this.width).clamp(0.005, 10.0),
        height: (height ?? this.height).clamp(0.005, 10.0),
        turn: turn ?? this.turn,
        shape: shape ?? this.shape,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        if (name.isNotEmpty) "name": name,
        if (style != null) "style": style!.toJson(),
        if (col != 0) "col": col,
        if (row != 0) "row": row,
        if (colSpan != 1) "cs": colSpan,
        if (rowSpan != 1) "rs": rowSpan,
        "x": x,
        "y": y,
        "w": width,
        "h": height,
        if (turn != 0) "turn": turn,
        if (shape != LayoutCellShape.rectangle) "shape": shape.name,
      };

  factory LayoutCell.fromJson(Map<String, dynamic> j) => LayoutCell(
        id: jsonId(j["id"], newElementId()),
        name: jsonLabel(j["name"], ""),
        style: j["style"] is Map<String, dynamic>
            ? BoxSpec.fromJson(j["style"] as Map<String, dynamic>)
            : null,
        col: jsonInt(j["col"], 0).clamp(0, LayoutElement.maxTracks - 1),
        row: jsonInt(j["row"], 0).clamp(0, LayoutElement.maxTracks - 1),
        colSpan: jsonInt(j["cs"], 1).clamp(1, LayoutElement.maxTracks),
        rowSpan: jsonInt(j["rs"], 1).clamp(1, LayoutElement.maxTracks),
        x: jsonDouble(j["x"], 0.1).clamp(-10.0, 10.0),
        y: jsonDouble(j["y"], 0.1).clamp(-10.0, 10.0),
        width: jsonDouble(j["w"], 0.3).clamp(0.005, 10.0),
        height: jsonDouble(j["h"], 0.3).clamp(0.005, 10.0),
        turn: jsonDouble(j["turn"], 0).clamp(-360.0, 360.0),
        shape: LayoutCellShape.fromName(jsonStr(j["shape"])),
      );
}

/// LayoutElement is a Layout; see the top of this file.
class LayoutElement extends CanvasElement {
  final LayoutMode mode;

  /// root is a Panels layout's tree of cuts.
  final LayoutNode root;

  /// columns and rows are a Grid's tracks, by weight: [1, 2] is a narrow
  /// column and one twice as wide.
  final List<double> columns, rows;

  /// cells are every cell's name, style and (Grid, Free) place.
  final List<LayoutCell> cells;

  /// gutter is the gap between cells side by side (a vertical cut, a
  /// Grid's columns), rowGutter between cells one above another.
  final double gutter, rowGutter;

  /// margin is the room round all the cells, inside the box.
  final double margin;

  /// gutterColor paints the gutters and margin; clear, they show what is
  /// behind the layout.
  final Color gutterColor;

  /// cellStyle is how a cell with no style of its own is drawn.
  final BoxSpec cellStyle;

  /// order is the cells in the order a reader steps through them in Panel
  /// mode, as set by clicking them in turn; one not in it (cut off since)
  /// is read after, in its own place. [unread] are left out. See [reading].
  final List<String> order, unread;

  const LayoutElement(
    super.base, {
    this.mode = LayoutMode.panels,
    this.root = const LayoutNode.leaf("c1"),
    this.columns = const [1, 1],
    this.rows = const [1, 1],
    this.cells = const [LayoutCell(id: "c1")],
    this.gutter = 24,
    this.rowGutter = 24,
    this.margin = 0,
    this.gutterColor = const Color(0x00000000),
    this.cellStyle = const BoxSpec(
        borderWidth: 4, borderColor: Color(0xFF111111), padding: 0),
    this.order = const [],
    this.unread = const [],
  });

  /// maxTracks and maxCells bound what a received file can ask for.
  static const maxTracks = 24, maxCells = 200;

  @override
  ElementKind get kind => ElementKind.layout;

  @override
  Set<String> get assetIds => {
        ...cellStyle.assetIds,
        for (var c in cells) ...?c.style?.assetIds,
      };

  @override
  CanvasElement rebase(ElementBase base) => LayoutElement(base,
      mode: mode,
      root: root,
      columns: columns,
      rows: rows,
      cells: cells,
      gutter: gutter,
      rowGutter: rowGutter,
      margin: margin,
      gutterColor: gutterColor,
      cellStyle: cellStyle,
      order: order,
      unread: unread);

  LayoutElement copyWith({
    LayoutMode? mode,
    LayoutNode? root,
    List<double>? columns,
    List<double>? rows,
    List<LayoutCell>? cells,
    double? gutter,
    double? rowGutter,
    double? margin,
    Color? gutterColor,
    BoxSpec? cellStyle,
    List<String>? order,
    List<String>? unread,
  }) =>
      LayoutElement(base,
          mode: mode ?? this.mode,
          root: root ?? this.root,
          columns: columns ?? this.columns,
          rows: rows ?? this.rows,
          cells: cells ?? this.cells,
          gutter: (gutter ?? this.gutter).clamp(0.0, 2000.0),
          rowGutter: (rowGutter ?? this.rowGutter).clamp(0.0, 2000.0),
          margin: (margin ?? this.margin).clamp(0.0, 2000.0),
          gutterColor: gutterColor ?? this.gutterColor,
          cellStyle: cellStyle ?? this.cellStyle,
          order: order ?? this.order,
          unread: unread ?? this.unread);

  LayoutCell? cellById(String id) {
    for (var c in cells) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// styleOf is how cell [c] is drawn.
  BoxSpec styleOf(LayoutCell c) => c.style ?? cellStyle;

  /// shownCells are the cells this mode draws: a Panels layout's leaves in
  /// order, every other mode's list.
  List<LayoutCell> get shownCells {
    if (mode != LayoutMode.panels) return cells;
    return [
      for (var id in root.cells) cellById(id) ?? LayoutCell(id: id),
    ];
  }

  /// reading is the cells in the order Panel mode reads them: those in
  /// [order] first, as set, then the rest in their own order -- a Panels
  /// layout's left to right and top to bottom down its cuts, a Grid's row
  /// by row, Free cells as added -- less those [unread].
  List<LayoutCell> get reading {
    var shown = shownCells;
    var own = mode == LayoutMode.grid
        ? ([...shown]..sort((a, b) =>
            a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col)))
        : shown;
    var byId = {for (var c in shown) c.id: c};
    var seen = <String>{...unread};
    return [
      for (var id in order)
        if (byId[id] case var c? when seen.add(id)) c,
      for (var c in own)
        if (seen.add(c.id)) c,
    ];
  }

  /// numberOf is where cell [id] comes in [reading], from 1, or null for
  /// one left out.
  int? numberOf(String id) {
    var i = reading.indexWhere((c) => c.id == id);
    return i < 0 ? null : i + 1;
  }

  /// withCell is this layout with [cell] in place of the one of its id, or
  /// added.
  LayoutElement withCell(LayoutCell cell) => copyWith(cells: [
        for (var c in cells) c.id == cell.id ? cell : c,
        if (cellById(cell.id) == null) cell,
      ]);

  /// split cuts Panels cell [id] in two, the new cell after it ([b]),
  /// styled as it was. Answers the layout and the new cell's id.
  (LayoutElement, String) split(String id, {required bool vertical}) {
    var path = root.pathTo(id);
    var cell = cellById(id) ?? LayoutCell(id: id);
    if (path == null) return (this, id);
    var fresh = newElementId();
    var next = copyWith(
      root: root.replaced(
          path,
          LayoutNode.cut(
              vertical: vertical,
              a: LayoutNode.leaf(id),
              b: LayoutNode.leaf(fresh))),
      cells: [
        ...cells.where((c) => c.id != id),
        cell,
        cell.copyWith(id: fresh, name: ""),
      ],
      // Read straight after the half it was cut from, or left out with it.
      order: [
        for (var o in order) ...[o, if (o == id) fresh]
      ],
      unread: [...unread, if (unread.contains(id)) fresh],
    );
    return (next, fresh);
  }

  /// merge takes away the cut beside Panels cell [id]: it and what was on
  /// the other side are one cell again, [id]. Answers the layout and the
  /// cells gone, whose docked elements move into [id].
  (LayoutElement, List<String>) merge(String id) {
    var path = root.pathTo(id);
    if (path == null || path.isEmpty) return (this, const []);
    var parentPath = path.sublist(0, path.length - 1);
    var parent = root.nodeAt(parentPath)!;
    var gone = [
      for (var c in parent.cells)
        if (c != id) c
    ];
    var next = copyWith(
      root: root.replaced(parentPath, LayoutNode.leaf(id)),
      cells: [
        for (var c in cells)
          if (!gone.contains(c.id)) c
      ],
      order: [
        for (var o in order)
          if (!gone.contains(o)) o
      ],
      unread: [
        for (var o in unread)
          if (!gone.contains(o)) o
      ],
    );
    return (next, gone);
  }

  @override
  Map<String, dynamic> props() => {
        if (mode != LayoutMode.panels) "mode": mode.name,
        "root": root.toJson(),
        "columns": columns,
        "rows": rows,
        "cells": [for (var c in cells) c.toJson()],
        "gutter": gutter,
        "rowGutter": rowGutter,
        if (margin != 0) "margin": margin,
        if (gutterColor.a > 0) "gutterColor": colorToJson(gutterColor),
        "cellStyle": cellStyle.toJson(),
        if (order.isNotEmpty) "order": order,
        if (unread.isNotEmpty) "unread": unread,
      };

  factory LayoutElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    const plain = LayoutElement(ElementBase(id: ""));
    List<double> tracks(Object? v, List<double> fallback) {
      if (v is! List) return fallback;
      var out = [
        for (var x in v.take(maxTracks))
          if (x is num && x.isFinite) x.toDouble().clamp(0.01, 1000.0)
      ];
      return out.isEmpty ? fallback : out;
    }

    var raw = json["cells"];
    List<String> ids(Object? v) => v is List
        ? [
            for (var x in v.take(maxCells))
              if (x is String && x.isNotEmpty && x.length <= 64) x
          ]
        : const [];
    return LayoutElement(b,
        order: ids(json["order"]),
        unread: ids(json["unread"]),
        mode: LayoutMode.fromName(jsonStr(json["mode"])),
        root: json["root"] == null
            ? plain.root
            : LayoutNode.fromJson(json["root"]),
        columns: tracks(json["columns"], plain.columns),
        rows: tracks(json["rows"], plain.rows),
        cells: raw is List
            ? [
                for (var c in raw.take(maxCells))
                  if (c is Map<String, dynamic>) LayoutCell.fromJson(c)
              ]
            : const [],
        gutter: jsonDouble(json["gutter"], 24).clamp(0.0, 2000.0),
        rowGutter: jsonDouble(json["rowGutter"], 24).clamp(0.0, 2000.0),
        margin: jsonDouble(json["margin"], 0).clamp(0.0, 2000.0),
        gutterColor:
            colorFromJson(json["gutterColor"], const Color(0x00000000)),
        cellStyle:
            jsonSpec(json["cellStyle"], BoxSpec.fromJson, plain.cellStyle));
  }
}

/// dockOf is [dock]'s layout and cell ids ("layout:cell"), or null.
(String, String)? dockOf(String dock) {
  var at = dock.indexOf(":");
  if (at <= 0 || at == dock.length - 1) return null;
  return (dock.substring(0, at), dock.substring(at + 1));
}

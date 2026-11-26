import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// layout_presets.dart is the layouts a Layout can start from: comic pages
// cut into panels, pages of cards on a grid, and shapes set out freely.
// Each is made afresh, its cells given new ids, so two copies on a page are
// two sets of cells.

/// LayoutPreset is one starting layout.
enum LayoutPreset {
  threeTiers("Three tiers", LayoutMode.panels),
  sixPanels("Six panels", LayoutMode.panels),
  splash("Splash and a strip", LayoutMode.panels),
  slants("Action slants", LayoutMode.panels),
  fourPanels("Four panels", LayoutMode.panels),
  cards("Two by two cards", LayoutMode.grid),
  hero("One big, three small", LayoutMode.grid),
  bento("Bento", LayoutMode.grid),
  columns("Three columns", LayoutMode.grid),
  circles("Three circles", LayoutMode.free),
  scattered("Scattered frames", LayoutMode.free);

  final String label;
  final LayoutMode mode;
  const LayoutPreset(this.label, this.mode);
}

/// _cardStyle is a card's rounded fill; a comic page's panels are drawn in
/// comicInk.
const _cardStyle = BoxSpec(
    fill: Color(0x22FFFFFF),
    borderRadius: 18,
    borderWidth: 1.5,
    borderColor: Color(0x33FFFFFF),
    padding: 0);

/// layoutFrom is [base]'s layout made as [p] says, keeping nothing of what
/// it was but its place.
LayoutElement layoutFrom(ElementBase base, LayoutPreset p) {
  var cells = <LayoutCell>[];
  LayoutNode leaf() {
    var id = newElementId();
    cells.add(LayoutCell(id: id, name: "Panel ${cells.length + 1}"));
    return LayoutNode.leaf(id);
  }

  LayoutNode cut(bool vertical, double at, LayoutNode a, LayoutNode b,
          {double tilt = 0}) =>
      LayoutNode.cut(vertical: vertical, at: at, tilt: tilt, a: a, b: b);

  LayoutElement panels(LayoutNode Function() build) {
    var root = build();
    return LayoutElement(base,
        root: root,
        cells: cells,
        gutter: 22,
        rowGutter: 26,
        margin: 0,
        gutterColor: const Color(0xFFFFFFFF),
        cellStyle: comicInk);
  }

  LayoutElement grid(List<double> columns, List<double> rows,
      List<(int, int, int, int)> spans) {
    return LayoutElement(base,
        mode: LayoutMode.grid,
        columns: columns,
        rows: rows,
        cells: [
          for (var (i, (c, r, cs, rs)) in spans.indexed)
            LayoutCell(
                id: newElementId(),
                name: "Card ${i + 1}",
                col: c,
                row: r,
                colSpan: cs,
                rowSpan: rs),
        ],
        gutter: 32,
        rowGutter: 32,
        cellStyle: _cardStyle);
  }

  LayoutElement free(
          List<(double, double, double, double, LayoutCellShape)> at) =>
      LayoutElement(base,
          mode: LayoutMode.free,
          cells: [
            for (var (i, (x, y, w, h, shape)) in at.indexed)
              LayoutCell(
                  id: newElementId(),
                  name: "Frame ${i + 1}",
                  x: x,
                  y: y,
                  width: w,
                  height: h,
                  turn: shape == LayoutCellShape.rectangle
                      ? (i.isEven ? -4 : 3)
                      : 0,
                  shape: shape),
          ],
          cellStyle: const BoxSpec(
              fill: Color(0x33FFFFFF),
              borderWidth: 6,
              borderColor: Color(0xFFFFFFFF),
              padding: 0));

  return switch (p) {
    LayoutPreset.threeTiers => panels(() => cut(false, 0.34, leaf(),
        cut(false, 0.5, cut(true, 0.42, leaf(), leaf()), leaf()))),
    LayoutPreset.sixPanels => panels(() => cut(
        false,
        0.34,
        cut(true, 0.5, leaf(), leaf()),
        cut(false, 0.5, cut(true, 0.5, leaf(), leaf()),
            cut(true, 0.5, leaf(), leaf())))),
    LayoutPreset.splash => panels(() => cut(false, 0.66, leaf(),
        cut(true, 0.34, leaf(), cut(true, 0.5, leaf(), leaf())))),
    LayoutPreset.slants => panels(() => cut(
        false,
        0.36,
        cut(true, 0.56, leaf(), leaf(), tilt: 6),
        cut(false, 0.48, leaf(), cut(true, 0.4, leaf(), leaf(), tilt: -5),
            tilt: -2),
        tilt: 2)),
    LayoutPreset.fourPanels => panels(() => cut(false, 0.5,
        cut(true, 0.5, leaf(), leaf()), cut(true, 0.5, leaf(), leaf()))),
    LayoutPreset.cards => grid([1, 1], [1, 1],
        [(0, 0, 1, 1), (1, 0, 1, 1), (0, 1, 1, 1), (1, 1, 1, 1)]),
    LayoutPreset.hero => grid([1, 1, 1], [2, 1],
        [(0, 0, 3, 1), (0, 1, 1, 1), (1, 1, 1, 1), (2, 1, 1, 1)]),
    LayoutPreset.bento => grid([1, 1, 1], [1, 1, 1],
        [(0, 0, 2, 2), (2, 0, 1, 1), (2, 1, 1, 1), (0, 2, 1, 1), (1, 2, 2, 1)]),
    LayoutPreset.columns =>
      grid([1, 1, 1], [1], [(0, 0, 1, 1), (1, 0, 1, 1), (2, 0, 1, 1)]),
    LayoutPreset.circles => free([
        (0.02, 0.2, 0.3, 0.6, LayoutCellShape.ellipse),
        (0.35, 0.2, 0.3, 0.6, LayoutCellShape.ellipse),
        (0.68, 0.2, 0.3, 0.6, LayoutCellShape.ellipse),
      ]),
    LayoutPreset.scattered => free([
        (0.04, 0.06, 0.42, 0.4, LayoutCellShape.rectangle),
        (0.52, 0.12, 0.42, 0.36, LayoutCellShape.rectangle),
        (0.1, 0.54, 0.38, 0.38, LayoutCellShape.rectangle),
        (0.56, 0.56, 0.36, 0.36, LayoutCellShape.hexagon),
      ]),
  };
}

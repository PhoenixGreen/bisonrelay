import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/render/layout_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// layout_settings.dart is a Layout's settings: where it starts from, its
// mode and cells in Content, its gutters and the cells' look in Look; and
// dockGroup, the "In a cell" controls every element has in its Layout
// section once its page has a Layout.

String _weights(List<double> w) =>
    [for (var x in w) x == x.roundToDouble() ? "${x.round()}" : "$x"].join(" ");

List<double>? _readWeights(String s) {
  var out = [
    for (var p in s.split(RegExp(r"[\s,]+")))
      if (double.tryParse(p) case var v? when v > 0) v
  ];
  return out.isEmpty || out.length > LayoutElement.maxTracks ? null : out;
}

List<Widget> layoutSettings(
  BuildContext context,
  CanvasController controller,
  LayoutElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(LayoutElement next) {
    begin();
    controller.setLayout(next);
    commit();
  }

  void typing(LayoutElement next) {
    begin();
    controller.setLayout(next, transient: true);
  }

  var cells = e.shownCells;
  // The previews are drawn again only when the layout's shape changes.
  var shape = (e.width / math.max(1, e.height) * 50).round();
  var pickedId = controller.layoutCell(e.id);
  var picked = cells.where((c) => c.id == pickedId).firstOrNull;
  String nameOf(LayoutCell c) {
    var i = cells.indexOf(c);
    return c.name.isNotEmpty ? c.name : "Cell ${i + 1}";
  }

  void putCell(LayoutCell c, {bool keep = false}) =>
      keep ? typing(e.withCell(c)) : now(e.withCell(c));

  // The cut above a Panels cell: the one its own edge was made by.
  List<bool>? cutPath;
  LayoutNode? cut;
  if (picked != null && e.mode == LayoutMode.panels) {
    var path = e.root.pathTo(picked.id);
    if (path != null && path.isNotEmpty) {
      cutPath = path.sublist(0, path.length - 1);
      cut = e.root.nodeAt(cutPath);
    }
  }
  void putCut(LayoutNode next, {bool keep = false}) {
    var root = e.root.replaced(cutPath!, next);
    keep ? typing(e.copyWith(root: root)) : now(e.copyWith(root: root));
  }

  return [
    elementPanel(context, controller, e, write, begin, commit,
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.mode.label} · ${cells.length} cell"
                  "${cells.length == 1 ? "" : "s"}",
              children: [
                CanvasTiles<LayoutPreset>(
                  key: const ValueKey("layoutPresets"),
                  foldAs: "layout.tiles.preset",
                  label: "Start from",
                  help: "A ready-made layout: comic pages cut into panels, "
                      "cards on a grid, or frames set out freely. Click one "
                      "to start from it; what was docked in this layout is "
                      "let go where it is.",
                  columns: 3,
                  previewHeight: 74,
                  tiles: [
                    for (var p in LayoutPreset.values)
                      CanvasTile(p, p.label,
                          drawnFrom: (p, shape),
                          paint: (canvas, size) => paintLayoutPreview(
                              canvas, size, p,
                              boxSize: Size(e.width, e.height))),
                  ],
                  selected: (_) => false,
                  keyOf: (p) => "layoutPreset-${p.name}",
                  onPick: (p) {
                    now(layoutFrom(e.base, p));
                    controller.pickLayoutCell(e.id, null);
                  },
                ),
                CanvasControlGroup(
                    key: const ValueKey("layoutCells"),
                    label: "Cells",
                    help: "Panels cuts a cell in two, again and again, as a "
                        "comic page is drawn; Grid sets cells on columns and "
                        "rows; Free puts shapes anywhere. Double-click a cell "
                        "on the canvas to pick it; drag a cut or a grid line "
                        "to move it. Any element can be docked in a cell from "
                        "its own Layout section: it is drawn inside it and "
                        "moves with it.",
                    children: [
                      CanvasSegmented<LayoutMode>(
                        key: const ValueKey("layoutMode"),
                        label: "Mode",
                        value: e.mode,
                        options: [
                          for (var m in LayoutMode.values) (m, m.label)
                        ],
                        keyOf: (m) => "layoutMode-${m.name}",
                        onChanged: (m) => controller.setLayoutMode(e, m),
                      ),
                      CanvasDropdown<String>(
                        key: const ValueKey("layoutPicked"),
                        label: "Cell",
                        value: picked?.id ?? "",
                        options: [
                          ("", "The whole layout"),
                          for (var c in cells) (c.id, nameOf(c)),
                        ],
                        onChanged: (id) => controller.pickLayoutCell(
                            e.id, id.isEmpty ? null : id),
                      ),
                      if (e.mode == LayoutMode.panels && picked != null) ...[
                        CanvasTextButton(
                          key: const ValueKey("layoutSplitDown"),
                          label: "Cut down",
                          icon: Icons.vertical_split_outlined,
                          onPressed: () => controller
                              .splitLayoutCell(e, picked.id, vertical: true),
                        ),
                        CanvasTextButton(
                          key: const ValueKey("layoutSplitAcross"),
                          label: "Cut across",
                          icon: Icons.horizontal_split_outlined,
                          onPressed: () => controller
                              .splitLayoutCell(e, picked.id, vertical: false),
                        ),
                      ],
                      if (e.mode != LayoutMode.panels)
                        CanvasTextButton(
                          key: const ValueKey("layoutAddCell"),
                          label: "Add a cell",
                          icon: Icons.add,
                          onPressed: () => controller.addLayoutCell(e),
                        ),
                      if (picked != null && cells.length > 1)
                        CanvasTextButton(
                          key: const ValueKey("layoutRemoveCell"),
                          label: e.mode == LayoutMode.panels
                              ? "Merge with its neighbour"
                              : "Remove this cell",
                          icon: e.mode == LayoutMode.panels
                              ? Icons.merge_outlined
                              : Icons.delete_outline,
                          onPressed: () =>
                              controller.removeLayoutCell(e, picked.id),
                        ),
                      if (e.mode == LayoutMode.grid) ...[
                        const CanvasLineBreak(),
                        CanvasTextField(
                          key: const ValueKey("layoutColumns"),
                          label: "Columns (widths)",
                          value: _weights(e.columns),
                          hint: "1 1 2",
                          width: 110,
                          onChanged: (v) {
                            var w = _readWeights(v);
                            if (w != null) {
                              controller.setLayoutTracks(e, columns: w);
                            }
                          },
                        ),
                        CanvasTextField(
                          key: const ValueKey("layoutRows"),
                          label: "Rows (heights)",
                          value: _weights(e.rows),
                          hint: "2 1",
                          width: 110,
                          onChanged: (v) {
                            var w = _readWeights(v);
                            if (w != null) {
                              controller.setLayoutTracks(e, rows: w);
                            }
                          },
                        ),
                      ],
                    ]),
                if (picked != null)
                  CanvasControlGroup(
                      key: const ValueKey("layoutCell"),
                      label: nameOf(picked),
                      children: [
                        CanvasTextField(
                          key: const ValueKey("layoutCellName"),
                          label: "Name",
                          value: picked.name,
                          onChanged: (v) =>
                              putCell(picked.copyWith(name: v), keep: true),
                          onCommit: commit,
                        ),
                        if (cut != null) ...[
                          const CanvasLineBreak(),
                          CanvasStepper(
                            key: const ValueKey("layoutCutAt"),
                            label: "Cut at",
                            value: cut.at * 100,
                            min: 2,
                            max: 98,
                            suffix: "%",
                            onChanged: (v) =>
                                putCut(cut!.withCut(at: v / 100), keep: true),
                            onCommit: commit,
                          ),
                          CanvasStepper(
                            key: const ValueKey("layoutCutTilt"),
                            label: "Tilt",
                            value: cut.tilt,
                            min: -60,
                            max: 60,
                            suffix: "°",
                            onChanged: (v) =>
                                putCut(cut!.withCut(tilt: v), keep: true),
                            onCommit: commit,
                          ),
                          CanvasStepper(
                            key: const ValueKey("layoutCutGutter"),
                            label: "Its gutter",
                            value: cut.gutter ??
                                (cut.vertical ? e.gutter : e.rowGutter),
                            min: 0,
                            max: 400,
                            onChanged: (v) =>
                                putCut(cut!.withCut(gutter: v), keep: true),
                            onCommit: commit,
                          ),
                        ],
                        if (e.mode == LayoutMode.grid) ...[
                          const CanvasLineBreak(),
                          for (var (key, label, value, set) in [
                            (
                              "Col",
                              "Column",
                              picked.col + 1,
                              (int v) => picked.copyWith(col: v - 1)
                            ),
                            (
                              "Row",
                              "Row",
                              picked.row + 1,
                              (int v) => picked.copyWith(row: v - 1)
                            ),
                            (
                              "ColSpan",
                              "Across",
                              picked.colSpan,
                              (int v) => picked.copyWith(colSpan: v)
                            ),
                            (
                              "RowSpan",
                              "Down",
                              picked.rowSpan,
                              (int v) => picked.copyWith(rowSpan: v)
                            ),
                          ])
                            CanvasStepper(
                              key: ValueKey("layoutCell$key"),
                              label: label,
                              value: value.toDouble(),
                              min: 1,
                              max: LayoutElement.maxTracks.toDouble(),
                              step: 1,
                              onChanged: (v) => putCell(set(v.round())),
                            ),
                        ],
                        if (e.mode == LayoutMode.free) ...[
                          const CanvasLineBreak(),
                          CanvasDropdown<LayoutCellShape>(
                            key: const ValueKey("layoutCellShape"),
                            label: "Shape",
                            value: picked.shape,
                            options: [
                              for (var s in LayoutCellShape.values) (s, s.label)
                            ],
                            onChanged: (s) =>
                                putCell(picked.copyWith(shape: s)),
                          ),
                          CanvasStepper(
                            key: const ValueKey("layoutCellTurn"),
                            label: "Turn",
                            value: picked.turn,
                            min: -180,
                            max: 180,
                            suffix: "°",
                            onChanged: (v) =>
                                putCell(picked.copyWith(turn: v), keep: true),
                            onCommit: commit,
                          ),
                        ],
                        const CanvasLineBreak(),
                        CanvasToggle(
                          key: const ValueKey("layoutCellOwnStyle"),
                          label: "Its own look",
                          value: picked.style != null,
                          onChanged: (v) => putCell(v
                              ? picked.copyWith(style: e.cellStyle)
                              : picked.copyWith(clearStyle: true)),
                        ),
                        if (picked.style != null)
                          boxGroup(
                              picked.style!,
                              (b) => putCell(picked.copyWith(style: b),
                                  keep: true),
                              begin,
                              commit,
                              label: "This cell",
                              fillLabel: "Fill",
                              remember: "layoutCellStyle",
                              rule: false,
                              fill: true,
                              context: context),
                      ]),
              ]),
          PanelBit(PanelSection.look,
              summary:
                  e.gutterColor.a > 0 ? "Gutters painted" : "Clear gutters",
              children: [
                CanvasControlGroup(
                    key: const ValueKey("layoutGutters"),
                    label: "Gutters",
                    children: [
                      CanvasStepper(
                        key: const ValueKey("layoutGutter"),
                        label: "Side by side",
                        value: e.gutter,
                        min: 0,
                        max: 400,
                        onChanged: (v) => typing(e.copyWith(gutter: v)),
                        onCommit: commit,
                      ),
                      CanvasStepper(
                        key: const ValueKey("layoutRowGutter"),
                        label: "One above another",
                        value: e.rowGutter,
                        min: 0,
                        max: 400,
                        onChanged: (v) => typing(e.copyWith(rowGutter: v)),
                        onCommit: commit,
                      ),
                      CanvasStepper(
                        key: const ValueKey("layoutMargin"),
                        label: "Margin",
                        value: e.margin,
                        min: 0,
                        max: 400,
                        onChanged: (v) => typing(e.copyWith(margin: v)),
                        onCommit: commit,
                      ),
                      CanvasColorButton(
                        key: const ValueKey("layoutGutterColour"),
                        label: "Colour",
                        color: e.gutterColor,
                        onChanged: (c) => now(e.copyWith(gutterColor: c)),
                      ),
                      if (e.gutterColor.a > 0)
                        CanvasIconButton(
                          key: const ValueKey("layoutGutterClear"),
                          icon: Icons.format_color_reset_outlined,
                          tooltip: "Clear gutters: what is behind shows",
                          onPressed: () => now(
                              e.copyWith(gutterColor: const Color(0x00000000))),
                        ),
                    ]),
                boxGroup(e.cellStyle, (b) => typing(e.copyWith(cellStyle: b)),
                    begin, commit,
                    label: "Cells",
                    fillLabel: "Fill",
                    remember: "layoutCells",
                    rule: false,
                    fill: true,
                    context: context),
              ]),
        ]),
  ];
}

/// dockGroup is the "In a cell" controls for [e]: which Layout cell it is
/// docked in, whether it breaks out of its edge, and fitting it to the
/// cell. Null where the page has no Layout to dock in.
Widget? dockGroup(CanvasController controller, CanvasElement e) {
  var cells = controller.dockableCells(e);
  if (cells.isEmpty) return null;
  var now = e.base.dock;
  var known = cells.any((c) => "${c.$1}:${c.$2}" == now);
  return CanvasControlGroup(
      key: const ValueKey("dockGroup"),
      label: "In a cell",
      help: "Docked in a Layout's cell, it is drawn inside the cell and moves "
          "and resizes with it as the layout changes. Break out lets it "
          "reach over the cell's edge, as a figure does over a panel's line.",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("dockCell"),
          label: "Cell",
          value: known ? now : "",
          options: [
            ("", "None"),
            for (var (l, c, name) in cells) ("$l:$c", name),
          ],
          onChanged: (v) {
            var d = dockOf(v);
            controller.dockElement(e, d?.$1 ?? "", d?.$2 ?? "");
          },
        ),
        if (known) ...[
          CanvasToggle(
            key: const ValueKey("dockOut"),
            label: "Break out",
            value: e.base.dockOut,
            onChanged: (v) => controller.replaceElement(e.withBase(dockOut: v)),
          ),
          CanvasTextButton(
            key: const ValueKey("dockFit"),
            label: "Fit to the cell",
            icon: Icons.fit_screen_outlined,
            onPressed: () {
              var d = dockOf(now)!;
              controller.dockElement(e, d.$1, d.$2, fit: true);
            },
          ),
        ],
      ]);
}

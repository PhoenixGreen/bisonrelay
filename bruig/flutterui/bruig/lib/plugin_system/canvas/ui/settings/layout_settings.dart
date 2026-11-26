import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/render/layout_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// layout_settings.dart is a Layout's settings: where it starts from, its
// mode and cells in Content, its gutters and the cells' look in Look; and
// dockGroup, the "In a cell" controls every element has in its Layout
// section once its page has a Layout. It writes as every panel does
// (write, begin, commit), each range is LayoutRange's, and a cell's box
// offers only what a cell is drawn with (BoxParts.outline).

String _weights(List<double> w) =>
    [for (var x in w) x == x.roundToDouble() ? "${x.round()}" : "$x"].join(" ");

List<double>? _readWeights(String s) {
  var out = [
    for (var p in s.split(RegExp(r"[\s,]+")))
      if (double.tryParse(p) case var v? when v > 0) v
  ];
  return out.isEmpty || out.length > LayoutElement.maxTracks ? null : out;
}

/// _Layout is a Layout in its panel and how to write it: what each piece of
/// the panel is handed.
class _Layout {
  final BuildContext context;
  final CanvasController controller;
  final LayoutElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;

  /// cells are the cells it draws, and [picked] the one picked, or null for
  /// the whole layout.
  final List<LayoutCell> cells;
  final LayoutCell? picked;

  _Layout(this.context, this.controller, this.e, this.write, this.begin,
      this.commit)
      : cells = e.shownCells,
        picked = e.shownCells
            .where((c) => c.id == controller.layoutCell(e.id))
            .firstOrNull;

  /// now writes [next] as one step: a choice made in one press.
  void now(LayoutElement next) {
    begin();
    write(next);
    commit();
  }

  /// live writes [next] as a drag or a typed number goes; [commit] ends it.
  void live(LayoutElement next) {
    begin();
    write(next);
  }

  /// putCell writes [c] in place of the cell of its id: as it goes with
  /// [keep], else as one step.
  void putCell(LayoutCell c, {bool keep = false}) =>
      keep ? live(e.withCell(c)) : now(e.withCell(c));
}

/// layoutSettings is [e]'s panel (see element_panel.dart): where it starts
/// from and its cells in Content, its gutters and the cells' look in Look.
List<Widget> layoutSettings(
  BuildContext context,
  CanvasController controller,
  LayoutElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var l = _Layout(context, controller, e, write, begin, commit);
  var cells = l.cells;
  return [
    elementPanel(context, controller, e, write, begin, commit,
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.mode.label} · ${cells.length} cell"
                  "${cells.length == 1 ? "" : "s"}",
              children: [
                _presets(l),
                _cellsGroup(l),
                if (cells.length > 1) _readingGroup(context, controller, e),
                if (l.picked case var picked?) _pickedCellGroup(l, picked),
              ]),
          PanelBit(PanelSection.look,
              summary:
                  e.gutterColor.a > 0 ? "Gutters painted" : "Clear gutters",
              children: [
                _guttersGroup(l),
                boxGroup(e.cellStyle, (b) => l.live(e.copyWith(cellStyle: b)),
                    begin, commit,
                    label: "Cells",
                    fillLabel: "Fill",
                    remember: "layoutCells",
                    rule: false,
                    parts: BoxParts.outline,
                    fillPickedIn: context),
              ]),
        ]),
  ];
}

/// _presets are the ready-made layouts to start from, each a picture of
/// itself.
Widget _presets(_Layout l) {
  var e = l.e;
  // The previews are drawn again only when the layout's shape changes.
  var shape = (e.width / math.max(1, e.height) * 50).round();
  return CanvasTiles<LayoutPreset>(
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
            paint: (canvas, size) => paintLayoutPreview(canvas, size, p,
                boxSize: Size(e.width, e.height))),
    ],
    selected: (_) => false,
    keyOf: (p) => "layoutPreset-${p.name}",
    onPick: (p) {
      l.now(layoutFrom(e.base, p));
      l.controller.pickLayoutCell(e.id, null);
    },
  );
}

/// _cellsGroup is how the cells are made: the mode, which is picked, a
/// Panels cell cut in two, a cell added or taken away, and a Grid's tracks.
Widget _cellsGroup(_Layout l) {
  var (e, controller, picked) = (l.e, l.controller, l.picked);
  return CanvasControlGroup(
      key: const ValueKey("layoutCells"),
      label: "Cells",
      help: "Panels cuts a cell in two, again and again, as a "
          "comic page is drawn; Grid sets cells on columns and "
          "rows; Free puts shapes anywhere. Double-click a cell "
          "on the canvas to pick it; drag a cut or a grid line "
          "to move it. Any element can be docked in a cell from "
          "its own Layout section: it is drawn inside it, and "
          "moves with the layout.",
      children: [
        CanvasSegmented<LayoutMode>(
          key: const ValueKey("layoutMode"),
          label: "Mode",
          value: e.mode,
          options: [for (var m in LayoutMode.values) (m, m.label)],
          keyOf: (m) => "layoutMode-${m.name}",
          onChanged: (m) => l.now(layoutInMode(e, m)),
        ),
        CanvasDropdown<String>(
          key: const ValueKey("layoutPicked"),
          label: "Cell",
          value: picked?.id ?? "",
          options: [
            ("", "The whole layout"),
            for (var c in l.cells) (c.id, e.nameOf(c)),
          ],
          onChanged: (id) =>
              controller.pickLayoutCell(e.id, id.isEmpty ? null : id),
        ),
        if (e.mode == LayoutMode.panels && picked != null) ...[
          CanvasTextButton(
            key: const ValueKey("layoutSplitDown"),
            label: "Cut down",
            icon: Icons.vertical_split_outlined,
            onPressed: () =>
                controller.splitLayoutCell(e, picked.id, vertical: true),
          ),
          CanvasTextButton(
            key: const ValueKey("layoutSplitAcross"),
            label: "Cut across",
            icon: Icons.horizontal_split_outlined,
            onPressed: () =>
                controller.splitLayoutCell(e, picked.id, vertical: false),
          ),
        ],
        if (e.mode != LayoutMode.panels)
          CanvasTextButton(
            key: const ValueKey("layoutAddCell"),
            label: "Add a cell",
            icon: Icons.add,
            onPressed: () => controller.addLayoutCell(e),
          ),
        if (picked != null && l.cells.length > 1)
          CanvasTextButton(
            key: const ValueKey("layoutRemoveCell"),
            label: e.mode == LayoutMode.panels
                ? "Merge with its neighbour"
                : "Remove this cell",
            icon: e.mode == LayoutMode.panels
                ? Icons.merge_outlined
                : Icons.delete_outline,
            onPressed: () => controller.removeLayoutCell(e, picked.id),
          ),
        if (e.mode == LayoutMode.grid) ...[
          const CanvasLineBreak(),
          _tracks(l, columns: true),
          _tracks(l, columns: false),
        ],
      ]);
}

/// _tracks is a Grid's column widths, or with [columns] false its row
/// heights, typed as weights ("1 1 2"). A reading that is no weights at
/// all leaves them as they were.
Widget _tracks(_Layout l, {required bool columns}) {
  var e = l.e;
  return CanvasTextField(
    key: ValueKey(columns ? "layoutColumns" : "layoutRows"),
    label: columns ? "Columns (widths)" : "Rows (heights)",
    value: _weights(columns ? e.columns : e.rows),
    hint: columns ? "1 1 2" : "2 1",
    width: 110,
    onChanged: (v) {
      if (_readWeights(v) case var w?) {
        l.live(columns ? e.withTracks(columns: w) : e.withTracks(rows: w));
      }
    },
    onCommit: l.commit,
  );
}

/// _pickedCellGroup is the picked cell: its name, then what places it in
/// its mode (its cut, its place on the Grid, its shape and turn), then its
/// own look.
Widget _pickedCellGroup(_Layout l, LayoutCell picked) {
  var e = l.e;
  return CanvasControlGroup(
      key: const ValueKey("layoutCell"),
      label: e.nameOf(picked),
      children: [
        CanvasTextField(
          key: const ValueKey("layoutCellName"),
          label: "Name",
          value: picked.name,
          onChanged: (v) => l.putCell(picked.copyWith(name: v), keep: true),
          onCommit: l.commit,
        ),
        ...switch (e.mode) {
          LayoutMode.panels => _cutRow(l, picked),
          LayoutMode.grid => _gridPlaceRow(l, picked),
          LayoutMode.free => _freeShapeRow(l, picked),
        },
        ..._ownLook(l, picked),
      ]);
}

/// _cutRow is the cut a Panels cell's own edge was made by: where it
/// crosses, its tilt and its gutter. None for a cell never cut.
List<Widget> _cutRow(_Layout l, LayoutCell picked) {
  var e = l.e;
  var path = e.root.pathTo(picked.id);
  if (path == null || path.isEmpty) return const [];
  var cutPath = path.sublist(0, path.length - 1);
  var cut = e.root.nodeAt(cutPath);
  if (cut == null) return const [];
  void put(LayoutNode next) =>
      l.live(e.copyWith(root: e.root.replaced(cutPath, next)));
  return [
    const CanvasLineBreak(),
    CanvasStepper(
      key: const ValueKey("layoutCutAt"),
      label: "Cut at",
      value: cut.at * 100,
      min: LayoutRange.minCutAt * 100,
      max: LayoutRange.maxCutAt * 100,
      suffix: "%",
      onChanged: (v) => put(cut.withCut(at: v / 100)),
      onCommit: l.commit,
    ),
    CanvasStepper(
      key: const ValueKey("layoutCutTilt"),
      label: "Tilt",
      value: cut.tilt,
      min: -LayoutRange.maxTilt,
      max: LayoutRange.maxTilt,
      suffix: "°",
      onChanged: (v) => put(cut.withCut(tilt: v)),
      onCommit: l.commit,
    ),
    CanvasStepper(
      key: const ValueKey("layoutCutGutter"),
      label: "Its gutter",
      value: cutGutter(e, cut),
      min: 0,
      max: LayoutRange.maxGutter,
      onChanged: (v) => put(cut.withCut(gutter: v)),
      onCommit: l.commit,
    ),
  ];
}

/// _gridPlaceRow is where a Grid cell starts, counting from 1, and how many
/// tracks it spans each way.
List<Widget> _gridPlaceRow(_Layout l, LayoutCell picked) => [
      const CanvasLineBreak(),
      for (var (key, label, value, set) in [
        (
          "Col",
          "Column",
          picked.col + 1,
          (int v) => picked.copyWith(col: v - 1)
        ),
        ("Row", "Row", picked.row + 1, (int v) => picked.copyWith(row: v - 1)),
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
          onChanged: (v) => l.putCell(set(v.round())),
        ),
    ];

/// _freeShapeRow is a Free cell's outline and its turn.
List<Widget> _freeShapeRow(_Layout l, LayoutCell picked) => [
      const CanvasLineBreak(),
      CanvasDropdown<LayoutCellShape>(
        key: const ValueKey("layoutCellShape"),
        label: "Shape",
        value: picked.shape,
        options: [for (var s in LayoutCellShape.values) (s, s.label)],
        onChanged: (s) => l.putCell(picked.copyWith(shape: s)),
      ),
      CanvasStepper(
        key: const ValueKey("layoutCellTurn"),
        label: "Turn",
        value: picked.turn,
        min: -180,
        max: 180,
        suffix: "°",
        onChanged: (v) => l.putCell(picked.copyWith(turn: v), keep: true),
        onCommit: l.commit,
      ),
    ];

/// _ownLook is whether the picked cell is drawn its own way, and that way.
List<Widget> _ownLook(_Layout l, LayoutCell picked) => [
      const CanvasLineBreak(),
      CanvasToggle(
        key: const ValueKey("layoutCellOwnStyle"),
        label: "Its own look",
        value: picked.style != null,
        onChanged: (v) => l.putCell(v
            ? picked.copyWith(style: l.e.cellStyle)
            : picked.copyWith(clearStyle: true)),
      ),
      if (picked.style case var style?)
        boxGroup(style, (b) => l.putCell(picked.copyWith(style: b), keep: true),
            l.begin, l.commit,
            label: "This cell",
            fillLabel: "Fill",
            remember: "layoutCellStyle",
            rule: false,
            parts: BoxParts.outline,
            fillPickedIn: l.context),
    ];

/// _guttersGroup is the room between the cells and round them, and its
/// colour.
Widget _guttersGroup(_Layout l) {
  var e = l.e;
  Widget gap(String key, String label, double value,
          LayoutElement Function(double) set) =>
      CanvasStepper(
        key: ValueKey(key),
        label: label,
        value: value,
        min: 0,
        max: LayoutRange.maxGutter,
        onChanged: (v) => l.live(set(v)),
        onCommit: l.commit,
      );
  return CanvasControlGroup(
      key: const ValueKey("layoutGutters"),
      label: "Gutters",
      children: [
        gap("layoutGutter", "Side by side", e.gutter,
            (v) => e.copyWith(gutter: v)),
        gap("layoutRowGutter", "One above another", e.rowGutter,
            (v) => e.copyWith(rowGutter: v)),
        gap("layoutMargin", "Margin", e.margin, (v) => e.copyWith(margin: v)),
        CanvasColorButton(
          key: const ValueKey("layoutGutterColour"),
          label: "Colour",
          color: e.gutterColor,
          onChanged: (c) => l.now(e.copyWith(gutterColor: c)),
        ),
        if (e.gutterColor.a > 0)
          CanvasIconButton(
            key: const ValueKey("layoutGutterClear"),
            icon: Icons.format_color_reset_outlined,
            tooltip: "Clear gutters: what is behind shows",
            onPressed: () =>
                l.now(e.copyWith(gutterColor: const Color(0x00000000))),
          ),
      ]);
}

/// _readingGroup is the order Panel mode reads [e]'s cells in: set by
/// clicking them in turn on the canvas, then nudged here, and a cell left
/// out or put back.
Widget _readingGroup(
    BuildContext context, CanvasController controller, LayoutElement e) {
  var theme = ThemeNotifier.of(context);
  var ordering = controller.orderingLayout == e.id;
  var cells = e.shownCells;
  var reading = e.reading;
  return CanvasControlGroup(
    key: const ValueKey("layoutReading"),
    label: "Reading order",
    help: "The order Panel mode steps through the cells in, when the book is "
        "read panel by panel. Set reading order, then click the cells on "
        "the canvas one after another; a cell not clicked is left out. "
        "Enter or Done keeps it, Escape puts it back as it was.",
    below: ordering
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                "Click the cells in the order they are read: "
                "${controller.orderClicked.length} of ${cells.length}.",
                style: TextStyle(
                    fontSize: 11, color: theme.colors.onSurfaceVariant)),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var (i, c) in reading.indexed)
                _readingRow(context, controller, e, c, i + 1),
              for (var c in cells)
                if (!reading.contains(c))
                  _readingRow(context, controller, e, c, null),
            ]),
          ),
    children: _readingButtons(controller, e, ordering: ordering),
  );
}

/// _readingRow is cell [c] in the reading order, [n]th, or left out with
/// none: moved sooner or later, and left out or put back.
Widget _readingRow(BuildContext context, CanvasController controller,
    LayoutElement e, LayoutCell c, int? n) {
  var theme = ThemeNotifier.of(context);
  var read = e.reading.length;
  return Row(
    key: ValueKey("layoutRead-${c.id}"),
    children: [
      SizedBox(
        width: 22,
        child: Text(n == null ? "–" : "$n",
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: n == null
                    ? theme.colors.onSurfaceVariant
                    : theme.colors.primary)),
      ),
      Expanded(
        child: Text(e.nameOf(c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5,
                color: n == null
                    ? theme.colors.onSurfaceVariant
                    : theme.colors.onSurface)),
      ),
      if (n != null) ...[
        CanvasIconButton(
          key: ValueKey("layoutReadUp-${c.id}"),
          icon: Icons.arrow_upward,
          tooltip: "Read sooner",
          tight: true,
          onPressed: n > 1 ? () => controller.moveInReading(e, c.id, -1) : null,
        ),
        CanvasIconButton(
          key: ValueKey("layoutReadDown-${c.id}"),
          icon: Icons.arrow_downward,
          tooltip: "Read later",
          tight: true,
          onPressed:
              n < read ? () => controller.moveInReading(e, c.id, 1) : null,
        ),
      ],
      CanvasIconButton(
        key: ValueKey("layoutReadOn-${c.id}"),
        icon: n == null
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        tooltip: n == null ? "Read it" : "Leave it out",
        tight: true,
        onPressed: n == null || read > 1
            ? () => controller.setCellRead(e, c.id, n == null)
            : null,
      ),
    ],
  );
}

/// _readingButtons start setting the order by clicking, and put it back;
/// while [ordering], keep what was clicked or let it go.
List<Widget> _readingButtons(CanvasController controller, LayoutElement e,
        {required bool ordering}) =>
    [
      if (!ordering) ...[
        CanvasTextButton(
          key: const ValueKey("layoutSetOrder"),
          label: "Set reading order",
          icon: Icons.format_list_numbered,
          onPressed: () => controller.beginReadingOrder(e),
        ),
        if (e.order.isNotEmpty || e.unread.isNotEmpty)
          CanvasTextButton(
            key: const ValueKey("layoutResetOrder"),
            label: "Reset",
            icon: Icons.restart_alt,
            onPressed: () => controller.resetReadingOrder(e),
          ),
      ] else ...[
        CanvasTextButton(
          key: const ValueKey("layoutOrderDone"),
          label: "Done",
          icon: Icons.check,
          onPressed: controller.finishReadingOrder,
        ),
        CanvasTextButton(
          key: const ValueKey("layoutOrderCancel"),
          label: "Cancel",
          icon: Icons.close,
          onPressed: () => controller.finishReadingOrder(keep: false),
        ),
      ],
    ];

/// dockGroup is the "In a cell" controls for [e]: which Layout cell it is
/// docked in, whether it breaks out of its edge, and fitting it to the
/// cell. Null where the page has no Layout to dock in.
Widget? dockGroup(CanvasController controller, CanvasElement e) {
  var cells = controller.dockableCells(e);
  if (cells.isEmpty) return null;
  var docked = e.base.docked;
  var known = cells.any((c) => c.dock == docked);
  return CanvasControlGroup(
      key: const ValueKey("dockGroup"),
      label: "In a cell",
      help: "Docked in a Layout's cell, it is drawn inside the cell, and "
          "moves when the whole layout is moved. Moving a cut or a gutter "
          "leaves it as it is: what goes over the cell's edge is hidden, and "
          "shows again while the layout is hidden in the layers. Break out "
          "lets it reach over the edge, as a figure does over a panel's "
          "line.",
      children: [
        CanvasDropdown<String>(
          key: const ValueKey("dockCell"),
          label: "Cell",
          value: known ? docked!.toJson() : "",
          options: [
            ("", "None"),
            for (var (:dock, :name) in cells) (dock.toJson(), name),
          ],
          onChanged: (v) {
            var d = LayoutDock.read(v);
            controller.dockElement(e, d?.layout ?? "", d?.cell ?? "");
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
            onPressed: () => controller
                .dockElement(e, docked!.layout, docked.cell, fit: true),
          ),
        ],
      ]);
}

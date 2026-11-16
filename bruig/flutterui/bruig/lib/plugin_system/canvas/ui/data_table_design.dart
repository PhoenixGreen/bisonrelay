import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/table_design.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart'
    show sheetColumnName;
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// data_table_design.dart is the Data Studio's Table tab (Ken, 2026-11-15:
// "a design view that allows me to visually improve the way tables ... look
// ... select cells or rows or columns or tables ... and be given options to
// customise"; prototype https://claude.ai/artifact/JyqWLMrdCunvo9GReCzYyq).
//
// The table is drawn large, as the canvas draws it, with a tab over each
// column and beside each row (lettered and numbered as its sheet is). Click a
// cell, a tab, or round the table, and the panel on the right is about that:
// the table's look and its styles; the header; a column's width and the
// styles reaching it; a row; a cell and the styles on it in the order they
// apply. A style -- one of the table's rules -- is listed by name, lights up
// everything it reaches when hovered, and opens to its reach and its look.
//
// Every change goes through the controller as one step to undo, so the
// canvas follows at once.

/// TableDesign is the Table tab for one table.
class TableDesign extends StatefulWidget {
  final CanvasController controller;
  final TableElement table;
  const TableDesign({required this.controller, required this.table, super.key});

  @override
  State<TableDesign> createState() => _TableDesignState();
}

const _palette = [
  0xFFFFFF, 0xC9D6EA, 0x8A8787, 0x59606B, 0x1C1C1C, 0x000000, //
  0x0C8310, 0x2FE08A, 0xF2B33D, 0xF7DE8E, 0xE8645A, 0xC82B0E, //
  0x4C8DF6, 0x073E8C, 0x9B7CF4, 0x3FC1D9,
];
const _hoverInk = Color(0xFF9B7CF4);

int? _rgb(Color c) => c.a == 0 ? null : c.toARGB32() & 0xFFFFFF;
Color _colour(int? v) =>
    v == null ? const Color(0x00000000) : Color(0xFF000000 | v);

class _TableDesignState extends State<TableDesign> {
  CanvasController get c => widget.controller;
  TableElement get t => widget.table;
  TablePart _picked = TablePart.table;
  TablePart? _hover;
  int? _hoverStyle;
  bool _fine = false;

  // Making a style (prototype v3): pointing is "click what to style";
  // options are what it could reach, offered from the click, hovered to see
  // them lit; made is the step after, its look.
  bool _pointing = false;
  List<ReachOption>? _options;
  int? _optionHover;
  bool _made = false;

  /// _rows is rows picked with shift on their tabs, for a style on several.
  List<int> _rows = const [];

  /// _copied is a look copied from a style or a cell, to paste on another.
  TableCellStyle? _copied;

  /// _dragging is the column whose right edge is being dragged, and the
  /// widths it started from.
  int? _dragging;
  List<double> _dragFrom = const [];
  double _dragX = 0;
  int? _edge;
  Timer? _ending;
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(TableDesign old) {
    super.didUpdateWidget(old);
    if (old.table.id != t.id) {
      _picked = TablePart.table;
      _hover = null;
      _hoverStyle = null;
    }
    if (!_stillThere(_picked)) _picked = TablePart.table;
  }

  @override
  void dispose() {
    _end();
    _focus.dispose();
    super.dispose();
  }

  bool _stillThere(TablePart p) => switch (p.kind) {
        TablePartKind.style => p.style < t.rules.length,
        TablePartKind.column => p.col < t.columnCount,
        TablePartKind.row => p.row < t.rows.length,
        TablePartKind.cell => p.row < t.rows.length && p.col < t.columnCount,
        TablePartKind.header => t.headerRow,
        TablePartKind.table => true,
      };

  // ---- Writing: one change is one undo step; a drag is one too.

  void _set(TableElement next) {
    _end();
    c.beginInteraction();
    c.replaceElement(next, transient: true);
    c.endInteraction();
  }

  /// _live is a change in a run of them (a slider, typing): kept open as
  /// one step, closed when the run stops.
  void _live(TableElement next) {
    c.beginInteraction();
    c.replaceElement(next, transient: true);
    _ending?.cancel();
    _ending = Timer(const Duration(milliseconds: 400), _end);
  }

  void _end() {
    _ending?.cancel();
    _ending = null;
    c.endInteraction();
  }

  TableElement _withRule(int i, TableRule r) {
    var rules = [...t.rules];
    rules[i] = r;
    return t.copyWith(rules: rules);
  }

  void _setRule(int i, TableRule r, {bool live = false}) =>
      live ? _live(_withRule(i, r)) : _set(_withRule(i, r));

  void _pick(TablePart p) => setState(() {
        _picked = p;
        _fine = false;
        _made = false;
        _pointing = false;
        _options = null;
        _optionHover = null;
        if (p.kind != TablePartKind.row) _rows = const [];
      });

  /// _offer opens the New style's first step with [options].
  void _offer(List<ReachOption> options) => setState(() {
        _options = options;
        _optionHover = null;
        _pointing = false;
      });

  /// _make is an option chosen: the style is made with a look that shows,
  /// and opened at its look.
  void _make(ReachOption o) {
    _newStyle(o.rule.copyWith(style: lookFor(o.rule)));
    setState(() => _made = true);
  }

  void _cancelNew() => setState(() {
        _pointing = false;
        _options = null;
        _optionHover = null;
      });

  /// _up is Esc: from a cell to its row's... the table; from a style to the
  /// part it was reached from is not known, so to the table.
  void _up() {
    if (_pointing || _options != null) return _cancelNew();
    _pick(switch (_picked.kind) {
      TablePartKind.cell => TablePart.column(_picked.col),
      _ => TablePart.table,
    });
  }

  /// _newStyle adds [rule] at the end and opens it.
  void _newStyle(TableRule rule) {
    _set(t.copyWith(rules: [...t.rules, rule]));
    _pick(TablePart.style(t.rules.length));
  }

  String _columnKey(int col) {
    var head = t.header;
    var name = col < head.length ? head[col].trim() : "";
    return name.isEmpty ? "${col + 1}" : name;
  }

  // ---- Names for the parts, as the sheet names them when there is one.

  String _columnLetter(int col) {
    var link = linkOf(t);
    return columnName((link?.range.c0 ?? 0) + col);
  }

  String _rowLabel(int row) {
    if (t.headerRow && row == 0) return "H";
    var link = linkOf(t);
    return link == null
        ? "${t.headerRow ? row : row + 1}"
        : "${link.range.r0 + row + 1}";
  }

  String _partName(TablePart p) => switch (p.kind) {
        TablePartKind.table => "Table",
        TablePartKind.header => "Header row",
        TablePartKind.column => "Column · ${t.columnName(p.col)}",
        TablePartKind.row => "Row ${_rowLabel(p.row)}",
        TablePartKind.cell => "Cell ${_columnLetter(p.col)}${_rowLabel(p.row)}",
        TablePartKind.style => "Style · ${styleName(t, p.style)}",
      };

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _up();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Column(children: [
            _crumbs(context),
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
            Expanded(child: _stage(context)),
          ]),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        SizedBox(width: 380, child: _panel(context)),
      ]),
    );
  }

  Widget _crumbs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var trail = <TablePart>[TablePart.table];
    if (_picked.kind == TablePartKind.cell) {
      trail.add(TablePart.column(_picked.col));
    }
    if (_picked != TablePart.table) trail.add(_picked);
    return SizedBox(
      height: 38,
      child: Row(children: [
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var (i, p) in trail.indexed) ...[
                if (i > 0)
                  Text("›", style: TextStyle(color: colors.onSurfaceVariant)),
                TextButton(
                  key: ValueKey("tableDesignCrumb-$i"),
                  onPressed: () => _pick(p),
                  child: Text(_partName(p),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: i == trail.length - 1
                              ? colors.onSurface
                              : colors.onSurfaceVariant)),
                ),
              ],
            ]),
          ),
        ),
        Flexible(
          child: Text(
              _pointing
                  ? "Click what to style · Esc to stop"
                  : "Click a cell, a tab, or round the table · shift-click row tabs · drag a column's edge · Esc goes up",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  // ---- The stage.

  Widget _stage(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      var g = _Geom.of(t, box.maxWidth);
      var lit = <(int, int)>[];
      var litStyle = _hoverStyle ??
          (_picked.kind == TablePartKind.style ? _picked.style : null);
      var options = _options, oh = _optionHover;
      if (options != null && oh != null && oh < options.length) {
        lit = styleCells(t, options[oh].rule);
      } else if (litStyle != null && litStyle < t.rules.length) {
        lit = styleCells(t, t.rules[litStyle]);
      }
      return Container(
        color: colors.surfaceContainerLowest,
        child: SingleChildScrollView(
          key: const ValueKey("tableDesignScroll"),
          child: SizedBox(
            width: box.maxWidth,
            height: g.size.height,
            child: MouseRegion(
              cursor: _edge != null || _dragging != null
                  ? SystemMouseCursors.resizeColumn
                  : _pointing
                      ? SystemMouseCursors.precise
                      : SystemMouseCursors.basic,
              onHover: (e) {
                var p = g.partAt(e.localPosition, t);
                var edge = g.edgeAt(e.localPosition);
                if (p != _hover || edge != _edge) {
                  setState(() {
                    _hover = p;
                    _edge = edge;
                  });
                }
              },
              onExit: (_) => setState(() {
                _hover = null;
                _edge = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onTapDown: (d) => _clicked(g, d.localPosition),
                onHorizontalDragStart: (d) {
                  var j = g.edgeAt(d.localPosition);
                  if (j == null) return;
                  setState(() {
                    _dragging = j;
                    _dragFrom = [...g.w];
                    _dragX = d.localPosition.dx;
                  });
                },
                onHorizontalDragUpdate: (d) {
                  var j = _dragging;
                  if (j == null) return;
                  var by = (d.localPosition.dx - _dragX) / g.k;
                  var next = [..._dragFrom];
                  var room = next[j] + next[j + 1];
                  next[j] = (next[j] + by).clamp(12.0, room - 12).toDouble();
                  next[j + 1] = room - next[j];
                  _live(t.copyWith(columnWidths: next));
                },
                onHorizontalDragEnd: (_) {
                  if (_dragging == null) return;
                  setState(() => _dragging = null);
                  _end();
                },
                child: CustomPaint(
                  key: const ValueKey("tableDesignStage"),
                  size: g.size,
                  painter: _StagePainter(
                    t: t,
                    g: g,
                    ground: c.document.background.spec.background,
                    images: c.images,
                    picked: _picked,
                    hover: _hover,
                    lit: lit,
                    accent: colors.primary,
                    tabFill: colors.surfaceContainerHigh,
                    tabInk: colors.onSurfaceVariant,
                    columnLabel: _columnLetter,
                    rowLabel: _rowLabel,
                    rows: _rows,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  /// _clicked is a click on the stage: with shift on a row tab, that row
  /// added to (or taken from) the rows picked; while pointing, what to style;
  /// otherwise the part, picked.
  void _clicked(_Geom g, Offset at) {
    _focus.requestFocus();
    var p = g.partAt(at, t) ?? TablePart.table;
    var shift = HardwareKeyboard.instance.isShiftPressed;
    if (shift && p.kind == TablePartKind.row) {
      var rows = [..._rows];
      if (rows.isEmpty && _picked.kind == TablePartKind.row) {
        rows.add(_picked.row);
      }
      rows.contains(p.row) ? rows.remove(p.row) : rows.add(p.row);
      rows.sort();
      setState(() {
        _rows = rows;
        _picked = rows.isEmpty ? TablePart.table : TablePart.row(rows.last);
        _made = false;
        if (_pointing && rows.length > 1) {
          _options = reachOptions(t, p, rows: rows);
          _pointing = false;
        }
      });
      return;
    }
    if (_pointing) {
      setState(() {
        _picked = p;
        _rows = p.kind == TablePartKind.row ? [p.row] : const [];
        _options = reachOptions(t, p);
        _pointing = false;
      });
      return;
    }
    _pick(p);
    if (p.kind == TablePartKind.row) setState(() => _rows = [p.row]);
  }

  // ---- The panel.

  Widget _panel(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var p = _picked;
    var drafting = _pointing || _options != null;
    var several = _rows.length > 1 && !drafting;
    var (title, says) = drafting
        ? (
            "New style",
            _pointing
                ? "Step 1 of 2: click what to style."
                : "Step 1 of 2: what it reaches."
          )
        : several
            ? ("${_rows.length} rows", "Picked with shift on their tabs.")
            : switch (p.kind) {
                TablePartKind.table => (
                    t.name.isEmpty ? "Table" : t.name,
                    "Its look, and every style on it."
                  ),
                TablePartKind.header => (
                    "Header row",
                    "Its fill, words and height."
                  ),
                TablePartKind.column => (
                    t.columnName(p.col),
                    "Column ${_columnLetter(p.col)}: its width and the styles on it."
                  ),
                TablePartKind.row => (
                    "Row ${_rowLabel(p.row)}",
                    t.cell(p.row,
                        t.headerColumn ? 0 : math.min(2, t.columnCount - 1))
                  ),
                TablePartKind.cell => (
                    "Cell ${_columnLetter(p.col)}${_rowLabel(p.row)}",
                    t.cell(p.row, p.col).isEmpty
                        ? "Empty"
                        : "“${t.cell(p.row, p.col)}”"
                  ),
                TablePartKind.style => (
                    styleName(t, p.style),
                    styleReach(t, t.rules[p.style])
                  ),
              };
    var key = drafting
        ? "new"
        : several
            ? "rows"
            : p.kind.name;
    return Container(
      color: colors.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                key: const ValueKey("tableDesignTitle"),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface)),
            const SizedBox(height: 2),
            Text(says,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey("tableDesignPanel-$key"),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: drafting
                    ? _newPanel(context)
                    : several
                        ? _rowsPanel(context)
                        : switch (p.kind) {
                            TablePartKind.table => _tablePanel(context),
                            TablePartKind.header => _headerPanel(context),
                            TablePartKind.column =>
                              _columnPanel(context, p.col),
                            TablePartKind.row => _rowPanel(context, p.row),
                            TablePartKind.cell =>
                              _cellPanel(context, p.row, p.col),
                            TablePartKind.style =>
                              _stylePanel(context, p.style),
                          }),
          ),
        ),
      ]),
    );
  }

  /// _newPanel is the New style's first step: pointing, or the options.
  List<Widget> _newPanel(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var options = _options;
    return [
      if (options == null) ...[
        _hint(context,
            "Click a cell, a row tab or a column tab on the table. Shift-click row tabs for several rows."),
      ] else ...[
        const StudioLabel("What should it reach?"),
        _hint(context, "Hover one to see it lit on the table."),
        const SizedBox(height: 6),
        if (options.isEmpty) _hint(context, "Nothing to offer from that."),
        for (var (i, o) in options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: MouseRegion(
              onEnter: (_) => setState(() => _optionHover = i),
              onExit: (_) => setState(() => _optionHover = null),
              child: Material(
                color: colors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: _optionHover == i
                            ? _hoverInk
                            : const Color(0x00000000))),
                child: InkWell(
                  key: ValueKey("tableReach-$i"),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _make(o),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Text(o.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                  ),
                ),
              ),
            ),
          ),
        _hint(context,
            "“Wherever it is” follows that team as the numbers move it; “whoever is there” stays on that place."),
      ],
      _buttons([
        if (options != null)
          StudioPill(
              key: const ValueKey("tableNewRepoint"),
              label: "Click something else",
              onTap: () => setState(() {
                    _options = null;
                    _pointing = true;
                  })),
        StudioPill(
            key: const ValueKey("tableNewCancel"),
            label: "Cancel",
            onTap: _cancelNew),
      ]),
    ];
  }

  /// _rowsPanel is several rows picked with shift.
  List<Widget> _rowsPanel(BuildContext context) => [
        _hint(
            context,
            "${[
              for (var r in _rows) _rowLabel(r)
            ].join(", ")}. A style on them can keep to these places or go with who is in them."),
        _buttons([
          StudioPill(
              key: const ValueKey("tableDesignStyleRows"),
              label: "+ New style for these",
              filled: true,
              onTap: () => _offer(
                  reachOptions(t, TablePart.row(_rows.last), rows: _rows))),
        ]),
      ];

  Widget _hint(BuildContext context, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: color ??
                    ThemeNotifier.of(context).colors.onSurfaceVariant)),
      );

  Widget _buttons(List<Widget> pills) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: pills),
      );

  Widget _swatches(
      String id, String label, Color value, ValueChanged<Color> set,
      {bool none = true}) {
    var v = _rgb(value);
    var palette = [if (v != null && !_palette.contains(v)) v, ..._palette];
    return StudioSwatches(
        id: id,
        label: label,
        palette: palette,
        value: v,
        asMade: none,
        onPick: (x) => set(_colour(x)));
  }

  Widget _slider(String label, double value, double min, double max,
          double rest, void Function(double) live,
          {String Function(double)? format}) =>
      StudioSlider(
        key: ValueKey("tableSlider-$label"),
        label: label,
        value: value,
        min: min,
        max: max,
        rest: rest,
        format: format ?? (v) => v.toStringAsFixed(v.abs() < 10 ? 1 : 0),
        onChanged: live,
        onChangeEnd: (_) => _end(),
      );

  /// _styleList is styles [indices], each a row: an eye to switch it off,
  /// its name and reach, a mark when it does nothing. Hovered, everything it
  /// reaches lights up on the table.
  List<Widget> _styleList(BuildContext context, List<int> indices) {
    final colors = ThemeNotifier.of(context).colors;
    return [
      for (var i in indices)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoverStyle = i),
            onExit: (_) => setState(() => _hoverStyle = null),
            child: Material(
              color: colors.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: _hoverStyle == i
                          ? _hoverInk
                          : const Color(0x00000000))),
              child: InkWell(
                key: ValueKey("tableStyle-$i"),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pick(TablePart.style(i)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
                  child: Row(children: [
                    IconButton(
                      key: ValueKey("tableStyleEye-$i"),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: Icon(
                          t.rules[i].off
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: colors.onSurfaceVariant),
                      onPressed: () => _setRule(
                          i, t.rules[i].copyWith(off: !t.rules[i].off)),
                    ),
                    Expanded(
                      child: Opacity(
                        opacity: t.rules[i].off ? 0.5 : 1,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(styleName(t, i),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface)),
                              Text(styleReach(t, t.rules[i]),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant)),
                            ]),
                      ),
                    ),
                    if (styleIdle(t, t.rules[i]) != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text("does nothing",
                            key: ValueKey("tableStyleIdle-$i"),
                            style: const TextStyle(
                                fontSize: 10.5, color: Color(0xFFF2B33D))),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _tablePanel(BuildContext context) => [
        StudioLabel("Styles on this table · ${t.rules.length}"),
        _hint(
            context,
            t.rules.isEmpty
                ? "None yet. Click a column, row or cell and add one there."
                : "Hover one to see what it reaches; click it to change it."),
        const SizedBox(height: 6),
        for (var (name, indices) in styleGroups(t)) ...[
          StudioPartHeading("$name · ${indices.length}"),
          ..._styleList(context, indices),
        ],
        _buttons([
          StudioPill(
              key: const ValueKey("tableDesignNewStyle"),
              label: "+ New style",
              onTap: () => setState(() {
                    _pointing = true;
                    _options = null;
                  })),
        ]),
        const StudioLabel("Cells"),
        _swatches("tableCellFill", "Fill", t.cellFill,
            (v) => _set(t.copyWith(cellFill: v))),
        _swatches("tableCellInk", "Words", t.cellSpec.color,
            (v) => _set(t.copyWith(cellSpec: t.cellSpec.copyWith(color: v))),
            none: false),
        _slider(
            "Size",
            t.cellSpec.fontSize,
            6,
            72,
            20,
            (v) =>
                _live(t.copyWith(cellSpec: t.cellSpec.copyWith(fontSize: v)))),
        _typeface("tableCellFont", t.cellSpec,
            (spec) => _set(t.copyWith(cellSpec: spec))),
        _slider("Padding", t.cellPadding, 0, 40, 10,
            (v) => _live(t.copyWith(cellPadding: v))),
        // One figure until somebody wants four: a title row often wants
        // more above and below.
        StudioPills<bool>(
            id: "tablePadSides",
            label: "Padding sides",
            value: t.evenPadding,
            options: const [(true, "All the same"), (false, "Each side")],
            onChanged: (even) => _set(even
                ? t.copyWith(evenPadding: true)
                : t.copyWith(
                    padTop: t.topPad,
                    padRight: t.rightPad,
                    padBottom: t.bottomPad,
                    padLeft: t.leftPad))),
        if (!t.evenPadding) ...[
          _slider("Top", t.topPad, 0, 40, t.cellPadding,
              (v) => _live(t.copyWith(padTop: v))),
          _slider("Right", t.rightPad, 0, 40, t.cellPadding,
              (v) => _live(t.copyWith(padRight: v))),
          _slider("Bottom", t.bottomPad, 0, 40, t.cellPadding,
              (v) => _live(t.copyWith(padBottom: v))),
          _slider("Left", t.leftPad, 0, 40, t.cellPadding,
              (v) => _live(t.copyWith(padLeft: v))),
        ],
        _slider("Pictures", t.pictureScale, 0.2, 1.5, 1,
            (v) => _live(t.copyWith(pictureScale: v)),
            format: (v) => "${(v * 100).round()}%"),
        StudioPills<bool>(
            id: "tableZebra",
            label: "Stripes",
            value: t.zebra,
            options: const [(true, "On"), (false, "Off")],
            onChanged: (v) => _set(t.copyWith(zebra: v))),
        if (t.zebra)
          _swatches("tableZebraFill", "Stripe", t.zebraFill,
              (v) => _set(t.copyWith(zebraFill: v.withValues(alpha: 0.1)))),
        StudioPills<TableGrid>(
            id: "tableGrid",
            label: "Lines",
            value: t.grid,
            options: [for (var g in TableGrid.values) (g, g.label)],
            onChanged: (v) => _set(t.copyWith(grid: v))),
        if (t.grid != TableGrid.none) ...[
          _swatches("tableGridColour", "Line colour", t.gridColor,
              (v) => _set(t.copyWith(gridColor: v)),
              none: false),
          _slider("Thickness", t.gridWidth, 0, 6, 1,
              (v) => _live(t.copyWith(gridWidth: v))),
        ],
        _slider("Corners", t.cornerRadius, 0, 40, 6,
            (v) => _live(t.copyWith(cornerRadius: v))),
        StudioPills<bool>(
            id: "tableHeaderRow",
            label: "Header row",
            value: t.headerRow,
            options: const [(true, "Shown"), (false, "None")],
            onChanged: (v) => _set(t.copyWith(headerRow: v))),
        StudioPills<bool>(
            id: "tableHeaderColumn",
            label: "Header column",
            value: t.headerColumn,
            options: const [(true, "Shown"), (false, "None")],
            onChanged: (v) => _set(t.copyWith(headerColumn: v))),
        StudioPills<bool>(
            id: "tableOutline",
            label: "Outline",
            value: t.showOutline,
            options: const [(true, "On"), (false, "Off")],
            onChanged: (v) => _set(t.copyWith(showOutline: v))),
        StudioPills<String>(
            id: "tableColumns",
            label: "Columns",
            value: _columnSizing,
            options: [
              ("fit", "Fit to contents"),
              ("even", "All the same"),
              if (_columnSizing == "dragged") ("dragged", "As dragged"),
            ],
            onChanged: (v) {
              if (v == _columnSizing || v == "dragged") return;
              _set(t.copyWith(
                  columnWidths: v == "fit"
                      ? const []
                      : List.filled(
                          t.columnCount, 1 / math.max(1, t.columnCount))));
            }),
        _buttons([
          StudioPill(
              key: const ValueKey("tableDesignMatchCanvas"),
              label: "Match the canvas",
              icon: Icons.format_paint_outlined,
              tooltip: "Colours taken from the canvas's background and "
                  "what is on it",
              onTap: () {
                var d = c.document;
                _set(tableInColours(
                    t,
                    canvasColours(d.background.spec.background, [
                      for (var other in d.elements)
                        if (other.id != t.id) other
                    ])));
              }),
        ]),
        ..._rowsShown(context),
        const StudioLabel("Motion"),
        StudioPills<String>(
            id: "tableTurn",
            label: "Arrives",
            value: t.turn.name,
            options: [for (var v in TableTurn.values) (v.name, v.label)],
            onChanged: (v) => _set(t.copyWith(turn: TableTurn.fromName(v)))),
        _hint(context,
            "Whole, or a row or a column at a time, as it arrives on the canvas."),
      ];

  /// _columnSizing is which of three states its columns are in: sized by
  /// what is in them, all the same, or as they were dragged.
  String get _columnSizing {
    if (t.evenColumns) return "fit";
    var first = t.columnWidths.first;
    for (var w in t.columnWidths) {
      if ((w - first).abs() > 0.001) return "dragged";
    }
    return "even";
  }

  /// _typeface is a dropdown of the faces for [spec].
  Widget _typeface(String id, TextSpec spec, ValueChanged<TextSpec> set) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const StudioLabel("Typeface"),
        _Dropdown<String>(
            key: ValueKey(id),
            value: spec.fontFamily,
            options: [
              if (!canvasFonts.contains(spec.fontFamily))
                (spec.fontFamily, spec.fontFamily),
              for (var f in canvasFonts) (f, f),
            ],
            onChanged: (f) => set(spec.copyWith(fontFamily: f))),
      ]);

  /// _rowsShown is which of its sheet's rows the table shows, and in what
  /// order: its own, the sheet left as it is (moved here from the Sheet
  /// tab's side panel, Ken 2026-11-16).
  List<Widget> _rowsShown(BuildContext context) {
    var link = linkOf(t);
    var sheet = link == null ? null : c.sheetById(link.sheet);
    if (link == null || sheet == null) return const [];
    void set(SheetLink next) => _set(withLink(t, next) as TableElement);
    var columns = [
      for (var col = 0; col < link.range.cols; col++)
        (col, sheetColumnName(sheet, link, col)),
    ];
    return [
      const StudioLabel("Rows shown"),
      _hint(
          context,
          "Which of the sheet's rows this table shows, and in what order. "
          "The sheet isn't changed: a table can show every club while a "
          "chart of the same sheet shows the top five."),
      const SizedBox(height: 6),
      const StudioLabel("In order of"),
      _Dropdown<int>(
          key: const ValueKey("tableRowsSort"),
          value: link.sortBy.clamp(-1, link.range.cols - 1),
          options: [(-1, "The sheet's own order"), ...columns],
          onChanged: (v) => set(link.copyWith(sortBy: v))),
      if (link.sortBy >= 0)
        StudioPills<bool>(
            id: "tableRowsOrder",
            label: "",
            value: link.descending,
            options: const [(true, "Largest first"), (false, "Smallest first")],
            onChanged: (v) => set(link.copyWith(descending: v))),
      StudioPills<int>(
          id: "tableRowsTop",
          label: "Show",
          value: const [0, 3, 5, 10, 20].contains(link.top) ? link.top : 0,
          options: [
            (0, "Every row"),
            for (var n in const [3, 5, 10, 20])
              (n, link.sortBy >= 0 ? "Top $n" : "First $n"),
          ],
          onChanged: (n) => set(link.copyWith(top: n))),
      const StudioLabel("Only where"),
      _Dropdown<int>(
          key: const ValueKey("tableRowsWhere"),
          value: link.whereColumn.clamp(-1, link.range.cols - 1),
          options: [(-1, "Every row"), ...columns],
          onChanged: (v) => set(link.copyWith(whereColumn: v))),
      if (link.whereColumn >= 0) ...[
        const SizedBox(height: 6),
        _TextBox(
            key: const ValueKey("tableRowsIs"),
            text: link.where,
            hint: "is: >5, Arsenal, <>0",
            onChanged: (v) =>
                _live(withLink(t, link.copyWith(where: v)) as TableElement)),
      ],
    ];
  }

  List<Widget> _headerPanel(BuildContext context) => [
        _swatches("tableHeaderFill", "Fill", t.headerFill,
            (v) => _set(t.copyWith(headerFill: v))),
        _swatches(
            "tableHeaderInk",
            "Words",
            t.headerSpec.color,
            (v) =>
                _set(t.copyWith(headerSpec: t.headerSpec.copyWith(color: v))),
            none: false),
        _slider(
            "Size",
            t.headerSpec.fontSize,
            6,
            72,
            20,
            (v) => _live(
                t.copyWith(headerSpec: t.headerSpec.copyWith(fontSize: v)))),
        StudioPills<int>(
            id: "tableHeaderWeight",
            label: "Weight",
            value: t.headerSpec.weight,
            options: const [(300, "Light"), (400, "Regular"), (700, "Bold")],
            onChanged: (v) =>
                _set(t.copyWith(headerSpec: t.headerSpec.copyWith(weight: v)))),
        _typeface("tableHeaderFont", t.headerSpec,
            (spec) => _set(t.copyWith(headerSpec: spec))),
        _slider("Height", t.headerHeightRatio, 0.5, 3, 1.15,
            (v) => _live(t.copyWith(headerHeightRatio: v)),
            format: (v) => "${v.toStringAsFixed(2)}×"),
        _hint(context, "Its height against a row's."),
        const StudioLabel("Styles on it"),
        ..._styleList(context, stylesOnRow(t, 0)),
      ];

  List<Widget> _columnPanel(BuildContext context, int col) {
    var g = _Geom.of(t, 1000);
    var widths = g.w;
    var stylesHere = stylesOnColumn(t, col);
    return [
      _slider(
          "Width", widths[col], 10, math.max(60, t.width * 0.7), widths[col],
          (v) {
        var next = [...widths];
        next[col] = v;
        _live(t.copyWith(columnWidths: next));
      }, format: (v) => "${v.round()}"),
      _hint(context,
          "The others make room. Widths are kept as shares of the table's."),
      StudioLabel("Styles on this column · ${stylesHere.length}"),
      ..._styleList(context, stylesHere),
      _buttons([
        StudioPill(
            key: const ValueKey("tableDesignStyleColumn"),
            label: "+ New style from this",
            onTap: () => _offer(reachOptions(t, TablePart.column(col)))),
      ]),
      ..._wordsGuide(context, col),
    ];
  }

  /// _wordsGuide gathers the styles about words in one column -- the Form
  /// column's W, D and L boxes (prototype v2's Form guide) -- so their
  /// boxes are set side by side, and their size and corners together.
  List<Widget> _wordsGuide(BuildContext context, int col) {
    var words = [
      for (var i in stylesOnColumn(t, col))
        if (t.rules[i].match.isNotEmpty && t.rules[i].column.trim().isNotEmpty)
          i
    ];
    if (words.length < 2) return const [];
    var boxed = [
      for (var i in words)
        if (t.rules[i].style.background.a > 0) i
    ];
    void all(TableCellStyle Function(TableCellStyle) change) {
      var rules = [...t.rules];
      for (var i in boxed) {
        rules[i] = rules[i].copyWith(style: change(rules[i].style));
      }
      _live(t.copyWith(rules: rules));
    }

    var size = boxed.isEmpty ? 0.0 : t.rules[boxed.first].style.minWidth;
    var corners = boxed.isEmpty ? 0.0 : t.rules[boxed.first].style.radius;
    return [
      StudioLabel("Its words · ${words.length}"),
      _hint(context, "Each word's box and colour, side by side."),
      for (var i in words) ...[
        _swatches(
            "tableWordBox-$i",
            "“${t.rules[i].match}” box",
            t.rules[i].style.background,
            (v) => _setRule(
                i,
                t.rules[i].copyWith(
                    style: t.rules[i].style.copyWith(background: v)))),
        _swatches(
            "tableWordInk-$i",
            "“${t.rules[i].match}” words",
            t.rules[i].style.textColor,
            (v) => _setRule(
                i,
                t.rules[i]
                    .copyWith(style: t.rules[i].style.copyWith(textColor: v)))),
      ],
      if (boxed.isNotEmpty) ...[
        _slider("Box size", size, 0, 60, 0,
            (v) => all((s) => s.copyWith(minWidth: v, minHeight: v))),
        _slider("Box corners", corners, 0, 20, 4,
            (v) => all((s) => s.copyWith(radius: v))),
      ],
    ];
  }

  List<Widget> _rowPanel(BuildContext context, int row) {
    var stylesHere = stylesOnRow(t, row);
    return [
      StudioLabel("Styles on this row · ${stylesHere.length}"),
      ..._styleList(context, stylesHere),
      _buttons([
        StudioPill(
            key: const ValueKey("tableDesignStyleRow"),
            label: "+ New style from this",
            onTap: () => _offer(reachOptions(t, TablePart.row(row)))),
      ]),
      _hint(context, "Shift-click other row tabs to style several rows."),
    ];
  }

  List<Widget> _cellPanel(BuildContext context, int row, int col) {
    var on = stylesAt(t, row, col);
    return [
      StudioLabel("On this cell · ${on.length}"),
      _hint(
          context,
          on.isEmpty
              ? "No styles reach it: it has the table's look."
              : "In the order they apply: where two say different things, the lower one wins."),
      const SizedBox(height: 6),
      ..._styleList(context, on),
      _buttons([
        StudioPill(
            key: const ValueKey("tableDesignStyleCell"),
            label: "+ New style from this",
            onTap: () => _offer(reachOptions(t, TablePart.cell(row, col)))),
        StudioPill(
            key: const ValueKey("tableCellCopy"),
            label: "Copy its look",
            onTap: () => setState(() =>
                _copied = t.lookAt(row, col).style ?? const TableCellStyle())),
        if (t.lookAt(row, col).style != null)
          StudioPill(
              key: const ValueKey("tableCellMake"),
              label: "Make a style from its look",
              onTap: () {
                var o = reachOptions(t, TablePart.cell(row, col)).firstOrNull;
                if (o == null) return;
                _newStyle(o.rule.copyWith(style: t.lookAt(row, col).style));
              }),
        StudioPill(
            label: "Its column", onTap: () => _pick(TablePart.column(col))),
        StudioPill(
            label: row == 0 && t.headerRow ? "The header" : "Its row",
            onTap: () => _pick(row == 0 && t.headerRow
                ? TablePart.header
                : TablePart.row(row))),
      ]),
    ];
  }

  List<Widget> _stylePanel(BuildContext context, int i) {
    var rule = t.rules[i];
    var s = rule.style;
    void look(TableCellStyle next, {bool live = false}) =>
        _setRule(i, rule.copyWith(style: next), live: live);
    var idle = styleIdle(t, rule);
    var columns = <(String, String)>[
      ("", "Every column"),
      for (var col = 0; col < t.columnCount; col++)
        (_columnKey(col), t.columnName(col)),
    ];
    var colValue = rule.column.trim();
    if (!columns.any((o) => o.$1.toLowerCase() == colValue.toLowerCase())) {
      columns.add((colValue, spanWords(colValue, "column")));
    } else {
      colValue = columns
          .firstWhere((o) => o.$1.toLowerCase() == colValue.toLowerCase())
          .$1;
    }
    var rowsKind = switch (rule.rows.trim()) {
      "" => "",
      "1" when t.headerRow => "1",
      ">1" when t.headerRow => ">1",
      _ => "some",
    };
    List<bool> sidesOf(String k) => switch (k) {
          "above" => const [true, false, false, false],
          "under" => const [false, false, true, false],
          "both" => const [true, false, true, false],
          "sides" => const [false, true, false, true],
          _ => const [true, true, true, true],
        };
    var sidesKey = s.allSides
        ? "all"
        : switch (s.sides) {
            [true, false, false, false] => "above",
            [false, false, true, false] => "under",
            [true, false, true, false] => "both",
            [false, true, false, true] => "sides",
            _ => "own",
          };
    return [
      if (_made) ...[
        _hint(context,
            "Step 2 of 2: its look. It names itself from what it reaches and looks like, until you type a name.",
            color: ThemeNotifier.of(context).colors.primary),
        _buttons([
          StudioPill(
              key: const ValueKey("tableNewDone"),
              label: "Done",
              filled: true,
              onTap: () => _pick(TablePart.table)),
        ]),
      ],
      if (idle != null)
        _hint(context, "Does nothing: $idle.", color: const Color(0xFFF2B33D)),
      const StudioLabel("Name"),
      _TextBox(
        key: ValueKey("tableStyleName-$i"),
        text: rule.name,
        hint: styleName(t.copyWith(rules: [rule.copyWith(name: "")]), 0),
        onChanged: (v) => _setRule(i, rule.copyWith(name: v), live: true),
      ),
      const StudioLabel("What it reaches"),
      _Dropdown<String>(
        key: ValueKey("tableStyleColumn-$i"),
        value: colValue,
        options: columns,
        onChanged: (v) => _setRule(i, rule.copyWith(column: v)),
      ),
      const SizedBox(height: 6),
      if (rule.keys.isNotEmpty) ...[
        const StudioLabel("Follows"),
        _TextBox(
          key: ValueKey("tableStyleKeys-$i"),
          text: rule.keys.join(", "),
          hint: "Names, with commas between",
          onChanged: (v) => _setRule(
              i,
              rule.copyWith(keys: [
                for (var k in v.split(","))
                  if (k.trim().isNotEmpty) k.trim()
              ]),
              live: true),
        ),
        _hint(context,
            "Found in the ${rule.keyColumn} column, wherever they are as the numbers change."),
        _buttons([
          StudioPill(
              key: const ValueKey("tableStyleKeep"),
              label: "Keep to their places now",
              onTap: () => _setRule(i, _kept(rule))),
        ]),
      ] else
        StudioPills<String>(
            id: "tableStyleRows",
            label: "Rows",
            value: rowsKind,
            options: [
              ("", "Every row"),
              if (t.headerRow) ("1", "The header"),
              if (t.headerRow) (">1", "All but the header"),
              ("some", "Some rows"),
            ],
            onChanged: (v) => _setRule(
                i,
                rule.copyWith(
                    rows: v == "some" ? (t.headerRow ? "2" : "1") : v))),
      if (rowsKind == "some") ...[
        const SizedBox(height: 6),
        _TextBox(
          key: ValueKey("tableStyleRowsText-$i"),
          text: rule.rows,
          hint: "5, or 18:20, or >1",
          onChanged: (v) => _setRule(i, rule.copyWith(rows: v), live: true),
        ),
        _hint(context,
            "${spanWords(rule.rows, "row", header: t.headerRow)}. Counting the header as 1: “18:20” is three rows, “>1” every row after the first."),
      ],
      if (rule.keys.isEmpty &&
          rowsKind == "some" &&
          keyColumnOf(t) >= 0 &&
          _followable(rule))
        _buttons([
          StudioPill(
              key: const ValueKey("tableStyleFollow"),
              label: "Follow who is there now",
              onTap: () => _setRule(i, _followed(rule))),
        ]),
      ..._whenPart(context, i, rule),
      const StudioLabel("Only where it says"),
      _TextBox(
        key: ValueKey("tableStyleMatch-$i"),
        text: rule.match,
        hint: "Words to look for (empty: every cell)",
        onChanged: (v) => _setRule(i, rule.copyWith(match: v), live: true),
      ),
      if (rule.match.isNotEmpty)
        StudioPills<TableMatch>(
            id: "tableStyleHow",
            label: "Found as",
            value: rule.how,
            options: [for (var m in TableMatch.values) (m, m.label)],
            onChanged: (v) => _setRule(i, rule.copyWith(how: v))),
      const StudioLabel("Its look"),
      _swatches("tableStyleFill", "Fill", s.background,
          (v) => look(s.copyWith(background: v))),
      _swatches("tableStyleInk", "Words", s.textColor,
          (v) => look(s.copyWith(textColor: v))),
      _slider("Size", s.fontScale, 0.4, 2.5, 1,
          (v) => look(s.copyWith(fontScale: v), live: true),
          format: (v) => "${(v * 100).round()}%"),
      StudioPills<int>(
          id: "tableStyleWeight",
          label: "Weight",
          value: s.weight,
          options: const [
            (0, "Its own"),
            (300, "Light"),
            (400, "Regular"),
            (700, "Bold")
          ],
          onChanged: (v) => look(s.copyWith(weight: v))),
      StudioPills<String>(
          id: "tableStyleAlign",
          label: "Lined up",
          value: s.align?.name ?? "",
          options: const [
            ("", "Its own"),
            ("left", "Left"),
            ("center", "Centre"),
            ("right", "Right")
          ],
          onChanged: (v) => look(v.isEmpty
              ? TableCellStyle.fromJson({...s.toJson()}..remove("align"))
              : s.copyWith(align: TextAlignSpec.values.byName(v)))),
      if (rule.match.isNotEmpty || s.background.a > 0)
        StudioPills<bool>(
            id: "tableStyleHug",
            label: "Box",
            value: s.hug,
            options: const [
              (true, "Round the words"),
              (false, "Fills the cell")
            ],
            onChanged: (v) => look(s.copyWith(hug: v))),
      if (s.background.a > 0) ...[
        _slider("Corners", s.radius, 0, 24, 4,
            (v) => look(s.copyWith(radius: v), live: true)),
        _slider("Inset", s.inset, 0, 24, 6,
            (v) => look(s.copyWith(inset: v), live: true)),
      ],
      const StudioLabel("Lines"),
      _swatches("tableStyleLine", "Colour", s.borderColor, (v) {
        look(s.copyWith(
            borderColor: v,
            borderWidth: v.a > 0 && s.borderWidth == 0 ? 2 : s.borderWidth));
      }),
      if (s.borderColor.a > 0) ...[
        _slider("Thickness", s.borderWidth, 0, 8, 0,
            (v) => look(s.copyWith(borderWidth: v), live: true)),
        StudioPills<String>(
            id: "tableStyleSides",
            label: "Where",
            value: sidesKey,
            options: [
              ("all", "All round"),
              ("above", "Above"),
              ("under", "Under"),
              ("both", "Above and under"),
              ("sides", "Either side"),
              if (sidesKey == "own") ("own", "Its own"),
            ],
            onChanged: (v) {
              if (v != "own") look(s.copyWith(sides: sidesOf(v)));
            }),
      ],
      _buttons([
        StudioPill(
            key: const ValueKey("tableStyleFine"),
            label: _fine ? "Fine placement ▴" : "Fine placement ▾",
            onTap: () => setState(() => _fine = !_fine)),
      ]),
      if (_fine) ...[
        _hint(context,
            "For boxes round single letters, so a row of them lines up: a fixed width per letter, the gap, a least size, and nudges for a letter whose ink sits off-centre."),
        _slider("Letter width", s.letterWidth, 0, 40, 0,
            (v) => look(s.copyWith(letterWidth: v), live: true)),
        _slider("Letter gap", s.letterSpacing, -5, 20, 0,
            (v) => look(s.copyWith(letterSpacing: v), live: true)),
        _slider("Margin", s.textPad, 0, 30, 0,
            (v) => look(s.copyWith(textPad: v), live: true)),
        _slider("Least width", s.minWidth, 0, 80, 0,
            (v) => look(s.copyWith(minWidth: v), live: true)),
        _slider("Least height", s.minHeight, 0, 80, 0,
            (v) => look(s.copyWith(minHeight: v), live: true)),
        _slider("Nudge across", s.nudgeX, -10, 10, 0,
            (v) => look(s.copyWith(nudgeX: v), live: true)),
        _slider("Nudge down", s.nudgeY, -10, 10, 0,
            (v) => look(s.copyWith(nudgeY: v), live: true)),
        StudioPills<bool>(
            id: "tableStyleRedact",
            label: "Words",
            value: s.redact,
            options: const [(false, "Shown"), (true, "Hidden")],
            onChanged: (v) => look(s.copyWith(redact: v))),
      ],
      const StudioLabel("This style"),
      _buttons([
        StudioPill(
            key: const ValueKey("tableStyleCopy"),
            label: "Copy look",
            onTap: () => setState(() => _copied = s)),
        StudioPill(
            key: const ValueKey("tableStylePaste"),
            label: "Paste look",
            onTap: _copied == null ? null : () => look(_copied!)),
        StudioPill(
            key: const ValueKey("tableStyleOff"),
            label: rule.off ? "Switch on" : "Switch off",
            onTap: () => _setRule(i, rule.copyWith(off: !rule.off))),
        StudioPill(
            key: const ValueKey("tableStyleDuplicate"),
            label: "Duplicate",
            onTap: () {
              var rules = [...t.rules]..insert(
                  i + 1,
                  rule.copyWith(
                      name: rule.name.isEmpty ? "" : "${rule.name} (copy)"));
              _set(t.copyWith(rules: rules));
              _pick(TablePart.style(i + 1));
            }),
        StudioPill(
            key: const ValueKey("tableStyleEarlier"),
            label: "Earlier",
            tooltip: "Applied before the one above it",
            onTap: i == 0 ? null : () => _move(i, -1)),
        StudioPill(
            key: const ValueKey("tableStyleLater"),
            label: "Later",
            tooltip: "Applied after the one below it, so it wins",
            onTap: i == t.rules.length - 1 ? null : () => _move(i, 1)),
        StudioPill(
            key: const ValueKey("tableStyleDelete"),
            label: "Delete",
            onTap: () {
              _set(t.copyWith(rules: [...t.rules]..removeAt(i)));
              _pick(TablePart.table);
            }),
      ]),
    ];
  }

  /// _kept is [rule] keeping to where the teams it follows are now.
  TableRule _kept(TableRule rule) {
    var rows = [
      for (var r = 0; r < t.rows.length; r++)
        if (rule.reachesRow(r, t.header, (c) => t.cell(r, c))) r + 1
    ];
    var spec = rows.isEmpty
        ? rule.rows
        : rows.length == 1
            ? "${rows.first}"
            : rows.last - rows.first + 1 == rows.length
                ? "${rows.first}:${rows.last}"
                : "${rows.first}";
    return rule.copyWith(rows: spec, keys: const []);
  }

  /// _followable is whether [rule]'s rows are body rows that can be named.
  bool _followable(TableRule rule) {
    var n = 0;
    for (var r = 0; r < t.rows.length; r++) {
      if (rule.matchesRow(r)) {
        if (t.headerRow && r == 0) return false;
        n++;
      }
    }
    return n > 0 && n <= 8;
  }

  /// _followed is [rule] going with the teams in its rows now.
  TableRule _followed(TableRule rule) {
    var k = keyColumnOf(t);
    return rule.copyWith(rows: "", keyColumn: columnKey(t, k), keys: [
      for (var r = 0; r < t.rows.length; r++)
        if (rule.matchesRow(r)) t.cell(r, k).trim()
    ]);
  }

  /// _whenPart is a style's number condition: "only where Points is 9 or
  /// more", or a way to add one.
  List<Widget> _whenPart(BuildContext context, int i, TableRule rule) {
    var numeric = [
      for (var col = 0; col < t.columnCount; col++)
        if (t.rows.length > 1 &&
            [
              for (var r = t.headerRow ? 1 : 0; r < t.rows.length; r++)
                t.cell(r, col)
            ]
                .where((v) => v.trim().isNotEmpty)
                .every((v) => cellNumber(v) != null))
          columnKey(t, col)
    ];
    var w = rule.when;
    if (w == null) {
      if (numeric.isEmpty) return const [];
      return [
        _buttons([
          StudioPill(
              key: const ValueKey("tableStyleWhenAdd"),
              label: "+ Only where a number is…",
              onTap: () => _setRule(
                  i, rule.copyWith(when: TableWhen(numeric.last, ">=", 0)))),
        ]),
      ];
    }
    return [
      const StudioLabel("Only where"),
      _Dropdown<String>(
        key: ValueKey("tableStyleWhenColumn-$i"),
        value: numeric.contains(w.column)
            ? w.column
            : numeric.firstOrNull ?? w.column,
        options: [
          for (var n in {...numeric, w.column}) (n, n)
        ],
        onChanged: (v) =>
            _setRule(i, rule.copyWith(when: w.copyWith(column: v))),
      ),
      const SizedBox(height: 6),
      StudioPills<String>(
          id: "tableStyleWhenOp",
          label: "Is",
          value: w.op,
          options: const [
            (">=", "or more"),
            ("<=", "or less"),
            (">", "over"),
            ("<", "under"),
            ("=", "exactly"),
          ],
          onChanged: (v) =>
              _setRule(i, rule.copyWith(when: w.copyWith(op: v)))),
      const SizedBox(height: 6),
      _TextBox(
        key: ValueKey("tableStyleWhenValue-$i"),
        text: w.value == w.value.roundToDouble()
            ? "${w.value.round()}"
            : "${w.value}",
        hint: "A number",
        onChanged: (v) {
          var n = double.tryParse(v.trim());
          if (n != null) {
            _setRule(i, rule.copyWith(when: w.copyWith(value: n)), live: true);
          }
        },
      ),
      _hint(context, "Changes as the numbers do: ${whenWords(w)}."),
      _buttons([
        StudioPill(
            key: const ValueKey("tableStyleWhenRemove"),
            label: "No number condition",
            onTap: () => _setRule(i, rule.copyWith(noWhen: true))),
      ]),
    ];
  }

  void _move(int i, int by) {
    var rules = [...t.rules];
    var r = rules.removeAt(i);
    rules.insert(i + by, r);
    _set(t.copyWith(rules: rules));
    _pick(TablePart.style(i + by));
  }
}

/// _Geom is where the table and its tabs are on the stage: the table scaled
/// to the stage's width (no larger than 125%), the column tabs over it, the
/// row tabs left of it.
class _Geom {
  final double k;
  final Offset o;
  final List<double> w, h;
  final Size size;
  final Size table;
  const _Geom(this.k, this.o, this.w, this.h, this.size, this.table);

  static const tab = 22.0, gap = 6.0, margin = 16.0;

  factory _Geom.of(TableElement t, double avail) {
    var rect = Rect.fromLTWH(0, 0, math.max(1, t.width), math.max(1, t.height));
    var k = ((avail - margin * 2 - tab - gap) / rect.width)
        .clamp(0.1, 1.25)
        .toDouble();
    var o = const Offset(margin + tab + gap, margin + tab + gap);
    var w = t.rows.isEmpty ? <double>[] : tableColumnWidths(t, rect);
    var h = t.rows.isEmpty ? <double>[] : tableRowHeights(t, rect);
    return _Geom(k, o, w, h, Size(avail, o.dy + rect.height * k + margin),
        Size(rect.width * k, rect.height * k));
  }

  double _sum(List<double> v, int n) {
    var s = 0.0;
    for (var i = 0; i < n && i < v.length; i++) {
      s += v[i];
    }
    return s;
  }

  Rect get tableRect => o & table;
  Rect colRect(int j) =>
      Rect.fromLTWH(o.dx + _sum(w, j) * k, o.dy, w[j] * k, table.height);
  Rect colTab(int j) =>
      Rect.fromLTWH(o.dx + _sum(w, j) * k + 1, margin, w[j] * k - 2, tab);
  Rect rowRect(int i) =>
      Rect.fromLTWH(o.dx, o.dy + _sum(h, i) * k, table.width, h[i] * k);
  Rect rowTab(int i) =>
      Rect.fromLTWH(margin, o.dy + _sum(h, i) * k + 1, tab, h[i] * k - 2);
  Rect cellRect(int i, int j) => Rect.fromLTWH(
      o.dx + _sum(w, j) * k, o.dy + _sum(h, i) * k, w[j] * k, h[i] * k);

  /// partAt is the part under [p], or null off the table.
  TablePart? partAt(Offset p, TableElement t) {
    if (p.dy >= margin && p.dy <= margin + tab) {
      for (var j = 0; j < w.length; j++) {
        if (colTab(j).inflate(1).contains(p)) return TablePart.column(j);
      }
    }
    if (p.dx >= margin && p.dx <= margin + tab) {
      for (var i = 0; i < h.length; i++) {
        if (rowTab(i).inflate(1).contains(p)) {
          return t.headerRow && i == 0 ? TablePart.header : TablePart.row(i);
        }
      }
    }
    if (tableRect.contains(p)) {
      for (var i = 0; i < h.length; i++) {
        for (var j = 0; j < w.length; j++) {
          if (cellRect(i, j).contains(p)) return TablePart.cell(i, j);
        }
      }
    }
    if (tableRect.inflate(14).contains(p)) return TablePart.table;
    return null;
  }

  /// edgeAt is the column whose right edge is under [p] (within a few
  /// pixels), over the tabs or the table, for dragging; never the last.
  int? edgeAt(Offset p) {
    if (p.dy < margin || p.dy > o.dy + table.height) return null;
    var x = o.dx;
    for (var j = 0; j < w.length - 1; j++) {
      x += w[j] * k;
      if ((p.dx - x).abs() <= 4) return j;
    }
    return null;
  }

  /// rectsOf is where [part] is drawn, to outline it.
  List<Rect> rectsOf(TablePart part, TableElement t) => switch (part.kind) {
        TablePartKind.table => [tableRect],
        TablePartKind.header => h.isEmpty ? [] : [rowRect(0), rowTab(0)],
        TablePartKind.column =>
          part.col < w.length ? [colRect(part.col), colTab(part.col)] : [],
        TablePartKind.row =>
          part.row < h.length ? [rowRect(part.row), rowTab(part.row)] : [],
        TablePartKind.cell => part.row < h.length && part.col < w.length
            ? [cellRect(part.row, part.col)]
            : [],
        TablePartKind.style => [],
      };
}

class _StagePainter extends CustomPainter {
  final TableElement t;
  final _Geom g;
  final Color ground, accent, tabFill, tabInk;
  final CanvasImageStore images;
  final TablePart picked;
  final TablePart? hover;
  final List<(int, int)> lit;
  final String Function(int) columnLabel, rowLabel;
  final List<int> rows;
  _StagePainter({
    this.rows = const [],
    required this.t,
    required this.g,
    required this.ground,
    required this.images,
    required this.picked,
    required this.hover,
    required this.lit,
    required this.accent,
    required this.tabFill,
    required this.tabInk,
    required this.columnLabel,
    required this.rowLabel,
  }) : super(repaint: images);

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas's own ground behind the table, as on the page.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            g.tableRect.inflate(12), const Radius.circular(8)),
        Paint()..color = ground);
    canvas.save();
    canvas.translate(g.o.dx, g.o.dy);
    canvas.scale(g.k);
    paintTable(canvas, Rect.fromLTWH(0, 0, t.width, t.height), t,
        images: images);
    canvas.restore();

    bool isPicked(TablePart p) => picked == p;
    bool isHover(TablePart p) => hover == p;
    void tabAt(Rect r, String label, TablePart p) {
      var on = isPicked(p) ||
          (picked.kind == TablePartKind.cell &&
              ((p.kind == TablePartKind.column && p.col == picked.col) ||
                  (p.kind == TablePartKind.row && p.row == picked.row) ||
                  (p.kind == TablePartKind.header && picked.row == 0)));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(5)),
          Paint()
            ..color = on
                ? accent
                : isHover(p)
                    ? _hoverInk.withValues(alpha: 0.35)
                    : tabFill);
      var tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: on ? const Color(0xFF062018) : tabInk)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: math.max(1, r.width));
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }

    for (var j = 0; j < g.w.length; j++) {
      tabAt(g.colTab(j), columnLabel(j), TablePart.column(j));
    }
    for (var i = 0; i < g.h.length; i++) {
      tabAt(g.rowTab(i), rowLabel(i),
          t.headerRow && i == 0 ? TablePart.header : TablePart.row(i));
    }

    // What a style reaches, lit.
    if (lit.isNotEmpty) {
      var fill = Paint()..color = accent.withValues(alpha: 0.22);
      var edge = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var (r, col) in lit) {
        if (r >= g.h.length || col >= g.w.length) continue;
        var rect = g.cellRect(r, col).deflate(1);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, edge);
      }
    }

    var hv = hover;
    if (hv != null && hv != picked) {
      var p = Paint()
        ..color = _hoverInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var r in g.rectsOf(hv, t)) {
        canvas.drawRect(r.deflate(0.75), p);
      }
    }
    var p = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var r in g.rectsOf(picked, t)) {
      canvas.drawRect(r.deflate(1), p);
    }
    if (rows.length > 1) {
      for (var row in rows) {
        for (var r in g.rectsOf(TablePart.row(row), t)) {
          canvas.drawRect(r.deflate(1), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) =>
      !identical(old.t, t) ||
      old.picked != picked ||
      old.hover != hover ||
      old.lit != lit ||
      old.rows != rows ||
      old.g.k != g.k ||
      old.ground != ground ||
      old.accent != accent;
}

/// _TextBox is a one-line field that keeps what is typed while the table
/// changes under it.
class _TextBox extends StatefulWidget {
  final String text, hint;
  final ValueChanged<String> onChanged;
  const _TextBox(
      {required this.text,
      required this.hint,
      required this.onChanged,
      super.key});

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  late final TextEditingController _c =
      TextEditingController(text: widget.text);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(_TextBox old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return TextField(
      controller: _c,
      focusNode: _f,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 13, color: colors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide.none),
      ),
    );
  }
}

/// _Dropdown is a choice among many, as a dropdown (Ken prefers them to
/// pop-ups for long lists).
class _Dropdown<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const _Dropdown(
      {required this.value,
      required this.options,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(7)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          style: TextStyle(fontSize: 13, color: colors.onSurface),
          dropdownColor: colors.surfaceContainerHigh,
          items: [
            for (var (v, name) in options)
              DropdownMenuItem(
                  value: v, child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

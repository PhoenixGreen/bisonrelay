import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/chart_presets.dart'
    show ChartUse;
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/table_design.dart';
import 'package:bruig/plugin_system/canvas/model/table_presets.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart' show CanvasHint;
import 'package:bruig/plugin_system/canvas/ui/data_studio_side.dart';
import 'package:bruig/plugin_system/canvas/ui/data_style_picker.dart';
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

Color _colour(int? v) =>
    v == null ? const Color(0x00000000) : Color(0xFF000000 | v);

class _TableDesignState extends State<TableDesign> {
  CanvasController get c => widget.controller;
  TableElement get t => widget.table;
  TablePart _picked = TablePart.table;
  TablePart? _hover;
  int? _hoverStyle;

  // The gallery of designs (Ken, 2026-11-17; prototype v7): open, the kind
  // opened, the design picked, and what they're filtered by.
  bool _gallery = false;
  String? _galleryKind;
  int? _galleryPreset;
  ChartUse? _galleryUse;

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
            Expanded(child: _gallery ? _designs(context) : _stage(context)),
          ]),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
        SizedBox(
            width: 380,
            child: _gallery ? _designPanel(context) : _panel(context)),
      ]),
    );
  }

  /// _crumbs is the bar over the stage: what can be done there, and the
  /// designs. The way to what is picked is in the sidebar's header now.
  Widget _crumbs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      height: 38,
      child: Row(children: [
        const SizedBox(width: 14),
        Expanded(
          child: Text(
              _pointing
                  ? "Click what to style · Esc to stop"
                  : "Click a cell, a tab, or round the table · shift-click row tabs · drag a column's edge · Esc goes up",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
        ),
        const SizedBox(width: 8),
        StudioPill(
            key: const ValueKey("tableDesignGallery"),
            label: _gallery ? "Back to the table" : "Designs",
            icon: _gallery
                ? Icons.arrow_back
                : Icons.dashboard_customize_outlined,
            selected: _gallery,
            tooltip: "Starting designs for this table, drawn with its cells",
            onTap: () => setState(() {
                  _gallery = !_gallery;
                  _galleryKind = null;
                  _galleryPreset = null;
                })),
        const SizedBox(width: 12),
      ]),
    );
  }

  // ---- The gallery of designs.

  Color get _ground =>
      dataStyleNamed(t.style)?.ground ?? c.document.background.spec.background;

  TableKind get _kindOpen => tableKinds.firstWhere((k) => k.id == _galleryKind);

  Widget _designCard(BuildContext context,
      {required Key key,
      required String name,
      required String says,
      required TableElement? shown,
      required bool picked,
      List<ChartUse> uses = const [],
      VoidCallback? onTap}) {
    final colors = ThemeNotifier.of(context).colors;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: picked ? colors.primary : colors.outlineVariant,
                width: picked ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: shown == null
                      ? ColoredBox(color: colors.surfaceContainerHighest)
                      : CustomPaint(
                          size: Size.infinite,
                          painter: _DesignThumb(shown, _ground, c.images)),
                ),
              ),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface)),
              Text(says,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: colors.onSurfaceVariant)),
              if (uses.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(uses.map((u) => u.label).join(" · "),
                    style: TextStyle(fontSize: 10.5, color: colors.primary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _designGrid(List<Widget> cards) =>
      LayoutBuilder(builder: (context, box) {
        var n = math.max(1, (box.maxWidth / 260).floor());
        var w = (box.maxWidth - 12 * (n - 1)) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (var card in cards)
            SizedBox(width: w, height: w * 0.8, child: card),
        ]);
      });

  Widget _designs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var shape = TableShape(t);
    var head = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_galleryKind != null)
              StudioPill(
                  key: const ValueKey("tableGalleryBack"),
                  label: "All tables",
                  icon: Icons.arrow_back,
                  onTap: () => setState(() {
                        _galleryKind = null;
                        _galleryPreset = null;
                      })),
            for (var (u, name) in [
              (null, "All"),
              for (var x in ChartUse.values) (x, x.label)
            ])
              StudioPill(
                  key: ValueKey("tableGalleryUse-${u?.name ?? "all"}"),
                  label: name,
                  selected: _galleryUse == u,
                  onTap: () => setState(() => _galleryUse = u)),
          ]),
    );
    if (_galleryKind == null) {
      var kinds = [
        for (var k in tableKinds)
          if (_galleryUse == null ||
              k.presets.any((p) => p.uses.contains(_galleryUse)))
            k
      ];
      return SingleChildScrollView(
        key: const ValueKey("tableGallery"),
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          _designGrid([
            for (var k in kinds)
              () {
                var p = k.presets.firstWhere(
                    (p) => p.needs?.call(shape) == null,
                    orElse: () => k.presets.first);
                var can = k.presets.any((p) => p.needs?.call(shape) == null);
                return _designCard(context,
                    key: ValueKey("tableKind-${k.id}"),
                    name: k.name,
                    says:
                        can ? k.use : "Needs ${k.presets.first.needs!(shape)}",
                    shown: presetTable(p, t),
                    picked: false,
                    onTap: () => setState(() {
                          _galleryKind = k.id;
                          _galleryPreset = null;
                        }));
              }(),
          ]),
        ]),
      );
    }
    var kind = _kindOpen;
    return SingleChildScrollView(
      key: const ValueKey("tableGalleryPresets"),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Text(kind.name,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        _hint(context,
            "${kind.use} Pick a starting design; it keeps the cells and your own styles."),
        const SizedBox(height: 10),
        _designGrid([
          for (var (i, p) in kind.presets.indexed)
            if (_galleryUse == null || p.uses.contains(_galleryUse))
              _designCard(context,
                  key: ValueKey("tablePreset-$i"),
                  name: p.name,
                  says: p.needs?.call(shape) == null
                      ? p.says
                      : "Needs ${p.needs!(shape)}",
                  shown:
                      p.needs?.call(shape) == null ? presetTable(p, t) : null,
                  picked: _galleryPreset == i,
                  uses: p.uses,
                  onTap: p.needs?.call(shape) == null
                      ? () => setState(() => _galleryPreset = i)
                      : null),
        ]),
      ]),
    );
  }

  Widget _designPanel(BuildContext context) {
    var preset = _galleryKind != null && _galleryPreset != null
        ? _kindOpen.presets[_galleryPreset!]
        : null;
    var shown = preset == null ? null : presetTable(preset, t);
    return StudioSide(
      header: StudioSideHeader(
        icon: Icons.dashboard_customize_outlined,
        crumbs: [
          ("Table", () => setState(() => _gallery = false)),
          ("Designs", null),
        ],
        crumbKey: "tableGalleryCrumb",
        title:
            preset == null ? "Designs" : "${_kindOpen.name} · ${preset.name}",
        titleKey: const ValueKey("tableGalleryTitle"),
        onUp: () => setState(() => _gallery = false),
      ),
      quick: [
        if (shown == null)
          _note("Each kind of table drawn with this table's cells. Open one "
              "to see its starting designs.")
        else ...[
          AspectRatio(
            aspectRatio: 1.4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                  key: const ValueKey("tableGalleryPreview"),
                  size: Size.infinite,
                  painter: _DesignThumb(shown, _ground, c.images)),
            ),
          ),
          const SizedBox(height: 8),
          _note(preset!.says),
          const SizedBox(height: 4),
          _note("It sets the header, lines, stripes, which columns are drawn "
              "rather than written, and what stands out. The cells, your own "
              "styles and the table's style stay."),
        ],
        const SizedBox(height: 10),
        studioButtons([
          if (shown != null)
            studioButton("Use this design",
                key: const ValueKey("tableGalleryApply"),
                primary: true, onPressed: () {
              _set(shown);
              setState(() {
                _gallery = false;
                _galleryKind = null;
                _galleryPreset = null;
                _picked = TablePart.table;
              });
            }),
          studioButton("Cancel",
              key: const ValueKey("tableGalleryCancel"),
              onPressed: () => setState(() => _gallery = false)),
        ]),
      ],
      body: const [],
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

  // ---- The panel: the Studio's sidebar (data_studio_side.dart; Ken,
  // 2026-11-17, the sidebar prototype): the way to what is picked in its
  // header, what is changed most in a strip under it, then sections that
  // fold, each saying what is set in it.

  /// _trail is the way to what is picked, from the table.
  List<TablePart> get _trail {
    var trail = <TablePart>[TablePart.table];
    if (_picked.kind == TablePartKind.cell) {
      trail.add(TablePart.column(_picked.col));
    }
    if (_picked != TablePart.table) trail.add(_picked);
    return trail;
  }

  Widget _panel(BuildContext context) {
    var p = _picked;
    var drafting = _pointing || _options != null;
    var several = _rows.length > 1 && !drafting;
    var trail = _trail;
    var crumbs = drafting
        ? <(String, VoidCallback?)>[("Table", _cancelNew), ("New style", null)]
        : several
            ? <(String, VoidCallback?)>[
                ("Table", () => _pick(TablePart.table)),
                ("${_rows.length} rows", null)
              ]
            : <(String, VoidCallback?)>[
                for (var (i, part) in trail.indexed)
                  (
                    _partName(part),
                    i == trail.length - 1 ? null : () => _pick(part)
                  ),
              ];
    var title = drafting
        ? "New style"
        : several
            ? "${_rows.length} rows"
            : switch (p.kind) {
                TablePartKind.table =>
                  t.name.isEmpty ? "The whole table" : t.name,
                TablePartKind.header => "Header row",
                TablePartKind.column => t.columnName(p.col),
                TablePartKind.row => "Row ${_rowLabel(p.row)}",
                TablePartKind.cell =>
                  "Cell ${_columnLetter(p.col)}${_rowLabel(p.row)}",
                TablePartKind.style => styleName(t, p.style),
              };
    var key = drafting
        ? "new"
        : several
            ? "rows"
            : p.kind.name;
    var (quick, body) = drafting
        ? _newPanel(context)
        : several
            ? _rowsPanel(context)
            : switch (p.kind) {
                TablePartKind.table => _tablePanel(context),
                TablePartKind.header => _headerPanel(context),
                TablePartKind.column => _columnPanel(context, p.col),
                TablePartKind.row => _rowPanel(context, p.row),
                TablePartKind.cell => _cellPanel(context, p.row, p.col),
                TablePartKind.style => _stylePanel(context, p.style),
              };
    return StudioSide(
      header: StudioSideHeader(
        icon: p.kind == TablePartKind.style && !drafting
            ? Icons.auto_fix_high
            : Icons.table_chart_outlined,
        crumbs: crumbs,
        crumbKey: "tableDesignCrumb",
        title: title,
        titleKey: const ValueKey("tableDesignTitle"),
        onUp: p == TablePart.table && !drafting && !several ? null : _up,
      ),
      scrollKey: ValueKey("tableDesignPanel-$key"),
      quick: quick,
      body: body,
    );
  }

  /// _newPanel is the New style's first step: pointing, or the options.
  (List<Widget>, List<Widget>) _newPanel(BuildContext context) {
    var options = _options;
    return (
      const <Widget>[],
      [
        studioSection(
            remember: "table.new",
            icon: Icons.ads_click,
            title: options == null
                ? "Click what to style"
                : "What should it reach?",
            summary: options == null
                ? "A cell, a row tab or a column tab"
                : "Hover one to see it lit",
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    if (options == null)
                      const StudioNote(
                          "Click a cell, a row tab or a column tab on the table. "
                          "Shift-click row tabs for several rows.")
                    else ...[
                      if (options.isEmpty)
                        const StudioNote("Nothing to offer from that."),
                      for (var (i, o) in options.indexed)
                        StudioItem(
                            key: ValueKey("tableReach-$i"),
                            mark: const Icon(Icons.adjust, size: 14),
                            title: o.label,
                            lit: _optionHover == i,
                            onHover: (h) =>
                                setState(() => _optionHover = h ? i : null),
                            onTap: () => _make(o)),
                    ],
                    studioButtons([
                      if (options != null)
                        studioButton("Click something else",
                            key: const ValueKey("tableNewRepoint"),
                            onPressed: () => setState(() {
                                  _options = null;
                                  _pointing = true;
                                })),
                      studioButton("Cancel",
                          key: const ValueKey("tableNewCancel"),
                          onPressed: _cancelNew),
                    ]),
                  ],
                  help: options == null
                      ? null
                      : "“Wherever it is” follows that team as the numbers "
                          "move it; “whoever is there” stays on that place."),
            ]),
      ]
    );
  }

  /// _rowsPanel is several rows picked with shift.
  (List<Widget>, List<Widget>) _rowsPanel(BuildContext context) => (
        [
          StudioNote(
              "${[for (var r in _rows) _rowLabel(r)].join(", ")}. A style on "
              "them can keep to these places or go with who is in them."),
          const SizedBox(height: 8),
          studioButtons([
            studioButton("New style for these",
                key: const ValueKey("tableDesignStyleRows"),
                icon: Icons.add,
                primary: true,
                onPressed: () => _offer(
                    reachOptions(t, TablePart.row(_rows.last), rows: _rows))),
          ]),
        ],
        const <Widget>[]
      );

  /// _hint is what a group is for, behind its "?".
  Widget _hint(BuildContext context, String text) => CanvasHint(text);

  /// _note is words that must be seen: a state, a warning.
  Widget _note(String text, {Color? color}) => StudioNote(text, colour: color);

  /// _styleColours are the colours of the table's style, offered first.
  List<Color> get _styleColours {
    var s = dataStyleNamed(t.style);
    if (s == null) {
      return [
        for (var c in [
          t.cellFill,
          t.cellSpec.color,
          t.headerFill,
          t.headerSpec.color,
          t.gridColor
        ])
          if (c.a > 0) c
      ];
    }
    return [
      s.ground,
      s.ink,
      s.dim,
      s.accent,
      s.headFill,
      s.headInk,
      s.grid,
      ...s.palette.take(4)
    ];
  }

  Widget _swatches(
          String id, String label, Color value, ValueChanged<Color> set,
          {bool none = true}) =>
      StudioColourField(
          id: id,
          label: label,
          value: value,
          styleColours: _styleColours,
          palette: _palette,
          asMade: none,
          onPick: (c) => set(c.a == 0 ? _colour(null) : c));

  Widget _slider(String label, double value, double min, double max,
          double rest, void Function(double) live,
          {bool percent = false,
          int decimals = 0,
          double? step,
          String suffix = ""}) =>
      studioStepper(
          key: ValueKey("tableSlider-$label"),
          label: label,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          rest: rest,
          percent: percent,
          decimals: decimals,
          step: step,
          suffix: suffix,
          onChanged: live,
          onCommit: _end);

  /// _styleList is styles [indices], each a row: its name and reach, an eye
  /// to switch it off, a mark when it does nothing. Hovered, everything it
  /// reaches lights up on the table.
  List<Widget> _styleList(BuildContext context, List<int> indices) => [
        for (var i in indices)
          StudioItem(
            key: ValueKey("tableStyle-$i"),
            mark: studioDot(t.rules[i].style.background.a > 0
                ? t.rules[i].style.background
                : t.rules[i].style.textColor.a > 0
                    ? t.rules[i].style.textColor
                    : const Color(0xFF59606B)),
            title: styleName(t, i),
            subtitle: styleReach(t, t.rules[i]),
            off: t.rules[i].off,
            tag: styleIdle(t, t.rules[i]) != null ? "does nothing" : null,
            tagKey: ValueKey("tableStyleIdle-$i"),
            lit: _hoverStyle == i,
            onHover: (h) => setState(() => _hoverStyle = h ? i : null),
            onEye: () => _setRule(i, t.rules[i].copyWith(off: !t.rules[i].off)),
            eyeKey: ValueKey("tableStyleEye-$i"),
            onTap: () => _pick(TablePart.style(i)),
          ),
      ];

  /// _typeface is a dropdown of the faces for [spec].
  Widget _typeface(String id, TextSpec spec, ValueChanged<TextSpec> set) =>
      studioDrop<String>(
          key: ValueKey(id),
          label: "Typeface",
          value: spec.fontFamily,
          options: [
            if (!canvasFonts.contains(spec.fontFamily))
              (spec.fontFamily, spec.fontFamily),
            for (var f in canvasFonts) (f, f),
          ],
          onChanged: (f) => set(spec.copyWith(fontFamily: f)));

  (List<Widget>, List<Widget>) _tablePanel(BuildContext context) {
    var st = dataStyleNamed(t.style);
    var link = linkOf(t);
    var linked = link != null && c.sheetById(link.sheet) != null;
    var padSaid = t.evenPadding
        ? "padding ${t.cellPadding.round()}"
        : "padding each side";
    return (
      [
        studioRow([
          studioDrop<String>(
              key: const ValueKey("tableQuickStyle"),
              label: "Style",
              value: st?.name ?? "",
              options: [
                if (st == null) ("", "Its own"),
                for (var s in dataStyles) (s.name, s.name),
              ],
              onChanged: (name) {
                if (dataStyleNamed(name) case var s?) {
                  _set(tableInStyle(t, s));
                }
              }),
          studioButton("Canvas colours",
              key: const ValueKey("tableDesignMatchCanvas"),
              icon: Icons.format_paint_outlined,
              tooltip:
                  "Colours taken from the canvas's background and what is on it",
              onPressed: () {
            var d = c.document;
            _set(tableInColours(
                t,
                canvasColours(d.background.spec.background, [
                  for (var other in d.elements)
                    if (other.id != t.id) other
                ])));
          }),
        ], flex: [
          3,
          2
        ]),
        const SizedBox(height: 8),
        studioRow([
          _typeface("tableCellFont", t.cellSpec,
              (spec) => _set(t.copyWith(cellSpec: spec))),
          _slider(
              "Size",
              t.cellSpec.fontSize,
              6,
              72,
              20,
              (v) => _live(
                  t.copyWith(cellSpec: t.cellSpec.copyWith(fontSize: v)))),
          _swatches("tableCellInk", "Words", t.cellSpec.color,
              (v) => _set(t.copyWith(cellSpec: t.cellSpec.copyWith(color: v))),
              none: false),
        ], flex: [
          3,
          2,
          2
        ]),
      ],
      [
        studioSection(
            remember: "table.style",
            icon: Icons.palette_outlined,
            title: "Style",
            summary: st?.name ?? "Its own",
            children: [
              studioGroup(
                  "",
                  [
                    DataStylePicker(
                        key: const ValueKey("tableStyles"),
                        element: t,
                        onPick: (s) => _set(tableInStyle(t, s))),
                    if (st != null)
                      studioButton("The whole page in ${st.name}",
                          key: const ValueKey("tableStylePage"),
                          icon: Icons.auto_awesome,
                          tooltip: "Every chart, table and word on this page, "
                              "and its ground, as one step to undo",
                          onPressed: () => c.stylePage(st)),
                  ],
                  help: "Its colours, typefaces, rules and corners at once; "
                      "the cells and their styles stay."),
            ]),
        if (linked) _rowsShown(context, link),
        studioSection(
            remember: "table.styles",
            icon: Icons.auto_fix_high,
            title: "Styles on it",
            count: t.rules.length,
            summary: t.rules.isEmpty
                ? "None yet"
                : "${t.rules.where((r) => !r.off).length} on · hover one to see what it reaches",
            open: true,
            children: [
              for (var (name, indices) in styleGroups(t))
                studioGroup(
                    "$name · ${indices.length}", _styleList(context, indices)),
              studioGroup("", [
                if (t.rules.isEmpty)
                  const StudioNote(
                      "None yet. Click a column, row or cell and add one there."),
                studioChips([
                  (
                    "+ New style",
                    const ValueKey("tableDesignNewStyle"),
                    () => setState(() {
                          _pointing = true;
                          _options = null;
                        })
                  ),
                ]),
              ]),
            ]),
        // The cells' face, size and colour are in the strip at the top;
        // the header row's here, beside them.
        studioSection(
            remember: "table.words",
            icon: Icons.title,
            title: "Header words",
            summary: [
              t.headerSpec.fontFamily,
              "${t.headerSpec.fontSize.round()}px",
              switch (t.headerSpec.weight) {
                300 => "light",
                700 => "bold",
                _ => "regular",
              },
            ].join(" · "),
            children: [
              studioGroup("", [
                studioRow([
                  _typeface("tableHeaderFont", t.headerSpec,
                      (spec) => _set(t.copyWith(headerSpec: spec))),
                  _slider(
                      "Header size",
                      t.headerSpec.fontSize,
                      6,
                      72,
                      20,
                      (v) => _live(t.copyWith(
                          headerSpec: t.headerSpec.copyWith(fontSize: v)))),
                ], flex: [
                  3,
                  2
                ]),
                studioRow([
                  studioSeg<int>(
                      id: "tableHeaderWeight",
                      label: "Weight",
                      value: t.headerSpec.weight,
                      options: const [
                        (300, "Light"),
                        (400, "Regular"),
                        (700, "Bold")
                      ],
                      onChanged: (v) => _set(t.copyWith(
                          headerSpec: t.headerSpec.copyWith(weight: v)))),
                  _swatches(
                      "tableHeaderInk",
                      "Colour",
                      t.headerSpec.color,
                      (v) => _set(t.copyWith(
                          headerSpec: t.headerSpec.copyWith(color: v))),
                      none: false),
                ], flex: [
                  3,
                  2
                ]),
                studioButton("All of the header row",
                    key: const ValueKey("tableToHeader"),
                    icon: Icons.chevron_right,
                    onPressed: () => _pick(TablePart.header)),
              ]),
            ]),
        studioSection(
            remember: "table.cells",
            icon: Icons.grid_on,
            title: "Cells",
            summary: [
              t.cellFill.a > 0 ? "Filled" : "No fill",
              t.zebra ? "striped" : "plain",
              padSaid,
            ].join(" · "),
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableCellFill", "Fill", t.cellFill,
                      (v) => _set(t.copyWith(cellFill: v))),
                  if (t.zebra)
                    _swatches(
                        "tableZebraFill",
                        "Stripe",
                        t.zebraFill,
                        (v) => _set(
                            t.copyWith(zebraFill: v.withValues(alpha: 0.1))))
                  else
                    const SizedBox.shrink(),
                ]),
                StudioSwitchRow(
                    key: const ValueKey("tableZebra"),
                    label: "Stripes",
                    note: "every other row",
                    value: t.zebra,
                    onChanged: (v) => _set(t.copyWith(zebra: v))),
              ]),
              studioGroup("Padding", [
                // One figure until somebody wants four: a title row often
                // wants more above and below.
                studioSeg<bool>(
                    id: "tablePadSides",
                    value: t.evenPadding,
                    options: const [
                      (true, "All the same"),
                      (false, "Each side")
                    ],
                    onChanged: (even) => _set(even
                        ? t.copyWith(evenPadding: true)
                        : t.copyWith(
                            padTop: t.topPad,
                            padRight: t.rightPad,
                            padBottom: t.bottomPad,
                            padLeft: t.leftPad))),
                if (t.evenPadding)
                  studioRow([
                    _slider("Padding", t.cellPadding, 0, 40, 10,
                        (v) => _live(t.copyWith(cellPadding: v))),
                    _slider("Pictures", t.pictureScale, 0.2, 1.5, 1,
                        (v) => _live(t.copyWith(pictureScale: v)),
                        percent: true, step: 0.05),
                  ])
                else ...[
                  studioRow([
                    _slider("Top", t.topPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padTop: v))),
                    _slider("Bottom", t.bottomPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padBottom: v))),
                  ]),
                  studioRow([
                    _slider("Left", t.leftPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padLeft: v))),
                    _slider("Right", t.rightPad, 0, 40, t.cellPadding,
                        (v) => _live(t.copyWith(padRight: v))),
                  ]),
                  studioRow([
                    _slider("Pictures", t.pictureScale, 0.2, 1.5, 1,
                        (v) => _live(t.copyWith(pictureScale: v)),
                        percent: true, step: 0.05),
                    const SizedBox.shrink(),
                  ]),
                ],
              ]),
            ]),
        studioSection(
            remember: "table.lines",
            icon: Icons.border_all,
            title: "Lines and corners",
            summary: [
              t.grid == TableGrid.none
                  ? "No lines"
                  : "${t.grid.label} · ${t.gridWidth.toStringAsFixed(t.gridWidth % 1 == 0 ? 0 : 1)}px",
              "corners ${t.cornerRadius.round()}",
            ].join(" · "),
            children: [
              studioGroup("", [
                studioSeg<TableGrid>(
                    id: "tableGrid",
                    label: "Lines",
                    value: t.grid,
                    options: [
                      for (var g in TableGrid.values)
                        (g, g.label.replaceAll(" only", ""))
                    ],
                    onChanged: (v) => _set(t.copyWith(grid: v))),
                if (t.grid != TableGrid.none)
                  studioRow([
                    _swatches("tableGridColour", "Colour", t.gridColor,
                        (v) => _set(t.copyWith(gridColor: v)),
                        none: false),
                    _slider("Thickness", t.gridWidth, 0, 6, 1,
                        (v) => _live(t.copyWith(gridWidth: v)),
                        decimals: 1, step: 0.5),
                  ]),
                studioRow([
                  _slider("Corners", t.cornerRadius, 0, 40, 6,
                      (v) => _live(t.copyWith(cornerRadius: v))),
                  const SizedBox.shrink(),
                ]),
                StudioSwitchRow(
                    key: const ValueKey("tableOutline"),
                    label: "Outline round it",
                    value: t.showOutline,
                    onChanged: (v) => _set(t.copyWith(showOutline: v))),
              ]),
            ]),
        studioSection(
            remember: "table.layout",
            icon: Icons.view_quilt_outlined,
            title: "Layout",
            summary: [
              t.headerRow ? "Header row" : "No header row",
              if (t.headerColumn) "header column",
              switch (_columnSizing) {
                "fit" => "fit to contents",
                "even" => "even columns",
                _ => "columns as dragged",
              },
              if (t.cards) "cards apart",
            ].join(" · "),
            children: [
              studioGroup("", [
                StudioSwitchRow(
                    key: const ValueKey("tableHeaderRow"),
                    label: "Header row",
                    value: t.headerRow,
                    onChanged: (v) => _set(t.copyWith(headerRow: v))),
                StudioSwitchRow(
                    key: const ValueKey("tableHeaderColumn"),
                    label: "Header column",
                    note: "the first",
                    value: t.headerColumn,
                    onChanged: (v) => _set(t.copyWith(headerColumn: v))),
                studioSeg<String>(
                    id: "tableColumns",
                    label: "Column widths",
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
                              : List.filled(t.columnCount,
                                  1 / math.max(1, t.columnCount))));
                    }),
                studioSeg<bool>(
                    id: "tableGroupRows",
                    label: "Rows with only a first cell",
                    value: t.groupRows,
                    options: const [
                      (false, "Like the rest"),
                      (true, "Headings across")
                    ],
                    onChanged: (v) => _set(t.copyWith(groupRows: v))),
                studioSeg<bool>(
                    id: "tableCards",
                    label: "Columns after the first",
                    value: t.cards,
                    options: const [
                      (false, "One table"),
                      (true, "Cards apart")
                    ],
                    onChanged: (v) => _set(t.copyWith(cards: v))),
                if (t.cards && t.columnCount > 1)
                  studioRow([
                    studioDrop<int>(
                        key: const ValueKey("tablePicked"),
                        label: "Raised card",
                        value: t.picked > 0 && t.picked < t.columnCount
                            ? t.picked
                            : -1,
                        options: [
                          (-1, "None"),
                          for (var col = 1; col < t.columnCount; col++)
                            (
                              col,
                              t.cell(0, col).trim().isEmpty
                                  ? "Column ${col + 1}"
                                  : t.cell(0, col).trim()
                            ),
                        ],
                        onChanged: (v) => _set(t.copyWith(picked: v))),
                    if (t.picked > 0)
                      studioText(
                          key: const ValueKey("tableRibbon"),
                          label: "Its ribbon",
                          value: t.ribbon,
                          hint: "Most popular",
                          onChanged: (v) => _live(t.copyWith(ribbon: v)))
                    else
                      const SizedBox.shrink(),
                  ]),
              ]),
            ]),
        studioSection(
            remember: "table.motion",
            icon: Icons.animation,
            title: "Motion",
            summary: t.turn.label,
            children: [
              studioGroup(
                  "",
                  [
                    studioSeg<String>(
                        id: "tableTurn",
                        label: "Arrives",
                        value: t.turn.name,
                        options: [
                          for (var v in TableTurn.values) (v.name, v.label)
                        ],
                        onChanged: (v) =>
                            _set(t.copyWith(turn: TableTurn.fromName(v)))),
                  ],
                  help: "Whole, or a row or a column at a time, as it "
                      "arrives on the canvas."),
            ]),
      ]
    );
  }

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

  /// _rowsShown is which of its sheet's rows the table shows, and in what
  /// order: its own, the sheet left as it is (moved here from the Sheet
  /// tab's side panel, Ken 2026-11-16).
  Widget _rowsShown(BuildContext context, SheetLink link) {
    var sheet = c.sheetById(link.sheet)!;
    void set(SheetLink next) => _set(withLink(t, next) as TableElement);
    var columns = [
      for (var col = 0; col < link.range.cols; col++)
        (col, sheetColumnName(sheet, link, col)),
    ];
    String name(int col) =>
        columns.firstWhere((x) => x.$1 == col, orElse: () => (col, "?")).$2;
    var sorted = link.sortBy >= 0;
    return studioSection(
        remember: "table.rows",
        icon: Icons.format_list_numbered,
        title: "Rows",
        summary: [
          link.top <= 0
              ? "Every row"
              : "${sorted ? "Top" : "First"} ${link.top}",
          sorted
              ? "by ${name(link.sortBy)}, ${link.descending ? "largest" : "smallest"} first"
              : "the sheet's order",
          if (link.whereColumn >= 0 && link.where.trim().isNotEmpty)
            "${name(link.whereColumn)} ${link.where.trim()}",
        ].join(" · "),
        children: [
          studioGroup(
              "",
              [
                studioRow([
                  studioSeg<int>(
                      id: "tableRowsTop",
                      label: "Show",
                      value: link.top > 0 ? (link.top) : 0,
                      options: [
                        (0, "Every row"),
                        (link.top > 0 ? link.top : 5, sorted ? "Top" : "First"),
                      ],
                      onChanged: (n) => set(link.copyWith(top: n))),
                  if (link.top > 0)
                    studioStepper(
                        key: const ValueKey("tableRowsHowMany"),
                        label: "How many",
                        value: link.top.toDouble(),
                        min: 1,
                        max: 100,
                        onChanged: (v) => set(link.copyWith(top: v.round())))
                  else
                    const SizedBox.shrink(),
                ], flex: [
                  3,
                  2
                ]),
              ],
              help: "Which of the sheet's rows this table shows, and in what "
                  "order. The sheet isn't changed: a table can show every "
                  "club while a chart of the same sheet shows the top five."),
          studioGroup("In order of", [
            studioRow([
              studioDrop<int>(
                  key: const ValueKey("tableRowsSort"),
                  value: link.sortBy.clamp(-1, link.range.cols - 1),
                  options: [(-1, "The sheet's own order"), ...columns],
                  onChanged: (v) => set(link.copyWith(sortBy: v))),
              if (sorted)
                studioSeg<bool>(
                    id: "tableRowsOrder",
                    value: link.descending,
                    options: const [(true, "Largest"), (false, "Smallest")],
                    onChanged: (v) => set(link.copyWith(descending: v)))
              else
                const SizedBox.shrink(),
            ]),
            // A league's positions stay 1, 2, 3 while the clubs move.
            if (sorted)
              studioSeg<bool>(
                  id: "tableRowsNumbering",
                  label: "First column",
                  value: link.numbering,
                  options: const [
                    (true, "Keeps its place"),
                    (false, "Moves with its row")
                  ],
                  onChanged: (v) => set(link.copyWith(numbering: v))),
          ]),
          studioGroup("Only where", [
            studioRow([
              studioDrop<int>(
                  key: const ValueKey("tableRowsWhere"),
                  value: link.whereColumn.clamp(-1, link.range.cols - 1),
                  options: [(-1, "Every row"), ...columns],
                  onChanged: (v) => set(link.copyWith(whereColumn: v))),
              if (link.whereColumn >= 0)
                studioText(
                    key: const ValueKey("tableRowsIs"),
                    value: link.where,
                    hint: "is: >5, Arsenal, <>0",
                    onChanged: (v) => _live(
                        withLink(t, link.copyWith(where: v)) as TableElement))
              else
                const SizedBox.shrink(),
            ]),
          ]),
        ]);
  }

  (List<Widget>, List<Widget>) _headerPanel(BuildContext context) => (
        [
          studioRow([
            _typeface("tableHeaderFont", t.headerSpec,
                (spec) => _set(t.copyWith(headerSpec: spec))),
            _slider(
                "Size",
                t.headerSpec.fontSize,
                6,
                72,
                20,
                (v) => _live(t.copyWith(
                    headerSpec: t.headerSpec.copyWith(fontSize: v)))),
          ], flex: [
            3,
            2
          ]),
          const SizedBox(height: 8),
          studioRow([
            studioSeg<int>(
                id: "tableHeaderWeight",
                label: "Weight",
                value: t.headerSpec.weight,
                options: const [
                  (300, "Light"),
                  (400, "Regular"),
                  (700, "Bold")
                ],
                onChanged: (v) => _set(
                    t.copyWith(headerSpec: t.headerSpec.copyWith(weight: v)))),
            _swatches(
                "tableHeaderInk",
                "Words",
                t.headerSpec.color,
                (v) => _set(
                    t.copyWith(headerSpec: t.headerSpec.copyWith(color: v))),
                none: false),
          ], flex: [
            3,
            2
          ]),
        ],
        [
          studioSection(
              remember: "table.headerLook",
              icon: Icons.format_color_fill,
              title: "Its look",
              summary: [
                t.headerFill.a > 0 ? "Filled" : "No fill",
                "${t.headerHeightRatio.toStringAsFixed(2)}× a row",
              ].join(" · "),
              open: true,
              children: [
                studioGroup(
                    "",
                    [
                      studioRow([
                        _swatches("tableHeaderFill", "Fill", t.headerFill,
                            (v) => _set(t.copyWith(headerFill: v))),
                        _slider("Height", t.headerHeightRatio, 0.5, 3, 1.15,
                            (v) => _live(t.copyWith(headerHeightRatio: v)),
                            decimals: 2, step: 0.05, suffix: "×"),
                      ]),
                    ],
                    help: "Its height against a row's."),
              ]),
          studioSection(
              remember: "table.headerStyles",
              icon: Icons.auto_fix_high,
              title: "Styles on it",
              count: stylesOnRow(t, 0).length,
              summary: stylesOnRow(t, 0).isEmpty ? "None" : "",
              children: [
                studioGroup("", [
                  if (stylesOnRow(t, 0).isEmpty) const StudioNote("None."),
                  ..._styleList(context, stylesOnRow(t, 0)),
                ]),
              ]),
        ]
      );

  (List<Widget>, List<Widget>) _columnPanel(BuildContext context, int col) {
    var g = _Geom.of(t, 1000);
    var widths = g.w;
    var stylesHere = stylesOnColumn(t, col);
    var kind = t.columnKinds[col] ?? "";
    return (
      [
        studioRow([
          _slider("Width", widths[col], 10, math.max(60, t.width * 0.7),
              widths[col], (v) {
            var next = [...widths];
            next[col] = v;
            _live(t.copyWith(columnWidths: next));
          }),
          // Drawn rather than written (TableElement.columnKinds).
          studioDrop<String>(
              key: const ValueKey("tableColumnKind"),
              label: "Its cells show",
              value: kind,
              options: [for (var (k, says) in tableCellKinds) (k, says)],
              onChanged: (k) => _set(t.copyWith(columnKinds: {
                    for (var MapEntry(:key, :value) in t.columnKinds.entries)
                      if (key != col) key: value,
                    if (k.isNotEmpty) col: k,
                  }))),
        ], flex: [
          2,
          3
        ]),
        const SizedBox(height: 6),
        _note(switch (kind) {
          "spark" =>
            "Each cell's numbers, like “3, 5, 4, 8”, as a small line ending on a dot.",
          "ticks" =>
            "Yes, true or 1 a tick; no, false or 0 a cross; blank a dash.",
          "harvey" =>
            "0 to 4, a share up to 1, or a percentage, as a part-filled circle.",
          "change" => "Up green with ▲, down red with ▼, by the size of it.",
          "merge" =>
            "The same value in the rows below runs on as one tall cell.",
          "heat" =>
            "Shaded by its size among the column's numbers, the number written over it.",
          _ => "Written as typed. The other columns make room for its width.",
        }),
      ],
      [
        studioSection(
            remember: "table.columnStyles",
            icon: Icons.auto_fix_high,
            title: "Styles on this column",
            count: stylesHere.length,
            summary: stylesHere.isEmpty
                ? "None"
                : [for (var i in stylesHere) styleName(t, i)].join(", "),
            open: true,
            children: [
              studioGroup("", [
                ..._styleList(context, stylesHere),
                studioChips([
                  (
                    "+ New style from this",
                    const ValueKey("tableDesignStyleColumn"),
                    () => _offer(reachOptions(t, TablePart.column(col)))
                  ),
                ]),
              ]),
            ]),
        ..._wordsGuide(context, col),
      ]
    );
  }

  /// _wordsGuide gathers the styles about words in one column -- the Form
  /// column's W, D and L boxes (prototype v2's Form guide) -- so their
  /// boxes are set side by side, a line a word, and their size and corners
  /// together.
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
      studioSection(
          remember: "table.words",
          icon: Icons.text_fields,
          title: "Its words",
          count: words.length,
          summary: [for (var i in words) t.rules[i].match].join(" · "),
          open: true,
          children: [
            for (var i in words)
              studioGroup("“${t.rules[i].match}”", [
                studioRow([
                  _swatches(
                      "tableWordBox-$i",
                      "Box",
                      t.rules[i].style.background,
                      (v) => _setRule(
                          i,
                          t.rules[i].copyWith(
                              style:
                                  t.rules[i].style.copyWith(background: v)))),
                  _swatches(
                      "tableWordInk-$i",
                      "Words",
                      t.rules[i].style.textColor,
                      (v) => _setRule(
                          i,
                          t.rules[i].copyWith(
                              style: t.rules[i].style.copyWith(textColor: v)))),
                ]),
              ]),
            if (boxed.isNotEmpty)
              studioGroup("Every box", [
                studioRow([
                  _slider("Box size", size, 0, 60, 0,
                      (v) => all((s) => s.copyWith(minWidth: v, minHeight: v))),
                  _slider("Box corners", corners, 0, 20, 4,
                      (v) => all((s) => s.copyWith(radius: v))),
                ]),
              ]),
          ]),
    ];
  }

  (List<Widget>, List<Widget>) _rowPanel(BuildContext context, int row) {
    var stylesHere = stylesOnRow(t, row);
    return (
      const <Widget>[],
      [
        studioSection(
            remember: "table.rowStyles",
            icon: Icons.auto_fix_high,
            title: "Styles on this row",
            count: stylesHere.length,
            summary: "Shift-click other row tabs to style several",
            open: true,
            children: [
              studioGroup("", [
                ..._styleList(context, stylesHere),
                studioChips([
                  (
                    "+ New style from this",
                    const ValueKey("tableDesignStyleRow"),
                    () => _offer(reachOptions(t, TablePart.row(row)))
                  ),
                ]),
              ]),
            ]),
      ]
    );
  }

  (List<Widget>, List<Widget>) _cellPanel(
      BuildContext context, int row, int col) {
    var on = stylesAt(t, row, col);
    return (
      [
        studioButtons([
          studioButton("New style from this",
              key: const ValueKey("tableDesignStyleCell"),
              icon: Icons.add,
              onPressed: () =>
                  _offer(reachOptions(t, TablePart.cell(row, col)))),
          studioButton("Copy its look",
              key: const ValueKey("tableCellCopy"),
              icon: Icons.content_copy,
              onPressed: () => setState(() => _copied =
                  t.lookAt(row, col).style ?? const TableCellStyle())),
          if (t.lookAt(row, col).style != null)
            studioButton("Make a style from its look",
                key: const ValueKey("tableCellMake"), onPressed: () {
              var o = reachOptions(t, TablePart.cell(row, col)).firstOrNull;
              if (o == null) return;
              _newStyle(o.rule.copyWith(style: t.lookAt(row, col).style));
            }),
          studioButton("Its column",
              key: const ValueKey("tableCellColumn"),
              onPressed: () => _pick(TablePart.column(col))),
          studioButton(row == 0 && t.headerRow ? "The header" : "Its row",
              key: const ValueKey("tableCellRow"),
              onPressed: () => _pick(row == 0 && t.headerRow
                  ? TablePart.header
                  : TablePart.row(row))),
        ]),
      ],
      [
        studioSection(
            remember: "table.cellStyles",
            icon: Icons.auto_fix_high,
            title: "Styles reaching it",
            count: on.length,
            summary: on.isEmpty
                ? "None: it has the table's look"
                : "In the order they apply",
            open: true,
            children: [
              studioGroup(
                  "",
                  [
                    if (on.isEmpty)
                      const StudioNote(
                          "No styles reach it: it has the table's look."),
                    ..._styleList(context, on),
                  ],
                  help: on.isEmpty
                      ? null
                      : "In the order they apply: where two say different "
                          "things, the lower one wins."),
            ]),
      ]
    );
  }

  (List<Widget>, List<Widget>) _stylePanel(BuildContext context, int i) {
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
    var lookSaid = [
      if (s.background.a > 0) "filled",
      if (s.textColor.a > 0) "coloured words",
      if (s.weight == 700) "bold",
      if (s.weight == 300) "light",
      if ((s.fontScale - 1).abs() > 0.01) "${(s.fontScale * 100).round()}%",
      if (s.align != null) "lined up ${s.align!.name}",
    ];
    var fineSaid = [
      if (s.letterWidth > 0) "letters ${s.letterWidth.round()}",
      if (s.minWidth > 0 || s.minHeight > 0) "least size",
      if (s.nudgeX != 0 || s.nudgeY != 0) "nudged",
      if (s.redact) "words hidden",
    ];
    return (
      [
        if (_made) ...[
          _note(
              "Step 2 of 2: its look. It names itself from what it reaches "
              "and looks like, until you type a name.",
              color: ThemeNotifier.of(context).colors.primary),
          const SizedBox(height: 6),
          studioButtons([
            studioButton("Done",
                key: const ValueKey("tableNewDone"),
                primary: true,
                onPressed: () => _pick(TablePart.table)),
          ]),
          const SizedBox(height: 8),
        ],
        if (idle != null) ...[
          _note("Does nothing: $idle.", color: const Color(0xFFF2B33D)),
          const SizedBox(height: 6),
        ],
        studioRow([
          studioText(
            key: ValueKey("tableStyleName-$i"),
            label: "Name",
            value: rule.name,
            hint: styleName(t.copyWith(rules: [rule.copyWith(name: "")]), 0),
            onChanged: (v) => _setRule(i, rule.copyWith(name: v), live: true),
          ),
        ]),
        const SizedBox(height: 8),
        studioButtons([
          studioButton(rule.off ? "Switch on" : "Switch off",
              key: const ValueKey("tableStyleOff"),
              icon: rule.off
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              onPressed: () => _setRule(i, rule.copyWith(off: !rule.off))),
          studioButton("Copy look",
              key: const ValueKey("tableStyleCopy"),
              onPressed: () => setState(() => _copied = s)),
          studioButton("Paste look",
              key: const ValueKey("tableStylePaste"),
              onPressed: _copied == null ? null : () => look(_copied!)),
          studioButton("Duplicate", key: const ValueKey("tableStyleDuplicate"),
              onPressed: () {
            var rules = [...t.rules]..insert(
                i + 1,
                rule.copyWith(
                    name: rule.name.isEmpty ? "" : "${rule.name} (copy)"));
            _set(t.copyWith(rules: rules));
            _pick(TablePart.style(i + 1));
          }),
          studioButton("Earlier",
              key: const ValueKey("tableStyleEarlier"),
              icon: Icons.arrow_upward,
              tooltip: "Applied before the one above it",
              onPressed: i == 0 ? null : () => _move(i, -1)),
          studioButton("Later",
              key: const ValueKey("tableStyleLater"),
              icon: Icons.arrow_downward,
              tooltip: "Applied after the one below it, so it wins",
              onPressed: i == t.rules.length - 1 ? null : () => _move(i, 1)),
          studioButton("Delete",
              key: const ValueKey("tableStyleDelete"),
              icon: Icons.delete_outline, onPressed: () {
            _set(t.copyWith(rules: [...t.rules]..removeAt(i)));
            _pick(TablePart.table);
          }),
        ]),
      ],
      [
        studioSection(
            remember: "table.styleReach",
            icon: Icons.place_outlined,
            title: "What it reaches",
            summary: styleReach(t, rule),
            open: true,
            children: [
              studioGroup("", [
                studioDrop<String>(
                  key: ValueKey("tableStyleColumn-$i"),
                  label: "Column",
                  value: colValue,
                  options: columns,
                  onChanged: (v) => _setRule(i, rule.copyWith(column: v)),
                ),
                if (rule.keys.isNotEmpty) ...[
                  studioText(
                    key: ValueKey("tableStyleKeys-$i"),
                    label: "Follows",
                    value: rule.keys.join(", "),
                    hint: "Names, with commas between",
                    onChanged: (v) => _setRule(
                        i,
                        rule.copyWith(keys: [
                          for (var k in v.split(","))
                            if (k.trim().isNotEmpty) k.trim()
                        ]),
                        live: true),
                  ),
                  _note("Found in the ${rule.keyColumn} column, wherever "
                      "they are as the numbers change."),
                  studioButtons([
                    studioButton("Keep to their places now",
                        key: const ValueKey("tableStyleKeep"),
                        onPressed: () => _setRule(i, _kept(rule))),
                  ]),
                ] else
                  studioDrop<String>(
                      key: const ValueKey("tableStyleRows"),
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
                              rows: v == "some"
                                  ? (t.headerRow ? "2" : "1")
                                  : v))),
                if (rowsKind == "some") ...[
                  studioText(
                    key: ValueKey("tableStyleRowsText-$i"),
                    label: "Which rows",
                    value: rule.rows,
                    hint: "5, or 18:20, or >1",
                    onChanged: (v) =>
                        _setRule(i, rule.copyWith(rows: v), live: true),
                  ),
                  _note(
                      "${spanWords(rule.rows, "row", header: t.headerRow)}. Counting the header as 1: “18:20” is three rows, “>1” every row after the first."),
                ],
                if (rule.keys.isEmpty &&
                    rowsKind == "some" &&
                    keyColumnOf(t) >= 0 &&
                    _followable(rule))
                  studioButtons([
                    studioButton("Follow who is there now",
                        key: const ValueKey("tableStyleFollow"),
                        onPressed: () => _setRule(i, _followed(rule))),
                  ]),
              ]),
              ..._whenPart(context, i, rule),
              studioGroup("Only where it says", [
                studioText(
                  key: ValueKey("tableStyleMatch-$i"),
                  value: rule.match,
                  hint: "Words to look for (empty: every cell)",
                  onChanged: (v) =>
                      _setRule(i, rule.copyWith(match: v), live: true),
                ),
                if (rule.match.isNotEmpty)
                  studioSeg<TableMatch>(
                      id: "tableStyleHow",
                      label: "Found as",
                      value: rule.how,
                      options: [for (var m in TableMatch.values) (m, m.label)],
                      onChanged: (v) => _setRule(i, rule.copyWith(how: v))),
              ]),
            ]),
        studioSection(
            remember: "table.styleLook",
            icon: Icons.palette_outlined,
            title: "Its look",
            summary: lookSaid.isEmpty ? "As the table" : lookSaid.join(" · "),
            open: true,
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableStyleFill", "Fill", s.background,
                      (v) => look(s.copyWith(background: v))),
                  _swatches("tableStyleInk", "Words", s.textColor,
                      (v) => look(s.copyWith(textColor: v))),
                ]),
                studioRow([
                  _slider("Size", s.fontScale, 0.4, 2.5, 1,
                      (v) => look(s.copyWith(fontScale: v), live: true),
                      percent: true, step: 0.1),
                  const SizedBox.shrink(),
                ]),
                studioSeg<int>(
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
                studioSeg<String>(
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
                        ? TableCellStyle.fromJson(
                            {...s.toJson()}..remove("align"))
                        : s.copyWith(align: TextAlignSpec.values.byName(v)))),
                if (rule.match.isNotEmpty || s.background.a > 0)
                  studioSeg<bool>(
                      id: "tableStyleHug",
                      label: "Box",
                      value: s.hug,
                      options: const [
                        (true, "Round the words"),
                        (false, "Fills the cell")
                      ],
                      onChanged: (v) => look(s.copyWith(hug: v))),
                if (s.background.a > 0)
                  studioRow([
                    _slider("Corners", s.radius, 0, 24, 4,
                        (v) => look(s.copyWith(radius: v), live: true)),
                    _slider("Inset", s.inset, 0, 24, 6,
                        (v) => look(s.copyWith(inset: v), live: true)),
                  ]),
              ]),
            ]),
        studioSection(
            remember: "table.styleLines",
            icon: Icons.border_style,
            title: "Lines",
            summary: s.borderColor.a > 0
                ? "${s.borderWidth.round()}px · $sidesKey"
                : "None",
            children: [
              studioGroup("", [
                studioRow([
                  _swatches("tableStyleLine", "Colour", s.borderColor, (v) {
                    look(s.copyWith(
                        borderColor: v,
                        borderWidth:
                            v.a > 0 && s.borderWidth == 0 ? 2 : s.borderWidth));
                  }),
                  if (s.borderColor.a > 0)
                    _slider("Thickness", s.borderWidth, 0, 8, 0,
                        (v) => look(s.copyWith(borderWidth: v), live: true))
                  else
                    const SizedBox.shrink(),
                ]),
                if (s.borderColor.a > 0)
                  studioDrop<String>(
                      key: const ValueKey("tableStyleSides"),
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
              ]),
            ]),
        studioSection(
            remember: "table.styleFine",
            icon: Icons.straighten,
            title: "Fine placement",
            summary: fineSaid.isEmpty ? "As made" : fineSaid.join(" · "),
            children: [
              studioGroup(
                  "",
                  [
                    studioRow([
                      _slider("Letter width", s.letterWidth, 0, 40, 0,
                          (v) => look(s.copyWith(letterWidth: v), live: true)),
                      _slider(
                          "Letter gap",
                          s.letterSpacing,
                          -5,
                          20,
                          0,
                          (v) =>
                              look(s.copyWith(letterSpacing: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Margin", s.textPad, 0, 30, 0,
                          (v) => look(s.copyWith(textPad: v), live: true)),
                      _slider("Least width", s.minWidth, 0, 80, 0,
                          (v) => look(s.copyWith(minWidth: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Least height", s.minHeight, 0, 80, 0,
                          (v) => look(s.copyWith(minHeight: v), live: true)),
                      _slider("Nudge across", s.nudgeX, -10, 10, 0,
                          (v) => look(s.copyWith(nudgeX: v), live: true)),
                    ]),
                    studioRow([
                      _slider("Nudge down", s.nudgeY, -10, 10, 0,
                          (v) => look(s.copyWith(nudgeY: v), live: true)),
                      studioSeg<bool>(
                          id: "tableStyleRedact",
                          label: "Words",
                          value: s.redact,
                          options: const [(false, "Shown"), (true, "Hidden")],
                          onChanged: (v) => look(s.copyWith(redact: v))),
                    ]),
                  ],
                  help: "For boxes round single letters, so a row of them "
                      "lines up: a fixed width per letter, the gap, a least "
                      "size, and nudges for a letter whose ink sits "
                      "off-centre."),
            ]),
      ]
    );
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
        studioGroup("", [
          studioChips([
            (
              "+ Only where a number is…",
              const ValueKey("tableStyleWhenAdd"),
              () => _setRule(
                  i, rule.copyWith(when: TableWhen(numeric.last, ">=", 0)))
            ),
          ]),
        ]),
      ];
    }
    return [
      studioGroup("Only where a number is", [
        studioRow([
          studioDrop<String>(
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
          studioText(
            key: ValueKey("tableStyleWhenValue-$i"),
            value: w.value == w.value.roundToDouble()
                ? "${w.value.round()}"
                : "${w.value}",
            hint: "A number",
            onChanged: (v) {
              var n = double.tryParse(v.trim());
              if (n != null) {
                _setRule(i, rule.copyWith(when: w.copyWith(value: n)),
                    live: true);
              }
            },
          ),
        ]),
        studioSeg<String>(
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
        _note("Changes as the numbers do: ${whenWords(w)}."),
        studioButtons([
          studioButton("No number condition",
              key: const ValueKey("tableStyleWhenRemove"),
              onPressed: () => _setRule(i, rule.copyWith(noWhen: true))),
        ]),
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

/// _DesignThumb draws a table fitted on [ground], for the gallery.
class _DesignThumb extends CustomPainter {
  final TableElement t;
  final Color ground;
  final CanvasImageStore images;
  _DesignThumb(this.t, this.ground, this.images) : super(repaint: images);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var w = math.max(1.0, t.width), h = math.max(1.0, t.height);
    var k = math.min((size.width - 10) / w, (size.height - 10) / h);
    canvas.save();
    canvas.translate((size.width - w * k) / 2, (size.height - h * k) / 2);
    canvas.scale(k);
    paintTable(canvas, Rect.fromLTWH(0, 0, w, h), t, images: images);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DesignThumb old) =>
      !identical(old.t, t) || old.ground != ground;
}

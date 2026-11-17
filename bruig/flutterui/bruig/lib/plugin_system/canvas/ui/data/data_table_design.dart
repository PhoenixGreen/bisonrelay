import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/ui/data/vector_saving.dart';
import 'package:bruig/plugin_system/canvas/export/vector_export.dart';
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
import 'package:bruig/plugin_system/canvas/ui/data/data_studio_side.dart';
import 'package:bruig/plugin_system/canvas/ui/data/data_style_picker.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/data_source_settings.dart'
    show sheetColumnName;
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'table_gallery.dart';
part 'table_stage.dart';
part 'table_panel.dart';
part 'table_whole_panel.dart';
part 'table_part_panels.dart';
part 'table_style_panel.dart';

// data_table_design.dart is the Data Studio's Table tab: the table drawn
// large, as the canvas draws it, with a tab over each column and beside
// each row (lettered and numbered as its sheet is). Clicking a cell, a tab
// or round the table picks what the right-hand panel is about. A style (one
// of the table's rules) lights everything it reaches when hovered. Every
// change goes through the controller as one undo step.

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
  // The parts are extensions, and call setState: overridden so the call
  // is this class's own, not State's protected one.
  @override
  void setState(VoidCallback fn) => super.setState(fn);

  CanvasController get c => widget.controller;
  TableElement get t => widget.table;
  TablePart _picked = TablePart.table;
  TablePart? _hover;
  int? _hoverStyle;

  // The gallery: open, the kind opened, the design picked, the filter.
  bool _gallery = false;
  String? _galleryKind;
  int? _galleryPreset;
  ChartUse? _galleryUse;

  // Making a style: pointing ("click what to style"), then options it
  // could reach, lit when hovered, then its look.
  bool _pointing = false;
  List<ReachOption>? _options;
  int? _optionHover;
  bool _made = false;

  /// _rows is rows picked with shift on their tabs, for a style on several.
  List<int> _rows = const [];

  /// _copied is a look copied from a style or a cell, to paste on another.
  TableCellStyle? _copied;

  /// _dragging is the column whose edge is dragged, and its start widths.
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

  // Writing: one change is one undo step; a drag is one too.

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

  /// _make makes the chosen option's style with a visible look, opened.
  void _make(ReachOption o) {
    _newStyle(o.rule.copyWith(style: lookFor(o.rule)));
    setState(() => _made = true);
  }

  void _cancelNew() => setState(() {
        _pointing = false;
        _options = null;
        _optionHover = null;
      });

  /// _up is Esc: up to the table.
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

  // Names for the parts, as the sheet names them when there is one.

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
  /// designs. The way to what is picked is in the sidebar's header.
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

  // ---- table_gallery.dart -------------------------------------------------

  // The gallery of designs.

  // ---- table_stage.dart ---------------------------------------------------

  // The stage.

  // ---- table_panel.dart ---------------------------------------------------

  // The panel: the Studio's sidebar (data_studio_side.dart).

  // ---- table_style_panel.dart ---------------------------------------------
}

/// _Geom is where the table (scaled to the stage, at most 125%) and its
/// tabs are on the stage.
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

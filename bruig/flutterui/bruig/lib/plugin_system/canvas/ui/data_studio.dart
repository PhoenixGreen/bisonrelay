import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_grid.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_studio.dart is the Data Studio (Ken, 2026-11-15: Table and Chart made
// one Data element, built in "a full screen studio mode ... more inline with
// common spreadsheet software like open office"): the canvas's sheets given
// the whole page, as Calc lays a workbook out.
//
// Across the top, its tools; under them the name box and the formula bar;
// the sheet in the middle (data_grid.dart) with a tab for each sheet below
// it and a status bar under that (the selection's sum, average and count).
// On the right, what the canvas shows: the Data element picked, drawn as it
// is on the page, the others of this sheet to pick from -- their ranges
// drawn round in the sheet -- and the picked one's own settings, as its
// panel on the canvas has them.
//
// Every change goes through the controller, so the canvas follows at once
// and each is a step to undo.

class DataStudio extends StatefulWidget {
  final CanvasController controller;
  final String sheetId;
  final VoidCallback onDone;
  const DataStudio(
      {required this.controller,
      required this.sheetId,
      required this.onDone,
      super.key});

  @override
  State<DataStudio> createState() => _DataStudioState();
}

/// _paper is whether the sheet is drawn on Calc's paper or in the app's
/// theme, kept while the app runs.
bool _paper = true;

class _DataStudioState extends State<DataStudio> {
  CanvasController get c => widget.controller;
  late String _sheet = widget.sheetId;
  DataSel _sel = const DataSel.at(0, 0);
  String? _view;
  final GlobalKey<DataGridState> _grid = GlobalKey();
  final FocusNode _gridFocus = FocusNode();
  final TextEditingController _formula = TextEditingController();
  final FocusNode _formulaFocus = FocusNode();
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _renaming;
  final TextEditingController _rename = TextEditingController();
  String _said = "";

  @override
  void initState() {
    super.initState();
    _view = c.dataStudioView;
    c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _gridFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _gridFocus.dispose();
    _formula.dispose();
    _formulaFocus.dispose();
    _name.dispose();
    _nameFocus.dispose();
    _rename.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  DataSheet? get sheet => c.sheetById(_sheet);

  List<CanvasElement> get _views => viewsOf(c.document, _sheet);

  CanvasElement? get _picked {
    var all = _views;
    return all.where((v) => v.id == _view).firstOrNull ?? all.firstOrNull;
  }

  void _say(String words) => setState(() => _said = words);

  /// _rows is the selection's rows clamped to what the sheet holds -- a
  /// column picked whole is its used rows.
  CellRange _used(CellRange g) {
    var s = sheet!;
    var used = s.used;
    return CellRange(g.r0, g.c0, math.max(g.r0, math.min(g.r1, used.r1)),
        math.max(g.c0, math.min(g.c1, used.c1)));
  }

  /// _forView is the range a new view of the selection shows: the
  /// selection, or -- one cell picked -- the block it is in.
  CellRange _forView() {
    var g = _sel.range;
    if (!_sel.single) return _used(g);
    var s = sheet!;
    if (s.rowCount == 0) return const CellRange(0, 0, 0, 0);
    return s.used;
  }

  void _addView(ElementKind kind) {
    var made = c.addDataView(kind, _sheet, _forView());
    setState(() => _view = made.id);
    _say("A ${kind == ElementKind.chart ? "chart" : "table"} of "
        "${linkOf(made)?.range.a1 ?? ""} is on the canvas.");
  }

  void _sort({required bool descending}) {
    var s = sheet;
    if (s == null) return;
    var g = _used(_sel.range);
    if (g.rows < 2) {
      _say("Select the rows to sort first.");
      return;
    }
    var by = _sel.ac.clamp(g.c0, g.c1);
    // A heading row stays where it is.
    var r0 = g.r0;
    if (sheetValue(s, r0, by) is! double &&
        sheetValue(s, r0 + 1, by) is double) {
      r0++;
    }
    c.sortSheetRows(_sheet, CellRange(r0, g.c0, g.r1, g.c1), by,
        descending: descending);
    _say("Sorted by column ${columnName(by)}, "
        "${descending ? "largest" : "smallest"} first.");
  }

  void _rowsOrColumns({required bool rows, required bool insert}) {
    var g = _sel.range;
    var used = sheet!.used;
    if (rows) {
      var n = math.max(1, math.min(g.r1, math.max(g.r0, used.r1)) - g.r0 + 1);
      insert
          ? c.insertSheetRows(_sheet, g.r0, n)
          : c.deleteSheetRows(_sheet, g.r0, n);
    } else {
      var n = math.max(1, math.min(g.c1, math.max(g.c0, used.c1)) - g.c0 + 1);
      insert
          ? c.insertSheetColumns(_sheet, g.c0, n)
          : c.deleteSheetColumns(_sheet, g.c0, n);
    }
    _gridFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var s = sheet ?? c.document.sheets.firstOrNull;
    if (s == null) {
      return Material(
          color: colors.surface,
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("This canvas has no sheets yet.",
                style: TextStyle(color: colors.onSurface)),
            const SizedBox(height: 12),
            StudioPill(
                label: "Make one",
                filled: true,
                onTap: () => setState(() => _sheet = c.addSheet())),
            const SizedBox(height: 8),
            StudioPill(label: "Back to the canvas", onTap: widget.onDone),
          ])));
    }
    if (s.id != _sheet) _sheet = s.id;
    if (!_formulaFocus.hasFocus) _formula.text = s.raw(_sel.ar, _sel.ac);
    if (!_nameFocus.hasFocus) _name.text = _sel.range.a1;
    var picked = _picked;
    var look = _paper ? DataGridLook.calc : DataGridLook.theme(colors);
    return Material(
      color: colors.surface,
      child: Column(children: [
        _topBar(context, s),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        _formulaBar(context, s),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(children: [
                Expanded(
                  child: DataGrid(
                    key: _grid,
                    sheet: s,
                    sel: _sel,
                    look: look,
                    focusNode: _gridFocus,
                    outlines: [if (picked != null) _outlineOf(picked)],
                    onSelect: (next) => setState(() => _sel = next),
                    onEdit: (r, col, text) => c.setSheetCells(_sheet, r, col, [
                      [text]
                    ]),
                    onPaste: (r, col, rows) {
                      c.setSheetCells(_sheet, r, col, rows);
                      _say("Pasted ${rows.length} row"
                          "${rows.length == 1 ? "" : "s"}.");
                    },
                    onClear: (g) => c.clearSheetCells(_sheet, _used(g)),
                    onFill: (from, to) {
                      c.fillSheet(_sheet, from, to);
                      _say("Filled ${to.a1}.");
                    },
                    onUndo: c.undo,
                    onRedo: c.redo,
                  ),
                ),
                _sheetTabs(context),
              ]),
            ),
            VerticalDivider(
                width: 1, thickness: 1, color: colors.outlineVariant),
            SizedBox(width: 380, child: _side(context, s, picked)),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        _status(context, s),
      ]),
    );
  }

  DataOutline _outlineOf(CanvasElement v) {
    var link = linkOf(v)!;
    if (v is ChartElement) {
      return DataOutline(link.range, const Color(0xFF9B7CF4), columns: {
        link.labels: const Color(0xFF9B7CF4),
        for (var (i, p) in link.series.indexed)
          p: i < v.data.series.length
              ? v.data.series[i].color
              : chartPalette[i % chartPalette.length],
      });
    }
    return DataOutline(link.range, const Color(0xFF2ED6A1));
  }

  Widget _topBar(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
    Widget gap([double w = 4]) => SizedBox(width: w);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text("Data Studio",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        gap(12),
        Expanded(
          child: Text(s.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
        ),
        Flexible(
          flex: 6,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: [
              StudioPill(
                  key: const ValueKey("dataStudioUndo"),
                  label: "Undo",
                  tooltip: "Undo (⌘Z)",
                  onTap: c.canUndo ? c.undo : null),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioRedo"),
                  label: "Redo",
                  tooltip: "Redo (⇧⌘Z)",
                  onTap: c.canRedo ? c.redo : null),
              gap(12),
              StudioPill(
                  key: const ValueKey("dataStudioSortUp"),
                  label: "Sort ↑",
                  tooltip: "The selection's rows by this column, smallest "
                      "first",
                  onTap: () => _sort(descending: false)),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioSortDown"),
                  label: "Sort ↓",
                  tooltip: "Largest first",
                  onTap: () => _sort(descending: true)),
              gap(12),
              StudioPill(
                  key: const ValueKey("dataStudioRowIn"),
                  label: "+ Row",
                  tooltip: "Rows above the selection",
                  onTap: () => _rowsOrColumns(rows: true, insert: true)),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioRowOut"),
                  label: "− Row",
                  tooltip: "Take the selection's rows out",
                  onTap: () => _rowsOrColumns(rows: true, insert: false)),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioColumnIn"),
                  label: "+ Column",
                  tooltip: "Columns left of the selection",
                  onTap: () => _rowsOrColumns(rows: false, insert: true)),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioColumnOut"),
                  label: "− Column",
                  tooltip: "Take the selection's columns out",
                  onTap: () => _rowsOrColumns(rows: false, insert: false)),
              gap(12),
              StudioPill(
                  key: const ValueKey("dataStudioAddTable"),
                  label: "+ Table",
                  tooltip: "A table of the selection on the canvas",
                  onTap: () => _addView(ElementKind.table)),
              gap(),
              StudioPill(
                  key: const ValueKey("dataStudioAddChart"),
                  label: "+ Chart",
                  tooltip: "A chart of the selection on the canvas",
                  filled: true,
                  onTap: () => _addView(ElementKind.chart)),
              gap(12),
              StudioPill(
                  key: const ValueKey("dataStudioPaper"),
                  label: _paper ? "Sheet: Paper" : "Sheet: Theme",
                  tooltip: "The sheet on paper, as in Calc, or in the app's "
                      "colours",
                  onTap: () => setState(() => _paper = !_paper)),
              gap(12),
              StudioPill(
                  key: const ValueKey("dataStudioDone"),
                  label: "Done",
                  filled: true,
                  onTap: widget.onDone),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _formulaBar(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
    InputDecoration box() => InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colors.outlineVariant)),
        );
    var format = s.formatAt(_sel.ar, _sel.ac);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        // How the selection's numbers are written (Calc's Number Format).
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey("dataStudioFormat"),
            value: _formatKey(format),
            isDense: true,
            style: TextStyle(fontSize: 13, color: colors.onSurface),
            dropdownColor: colors.surfaceContainerHigh,
            items: [
              for (var (k, label) in _formatChoices)
                DropdownMenuItem(value: k, child: Text(label)),
            ],
            onChanged: (k) {
              if (k != null) _setFormat(s, _formatFor(k, format));
            },
          ),
        ),
        const SizedBox(width: 6),
        StudioPill(
            key: const ValueKey("dataStudioFewer"),
            label: ".0−",
            tooltip: "Fewer decimals",
            onTap: () => _setFormat(
                s,
                (format ?? const CellFormat(CellFormatKind.general)).copyWith(
                    decimals: math.max(0, (format?.places ?? 0) - 1)))),
        const SizedBox(width: 4),
        StudioPill(
            key: const ValueKey("dataStudioMore"),
            label: ".00+",
            tooltip: "More decimals",
            onTap: () => _setFormat(
                s,
                (format ?? const CellFormat(CellFormatKind.general)).copyWith(
                    decimals: math.min(10, (format?.places ?? 0) + 1)))),
        const SizedBox(width: 12),
        SizedBox(
          width: 104,
          child: TextField(
            key: const ValueKey("dataStudioNameBox"),
            controller: _name,
            focusNode: _nameFocus,
            style: TextStyle(
                fontSize: 12.5,
                fontFamily: "monospace",
                color: colors.onSurface),
            decoration: box(),
            onSubmitted: (text) {
              var g = CellRange.parse(text);
              if (g == null) {
                _say("Type a cell like B4 or a range like A1:C9.");
              } else {
                setState(() => _sel = DataSel(g.r0, g.c0, g.r1, g.c1));
              }
              _gridFocus.requestFocus();
            },
          ),
        ),
        const SizedBox(width: 8),
        Text("fx",
            style: TextStyle(
                fontStyle: FontStyle.italic,
                fontFamily: "Georgia",
                color: colors.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const ValueKey("dataStudioFormula"),
            controller: _formula,
            focusNode: _formulaFocus,
            style: TextStyle(
                fontSize: 13, fontFamily: "monospace", color: colors.onSurface),
            decoration: box()
                .copyWith(hintText: "Type a value, or a formula: =SUM(B2:B9)"),
            onSubmitted: (text) {
              if (text != s.raw(_sel.ar, _sel.ac)) {
                c.setSheetCells(_sheet, _sel.ar, _sel.ac, [
                  [text]
                ]);
              }
              _gridFocus.requestFocus();
            },
          ),
        ),
      ]),
    );
  }

  static const _formatChoices = [
    ("general", "General"),
    ("number", "Number 1,234"),
    (r"money:$", r"Money $"),
    ("money:£", "Money £"),
    ("money:€", "Money €"),
    ("percent", "Percent %"),
    ("short", "Short 1.2k"),
    ("date", "Date 15/11/2026"),
    ("text", "Text, as typed"),
  ];

  String _formatKey(CellFormat? f) => switch (f?.kind) {
        null || CellFormatKind.general => "general",
        CellFormatKind.money => "money:${f!.symbol}",
        var k => k.name,
      };

  CellFormat? _formatFor(String key, CellFormat? was) {
    if (key == "general") return null;
    var parts = key.split(":");
    var kind = CellFormatKind.values.byName(parts.first);
    return CellFormat(kind, symbol: parts.length > 1 ? parts[1] : r"$");
  }

  /// _setFormat gives the selection [f]: whole columns, picked by their
  /// letters, as their columns'.
  void _setFormat(DataSheet s, CellFormat? f) {
    var g = _sel.range;
    var columns = g.r0 == 0 && g.r1 >= math.max(199, s.rowCount);
    c.formatSheetCells(_sheet, columns ? g : _used(g), f, columns: columns);
    _gridFocus.requestFocus();
  }

  Widget _sheetTabs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var sheets = c.document.sheets;
    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant))),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var sh in sheets)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _renaming == sh.id
                    ? SizedBox(
                        width: 150,
                        child: TextField(
                          key: const ValueKey("dataStudioRename"),
                          controller: _rename,
                          autofocus: true,
                          style: TextStyle(
                              fontSize: 12.5, color: colors.onSurface),
                          decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8)),
                          onSubmitted: (v) {
                            c.renameSheet(sh.id, v);
                            setState(() => _renaming = null);
                          },
                          onTapOutside: (_) {
                            c.renameSheet(sh.id, _rename.text);
                            setState(() => _renaming = null);
                          },
                        ),
                      )
                    : GestureDetector(
                        key: ValueKey("dataStudioTab-${sh.id}"),
                        onTap: () => setState(() {
                          _sheet = sh.id;
                          _sel = const DataSel.at(0, 0);
                          _view = null;
                        }),
                        onDoubleTap: () => setState(() {
                          _renaming = sh.id;
                          _rename.text = sh.name;
                        }),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: sh.id == _sheet
                                ? colors.surface
                                : Colors.transparent,
                            border: Border.all(
                                color: sh.id == _sheet
                                    ? colors.outlineVariant
                                    : Colors.transparent),
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(6)),
                          ),
                          child: Text(sh.name,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: sh.id == _sheet
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant)),
                        ),
                      ),
              ),
          ]),
        ),
        StudioPill(
            key: const ValueKey("dataStudioAddSheet"),
            label: "+ Sheet",
            onTap: () => setState(() {
                  _sheet = c.addSheet();
                  _sel = const DataSel.at(0, 0);
                  _view = null;
                })),
        const SizedBox(width: 4),
        StudioPill(
            key: const ValueKey("dataStudioRemoveSheet"),
            label: "Remove",
            tooltip: _views.isEmpty
                ? "Take this sheet out of the canvas"
                : "Shown on the canvas: delete its tables and charts first",
            onTap: _views.isEmpty && sheets.length > 1
                ? () {
                    var gone = _sheet;
                    if (c.removeSheet(gone)) {
                      setState(() {
                        _sheet = c.document.sheets.first.id;
                        _sel = const DataSel.at(0, 0);
                      });
                    }
                  }
                : null),
      ]),
    );
  }

  Widget _side(BuildContext context, DataSheet s, CanvasElement? picked) {
    final colors = ThemeNotifier.of(context).colors;
    var views = _views;
    return Container(
      color: colors.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: const StudioLabel("What the canvas shows"),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 190,
            child: picked == null
                ? Center(
                    child: Text(
                        "Nothing on the canvas shows this sheet. Select cells "
                        "and press + Table or + Chart.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant)))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CustomPaint(
                      key: const ValueKey("dataStudioPreview"),
                      painter: _ViewPreview(
                          picked, c.document.background.spec.background),
                      size: Size.infinite,
                    ),
                  ),
          ),
        ),
        if (views.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (var v in views)
                StudioPill(
                  key: ValueKey("dataStudioView-${v.id}"),
                  label: "${v is ChartElement ? "Chart" : "Table"} · "
                      "${v.name.isEmpty ? v.kind.label : v.name} · "
                      "${linkOf(v)!.range.a1}",
                  selected: v.id == picked?.id,
                  onTap: () => setState(() => _view = v.id),
                ),
            ]),
          ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        Expanded(
          child: picked == null
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  key: ValueKey("dataStudioSettings-${picked.id}"),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  child: CanvasControlScope(
                    maxWidth: 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: elementSettings(context, c, picked),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _status(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
    var g = _used(_sel.range);
    var numbers = <double>[];
    var count = 0;
    for (var r = g.r0; r <= g.r1; r++) {
      for (var col = g.c0; col <= g.c1; col++) {
        var v = sheetValue(s, r, col);
        if (v == null || v == "") continue;
        count++;
        if (v is double) numbers.add(v);
      }
    }
    var sum = numbers.fold(0.0, (a, b) => a + b);
    String n(double v) => numText(double.parse(v.toStringAsFixed(6)));
    var using = [
      for (var v in _views)
        if (linkOf(v)!.range.overlaps(_sel.range))
          v.name.isEmpty ? v.kind.label : v.name
    ];
    TextStyle st([bool strong = false]) => TextStyle(
        fontSize: 12,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        color: strong ? colors.onSurface : colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Text("Sum ", style: st()),
        Text(numbers.isEmpty ? "–" : n(sum),
            key: const ValueKey("dataStudioSum"), style: st(true)),
        const SizedBox(width: 18),
        Text("Average ", style: st()),
        Text(numbers.isEmpty ? "–" : n(sum / numbers.length), style: st(true)),
        const SizedBox(width: 18),
        Text("Count ", style: st()),
        Text("$count", style: st(true)),
        const SizedBox(width: 18),
        Expanded(
          child: Text(_said,
              overflow: TextOverflow.ellipsis,
              style: st().copyWith(color: colors.primary)),
        ),
        Text(
            using.isEmpty
                ? "Not shown on the canvas"
                : "Shown by ${using.join(", ")}",
            style: st()),
      ]),
    );
  }
}

/// _ViewPreview draws a Data element as the canvas does, fitted to the box
/// on the canvas's own ground.
class _ViewPreview extends CustomPainter {
  final CanvasElement e;
  final Color ground;
  _ViewPreview(this.e, this.ground);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
    var scale = math.min((size.width - 16) / w, (size.height - 16) / h);
    canvas.save();
    canvas.translate(
        (size.width - w * scale) / 2, (size.height - h * scale) / 2);
    canvas.scale(scale);
    var rect = Rect.fromLTWH(0, 0, w, h);
    switch (e) {
      case TableElement t:
        paintTable(canvas, rect, t);
      case ChartElement ch:
        paintChart(canvas, rect, ch);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ViewPreview old) =>
      !identical(old.e, e) || old.ground != ground;
}

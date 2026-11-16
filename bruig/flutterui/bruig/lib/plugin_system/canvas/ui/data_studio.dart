import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/sheet_files.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart';
import 'package:bruig/plugin_system/canvas/ui/data_connect.dart';
import 'package:bruig/plugin_system/canvas/ui/data_grid.dart';
import 'package:bruig/plugin_system/canvas/ui/data_reshape.dart';
import 'package:bruig/plugin_system/canvas/ui/data_sheet_find.dart';
import 'package:bruig/plugin_system/canvas/ui/data_table_design.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// DataStudioTab is what the studio shows: the sheet, or the design of one
/// of its tables.
enum DataStudioTab { sheet, table, charts }

class _DataStudioState extends State<DataStudio> {
  CanvasController get c => widget.controller;
  late String _sheet = widget.sheetId;
  DataSel _sel = const DataSel.at(0, 0);
  String? _view;

  /// _chartFromGallery opens the Charts tab on its gallery once, after the
  /// empty tab's button made the sheet's first chart.
  bool _chartFromGallery = false;
  final GlobalKey<DataGridState> _grid = GlobalKey();
  final FocusNode _gridFocus = FocusNode();
  final TextEditingController _formula = TextEditingController();
  final FocusNode _formulaFocus = FocusNode();
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _renaming;

  /// _asking is what the sheet tabs bar is asking to be sure of before it
  /// does it: "remove" (this sheet, with what shows it) or "tidy" (every
  /// sheet nothing on the canvas shows); null, nothing.
  String? _asking;
  final TextEditingController _rename = TextEditingController();
  String _said = "";
  DataStudioTab _tab = DataStudioTab.sheet;

  // Connect data (data_connect.dart): the steps open in the side panel,
  // the grid previewing what will come; after a refresh, the cells that
  // changed light up for a moment.
  bool _connecting = false;
  bool _editingSource = false;
  List<List<String>>? _preview;
  Set<(int, int)> _flash = const {};
  Timer? _flashing;

  void _flashCells(Set<(int, int)> cells) {
    _flashing?.cancel();
    setState(() => _flash = cells);
    _flashing = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flash = const {});
    });
  }

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
    _flashing?.cancel();
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

  /// _rowsOrColumns puts [n] rows (or columns) in before [at], or takes
  /// them out from it: the grid's right-click menu on its headers.
  void _rowsOrColumns(
      {required bool rows,
      required bool insert,
      required int at,
      required int n}) {
    if (rows) {
      insert
          ? c.insertSheetRows(_sheet, at, n)
          : c.deleteSheetRows(_sheet, at, n);
    } else {
      insert
          ? c.insertSheetColumns(_sheet, at, n)
          : c.deleteSheetColumns(_sheet, at, n);
    }
    var what = rows
        ? (n == 1 ? "a row" : "$n rows")
        : (n == 1 ? "a column" : "$n columns");
    _say(insert ? "Put in $what." : "Took out $what.");
    _gridFocus.requestFocus();
  }

  /// _resize gives the grid [rows] by [columns] (its ends' − and +): the
  /// selection kept inside it.
  void _resize(int rows, int columns) {
    var s = sheet!;
    var cutting = s.rowCount > rows || s.columnCount > columns;
    c.resizeSheet(_sheet, rows, columns);
    var g = _sel;
    setState(() => _sel = DataSel(
        math.min(g.ar, rows - 1),
        math.min(g.ac, columns - 1),
        math.min(g.fr, rows - 1),
        math.min(g.fc, columns - 1)));
    _say("The sheet is $rows rows by $columns columns"
        "${cutting ? "; what was past the edge went with them" : ""}.");
  }

  Future<void> _import() async {
    var picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ["csv", "tsv", "txt", "xlsx", "ods"],
      withData: true,
    );
    var file = picked?.files.singleOrNull;
    if (file == null || !mounted) return;
    try {
      var bytes = file.bytes ?? await File(file.path!).readAsBytes();
      var read = readSheets(file.name, bytes);
      var ids = c.addReadSheets(read);
      setState(() {
        _sheet = ids.first;
        _sel = const DataSel.at(0, 0);
        _view = null;
      });
      _say("Read ${read.length == 1 ? "a sheet" : "${read.length} sheets"} "
          "from ${file.name}.");
    } on FormatException catch (e) {
      _say(e.message);
    } catch (e) {
      _say("That file couldn't be read: $e");
    }
  }

  Future<void> _export(DataSheet s) async {
    var path = await FilePicker.platform.saveFile(
      dialogTitle: "Export ${s.name} as CSV",
      fileName: "${s.name}.csv",
      type: FileType.custom,
      allowedExtensions: const ["csv"],
    );
    if (path == null || !mounted) return;
    try {
      await File(path).writeAsString(csvOf(s));
      _say("Saved ${path.split(Platform.pathSeparator).last}.");
    } catch (e) {
      _say("It couldn't be saved: $e");
    }
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
    if (_tab != DataStudioTab.sheet) {
      return Material(
        color: colors.surface,
        child: Column(children: [
          _topBar(context, s),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          Expanded(
              child: _tab == DataStudioTab.table
                  ? _tableTab(context, s)
                  : _chartsTab(context, s)),
        ]),
      );
    }
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
                if (_preview != null)
                  Container(
                    key: const ValueKey("dataStudioPreviewBar"),
                    width: double.infinity,
                    color: colors.primary.withValues(alpha: 0.14),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                        "Preview: what Connect will put in the sheet "
                        "(${_preview!.length - 1} rows)",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface)),
                  ),
                Expanded(
                  child: _preview != null
                      ? DataGrid(
                          key: const ValueKey("dataStudioPreviewGrid"),
                          sheet: DataSheet(id: "preview", cells: _preview!),
                          sel: const DataSel.at(0, 0),
                          look: look,
                          images: c.images,
                          onSelect: (_) {},
                          onEdit: (_, __, ___) {},
                          onPaste: (_, __, ___) {},
                          onClear: (_) {},
                        )
                      : DataGrid(
                          key: _grid,
                          flash: _flash,
                          sheet: s,
                          sel: _sel,
                          look: look,
                          images: c.images,
                          focusNode: _gridFocus,
                          outlines: [if (picked != null) _outlineOf(picked)],
                          onSelect: (next) => setState(() => _sel = next),
                          onEdit: (r, col, text) =>
                              c.setSheetCells(_sheet, r, col, [
                            [text]
                          ]),
                          onPaste: (r, col, rows) {
                            c.pasteSheetCells(_sheet, r, col, rows);
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
                          onResize: _resize,
                          onRowsOrColumns: _rowsOrColumns,
                        ),
                ),
                _sheetTabs(context),
              ]),
            ),
            VerticalDivider(
                width: 1, thickness: 1, color: colors.outlineVariant),
            SizedBox(
                width: 380,
                child: _connecting
                    ? Container(
                        color: colors.surfaceContainerLow,
                        child: ConnectData(
                          key: ValueKey("dataStudioConnect-$_editingSource"),
                          controller: c,
                          sheetId: _sheet,
                          editing: _editingSource,
                          onPreview: (rows) => setState(() => _preview = rows),
                          onCancel: () => setState(() {
                            _connecting = false;
                            _preview = null;
                          }),
                          onConnected: (id, changed) {
                            setState(() {
                              _connecting = false;
                              _preview = null;
                              _sheet = id;
                            });
                            _flashCells(changed);
                            _say(
                                "Connected: ${sourceSays(c.sheetById(id)?.source ?? const DataSource())}.");
                          },
                        ),
                      )
                    : _side(context, s, picked)),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        _status(context, s),
      ]),
    );
  }

  /// _tableTab is the Table tab: the design of the table picked among this
  /// sheet's views (or its first), with a chip for each when there are
  /// several.
  Widget _tableTab(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
    var tables = _views.whereType<TableElement>().toList();
    if (tables.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("No table on the canvas shows this sheet.",
            style: TextStyle(color: colors.onSurface)),
        const SizedBox(height: 12),
        StudioPill(
            key: const ValueKey("dataStudioTableMake"),
            label: "+ Table of this sheet",
            filled: true,
            onTap: () {
              var made = c.addDataView(ElementKind.table, _sheet, s.used);
              setState(() => _view = made.id);
            }),
      ]));
    }
    var table = tables.where((v) => v.id == _view).firstOrNull ?? tables.first;
    return Column(children: [
      if (tables.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (var v in tables)
              StudioPill(
                key: ValueKey("dataStudioTablePick-${v.id}"),
                label: "${v.name.isEmpty ? "Table" : v.name} · "
                    "${linkOf(v)!.range.a1}",
                selected: v.id == table.id,
                onTap: () => setState(() => _view = v.id),
              ),
          ]),
        ),
      Expanded(
          child: TableDesign(
              key: const ValueKey("dataStudioTableDesign"),
              controller: c,
              table: table)),
    ]);
  }

  /// _chartsTab is the Charts tab: the chart picked among this sheet's
  /// views, or its first; none, a way to make one.
  Widget _chartsTab(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
    var charts = _views.whereType<ChartElement>().toList();
    if (charts.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("No chart on the canvas shows this sheet.",
            style: TextStyle(color: colors.onSurface)),
        const SizedBox(height: 12),
        StudioPill(
            key: const ValueKey("dataStudioChartMake"),
            label: "+ Chart of this sheet",
            filled: true,
            onTap: () {
              var made = c.addDataView(ElementKind.chart, _sheet, s.used);
              setState(() {
                _view = startedChart(c, made).id;
                _chartFromGallery = true;
              });
            }),
      ]));
    }
    var chart = charts.where((v) => v.id == _view).firstOrNull ?? charts.first;
    // Read once: the tab's state opens on the gallery when it is made.
    var gallery = _chartFromGallery;
    _chartFromGallery = false;
    return ChartsDesign(
        key: const ValueKey("dataStudioChartsDesign"),
        controller: c,
        sheetId: s.id,
        chart: chart,
        startInGallery: gallery,
        onPickChart: (id) => setState(() => _view = id));
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
        for (var (tab, name) in const [
          (DataStudioTab.sheet, "Sheet"),
          (DataStudioTab.table, "Table"),
          (DataStudioTab.charts, "Charts"),
        ]) ...[
          StudioPill(
              key: ValueKey("dataStudioTab-${tab.name}"),
              label: name,
              selected: _tab == tab,
              onTap: () => setState(() => _tab = tab)),
          gap(),
        ],
        gap(8),
        // The sheet's name is on its tab under the grid; on the other tabs,
        // here, since they have no tabs of sheets.
        // The rest of the bar is the sheet's name there, so Done is at the
        // right.
        Expanded(
          child: _tab == DataStudioTab.sheet
              ? const SizedBox.shrink()
              : Text(s.name,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
        ),
        // Undo and Redo are on the row below on the Sheet tab.
        if (_tab != DataStudioTab.sheet) ..._undoRedo(),
        gap(12),
        StudioPill(
            key: const ValueKey("dataStudioDone"),
            label: "Done",
            filled: true,
            onTap: widget.onDone),
      ]),
    );
  }

  /// _undoRedo are Undo and Redo, as icons.
  List<Widget> _undoRedo() => [
        StudioPill(
            key: const ValueKey("dataStudioUndo"),
            label: "",
            icon: Icons.undo,
            tooltip: "Undo (⌘Z)",
            onTap: c.canUndo ? c.undo : null),
        const SizedBox(width: 4),
        StudioPill(
            key: const ValueKey("dataStudioRedo"),
            label: "",
            icon: Icons.redo,
            tooltip: "Redo (⇧⌘Z)",
            onTap: c.canRedo ? c.redo : null),
      ];

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // The tools scroll sideways where the window is short of room (a big
      // text size), the cell's box and its formula keeping theirs.
      child: LayoutBuilder(
        builder: (context, room) => Row(children: [
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: math.max(0, room.maxWidth - 104 - 48 - 240)),
            child: SingleChildScrollView(
              key: const ValueKey("dataStudioTools"),
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ..._undoRedo(),
                const SizedBox(width: 12),
                StudioPill(
                    key: const ValueKey("dataStudioSortUp"),
                    label: "Sort",
                    icon: Icons.arrow_upward,
                    tooltip:
                        "The selection's rows by this column, smallest first",
                    onTap: () => _sort(descending: false)),
                const SizedBox(width: 4),
                StudioPill(
                    key: const ValueKey("dataStudioSortDown"),
                    label: "Sort",
                    icon: Icons.arrow_downward,
                    tooltip: "Largest first",
                    onTap: () => _sort(descending: true)),
              ]),
            ),
          ),
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
                  fontSize: 13,
                  fontFamily: "monospace",
                  color: colors.onSurface),
              decoration: box().copyWith(
                  hintText: "Type a value, or a formula: =SUM(B2:B9)"),
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
      ),
    );
  }

  static const _ruleChoices = [
    ("bars", "Data bars"),
    ("barsBlue", "Data bars, blue"),
    ("scale", "Colour scale, red to green"),
    ("scaleBlue", "Colour scale, white to blue"),
    ("above", "Above average"),
    ("below", "Below average"),
    ("top", "Top 3"),
    ("clear", "Clear colour rules here"),
  ];

  void _setRule(DataSheet s, String key) {
    var g = _used(_sel.range);
    if (key == "clear") {
      c.clearSheetRules(_sheet, g);
      _say("Colour rules taken off ${g.a1}.");
    } else {
      c.addSheetRule(
          _sheet,
          switch (key) {
            "barsBlue" =>
              SheetRule(g, SheetRuleKind.bars, colour: const Color(0xFF4C8DF6)),
            "scale" => SheetRule(g, SheetRuleKind.scale),
            "scaleBlue" => SheetRule(g, SheetRuleKind.scale,
                low: const Color(0xFFFFFFFF), high: const Color(0xFF7FA8F5)),
            "above" => SheetRule(g, SheetRuleKind.above,
                colour: const Color(0xFFBFEBD6)),
            "below" => SheetRule(g, SheetRuleKind.below,
                colour: const Color(0xFFF6C9C4)),
            "top" => SheetRule(g, SheetRuleKind.top,
                colour: const Color(0xFFF7DE8E), value: "3"),
            _ => SheetRule(g, SheetRuleKind.bars),
          });
      _say("${_ruleChoices.firstWhere((r) => r.$1 == key).$2} on ${g.a1}.");
    }
    _gridFocus.requestFocus();
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
    var columns = g.r0 == 0 && g.r1 >= s.shownRows - 1;
    c.formatSheetCells(_sheet, columns ? g : _used(g), f, columns: columns);
    _gridFocus.requestFocus();
  }

  Widget _sheetTabs(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var sheets = c.document.sheets;
    // Sheets nothing on the canvas shows -- left behind when their tables
    // and charts were deleted. One is always kept.
    var unused = {
      for (var x in sheets)
        if (viewsOf(c.document, x.id).isEmpty) x.id
    };
    if (unused.length == sheets.length) unused.remove(_sheet);
    var (ordered, here) = sheetsInOrder(c.document);
    return Container(
      height: 36,
      decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant))),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        // Every sheet, searched as typed; and the tabs with this page's
        // first (data_sheet_find.dart).
        SheetFinder(
            document: c.document,
            current: _sheet,
            onOpen: (id) => setState(() {
                  _sheet = id;
                  _sel = const DataSel.at(0, 0);
                  _view = null;
                  _asking = null;
                })),
        const SizedBox(width: 6),
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var (k, sh) in ordered.indexed) ...[
              if (k == here && here > 0)
                Container(
                    key: const ValueKey("dataStudioTabsRest"),
                    width: 1,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    color: colors.outlineVariant),
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
                          _asking = null;
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
                          child: Text(
                              sh.source.on
                                  ? "${sh.name} · ${sourceSays(sh.source)}"
                                  : sh.name,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  // Nothing on the canvas shows it: said
                                  // by its look, and by Remove unused.
                                  fontStyle: unused.contains(sh.id)
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  color: sh.id == _sheet
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: unused.contains(sh.id)
                                              ? 0.6
                                              : 1))),
                        ),
                      ),
              ),
            ],
          ]),
        ),
        if (_asking != null) ...[
          Flexible(
            child: Text(
                _asking == "tidy"
                    ? "Remove ${unused.length} sheet${unused.length == 1 ? "" : "s"} nothing shows?"
                    : _views.isEmpty
                        ? "Remove this sheet?"
                        : "Remove this sheet and the ${_views.length} "
                            "table${_views.length == 1 ? "" : "s"} or chart${_views.length == 1 ? "" : "s"} showing it?",
                key: const ValueKey("dataStudioAsking"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: colors.onSurface)),
          ),
          const SizedBox(width: 8),
          StudioPill(
              key: const ValueKey("dataStudioSure"),
              label: "Remove",
              filled: true,
              onTap: () {
                var tidy = _asking == "tidy";
                var gone = tidy ? unused : {_sheet};
                var left = [
                  for (var x in sheets)
                    if (!gone.contains(x.id)) x.id
                ];
                c.removeSheets(gone);
                setState(() {
                  _asking = null;
                  if (gone.contains(_sheet)) {
                    _sheet = left.first;
                    _sel = const DataSel.at(0, 0);
                    _view = null;
                  }
                });
                _say(tidy
                    ? "Removed ${gone.length} sheet${gone.length == 1 ? "" : "s"} nothing showed."
                    : "Sheet removed.");
              }),
          const SizedBox(width: 4),
          StudioPill(
              key: const ValueKey("dataStudioNotSure"),
              label: "Cancel",
              onTap: () => setState(() => _asking = null)),
        ] else ...[
          if (unused.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StudioPill(
                  key: const ValueKey("dataStudioTidySheets"),
                  label: "Remove unused (${unused.length})",
                  tooltip: "Sheets that no table or chart on the canvas "
                      "shows (in italics)",
                  onTap: () => setState(() => _asking = "tidy")),
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
                  : "Take this sheet out, with the tables and charts "
                      "showing it",
              onTap: sheets.length > 1
                  ? () {
                      // Nothing in it and nothing showing it: gone at once.
                      var s = c.sheetById(_sheet);
                      if (_views.isEmpty && (s == null || s.rowCount == 0)) {
                        var left = sheets.firstWhere((x) => x.id != _sheet);
                        c.removeSheets({_sheet});
                        setState(() {
                          _sheet = left.id;
                          _sel = const DataSel.at(0, 0);
                          _view = null;
                        });
                      } else {
                        setState(() => _asking = "remove");
                      }
                    }
                  : null),
        ],
      ]),
    );
  }

  /// _side is the Sheet tab's side panel: all about the sheet (Ken,
  /// 2026-11-16: what a table or chart looks like is the Table and Charts
  /// tabs'). Where its cells come from; the sheet itself; the cells picked;
  /// and what on the canvas is made from it. One scroll, nothing pinned.
  Widget _side(BuildContext context, DataSheet s, CanvasElement? picked) {
    final colors = ThemeNotifier.of(context).colors;
    Widget part(List<Widget> children) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
    Widget hint(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        );
    Widget rule() => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        );
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        key: const ValueKey("dataStudioSide"),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Where its cells come from.
          part([
            const StudioLabel("Its data"),
            if (s.source.on)
              SheetSourceCard(
                controller: c,
                sheet: s,
                onEdit: () => setState(() {
                  _connecting = true;
                  _editingSource = true;
                }),
                onRefreshed: _flashCells,
              )
            else ...[
              Wrap(spacing: 4, runSpacing: 4, children: [
                StudioPill(
                    key: const ValueKey("dataStudioConnectData"),
                    label: "Connect data",
                    icon: Icons.link,
                    tooltip: "Fill this sheet from a web address or a file, "
                        "and refresh it",
                    onTap: () => setState(() {
                          _connecting = true;
                          _editingSource = false;
                        })),
                StudioPill(
                    key: const ValueKey("dataStudioImport"),
                    label: "Import",
                    icon: Icons.file_open_outlined,
                    tooltip: "Sheets from a CSV, XLSX or ODS file: values "
                        "and formulas",
                    onTap: _import),
              ]),
              hint("Typed in here. Connect it to a web address or a file "
                  "and it can be refreshed."),
            ],
          ]),
          rule(),
          // The sheet itself.
          part([
            const StudioLabel("This sheet"),
            _Box(
                key: const ValueKey("dataStudioSheetName"),
                text: s.name,
                hint: "Its name",
                onCommit: (v) {
                  if (v.trim().isNotEmpty) c.renameSheet(s.id, v.trim());
                }),
            const SizedBox(height: 6),
            // Kept in a folder, for the list of sheets (data_sheet_find).
            _Box(
                key: const ValueKey("dataStudioSheetFolder"),
                text: s.folder,
                hint: "Its folder (optional)",
                onCommit: (v) {
                  if (v.trim() != s.folder) {
                    c.setSheet(s.copyWith(folder: v.trim()));
                  }
                }),
            const SizedBox(height: 8),
            // Wrapping onto a second line at a large text size.
            Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    child: _Box(
                        key: const ValueKey("dataStudioSheetRows"),
                        text: "${s.shownRows}",
                        digits: true,
                        onCommit: (v) {
                          var n = int.tryParse(v);
                          if (n != null && n > 0 && n != s.shownRows) {
                            _resize(n, s.shownColumns);
                          }
                        }),
                  ),
                  Text("rows by",
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                  SizedBox(
                    width: 64,
                    child: _Box(
                        key: const ValueKey("dataStudioSheetColumns"),
                        text: "${s.shownColumns}",
                        digits: true,
                        onCommit: (v) {
                          var n = int.tryParse(v);
                          if (n != null && n > 0 && n != s.shownColumns) {
                            _resize(s.shownRows, n);
                          }
                        }),
                  ),
                  Text("columns",
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                ]),
            StudioPills<bool>(
                id: "dataStudioLook",
                label: "Shown",
                value: _paper,
                options: const [(true, "On paper"), (false, "In the theme")],
                onChanged: (v) => setState(() => _paper = v)),
            const SizedBox(height: 8),
            StudioPill(
                key: const ValueKey("dataStudioExport"),
                label: "Export CSV",
                icon: Icons.download_outlined,
                tooltip: "This sheet as a CSV file, as it shows",
                onTap: () => _export(s)),
          ]),
          rule(),
          // The cells picked.
          part(_selection(context, s)),
          rule(),
          // What on the canvas is made from it.
          part(_madeFrom(context, s, picked)),
          rule(),
          // Another sheet made from this one, or what this one is made from
          // (data_reshape.dart): last, as the least often wanted.
          part([
            SheetReshapePart(
                key: const ValueKey("dataStudioReshapePart"),
                controller: c,
                sheet: s,
                onOpen: (id) => setState(() => _sheet = id)),
          ]),
        ]),
      ),
    );
  }

  /// _selection is the Selection part of the side panel: what the cells
  /// picked add up to, and how they are written -- their number format and
  /// colour rules (Calc's Format Cells and Conditional Formatting).
  List<Widget> _selection(BuildContext context, DataSheet s) {
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
    TextStyle st([bool strong = false]) => TextStyle(
        fontSize: 12.5,
        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        color: strong ? colors.onSurface : colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()]);
    var format = s.formatAt(_sel.ar, _sel.ac);
    CellFormat stepped(int by) =>
        (format ?? const CellFormat(CellFormatKind.general))
            .copyWith(decimals: ((format?.places ?? 0) + by).clamp(0, 10));
    Widget menu<T>(Key key, T? value, List<(T, String)> options,
            ValueChanged<T> onChanged,
            {String? hint}) =>
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              key: key,
              value: value,
              isDense: true,
              isExpanded: true,
              hint: hint == null
                  ? null
                  : Text(hint,
                      style:
                          TextStyle(fontSize: 12.5, color: colors.onSurface)),
              style: TextStyle(fontSize: 12.5, color: colors.onSurface),
              dropdownColor: colors.surfaceContainerHigh,
              items: [
                for (var (v, label) in options)
                  DropdownMenuItem(value: v, child: Text(label)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        );
    return [
      StudioLabel("Selection · ${_sel.range.a1}"),
      Wrap(spacing: 14, runSpacing: 2, children: [
        Text.rich(
            TextSpan(children: [
              TextSpan(text: "Sum ", style: st()),
              TextSpan(text: numbers.isEmpty ? "–" : n(sum), style: st(true)),
            ]),
            key: const ValueKey("dataStudioSum")),
        Text.rich(TextSpan(children: [
          TextSpan(text: "Average ", style: st()),
          TextSpan(
              text: numbers.isEmpty ? "–" : n(sum / numbers.length),
              style: st(true)),
        ])),
        Text.rich(TextSpan(children: [
          TextSpan(text: "Count ", style: st()),
          TextSpan(text: "$count", style: st(true)),
        ])),
      ]),
      const SizedBox(height: 8),
      // How its numbers are written (Calc's Number Format).
      Row(children: [
        Expanded(
          child: menu<String>(const ValueKey("dataStudioFormat"),
              _formatKey(format), _formatChoices, (k) {
            _setFormat(s, _formatFor(k, format));
          }),
        ),
        const SizedBox(width: 6),
        StudioPill(
            key: const ValueKey("dataStudioFewer"),
            label: ".0−",
            tooltip: "Fewer decimals",
            onTap: () => _setFormat(s, stepped(-1))),
        const SizedBox(width: 4),
        StudioPill(
            key: const ValueKey("dataStudioMore"),
            label: ".00+",
            tooltip: "More decimals",
            onTap: () => _setFormat(s, stepped(1))),
      ]),
      const SizedBox(height: 6),
      // Bars, scales and highlights over it, drawn by the tables showing it.
      menu<String>(const ValueKey("dataStudioRules"), null, _ruleChoices,
          (k) => _setRule(s, k),
          hint: "Colour rules…"),
    ];
  }

  /// _madeFrom is the side panel's list of what on the canvas shows the
  /// sheet: a table or chart put down from the selection, one taken off;
  /// each with the range it reads, pointed at the selection instead, or
  /// opened in its tab to be designed.
  List<Widget> _madeFrom(
      BuildContext context, DataSheet s, CanvasElement? picked) {
    final colors = ThemeNotifier.of(context).colors;
    var views = _views;
    String nameOf(CanvasElement v) => v.name.isEmpty ? v.kind.label : v.name;
    return [
      const StudioLabel("Made from this sheet"),
      Wrap(spacing: 4, runSpacing: 4, children: [
        StudioPill(
            key: const ValueKey("dataStudioAddTable"),
            label: "Table",
            icon: Icons.add,
            tooltip: "A table of the selection on the canvas",
            onTap: () => _addView(ElementKind.table)),
        StudioPill(
            key: const ValueKey("dataStudioAddChart"),
            label: "Chart",
            icon: Icons.add,
            tooltip: "A chart of the selection on the canvas",
            onTap: () => _addView(ElementKind.chart)),
        StudioPill(
            key: const ValueKey("dataStudioRemoveView"),
            label: "Remove",
            icon: Icons.remove,
            tooltip: picked == null
                ? "Nothing to take off the canvas"
                : "Take ${nameOf(picked)} off the canvas",
            onTap: picked == null
                ? null
                : () {
                    var name = nameOf(picked);
                    c.removeDataView(picked.id);
                    setState(() => _view = null);
                    _say("$name is off the canvas.");
                  }),
      ]),
      if (views.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              "Nothing on the canvas shows this sheet yet. Select cells and "
              "press + Table or + Chart.",
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        ),
      for (var v in views)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: v.id == picked?.id
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                    color: v.id == picked?.id
                        ? colors.primary
                        : colors.outlineVariant)),
            child: InkWell(
              key: ValueKey("dataStudioView-${v.id}"),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _view = v.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            v is ChartElement
                                ? Icons.bar_chart
                                : Icons.table_chart_outlined,
                            size: 16,
                            color: colors.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(nameOf(v),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface)),
                        ),
                        Text(linkOf(v)!.range.a1,
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: "monospace",
                                color: colors.onSurfaceVariant)),
                      ]),
                      if (v.id == picked?.id) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          StudioPill(
                              key: const ValueKey("dataStudioUseSelection"),
                              label: "Use the selection",
                              tooltip: "Show ${_forView().a1} instead",
                              onTap: () {
                                var range = _forView();
                                c.showRange(v, range);
                                _say("${nameOf(v)} shows ${range.a1}.");
                              }),
                          StudioPill(
                              key: const ValueKey("dataStudioDesign"),
                              label: "Design it",
                              icon: Icons.arrow_forward,
                              tooltip: v is ChartElement
                                  ? "In the Charts tab"
                                  : "In the Table tab",
                              onTap: () => setState(() => _tab =
                                  v is ChartElement
                                      ? DataStudioTab.charts
                                      : DataStudioTab.table)),
                        ]),
                      ],
                    ]),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _status(BuildContext context, DataSheet s) {
    final colors = ThemeNotifier.of(context).colors;
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

/// _Box is a small text box that writes what was typed when Enter is
/// pressed or it is left, showing [text] again otherwise.
class _Box extends StatefulWidget {
  final String text;
  final String hint;
  final bool digits;
  final ValueChanged<String> onCommit;
  const _Box(
      {required this.text,
      required this.onCommit,
      this.hint = "",
      this.digits = false,
      super.key});

  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  late final TextEditingController _c =
      TextEditingController(text: widget.text);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Box old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _commit() {
    if (_c.text != widget.text) widget.onCommit(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    var border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.outlineVariant));
    return TextField(
      controller: _c,
      focusNode: _f,
      keyboardType: widget.digits ? TextInputType.number : null,
      inputFormatters:
          widget.digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      textAlign: widget.digits ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 13, color: colors.onSurface),
      decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: border,
          enabledBorder: border),
      onSubmitted: (_) => _commit(),
    );
  }
}

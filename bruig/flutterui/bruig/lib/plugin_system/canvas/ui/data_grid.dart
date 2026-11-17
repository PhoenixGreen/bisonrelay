import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// data_grid.dart is the Data Studio's sheet: a spreadsheet's grid, as Calc
// lays one out (Ken, 2026-11-15: "more inline with common spreadsheet
// software like open office") -- column letters across the top, row numbers
// down the side, a cell picked or a range dragged out, typed into, copied
// and pasted with Calc, Excel or Sheets as tab-separated text.
//
// The cells are painted, only those in view, under a pair of scroll views
// that do nothing but scroll: a big sheet scrolls as quickly as a small
// one. The headers are painted beside them, following the scrolling.
//
// It edits nothing itself: what is typed, pasted and cleared goes to the
// Data Studio, which writes it into the sheet through the controller.

const double dataRowHeight = 26;
const double dataColumnWidth = 104;
const double dataHeaderWidth = 48;

/// DataSel is a selection: the cell it began at (the anchor, where typing
/// goes) and the one it was dragged or shifted to.
@immutable
class DataSel {
  final int ar, ac, fr, fc;
  const DataSel(this.ar, this.ac, this.fr, this.fc);
  const DataSel.at(int r, int c) : this(r, c, r, c);

  CellRange get range => CellRange(
      math.min(ar, fr), math.min(ac, fc), math.max(ar, fr), math.max(ac, fc));
  DataSel extendedTo(int r, int c) => DataSel(ar, ac, r, c);
  bool get single => ar == fr && ac == fc;

  @override
  bool operator ==(Object other) =>
      other is DataSel &&
      other.ar == ar &&
      other.ac == ac &&
      other.fr == fr &&
      other.fc == fc;
  @override
  int get hashCode => Object.hash(ar, ac, fr, fc);
}

/// DataOutline is a range drawn round on the grid: a view's, in its colour,
/// a chart's label and series columns each in its own.
@immutable
class DataOutline {
  final CellRange range;
  final Color colour;
  final Map<int, Color> columns;
  const DataOutline(this.range, this.colour, {this.columns = const {}});
}

/// DataGridLook is the grid's colours: Calc's paper, or the app's theme.
@immutable
class DataGridLook {
  final Color paper, line, head, headInk, ink, selection, edge, error;
  const DataGridLook(
      {required this.paper,
      required this.line,
      required this.head,
      required this.headInk,
      required this.ink,
      required this.selection,
      required this.edge,
      this.error = const Color(0xFFD0453A)});

  static const DataGridLook calc = DataGridLook(
      paper: Color(0xFFFCFCFA),
      line: Color(0xFFE2E4E8),
      head: Color(0xFFEEF0F3),
      headInk: Color(0xFF59606B),
      ink: Color(0xFF1D2127),
      selection: Color(0x2A2ED6A1),
      edge: Color(0xFF1FB487));

  static DataGridLook theme(ColorScheme c) => DataGridLook(
      paper: c.surfaceContainerLowest,
      line: c.outlineVariant.withValues(alpha: 0.55),
      head: c.surfaceContainerHigh,
      headInk: c.onSurfaceVariant,
      ink: c.onSurface,
      selection: c.primary.withValues(alpha: 0.16),
      edge: c.primary);
}

class DataGrid extends StatefulWidget {
  final DataSheet sheet;
  final DataSel sel;
  final ValueChanged<DataSel> onSelect;
  final void Function(int r, int c, String text) onEdit;
  final void Function(int r, int c, List<List<String>> rows) onPaste;
  final ValueChanged<CellRange> onClear;

  /// onFill is the fill handle -- the square at the selection's corner --
  /// dragged down or across: the selection carried on over [to] (a series
  /// continued, a formula copied), as in Calc.
  final void Function(CellRange from, CellRange to)? onFill;
  final List<DataOutline> outlines;
  final DataGridLook look;
  final VoidCallback? onUndo, onRedo;
  final FocusNode? focusNode;

  /// shown is what a cell shows, where it differs from what was typed.
  final String Function(int r, int c)? shown;

  /// flash is cells to light up: what a refresh changed.
  final Set<(int, int)> flash;

  /// images is where a cell naming a picture gets it, to show the picture
  /// rather than its name (as the tables showing the sheet do).
  final CanvasImageStore? images;

  /// onResize gives the grid a new size, rows by columns: the − and + at
  /// the end of the row numbers and of the column letters (Ken, 2026-11-16),
  /// with a box for how many. None, and the grid has no such ends.
  final void Function(int rows, int columns)? onResize;

  /// onRowsOrColumns puts [n] rows (or columns) in before [at], or takes
  /// them out from it: the menu a row number or column letter opens on a
  /// right-click.
  final void Function(
      {required bool rows,
      required bool insert,
      required int at,
      required int n})? onRowsOrColumns;

  const DataGrid({
    required this.sheet,
    required this.sel,
    required this.onSelect,
    required this.onEdit,
    required this.onPaste,
    required this.onClear,
    this.onFill,
    this.outlines = const [],
    this.look = DataGridLook.calc,
    this.onUndo,
    this.onRedo,
    this.focusNode,
    this.shown,
    this.images,
    this.flash = const {},
    this.onResize,
    this.onRowsOrColumns,
    super.key,
  });

  @override
  State<DataGrid> createState() => DataGridState();
}

class DataGridState extends State<DataGrid> {
  final ScrollController _v = ScrollController(), _h = ScrollController();
  late FocusNode _focus;
  bool _ownFocus = false;
  final TextEditingController _edit = TextEditingController();
  final FocusNode _editFocus = FocusNode();

  /// _editing is the cell being typed into, or null.
  (int, int)? _editing;
  DateTime _lastDown = DateTime.fromMillisecondsSinceEpoch(0);
  (int, int)? _lastDownAt;
  bool _dragging = false;

  /// _fillTo is where the fill handle has been dragged to: the cells it
  /// would fill, or null when it isn't being dragged.
  CellRange? _fillTo;
  bool _filling = false;

  /// _now is the selection as of the last key or pointer: several keys can
  /// come between two frames, each going on from where the last left it.
  late DataSel _now = widget.sel;

  int get _rows => widget.sheet.shownRows;
  int get _cols => widget.sheet.shownColumns;

  /// How many rows and columns the − and + at the grid's ends take off or
  /// put on.
  final TextEditingController _rowStep = TextEditingController(text: "1");
  final TextEditingController _columnStep = TextEditingController(text: "1");
  String _shown(int r, int c) =>
      widget.shown?.call(r, c) ?? sheetShown(widget.sheet, r, c);

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _ownFocus = widget.focusNode == null;
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus && _editing != null) _commit();
    });
  }

  @override
  void didUpdateWidget(DataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _now = widget.sel;
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    if (_ownFocus) _focus.dispose();
    _edit.dispose();
    _editFocus.dispose();
    _rowStep.dispose();
    _columnStep.dispose();
    super.dispose();
  }

  /// editing is whether a cell is being typed into.
  bool get editing => _editing != null;

  /// startEdit types into the selection's anchor: from [initial] (a key
  /// pressed), or what was typed there before.
  void startEdit([String? initial]) {
    var r = _now.ar, c = _now.ac;
    setState(() {
      _editing = (r, c);
      _edit.text = initial ?? widget.sheet.raw(r, c);
      _edit.selection = TextSelection.collapsed(offset: _edit.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _commit({int dr = 0, int dc = 0}) {
    var at = _editing;
    if (at == null) return;
    _editing = null;
    var text = _edit.text;
    if (text != widget.sheet.raw(at.$1, at.$2)) {
      widget.onEdit(at.$1, at.$2, text);
    }
    setState(() {});
    if (dr != 0 || dc != 0) _select(DataSel.at(at.$1 + dr, at.$2 + dc));
    _focus.requestFocus();
  }

  void _cancel() {
    setState(() => _editing = null);
    _focus.requestFocus();
  }

  /// _select picks [s] -- and, unless [stay], scrolls to the cell it was
  /// moved to. A whole row or column picked by its header stays where the
  /// view is, as in Calc (it went to the last row).
  void _select(DataSel s, {bool stay = false}) {
    var clamp = DataSel(s.ar.clamp(0, _rows - 1), s.ac.clamp(0, _cols - 1),
        s.fr.clamp(0, _rows - 1), s.fc.clamp(0, _cols - 1));
    _now = clamp;
    widget.onSelect(clamp);
    if (!stay) _reveal(clamp.fr, clamp.fc);
  }

  /// _reveal scrolls cell [r], [c] into view.
  void _reveal(int r, int c) {
    if (!_v.hasClients || !_h.hasClients) return;
    var top = r * dataRowHeight, bottom = top + dataRowHeight;
    var left = c * dataColumnWidth, right = left + dataColumnWidth;
    var vp = _v.position, hp = _h.position;
    if (top < vp.pixels) {
      _v.jumpTo(top);
    } else if (bottom > vp.pixels + vp.viewportDimension) {
      _v.jumpTo(math.min(vp.maxScrollExtent, bottom - vp.viewportDimension));
    }
    if (left < hp.pixels) {
      _h.jumpTo(left);
    } else if (right > hp.pixels + hp.viewportDimension) {
      _h.jumpTo(math.min(hp.maxScrollExtent, right - hp.viewportDimension));
    }
  }

  (int, int) _cellAt(Offset local) => (
        ((local.dy + (_v.hasClients ? _v.offset : 0)) / dataRowHeight)
            .floor()
            .clamp(0, _rows - 1),
        ((local.dx + (_h.hasClients ? _h.offset : 0)) / dataColumnWidth)
            .floor()
            .clamp(0, _cols - 1),
      );

  /// _handle is the fill handle's square, where the view is scrolled to.
  Rect _handle() {
    var g = _now.range;
    var x = (g.c1 + 1) * dataColumnWidth - (_h.hasClients ? _h.offset : 0);
    var y = (g.r1 + 1) * dataRowHeight - (_v.hasClients ? _v.offset : 0);
    return Rect.fromCenter(center: Offset(x, y), width: 12, height: 12);
  }

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.trackpad) return;
    if (_editing != null) _commit();
    _focus.requestFocus();
    if (widget.onFill != null && _handle().contains(e.localPosition)) {
      _filling = true;
      _fillTo = null;
      return;
    }
    var (r, c) = _cellAt(e.localPosition);
    var now = DateTime.now();
    var again = _lastDownAt == (r, c) &&
        now.difference(_lastDown) < const Duration(milliseconds: 400);
    _lastDown = now;
    _lastDownAt = (r, c);
    if (HardwareKeyboard.instance.isShiftPressed) {
      _select(_now.extendedTo(r, c));
    } else {
      _select(DataSel.at(r, c));
    }
    _dragging = true;
    if (again) startEdit();
  }

  void _move(PointerMoveEvent e) {
    if (_filling) {
      var (r, c) = _cellAt(e.localPosition);
      var g = _now.range;
      CellRange? to;
      // Down or across, whichever it was dragged further.
      if (r > g.r1 &&
          (r - g.r1) * dataRowHeight >= (c - g.c1) * dataColumnWidth) {
        to = CellRange(g.r1 + 1, g.c0, r, g.c1);
      } else if (c > g.c1) {
        to = CellRange(g.r0, g.c1 + 1, g.r1, c);
      }
      if (to != _fillTo) setState(() => _fillTo = to);
      return;
    }
    if (!_dragging || _editing != null) return;
    var (r, c) = _cellAt(e.localPosition);
    if (r != _now.fr || c != _now.fc) {
      _select(_now.extendedTo(r, c));
    }
  }

  void _up() {
    _dragging = false;
    if (!_filling) return;
    _filling = false;
    var to = _fillTo;
    setState(() => _fillTo = null);
    if (to == null) return;
    var from = _now.range;
    widget.onFill?.call(from, to);
    _select(DataSel(
        from.r0, from.c0, math.max(from.r1, to.r1), math.max(from.c1, to.c1)));
  }

  void _headerDown(PointerDownEvent e, {required bool column}) {
    var local = e.localPosition;
    if (_editing != null) _commit();
    _focus.requestFocus();
    if (e.buttons & kSecondaryMouseButton != 0) {
      _headerMenu(e.position, local, column: column);
      return;
    }
    if (column) {
      var c = ((local.dx + _h.offset) / dataColumnWidth)
          .floor()
          .clamp(0, _cols - 1);
      var shift = HardwareKeyboard.instance.isShiftPressed;
      _select(
          shift
              ? DataSel(0, _now.ac, _rows - 1, c)
              : DataSel(0, c, _rows - 1, c),
          stay: true);
    } else {
      var r =
          ((local.dy + _v.offset) / dataRowHeight).floor().clamp(0, _rows - 1);
      var shift = HardwareKeyboard.instance.isShiftPressed;
      _select(
          shift
              ? DataSel(_now.ar, 0, r, _cols - 1)
              : DataSel(r, 0, r, _cols - 1),
          stay: true);
    }
  }

  /// _headerMenu is the right-click menu of a row number or column letter:
  /// rows (or columns) put in either side of those picked, or taken out --
  /// the row it was opened on picked first, unless it is among them.
  Future<void> _headerMenu(Offset global, Offset local,
      {required bool column}) async {
    var on = onRowsOrColumns;
    if (on == null) return;
    var g = _now.range;
    int at, n;
    if (column) {
      var c = ((local.dx + _h.offset) / dataColumnWidth)
          .floor()
          .clamp(0, _cols - 1);
      var whole = g.r0 == 0 && g.r1 >= _rows - 1 && c >= g.c0 && c <= g.c1;
      if (!whole) _select(DataSel(0, c, _rows - 1, c), stay: true);
      at = whole ? g.c0 : c;
      n = whole ? g.cols : 1;
    } else {
      var r =
          ((local.dy + _v.offset) / dataRowHeight).floor().clamp(0, _rows - 1);
      var whole = g.c0 == 0 && g.c1 >= _cols - 1 && r >= g.r0 && r <= g.r1;
      if (!whole) _select(DataSel(r, 0, r, _cols - 1), stay: true);
      at = whole ? g.r0 : r;
      n = whole ? g.rows : 1;
    }
    var noun = column
        ? (n == 1 ? "column" : "$n columns")
        : (n == 1 ? "row" : "$n rows");
    var choice = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: [
        PopupMenuItem(
            key: const ValueKey("dataGridMenu-before"),
            value: "before",
            child: Text("Insert $noun ${column ? "left" : "above"}")),
        PopupMenuItem(
            key: const ValueKey("dataGridMenu-after"),
            value: "after",
            child: Text("Insert $noun ${column ? "right" : "below"}")),
        PopupMenuItem(
            key: const ValueKey("dataGridMenu-delete"),
            value: "delete",
            child: Text("Delete $noun")),
      ],
    );
    if (choice == null || !mounted) return;
    on(
        rows: !column,
        insert: choice != "delete",
        at: choice == "after" ? at + n : at,
        n: n);
    _focus.requestFocus();
  }

  /// onRowsOrColumns is the grid's own, or null.
  void Function(
      {required bool rows,
      required bool insert,
      required int at,
      required int n})? get onRowsOrColumns => widget.onRowsOrColumns;

  /// _step is how many the − and + at an end take off or put on: what is
  /// typed in its box, 1 when that isn't a number.
  int _step(TextEditingController box) =>
      math.max(1, int.tryParse(box.text.trim()) ?? 1);

  void _resize({int rows = 0, int columns = 0}) {
    var on = widget.onResize;
    if (on == null) return;
    on(math.max(1, _rows + rows * _step(_rowStep)),
        math.max(1, _cols + columns * _step(_columnStep)));
    _focus.requestFocus();
  }

  /// _ends is the − [n] + of the grid's last row ([rows]) or column.
  Widget _ends({required bool rows}) {
    var look = widget.look;
    var noun = rows ? "rows" : "columns";
    Widget button(String key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
                width: 22,
                height: 22,
                child: Icon(icon, size: 16, color: look.headInk)),
          ),
        );
    var box = SizedBox(
      width: 38,
      height: 20,
      child: TextField(
        key: ValueKey("dataGrid${rows ? "Row" : "Column"}Step"),
        controller: rows ? _rowStep : _columnStep,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 12, color: look.ink),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          filled: true,
          fillColor: look.paper,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: look.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: look.line)),
        ),
        onSubmitted: (_) => _resize(rows: rows ? 1 : 0, columns: rows ? 0 : 1),
      ),
    );
    var less = button(
        "dataGrid${rows ? "Rows" : "Columns"}Less",
        Icons.remove,
        "Take $noun off the end",
        () => _resize(rows: rows ? -1 : 0, columns: rows ? 0 : -1));
    var more = button(
        "dataGrid${rows ? "Rows" : "Columns"}More",
        Icons.add,
        "More $noun at the end",
        () => _resize(rows: rows ? 1 : 0, columns: rows ? 0 : 1));
    // Drawn as the grid is, at its own size, whatever the app's text size.
    return MediaQuery.withNoTextScaling(
      child: Material(
        color: look.head,
        child: rows
            ? Row(children: [
                SizedBox(
                    width: dataHeaderWidth,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [less, more])),
                const SizedBox(width: 6),
                box,
                const SizedBox(width: 6),
                Text(noun, style: TextStyle(fontSize: 12, color: look.headInk)),
              ])
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                less,
                const SizedBox(width: 2),
                box,
                const SizedBox(width: 2),
                more,
              ]),
      ),
    );
  }

  /// copyText is the selection as Calc and Excel take it: rows of cells
  /// apart by tabs, a line apiece.
  String copyText() {
    var g = _now.range;
    var used = widget.sheet.used;
    var r1 = math.min(g.r1, used.r1), c1 = math.min(g.c1, used.c1);
    return [
      for (var r = g.r0; r <= r1; r++)
        [for (var c = g.c0; c <= c1; c++) _shown(r, c)].join("\t"),
    ].join("\n");
  }

  Future<void> _paste() async {
    var data = await Clipboard.getData(Clipboard.kTextPlain);
    var text = data?.text;
    if (text == null || text.isEmpty) return;
    pasteText(text);
  }

  /// pasteText puts [text] -- tab-separated, or comma-separated where there
  /// is no tab -- in at the selection.
  void pasteText(String text) {
    var lines =
        text.replaceAll("\r\n", "\n").replaceAll("\r", "\n").split("\n");
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    var rows = text.contains("\t")
        ? [for (var l in lines) l.split("\t")]
        : splitTable(lines.join("\n"));
    if (rows.isEmpty) return;
    var g = _now.range;
    widget.onPaste(g.r0, g.c0, rows);
    var w = rows.fold(1, (n, r) => math.max(n, r.length));
    _now = DataSel(g.r0, g.c0, g.r0 + rows.length - 1, g.c0 + w - 1);
    widget.onSelect(_now);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_editing != null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var keys = HardwareKeyboard.instance;
    var mod = keys.isMetaPressed || keys.isControlPressed;
    var shift = keys.isShiftPressed;
    var s = _now;
    var k = event.logicalKey;
    (int, int)? step = switch (k) {
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      LogicalKeyboardKey.arrowLeft => (0, -1),
      LogicalKeyboardKey.arrowRight => (0, 1),
      _ => null,
    };
    if (step != null) {
      _select(shift
          ? s.extendedTo(s.fr + step.$1, s.fc + step.$2)
          : DataSel.at(s.ar + step.$1, s.ac + step.$2));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _select(DataSel.at(s.ar + (shift ? -1 : 1), s.ac));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab) {
      _select(DataSel.at(s.ar, s.ac + (shift ? -1 : 1)));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f2) {
      startEdit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      widget.onClear(s.range);
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyZ) {
      shift ? widget.onRedo?.call() : widget.onUndo?.call();
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyY) {
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }
    if (mod && (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyX)) {
      Clipboard.setData(ClipboardData(text: copyText()));
      if (k == LogicalKeyboardKey.keyX) widget.onClear(s.range);
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    if (mod && k == LogicalKeyboardKey.keyA) {
      var used = widget.sheet.used;
      _select(DataSel(0, 0, used.r1, used.c1));
      return KeyEventResult.handled;
    }
    var ch = event.character;
    if (!mod && ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
      startEdit(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _editKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    var k = event.logicalKey;
    var shift = HardwareKeyboard.instance.isShiftPressed;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _commit(dr: shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab) {
      _commit(dc: shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    var look = widget.look;
    var rows = _rows, cols = _cols;
    var ends = widget.onResize != null;
    var scrolled = Listenable.merge([_v, _h]);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: ColoredBox(
        color: look.paper,
        child: Column(children: [
          SizedBox(
            height: dataRowHeight,
            child: Row(children: [
              Container(
                width: dataHeaderWidth,
                decoration: BoxDecoration(
                    color: look.head,
                    border: Border(
                        right: BorderSide(color: look.line),
                        bottom: BorderSide(color: look.line))),
              ),
              Expanded(
                child: ClipRect(
                  child: Stack(children: [
                    Positioned.fill(
                      child: Listener(
                        onPointerDown: (e) => _headerDown(e, column: true),
                        child: CustomPaint(
                          key: const ValueKey("dataGridColumns"),
                          size: Size.infinite,
                          painter: _Headers(
                              look: look,
                              scroll: _h,
                              columns: true,
                              count: cols,
                              from: widget.sel.range.c0,
                              to: widget.sel.range.c1),
                        ),
                      ),
                    ),
                    if (ends)
                      AnimatedBuilder(
                        animation: _h,
                        builder: (context, child) => Positioned(
                            key: const ValueKey("dataGridColumnEnds"),
                            left: cols * dataColumnWidth -
                                (_h.hasClients ? _h.offset : 0),
                            top: 0,
                            bottom: 0,
                            width: dataColumnWidth,
                            child: child!),
                        child: _ends(rows: false),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ClipRect(
              child: Stack(children: [
                Positioned.fill(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: dataHeaderWidth,
                          child: ClipRect(
                            child: Listener(
                              onPointerDown: (e) =>
                                  _headerDown(e, column: false),
                              child: CustomPaint(
                                key: const ValueKey("dataGridRows"),
                                size: Size.infinite,
                                painter: _Headers(
                                    look: look,
                                    scroll: _v,
                                    columns: false,
                                    count: rows,
                                    from: widget.sel.range.r0,
                                    to: widget.sel.range.r1),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: Stack(children: [
                              Positioned.fill(
                                child: Scrollbar(
                                  controller: _v,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _v,
                                    child: Scrollbar(
                                      controller: _h,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _h,
                                        scrollDirection: Axis.horizontal,
                                        // Room past the last row and column for
                                        // their ends.
                                        child: SizedBox(
                                            width: (cols + (ends ? 1 : 0)) *
                                                dataColumnWidth,
                                            height: (rows + (ends ? 1.5 : 0)) *
                                                dataRowHeight),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    key: const ValueKey("dataGridCells"),
                                    painter: _Cells(
                                      sheet: widget.sheet,
                                      shown: _shown,
                                      sel: widget.sel,
                                      outlines: widget.outlines,
                                      look: look,
                                      v: _v,
                                      h: _h,
                                      repaint: widget.images == null
                                          ? scrolled
                                          : Listenable.merge(
                                              [scrolled, widget.images]),
                                      images: widget.images,
                                      flash: widget.flash,
                                      editing: _editing,
                                      fillTo: _fillTo,
                                      handle: widget.onFill != null,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Listener(
                                  key: const ValueKey("dataGridPointer"),
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _down,
                                  onPointerMove: _move,
                                  onPointerUp: (_) => _up(),
                                  onPointerCancel: (_) {
                                    _dragging = false;
                                    _filling = false;
                                    setState(() => _fillTo = null);
                                  },
                                ),
                              ),
                              if (_editing case (var r, var c))
                                AnimatedBuilder(
                                  animation: scrolled,
                                  builder: (context, _) => Positioned(
                                    left: c * dataColumnWidth - _h.offset,
                                    top: r * dataRowHeight - _v.offset,
                                    height: dataRowHeight,
                                    width: math.max(dataColumnWidth * 1.6, 160),
                                    child: Focus(
                                      onKeyEvent: _editKey,
                                      skipTraversal: true,
                                      child: Material(
                                        color: look.paper,
                                        child: TextField(
                                          key: const ValueKey("dataGridEditor"),
                                          controller: _edit,
                                          focusNode: _editFocus,
                                          style: TextStyle(
                                              fontSize: 13, color: look.ink),
                                          cursorColor: look.edge,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 6),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.zero,
                                                borderSide: BorderSide(
                                                    color: look.edge,
                                                    width: 2)),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.zero,
                                                borderSide: BorderSide(
                                                    color: look.edge,
                                                    width: 2)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ]),
                ),
                if (ends)
                  AnimatedBuilder(
                    animation: _v,
                    builder: (context, child) => Positioned(
                        key: const ValueKey("dataGridRowEnds"),
                        left: 0,
                        right: 0,
                        top: rows * dataRowHeight -
                            (_v.hasClients ? _v.offset : 0),
                        height: dataRowHeight,
                        child: child!),
                    child: _ends(rows: true),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// _Headers paints the column letters or the row numbers in view, those
/// of the selection lit.
class _Headers extends CustomPainter {
  final DataGridLook look;
  final ScrollController scroll;
  final bool columns;
  final int from, to;

  /// count is how many the grid has: none drawn past them.
  final int count;
  _Headers(
      {required this.look,
      required this.scroll,
      required this.columns,
      required this.count,
      required this.from,
      required this.to})
      : super(repaint: scroll);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = look.head);
    var offset = scroll.hasClients ? scroll.offset : 0.0;
    var step = columns ? dataColumnWidth : dataRowHeight;
    var first = math.max(0, (offset / step).floor());
    var last = math.min(count - 1,
        ((offset + (columns ? size.width : size.height)) / step).ceil());
    var line = Paint()..color = look.line;
    for (var i = first; i <= last; i++) {
      var at = i * step - offset;
      var cell = columns
          ? Rect.fromLTWH(at, 0, step, size.height)
          : Rect.fromLTWH(0, at, size.width, step);
      if (i >= from && i <= to) {
        canvas.drawRect(cell, Paint()..color = look.selection);
      }
      var tp = TextPainter(
          text: TextSpan(
              text: columns ? columnName(i) : "${i + 1}",
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: i >= from && i <= to ? look.ink : look.headInk)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
      if (columns) {
        canvas.drawRect(Rect.fromLTWH(cell.right - 1, 0, 1, size.height), line);
      } else {
        canvas.drawRect(Rect.fromLTWH(0, cell.bottom - 1, size.width, 1), line);
      }
    }
    if (columns) {
      canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), line);
    } else {
      canvas.drawRect(Rect.fromLTWH(size.width - 1, 0, 1, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_Headers old) =>
      old.from != from ||
      old.to != to ||
      old.count != count ||
      old.look != look;
}

/// _Cells paints the cells in view: what each shows (numbers to the right),
/// the views' ranges, and the selection.
class _Cells extends CustomPainter {
  final DataSheet sheet;
  final String Function(int r, int c) shown;
  final DataSel sel;
  final List<DataOutline> outlines;
  final DataGridLook look;
  final ScrollController v, h;
  final (int, int)? editing;
  final CellRange? fillTo;
  final bool handle;
  final CanvasImageStore? images;
  final Set<(int, int)> flash;
  _Cells(
      {required this.sheet,
      required this.shown,
      required this.sel,
      required this.outlines,
      required this.look,
      required this.v,
      required this.h,
      required Listenable repaint,
      required this.editing,
      this.fillTo,
      this.images,
      this.flash = const {},
      this.handle = false})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    var dy = v.hasClients ? v.offset : 0.0, dx = h.hasClients ? h.offset : 0.0;
    // From the first row and column even scrolled past them (a bounce at
    // the top or left edge gives a negative offset).
    var r0 = math.max(0, (dy / dataRowHeight).floor());
    var c0 = math.max(0, (dx / dataColumnWidth).floor());
    // No further than the grid's last row and column.
    var r1 = math.min(
        sheet.shownRows - 1, ((dy + size.height) / dataRowHeight).ceil());
    var c1 = math.min(
        sheet.shownColumns - 1, ((dx + size.width) / dataColumnWidth).ceil());
    var bottom = math.min(size.height, sheet.shownRows * dataRowHeight - dy);
    var right = math.min(size.width, sheet.shownColumns * dataColumnWidth - dx);
    Rect cell(int r, int c) => Rect.fromLTWH(c * dataColumnWidth - dx,
        r * dataRowHeight - dy, dataColumnWidth, dataRowHeight);
    Rect block(CellRange g) => Rect.fromLTRB(cell(g.r0, g.c0).left,
        cell(g.r0, g.c0).top, cell(g.r1, g.c1).right, cell(g.r1, g.c1).bottom);

    // Chart columns tinted under everything.
    for (var o in outlines) {
      for (var MapEntry(key: p, value: colour) in o.columns.entries) {
        var col = o.range.c0 + p;
        if (col < c0 || col > c1) continue;
        canvas.drawRect(block(CellRange(o.range.r0 + 1, col, o.range.r1, col)),
            Paint()..color = colour.withValues(alpha: 0.10));
      }
    }
    var g = sel.range;
    canvas.drawRect(block(g), Paint()..color = look.selection);
    var lit = Paint()..color = const Color(0x592ED6A1);
    for (var (r, c) in flash) {
      if (r < r0 || r > r1 || c < c0 || c > c1) continue;
      canvas.drawRect(cell(r, c).deflate(1), lit);
    }

    var line = Paint()..color = look.line;
    for (var r = r0; r <= r1; r++) {
      var y = (r + 1) * dataRowHeight - dy - 1;
      canvas.drawRect(Rect.fromLTWH(0, y, math.max(0, right), 1), line);
    }
    for (var c = c0; c <= c1; c++) {
      var x = (c + 1) * dataColumnWidth - dx - 1;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, math.max(0, bottom)), line);
    }

    var rows = math.min(r1, sheet.rowCount - 1);
    for (var r = r0; r <= rows; r++) {
      var width = sheet.cells[r].length;
      for (var c = c0; c <= math.min(c1, width - 1); c++) {
        if (editing == (r, c)) continue;
        // Its colour rules, as the tables showing it draw them.
        if (sheetLook(sheet, r, c) case var sl?) {
          var box = cell(r, c).deflate(1);
          if (sl.fill case var fill?) {
            canvas.drawRect(box, Paint()..color = fill);
          }
          if (sl.bar case var bar? when bar > 0) {
            canvas.drawRect(
                Rect.fromLTWH(box.left + 2, box.top + 4, (box.width - 4) * bar,
                    box.height - 8),
                Paint()..color = sl.barColour.withValues(alpha: 0.45));
          }
        }
        var text = shown(r, c);
        if (text.isEmpty) continue;
        // A picture: drawn at the cell's left, square, rather than its name.
        var asset = TableElement.pictureIn(text);
        var store = images;
        if (asset != null && store != null) {
          var box = cell(r, c);
          var side = box.height - 6;
          if (paintCellPicture(canvas, store, asset,
              Rect.fromLTWH(box.left + 6, box.top + 3, side, side))) {
            continue;
          }
        }
        // Numbers to the right and errors in red, by what the cell is
        // worth, not how it is written ("\$14.20" is a number).
        var value = sheetValue(sheet, r, c);
        var number = value is double;
        var bad = value is SheetError;
        var tp = TextPainter(
            text: TextSpan(
                text: text,
                style: TextStyle(
                    fontSize: 13,
                    color: bad ? look.error : look.ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            maxLines: 1,
            ellipsis: "…",
            textDirection: TextDirection.ltr)
          ..layout(maxWidth: dataColumnWidth - 12);
        var box = cell(r, c);
        var x = number ? box.right - 6 - tp.width : box.left + 6;
        tp.paint(canvas, Offset(x, box.center.dy - tp.height / 2));
        tp.dispose();
      }
    }

    for (var o in outlines) {
      var b = block(o.range).deflate(1);
      canvas.drawRect(
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = o.colour);
      for (var MapEntry(key: p, value: colour) in o.columns.entries) {
        var col = o.range.c0 + p;
        canvas.drawRect(
            block(CellRange(o.range.r0, col, o.range.r1, col)).deflate(1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = colour);
      }
    }
    canvas.drawRect(
        block(g).deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = look.edge);
    if (!sel.single) {
      canvas.drawRect(
          cell(sel.ar, sel.ac).deflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = look.edge);
    }
    // Where the fill handle would fill, and the handle itself.
    if (fillTo case var f?) {
      canvas.drawRect(
          block(f).deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = look.edge.withValues(alpha: 0.7));
    }
    if (handle && editing == null) {
      var corner = block(g).bottomRight;
      canvas.drawRect(Rect.fromCenter(center: corner, width: 7, height: 7),
          Paint()..color = look.paper);
      canvas.drawRect(Rect.fromCenter(center: corner, width: 5, height: 5),
          Paint()..color = look.edge);
    }
  }

  @override
  bool shouldRepaint(_Cells old) =>
      !identical(old.sheet, sheet) ||
      old.sel != sel ||
      old.look != look ||
      old.editing != editing ||
      old.fillTo != fillTo ||
      !identical(old.flash, flash) ||
      old.outlines.length != outlines.length ||
      !_sameOutlines(old.outlines, outlines);

  static bool _sameOutlines(List<DataOutline> a, List<DataOutline> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].range != b[i].range || a[i].colour != b[i].colour) return false;
      if (a[i].columns.length != b[i].columns.length) return false;
      for (var MapEntry(:key, :value) in a[i].columns.entries) {
        if (b[i].columns[key] != value) return false;
      }
    }
    return true;
  }
}

import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
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
  final List<DataOutline> outlines;
  final DataGridLook look;
  final VoidCallback? onUndo, onRedo;
  final FocusNode? focusNode;

  /// shown is what a cell shows, where it differs from what was typed.
  final String Function(int r, int c)? shown;

  const DataGrid({
    required this.sheet,
    required this.sel,
    required this.onSelect,
    required this.onEdit,
    required this.onPaste,
    required this.onClear,
    this.outlines = const [],
    this.look = DataGridLook.calc,
    this.onUndo,
    this.onRedo,
    this.focusNode,
    this.shown,
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

  /// _now is the selection as of the last key or pointer: several keys can
  /// come between two frames, each going on from where the last left it.
  late DataSel _now = widget.sel;

  int get _rows => math.max(200, widget.sheet.rowCount + 60);
  int get _cols => math.max(26, widget.sheet.columnCount + 10);
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
  void didUpdateWidget(DataGrid old) {
    super.didUpdateWidget(old);
    _now = widget.sel;
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    if (_ownFocus) _focus.dispose();
    _edit.dispose();
    _editFocus.dispose();
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

  void _select(DataSel s) {
    var clamp = DataSel(s.ar.clamp(0, _rows - 1), s.ac.clamp(0, _cols - 1),
        s.fr.clamp(0, _rows - 1), s.fc.clamp(0, _cols - 1));
    _now = clamp;
    widget.onSelect(clamp);
    _reveal(clamp.fr, clamp.fc);
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

  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.trackpad) return;
    if (_editing != null) _commit();
    _focus.requestFocus();
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
    if (!_dragging || _editing != null) return;
    var (r, c) = _cellAt(e.localPosition);
    if (r != _now.fr || c != _now.fc) {
      _select(_now.extendedTo(r, c));
    }
  }

  void _headerDown(Offset local, {required bool column}) {
    if (_editing != null) _commit();
    _focus.requestFocus();
    if (column) {
      var c = ((local.dx + _h.offset) / dataColumnWidth).floor();
      var shift = HardwareKeyboard.instance.isShiftPressed;
      _select(shift
          ? DataSel(0, _now.ac, _rows - 1, c)
          : DataSel(0, c, _rows - 1, c));
    } else {
      var r = ((local.dy + _v.offset) / dataRowHeight).floor();
      var shift = HardwareKeyboard.instance.isShiftPressed;
      _select(shift
          ? DataSel(_now.ar, 0, r, _cols - 1)
          : DataSel(r, 0, r, _cols - 1));
    }
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
                  child: Listener(
                    onPointerDown: (e) =>
                        _headerDown(e.localPosition, column: true),
                    child: CustomPaint(
                      key: const ValueKey("dataGridColumns"),
                      size: Size.infinite,
                      painter: _Headers(
                          look: look,
                          scroll: _h,
                          columns: true,
                          from: widget.sel.range.c0,
                          to: widget.sel.range.c1),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: dataHeaderWidth,
                child: ClipRect(
                  child: Listener(
                    onPointerDown: (e) =>
                        _headerDown(e.localPosition, column: false),
                    child: CustomPaint(
                      key: const ValueKey("dataGridRows"),
                      size: Size.infinite,
                      painter: _Headers(
                          look: look,
                          scroll: _v,
                          columns: false,
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
                              child: SizedBox(
                                  width: cols * dataColumnWidth,
                                  height: rows * dataRowHeight),
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
                            repaint: scrolled,
                            editing: _editing,
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
                        onPointerUp: (_) => _dragging = false,
                        onPointerCancel: (_) => _dragging = false,
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
                                style: TextStyle(fontSize: 13, color: look.ink),
                                cursorColor: look.edge,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 6),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(
                                          color: look.edge, width: 2)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.zero,
                                      borderSide: BorderSide(
                                          color: look.edge, width: 2)),
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
  _Headers(
      {required this.look,
      required this.scroll,
      required this.columns,
      required this.from,
      required this.to})
      : super(repaint: scroll);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = look.head);
    var offset = scroll.hasClients ? scroll.offset : 0.0;
    var step = columns ? dataColumnWidth : dataRowHeight;
    var first = (offset / step).floor();
    var last = ((offset + (columns ? size.width : size.height)) / step).ceil();
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
      old.from != from || old.to != to || old.look != look;
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
  _Cells(
      {required this.sheet,
      required this.shown,
      required this.sel,
      required this.outlines,
      required this.look,
      required this.v,
      required this.h,
      required Listenable repaint,
      required this.editing})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    var dy = v.hasClients ? v.offset : 0.0, dx = h.hasClients ? h.offset : 0.0;
    var r0 = (dy / dataRowHeight).floor(), c0 = (dx / dataColumnWidth).floor();
    var r1 = ((dy + size.height) / dataRowHeight).ceil();
    var c1 = ((dx + size.width) / dataColumnWidth).ceil();
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

    var line = Paint()..color = look.line;
    for (var r = r0; r <= r1; r++) {
      var y = (r + 1) * dataRowHeight - dy - 1;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    for (var c = c0; c <= c1; c++) {
      var x = (c + 1) * dataColumnWidth - dx - 1;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), line);
    }

    var rows = math.min(r1, sheet.rowCount - 1);
    for (var r = r0; r <= rows; r++) {
      var width = sheet.cells[r].length;
      for (var c = c0; c <= math.min(c1, width - 1); c++) {
        if (editing == (r, c)) continue;
        var text = shown(r, c);
        if (text.isEmpty) continue;
        var number = cellNumber(text) != null;
        var bad = text.startsWith("#") && text.endsWith("!");
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
  }

  @override
  bool shouldRepaint(_Cells old) =>
      !identical(old.sheet, sheet) ||
      old.sel != sel ||
      old.look != look ||
      old.editing != editing ||
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

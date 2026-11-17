part of 'data_table_design.dart';

// The stage the table is drawn on, and pointing at its parts. Part of
// _TableDesignState: its fields, lifecycle and build are in
// data_table_design.dart.

extension _TableStage on _TableDesignState {
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

  /// _clicked is a stage click: shift on a row tab toggles that row; while
  /// pointing, what to style; otherwise the part, picked.
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
}

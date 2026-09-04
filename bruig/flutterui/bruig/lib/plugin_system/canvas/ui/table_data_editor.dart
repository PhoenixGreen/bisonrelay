import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// table_data_editor.dart is a table's cells, in either of the two forms
// anybody wants them in.
//
// The same arrangement as the chart's numbers next door, and deliberately the
// same: pasted text is the fast way in and a bad way to change one cell in the
// middle of sixty, and a reader who has learnt one of these should not have to
// learn the other. What differs is only what a cell holds -- words rather than
// numbers -- and that a table has no series, so its first row is a row like
// any other.
//
// It is as wide as the sidebar and as tall as it has been dragged, because a
// table crammed into a 280-pixel control with two visible lines is a table
// nobody can read.

const String _layoutKey = "canvasTableDataGrid";
const String _heightKey = "canvasTableDataHeight";

const double _minHeight = 70;
const double _maxHeight = 460;

class TableDataEditor extends StatefulWidget {
  final List<List<String>> rows;

  /// onChanged is a change to keep. The caller opens the undo step.
  final ValueChanged<List<List<String>>> onChanged;
  final VoidCallback onCommit;

  const TableDataEditor({
    required this.rows,
    required this.onChanged,
    required this.onCommit,
    super.key,
  });

  @override
  State<TableDataEditor> createState() => _TableDataEditorState();
}

class _TableDataEditorState extends State<TableDataEditor> {
  /// Static, for the reason the chart's are: this editor is rebuilt from
  /// scratch whenever the settings panel is, and a fresh State reads a stored
  /// preference asynchronously -- so a table dragged taller went back to its
  /// default height every time it was returned to.
  static bool? _rememberedGrid;
  static double? _rememberedHeight;

  late bool _grid = _rememberedGrid ?? false;
  late double _height = _rememberedHeight ?? 132;

  List<List<String>> get rows => widget.rows;

  int get columns => rows.fold(0, (n, r) => r.length > n ? r.length : n);

  @override
  void initState() {
    super.initState();
    if (_rememberedHeight == null || _rememberedGrid == null) _restore();
  }

  Future<void> _restore() async {
    var grid = await StorageManager.readData(_layoutKey);
    var height = await StorageManager.readData(_heightKey);
    if (grid is bool) _rememberedGrid = grid;
    if (height is num) {
      _rememberedHeight = height.toDouble().clamp(_minHeight, _maxHeight);
    }
    if (!mounted) return;
    setState(() {
      _grid = _rememberedGrid ?? _grid;
      _height = _rememberedHeight ?? _height;
    });
  }

  void _write(List<List<String>> next) {
    widget.onChanged(next);
    widget.onCommit();
  }

  /// _rectangular is [rows] with every row padded to the widest, which is what
  /// a grid needs to draw and what a paste routinely is not.
  List<List<String>> get _rectangular {
    var width = columns;
    return [
      for (var row in rows)
        [...row, for (var i = row.length; i < width; i++) ""],
    ];
  }

  void _withCell(int row, int col, String value) {
    var next = _rectangular;
    if (row < 0 || row >= next.length) return;
    next[row][col] = value;
    widget.onChanged(next);
  }

  void _addRow() {
    _write([..._rectangular, List.filled(columns == 0 ? 1 : columns, "")]);
  }

  void _addColumn() {
    var next = _rectangular;
    _write([
      for (var row in next) [...row, ""],
    ]);
  }

  void _removeRow(int row) {
    var next = _rectangular..removeAt(row);
    _write(next);
  }

  /// _moveRow and _moveColumn shuffle one along by [by].
  ///
  /// Buttons rather than dragging the rows about. A row added at the end and
  /// wanted second is one press away either way, and a drag inside a grid of
  /// text fields is a gesture that has to be told apart from selecting text
  /// in one of them.
  void _moveRow(int row, int by) {
    var next = _rectangular;
    var to = row + by;
    if (to < 0 || to >= next.length) return;
    var moved = next.removeAt(row);
    next.insert(to, moved);
    _write(next);
  }

  void _moveColumn(int col, int by) {
    var to = col + by;
    if (to < 0 || to >= columns) return;
    // Taken out and put back, which is the only ordering that is right in
    // both directions. Inserting first and then removing has to know whether
    // the insertion shifted the thing being removed, and getting that wrong
    // leaves the row exactly as it was -- a button that does nothing.
    _write([
      for (var row in _rectangular)
        [...row]
          ..removeAt(col)
          ..insert(to, row[col]),
    ]);
  }

  void _removeColumn(int col) {
    _write([
      for (var row in _rectangular) [...row]..removeAt(col),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var stacked = CanvasControlScope.isStacked(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          CanvasIconButton(
            icon: _grid ? Icons.notes : Icons.grid_on,
            tooltip: _grid
                ? "Edit the cells as pasted text"
                : "Edit the cells in a grid",
            active: _grid,
            onPressed: () {
              setState(() => _grid = !_grid);
              _rememberedGrid = _grid;
              StorageManager.saveData(_layoutKey, _grid);
            },
          ),
          CanvasIconButton(
            icon: Icons.add,
            tooltip: "Add a row",
            onPressed: _addRow,
          ),
          CanvasIconButton(
            icon: Icons.view_column_outlined,
            tooltip: "Add a column",
            onPressed: _addColumn,
          ),
        ]),
        SizedBox(
          width: stacked ? double.infinity : 280,
          height: _height,
          child: _grid ? _table(theme) : _raw(),
        ),
        _grip(theme),
      ],
    );
  }

  Widget _grip(ThemeNotifier theme) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() {
            _height = (_height + d.delta.dy).clamp(_minHeight, _maxHeight);
            _rememberedHeight = _height;
          }),
          onVerticalDragEnd: (_) => StorageManager.saveData(_heightKey, _height),
          onVerticalDragCancel: () =>
              StorageManager.saveData(_heightKey, _height),
          child: SizedBox(
            height: 11,
            child: Center(
              child: Container(
                height: 3,
                width: 34,
                decoration: BoxDecoration(
                  color: theme.colors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );

  /// _raw is the whole grid as one block, comma separated with quoting -- see
  /// joinTable.
  Widget _raw() => CanvasGridCell(
        value: TableElement(const ElementBase(id: ""), rows: rows).asText(),
        multiline: true,
        hint: "Team, Played, Points\nManchester City, 2, 6",
        onChanged: (text) => widget.onChanged(TableElement.parseRows(text)),
        onCommit: widget.onCommit,
      );

  Widget _table(ThemeNotifier theme) {
    if (rows.isEmpty) {
      return Center(
        child: Text("No rows yet",
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      );
    }

    const cellWidth = 92.0;
    var grid = _rectangular;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // A row of crosses over the columns, since a column is removed by
            // the column and not from a list of names somewhere else.
            Row(children: [
              for (var c = 0; c < columns; c++)
                SizedBox(
                  width: cellWidth + 4,
                  child: Row(children: [
                    CanvasIconButton(
                      icon: Icons.chevron_left,
                      tooltip: "Move this column left",
                      onPressed: c == 0 ? null : () => _moveColumn(c, -1),
                    ),
                    CanvasIconButton(
                      icon: Icons.chevron_right,
                      tooltip: "Move this column right",
                      onPressed:
                          c == columns - 1 ? null : () => _moveColumn(c, 1),
                    ),
                    CanvasIconButton(
                      icon: Icons.close,
                      tooltip: "Remove this column",
                      onPressed: () => _removeColumn(c),
                    ),
                  ]),
                ),
            ]),
            for (var r = 0; r < grid.length; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  for (var c = 0; c < columns; c++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: cellWidth,
                        child: CanvasGridCell(
                          value: grid[r][c],
                          dense: true,
                          onChanged: (v) => _withCell(r, c, v),
                          onCommit: widget.onCommit,
                        ),
                      ),
                    ),
                  CanvasIconButton(
                    icon: Icons.keyboard_arrow_up,
                    tooltip: "Move this row up",
                    onPressed: r == 0 ? null : () => _moveRow(r, -1),
                  ),
                  CanvasIconButton(
                    icon: Icons.keyboard_arrow_down,
                    tooltip: "Move this row down",
                    onPressed:
                        r == grid.length - 1 ? null : () => _moveRow(r, 1),
                  ),
                  CanvasIconButton(
                    icon: Icons.close,
                    tooltip: "Remove this row",
                    onPressed: () => _removeRow(r),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

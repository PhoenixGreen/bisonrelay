import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
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
  List<List<String>> get rows => widget.rows;

  int get columns => rows.fold(0, (n, r) => r.length > n ? r.length : n);

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
  Widget build(BuildContext context) => CanvasDataEditorShell(
        remember: "canvasTableData",
        gridTooltip: "Edit the cells in a grid",
        textTooltip: "Edit the cells as pasted text",
        toolbar: [
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
        ],
        text: (_) => _raw(),
        grid: (context) => _table(ThemeNotifier.of(context)),
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

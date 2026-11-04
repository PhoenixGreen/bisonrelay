import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// table_data_editor.dart is a table's cells, as a grid or as pasted text,
// arranged like the chart's numbers editor so one teaches the other. A table
// has no series, so its first row is a row like any other.

class TableDataEditor extends StatefulWidget {
  final List<List<String>> rows;

  /// elementId is which table this is, so the grid's height is kept for this
  /// one rather than for tables in general. See CanvasDataEditorShell.scope.
  final String elementId;

  /// onChanged is a change to keep. The caller opens the undo step.
  final ValueChanged<List<List<String>>> onChanged;
  final VoidCallback onCommit;

  /// names are what the cells of [namesColumn] are likely to hold, offered as
  /// somebody types (the coins a comparison can ask for, say). Empty for free
  /// text.
  final List<String> names;
  final int namesColumn;

  const TableDataEditor({
    required this.rows,
    required this.onChanged,
    required this.onCommit,
    this.elementId = "",
    this.names = const [],
    this.namesColumn = 0,
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

  /// _rectangular is [rows] with every row padded to the widest, as the grid
  /// needs and a paste often is not.
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

  /// _moveRow and _moveColumn shuffle one along by [by]: buttons rather than
  /// dragging, which a grid of text fields would confuse with selecting text.
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
    // Taken out and put back, which is right in both directions without
    // working out whether an insertion shifted the one being removed.
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

  // At the ordinary size inside a card: card-sized buttons overran the
  // columns.
  @override
  Widget build(BuildContext context) =>
      CanvasCards.none(Builder(builder: _build));

  Widget _build(BuildContext context) => CanvasDataEditorShell(
        remember: "canvasTableData",
        // Per table, for the same reason a chart's is per chart.
        scope: widget.elementId,
        // Tall enough for the rows, erring high: a row is about thirty and the
        // buttons along the foot about forty, and a little short brings the
        // scrollbar back.
        wanted: widget.rows.length * 32 + 48,
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
            // A row of crosses over the columns: a column is removed by the column.
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
                          // Only the column that names a row, and not its heading.
                          suggestions: c == widget.namesColumn && r > 0
                              ? widget.names
                              : const [],
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

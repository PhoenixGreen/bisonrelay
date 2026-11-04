import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/tabular_text.dart';

// table_sort.dart puts a table's rows in order: a column to sort on, more to
// break ties, and a first column of positions that stays put (a league table
// needs all three).
//
// The sort is applied, rewriting the rows once (one undo step), rather than a
// view the painter reads through: rows that reordered while a cell was typed
// into would be unusable, and cell colour rules are written against row
// numbers. The spec is kept so a refreshed table can be put back in order.

/// TableSortLevel is one column to order by, and which way.
class TableSortLevel {
  /// column is an index into the row, or -1 for "not set".
  final int column;

  /// descending is highest first, the default (what a league table wants).
  final bool descending;

  const TableSortLevel({this.column = -1, this.descending = true});

  bool get on => column >= 0;

  TableSortLevel copyWith({int? column, bool? descending}) => TableSortLevel(
        column: column ?? this.column,
        descending: descending ?? this.descending,
      );

  Map<String, dynamic> toJson() => {"c": column, "d": descending};

  factory TableSortLevel.fromJson(Map<String, dynamic> json) => TableSortLevel(
        column: jsonInt(json["c"], -1),
        descending: jsonBool(json["d"], true),
      );
}

/// TableSort is the whole order: up to three columns, and what to do about the
/// first one.
class TableSort {
  /// levels are tried in turn, so the second only decides the rows the first
  /// left equal. The settings offer three (points, goal difference, goals).
  final List<TableSortLevel> levels;

  /// pinFirstColumn keeps the first column's values where they are while the
  /// rest of each row moves, so a position column still reads 1, 2, 3.
  final bool pinFirstColumn;

  const TableSort({this.levels = const [], this.pinFirstColumn = true});

  bool get on => levels.any((l) => l.on);

  /// at is the level at [index], padded out so the settings panel can always
  /// show three.
  TableSortLevel at(int index) =>
      index < levels.length ? levels[index] : const TableSortLevel();

  TableSort withLevel(int index, TableSortLevel level) {
    var next = [
      for (var i = 0;
          i < (index + 1 > levels.length ? index + 1 : levels.length);
          i++)
        i == index ? level : at(i),
    ];
    return TableSort(levels: next, pinFirstColumn: pinFirstColumn);
  }

  TableSort copyWith({List<TableSortLevel>? levels, bool? pinFirstColumn}) =>
      TableSort(
        levels: levels ?? this.levels,
        pinFirstColumn: pinFirstColumn ?? this.pinFirstColumn,
      );

  Map<String, dynamic> toJson() => {
        "levels": [for (var l in levels) l.toJson()],
        if (!pinFirstColumn) "pin": false,
      };

  factory TableSort.fromJson(Map<String, dynamic> json) => TableSort(
        levels: [
          for (var l in (json["levels"] as List? ?? const []))
            if (l is Map<String, dynamic>) TableSortLevel.fromJson(l),
        ],
        pinFirstColumn: jsonBool(json["pin"], true),
      );
}

/// sortTableRows is [rows] in the order [sort] asks for, with the header row
/// (when [headerRow]) left on top.
///
/// A row too short to have the sorted column counts as empty there, which
/// sorts below the numbers when descending.
List<List<String>> sortTableRows(
  List<List<String>> rows,
  TableSort sort, {
  bool headerRow = false,
}) {
  var levels = [
    for (var l in sort.levels)
      if (l.on) l
  ];
  if (levels.isEmpty || rows.length < 2) return rows;

  var head = headerRow ? rows.take(1).toList() : const <List<String>>[];
  var body = [
    for (var r in rows.skip(head.length)) [...r]
  ];
  if (body.length < 2) return rows;

  // The first column's values before anything moved, so they can be put back
  // down the table in the same order afterwards.
  var pinned = sort.pinFirstColumn
      ? [for (var r in body) r.isEmpty ? "" : r.first]
      : const <String>[];

  body.sort((a, b) {
    for (var level in levels) {
      var order = _compare(_at(a, level.column), _at(b, level.column));
      if (order != 0) return level.descending ? -order : order;
    }
    return 0;
  });

  if (sort.pinFirstColumn) {
    for (var i = 0; i < body.length && i < pinned.length; i++) {
      if (body[i].isNotEmpty) body[i][0] = pinned[i];
    }
  }
  return [...head, ...body];
}

String _at(List<String> row, int column) =>
    column >= 0 && column < row.length ? row[column] : "";

/// _compare orders two cells, as numbers when they both are (so "9" comes
/// before "10"), else as case-blind text.
int _compare(String a, String b) {
  var x = cellNumber(a);
  var y = cellNumber(b);
  if (x != null && y != null) return x.compareTo(y);
  // A cell with a number in it beats one without, so blanks and dashes end up
  // together at one end instead of scattered through the table.
  if (x != null) return 1;
  if (y != null) return -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

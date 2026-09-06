import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// table_sort.dart puts a table's rows in order.
//
// Written for a league table, which is the case that needs every part of it: a
// column to sort on, more columns to break the ties with, and a first column
// of positions that must not travel with the rows it numbers. Sorting on
// points alone leaves four teams on six points in whatever order they were
// typed, which is not a league table -- it is a list that happens to be nearly
// sorted.
//
// It is a spec that is applied, not a view the painter reads through. Two
// reasons. A table whose rows re-ordered themselves while a cell was being
// typed into would be unusable, and the rules that colour cells are written
// against row numbers -- so rows that moved underneath them would take their
// colours somewhere unexpected. Applying it rewrites the rows once, which is
// one undo step and exactly what is on screen. The spec is kept so that the
// same order can be put back after the data changes underneath, which is what
// a refreshed table needs.

/// TableSortLevel is one column to order by, and which way.
class TableSortLevel {
  /// column is an index into the row, or -1 for "not set".
  final int column;

  /// descending is highest first, which is what a league table wants and is
  /// therefore the default. A column of names wants the other one.
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
  /// left equal. Three because that is what a league table needs -- points,
  /// then goal difference, then goals scored -- and a fourth has never decided
  /// anything anybody has been able to name.
  final List<TableSortLevel> levels;

  /// pinFirstColumn keeps the first column's values where they are while the
  /// rest of each row moves.
  ///
  /// A league table's first column is the position, and a position is a
  /// property of the row's place rather than of the team in it -- so it must
  /// read 1, 2, 3 after sorting rather than travelling with whoever used to be
  /// first. On by default because a table with a first column worth sorting on
  /// would be sorted on it.
  final bool pinFirstColumn;

  const TableSort({this.levels = const [], this.pinFirstColumn = true});

  bool get on => levels.any((l) => l.on);

  /// at is the level at [index], padded out so the settings panel can always
  /// show three.
  TableSortLevel at(int index) =>
      index < levels.length ? levels[index] : const TableSortLevel();

  TableSort withLevel(int index, TableSortLevel level) {
    var next = [
      for (var i = 0; i < (index + 1 > levels.length ? index + 1 : levels.length); i++)
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

/// sortTableRows is [rows] in the order [sort] asks for.
///
/// [headerRow] is kept where it is: it is a label for the columns, not a row
/// of data, and a header that sorted into the middle of the table is the most
/// obvious possible bug.
///
/// Ragged rows are tolerated, as everywhere else here -- a row too short to
/// have the column being sorted on counts as empty, which sorts to the bottom
/// rather than throwing.
List<List<String>> sortTableRows(
  List<List<String>> rows,
  TableSort sort, {
  bool headerRow = false,
}) {
  var levels = [for (var l in sort.levels) if (l.on) l];
  if (levels.isEmpty || rows.length < 2) return rows;

  var head = headerRow ? rows.take(1).toList() : const <List<String>>[];
  var body = [for (var r in rows.skip(head.length)) [...r]];
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

/// _compare orders two cells, as numbers when they both are.
///
/// Numbers first because this is a table of them and "10" must not come before
/// "9". Falling back to text means a column of names still sorts sensibly, and
/// a column of mixed rubbish sorts consistently rather than throwing.
int _compare(String a, String b) {
  var x = _number(a);
  var y = _number(b);
  if (x != null && y != null) return x.compareTo(y);
  // A cell with a number in it beats one without, so blanks and dashes end up
  // together at one end instead of scattered through the table.
  if (x != null) return 1;
  if (y != null) return -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// _number reads a cell as a number, allowing the things a table of figures
/// actually contains: a leading plus, thousands separators, a percent sign.
double? _number(String cell) {
  var text = cell.trim().replaceAll(",", "").replaceAll("%", "");
  if (text.startsWith("+")) text = text.substring(1);
  return text.isEmpty ? null : double.tryParse(text);
}

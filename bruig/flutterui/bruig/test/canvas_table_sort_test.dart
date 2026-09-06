import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_table_sort_test.dart is about a league table coming out in the right
// order, which is the case that needs every part of the sorter: a column to
// order by, more columns to break the ties, and a first column of positions
// that must not travel with the rows it numbers.

void main() {
  // Pos, Team, Played, GD, For, Points -- the shape of the reporter's table.
  List<List<String>> table() => [
        ["", "Team", "P", "GD", "F", "Pts"],
        ["1", "Arsenal", "2", "4", "4", "6"],
        ["2", "Hull City", "2", "4", "3", "6"],
        ["3", "Liverpool", "3", "2", "6", "5"],
        ["4", "Man City", "2", "4", "6", "6"],
        ["5", "Chelsea", "2", "4", "7", "6"],
      ];

  const points = TableSortLevel(column: 5);
  const goalDifference = TableSortLevel(column: 3);
  const scored = TableSortLevel(column: 4);

  List<String> teamsIn(List<List<String>> rows) =>
      [for (var r in rows.skip(1)) r[1]];

  test("the highest points go to the top", () {
    var sorted = sortTableRows(table(), const TableSort(levels: [points]),
        headerRow: true);
    expect(sorted.first[1], "Team", reason: "the header stays a header");
    expect(teamsIn(sorted).last, "Liverpool", reason: "five points, alone");
  });

  test("ties fall through to the next column, and then the one after", () {
    // Four teams on six points, all on a goal difference of four, so the
    // whole order is decided by goals scored -- which is exactly the case a
    // single sort column gets wrong and leaves in typing order.
    var sorted = sortTableRows(
        table(), const TableSort(levels: [points, goalDifference, scored]),
        headerRow: true);
    expect(teamsIn(sorted), [
      "Chelsea", // 6 pts, GD 4, 7 for
      "Man City", // 6, 4, 6
      "Arsenal", // 6, 4, 4
      "Hull City", // 6, 4, 3
      "Liverpool", // 5
    ]);
  });

  test("a level that decides nothing leaves the one before it alone", () {
    var one = sortTableRows(
        table(), const TableSort(levels: [points, goalDifference]),
        headerRow: true);
    var two = sortTableRows(
        table(),
        // Played is 2 for every team on six points, so it can decide nothing.
        const TableSort(
            levels: [points, goalDifference, TableSortLevel(column: 2)]),
        headerRow: true);
    expect(teamsIn(one), teamsIn(two));
  });

  test("the position column stays reading 1, 2, 3", () {
    var sorted = sortTableRows(
        table(), const TableSort(levels: [points, goalDifference, scored]),
        headerRow: true);
    expect([for (var r in sorted.skip(1)) r[0]], ["1", "2", "3", "4", "5"]);
    expect(sorted[1][1], "Chelsea",
        reason: "the row moved even though its number did not");
  });

  test("and travels with its row when it is not pinned", () {
    var sorted = sortTableRows(
        table(),
        const TableSort(
            levels: [points, goalDifference, scored], pinFirstColumn: false),
        headerRow: true);
    // Chelsea was fifth and keeps its 5 -- which is what somebody sorting a
    // table whose first column is data rather than a position wants.
    expect(sorted[1][0], "5");
  });

  test("numbers sort as numbers, not as text", () {
    var rows = [
      ["a", "9"],
      ["b", "10"],
      ["c", "100"],
    ];
    var sorted = sortTableRows(
        rows,
        const TableSort(
            levels: [TableSortLevel(column: 1)], pinFirstColumn: false));
    expect([for (var r in sorted) r[0]], ["c", "b", "a"]);
  });

  test("a column of words sorts alphabetically", () {
    var rows = [
      ["Wolves"],
      ["Arsenal"],
      ["chelsea"],
    ];
    var sorted = sortTableRows(
        rows,
        const TableSort(
            levels: [TableSortLevel(column: 0, descending: false)],
            pinFirstColumn: false));
    expect([for (var r in sorted) r.first], ["Arsenal", "chelsea", "Wolves"]);
  });

  test("blanks and ragged rows do not throw, and end up together", () {
    var rows = [
      ["a", "3"],
      ["b"],
      ["c", ""],
      ["d", "7"],
    ];
    var sorted = sortTableRows(
        rows,
        const TableSort(
            levels: [TableSortLevel(column: 1)], pinFirstColumn: false));
    expect([for (var r in sorted) r.first].take(2), ["d", "a"]);
    expect([for (var r in sorted) r.first].skip(2).toSet(), {"b", "c"});
  });

  test("an unsorted table is left exactly as it is", () {
    var element = TableElement(const ElementBase(id: "t"), rows: table());
    expect(identical(element.sorted(), element), isTrue,
        reason: "no undo step for a table nobody asked to sort");
  });

  test("the order survives a round trip, so a refresh can use it again", () {
    var element = TableElement(
      const ElementBase(id: "t"),
      rows: table(),
      headerRow: true,
      sort: const TableSort(
          levels: [points, goalDifference], pinFirstColumn: false),
    );
    var back =
        CanvasDocument.decode(CanvasDocument(elements: [element]).encode())!
            .elements
            .first;
    var sort = (back as TableElement).sort;
    expect(sort.levels.length, 2);
    expect(sort.at(0).column, 5);
    expect(sort.at(1).column, 3);
    expect(sort.pinFirstColumn, isFalse);
  });
}

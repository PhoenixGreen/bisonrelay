import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/table_design.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_table_design_test.dart is the Data Studio's Table tab (Ken,
// 2026-11-15: a design view to "select cells or rows or columns or tables
// ... and be given options to customise"): a table's rules shown as named
// styles -- what each reaches, what it looks like, whether it does anything
// -- and the table clicked part by part, a style made, changed, switched off
// and taken away, each one step to undo.

const league = [
  ["Club", "W", "D", "GD", "Pts"],
  ["Arsenal", "14", "4", "28", "46"],
  ["Liverpool", "13", "5", "25", "44"],
  ["Chelsea", "12", "4", "17", "40"],
];

const rules = [
  TableRule(column: "Pts", rows: ">1", style: TableCellStyle(weight: 700)),
  TableRule(
      match: "Chelsea", style: TableCellStyle(background: Color(0xFFE8645A))),
  TableRule(
      column: "GD",
      match: "99",
      style: TableCellStyle(textColor: Color(0xFF2FE08A))),
];

TableElement table0() => const TableElement(
    ElementBase(id: "t1", name: "League", width: 500, height: 220),
    rows: league,
    rules: rules);

CanvasDocument opened() =>
    CanvasDocument.fromJson(CanvasDocument(elements: [table0()]).toJson());

void main() {
  group("styles in words", () {
    test("what each reaches and looks like, and a name from both", () {
      var t = table0();
      expect(styleReach(t, t.rules[0]), "Pts column · every row");
      expect(styleLook(t.rules[0].style), "bold");
      expect(styleName(t, 0), "Pts · bold");
      expect(styleName(t, 1), "“Chelsea” · red box");
      expect(styleName(t, 2), "“99” in GD · green words");
      var named = t.copyWith(rules: [rules[0].copyWith(name: "Points bold")]);
      expect(styleName(named, 0), "Points bold");
    });

    test("a style that finds nothing, or shows nothing, is said to", () {
      var t = table0();
      expect(styleIdle(t, t.rules[0]), isNull);
      expect(styleIdle(t, t.rules[2]), "“99” is nowhere it looks");
      expect(styleIdle(t, const TableRule(column: "Pts")),
          "It changes nothing you can see");
      expect(styleIdle(t, const TableRule(rows: "40")), "It reaches no cells");
    });

    test("rows as words, the header counted as row 1", () {
      expect(spanWords("", "row", header: true), "every row");
      expect(spanWords("1", "row", header: true), "the header");
      expect(spanWords(">1", "row", header: true), "every row but the header");
      expect(spanWords("19:21", "row", header: true), "18th to 20th");
      expect(spanWords("6", "row", header: true), "5th");
      expect(spanWords("4:6", "column"), "columns 4–6");
      expect(spanWords("x", "row"), contains("can't be read"));
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(ordinal).toList(), [
        "1st",
        "2nd",
        "3rd",
        "4th",
        "11th",
        "12th",
        "13th",
        "21st",
        "22nd",
        "101st"
      ]);
    });

    test("the styles on a cell in the order they apply; grouped", () {
      var t = table0();
      expect(stylesAt(t, 3, 4), [0]);
      expect(stylesAt(t, 3, 0), [1]);
      expect(stylesAt(t, 0, 4), isEmpty, reason: "the header is not >1");
      expect(stylesOnColumn(t, 4), [0]);
      expect(stylesOnRow(t, 3), [0, 1]);
      expect(styleCells(t, t.rules[1]), [(3, 0)]);
      expect([for (var (n, i) in styleGroups(t)) "$n $i"],
          ["Columns [0, 2]", "Words anywhere [1]"]);
    });

    test("a name and switched off go through JSON; off draws nothing", () {
      var r = rules[1].copyWith(name: "Bottom club", off: true);
      var back = TableRule.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.name, "Bottom club");
      expect(back.off, isTrue);
      expect(TableRule.fromJson(rules[1].toJson()).off, isFalse);
      var t = table0();
      expect(t.lookAt(3, 0).style?.background, const Color(0xFFE8645A));
      var off = t.copyWith(rules: [t.rules[0], r, t.rules[2]]);
      expect(off.lookAt(3, 0).style, isNull);
    });
  });

  group("styles that follow, and numbers", () {
    test("a style follows its team when the rows change order", () {
      var t = table0().copyWith(rules: [
        const TableRule(
            keys: ["Liverpool"],
            keyColumn: "Club",
            style: TableCellStyle(background: Color(0xFF2FE08A))),
      ]);
      expect(t.lookAt(2, 1).style?.background, const Color(0xFF2FE08A));
      expect(t.lookAt(1, 1).style, isNull);
      var moved =
          t.copyWith(rows: [league[0], league[2], league[1], league[3]]);
      expect(moved.lookAt(1, 1).style?.background, const Color(0xFF2FE08A));
      expect(moved.lookAt(2, 1).style, isNull);
      expect(styleReach(t, t.rules[0]),
          "every column · Liverpool, wherever it is");
      expect(styleName(t, 0), "Liverpool's row · green box");
    });

    test("a number condition reaches only the rows that have it", () {
      var t = table0().copyWith(rules: [
        const TableRule(
            column: "Pts",
            when: TableWhen("Pts", ">=", 44),
            style: TableCellStyle(weight: 700)),
      ]);
      expect(styleCells(t, t.rules[0]), [(1, 4), (2, 4)]);
      expect(styleReach(t, t.rules[0]),
          "Pts column · every row · where Pts is 44 or more");
      expect(styleName(t, 0), "Pts is 44 or more · bold");
    });

    test("keys and the condition go through JSON", () {
      const r = TableRule(
          keys: ["Arsenal", "Chelsea"],
          keyColumn: "Club",
          when: TableWhen("GD", "<", 20));
      var back = TableRule.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.keys, ["Arsenal", "Chelsea"]);
      expect(back.keyColumn, "Club");
      expect(back.when, const TableWhen("GD", "<", 20));
    });

    test("what a click offers", () {
      var t = table0();
      expect(keyColumnOf(t), 0);
      expect([
        for (var o in reachOptions(t, const TablePart.cell(2, 4))) o.label
      ], [
        "Liverpool's Pts, wherever Liverpool is",
        "Liverpool's row, wherever Liverpool is",
        "The 2nd row, whoever is there",
        "The Pts column",
        "Pts 44 or more",
        "Rows where Pts is 44 or more",
      ]);
      expect([
        for (var o in reachOptions(t, const TablePart.row(1), rows: [1, 2, 3]))
          o.label
      ], [
        "1st to 3rd, whoever is there",
        "Arsenal, Liverpool and Chelsea, wherever they are",
      ]);
      var form = TableElement(const ElementBase(id: "f"), rows: const [
        ["Team", "Form"],
        ["A", "W W L"],
      ]);
      expect(reachOptions(form, const TablePart.cell(1, 1)).map((o) => o.label),
          containsAll(["Every “W” in Form", "Every “L” in Form"]));
    });
  });

  group("the Table tab", () {
    late CanvasController c;
    TableElement table() => c.document.elementById("t1") as TableElement;

    Future<void> studio(WidgetTester tester, {double scale = 1.25}) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c = CanvasController(opened(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.openDataStudio(c.document.sheets.single.id, view: "t1");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (_) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (_) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (_) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: DataStudio(
                    controller: c,
                    sheetId: c.dataStudio.value!,
                    onDone: c.closeDataStudio))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("dataStudioTab-table")));
      await tester.pumpAndSettle();
    }

    /// at is where a cell, a column tab (row -1) or a row tab (col -1) is
    /// on the stage, laid out as the stage lays it out.
    Offset at(WidgetTester tester, int row, int col) {
      var stage = find.byKey(const ValueKey("tableDesignStage"));
      var origin = tester.getTopLeft(stage);
      var width = tester.getSize(stage).width;
      var t = table();
      var rect = Rect.fromLTWH(0, 0, t.width, t.height);
      var k = ((width - 16 * 2 - 22 - 6) / t.width).clamp(0.1, 1.25);
      var w = tableColumnWidths(t, rect), h = tableRowHeights(t, rect);
      double sum(List<double> v, int n) =>
          v.take(math.max(0, n)).fold(0.0, (a, b) => a + b);
      const o = 16.0 + 22 + 6;
      var x = col < 0 ? 16 + 11.0 : o + (sum(w, col) + w[col] / 2) * k;
      var y = row < 0 ? 16 + 11.0 : o + (sum(h, row) + h[row] / 2) * k;
      return origin + Offset(x, y);
    }

    String title(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey("tableDesignTitle")))
        .data!;

    testWidgets("parts clicked: the table, a column, a row, a cell",
        (tester) async {
      await studio(tester);
      expect(find.byKey(const ValueKey("tableDesignStage")), findsOneWidget);
      expect(title(tester), "League");
      // Every style listed, the idle one marked.
      expect(find.byKey(const ValueKey("tableStyle-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("tableStyleIdle-2")), findsOneWidget);
      expect(find.byKey(const ValueKey("tableStyleIdle-0")), findsNothing);

      await tester.tapAt(at(tester, -1, 4));
      await tester.pumpAndSettle();
      expect(title(tester), "Pts");
      expect(find.byKey(const ValueKey("tableStyle-0")), findsOneWidget);

      await tester.tapAt(at(tester, 3, -1));
      await tester.pumpAndSettle();
      expect(title(tester), "Row 4");

      await tester.tapAt(at(tester, 3, 0));
      await tester.pumpAndSettle();
      expect(title(tester), "Cell A4");
      expect(find.byKey(const ValueKey("tableStyle-1")), findsOneWidget,
          reason: "the Chelsea style is on it");
      expect(find.byKey(const ValueKey("tableStyle-0")), findsNothing);

      // Esc goes up: the cell to its column, the column to the table.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(title(tester), "Club");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(title(tester), "League");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a style made for a column, changed, switched off, deleted",
        (tester) async {
      await studio(tester);
      await tester.tapAt(at(tester, -1, 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("tableDesignStyleColumn")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("tableReach-0")));
      await tester.pumpAndSettle();
      expect(table().rules.length, 4);
      expect(table().rules[3].column, "GD");
      expect(table().rules[3].rows, ">1");
      expect(title(tester), "GD · gold fill");

      // A fill picked: the GD cells take it, on the canvas too.
      final fill = find.byKey(const ValueKey("tableStyleFill-2fe08a"));
      await tester.ensureVisible(fill);
      await tester.tap(fill);
      await tester.pumpAndSettle();
      expect(table().rules[3].style.background, const Color(0xFF2FE08A));
      expect(table().lookAt(1, 3).style?.background, const Color(0xFF2FE08A));
      expect(title(tester), "GD · green fill");

      // Named.
      final name = find.descendant(
          of: find.byKey(const ValueKey("tableStyleName-3")),
          matching: find.byType(TextField));
      await tester.ensureVisible(name);
      await tester.enterText(name, "Goal difference");
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(table().rules[3].name, "Goal difference");

      // Switched off, then on, from the table's list.
      final off = find.byKey(const ValueKey("tableStyleOff"));
      await tester.ensureVisible(off);
      await tester.tap(off);
      await tester.pumpAndSettle();
      expect(table().rules[3].off, isTrue);
      expect(table().lookAt(1, 3).style, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final eye = find.byKey(const ValueKey("tableStyleEye-3"));
      await tester.ensureVisible(eye);
      await tester.tap(eye);
      await tester.pumpAndSettle();
      expect(table().rules[3].off, isFalse);

      // Moved earlier, then deleted; each an undo step.
      await tester.tap(find.byKey(const ValueKey("tableStyle-3")));
      await tester.pumpAndSettle();
      final earlier = find.byKey(const ValueKey("tableStyleEarlier"));
      await tester.ensureVisible(earlier);
      await tester.tap(earlier);
      await tester.pumpAndSettle();
      expect(table().rules[2].name, "Goal difference");
      final delete = find.byKey(const ValueKey("tableStyleDelete"));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(table().rules.length, 3);
      c.undo();
      await tester.pumpAndSettle();
      expect(table().rules.length, 4);
      expect(table().rules[2].name, "Goal difference");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the table's own look: a slider is one step to undo",
        (tester) async {
      await studio(tester);
      var before = table().cornerRadius;
      var corners = find.descendant(
          of: find.byKey(const ValueKey("tableSlider-Corners")),
          matching: find.byType(Slider));
      await tester.ensureVisible(corners);
      await tester.drag(corners, const Offset(60, 0));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(table().cornerRadius, isNot(before));
      c.undo();
      await tester.pumpAndSettle();
      expect(table().cornerRadius, before);
    });

    testWidgets("New style by pointing: a team's row that goes with it",
        (tester) async {
      await studio(tester);
      final add = find.byKey(const ValueKey("tableDesignNewStyle"));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(title(tester), "New style");
      await tester.tapAt(at(tester, 2, 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("tableReach-0")), findsOneWidget);
      // Liverpool's row, following.
      await tester.tap(find.byKey(const ValueKey("tableReach-1")));
      await tester.pumpAndSettle();
      var made = table().rules.last;
      expect(made.keys, ["Liverpool"]);
      expect(made.keyColumn, "Club");
      expect(made.style.background.a, greaterThan(0),
          reason: "it shows at once");
      expect(find.byKey(const ValueKey("tableNewDone")), findsOneWidget);
      // Kept to its place instead, then followed again.
      final keep = find.byKey(const ValueKey("tableStyleKeep"));
      await tester.ensureVisible(keep);
      await tester.tap(keep);
      await tester.pumpAndSettle();
      expect(table().rules.last.keys, isEmpty);
      expect(table().rules.last.rows, "3");
      final follow = find.byKey(const ValueKey("tableStyleFollow"));
      await tester.ensureVisible(follow);
      await tester.tap(follow);
      await tester.pumpAndSettle();
      expect(table().rules.last.keys, ["Liverpool"]);
      final done = find.byKey(const ValueKey("tableNewDone"));
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(title(tester), "League");
      expect(tester.takeException(), isNull);
    });

    testWidgets("rows picked with shift; a number condition; copy and paste",
        (tester) async {
      await studio(tester);
      await tester.tapAt(at(tester, 1, -1));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tapAt(at(tester, 2, -1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(title(tester), "2 rows");
      await tester.tap(find.byKey(const ValueKey("tableDesignStyleRows")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("tableReach-0")));
      await tester.pumpAndSettle();
      expect(table().rules.last.rows, "2:3");
      var made = table().rules.length - 1;

      // A number condition added to it.
      final when = find.byKey(const ValueKey("tableStyleWhenAdd"));
      await tester.ensureVisible(when);
      await tester.tap(when);
      await tester.pumpAndSettle();
      expect(table().rules[made].when?.column, "Pts");
      final value = find.descendant(
          of: find.byKey(ValueKey("tableStyleWhenValue-$made")),
          matching: find.byType(TextField));
      await tester.ensureVisible(value);
      await tester.enterText(value, "45");
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(table().rules[made].when?.value, 45);
      expect(styleCells(table(), table().rules[made]).map((p) => p.$1).toSet(),
          {1});

      // Its look copied onto the bold Pts style.
      final copy = find.byKey(const ValueKey("tableStyleCopy"));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey("tableStyle-0"));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      final paste = find.byKey(const ValueKey("tableStylePaste"));
      await tester.ensureVisible(paste);
      await tester.tap(paste);
      await tester.pumpAndSettle();
      expect(table().rules[0].style.background,
          table().rules[made].style.background);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a column's edge dragged: it widens, its neighbour narrows",
        (tester) async {
      await studio(tester);
      var stage = find.byKey(const ValueKey("tableDesignStage"));
      var t = table();
      var rect = Rect.fromLTWH(0, 0, t.width, t.height);
      var w = tableColumnWidths(t, rect);
      var width = tester.getSize(stage).width;
      var k = ((width - 16 * 2 - 22 - 6) / t.width).clamp(0.1, 1.25);
      var edge = tester.getTopLeft(stage) +
          Offset(16.0 + 22 + 6 + w[0] * k, 16 + 11.0);
      await tester.dragFrom(edge, const Offset(40, 0));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      var after = table().columnWidths;
      expect(after.length, w.length);
      expect(after[0], greaterThan(w[0] + 20));
      expect(after[1], lessThan(w[1] - 20));
      expect(after[2], closeTo(w[2], 0.01));
      c.undo();
      await tester.pumpAndSettle();
      expect(table().columnWidths, isEmpty);
    });

    for (var scale in [0.65, 1.0, 1.5]) {
      testWidgets("nothing overflows at text size $scale", (tester) async {
        await studio(tester, scale: scale);
        for (var (row, col) in [(-1, 2), (2, -1), (0, -1), (3, 0)]) {
          await tester.tapAt(at(tester, row, col));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey("tableStyle-1")));
        await tester.pumpAndSettle();
        final fine = find.byKey(const ValueKey("tableStyleFine"));
        await tester.ensureVisible(fine);
        await tester.tap(fine);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

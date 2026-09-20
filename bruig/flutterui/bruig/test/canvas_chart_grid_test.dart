import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_grid_test.dart is the chart's numbers, laid out like the
// table element's.
//
// They were not: the name cell over a column carried its own remove button
// inline and the "From" dropdown was thirty pixels wider, so three rows all
// describing one series came out three different widths and none of them
// stood over the numbers underneath.

void main() {
  Future<CanvasController> panel(WidgetTester tester, ChartData data) async {
    var element = ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      data: data,
    );
    var controller =
        CanvasController(const CanvasDocument().addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly("c");

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(body: CanvasDesignPanel(controller: controller))),
    ));
    await tester.pumpAndSettle();

    // The numbers open as pasted text; the grid is the other view.
    var toGrid = find.byTooltip("Edit the numbers in a table");
    if (toGrid.evaluate().isNotEmpty) {
      await tester.ensureVisible(toGrid);
      await tester.pumpAndSettle();
      await tester.tap(toGrid);
      await tester.pumpAndSettle();
    }
    return controller;
  }

  Future<void> press(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await tester.pumpAndSettle();
    await tester.tap(what);
    await tester.pumpAndSettle();
  }

  ChartData two() => ChartData.parse("Cat\tOne\tTwo\nx\t1\t10\ny\t2\t20");

  testWidgets("a heading stands over its own numbers", (tester) async {
    await panel(tester, two());

    // The cells of one column, top to bottom: the heading and the two
    // readings under it. All three start at the same place and are the same
    // width, or the grid is not a grid.
    // In order: the two headings, then each row's category cell and its two
    // readings. So the first column's heading is 0 and its readings are 3
    // and 6.
    var cells = find.byType(CanvasGridCell);
    var heading = tester.getRect(cells.at(0));
    var first = tester.getRect(cells.at(3));
    var second = tester.getRect(cells.at(6));

    expect(first.left, closeTo(heading.left, 0.5));
    expect(first.width, closeTo(heading.width, 0.5));
    expect(second.left, closeTo(heading.left, 0.5));
    expect(second.width, closeTo(heading.width, 0.5));
  });

  testWidgets("a series is moved by the buttons over its column",
      (tester) async {
    var controller = await panel(tester, two());
    ChartData dataIn() =>
        (controller.document.elements.single as ChartElement).data;
    expect(dataIn().series.map((s) => s.name), ["One", "Two"]);

    await press(tester, find.byKey(const ValueKey("seriesRight0")));
    expect(dataIn().series.map((s) => s.name), ["Two", "One"]);
    expect(dataIn().valueAt(0, 0), 10, reason: "its numbers go with it");

    await press(tester, find.byKey(const ValueKey("seriesLeft1")));
    expect(dataIn().series.map((s) => s.name), ["One", "Two"]);
  });

  testWidgets("and a row by the buttons on the end of it", (tester) async {
    var controller =
        await panel(tester, ChartData.parse("Cat\tA\nx\t1\ny\t2\nz\t3"));
    ChartData dataIn() =>
        (controller.document.elements.single as ChartElement).data;

    await press(tester, find.byKey(const ValueKey("rowDown0")));
    expect(dataIn().categories, ["y", "x", "z"]);
    expect(dataIn().valueAt(0, 0), 2, reason: "the reading goes with the row");
    expect(dataIn().valueAt(0, 1), 1);

    await press(tester, find.byKey(const ValueKey("rowUp1")));
    expect(dataIn().categories, ["x", "y", "z"]);
  });

  testWidgets("and the estimate mark moves with its row", (tester) async {
    var controller =
        await panel(tester, ChartData.parse("Cat\tA\nx\t1\ny\t2\nz\t3"));
    ChartData dataIn() =>
        (controller.document.elements.single as ChartElement).data;

    await press(tester, find.byKey(const ValueKey("rowEstimated2")));
    expect(dataIn().isEstimated(2), isTrue);

    await press(tester, find.byKey(const ValueKey("rowUp2")));
    expect(dataIn().categories, ["x", "z", "y"]);
    expect(dataIn().isEstimated(1), isTrue,
        reason: "the mark belongs to the row, not to the place in the list");
    expect(dataIn().isEstimated(2), isFalse);
  });

  testWidgets("the From row is not there without a source", (tester) async {
    // A chart of typed numbers has nowhere for a series to come from but the
    // grid itself, so there is nothing to choose.
    await panel(tester, two());
    expect(find.byKey(const ValueKey("chartGridSeries0")), findsNothing);
  });
}

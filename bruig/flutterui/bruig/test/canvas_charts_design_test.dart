import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_charts_design_test.dart is the Data Studio's Charts tab (Ken,
// 2026-11-15: chart design "very visual and flexible"; prototypes v5-v6):
// the chart drawn large and clicked part by part -- a series, then one bar
// -- a bar highlighted and the highlight changed, a column put in a slot,
// the rows a chart shows, each one step to undo.

const league = [
  ["Club", "Last", "GD", "Pts"],
  ["Arsenal", "W", "28", "46"],
  ["Liverpool", "D", "25", "44"],
  ["Chelsea", "L", "17", "40"],
  ["Spurs", "W", "9", "33"],
];

CanvasDocument opened() => CanvasDocument.fromJson(CanvasDocument(elements: [
      TableElement(
          const ElementBase(id: "t1", name: "League", width: 500, height: 220),
          rows: league),
      ChartElement(
          const ElementBase(id: "c1", name: "Points", width: 500, height: 300),
          fromTable: const TableLink(
              tableId: "t1", categoryColumn: 0, valueColumns: [3])),
    ]).toJson());

void main() {
  late CanvasController c;
  ChartElement chart() => c.document.elementById("c1") as ChartElement;

  Future<void> studio(WidgetTester tester, {double scale = 1.25}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = CanvasController(opened(), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.openDataStudio(c.document.sheets.single.id, view: "c1");
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
    await tester.tap(find.byKey(const ValueKey("dataStudioTab-charts")));
    await tester.pumpAndSettle();
  }

  String title(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey("chartsTitle"))).data!;

  ChartsDesignState state(WidgetTester tester) =>
      tester.state<ChartsDesignState>(find.byType(ChartsDesign));

  /// barAt is where the painter drew the bar for [index], on the screen.
  Offset barAt(WidgetTester tester, int index) {
    var s = state(tester);
    var part = s.parts
        .firstWhere((p) => p.kind == ChartPartKind.mark && p.index == index);
    return tester.getTopLeft(find.byKey(const ValueKey("chartsStage"))) +
        s.stageOffsetOf(part);
  }

  testWidgets("a bar clicked: its series, then itself; highlighted",
      (tester) async {
    await studio(tester);
    expect(title(tester), "Points");
    expect(state(tester).parts.where((p) => p.kind == ChartPartKind.mark),
        hasLength(4),
        reason: "the painter noted where each bar is");

    await tester.tapAt(barAt(tester, 2));
    await tester.pumpAndSettle();
    expect(title(tester), "Pts", reason: "first its series");
    await tester.tapAt(barAt(tester, 2));
    await tester.pumpAndSettle();
    expect(title(tester), "Chelsea", reason: "then that bar alone");

    await tester.tap(find.byKey(const ValueKey("chartsHighlightMark")));
    await tester.pumpAndSettle();
    expect(chart().highlights.single.who, "Chelsea");
    expect(chart().data.marks[2], const Color(0xFFF2B33D));
    expect(chart().data.marks[0]!.a, lessThan(0.5), reason: "the rest faded");
    expect(title(tester), "Just Chelsea");

    // Changed to the top two by points.
    await tester.tap(
        find.byKey(const ValueKey("studioPill-chartsReach-ChartReach.top")));
    await tester.pumpAndSettle();
    expect(chart().highlights.single.reach, ChartReach.top);
    // The top three: Spurs, fourth, is the one faded.
    expect(chart().data.marks[2], const Color(0xFFF2B33D));
    expect(chart().data.marks[3]!.a, lessThan(0.5));

    // One step back takes the change of reach away.
    c.undo();
    await tester.pumpAndSettle();
    expect(chart().highlights.single.reach, ChartReach.one);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(title(tester), "Points");
    expect(tester.takeException(), isNull);
  });

  testWidgets("a column put in a slot; the rows a chart shows", (tester) async {
    await studio(tester);
    // Last (results) to colour each bar by.
    await tester.tap(find.byKey(const ValueKey("chartsColumn-1")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("chartsPutColour")));
    await tester.pumpAndSettle();
    expect(chart().sheet!.colourBy, 1);
    expect(chart().data.marks.first, const Color(0xFF2FE08A), reason: "a win");
    expect(chart().data.marks[2], const Color(0xFFE8645A), reason: "a loss");

    // GD as a second series.
    await tester.tap(find.byKey(const ValueKey("chartsColumn-2")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("chartsPutValues")));
    await tester.pumpAndSettle();
    expect(chart().sheet!.series, [3, 2]);
    expect(chart().data.series.length, 2);

    // Only the top two.
    await tester.tap(find.byKey(const ValueKey("studioPill-chartsRows-top")));
    await tester.pumpAndSettle();
    expect(chart().sheet!.top, 5);
    expect(chart().data.categories.length, 4);

    // The bottom places 3 and 4, the sheet left as it is.
    await tester
        .tap(find.byKey(const ValueKey("studioPill-chartsRows-places")));
    await tester.pumpAndSettle();
    final places = find.descendant(
        of: find.byKey(const ValueKey("chartsPlaces")),
        matching: find.byType(TextField));
    await tester.ensureVisible(places);
    await tester.enterText(places, "3-4");
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(chart().data.categories, ["Chelsea", "Spurs"]);
    expect(c.document.sheets.single.cells, league,
        reason: "a chart's reading never writes the sheet");
    expect(tester.takeException(), isNull);
  });

  testWidgets("the title and the plot picked from the drawing", (tester) async {
    await studio(tester);
    c.replaceElement(chart().copyWith(title: "Points so far"));
    await tester.pumpAndSettle();
    var s = state(tester);
    var stage = tester.getTopLeft(find.byKey(const ValueKey("chartsStage")));
    var heading = s.parts.firstWhere((p) => p.kind == ChartPartKind.title);
    await tester.tapAt(stage + s.stageOffsetOf(heading));
    await tester.pumpAndSettle();
    expect(title(tester), "Title");
    // The plot's top left corner, where no bar reaches.
    var plot = s.parts.firstWhere((p) => p.kind == ChartPartKind.plot);
    await tester
        .tapAt(stage + s.stageAt(plot.rect.topLeft + const Offset(3, 3)));
    await tester.pumpAndSettle();
    expect(title(tester), "Plot");
    expect(tester.takeException(), isNull);
  });

  for (var scale in [0.65, 1.0, 1.5]) {
    testWidgets("nothing overflows at text size $scale", (tester) async {
      await studio(tester, scale: scale);
      await tester.tapAt(barAt(tester, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(barAt(tester, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsHighlightMark")));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey("studioPill-chartsReach-ChartReach.when")));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey("studioPill-chartsRows-places")));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

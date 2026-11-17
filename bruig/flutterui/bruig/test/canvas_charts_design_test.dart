import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/chart_play.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/data_charts_design.dart';
import 'package:bruig/plugin_system/canvas/ui/data_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
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
  // The sidebar's sections open, as these tests are of what each control
  // does; where they are folded is the sidebar's own test.
  setUp(() => CanvasSection.openAll = true);
  tearDown(() => CanvasSection.openAll = false);
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

  /// rows picks which rows the chart shows, in the slot bar.
  Future<void> rows(WidgetTester tester, String which) async {
    await tester.tap(find.byKey(const ValueKey("chartsRows")));
    await tester.pumpAndSettle();
    await tester.tap(find.text(which).last);
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
    await rows(tester, "Top");
    expect(chart().sheet!.top, 5);
    expect(chart().data.categories.length, 4);

    // The bottom places 3 and 4, the sheet left as it is.
    await rows(tester, "Places");
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
      await rows(tester, "Places");
      // The gallery too, and a kind's starting designs.
      final add = find.byKey(const ValueKey("chartsNew"));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("chartsKind-horizontalBar")),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("chartsKind-horizontalBar")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("chartsPreset-0")));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // Ken, 2026-11-17 (prototype v7): the gallery replaces the suggestions,
  // built from the columns ticked: every kind drawn with them, the best
  // fit first; a kind's starting designs; one picked, given a style and an
  // extra, and started.
  testWidgets("a new chart from the gallery: a kind, a design, a style",
      (tester) async {
    await studio(tester);
    var before = c.document.elements.length;
    final add = find.byKey(const ValueKey("chartsNew"));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(title(tester), "New chart");
    // Club and Pts ticked to start: ranked bars first.
    expect(find.text("Bars · best fit"), findsOneWidget);
    // Kinds the columns can't feed say what they need.
    expect(
        find.textContaining("Needs four columns of numbers"), findsOneWidget);
    // GD ticked as well: a scatter is the best fit.
    await tester.tap(find.byKey(const ValueKey("chartsColumn-2")));
    await tester.pumpAndSettle();
    expect(find.text("Scatter · best fit"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("chartsColumn-2")));
    await tester.pumpAndSettle();
    // Asked by the question it answers, and by a word.
    await tester.tap(find.byKey(const ValueKey("chartsGalleryAsk-part")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("chartsKind-pie")), findsOneWidget);
    expect(find.byKey(const ValueKey("chartsKind-line")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("chartsGalleryAsk-all")));
    await tester.pumpAndSettle();
    // Bars: its designs; the race needs a date column.
    await tester.tap(find.byKey(const ValueKey("chartsKind-horizontalBar")));
    await tester.pumpAndSettle();
    expect(find.text("Needs a date column"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("chartsPreset-1")));
    await tester.pumpAndSettle();
    expect(title(tester), "Bars · Highlight one");
    expect(find.byKey(const ValueKey("chartsGalleryPreview")), findsOneWidget);
    // An average line added; the Broadcast style.
    await tester.tap(find.byKey(const ValueKey("chartsGalleryMod-average")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("chartsGalleryStyle")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Style: Broadcast").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("chartsGalleryStart")));
    await tester.pumpAndSettle();
    expect(c.document.elements.length, before + 1);
    var made = c.document.elements.last as ChartElement;
    expect(made.type, ChartType.horizontalBar);
    expect(made.sheet!.sortBy, 3);
    expect(made.data.categories.first, "Arsenal");
    expect(made.highlights, hasLength(1));
    expect(made.notes.single.kind, ChartNoteKind.line);
    expect(made.style, "Broadcast");
    expect(title(tester), made.name.isEmpty ? "Chart" : made.name,
        reason: "the new chart is opened");
    // One step to undo.
    c.undo();
    await tester.pumpAndSettle();
    expect(c.document.elements.length, before);
    expect(tester.takeException(), isNull);
  });

  // Ken, 2026-11-17: what the chart's canvas panel could change and the
  // Charts tab couldn't, now in the part it belongs to.
  testWidgets("each part's own settings, as on the canvas panel",
      (tester) async {
    await studio(tester);
    c.replaceElement(chart().copyWith(
        title: "The league", description: "This season", showLegend: true));
    await tester.pumpAndSettle();
    Future<void> pick(ChartPartKind kind) async {
      var s = state(tester);
      var part = s.parts.firstWhere((p) => p.kind == kind);
      await tester.tapAt(
          tester.getTopLeft(find.byKey(const ValueKey("chartsStage"))) +
              s.stageOffsetOf(part));
      await tester.pumpAndSettle();
    }

    Future<void> tap(String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> menu(String key, String choice) async {
      await tap(key);
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    // The title's typeface and weight.
    await pick(ChartPartKind.title);
    await menu("chartsTitleFont", "Georgia");
    expect(chart().titleSpec.fontFamily, "Georgia");
    await tap("studioPill-chartsTitleFontWeight-400");
    expect(chart().titleSpec.weight, 400);
    // The description had no panel at all.
    await pick(ChartPartKind.description);
    expect(find.byKey(const ValueKey("chartsDescriptionText")), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey("chartsDescriptionText")), "{count} clubs");
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(chart().description, "{count} clubs");
    // The key: where it goes.
    await pick(ChartPartKind.legend);
    await tap("studioPill-chartsLegendPlace-bottom");
    expect(chart().legend.placement.name, "bottom");
    // The plot: log scale, the numbers' unit.
    await pick(ChartPartKind.plot);
    await tap("studioPill-chartsLogScale-true");
    expect(chart().logScale, isTrue);
    // How its marks are drawn: tracks behind the bars.
    await tap("chartsTrack");
    expect(chart().design.track, isTrue);
    await tap("studioPill-chartsDecimals-0");
    expect(chart().numbers.decimals, 0);
    await tester.enterText(
        find.byKey(const ValueKey("chartsNumberAfter")), " pts");
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(chart().numbers.after, " pts");
    // The numbers up the side: a title of their own, and their steps.
    await pick(ChartPartKind.yLabels);
    await tester.enterText(
        find.byKey(const ValueKey("chartsYTitle")), "Points");
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(chart().yAxisLabel, "Points");
    expect(chart().showYTitle, isTrue);
    // A doughnut's middle, from the whole chart.
    c.replaceElement(chart().copyWith(type: ChartType.donut));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("chartsSlider-Hole")), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey("chartsCentreWords")), "{leader by Pts}");
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(chart().centreLabel, "{leader by Pts}");
    expect(tester.takeException(), isNull);
  });

  testWidgets("steps: added, changed, switched between, previewed, deleted",
      (tester) async {
    await studio(tester);
    c.replaceElement(chart().copyWith(title: "{leader by Pts} on top"));
    await tester.pumpAndSettle();
    // The title's live words, read as they stand.
    var s = state(tester);
    var heading = s.parts.firstWhere((p) => p.kind == ChartPartKind.title);
    await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey("chartsStage"))) +
            s.stageOffsetOf(heading));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.byKey(const ValueKey("chartsReadsNow"))).data,
        "Reads now: Arsenal on top");
    expect(find.byKey(const ValueKey("chartsWord-Leader")), findsOneWidget);

    // A second step, its own title.
    await tester.tap(find.byKey(const ValueKey("chartsAddStep")));
    await tester.pumpAndSettle();
    expect(chart().steps, hasLength(2));
    expect(chart().stepAt, 1);
    c.replaceElement(chart().copyWith(title: "The bottom one"));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("chartsStep-0")));
    await tester.pumpAndSettle();
    expect(chart().title, "{leader by Pts} on top");
    await tester.tap(find.byKey(const ValueKey("chartsStep-1")));
    await tester.pumpAndSettle();
    expect(chart().title, "The bottom one");

    // Moved on by the timeline's marks: no pace of its own then.
    Future<void> follow(String label) async {
      final menu = find.byKey(const ValueKey("chartsFollow"));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await follow(ChartStepsFollow.marks.label);
    expect(chart().follow, "marks");
    expect(find.byKey(const ValueKey("chartsSlider-Each")), findsNothing);
    await follow(ChartStepsFollow.time.label);
    expect(chart().follow, "time");

    // Previewed: it plays, and stops.
    await tester.tap(find.byKey(const ValueKey("chartsPreview")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Playing…"), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text("▶ Preview"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("chartsDeleteStep")));
    await tester.pumpAndSettle();
    expect(chart().steps, isEmpty, reason: "one step left is no steps");
    expect(chart().title, "{leader by Pts} on top");
    expect(tester.takeException(), isNull);
  });

  // Ken, 2026-11-17: the six styles replace the Looks.
  testWidgets("a style; a check with its fix; the board laid out",
      (tester) async {
    await studio(tester);
    final broadcast = find.byKey(const ValueKey("dataStyle-Broadcast"));
    await tester.ensureVisible(broadcast);
    await tester.tap(broadcast);
    await tester.pumpAndSettle();
    expect(chart().style, "Broadcast");
    expect(chart().panel, const Color(0xFF0B1022), reason: "its own ground");
    expect(chart().titleSpec.fontFamily, "Oswald");
    expect(chart().data.series.first.color, const Color(0xFF2FD3FF));
    // On the canvas's ground instead.
    final canvasGround =
        find.byKey(const ValueKey("studioPill-chartsGround-false"));
    await tester.ensureVisible(canvasGround);
    await tester.tap(canvasGround);
    await tester.pumpAndSettle();
    expect(chart().panel.a, 0);
    // Another style keeps it on the canvas's ground.
    final editorial = find.byKey(const ValueKey("dataStyle-Editorial"));
    await tester.ensureVisible(editorial);
    await tester.pumpAndSettle();
    await tester.tap(editorial);
    await tester.pumpAndSettle();
    expect(chart().style, "Editorial");
    expect(chart().panel.a, 0);
    expect(chart().titleSpec.fontFamily, "Georgia");

    // Labelled by the results, which repeat: said, and fixed in a click.
    expect(find.byKey(const ValueKey("chartsChecks")), findsNothing);
    c.replaceElement(
        chart().copyWith(sheet: chart().sheet!.copyWith(labels: 1)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("chartsChecks")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("chartsFix-0-0")));
    await tester.pumpAndSettle();
    expect(chart().sheet!.group, "total");
    expect(chart().data.categories, ["W", "D", "L"]);
    expect(chart().data.series.single.values, [79, 44, 40]);
    expect(find.byKey(const ValueKey("chartsChecks")), findsNothing);

    // The board: the table and the chart, laid out side by side.
    await tester.tap(find.byKey(const ValueKey("chartsBoard")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("chartsBoardView-t1")), findsOneWidget);
    expect(find.byKey(const ValueKey("chartsBoardView-c1")), findsOneWidget);
    final layOut = find.byKey(const ValueKey("chartsLayOut"));
    await tester.ensureVisible(layOut);
    await tester.tap(layOut);
    await tester.pumpAndSettle();
    var t = c.document.elementById("t1")!, ch = c.document.elementById("c1")!;
    // Two a row, filling the page: side by side, the same width, apart.
    expect(ch.base.y, t.base.y);
    expect(ch.base.width, t.base.width);
    expect(ch.base.x, greaterThan(t.base.x + t.base.width));
    expect(tester.takeException(), isNull);
  });

  // Ken, 2026-11-17 (the improvements report's fourth item): notes bound
  // to the data by name -- a callout, an arrow, a bracket saying the gap.
  testWidgets("a callout, an arrow and a bracket bound to the clubs",
      (tester) async {
    await studio(tester);
    for (var key in [
      "chartsAddCallout",
      "chartsAddArrow",
      "chartsAddBracket"
    ]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final add = find.byKey(ValueKey(key));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
    }
    var notes = chart().notes;
    expect([for (var n in notes) n.kind],
        [ChartNoteKind.callout, ChartNoteKind.arrow, ChartNoteKind.bracket]);
    // On the largest by points; the bracket from the second to the first.
    var d = chart().data;
    var byPts = [...d.categories]..sort((a, b) => d
        .valueAt(0, d.categories.indexOf(b))
        .compareTo(d.valueAt(0, d.categories.indexOf(a))));
    expect(notes[0].who, byPts.first);
    expect((notes[2].who, notes[2].whom), (byPts[1], byPts.first));
    expect(state(tester).parts.where((p) => p.kind == ChartPartKind.note),
        hasLength(3),
        reason: "each drawn, and found where it was drawn");
    // The bracket picked: its two clubs chosen by name.
    expect(find.byKey(const ValueKey("chartsNoteWhom-2")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("notes added and changed; a club picked out everywhere",
      (tester) async {
    await studio(tester);
    final average = find.byKey(const ValueKey("chartsAddAverage"));
    await tester.ensureVisible(average);
    await tester.tap(average);
    await tester.pumpAndSettle();
    expect(chart().notes.single.kind, ChartNoteKind.line);
    expect(chart().notes.single.value.isNaN, isTrue, reason: "the average");
    expect(title(tester), "Line");
    expect(state(tester).parts.where((p) => p.kind == ChartPartKind.note),
        hasLength(1),
        reason: "drawn, and found where it was drawn");
    await tester
        .tap(find.byKey(const ValueKey("studioPill-chartsNoteAt-false")));
    await tester.pumpAndSettle();
    expect(chart().notes.single.value, 0);

    // A bar labelled, and picked out everywhere.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tapAt(barAt(tester, 1));
    await tester.pumpAndSettle();
    await tester.tapAt(barAt(tester, 1));
    await tester.pumpAndSettle();
    expect(title(tester), "Liverpool");
    await tester.tap(find.byKey(const ValueKey("chartsLabelMark")));
    await tester.pumpAndSettle();
    expect(chart().notes.last.kind, ChartNoteKind.label);
    expect(chart().notes.last.who, "Liverpool");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tapAt(barAt(tester, 2));
    await tester.pumpAndSettle();
    await tester.tapAt(barAt(tester, 2));
    await tester.pumpAndSettle();
    final spot = find.byKey(const ValueKey("chartsSpotlight"));
    await tester.ensureVisible(spot);
    await tester.tap(spot);
    await tester.pumpAndSettle();
    expect(c.document.sheets.single.spotlight, "Chelsea");
    expect(chart().data.marks[2], const Color(0xFFF2B33D));
    expect(find.byKey(const ValueKey("chartsSpotlightName")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("chartsSpotlightOff")));
    await tester.pumpAndSettle();
    expect(c.document.sheets.single.spotlight, "");
    expect(tester.takeException(), isNull);
  });
}

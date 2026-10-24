import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_slice_colours_test.dart is a pie whose slices are given their
// own colours.
//
// A pie is one series' values, so before ChartElement.sliceColors the only
// way to colour a slice was a dummy series per slice for it to borrow from.

const _amber = Color(0xFFFFB020);
const _teal = Color(0xFF2ED6A1);

ChartElement _pie({List<Color> slices = const []}) => ChartElement(
      const ElementBase(id: "c", width: 200, height: 200),
      type: ChartType.pie,
      showLegend: false,
      sliceColors: slices,
      data: const ChartData(categories: [
        "right",
        "left"
      ], series: [
        ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: [50, 50]),
      ]),
    );

/// _at is the colour painted at ([x], [y]).
Future<Color> _at(ChartElement e, int x, int y) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 200),
      Paint()..color = const Color(0xFF000000));
  paintChart(canvas, const Rect.fromLTWH(0, 0, 200, 200), e);
  var image = await recorder.endRecording().toImage(200, 200);
  var bytes = (await image.toByteData())!;
  var p = bytes.getUint32((y * 200 + x) * 4);
  image.dispose();
  // RGBA as read, back into ARGB.
  return Color(((p & 0xFF) << 24) | (p >> 8));
}

void main() {
  test("a slice takes its own colour before a series' or the palette's", () {
    var pie = _pie(slices: const [_amber]);
    expect(sliceColour(pie, 0), _amber);
    expect(sliceColour(pie, 1), chartPalette[1],
        reason: "a slice with no colour of its own falls back");
    expect(sliceColour(_pie(), 0), chartPalette[0]);
  });

  test("the colours are saved and read back", () {
    var pie = _pie(slices: const [_amber, _teal]);
    var back = ChartElement.fromJson(pie.toJson(), const ElementBase(id: "c"));
    expect(back.sliceColors, [_amber, _teal]);
    expect(_pie().toJson().containsKey("sliceColors"), isFalse,
        reason: "nothing is written for a pie with none");
  });

  test("the slices are painted in them", () async {
    // Two halves from twelve o'clock: the first runs down the right side.
    var pie = _pie(slices: const [_amber, _teal]);
    expect(await _at(pie, 150, 100), _amber);
    expect(await _at(pie, 50, 100), _teal);
  });

  Future<CanvasController> panel(WidgetTester tester, ChartElement e) async {
    var controller = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(controller.dispose);
    controller.selectOnly(e.id);
    tester.view.physicalSize = const Size(1400, 1600);
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
    return controller;
  }

  testWidgets("a pie has a colour button per slice, and it sets that slice",
      (tester) async {
    var controller = await panel(tester, _pie());
    expect(find.byKey(const ValueKey("chartSliceColours")), findsOneWidget);
    var second = find.byKey(const ValueKey("chartSlice1"));
    expect(second, findsOneWidget);
    tester.widget<CanvasColorButton>(second).onChanged(_teal);
    await tester.pumpAndSettle();
    var e = controller.document.elements.single as ChartElement;
    expect(e.sliceColors, [chartPalette[0], _teal],
        reason: "the first keeps what it showed, the second takes the pick");
    controller.undo();
    expect((controller.document.elements.single as ChartElement).sliceColors,
        isEmpty,
        reason: "one undo step");
  });

  test("one series of bars is painted a colour a bar", () async {
    // Two bars, left and right, the right one amber; the left keeps the
    // series' blue. No dummy series stacked under them to borrow from.
    var bars = _pie(slices: const [Color(0x00000000), _amber]).copyWith(
        type: ChartType.bar, showAxes: false, showGrid: false);
    expect(barsTakeColours(bars), isTrue);
    var left = await _at(bars.copyWith(sliceColors: const []), 80, 150);
    expect(left, const Color(0xFF3D7EFF), reason: "the series' own");
    var coloured = bars.copyWith(sliceColors: const [_teal, _amber]);
    expect(await _at(coloured, 80, 150), _teal);
    expect(await _at(coloured, 160, 150), _amber);
  });

  testWidgets("a bar chart of one series has a colour button per bar",
      (tester) async {
    var controller = await panel(tester, _pie().copyWith(type: ChartType.bar));
    var row = find.byKey(const ValueKey("chartSliceColours"));
    expect(row, findsOneWidget);
    expect(tester.widget<CanvasControlGroup>(row).label, "Bars");
    var first = tester
        .widget<CanvasColorButton>(find.byKey(const ValueKey("chartSlice0")));
    expect(first.color, const Color(0xFF3D7EFF),
        reason: "shows the colour the bar is drawn in, the series'");
    tester
        .widget<CanvasColorButton>(find.byKey(const ValueKey("chartSlice1")))
        .onChanged(_teal);
    await tester.pumpAndSettle();
    var e = controller.document.elements.single as ChartElement;
    expect(e.sliceColors, [const Color(0xFF3D7EFF), _teal]);
  });

  testWidgets("but bars of several series are coloured by series",
      (tester) async {
    var two = _pie().copyWith(
        type: ChartType.groupedBar,
        data: const ChartData(categories: [
          "a",
          "b"
        ], series: [
          ChartSeries(name: "x", color: Color(0xFF3D7EFF), values: [1, 2]),
          ChartSeries(name: "y", color: _amber, values: [2, 1]),
        ]));
    await panel(tester, two);
    expect(find.byKey(const ValueKey("chartSliceColours")), findsNothing);
  });
}

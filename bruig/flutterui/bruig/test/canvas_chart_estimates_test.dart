import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_estimates_test.dart is a figure worked out rather than looked
// up, and the chart saying so.
//
// A treasury series reconstructed from block-subsidy arithmetic and one read
// off an explorer are not the same claim, and a chart that draws them alike
// makes the stronger claim for both. The weight of the mark carries it: a
// sourced year is solid and full, an estimated one faint and dashed. The
// alternative is a footnote naming the estimated years, which nobody reads
// against the bar they are looking at.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);
const Color _ink = Color(0xFF30E0A0);

ChartElement _chart({
  required List<bool> estimated,
  ChartType type = ChartType.bar,
}) =>
    ChartElement(
      const ElementBase(id: "c", width: 300, height: 200),
      type: type,
      showLegend: false,
      showGrid: false,
      showAxes: false,
      showXLabels: false,
      showYLabels: false,
      showPoints: false,
      smooth: false,
      strokeWidth: 4,
      data: ChartData(
        categories: const ["a", "b", "c", "d"],
        series: const [
          ChartSeries(name: "A", color: _ink, values: [6, 6, 6, 6])
        ],
        estimated: estimated,
      ),
    );

/// _ink counts how much of the series' colour was laid down, weighted by how
/// solidly -- which is the whole question here.
Future<double> _weight(ChartElement e, {int from = 0, int to = _w}) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  var total = 0.0;
  for (var y = 0; y < _h; y++) {
    for (var x = from; x < to; x++) {
      total += (bytes.getUint32((y * _w + x) * 4) >> 8) & 0xFF;
    }
  }
  return total;
}

void main() {
  group("a chart that marks its estimates", () {
    test("says so, and only when a row is marked", () {
      var plain = ChartData.parse("Cat\tA\n2019\t1\n2020\t2");
      expect(plain.marksEstimates, isFalse);
      expect(plain.isEstimated(0), isFalse);

      var marked = plain.withEstimated(1, true);
      expect(marked.marksEstimates, isTrue);
      expect(marked.isEstimated(0), isFalse);
      expect(marked.isEstimated(1), isTrue);
    });

    test("keeps the marks when it is saved", () {
      var data =
          ChartData.parse("Cat\tA\n2019\t1\n2020\t2").withEstimated(1, true);
      var back = ChartData.fromJson(data.toJson());
      expect(back.isEstimated(1), isTrue);
      expect(back.isEstimated(0), isFalse);
      // And a chart nobody has marked saves the file it always did.
      expect(ChartData.parse("Cat\tA\n2019\t1").toJson().containsKey("est"),
          isFalse);
    });

    test("keeps them when a row above is taken away", () {
      var data = ChartData.parse("Cat\tA\nx\t1\ny\t2\nz\t3")
          .withEstimated(2, true)
          .withRowRemoved(0);
      expect(data.categories, ["y", "z"]);
      expect(data.isEstimated(1), isTrue,
          reason: "the marks walk up with the rows they belong to");
      expect(data.isEstimated(0), isFalse);
    });

    testWidgets("is marked a row at a time, from the grid", (tester) async {
      // A control that does nothing when it is pressed is what a model-only
      // test cannot see.
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\n2019\t10\n2020\t6"),
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

      ChartData dataIn() =>
          (controller.document.elements.single as ChartElement).data;
      expect(dataIn().isEstimated(1), isFalse);

      // The numbers open as pasted text, and the marks live on the rows of
      // the grid -- there is nowhere to put a switch in a block of text.
      var toGrid = find.byTooltip("Edit the numbers in a table");
      if (toGrid.evaluate().isNotEmpty) {
        await tester.ensureVisible(toGrid);
        await tester.pumpAndSettle();
        await tester.tap(toGrid);
        await tester.pumpAndSettle();
      }

      var button = find.byKey(const ValueKey("rowEstimated1"));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(dataIn().isEstimated(1), isTrue);
      expect(dataIn().isEstimated(0), isFalse, reason: "that row alone");

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(dataIn().isEstimated(1), isFalse, reason: "and back again");
    });

    testWidgets("draws an estimated bar fainter than a sourced one",
        (tester) async {
      late double sourced, estimated;
      await tester.runAsync(() async {
        // The same value in the same place, marked and unmarked. A quarter of
        // the width, so only the second bar is counted.
        sourced = await _weight(
            _chart(estimated: const [false, false, false, false]),
            from: _w ~/ 4,
            to: _w ~/ 2);
        estimated = await _weight(
            _chart(estimated: const [false, true, false, false]),
            from: _w ~/ 4,
            to: _w ~/ 2);
      });
      expect(sourced, greaterThan(0));
      expect(estimated, lessThan(sourced * 0.6),
          reason: "$estimated against $sourced");
      expect(estimated, greaterThan(0), reason: "faint, not gone");
    });

    testWidgets("and lays down less ink along an estimated stretch of line",
        (tester) async {
      late double solid, broken;
      await tester.runAsync(() async {
        solid =
            await _weight(_chart(estimated: const [], type: ChartType.line));
        broken = await _weight(_chart(
            estimated: const [false, true, true, false], type: ChartType.line));
      });
      expect(solid, greaterThan(0));
      // Dashes are gaps in the stroke, so the middle of the line is lighter.
      expect(broken, lessThan(solid * 0.85), reason: "$broken against $solid");
    });

    testWidgets("and leaves a chart with no marks exactly as it was",
        (tester) async {
      late double before, after;
      await tester.runAsync(() async {
        before = await _weight(_chart(estimated: const []));
        after = await _weight(
            _chart(estimated: const [false, false, false, false]));
      });
      expect(after, closeTo(before, 0.5));
    });
  });
}

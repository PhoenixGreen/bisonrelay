import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_label_gap_backdrop_test.dart is two things set on a bar chart:
// how far each axis' values sit from the plot, and the panel a series can
// draw behind each of its bars.

const int _w = 300, _h = 200;
const Rect _rect = Rect.fromLTWH(0, 0, 300, 200);
const _green = Color(0xFF30E0A0);

ChartElement _chart({
  double xGap = 0,
  double yGap = 0,
  double barGap = 0,
  bool horizontal = false,
  ChartBackdrop? backdrop,
}) =>
    ChartElement(
      const ElementBase(id: "c", width: 300, height: 200),
      type: horizontal ? ChartType.horizontalBar : ChartType.bar,
      xLabelGap: xGap,
      yLabelGap: yGap,
      barGap: barGap,
      showLegend: false,
      showGrid: false,
      showAxes: false,
      labelSpec: const TextSpec(fontSize: 14, color: Color(0xFFFFFFFF)),
      data: ChartData(categories: const [
        "Jan",
        "Feb",
        "Mar"
      ], series: [
        ChartSeries(
            name: "A",
            color: _green,
            values: const [10, 4, 14],
            backdrop: backdrop),
      ]),
    );

Future<List<int>> _pixels(ChartElement e) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(_rect, Paint()..color = const Color(0xFF000000));
  paintChart(canvas, _rect, e);
  var image = await recorder.endRecording().toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  image.dispose();
  return [
    for (var i = 0; i < bytes.lengthInBytes; i += 4)
      (bytes.getUint32(i) >> 8) | ((bytes.getUint32(i) & 0xFF) << 24),
  ];
}

typedef _Is = bool Function(int r, int g, int b);
bool _white(int r, int g, int b) => r > 150 && g > 150 && b > 150;
bool _bar(int r, int g, int b) => g > 180 && r < 120 && b > 100 && b < 200;
bool _red(int r, int g, int b) => r > 200 && g < 60 && b < 60;

/// _where lists the points of one colour, optionally only inside [within].
List<Offset> _where(List<int> px, _Is is_, [Rect within = _rect]) => [
      for (var y = within.top.round(); y < within.bottom.round(); y++)
        for (var x = within.left.round(); x < within.right.round(); x++)
          if (is_((px[y * _w + x] >> 16) & 0xFF, (px[y * _w + x] >> 8) & 0xFF,
              px[y * _w + x] & 0xFF))
            Offset(x.toDouble(), y.toDouble()),
    ];

/// _bottomGap is the air between the bottom of the bars and the top of the
/// writing under them.
Future<double> _bottomGap(ChartElement e) async {
  var px = await _pixels(e);
  var barBottom =
      _where(px, _bar).map((p) => p.dy).reduce((a, b) => a > b ? a : b);
  var under = _where(
      px, _white, Rect.fromLTRB(60, barBottom + 1, _w.toDouble(), _h * 1.0));
  return under.map((p) => p.dy).reduce((a, b) => a < b ? a : b) - barBottom;
}

/// _sideGap is the air between the figures up the side and the first bar.
Future<double> _sideGap(ChartElement e) async {
  var px = await _pixels(e);
  var bars = _where(px, _bar);
  var barLeft = bars.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
  var barBottom = bars.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
  var side = _where(px, _white, Rect.fromLTRB(0, 0, barLeft, barBottom - 2));
  return barLeft - side.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
}

void main() {
  group("the values' gap", () {
    testWidgets("moves the writing under the bars away and back",
        (tester) async {
      late double none, more, less;
      await tester.runAsync(() async {
        none = await _bottomGap(_chart());
        more = await _bottomGap(_chart(xGap: 20));
        less = await _bottomGap(_chart(xGap: -3));
      });
      expect(more - none, closeTo(20, 2));
      expect(none - less, closeTo(3, 2));
    });

    testWidgets("moves the figures up the side away and back", (tester) async {
      late double none, more, less;
      await tester.runAsync(() async {
        none = await _sideGap(_chart());
        more = await _sideGap(_chart(yGap: 20));
        less = await _sideGap(_chart(yGap: -3));
      });
      expect(more - none, closeTo(20, 2));
      expect(none - less, closeTo(3, 2));
    });

    testWidgets("is the side's on a chart drawn sideways too", (tester) async {
      late double none, more;
      await tester.runAsync(() async {
        none = await _sideGap(_chart(horizontal: true));
        more = await _sideGap(_chart(horizontal: true, yGap: 15));
      });
      expect(more - none, closeTo(15, 2));
    });

    test("is saved, and nought is not written", () {
      var e = _chart(xGap: 12, yGap: -4);
      var back = ChartElement.fromJson(e.toJson(), e.base);
      expect([back.xLabelGap, back.yLabelGap], [12, -4]);
      expect(_chart().toJson().containsKey("xLabelGap"), isFalse);
    });
  });

  group("a series' background", () {
    const red = Color(0xFFFF0000);

    testWidgets("is off unless asked for", (tester) async {
      late List<Offset> off, on;
      await tester.runAsync(() async {
        off = _where(
            await _pixels(
                _chart(barGap: 0.5, backdrop: const ChartBackdrop(fill: red))),
            _red);
        on = _where(
            await _pixels(_chart(
                barGap: 0.5,
                backdrop: const ChartBackdrop(on: true, fill: red))),
            _red);
      });
      expect(off, isEmpty, reason: "kept, but switched off");
      expect(on, isNotEmpty);
    });

    testWidgets("stands behind each bar, as tall as asked", (tester) async {
      late List<Offset> bars, panels, half;
      await tester.runAsync(() async {
        var px = await _pixels(_chart(
            barGap: 0.5, backdrop: const ChartBackdrop(on: true, fill: red)));
        bars = _where(px, _bar);
        panels = _where(px, _red);
        half = _where(
            await _pixels(_chart(
                barGap: 0.5,
                backdrop:
                    const ChartBackdrop(on: true, fill: red, height: 0.5))),
            _red);
      });
      var barTop = bars.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      var panelTop = panels.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      expect(panelTop, lessThan(barTop), reason: "the whole plot's height");
      // The bars are drawn over it: not one of their pixels went red.
      expect(bars.length, greaterThan(100));
      var halfTop = half.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      expect(halfTop, greaterThan(panelTop + 40), reason: "half as tall");
    });

    testWidgets("grows from the side it is told to", (tester) async {
      Future<(double, double)> spill(ChartBackdropGrow grow) async {
        var px = await _pixels(_chart(
            barGap: 0.6,
            backdrop:
                ChartBackdrop(on: true, fill: red, width: 1.8, grow: grow)));
        var bars = _where(px, _bar);
        // The first bar's own column, and the red either side of it.
        var left = bars.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
        var first = bars.where((p) => p.dx < left + 45);
        var right = first.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
        var reds = _where(px, _red);
        return (
          reds.where((p) => p.dx < left - 2).length.toDouble(),
          reds.where((p) => p.dx > right + 2 && p.dx < right + 15).length * 1.0,
        );
      }

      late (double, double) l, c, r;
      await tester.runAsync(() async {
        l = await spill(ChartBackdropGrow.left);
        c = await spill(ChartBackdropGrow.centre);
        r = await spill(ChartBackdropGrow.right);
      });
      expect(l.$1, 0, reason: "anchored at the bar's left edge");
      expect(l.$2, greaterThan(0));
      expect(r.$2, 0, reason: "anchored at the bar's right edge");
      expect(r.$1, greaterThan(0));
      expect(c.$1, greaterThan(0));
      expect(c.$2, greaterThan(0));
    });

    testWidgets("hangs from the top, sits on the bottom, or centres",
        (tester) async {
      Future<(double, double)> extent(ChartBackdropGrow grow) async {
        var px = await _pixels(_chart(
            barGap: 0.5,
            backdrop:
                ChartBackdrop(on: true, fill: red, height: 0.3, grow: grow)));
        var reds = _where(px, _red);
        var bars = _where(px, _bar);
        // Red, and where the bars would have covered it.
        var ys = [...reds, ...bars.where((p) => true)].map((p) => p.dy);
        var top = reds.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
        var bottom = ys.reduce((a, b) => a > b ? a : b);
        return (top, bottom);
      }

      late (double, double) top, bottom, centre;
      await tester.runAsync(() async {
        top = await extent(ChartBackdropGrow.top);
        bottom = await extent(ChartBackdropGrow.bottom);
        centre = await extent(ChartBackdropGrow.centre);
      });
      expect(top.$1, lessThan(centre.$1));
      expect(centre.$1, lessThan(bottom.$1));
    });

    testWidgets("can stand taller than the chart", (tester) async {
      late double whole, taller;
      Future<double> topOf(double height) async {
        var px = await _pixels(_chart(
            barGap: 0.5,
            backdrop: ChartBackdrop(on: true, fill: red, height: height)));
        return _where(px, _red)
            .map((p) => p.dy)
            .reduce((a, b) => a < b ? a : b);
      }

      await tester.runAsync(() async {
        whole = await topOf(1);
        taller = await topOf(1.1);
      });
      expect(taller, lessThan(whole - 5));
      var kept = ChartBackdrop.fromJson(
          const ChartBackdrop(on: true, height: 2.5).toJson());
      expect(kept.height, 2.5);
    });

    test("is saved with the series", () {
      var s = const ChartSeries(
        name: "A",
        color: _green,
        values: [1],
        backdrop: ChartBackdrop(
            on: true,
            height: 0.7,
            width: 1.5,
            fill: red,
            border: Color(0xFF0000FF),
            radius: 6,
            borderWidth: 2,
            grow: ChartBackdropGrow.right),
      );
      var b = ChartSeries.fromJson(s.toJson(), 0).backdrop!;
      expect([b.on, b.height, b.width, b.radius, b.borderWidth, b.grow],
          [true, 0.7, 1.5, 6, 2, ChartBackdropGrow.right]);
      expect([b.fill, b.border], [red, const Color(0xFF0000FF)]);
      expect(
          const ChartSeries(name: "A", color: _green, values: [1])
              .toJson()
              .containsKey("backdrop"),
          isFalse);
    });

    testWidgets("is switched on behind the series' own button", (tester) async {
      var element = _chart();
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

      Future<void> press(Finder what) async {
        await tester.ensureVisible(what);
        await tester.pumpAndSettle();
        await tester.tap(what);
        await tester.pumpAndSettle();
      }

      ChartSeries series() =>
          (controller.document.elements.single as ChartElement)
              .data
              .series
              .single;

      await press(find.byKey(const ValueKey("seriesMore0")));
      expect(find.byKey(const ValueKey("seriesBackdropHeight0")), findsNothing);
      await press(find.byKey(const ValueKey("seriesBackdrop0")));
      expect(series().backdrop?.on, isTrue);
      for (var k in [
        "seriesBackdropHeight0",
        "seriesBackdropWidth0",
        "seriesBackdropGrow0",
        "seriesBackdropFill0",
        "seriesBackdropBorder0",
        "seriesBackdropBorderWidth0",
        "seriesBackdropRadius0",
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // On lines of their own, a row gap clear of each other: the switch,
      // then the size, then the paint.
      Rect at(String k) => tester.getRect(find.byKey(ValueKey(k)));
      var toggle = at("seriesBackdrop0");
      var height = at("seriesBackdropHeight0");
      var fill = at("seriesBackdropFill0");
      expect(height.top, greaterThanOrEqualTo(toggle.bottom + canvasRowGap - 1),
          reason: "the size starts a line under the switch");
      expect(fill.top, greaterThanOrEqualTo(height.bottom + canvasRowGap - 1),
          reason: "the paint starts a line under the size");
      expect(at("seriesBackdropGrow0").center.dy, closeTo(height.center.dy, 2),
          reason: "Grow from is on the size's line");

      await press(find.byKey(const ValueKey("seriesBackdrop0")));
      expect(series().backdrop?.on, isFalse);
      expect(series().backdrop, isNotNull, reason: "kept for switching back");
    });
  });
}

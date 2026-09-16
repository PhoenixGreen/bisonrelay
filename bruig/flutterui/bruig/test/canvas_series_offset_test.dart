import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_series_offset_test.dart is one series arriving earlier or later than
// another.
//
// Reported with a chart of bars and a line over them, arriving on Draw on:
// the line traced faster than the bars and then finished with them. The
// presets stagger by *item*, and the two do not have the same items -- a set
// of bars is one item per category, a line is one item per series -- so the
// line is given the whole window while the bars go one after another. Each is
// right alone and the pair is wrong, and no single stagger rule fixes it.

void main() {
  const series =
      ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: [1, 2, 3]);

  group("where a series is in the animation", () {
    test("is the whole thing when nothing is offset", () {
      expect(series.delay, 0);
      for (var at in [0.0, 0.25, 1.0]) {
        expect(series.revealAt(at), at);
      }
    });

    test("later, when it is pushed back -- and still finishes on time", () {
      // The offset moves the start. The series still has to be complete when
      // the chart stops animating, or it races the last of the way and jumps
      // to the end -- which is what shifting the whole window did.
      var late = series.copyWith(delay: 0.25);
      expect(late.revealAt(0.25), 0);
      expect(late.revealAt(0.625), closeTo(0.5, 0.0001),
          reason: "halfway through the three quarters it has left");
      expect(late.revealAt(1), 1.0, reason: "done when the chart is");
    });

    test("sooner, when it is brought forward -- and is done early", () {
      var early = series.copyWith(delay: -0.25);
      expect(early.revealAt(0), 0, reason: "it starts at the start");
      expect(early.revealAt(0.375), closeTo(0.5, 0.0001));
      expect(early.revealAt(0.75), 1.0, reason: "and finishes a quarter early");
      expect(early.revealAt(1), 1.0);
    });

    test("and it is held at both ends rather than wrapping", () {
      // An arrival that started again would be two arrivals.
      var late = series.copyWith(delay: 0.5);
      expect(late.revealAt(0), 0);
      expect(series.copyWith(delay: -0.9).revealAt(1), 1);
    });

    test("an offset of everything still leaves time to arrive in", () {
      // A series that arrives in no time does not arrive.
      var all = series.copyWith(delay: 1);
      expect(all.revealAt(1), 1);
      expect(all.revealAt(0.99), lessThan(1));
    });

    test("it survives being saved, and costs nothing unused", () {
      expect(series.toJson().containsKey("delay"), isFalse);
      var late = series.copyWith(delay: 0.3);
      expect(ChartSeries.fromJson(late.toJson(), 0).delay, closeTo(0.3, 1e-9));
    });

    test("and a saved offset past the ends is brought back", () {
      var back = ChartSeries.fromJson({
        "name": "s",
        "color": 0xFF3D7EFF,
        "values": [1.0],
        "delay": 4.0,
      }, 0);
      expect(back.delay, 1.0);
    });
  });

  group("the control", () {
    Future<void> show(WidgetTester tester,
        {required bool animated, double width = 300}) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var data = ChartData.parse("Cat\tOne\tTwo\nx\t10\t4");
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: width,
                child: SizedBox(
                  width: width,
                  child: ChartDataEditor(
                    data: data,
                    animated: animated,
                    onChanged: (_) {},
                    onCommit: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets("is not offered on a chart that does not arrive",
        (tester) async {
      await show(tester, animated: false);
      expect(find.byKey(const ValueKey("seriesDelay1")), findsNothing);
    });

    testWidgets("nor on the first series, which the rest are offset against",
        (tester) async {
      await show(tester, animated: true);
      expect(find.byKey(const ValueKey("seriesDelay0")), findsNothing);
      expect(find.byKey(const ValueKey("seriesDelay1")), findsOneWidget);
    });

    testWidgets("it sits out on the series' row, not behind its button",
        (tester) async {
      // A setting on a line of its own reads as belonging to the series after
      // it as easily as the one before -- and this is the one setting that is
      // about a series *against the others*, set by looking down the column
      // and comparing, which cannot be done one flyout at a time. So it stays
      // in sight while the rest of the series' settings go behind the button.
      await show(tester, animated: true);
      var offset = tester.getRect(find.byKey(const ValueKey("seriesDelay1")));
      var colour = tester.getRect(find.byType(CanvasColorButton).at(1));
      expect(offset.top, closeTo(colour.top, 0.5));
      expect(offset.left, greaterThan(colour.left));
      expect(find.byKey(const ValueKey("seriesWidth1")), findsNothing,
          reason: "the width is behind the button, the offset is not");
    });

    testWidgets("and the whole series still fits one line of the sidebar",
        (tester) async {
      // Name, kind, colour, offset and the button, at the width a sidebar is
      // usually left at. Narrower than this the row wraps, which is what a
      // Wrap is for; what must not happen is it wrapping at an ordinary
      // width, where the offset would read as belonging to the series after.
      await show(tester, animated: true);
      var colour = tester.getRect(find.byType(CanvasColorButton).at(1));
      var more = tester.getRect(find.byKey(const ValueKey("seriesMore1")));
      expect(more.right, lessThanOrEqualTo(300));
      expect(more.top, closeTo(colour.top, 0.5));
    });
  });

  test("a chart that does not arrive has nothing to offset against", () {
    // The knob is about lining two arrivals up; with no arrival there is
    // nothing to line up.
    expect(const ChartAnimation().on, isFalse);
  });

  // The other half, and the half a model test cannot show: that the painter
  // asks. A setting the painter never reads is a dead control.
  group("what is actually drawn", () {
    ChartElement chart({double delay = 0}) => ChartElement(
          const ElementBase(id: "c", width: 240, height: 160),
          type: ChartType.bar,
          showLegend: false,
          showXLabels: false,
          showYLabels: false,
          showGrid: false,
          animation: const ChartAnimation(preset: ChartAnimationPreset.drawOn),
          data: ChartData(categories: const [
            "a",
            "b",
            "c",
            "d"
          ], series: [
            const ChartSeries(
                name: "bars",
                color: Color(0xFFFFB020),
                values: [80, 90, 70, 60]),
            ChartSeries(
                name: "line",
                color: const Color(0xFF3D7EFF),
                type: ChartType.line,
                values: const [40, 50, 45, 55],
                delay: delay),
          ]),
        );

    /// blue counts the line's own ink partway through the arrival.
    Future<int> blue(ChartElement e, double at) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 240, 160),
          Paint()..color = const Color(0xFF000000));
      paintChart(canvas, const Rect.fromLTWH(0, 0, 240, 160), e, reveal: at);
      var image = await recorder.endRecording().toImage(240, 160);
      var bytes = (await image.toByteData())!;
      var n = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var p = bytes.getUint32(i);
        var r = (p >> 24) & 0xFF;
        var b = (p >> 8) & 0xFF;
        if (b > 0x90 && b > r + 0x40) n++;
      }
      image.dispose();
      return n;
    }

    testWidgets("a delayed series is further behind partway through",
        (tester) async {
      late int ontime;
      late int held;
      await tester.runAsync(() async {
        ontime = await blue(chart(), 0.4);
        held = await blue(chart(delay: 0.35), 0.4);
      });
      expect(ontime, greaterThan(0), reason: "the line is drawing");
      expect(held, lessThan(ontime),
          reason: "and the delayed one has drawn less of itself");
    });

    testWidgets("and one brought forward is further ahead", (tester) async {
      late int ontime;
      late int early;
      await tester.runAsync(() async {
        ontime = await blue(chart(), 0.3);
        early = await blue(chart(delay: -0.3), 0.3);
      });
      expect(early, greaterThan(ontime));
    });

    testWidgets("everything is there at the end, however it was offset",
        (tester) async {
      // Held at the ends rather than wrapped: a series brought forward or
      // pushed back still finishes, or the chart would end incomplete.
      late int ontime;
      late int held;
      await tester.runAsync(() async {
        ontime = await blue(chart(), 1);
        held = await blue(chart(delay: 0.5), 1);
      });
      expect(held, ontime);
    });
  });
}

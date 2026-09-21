import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
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
// Reported twice. First as a chart of bars with a line over them, arriving on
// Draw on: the line traced faster than the bars and then finished with them.
// The presets stagger by *item*, and the two do not have the same items -- a
// set of bars is one item per category, a line is one item per series -- so
// the line is given the whole window while the bars go one after another.
// Each is right alone and the pair is wrong, and no single stagger rule fixes
// it, which is why there is a knob.
//
// Then as "the offset is acting like a speed control". It was: it squeezed a
// series into what was left of the window instead of moving it in time, so a
// series pushed back by a third arrived in two thirds of the time. It is
// seconds now, and a real shift -- the renderer asks the element's own
// keyframes what the chart looked like that many seconds ago.

void main() {
  const series =
      ChartSeries(name: "s", color: Color(0xFF3D7EFF), values: [1, 2, 3]);

  group("an offset is a shift in time", () {
    // Twelve frames a second, and a chart that arrives over exactly one of
    // them. So a frame is a twelfth and half a second is six frames, which is
    // what makes the numbers below readable.
    ChartElement chart(double delay) => ChartElement(
          ElementBase(
            id: "c",
            width: 200,
            height: 120,
            track: ElementTrack(const [
              Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
              Keyframe(frame: 12, values: {KeyframeChannel.reveal: 1}),
            ]),
          ),
          animation: const ChartAnimation(preset: ChartAnimationPreset.drawOn),
          data: ChartData(categories: const [
            "a",
            "b"
          ], series: [
            const ChartSeries(
                name: "first", color: Color(0xFFFFB020), values: [1, 2]),
            ChartSeries(
                name: "second",
                color: const Color(0xFF3D7EFF),
                values: const [2, 3],
                delay: delay),
          ]),
        );

    double? secondAt(double delay, int frame) =>
        chartSeriesReveal(chart(delay), frame, 12)?[1];

    test("costs nothing on a chart where nothing is offset", () {
      expect(chartSeriesReveal(chart(0), 6, 12), isNull,
          reason: "nearly every chart, and it does no work for them");
    });

    test("later means later, at the same speed", () {
      // Half a second back is six frames back: what the delayed series is
      // doing on frame twelve is what the chart was doing on frame six. The
      // *shape* of its arrival is untouched, which is the whole point -- the
      // offset used to squeeze the series into what was left of the window,
      // so a series pushed back drew itself faster than the one beside it.
      expect(secondAt(0.5, 6), closeTo(0, 1e-9), reason: "not started yet");
      expect(secondAt(0.5, 12), closeTo(0.5, 1e-9),
          reason: "halfway, when the chart itself has finished");
      expect(secondAt(0.5, 15), closeTo(0.75, 1e-9));
      expect(secondAt(0.5, 18), closeTo(1, 1e-9),
          reason: "and complete half a second after the chart");
    });

    test("and it takes exactly as long as the chart does", () {
      // Started six frames late and finished six frames late: twelve frames
      // either way, which is what "the same speed" means.
      double whole(int f) =>
          chart(0).track!.at(f).values[KeyframeChannel.reveal]!;
      var ontime = [for (var f = 0; f <= 12; f++) whole(f)];
      var late = [for (var f = 6; f <= 18; f++) secondAt(0.5, f)!];
      for (var i = 0; i < ontime.length; i++) {
        expect(late[i], closeTo(ontime[i], 1e-9));
      }
    });

    test("sooner means sooner", () {
      expect(secondAt(-0.5, 0), closeTo(0.5, 1e-9),
          reason: "already halfway when the chart starts");
      expect(secondAt(-0.5, 6), closeTo(1, 1e-9), reason: "and done early");
    });

    test("it is held at both ends rather than wrapping", () {
      // An arrival that started again would be two arrivals.
      expect(secondAt(2, 0), closeTo(0, 1e-9));
      expect(secondAt(-2, 0), closeTo(1, 1e-9));
      expect(secondAt(0.5, 600), closeTo(1, 1e-9));
    });

    test("it survives being saved, and costs nothing unused", () {
      expect(series.toJson().containsKey("delay"), isFalse);
      var late = series.copyWith(delay: 2.5);
      expect(ChartSeries.fromJson(late.toJson(), 0).delay, closeTo(2.5, 1e-9));
    });

    test("and a saved offset past the ends is brought back", () {
      var back = ChartSeries.fromJson({
        "name": "s",
        "color": 0xFF3D7EFF,
        "values": [1.0],
        "delay": 400.0,
      }, 0);
      expect(back.delay, maxSeriesDelay);
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
    ChartElement chart() => ChartElement(
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
            const ChartSeries(
                name: "line",
                color: Color(0xFF3D7EFF),
                type: ChartType.line,
                values: [40, 50, 45, 55]),
          ]),
        );

    /// blue counts the line's own ink, for a chart drawn [at] with the second
    /// series [second] of the way through its own arrival.
    Future<int> blue(double at, {double? second}) async {
      var recorder = ui.PictureRecorder();
      var canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 240, 160),
          Paint()..color = const Color(0xFF000000));
      paintChart(canvas, const Rect.fromLTWH(0, 0, 240, 160), chart(),
          reveal: at, seriesReveal: second == null ? null : [at, second]);
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

    testWidgets("a series held back has drawn less of itself", (tester) async {
      late int ontime;
      late int held;
      await tester.runAsync(() async {
        ontime = await blue(0.4);
        held = await blue(0.4, second: 0.2);
      });
      expect(ontime, greaterThan(0), reason: "the line is drawing");
      expect(held, lessThan(ontime));
    });

    testWidgets("and one brought forward has drawn more", (tester) async {
      late int ontime;
      late int early;
      await tester.runAsync(() async {
        ontime = await blue(0.3);
        early = await blue(0.3, second: 0.7);
      });
      expect(early, greaterThan(ontime));
    });

    testWidgets("it goes on arriving after the chart itself has finished",
        (tester) async {
      // The thing the old squeeze could not do, and the reason it was a
      // squeeze: the chart's own reveal is one and over, and a series put
      // back by a second still has most of a second to go.
      late int whole;
      late int behind;
      await tester.runAsync(() async {
        whole = await blue(1);
        behind = await blue(1, second: 0.35);
      });
      expect(behind, lessThan(whole));
      expect(behind, greaterThan(0), reason: "part of it is there");
    });

    testWidgets("and everything is there once it has", (tester) async {
      late int whole;
      late int done;
      await tester.runAsync(() async {
        whole = await blue(1);
        done = await blue(1, second: 1);
      });
      expect(done, whole);
    });
  });
}

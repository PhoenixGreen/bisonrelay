import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_chart_turns_waffle_test.dart is batch 3's chart additions from the
// privacy video's report (Ken, 2026-11-12): a chart's series arriving one
// after another, and the waffle chart -- a share read as so many squares in
// a hundred.

void main() {
  group("series in turn", () {
    test("each its share of the arrival, one after another", () {
      expect(seriesInTurnReveal(0.25, 0, 2), closeTo(0.5, 1e-9));
      expect(seriesInTurnReveal(0.25, 1, 2), 0);
      expect(seriesInTurnReveal(0.75, 0, 2), 1);
      expect(seriesInTurnReveal(0.75, 1, 2), closeTo(0.5, 1e-9));
    });

    test("the renderer hands each series its own reveal", () {
      var e = ChartElement(
        const ElementBase(id: "c"),
        data: ChartData.parse("Cat\tA\tB\nx\t1\t2\ny\t3\t4"),
        animation: const ChartAnimation(
            preset: ChartAnimationPreset.grow, seriesInTurn: true),
      );
      var reveal = chartSeriesReveal(e, 0, 24,
          poseAt: (_) =>
              const Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0.25}));
      expect(reveal, [closeTo(0.5, 1e-9), 0]);
      // Together, nothing of its own to hand out.
      expect(
          chartSeriesReveal(
              e.copyWith(animation: e.animation.copyWith(seriesInTurn: false)),
              0,
              24),
          isNull);
    });

    test("kept", () {
      var a = const ChartAnimation(seriesInTurn: true);
      expect(ChartAnimation.fromJson(a.toJson()).seriesInTurn, isTrue);
      expect(
          const ChartAnimation().toJson().containsKey("seriesInTurn"), isFalse);
    });
  });

  group("the waffle chart", () {
    test("a hundred squares, shared out by the largest remainders", () {
      var cells = waffleCells([1, 1, 1]);
      expect(cells.fold<int>(0, (t, n) => t + n), 100);
      expect(cells, [34, 33, 33]);
      expect(waffleCells([67, 33]), [67, 33]);
      expect(waffleCells([0, 0]), [0, 0]);
    });

    test("drawn: its first square in its first value's colour", () async {
      var e = ChartElement(
        const ElementBase(id: "w", width: 200, height: 200),
        type: ChartType.waffle,
        data: ChartData.parse("Cat\tShare\nPublic\t67\nPrivate\t33"),
        title: "",
      );
      var recorder = ui.PictureRecorder();
      var canvas = Canvas(recorder);
      paintChart(canvas, const Rect.fromLTWH(0, 0, 200, 200), e);
      var image = await recorder.endRecording().toImage(200, 200);
      var bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      // The grid's top left square, in from its corner.
      var area = e.body.rectIn(const Rect.fromLTWH(0, 0, 200, 200));
      var side = area.shortestSide * 0.88;
      var box = Rect.fromCenter(center: area.center, width: side, height: side);
      var p = box.topLeft + Offset(side / 20, side / 20);
      var at = (p.dy.round() * 200 + p.dx.round()) * 4;
      var colour = sliceColour(e, 0);
      expect(bytes.getUint8(at), closeTo((colour.r * 255).round(), 3));
      expect(bytes.getUint8(at + 1), closeTo((colour.g * 255).round(), 3));
      if (const String.fromEnvironment("OUT").isNotEmpty) {
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(const String.fromEnvironment("OUT"))
            .writeAsBytesSync(png!.buffer.asUint8List());
      }
    });

    test("not drawn against axes", () {
      expect(ChartType.waffle.isCircular, isTrue);
      expect(colouredByValue(ChartType.waffle), isTrue);
    });
  });
}

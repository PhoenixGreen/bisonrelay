import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_skew_test.dart is an element slanted: kept, drawn where its box is
// slanted to, clicked there, and slanted by a side handle with the opposite
// side staying put.

ShapeElement _box({double skewX = 0, double skewY = 0, double rotation = 0}) =>
    ShapeElement(
        ElementBase(
            id: "s",
            x: 100,
            y: 100,
            width: 100,
            height: 100,
            rotation: rotation,
            skewX: skewX,
            skewY: skewY),
        fill: const Color(0xFFFF0000),
        strokeWidth: 0);

void main() {
  test("a frame turned and slanted goes there and back", () {
    var f = BoxFrame(30, 20, -10);
    for (var p in const [Offset(10, 0), Offset(-5, 7), Offset(40, -30)]) {
      expect((f.invert(f.apply(p)) - p).distance, lessThan(1e-9));
    }
    expect(BoxFrame(0, 0, 0).upright, isTrue);
  });

  test("a slant is kept, and held within bounds", () {
    var e = _box(skewX: 25, skewY: -10);
    var back = elementFromJson(e.toJson()) as ShapeElement;
    expect(back.base.skewX, 25);
    expect(back.base.skewY, -10);
    expect(e.withBase(skewX: 200).base.skewX, maxSkew);
  });

  test("a slanted box is drawn slanted", () async {
    // Skew X of 45: the top edge leans left of the box, the bottom right.
    var document = CanvasDocument(
        size: const CanvasSize(width: 300, ratio: CanvasRatio.square),
        elements: [_box(skewX: 45)]);
    var image = await renderFrame(document);
    var raw =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
    bool red(int x, int y) {
      var i = (y * image.width + x) * 4;
      return raw[i] > 200 && raw[i + 1] < 60 && raw[i + 2] < 60;
    }

    // Near the top: shifted left of the upright box by most of half its
    // height. Near the bottom: shifted right.
    expect(red(60, 105), isTrue, reason: "top edge leans left");
    expect(red(190, 105), isFalse);
    expect(red(240, 195), isTrue, reason: "bottom edge leans right");
    expect(red(110, 195), isFalse);
    image.dispose();
  });

  group("on the stage", () {
    Future<(CanvasController, GlobalKey<CanvasStageState>)> open(
        WidgetTester tester, ShapeElement e) async {
      var key = GlobalKey<CanvasStageState>();
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 900,
                    height: 700,
                    child: CanvasStage(key: key, controller: c)))),
      ));
      await tester.pumpAndSettle();
      c.selectOnly("s");
      await tester.pumpAndSettle();
      return (c, key);
    }

    testWidgets("with Skew on, the top handle slants it; the bottom stays",
        (tester) async {
      var (c, key) = await open(tester, _box());
      c.skewHandles = true;
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      var before = BoxFrame(0, 0, 0).corners(_box().bounds);
      await tester.dragFrom(
          stage.handleAt(StageHandle.topCenter), Offset(40 * scale, 0));
      await tester.pumpAndSettle();
      var e = c.document.elementById("s")!;
      expect(e.base.skewX, isNot(0), reason: "slanted");
      expect(e.width, 100, reason: "not resized");
      var after =
          BoxFrame(e.rotation, e.base.skewX, e.base.skewY).corners(e.bounds);
      // Corners: top-left, top-right, bottom-right, bottom-left.
      expect((after[3] - before[3]).distance, lessThan(0.5),
          reason: "the bottom stays");
      expect((after[2] - before[2]).distance, lessThan(0.5));
      expect(after[0].dx - before[0].dx, closeTo(40, 0.5),
          reason: "the top went with the pointer");
      c.undo();
      expect(c.document.elementById("s")!.base.skewX, 0, reason: "one step");
    });

    testWidgets("without Skew or a key, a side handle still resizes",
        (tester) async {
      var (c, key) = await open(tester, _box());
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      await tester.dragFrom(
          stage.handleAt(StageHandle.centerRight), Offset(30 * scale, 0));
      await tester.pumpAndSettle();
      var e = c.document.elementById("s")!;
      expect(e.width, closeTo(130, 1));
      expect(e.base.skewX, 0);
    });

    testWidgets("a slanted element is clicked where it is drawn",
        (tester) async {
      var (c, key) = await open(tester, _box(skewX: 45));
      c.clearSelection();
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      // Left of the upright box, where the slanted top reaches.
      await tester.tapAt(stage.toStagePoint(const Offset(70, 105)));
      await tester.pumpAndSettle();
      expect(c.selection, {"s"});
      // Inside the upright box's top-right, which the slant has left.
      c.clearSelection();
      await tester.tapAt(stage.toStagePoint(const Offset(190, 105)));
      await tester.pumpAndSettle();
      expect(c.selection, isEmpty);
    });
  });
}

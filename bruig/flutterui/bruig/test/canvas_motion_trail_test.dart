import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_motion_trail_test.dart is the prototype's trail and onion skin: the
// element whose motion the Chain is open on drawn with the path it takes,
// dashed, and faint copies of where it was -- shown until hidden from the
// Chain's ⋯.

void main() {
  testWidgets("its path is drawn on the stage while its motion is open",
      (tester) async {
    // Across the page from left to right over four seconds.
    var c = CanvasController(
        CanvasDocument(frames: 240, frameRate: 24, elements: [
          ShapeElement(
              const ElementBase(
                  id: "a",
                  x: 50,
                  y: 300,
                  width: 40,
                  height: 40,
                  motion: ElementMotion(clips: [
                    MotionClip(
                        id: "go",
                        kind: MotionKind.action,
                        length: 4,
                        keys: {
                          MotionProp.x: [
                            MotionKey(0, MotionNumber(0)),
                            MotionKey(4, MotionNumber(600)),
                          ],
                        }),
                  ], placed: [
                    ClipPlacement(id: "p", clip: "go", length: 4)
                  ])),
              fill: const Color(0xFF000000)),
        ]),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    c.selectOnly("a");
    c.frame = 48;
    var key = GlobalKey<CanvasStageState>();
    var shot = GlobalKey();
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
              body: RepaintBoundary(
                  key: shot,
                  child: SizedBox(
                      width: 900,
                      height: 700,
                      child: CanvasStage(key: key, controller: c))))),
    ));
    await tester.pumpAndSettle();
    StagePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<StagePainter>()
        .single;
    expect(painter().trail, isFalse, reason: "the Chain shut");
    c.animationOpen = true;
    await tester.pumpAndSettle();
    expect(painter().trail, isTrue, reason: "open on its motion");

    // Ahead of it, where it will be in two seconds: its path, faint green.
    var ahead = key.currentState!.toStagePoint(const Offset(450, 320));
    Future<int> greenThere() async {
      var boundary =
          shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var greenest = 0;
      await tester.runAsync(() async {
        var image = await boundary.toImage();
        var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        // Across a few pixels of the line: the dashes have gaps.
        for (var dx = -12; dx <= 12; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            var x = (ahead.dx + dx).round(), y = (ahead.dy + dy).round();
            var i = (y * image.width + x) * 4;
            var g = raw.getUint8(i + 1) - raw.getUint8(i);
            if (g > greenest) greenest = g;
          }
        }
      });
      return greenest;
    }

    expect(await greenThere(), greaterThan(8), reason: "the dashed path");
    c.motionTrail = false;
    await tester.pumpAndSettle();
    expect(painter().trail, isFalse, reason: "hidden from the ⋯");
    expect(await greenThere(), lessThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_arrival_cut_test.dart is an arrival that never settles, marked on
// the timeline (Ken, 2026-11-12: a 2 s arrival on a 49-frame scene ran the
// whole timeline): its bar as long as it really is, and where the scene
// ends -- or its leave begins -- before it does, hatched with a red edge.

void main() {
  /// cutMarks is how many of the cut's red pixels the timeline shows, with
  /// the scene [frames] long after an arrival made in a long one.
  Future<int> cutMarks(WidgetTester tester, int frames) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var c = CanvasController(
        CanvasDocument(frames: 96, frameRate: 24, elements: [
          ShapeElement(
              const ElementBase(id: "a", name: "Logo", width: 10, height: 10)),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.applyElementAnimation(
        c.document.elementById("a")!, ElementAnimationPreset.fadeUp);
    c.setSceneLength(frames);
    var key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: RepaintBoundary(
                  key: key,
                  child: CanvasTimeline(controller: c, height: 200)))),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    var n = 0;
    await tester.runAsync(() async {
      var b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var img = await b.toImage(pixelRatio: 1);
      var bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        var (r, g, bl) =
            (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
        if ((r - 0xFF).abs() < 6 &&
            (g - 0x5F).abs() < 6 &&
            (bl - 0x52).abs() < 6) {
          n++;
        }
      }
    });
    return n;
  }

  testWidgets("cut off by the scene's end, it is marked", (tester) async {
    expect(await cutMarks(tester, 12), greaterThan(20));
  });

  testWidgets("settled within the scene, it is not", (tester) async {
    expect(await cutMarks(tester, 96), 0);
  });
}

import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/storyboard.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_storyboard_test.dart is the whole run as pictures, each a way back
// into the editor at the moment it shows.

CanvasDocument _three() => const CanvasDocument(scenes: [
      CanvasScene(id: "a", name: "Intro", frames: 50),
      CanvasScene(id: "b", name: "Argument", frames: 200),
      CanvasScene(id: "c", name: "Outro", frames: 50),
    ]);

void main() {
  test("the pictures are taken evenly through each scene, clear of its ends",
      () {
    var frames = storyboardFrames(_three(), 1);
    expect(frames, hasLength(storyboardShots));
    expect(frames.first, greaterThan(0));
    expect(frames.last, lessThan(199));
    for (var i = 1; i < frames.length; i++) {
      expect(frames[i], greaterThan(frames[i - 1]));
    }
  });

  testWidgets("every scene is a row of pictures, and a picture goes there",
      (tester) async {
    var c = CanvasController(_three());
    addTearDown(c.dispose);
    var asked = <int>[];
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: CanvasStoryboard(
                  controller: c,
                  render: (doc, frame) async {
                    asked.add(frame);
                    var r = ui.PictureRecorder();
                    ui.Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 16, 9),
                        Paint()..color = const Color(0xFF2970FF));
                    return r.endRecording().toImage(16, 9);
                  }))),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text("Intro  ·  0:00"), findsOneWidget);
    expect(find.byType(RawImage), findsNWidgets(3 * storyboardShots));
    expect(asked.length, 3 * storyboardShots);
    expect(asked.where((f) => f >= c.document.startOfScene(1)), isNotEmpty,
        reason: "drawn at frames of the run, not of each scene");

    var f = storyboardFrames(c.document, 1)[2];
    await tester.tap(find.byKey(ValueKey("shot-1-$f")));
    await tester.pumpAndSettle();
    expect(c.sceneAt, 1);
    expect(c.frame, f);
  });
}

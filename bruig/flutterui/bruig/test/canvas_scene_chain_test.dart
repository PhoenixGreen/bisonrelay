import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_scene_chain_test.dart is a scene's motion chain as the chain
// prototype has it (Ken, 2026-11-08, "Scene chain yes"): its own clips --
// a Camera's, keying its zoom and where it looks -- with a "+" to put one
// on, a join after them, its Transition, its Camera, and an Output.

CanvasDocument _two() => CanvasDocument(
      frameRate: 24,
      scenes: [
        // How it gives way to the next is the scene's own.
        CanvasScene(
            id: "a",
            name: "Harbour",
            frames: 48,
            transition: const SceneTransition(
                kind: SceneTransitionKind.fade, frames: 12)),
        const CanvasScene(id: "b", name: "Lighthouse", frames: 24),
      ],
    );

Future<void> _show(WidgetTester tester, CanvasController c,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(1800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) =>
                      AnimationPanel(controller: c, height: 360)))),
    )),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (var scale in [1.0, 1.5]) {
    testWidgets(
        "Source, Transition, Camera, Output; a camera put on, at $scale",
        (tester) async {
      var c = CanvasController(_two());
      addTearDown(c.dispose);
      c.pickScene(0);
      await _show(tester, c, scale: scale);
      expect(tester.takeException(), isNull);
      for (var zone in ["Source", "Transition", "Camera", "Output"]) {
        expect(find.byKey(ValueKey("motionZone-$zone")), findsOneWidget,
            reason: zone);
      }
      expect(find.byKey(const ValueKey("sceneCameraCard")), findsOneWidget);
      expect(
          tester
              .widget<Text>(find
                  .descendant(
                      of: find.byKey(const ValueKey("sceneOutputThen")),
                      matching: find.byType(Text))
                  .last)
              .data,
          "Lighthouse, by cross fade");
      expect(
          tester
              .widget<Text>(find
                  .descendant(
                      of: find.byKey(const ValueKey("sceneOutputLength")),
                      matching: find.byType(Text))
                  .last)
              .data,
          "2.0 s");

      // The "+": a Camera on the scene, its clips the Source.
      await tester.tap(find.byKey(const ValueKey("sceneAddCamera")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.document.elements.whereType<CameraElement>(), hasLength(1));
      expect(c.pickedScene, 0, reason: "still on the scene's chain");
      expect(find.byKey(const ValueKey("motionClipsCard")), findsOneWidget);
      expect(find.byKey(const ValueKey("sceneJoin-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("sceneAddCameraCard")), findsNothing);
      expect(find.byKey(const ValueKey("sceneCameraNote")), findsOneWidget,
          reason: "the slow move gives way to the camera's clips");
      expect(find.byKey(const ValueKey("sceneCameraCard")), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("a scene not open is opened to give it a camera", (tester) async {
    var c = CanvasController(_two());
    addTearDown(c.dispose);
    c.pickScene(1);
    await _show(tester, c);
    expect(find.text("Open Lighthouse"), findsOneWidget);
    expect(
        tester
            .widget<Text>(find
                .descendant(
                    of: find.byKey(const ValueKey("sceneOutputThen")),
                    matching: find.byType(Text))
                .last)
            .data,
        "the end");
    await tester.tap(find.byKey(const ValueKey("sceneAddCamera")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.document.at, 1);
    expect(c.pickedScene, 1);
    expect(find.text("+ Camera"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

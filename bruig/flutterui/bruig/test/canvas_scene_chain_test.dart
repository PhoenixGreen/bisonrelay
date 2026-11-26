import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show cameraFraming, sceneFraming;
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_cards.dart'
    show StudioDrop;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_scene_chain_test.dart is a scene's motion chain as the chain
// prototype has it: its own clips --
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
  setTestScreen(tester, const Size(1800, 600));
  await tester.pumpWidget(canvasApp(
      MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) =>
                          AnimationPanel(controller: c, height: 360))))),
      scaffold: false));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (var scale in [0.65, 1.0, 1.5]) {
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

  // While a shown Camera frames the scene, the scene's slow move does
  // nothing, so its card says so in place of its moves; hidden or taken
  // away, the card is back with the move it had.
  for (var scale in [0.65, 1.0, 1.5]) {
    testWidgets(
        "a Camera framing the scene stands in for its slow move, at "
        "$scale", (tester) async {
      var doc = _two().withScene(
          0, _two().scene.copyWith(camera: CameraMove.pushIn.camera(0.3)));
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.pickScene(0);
      await _show(tester, c, scale: scale);
      expect(find.byKey(const ValueKey("cameraMove")), findsOneWidget);

      c.addElement(newElement(ElementKind.camera, c.document), select: false);
      var cam = c.document.elements.whereType<CameraElement>().single;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey("sceneCameraNote")), findsOneWidget);
      for (var k in ["cameraMove", "cameraStrength", "cameraShake"]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      expect(find.textContaining("Framed by Camera"), findsOneWidget);
      expect(sceneFraming(c.document, 10), cameraFraming(cam, 10, c.document),
          reason: "the Camera is what frames it");

      c.replaceElement(cam.withBase(visible: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey("sceneCameraNote")), findsNothing);
      expect(
          tester
              .widget<StudioDrop<CameraMove>>(
                  find.byKey(const ValueKey("cameraMove")))
              .value,
          CameraMove.pushIn,
          reason: "the move it had, kept");
      expect(c.document.scene.camera?.toJson(),
          CameraMove.pushIn.camera(0.3)!.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // Of two Cameras shown, the card names the first in the scene's order,
  // which is the one that frames it, and the next once the first is hidden.
  testWidgets("of two Cameras shown, the card names the one that frames",
      (tester) async {
    var c = CanvasController(_two());
    addTearDown(c.dispose);
    c.pickScene(0);
    c.addElement(
        newElement(ElementKind.camera, c.document).withBase(name: "Wide"),
        select: false);
    c.addElement(
        newElement(ElementKind.camera, c.document).withBase(name: "Close"),
        select: false);
    await _show(tester, c);
    expect(find.textContaining("Framed by Wide"), findsOneWidget);
    expect(find.textContaining("Framed by Close"), findsNothing);

    var wide = c.document.elements.firstWhere((e) => e.name == "Wide");
    c.replaceElement(wide.withBase(visible: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining("Framed by Close"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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

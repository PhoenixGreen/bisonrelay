import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/layer_blend.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_element_blend_test.dart is the motion chain's Output Blend: an
// element laid over what is under it -- multiplied, screened, added -- as
// the prototype's Output has it.

ShapeElement _box(String id, Color fill,
        {LayerBlend blend = LayerBlend.normal}) =>
    ShapeElement(
        ElementBase(id: id, x: 0, y: 0, width: 300, height: 300, blend: blend),
        fill: fill,
        strokeWidth: 0);

CanvasDocument _page(List<CanvasElement> elements) => CanvasDocument(
    frames: 24,
    frameRate: 24,
    size: const CanvasSize(width: 300, ratio: CanvasRatio.square),
    elements: elements);

Future<List<int>> _middle(CanvasDocument doc) async {
  var image = await renderFrame(doc);
  var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var at = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return [for (var i = 0; i < 3; i++) raw.getUint8(at + i)];
}

void main() {
  test("multiplied over what is under it, and kept", () async {
    const blue = Color(0xFF0000FF), red = Color(0xFFFF0000);
    var normal = await _middle(_page([_box("b", blue), _box("r", red)]));
    expect(normal, [255, 0, 0], reason: "red over blue, as it is");
    var multiplied = await _middle(
        _page([_box("b", blue), _box("r", red, blend: LayerBlend.multiply)]));
    expect(multiplied, [0, 0, 0], reason: "red times blue is nothing");
    var screened = await _middle(
        _page([_box("b", blue), _box("r", red, blend: LayerBlend.screen)]));
    expect(screened, [255, 0, 255], reason: "screened: both, brighter");

    var e = _box("r", red, blend: LayerBlend.multiply);
    expect(elementFromJson(e.toJson()).base.blend, LayerBlend.multiply);
    expect(_box("b", blue).toJson().toString(), isNot(contains("blend")),
        reason: "normal, as before, saved as it was");
  });

  for (var scale in [1.0, 1.5]) {
    testWidgets("the Output card sets the blend, at $scale", (tester) async {
      tester.view.physicalSize = const Size(3000, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(_page([_box("r", const Color(0xFFFF0000))]));
      addTearDown(c.dispose);
      var id = c.newClip("r", kind: MotionKind.arrive, slot: 0);
      c.pickMotion("r", id);
      c.selectOnly("r");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: 400)))),
      ));
      await tester.pumpAndSettle();
      var blend = find.byKey(const ValueKey("motionOutputBlend"));
      await tester.ensureVisible(blend);
      tester.widget<StudioDrop<LayerBlend>>(blend).onChanged(LayerBlend.screen);
      await tester.pumpAndSettle();
      expect(c.document.elementById("r")!.base.blend, LayerBlend.screen);
      c.undo();
      expect(c.document.elementById("r")!.base.blend, LayerBlend.normal);
      expect(tester.takeException(), isNull);
    });
  }
}

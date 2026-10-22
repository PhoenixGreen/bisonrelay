import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/svg_import.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_vector_tint_test.dart is a drawing laid over with one colour.
//
// The point of VectorElement.tint is that recolouring an icon no longer
// takes it apart: a black stock icon in a video's teal stays a reference to
// its file, rather than a copy of every outline in it.

const _teal = Color(0xFF2ED6A1);

/// _square is a black square in the left half of a 100x100 drawing, the
/// right half left empty.
VectorElement _square({Color? tint}) {
  var svg =
      importSvg('<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="0" y="0" width="50" height="100" fill="#000000"/></svg>')!;
  return VectorElement(const ElementBase(id: "v", width: 100, height: 100),
      assetId: "icon.svg",
      viewBox: svg.viewBox,
      shapes: svg.shapes,
      tint: tint);
}

Future<Color> _at(VectorElement e, int x, int y) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = const Color(0xFFFFFFFF));
  paintVector(canvas, const Rect.fromLTWH(0, 0, 100, 100), e, null);
  var image = await recorder.endRecording().toImage(100, 100);
  var bytes = (await image.toByteData())!;
  var p = bytes.getUint32((y * 100 + x) * 4);
  image.dispose();
  return Color(((p & 0xFF) << 24) | (p >> 8));
}

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  test("the tint is saved, and nothing is written without one", () {
    var back = VectorElement.fromJson(
        _square(tint: _teal).toJson(), const ElementBase(id: "v"));
    expect(back.tint, _teal);
    expect(_square().toJson().containsKey("tint"), isFalse);
    expect(_square(tint: _teal).copyWith(clearTint: true).tint, isNull);
  });

  test("a tinted drawing is drawn in the tint, and its gaps stay gaps",
      () async {
    expect(await _at(_square(), 25, 50), const Color(0xFF000000));
    expect(await _at(_square(tint: _teal), 25, 50), _teal);
    expect(await _at(_square(tint: _teal), 75, 50), const Color(0xFFFFFFFF),
        reason: "the empty half is not filled with the tint");
  });

  testWidgets("choosing a tint keeps the drawing a reference to its file",
      (tester) async {
    var e = const VectorElement(ElementBase(id: "v", width: 100, height: 100),
        assetId: "icon.svg");
    var controller = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(controller.dispose);
    controller.selectOnly("v");
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(body: CanvasDesignPanel(controller: controller))),
    ));
    await tester.pumpAndSettle();

    tester
        .widget<CanvasColorButton>(find.byKey(const ValueKey("vectorTint")))
        .onChanged(_teal);
    await tester.pumpAndSettle();
    var tinted = controller.document.elements.single as VectorElement;
    expect(tinted.tint, _teal);
    expect(tinted.shapes, isNull, reason: "not taken apart");

    await tester.ensureVisible(find.byKey(const ValueKey("vectorTintOff")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("vectorTintOff")));
    await tester.pumpAndSettle();
    expect((controller.document.elements.single as VectorElement).tint, isNull);
  });
}

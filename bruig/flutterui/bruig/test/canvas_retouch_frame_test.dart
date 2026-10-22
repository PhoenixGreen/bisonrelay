// canvas_retouch_frame_test.dart is retouching across the whole frame: a
// clone from a picture layer over the base picture, painted out past the
// base picture, copies what is seen and lands on top of it.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<ui.Image> _pic(int w, int h, List<int> Function(int, int) f) {
  var px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      px.setRange((y * w + x) * 4, (y * w + x) * 4 + 4, f(x, y));
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

void main() {
  testWidgets("cloning every layer copies what is seen, past the base picture",
      (tester) async {
    var key = GlobalKey<CanvasStageState>();
    // A frame 400 wide, the base picture -- red -- only in its middle 100.
    var e = ImageElement(
        const ElementBase(id: "i", x: 0, y: 0, width: 400, height: 400),
        assetId: "red",
        fit: ImageFit.stretch,
        layers: [
          ImageLayer.base
              .copyWith(basePlace: const Rect.fromLTWH(375, 375, 250, 250)),
          // Blue over the middle of the red: what is seen there.
          ImageLayer.picture("blue", const Rect.fromLTWH(400, 400, 200, 200)),
        ]);
    var c = CanvasController(const CanvasDocument(
            size: CanvasSize(width: 400, ratio: CanvasRatio.square))
        .addElement(e));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(800, 800);
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
                body: SizedBox(
                    width: 800,
                    height: 800,
                    child: CanvasStage(key: key, controller: c))))));
    await tester.runAsync(() async {
      c.images.putForTest("red", await _pic(8, 8, (x, y) => [255, 0, 0, 255]));
      c.images.putForTest("blue", await _pic(8, 8, (x, y) => [0, 0, 255, 255]));
    });
    await tester.pumpAndSettle();
    c.selectOnly("i");
    c.editImage("i");
    c.imageTool = ImageTool.clone;
    c.retouchWholeFrame = true;
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    var scale = stage.pageRect.width / c.document.size.width;
    Offset screen(Offset p) => stage.pageRect.topLeft + p * scale;
    // Option-click the middle of the red picture (200,200), then paint at (80,80) -- outside it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.tapAt(screen(const Offset(200, 200)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    await tester.dragFrom(screen(const Offset(80, 80)), Offset(0, 30 * scale));
    await tester.pumpAndSettle();
    var now = c.document.elementById("i") as ImageElement;
    expect(now.stack.last.name, "Retouch", reason: "on top of the picture");
    expect(now.stack.last.strokes.single.kind, StrokeKind.clone);
    await tester.runAsync(() async {
      var img = await renderFrame(c.document, images: c.images);
      var raw =
          (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
              .buffer
              .asUint8List();
      List<int> at(int x, int y) {
        var i = (y * img.width + x) * 4;
        return [raw[i], raw[i + 1], raw[i + 2], raw[i + 3]];
      }

      expect(at(80, 95), [0, 0, 255, 255],
          reason: "the blue seen where it copied from, not the red under it");
      expect(at(30, 30), isNot([0, 0, 255, 255]), reason: "only where it went");
    });
  });
}

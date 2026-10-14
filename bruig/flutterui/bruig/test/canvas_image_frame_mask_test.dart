import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_image_frame_mask_test.dart is a mask on a layer that is not a
// picture -- an adjustment, a texture, a colour -- painted over the frame.

class _Pictures implements CanvasImageSource {
  final Map<String, ui.Image> images;
  _Pictures(this.images);
  @override
  bool get loading => false;
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      images[assetId];
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

Future<ui.Image> _solid(List<int> c) {
  var pixels = Uint8List(8 * 8 * 4);
  for (var i = 0; i < 64; i++) {
    for (var k = 0; k < 4; k++) {
      pixels[i * 4 + k] = c[k];
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, 8, 8, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _leftHalf hides the left half of the frame.
const _leftHalf = ImageMask(marks: [
  MaskMark(
      kind: MaskMarkKind.lasso,
      points: [Offset(0, 0), Offset(0.5, 0), Offset(0.5, 1), Offset(0, 1)])
]);

const _box = ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100);

void main() {
  test("a layer's mask is saved with it", () {
    var layer = ImageLayer.adjusting(AdjustKind.invert).copyWith(mask: _leftHalf);
    var back = ImageLayer.fromJson(layer.toJson())!;
    expect(back.mask.marks.single.kind, MaskMarkKind.lasso);
    expect(back.framed, isTrue);
    expect(_picture().framed, isFalse);
  });

  group("drawing", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({"red": await _solid([255, 0, 0, 255])});
    });

    Future<List<int>> pixel(ImageElement e, int x, int y) async {
      var image = await renderFrame(
          CanvasDocument(
              size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
              elements: [e]),
          images: images);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var p = raw!.buffer.asUint8List();
        var i = (y * 100 + x) * 4;
        return [p[i], p[i + 1], p[i + 2]];
      } finally {
        image.dispose();
      }
    }

    ImageElement over(ImageLayer layer) => ImageElement(_box,
        assetId: "red", fit: ImageFit.stretch, layers: [ImageLayer.base, layer]);

    test("a masked adjustment adjusts only where its mask shows", () async {
      var e = over(
          ImageLayer.adjusting(AdjustKind.invert).copyWith(mask: _leftHalf));
      expect(await pixel(e, 25, 50), [255, 0, 0], reason: "masked away");
      expect(await pixel(e, 75, 50), [0, 255, 255], reason: "inverted");
    });

    test("a masked colour layer covers only where its mask shows", () async {
      var e = over(ImageLayer.solid(const PaintSpec(ui.Color(0xFF00FF00)))
          .copyWith(mask: _leftHalf));
      expect(await pixel(e, 25, 50), [255, 0, 0]);
      expect(await pixel(e, 75, 50), [0, 255, 0]);
    });

    test("a fade on a texture's mask fades it in across the frame", () async {
      var e = over(ImageLayer.solid(const PaintSpec(ui.Color(0xFF0000FF)))
          .copyWith(
              mask: const ImageMask(marks: [
        MaskMark(kind: MaskMarkKind.fade, points: [Offset(0, 0), Offset(1, 0)])
      ])));
      var left = await pixel(e, 5, 50), right = await pixel(e, 95, 50);
      expect(left[0], greaterThan(200), reason: "the red there");
      expect(right[2], greaterThan(200), reason: "the blue there");
    });
  });

  testWidgets("the lasso masks a picked adjustment over the frame",
      (tester) async {
    var adjust = ImageLayer.adjusting(AdjustKind.invert);
    var key = GlobalKey<CanvasStageState>();
    var c = CanvasController(const CanvasDocument().addElement(ImageElement(
        const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
        assetId: "red",
        fit: ImageFit.stretch,
        layers: [ImageLayer.base, adjust])));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(800, 600);
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
                  height: 600,
                  child: CanvasStage(key: key, controller: c)))),
    ));
    await tester.runAsync(() async {
      c.images.putForTest("red", await _solid([255, 0, 0, 255]));
    });
    c.selectOnly("i");
    c.editImage("i", layer: adjust.id);
    c.imageTool = ImageTool.lasso;
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    var scale = stage.pageRect.width / c.document.size.width;
    Offset screen(Offset p) => stage.pageRect.topLeft + p * scale;
    var g = await tester.startGesture(screen(const Offset(100, 100)));
    for (var p in const [Offset(200, 100), Offset(200, 300), Offset(100, 300)]) {
      await g.moveTo(screen(p));
    }
    await g.up();
    await tester.pumpAndSettle();
    var layer = (c.document.elementById("i")! as ImageElement)
        .layerById(adjust.id)!;
    var mark = layer.mask.marks.single;
    expect(mark.points.first.dx, closeTo(0, 0.02));
    expect(mark.points[1].dx, closeTo(0.5, 0.02),
        reason: "a fraction of the frame");

    // Select subject has no picture to look in, and says so.
    c.imageTool = ImageTool.subject;
    await tester.pumpAndSettle();
    await tester.tapAt(screen(const Offset(200, 200)));
    await tester.pumpAndSettle();
    expect(c.maskNote, contains("looks for a subject"));
  });
}

ImageLayer _picture() =>
    ImageLayer.picture("red", const Rect.fromLTWH(0, 0, 500, 500));

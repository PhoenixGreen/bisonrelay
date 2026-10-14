import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_image_adjust_test.dart is an adjustment layer: saved, drawn through
// the real shader over what is under it, and set from the panel.

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

Future<ui.Image> _picture(int w, int h, List<int> Function(int x, int y) f) {
  var pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var p = f(x, y);
      var i = (y * w + x) * 4;
      for (var c = 0; c < 4; c++) {
        pixels[i + c] = p[c];
      }
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

const _box = ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100);

void main() {
  group("saving", () {
    test("an adjustment layer comes back as it was", () {
      var layer = ImageLayer.adjusting(AdjustKind.curves).copyWith(
          adjust: const ImageAdjustment(kind: AdjustKind.curves)
              .withCurve(CurveChannel.red, const [
                Offset(0, 0),
                Offset(0.5, 0.7),
                Offset(1, 1)
              ])
              .withValue("unused", 3)
              .copyWith(colour: const ui.Color(0xFF112233)),
          opacity: 0.4);
      var e = ImageElement(_box,
          assetId: "red", layers: [ImageLayer.base, layer]);
      var back = (elementFromJson(e.toJson()) as ImageElement).layers[1];
      expect(back.kind, LayerKind.adjustment);
      expect(back.opacity, 0.4);
      expect(back.adjust.kind, AdjustKind.curves);
      expect(back.adjust.curve(CurveChannel.red)[1], const Offset(0.5, 0.7));
      expect(back.adjust.curve(CurveChannel.green),
          const [Offset(0, 0), Offset(1, 1)],
          reason: "an untouched channel is the straight line");
    });

    test("a setting is held to its range, and starts where its kind says", () {
      var a = const ImageAdjustment(kind: AdjustKind.levels);
      expect(a.value("inWhite"), 1);
      expect(a.withValue("gamma", 99).value("gamma"), 4);
    });
  });

  group("curves", () {
    test("the straight line is the straight line", () {
      for (var x = 0.0; x <= 1; x += 0.1) {
        expect(curveAt(const [Offset(0, 0), Offset(1, 1)], x),
            closeTo(x, 1e-9));
      }
    });

    test("an S curve passes through its points and never overshoots", () {
      const s = [Offset(0, 0), Offset(0.25, 0.15), Offset(0.75, 0.85), Offset(1, 1)];
      expect(curveAt(s, 0.25), closeTo(0.15, 1e-9));
      expect(curveAt(s, 0.75), closeTo(0.85, 1e-9));
      var last = -1.0;
      for (var x = 0.0; x <= 1; x += 0.01) {
        var y = curveAt(s, x);
        expect(y, greaterThanOrEqualTo(last - 1e-9), reason: "rising at $x");
        expect(y, inInclusiveRange(0, 1));
        last = y;
      }
    });
  });

  group("drawing", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({
        "red": await _picture(8, 8, (x, y) => [255, 0, 0, 255]),
        "blue": await _picture(8, 8, (x, y) => [0, 0, 255, 255]),
        "grey": await _picture(8, 8, (x, y) => [100, 100, 100, 255]),
        // Red on the left, yellow on the right.
        "kit": await _picture(
            8, 8, (x, y) => x < 4 ? [220, 20, 20, 255] : [240, 200, 20, 255]),
      });
    });

    Future<List<int>> pixel(ImageElement e, int x, int y) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var p = raw!.buffer.asUint8List();
        var i = (y * image.width + x) * 4;
        return [p[i], p[i + 1], p[i + 2]];
      } finally {
        image.dispose();
      }
    }

    ImageElement over(String base, List<ImageLayer> layers) => ImageElement(
        _box,
        assetId: base,
        fit: ImageFit.stretch,
        layers: [ImageLayer.base, ...layers]);

    ImageLayer adjusting(ImageAdjustment a) =>
        ImageLayer.adjusting(a.kind).copyWith(adjust: a);

    void near(List<int> got, List<int> want, {int by = 6, String? reason}) {
      for (var c = 0; c < 3; c++) {
        expect(got[c], closeTo(want[c], by), reason: reason ?? "$got ≈ $want");
      }
    }

    test("invert", () async {
      near(
          await pixel(
              over("red", [
                adjusting(const ImageAdjustment(kind: AdjustKind.invert))
              ]),
              50,
              50),
          [0, 255, 255]);
    });

    test("threshold", () async {
      var a = const ImageAdjustment(kind: AdjustKind.threshold);
      near(await pixel(over("grey", [adjusting(a)]), 50, 50), [0, 0, 0]);
      near(
          await pixel(over("grey", [adjusting(a.withValue("level", 0.2))]),
              50, 50),
          [255, 255, 255]);
    });

    test("a hue turned a third of the way round makes red green", () async {
      var a = const ImageAdjustment(kind: AdjustKind.hueSaturation)
          .withValue("hue", 120);
      near(await pixel(over("red", [adjusting(a)]), 50, 50), [0, 255, 0]);
    });

    test("keep one colour greys everything but it", () async {
      var a = const ImageAdjustment(
          kind: AdjustKind.keepColour, colour: ui.Color(0xFFF0C814));
      var e = over("kit", [adjusting(a)]);
      var kept = await pixel(e, 80, 50), greyed = await pixel(e, 20, 50);
      near(kept, [240, 200, 20], reason: "the yellow kept");
      expect((greyed[0] - greyed[1]).abs(), lessThan(8),
          reason: "the red gone grey: $greyed");
    });

    test("a curve turned upside down inverts", () async {
      var a = const ImageAdjustment(kind: AdjustKind.curves)
          .withCurve(CurveChannel.rgb, const [Offset(0, 1), Offset(1, 0)]);
      near(await pixel(over("red", [adjusting(a)]), 50, 50), [0, 255, 255]);
      // And one channel's alone moves only that channel.
      var b = const ImageAdjustment(kind: AdjustKind.curves)
          .withCurve(CurveChannel.green, const [Offset(0, 1), Offset(1, 1)]);
      near(await pixel(over("red", [adjusting(b)]), 50, 50), [255, 255, 0]);
    });

    test("levels stretch a grey to white", () async {
      var a = const ImageAdjustment(kind: AdjustKind.levels)
          .withValue("inWhite", 100 / 255);
      near(await pixel(over("grey", [adjusting(a)]), 50, 50), [255, 255, 255]);
    });

    test("a gradient map paints brightness in its colours", () async {
      var a = const ImageAdjustment(
          kind: AdjustKind.gradientMap,
          fade: PaintSpec(ui.Color(0xFF0000FF),
              gradient: GradientSpec(to: ui.Color(0xFFFFFF00))));
      // Pure blue is dark: near the blue end.
      var p = await pixel(over("blue", [adjusting(a)]), 50, 50);
      expect(p[2], greaterThan(p[0]));
    });

    test("opacity lets the unadjusted show through", () async {
      var layer = adjusting(const ImageAdjustment(kind: AdjustKind.invert))
          .copyWith(opacity: 0.5);
      near(await pixel(over("red", [layer]), 50, 50), [128, 128, 128],
          by: 8);
    });

    test("only what is under it is adjusted", () async {
      var e = over("red", [
        adjusting(const ImageAdjustment(kind: AdjustKind.invert)),
        ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 500, 500)),
      ]);
      near(await pixel(e, 25, 25), [0, 0, 255], reason: "the blue over it");
      near(await pixel(e, 75, 75), [0, 255, 255], reason: "the red under it");
    });

    test("clipped, it adjusts only the layer it is clipped to", () async {
      var e = over("red", [
        ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 500, 500)),
        adjusting(const ImageAdjustment(kind: AdjustKind.invert))
            .copyWith(clip: true),
      ]);
      near(await pixel(e, 25, 25), [255, 255, 0], reason: "the blue inverted");
      near(await pixel(e, 75, 75), [255, 0, 0], reason: "the red left alone");
    });

    test("two adjustments stack, and a hidden one does nothing", () async {
      var invert = adjusting(const ImageAdjustment(kind: AdjustKind.invert));
      near(
          await pixel(
              over("red", [
                invert,
                ImageLayer.adjusting(AdjustKind.invert),
              ]),
              50,
              50),
          [255, 0, 0]);
      near(
          await pixel(over("red", [invert.copyWith(visible: false)]), 50, 50),
          [255, 0, 0]);
    });
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(
          const ImageElement(_box, assetId: "red", fit: ImageFit.stretch)));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(
              create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    ImageLayer adjustment(CanvasController c) =>
        (c.document.elementById("i")! as ImageElement)
            .stack
            .firstWhere((l) => l.kind == LayerKind.adjustment);


    testWidgets("an adjustment is added, picked, and set", (tester) async {
      var c = await pumpPanel(tester);
      await addLayer(tester, "imageAddAdjustment");
      expect(c.imageEditing, "i");
      expect(c.pickedLayer?.kind, LayerKind.adjustment);
      expect(find.byKey(const ValueKey("adjustKind")), findsOneWidget);

      var hue = tester
          .widget<CanvasStepper>(find.byKey(const ValueKey("adjust-hue")));
      hue.onChanged(90);
      hue.onCommit?.call();
      await tester.pumpAndSettle();
      expect(adjustment(c).adjust.value("hue"), 90);

      var sat = tester.widget<CanvasStepper>(
          find.byKey(const ValueKey("adjust-saturation")));
      sat.onChanged(-50);
      sat.onCommit?.call();
      await tester.pumpAndSettle();
      expect(adjustment(c).adjust.value("saturation"), closeTo(-0.5, 1e-9),
          reason: "shown as a percentage, kept as a fraction");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a click on the curve puts a point down and drags it",
        (tester) async {
      var c = await pumpPanel(tester);
      await addLayer(tester, "imageAddAdjustment");
      var layer = c.pickedLayer!;
      var e = c.document.elementById("i")! as ImageElement;
      c.changeImage(e.withLayer(layer.id,
          (l) => l.copyWith(adjust: const ImageAdjustment(kind: AdjustKind.curves))));
      await tester.pumpAndSettle();

      var square = find.byKey(const ValueKey("curveSquare"));
      await tester.ensureVisible(square);
      var box = tester.getRect(square);
      // A point put down at the middle and lifted a quarter.
      await tester.dragFrom(box.center, Offset(0, -box.height / 4));
      await tester.pumpAndSettle();
      var points = adjustment(c).adjust.curve(CurveChannel.rgb);
      expect(points, hasLength(3));
      expect(points[1].dx, closeTo(0.5, 0.05));
      expect(points[1].dy, greaterThan(0.65));

      c.undo();
      expect(adjustment(c).adjust.curves, isEmpty, reason: "one undo step");
      expect(tester.takeException(), isNull);
    });
  });
}

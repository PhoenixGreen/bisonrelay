import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_warp_test.dart is a picture bent by a grid of points: the curve
// through them, the grid made finer without losing the shape, kept, and
// drawn bent.

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
      pixels.setRange((y * w + x) * 4, (y * w + x) * 4 + 4, f(x, y));
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _pulled is a 4 by 4 grid with its middle column moved [by] across.
ImageWarp _pulled(double by) {
  var even = ImageWarp.even(4, 4);
  return even.withPoints([
    for (var (k, p) in even.points.indexed) k % 5 == 2 ? p + Offset(by, 0) : p
  ]);
}

void main() {
  test("an even grid bends nothing; a moved point is passed through", () {
    expect(const ImageWarp().active, isFalse);
    expect(ImageWarp.even(4, 4).active, isFalse);
    var w = _pulled(0.2);
    expect(w.active, isTrue);
    expect(w.sample(0.5, 0.5).dx, closeTo(0.7, 1e-9), reason: "through it");
    expect(w.sample(0, 0.5).dx, closeTo(0, 1e-9), reason: "edges stay");
    // Between points, a smooth curve: the next point along leans the same
    // way, less.
    var near = w.sample(0.375, 0.5).dx;
    expect(near, greaterThan(0.375));
    expect(near, lessThan(0.575));
  });

  test("made finer or coarser, the shape is kept", () {
    var w = _pulled(0.2);
    var finer = w.regridded(8, 8);
    for (var (u, v) in const [(0.5, 0.5), (0.3, 0.7), (0.9, 0.1)]) {
      expect((finer.sample(u, v) - w.sample(u, v)).distance, lessThan(0.02),
          reason: "($u, $v)");
    }
    expect(finer.cols, 8);
    expect(ImageWarp.even(4, 4).regridded(9, 2).active, isFalse);
  });

  test("a warp is kept with its picture", () {
    var e = ImageElement(const ElementBase(id: "i"),
        assetId: "a", warp: _pulled(0.25).regridded(6, 3));
    var back = elementFromJson(e.toJson()) as ImageElement;
    expect([back.warp.cols, back.warp.rows], [6, 3]);
    for (var (k, p) in back.warp.points.indexed) {
      expect((p - e.warp.points[k]).distance, lessThan(1e-4),
          reason: "kept to five places");
    }
    var plain = elementFromJson(
            const ImageElement(ElementBase(id: "j"), assetId: "a").toJson())
        as ImageElement;
    expect(plain.warp.active, isFalse);
  });

  test("a picture is drawn bent through its points", () async {
    var images = _Pictures({
      // Red on the left half, blue on the right.
      "halves": await _picture(
          20, 20, (x, y) => x < 10 ? [255, 0, 0, 255] : [0, 0, 255, 255]),
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

    ImageElement halves([ImageWarp warp = const ImageWarp()]) =>
        ImageElement(const ElementBase(id: "i", width: 100, height: 100),
            assetId: "halves", fit: ImageFit.stretch, warp: warp);
    expect(await pixel(halves(), 62, 50), [0, 0, 255], reason: "blue, flat");
    // The middle -- where red meets blue -- pulled a fifth to the right: red
    // where blue was, the edges where they were.
    expect(await pixel(halves(_pulled(0.2)), 62, 50), [255, 0, 0],
        reason: "red, bent");
    expect(await pixel(halves(_pulled(0.2)), 95, 50), [0, 0, 255]);
    expect(await pixel(halves(_pulled(0.2)), 5, 50), [255, 0, 0]);
  });

  group("worked on, on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> open(
        WidgetTester tester) async {
      var key = GlobalKey<CanvasStageState>();
      var c = CanvasController(const CanvasDocument().addElement(
          const ImageElement(
              ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
              assetId: "grey",
              fit: ImageFit.stretch)));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(800, 600);
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
                body: SizedBox(
                    width: 800,
                    height: 600,
                    child: CanvasStage(key: key, controller: c)))),
      ));
      await tester.runAsync(() async {
        c.images.putForTest(
            "grey", await _picture(8, 8, (x, y) => [128, 128, 128, 255]));
      });
      await tester.pumpAndSettle();
      // A click on the stage first, for the keys to reach it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      c.selectOnly("i");
      c.editWarp("i", "base");
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      return (c, (Offset p) => stage.pageRect.topLeft + p * scale);
    }

    ImageWarp warp(CanvasController c) =>
        (c.document.elementById("i")! as ImageElement).warp;

    testWidgets("a point dragged bends the picture, in one step",
        (tester) async {
      var (c, screen) = await open(tester);
      expect(c.warpLayer, "base");
      // The middle point of the 4 by 4 grid, at (200, 200) on the page.
      var scale = (screen(const Offset(1, 0)) - screen(Offset.zero)).dx;
      await tester.dragFrom(
          screen(const Offset(200, 200)), Offset(30 * scale, 0));
      await tester.pumpAndSettle();
      var w = warp(c);
      expect(w.active, isTrue);
      expect(w.points[12].dx, closeTo(0.65, 0.01), reason: "moved 30 of 200");
      expect(c.warpPicks, {12});
      c.undo();
      expect(warp(c).active, isFalse, reason: "one step");
    });

    testWidgets("points boxed are picked, sized together, and nudged",
        (tester) async {
      var (c, screen) = await open(tester);
      var scale = (screen(const Offset(1, 0)) - screen(Offset.zero)).dx;
      // A box round the middle nine points of the grid, (150..250, 150..250),
      // started well away from any point.
      await tester.dragFrom(
          screen(const Offset(125, 125)), Offset(140 * scale, 140 * scale));
      await tester.pumpAndSettle();
      expect(c.warpPicks.length, 9);
      // Their box's bottom-right corner, pulled out: sized about the middle.
      await tester.dragFrom(
          screen(const Offset(250, 250)), Offset(25 * scale, 25 * scale));
      await tester.pumpAndSettle();
      var w = warp(c);
      expect(w.points[12], const Offset(0.5, 0.5), reason: "the middle stays");
      expect(w.points[18].dx, greaterThan(0.75 + 0.05), reason: "pushed out");
      expect(w.points[0], Offset.zero, reason: "a point not picked stays");
      // And nudged.
      var before = warp(c).points[12];
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(warp(c).points[12].dx, closeTo(before.dx + 1 / 200, 1e-6));
    });

    testWidgets("Escape lets the picks go, then the grid", (tester) async {
      var (c, _) = await open(tester);
      c.warpPicks = {3, 4};
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.warpPicks, isEmpty);
      expect(c.warpLayer, "base");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.warpLayer, isNull);
      expect(c.imageEditing, "i", reason: "the picture still open");
    });
  });

  testWidgets("the Warp tool shows the grid, and makes it finer",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    CanvasSection.openAll = true;
    addTearDown(() => CanvasSection.openAll = false);
    var c = CanvasController(const CanvasDocument().addElement(
        const ImageElement(ElementBase(id: "i", width: 200, height: 200),
            assetId: "abcdefghij123456")));
    addTearDown(c.dispose);
    c.selectOnly("i");
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
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
          home: Scaffold(
              body: SizedBox(
                  width: 420, child: CanvasDesignPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("imageWarpCols")), findsNothing);
    var toggle = find.byKey(const ValueKey("positionTool-warp"));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.warpLayer, "base");
    expect(c.imageEditing, "i", reason: "the picture opened for it");
    var cols = find.byKey(const ValueKey("imageWarpCols"));
    await tester.ensureVisible(cols);
    await typeInto(tester, cols, "6");
    expect((c.document.elementById("i")! as ImageElement).warp.cols, 6);
    // Another tool puts the grid away.
    var place = find.byKey(const ValueKey("positionTool-place"));
    await tester.ensureVisible(place);
    await tester.tap(place);
    await tester.pumpAndSettle();
    expect(c.warpLayer, isNull);
    expect(tester.takeException(), isNull);
  });
}

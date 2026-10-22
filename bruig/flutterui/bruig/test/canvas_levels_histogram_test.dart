import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_levels_histogram_test.dart is a levels adjustment's histogram:
// counted from what is under it, and its handles setting the levels.

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

/// _halves is dark grey on the left and light grey on the right.
Future<ui.Image> _halves() {
  var pixels = Uint8List(20 * 20 * 4);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 20; x++) {
      var i = (y * 20 + x) * 4;
      var v = x < 10 ? 40 : 200;
      pixels[i] = v;
      pixels[i + 1] = v;
      pixels[i + 2] = v;
      pixels[i + 3] = 255;
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, 20, 20, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

ImageElement _levelled(ImageLayer levels) => ImageElement(
    const ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
    assetId: "halves",
    fit: ImageFit.stretch,
    layers: [ImageLayer.base, levels]);

void main() {
  test("the count is of what is under the layer", () async {
    var levels = ImageLayer.adjusting(AdjustKind.levels);
    var bins = await histogramOf(
        _levelled(levels), levels.id, _Pictures({"halves": await _halves()}));
    expect(bins, isNotNull);
    var total = bins!.reduce((a, b) => a + b);
    int near(int v) =>
        [for (var i = v - 2; i <= v + 2; i++) bins[i]].reduce((a, b) => a + b);
    // Two greys, and nothing much between but the line where they meet.
    expect(near(40) + near(200), greaterThan(total * 0.85));
    expect(near(40), closeTo(near(200), total * 0.08));
  });

  testWidgets("the handles set the levels", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var levels = ImageLayer.adjusting(AdjustKind.levels);
    var c =
        CanvasController(const CanvasDocument().addElement(_levelled(levels)));
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      c.images.putForTest("halves", await _halves());
    });
    c.selectOnly("i");
    c.editImage("i", layer: levels.id);
    tester.view.physicalSize = const Size(900, 4000);
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
    var plot = find.byKey(const ValueKey("levelsHistogram"));
    await tester.ensureVisible(plot);
    await tester.pumpAndSettle();
    var box = tester.getRect(plot);
    ImageAdjustment now() => (c.document.elementById("i")! as ImageElement)
        .layerById(levels.id)!
        .adjust;

    // The black handle, from the left edge to a fifth of the way.
    await tester.dragFrom(
        box.bottomLeft + const Offset(1, -4), Offset(box.width * 0.2, 0));
    await tester.pumpAndSettle();
    expect(now().value("inBlack"), closeTo(0.2, 0.03));

    // The white handle, from the right edge in to four fifths.
    await tester.dragFrom(
        box.bottomRight + const Offset(-1, -4), Offset(-box.width * 0.2, 0));
    await tester.pumpAndSettle();
    expect(now().value("inWhite"), closeTo(0.8, 0.03));

    // The middle, towards the black: the midtones lighter -- gamma over one.
    var mid = box.left + box.width * 0.5;
    await tester.dragFrom(
        Offset(mid, box.bottom - 4), Offset(-box.width * 0.15, 0));
    await tester.pumpAndSettle();
    expect(now().value("gamma"), greaterThan(1.1));

    c.undo();
    expect(now().value("gamma"), 1, reason: "each drag one step");
    expect(tester.takeException(), isNull);
  });
}

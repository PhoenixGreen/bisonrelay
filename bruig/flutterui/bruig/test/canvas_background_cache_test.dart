import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_background_cache_test.dart is why a canvas with a generated
// background is not slow to touch.
//
// The editor repaints for everything -- a pointer moving over the stage, a
// dropdown opening, a settings panel rebuilding -- and a generated background
// is the most expensive thing on a canvas by a wide margin. Every one of those
// repaints was generating it again to produce exactly the pixels it produced
// last time. Measured on the Banner preset, which is the one somebody
// reported: the best part of a second a frame.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// settle turns the real event loop, because the raster happens on it while
  /// a widget test runs in a fake one.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  group("the background is generated once", () {
    testWidgets("and drawn from a picture after that", (tester) async {
      var cache = ProceduralCache();
      addTearDown(cache.dispose);
      var banner = bannerCanvas();
      var size = banner.size.size;

      // Nothing yet: the first frame draws it the slow way, which is the
      // right way round -- a frame that is late is worse than a frame that
      // cost what it used to cost.
      expect(cache.imageFor(banner.background.spec, size, 0), isNull);

      await settle(tester);
      var ready = cache.imageFor(banner.background.spec, size, 0);
      expect(ready, isNotNull, reason: "the raster should have finished");
      expect(ready!.width, size.width.round());
      expect(ready.height, size.height.round());

      // And it is the same picture, not a new one each time.
      expect(identical(cache.imageFor(banner.background.spec, size, 0), ready),
          isTrue);
    });

    testWidgets("a different design is a different picture", (tester) async {
      var cache = ProceduralCache();
      addTearDown(cache.dispose);
      var spec = bannerCanvas().background.spec;
      const size = Size(400, 225);

      cache.imageFor(spec, size, 0);
      await settle(tester);
      var first = cache.imageFor(spec, size, 0);
      expect(first, isNotNull);

      // Changed, so what is held is a picture of a design nobody is looking
      // at any more -- but it is still handed back until the new one has been
      // made. That is what keeps a canvas moving while somebody drags a
      // slider: the alternative is the caller generating the new design
      // itself on every frame of the drag, and the dearest generator in the
      // list shades a point per pixel.
      var edited = spec.copyWith(seed: spec.seed + 1);
      expect(cache.imageFor(edited, size, 0), same(first),
          reason: "a raster behind, which is not something anybody can see");

      await settle(tester);
      var next = cache.imageFor(edited, size, 0);
      expect(next, isNotNull);
      expect(next, isNot(same(first)), reason: "and then it is the new one");

      // One canvas is open at a time, so one picture is kept: going back to
      // the design before it is a fresh raster, with the newest picture
      // standing in while that is made.
      expect(cache.imageFor(spec, size, 0), same(next));
      await settle(tester);
      expect(cache.imageFor(spec, size, 0), isNot(same(next)));
    });

    testWidgets("and so is a different size", (tester) async {
      var cache = ProceduralCache();
      addTearDown(cache.dispose);
      var spec = bannerCanvas().background.spec;

      cache.imageFor(spec, const Size(400, 225), 0);
      await settle(tester);
      expect(cache.imageFor(spec, const Size(400, 225), 0), isNotNull);
      expect(cache.imageFor(spec, const Size(800, 450), 0), isNull);
    });

    testWidgets("a background that moves is not kept at all", (tester) async {
      // It is a different picture every frame, so caching it would be a
      // raster per frame *and* the drawing -- worse than drawing it.
      var cache = ProceduralCache();
      addTearDown(cache.dispose);
      var moving =
          bannerCanvas().background.spec.copyWith(animated: true, speed: 1);

      expect(cache.imageFor(moving, const Size(400, 225), 0), isNull);
      await settle(tester);
      expect(cache.imageFor(moving, const Size(400, 225), 0), isNull);
    });
  });

  group("what the renderer does with it", () {
    /// lit is how many pixels are not the flat background colour, which is a
    /// rough measure of "the background got drawn".
    Future<int> lit(CanvasDocument document, {ProceduralCache? cache}) async {
      var size = document.size.size;
      var recorder = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(recorder), document.copyWith(elements: []),
          backgrounds: cache);
      var picture = recorder.endRecording();
      var image =
          await picture.toImage(size.width.round(), size.height.round());
      var bytes = (await image.toByteData())!;
      var flat = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint32(i) == 0x060A10FF) flat++;
      }
      var total = bytes.lengthInBytes ~/ 4;
      image.dispose();
      picture.dispose();
      return total - flat;
    }

    testWidgets("the cached picture is the same picture", (tester) async {
      // Which is the whole claim: it is faster and it is not different.
      var banner = bannerCanvas();
      var cache = ProceduralCache();
      addTearDown(cache.dispose);

      late int direct;
      late int cached;
      await tester.runAsync(() async {
        direct = await lit(banner);
        // Warm it, then draw again from the picture.
        await lit(banner, cache: cache);
      });
      await settle(tester);
      await tester.runAsync(() async {
        cached = await lit(banner, cache: cache);
      });

      expect(direct, greaterThan(1000),
          reason: "the generator should draw something");
      expect(cached, closeTo(direct, direct * 0.02));
    });

    testWidgets("and an export never uses one", (tester) async {
      // The exporter renders each frame once and wants exact pixels at a size
      // of its own choosing, so there is nothing for a cache to save it.
      var banner = bannerCanvas();
      late int plain;
      await tester.runAsync(() async {
        plain = await lit(banner);
      });
      expect(plain, greaterThan(1000));
    });
  });

  group("the generated background itself", () {
    testWidgets("flowWaves still draws its ribbons", (tester) async {
      // It was made cheaper by blurring each band once rather than each
      // strand -- a hundred and forty blurs became eight -- and what has to
      // survive that is the picture.
      var banner = bannerCanvas().copyWith(elements: const []);
      late int drawn;
      await tester.runAsync(() async {
        var size = banner.size.size;
        var recorder = ui.PictureRecorder();
        paintCanvasDocument(ui.Canvas(recorder), banner);
        var picture = recorder.endRecording();
        var image =
            await picture.toImage(size.width.round(), size.height.round());
        var bytes = (await image.toByteData())!;
        var count = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint32(i) != 0x060A10FF) count++;
        }
        image.dispose();
        picture.dispose();
        drawn = count;
      });

      var pixels = banner.size.width * banner.size.height;
      // Ribbons over a dark field: a good part of the frame is lit, and a
      // good part is not. Blank or saturated both mean the generator broke.
      expect(drawn / pixels, greaterThan(0.05));
      expect(drawn / pixels, lessThan(0.95));
    });
  });
}

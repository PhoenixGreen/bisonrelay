import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_background_element_cache_test.dart is a background element drawn
// from the editor's cache of patterns, as the canvas's own background is:
// generated afresh on every repaint, a metal panel was eighty milliseconds
// of every frame anything on the canvas moved.

void main() {
  CanvasDocument withPanel(ProceduralSpec spec) =>
      const CanvasDocument(frames: 60).addElement(BackgroundElement(
          const ElementBase(id: "b", width: 640, height: 360),
          spec: spec));

  int paint(CanvasDocument doc, ProceduralCache? cache, {int frame = 0}) {
    var sw = Stopwatch()..start();
    var r = ui.PictureRecorder();
    paintCanvasDocument(ui.Canvas(r), doc,
        frame: frame, editing: true, backgrounds: cache);
    r.endRecording().dispose();
    return sw.elapsedMicroseconds;
  }

  testWidgets("a still panel is drawn from the cache once it is made",
      (tester) async {
    var cache = ProceduralCache();
    addTearDown(cache.dispose);
    // Animated, as a style switched from a moving one is left -- but metal
    // does not move, so it is still a still.
    var doc = withPanel(const ProceduralSpec(
        style: ProceduralStyle.metal, animated: true));
    expect(ProceduralCache.moves((doc.elements.single as BackgroundElement).spec),
        isFalse);

    var live = 0;
    for (var f = 0; f < 10; f++) {
      live += paint(doc, null, frame: f);
    }
    paint(doc, cache); // asks for it to be made
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    var cached = 0;
    for (var f = 0; f < 10; f++) {
      cached += paint(doc, cache, frame: f);
    }
    expect(cached, lessThan(live / 5),
        reason: "drawn from the cache: $cached µs against $live µs live");
  });

  test("a moving pattern is not cached", () {
    expect(
        ProceduralCache.moves(const ProceduralSpec(
            style: ProceduralStyle.starfield, animated: true)),
        isTrue);
    expect(
        ProceduralCache.moves(
            const ProceduralSpec(style: ProceduralStyle.starfield)),
        isFalse);
  });
}

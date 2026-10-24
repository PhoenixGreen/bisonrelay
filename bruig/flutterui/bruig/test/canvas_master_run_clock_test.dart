import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_master_run_clock_test.dart is what is on the master canvas being
// animated across the whole run.
//
// The master is under every scene, and its timeline is the run's: a progress
// line keyed from frame 0 to the last frame of the last scene. Its keyframes
// were read on each scene's own frame, so it started again at every scene --
// correct on the master, where the two clocks are the same, and wrong
// everywhere it was meant to be seen.

/// _run is two scenes of 100 frames under a master square that fades in
/// over the whole 200.
CanvasDocument _run({CanvasKind kind = CanvasKind.scenes}) => CanvasDocument(
      size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
      background: const CanvasBackground(),
      frameRate: 24,
      kind: kind,
      master: CanvasScene(id: "m", name: "Master", elements: [
        ShapeElement(
          ElementBase(
              id: "fade",
              width: 100,
              height: 100,
              track: ElementTrack([
                const Keyframe(frame: 0, opacity: 0),
                const Keyframe(frame: 200, opacity: 1),
              ])),
          fill: const Color(0xFF000000),
        ),
      ]),
      masterOn: true,
    ).withScenes([
      const CanvasScene(id: "a", frames: 100),
      const CanvasScene(id: "b", frames: 100),
    ]);

/// _alpha is how far in the black square is, out of 255, read off how much
/// it has darkened the page behind it: the background is opaque, so the
/// pixel's own alpha says nothing.
Future<int> _alpha(ui.Image image) async {
  var bytes = (await image.toByteData())!;
  var at = ((50 * image.width) + 50) * 4;
  var corner = bytes.getUint8(at) + bytes.getUint8(at + 1) + bytes.getUint8(at + 2);
  image.dispose();
  return (255 * (1 - corner / _page)).round();
}

/// _page is the background's brightness, read where nothing is on it.
late int _page;

Future<int> _editorAlpha(CanvasDocument doc, int frame) async {
  var recorder = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(recorder), doc, frame: frame);
  return _alpha(await recorder.endRecording().toImage(100, 100));
}

void main() {
  setUpAll(() async {
    var bare = CanvasDocument(
        size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
        background: const CanvasBackground());
    var image = await renderFrame(bare);
    var bytes = (await image.toByteData())!;
    var at = ((50 * image.width) + 50) * 4;
    _page = bytes.getUint8(at) + bytes.getUint8(at + 1) + bytes.getUint8(at + 2);
    image.dispose();
  });

  testWidgets("half way through the second scene it is three quarters in",
      (tester) async {
    late int played, edited;
    await tester.runAsync(() async {
      played = await _alpha(await renderFrame(_run(), frame: 150));
      edited = await _editorAlpha(_run().goToScene(1), 50);
    });
    expect(played, inInclusiveRange(185, 197),
        reason: "the run's frame 150, not the scene's frame 50");
    expect(edited, inInclusiveRange(185, 197),
        reason: "and the same where the scene is open in the editor");
  });

  testWidgets("a book's master keeps to its page", (tester) async {
    // Read a page at a time: a page number does not wait for the pages
    // before it.
    late int page;
    await tester.runAsync(() async {
      page = await _editorAlpha(_run(kind: CanvasKind.pages).goToScene(1), 50);
    });
    expect(page, inInclusiveRange(58, 70), reason: "its own frame 50");
  });
}

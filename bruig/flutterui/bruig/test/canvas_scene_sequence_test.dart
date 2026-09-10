import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_scene_sequence_test.dart is a document played through: which scene
// is showing when, and what is drawn between two of them.

CanvasDocument _two({SceneTransition? over}) => CanvasDocument(
      size: const CanvasSize(width: 200, ratio: CanvasRatio.wide),
      background: const CanvasBackground(),
    ).withScenes([
      CanvasScene(id: "a", frames: 10, transition: over, elements: [
        ShapeElement(
          const ElementBase(id: "s1", x: 0, y: 0, width: 200, height: 120),
          fill: const Color(0xFFFF0000),
        ),
      ]),
      CanvasScene(id: "b", frames: 10, elements: [
        ShapeElement(
          const ElementBase(id: "s2", x: 0, y: 0, width: 200, height: 120),
          fill: const Color(0xFF0000FF),
        ),
      ]),
    ]);

Future<Map<int, int>> _ink(CanvasDocument document, int at) async {
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 120),
      Paint()..color = const Color(0xFF000000));
  paintSequenceFrame(canvas, document, at);
  var picture = recorder.endRecording();
  var image = await picture.toImage(200, 120);
  var bytes = (await image.toByteData())!;
  var counts = <int, int>{};
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    var pixel = bytes.getUint32(i);
    counts[pixel] = (counts[pixel] ?? 0) + 1;
  }
  image.dispose();
  picture.dispose();
  return counts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const red = 0xFF0000FF;

  const blue = 0x0000FFFF;

  group("where a moment falls", () {
    test("a cut runs one scene straight into the next", () {
      var it = _two();
      expect(it.sequenceFrames, 20);

      expect(placeInSequence(it, 0).scene, 0);
      expect(placeInSequence(it, 9).scene, 0);
      expect(placeInSequence(it, 9).changing, isFalse);
      expect(placeInSequence(it, 10).scene, 1);
      expect(placeInSequence(it, 10).frame, 0);
    });

    test("an overlapping transition has both scenes playing", () {
      // Which is the whole difference between a cross fade and a cut: for
      // those frames the document is two canvases, not one.
      var it = _two(
          over: const SceneTransition(
              kind: SceneTransitionKind.fade, frames: 4, overlap: 4));
      expect(it.sequenceFrames, 16, reason: "four frames are spent twice");

      var early = placeInSequence(it, 3);
      expect(early.changing, isFalse);

      var over = placeInSequence(it, 7);
      expect(over.changing, isTrue);
      expect(over.scene, 0);
      expect(over.next, 1);
      expect(over.through, greaterThan(0));
      expect(over.through, lessThanOrEqualTo(1));
    });

    test("and one with no overlap runs after the scene it ends", () {
      var it = _two(
          over: const SceneTransition(
              kind: SceneTransitionKind.through, frames: 4, overlap: 0));
      expect(it.sequenceFrames, 24,
          reason: "the four frames it runs for are its own");

      var during = placeInSequence(it, 11);
      expect(during.changing, isTrue,
          reason: "past the first scene's last frame, before the second");
      expect(during.frame, 9, reason: "the outgoing scene is held on its end");
      expect(during.nextFrame, 0);
    });

    test("past the end, the last scene holds on its last frame", () {
      var it = _two();
      var after = placeInSequence(it, 999);
      expect(after.scene, 1);
      expect(after.frame, 9);
    });
  });

  group("what gets published", () {
    testWidgets("is the whole run, not the canvas being edited",
        (tester) async {
      // A document of several scenes publishes as the sequence it plays. The
      // export draws it through the same function the preview does, so what
      // was watched is what comes out.
      var it = _two();
      expect(it.playFrames, 20);
      expect(it.frames, 10, reason: "the timeline shows one scene");

      late ui.Image early;
      late ui.Image late_;
      await tester.runAsync(() async {
        early = await renderFrame(it, frame: 2);
        late_ = await renderFrame(it, frame: 15);
      });

      Future<int> redOf(ui.Image image) async {
        var bytes = (await image.toByteData())!;
        var count = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint32(i) == red) count++;
        }
        return count;
      }

      late int first;
      late int second;
      await tester.runAsync(() async {
        first = await redOf(early);
        second = await redOf(late_);
      });
      early.dispose();
      late_.dispose();

      expect(first, greaterThan(1000), reason: "the first scene");
      expect(second, 0, reason: "and by frame 15 the second one");
    });

    test("a document of one scene publishes exactly as it did", () {
      var one = CanvasDocument(frames: 12, elements: const []);
      expect(one.hasScenes, isFalse);
      expect(one.playFrames, 12);
    });
  });

  group("what is drawn between two scenes", () {
    testWidgets("a cut shows one or the other and never both", (tester) async {
      late Map<int, int> before;
      late Map<int, int> after;
      await tester.runAsync(() async {
        before = await _ink(_two(), 9);
        after = await _ink(_two(), 10);
      });
      expect(before[red], 24000);
      expect(before[blue] ?? 0, 0);
      expect(after[blue], 24000);
      expect(after[red] ?? 0, 0);
    });

    testWidgets("a cross fade has both of them at once", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.fade, frames: 4, overlap: 4)),
            7);
      });
      // Mixed rather than one or the other: almost none of the page is
      // either scene's own colour at full strength.
      var pure = (mid[red] ?? 0) + (mid[blue] ?? 0);
      expect(pure, lessThan(2000), reason: "$pure pixels are still pure");
      expect(mid.length, greaterThan(1),
          reason: "the two colours mixed, which is what a fade is");
    });

    testWidgets("a fade through a colour reaches the colour", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.through,
                    frames: 4,
                    overlap: 4,
                    color: Color(0xFF00FF00))),
            7);
      });
      // Half way through, the page is the colour it goes through -- which is
      // the whole point of the transition, and the moment it is at its
      // strongest.
      expect(mid[0x00FF00FF] ?? 0, greaterThan(20000),
          reason:
              "the page reaches the colour: ${mid.keys.map((k) => k.toRadixString(16))}");
    });

    testWidgets("a wipe shows the new scene on one side of a line",
        (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.wipeRight,
                    frames: 4,
                    overlap: 4,
                    ease: SceneTransitionEase.straight)),
            7);
      });
      // Both at full strength, each on its own part of the page: a wipe
      // uncovers rather than mixing.
      expect(mid[red] ?? 0, greaterThan(1000));
      expect(mid[blue] ?? 0, greaterThan(1000));
      expect((mid[red] ?? 0) + (mid[blue] ?? 0), 24000);
    });

    testWidgets("a push moves both of them", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.pushLeft,
                    frames: 4,
                    overlap: 4,
                    ease: SceneTransitionEase.straight)),
            7);
      });
      expect(mid[red] ?? 0, greaterThan(500), reason: "the old one, going");
      expect(mid[blue] ?? 0, greaterThan(500), reason: "the new one, coming");
    });
  });
}

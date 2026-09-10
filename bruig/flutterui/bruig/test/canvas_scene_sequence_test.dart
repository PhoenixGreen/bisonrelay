import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
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

  _playModes();

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

  group("the overlay family", () {
    // Each of these puts something *over* the join rather than crossing the
    // two scenes: a band of colour, a set of bars, a shape opening. What is
    // measured is that the middle of the transition is neither scene as it
    // stands, and that the end of it is the scene arriving.
    Future<Map<int, int>> midOf(SceneTransition over) =>
        _ink(_two(over: over), 7);

    testWidgets("a band covers the page as the scenes change", (tester) async {
      late Map<int, int> mid;
      late Map<int, int> after;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.band,
            frames: 4,
            overlap: 4,
            color: Color(0xFF00FF00),
            ease: SceneTransitionEase.straight));
        after = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.band, frames: 4, overlap: 4)),
            10);
      });

      // The page is 200 by 112 and the picture 200 by 120, so the strip
      // below the page is the scene's own and is not the band's to cover.
      expect(mid[0x00FF00FF] ?? 0, greaterThan(20000),
          reason: "the band is over the whole page in the middle of it");
      expect((mid[red] ?? 0) + (mid[blue] ?? 0), lessThan(1600),
          reason: "which is why the change behind it is not seen");
      expect(after[blue], 24000, reason: "and it ends on the scene arriving");
    });

    testWidgets("blinds show the next scene through bars", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.blinds,
            frames: 4,
            overlap: 4,
            count: 6,
            ease: SceneTransitionEase.straight));
      });
      // Both, at full strength: the bars are a clip rather than a blend.
      expect(mid[red] ?? 0, greaterThan(4000));
      expect(mid[blue] ?? 0, greaterThan(4000));
    });

    testWidgets("a shape opens in the middle of the old one", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.shapeWipe,
            frames: 4,
            overlap: 4,
            shape: ShapeKind.circle,
            ease: SceneTransitionEase.straight));
      });
      expect(mid[blue] ?? 0, greaterThan(2000),
          reason: "the scene arriving, through the opening");
      expect(mid[red] ?? 0, greaterThan(2000),
          reason: "and the one it is opening in");
    });

    testWidgets("barn doors pull the old scene apart", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.barn,
            frames: 4,
            overlap: 4,
            ease: SceneTransitionEase.straight));
      });
      expect(mid[blue] ?? 0, greaterThan(2000), reason: "through the gap");
      expect(mid[red] ?? 0, greaterThan(2000), reason: "the doors themselves");
    });

    testWidgets("a clock sweeps round", (tester) async {
      late Map<int, int> mid;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.clock,
            frames: 4,
            overlap: 4,
            ease: SceneTransitionEase.straight));
      });
      // Half the page at the half way point, near enough: a sector of a
      // rectangle is not exactly half its area at half a turn.
      expect(mid[blue] ?? 0, greaterThan(6000));
      expect(mid[red] ?? 0, greaterThan(6000));
    });

    testWidgets("and a blur goes soft in the middle", (tester) async {
      late Map<int, int> mid;
      late Map<int, int> ends;
      await tester.runAsync(() async {
        mid = await midOf(const SceneTransition(
            kind: SceneTransitionKind.blurThrough,
            frames: 4,
            overlap: 4,
            color: Color(0x00000000),
            ease: SceneTransitionEase.straight));
        ends = await _ink(
            _two(
                over: const SceneTransition(
                    kind: SceneTransitionKind.blurThrough,
                    frames: 4,
                    overlap: 4,
                    color: Color(0x00000000))),
            10);
      });
      // A blurred flat colour is still that colour in the middle of the page
      // and mixed at its edges, so the picture is no longer one flat block.
      expect(mid.length, greaterThan(2),
          reason: "soft edges, which is what a blur is");
      expect(ends[blue], 24000, reason: "and sharp again at the end");
    });

    test("the overlay kinds are one family, and are offered together", () {
      var overlay = SceneTransitionKind.inFamily(SceneTransitionFamily.overlay);
      expect(overlay, contains(SceneTransitionKind.band));
      expect(overlay.length, 6);
      expect(SceneTransitionKind.cut.familyOf, SceneTransitionFamily.none);
      expect(
          SceneTransitionKind.slideLeft.familyOf, SceneTransitionFamily.move);
      expect(SceneTransitionKind.wipeUp.familyOf, SceneTransitionFamily.wipe);
    });

    test("and their settings survive being saved", () {
      var over = const SceneTransition(
        kind: SceneTransitionKind.blinds,
        way: SceneTransitionWay.up,
        shape: ShapeKind.star,
        count: 9,
        softness: 0.4,
      );
      var back = SceneTransition.fromJson(over.toJson());
      expect(back.kind, SceneTransitionKind.blinds);
      expect(back.way, SceneTransitionWay.up);
      expect(back.shape, ShapeKind.star);
      expect(back.count, 9);
      expect(back.softness, 0.4);
    });
  });
}

// Playing the document rather than the canvas in front of you.
void _playModes() {
  group("play scene, or play all", () {
    test("play runs the scene until it is told to run the document", () {
      var controller = CanvasController(const CanvasDocument().withScenes([
        const CanvasScene(id: "a", frames: 10),
        const CanvasScene(id: "b", frames: 10),
      ]));
      addTearDown(controller.dispose);

      expect(controller.playAll, isFalse, reason: "the scene, to begin with");
      controller.play();
      expect(controller.playing, isTrue);
      expect(controller.previewAt, isNull,
          reason: "the canvas is showing the scene, not the run");
      controller.pause();

      controller.playAll = true;
      controller.play();
      expect(controller.previewAt, isNotNull,
          reason: "the canvas is showing the run");
    });

    test("and playing the document walks the editor through the scenes", () {
      // The panel, the timeline and the canvas all say the same thing about
      // where the playback has got to.
      var controller = CanvasController(const CanvasDocument().withScenes([
        const CanvasScene(id: "a", frames: 3),
        const CanvasScene(id: "b", frames: 3),
      ]));
      addTearDown(controller.dispose);
      controller.playAll = true;
      controller.play();
      expect(controller.document.at, 0);

      for (var i = 0; i < 4; i++) {
        controller.tickForTest();
      }
      expect(controller.document.at, 1,
          reason: "the second scene, reached by playing into it");
      expect(controller.playing, isTrue);
    });

    test("a scene that holds stops the run at its end", () {
      var controller = CanvasController(const CanvasDocument().withScenes([
        const CanvasScene(id: "a", frames: 3, holds: true),
        const CanvasScene(id: "b", frames: 3),
      ]));
      addTearDown(controller.dispose);
      controller.playAll = true;
      controller.play();

      for (var i = 0; i < 6; i++) {
        controller.tickForTest();
      }
      expect(controller.document.at, 0, reason: "it never reached the second");
      expect(controller.playing, isFalse);
      expect(controller.previewAt, isNull);
    });
  });
}

import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_convert.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/game_ready.dart';
import 'package:flutter_test/flutter_test.dart';

// An element's own arrival and way out are clips (own_motion.dart): what
// presets lay, what the timeline shows, and what everything that asks when
// something arrives reads.

ShapeElement box(String id, {double x = 0, ElementTrack? track}) =>
    ShapeElement(
        ElementBase(id: id, x: x, width: 100, height: 100, track: track));

void main() {
  group("an own arrival", () {
    test("is laid, retimed and taken away as one clip", () {
      var e = withOwnSpan(box("a"), MotionKind.arrive, 12, 36, 24);
      expect(ownSpan(e, MotionKind.arrive, 24), (12, 24));
      expect(e.base.motion.clips, hasLength(1));
      var again = withOwnSpan(e, MotionKind.arrive, 0, 12, 24);
      expect(again.base.motion.clips, hasLength(1), reason: "the same clip");
      expect(ownSpan(again, MotionKind.arrive, 24), (0, 12));
      var gone = withoutOwn(again, MotionKind.arrive);
      expect(ownSpan(gone, MotionKind.arrive, 24), isNull);
      expect(gone.base.motion.isEmpty, isTrue);
    });

    test("staggered with others, its clip moves", () {
      var c = CanvasController(CanvasDocument(frames: 96, elements: [
        withOwnSpan(box("left"), MotionKind.arrive, 0, 12, 24),
        withOwnSpan(box("right", x: 300), MotionKind.arrive, 0, 12, 24),
      ]));
      addTearDown(c.dispose);
      c.staggerArrivals(["left", "right"], 10);
      expect(ownSpan(c.document.elementById("right")!, MotionKind.arrive, 24),
          (10, 12));
    });
  });

  test("the scene's last animated frame counts its clips", () {
    var d = CanvasDocument(
        frames: 24,
        frameRate: 24,
        elements: [withOwnSpan(box("a"), MotionKind.arrive, 20, 48, 24)]);
    expect(d.lastAnimatedFrame, 48);
  });

  test("a patrol moved by clips that does not come back is a loop jump", () {
    var patrol = convertElement(
        box("p",
            track: ElementTrack(const [
              Keyframe(frame: 0),
              Keyframe(frame: 23, dx: 200),
            ])),
        24)!;
    var jumps = loopJumps(
        CanvasDocument(frames: 24, frameRate: 24, elements: [patrol]));
    expect(jumps.map((j) => j.element.id), ["p"]);

    // Closed, it comes back round where it was.
    var c = CanvasController(
        CanvasDocument(frames: 24, frameRate: 24, elements: [patrol]));
    addTearDown(c.dispose);
    closeLoops(c, jumps);
    expect(loopJumps(c.document), isEmpty);
    c.undo();
    expect(loopJumps(c.document), hasLength(1), reason: "one undo step");
  });

  test("two players on one keyboard have keys of their own", () {
    var d = CanvasDocument(elements: [
      box("one").rebase(box("one")
          .base
          .copyWith(play: const PlaySpec(as: PlayAs.platformer))),
      box("two").rebase(box("two")
          .base
          .copyWith(play: const PlaySpec(as: PlayAs.platformer, player: 2))),
    ]);
    var one = {for (var a in d.controlsFor(1)) ...a.keys};
    var two = {for (var a in d.controlsFor(2)) ...a.keys};
    expect(one.intersection(two), isEmpty);
  });

  test("a clock rounds to its figures before it carries a second", () {
    expect(formatCounter(59.999, 2, CounterSeparator.minutes), "1:00.00");
    expect(formatCounter(59.994, 2, CounterSeparator.minutes), "0:59.99");
    expect(formatCounter(59.9, 0, CounterSeparator.minutes), "0:59",
        reason: "whole seconds as a clock shows them");
  });

  test("a MIDI file with no beat, or cut short, is never a crash", () {
    var header = Uint8List.fromList([
      ...("MThd".codeUnits), 0, 0, 0, 6, 0, 0, 0, 1, 0, 0, // division 0
    ]);
    expect(() => readMidiFile(header), throwsFormatException);
    var cut = Uint8List.fromList([
      ...("MThd".codeUnits),
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      1,
      0,
      96,
      ...("MTrk".codeUnits),
      0,
      0,
      0,
      20,
      0,
      0xFF,
      0x51,
    ]);
    // Read as far as it goes, or refused as a format error: never anything
    // else thrown at the caller.
    try {
      readMidiFile(cut);
    } on FormatException {
      // As good an answer.
    }
  });

  test("a preset on an element keeps its arrival as a clip", () {
    var c = CanvasController(CanvasDocument(frames: 48, elements: [box("a")]));
    addTearDown(c.dispose);
    c.applyElementAnimation(
        c.document.elementById("a")!, ElementAnimationPreset.fadeIn);
    var a = c.document.elementById("a")!;
    expect(a.track, isNull);
    expect(ownClipOf(a, MotionKind.arrive), isNotNull);
  });
}

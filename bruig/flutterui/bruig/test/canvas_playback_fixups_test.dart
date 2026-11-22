import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';

import 'support/canvas_audio_fake.dart';

// canvas_playback_fixups_test.dart holds the editor's playing to what it
// says: a button's Play to frame stopping on its frame, the metronome while
// every scene plays, the clock carrying on through a change of frame rate,
// a transition watched while the slots play, Stop during one, Stop at the
// start of a run, every road to Play doing what the play bar's button does,
// clips that start with the scene starting again as play goes round, the
// scene turned by playing every scene as a turn by hand is, and the bar's
// Pause holding a game.

/// spin is a clip that starts with the scene.
MotionClip spin() => presetNamed("Spin once")!
    .clip("spin")
    .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.sceneStarts)]);

/// slotted is a clip with no trigger: it plays from its slot.
MotionClip slotted() => presetNamed("Spin once")!.clip("spin");

ShapeElement box(String id, MotionClip clip) => ShapeElement(ElementBase(
    id: id,
    width: 40,
    height: 40,
    motion: ElementMotion.none.withClip(clip).inSlot(0, clip.id)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasController editor(CanvasDocument doc, {FakeEngine? engine}) {
    var c = CanvasController(doc, audioEngine: engine ?? FakeEngine({}));
    addTearDown(() {
      c.pause();
      c.dispose();
    });
    return c;
  }

  CanvasDocument scenes(int count, {int frames = 48}) =>
      CanvasDocument(scenes: [
        for (var i = 0; i < count; i++) CanvasScene(id: "s$i", frames: frames)
      ]);

  group("a button's Play to frame", () {
    test("stops on its frame", () {
      var c = editor(const CanvasDocument(frames: 40));
      c.runButtonAction(
          const ButtonAction(kind: ButtonActionKind.playToFrame, frame: 9));
      expect(c.playing, isTrue);
      for (var i = 0; i < 15 && c.playing; i++) {
        c.tickForTest();
      }
      expect((c.frame, c.playing), (9, false));
    });

    test("from past its frame, plays it from the start", () {
      var c = editor(const CanvasDocument(frames: 40));
      c.frame = 20;
      c.runButtonAction(
          const ButtonAction(kind: ButtonActionKind.playToFrame, frame: 9));
      for (var i = 0; i < 15 && c.playing; i++) {
        c.tickForTest();
      }
      expect((c.frame, c.playing), (9, false));
    });

    test("while every scene plays, on its own scene's frame", () {
      var c = editor(scenes(2, frames: 20));
      c.playAll = true;
      c.goToScene(1);
      c.frame = 0;
      c.runButtonAction(
          const ButtonAction(kind: ButtonActionKind.playToFrame, frame: 5));
      for (var i = 0; i < 15 && c.playing; i++) {
        c.tickForTest();
      }
      expect((c.document.at, c.frame, c.playing), (1, 5, false));
      expect(c.previewAt, isNull);
    });
  });

  test("the metronome clicks while every scene plays", () async {
    var engine = FakeEngine({});
    var c = editor(scenes(2, frames: 100), engine: engine);
    c.metronome = true;
    c.playAll = true;
    c.play();
    for (var i = 0; i < 50 && engine.voices.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(engine.clicks, isNotEmpty);
  });

  test("a lower frame rate while playing carries on from the playhead", () {
    var c = editor(const CanvasDocument(frames: 1000, frameRate: 24));
    var micros = 0;
    c.clockForTest = () => micros;
    void at(double seconds) {
      var to = (seconds * 1e6).round();
      while (micros < to) {
        micros = (micros + 1e6 ~/ 48).clamp(0, to);
        c.tickClockForTest();
      }
    }

    c.play();
    at(10);
    expect(c.frame, 240);
    c.apply(c.document.copyWith(frameRate: 12), transient: true);
    at(10.5);
    expect(c.frame, closeTo(246, 1.5),
        reason: "half a second at 12 a second, from where it was");
    // And a higher one does not leap ahead either.
    c.apply(c.document.copyWith(frameRate: 24), transient: true);
    at(11);
    expect(c.frame, closeTo(257, 2));
  });

  test("a transition watched while only the slots play moves", () {
    var c = editor(CanvasDocument(scenes: [
      CanvasScene(id: "a", frames: 48, elements: [box("x", slotted())]),
      const CanvasScene(id: "b", frames: 48),
    ]));
    var micros = 0;
    c.clockForTest = () => micros;
    c.pressMotionSlot("x", 0);
    expect(c.sessionOnly, isTrue);
    c.previewTransitionAfter(0);
    var from = c.previewAt!;
    micros = 0;
    for (var i = 0; i < 10; i++) {
      micros += 1e6 ~/ 48;
      c.tickClockForTest();
    }
    expect(c.previewAt, greaterThan(from));
  });

  test("Stop while a transition is watched, after an earlier Play, ends it",
      () {
    var c = editor(scenes(2));
    c.frame = 10;
    c.play();
    c.pause();
    c.previewTransitionAfter(0);
    c.tickForTest();
    c.stopPlaying();
    expect(c.previewAt, isNull);
    expect(c.playing, isFalse);
    expect(c.document.at, 0);
  });

  test("Stop when stopped, every scene playing, goes to the start of the run",
      () {
    var c = editor(scenes(3));
    c.playAll = true;
    c.goToScene(1);
    c.frame = 10;
    c.stopPlaying();
    expect((c.document.at, c.frame), (0, 0));
  });

  group("every road to Play does what the play bar's button does", () {
    test("Space with only the slots playing plays the timeline", () {
      var c = editor(const CanvasDocument(frames: 48)
          .copyWith(elements: [box("x", slotted())]));
      c.pressMotionSlot("x", 0);
      expect(c.sessionOnly, isTrue);
      canvasKey(
          c,
          const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.space,
              logicalKey: LogicalKeyboardKey.space,
              timeStamp: Duration.zero),
          reach: ShortcutReach.page);
      expect((c.playing, c.sessionOnly), (true, false));
    });

    test("a button's Play or pause, likewise", () {
      var c = editor(const CanvasDocument(frames: 48)
          .copyWith(elements: [box("x", slotted())]));
      c.pressMotionSlot("x", 0);
      c.runButtonAction(const ButtonAction(kind: ButtonActionKind.togglePlay));
      expect((c.playing, c.sessionOnly), (true, false));
    });

    test("in a game, Pause holds the game, and Play lets both go", () {
      var c = editor(const CanvasDocument(frames: 48).copyWith(game: true));
      c.gaming = true;
      addTearDown(() => c.gaming = false);
      expect(c.playing, isTrue);
      c.togglePlay();
      expect((c.playing, c.gamePaused), (false, true));
      c.togglePlay();
      expect((c.playing, c.gamePaused), (true, false));
    });
  });

  group("clips that start with the scene", () {
    CanvasDocument one() =>
        const CanvasDocument(frames: 6).copyWith(elements: [box("a", spin())]);

    test("start again as play goes round from the last frame", () {
      var c = editor(one());
      c.play();
      expect(c.motionPlayer.isOff("a"), isTrue);
      c.motionPlayer.leave("a");
      for (var i = 0; i < 6; i++) {
        c.tickForTest();
      }
      expect(c.frame, 0);
      expect(c.motionPlayer.isOff("a"), isTrue, reason: "the scene began");
    });

    test("but not as the loop goes round", () {
      var c = editor(one());
      c.looping = true;
      c.play();
      c.motionPlayer.leave("a");
      for (var i = 0; i < 6; i++) {
        c.tickForTest();
      }
      expect(c.frame, 0);
      expect(c.motionPlayer.isOff("a"), isFalse);
    });
  });

  test("playing every scene, a turn lets go of the scene left, as by hand", () {
    var c = editor(const CanvasDocument().withScenes([
      CanvasScene(id: "s1", frames: 3, elements: [box("a", slotted())]),
      CanvasScene(id: "s2", frames: 3, elements: [box("b", slotted())]),
    ]));
    c.selectOnly("a");
    expect(c.selection, {"a"});
    c.playAll = true;
    c.play();
    for (var i = 0; i < 3; i++) {
      c.tickForTest();
    }
    expect(c.document.at, 1);
    expect(c.selection, isEmpty);
    expect(c.frameOn(0), 2, reason: "where the first scene was left");
  });
}

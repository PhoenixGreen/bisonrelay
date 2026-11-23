import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
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

  test("Stop after an element's preview leaves the playhead where it is", () {
    var c = editor(const CanvasDocument(frames: 48)
        .copyWith(elements: [box("x", slotted())]));
    c.frame = 10;
    c.play();
    c.tickForTest();
    c.pause();
    c.frame = 30;
    c.previewElement("x");
    c.tickForTest();
    c.stopPlaying();
    expect((c.frame, c.playing, c.previewing), (30, false, null),
        reason: "not back to where the earlier Play began");
  });

  group("markers", () {
    TimelineAction stop(String label) =>
        TimelineAction(frame: 5, kind: TimelineActionKind.stop, label: label);

    test("a stop's label goes as the scene is turned by hand", () {
      var c = editor(CanvasDocument(scenes: [
        CanvasScene(id: "s1", frames: 20, actions: [stop("One")]),
        CanvasScene(id: "s2", frames: 20, actions: [stop("Two")]),
      ]));
      c.frame = 3;
      c.play();
      for (var i = 0; i < 4 && c.playing; i++) {
        c.tickForTest();
      }
      expect(c.holdingMarker?.label, "One");
      c.goToScene(1);
      expect(c.frame, 5, reason: "the same frame on the next scene");
      expect(c.holdingMarker, isNull, reason: "play never stopped on Two");
    });

    test("a pause and a loop on one frame keep a count each", () {
      // The loop goes back once; the second time round, the pause holds
      // the playhead for its two frames and play goes on.
      var c = editor(const CanvasDocument(frames: 20, actions: [
        TimelineAction(frame: 5, kind: TimelineActionKind.pause, holdFrames: 2),
        TimelineAction(
            frame: 5, kind: TimelineActionKind.loop, target: 0, repeats: 1),
      ]));
      c.play();
      var seen = <int>[];
      for (var i = 0; i < 20; i++) {
        c.tickForTest();
        seen.add(c.frame);
      }
      expect(seen.where((f) => f == 5).length, 3, reason: "$seen");
      expect(seen, contains(6), reason: "$seen");
    });
  });

  group("a scene turned", () {
    // Clips picked on the timeline name the scene they were picked on.
    CanvasDocument two() => CanvasDocument(scenes: [
          CanvasScene(id: "s1", frames: 48, elements: [
            ShapeElement(const ElementBase(id: "a", width: 40, height: 40)),
          ]),
          CanvasScene(id: "s2", frames: 48, elements: [
            ShapeElement(const ElementBase(id: "b", width: 40, height: 40)),
            ShapeElement(const ElementBase(id: "c", width: 40, height: 40)),
          ]),
        ]);

    test("by hand, clips picked together on the scene left are let go", () {
      var c = editor(two());
      for (var i = 0; i < 2; i++) {
        c.placeClip("a", c.newClip("a", preset: presetNamed("Jump")),
            seconds: i * 1.0);
      }
      var picks = {for (var p in c.motionOf("a").placed) ("a", p.id)};
      c.pickMotions(picks);
      expect(c.motionPicks, hasLength(2));
      c.goToScene(1);
      // Delete on the next scene deletes what is picked there.
      c.selectOnly("c");
      c.deleteSelected();
      expect(c.document.elementById("c"), isNull);
      expect(c.motionPicks, isEmpty);
    });

    test("by hand, a clip picked from another scene is not left picked", () {
      // Picked from the first scene, "b" is on another canvas; with its own
      // scene in front it would be lit on the timeline, outside the
      // selection, where a click on the canvas cannot take it out.
      var c = editor(two());
      c.playAll = true;
      c.pickClip("b");
      expect(c.clipSelection, {"b"});
      c.goToScene(1);
      expect(c.clipSelection, c.selection);
    });

    test("by play, likewise", () {
      var c = editor(two());
      c.playAll = true;
      c.pickClip("b");
      c.placeClip("a", c.newClip("a", preset: presetNamed("Jump")), seconds: 0);
      c.pickMotions({("a", c.motionOf("a").placed.single.id)});
      c.play();
      for (var i = 0; i < 48 && c.document.at == 0; i++) {
        c.tickForTest();
      }
      expect(c.document.at, 1);
      expect(c.clipSelection, isEmpty);
      expect(c.motionPicks, isEmpty);
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

  // Three scenes of 48 frames joined by a fade of 12 frames that overlaps
  // them by 12: they start at 0, 36 and 72 of a run of 120 frames, and the
  // joins' transitions are frames 36 to 47 and 72 to 83 of it.
  CanvasDocument faded(
          {bool game = false, List<CanvasElement> first = const []}) =>
      CanvasDocument(game: game, scenes: [
        CanvasScene(
            id: "s0",
            frames: 48,
            transition: const SceneTransition(kind: SceneTransitionKind.fade),
            elements: first),
        const CanvasScene(
            id: "s1",
            frames: 48,
            transition: SceneTransition(kind: SceneTransitionKind.fade)),
        const CanvasScene(id: "s2", frames: 48),
      ]);

  group("a join watched and paused, its playhead moved by hand", () {
    CanvasController paused() {
      var c = editor(faded());
      c.playAll = true;
      c.previewTransitionAfter(0);
      for (var i = 0; i < 60 && c.previewAt != 40; i++) {
        c.tickForTest();
      }
      c.pause();
      expect(c.previewAt, 40);
      return c;
    }

    test("inside its transition, is still watched", () {
      var c = paused();
      c.goToRunFrame(44);
      expect(c.previewAt, 44);
      expect(c.joinPlaying(0), isTrue);
    });

    test("off it, ends the watching where the playhead was put", () {
      var c = paused();
      c.goToRunFrame(100);
      expect((c.document.at, c.frame, c.previewAt), (2, 28, null));
      c.stopPreview();
      expect(c.document.at, 2, reason: "not back to where it was watched from");
      c.play();
      expect(c.joinPlaying(0), isFalse, reason: "the old join is not lit");
      for (var i = 0; i < 30 && c.playing; i++) {
        c.tickForTest();
      }
      expect(c.playing, isFalse, reason: "the run played to its end");
      expect(c.document.at, 2, reason: "and stayed there");
    });

    test("stepped off it, likewise", () {
      var c = paused();
      c.stepFrame(10);
      expect(c.previewAt, isNull);
      c.play();
      expect(c.joinPlaying(0), isFalse);
    });

    test("into the next join's transition, holds that frame of the run", () {
      var c = paused();
      c.goToRunFrame(76);
      expect(c.previewAt, 76);
      expect(c.joinPlaying(0), isFalse);
      expect(c.joinPlaying(1), isTrue);
      c.frame = 2;
      expect(c.previewAt, isNull, reason: "a frame held is let go by hand");
    });
  });

  test("a frame of the run held in a game plays on to the run's end", () {
    // Held, the game's timeline is stepped into a transition; let go, it
    // plays on from there, not stopping at once for want of an end.
    var c = editor(faded(game: true));
    c.playAll = true;
    c.gaming = true;
    addTearDown(() => c.gaming = false);
    c.gamePaused = true;
    c.goToRunFrame(76);
    expect(c.previewAt, 76);
    c.gamePaused = false;
    c.tickForTest();
    expect((c.playing, c.previewAt), (true, 77));
  });

  test("a scrub while every scene plays goes on through the scenes", () {
    var c = editor(faded());
    c.playAll = true;
    c.play();
    c.tickForTest();
    c.goToRunFrame(10);
    expect(c.previewAt, 10, reason: "still the run's frame");
    for (var i = 0; i < 40; i++) {
      c.tickForTest();
    }
    expect(c.document.at, 1, reason: "walked on, not round the first scene");
    expect(c.previewAt, 50);
  });

  group("the slots alone, launched", () {
    test("over a join watched and paused, end the watching", () {
      var c = editor(faded(first: [box("x", slotted())]));
      c.previewTransitionAfter(0);
      c.tickForTest();
      c.pause();
      expect(c.previewAt, isNotNull);
      c.pressMotionSlot("x", 0);
      expect(c.sessionOnly, isTrue);
      expect(c.previewAt, isNull);
      c.pause();
      expect(c.previewAt, isNull, reason: "and it does not come back");
    });

    test("over a frame of the run held, let it go", () {
      var c = editor(faded(first: [box("x", slotted())]));
      c.playAll = true;
      c.goToRunFrame(40);
      expect(c.previewAt, 40);
      c.pressMotionSlot("x", 0);
      expect((c.sessionOnly, c.previewAt), (true, null));
    });
  });

  test("the clip editor's preview in a held game plays on the game's clock",
      () {
    var c = editor(const CanvasDocument(frames: 48, game: true, elements: [
      AudioElement(ElementBase(id: "a"), clip: MediaClip(timed: true)),
    ]));
    c.setSessionClip(
        "a",
        0,
        const SessionClip(
            id: "one",
            sound: MediaSource(assetId: "t.wav", name: "Loop", length: 4),
            bars: 1));
    c.gaming = true;
    addTearDown(() => c.gaming = false);
    c.gamePaused = true;
    c.openClipEditor("a", 0);
    c.previewClip();
    expect(c.sessionOnly, isFalse, reason: "not the slots alone");
    expect(c.playing, isFalse, reason: "the game is still held");
  });

  group("undo and redo", () {
    AudioElement voice(double gainDb) =>
        AudioElement(const ElementBase(id: "v"),
            clip: MediaClip(
                timed: true,
                channelName: "Voice",
                mix: ChannelMix(gainDb: gainDb)));

    test("tell the mix what the document holds", () async {
      var engine = FakeEngine({});
      var c = editor(CanvasDocument(frames: 48, elements: [voice(0)]),
          engine: engine);
      await c.audio.measure("none");
      c.frame = 1;
      expect(engine.channels["v"]?.gainDb, 0);
      c.apply(c.document.withElement(voice(-12)));
      expect(engine.channels["v"]!.gainDb, -12);
      c.undo();
      expect(engine.channels["v"]!.gainDb, 0, reason: "undone, heard undone");
      c.redo();
      expect(engine.channels["v"]!.gainDb, -12);
    });

    test("let go of a frame of the run held past the run's new end", () {
      var c = editor(faded());
      c.playAll = true;
      c.goToRunFrame(80);
      expect((c.document.at, c.previewAt), (1, 80));
      CanvasDocument shorter() =>
          c.document.removeScene(2).copyWith(frames: 20);
      c.apply(shorter());
      expect(c.document.playFrames, 56);
      expect(c.previewAt, isNull, reason: "frame 80 of a run of 56");
      c.undo();
      c.goToRunFrame(80);
      expect(c.previewAt, 80);
      c.redo();
      expect(c.previewAt, isNull);
    });
  });

  group("a join watched, ended, goes back with the media", () {
    AudioElement channel(String id) => AudioElement(ElementBase(id: id),
        clip: MediaClip(timed: true, channelName: id));

    test("to the scene it was watched from", () {
      var c = editor(CanvasDocument(scenes: [
        CanvasScene(
            id: "s0",
            frames: 48,
            transition: const SceneTransition(kind: SceneTransitionKind.fade),
            elements: [channel("a")]),
        CanvasScene(id: "s1", frames: 48, elements: [channel("b")]),
      ]));
      c.playAll = true;
      c.previewTransitionAfter(0);
      for (var i = 0; i < 60 && c.document.at == 0; i++) {
        c.tickForTest();
      }
      expect(c.audio.strips, {"b"});
      c.stopPreview();
      expect(c.document.at, 0);
      expect(c.audio.strips, {"a"}, reason: "the mix of the scene shown");
    });

    test("onto the master it was watched from", () {
      var c = editor(CanvasDocument(
          scenes: [
            CanvasScene(id: "s0", frames: 48, elements: [channel("a")]),
            const CanvasScene(id: "s1", frames: 48),
          ],
          master: CanvasScene(id: "m", elements: [channel("m")]),
          masterOn: true));
      c.showMaster();
      c.previewTransitionAfter(0);
      c.tickForTest();
      c.pause();
      // Turned to a scene by hand while the join is paused.
      c.goToScene(0);
      expect(c.audio.strips, containsAll(["a", "m"]));
      c.stopPreview();
      expect(c.document.editingMaster, isTrue);
      expect(c.audio.strips, {"m"}, reason: "the master's mix");
    });
  });

  test("a scene turned to on a frame past its end tells the mix the frame",
      () async {
    var engine = FakeEngine({});
    var c = editor(
        CanvasDocument(frameRate: 30, scenes: [
          const CanvasScene(id: "s0", frames: 120),
          CanvasScene(id: "s1", frames: 120, elements: [
            AudioElement(const ElementBase(id: "v"),
                clip: MediaClip(
                    timed: true,
                    channelName: "Voice",
                    mix: ChannelMix(automation: [
                      AutomationLane("volume", [(0, -30), (2, 0)]),
                    ]))),
          ]),
        ]),
        engine: engine);
    await c.audio.measure("none");
    c.goToScene(1);
    c.frame = 90;
    c.goToScene(0);
    // Shortened from elsewhere: the frame it was left on is past its end.
    c.setSceneFrames({1: 30});
    c.goToScene(1);
    expect(c.frame, 29);
    var told = engine.channels["v"]!.gainDb;
    c.frame = 0;
    c.frame = 29;
    expect(told, engine.channels["v"]!.gainDb, reason: "the frame shown");
  });

  group("a Code panel's picks", () {
    CodeElement code() =>
        const CodeElement(ElementBase(id: "k", width: 900, height: 600))
            .startedAs(CodeKind.web);

    test("go with the canvas, when another is opened", () {
      var c = editor(CanvasDocument(frames: 48, elements: [code()]));
      c.showCodeTab(code(), 0, code().files.last.id);
      expect(c.codeShowFor(code()).picked, isNotEmpty);
      c.load(CanvasDocument(frames: 48, elements: [code()]));
      expect(c.codeShowFor(code()).picked, isEmpty,
          reason: "another canvas's panel with the same id");
    });

    test("go with the scene, when it is turned", () {
      var c = editor(CanvasDocument(scenes: [
        CanvasScene(id: "s0", frames: 48, elements: [code()]),
        const CanvasScene(id: "s1", frames: 48),
      ]));
      c.showCodeTab(code(), 0, code().files.last.id);
      expect(c.codeShowFor(code()).picked, isNotEmpty);
      c.goToScene(1);
      c.goToScene(0);
      expect(c.codeShowFor(code()).picked, isEmpty);
    });
  });
}

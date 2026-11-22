import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

/// slotted is a box with a clip in its first slot, to play from there.
ShapeElement slotted(String id) {
  var clip = presetNamed("Spin once")!.clip("spin");
  return ShapeElement(ElementBase(
      id: id,
      width: 40,
      height: 40,
      motion: ElementMotion.none.withClip(clip).inSlot(0, clip.id)));
}

// canvas_controller_load_test.dart holds the editing session to letting go
// of one canvas when another is opened. The session lives as long as the
// app, so whatever it keeps about a canvas (a scene picked, a studio open
// on one of its sheets, rows fetched for one of its tables) is met by the
// next canvas unless load forgets it.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("opening another canvas forgets what was kept about the last", () {
    var c = CanvasController(const CanvasDocument(scenes: [
      CanvasScene(id: "a"),
      CanvasScene(id: "b"),
      CanvasScene(id: "c"),
    ]));
    addTearDown(c.dispose);

    c.pickScene(2);
    c.goToScene(1);
    c.lastFetched["chart1"] = const FetchedRows([], [], []);
    c.toggleClipSettings("shape1");
    c.dataStudio.value = "sheet1";
    c.scoreStudio.value = "score1";
    c.codeStudio.value = "code1";
    c.studio3dOpen.value = true;
    c.studio3dElement = "hero";
    c.setAnalysing("ch1", "eq", true);
    c.setPresetName("ch1", "eq", "Bright");
    c.hoveredButton = "button1";

    c.load(const CanvasDocument(scenes: [
      CanvasScene(id: "a"),
      CanvasScene(id: "b"),
      CanvasScene(id: "c"),
    ]));

    expect(c.pickedScene, isNull);
    expect(c.lastFetched, isEmpty);
    expect(c.clipSettingsOpen("shape1"), isFalse);
    expect(c.dataStudio.value, isNull);
    expect(c.scoreStudio.value, isNull);
    expect(c.codeStudio.value, isNull);
    expect(c.studio3dOpen.value, isFalse);
    expect(c.studio3dElement, isNull);
    expect(c.analysing("ch1", "eq"), isFalse);
    expect(c.presetNameOf("ch1", "eq"), isNull);
    expect(c.hoveredButton, isNull);
    expect(c.selection, isEmpty);
    expect(c.canUndo, isFalse);
    // The scenes share ids with the last canvas's: where the playhead was
    // left on one of those is not where it is on these.
    c.frame = 0;
    expect(c.frameOn(0), 0);
  });

  test("the painters' hooks go back to the editor when a second session shuts",
      () {
    // A canvas played in Files has a session of its own, made while the
    // editor's is alive, and the hooks the painters ask are one each for
    // the app. Shut, it must hand them back.
    var editor = CanvasController(const CanvasDocument(frames: 48));
    addTearDown(editor.dispose);
    var played = CanvasController(const CanvasDocument(frames: 48));

    played.play();
    expect(sheetPlaying!(), isTrue, reason: "the newest session answers");
    played.dispose();

    expect(sheetPlaying!(), isFalse, reason: "the editor's, which is paused");
    editor.play();
    expect(sheetPlaying!(), isTrue);
    editor.pause();
  });

  test("opening another canvas forgets how the last was looked at", () {
    // Channel heights and the stretch of the timeline in view are a
    // canvas's own. One never saved has no view kept to put in their place,
    // so what the last canvas left would be what it opened with.
    var c = CanvasController(const CanvasDocument(frames: 48));
    addTearDown(c.dispose);
    c.setLaneHeight("narrator", 120);
    c.timelineView = const TimelineView(10, 20);
    c.openEffects("narrator");
    expect(c.canvasView, isNotEmpty);

    c.load(const CanvasDocument(frames: 48));
    expect(c.laneHeights, isEmpty);
    expect(c.timelineView, isNull);
    expect(c.canvasView, isEmpty);
  });

  test("opening another canvas lets go of the editor's loop", () {
    // The loop is round a stretch of the last canvas's frames.
    var c = CanvasController(const CanvasDocument(frames: 200));
    addTearDown(c.dispose);
    c.looping = true;
    c.setLoop(100, 50);

    c.load(const CanvasDocument(frames: 200));
    expect(c.looping, isFalse);
    expect(c.loopRange, (from: 0, length: 200),
        reason: "where a first press would put it");
  });

  group("opening another canvas while the last plays", () {
    // Every way the editor can be playing, or holding, as another canvas
    // opens: each names the last canvas's scenes, frames or elements, and
    // the new one opens stopped.
    CanvasController editor(CanvasDocument doc) {
      var c = CanvasController(doc, audioEngine: FakeEngine({}));
      addTearDown(() {
        c.gaming = false;
        c.pause();
        c.dispose();
      });
      return c;
    }

    CanvasDocument twoScenes() => const CanvasDocument(scenes: [
          CanvasScene(id: "a", frames: 48),
          CanvasScene(id: "b", frames: 48),
        ]);

    void expectAtRest(CanvasController c) {
      expect(c.playing, isFalse, reason: "the timer");
      expect(c.sessionOnly, isFalse, reason: "only the slots");
      expect(c.previewing, isNull, reason: "an element previewed");
      expect(c.previewAt, isNull, reason: "a transition or a run");
      expect(c.gaming, isFalse, reason: "a game");
      expect(c.gamePaused, isFalse, reason: "a game held");
      expect(c.recording, isFalse, reason: "recording");
      expect(c.looping, isFalse, reason: "the loop");
      expect(c.practising, isNull, reason: "practice");
      expect(c.waitingFor, isNull, reason: "a stop waiting");
      expect(c.holdingMarker, isNull, reason: "a marker's label");
    }

    var piano = newInstrument(const CanvasDocument());
    var sheet = SheetElement(const ElementBase(id: "sheet"), follows: piano.id);
    var states = <(String, CanvasDocument, void Function(CanvasController))>[
      (
        "the timeline playing",
        const CanvasDocument(frames: 48),
        (c) {
          c.play();
          c.tickForTest();
        }
      ),
      (
        "only the slots playing",
        CanvasDocument(frames: 48, elements: [slotted("x")]),
        (c) {
          c.pressMotionSlot("x", 0);
          expect(c.sessionOnly, isTrue);
        }
      ),
      (
        "an element previewed",
        CanvasDocument(frames: 48, elements: [slotted("x")]),
        (c) {
          c.previewElement("x");
          c.tickForTest();
          expect(c.previewing, isNotNull);
        }
      ),
      (
        "a transition previewed and paused",
        twoScenes(),
        (c) {
          c.previewTransitionAfter(0);
          c.tickForTest();
          c.tickForTest();
          c.pause();
          expect(c.previewAt, isNotNull, reason: "a paused join is kept");
        }
      ),
      (
        "every scene playing",
        twoScenes(),
        (c) {
          c.playAll = true;
          c.play();
          c.tickForTest();
          expect(c.previewAt, isNotNull);
        }
      ),
      (
        "a game",
        const CanvasDocument(frames: 48, game: true),
        (c) {
          c.gaming = true;
          expect(c.gaming, isTrue);
        }
      ),
      (
        "a game held",
        const CanvasDocument(frames: 48, game: true),
        (c) {
          c.gaming = true;
          c.gamePaused = true;
          expect(c.gamePaused, isTrue);
        }
      ),
      (
        "recording",
        const CanvasDocument(frames: 48),
        (c) {
          c.recording = true;
          expect(c.recording, isTrue);
        }
      ),
      (
        "the loop",
        const CanvasDocument(frames: 200),
        (c) {
          c.looping = true;
          c.setLoop(100, 50);
          c.play();
        }
      ),
      (
        "a range of frames",
        const CanvasDocument(frames: 40),
        (c) {
          c.runButtonAction(
              const ButtonAction(kind: ButtonActionKind.playToFrame, frame: 9));
          c.tickForTest();
        }
      ),
      (
        "practice",
        CanvasDocument(frames: 240, frameRate: 24, elements: [piano, sheet]),
        (c) {
          c.startPractice(sheet);
          expect(c.practising, "sheet");
        }
      ),
      (
        "a slowed sheet",
        CanvasDocument(
            frames: 240,
            frameRate: 24,
            elements: [piano, sheet.copyWith(tempo: 0.5)]),
        (c) {
          c.playSheet(c.document.elementById("sheet") as SheetElement);
          expect(c.playing, isTrue);
        }
      ),
      (
        "a stop waiting for an action",
        const CanvasDocument(frames: 100, actions: [
          TimelineAction(
              frame: 10, kind: TimelineActionKind.stop, waitsFor: "jump"),
        ]),
        (c) {
          c.frame = 8;
          c.play();
          c.tickForTest();
          c.tickForTest();
          expect(c.waitingFor, "jump");
        }
      ),
    ];
    for (var (name, doc, start) in states) {
      test(name, () {
        var c = editor(doc);
        start(c);
        c.load(const CanvasDocument(frames: 100));
        expectAtRest(c);
        // And it plays as any canvas does: at its own pace, through the
        // frames a range or a slowed sheet of the last would have held.
        var micros = 0;
        c.clockForTest = () => micros;
        c.play();
        for (var i = 1; i <= 24; i++) {
          micros = (i * 1e6 / 24).ceil();
          c.tickClockForTest();
        }
        expect(c.frame, 24);
      });
    }

    test("a live counter running", () {
      var counter = CounterElement(const ElementBase(id: "count"),
          keyed: false, from: 0, to: 1000, rate: 1);
      var c = editor(CanvasDocument(elements: [counter]));
      c.pressCounterButton(counter, CounterButton.startStop);
      c.setCounterValue(counter, 30);
      expect(c.counterRunning(counter), isTrue);

      // Another canvas with a counter of the same id, waiting to be started.
      var next = CounterElement(const ElementBase(id: "count"),
          keyed: false, from: 5, to: 1000, rate: 1);
      c.load(CanvasDocument(elements: [next]));
      expect(c.counterRunning(next), isFalse);
      expect(c.counterValue(next), 5);
    });

    test("a stop's label, stopped on in the last canvas", () {
      // A stop on the first frame stops play as it goes round.
      var c = editor(const CanvasDocument(frames: 10, actions: [
        TimelineAction(
            frame: 0, kind: TimelineActionKind.stop, label: "The end"),
      ]));
      c.play();
      for (var i = 0; i < 10 && c.playing; i++) {
        c.tickForTest();
      }
      expect(c.holdingMarker?.label, "The end");

      c.load(const CanvasDocument(frames: 10, actions: [
        TimelineAction(
            frame: 0, kind: TimelineActionKind.stop, label: "Press to start"),
      ]));
      expect(c.holdingMarker, isNull, reason: "nothing stopped on this one");
    });

    test("a row folded by its own arrow, on two canvases never saved", () {
      var c = editor(const CanvasDocument(frames: 48));
      var folded = c.rowFolded("scenes");
      c.toggleRowFold("scenes");
      expect(c.rowFolded("scenes"), !folded);
      c.load(emptyCanvas());
      expect(c.rowFolded("scenes"), folded);
    });
  });

  test("coming back to the page finds the zoom as it was left", () {
    // The page puts the frame last chosen back each time it opens. The same
    // frame as now is no change, and must not send the view back to fit.
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.restoreFit(CanvasFit.width);
    c.zoom = 2;
    c.restoreFit(CanvasFit.width);
    expect(c.zoom, 2);
    c.restoreFit(CanvasFit.whole);
    expect(c.zoom, 1, reason: "another frame starts from the whole of it");
  });
}

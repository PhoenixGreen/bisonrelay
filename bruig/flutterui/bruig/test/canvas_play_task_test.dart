import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'support/canvas_audio_fake.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_play_task_test.dart is a play task card: the piano book's Practise
// box made a task that knows when each step is done (Ken: "similar to the
// tasks box used for the code element"). Steps tick as keys are played on
// the page; a step no key can show is ticked by the student.

/// press plays [keys] one after another on [inst], each let go before the
/// next, as a beginner plays.
void press(CanvasController c, AudioElement inst, List<String> keys) {
  for (var k in keys) {
    var n = noteNumber(k)!;
    c.noteOn(inst, n);
    c.noteOff(inst, n);
  }
}

/// chord holds [keys] down together, then lets them go.
void chord(CanvasController c, AudioElement inst, List<String> keys) {
  var ns = [for (var k in keys) noteNumber(k)!];
  for (var n in ns) {
    c.noteOn(inst, n);
  }
  for (var n in ns) {
    c.noteOff(inst, n);
  }
}

void main() {
  group("reading notes", () {
    test("by name, accidental and octave", () {
      expect(noteNumber("C4"), 60, reason: "Middle C");
      expect(noteNumber("A4"), 69);
      expect(noteNumber("F#3"), 54);
      expect(noteNumber("F♯3"), 54);
      expect(noteNumber("Bb2"), 46);
      expect(noteNumber("c5"), 72);
      expect(noteNumber("H2"), isNull);
      expect(noteNumber("C"), isNull, reason: "an octave is needed");
    });

    test("steps, with chords", () {
      expect(readSteps("C4 D4  E4"), [
        {60},
        {62},
        {64}
      ]);
      expect(readSteps("C3+E3+G3, F3+A3+C4"), [
        {48, 52, 55},
        {53, 57, 60}
      ]);
      expect(readSteps("C4 nonsense"), [
        {60}
      ]);
    });
  });

  group("a step is done", () {
    PlayCheckState run(PlayCheck c, List<Object> played) {
      var s = PlayCheckState.fresh;
      for (var p in played) {
        var keys = p is List<String> ? p : [p as String];
        var held = <int>{};
        for (var k in keys) {
          held.add(noteNumber(k)!);
          s = heardBy(c, s, noteNumber(k)!, held);
        }
      }
      return s;
    }

    test("every key, in any order", () {
      const c = PlayCheck(PlayCheckKind.keys, "Every C", steps: "C2 C3 C4 C5");
      expect(run(c, ["C4", "C2", "D4", "C5"]).done, isFalse);
      expect(run(c, ["C4", "C2", "D4", "C5", "C3"]).done, isTrue);
    });

    test("a key, so many times", () {
      const c = PlayCheck(PlayCheckKind.keys, "Middle C four times",
          steps: "C4", count: 4);
      expect(run(c, ["C4", "C4", "C4"]).done, isFalse);
      expect(run(c, ["C4", "C4", "C4", "C4"]).done, isTrue);
    });

    test("in order, starting over after a wrong key", () {
      const c =
          PlayCheck(PlayCheckKind.order, "C position", steps: "C4 D4 E4 F4 G4");
      expect(run(c, ["C4", "D4", "E4", "F4", "G4"]).done, isTrue);
      expect(run(c, ["C4", "D4", "A4", "E4", "F4", "G4"]).done, isFalse,
          reason: "a wrong key starts it over");
      expect(run(c, ["C4", "D4", "A4", "C4", "D4", "E4", "F4", "G4"]).done,
          isTrue);
      expect(run(c, ["C4", "C4", "D4", "D4", "E4", "F4", "G4"]).done, isTrue,
          reason: "a key played again is not a mistake");
    });

    test("chords held together, in order", () {
      const c = PlayCheck(PlayCheckKind.order, "C, F, G",
          steps: "C3+E3+G3 F3+A3+C4 G3+B3+D4");
      expect(
          run(c, [
            ["C3", "E3", "G3"],
            ["F3", "A3", "C4"],
            ["G3", "B3", "D4"],
          ]).done,
          isTrue);
      expect(
          run(c, ["C3", "E3", "G3", "F3", "A3", "C4", "G3", "B3", "D4"]).done,
          isFalse,
          reason: "the notes one at a time are not chords");
    });
  });

  group("on the canvas", () {
    (CanvasController, AudioElement, PlayTaskElement) lesson() {
      var inst = newInstrument(const CanvasDocument());
      var card = PlayTaskElement(const ElementBase(id: "task", width: 900),
          checks: const [
            PlayCheck(PlayCheckKind.keys, "Find every C", steps: "C3 C4"),
            PlayCheck(PlayCheckKind.order, "Play C D E", steps: "C4 D4 E4"),
            PlayCheck(PlayCheckKind.self, "Say the finger numbers"),
          ]);
      var c = CanvasController(
          const CanvasDocument().addElement(inst).addElement(card),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      return (c, inst, card);
    }

    test("steps tick as the keys are played", () {
      var (c, inst, card) = lesson();
      expect(c.playTaskShowFor(card).done, [false, false, false]);
      press(c, inst, ["C3", "C4"]);
      expect(c.playTaskShowFor(card).done, [true, false, false]);
      press(c, inst, ["D4", "E4"]);
      expect(c.playTaskShowFor(card).done, [true, true, false],
          reason: "the C before them started the run");
    });

    test("the student ticks their own step, and can untick it", () {
      var (c, _, card) = lesson();
      c.tickPlayStep(card, 2);
      expect(c.playTaskShowFor(card).done, [false, false, true]);
      c.tickPlayStep(card, 0);
      expect(c.playTaskShowFor(card).done[0], isFalse,
          reason: "a step the keys mark is not ticked by hand");
      c.tickPlayStep(card, 2);
      expect(c.playTaskShowFor(card).done[2], isFalse);
    });

    test("Start again clears it", () {
      var (c, inst, card) = lesson();
      press(c, inst, ["C3", "C4"]);
      c.startPlayTaskAgain(card);
      expect(c.playTaskShowFor(card).done, [false, false, false]);
    });

    test("a card listening to another instrument hears nothing", () {
      var (c, inst, card) = lesson();
      c.setPlayTask(card.copyWith(instrument: "someone else"));
      press(c, inst, ["C3", "C4"]);
      var now = c.document.elementById("task") as PlayTaskElement;
      expect(c.playTaskShowFor(now).done[0], isFalse);
    });

    test("it is as tall as what it says, done or not", () {
      var (_, _, card) = lesson();
      var fit = playTaskFitHeight(card, card.width);
      expect(playTaskLayout(card, card.width, banner: true).height, fit);
      expect(playTaskLayout(card, card.width).height, lessThanOrEqualTo(fit));
    });

    test("written down and read back", () {
      var (_, _, card) = lesson();
      var back = CanvasDocument.fromJson(
              const CanvasDocument().addElement(card).toJson())
          .elementById("task") as PlayTaskElement;
      expect([for (var c in back.checks) c.toJson()],
          [for (var c in card.checks) c.toJson()]);
      expect(back.box.toJson(), card.box.toJson());
      expect(back.accent, card.accent);
    });

    testWidgets("a press on a student's step ticks it", (tester) async {
      var (c, _, card) = lesson();
      c.setPlayTask(card.copyWith(), transient: false);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, const Size(1000, 800));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 1000,
          height: 800,
          child: CanvasStage(key: key, controller: c))));
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var now = c.document.elementById("task") as PlayTaskElement;
      var row = playTaskLayout(now, now.width).rows[2];
      await tester.tapAt(stage.toStagePoint(now.bounds.topLeft + row.center));
      await tester.pumpAndSettle();
      expect(c.playTaskShowFor(now).done[2], isTrue);
    });
  });

  group("playing along", () {
    MidiNote q(int key, double beat) => MidiNote(key, beat * 0.5, 0.48);

    (CanvasController, AudioElement, SheetElement, PlayTaskElement) take() {
      var piano = newInstrument(const CanvasDocument());
      piano = piano.copyWith(
          instrument: piano.instrument!
              .copyWith(notes: [q(60, 1), q(62, 2), q(64, 3)]));
      var sheet = SheetElement(const ElementBase(id: "sheet"),
          follows: piano.id, mode: PracticeMode.wait);
      var card = PlayTaskElement(const ElementBase(id: "task", width: 900),
          checks: const [
            PlayCheck(PlayCheckKind.along, "Play along", percent: 100),
          ]);
      var c = CanvasController(
          CanvasDocument(
              frames: 240, frameRate: 24, elements: [piano, sheet, card]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      return (c, piano, sheet, card);
    }

    /// played waits for each note in turn and plays [keys] at it.
    void played(CanvasController c, AudioElement piano, List<int> keys) {
      for (var k in keys) {
        for (var i = 0; i < 30; i++) {
          c.tickForTest();
        }
        c.noteOn(piano, k);
        c.noteOff(piano, k);
      }
    }

    test("a take with enough right ticks it", () {
      var (c, piano, sheet, card) = take();
      c.startPractice(sheet);
      played(c, piano, [60, 62, 64]);
      expect(c.practiceScore.$1, 3);
      expect(c.playTaskShowFor(card).done, [true]);
    });

    test("one with too few right does not", () {
      var (c, piano, sheet, card) = take();
      c.startPractice(sheet);
      played(c, piano, [61, 60, 62, 64]);
      expect(c.playTaskShowFor(card).done, [false],
          reason: "a wrong key first: two of three right, short of 100%");
    });

    test("nor does playing with no take", () {
      var (c, piano, _, card) = take();
      press(c, piano, ["C4", "D4", "E4"]);
      expect(c.playTaskShowFor(card).done, [false]);
    });
  });
}

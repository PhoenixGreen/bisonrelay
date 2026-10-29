import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart';
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_sheet_test.dart is Sheet music: a part written out as a score, the
// score engraved, and a take practised against it -- waited for, played
// along with, listened to.

/// At 120 BPM, a quarter is half a second.
MidiNote q(int key, double beat, double beats) =>
    MidiNote(key, beat * 0.5, beats * 0.5 - 0.02);

void main() {
  group("writing a part out", () {
    test("bars of quarters; a rest where nothing plays", () {
      var s = writeScore([q(60, 0, 1), q(62, 1, 1), q(64, 3, 1)]);
      expect(s.staves, [Staff.treble]);
      expect(s.bars.length, 1);
      var items = s.bars.single.staves[Staff.treble]!;
      expect([for (var w in items) (w.at, w.quarters, w.keys.join(","))], [
        (0.0, 1.0, "60"),
        (1.0, 1.0, "62"),
        (2.0, 1.0, ""),
        (3.0, 1.0, "64"),
      ]);
    });

    test("a note over the barline is tied into the next bar", () {
      var s = writeScore([q(60, 3, 2)]);
      expect(s.bars.length, 2);
      var a = s.bars[0].staves[Staff.treble]!.last;
      var b = s.bars[1].staves[Staff.treble]!.first;
      expect((a.quarters, a.tiedOn), (1.0, true));
      expect((b.quarters, b.tiedOn, b.notes), (1.0, false, a.notes));
    });

    test("dotted values, chords, and the left hand on the bass", () {
      var s = writeScore([
        q(64, 0, 1.5), q(67, 0, 1.5), q(62, 1.5, 0.5), q(48, 0, 4),
      ]);
      expect(s.staves, [Staff.treble, Staff.bass]);
      var treble = s.bars.single.staves[Staff.treble]!;
      expect((treble[0].keys.join(","), treble[0].quarters, treble[0].dots),
          ("64,67", 1.5, 1));
      expect(treble[1].quarters, 0.5);
      expect(s.bars.single.staves[Staff.bass]!.single.quarters, 4);
    });

    test("rests are never dotted", () {
      var s = writeScore([q(60, 0, 1.5)]);
      var rests = s.bars.single.staves[Staff.treble]!.where((w) => w.isRest);
      expect(rests.every((r) => r.dots == 0), isTrue);
      expect(rests.fold<double>(0, (a, r) => a + r.quarters), 2.5);
    });

    test("in 3/4, three beats to the bar", () {
      var s = writeScore([q(60, 0, 3), q(62, 3, 3)], beatsPerBar: 3);
      expect(s.bars.length, 2);
      expect(s.bars[0].staves[Staff.treble]!.single.quarters, 3);
    });

    test("where a key sits on its staff, and its sharp", () {
      expect(staffStep(64, Staff.treble), (0, false), reason: "E4, bottom line");
      expect(staffStep(60, Staff.treble), (-2, false), reason: "C4, a ledger");
      expect(staffStep(61, Staff.treble), (-2, true));
      expect(staffStep(43, Staff.bass), (0, false), reason: "G2, bottom line");
      expect(staffStep(57, Staff.bass), (8, false), reason: "A3, top line");
    });

    test("engraving it draws, with or without an instrument", () {
      var rec = ui.PictureRecorder();
      var canvas = Canvas(rec);
      paintSheet(canvas, const Rect.fromLTWH(0, 0, 600, 300),
          writeScore([q(60, 0, 1), q(48, 0, 4)]),
          at: 1, marks: const SheetMarks(marks: {0: NoteMark.right}));
      paintSheetElement(canvas, const Rect.fromLTWH(0, 0, 600, 300),
          const SheetElement(ElementBase(id: "s")), const CanvasDocument(), 0);
      rec.endRecording().dispose();
    });
  });

  group("practising", () {
    /// make is a piano at 120 BPM, 24 frames a second -- a quarter every
    /// twelve frames -- playing [notes], and Sheet music of it.
    (CanvasController, AudioElement, SheetElement) make(List<MidiNote> notes,
        {PracticeMode mode = PracticeMode.wait,
        PracticeHands hands = PracticeHands.both}) {
      var piano = newInstrument(const CanvasDocument());
      piano = piano.copyWith(
          instrument: piano.instrument!.copyWith(notes: notes));
      var sheet = SheetElement(const ElementBase(id: "sheet"),
          follows: piano.id, mode: mode, hands: hands);
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [piano, sheet]),
          audioEngine: FakeEngine({}));
      return (c, piano, sheet);
    }

    test("Wait for me holds on a note until it is played", () {
      var (c, piano, sheet) = make([q(60, 1, 1), q(64, 2, 1)]);
      addTearDown(c.dispose);
      c.startPractice(sheet);
      for (var i = 0; i < 30; i++) {
        c.tickForTest();
      }
      expect(c.frame, 11, reason: "held before the first note, at frame 12");
      expect(sheetMarksOf!(sheet).waiting, {0});
      expect(c.audioState(piano).next, {60}, reason: "its key lit blue");

      c.noteOn(piano, 62);
      c.noteOff(piano, 62);
      expect(sheetMarksOf!(sheet).marks[0], NoteMark.wrong);
      expect(sheetMarksOf!(sheet).wrongKeys[0], 62);
      c.tickForTest();
      expect(c.frame, 11, reason: "a wrong note: it waits on");

      c.noteOn(piano, 60);
      c.noteOff(piano, 60);
      expect(sheetMarksOf!(sheet).marks[0], NoteMark.right);
      for (var i = 0; i < 5; i++) {
        c.tickForTest();
      }
      expect(c.frame, greaterThan(12), reason: "and goes on");
      c.stopPractice();
      expect(c.practising, isNull);
    });

    test("Play along marks right, wrong and missed as it goes", () {
      var (c, piano, sheet) =
          make([q(60, 1, 1), q(62, 2, 1), q(64, 3, 1)], mode: PracticeMode.along);
      addTearDown(c.dispose);
      c.startPractice(sheet);
      for (var i = 0; i < 12; i++) {
        c.tickForTest();
      }
      c.noteOn(piano, 60); // on time
      c.noteOff(piano, 60);
      for (var i = 0; i < 12; i++) {
        c.tickForTest();
      }
      c.noteOn(piano, 65); // the wrong key for D
      c.noteOff(piano, 65);
      for (var i = 0; i < 30; i++) {
        c.tickForTest();
      }
      var marks = sheetMarksOf!(sheet).marks;
      expect(marks, {0: NoteMark.right, 1: NoteMark.wrong, 2: NoteMark.missed});
      expect(c.practiceScore, (1, 1));
    });

    test("the hand not practised is played for you; the part's file is quiet",
        () async {
      var (c, piano, sheet) = make([q(60, 0, 1), q(48, 0, 1)],
          mode: PracticeMode.along, hands: PracticeHands.right);
      addTearDown(c.dispose);
      c.startPractice(sheet);
      c.tickForTest();
      // The engine starts a moment after the first note asks for it.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      var engine = c.audio.engine as FakeEngine;
      expect(engine.notes.where((n) => n.$3 > 0).map((n) => n.$2), [48],
          reason: "the left hand's C, not the right's");
      for (var i = 0; i < 20; i++) {
        c.tickForTest();
      }
      expect(engine.notes.any((n) => n.$2 == 48 && n.$3 == 0), isTrue,
          reason: "and let go at its end");
    });

    test("Listen plays every note", () async {
      var (c, _, sheet) =
          make([q(60, 0, 1), q(48, 0, 1)], mode: PracticeMode.listen);
      addTearDown(c.dispose);
      c.startPractice(sheet);
      for (var i = 0; i < 4; i++) {
        c.tickForTest();
      }
      await Future<void>.delayed(Duration.zero);
      var engine = c.audio.engine as FakeEngine;
      expect(engine.notes.where((n) => n.$3 > 0).map((n) => n.$2).toSet(),
          {60, 48});
    });
  });

  group("the element", () {
    test("is kept", () {
      const e = SheetElement(ElementBase(id: "s"),
          follows: "p",
          title: "Ode",
          mode: PracticeMode.along,
          hands: PracticeHands.left,
          tempo: 0.6);
      var back = SheetElement.fromJson(e.props(), const ElementBase(id: "s"));
      expect((back.follows, back.title, back.mode, back.hands, back.tempo),
          ("p", "Ode", PracticeMode.along, PracticeHands.left, 0.6));
    });

    test("added, it shows the first instrument there is", () {
      var piano = newInstrument(const CanvasDocument());
      var doc = CanvasDocument(elements: [piano]);
      var sheet = newElement(ElementKind.sheet, doc) as SheetElement;
      expect((sheet.follows, sheet.title), (piano.id, "Piano"));
    });

    testWidgets("its settings start a take", (tester) async {
      var piano = newInstrument(const CanvasDocument());
      piano = piano.copyWith(
          instrument: piano.instrument!.copyWith(notes: [q(60, 1, 1)]));
      var sheet = SheetElement(const ElementBase(id: "sheet"), follows: piano.id);
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [piano, sheet]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.selectOnly("sheet");
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ListenableBuilder(
          listenable: c,
          builder: (context, _) => SingleChildScrollView(
            child: SizedBox(
              width: 320,
              child: CanvasControlScope(
                maxWidth: 280,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: elementSettings(context, c, c.selected!)),
              ),
            ),
          ),
        ))),
      ));
      await tester.pump();
      var go = find.byKey(const ValueKey("practiceGo"));
      await tester.ensureVisible(go);
      await tester.tap(go);
      await tester.pump();
      expect(c.practising, "sheet");
      expect(c.playing, isTrue);
      await tester.tap(go);
      await tester.pump();
      expect(c.practising, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}

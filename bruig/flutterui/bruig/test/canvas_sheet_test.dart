import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
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
      expect([
        for (var w in items) (w.at, w.quarters, w.keys.join(","))
      ], [
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
        q(64, 0, 1.5),
        q(67, 0, 1.5),
        q(62, 1.5, 0.5),
        q(48, 0, 4),
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
      expect(staffStep(64, Staff.treble), (0, false),
          reason: "E4, bottom line");
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

  group("voices", () {
    test("a note held under a moving tune is a voice of its own", () {
      // C5 held the whole bar, under E5 F5 G5 A5.
      var score = writeScore([
        q(72, 0, 4),
        q(76, 0, 1),
        q(77, 1, 1),
        q(79, 2, 1),
        q(81, 3, 1),
      ]);
      var items = score.bars[0].staves[Staff.treble]!;
      expect(score.voicesIn(score.bars[0], Staff.treble), 2);
      var upper = items.where((w) => w.voice == 0).toList();
      var lower = items.where((w) => w.voice == 1).toList();
      expect(upper.map((w) => w.keys.single), [76, 77, 79, 81],
          reason: "the tune on top");
      expect(lower.single.keys, [72], reason: "the held note under it");
      expect(lower.single.quarters, 4);
    });

    test("a legato overlap is cut short, not a second voice", () {
      // Each note held a sixteenth into the next, as a legato touch does.
      var score = writeScore([
        for (var i = 0; i < 4; i++) MidiNote(60 + i * 2, i * 0.5, 0.62),
      ]);
      expect(score.voicesIn(score.bars[0], Staff.treble), 1);
      expect(
          score.bars[0].staves[Staff.treble]!
              .where((w) => !w.isRest)
              .map((w) => w.quarters),
          [1, 1, 1, 1]);
    });

    test("two voices go out to MusicXML and come back", () {
      var notes = [q(72, 0, 4), q(76, 0, 1), q(77, 1, 1), q(79, 2, 2)];
      var xml = scoreToMusicXml(writeScore(notes));
      expect(xml, contains("<voice>2</voice>"));
      expect(xml, contains("<backup>"));
      var back = readMusicXml(utf8.encode(xml));
      expect(back.notes.map((n) => (n.key, n.start, n.length)).toSet(), {
        (72, 0.0, 4.0),
        (76, 0.0, 1.0),
        (77, 1.0, 1.0),
        (79, 2.0, 2.0),
      });
    });
  });

  group("triplets", () {
    List<Written> treble(Score s, int bar) => s.bars[bar].staves[Staff.treble]!;

    test("a beat played in threes is a triplet; sixteenths stay as they are",
        () {
      var score = writeScore([
        q(72, 0, 1 / 3),
        q(74, 1 / 3, 1 / 3),
        q(76, 2 / 3, 1 / 3),
        q(77, 1, 1),
        q(79, 2, 0.25),
        q(77, 2.25, 0.25),
        q(76, 2.5, 0.25),
        q(74, 2.75, 0.25),
        q(72, 3, 1),
      ]);
      var items = treble(score, 0);
      var three = items.take(3).toList();
      expect([for (var w in three) w.tuplet], [true, true, true]);
      expect([for (var w in three) w.base], [0.5, 0.5, 0.5],
          reason: "written as quavers");
      expect([
        for (var w in three) w.quarters * 3
      ], [
        closeTo(1, 1e-9),
        closeTo(1, 1e-9),
        closeTo(1, 1e-9),
      ]);
      expect(items.skip(3).every((w) => !w.tuplet), isTrue);
      expect([for (var w in items.skip(4).take(4)) w.base],
          [0.25, 0.25, 0.25, 0.25]);
      expect(tupletGroups(items), [
        [0, 1, 2]
      ]);
      // The three beamed, as one beat's quavers are.
      expect(beamGroups(items, score).first, [0, 1, 2]);
    });

    test("swung: a triplet crotchet and quaver; a rest a triplet's too", () {
      var score = writeScore([
        q(72, 0, 2 / 3),
        q(74, 2 / 3, 1 / 3),
        // A rest, then two.
        q(76, 4 / 3, 1 / 3),
        q(77, 5 / 3, 1 / 3),
        q(79, 2, 2),
      ]);
      var items = treble(score, 0);
      expect([
        for (var w in items.take(5)) (w.isRest, w.base, w.tuplet)
      ], [
        (false, 1.0, true),
        (false, 0.5, true),
        (true, 0.5, true),
        (false, 0.5, true),
        (false, 0.5, true),
      ]);
      expect(tupletGroups(items), [
        [0, 1],
        [2, 3, 4]
      ]);
      expect(items.last.base, 2, reason: "a plain half after them");
      expect(items.last.tuplet, isFalse);
    });

    test("played a little off, they are still threes", () {
      var score = writeScore([
        q(72, 0.02, 0.3),
        q(74, 0.36, 0.3),
        q(76, 0.64, 0.3),
        q(77, 1, 3),
      ]);
      expect([for (var w in treble(score, 0).take(3)) w.tuplet],
          [true, true, true]);
      expect(score.noteStarts[1] * 3, closeTo(1, 1e-9));
    });

    test("a note held through a beat in threes is plain", () {
      // A crotchet, a triplet in beat two, then a half: written whole,
      // not in thirds -- nor a note held over the triplet's beat.
      var score = writeScore([
        q(71, 0, 1),
        q(72, 1, 1 / 3),
        q(74, 4 / 3, 1 / 3),
        q(76, 5 / 3, 1 / 3),
        q(77, 2, 2),
        q(67, 4, 3),
      ]);
      var items = treble(score, 0);
      expect(items[0].tuplet, isFalse);
      expect(items[0].quarters, 1);
      expect(items[4].quarters, 2);
      expect(items[4].tuplet, isFalse);
      expect(items[4].tiedOn, isFalse);
      expect(tupletGroups(items), [
        [1, 2, 3]
      ]);
      // A dotted half in the next bar, over no threes.
      expect(treble(score, 1).first.quarters, 3);
    });

    test("out to MusicXML as three in two, and back as thirds", () {
      var notes = [
        q(72, 0, 1 / 3),
        q(74, 1 / 3, 1 / 3),
        q(76, 2 / 3, 1 / 3),
        q(77, 1, 3),
      ];
      var xml = scoreToMusicXml(writeScore(notes));
      expect(xml, contains("<actual-notes>3</actual-notes>"));
      expect(xml, contains('<tuplet type="start"/>'));
      expect(xml, contains('<tuplet type="stop"/>'));
      expect(xml, contains("<duration>8</duration>"), reason: "a third of 24");
      var back = readMusicXml(utf8.encode(xml));
      var starts = [for (var n in back.notes) n.start]..sort();
      expect(starts[1], closeTo(1 / 3, 1e-6));
      expect(starts[2], closeTo(2 / 3, 1e-6));
      // Written again, still a triplet.
      var again = writeScore([
        for (var n in back.notes)
          MidiNote(n.key, n.start * 0.5, n.length * 0.5 - 0.02)
      ]);
      expect(tupletGroups(treble(again, 0)), [
        [0, 1, 2]
      ]);
    });
  });

  group("keys", () {
    test("a key is heard in the notes, and spelled as it has it", () {
      // D major's scale, held: two sharps.
      var dMajor = [
        for (var (i, k) in [62, 64, 66, 67, 69, 71, 73, 74].indexed)
          q(k, i.toDouble(), 1)
      ];
      expect(keyFifthsOf(dMajor), 2);
      // G minor: two flats -- B flat's major.
      var gMinor = [
        for (var (i, k) in [55, 57, 58, 60, 62, 63, 66, 67, 67, 70, 62].indexed)
          q(k, i.toDouble(), i == 0 || i == 7 ? 3 : 1)
      ];
      expect(keyFifthsOf(gMinor), -2);
      expect(spellKey(70, -1).letter, 6, reason: "B flat in F");
      expect(spellKey(70, -1).alter, -1);
      expect(spellKey(70, 5).alter, 1, reason: "A sharp in B");
      expect(spellKey(66, 0).alter, 1, reason: "a sharp, in C");
      expect(spellKey(63, -3).letter, 2, reason: "E flat in E flat");
    });

    test("signs only where the key and the bar so far do not say it", () {
      // In F: B flat as written, then B natural, then B natural again in
      // the bar, then B flat -- and in the next bar B natural again.
      var score = writeScore([
        q(70, 0, 1),
        q(71, 1, 1),
        q(71, 2, 1),
        q(70, 3, 1),
        q(71, 4, 1),
      ], fifths: -1);
      expect(score.fifths, -1);
      var first = score.bars[0].staves[Staff.treble]!;
      expect([for (var w in first) w.accidentals.single], [null, 0, null, -1]);
      expect(score.bars[1].staves[Staff.treble]!.first.accidentals.single, 0,
          reason: "a new bar: the key again");
    });

    test("worked out from the instrument's Scale effect, where it has one", () {
      var part = InstrumentPart(effects: [
        MidiEffect(MidiEffectKind.scale)
            .withValue("root", 2) // D
            .withValue("scale", 3), // dorian: C major's notes
      ], notes: [
        q(62, 0, 1)
      ]);
      expect(sheetFifths(part, null), 0);
      expect(sheetFifths(part, 4), 4, reason: "chosen: as chosen");
    });

    test("quavers and semiquavers in a beat are beamed together", () {
      var score = writeScore([
        q(60, 0, 0.5),
        q(62, 0.5, 0.5),
        q(64, 1, 0.25),
        q(65, 1.25, 0.25),
        q(67, 1.5, 0.5),
        q(69, 2, 1),
      ]);
      var items = score.bars[0].staves[Staff.treble]!;
      var groups = beamGroups(items, score);
      expect(
          groups,
          [
            [0, 1],
            [2, 3, 4],
          ],
          reason: "beat one's two quavers; beat two's semiquavers and quaver");
      // And engraved.
      var rec = ui.PictureRecorder();
      paintSheet(Canvas(rec), const Rect.fromLTWH(0, 0, 600, 300), score);
      rec.endRecording().dispose();
    });
  });

  group("MusicXML", () {
    test("written out and read back, it is the same notes", () {
      var notes = [
        q(65, 0, 1.5), // dotted crotchet
        q(70, 1.5, 0.5), // B flat
        q(69, 2, 0.25),
        q(67, 2.25, 0.25),
        q(60, 2.5, 0.5),
        q(64, 2.5, 0.5), // a chord
        q(72, 3, 2), // tied over the barline
        q(41, 0, 4), // the left hand
      ];
      var score = writeScore(notes, fifths: -1);
      var xml = scoreToMusicXml(score, title: "Song", tempo: 120);
      expect(xml, contains("<fifths>-1</fifths>"));
      expect(xml, contains("<alter>-1</alter>"));
      var back = readMusicXml(utf8.encode(xml));
      expect(back.title, "Song");
      expect(back.tempo, 120);
      expect(back.fifths, -1);
      String all(Iterable<MidiNote> ns) =>
          ([for (var n in ns) "${n.key}@${n.start}+${n.length}"]..sort())
              .join(" ");
      // Quarters, as written: the test's notes are at 120, two quarters a
      // second.
      expect(
          all(back.notes),
          all([
            for (var n in notes)
              MidiNote(n.key, n.start * 2, (n.length * 2 * 4).round() / 4)
          ]),
          reason: "every key, start and length, the tie one note");
    });

    test("a compressed score (.mxl) is opened for the score inside", () {
      var xml = scoreToMusicXml(writeScore([q(60, 0, 1)]));
      var zip = Archive()
        ..addFile(ArchiveFile.string("META-INF/container.xml",
            '<container><rootfiles><rootfile full-path="score.xml"/></rootfiles></container>'))
        ..addFile(ArchiveFile.string("score.xml", xml));
      var back = readMusicXml(ZipEncoder().encode(zip));
      expect(back.notes.single.key, 60);
      expect(() => readMusicXml(utf8.encode("<html/>")),
          throwsA(isA<MusicXmlException>()));
    });

    test("opened into the sheet's instrument: its notes, the key, one undo",
        () {
      var piano = newInstrument(const CanvasDocument());
      var sheet =
          SheetElement(const ElementBase(id: "sheet"), follows: piano.id);
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [piano, sheet]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var score = MusicXmlScore(const [MidiNote(62, 0, 2), MidiNote(66, 2, 2)],
          title: "Etude", fifths: 2);
      expect(c.importScore(sheet, score), isNull);
      var part = (c.document.elementById(piano.id) as AudioElement).instrument!;
      // Quarters at the canvas's 120: half a second each.
      expect(part.notes.map((n) => (n.key, n.start, n.length)),
          [(62, 0.0, 1.0), (66, 1.0, 1.0)]);
      var s = c.document.elementById("sheet") as SheetElement;
      expect(s.key, 2);
      expect(s.title, "Etude");
      expect(c.exportScore(s), contains("<fifths>2</fifths>"));
      c.undo();
      expect(
          (c.document.elementById(piano.id) as AudioElement).instrument!.notes,
          isNot(part.notes));
    });
  });

  group("practising", () {
    /// make is a piano at 120 BPM, 24 frames a second -- a quarter every
    /// twelve frames -- playing [notes], and Sheet music of it.
    (CanvasController, AudioElement, SheetElement) make(List<MidiNote> notes,
        {PracticeMode mode = PracticeMode.wait,
        PracticeHands hands = PracticeHands.both}) {
      var piano = newInstrument(const CanvasDocument());
      piano =
          piano.copyWith(instrument: piano.instrument!.copyWith(notes: notes));
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
      expect(sheetMarksOf!(sheet).marks[0], NoteMark.wrong,
          reason: "found, it goes on -- but marked as it went first time");
      for (var i = 0; i < 5; i++) {
        c.tickForTest();
      }
      expect(c.frame, greaterThan(12), reason: "and goes on");
      c.stopPractice();
      expect(c.practising, isNull);
    });

    test("round a loop, its notes are marked afresh each time", () {
      // A quarter every twelve frames; the loop the first two beats.
      var (c, piano, sheet) = make([q(60, 0.5, 0.5)], mode: PracticeMode.along);
      addTearDown(c.dispose);
      c.setLoop(0, 24);
      c.looping = true;
      c.startPractice(sheet);
      var missed = false, cleared = false;
      var last = c.frame;
      for (var i = 0; i < 80; i++) {
        c.tickForTest();
        if (sheetMarksOf!(sheet).marks[0] == NoteMark.missed) missed = true;
        // Round the loop: back where it started.
        if (missed && c.frame < last) {
          cleared = sheetMarksOf!(sheet).marks[0] == null;
          break;
        }
        last = c.frame;
      }
      expect(missed, isTrue, reason: "gone by unplayed, first time round");
      expect(cleared, isTrue, reason: "and unmarked again, round the loop");
      c.stopPractice();
    });

    test("Play along marks right, wrong and missed as it goes", () {
      var (c, piano, sheet) = make([q(60, 1, 1), q(62, 2, 1), q(64, 3, 1)],
          mode: PracticeMode.along);
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
          tempo: 0.6,
          lines: 4);
      var back = SheetElement.fromJson(e.props(), const ElementBase(id: "s"));
      expect((
        back.follows,
        back.title,
        back.mode,
        back.hands,
        back.tempo,
        back.lines
      ), (
        "p",
        "Ode",
        PracticeMode.along,
        PracticeHands.left,
        0.6,
        4
      ));
      expect(
          SheetElement.fromJson(
                  const SheetElement(ElementBase(id: "s")).props(),
                  const ElementBase(id: "s"))
              .lines,
          2,
          reason: "two lines unless set");
      expect(e.copyWith(lines: 20).lines, 8);
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
      var sheet =
          SheetElement(const ElementBase(id: "sheet"), follows: piano.id);
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
      // Lines to a page, from its dropdown.
      var lines = find.byKey(const ValueKey("sheetLines"));
      await tester.ensureVisible(lines);
      await tester.tap(lines);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text("4 lines").last);
      await tester.pump(const Duration(milliseconds: 300));
      expect((c.document.elementById("sheet") as SheetElement).lines, 4);
      expect(tester.takeException(), isNull);
    });
  });

  group("pages", () {
    test("a page at a time; at its last line, the lines above turned", () {
      // Four lines to a page, ten systems.
      expect(pageLines(0, 4, 10), [0, 1, 2, 3]);
      expect(pageLines(2, 4, 10), [0, 1, 2, 3]);
      expect(pageLines(3, 4, 10), [4, 5, 6, 3], reason: "half turned");
      expect(pageLines(4, 4, 10), [4, 5, 6, 7]);
      // The last page, short: its end blank, and nothing to turn to.
      expect(pageLines(8, 4, 10), [8, 9, null, null]);
      expect(pageLines(9, 4, 10), [8, 9, null, null]);
      // One line: just the one played.
      expect(pageLines(5, 1, 10), [5]);
      // Two: as before, the line played and the next, the next above it at
      // a page's end.
      expect(pageLines(1, 2, 10), [2, 1]);
    });

    test("any number of lines draws", () {
      var score = writeScore([
        for (var i = 0; i < 64; i++) q(60 + i % 12, i.toDouble(), 1),
      ]);
      for (var n = 1; n <= 8; n++) {
        for (var at in [null, 0.0, 30.0, 63.0]) {
          var rec = ui.PictureRecorder();
          paintSheet(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 600, 800), score,
              lines: n, at: at);
          rec.endRecording().dispose();
        }
      }
    });
  });
}

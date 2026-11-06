import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_note_editing_test.dart is the notes' own settings -- muted, and
// left to chance -- and the piano roll's further tools: strum, crescendo,
// chop, join, mute and chance.

void main() {
  group("a note's own settings", () {
    test("muted and chance are kept, and an old note reads as it was", () {
      const n = MidiNote(60, 1, 0.5, 90, true, 0.25);
      expect(MidiNote.fromJson(n.toJson()), n);
      expect(const MidiNote(60, 1, 0.5).toJson().length, 4,
          reason: "written as before when neither is set");
      var old = MidiNote.fromJson([60, 1, 0.5, 90])!;
      expect((old.muted, old.chance), (false, 1.0));
    });

    test("as played: muted left out; chance the same every time", () {
      var notes = [
        const MidiNote(60, 0, 1),
        const MidiNote(62, 1, 1, 96, true),
        for (var i = 0; i < 40; i++) MidiNote(64, 2.0 + i, 1, 96, false, 0.5),
      ];
      var heard = notesHeard(notes);
      expect(heard.first, notes.first);
      expect(heard.any((n) => n.key == 62), isFalse, reason: "muted");
      var halves = heard.where((n) => n.key == 64).length;
      expect(halves, inInclusiveRange(10, 30), reason: "about half");
      expect(notesHeard(notes), heard, reason: "the same each time");
      var all = [const MidiNote(60, 0, 1)];
      expect(identical(notesHeard(all), all), isTrue);
      var part = InstrumentPart(notes: notes);
      expect(part.played(0.5).notes.length, heard.length);
    });
  });

  group("the further tools", () {
    const chord = [MidiNote(60, 0, 1), MidiNote(64, 0, 1), MidiNote(67, 0, 1)];

    test("strum: each a little after the one under it", () {
      var out = applyNoteTool(NoteTool.strum, chord, const {});
      expect(out.map((n) => n.start), [0, 0.06, 0.12]);
      expect(out.last.end, closeTo(1, 1e-9), reason: "still ending together");
    });

    test("crescendo: softer to louder", () {
      var run = [for (var i = 0; i < 4; i++) MidiNote(60, i.toDouble(), 1)];
      var out = applyNoteTool(NoteTool.crescendo, run, const {});
      expect(out.first.velocity, 40);
      expect(out.last.velocity, 127);
    });

    test("chop and join undo each other", () {
      var one = [const MidiNote(60, 0, 2)];
      var chopped = applyNoteTool(NoteTool.chop, one, const {});
      expect(chopped.map((n) => (n.start, n.length)), [(0, 1), (1, 1)]);
      expect(applyNoteTool(NoteTool.join, chopped, const {}), one);
    });

    test("mute toggles; chance and always", () {
      var muted = applyNoteTool(NoteTool.mute, chord, {0});
      expect(muted.map((n) => n.muted), [true, false, false]);
      expect(applyNoteTool(NoteTool.mute, muted, {0}).first.muted, isFalse);
      var chancy = applyNoteTool(NoteTool.chance, chord, const {});
      expect(chancy.every((n) => n.chance == 0.5), isTrue);
      expect(
          applyNoteTool(NoteTool.always, chancy, const {})
              .every((n) => n.chance == 1),
          isTrue);
    });
  });

  // The prototype's Transform and Generate, beyond the tools there were.
  group("Transform and Generate", () {
    test("Duplicate puts a copy after them, on the grid", () {
      var notes = const [MidiNote(60, 0, 0.5), MidiNote(62, 0.5, 0.5)];
      var out = applyNoteTool(NoteTool.duplicate, notes, const {}, grid: 0.25);
      expect([for (var n in out) (n.key, n.start)],
          [(60, 0.0), (62, 0.5), (60, 1.0), (62, 1.5)]);
    });

    test("Swing pushes every second step a third of a step late", () {
      var notes = [for (var i = 0; i < 4; i++) MidiNote(60, i * 0.25, 0.2)];
      var out = applyNoteTool(NoteTool.swing, notes, const {}, grid: 0.25);
      expect([
        for (var n in out) n.start
      ], [
        0.0,
        closeTo(0.25 + 0.25 / 3, 1e-9),
        0.5,
        closeTo(0.75 + 0.25 / 3, 1e-9)
      ]);
    });

    test("Arpeggiate spreads a chord up the grid, lowest first", () {
      var chord = const [
        MidiNote(67, 0, 1),
        MidiNote(60, 0, 1),
        MidiNote(64, 0, 1),
      ];
      var out = applyNoteTool(NoteTool.arpeggiate, chord, const {}, grid: 0.5);
      var by = {for (var n in out) n.key: (n.start, n.length)};
      expect(by, {60: (0.0, 0.5), 64: (0.5, 0.5), 67: (1.0, 0.5)});
    });

    test("Rhythm lays five in every eight steps, even with no notes", () {
      var out = applyNoteTool(NoteTool.rhythm, const [], const {},
          grid: 0.25, loopEnd: 2);
      expect([for (var n in out) n.start], [0.0, 0.5, 0.75, 1.25, 1.5]);
      expect(out.every((n) => n.key == 60), isTrue);
    });

    test("Fill chords makes each note the root of the scale's chord", () {
      // C major: on D, D F A; on G, G B D.
      var out = applyNoteTool(NoteTool.fillChords,
          const [MidiNote(62, 0, 1), MidiNote(67, 1, 1)], const {});
      expect({
        for (var n in out) (n.start, n.key)
      }, {
        (0.0, 62),
        (0.0, 65),
        (0.0, 69),
        (1.0, 67),
        (1.0, 71),
        (1.0, 74),
      });
    });
  });
}

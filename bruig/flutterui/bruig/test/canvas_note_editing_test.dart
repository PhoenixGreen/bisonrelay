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
}

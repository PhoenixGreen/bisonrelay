import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_score_edit_test.dart is every change the Score Studio makes to a
// score: note input as MuseScore's (writing over what is there), deletes,
// values, transposing, marks, bars and parts.

/// shape is a bar written short: "C4/1 r/2" -- each event's notes (or r)
/// and quarters, voice by voice as stored.
String shape(MusicScore s, {String part = "p1", int staff = 0, int bar = 0}) =>
    [
      for (var e in s.partById(part)!.staves[staff].bars[bar])
        "${e.isRest ? "r" : e.slash ? "/" : e.pitches.join("+")}/${e.quarters}"
            "${e.voice > 0 ? "v${e.voice}" : ""}"
    ].join(" ");

MusicScore blank({int bars = 2, String inst = "piano"}) =>
    MusicScore.blank("s", instruments: [inst], bars: bars);

ScoreCursor at(int bar, double t, {int staff = 0, int voice = 0}) =>
    (part: "p1", staff: staff, bar: bar, at: t, voice: voice);

Pitch p(String n) => Pitch.parse(n)!;

void main() {
  test("rests: each on a beat its value falls on", () {
    expect(restsFor(1, 4), [(1.0, 0), (2.0, 0)]);
    expect(restsFor(0, 3), [(2.0, 0), (1.0, 0)]);
    expect(restsFor(0.5, 2), [(0.5, 0), (1.0, 0)]);
    expect(restsFor(0, 3, compound: true), [(2.0, 1)]);
    expect(restsFor(1.5, 3, compound: true), [(1.0, 1)]);
  });

  test("values: a length as the values that write it", () {
    expect(valuesFor(3), [(2.0, 1)]);
    expect(valuesFor(2.5), [(2.0, 0), (0.5, 0)]);
    expect(valuesFor(3.75), [(2.0, 1), (0.5, 1)]);
  });

  group("note input", () {
    test("into an empty bar: the note, then rests to the end", () {
      var (s, id, cur) = blank().enter(at(0, 0), [p("C4")], 1);
      expect(shape(s), "C4/1.0 r/1.0 r/2.0");
      expect(s.event(id)!.pitches.single.name, "C4");
      expect(cur, at(0, 1));
    });

    test("one after another, the cursor moving on into the next bar", () {
      var s = blank();
      var c = at(0, 0);
      for (var n in ["C4", "D4", "E4", "F4", "G4"]) {
        var (next, _, cur) = s.enter(c, [p(n)], 1);
        s = next;
        c = cur;
      }
      expect(shape(s), "C4/1.0 D4/1.0 E4/1.0 F4/1.0");
      expect(shape(s, bar: 1), "G4/1.0 r/1.0 r/2.0");
      expect(c, at(1, 1));
    });

    test("over a longer note: it is cut short", () {
      var (s, _, _) = blank().enter(at(0, 0), [p("C4")], 4);
      (s, _, _) = s.enter(at(0, 2), [p("G4")], 1);
      expect(shape(s), "C4/2.0 G4/1.0 r/1.0");
    });

    test("cut where its length cannot be written as one: rests", () {
      var (s, _, _) = blank().enter(at(0, 0), [p("C4")], 4);
      (s, _, _) = s.enter(at(0, 2.5), [p("G4")], 0.5);
      // 2.5 is a minim and a quaver: not one value, so rests stand for it.
      expect(shape(s), "r/2.0 r/0.5 G4/0.5 r/1.0");
    });

    test("too long for the room left: cut at the bar line", () {
      var (s, _, _) = blank().enter(at(0, 3), [p("C4")], 4);
      expect(shape(s), "r/2.0 r/1.0 C4/1.0");
    });

    test("a second voice leaves the first alone", () {
      var (s, _, _) = blank().enter(at(0, 0), [p("C5")], 4);
      (s, _, _) = s.enter(at(0, 1, voice: 1), [p("E4")], 1);
      expect(shape(s), "C5/4.0 r/1.0v1 E4/1.0v1");
    });

    test("a strum written on a strum part", () {
      var (s, id, _) = blank(inst: "guitarStrum")
          .enter(at(0, 0), const [], 1, slash: true, strum: Strum.up);
      expect(shape(s).split(" ").first, "//1.0");
      expect(s.event(id)!.strum, Strum.up);
    });

    test("a note added to a chord", () {
      var (s, id, _) = blank().enter(at(0, 0), [p("C4")], 1);
      s = s.addToChord(id, p("E4")).addToChord(id, p("G4"));
      expect(s.event(id)!.pitches.map((x) => x.name), ["C4", "E4", "G4"]);
    });
  });

  test("deleted: a rest as long, its markings gone", () {
    var s = odeToJoy();
    var e = s.parts[0].staves[0].bars[0][0];
    var d = s.deleteEvent(e.id).event(e.id)!;
    expect([d.isRest, d.quarters, d.dyn, d.lyrics], [true, 1, null, isEmpty]);
  });

  test("a value changed: longer writes over, shorter leaves rests", () {
    var (s, id, _) = blank().enter(at(0, 0), [p("C4")], 1);
    (s, _, _) = s.enter(at(0, 1), [p("D4")], 1);
    expect(shape(s.setValue(id, 2)), "C4/2.0 r/2.0");
    var short = s.setValue(id, 0.5);
    expect(shape(short), "C4/0.5 r/0.5 D4/1.0 r/2.0");
    expect(shape(s.setValue(id, 1, dots: 1)), "C4/1.5 r/0.5 r/2.0");
  });

  group("transposed", () {
    test("a step at a time, keeping to the key", () {
      var s = odeToJoy().copyWith(fifths: 1); // G major: F is F#
      var e = s.parts[0].staves[0].bars[0][0]; // E4
      expect(
          s.transposed(e.id, steps: 1).event(e.id)!.pitches.single.name, "F#4");
      expect(
          s.transposed(e.id, steps: -2).event(e.id)!.pitches.single.name, "C4");
    });

    test("a semitone: sharps up and flats down in C, the key's own else", () {
      var s = odeToJoy();
      var e = s.parts[0].staves[0].bars[0][0]; // E4
      String moved(MusicScore s, int n) =>
          s.transposed(e.id, semitones: n).event(e.id)!.pitches.single.name;
      expect(moved(s, 1), "F4");
      expect(moved(s, 2), "F#4");
      expect(moved(s, -1), "Eb4");
      expect(moved(s.copyWith(fifths: -2), 2), "Gb4");
      expect(moved(s.copyWith(fifths: -2), -1), "Eb4");
    });

    test("an octave", () {
      var s = odeToJoy();
      var e = s.parts[0].staves[1].bars[0][0]; // C3 G3
      expect(
          s
              .transposed(e.id, octaves: 1)
              .event(e.id)!
              .pitches
              .map((x) => x.name),
          ["C4", "G4"]);
    });
  });

  test("marked: articulations toggle, a dynamic set and taken off", () {
    var s = odeToJoy();
    var id = s.parts[1].staves[0].bars[1][0].id;
    s = s.toggleArticulation(id, Articulation.accent);
    expect(s.event(id)!.articulations, {Articulation.accent});
    s = s.toggleArticulation(id, Articulation.accent);
    expect(s.event(id)!.articulations, isEmpty);
    s = s.setDynamic(id, Dynamic.ff);
    expect(s.event(id)!.dyn, Dynamic.ff);
    s = s.setDynamic(id, Dynamic.ff);
    expect(s.event(id)!.dyn, isNull, reason: "the same again takes it off");
    s = s.setChord(id, " Am7 ").setLyric(id, 2, "la");
    expect([
      s.event(id)!.chord,
      s.event(id)!.lyrics,
      s.verses
    ], [
      "Am7",
      ["", "", "la"],
      3
    ]);
  });

  test("a bar put in: rests on every staff, what was after moves along", () {
    var s = odeToJoy();
    var mark = s.bars[3];
    var t = s.insertBars(1);
    expect(t.barCount, 6);
    for (var p in t.parts) {
      for (var st in p.staves) {
        expect(st.bars[1].every((e) => e.isRest), isTrue);
        expect(st.bars[1].fold(0.0, (a, e) => a + e.quarters), 4);
      }
    }
    expect(t.bars[4].endings, mark.endings);
    expect(t.spanners.firstWhere((x) => x.id == "s1").to.bar, 2,
        reason: "the slur to bar 2 now ends in bar 3");
    // And every id still one of a kind.
    var ids = [
      for (var p in t.parts)
        for (var st in p.staves)
          for (var b in st.bars)
            for (var e in b) e.id
    ];
    expect(ids.toSet().length, ids.length);
  });

  test("a bar taken out, and never the last", () {
    var s = odeToJoy();
    var t = s.removeBars(0);
    expect(t.barCount, 4);
    expect(t.spanners.where((x) => x.id == "s1"), isEmpty,
        reason: "a slur from the bar taken out goes with it");
    expect(blank(bars: 1).removeBars(0).barCount, 1);
  });

  test("parts added, moved and taken out", () {
    var s = odeToJoy().addPart("flute").addPart("violin");
    expect(s.parts.map((p) => p.name),
        ["Piano", "Violin", "Guitar", "Flute", "Violin 2"]);
    expect(s.parts.last.staves.single.bars.length, 5);
    s = s.movePart(s.parts.last.id, -10);
    expect(s.parts.first.name, "Violin 2");
    s = s.removePart("vln");
    expect(
        s.parts.map((p) => p.name), ["Violin 2", "Piano", "Guitar", "Flute"]);
    expect(s.spanners.any((x) => x.part == "vln"), isFalse);
  });

  test("a mark moved on an event, a bar and the score", () {
    var s = odeToJoy();
    var id = s.parts[0].staves[0].bars[0][0].id;
    s = s
        .movedEventMark(id, MarkKind.dynamic, const Offset(4, 2))
        .movedBarMark(0, MarkKind.rehearsal, const Offset(-8, 0))
        .movedScoreMark(MarkKind.tempo, const Offset(0, -6));
    expect(s.event(id)!.offsets[MarkKind.dynamic], const Offset(4, 2));
    expect(s.bars[0].offsets[MarkKind.rehearsal], const Offset(-8, 0));
    expect(s.offsets[MarkKind.tempo], const Offset(0, -6));
    expect(s.movedScoreMark(MarkKind.tempo, Offset.zero).offsets, isEmpty);
  });
}

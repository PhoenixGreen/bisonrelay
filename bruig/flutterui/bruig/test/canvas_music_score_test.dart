import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_music_score_test.dart is the score as the source (Ken, 2026-11-14):
// what is written -- repeats, endings, jumps, dynamics, articulations, ties,
// strums -- and what is played from it, part by part, for the instrument
// channel each part plays on.

int _n = 0;
ScoreEvent note(String pitches, double value,
        {int dots = 0,
        bool tie = false,
        Dynamic? dyn,
        Set<Articulation> art = const {},
        String? chord,
        int voice = 0}) =>
    ScoreEvent("n${++_n}", value,
        dots: dots,
        pitches: [for (var p in pitches.split(" ")) Pitch.parse(p)!],
        tie: tie,
        dyn: dyn,
        articulations: art,
        chord: chord,
        voice: voice);

ScoreEvent rest(double value) => ScoreEvent("r${++_n}", value);

ScoreEvent strum(Strum dir, {String? chord, double value = 1}) =>
    ScoreEvent("s${++_n}", value, slash: true, strum: dir, chord: chord);

/// one is a one-part score of [bars] (each a list of events) with [info].
MusicScore one(List<List<ScoreEvent>> bars,
        {List<BarInfo>? info,
        String instrument = "piano",
        double tempo = 120,
        List<Spanner> spanners = const []}) =>
    MusicScore("s",
        tempo: tempo,
        bars: info ?? List.filled(bars.length, const BarInfo()),
        spanners: spanners,
        parts: [
          ScorePart("p1", "Part", instrument,
              [ScoreStaff(scoreInstrument(instrument).clefs.first, bars)]),
        ]);

List<int> order(MusicScore s) => [for (var b in s.playOrder()) b.bar];

MusicScore structure(List<BarInfo> info) => one([
      for (var _ in info) [rest(4)]
    ], info: info);

void main() {
  test("a pitch: spelled for the key, named, read back", () {
    expect(Pitch.spelled(61).name, "C#4");
    expect(Pitch.spelled(61, fifths: -3).name, "Db4");
    expect(Pitch.spelled(70, fifths: -1).name, "Bb4");
    expect(Pitch.parse("Ebb2")!.key, 38);
    expect(Pitch.parse("F#5")!.key, 78);
    expect(Pitch.parse("C4")!.step, 35);
    expect(Pitch.parse("H4"), isNull);
  });

  test("a value: dotted, and in a triplet", () {
    expect(const ScoreEvent("a", 1, dots: 1).quarters, 1.5);
    expect(const ScoreEvent("a", 2, dots: 2).quarters, 3.5);
    expect(const ScoreEvent("a", 0.5, tuplet: Tuplet.triplet).quarters,
        closeTo(1 / 3, 1e-9));
    expect(const ScoreEvent("a", 0.5, grace: true).quarters, 0);
  });

  group("the play order", () {
    test("a repeat with first and second endings", () {
      // The prototype's: 1 2 3 4 1 2 3 5.
      var s = structure([
        const BarInfo(repeatStart: true),
        const BarInfo(),
        const BarInfo(),
        const BarInfo(endings: [1], repeatEnd: 2),
        const BarInfo(endings: [2]),
      ]);
      expect(order(s), [0, 1, 2, 3, 0, 1, 2, 4]);
      expect([for (var b in s.playOrder()) b.pass], [1, 1, 1, 1, 2, 2, 2, 2]);
      expect(s.playOrder()[4].start, 16, reason: "four bars of four in");
    });

    test("an end repeat with no start goes back to the top", () {
      var s = structure([
        const BarInfo(),
        const BarInfo(repeatEnd: 2),
        const BarInfo(),
      ]);
      expect(order(s), [0, 1, 0, 1, 2]);
    });

    test("a second repeat goes back only as far as the first one's end", () {
      var s = structure([
        const BarInfo(repeatEnd: 2),
        const BarInfo(),
        const BarInfo(repeatEnd: 2),
      ]);
      expect(order(s), [0, 0, 1, 2, 1, 2]);
    });

    test("played three times", () {
      var s = structure([
        const BarInfo(repeatStart: true),
        const BarInfo(endings: [1, 2], repeatEnd: 3),
        const BarInfo(endings: [3]),
        const BarInfo(),
      ]);
      expect(order(s), [0, 1, 0, 1, 0, 2, 3]);
    });

    test("D.C. al Fine", () {
      var s = structure([
        const BarInfo(),
        const BarInfo(fine: true),
        const BarInfo(),
        const BarInfo(jump: Jump.dcAlFine),
      ]);
      expect(order(s), [0, 1, 2, 3, 0, 1]);
    });

    test("D.S. al Coda", () {
      var s = structure([
        const BarInfo(),
        const BarInfo(segno: true),
        const BarInfo(toCoda: true),
        const BarInfo(),
        const BarInfo(jump: Jump.dsAlCoda),
        const BarInfo(coda: true),
        const BarInfo(),
      ]);
      expect(order(s), [0, 1, 2, 3, 4, 1, 2, 5, 6]);
    });

    test("after a D.C. no repeat is taken, and only the last ending plays", () {
      var s = structure([
        const BarInfo(repeatStart: true),
        const BarInfo(),
        const BarInfo(endings: [1], repeatEnd: 2),
        const BarInfo(endings: [2], jump: Jump.dc),
      ]);
      expect(order(s), [0, 1, 2, 0, 1, 3, 0, 1, 3]);
    });

    test("a time change makes its bars longer", () {
      var s = structure([
        const BarInfo(),
        const BarInfo(time: (3, 4)),
        const BarInfo(),
      ]);
      expect([for (var b in s.playOrder()) b.start], [0, 4, 7]);
      expect(s.lengthQuarters(), 10);
    });
  });

  group("a part as played", () {
    test("each note when it is played, through a repeat, at the tempo", () {
      var s = one([
        [note("C4", 2), note("E4", 2)],
        [note("G4", 4)],
      ], info: const [
        BarInfo(repeatStart: true),
        BarInfo(repeatEnd: 2),
      ]);
      var notes = s.partNotes("p1");
      expect([for (var n in notes) n.note.key], [60, 64, 67, 60, 64, 67]);
      // Two seconds a bar at 120.
      expect([for (var n in notes) n.note.start], [0, 1, 2, 4, 5, 6]);
      expect(notes[3].event, notes[0].event, reason: "the same event again");
      expect(notes[3].played, 2, reason: "the third bar played");
    });

    test("dynamics: p soft, f loud, and they last; sfz just the one", () {
      var s = one([
        [
          note("C4", 1, dyn: Dynamic.p),
          note("C4", 1),
          note("C4", 1, dyn: Dynamic.sfz),
          note("C4", 1),
        ],
        [note("C4", 2, dyn: Dynamic.f), note("C4", 2)],
      ]);
      var v = [for (var n in s.partNotes("p1")) n.note.velocity];
      expect(v, [
        Dynamic.p.velocity,
        Dynamic.p.velocity,
        Dynamic.sfz.velocity,
        Dynamic.p.velocity,
        Dynamic.f.velocity,
        Dynamic.f.velocity,
      ]);
    });

    test("a crescendo swells the notes under it", () {
      var s = one([
        [note("C4", 1), note("C4", 1), note("C4", 1), note("C4", 1)],
      ], spanners: const [
        Spanner("h", SpannerKind.crescendo, "p1", 0, (bar: 0, at: 0),
            (bar: 0, at: 3)),
      ]);
      var v = [for (var n in s.partNotes("p1")) n.note.velocity];
      expect(v.first, Dynamic.mf.velocity);
      expect(v[3], greaterThan(v[1]));
      expect(v[1], greaterThan(v[0]));
    });

    test("articulations: staccato short, tenuto full, accent harder", () {
      var s = one([
        [
          note("C4", 1),
          note("C4", 1, art: {Articulation.staccato}),
          note("C4", 1, art: {Articulation.tenuto}),
          note("C4", 1, art: {Articulation.accent}),
        ],
      ]);
      var n = [for (var x in s.partNotes("p1")) x.note];
      expect(n[1].length, closeTo(0.25, 1e-9), reason: "half of half a second");
      expect(n[2].length, closeTo(0.5, 1e-9));
      expect(n[0].length, lessThan(0.5));
      expect(n[3].velocity, greaterThan(n[0].velocity));
    });

    test("a tie is one note, across the bar line", () {
      var s = one([
        [rest(2), note("E4 G4", 2, tie: true)],
        [note("E4 G4", 1), rest(3)],
      ]);
      var n = s.partNotes("p1");
      expect(n.length, 2);
      expect(n[0].note.start, 1);
      expect(n[0].note.length, closeTo(1.5 - 0.05 * 0.5, 1e-9),
          reason: "1 s of half note + 0.5 s crotchet, its end let go a little");
    });

    test("a tie within the bar, in its own voice", () {
      var s = one([
        [
          note("C5", 2, tie: true),
          note("C5", 2),
          note("C4", 4, voice: 1),
        ],
      ]);
      var n = s.partNotes("p1");
      expect([for (var x in n) x.note.key]..sort(), [60, 72]);
    });

    test("a transposing part sounds where it should", () {
      // A B♭ clarinet's written D sounds C.
      var s = one([
        [note("D4", 4)],
      ], instrument: "clarinet");
      expect(s.partNotes("p1").single.note.key, 60);
    });

    test("a tempo change speeds the bars after it", () {
      var s = one([
        [note("C4", 4)],
        [note("C4", 4)],
      ], info: const [
        BarInfo(),
        BarInfo(tempo: 240),
      ]);
      var n = s.partNotes("p1");
      expect(n[1].note.start, 2);
      expect(n[1].note.length, closeTo(0.95, 1e-9), reason: "a second a bar");
    });

    test("a strum: the chord in force, down low to high, up high to low", () {
      var s = one([
        [strum(Strum.down, chord: "G"), strum(Strum.up), rest(2)],
      ], instrument: "guitarStrum");
      var n = s.partNotes("p1");
      var down = [
        for (var x in n)
          if (x.note.start < 0.4) x.note
      ];
      var up = [
        for (var x in n)
          if (x.note.start >= 0.4) x.note
      ];
      expect({for (var d in down) d.key % 12}, {7, 11, 2});
      expect(down.first.key % 12, 7, reason: "its root lowest, first");
      expect(up.first.key, greaterThan(up.last.key));
      expect(down[1].start, greaterThan(down[0].start),
          reason: "the strings a moment apart");
    });
  });

  test("chord symbols voiced", () {
    Set<int> pcs(String c) => {for (var k in chordKeys(c)) k % 12};
    expect(pcs("Am"), {9, 0, 4});
    expect(pcs("G7"), {7, 11, 2, 5});
    expect(pcs("Cmaj7"), {0, 4, 7, 11});
    expect(pcs("Dsus4"), {2, 7, 9});
    expect(chordKeys("D/F#").first % 12, 6, reason: "the bass lowest");
    expect(chordKeys("Bb").first % 12, 10);
    expect(chordKeys("??"), chordKeys("C"));
    for (var k in chordKeys("E")) {
      expect(k, inInclusiveRange(40, 64));
    }
  });

  test("kept: a score, whole, in its document", () {
    var s = MusicScore("ode",
        title: "Ode to Joy",
        composer: "Beethoven",
        tempo: 112,
        tempoText: "Allegro",
        beats: 3,
        beatUnit: 4,
        fifths: -2,
        verses: 2,
        offsets: const {
          MarkKind.tempo: Offset(4, -6)
        },
        bars: const [
          BarInfo(mark: "A", repeatStart: true, segno: true),
          BarInfo(
              endings: [1, 2],
              repeatEnd: 3,
              time: (6, 8),
              key: 1,
              tempo: 90,
              tempoText: "Slower",
              breakAfter: BarBreak.system,
              offsets: {MarkKind.rehearsal: Offset(-10, 0)}),
          BarInfo(jump: Jump.dsAlCoda, toCoda: true, fine: true, coda: true),
        ],
        spanners: const [
          Spanner("sl", SpannerKind.slur, "p1", 1, (bar: 0, at: 0),
              (bar: 1, at: 1.5)),
        ],
        parts: [
          ScorePart(
              "p1",
              "Piano",
              "piano",
              [
                ScoreStaff(Clef.treble, [
                  [
                    ScoreEvent("a", 1,
                        dots: 1,
                        pitches: [Pitch.parse("C4")!, Pitch.parse("F#4")!],
                        tie: true,
                        voice: 1,
                        chord: "D/F#",
                        dyn: Dynamic.mp,
                        articulations: const {
                          Articulation.accent,
                          Articulation.fermata
                        },
                        lyrics: const ["Joy-", "Hearts"],
                        offsets: const {MarkKind.chord: Offset(3, -2)}),
                    const ScoreEvent("b", 0.5, tuplet: Tuplet(5, 4)),
                    const ScoreEvent("c", 0.25, grace: true),
                  ],
                ]),
                const ScoreStaff(Clef.bass, [[]]),
              ],
              short: "Pno.",
              channel: "inst1"),
          const ScorePart("p2", "Guitar", "guitarStrum", [
            ScoreStaff(Clef.treble, [
              [ScoreEvent("s", 1, slash: true, strum: Strum.up)],
            ]),
          ]),
        ]);
    var doc = CanvasDocument(elements: const [], scores: [s]);
    var back = CanvasDocument.fromJson(
            jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>)
        .scores
        .single;
    expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
    // And what it says survived, not only its shape.
    var e = back.parts[0].staves[0].bars[0][0];
    expect([
      e.pitches.last.name,
      e.dyn,
      e.lyrics,
      e.offsets[MarkKind.chord]
    ], [
      "F#4",
      Dynamic.mp,
      ["Joy-", "Hearts"],
      const Offset(3, -2)
    ]);
    expect(back.bars[1].time, (6, 8));
    expect(back.bars[1].endings, [1, 2]);
    expect(back.parts[1].staves[0].bars[0][0].strum, Strum.up);
    expect(back.spanners.single.to, (bar: 1, at: 1.5));
    expect(back.parts[0].channel, "inst1");
    expect(back.offsets[MarkKind.tempo], const Offset(4, -6));
  });

  test("a mark moved, and put back", () {
    var e = const ScoreEvent("a", 1, chord: "C")
        .movedMark(MarkKind.chord, const Offset(5, 5));
    expect(e.offsets[MarkKind.chord], const Offset(5, 5));
    expect(e.movedMark(MarkKind.chord, Offset.zero).offsets, isEmpty);
  });

  test("a new score: empty bars for each instrument's staves", () {
    var s = MusicScore.blank("b",
        instruments: ["piano", "violin", "guitarStrum"], bars: 4, beats: 3);
    expect([for (var p in s.parts) p.staves.length], [2, 1, 1]);
    expect(s.parts[0].staves[1].clef, Clef.bass);
    expect(s.parts[2].strum, isTrue);
    expect(s.parts[1].staves[0].bars.length, 4);
    expect(s.parts[1].staves[0].bars[0].single.quarters, 3);
    expect(s.parts[1].staves[0].bars[0].single.isRest, isTrue);
    expect(s.partNotes("p1"), isEmpty);
  });

  group("notes made into a score", () {
    test("a piano part on two staves, played back as it was", () {
      var notes = const [
        MidiNote(48, 0, 1), // C3, the left hand
        MidiNote(64, 0, 0.5),
        MidiNote(67, 0.5, 0.5),
        MidiNote(72, 1, 1),
      ];
      var s = scoreFromNotes("m", notes, tempo: 120);
      expect(s.parts.single.staves.length, 2);
      expect(s.parts.single.staves[1].clef, Clef.bass);
      var back = s.partNotes("p1");
      expect([for (var n in back) n.note.key]..sort(), [48, 64, 67, 72]);
      for (var n in back) {
        var was = notes.firstWhere((m) => m.key == n.note.key);
        expect(n.note.start, closeTo(was.start, 1e-9));
      }
    });

    test("a one-staff instrument keeps its low notes", () {
      var s = scoreFromNotes(
          "c", const [MidiNote(43, 0, 1), MidiNote(36, 1, 1)],
          instrument: "cello");
      expect(s.parts.single.staves.single.clef, Clef.bass);
      expect([for (var n in s.partNotes("p1")) n.note.key], [43, 36]);
    });

    test("a transposing instrument is written where it reads", () {
      var s = scoreFromNotes("t", const [MidiNote(60, 0, 2)],
          instrument: "clarinet");
      var e = s.parts.single.staves.single.bars.first.first;
      expect(e.pitches.single.name, "D4");
      expect(s.partNotes("p1").single.note.key, 60);
    });

    test("a MusicXML file: its title, tempo, time and key kept", () {
      const xml = """<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Little Tune</work-title></work>
  <part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><key><fifths>1</fifths></key>
        <time><beats>3</beats><beat-type>4</beat-type></time></attributes>
      <direction><sound tempo="90"/></direction>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration></note>
    </measure>
    <measure number="2">
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>3</duration></note>
    </measure>
  </part>
</score-partwise>""";
      var s = scoreFromMusicXml("x", readMusicXml(utf8.encode(xml)));
      expect([s.title, s.tempo, s.beats, s.beatUnit, s.fifths],
          ["Little Tune", 90, 3, 4, 1]);
      expect(s.barCount, 2);
      var first = s.parts.single.staves.first.bars[0];
      expect(first.first.pitches.single.name, "G4");
      // However the F# is written (a minim, or crotchets tied), it plays as
      // one note, spelled as the key has it.
      expect([for (var n in s.partNotes("p1")) n.note.key], [67, 66, 67]);
      expect(
          first.skip(1).every((e) => e.pitches.single.name == "F#4"), isTrue);
      expect(s.partNotes("p1").last.note.start, closeTo(2, 1e-9),
          reason: "three beats at 90 are two seconds");
    });

    test("a MIDI file's program picks the instrument", () {
      var s = scoreFromMidi("m", const MidiImport([MidiNote(60, 0, 1)], 40));
      expect(s.parts.single.instrument, "violin");
      expect(instrumentForProgram(27), "guitar");
      expect(instrumentForProgram(null), "piano");
    });
  });
}

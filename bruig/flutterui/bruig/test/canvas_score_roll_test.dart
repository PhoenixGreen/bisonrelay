import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_roll.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_score_roll_test.dart is a score part edited in the piano roll (Ken,
// 2026-11-14): shown as written, and what is drawn written back as notation
// -- only the bars touched, markings kept at their beat, a velocity drawn
// kept on its note.

/// shape is a bar written short, as canvas_score_edit_test has it.
String shape(MusicScore s, {String part = "pno", int staff = 0, int bar = 0}) =>
    [
      for (var e in s.partById(part)!.staves[staff].bars[bar])
        "${e.isRest ? "r" : e.pitches.join("+")}/${e.quarters}"
            "${e.tie ? "~" : ""}${e.voice > 0 ? "v${e.voice}" : ""}"
    ].join(" ");

List<MidiNote> notesOf(MusicScore s, String part) =>
    [for (var n in writtenNotes(s, part)) n.note];

/// moved is [notes] with the one matching [key] at [start] changed.
List<MidiNote> moved(List<MidiNote> notes, int key, double start,
        MidiNote Function(MidiNote n) f) =>
    [
      for (var n in notes)
        n.key == key && (n.start - start).abs() < 1e-6 ? f(n) : n
    ];

void main() {
  test("as written: each bar once, ties joined, sounding keys", () {
    var s = odeToJoy();
    var w = writtenNotes(s, "pno");
    // Bar 1's right hand, and its left hand's open fifths.
    expect([
      for (var n in w)
        if (n.note.start < 4) (n.note.key, n.note.start, n.staff)
    ], [
      (48, 0.0, 1),
      (55, 0.0, 1),
      (64, 0.0, 0),
      (64, 1.0, 0),
      (48, 2.0, 1),
      (55, 2.0, 1),
      (65, 2.0, 0),
      (67, 3.0, 0),
    ]);
    // Five bars, not the eight played.
    expect(w.map((n) => n.note.start).reduce((a, b) => a > b ? a : b),
        lessThan(20));
    expect(w.first.note.velocity, Dynamic.mf.velocity);
    // A clarinet's written D sounds C.
    var cl = MusicScore("c", bars: const [
      BarInfo()
    ], parts: [
      ScorePart("p", "Cl", "clarinet", [
        ScoreStaff(Clef.treble, [
          [
            ScoreEvent("a", 4, pitches: [Pitch.parse("D4")!])
          ]
        ])
      ])
    ]);
    expect(writtenNotes(cl, "p").single.note.key, 60);
  });

  test("given back as it is, nothing changes", () {
    var s = odeToJoy();
    var back = withRollNotes(s, "pno", notesOf(s, "pno"));
    expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
  });

  test("a note moved: its bar written again, its words and id kept", () {
    var s = odeToJoy();
    var e = s.parts[0].staves[0].bars[0][1]; // E4 "ful," on beat 2
    var t = withRollNotes(
        s, "pno", moved(notesOf(s, "pno"), 64, 1, (n) => n.copyWith(key: 65)));
    var now = t.parts[0].staves[0].bars[0][1];
    expect(now.pitches.single.name, "F4");
    expect(now.id, e.id);
    expect(now.lyrics, e.lyrics);
    // Every other bar is the very same.
    for (var b = 1; b < 5; b++) {
      expect(
          identical(t.parts[0].staves[0].bars[b], s.parts[0].staves[0].bars[b]),
          isTrue,
          reason: "bar ${b + 1}");
    }
    expect(
        identical(t.parts[0].staves[1].bars[0], s.parts[0].staves[1].bars[0]),
        isTrue,
        reason: "the left hand");
  });

  test("a note held over the bar line: tied", () {
    var s = odeToJoy();
    // The last note of bar 1 (G4, beat 4) held two beats, in place of the
    // G4 that starts bar 2.
    var t = withRollNotes(s, "pno", [
      for (var n
          in moved(notesOf(s, "pno"), 67, 3, (n) => n.copyWith(length: 2)))
        if (!(n.key == 67 && n.start == 4)) n
    ]);
    expect(shape(t), "E4/1.0 E4/1.0 F4/1.0 G4/1.0~");
    expect(shape(t, bar: 1).split(" ").first, "G4/1.0");
    // And plays as one note.
    var played = t.partNotes("pno").where((n) => n.note.key == 67).first;
    expect(played.note.length, greaterThan(60 / 112 * 1.9));
  });

  test("a note taken out: a rest; its dynamic goes to what is there", () {
    var s = odeToJoy();
    var t = withRollNotes(s, "pno", [
      for (var n in notesOf(s, "pno"))
        if (!(n.key == 64 && n.start == 0)) n
    ]);
    var first = t.parts[0].staves[0].bars[0].first;
    expect(first.isRest, isTrue);
    expect(first.dyn, Dynamic.mf, reason: "the mf stays at the beat");
    expect(first.chord, "C");
  });

  test("an overlap: a second voice", () {
    var s = odeToJoy();
    // A held C4 under the first bar's tune.
    var t = withRollNotes(
        s, "pno", [...notesOf(s, "pno"), const MidiNote(60, 0, 4, 80)]);
    expect(shape(t), contains("v1"));
    var lower = t.parts[0].staves[0].bars[0].where((e) => e.voice == 1);
    expect(lower.single.pitches.single.name, "C4");
    expect(lower.single.quarters, 4);
  });

  test("a velocity drawn: kept on the note, the dynamic left as it was", () {
    var s = odeToJoy();
    var t = withRollNotes(s, "pno",
        moved(notesOf(s, "pno"), 65, 2, (n) => n.copyWith(velocity: 120)));
    var e = t.parts[0].staves[0].bars[0][2];
    expect(e.velocity, 120);
    expect(e.dyn, isNull);
    expect(t.parts[0].staves[0].bars[0][0].dyn, Dynamic.mf);
    var played = t.partNotes("pno").firstWhere((n) => n.event == e.id);
    expect(played.note.velocity, 120);
    // Back to what it is marked, the drawn velocity goes.
    var u = withRollNotes(t, "pno",
        moved(notesOf(t, "pno"), 65, 2, (n) => n.copyWith(velocity: 80)));
    expect(u.parts[0].staves[0].bars[0][2].velocity, isNull);
  });

  test("drawn past the end: bars added for it", () {
    var s = odeToJoy();
    var t = withRollNotes(
        s, "pno", [...notesOf(s, "pno"), const MidiNote(72, 22, 1, 80)]);
    expect(t.barCount, 6);
    expect(shape(t, bar: 5), "r/2.0 C5/1.0 r/1.0");
  });

  test("off the grid, onto the sixteenths; a triplet left alone stays one", () {
    var trip = MusicScore("t", bars: const [
      BarInfo(),
      BarInfo()
    ], parts: [
      ScorePart("p", "Piano", "piano", [
        ScoreStaff(Clef.treble, [
          [
            for (var (i, n) in ["C5", "D5", "E5"].indexed)
              ScoreEvent("t$i", 0.5,
                  tuplet: Tuplet.triplet, pitches: [Pitch.parse(n)!]),
            const ScoreEvent(
              "r",
              2,
            ),
            const ScoreEvent("r2", 1),
          ],
          [const ScoreEvent("r3", 4)],
        ]),
        const ScoreStaff(Clef.bass, [
          [ScoreEvent("b1", 4)],
          [ScoreEvent("b2", 4)]
        ]),
      ])
    ]);
    var t = withRollNotes(
        trip, "p", [...notesOf(trip, "p"), const MidiNote(76, 4.1, 0.9, 80)]);
    expect(
        identical(
            t.parts[0].staves[0].bars[0], trip.parts[0].staves[0].bars[0]),
        isTrue,
        reason: "the triplet's bar untouched");
    expect(shape(t, part: "p", bar: 1), "E5/1.0 r/1.0 r/2.0");
  });

  testWidgets("in the roll itself: a note drawn is written in the score",
      (tester) async {
    var c = CanvasController(const CanvasDocument(frames: 240),
        audioEngine: FakeEngine({}));
    c.addScore(MusicScore.blank("ode", instruments: ["violin"], bars: 2));
    var ch = c.document.elementById(c.scoreById("ode")!.parts.single.channel)
        as AudioElement;
    c.openPianoRoll(ch.clip.channel.isEmpty ? ch.id : ch.clip.channel);
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => CanvasMixer.effects(
                          controller: c,
                          height: 760,
                          onResize: (_) {},
                          onClose: () {}))))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    // A beat is 48 wide, a key 12 high, the top row key 127.
    var grid = tester.getTopLeft(find.byKey(const ValueKey("rollGrid")));
    await tester.tapAt(grid + const Offset(1 * 48 + 3, (127 - 67) * 12 + 6));
    await tester.pump();
    var s = c.scoreById("ode")!;
    expect(
        shape(s, part: s.parts.single.id), "r/1.0 G4/0.25 r/0.25 r/0.5 r/2.0");
    c.undo();
    expect(shape(c.scoreById("ode")!, part: s.parts.single.id), "r/4.0",
        reason: "one change to undo");
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

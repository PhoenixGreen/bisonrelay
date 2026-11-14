import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/score_channels.dart';
import 'package:bruig/plugin_system/canvas/model/score_edit.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_score_channels_test.dart is each part of a score playing on an
// instrument channel of its own, its notes made from the score at every
// edit (Ken, 2026-11-14: "the score works as MIDI: all instruments play").

/// duet is a two-bar score for piano and violin, each part a scale step.
MusicScore duet({String violinNote = "E5"}) =>
    MusicScore("ode", title: "Ode", tempo: 120, bars: const [
      BarInfo(),
      BarInfo()
    ], parts: [
      ScorePart("pno", "Piano", "piano", [
        ScoreStaff(Clef.treble, [
          [
            ScoreEvent("a", 4, pitches: [Pitch.parse("C4")!])
          ],
          [
            ScoreEvent("b", 4, pitches: [Pitch.parse("D4")!])
          ],
        ]),
        const ScoreStaff(Clef.bass, [
          [ScoreEvent("r1", 4)],
          [ScoreEvent("r2", 4)],
        ]),
      ]),
      ScorePart("vln", "Violin", "violin", [
        ScoreStaff(Clef.treble, [
          [
            ScoreEvent("c", 4, pitches: [Pitch.parse(violinNote)!])
          ],
          const [ScoreEvent("r3", 4)],
        ]),
      ]),
    ]);

AudioElement channelOf(CanvasController c, MusicScore s, String part) =>
    c.document.elementById(c.scoreById(s.id)!.partById(part)!.channel)
        as AudioElement;

void main() {
  test("kept: a channel's link to its score, a sheet's score part", () {
    var part = InstrumentPart.fromJson(
        const InstrumentPart(score: "ode/pno").toJson());
    expect(part.score, "ode/pno");
    expect(part.fromScore, isTrue);
    var sheet = elementFromJson(SheetElement(const ElementBase(id: "s"),
            follows: "ch", score: "ode", part: "vln")
        .toJson()) as SheetElement;
    expect([sheet.follows, sheet.score, sheet.part], ["ch", "ode", "vln"]);
  });

  test("synced: each part's notes in its channel, and no change no change", () {
    var piano = newInstrument(const CanvasDocument());
    var s = duet();
    s = s.copyWith(parts: [s.parts[0].copyWith(channel: piano.id), s.parts[1]]);
    var doc = scoreSynced(CanvasDocument(elements: [piano]), s);
    var made = doc.elementById(piano.id) as AudioElement;
    expect([for (var n in made.instrument!.notes) (n.key, n.start)],
        [(60, 0.0), (62, 2.0)]);
    expect(made.instrument!.score, "ode/pno");
    expect(scorePartOf(doc, made.instrument!)!.$2.name, "Piano");
    // Synced again with nothing changed, the element is the same one.
    var again = scoreSynced(doc, s);
    expect(identical(again.elementById(piano.id), made), isTrue);
  });

  test("a score taken out leaves its channels their notes", () {
    var piano = newInstrument(const CanvasDocument());
    var s = duet();
    s = s.copyWith(parts: [s.parts[0].copyWith(channel: piano.id), s.parts[1]]);
    var doc =
        scoreRemoved(scoreSynced(CanvasDocument(elements: [piano]), s), "ode");
    var left = doc.elementById(piano.id) as AudioElement;
    expect(doc.scores, isEmpty);
    expect(left.instrument!.fromScore, isFalse);
    expect(left.instrument!.notes.length, 2);
  });

  group("in the editor", () {
    test("a score added: a hidden channel a part, its sound, one undo", () {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addScore(duet());
      var violin = channelOf(c, duet(), "vln");
      expect(violin.base.name, "Violin");
      expect(violin.base.visible, isFalse);
      expect(violin.instrument!.program, 40);
      expect(violin.instrument!.notes.single.key, 76);
      expect(channelOf(c, duet(), "pno").instrument!.notes.length, 2);
      c.undo();
      expect(c.document.scores, isEmpty);
      expect(c.document.elements.whereType<AudioElement>(), isEmpty);
    });

    test("the score edited: its channel's notes follow", () {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addScore(duet());
      var s = c.scoreById("ode")!;
      var edited = duet(violinNote: "G5");
      c.setScore(edited.copyWith(parts: [
        for (var (i, p) in edited.parts.indexed)
          p.copyWith(channel: s.parts[i].channel),
      ]));
      expect(channelOf(c, s, "vln").instrument!.notes.single.key, 79);
    });

    test("the piano roll writes a score part into its score; a strum's not",
        () {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var s = duet().addPart("guitarStrum");
      c.addScore(s);
      var piano = channelOf(c, s, "pno");
      var strum = channelOf(c, s, s.parts.last.id);
      var own = newInstrument(c.document);
      c.addElement(own, select: false);
      for (var (e, changes) in [(piano, true), (strum, false), (own, true)]) {
        c.openPianoRoll(e.clip.channel.isEmpty ? e.id : e.clip.channel);
        c.setRollContent(notes: const [MidiNote(72, 0, 1)]);
        var now = c.document.elementById(e.id) as AudioElement;
        expect(now.instrument!.notes.any((n) => n.key == 72), changes,
            reason: e.base.name);
      }
      // The piano's C5 is the score's now, as written.
      var bar = c.scoreById("ode")!.parts[0].staves[0].bars[0];
      expect(bar.first.pitches.single.name, "C5");
    });

    test("a new sheet shows the score's first part", () {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addScore(duet());
      var sheet = newElement(ElementKind.sheet, c.document) as SheetElement;
      expect([sheet.score, sheet.part, sheet.title], ["ode", "pno", "Ode"]);
      expect(sheet.follows, channelOf(c, duet(), "pno").id);
    });

    testWidgets("its settings choose a part of the score", (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 240),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addScore(duet());
      var sheet = SheetElement(const ElementBase(id: "sheet"));
      c.addElement(sheet);
      tester.view.physicalSize = const Size(1200, 1600);
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
      var follows = find.byKey(const ValueKey("sheetFollows"));
      await tester.ensureVisible(follows);
      await tester.tap(follows);
      await tester.pump(const Duration(milliseconds: 300));
      // The score's parts, not their hidden channels by name alone.
      expect(find.text("Ode · Violin"), findsWidgets);
      await tester.tap(find.text("Ode · Violin").last);
      await tester.pump(const Duration(milliseconds: 300));
      var now = c.document.elementById("sheet") as SheetElement;
      expect([now.score, now.part], ["ode", "vln"]);
      expect(now.follows, channelOf(c, duet(), "vln").id);
    });
  });
}

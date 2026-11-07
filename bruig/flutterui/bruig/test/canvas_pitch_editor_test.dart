import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/pitch_retune.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_pitch_editor_test.dart is the Pitch editor: a recording's notes
// found from its pitch, moved, split, glued, straightened, and the
// recording made again from the original with them -- its timing kept,
// the rest as it was.

const double rate = 48000;

/// sung is [seconds] of a voice-like buzz at [hz]: a saw, softened.
Float32List sung(List<(double, double)> parts) {
  var out = <double>[];
  var phase = 0.0;
  for (var (hz, seconds) in parts) {
    for (var i = 0; i < (seconds * rate).round(); i++) {
      phase = (phase + hz / rate) % 1;
      out.add(hz <= 0
          ? 0
          : 0.3 * math.sin(2 * math.pi * phase) +
              0.1 * math.sin(4 * math.pi * phase));
    }
  }
  return Float32List.fromList(out);
}

double? pitchAround(Float32List x, double seconds) {
  var at = (seconds * rate).round();
  var p = detectPitch(Float32List.sublistView(x, at, at + 2048),
      rate: rate, minHz: 60, maxHz: 1000);
  return p?.hz;
}

void main() {
  group("the notes", () {
    test("found where the pitch steps, and not in a wobble", () {
      List<double?> track = [
        for (var i = 0; i < 25; i++) 60 + 0.3 * math.sin(i / 2),
        for (var i = 0; i < 25; i++) 64.1,
        for (var i = 0; i < 5; i++) null,
        for (var i = 0; i < 15; i++) 66.8,
        // A blip too short to be a note.
        null, 70, null,
      ];
      var notes = findNotes(track);
      expect(notes.map((n) => n.sung.round()), [60, 64, 67]);
      expect(notes[0].start, 0);
      expect(notes[1].start, closeTo(0.5, 1e-9));
      expect(notes[2].start, closeTo(1.1, 1e-9));
      expect(notes[2].end, closeTo(1.4, 1e-9));
    });

    test("where each is moved to; kept; split and glued", () {
      const n = PitchNote(0, 1, 60.3);
      expect(n.target, 60.3);
      expect(n.copyWith(straighten: 1).target, 60);
      expect(n.copyWith(straighten: 1, shift: 2).target, 62);
      expect(n.copyWith(shift: 0).edited, isFalse);
      var edit = PitchEdit("a.wav", notes: [
        n.copyWith(shift: 1, wobble: 0.5),
        const PitchNote(1, 2, 64),
      ]);
      expect(PitchEdit.fromJson(edit.toJson())!.notes, edit.notes);
      var cut = edit.split(0, 0.4);
      expect(
          cut.notes.map((n) => (n.start, n.end)), [(0, 0.4), (0.4, 1), (1, 2)]);
      expect(cut.notes[1].shift, 1, reason: "both halves keep its changes");
      var glued = edit.glue(0);
      expect(glued.notes.single.end, 2);
      expect(glued.notes.single.sung, closeTo((60.3 + 64) / 2, 1e-9));
      expect(edit.stale, isTrue);
      expect(edit.copyWith(madeWith: edit.key).stale, isFalse);
    });

    test("a start moved by Quantise timing: kept, and where it is heard from",
        () {
      const n = PitchNote(1, 2, 60);
      var moved = n.copyWith(startAt: 1.2);
      expect(moved.edited, isTrue);
      expect(moved.heardStart, 1.2);
      expect(PitchNote.fromJson(moved.toJson()), moved);
      // Stretched from 1.2 to its end: half way there is 0.4 of the way
      // through what was sung.
      expect(moved.sourceAt(1.6), closeTo(1.5, 1e-9));
      expect(moved.sourceAt(1.1), isNull,
          reason: "silence before, moved later");
      expect(moved.sourceAt(0.5), 0.5, reason: "before the note, as it was");
      expect(n.copyWith(startAt: 0.8).sourceAt(0.8), 1,
          reason: "moved earlier: it starts there");
      expect(moved.copyWith(clearStartAt: true).startAt, isNull);
    });

    // Ken, 2026-11-08: a note stretched by its edges, and faded in and out.
    test("stretched by its edges and faded: kept, heard, split and glued", () {
      const n = PitchNote(1, 2, 60);
      var long = n.copyWith(endAt: 2.5);
      expect(long.edited, isTrue);
      expect(long.heardEnd, 2.5);
      expect(long.stretch, closeTo(1.5, 1e-9));
      expect(PitchNote.fromJson(long.toJson()), long);
      // Heard from its start to 2.5: half way is half way through it.
      expect(long.sourceAt(1.75), closeTo(1.5, 1e-9));
      expect(long.sourceAt(2.4), closeTo(1 + 1.4 / 1.5, 1e-9));
      expect(long.sourceAt(2.6), 2.6, reason: "after it, as it was");
      var short = n.copyWith(endAt: 1.5);
      expect(short.sourceAt(1.25), closeTo(1.5, 1e-9));
      expect(short.sourceAt(1.8), isNull, reason: "squeezed: silent after");
      expect(short.copyWith(clearEndAt: true).endAt, isNull);
      // Faded in over a fifth of a second, out over a tenth.
      var faded = n.copyWith(fadeIn: 0.2, fadeOut: 0.1);
      expect(faded.edited, isTrue);
      expect(PitchNote.fromJson(faded.toJson()), faded);
      expect(faded.fadeAt(1.0), 0);
      expect(faded.fadeAt(1.1), closeTo(0.5, 1e-9));
      expect(faded.fadeAt(1.5), 1);
      expect(faded.fadeAt(1.95), closeTo(0.5, 1e-9));
      expect(faded.reset.edited, isFalse);
      expect(faded.copyWith(fadeIn: 0.3).hashCode, isNot(faded.hashCode));
      // Split: each half heard where it was, stretched as it was; the
      // first keeps its fade in, the second its fade out.
      var both = n.copyWith(endAt: 3, fadeIn: 0.2, fadeOut: 0.4);
      var cut = PitchEdit("a.wav", notes: [both]).split(0, 1.5);
      var (a, b) = (cut.notes[0], cut.notes[1]);
      expect((a.start, a.end, a.heardStart, a.heardEnd), (1, 1.5, 1, 2));
      expect((b.start, b.end, b.heardStart, b.heardEnd), (1.5, 2, 2, 3));
      expect((a.fadeIn, a.fadeOut, b.fadeIn, b.fadeOut), (0.2, 0, 0, 0.4));
      expect(a.sourceAt(1.5), closeTo(1.25, 1e-9));
      expect(b.sourceAt(2.5), closeTo(1.75, 1e-9));
      // Not stretched, split, neither half is.
      var plain = PitchEdit("a.wav", notes: [n]).split(0, 1.5);
      expect(plain.notes.every((m) => !m.timed), isTrue);
      // Glued back: one note, heard from the first's start to the second's
      // end, faded as each was.
      var glued = cut.glue(0).notes.single;
      expect((glued.start, glued.end, glued.heardStart, glued.heardEnd),
          (1, 2, 1, 3));
      expect((glued.fadeIn, glued.fadeOut), (0.2, 0.4));
    });

    test("each note's own retune, vibrato, formant, slide and drawing kept",
        () {
      var n = const PitchNote(0, 1, 60.3).copyWith(
          wobble: 0.5,
          vibrato: 0.2,
          retuneMs: 80,
          formant: -3,
          slideMs: 120,
          curve: const [(0.1, 61), (0.5, 63)]);
      expect(n.edited, isTrue);
      var back = PitchNote.fromJson(n.toJson())!;
      expect(back, n);
      expect(back.drawnAt(0.3), closeTo(62, 1e-9));
      expect(back.drawnAt(0.7), isNull, reason: "only where it is drawn");
      // A file from before: its one wobble kept both.
      var old = PitchNote.fromJson({"s": 0, "e": 1, "p": 60, "wobble": 0.3})!;
      expect(old.vibrato, 0.3);
      expect(old.wobble, 0.3);
      expect(n.movedTo(67).target, 67);
      expect(n.reset.edited, isFalse);
      // Split, the drawing goes with each half.
      var cut = PitchEdit("a.wav", notes: [n]).split(0, 0.3);
      expect(cut.notes[0].curve, [(0.1, 61.0)]);
      expect(cut.notes[1].curve, [(0.5, 63.0)]);
    });

    test("heard: drawn, drifting, retuned and slid in", () {
      const n = PitchNote(1, 2, 60, shift: 2);
      // As sung 60.4 drifting at 60.2: the drift and the swing round it
      // kept as asked.
      expect(pitchHeardAt(n, 1.5, 60.4, 60.2), closeTo(62.4, 1e-9));
      expect(pitchHeardAt(n.copyWith(vibrato: 0), 1.5, 60.4, 60.2),
          closeTo(62.2, 1e-9));
      expect(pitchHeardAt(n.copyWith(vibrato: 0, wobble: 0), 1.5, 60.4, 60.2),
          closeTo(62, 1e-9));
      // Retuned over 100ms: still near as sung at its start, there after.
      var slow = n.copyWith(retuneMs: 100, vibrato: 0, wobble: 0);
      expect(pitchHeardAt(slow, 1.0, 60, 60), closeTo(60, 1e-9));
      expect(pitchHeardAt(slow, 1.6, 60, 60), closeTo(62, 0.01));
      // Slid in from the note before.
      var slid = n.copyWith(slideMs: 200, vibrato: 0, wobble: 0);
      expect(pitchHeardAt(slid, 1.0, 60, 60, before: 55), closeTo(55, 1e-9));
      expect(pitchHeardAt(slid, 1.1, 60, 60, before: 55), closeTo(58.5, 1e-9));
      expect(pitchHeardAt(slid, 1.3, 60, 60, before: 55), closeTo(62, 1e-9));
      // Drawn: what is drawn.
      var drawn = n.copyWith(curve: const [(1.2, 64), (1.6, 66)]);
      expect(pitchHeardAt(drawn, 1.4, 60, 60), closeTo(65, 1e-9));
    });
  });

  group("the sound", () {
    test("a note moved an octave sounds an octave up; the rest as it was", () {
      // A3 for a second, then a second of D4.
      var x = sung([(220, 1), (293.66, 1)]);
      var track = pitchTrackOfPcm(x);
      var notes = findNotes(track);
      expect(notes.length, 2);
      var moved = [notes[0].copyWith(shift: 12), notes[1]];
      var out = retuneTake(x, track, moved);
      expect(out.length, x.length, reason: "its timing kept");
      expect(pitchAround(out, 0.5), closeTo(440, 8));
      // The second, unchanged, as it was.
      for (var i = (1.3 * rate).round(); i < (1.3 * rate).round() + 500; i++) {
        expect(out[i], x[i]);
      }
    });

    test("straightened onto its note, and its wobble kept or smoothed", () {
      expect(hzOf(69), 440);
      // Sung a third of a semitone sharp of A3.
      var x = sung([(224.2, 1)]);
      var track = pitchTrackOfPcm(x);
      var n = findNotes(track).single;
      var out = retuneTake(x, track, [n.copyWith(straighten: 1)]);
      expect(pitchAround(out, 0.5), closeTo(220, 4));
    });

    test("moved later in time: quiet till then, its own sound after", () {
      // A second of A3, from 0.2 s; the rest silent.
      var x = sung([(0, 0.2), (220, 1), (0, 0.3)]);
      var track = pitchTrackOfPcm(x);
      var n = findNotes(track).first;
      var out = retuneTake(x, track, [n.copyWith(startAt: n.start + 0.2)]);
      expect(out.length, x.length, reason: "its timing kept overall");
      double loud(double from, double to) {
        var most = 0.0;
        for (var i = (from * rate).round(); i < (to * rate).round(); i++) {
          most = math.max(most, out[i].abs());
        }
        return most;
      }

      expect(loud(n.start + 0.03, n.start + 0.17), lessThan(0.02),
          reason: "silent where it no longer is");
      expect(loud(n.start + 0.25, n.start + 0.6), greaterThan(0.1));
      expect(pitchAround(out, n.start + 0.5), closeTo(220, 6),
          reason: "stretched, its pitch the same");
    });

    double loudIn(Float32List out, double from, double to) {
      var most = 0.0;
      for (var i = (from * rate).round(); i < (to * rate).round(); i++) {
        most = math.max(most, out[i].abs());
      }
      return most;
    }

    test("faded in and out: quiet at its edges, as loud as ever between", () {
      var x = sung([(0, 0.2), (220, 1), (0, 0.3)]);
      var track = pitchTrackOfPcm(x);
      var n = findNotes(track).first;
      var out = retuneTake(x, track, [n.copyWith(fadeIn: 0.4, fadeOut: 0.3)]);
      var full = loudIn(out, n.start + 0.45, n.end - 0.35);
      expect(full, greaterThan(0.25), reason: "between its fades, as it was");
      expect(loudIn(out, n.start, n.start + 0.04), lessThan(full * 0.15),
          reason: "it starts quiet");
      expect(loudIn(out, n.start + 0.18, n.start + 0.22),
          closeTo(full * 0.5, full * 0.15),
          reason: "half way in, half as loud");
      expect(loudIn(out, n.end - 0.04, n.end), lessThan(full * 0.2),
          reason: "it ends quiet");
    });

    test("stretched by its end: its sound lasts as long, its pitch kept", () {
      // 0.6 s of A3, then silence.
      var x = sung([(0, 0.1), (220, 0.6), (0, 0.8)]);
      var track = pitchTrackOfPcm(x);
      var n = findNotes(track).first;
      var out = retuneTake(x, track, [n.copyWith(endAt: n.end + 0.4)]);
      expect(out.length, x.length);
      expect(loudIn(x, n.end + 0.1, n.end + 0.3), lessThan(0.01),
          reason: "silent there as sung");
      expect(loudIn(out, n.end + 0.05, n.end + 0.3), greaterThan(0.2),
          reason: "stretched on into it");
      expect(pitchAround(out, n.end + 0.1), closeTo(220, 6),
          reason: "stretched, not slowed down");
      expect(loudIn(out, n.end + 0.5, n.end + 0.7), lessThan(0.02),
          reason: "over where it now ends");
      // Squeezed: silent before where it was sung to end.
      var short = retuneTake(x, track, [n.copyWith(endAt: n.end - 0.25)]);
      expect(loudIn(short, n.end - 0.18, n.end - 0.02), lessThan(0.02));
      expect(loudIn(short, n.start + 0.05, n.end - 0.3), greaterThan(0.2));
    });

    test("its formant moved, its pitch kept", () {
      var x = sung([(220, 1)]);
      var track = pitchTrackOfPcm(x);
      var n = findNotes(track).single;
      for (var f in [-4.0, 4.0]) {
        var out = retuneTake(x, track, [n.copyWith(formant: f)]);
        expect(pitchAround(out, 0.5), closeTo(220, 5), reason: "at $f st");
        // And the sound changed: not the same samples.
        var diff = 0.0;
        for (var i = 20000; i < 22000; i++) {
          diff += (out[i] - x[i]).abs();
        }
        expect(diff, greaterThan(1), reason: "its colour moved at $f st");
      }
    });
  });

  group("in the controller", () {
    late CanvasController c;
    late FakeEngine engine;
    var stored = <String, Float32List>{};
    var x = sung([(220, 0.6), (293.66, 0.6)]);

    setUp(() {
      // The real ones back after: a bundle runs other files after this.
      var audio = CanvasController.takeAudio;
      var store = CanvasController.speechTakeStore;
      addTearDown(() {
        CanvasController.takeAudio = audio;
        CanvasController.speechTakeStore = store;
      });
      stored = {"take.wav": x};
      CanvasController.takeAudio = (id) async => stored[id];
      CanvasController.speechTakeStore = (wav) async {
        var id = "made${stored.length}.wav";
        stored[id] = x;
        return id;
      };
      pitchTrackSeed("take.wav", pitchTrackOfPcm(x));
      c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            AudioElement(const ElementBase(id: "v", name: "Voice"),
                clip: const MediaClip(
                    timed: true,
                    playlist: [MediaSource(assetId: "take.wav", length: 1.2)])),
          ]),
          audioEngine: engine = FakeEngine({"take.wav": 1.2}));
      addTearDown(c.dispose);
    });

    test("found, moved, made again from the original, put back", () async {
      expect(c.pitchEditOf("v"), isNull);
      expect(c.findPitchNotes("v"), isTrue);
      expect(c.pitchEditOf("v")!.notes.length, 2);
      c.editPitch(
          "v",
          (e) => e.copyWith(
              notes: [...e.notes]..[0] = e.notes[0].copyWith(shift: 2)));
      await c.renderPitch("v");
      var source = c.pitchSourceOf("v")!;
      expect(source.assetId, isNot("take.wav"), reason: "made again");
      expect(source.pitch!.original, "take.wav");
      expect(source.pitch!.stale, isFalse);
      expect(c.document.elementById("v") is AudioElement, isTrue);
      expect((c.document.elementById("v") as AudioElement).clip.mediaIds,
          containsAll(["take.wav", source.assetId]),
          reason: "the original kept with it");
      c.forgetPitch("v");
      expect(c.pitchSourceOf("v")!.assetId, "take.wav");
      expect(c.pitchEditOf("v"), isNull);
    });

    testWidgets("its Pitch tab, the notes found, and one dragged up a tone",
        (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.showPitch("v");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 420,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey("pitchFind")));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.pitchEditOf("v")!.notes.length, 2);
      // The first note's blob: A3 for 0.6 s, a second at 120 px.
      var note = c.pitchEditOf("v")!.notes.first;
      var grid = find.byKey(const ValueKey("pitchGrid"));
      await tester.ensureVisible(grid);
      await tester.pump();
      // Where a note is: its rows from three under the lowest to three
      // over the highest, filling the grid; its time across it.
      Offset at(PitchNote n, double target) {
        var edit = c.pitchEditOf("v")!;
        var high =
            edit.notes.map((n) => math.max(n.sung, n.target)).reduce(math.max) +
                3;
        var low =
            edit.notes.map((n) => math.min(n.sung, n.target)).reduce(math.min) -
                3;
        var top = high.ceilToDouble(), bottom = low.floorToDouble();
        var size = tester.getSize(grid);
        var tone = size.height / (top - bottom);
        var perSecond = size.width / (pitchTrackOfPcm(x).length * 0.02);
        return tester.getTopLeft(grid) +
            Offset((n.start + n.length / 2) * perSecond,
                (top - target) * tone + tone / 2);
      }

      double tone() {
        var edit = c.pitchEditOf("v")!;
        var high =
            edit.notes.map((n) => math.max(n.sung, n.target)).reduce(math.max) +
                3;
        var low =
            edit.notes.map((n) => math.min(n.sung, n.target)).reduce(math.min) -
                3;
        return tester.getSize(grid).height /
            (high.ceilToDouble() - low.floorToDouble());
      }

      // Two rows up, onto the scale (C major, the editor's own here).
      await tester.dragFrom(at(note, note.target), Offset(0, -2 * tone()));
      await tester.pump(const Duration(milliseconds: 100));
      var moved = c.pitchEditOf("v")!.notes.first;
      expect(moved.target, closeTo(note.target.roundToDouble() + 2, 1e-6),
          reason: "two rows up: a tone, on the scale");
      expect(find.byKey(const ValueKey("pitchInspector")), findsOneWidget);
      expect(find.byKey(const ValueKey("pitchPickedTitle")), findsOneWidget,
          reason: "the note picked, its own settings shown");
      expect(find.byKey(const ValueKey("pitchRetune")), findsOneWidget);
      expect(find.byKey(const ValueKey("pitchFormant")), findsOneWidget);
      // Up a note from the keyboard: the next of the scale, B to C.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.pitchEditOf("v")!.notes.first.target, closeTo(60, 1e-6));
      // Twice on it: back to the nearest note to where it was sung.
      var first = c.pitchEditOf("v")!.notes.first;
      await tester.tapAt(at(first, first.target));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at(first, first.target));
      await tester.pump();
      expect(c.pitchEditOf("v")!.notes.first.target,
          closeTo(note.sung.roundToDouble(), 1e-6));
      // Drawn over by hand: a pitch of its own.
      await tester.tap(find.byKey(const ValueKey("pitchTool-draw")));
      await tester.pump();
      var second = c.pitchEditOf("v")!.notes[1];
      var from = at(second, second.target) - const Offset(30, 0);
      await tester.dragFrom(from, const Offset(60, -10));
      await tester.pump();
      expect(c.pitchEditOf("v")!.notes[1].curve.length, greaterThan(1));
      // Every note onto the scale: Correct every note.
      await tester.ensureVisible(find.byKey(const ValueKey("pitchCorrectAll")));
      await tester.tap(find.byKey(const ValueKey("pitchCorrectAll")));
      await tester.pump();
      for (var n in c.pitchEditOf("v")!.notes) {
        expect(n.target, closeTo(n.target.roundToDouble(), 1e-6));
      }
      // Heard as sung, and corrected again.
      await tester.runAsync(() => c.renderPitch("v"));
      await tester.pump();
      var made = c.pitchSourceOf("v")!.assetId;
      await tester.ensureVisible(find.byKey(const ValueKey("pitchHearSung")));
      await tester.tap(find.byKey(const ValueKey("pitchHearSung")));
      await tester.pump();
      expect(c.pitchSourceOf("v")!.assetId, "take.wav");
      expect(c.pitchHeardAsSung("v"), isTrue);
      await tester.tap(find.byKey(const ValueKey("pitchHearCorrected")));
      await tester.pump();
      expect(c.pitchSourceOf("v")!.assetId, made);
      // A key pressed sounds its note, through the channel; let go, stops.
      engine.notes.clear();
      var keys = tester.getRect(find.byKey(const ValueKey("pitchKeys")));
      var press = await tester.startGesture(keys.topLeft + const Offset(10, 5));
      await tester.pump();
      expect(engine.notes.single.$1, "v");
      expect(engine.notes.single.$3, greaterThan(0));
      await press.up();
      await tester.pump();
      expect(engine.notes.last.$3, 0, reason: "let go");
      // Quantise timing, nothing picked: every start on a sixteenth of the
      // song.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey("pitchQuantise")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("pitchQuantise")));
      await tester.pump();
      var sixteenth = 0.5 / 4;
      for (var n in c.pitchEditOf("v")!.notes) {
        var q = n.heardStart / sixteenth;
        expect(q, closeTo(q.roundToDouble(), 1e-6), reason: "${n.heardStart}");
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    });

    // Ken, 2026-11-08: a note's edges stretch it, the squares on its top
    // edge fade it.
    testWidgets("a note's edge dragged stretches it; its handle fades it",
        (tester) async {
      tester.view.physicalSize = const Size(1800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      c.showPitch("v");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 420,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.findPitchNotes("v"), isTrue);
      await tester.pump();
      var grid = find.byKey(const ValueKey("pitchGrid"));
      await tester.ensureVisible(grid);
      await tester.pump();
      var edit = c.pitchEditOf("v")!;
      var high =
          edit.notes.map((n) => math.max(n.sung, n.target)).reduce(math.max) +
              3;
      var low =
          edit.notes.map((n) => math.min(n.sung, n.target)).reduce(math.min) -
              3;
      var top = high.ceilToDouble(), bottom = low.floorToDouble();
      var size = tester.getSize(grid);
      var row = size.height / (top - bottom);
      var perSecond = size.width / (pitchTrackOfPcm(x).length * 0.02);
      var h = math.max(14.0, row * 1.25);
      var origin = tester.getTopLeft(grid);
      double yOf(PitchNote n) => (top - n.target) * row + row / 2;
      // The first note's right edge, a fifth of a second in: squeezed.
      var first = edit.notes.first;
      await tester.dragFrom(
          origin + Offset(first.end * perSecond - 2, yOf(first)),
          Offset(-0.2 * perSecond, 0));
      await tester.pump();
      var squeezed = c.pitchEditOf("v")!.notes.first;
      expect(squeezed.heardEnd, closeTo(first.end - 0.2, 0.02));
      expect(squeezed.stretch, lessThan(0.75));
      expect(squeezed.start, first.start, reason: "sung where it was");
      // The second note's fade-in square, at its top-left corner, dragged
      // a tenth of a second in.
      var second = edit.notes[1];
      await tester.dragFrom(
          origin +
              Offset(
                  second.heardStart * perSecond + 1, yOf(second) - h / 2 + 1),
          Offset(0.1 * perSecond, 0));
      await tester.pump();
      var faded = c.pitchEditOf("v")!.notes[1];
      expect(faded.fadeIn, closeTo(0.1, 0.02));
      expect(faded.target, closeTo(second.target, 1e-9),
          reason: "not moved up or down");
      // Its fade out, and its length, in the inspector.
      expect(find.byKey(const ValueKey("pitchFadeOut")), findsOneWidget);
      expect(find.byKey(const ValueKey("pitchStretch")), findsOneWidget);
      // One undo each.
      c.undo();
      expect(c.pitchEditOf("v")!.notes[1].fadeIn, 0);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    });

    test("its lyrics: the words of the take its Speech spoke", () {
      c.setSpeech(
          "v",
          SpeechSpec(lines: [
            const SpeechLine("Oh I fly").withSlot(
                0,
                const SpeechTake("take.wav", 1.2, [
                  (text: "Oh", start: 0.0, end: 0.5),
                  (text: "fly", start: 0.6, end: 1.2),
                ])),
          ]));
      expect(c.pitchWordsOf("v")!.map((w) => w.text), ["Oh", "fly"]);
    });
  });
}

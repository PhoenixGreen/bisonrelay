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
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
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
  });

  group("in the controller", () {
    late CanvasController c;
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
          audioEngine: FakeEngine({"take.wav": 1.2}));
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
      var top = tester.getTopLeft(grid);
      // Rows from 4 over the highest note: the first note's row.
      var edit = c.pitchEditOf("v")!;
      var high = edit.notes.map((n) => n.sung).reduce(math.max) + 4;
      var low = edit.notes.map((n) => n.sung).reduce(math.min) - 4;
      // A semitone's height: the grid fills the room it has.
      var tone = tester.getSize(grid).height /
          (high.ceilToDouble() - low.floorToDouble());
      var y = (high.ceilToDouble() - note.target) * tone + tone / 2;
      var at = top + Offset((note.start + note.length / 2) * 120, y);
      await tester.dragFrom(at, Offset(0, -2 * tone));
      await tester.pump(const Duration(milliseconds: 100));
      var moved = c.pitchEditOf("v")!.notes.first;
      expect(moved.target, closeTo(note.target.roundToDouble() + 2, 1e-6),
          reason: "two rows up: a tone, on the semitones");
      expect(find.byKey(const ValueKey("pitchInspector")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

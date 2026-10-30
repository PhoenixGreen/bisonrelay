import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/vocaliser.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_vocaliser_test.dart is speech sung: a take's words as syllables,
// a melody one note at a time, and each syllable moved onto its note.

/// voice is [seconds] of a voice-like tone at [hz]: a buzz with falling
/// harmonics, as a voice's vowel is.
Float32List voice(double hz, double seconds) {
  var n = (seconds * 48000).round();
  var x = Float32List(n);
  for (var i = 0; i < n; i++) {
    var t = i / 48000;
    for (var h = 1; h <= 6; h++) {
      x[i] += 0.25 / h * math.sin(2 * math.pi * hz * h * t);
    }
  }
  return x;
}

void main() {
  test("words are broken into syllables, a vowel group each", () {
    var s = syllablesOf([
      (text: "hello", start: 0.0, end: 0.5),
      (text: "made", start: 0.5, end: 0.8),
      (text: "banana", start: 1.0, end: 1.6),
    ]);
    // Cut halfway between vowels: hel-lo, ba-na-na.
    expect(s.map((x) => x.text), ["hel", "lo", "made", "ba", "na", "na"]);
    expect(s.first.start, 0);
    expect(s[1].end, closeTo(0.5, 1e-9));
    expect(s[3].start, closeTo(1.0, 1e-9));
  });

  test("a melody is one note at a time, the higher where two sound", () {
    var m = melodyOf(const [
      MidiNote(60, 0, 1),
      MidiNote(64, 0, 1), // a chord: the higher
      MidiNote(67, 0.5, 1), // overlaps: the last cut short
    ]);
    expect(m.map((n) => n.key), [64, 67]);
    expect(m.first.length, closeTo(0.5, 1e-9));
  });

  test("syllables go on the notes in order, the last held or shared", () {
    const syl = [
      (text: "a", start: 0.0, end: 0.1),
      (text: "b", start: 0.1, end: 0.2),
    ];
    var held = assignSyllables(syl, const [
      MidiNote(60, 0, 1),
      MidiNote(62, 1, 1),
      MidiNote(64, 2, 1),
    ]);
    expect(held.map((s) => s.syllable.text), ["a", "b", "b"]);
    var shared = assignSyllables(const [
      (text: "a", start: 0.0, end: 0.1),
      (text: "b", start: 0.1, end: 0.2),
      (text: "c", start: 0.2, end: 0.3),
    ], const [
      MidiNote(60, 0, 1),
      MidiNote(62, 1, 1)
    ]);
    expect(shared.map((s) => s.syllable.text), ["a", "bc"]);
  });

  test("a spoken vowel is sung on each note's pitch, for its length", () {
    // Spoken at 150Hz; sung on A3 then E4.
    var spoken = voice(150, 1.0);
    var sung = singTake(
        spoken,
        assignSyllables(const [
          (text: "ah", start: 0.1, end: 0.5),
          (text: "oh", start: 0.5, end: 0.9),
        ], const [
          MidiNote(57, 2.0, 0.8),
          MidiNote(64, 2.8, 0.8),
        ]),
        settings: const SingSettings(vibrato: 0, glideSeconds: 0));
    expect(sung.length / 48000, closeTo(1.6, 0.01),
        reason: "from the first note's start to the last's end");
    double pitchAt(double second) {
      var from = (second * 48000).round();
      return detectPitch(Float32List.sublistView(sung, from, from + 2048))!.hz;
    }

    expect(pitchAt(0.3), closeTo(220, 4), reason: "A3");
    expect(pitchAt(1.1), closeTo(329.6, 6), reason: "E4");
    var peak = sung.map((v) => v.abs()).reduce(math.max);
    expect(peak, lessThan(1.2), reason: "about as loud as it was spoken");
    expect(peak, greaterThan(0.2));
  });

  group("on a channel", () {
    late Future<Float32List?> Function(String) audioWas;
    late Future<String?> Function(String) storeWas;
    setUp(() {
      audioWas = CanvasController.takeAudio;
      storeWas = CanvasController.speechStore;
      CanvasController.takeAudio = (id) async => voice(150, 1.0);
      CanvasController.speechStore = (file) async => "sung.wav";
    });
    tearDown(() {
      CanvasController.takeAudio = audioWas;
      CanvasController.speechStore = storeWas;
    });

    CanvasController make({bool take = true}) => CanvasController(
        CanvasDocument(frames: 400, frameRate: 25, elements: [
          AudioElement(const ElementBase(id: "a", name: "Singer"),
              clip: MediaClip(
                  playlist: const [MediaSource(assetId: "t", length: 1)],
                  timed: true,
                  mix: ChannelMix(
                      speech: SpeechSpec(script: "la la", takes: [
                        if (take)
                          const SpeechTake("take.wav", 1, [
                            (text: "la", start: 0.1, end: 0.4),
                            (text: "la", start: 0.5, end: 0.9),
                          ]),
                      ]),
                      vocaliser: const VocaliserSpec(vibrato: 0)))),
          // The tune: a part starting at two seconds.
          AudioElement(const ElementBase(id: "keys", name: "Tune"),
              clip: const MediaClip(timed: true, at: 50),
              instrument: const InstrumentPart(notes: [
                MidiNote(60, 0.5, 0.5),
                MidiNote(62, 1.0, 0.5),
              ])),
        ]),
        audioEngine: FakeEngine({"t": 1}));

    test("Sing lays the sung take on the channel, where the tune starts",
        () async {
      var c = make();
      addTearDown(c.dispose);
      var before = c.document.elements.length;
      expect(await c.sing("a"), isNull);
      var added = c.document.elements.last as AudioElement;
      expect(c.document.elements, hasLength(before + 1));
      expect(added.clip.channel, "a");
      expect(added.clip.at, 50 + 13,
          reason: "two seconds and the first "
              "note's half second in, at twenty-five frames a second");
      expect(added.clip.playlist.single.name, "Sung take 1");
      expect(added.clip.playlist.single.length, closeTo(1.0, 0.01));
      c.undo();
      expect(c.document.elements, hasLength(before));
    });

    test("with nothing spoken, or nothing to sing to, it says so", () async {
      var c = make(take: false);
      addTearDown(c.dispose);
      expect(await c.sing("a"), contains("speak a take"));
      var d = make();
      addTearDown(d.dispose);
      d.setVocaliser("a", const VocaliserSpec(melody: "nobody"));
      expect(await d.sing("a"), contains("pick a MIDI channel"));
    });

    testWidgets("added from the effects, sung from, and on the strip",
        (tester) async {
      var c = make();
      c.setVocaliser("a", null);
      c.openEffects("a");
      tester.view.physicalSize = const Size(1600, 900);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 380,
                                  onResize: (_) {},
                                  onClose: () {}),
                              CanvasMixer(
                                  controller: c,
                                  height: 420,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("addDevice-vocaliser")));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.vocaliserOf("a"), isNotNull);
      expect(find.byKey(const ValueKey("device-vocaliser")), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("device-vocaliser")),
              matching: find.text("Tune")),
          findsOneWidget,
          reason: "the MIDI channel");
      await tester.tap(find.byKey(const ValueKey("vocaliserSing")));
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (!c.singing.contains("a")) break;
      }
      expect(
          c.document.elements
              .whereType<AudioElement>()
              .any((e) => e.clip.playlist.any((s) => s.name == "Sung take 1")),
          isTrue);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("strip-a")),
              matching: find.byKey(const ValueKey("vocaliserSlot"))),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

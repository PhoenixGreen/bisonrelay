import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/phrasing.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/phrasing_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_phrasing_test.dart is the Phrasing panel: a take's words read --
// their pitch and loudness -- and shaped after it is spoken, a word at a
// time, and the panel that does it.

const _rate = 48000.0;

/// _voice is a voice saying [words] -- a buzz through a mouth's resonance,
/// at [hz] or, given, gliding from [hz] to [to] over each word -- silent
/// between them: [seconds] long.
Float32List _voice(List<TimedWord> words, double seconds,
    {double hz = 150, double? to}) {
  var out = Float32List((seconds * _rate).round());
  for (var w in words) {
    var phase = 0.0;
    var from = (w.start * _rate).round(), end = (w.end * _rate).round();
    double y1 = 0, y2 = 0;
    for (var i = from; i < end && i < out.length; i++) {
      var u = (i - from) / (end - from);
      var f = to == null ? hz : hz * math.pow(to / hz, u);
      phase += f / _rate;
      var pulse = phase >= 1 ? 1.0 : 0.0;
      if (phase >= 1) phase -= 1;
      // A resonance at 700Hz: an "ah".
      const r = 0.97, theta = 2 * math.pi * 700 / _rate;
      var y = pulse + 2 * r * math.cos(theta) * y1 - r * r * y2;
      y2 = y1;
      y1 = y;
      out[i] = 0.02 * y;
    }
  }
  return out;
}

double _rms(Float32List x, double from, double to) {
  var a = (from * _rate).round(), b = (to * _rate).round();
  var sum = 0.0;
  for (var i = a; i < b; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (b - a));
}

/// _pitchAt is what YIN hears of [x] round [t] seconds, as a MIDI note.
double _pitchAt(Float32List x, double t) {
  var at = (t * _rate).round();
  var p = detectPitch(Float32List.sublistView(x, at - 1024, at + 1024),
      rate: _rate, minHz: 60, maxHz: 600);
  return midiOf(p!.hz);
}

const _words = <TimedWord>[
  (text: "one", start: 0.2, end: 0.7),
  (text: "two", start: 0.9, end: 1.4),
  (text: "three.", start: 1.6, end: 2.1),
];

void main() {
  group("a take", () {
    test("read: each word's pitch, its loudness, the voice's middle", () {
      var pcm = _voice(_words, 2.4);
      var reading = readTake(pcm, _words);
      expect(reading.middle, closeTo(midiOf(150), 0.5));
      for (var w in _words) {
        expect(reading.meanOf(w), closeTo(midiOf(150), 0.5));
      }
      expect(reading.pitch[(0.8 / TakeReading.frame).round()], isNull,
          reason: "silent between the words");
      expect(reading.levels, hasLength(3));
      expect(reading.levels.first, greaterThan(-40));
    });

    test("left as it was, it is as it was", () {
      var pcm = _voice(_words, 2.4);
      var made = shapeTake(pcm, _words, const [], readTake(pcm, _words));
      expect(made.sound.length, pcm.length);
      for (var i = 2000; i < pcm.length - 2000; i++) {
        expect(made.sound[i], closeTo(pcm[i], 1e-5));
      }
      expect(made.words, _words);
    });

    test("a word moved in pitch, drawn out, a pause after, made quieter", () {
      var pcm = _voice(_words, 2.4);
      var reading = readTake(pcm, _words);
      var shapes = const [
        WordShape(length: 1.4),
        WordShape(pitch: 3, pause: 0.3),
        WordShape(loudness: -6),
      ];
      var made = shapeTake(pcm, _words, shapes, reading);
      // Longer by the first word's 0.2 s and the pause's 0.3.
      expect(made.sound.length / _rate, closeTo(2.4 + 0.2 + 0.3, 1e-3));
      var two = made.words[1], three = made.words[2];
      expect(made.words.first.end, closeTo(0.9, 1e-3));
      expect(two.start, closeTo(1.1, 1e-3));
      // Its pitch three semitones up; the words either side as they were.
      expect(_pitchAt(made.sound, (two.start + two.end) / 2),
          closeTo(midiOf(150) + 3, 0.4));
      expect(_pitchAt(made.sound, 0.55), closeTo(midiOf(150), 0.3));
      expect(_pitchAt(made.sound, (three.start + three.end) / 2),
          closeTo(midiOf(150), 0.3));
      // Silence after it, as long as asked.
      expect(_rms(made.sound, two.end + 0.03, two.end + 0.27), lessThan(1e-4));
      // Half as loud.
      expect(
          _rms(made.sound, three.start + 0.05, three.end - 0.05) /
              _rms(pcm, 1.65, 2.05),
          closeTo(0.5, 0.03));
    });

    test("its rise and fall made more of, or flattened", () {
      // Each word rises a fifth through it.
      var pcm = _voice(_words, 2.4, hz: 120, to: 180);
      var reading = readTake(pcm, _words);
      double spread(List<WordShape> shapes) {
        var made = shapeTake(pcm, _words, shapes, reading);
        var w = made.words[1];
        var span = w.end - w.start;
        return _pitchAt(made.sound, w.end - span * 0.2) -
            _pitchAt(made.sound, w.start + span * 0.2);
      }

      var asSaid = spread(const []);
      expect(asSaid, greaterThan(3));
      expect(spread(const [WordShape.plain, WordShape(inflection: 0)]),
          lessThan(1),
          reason: "flat");
      expect(spread(const [WordShape.plain, WordShape(inflection: 1.5)]),
          closeTo(asSaid * 1.5, 1));
    });
  });

  group("a word's shape", () {
    test("kept within what still sounds like the voice", () {
      var shape = const WordShape().copyWith(
          pitch: 9, length: 2, inflection: 3, pause: 2, loudness: -40);
      expect(shape.pitch, 6);
      expect(shape.length, 1.4);
      expect(shape.inflection, 2);
      expect(shape.pause, 0.8);
      expect(shape.loudness, -12);
      var stressed = WordShape.plain.stressed;
      expect(stressed.pitch, 1.5);
      expect(stressed.length, closeTo(1.1, 1e-9));
      expect(stressed.loudness, 3);
      expect(WordShape.fromJson(shape.toJson()), shape);
    });

    test("kept with its take, which keeps the take as spoken", () {
      var spoken = SpeechTake("a.wav", 2.4, _words);
      var shaped = spoken.withShapes(const [WordShape(pitch: 2)]);
      expect(shaped.shapes, hasLength(3), reason: "one a word");
      expect(shaped.needsShaping, isTrue);
      expect(shaped.assetId, "a.wav", reason: "its sound as it was, for now");
      var made = shaped.madeAs("b.wav", 2.4, _words);
      expect(made.needsShaping, isFalse);
      expect(made.ids, {"b.wav", "a.wav"});
      var back = SpeechTake.fromJson(made.toJson())!;
      expect(back.asSpoken.assetId, "a.wav");
      expect(back.shapeOf(0), const WordShape(pitch: 2));
      expect(back.needsShaping, isFalse);
      // Every word as said again: the take as spoken.
      var reset = made.withShapes(const []);
      expect(reset.shaped, isFalse);
      expect(reset.madeAs("x", 0, const []).assetId, "a.wav");
    });
  });

  group("on a channel", () {
    late Future<Float32List?> Function(String) audioWas;
    late Future<String?> Function(Uint8List) storeWas;
    late Future<String?> Function(String) pathWas;
    late FakeEngine engine;
    var sounds = <String, Float32List>{};

    setUp(() {
      audioWas = CanvasController.takeAudio;
      storeWas = CanvasController.speechTakeStore;
      pathWas = CanvasController.takePath;
      sounds = {"spoken.wav": _voice(_words, 2.4)};
      CanvasController.takeAudio = (id) async => sounds[id];
      var made = 0;
      CanvasController.speechTakeStore = (wav) async {
        var id = "shaped${++made}.wav";
        // Its sound, read back as it would be: 16-bit stereo at 48kHz.
        var b = ByteData.sublistView(wav);
        var n = (wav.length - 44) ~/ 4;
        sounds[id] = Float32List.fromList([
          for (var i = 0; i < n; i++)
            b.getInt16(44 + i * 4, Endian.little) / 32768
        ]);
        return id;
      };
    });

    tearDown(() {
      CanvasController.takeAudio = audioWas;
      CanvasController.speechTakeStore = storeWas;
      CanvasController.takePath = pathWas;
    });

    CanvasController make() {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 25, elements: [
            AudioElement(const ElementBase(id: "a", name: "Narrator"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]),
          audioEngine: engine = FakeEngine({"t": 2, "spoken.wav": 2.4}));
      c.setSpeech(
          "a",
          SpeechSpec(voice: "v1", script: "one two three.", lines: [
            const SpeechLine("one two three.")
                .withSlot(0, const SpeechTake("spoken.wav", 2.4, _words)),
          ]));
      return c;
    }

    test("shaped, made again, undone, and reset", () async {
      var c = make();
      addTearDown(c.dispose);
      c.openPhrasing("a", 0, 0);
      expect(c.phrasing, (channel: "a", line: 0, slot: 0));
      // Read in the background.
      for (var i = 0; i < 50 && c.readingOf(c.phrasingTake!) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.readingOf(c.phrasingTake!), isNotNull);
      c.shapeWord(1, const WordShape(pitch: 3));
      expect(c.phrasingTake!.shapeOf(1).pitch, 3);
      expect(c.phrasingTake!.needsShaping, isTrue);
      var made = await c.shapedTake("a", 0, 0);
      expect(made!.assetId, startsWith("shaped"));
      expect(made.needsShaping, isFalse);
      expect(made.asSpoken.assetId, "spoken.wav");
      var two = made.words[1];
      expect(_pitchAt(sounds[made.assetId]!, (two.start + two.end) / 2),
          closeTo(midiOf(150) + 3, 0.5));
      // Kept with the canvas: the shaped take and the take as spoken.
      expect(c.document.mediaIds, containsAll(["spoken.wav", made.assetId]));
      // Undone: its shape as it was -- and its sound made again when it
      // is asked for.
      c.undo();
      expect(c.phrasingTake!.shaped, isFalse);
      expect((await c.shapedTake("a", 0, 0))!.assetId, "spoken.wav");
      c.redo();
      c.resetPhrasing();
      expect(c.phrasingTake!.shaped, isFalse);
      expect((await c.shapedTake("a", 0, 0))!.assetId, "spoken.wav");
      c.closePhrasing();
      expect(c.phrasing, isNull);
    });

    for (var scale in [1.0, 1.25, 1.5]) {
      testWidgets(
          "in the device: picked, dragged, zoomed, heard -- at ${scale}x",
          (tester) async {
        var c = make();
        CanvasController.takePath = (id) async => "/kept/$id";
        c.openEffects("a");
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
          ],
          child: MaterialApp(
              home: MediaQuery(
            data: MediaQueryData(
                size: const Size(1600, 900),
                textScaler: TextScaler.linear(scale)),
            child: Scaffold(
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
                            ]))),
          )),
        ));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Phrasing, from the header: in place of the sections.
        expect(find.byKey(const ValueKey("speechLine-0")), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("speechPhrasing")));
        await tester.pump();
        expect(c.phrasing, (channel: "a", line: 0, slot: 0));
        for (var i = 0; i < 40 && c.readingOf(c.phrasingTake!) == null; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey("speechLine-0")), findsNothing);
        expect(find.byType(PhrasingLanes), findsOneWidget);
        expect(find.byType(PhrasingWordPanel), findsOneWidget);
        expect(find.byKey(const ValueKey("speechHear")), findsOneWidget,
            reason: "the section's slots and Hear still in view");
        expect(tester.takeException(), isNull, reason: "nothing overflows");
        Finder word(int i) => find.byKey(ValueKey("phrasingWord-$i"));
        // A word picked, then dragged up: its pitch, by the half semitone.
        await tester.tap(word(1));
        await tester.pump();
        expect(c.phrasingPicked, {1});
        await tester.drag(word(1), const Offset(0, -40));
        await tester.pump();
        var up = c.phrasingTake!.shapeOf(1).pitch;
        expect(up, greaterThan(0));
        expect((up * 2) % 1, 0, reason: "by the half semitone");
        c.undo();
        expect(c.phrasingTake!.shapeOf(1).pitch, 0, reason: "one undo");
        // Shift-clicked, another word with it: dragged together.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(word(2));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(c.phrasingPicked, {2, 1});
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey("phrasingPicked")))
                .data,
            "2 words");
        await tester.drag(word(1), const Offset(0, -40));
        await tester.pump();
        expect(
            c.phrasingTake!.shapeOf(2).pitch, c.phrasingTake!.shapeOf(1).pitch);
        expect(c.phrasingTake!.shapeOf(2).pitch, greaterThan(0));
        expect(c.phrasingTake!.shapeOf(0).pitch, 0);
        // Stressed together, and reset together.
        await tester
            .ensureVisible(find.byKey(const ValueKey("phrasingStress")));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("phrasingStress")));
        await tester.pump();
        expect(c.phrasingTake!.shapeOf(1).loudness, 3);
        expect(c.phrasingTake!.shapeOf(2).loudness, 3);
        await tester.tap(find.byKey(const ValueKey("phrasingResetWord")));
        await tester.pump();
        expect(c.phrasingTake!.shaped, isFalse);
        // A box dragged round the first two words picks them.
        await tester.ensureVisible(word(0));
        await tester.pump();
        var a = tester.getTopLeft(word(0)) + const Offset(2, -6);
        var b = tester.getBottomRight(word(1)) + const Offset(2, 2);
        await tester.dragFrom(a, b - a, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(c.phrasingPicked, {0, 1});
        // Zoomed in on the time, a word is wider; on the pitch, further
        // from a word a semitone off.
        c.shapeWords({2: const WordShape(pitch: 3)});
        await tester
            .ensureVisible(find.byKey(const ValueKey("phrasingTimeIn")));
        await tester.pump();
        var wide = tester.getSize(word(1)).width;
        double apart() =>
            tester.getTopLeft(word(1)).dy - tester.getTopLeft(word(2)).dy;
        var was = apart();
        await tester.tap(find.byKey(const ValueKey("phrasingTimeIn")));
        await tester.pump();
        await tester.pump();
        expect(tester.getSize(word(1)).width, greaterThan(wide * 1.3));
        await tester.tap(find.byKey(const ValueKey("phrasingPitchIn")));
        await tester.pump();
        await tester.pump();
        expect(apart(), greaterThan(was * 1.3));
        await tester.tap(find.byKey(const ValueKey("phrasingFit")));
        await tester.pump();
        // The playhead put on the ruler, and heard from there.
        var ruler = tester.getRect(find.byKey(const ValueKey("phrasingRuler")));
        var x1 = tester.getCenter(word(1)).dx;
        await tester.tapAt(Offset(x1, ruler.center.dy));
        await tester.pump();
        expect(
            tester.getCenter(find.byKey(const ValueKey("phrasingPlayhead"))).dx,
            closeTo(x1, 4));
        await tester.runAsync(() async {
          await c.hearSlot("a", 0, 0, spoken: true);
          c.stopHearing();
        });
        await tester.tap(find.byKey(const ValueKey("phrasingHearSpoken")));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        var at = engine.voices.last.at;
        expect(at, closeTo((_words[1].start + _words[1].end) / 2, 0.05),
            reason: "from the playhead, the middle of the second word");
        c.stopHearing();
        // Back to the sections.
        await tester.tap(find.byKey(const ValueKey("speechPhrasing")));
        await tester.pump();
        expect(c.phrasing, isNull);
        expect(find.byKey(const ValueKey("speechLine-0")), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
    }
  });
}

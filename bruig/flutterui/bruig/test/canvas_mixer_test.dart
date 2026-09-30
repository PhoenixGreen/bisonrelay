import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_video_element_test.dart' show FakeFrames;

// canvas_mixer_test.dart is the mixer: that its settings mean the same thing
// in the editor and in an export, that the runtime routes each sound through
// its strip, and the panel that sets them.

/// soloudResponseDb is what SoLoud's band EQ does at [f] given [gains] at its
/// band centres -- its own blend (see soloudBlend), so the curve it is handed
/// can be checked against the curve an export applies.
double soloudResponseDb(List<double> gains, double f) {
  var w = soloudBlend(f, eqBandCentres(gains.length));
  var g = 0.0;
  for (var i = 0; i < gains.length; i++) {
    g += gains[i] * w[i];
  }
  return 20 * math.log(g) / math.ln10;
}

const song = "aaaaaaaaaaaaaaaa.mp3";

void main() {
  group("the EQ means one thing", () {
    test("flat is flat, and off is off", () {
      expect(const Eq(on: true).responseDb(1000), closeTo(0, 1e-9));
      expect(const Eq(mid: EqBand(1000, gainDb: 6)).responseDb(1000), 0,
          reason: "switched off");
    });

    test("each band does what it says where it says", () {
      const eq = Eq(
          on: true,
          low: EqBand(100, gainDb: 6),
          mid: EqBand(2000, gainDb: -4, q: 1),
          high: EqBand(10000, gainDb: 3));
      expect(eq.responseDb(20), closeTo(6, 0.5), reason: "under the shelf");
      expect(eq.responseDb(2000), closeTo(-4, 0.3),
          reason: "the bell's centre");
      expect(eq.responseDb(20000), closeTo(3, 0.5), reason: "over the shelf");
      expect(eq.responseDb(500), closeTo(0, 0.8), reason: "between them");
    });

    // The claim the whole mixer rests on: the editor sounds like the export.
    // The export runs these biquads; the editor runs SoLoud's EQ, which is a
    // row of sixty-four flat bands, given the gains that fit this curve best.
    // At the farthest the editor's controls go -- twelve decibels either way,
    // on any band -- the two stay within about a decibel of each other. (A
    // notch narrower than the editor can make would miss by more: the bands
    // are a tenth of an octave wide, and that is SoLoud's own limit.)
    test("the editor's bands follow the export's curve to about a decibel", () {
      for (var eq in const [
        Eq(on: true, mid: EqBand(1000, gainDb: 12, q: 1)),
        Eq(on: true, mid: EqBand(3000, gainDb: -12, q: 1)),
        Eq(on: true, mid: EqBand(8000, gainDb: -12, q: 1)),
        Eq(
            on: true,
            low: EqBand(60, gainDb: 12),
            high: EqBand(12000, gainDb: -12)),
        Eq(
            on: true,
            low: EqBand(300, gainDb: -12),
            mid: EqBand(2500, gainDb: 12),
            high: EqBand(6000, gainDb: 12)),
      ]) {
        var gains = eqBandGains(eq);
        var worst = 0.0;
        for (var i = 0; i <= 400; i++) {
          var f = 40 * math.pow(15000 / 40, i / 400).toDouble();
          worst = math.max(
              worst, (soloudResponseDb(gains, f) - eq.responseDb(f)).abs());
        }
        expect(worst, lessThan(1.1), reason: "${eq.toJson()}");
      }
    });

    test("fitted, not sampled: better than the curve at the centres", () {
      const eq = Eq(on: true, mid: EqBand(3000, gainDb: -12, q: 1));
      double worstOf(List<double> gains) {
        var worst = 0.0;
        for (var i = 0; i <= 400; i++) {
          var f = 40 * math.pow(15000 / 40, i / 400).toDouble();
          worst = math.max(
              worst, (soloudResponseDb(gains, f) - eq.responseDb(f)).abs());
        }
        return worst;
      }

      var sampled = [
        for (var f in eqBandCentres(soloudBands))
          math.pow(10, eq.responseDb(f) / 20).toDouble()
      ];
      expect(worstOf(eqBandGains(eq)), lessThan(worstOf(sampled)));
    });

    test("and is written for ffmpeg as the same three filters", () {
      var args = eqFfmpeg(const Eq(
          on: true,
          low: EqBand(120, gainDb: -3),
          mid: EqBand(1000, gainDb: 2, q: 1.5)));
      expect(args, [
        "lowshelf=f=120.000:t=q:w=0.707:g=-3.000",
        "equalizer=f=1000.000:t=q:w=1.500:g=2.000",
      ]);
    });
  });

  group("a strip", () {
    test("balance takes from the side it turns away from, never adds", () {
      expect(const ChannelMix().gains, (1, 1));
      var (l, r) = const ChannelMix(balance: 0.5).gains;
      expect([l, r], [0.5, 1]);
      (l, r) = const ChannelMix(balance: -1, gainDb: -6).gains;
      expect(l, closeTo(0.501, 0.001));
      expect(r, 0);
    });

    test("writes an export chain in the editor's order", () {
      var chain = const ChannelMix(
              gainDb: -6,
              balance: -0.25,
              eq: Eq(on: true, mid: EqBand(1000, gainDb: 3)),
              comp: Dynamics(on: true))
          .ffmpeg;
      expect(chain[0], startsWith("equalizer"));
      expect(chain[1], startsWith("acompressor"));
      expect(chain[2], startsWith("pan=stereo|c0="));
    });

    test("the master brings to the target before the limiter", () {
      var chain = const MasterMix(normalise: true, target: -14).ffmpeg;
      var norm = chain.indexWhere((f) => f.startsWith("loudnorm=I=-14"));
      var limit = chain.indexWhere((f) => f.startsWith("alimiter"));
      expect(norm, greaterThanOrEqualTo(0));
      expect(limit, greaterThan(norm),
          reason: "nothing after the limiter may take a peak back over it");
    });

    test("reads back what it wrote, and writes nothing untouched", () {
      var mix = const ChannelMix(
          gainDb: -3,
          balance: 0.2,
          mute: true,
          eq: Eq(on: true, high: EqBand(9000, gainDb: 2)),
          comp: Dynamics(on: true, ratio: 4));
      var back = ChannelMix.fromJson(mix.toJson());
      expect(back.gainDb, -3);
      expect(back.balance, 0.2);
      expect(back.mute, isTrue);
      expect(back.eq.high.gainDb, 2);
      expect(back.comp.ratio, 4);
      expect(const MediaClip().toJson(), isEmpty);
      var doc = CanvasDocument.decode(
          const CanvasDocument(masterMix: MasterMix(target: -23)).encode())!;
      expect(doc.masterMix.target, -23);
    });
  });

  group("the runtime", () {
    late FakeEngine engine;
    late AudioRuntime runtime;

    setUp(() {
      engine = FakeEngine({song: 10});
      runtime = AudioRuntime(engine: engine, locate: (id) async => id);
    });
    tearDown(() => runtime.dispose());

    AudioElement sound(String id) => AudioElement(ElementBase(id: id),
        clip: const MediaClip(playlist: [MediaSource(assetId: song)]));

    // A sound on the timeline is as loud as its clip says, when the clip's
    // volume line is moved while it plays -- and past full, to six decibels.
    test("a timeline sound follows its clip's volume as it changes", () async {
      AudioElement timed(double volume) => AudioElement(
          const ElementBase(id: "t", visible: false),
          clip: MediaClip(
              timed: true,
              volume: volume,
              playlist: const [MediaSource(assetId: song)]));
      runtime.cue(timed(1), const ClipMoment(0, 0, 1), playing: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(engine.voices, isNotEmpty);
      runtime.cue(timed(1.8), const ClipMoment(0, 0, 1), playing: true);
      expect(engine.last.volume, closeTo(1.8, 1e-9));
      runtime.cue(timed(0.3), const ClipMoment(0, 0, 1), playing: true);
      expect(engine.last.volume, closeTo(0.3, 1e-9));
    });

    test("plays each sound through its own strip", () async {
      runtime.setMix(const {"a": ChannelMix(balance: 1)},
          master: const MasterMix());
      await runtime.play(sound("a"));
      await runtime.play(sound("b"));
      expect(engine.onChannel[engine.voices[0]], "a");
      expect(engine.onChannel[engine.voices[1]], isNull,
          reason: "no strip, straight to the master");
      expect(engine.channels["a"]!.left, 0);
      expect(engine.channels["a"]!.right, 1);
    });

    test("a video's sound goes through its video's strip", () async {
      runtime.setMix(const {"v": ChannelMix()}, master: const MasterMix());
      await runtime.play(sound("video:v"));
      expect(engine.onChannel[engine.voices.single], "v");
    });

    test("solo silences every strip but the soloed", () async {
      await runtime.play(sound("a"));
      runtime.setMix(const {"a": ChannelMix(), "b": ChannelMix()},
          solo: {"b"}, master: const MasterMix());
      expect(engine.channels["a"]!.left, 0);
      expect(engine.channels["b"]!.left, 1);
    });

    test("the master's EQ, glue and limiter reach the engine", () async {
      runtime.setMix(const {},
          master: MasterMix(
              gainDb: -6,
              eq: const Eq(on: true, low: EqBand(100, gainDb: 3)),
              comp: const MasterMix().comp.copyWith(on: true)));
      await runtime.play(sound("a"));
      var master = engine.master!;
      expect(master.volume, closeTo(0.501, 0.001));
      expect(master.eq, hasLength(soloudBands));
      expect(master.comp, isNotNull);
      expect(master.ceilingDb, -1);
    });

    test("the same mix set again is not sent again", () async {
      await runtime.play(sound("a"));
      runtime.setMix(const {"a": ChannelMix()}, master: const MasterMix());
      var first = engine.channels["a"];
      engine.channels.clear();
      runtime.setMix(const {"a": ChannelMix()}, master: const MasterMix());
      expect(first, isNotNull);
      expect(engine.channels, isEmpty);
    });
  });

  group("an export", () {
    test("each stretch through its strip, the sum through the master", () {
      var (_, graph) = mixArgs(const [
        ExportSound(
            path: "/a.flac",
            at: 0,
            from: 0,
            length: 2,
            mix: ChannelMix(gainDb: -6, comp: Dynamics(on: true))),
      ], master: const MasterMix(normalise: true));
      expect(graph, contains("acompressor"));
      expect(graph, contains("pan=stereo"));
      expect(graph, contains("loudnorm=I=-16"));
      expect(graph, contains("aresample=48000,apad[mix]"));
    });

    test("a muted strip is not in it at all", () async {
      var doc = CanvasDocument(frameRate: 25, frames: 50, elements: [
        VideoElement(const ElementBase(id: "v"),
            clip: const MediaClip(playlist: [
              MediaSource(assetId: "x", soundId: "s", length: 2),
            ], timed: true, mix: ChannelMix(mute: true))),
      ]);
      var media = ExportMedia.of(doc,
          frames: FakeFrames(2), locate: (kind, id) async => "/$id")!;
      expect(await media.sounds(), isEmpty);
      media.dispose();
    });

    test("ffmpeg's loudness summary is read", () {
      var m = parseLoudness('''
[Parsed_ebur128_0 @ 0x1] Summary:

  Integrated loudness:
    I:         -16.3 LUFS
    Threshold: -26.5 LUFS

  Loudness range:
    LRA:         2.1 LU
    Threshold: -36.4 LUFS
    LRA low:   -17.2 LUFS
    LRA high:  -15.1 LUFS

  True peak:
    Peak:       -1.2 dBFS
''')!;
      expect(m.integrated, -16.3);
      expect(m.range, 2.1);
      expect(m.truePeak, -1.2);
    });

    // The real thing: a tone, mixed, brought to a target and measured. What
    // Measure shows is what an export will be.
    test("brought to the target, it measures at the target", () async {
      var ffmpeg = await ffmpegPath();
      if (ffmpeg == null) return markTestSkipped("ffmpeg is not installed");
      var root = await Directory.systemTemp.createTemp("canvas_mixer_test");
      CanvasStorage.rootOverride = root.path;
      addTearDown(() async {
        CanvasStorage.rootOverride = null;
        await root.delete(recursive: true);
      });
      var tone = path.join(root.path, "tone.flac");
      await Process.run(ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
        "-t", "6", "-af", "volume=0.1", tone,
      ]);
      var id = (await CanvasMedia.saveFile(MediaKind.audio, tone))!;
      CanvasDocument doc(MasterMix master) => CanvasDocument(
            frameRate: 25,
            frames: 150,
            masterMix: master,
            background: CanvasBackground(
                sound: AudioElement(const ElementBase(id: "bed"),
                    clip: MediaClip(
                        playlist: [MediaSource(assetId: id, length: 6)],
                        timed: true))),
          );
      var quiet = await measureMix(doc(const MasterMix()));
      expect(quiet, isNotNull);
      expect(quiet!.integrated, lessThan(-20), reason: "a quiet tone");
      var brought = (await measureMix(
          doc(const MasterMix(normalise: true, target: -16))))!;
      expect(brought.integrated, closeTo(-16, 1));
      expect(brought.truePeak, lessThanOrEqualTo(-0.9),
          reason: "and the limiter held the ceiling");
    });
  });

  group("the panel", () {
    late FakeEngine engine;

    setUp(() => engine = FakeEngine({song: 10}));

    VideoElement timed(String id, String name) =>
        VideoElement(ElementBase(id: id, name: name),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: "x", length: 4)], timed: true));

    Future<CanvasController> show(WidgetTester tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 25, elements: [
            timed("v", "Speaker"),
            timed("w", "Backdrop"),
          ]),
          audioEngine: engine,
          frameSource: FakeFrames(4));
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
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
                    child: CanvasMixer(
                        controller: c,
                        height: 380,
                        onResize: (_) {},
                        onClose: () {})))),
      ));
      await tester.pump();
      return c;
    }

    Future<void> done(WidgetTester tester, CanvasController c) async {
      // The fader and the curve take a double-click, so a press on either
      // leaves the double-tap recogniser waiting for a second one.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    testWidgets("a strip for each sound on the timeline, and the master",
        (tester) async {
      var c = await show(tester);
      expect(find.byKey(const ValueKey("strip-v")), findsOneWidget);
      expect(find.byKey(const ValueKey("strip-w")), findsOneWidget);
      expect(find.byKey(const ValueKey("strip-master")), findsOneWidget);
      expect(find.text("Speaker"), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("the fader sets the level, in one undo step", (tester) async {
      var c = await show(tester);
      var fader = find.descendant(
          of: find.byKey(const ValueKey("strip-v")),
          matching: find.byKey(const ValueKey("fader")));
      await tester.drag(fader, const Offset(0, 60));
      await tester.pump();
      var db = (c.document.elements.first as VideoElement).clip.mix.gainDb;
      expect(db, lessThan(0), reason: "dragged down, turned down");
      c.undo();
      expect((c.document.elements.first as VideoElement).clip.mix.gainDb, 0);
      await done(tester, c);
    });

    // The reading under a fader is clicked and typed into, for a level to
    // the tenth of a decibel -- which a fader dragged by hand cannot hit.
    testWidgets("the level under a fader takes a typed value", (tester) async {
      var c = await show(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey("strip-v")),
          matching: find.byKey(const ValueKey("faderReading"))));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey("dbEntry")), "−6.5 dB");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((c.document.elements.first as VideoElement).clip.mix.gainDb, -6.5);
      c.undo();
      expect((c.document.elements.first as VideoElement).clip.mix.gainDb, 0,
          reason: "one undo step");

      await tester.tap(find.byKey(const ValueKey("masterReading")));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey("dbEntry")), "-3");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(c.document.masterMix.gainDb, -3);
      await done(tester, c);
    });

    testWidgets("the knob beside the pan control says Pan", (tester) async {
      var c = await show(tester);
      expect(find.text("Pan"), findsWidgets);
      expect(find.text("Bal"), findsNothing);
      await done(tester, c);
    });

    testWidgets("mute is saved, solo is not", (tester) async {
      var c = await show(tester);
      var strip = find.byKey(const ValueKey("strip-v"));
      await tester.tap(find.descendant(
          of: strip, matching: find.byKey(const ValueKey("mute"))));
      await tester.pump();
      expect((c.document.elements.first as VideoElement).clip.mix.mute, isTrue);

      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey("strip-w")),
          matching: find.byKey(const ValueKey("solo"))));
      await tester.pump();
      expect(c.solo, {"w"});
      expect(c.document.encode(), isNot(contains("solo")));
      await done(tester, c);
    });

    testWidgets("the EQ opens, and a point dragged lifts the curve",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey("strip-v")),
          matching: find.byKey(const ValueKey("eqSlot"))));
      await tester.pump();
      var curve = find.byKey(const ValueKey("eqCurve"));
      expect(curve, findsOneWidget);
      var box = tester.getRect(curve);
      // The bell starts at 1 kHz, on the flat line: log-spaced 20 Hz..20 kHz.
      var x = box.left + math.log(1000 / 20) / math.log(1000) * box.width;
      await tester.dragFrom(Offset(x, box.center.dy), const Offset(0, -60));
      await tester.pump();
      var eq = (c.document.elements.first as VideoElement).clip.mix.eq;
      expect(eq.on, isTrue, reason: "moving a point switches it on");
      expect(eq.mid.gainDb, greaterThan(2));
      await tester.tap(find.byKey(const ValueKey("mixerBack")));
      await tester.pump();
      expect(find.byKey(const ValueKey("strip-v")), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("the master's target and normalising are the document's",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.byKey(const ValueKey("normalise")));
      await tester.pump();
      expect(c.document.masterMix.normalise, isTrue);
      expect(find.byKey(const ValueKey("measure")), findsOneWidget);
      await done(tester, c);
    });
  });
}

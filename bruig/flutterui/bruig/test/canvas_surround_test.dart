import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/audio_export.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'canvas_audio_fake.dart';

// canvas_surround_test.dart is where a sound is heard from: the speakers a
// piece is mixed for, a channel's place among them, a sound placed by the
// picture -- and the files written, read back.

const _l = 0, _r = 1, _c = 2, _lfe = 3, _ls = 4, _rs = 5;

double _rms(Float32List x, [int? n]) {
  var count = n ?? x.length;
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / count);
}

Float32List _tone(int n, double hz, [double level = 0.5]) => Float32List.fromList(
    [for (var i = 0; i < n; i++) level * math.sin(2 * math.pi * hz * i / mixRate)]);

/// _through runs a 1kHz tone (or [hz]) on one channel with [mix] through a
/// graph for [layout], and returns each speaker's level and the fold-down.
(List<double>, double, double) _through(SpeakerLayout layout, ChannelMix mix,
    {Heard? placed, double hz = 1000, int blocks = 8}) {
  var g = MixGraph()
    ..setSpeakers(layout)
    ..setMaster(const MasterMix(limiter: false))
    ..setChannel("a", mix);
  if (placed != null) g.setPlacement("a", placed);
  const n = 2048;
  var tone = _tone(n, hz);
  var l = Float32List(n), r = Float32List(n);
  var levels = <double>[];
  for (var b = 0; b < blocks; b++) {
    g.begin(n);
    var (il, ir) = g.input("a", n);
    il.setRange(0, n, tone);
    ir.setRange(0, n, tone);
    g.finish(l, r, n);
    if (b == blocks - 1) levels = [for (var s in g.speakers) _rms(s, n)];
  }
  return (levels, _rms(l), _rms(r));
}

void main() {
  group("panning", () {
    test("on a speaker, all of it there; between two, power shared", () {
      var at = panGains(SpeakerLayout.surround51, 110);
      expect(at[_rs], closeTo(1, 1e-9));
      expect(at.where((g) => g > 1e-9).length, 1);
      var half = panGains(SpeakerLayout.surround51, -15);
      expect(half[_l], closeTo(math.sqrt1_2, 1e-9));
      expect(half[_c], closeTo(math.sqrt1_2, 1e-9));
      for (var a = -180.0; a < 180; a += 7.5) {
        var g = panGains(SpeakerLayout.surround71, a);
        expect(g.fold<double>(0, (s, x) => s + x * x), closeTo(1, 1e-9),
            reason: "constant power at $a");
        expect(g[_lfe], 0, reason: "the LFE has no direction");
      }
    });

    test("stereo holds the front pair; behind is the same side", () {
      expect(panGains(SpeakerLayout.stereo, -90)[_l], closeTo(1, 1e-9));
      expect(panGains(SpeakerLayout.stereo, 150).toList(),
          panGains(SpeakerLayout.stereo, 30).toList());
      var mid = panGains(SpeakerLayout.stereo, 0);
      expect(mid[_l], closeTo(math.sqrt1_2, 1e-9));
    });

    test("the fold-down and the loudness weights are ITU's", () {
      var f = foldDown(SpeakerLayout.surround51);
      expect(f[_c].$1, closeTo(math.sqrt1_2, 1e-9));
      expect(f[_lfe], (0.0, 0.0));
      expect(f[_ls], (math.sqrt1_2, 0.0));
      expect(loudnessWeights(SpeakerLayout.surround51),
          [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]);
    });

    test("the settings are kept", () {
      const a = AudioSettings(speakers: SpeakerLayout.surround71);
      expect(AudioSettings.fromJson(a.toJson()).speakers,
          SpeakerLayout.surround71);
      var mix = const ChannelMix()
          .withSurround(const SurroundPan(angle: 120, width: 20))
          .withLfe(-6);
      var back = ChannelMix.fromJson(mix.toJson());
      expect((back.surround, back.lfeDb), (mix.surround, -6.0));
      expect(const ChannelMix().withLfe(-90).lfeDb, isNull);
      const place = SoundPlacement(by: PlaceBy.stage, stage: "s", x: 2);
      var clip = MediaClip.fromJson(const MediaClip(place: place).toJson());
      expect((clip.place.by, clip.place.stage, clip.place.x),
          (PlaceBy.stage, "s", 2.0));
    });
  });

  group("the graph", () {
    test("stereo is as it was: left to left, right to right", () {
      var (levels, l, r) = _through(SpeakerLayout.stereo, const ChannelMix());
      expect(levels.length, 2);
      expect(l, closeTo(0.5 / math.sqrt2, 0.01));
      expect(r, closeTo(l, 1e-6));
    });

    test("in surround, a channel with no place is the front pair", () {
      var (levels, _, _) =
          _through(SpeakerLayout.surround51, const ChannelMix());
      expect(levels[_l], closeTo(0.5 / math.sqrt2, 0.01));
      expect(levels[_r], closeTo(levels[_l], 1e-6));
      for (var c in [_c, _lfe, _ls, _rs]) {
        expect(levels[c], lessThan(1e-6), reason: "speaker $c");
      }
    });

    test("a channel turned to the back right is heard there", () {
      var (levels, l, r) = _through(
          SpeakerLayout.surround51,
          const ChannelMix()
              .withSurround(const SurroundPan(angle: 110, width: 0)));
      expect(levels[_rs], greaterThan(0.4));
      for (var c in [_l, _r, _c, _ls]) {
        expect(levels[c], lessThan(1e-6), reason: "speaker $c");
      }
      // Folded down, it is on the right, three decibels under.
      expect(l, lessThan(1e-6));
      expect(r, closeTo(levels[_rs] * math.sqrt1_2, 1e-3));
    });

    test("the LFE gets the lows of what is sent it, not the highs", () {
      var mix = const ChannelMix().withLfe(0);
      var (low, _, _) =
          _through(SpeakerLayout.surround51, mix, hz: 40);
      var (high, _, _) =
          _through(SpeakerLayout.surround51, mix, hz: 2000);
      expect(low[_lfe], greaterThan(0.3));
      expect(high[_lfe], lessThan(low[_lfe] * 0.05));
    });

    test("a placed sound is one point at its angle, as loud as it was", () {
      var (levels, _, _) = _through(
          SpeakerLayout.surround51, const ChannelMix(),
          placed: const Heard(-110));
      expect(levels[_ls], greaterThan(0.4));
      for (var c in [_l, _r, _c, _rs]) {
        expect(levels[c], lessThan(1e-6), reason: "speaker $c");
      }
      // In stereo, in the middle: each side as loud as the channel was.
      var (_, l, r) = _through(SpeakerLayout.stereo, const ChannelMix(),
          placed: const Heard(0));
      expect(l, closeTo(0.5 / math.sqrt2, 0.01));
      expect(r, closeTo(l, 1e-6));
      // Quieter for being further off.
      var (_, far, _) = _through(SpeakerLayout.stereo, const ChannelMix(),
          placed: const Heard(0, 0.5));
      expect(far, closeTo(l / 2, 0.005));
    });

    test("a sound moved glides there, with no step", () {
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setChannel("a", const ChannelMix())
        ..setPlacement("a", const Heard(-30));
      const n = 1024;
      var l = Float32List(n), r = Float32List(n);
      var ones = Float32List(n)..fillRange(0, n, 1);
      var got = <double>[];
      for (var b = 0; b < 2; b++) {
        if (b == 1) g.setPlacement("a", const Heard(30));
        g.begin(n);
        var (il, ir) = g.input("a", n);
        il.setRange(0, n, ones);
        ir.setRange(0, n, ones);
        g.finish(l, r, n);
        got.addAll(l);
      }
      var steps = [
        for (var i = 1; i < got.length; i++) (got[i] - got[i - 1]).abs()
      ];
      expect(steps.reduce(math.max), lessThan(0.01));
      expect(got.last, closeTo(0, 1e-6), reason: "and arrives");
    });

    test("loudness over every speaker, weighted", () {
      const n = mixRate * 4;
      var tone = _tone(n, 1000);
      var stereo = LoudnessMeter()..add(tone, tone, n);
      var both = SpeakerLoudness(const [1, 1])..add([tone, tone], n);
      expect(both.integrated, closeTo(stereo.integrated, 0.01));
      // The same tone from a surround: a decibel and a half louder.
      var silent = Float32List(n);
      var front = SpeakerLoudness(loudnessWeights(SpeakerLayout.surround51))
        ..add([tone, silent, silent, silent, silent, silent], n);
      var side = SpeakerLoudness(loudnessWeights(SpeakerLayout.surround51))
        ..add([silent, silent, silent, silent, tone, silent], n);
      expect(side.integrated - front.integrated, closeTo(1.5, 0.05));
      var lfe = SpeakerLoudness(loudnessWeights(SpeakerLayout.surround51))
        ..add([silent, silent, silent, tone, silent, silent], n);
      expect(lfe.integrated, double.negativeInfinity);
    });
  });

  group("placed by the picture", () {
    AudioElement sound(double x, SoundPlacement place) => AudioElement(
        ElementBase(id: "a", x: x, y: 100, width: 40, height: 40),
        clip: MediaClip(
            playlist: const [MediaSource(assetId: "t", length: 2)],
            timed: true,
            place: place));

    test("across the canvas: its left edge to its right is the arc", () {
      const doc = CanvasDocument();
      var w = doc.size.rect.width;
      const place = SoundPlacement(by: PlaceBy.canvas, arc: 60);
      expect(heardAt(doc, sound(-20, place), place, 0)!.angle,
          closeTo(-30, 0.01));
      expect(heardAt(doc, sound(w / 2 - 20, place), place, 0)!.angle,
          closeTo(0, 0.01));
      var wide = place.copyWith(arc: 180);
      expect(heardAt(doc, sound(w - 20, wide), wide, 0)!.angle,
          closeTo(90, 0.01));
      expect(heardAt(doc, sound(0, const SoundPlacement()),
              const SoundPlacement(), 0),
          isNull);
    });

    test("with another element: where it goes, it goes", () {
      var doc = CanvasDocument(elements: [
        sound(0, const SoundPlacement(by: PlaceBy.follow, follow: "car")),
        const AudioElement(
            ElementBase(id: "car", x: 0, y: 0, width: 10, height: 10)),
      ]);
      var a = doc.elementById("a")!;
      var place = (a as AudioElement).clip.place;
      expect(heardAt(doc, a, place, 0)!.angle, lessThan(-25));
    });

    test("the controller hands each placed channel's place on", () async {
      var engine = FakeEngine({"t": 2});
      const place = SoundPlacement(by: PlaceBy.canvas, arc: 60);
      var c = CanvasController(
          CanvasDocument(
              frames: 50,
              frameRate: 25,
              audio: const AudioSettings(speakers: SpeakerLayout.surround51),
              elements: [sound(-20, place)]),
          audioEngine: engine);
      addTearDown(c.dispose);
      expect(c.placementsNow["a"]!.angle, closeTo(-30, 0.01));
      c.play();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.pause();
      expect(engine.speakers, SpeakerLayout.surround51);
      expect(engine.placements["a"]!.angle, closeTo(-30, 0.01));
    });
  });

  group("written", () {
    late Directory dir;
    late String tone;
    var ready = false;

    setUpAll(() async {
      var which = await Process.run("which", ["ffmpeg"]);
      if (which.exitCode != 0) return;
      dir = await Directory.systemTemp.createTemp("canvas-surround");
      tone = path.join(dir.path, "tone.wav");
      await Process.run("ffmpeg", [
        "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", tone //
      ]);
      ready = true;
    });

    tearDownAll(() async {
      if (ready) await dir.delete(recursive: true);
    });

    CanvasDocument doc(SpeakerLayout speakers,
            {ChannelMix mix = const ChannelMix(),
            SoundPlacement place = const SoundPlacement(),
            double x = 100}) =>
        CanvasDocument(
            frames: 50,
            frameRate: 25,
            audio: AudioSettings(speakers: speakers),
            elements: [
              AudioElement(ElementBase(id: "a", x: x, width: 40, height: 40),
                  clip: MediaClip(
                      playlist: const [
                        MediaSource(assetId: "tone", name: "tone", length: 2)
                      ],
                      timed: true,
                      mix: mix,
                      place: place)),
            ]);

    /// mediaFor is [d]'s sounds as an export gathers them, every file
    /// [file].
    Future<List<ExportSound>> mediaFor(CanvasDocument d, String file) async {
      var media = ExportMedia.of(d, locate: (kind, id) async => file)!;
      try {
        return await media.sounds();
      } finally {
        media.dispose();
      }
    }

    /// levels reads [file] -- a float WAV of [channels] -- back, as each
    /// channel's level.
    List<double> levels(String file, int channels) {
      var bytes = File(file).readAsBytesSync();
      var at = channels > 2 ? 68 : 44;
      var data = ByteData.sublistView(bytes, at);
      var frames = data.lengthInBytes ~/ (4 * channels);
      var sums = List.filled(channels, 0.0);
      for (var f = 0; f < frames; f++) {
        for (var c = 0; c < channels; c++) {
          var v = data.getFloat32((f * channels + c) * 4, Endian.little);
          sums[c] += v * v;
        }
      }
      return [for (var s in sums) math.sqrt(s / frames)];
    }

    test("a 5.1 mix is six speakers, each where it was put", () async {
      if (!ready) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      var d = doc(SpeakerLayout.surround51,
          mix: const ChannelMix()
              .withSurround(const SurroundPan(angle: -110, width: 0)));
      var media = await mediaFor(d, tone);
      var out = path.join(dir.path, "mix.wav");
      expect(
          await renderMixWav(media, d.masterMix,
              seconds: 2,
              ffmpeg: "ffmpeg",
              out: out,
              speakers: SpeakerLayout.surround51),
          isTrue);
      var said = await Process.run("ffmpeg", ["-hide_banner", "-i", out]);
      expect("${said.stderr}", contains("5.1"),
          reason: "ffmpeg reads the speakers from the channel mask");
      var got = levels(out, 6);
      expect(got[_ls], greaterThan(0.05));
      for (var c in [_l, _r, _c, _lfe, _rs]) {
        expect(got[c], lessThan(1e-4), reason: "speaker $c");
      }
    });

    for (var (format, layout) in [
      (AudioFormat.wav, "5.1"),
      (AudioFormat.flac, "5.1"),
      (AudioFormat.aac, "5.1"),
      (AudioFormat.opus, "5.1"),
      (AudioFormat.mp3, "stereo"),
    ]) {
      test("published as ${format.label}: $layout", () async {
        if (!ready) {
          markTestSkipped("ffmpeg is not installed");
          return;
        }
        var made = await renderAudio(doc(SpeakerLayout.surround51),
            options: AudioOptions(format: format),
            locate: (kind, id) async => tone);
        expect(made, isNotNull);
        var file = path.join(dir.path, "out${format.extension}");
        await File(file).writeAsBytes(made!.data);
        var said = await Process.run("ffmpeg", ["-hide_banner", "-i", file]);
        expect("${said.stderr}", contains(", $layout"));
      });
    }

    test("7.1 is eight", () async {
      if (!ready) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      var made = await renderAudio(doc(SpeakerLayout.surround71),
          options: const AudioOptions(format: AudioFormat.flac),
          locate: (kind, id) async => tone);
      var file = path.join(dir.path, "seven.flac");
      await File(file).writeAsBytes(made!.data);
      var said = await Process.run("ffmpeg", ["-hide_banner", "-i", file]);
      expect("${said.stderr}", contains("7.1"));
    });

    test("placed at the canvas's left edge, a stereo file's left", () async {
      if (!ready) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      var d = doc(SpeakerLayout.stereo,
          place: const SoundPlacement(by: PlaceBy.canvas), x: -20);
      var media = await mediaFor(d, tone);
      expect(media.single.place.single.$2.angle, closeTo(-30, 0.01));
      var out = path.join(dir.path, "left.wav");
      await renderMixWav(media, d.masterMix,
          seconds: 2, ffmpeg: "ffmpeg", out: out);
      var got = levels(out, 2);
      expect(got[_l], greaterThan(0.05));
      expect(got[_r], lessThan(1e-4));
    });
  });

  group("the controls", () {
    /// show puts [child] up -- and, for the mixer, whose meters never
    /// settle, pumps a frame rather than waiting for them to.
    Future<void> show(WidgetTester tester, Widget child,
        {bool settle = true}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> frame(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 100));

    AudioElement timed(String id,
            {SoundPlacement place = const SoundPlacement(), double x = 100}) =>
        AudioElement(ElementBase(id: id, name: id, x: x, width: 40, height: 40),
            clip: MediaClip(
                playlist: const [MediaSource(assetId: "t", length: 2)],
                timed: true,
                place: place));

    Widget mixer(CanvasController c) => Align(
        alignment: Alignment.bottomCenter,
        child: CanvasMixer(
            controller: c, height: 420, onResize: (_) {}, onClose: () {}));

    testWidgets("Speakers in Canvas settings", (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      await show(tester, CanvasSettingsPanel(controller: c));
      var speakers = find.byKey(const ValueKey("audioSpeakers"));
      await tester.ensureVisible(speakers);
      tester
          .widget<CanvasDropdown<SpeakerLayout>>(speakers)
          .onChanged(SpeakerLayout.surround51);
      await tester.pumpAndSettle();
      expect(c.document.audio.speakers, SpeakerLayout.surround51);
      expect(
          tester
              .widgetList<CanvasHint>(find.byType(CanvasHint))
              .any((h) => h.message.contains("folded down to two speakers")),
          isTrue);
    });

    testWidgets("stereo keeps its pan knob; surround opens the Panner",
        (tester) async {
      var c = CanvasController(CanvasDocument(frames: 50, elements: [timed("a")]),
          audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      await show(tester, mixer(c), settle: false);
      Finder inStrip(String key) => find.descendant(
          of: find.byKey(const ValueKey("strip-a")),
          matching: find.byKey(ValueKey(key)));
      expect(inStrip("balance"), findsOneWidget);
      expect(inStrip("pannerButton"), findsNothing);

      c.apply(c.document.copyWith(
          audio: const AudioSettings(speakers: SpeakerLayout.surround51)));
      await frame(tester);
      // The room is too small to place a sound by in a strip: a button,
      // with the room in miniature and where it is heard from.
      expect(inStrip("balance"), findsNothing);
      expect(inStrip("pannerButton"), findsOneWidget);
      expect(find.descendant(
              of: find.byKey(const ValueKey("strip-a")),
              matching: find.text("Front")),
          findsOneWidget);
      await tester.tap(inStrip("pannerButton"));
      await frame(tester);
      expect(c.effectsOf, "a");
      expect(c.effectsFocus, "panner", reason: "the Panner, scrolled to");

      c.setChannelMix(c.timelineChannels.single,
          (c.document.elements.single as AudioElement)
              .clip
              .mix
              .withSurround(const SurroundPan(angle: 116.6)));
      await frame(tester);
      expect(find.descendant(
              of: find.byKey(const ValueKey("strip-a")),
              matching: find.text("R117°")),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a placed channel shows where the picture puts it",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 50, elements: [
            timed("a",
                place: const SoundPlacement(by: PlaceBy.canvas), x: -20),
          ]),
          audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      await show(tester, mixer(c), settle: false);
      expect(find.byKey(const ValueKey("pannerButton")), findsOneWidget,
          reason: "even in stereo: a placed sound is shown where it is");
      expect(find.text("L30°"), findsOneWidget);
    });

    testWidgets("Placement in the sound's settings", (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 50, elements: [timed("a", x: -20)]),
          audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      c.selectOnly("a");
      await show(
          tester,
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: CanvasControlScope(
                  maxWidth: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: elementSettings(context, c, c.selected!),
                  ),
                ),
              ),
            ),
          ));
      var section = find.byKey(const ValueKey("elementSection-placement"));
      expect(section, findsOneWidget);
      if (find.byKey(const ValueKey("placeBy")).evaluate().isEmpty) {
        await tester.ensureVisible(section);
        await tester.tap(find.descendant(
            of: section, matching: find.text("Placement")).first);
        await tester.pumpAndSettle();
      }
      tester
          .widget<CanvasDropdown<PlaceBy>>(
              find.byKey(const ValueKey("placeBy")))
          .onChanged(PlaceBy.canvas);
      await tester.pumpAndSettle();
      var place = (c.document.elements.single as AudioElement).clip.place;
      expect(place.by, PlaceBy.canvas);
      expect(
          tester
              .widgetList<CanvasHint>(find.byType(CanvasHint))
              .any((h) => h.message.contains("30° to the left")),
          isTrue);
      expect(find.byKey(const ValueKey("placeArc")), findsOneWidget);
      expect(find.byKey(const ValueKey("placeStage")), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group("the Panner", () {
    Future<CanvasController> open(WidgetTester tester, SpeakerLayout layout,
        {SoundPlacement place = const SoundPlacement()}) async {
      tester.view.physicalSize = const Size(1800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var c = CanvasController(
          CanvasDocument(
              frames: 50,
              audio: AudioSettings(speakers: layout),
              elements: [
                AudioElement(
                    const ElementBase(id: "a", name: "a", x: -20, width: 40),
                    clip: MediaClip(
                        playlist: const [MediaSource(assetId: "t", length: 2)],
                        timed: true,
                        place: place)),
              ]),
          audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      c.openEffects("a");
      for (var d in ["eq", "comp", "duck"]) {
        c.foldDevice(d, true);
      }
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
                    builder: (context, _) => CanvasMixer.effects(
                        controller: c,
                        height: 400,
                        onResize: (_) {},
                        onClose: () {})))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return c;
    }

    ChannelMix mixOf(CanvasController c) =>
        (c.document.elements.single as AudioElement).clip.mix;

    Future<void> dragTo(WidgetTester tester, double deg) async {
      // The room is an ellipse as wide as the device: aimed through it.
      var room = tester.getRect(find.byKey(const ValueKey("pannerRoom")));
      var rx = room.width / 2 - 22, ry = room.height / 2 - 18;
      var a = deg * math.pi / 180;
      Offset at(double k) =>
          room.center + Offset(math.sin(a) * rx * k, -math.cos(a) * ry * k);
      var g = await tester.startGesture(room.center + const Offset(0, -40));
      await g.moveTo(at(0.3));
      await g.moveTo(at(0.6));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets("in stereo, dragged to the right speaker is hard right",
        (tester) async {
      var c = await open(tester, SpeakerLayout.stereo);
      expect(find.byKey(const ValueKey("pannerBalance")), findsOneWidget);
      await dragTo(tester, 40);
      expect(mixOf(c).balance, 1);
      await tester.tap(find.byKey(const ValueKey("pannerFront")));
      await tester.pump(const Duration(milliseconds: 400));
      expect(mixOf(c).balance, 0);
    });

    testWidgets("in 5.1, dragged round behind; the wheel spreads it",
        (tester) async {
      var c = await open(tester, SpeakerLayout.surround51);
      await dragTo(tester, -135);
      expect(mixOf(c).surround!.angle, closeTo(-135, 1));
      var room = find.byKey(const ValueKey("pannerRoom"));
      tester.binding.handlePointerEvent(PointerScrollEvent(
          position: tester.getCenter(room),
          scrollDelta: const Offset(0, -40)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(mixOf(c).surround!.width, closeTo(70, 0.01));
      expect(find.text("L135°"), findsWidgets);
      c.undo();
      expect(mixOf(c).surround!.width, 60, reason: "each change undoable");
      // Double-clicked: the front pair again.
      await tester.tap(room);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(room);
      await tester.pump(const Duration(milliseconds: 400));
      expect(mixOf(c).surround, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets("placed by the picture, it shows where, and stays",
        (tester) async {
      var c = await open(tester, SpeakerLayout.surround71,
          place: const SoundPlacement(by: PlaceBy.canvas));
      expect(find.text("Placed by the picture"), findsOneWidget);
      expect(find.byKey(const ValueKey("pannerAngle")), findsNothing);
      await dragTo(tester, 90);
      expect(mixOf(c).surround, isNull);
    });

    test("the speakers are lit by what each carries", () {
      var front =
          speakerLights(SpeakerLayout.surround51, const ChannelMix(), null);
      expect(front, [1.0, 1.0, 0.0, 0.0, 0.0, 0.0]);
      var back = speakerLights(
          SpeakerLayout.surround51,
          const ChannelMix()
              .withSurround(const SurroundPan(angle: 110, width: 0))
              .withLfe(0),
          null);
      expect(back[5], closeTo(1, 1e-9));
      expect(back[3], 1, reason: "the LFE, sent at full");
      expect(speakerLights(SpeakerLayout.stereo,
          const ChannelMix(balance: 0.5), null), [0.5, 1.0]);
    });
  });
}

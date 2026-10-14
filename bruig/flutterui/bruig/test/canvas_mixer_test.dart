import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
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

    test("eight bands: two cuts, two shelves and four bells", () {
      expect(EqSlot.values, hasLength(8));
      expect([
        for (var s in EqSlot.values) s.kind
      ], [
        EqKind.lowCut,
        EqKind.lowShelf,
        EqKind.bell,
        EqKind.bell,
        EqKind.bell,
        EqKind.bell,
        EqKind.highShelf,
        EqKind.highCut,
      ]);
      expect(const Eq(on: true).flat, isTrue,
          reason: "the cuts start off, the rest at nought");
    });

    test("a cut is three decibels down at its corner, and as steep as asked",
        () {
      const twelve = Eq(on: true, lowCut: EqBand(200));
      expect(twelve.responseDb(200), closeTo(-3, 0.1));
      // An octave below, twelve decibels an octave is near twelve down.
      expect(twelve.responseDb(100), closeTo(-12.3, 0.5));
      const fortyEight = Eq(on: true, lowCut: EqBand(200, slope: 48));
      expect(fortyEight.responseDb(100), lessThan(-40));
      expect(fortyEight.responseDb(2000), closeTo(0, 0.1));
      const top = Eq(on: true, highCut: EqBand(4000, slope: 24));
      expect(top.responseDb(8000), lessThan(-20));
      expect(top.responseDb(400), closeTo(0, 0.1));
    });

    test("the output gain lifts everything", () {
      expect(const Eq(on: true, gainDb: 4).responseDb(50), closeTo(4, 1e-9));
      expect(const Eq(on: true, gainDb: 4).flat, isFalse);
    });

    test("a file from before eight bands reads as it was", () {
      var old = Eq.fromJson(const {
        "on": true,
        "low": {"f": 100, "g": 3, "q": 0.707},
        "mid": {"f": 2000, "g": -2, "q": 1},
        "high": {"f": 9000, "g": 1, "q": 0.707},
      });
      expect(old.low.gainDb, 3);
      expect(old.mid.freq, 2000);
      expect(old.high.gainDb, 1);
      expect(old.lowCut.on, isFalse);
      expect(old.lowMid.gainDb, 0);
      var eq = const Eq(
          on: true,
          lowCut: EqBand(80, slope: 36, q: 1.2),
          presence: EqBand(5000, gainDb: 2, q: 2, on: false),
          gainDb: -2);
      var back = Eq.fromJson(eq.toJson());
      expect(back.lowCut.slope, 36);
      expect(back.lowCut.on, isTrue);
      expect(back.presence.on, isFalse);
      expect(back.gainDb, -2);
    });

    test("a cut is written for ffmpeg as a section per twelve dB", () {
      var args = eqFfmpeg(const Eq(
          on: true,
          lowCut: EqBand(80, slope: 24, q: 1),
          highCut: EqBand(12000),
          gainDb: 1.5));
      expect(args, [
        "highpass=f=80.000:p=2:t=q:w=1.000",
        "highpass=f=80.000:p=2:t=q:w=0.707",
        "lowpass=f=12000.000:p=2:t=q:w=0.707",
        "volume=1.500dB",
      ]);
    });

    test("and ffmpeg's cut is the one drawn", () async {
      var which = await Process.run("which", ["ffmpeg"]);
      if (which.exitCode != 0) {
        markTestSkipped("ffmpeg is not installed");
        return;
      }
      const eq = Eq(on: true, lowCut: EqBand(200, slope: 24));
      Future<double> level(List<String> filters) async {
        var r = await Process.run("ffmpeg", [
          "-hide_banner", "-f", "lavfi", //
          "-i", "sine=frequency=100:sample_rate=48000:duration=2",
          "-af", [...filters, "volumedetect"].join(","),
          "-f", "null", "-",
        ]);
        var m = RegExp(r"mean_volume: (-?[\d.]+) dB")
            .firstMatch(r.stderr as String);
        return double.parse(m!.group(1)!);
      }

      var dry = await level(const []);
      var wet = await level(eqFfmpeg(eq));
      expect(wet - dry, closeTo(eq.responseDb(100), 0.5));
    });
  });

  test("a strip above nought is its volume, its pan held to one", () {
    // Reported: a fader above nought threw in SoLoud's pan, which takes
    // nothing over one -- and the throw lost the strip's EQ and compressor.
    var (gl, gr) = const ChannelMix(gainDb: 6, balance: 0.5).gains;
    var (volume, left, right) = busLevels(gl, gr);
    expect(volume, greaterThan(1));
    for (var side in [left, right]) {
      expect(side, inInclusiveRange(-1, 1));
    }
    expect(volume * left, closeTo(gl, 1e-9));
    expect(volume * right, closeTo(gr, 1e-9));
    expect(busLevels(0, 0), (0.0, 1.0, 1.0), reason: "muted: silent, centred");
    expect(busLevels(1, 1), (1.0, 1.0, 1.0));
  });

  group("the order of the EQ and the compressor", () {
    test("is the strip's, in the export", () {
      const eq = Eq(on: true, mid: EqBand(1000, gainDb: 3));
      const comp = Dynamics(on: true);
      var after = const ChannelMix(eq: eq, comp: comp).ffmpeg;
      expect(after.first, startsWith("equalizer"));
      var before = const ChannelMix(eq: eq, comp: comp, compFirst: true).ffmpeg;
      expect(before.first, startsWith("acompressor"));
      var master = const MasterMix(eq: eq, comp: comp, compFirst: true).ffmpeg;
      expect(master.first, startsWith("acompressor"));
      expect(master.last, startsWith("alimiter"), reason: "the limiter last");
      expect(
          ChannelMix.fromJson(const ChannelMix(compFirst: true).toJson())
              .compFirst,
          isTrue);
    });

    test("and in playing: SoLoud's filters are put back in that order", () {
      // A filter switched on lands last: one out of place is switched off,
      // with everything after it, and they go back on in order.
      void steps(List<String> have, List<String> want, List<String> off,
          List<String> on) {
        var (o, n) = reorderSteps(have, want);
        expect([o, n], [off, on], reason: "$have to $want");
      }

      steps(["eq", "comp"], ["eq", "comp"], [], []);
      steps(["eq", "comp"], ["comp", "eq"], ["eq", "comp"], ["comp", "eq"]);
      // The limiter on, then the EQ switched on: it must go before it.
      steps(["limiter"], ["eq", "limiter"], ["limiter"], ["eq", "limiter"]);
      steps(["eq", "comp", "limiter"], ["eq", "limiter"], ["comp", "limiter"],
          ["limiter"]);
    });
  });

  group("the compressor", () {
    test("a knee of nought is a hard corner", () {
      const c = Dynamics(threshold: -20, ratio: 4, kneeDb: 0);
      expect(c.reducedDb(-21), -21);
      expect(c.reducedDb(-12), closeTo(-18, 1e-9));
      const soft = Dynamics(threshold: -20, ratio: 4, kneeDb: 12);
      expect(soft.reducedDb(-20), lessThan(-20),
          reason: "a soft knee has started at the threshold");
    });

    test("auto gain brings its reference level back", () {
      const c = Dynamics(
          threshold: -20, ratio: 4, kneeDb: 0, autoGain: AutoGain.zero);
      expect(c.reducedDb(0) + c.totalMakeupDb, closeTo(0, 1e-9));
      const twelve = Dynamics(
          threshold: -20, ratio: 4, kneeDb: 0, autoGain: AutoGain.minus12);
      expect(twelve.reducedDb(-12) + twelve.totalMakeupDb, closeTo(-12, 1e-9));
      expect(const Dynamics(makeupDb: 3).totalMakeupDb, 3);
    });

    test("knee, mix and auto gain are saved and reach ffmpeg", () {
      const c =
          Dynamics(on: true, kneeDb: 0, mix: 0.5, autoGain: AutoGain.minus12);
      var back = Dynamics.fromJson(c.toJson());
      expect(back.kneeDb, 0);
      expect(back.mix, 0.5);
      expect(back.autoGain, AutoGain.minus12);
      expect(c.ffmpeg, contains(":mix=0.5000"));
      expect(c.ffmpeg, contains(":knee=1.0000"));
      expect(Dynamics.fromJson(const {"on": true}).kneeDb, 6,
          reason: "an older file keeps the knee it had");
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
      AudioElement timed(double volume) =>
          AudioElement(const ElementBase(id: "t", visible: false),
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

    // Played from part way through a sound, it starts silent and rises over
    // a few milliseconds: a waveform cut into mid-swing clicks. From the top
    // it starts at its level, the file itself starting from silence.
    test("a sound started part way through rises rather than clicking",
        () async {
      var e = AudioElement(const ElementBase(id: "t", visible: false),
          clip: const MediaClip(
              timed: true, volume: 1, playlist: [MediaSource(assetId: song)]));
      runtime.cue(e, const ClipMoment(0, 2.5, 1), playing: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      var voice = engine.last;
      expect(voice.fades.first.$1, closeTo(1, 1e-9), reason: "up to its level");
      expect(voice.fades.first.$2, declickSeconds);

      var fresh = AudioRuntime(engine: engine, locate: (id) async => id);
      addTearDown(fresh.dispose);
      fresh.cue(e, const ClipMoment(0, 0, 1), playing: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(engine.last.fades, isEmpty, reason: "from the top, no ramp");
    });

    // Every frame the playhead moves the sound is cued again. Its volume is
    // put on it only when it has changed -- put on every frame, it cut off
    // the rise a sound starts with -- and on the timeline by a glide.
    test("a timeline sound's volume is set when it changes, by a glide",
        () async {
      var e = AudioElement(const ElementBase(id: "t", visible: false),
          clip: const MediaClip(
              timed: true, volume: 1, playlist: [MediaSource(assetId: song)]));
      runtime.cue(e, const ClipMoment(0, 2.5, 1), playing: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      var voice = engine.last;
      for (var i = 1; i <= 10; i++) {
        voice.at = 2.5 + i * 0.04;
        runtime.cue(e, ClipMoment(0, 2.5 + i * 0.04, 1), playing: true);
      }
      expect(voice.fades, hasLength(1),
          reason: "the rise it started with, and nothing after it");

      runtime.cue(e, const ClipMoment(0, 2.94, 0.5), playing: true);
      expect(voice.fades.last, (0.5, glideSeconds),
          reason: "a fade's next step, glided to");
    });

    // The sound card reports where a sound has got in steps, so a little
    // either way is not the sound being out of time; moving a playing sound
    // is a jump that is heard.
    test("a timeline sound is moved only when it is really out of time",
        () async {
      var e = AudioElement(const ElementBase(id: "t", visible: false),
          clip: const MediaClip(
              timed: true, volume: 1, playlist: [MediaSource(assetId: song)]));
      runtime.cue(e, const ClipMoment(0, 1, 1), playing: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      var voice = engine.last;
      voice.at = 1.2;
      runtime.cue(e, const ClipMoment(0, 1, 1), playing: true);
      expect(voice.at, 1.2, reason: "a fifth of a second is left alone");
      voice.at = 1.6;
      runtime.cue(e, const ClipMoment(0, 1, 1), playing: true);
      expect(voice.at, 1, reason: "more than driftSeconds is put right");
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

    test("sounds on one channel share that channel's strip", () async {
      runtime.setMix(const {"ch": ChannelMix(balance: -1)},
          routes: const {"a": "ch", "b": "ch", "video:v": "ch", "v": "ch"},
          master: const MasterMix());
      await runtime.play(sound("a"));
      await runtime.play(sound("b"));
      await runtime.play(sound("video:v"));
      expect(engine.onChannel.values, everyElement("ch"));
      expect(engine.channels.keys, ["ch"],
          reason: "one strip -- one bus -- for the channel, not one a sound");
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

  group("the controller", () {
    testWidgets("gives each timeline channel one strip, not one per clip",
        (tester) async {
      var engine = FakeEngine({song: 10});
      AudioElement clip(String id, String channel, int at) =>
          AudioElement(ElementBase(id: id, visible: false),
              clip: MediaClip(
                  timed: true,
                  at: at,
                  channel: channel,
                  playlist: const [MediaSource(assetId: song, length: 10)]));
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 25, elements: [
            clip("a", "fx", 0),
            clip("b", "fx", 10),
            clip("c", "fx", 20),
            clip("d", "voice", 0),
          ]),
          audioEngine: engine);
      c.play();
      await tester.pump(const Duration(milliseconds: 100));
      c.stop();
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.audio.strips, {"fx", "voice"});
      expect(c.audio.routes, {"a": "fx", "b": "fx", "c": "fx", "d": "voice"});
      c.dispose();
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
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // As the screen has them: the effects panel, when it is open, over
      // the mixer.
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
                              if (c.effectsOpen)
                                CanvasMixer.effects(
                                    controller: c,
                                    height: 360,
                                    onResize: (_) {},
                                    onClose: () => c.effectsOpen = false),
                              CanvasMixer(
                                  controller: c,
                                  height: 380,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
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

    /// tapOn taps [f], scrolled into view first: the chain runs sideways
    /// past the edge.
    Future<void> tapOn(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> openOn(WidgetTester tester, String strip, String slot) async {
      await tester.tap(find.descendant(
          of: find.byKey(ValueKey(strip)),
          matching: find.byKey(ValueKey(slot))));
      await tester.pump(const Duration(milliseconds: 300));
      // And the chain's scroll to the device, which is animated.
      await tester.pump(const Duration(milliseconds: 300));
    }

    double leftOf(WidgetTester tester, String device) =>
        tester.getRect(find.byKey(ValueKey("device-$device"))).left;

    // Reported: between the one line and the full strips, the strips were
    // squeezed and their columns overflowed.
    testWidgets("the mixer and the effects fit at every height",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 25, elements: [
            timed("v", "Speaker"),
            timed("w", "Backdrop"),
          ]),
          audioEngine: engine,
          frameSource: FakeFrames(4));
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      Future<void> at(double h, {bool effects = false}) =>
          tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeNotifier>(
                  create: (c) => ThemeNotifier(doLoad: false)),
              ChangeNotifierProvider<SnackBarModel>(
                  create: (c) => SnackBarModel()),
            ],
            child: MaterialApp(
                home: Scaffold(
                    body: Align(
                        alignment: Alignment.bottomCenter,
                        child: effects
                            ? CanvasMixer.effects(
                                controller: c,
                                height: h,
                                onResize: (_) {},
                                onClose: () {})
                            : CanvasMixer(
                                controller: c,
                                height: h,
                                onResize: (_) {},
                                onClose: () {})))),
          ));
      for (var h = 400.0; h >= mixerMinHeight; h -= 3) {
        await at(h);
        expect(tester.takeException(), isNull, reason: "the mixer at $h");
      }
      c.effectsOf = "v";
      for (var h = 600.0; h >= effectsMinHeight; h -= 10) {
        await at(h, effects: true);
        expect(tester.takeException(), isNull, reason: "the effects at $h");
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets("a strip is picked with a press, and renamed by its name",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey("strip-w")),
          matching: find.byKey(const ValueKey("faderReading"))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.selectedChannel, "w", reason: "the same pick as the timeline's");
      await tester.tap(find.byKey(const ValueKey("strip-master")));
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.selectedChannel, mixerMasterKey);

      var name = find.descendant(
          of: find.byKey(const ValueKey("strip-v")),
          matching: find.byKey(const ValueKey("mixerName")));
      await tester.tap(name);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(name);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
          find.byKey(const ValueKey("mixerNameField")), "Narrator");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
          c.timelineChannels.firstWhere((l) => l.key == "v").name, "Narrator");
      await done(tester, c);
    });

    testWidgets("short, it is one line of names over meters", (tester) async {
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
                        height: mixerMinHeight,
                        onResize: (_) {},
                        onClose: () {})))),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey("strip-v")), findsNothing);
      for (var k in ["v", "w", mixerMasterKey]) {
        expect(find.byKey(ValueKey("compactMeter-$k")), findsOneWidget);
      }
      var meter = tester.getRect(find.byKey(const ValueKey("compactMeter-v")));
      expect(meter.width, greaterThan(meter.height), reason: "on its side");
      expect(tester.getRect(find.byKey(const ValueKey("compactName-v"))).bottom,
          lessThanOrEqualTo(meter.top + 1),
          reason: "the name over the meter");
      await tester.tap(find.byKey(const ValueKey("compact-w")));
      await tester.pump();
      expect(c.selectedChannel, "w");
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("picking a strip shows its effects", (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      expect(c.effectsOf, "v");
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey("strip-w")),
          matching: find.byKey(const ValueKey("faderReading"))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.effectsOf, "w");
      expect(c.selectedChannel, "w");
      var meter = find.byKey(const ValueKey("device-meter"));
      await tester.ensureVisible(meter);
      await tester.pump();
      expect(find.descendant(of: meter, matching: find.text("Backdrop")),
          findsOneWidget,
          reason: "the channel's strip, under its name");
      await done(tester, c);
    });

    testWidgets("the chain's channel strip pans, mutes and solos",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      var meter = find.byKey(const ValueKey("device-meter"));
      await tester.ensureVisible(meter);
      await tester.pump();
      await tester.tap(find.descendant(
          of: meter, matching: find.byKey(const ValueKey("meterMute"))));
      await tester.pump();
      expect((c.document.elements.first as VideoElement).clip.mix.mute, isTrue);
      await tester.tap(find.descendant(
          of: meter, matching: find.byKey(const ValueKey("meterSolo"))));
      await tester.pump();
      expect(c.solo, {"v"});
      // Folded like the rest.
      await tester.tap(find.byKey(const ValueKey("deviceFold-meter")));
      await tester.pump();
      expect(find.byKey(const ValueKey("meterFolded")), findsOneWidget);
      expect(find.byKey(const ValueKey("meterMute")), findsNothing);
      await done(tester, c);
    });

    testWidgets("the chain's meter is the strip's fader and meter",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      var meter = find.byKey(const ValueKey("device-meter"));
      await tester.ensureVisible(meter);
      await tester.pump();
      expect(
          find.descendant(
              of: meter, matching: find.byKey(const ValueKey("fader"))),
          findsOneWidget);
      await tester.drag(
          find.descendant(
              of: meter, matching: find.byKey(const ValueKey("fader"))),
          const Offset(0, 60));
      await tester.pump();
      expect((c.document.elements.first as VideoElement).clip.mix.gainDb,
          lessThan(0));
      await done(tester, c);
    });

    testWidgets("a slot opens the strip's effects as a chain, in order",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      for (var d in ["eq", "comp", "duck", "meter", "masterMeter"]) {
        expect(find.byKey(ValueKey("device-$d")), findsOneWidget, reason: d);
      }
      expect(find.byKey(const ValueKey("device-limiter")), findsNothing,
          reason: "the master's");
      var order = [
        for (var d in ["eq", "comp", "duck", "meter", "masterMeter"])
          leftOf(tester, d)
      ];
      expect([...order]..sort(), order, reason: "left to right as it sounds");

      // The compressor is moved before the EQ: in the chain and in the mix.
      await tapOn(tester, find.byKey(const ValueKey("deviceMoveRight-eq")));
      expect(leftOf(tester, "comp"), lessThan(leftOf(tester, "eq")));
      var mix = (c.document.elements.first as VideoElement).clip.mix;
      expect(mix.compFirst, isTrue);
      expect(c.canUndo, isTrue);

      // A panel of its own: the strips are still there under it.
      expect(find.byKey(const ValueKey("strip-v")), findsOneWidget);
      expect(
          tester.getRect(find.byKey(const ValueKey("effectsChain"))).bottom,
          lessThanOrEqualTo(
              tester.getRect(find.byKey(const ValueKey("strip-v"))).top));
      // Shut from the timeline's button: the panel has no bar of its own.
      expect(find.byTooltip("Close the effects"), findsNothing);
      c.effectsOpen = false;
      await tester.pump();
      expect(find.byKey(const ValueKey("effectsChain")), findsNothing);
      expect(find.byKey(const ValueKey("strip-v")), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("a device folds to its switch and a meter, and opens again",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      var open = tester.getSize(find.byKey(const ValueKey("device-eq"))).width;
      await tapOn(tester, find.byKey(const ValueKey("deviceFold-eq")));
      var folded =
          tester.getSize(find.byKey(const ValueKey("device-eq"))).width;
      expect(folded, lessThan(open / 4));
      expect(find.byKey(const ValueKey("eqFolded")), findsOneWidget);
      expect(find.byKey(const ValueKey("eqOn")), findsOneWidget,
          reason: "the switch stays");
      expect(find.byKey(const ValueKey("eqCurve")), findsNothing);
      expect(c.foldedDevices, {"eq"});
      // Opening the EQ from its slot unfolds it.
      await openOn(tester, "strip-v", "eqSlot");
      expect(find.byKey(const ValueKey("eqCurve")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("the EQ: a point dragged lifts the curve, cuts and gain",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "eqSlot");
      var curve = find.byKey(const ValueKey("eqCurve"));
      expect(curve, findsOneWidget);
      for (var slot in EqSlot.values) {
        expect(find.byKey(ValueKey("eqBand-${slot.name}")), findsOneWidget);
        expect(find.byKey(ValueKey("eqFreq-${slot.name}")), findsOneWidget);
      }
      await tester.ensureVisible(curve);
      await tester.pump();
      var box = tester.getRect(curve);
      // The mid bell starts at 1 kHz, on the flat line: log-spaced 20 Hz..20
      // kHz.
      var x = box.left + math.log(1000 / 20) / math.log(1000) * box.width;
      await tester.dragFrom(Offset(x, box.center.dy), const Offset(0, -60));
      await tester.pump();
      var eq = (c.document.elements.first as VideoElement).clip.mix.eq;
      expect(eq.on, isTrue, reason: "moving a point switches it on");
      expect(eq.mid.gainDb, greaterThan(2));
      expect(c.canUndo, isTrue);

      // A cut is switched on from its button, and its slope stepped.
      await tapOn(tester, find.byKey(const ValueKey("eqBand-lowCut")));
      await tapOn(tester, find.byKey(const ValueKey("eqSlope-lowCut")));
      eq = (c.document.elements.first as VideoElement).clip.mix.eq;
      expect(eq.lowCut.on, isTrue);
      expect(eq.lowCut.slope, 24);
      expect(eq.responseDb(20), lessThan(-12));

      // The output gain, dragged up.
      await tester.ensureVisible(find.byKey(const ValueKey("eqOutput")));
      await tester.pump();
      await tester.drag(
          find.byKey(const ValueKey("eqOutput")), const Offset(0, -40));
      await tester.pump();
      eq = (c.document.elements.first as VideoElement).clip.mix.eq;
      expect(eq.gainDb, greaterThan(0));
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });

    testWidgets("the master's chain: EQ, glue, limiter, loudness, meter",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.byKey(const ValueKey("masterEqSlot")));
      await tester.pump(const Duration(milliseconds: 300));
      var order = [
        for (var d in ["eq", "comp", "limiter", "loudness", "masterMeter"])
          leftOf(tester, d)
      ];
      expect([...order]..sort(), order);
      expect(find.byKey(const ValueKey("device-duck")), findsNothing);
      expect(find.byKey(const ValueKey("device-meter")), findsNothing);
      await tapOn(tester, find.byKey(const ValueKey("eqOn")));
      expect(c.document.masterMix.eq.on, isTrue);
      await tapOn(tester, find.byKey(const ValueKey("limitOn")));
      expect(c.document.masterMix.limiter, isFalse);
      await done(tester, c);
    });

    testWidgets("the master's Loudness slot opens the target and Measure",
        (tester) async {
      var c = await show(tester);
      expect(find.byKey(const ValueKey("normalise")), findsNothing,
          reason: "bringing an export to the target is a publish setting");
      await tester.tap(find.byKey(const ValueKey("loudnessSlot")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey("measure")), findsOneWidget);
      expect(find.byKey(const ValueKey("loudnessTarget")), findsOneWidget);
      await done(tester, c);
    });

    testWidgets("a channel's Duck slot ducks the others, but those left alone",
        (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "duckSlot");
      await tapOn(tester, find.byKey(const ValueKey("duckOn")));
      await tapOn(tester, find.byKey(const ValueKey("duckExcept-w")));
      var duck = (c.document.elements.first as VideoElement).clip.mix.duck;
      expect(duck.on, isTrue);
      expect(duck.except, ["w"]);
      await done(tester, c);
    });

    testWidgets("the compressor: a meter, a graph and knobs", (tester) async {
      var c = await show(tester);
      await openOn(tester, "strip-v", "compSlot");
      expect(find.byKey(const ValueKey("gainReduction")), findsOneWidget,
          reason: "the meter first");
      await tapOn(tester, find.byKey(const ValueKey("compViewGraph")));
      expect(find.byKey(const ValueKey("compCurve")), findsOneWidget);
      for (var k in [
        "compThreshold",
        "compRatio",
        "compMakeup",
        "compKnee",
        "compAttack",
        "compRelease",
        "compMix",
        "compIn",
        "compOut",
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await tapOn(tester, find.byKey(const ValueKey("compOn")));
      // Up turns the ratio right, as a knob does.
      await tester.ensureVisible(find.byKey(const ValueKey("compRatio")));
      await tester.pump();
      await tester.drag(
          find.byKey(const ValueKey("compRatio")), const Offset(0, -60));
      await tester.pump();
      await tapOn(tester, find.byKey(const ValueKey("autoGain-zero")));
      var comp = (c.document.elements.first as VideoElement).clip.mix.comp;
      expect(comp.on, isTrue);
      expect(comp.ratio, greaterThan(3));
      expect(comp.autoGain, AutoGain.zero);
      expect(tester.takeException(), isNull);
      await done(tester, c);
    });
  });
}

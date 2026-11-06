import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_analysers_test.dart is the Chain's analysers: the Scope, the
// Stereo Image (goniometer and correlation), Loudness (BS.1770 momentary,
// short-term, integrated, and true peak), the Spectrum over time, and the
// Tuner and Spectrum among them -- each hearing where it is, changing
// nothing.

Float32List sine(int n, double hz, double level, {double phase = 0}) =>
    Float32List.fromList([
      for (var i = 0; i < n; i++)
        level * math.sin(2 * math.pi * hz * i / mixRate + phase)
    ]);

void main() {
  group("loudness", () {
    test("BS.1770's own check: -20dBFS of 1kHz both sides is -20 LUFS", () {
      var tap = LoudnessTap();
      var x = sine(mixRate * 4, 1000, 0.1);
      for (var at = 0; at < x.length; at += 1024) {
        var n = math.min(1024, x.length - at);
        var block = Float32List.sublistView(x, at, at + n);
        tap.process(block, block, n);
      }
      var r = tap.reading;
      expect(r.momentary, closeTo(-20, 0.2));
      expect(r.shortTerm, closeTo(-20, 0.2));
      expect(r.integrated, closeTo(-20, 0.2));
      expect(r.truePeak, closeTo(-20, 0.2), reason: "a sine's peak is its own");
      tap.reset();
      expect(tap.reading.integrated, -double.infinity);
      expect(tap.reading.truePeak, -double.infinity);
    });

    test("short-term follows the last three seconds, momentary 400ms", () {
      var m = LoudnessMeter();
      var loud = sine(mixRate * 3, 1000, 0.5),
          quiet = sine(mixRate, 1000, 0.05);
      m.add(loud, loud, loud.length);
      m.add(quiet, quiet, quiet.length);
      expect(m.momentary, closeTo(-26, 0.3), reason: "only the quiet second");
      expect(m.shortTerm, greaterThan(m.momentary + 6),
          reason: "two loud seconds still in it");
    });

    test("true peak: between the samples, where they miss the crest", () {
      // A quarter of the rate at 45°: every sample at 0.707, the wave at 1.
      var x = sine(4800, mixRate / 4, 1, phase: math.pi / 4);
      var sampled = x.fold(0.0, (a, v) => math.max(a, v.abs()));
      expect(sampled, closeTo(math.sqrt1_2, 1e-3));
      var p = TruePeak()..add(x, x, x.length);
      expect(p.peak, closeTo(1, 0.06));
    });
  });

  group("the wave", () {
    test("kept oldest first, thinned to as many points as are drawn", () {
      var tap = WaveTap(DeviceKind.scope, frames: 480, points: 120);
      var ramp =
          Float32List.fromList([for (var i = 0; i < 1000; i++) i / 1000]);
      tap.process(ramp, ramp, 1000);
      var (l, _) = tap.wave;
      expect(l.length, 120);
      expect(l.first, closeTo(0.52, 1e-6), reason: "the last 480 of 1000");
      expect(l.last, closeTo(0.996, 1e-6));
      for (var i = 1; i < l.length; i++) {
        expect(l[i], greaterThan(l[i - 1]));
      }
    });

    test("correlation: alike one, opposite minus one, unrelated nought", () {
      var a = sine(2048, 440, 0.5);
      var minus = Float32List.fromList([for (var v in a) -v]);
      expect(correlation((a, a)), closeTo(1, 1e-9));
      expect(correlation((a, minus)), closeTo(-1, 1e-9));
      expect(correlation((a, Float32List(2048))), 0);
      var rnd = math.Random(3);
      Float32List noise() => Float32List.fromList(
          [for (var i = 0; i < 8192; i++) rnd.nextDouble() - 0.5]);
      expect(correlation((noise(), noise())).abs(), lessThan(0.06));
    });
  });

  group("in the chain", () {
    test("analysers are their own family, and only listen", () {
      for (var k in [
        DeviceKind.tuner,
        DeviceKind.spectrum,
        DeviceKind.scope,
        DeviceKind.stereoImage,
        DeviceKind.loudness,
      ]) {
        expect(k.group, DeviceGroup.analysers, reason: k.name);
        expect(listensOnly(k), isTrue, reason: k.name);
      }
      expect(listensOnly(DeviceKind.reverb), isFalse);
    });

    test("heard where they are, and the sound passes them as it was", () {
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setChannel(
            "a",
            const ChannelMix(devices: [
              MixDevice(DeviceKind.scope),
              MixDevice(DeviceKind.stereoImage),
              MixDevice(DeviceKind.loudness),
            ]));
      var plain = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setChannel("a", const ChannelMix());
      const n = 4800;
      var tone = sine(n, 500, 0.3);
      var l = Float32List(n), r = Float32List(n);
      var pl = Float32List(n), pr = Float32List(n);
      for (var b = 0; b < 4; b++) {
        for (var (graph, ol, or) in [(g, l, r), (plain, pl, pr)]) {
          graph.begin(n);
          var (il, ir) = graph.input("a", n);
          il.setRange(0, n, tone);
          ir.setRange(0, n, tone);
          graph.finish(ol, or, n);
        }
      }
      for (var i = 0; i < n; i += 97) {
        expect(l[i], closeTo(pl[i], 1e-6), reason: "unchanged by them");
      }
      var scope = g.waveOf("a", DeviceKind.scope)!;
      expect(scope.$1.length, greaterThan(100));
      expect(scope.$1.reduce(math.max), closeTo(0.3, 0.02));
      expect(correlation(g.waveOf("a", DeviceKind.stereoImage)!),
          closeTo(1, 1e-6));
      // 0.3 is -10.5dBFS; K-weighting takes about 0.6dB off at 500Hz.
      expect(g.loudnessOf("a")!.shortTerm, closeTo(-11.1, 0.3));
      expect(g.waveOf("b", DeviceKind.scope), isNull);
      g.resetLoudness("a");
      expect(g.loudnessOf("a")!.integrated, -double.infinity);
    });
  });

  test("its Target moved, a Loudness keeps what it measured", () {
    var strip = StripProcessor(
        const ChannelMix(devices: [MixDevice(DeviceKind.loudness)]));
    var tap = strip.devices.single as LoudnessTap;
    var x = sine(mixRate, 1000, 0.1);
    tap.process(x, x, x.length);
    strip.retune(const ChannelMix(devices: [
      MixDevice(DeviceKind.loudness, values: {"target": -23})
    ]));
    expect(identical(strip.devices.single, tap), isTrue);
    expect(tap.reading.integrated, closeTo(-20, 0.2));
  });

  group("their cards", () {
    Future<(CanvasController, FakeEngine)> show(WidgetTester tester,
        {double scale = 1, double height = 360}) async {
      var engine = FakeEngine({"t": 4});
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            AudioElement(const ElementBase(id: "a", name: "Music"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 4)],
                    timed: true,
                    mix: ChannelMix(devices: [
                      MixDevice(DeviceKind.scope),
                      MixDevice(DeviceKind.stereoImage),
                      MixDevice(DeviceKind.loudness),
                      MixDevice(DeviceKind.spectrum),
                    ]))),
          ]),
          audioEngine: engine);
      c.openEffects("a");
      // The engine started, as playing does.
      await c.audio.ready();
      tester.view.physicalSize = const Size(2400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => CanvasMixer.effects(
                            controller: c,
                            height: height,
                            onResize: (_) {},
                            onClose: () {}))))),
      ));
      await tester.pump();
      return (c, engine);
    }

    testWidgets(
        "each shows what it hears; Loudness starts again; the "
        "Spectrum over time", (tester) async {
      var (c, engine) = await show(tester);
      addTearDown(c.dispose);
      var a = sine(1024, 440, 0.5);
      engine.heardWave = (a, Float32List.fromList([for (var v in a) -v]));
      engine.heardLoudness = (
        momentary: -12.0,
        shortTerm: -14.0,
        integrated: -15.2,
        truePeak: -0.8,
      );
      // Read again on the cards' next tick.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey("scopeView")), findsOneWidget);
      expect(find.byKey(const ValueKey("stereoImageView")), findsOneWidget);
      expect(find.text("correlation −1.00"), findsWidgets,
          reason: "a side turned over");
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("loudnessShortTerm")))
              .data,
          "−14.0");
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey("loudnessTruePeak")))
              .data,
          "−0.8 dBTP");
      await tester.ensureVisible(find.byKey(const ValueKey("loudnessReset-2")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("loudnessReset-2")));
      await tester.pump();
      expect(engine.loudnessResets, 1);
      // The Spectrum, over time.
      await tester.ensureVisible(find.byKey(const ValueKey("spectrumView-3")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("spectrumView-3")));
      await tester.pump();
      expect(c.devicesOf("a")[3].value("view"), 1);
      expect(find.byKey(const ValueKey("spectrogramView")), findsOneWidget);
      // The Scope's time, from its knob.
      var time = c.devicesOf("a")[0].value("time");
      await tester.ensureVisible(find.byKey(const ValueKey("device-0-time")));
      await tester.pump();
      await tester.drag(
          find.byKey(const ValueKey("device-0-time")), const Offset(0, -40));
      await tester.pump();
      expect(c.devicesOf("a")[0].value("time"), greaterThan(time));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("they fit, at every height and text size", (tester) async {
      var failures = <String>[];
      for (var scale in [1.0, 1.25, 1.5]) {
        for (var height in [180.0, 260.0, 360.0, 520.0]) {
          var (c, _) = await show(tester, scale: scale, height: height);
          if (tester.takeException() case var e?) {
            failures
                .add("$height ${scale}x: ${e.toString().split("\n").first}");
          }
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      }
      expect(failures, isEmpty);
    });
  });

  // Ken: some devices' displays did not move. Every device's screen reads
  // the levels before and after it -- on a channel, a return and the
  // master alike -- and every analyser reads where it is.
  group("every device's display has what it draws from", () {
    var kinds = [
      for (var k in DeviceKind.values)
        if (k != DeviceKind.split) k,
    ];
    var devices = [
      for (var (i, k) in kinds.indexed) MixDevice(k, id: "d$i"),
    ];
    const n = 4800;

    MixGraph played() {
      var g = MixGraph()
        ..setMaster(MasterMix(limiter: false, devices: devices))
        ..setReturns([
          ReturnChannel("fx",
              name: "Room", devices: devices, mix: const ChannelMix())
        ])
        ..setChannel("a", ChannelMix(devices: devices, sends: const {"fx": 0}));
      g.tapped.addAll(["a", "fx", masterTapKey]);
      var tone = sine(n, 440, 0.3);
      var l = Float32List(n), r = Float32List(n);
      // Two seconds: a Delay set all wet is silent until its first echo,
      // and the return's comes after the channel's.
      for (var b = 0; b < 20; b++) {
        g.begin(n);
        var (il, ir) = g.input("a", n);
        il.setRange(0, n, tone);
        ir.setRange(0, n, tone);
        g.finish(l, r, n);
      }
      return g;
    }

    test("the levels at every step: a channel, a return and the master", () {
      var g = played();
      for (var (key, steps) in [
        ("a", ChannelMix(devices: devices).chain.length),
        ("fx", devices.length),
        (masterTapKey, MasterMix(devices: devices).chain.length),
      ]) {
        var taps = g.tapsOf(key);
        expect(taps.length, steps + 1, reason: "in, then after each: $key");
        expect(taps.first.$1, greaterThan(0.01), reason: "heard in: $key");
      }
    });

    test("each analyser reads where it is", () {
      var g = played();
      for (var key in ["a", "fx", null]) {
        expect(g.waveOf(key, DeviceKind.scope), isNotNull, reason: "$key");
        expect(g.waveOf(key, DeviceKind.stereoImage), isNotNull,
            reason: "$key");
        expect(g.loudnessOf(key)?.shortTerm.isFinite, isTrue, reason: "$key");
        expect(g.pitchOf(key), isNotNull, reason: "tuner: $key");
      }
    });
  });
}

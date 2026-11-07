import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/device_screens.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_device_scope_test.dart is a device's display showing the real
// sound (Ken, 2026-11-08: "the Gate visual doesn't show real audio
// signal"; reverb, delay, the drives and the crusher had no analysis; and
// every display starts off, to save the work).

Float32List _tone(int n, double level) => Float32List.fromList([
      for (var i = 0; i < n; i++) level * math.sin(2 * math.pi * 440 * i / 48000)
    ]);

void main() {
  test("a gate's sound kept going in and coming out; shut on the quiet", () {
    const gate = MixDevice(DeviceKind.gate,
        values: {"threshold": -20, "release": 5, "hold": 1, "floor": -80});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix(devices: [gate]));
    var id = deviceIdAt(const [gate], 0);
    expect(g.scopeOf("a", id), isNull, reason: "kept only once asked");
    g.scope("a", id, true);
    const n = 4800;
    var l = Float32List(n), r = Float32List(n);
    // Loud, then quiet under its threshold.
    for (var (b, level) in [0.5, 0.5, 0.02, 0.02, 0.02].indexed) {
      g.begin(n);
      var (il, ir) = g.input("a", n);
      var x = _tone(n, level);
      il.setRange(0, n, x);
      ir.setRange(0, n, x);
      g.finish(l, r, n);
      if (b == 1) {
        var open = g.scopeOf("a", id)!;
        expect(open.own![0], closeTo(1, 0.01), reason: "open on the loud");
      }
    }
    var s = g.scopeOf("a", id)!;
    expect(s.inWave.length, DeviceScope.waveLength);
    expect(s.inPeaks.length, DeviceScope.historyLength);
    var last = s.inPeaks.length - 1;
    expect(s.inPeaks[last], closeTo(0.02, 0.003), reason: "the quiet going in");
    expect(s.outPeaks[last], lessThan(0.001), reason: "and none of it out");
    expect(s.own![0], lessThan(0.01), reason: "shut");
    // Four tenths of a second back: the loud, through.
    var loud = last - 80;
    expect(s.inPeaks[loud], closeTo(0.5, 0.02));
    expect(s.outPeaks[loud], closeTo(0.5, 0.02));
    g.scope("a", id, false);
    expect(g.scopeOf("a", id), isNull);
  });

  test("a vocoder reads each band's voice and carrier", () {
    const voc = MixDevice(DeviceKind.vocoder, values: {"bands": 12});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix(devices: [voc]));
    var id = deviceIdAt(const [voc], 0);
    g.scope("a", id, true);
    const n = 4800;
    var l = Float32List(n), r = Float32List(n);
    for (var b = 0; b < 3; b++) {
      g.begin(n);
      var (il, ir) = g.input("a", n);
      var x = _tone(n, 0.3);
      il.setRange(0, n, x);
      ir.setRange(0, n, x);
      g.finish(l, r, n);
    }
    var own = g.scopeOf("a", id)!.own!;
    expect(own, hasLength(24));
    expect(own.sublist(0, 12).reduce(math.max), greaterThan(0.01),
        reason: "a 440 Hz voice heard in its bands");
  });

  // The prototype's join between two devices: "Listen from here".
  test("a chain heard from a step: what comes after is not", () {
    const gain = MixDevice(DeviceKind.utility, values: {"gain": -20});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix(devices: [gain]));
    const n = 4800;
    double peakOut() {
      var l = Float32List(n), r = Float32List(n);
      g.begin(n);
      var (il, ir) = g.input("a", n);
      var x = _tone(n, 0.5);
      il.setRange(0, n, x);
      ir.setRange(0, n, x);
      g.finish(l, r, n);
      return l.map((v) => v.abs()).reduce(math.max);
    }

    peakOut();
    expect(peakOut(), closeTo(0.05, 0.01), reason: "twenty down, through it");
    g.listenAt["a"] = 0;
    peakOut();
    expect(peakOut(), closeTo(0.5, 0.02), reason: "heard before it");
    g.listenAt.remove("a");
    peakOut();
    expect(peakOut(), closeTo(0.05, 0.01));
  });

  group("its display", () {
    CanvasController make(FakeEngine engine) => CanvasController(
        CanvasDocument(
            frames: 600,
            frameRate: 60,
            audio: const AudioSettings(tempo: 120),
            elements: [
              AudioElement(const ElementBase(id: "m", name: "Vox"),
                  clip: const MediaClip(playlist: [
                    MediaSource(assetId: "vox.wav", name: "Vox", length: 4)
                  ], timed: true)),
            ]),
        audioEngine: engine);

    Future<void> show(WidgetTester tester, CanvasController c) async {
      tester.view.physicalSize = const Size(1400, 600);
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
                        builder: (context, _) => ChainPanel(
                            controller: c, height: 300, onResize: (_) {}))))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets("A|B: a second set to compare; a join's menu",
        (tester) async {
      var engine = FakeEngine({"vox.wav": 4});
      var c = make(engine);
      addTearDown(c.dispose);
      c.setDevicesOf("m", const [MixDevice(DeviceKind.reverb)]);
      var reverb = deviceIdAt(c.devicesOf("m"), 0);
      await tester.runAsync(() => c.audio.ready());
      c.openEffects("m");
      await show(tester, c);
      double size() => c.devicesOf("m").single.value("size");
      var a = size();
      var ab = find.byKey(ValueKey("deviceAB-${deviceKey(reverb)}"));
      await tester.ensureVisible(ab);
      await tester.tap(ab);
      await tester.pump();
      expect(c.showingB("m", reverb), isTrue);
      expect(size(), a, reason: "B starts as a copy of A");
      c.setDevicesOf("m", [c.devicesOf("m").single.withValue("size", 0.2)]);
      await tester.pump();
      await tester.tap(ab);
      await tester.pump();
      expect(size(), a, reason: "A again");
      await tester.tap(ab);
      await tester.pump();
      expect(size(), 0.2, reason: "and B as it was left");

      // The join before it: heard from there, and an analyser put there.
      var join = find.byKey(const ValueKey("junction-0"));
      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("junctionListen-0")));
      await tester.pump();
      await tester.pump();
      expect(engine.listened, {"m": 0});
      expect(c.listening, ("m", 0));
      await tester.tap(join);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("junctionAnalyser-0-scope")));
      await tester.pump();
      await tester.pump();
      expect(c.devicesOf("m").map((d) => d.kind),
          [DeviceKind.scope, DeviceKind.reverb],
          reason: "before the reverb, where it was asked for");
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("starts off, a still picture; Analyse shows the sound",
        (tester) async {
      var engine = FakeEngine({"vox.wav": 4});
      var c = make(engine);
      addTearDown(c.dispose);
      c.setDevicesOf("m", const [
        MixDevice(DeviceKind.reverb),
        MixDevice(DeviceKind.gate),
      ]);
      var reverb = deviceIdAt(c.devicesOf("m"), 0);
      await tester.runAsync(() => c.audio.ready());
      c.openEffects("m");
      await show(tester, c);
      var analyse = find.byKey(ValueKey("deviceAnalyse-$reverb"));
      expect(analyse, findsOneWidget);
      expect(c.analysing("m", reverb), isFalse, reason: "off to begin with");
      CustomPaint screen() => tester.widget<CustomPaint>(find
          .descendant(
              of: find.byKey(const ValueKey("deviceLevels-0")),
              matching: find.byType(CustomPaint))
          .first);
      expect(screen().painter, isA<DeviceScreenPainter>());
      await tester.pump(const Duration(seconds: 1));
      expect(engine.scoped, isEmpty, reason: "nothing kept while it is off");

      engine.heardScope = (
        inWave: Float32List(DeviceScope.waveLength),
        outWave: Float32List(DeviceScope.waveLength),
        inPeaks: Float32List(DeviceScope.historyLength)..fillRange(0, 600, 0.5),
        outPeaks:
            Float32List(DeviceScope.historyLength)..fillRange(0, 600, 0.25),
        own: null,
      );
      await tester.ensureVisible(analyse);
      await tester.tap(analyse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.analysing("m", reverb), isTrue);
      expect(screen().painter, isA<DeviceAnalysisPainter>());
      expect((screen().painter as DeviceAnalysisPainter).scope, isNotNull);
      expect(engine.scoped, contains("m|$reverb"));
      // Off again: the engine stops keeping it.
      await tester.tap(analyse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.scoped, isEmpty);
      expect(screen().painter, isA<DeviceScreenPainter>());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

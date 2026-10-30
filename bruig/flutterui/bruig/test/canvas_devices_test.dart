import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_devices_test.dart is the devices beside the reverb and the delay --
// gate, auto filter, chorus, flanger, phaser, auto pan, saturator,
// overdrive, bit crusher, utility -- each doing to a sound what it says;
// and a channel's own chain of them, saved, heard, and put on from the
// effects.

/// sine is [n] samples of a sine at [hz] and [level], on both sides.
(Float32List, Float32List) sine(double hz, int n, {double level = 0.5}) {
  var l = Float32List(n), r = Float32List(n);
  for (var i = 0; i < n; i++) {
    l[i] = r[i] = level * math.sin(2 * math.pi * hz * i / mixRate);
  }
  return (l, r);
}

double rms(Float32List x, [int from = 0]) {
  var s = 0.0;
  for (var i = from; i < x.length; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / math.max(1, x.length - from));
}

/// run puts [x] through device [d], a block at a time.
(Float32List, Float32List) run(MixDevice d, (Float32List, Float32List) x) {
  var p = DeviceProcessor.of(d)!;
  var (l, r) = x;
  for (var at = 0; at < l.length; at += 512) {
    var n = math.min(512, l.length - at);
    var bl = Float32List.sublistView(l, at, at + n);
    var br = Float32List.sublistView(r, at, at + n);
    p.process(bl, br, n);
  }
  return (l, r);
}

void main() {
  group("each device", () {
    test("every kind runs, on and saved", () {
      for (var kind in DeviceKind.values) {
        var d = MixDevice(kind);
        expect(DeviceProcessor.of(d), isNotNull, reason: kind.name);
        expect(MixDevice.fromJson(d.toJson()), d, reason: kind.name);
        var (l, _) = run(d, sine(440, 4800));
        expect(l.every((v) => v.isFinite), isTrue, reason: kind.name);
      }
    });

    test("a gate shuts out what is under its threshold", () {
      var gate = const MixDevice(DeviceKind.gate, values: {"threshold": -20});
      var (quiet, _) = run(gate, sine(220, 9600, level: 0.01));
      var (loud, _) = run(gate, sine(220, 9600, level: 0.5));
      expect(rms(quiet, 4800), lessThan(1e-4), reason: "down to its floor");
      expect(rms(loud, 4800), greaterThan(0.3));
    });

    test("an auto filter's low-pass takes the highs, keeps the lows", () {
      var f = const MixDevice(DeviceKind.autoFilter, values: {"freq": 300});
      var (low, _) = run(f, sine(100, 9600));
      var (high, _) = run(f, sine(5000, 9600));
      expect(rms(low, 2400), greaterThan(0.3));
      expect(rms(high, 2400), lessThan(0.02));
      var hp = const MixDevice(DeviceKind.autoFilter,
          values: {"freq": 3000, "type": 1});
      var (lowHp, _) = run(hp, sine(100, 9600));
      expect(rms(lowHp, 2400), lessThan(0.02),
          reason: "a high-pass the other way");
    });

    test("drive makes a quiet sine louder and squarer, within one", () {
      var (l, _) = run(
          const MixDevice(DeviceKind.saturator, values: {"drive": 24}),
          sine(220, 4800, level: 0.2));
      expect(rms(l), greaterThan(0.5));
      expect(l.every((v) => v.abs() <= 1.0001), isTrue);
      var (o, _) = run(
          const MixDevice(DeviceKind.overdrive,
              values: {"drive": 1, "output": 0, "tone": 12000}),
          sine(220, 4800, level: 0.2));
      expect(rms(o, 480), greaterThan(0.5));
    });

    test("a bit crusher at one bit leaves three levels", () {
      var (l, _) = run(
          const MixDevice(DeviceKind.bitCrusher, values: {"bits": 1}),
          sine(220, 4800));
      expect({for (var v in l) (v == 0 ? 0.0 : v).toStringAsFixed(3)}.length,
          lessThanOrEqualTo(3));
    });

    test("utility: gain, mono and a side upside down", () {
      var (l, r) = run(
          const MixDevice(DeviceKind.utility, values: {"gain": -6}),
          sine(220, 480));
      expect(rms(l), closeTo(0.5 / math.sqrt2 * dbToGain(-6), 0.01));
      // Left and right apart; mono, they are the same.
      var x = (Float32List.fromList([1, 0.5]), Float32List.fromList([0, 0.5]));
      run(const MixDevice(DeviceKind.utility, values: {"mono": 1}), x);
      expect(x.$1, x.$2);
      var y = (Float32List.fromList([0.5]), Float32List.fromList([0.5]));
      run(const MixDevice(DeviceKind.utility, values: {"invert": 1}), y);
      expect((y.$1[0], y.$2[0]), (-0.5, 0.5));
      expect(r.length, 480);
    });

    test("auto pan moves a sound from side to side", () {
      var (l, r) = run(
          const MixDevice(DeviceKind.autoPan, values: {"amount": 1, "rate": 2}),
          sine(440, mixRate));
      // A quarter of a turn in, the LFO at its top: the left turned down.
      var q = mixRate ~/ 8;
      var lq = rms(Float32List.sublistView(l, q - 200, q + 200));
      var rq = rms(Float32List.sublistView(r, q - 200, q + 200));
      expect(lq, lessThan(rq * 0.2));
    });

    test("chorus, flanger and phaser change a sound but keep it", () {
      for (var kind in [
        DeviceKind.chorus,
        DeviceKind.flanger,
        DeviceKind.phaser
      ]) {
        var (dry, _) = sine(440, 9600);
        var (wet, _) = run(MixDevice(kind), sine(440, 9600));
        var diff = 0.0;
        for (var i = 2400; i < 9600; i++) {
          diff += (wet[i] - dry[i]).abs();
        }
        expect(diff / 7200, greaterThan(0.01),
            reason: "${kind.name} changed it");
        expect(rms(wet, 2400), inInclusiveRange(0.1, 0.9), reason: kind.name);
      }
    });

    test("a choice turns in whole steps, and reads as its name", () {
      var d = const MixDevice(DeviceKind.autoFilter).withValue("type", 1.4);
      expect(d.value("type"), 1);
      expect(DeviceKind.autoFilter.param("type").reading(1), "High-pass");
      expect(DeviceKind.utility.param("gain").reading(-6), "−6.0 dB");
    });
  });

  group("a channel's chain", () {
    test("is saved, and heard: a gate on a channel shuts out a quiet one", () {
      var mix = const ChannelMix(devices: [
        MixDevice(DeviceKind.gate, values: {"threshold": -20})
      ]);
      expect(ChannelMix.fromJson(mix.toJson()).devices.single.kind,
          DeviceKind.gate);
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setChannel("a", mix);
      var out = Float32List(512);
      for (var b = 0; b < 20; b++) {
        g.begin(512);
        var (l, r) = g.input("a", 512);
        l.fillRange(0, 512, 0.01);
        r.fillRange(0, 512, 0.01);
        out = Float32List(512);
        g.finish(out, Float32List(512), 512);
      }
      expect(out.last.abs(), lessThan(1e-4));
    });

    test("the master has its own chain too, before its EQ and glue", () {
      var c =
          CanvasController(const CanvasDocument(), audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.setDevicesOf(mixerMasterKey, const [MixDevice(DeviceKind.saturator)]);
      expect(c.document.masterMix.devices.single.kind, DeviceKind.saturator);
      var back = CanvasDocument.fromJson(c.document.toJson());
      expect(back.masterMix.devices.single.kind, DeviceKind.saturator);
      // Heard: a gate on the master shuts out a quiet mix.
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false, devices: [
          MixDevice(DeviceKind.gate, values: {"threshold": -20})
        ]))
        ..setChannel("a", const ChannelMix());
      var out = Float32List(512);
      for (var b = 0; b < 20; b++) {
        g.begin(512);
        var (l, r) = g.input("a", 512);
        l.fillRange(0, 512, 0.01);
        r.fillRange(0, 512, 0.01);
        out = Float32List(512);
        g.finish(out, Float32List(512), 512);
      }
      expect(out.last.abs(), lessThan(1e-4));
    });

    testWidgets(
        "devices are put on a channel from its effects, and opened "
        "from its strip", (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            AudioElement(const ElementBase(id: "a", name: "Guitar"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]),
          audioEngine: FakeEngine({"t": 2}));
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
                                  height: 360,
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
      var add = find.byKey(const ValueKey("addDevice-chorus"));
      // Down the list of kinds to it: they are built as they come into view.
      await tester.scrollUntilVisible(add, 40,
          scrollable: find.descendant(
              of: find.byKey(const ValueKey("addDeviceSlot")),
              matching: find.byType(Scrollable)));
      await tester.pump();
      await tester.tap(add);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.devicesOf("a").single.kind, DeviceKind.chorus);
      expect(find.byKey(const ValueKey("device-dev0")), findsOneWidget);
      // Its slot on the channel's strip opens it.
      var slot = find.descendant(
          of: find.byKey(const ValueKey("strip-a")),
          matching: find.byKey(const ValueKey("chanDevice-0")));
      expect(slot, findsOneWidget);
      c.effectsOpen = false;
      await tester.pump();
      await tester.tap(slot);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.effectsOpen, isTrue);
      expect(c.effectsFocus, "dev0");
      // Taken out: from its header's ×, which shows on the dark header --
      c.effectsOpen = true;
      await tester.pump(const Duration(milliseconds: 600));
      var remove = find.byKey(const ValueKey("deviceRemove-0"));
      var icon = tester.widget<Icon>(
          find.descendant(of: remove, matching: find.byType(Icon)));
      expect(icon.color!.computeLuminance(), greaterThan(0.5),
          reason: "light, on the dark header bar");
      await tester.tap(remove);
      await tester.pump();
      expect(c.devicesOf("a"), isEmpty);
      c.undo();
      expect(c.devicesOf("a"), hasLength(1));
      await tester.pump();
      // -- or by a right-click on its slot in the mixer.
      await tester.tap(
          find.descendant(
              of: find.byKey(const ValueKey("strip-a")),
              matching: find.byKey(const ValueKey("chanDevice-0"))),
          buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(c.devicesOf("a"), isEmpty);
      c.undo();
      expect(c.devicesOf("a"), hasLength(1), reason: "one change to undo");
      c.undo();
      expect(c.devicesOf("a"), isEmpty, reason: "one change to undo");
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}

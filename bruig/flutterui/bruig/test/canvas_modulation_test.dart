import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_modulation_test.dart is an LFO moving other devices' knobs: in a
// sound's chain, block by block in the engine; in an element's motion, at
// the moment asked for; and on the cards, with a pink ring on what it moves.

/// lfo moves device [device]'s [param] at [rate] in [shape].
MixDevice lfo(String device, String param,
        {double rate = 1, int shape = 2, double depth = 0.5, bool on = true}) =>
    MixDevice(DeviceKind.lfo,
        id: "d1",
        on: on,
        values: {"rate": rate, "shape": shape.toDouble()},
        mods: [ModTarget(device, param, depth)]);

const MixDevice utility = MixDevice(DeviceKind.utility, id: "d0");

/// run is a second of a steady 0.01 through [strip], block by block.
Float32List run(StripProcessor strip, {int seconds = 1}) {
  var total = mixRate * seconds;
  var out = Float32List(total);
  for (var at = 0; at < total; at += 480) {
    var l = Float32List(480)..fillRange(0, 480, 0.01);
    var r = Float32List.fromList(l);
    strip.process(l, r, 480);
    out.setRange(at, at + 480, l);
  }
  return out;
}

void main() {
  group("the model", () {
    test("what an LFO moves is kept, with the device", () {
      var d = lfo("d0", "gain", depth: -0.25);
      var back = MixDevice.fromJson(d.toJson())!;
      expect(back.mods, [const ModTarget("d0", "gain", -0.25)]);
      expect(back.switched(false).mods, back.mods);
      expect(back.withValue("rate", 2).mods, back.mods);
      var m = const MotionDevice(MotionDeviceKind.lfo,
          mods: [ModTarget("m0", "amount", 0.3)]);
      expect(MotionDevice.fromJson(m.toJson())!.mods, m.mods);
    });

    test("its shapes, from minus one to one", () {
      expect(lfoValue(0, 0.25), closeTo(1, 1e-9), reason: "sine at its top");
      expect(lfoValue(1, 0.5), closeTo(1, 1e-9), reason: "triangle's peak");
      expect(lfoValue(2, 0.25), 1);
      expect(lfoValue(2, 0.75), -1);
      expect(lfoValue(3, 2.1), lfoValue(3, 2.9), reason: "held a cycle");
      expect(lfoValue(3, 2.1), isNot(lfoValue(3, 3.1)));
      for (var i = 0; i < 50; i++) {
        expect(lfoValue(3, i.toDouble()).abs(), lessThanOrEqualTo(1));
      }
    });

    test("a moved knob stays on its knob", () {
      var p = DeviceKind.utility.param("gain");
      expect(modulated(p, 0, 0.5), 18, reason: "half its travel either way");
      expect(modulated(p, 30, 1), 36, reason: "no further than its end");
    });
  });

  group("in the engine", () {
    test("a square LFO turns a Utility's gain up and down", () {
      var strip = StripProcessor(
          ChannelMix(devices: [utility, lfo("d0", "gain", rate: 1)]));
      var out = run(strip);
      // Up 18 dB for half a second, down 18 for the other half.
      expect(out[mixRate ~/ 4], closeTo(0.01 * dbToGain(18), 1e-4));
      expect(out[mixRate * 3 ~/ 4], closeTo(0.01 * dbToGain(-18), 1e-4));
    });

    test("switched off, the knob goes back to where it is set", () {
      var moving = StripProcessor(
          ChannelMix(devices: [utility, lfo("d0", "gain", rate: 1)]));
      run(moving);
      var still = StripProcessor(
          ChannelMix(devices: [utility, lfo("d0", "gain", rate: 1, on: false)]),
          carry: moving);
      var out = run(still);
      expect(out[mixRate ~/ 4], closeTo(0.01, 1e-6));
    });
  });

  group("in motion", () {
    test("an LFO moves a move's knob at the moment asked for", () {
      var d = CanvasDocument(frames: 240, frameRate: 24, elements: [
        ShapeElement(const ElementBase(
            id: "a",
            width: 20,
            height: 20,
            motion: ElementMotion(devices: [
              // Up and down 30, at once a second...
              MotionDevice(MotionDeviceKind.oscillate,
                  id: "m0", values: {"rate": 1, "amount": 30, "moves": 0}),
              // ...its amount moved by a square LFO, up half its travel for
              // half a second and down after.
              MotionDevice(MotionDeviceKind.lfo,
                  id: "m1",
                  values: {"rate": 1, "shape": 2},
                  mods: [ModTarget("m0", "amount", 0.25)]),
            ]))),
      ]);
      var e = d.elementById("a")!;
      // A quarter of a second: the oscillator's top, its amount 30 + 50.
      expect(poseWithMotion(e, 6, d).dy, closeTo(80, 1e-6));
      // A second and a quarter: the top again, the square in its first half
      // again.
      expect(poseWithMotion(e, 30, d).dy, closeTo(80, 1e-6));
    });

    test("an LFO moves a look", () {
      var glow = const MotionDevice(MotionDeviceKind.glow,
          id: "m0", values: {"radius": 10});
      var chain = [
        glow,
        const MotionDevice(MotionDeviceKind.lfo,
            id: "m1",
            values: {"rate": 1, "shape": 2},
            mods: [ModTarget("m0", "radius", 0.5)]),
      ];
      // 10, and half of half its travel (0 to 60) more.
      expect(motionModulated(glow, chain, 0.25).value("radius"), 25);
      expect(motionModulated(glow, chain, 0.75).value("radius"), 0);
      expect(motionModulated(glow, const [], 0.25), glow);
    });
  });

  group("the cards", () {
    for (var scale in [1.0, 1.5]) {
      testWidgets("an LFO is given a knob to move; it wears a ring, at $scale",
          (tester) async {
        var c = CanvasController(
            CanvasDocument(frames: 100, elements: [
              AudioElement(const ElementBase(id: "a", name: "Pad"),
                  clip: const MediaClip(
                      playlist: [MediaSource(assetId: "t", length: 2)],
                      timed: true)),
            ]),
            audioEngine: FakeEngine({"t": 2}));
        addTearDown(c.dispose);
        c.setDevicesOf("a", [
          const MixDevice(DeviceKind.autoFilter),
          const MixDevice(DeviceKind.lfo),
        ]);
        c.openEffects("a");
        tester.view.physicalSize = const Size(2000, 900);
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
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
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
        expect(find.byKey(const ValueKey("knobModulated")), findsNothing);
        var add = find.byKey(const ValueKey("modAdd"));
        await tester.ensureVisible(add);
        await tester.pump();
        await tester.tap(add);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text("Auto Filter · Frequency").last);
        await tester.pump(const Duration(milliseconds: 300));
        var mods = c.devicesOf("a")[1].mods;
        expect(mods, [ModTarget(c.devicesOf("a")[0].id, "freq", 0.5)]);
        expect(find.byKey(const ValueKey("knobModulated")), findsOneWidget,
            reason: "the filter's frequency knob");
        expect(find.byKey(const ValueKey("modTarget-0")), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("modRemove-0")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.devicesOf("a")[1].mods, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}

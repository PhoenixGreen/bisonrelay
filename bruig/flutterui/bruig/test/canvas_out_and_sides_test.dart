import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_out_and_sides_test.dart is the chain prototype's Out trim at the
// foot of every effect, and its Works on (mid or side) on a strip's EQ and
// compressor as well as on a device (Ken, 2026-11-08, the 8 prototype
// comparisons, item 7).

/// _through is what [mix] makes of a steady [left]/[right] on a channel.
(double, double) _through(ChannelMix mix, double left, double right) {
  var g = MixGraph()
    ..setMaster(const MasterMix(limiter: false))
    ..setChannel("a", mix);
  const n = 480;
  var l = Float32List(n), r = Float32List(n);
  g.begin(n);
  var (il, ir) = g.input("a", n);
  for (var i = 0; i < n; i++) {
    il[i] = left;
    ir[i] = right;
  }
  g.finish(l, r, n);
  return (l[400], r[400]);
}

void main() {
  test("which devices have an Out: those with no level of their own", () {
    expect(DeviceKind.gate.hasOut, isTrue);
    expect(DeviceKind.chorus.hasOut, isTrue);
    expect(DeviceKind.saturator.hasOut, isFalse, reason: "has its Output");
    expect(DeviceKind.split.hasOut, isFalse);
  });

  test("a gate's Out of -6 dB halves what it lets through", () {
    const open = {"threshold": -80.0, "floor": -80.0};
    var (plain, _) = _through(
        const ChannelMix(devices: [MixDevice(DeviceKind.gate, values: open)]),
        0.2,
        0.2);
    var (trimmed, _) = _through(
        const ChannelMix(devices: [
          MixDevice(DeviceKind.gate, values: {...open, "out": -6.0206})
        ]),
        0.2,
        0.2);
    expect(plain, closeTo(0.2, 0.01));
    expect(trimmed, closeTo(plain / 2, 0.005));
    expect(
        MixDevice.fromJson(
                const MixDevice(DeviceKind.gate, values: {"out": -3}).toJson())!
            .value("out"),
        -3,
        reason: "kept with the canvas");
  });

  test("a device in a split's branch has its Out too", () {
    MixDevice split(double out) => MixDevice(DeviceKind.split, branches: [
          SplitBranch(devices: [
            MixDevice(DeviceKind.gate,
                values: {"threshold": -80.0, "floor": -80.0, "out": out})
          ]),
        ]);
    var (plain, _) = _through(ChannelMix(devices: [split(0)]), 0.2, 0.2);
    var (trimmed, _) =
        _through(ChannelMix(devices: [split(-6.0206)]), 0.2, 0.2);
    expect(plain, greaterThan(0.05));
    expect(trimmed, closeTo(plain / 2, 0.005));
  });

  test("an EQ on the sides leaves a centred sound as it was", () {
    const boost = Eq(on: true, gainDb: 12);
    var (l, r) = _through(const ChannelMix(eq: boost), 0.1, 0.1);
    expect(l, closeTo(0.4, 0.02), reason: "on both sides, 12 dB louder");
    var (sl, sr) =
        _through(ChannelMix(eq: boost.copyWith(stereo: 2)), 0.1, 0.1);
    expect(sl, closeTo(0.1, 0.002));
    expect(sr, closeTo(0.1, 0.002));
    // A sound only on the left: mid kept, the side made 4x.
    var (ol, or) = _through(ChannelMix(eq: boost.copyWith(stereo: 2)), 0.1, 0);
    expect(ol, closeTo(0.05 + 0.2, 0.01));
    expect(or, closeTo(0.05 - 0.2, 0.01));
    expect(Eq.fromJson(boost.copyWith(stereo: 1).toJson()).stereo, 1);
  });

  test("a compressor on the middle leaves the sides alone", () {
    const squash = Dynamics(on: true, threshold: -40, ratio: 20);
    // Opposite sides: all side, no middle -- nothing for it to squash.
    var (l, r) =
        _through(ChannelMix(comp: squash.copyWith(stereo: 1)), 0.3, -0.3);
    expect(l, closeTo(0.3, 0.005));
    expect(r, closeTo(-0.3, 0.005));
    var (wl, _) = _through(const ChannelMix(comp: squash), 0.3, -0.3);
    expect(wl, lessThan(0.25), reason: "on both, it squashes them");
  });

  testWidgets("the Out knob, and Works on in the EQ's and comp's ⋯",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true,
                  mix: ChannelMix(
                      eq: Eq(on: true),
                      comp: Dynamics(on: true),
                      devices: [MixDevice(DeviceKind.gate, id: "d0")]))),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    c.openEffects("m");
    tester.view.physicalSize = const Size(2400, 700);
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
                          controller: c, height: 420, onResize: (_) {}))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey("device-0-out")), findsOneWidget,
        reason: "the gate's Out trim");

    Future<void> pick(String more, String sub, String item) async {
      await tester.ensureVisible(find.byKey(ValueKey(more)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(more)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(sub)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(item)));
      await tester.pump();
      await tester.pump();
    }

    await pick("deviceMore-eq", "eqStereo", "eqStereo-2");
    expect(c.timelineChannels.single.mix.eq.stereo, 2);
    await pick("deviceMore-comp", "compStereo", "compStereo-1");
    expect(c.timelineChannels.single.mix.comp.stereo, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });
}

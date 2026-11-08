import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_return_chain_test.dart is a return's chain laid out and run as a
// channel's (the chain prototype, Ken's comparison 8, 2026-11-08): its EQ
// and compressor among its devices, moved as a channel's are, and the
// return run by a channel's strip -- retuned, not rebuilt, when a knob
// turns, so a reverb's tail carries on.

const _send = ChannelMix(sends: {"fx": 0});

/// _play runs [blocks] blocks of [level] into channel "a", sent whole to
/// return "fx", and gives the last block's left side.
Float32List _play(MixGraph g, double level, {int blocks = 1}) {
  const n = 480;
  var l = Float32List(n), r = Float32List(n);
  for (var b = 0; b < blocks; b++) {
    g.begin(n);
    var (il, ir) = g.input("a", n);
    il.fillRange(0, n, level);
    ir.fillRange(0, n, level);
    g.finish(l, r, n);
  }
  return l;
}

MixGraph _graph(ReturnChannel fx) => MixGraph()
  ..setMaster(const MasterMix(limiter: false))
  // Sent before the fader, the channel's own turned right down: only what
  // the return makes of it is heard.
  ..setReturns([fx.copyWith(pre: true)])
  ..setChannel("a", _send.copyWith(gainDb: -120));

void main() {
  test("a return's chain has its EQ and compressor, and they move", () {
    var c = CanvasController(CanvasDocument(frames: 10, returns: const [
      ReturnChannel("fx",
          name: "Room", devices: [MixDevice(DeviceKind.reverb, id: "rv")]),
    ]));
    addTearDown(c.dispose);
    expect(c.chainOf("fx"), ["rv", chainEq, chainComp]);
    c.moveDevice("fx", chainEq, -1);
    expect(c.chainOf("fx"), [chainEq, "rv", chainComp]);
    expect(c.document.returns.single.mix.order, [chainEq, "rv", chainComp],
        reason: "kept with the canvas");
    c.moveDevice("fx", chainComp, -2);
    expect(c.chainOf("fx"), [chainComp, chainEq, "rv"]);
    expect(c.document.returns.single.mix.compFirst, isTrue);
    c.undo();
    expect(c.chainOf("fx"), [chainEq, "rv", chainComp], reason: "one step");
  });

  test("its EQ runs where it was put: before a gate, it opens it", () {
    // 0.05 is −26 dB, under the gate's −20; the EQ's 12 dB lifts it over.
    const gate =
        MixDevice(DeviceKind.gate, id: "g", values: {"threshold": -20});
    const fx = ReturnChannel("fx",
        name: "Gated",
        devices: [gate],
        mix: ChannelMix(eq: Eq(on: true, gainDb: 12)));
    var after = _play(_graph(fx), 0.05, blocks: 10);
    expect(after[400].abs(), lessThan(0.01), reason: "gate first: shut");
    var before = _play(
        _graph(fx.copyWith(mix: fx.mix.copyWith(order: [chainEq, "g"]))), 0.05,
        blocks: 10);
    expect(before[400], closeTo(0.2, 0.02), reason: "EQ first: let through");
  });

  test("a knob turned on its reverb does not cut the tail", () {
    const fx = ReturnChannel("fx",
        name: "Room", devices: [MixDevice(DeviceKind.reverb, id: "rv")]);
    var g = _graph(fx);
    _play(g, 0.3, blocks: 20);
    g.setReturns([
      fx.copyWith(pre: true, devices: [
        const MixDevice(DeviceKind.reverb, id: "rv", values: {"damping": 0.6})
      ])
    ]);
    var tail = _play(g, 0);
    var sum = 0.0;
    for (var v in tail) {
      sum += v * v;
    }
    expect(sum, greaterThan(1e-4), reason: "still ringing after the turn");
  });

  test("an LFO set to Sync on a return or the master follows the tempo", () {
    const lfo = MixDevice(DeviceKind.lfo, id: "l", values: {"sync": 1});
    var doc = const CanvasDocument(
        audio: AudioSettings(tempo: 90),
        masterMix: MasterMix(devices: [lfo]),
        returns: [
          ReturnChannel("fx", name: "Room", devices: [lfo])
        ]);
    var want = lfoRate(lfo.value, bpm: 90, beatsPerBar: 4);
    expect(doc.syncedReturns.single.devices.single.value("rate"), want);
    expect(doc.syncedMaster.devices.single.value("rate"), want);
    expect(
        doc
            .copyWith(audio: const AudioSettings(tempo: 180))
            .syncedMaster
            .devices
            .single
            .value("rate"),
        isNot(want),
        reason: "another tempo, another rate");
  });

  test("its compressor's reduction reads, as a channel's does", () {
    const fx = ReturnChannel("fx",
        name: "Squashed",
        mix: ChannelMix(comp: Dynamics(on: true, threshold: -30, ratio: 8)));
    var g = _graph(fx);
    _play(g, 0.5, blocks: 20);
    expect(g.reductionOf("fx"), greaterThan(3));
  });

  testWidgets("its Chain: Effects, a join between each, its EQ moved first",
      (tester) async {
    var c = CanvasController(CanvasDocument(frames: 10, returns: const [
      ReturnChannel("fx",
          name: "Room", devices: [MixDevice(DeviceKind.reverb, id: "rv")]),
    ]));
    addTearDown(c.dispose);
    c.openEffects("fx");
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
    expect(find.byKey(const ValueKey("chainZone-Effects")), findsOneWidget);
    for (var i = 0; i <= 3; i++) {
      expect(find.byKey(ValueKey("junction-$i")), findsOneWidget,
          reason: "in, after the reverb, the EQ and the compressor");
    }
    double x(String id) =>
        tester.getTopLeft(find.byKey(ValueKey("deviceMore-$id"))).dx;
    expect(x("eq"), greaterThan(x(deviceKey("rv"))));
    // From its own ⋯, along the chain as a channel's EQ goes.
    await tester.tap(find.byKey(const ValueKey("deviceMore-eq")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("deviceMoveLeft-eq")));
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.chainOf("fx"), [chainEq, "rv", chainComp]);
    // The menu's press lands as it shuts, a frame on.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(x("eq"), lessThan(x(deviceKey("rv"))), reason: "drawn as it runs");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });
}

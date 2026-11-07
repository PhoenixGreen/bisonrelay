import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:bruig/plugin_system/canvas/model/modulation.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_device_extras_test.dart is what the prototype's cards had that ours
// did not (Ken, 2026-11-08, "continue with the Still missing"): a drive run
// oversampled, any device on only the middle or the sides, a sidechain from
// the ⋯ menu, a preset on the bar, a knob's lane and a controller learnt
// for it, the Output card's sends and where it goes, and a return analysed
// and listened to as a channel is.

Float32List _sine(int n, double hz, double level) => Float32List.fromList([
      for (var i = 0; i < n; i++) level * math.sin(2 * math.pi * hz * i / 48000)
    ]);

/// _at is how loud [x] is at [hz]: a single bin of a Fourier transform.
double _at(Float32List x, double hz) {
  var re = 0.0, im = 0.0;
  for (var i = 0; i < x.length; i++) {
    var w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (x.length - 1));
    re += x[i] * w * math.cos(2 * math.pi * hz * i / 48000);
    im += x[i] * w * math.sin(2 * math.pi * hz * i / 48000);
  }
  return math.sqrt(re * re + im * im) / x.length;
}

void main() {
  test("oversampled, a hard drive's harmonics fold back far less", () {
    // 15 kHz driven hard: its third harmonic, 45 kHz, folds to 3 kHz.
    double folded(int factor) {
      var d = MixDevice(DeviceKind.saturator,
          values: {"drive": 30, "type": 2, "oversample": factor.toDouble()});
      var s = Saturator(d);
      const n = 9600;
      var l = _sine(n, 15000, 0.5), r = _sine(n, 15000, 0.5);
      s.process(l, r, n);
      return _at(Float32List.sublistView(l, 2400), 3000);
    }

    // Clipped hard, a square wave: its 13th harmonic still folds onto
    // 3 kHz at four times, but at a third of the 3rd's strength or less.
    var plain = folded(1), four = folded(4);
    expect(four, lessThan(plain / 3),
        reason: "${plain.toStringAsFixed(5)} → ${four.toStringAsFixed(5)}");
  });

  test("on the side only, what both sides share passes by", () {
    // A gain of a quarter (−12 dB, undriven) on the sides alone.
    const quiet = MixDevice(DeviceKind.saturator,
        values: {"drive": 0, "output": -12, "type": 2, "stereo": 2});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setChannel("a", const ChannelMix(devices: [quiet]));
    const n = 480;
    var l = Float32List(n), r = Float32List(n);
    g.begin(n);
    var (il, ir) = g.input("a", n);
    for (var i = 0; i < n; i++) {
      il[i] = 0.1;
      ir[i] = 0;
    }
    g.finish(l, r, n);
    // Mid 0.05 kept, side 0.05 down to 0.0126: left 0.0626, right 0.0374.
    expect(l[100], closeTo(0.05 + 0.05 * 0.251, 0.002));
    expect(r[100], closeTo(0.05 - 0.05 * 0.251, 0.002));
    expect(MixDevice.fromJson(quiet.toJson())!.value("stereo"), 2,
        reason: "kept with the canvas");
  });

  test("a return's devices analysed and listened to, as a channel's", () {
    const cut = MixDevice(DeviceKind.utility, id: "d0", values: {"gain": -20});
    var g = MixGraph()
      ..setMaster(const MasterMix(limiter: false))
      ..setReturns([
        const ReturnChannel("fx",
            name: "Room", devices: [cut], mix: ChannelMix())
      ])
      // Into the return alone, as a group bus.
      ..setChannel("a", const ChannelMix(output: "fx"));
    g.scope("fx", "d0", true);
    const n = 4800;
    double run() {
      var l = Float32List(n), r = Float32List(n);
      g.begin(n);
      var (il, ir) = g.input("a", n);
      var x = _sine(n, 440, 0.5);
      il.setRange(0, n, x);
      ir.setRange(0, n, x);
      g.finish(l, r, n);
      return l.map((v) => v.abs()).reduce(math.max);
    }

    run();
    var through = run();
    var s = g.scopeOf("fx", "d0")!;
    expect(s.inPeaks.last, closeTo(0.5, 0.05));
    expect(s.outPeaks.last, closeTo(0.05, 0.01));
    g.listenAt["fx"] = 0;
    run();
    expect(run(), greaterThan(through * 5), reason: "heard before the cut");
  });

  test("a controller's knob learnt, then turning the setting", () {
    var c = CanvasController(
        CanvasDocument(frames: 100, elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true,
                  mix: ChannelMix(devices: [
                    MixDevice(DeviceKind.reverb, id: "d0"),
                  ]))),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    var target =
        AutomationTarget.deviceSetting("d0", DeviceKind.reverb, "size").id;
    c.learnControl("m", target);
    c.midiCc(21, 0.3);
    expect(c.learning, isNull);
    expect(c.controlOf("m", target), 21);
    c.midiCc(21, 1);
    expect(c.devicesOf("m").single.value("size"), 1);
    c.midiCc(21, 0);
    expect(c.devicesOf("m").single.value("size"), 0);
    var back = AudioSettings.fromJson(c.document.audio.toJson());
    expect(back.controls, [ControlLink(21, "m", target)]);
    c.forgetControl("m", target);
    expect(c.controlOf("m", target), isNull);
    // Its lane, shown on the timeline.
    c.showLaneFor("m", target);
    expect(c.automationShown, contains("m"));
  });

  testWidgets("the bar's preset, the ⋯ menu's extras, the Output card",
      (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 100, returns: const [
          ReturnChannel("fx", name: "Room", mix: ChannelMix()),
        ], elements: [
          AudioElement(const ElementBase(id: "m", name: "Music"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true,
                  mix: ChannelMix(devices: [
                    MixDevice(DeviceKind.saturator, id: "d0"),
                    MixDevice(DeviceKind.gate, id: "d1"),
                  ]))),
          AudioElement(const ElementBase(id: "k", name: "Kick"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 8)],
                  timed: true)),
        ]),
        audioEngine: FakeEngine({"t": 8}));
    addTearDown(c.dispose);
    c.openEffects("m");
    tester.view.physicalSize = const Size(1800, 600);
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
                          controller: c, height: 360, onResize: (_) {}))))),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey("devicePreset-1")), findsOneWidget,
        reason: "the gate's; the saturator's long name leaves it no room");
    expect(find.text("Default"), findsWidgets);

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

    // The saturator oversampled, and on the middle only.
    await pick("deviceMore-${deviceKey("d0")}", "deviceOversample-0",
        "deviceOversample-0-4");
    expect(c.devicesOf("m")[0].value("oversample"), 4);
    await pick(
        "deviceMore-${deviceKey("d0")}", "deviceStereo-0", "deviceStereo-0-1");
    expect(c.devicesOf("m")[0].value("stereo"), 1);
    // The gate listening to the kick.
    await pick("deviceMore-${deviceKey("d1")}", "deviceListens-1",
        "deviceListens-1-k");
    expect(c.devicesOf("m")[1].source, "k");

    // The Output: a send to the return, and where it goes.
    expect(find.byKey(const ValueKey("outputSend-fx")), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey("outputTo"))).data,
        "Master");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
  });

  // Ken, 2026-11-08: "I tried setting up the attack knob from the
  // instrument by right clicking but nothing happened."
  group("a macro turning the instrument", () {
    CanvasController make(FakeEngine engine,
            {List<MixDevice> devices = const []}) =>
        CanvasController(
            CanvasDocument(frames: 100, elements: [
              AudioElement(const ElementBase(id: "p", name: "Keys"),
                  clip:
                      MediaClip(timed: true, mix: ChannelMix(devices: devices)),
                  instrument: const InstrumentPart()),
            ]),
            audioEngine: engine);

    test("played and rendered as the macro has it; its own setting kept",
        () async {
      var engine = FakeEngine({});
      var c = make(engine, devices: [
        const MixDevice(DeviceKind.macro, id: "d0", values: {
          "m1": 1
        }, mods: [
          ModTarget(instrumentTarget, "attack", 0.5, 0),
        ]),
      ]);
      addTearDown(c.dispose);
      var e = c.document.elementById("p") as AudioElement;
      var own = e.instrument!.shape.attack;
      var turned = c.macroedPart("p", e.instrument!).shape.attack;
      expect(turned, greaterThan(own * 10),
          reason: "half its travel up, on a log scale");
      await c.audio.ready();
      c.noteOn(e, 60);
      expect(engine.parts.last.shape.attack, closeTo(turned, 1e-9));
      expect(
          (c.document.elementById("p") as AudioElement)
              .instrument!
              .shape
              .attack,
          own,
          reason: "the part's own setting stays where it was set");
    });

    testWidgets("its knob's right-click gives it to a macro", (tester) async {
      var c = make(FakeEngine({}));
      addTearDown(c.dispose);
      c.openEffects("p");
      tester.view.physicalSize = const Size(2000, 600);
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
      var attack = find.byKey(const ValueKey("instrumentCardAttack"));
      await tester.ensureVisible(attack);
      await tester.pump();
      await tester.tap(attack, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("knobMenu-0")));
      await tester.pump();
      await tester.pump();
      var macro =
          c.devicesOf("p").firstWhere((d) => d.kind == DeviceKind.macro);
      expect(macro.mods, [const ModTarget(instrumentTarget, "attack", 0.5, 0)],
          reason: "no macros yet: added, Macro 1 turning it");
      // Its macro's panel lists the instrument's knobs to turn.
      var index = c.devicesOf("p").indexOf(macro);
      expect(find.text("Instrument · Attack"), findsOneWidget,
          reason: "under Macro 1, what it turns");
      expect(find.byKey(ValueKey("macroTurns-$index-0")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

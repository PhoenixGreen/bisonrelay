import 'dart:math' as math;
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
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_sidechain_test.dart is a strip listening to another channel: a
// gate opened, or a compressor pushed down, by another channel's sound --
// live, for pumping and for live sources -- beside the Ducker, which works
// ahead from a voice's recordings and is shown in the channels it turns
// down.

const int rate = 48000;

/// run is a second of a steady tone on "pad", through [pad], with a loud
/// burst on "kick" -- muted, so only its effect is heard -- for the first
/// half. The pad as heard, block by block.
Float32List run(ChannelMix pad, {bool kickThere = true}) {
  var g = MixGraph()
    ..setMaster(const MasterMix(limiter: false))
    ..setReturns(const [])
    ..setChannel("pad", pad);
  if (kickThere) g.setChannel("kick", const ChannelMix(mute: true));
  var out = Float32List(rate);
  for (var at = 0; at < rate; at += 512) {
    var n = math.min(512, rate - at);
    g.begin(n);
    var (pl, pr) = g.input("pad", n);
    // Nothing on the kick in the second half: its input is not touched.
    var kick = at < rate ~/ 2 && kickThere ? g.input("kick", n) : null;
    for (var i = 0; i < n; i++) {
      var s = 0.1 * math.sin(2 * math.pi * 220 * (at + i) / rate);
      pl[i] += s;
      pr[i] += s;
      if (kick case (var kl, var kr)) {
        var k = 0.8 * math.sin(2 * math.pi * 60 * (at + i) / rate);
        kl[i] += k;
        kr[i] += k;
      }
    }
    var l = Float32List(n), r = Float32List(n);
    g.finish(l, r, n);
    out.setRange(at, at + n, l);
  }
  return out;
}

double rms(Float32List x, int from, int to) {
  var sum = 0.0;
  for (var i = from; i < to; i++) {
    sum += x[i] * x[i];
  }
  return math.sqrt(sum / (to - from));
}

/// firstHalf and secondHalf are the pad's level with the kick sounding, and
/// after, each past its settling.
double firstHalf(Float32List x) => rms(x, rate ~/ 8, rate ~/ 2);
double secondHalf(Float32List x) => rms(x, rate * 5 ~/ 8, rate);

MixDevice gate({String source = ""}) => MixDevice(DeviceKind.gate,
    values: const {"threshold": -20, "release": 20, "hold": 5}, source: source);

const Dynamics squash =
    Dynamics(on: true, threshold: -30, ratio: 10, attackMs: 1, releaseMs: 30);

void main() {
  group("the model", () {
    test("the compressor's key is kept in the file, and heard when on", () {
      var d = squash.copyWith(source: "kick");
      expect(Dynamics.fromJson(d.toJson()).source, "kick");
      expect(d.sidechain, "kick");
      expect(d.copyWith(on: false).sidechain, isNull);
      expect(squash.toJson().containsKey("source"), isFalse,
          reason: "an old file reads as it was");
    });

    test("a gate listens to the channel it is given", () {
      expect(gate(source: "kick").sidechain, "kick");
      expect(gate().sidechain, isNull);
      expect(gate(source: "kick").switched(false).sidechain, isNull);
    });

    test("a strip's sidechains are its devices' and its compressor's", () {
      var mix = ChannelMix(
          devices: [gate(source: "kick")],
          comp: squash.copyWith(source: "voice"));
      expect(mix.sidechains, {"kick", "voice"});
      expect(const ChannelMix().sidechains, isEmpty);
    });
  });

  group("a gate", () {
    test("opens to another channel's sound, muted or not", () {
      var out = run(ChannelMix(devices: [gate(source: "kick")]));
      expect(firstHalf(out), greaterThan(0.05), reason: "open with the kick");
      expect(secondHalf(out), lessThan(0.005), reason: "shut without it");
    });

    test("listens to itself with no channel chosen", () {
      // The pad alone is under the threshold: shut throughout.
      var out = run(ChannelMix(devices: [gate()]));
      expect(firstHalf(out), lessThan(0.005));
      expect(secondHalf(out), lessThan(0.005));
    });

    test("listens to itself when its channel has gone", () {
      var loud = MixDevice(DeviceKind.gate,
          values: const {"threshold": -40}, source: "kick");
      var out = run(ChannelMix(devices: [loud]), kickThere: false);
      expect(secondHalf(out), greaterThan(0.05));
    });
  });

  group("a compressor", () {
    test("is pushed down by another channel, and lets go after", () {
      var out = run(ChannelMix(comp: squash.copyWith(source: "kick")));
      expect(firstHalf(out), lessThan(secondHalf(out) * 0.5),
          reason: "down while the kick sounds");
      expect(secondHalf(out), closeTo(0.1 / math.sqrt2, 0.01),
          reason: "the pad alone is under its threshold");
    });

    test("listening to itself, leaves a quiet pad alone throughout", () {
      var out = run(const ChannelMix(comp: squash));
      expect(firstHalf(out), closeTo(secondHalf(out), 0.005));
    });
  });

  group("the cards", () {
    CanvasDocument doc() => CanvasDocument(frames: 100, elements: [
          for (var (id, name) in [
            ("voice", "Voice"),
            ("music", "Music"),
            ("kick", "Kick")
          ])
            AudioElement(ElementBase(id: id, name: name),
                clip: MediaClip(
                    playlist: const [MediaSource(assetId: "t", length: 2)],
                    timed: true,
                    mix: id == "voice"
                        ? const ChannelMix(
                            duck: Ducking(on: true, depthDb: -12))
                        : const ChannelMix())),
        ]);

    Future<CanvasController> mixer(WidgetTester tester, String key,
        {double scale = 1}) async {
      var c = CanvasController(doc(), audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      c.openEffects(key);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CanvasMixer.effects(
                                  controller: c,
                                  height: 380,
                                  onResize: (_) {},
                                  onClose: () {}),
                            ])))),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      return c;
    }

    for (var scale in [1.0, 1.5]) {
      testWidgets("a ducked channel has the Ducker first, at $scale",
          (tester) async {
        var c = await mixer(tester, "music", scale: scale);
        expect(tester.takeException(), isNull);
        var card = find.byKey(const ValueKey("duckedOn"));
        expect(card, findsOneWidget);
        expect(find.byKey(const ValueKey("duckedNow")), findsOneWidget);
        expect(find.textContaining("By Voice"), findsOneWidget);
        // First in the chain: left of the channel's EQ.
        expect(tester.getCenter(card).dx,
            lessThan(tester.getCenter(find.byKey(const ValueKey("eqOn"))).dx));
        // Off leaves the music alone; the setting is the voice's.
        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 100));
        var voice = c.timelineChannels.firstWhere((l) => l.key == "voice");
        expect(voice.mix.duck.except, ["music"]);
        expect(voice.mix.duck.on, isTrue, reason: "still ducks the kick");
        expect(find.byKey(const ValueKey("duckedOn")), findsOneWidget,
            reason: "kept, to switch back on");
        await tester.tap(card);
        await tester.pump(const Duration(milliseconds: 100));
        voice = c.timelineChannels.firstWhere((l) => l.key == "voice");
        expect(voice.mix.duck.except, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("the voice itself has no ducked card", (tester) async {
      await mixer(tester, "voice");
      expect(find.byKey(const ValueKey("duckedOn")), findsNothing);
      expect(find.byKey(const ValueKey("duckOn")), findsOneWidget,
          reason: "its own Ducker, where it is set");
      await tester.pumpWidget(const SizedBox());
    });

    for (var scale in [1.0, 1.5]) {
      testWidgets("the compressor's key is picked on it, at $scale",
          (tester) async {
        var c = await mixer(tester, "music", scale: scale);
        var source = find.byKey(const ValueKey("compSource"));
        await tester.ensureVisible(source);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(source);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.widgetWithText(DropdownMenuItem<String>, "Music"),
            findsNothing,
            reason: "not its own channel");
        await tester.tap(find.text("Kick").last);
        await tester.pump(const Duration(milliseconds: 500));
        var music = c.timelineChannels.firstWhere((l) => l.key == "music");
        expect(music.mix.comp.source, "kick");
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("a gate's key is picked beside its knobs", (tester) async {
      var c = await mixer(tester, "music");
      c.setDevicesOf("music", [const MixDevice(DeviceKind.gate)]);
      await tester.pump(const Duration(milliseconds: 100));
      var source = find.byKey(const ValueKey("deviceSource-0"));
      expect(source, findsOneWidget);
      expect(find.text("Itself"), findsWidgets);
      await tester.ensureVisible(source);
      await tester.pump();
      await tester.tap(source);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text("Kick").last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.devicesOf("music").single.sidechain, "kick");
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

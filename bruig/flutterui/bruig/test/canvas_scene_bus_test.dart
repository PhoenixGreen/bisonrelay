import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceKnob;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'canvas_audio_fake.dart';

// canvas_scene_bus_test.dart is a scene as a bus: everything heard in a
// scene -- its channels, its backdrop's, its transition's -- summed through
// the scene's own strip on its way to the master, while the master's own
// sounds go straight there; each sound still heard from where it is.

const int rate = 48000;

/// run is half a second of a tone on "scene" (heard through the bus) and a
/// tone at another pitch on "master" (not), through [bus]. The speakers'
/// blocks, joined.
List<Float32List> run(ChannelMix bus,
    {ChannelMix scene = const ChannelMix(),
    SpeakerLayout layout = SpeakerLayout.stereo,
    Heard? placed,
    bool viaBus = true}) {
  var g = MixGraph()
    ..setSpeakers(layout)
    ..setMaster(const MasterMix(limiter: false))
    ..setReturns(const [])
    ..setChannel("scene", scene)
    ..setChannel("master", const ChannelMix())
    ..setScene(bus, viaBus ? {"scene"} : const {});
  if (placed != null) g.setPlacement("scene", placed);
  var total = rate ~/ 2;
  var out = [for (var c = 0; c < layout.channels; c++) Float32List(total)];
  for (var at = 0; at < total; at += 512) {
    var n = math.min(512, total - at);
    g.begin(n);
    var (sl, sr) = g.input("scene", n);
    var (ml, mr) = g.input("master", n);
    for (var i = 0; i < n; i++) {
      var a = 0.2 * math.sin(2 * math.pi * 330 * (at + i) / rate);
      var b = 0.2 * math.sin(2 * math.pi * 550 * (at + i) / rate);
      sl[i] += a;
      sr[i] += a;
      ml[i] += b;
      mr[i] += b;
    }
    var l = Float32List(n), r = Float32List(n);
    g.finish(l, r, n);
    for (var c = 0; c < layout.channels; c++) {
      out[c].setRange(at, at + n, g.speakers[c]);
    }
  }
  return out;
}

/// at is how strong [x] is at [hz] past the first tenth of a second.
double at(Float32List x, double hz) {
  var from = rate ~/ 10;
  var w = 2 * math.pi * hz / rate, k = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = from; i < x.length; i++) {
    var s = x[i] + k * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - k * s1 * s2) / (x.length - from);
}

/// unity is a bus that is not at its defaults but changes nothing: a
/// device switched off on it.
const ChannelMix unity =
    ChannelMix(devices: [MixDevice(DeviceKind.gate, on: false)]);

void main() {
  group("the sound", () {
    test("a bus at its defaults changes nothing", () {
      var plain = run(const ChannelMix(), viaBus: false);
      var bussed = run(const ChannelMix());
      expect(bussed[0], plain[0]);
      expect(bussed[1], plain[1]);
    });

    test("a bus that changes nothing, though in use, changes nothing", () {
      var plain = run(const ChannelMix(), viaBus: false);
      var bussed = run(unity);
      for (var c = 0; c < 2; c++) {
        for (var i = 0; i < plain[c].length; i += 97) {
          expect(bussed[c][i], closeTo(plain[c][i], 1e-6));
        }
      }
    });

    test("its fader turns the scene down, and not the master's sounds", () {
      var plain = run(unity);
      var down = run(const ChannelMix(gainDb: -6));
      expect(at(down[0], 330) / at(plain[0], 330), closeTo(0.5, 0.01));
      expect(at(down[0], 550) / at(plain[0], 550), closeTo(1, 0.001));
    });

    test("muted, the scene is silent and the master still heard", () {
      var out = run(const ChannelMix(mute: true));
      expect(at(out[0], 330), lessThan(1e-6));
      expect(at(out[0], 550), greaterThan(0.05));
    });

    test("a sound panned in the scene stays where it was", () {
      var out = run(const ChannelMix(gainDb: -3),
          scene: const ChannelMix(balance: -1));
      expect(at(out[0], 330), greaterThan(0.03));
      expect(at(out[1], 330), lessThan(1e-6), reason: "nothing on the right");
    });

    test("in surround, a placed sound comes from the same speakers", () {
      var plain = run(const ChannelMix(),
          layout: SpeakerLayout.surround51,
          placed: const Heard(-110),
          viaBus: false);
      var bussed = run(unity,
          layout: SpeakerLayout.surround51, placed: const Heard(-110));
      for (var c = 0; c < plain.length; c++) {
        expect(at(bussed[c], 330), closeTo(at(plain[c], 330), 1e-6),
            reason: "speaker $c");
      }
      expect(at(bussed[4], 330), greaterThan(0.03), reason: "the left rear");
    });

    test("its fader moved, its strip is kept and ramps", () {
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setReturns(const [])
        ..setChannel("s", const ChannelMix())
        ..setScene(unity, {"s"});
      void block() {
        g.begin(256);
        var (l, r) = g.input("s", 256);
        l.fillRange(0, 256, 0.5);
        r.fillRange(0, 256, 0.5);
        g.finish(Float32List(256), Float32List(256), 256);
      }

      block();
      g.setScene(
          const ChannelMix(
              gainDb: -6, devices: [MixDevice(DeviceKind.gate, on: false)]),
          {"s"});
      block();
      // Ramped down over the block from where it was, not stepped.
      expect(g.speakers[0][0], closeTo(0.5, 0.01));
      expect(g.speakers[0][255], closeTo(0.5 * dbToGain(-6), 0.01));
    });
  });

  group("the model", () {
    test("a scene's bus is kept in the file, and left out at its defaults", () {
      var s = const CanvasScene(id: "a", bus: ChannelMix(gainDb: -4));
      expect(CanvasScene.fromJson(s.toJson()).bus.gainDb, -4);
      expect(const CanvasScene(id: "a").toJson().containsKey("bus"), isFalse);
      expect(CanvasScene.fromJson(const {"id": "a"}).bus.isDefault, isTrue);
    });

    test("each scene's bus covers where it plays in the run", () {
      var doc = CanvasDocument(frameRate: 10, scenes: const [
        CanvasScene(id: "a", frames: 20, bus: ChannelMix(gainDb: -1)),
        CanvasScene(id: "b", frames: 30, bus: ChannelMix(gainDb: -2)),
      ]);
      var buses = sceneBuses(doc);
      expect(buses.length, 2);
      expect(buses[0].bus.gainDb, -1);
      expect(buses[1].from, closeTo(doc.startOfScene(1) / 10, 1e-9));
      expect(buses[1].until, closeTo(buses[1].from + 3, 1e-9));
    });
  });

  test("an export turns each scene's sounds by its own bus, at its time",
      () async {
    var which = await Process.run("which", ["ffmpeg"]);
    if (which.exitCode != 0) {
      markTestSkipped("ffmpeg is not installed");
      return;
    }
    var dir = await Directory.systemTemp.createTemp("canvas-scene-bus");
    addTearDown(() => dir.delete(recursive: true));
    var tone = path.join(dir.path, "tone.wav");
    await Process.run("ffmpeg", [
      "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", tone //
    ]);
    var out = path.join(dir.path, "mix.wav");
    // One sound across two scenes' worth of run, the second scene's bus
    // six decibels down; and one the master's, across both.
    expect(
        await renderMixWav(
            [
              ExportSound(
                  path: tone,
                  at: 0,
                  from: 0,
                  length: 2,
                  channel: "rain",
                  inScene: true),
            ],
            const MasterMix(limiter: false),
            seconds: 2,
            ffmpeg: "ffmpeg",
            out: out,
            scenes: const [
              (from: 0.0, until: 1.0, bus: ChannelMix()),
              (from: 1.0, until: 2.0, bus: ChannelMix(gainDb: -6)),
            ]),
        isTrue);
    var pcm = (await File(out).readAsBytes()).buffer.asFloat32List(44);
    var left = Float32List.fromList(
        [for (var i = 0; i < pcm.length ~/ 2; i++) pcm[i * 2]]);
    double level(int from, int to) {
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += left[i] * left[i];
      }
      return math.sqrt(sum / (to - from));
    }

    var first = level(rate ~/ 5, rate * 4 ~/ 5);
    var second = level(rate * 6 ~/ 5, rate * 9 ~/ 5);
    expect(second / first, closeTo(0.5, 0.02));
  });

  group("playing", () {
    AudioElement sound(String id, {String channel = ""}) =>
        AudioElement(ElementBase(id: id, name: id),
            clip: MediaClip(
                playlist: const [MediaSource(assetId: "t", length: 2)],
                timed: true,
                channel: channel));

    test("the scene's channels go through its bus; the master's do not",
        () async {
      var engine = FakeEngine({"t": 2});
      var c = CanvasController(
          CanvasDocument(
            frameRate: 10,
            masterOn: true,
            master: CanvasScene(id: "m", elements: [sound("music")]),
            scenes: [
              CanvasScene(
                  id: "a",
                  frames: 20,
                  bus: const ChannelMix(gainDb: -5),
                  elements: [sound("rain")]),
              const CanvasScene(id: "b", frames: 20),
            ],
          ),
          audioEngine: engine);
      addTearDown(c.dispose);
      c.togglePlay();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.sceneChannels, contains("rain"));
      expect(engine.sceneChannels, isNot(contains("music")));
      expect(engine.sceneBus.gainDb, -5);
      c.togglePlay();
    });

    test("the bus is changed on the scene shown, as one undo step", () {
      var c = CanvasController(
          CanvasDocument(scenes: const [
            CanvasScene(id: "a"),
            CanvasScene(id: "b"),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.setSceneBus(const ChannelMix(gainDb: -3));
      expect(c.document.scenes[0].bus.gainDb, -3);
      expect(c.document.scenes[1].bus.isDefault, isTrue);
      c.setDevicesOf(sceneBusKey, [const MixDevice(DeviceKind.reverb)]);
      expect(c.devicesOf(sceneBusKey).single.kind, DeviceKind.reverb);
      expect(c.chainOf(sceneBusKey).first, isNot(chainEq),
          reason: "a device added goes before the EQ and compressor");
      c.undo();
      expect(c.devicesOf(sceneBusKey), isEmpty);
      expect(c.sceneBus.gainDb, -3);
    });
  });

  group("the strip", () {
    CanvasDocument doc() => CanvasDocument(frameRate: 10, scenes: [
          CanvasScene(id: "a", name: "Rain", frames: 20, elements: [
            AudioElement(ElementBase(id: "rain", name: "Rain sound"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]),
          const CanvasScene(id: "b", frames: 20),
        ]);

    Future<CanvasController> pump(WidgetTester tester,
        {bool effects = false, double scale = 1}) async {
      var c = CanvasController(doc(), audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      if (effects) c.openEffects(sceneBusKey);
      tester.view.physicalSize = const Size(1800, 900);
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
                              effects
                                  ? CanvasMixer.effects(
                                      controller: c,
                                      height: 380,
                                      onResize: (_) {},
                                      onClose: () {})
                                  : CanvasMixer(
                                      controller: c,
                                      height: 560,
                                      onResize: (_) {},
                                      onClose: () {}),
                            ])))),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      return c;
    }

    // Ken, 2026-11-08: the prototype's scene chain -- a Source of everything
    // heard in it, and an Output.
    for (var scale in [1.0, 1.5]) {
      testWidgets(
          "its chain starts with what it sums and ends at its Output, "
          "at $scale", (tester) async {
        var c = await pump(tester, effects: true, scale: scale);
        expect(find.byKey(const ValueKey("device-sceneSound")), findsOneWidget);
        expect(find.byKey(const ValueKey("sceneSoundScreen")), findsOneWidget);
        expect(find.byKey(const ValueKey("device-busOutput")), findsOneWidget);
        expect(find.text("Master"), findsWidgets);
        // Its Output's level is the bus's fader, one step a turn.
        await tester
            .ensureVisible(find.byKey(const ValueKey("busOutput-level")));
        tester
            .widget<DeviceKnob>(find.byKey(const ValueKey("busOutput-level")))
            .onChanged(-6);
        await tester.pump();
        expect(c.sceneBus.gainDb, -6);
        c.undo();
        expect(c.sceneBus.gainDb, 0);
        expect(tester.takeException(), isNull);
      });
    }

    for (var scale in [1.0, 1.5]) {
      testWidgets("the scene's strip sits before the master, at $scale",
          (tester) async {
        var c = await pump(tester, scale: scale);
        expect(tester.takeException(), isNull);
        var strip = find.byKey(const ValueKey("strip-scene"));
        expect(strip, findsOneWidget);
        expect(find.text("Rain"), findsOneWidget);
        expect(
            tester.getCenter(strip).dx,
            lessThan(tester
                .getCenter(find.byKey(const ValueKey("strip-master")))
                .dx));
        await tester.tap(find.byKey(const ValueKey("sceneMute")).first);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.document.scenes[0].bus.mute, isTrue);
        expect(c.document.scenes[1].bus.mute, isFalse,
            reason: "only the scene shown");
        await tester.tap(find.byKey(const ValueKey("sceneEq")));
        await tester.pump(const Duration(milliseconds: 300));
        expect(c.effectsOf, sceneBusKey, reason: "its chain, opened");
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("a single canvas with no master has no scene strip",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 20, elements: [
            AudioElement(ElementBase(id: "v", name: "V"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 2)],
                    timed: true)),
          ]),
          audioEngine: FakeEngine({"t": 2}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1400, 900);
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
                    child: CanvasMixer(
                        controller: c,
                        height: 560,
                        onResize: (_) {},
                        onClose: () {})))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey("strip-scene")), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    for (var scale in [1.0, 1.5]) {
      testWidgets("the scene's chain is edited as a channel's, at $scale",
          (tester) async {
        var c = await pump(tester, effects: true, scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey("eqOn")), findsOneWidget);
        expect(find.byKey(const ValueKey("compOn")), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("compOn")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.sceneBus.comp.on, isTrue);
        // A device put on it, and moved past the EQ.
        c.setDevicesOf(sceneBusKey, [const MixDevice(DeviceKind.chorus)]);
        await tester.pump(const Duration(milliseconds: 100));
        var id = c.chainOf(sceneBusKey).first;
        c.moveDevice(sceneBusKey, id, 1);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.chainOf(sceneBusKey), [chainEq, id, chainComp]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}

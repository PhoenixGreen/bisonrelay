import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/scenes_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// What the Canvas costs when nobody is using it: found when the whole app
// had grown slow. A page left goes quiet; the mixer's meters rest; playing
// is not a change to the canvas; the renderer lets go of its pictures; and
// two canvases on one sound engine do not play through each other's mix.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("leaving the page stops what it set going", () {
    var clock = CounterElement(const ElementBase(id: "clock"),
        keyed: false, source: CounterSource.clock);
    var c = CanvasController(
        const CanvasDocument(frames: 240).copyWith(game: true, elements: [
          clock,
          ShapeElement(const ElementBase(
              id: "hero",
              width: 40,
              height: 80,
              play: PlaySpec(as: PlayAs.platformer))),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.startCounters();
    c.play();
    expect(c.playing, isTrue);
    c.gaming = true;
    c.leavePage();
    expect(c.gaming, isFalse, reason: "a game, and its hold on the keys");
    expect(c.playing, isFalse, reason: "nor its playhead, cueing sounds");
    var ticks = c.counterTicks;
    c.tickCounters();
    // Started again by the page as it opens: see CanvasStage.
    expect(c.counterTicks, greaterThanOrEqualTo(ticks));
  });

  test("leaving the page lets go of the renderer's pictures", () {
    var recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = Colors.red);
    var image = recorder.endRecording().toImageSync(4, 4);
    RasterCache.instance.put("someone|layer", const [], image);
    expect(RasterCache.instance.length, greaterThan(0));
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.leavePage();
    expect(RasterCache.instance.length, 0);
  });

  test("a frame played on is not a change to the canvas", () {
    var c = CanvasController(const CanvasDocument(frames: 240, frameRate: 10),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var now = 0;
    c.clockForTest = () => now;
    c.play();
    var revision = c.revision;
    for (var i = 1; i <= 20; i++) {
      now = i * 100000;
      c.tickClockForTest();
    }
    expect(c.frame, greaterThan(10), reason: "it played on");
    expect(c.revision, revision,
        reason: "and what redraws on a change -- the settings -- did not");
    c.pause();
  });

  testWidgets("the mixer's meters rest when nothing sounds", (tester) async {
    var c = CanvasController(const CanvasDocument(frames: 240),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: CanvasMixer(
                  controller: c,
                  height: 400,
                  onResize: (_) {},
                  onClose: () {}))),
    ));
    // A moment for the peaks to fall, and it asks for no more frames.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse,
        reason: "a ticker left running redraws the window at every refresh");
    // Playing, it moves again.
    c.play();
    expect(c.playing, isTrue);
    expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
    c.pause();
    await tester.pumpWidget(const SizedBox());
  });

  test("two canvases on one engine: each sends its own mix whole", () async {
    var engine = FakeEngine({});
    AudioRuntime runtime() =>
        AudioRuntime(engine: engine, locate: (id) async => null);
    var editor = runtime(), preview = runtime();
    addTearDown(editor.dispose);
    await editor.ready();
    await preview.ready();
    editor.setMix(const {}, master: const MasterMix(gainDb: -3));
    expect(engine.master?.volume, closeTo(dbToGain(-3), 1e-9));
    preview.setMix(const {}, master: const MasterMix(gainDb: -12));
    // Back to the editor, its master unchanged: sent again all the same.
    editor.setMix(const {}, master: const MasterMix(gainDb: -3));
    expect(engine.master?.volume, closeTo(dbToGain(-3), 1e-9),
        reason: "not left playing through the preview's");
    // A preview gone takes its strips with it.
    preview.setMix({"bus": const ChannelMix()}, master: const MasterMix());
    expect(engine.channels.containsKey("bus"), isTrue);
    preview.dispose();
    expect(engine.channels.containsKey("bus"), isFalse);
  });

  test("a scene's preview is drawn again only for its own changes", () {
    var doc = const CanvasDocument().withScenes([
      const CanvasScene(id: "a", frames: 10),
      const CanvasScene(id: "b", frames: 10),
    ]);
    // Scene b changed; a did not.
    var edited = doc.withScene(
        1,
        doc.allScenes[1].copyWith(elements: [
          ShapeElement(const ElementBase(id: "x")),
        ]));
    expect(sceneDrawnDiffers(doc, edited, 0), isFalse);
    expect(sceneDrawnDiffers(doc, edited, 1), isTrue);
  });

  // Ken's strip, master and panner meters stood dead while the devices'
  // own moved: a ticker's time starts from nought each time it starts, and
  // the last read kept from the run before held every frame back until the
  // new run had lasted as long.
  group("the meters move again after resting", () {
    Future<(CanvasController, FakeEngine)> open(
        WidgetTester tester, String chain) async {
      var engine = FakeEngine({"t": 20})..heardTaps = [(0.5, 0.5), (0.5, 0.5)];
      var c = CanvasController(
          CanvasDocument(frames: 100, elements: [
            AudioElement(const ElementBase(id: "a", name: "Guitar"),
                clip: const MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 20)],
                    timed: true)),
          ]),
          audioEngine: engine);
      addTearDown(c.dispose);
      await tester.runAsync(() => c.audio.ready());
      c.openEffects(chain);
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
                            ])))),
      ));
      return (c, engine);
    }

    // Sound for a while, then quiet long enough to rest, then sound again.
    Future<void> soundRestSound(WidgetTester tester, FakeEngine engine,
        {Future<void> Function()? resting}) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      engine
        ..heardLevels = (0, 0)
        ..heardTaps = [(0, 0), (0, 0)];
      // The held peaks fall a step a reading: long enough for them all to
      // reach the floor, and the meters to rest.
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse,
          reason: "resting");
      await resting?.call();
      engine
        ..heardLevels = (0.5, 0.5)
        ..heardTaps = [(0.5, 0.5), (0.5, 0.5)];
      // The slow check wakes it; a few frames on.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // The chain prototype's gain badges, on the master's chain too, and on
    // its EQ: what each does to the level.
    testWidgets("the master's devices and EQ say what they do to the level",
        (tester) async {
      var (c, engine) = await open(tester, mixerMasterKey);
      c.setMasterMix(c.document.masterMix.copyWith(
          devices: const [MixDevice(DeviceKind.saturator, id: "d0")]));
      var chain = c.chainOf(mixerMasterKey);
      var at = chain.indexOf("d0"), eq = chain.indexOf(chainEq);
      var taps = [for (var i = 0; i <= chain.length; i++) (0.5, 0.5)];
      taps[at + 1] = (0.25, 0.25);
      if (eq == at + 1) taps[eq + 1] = (0.5, 0.5);
      engine.heardTaps = taps;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
          tester.widget<Text>(find.byKey(const ValueKey("deviceGain-d0"))).data,
          "−6.0",
          reason: "half the gain, on the master's chain");
      if (eq == at + 1) {
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey("deviceGain-eq")))
                .data,
            "+6.0");
      }
      await tester.pumpWidget(const SizedBox());
    });

    // The chain prototype's clip lights: lit once a join clips, until its
    // lights are cleared from a join's menu.
    testWidgets("a join that clipped stays lit until cleared", (tester) async {
      var (c, engine) = await open(tester, "a");
      Color lamp() => (tester
              .widget<Container>(find.byKey(const ValueKey("junctionClip-0")))
              .decoration as BoxDecoration)
          .color!;
      engine.heardTaps = [(1.4, 1.4), (1.4, 1.4)];
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      engine.heardTaps = [(0.1, 0.1), (0.1, 0.1)];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(lamp(), const Color(0xFFE5484D), reason: "four seconds on, lit");
      await tester.tap(find.byKey(const ValueKey("junction-0")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("junctionClear-0")));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(lamp(), isNot(const Color(0xFFE5484D)), reason: "cleared");
      await tester.pumpWidget(const SizedBox());
    });

    // The chain prototype: a folded card keeps a meter at its foot.
    testWidgets("a folded device shows its level as the sound leaves it",
        (tester) async {
      var (c, engine) = await open(tester, "a");
      c.setDevicesOf("a", const [MixDevice(DeviceKind.reverb)]);
      var id = deviceIdAt(c.devicesOf("a"), 0);
      c.foldDevice(deviceKey(id), true);
      engine.heardTaps = [for (var i = 0; i < 8; i++) (0.5, 0.5)];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      var level = find.descendant(
          of: find.byKey(const ValueKey("foldedLevel-0")),
          matching: find.byType(FractionallySizedBox));
      expect(level, findsOneWidget, reason: "folded, a meter at its foot");
      expect(tester.widget<FractionallySizedBox>(level).heightFactor,
          closeTo(0.9, 0.02),
          reason: "half the gain, six down of sixty");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the levels between a channel's devices", (tester) async {
      var (c, engine) = await open(tester, "a");
      String reading() => tester
          .widget<Tooltip>(find.descendant(
              of: find.byKey(const ValueKey("junction-0")),
              matching: find.byType(Tooltip)))
          .message!;
      await soundRestSound(tester, engine, resting: () async {
        expect(reading(), startsWith("−∞"), reason: "fallen as it rested");
      });
      expect(reading(), startsWith("-6.0 dB"),
          reason: "moving again at once, not after as long as it ran before");
      // The peak held under it, and its clip light dark below nought.
      expect(
          tester.widget<Text>(find.byKey(const ValueKey("junctionDb-0"))).data,
          "−6");
      var lamp = tester
          .widget<Container>(find.byKey(const ValueKey("junctionClip-0")));
      expect((lamp.decoration as BoxDecoration).color,
          isNot(const Color(0xFFE5484D)));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("the master's meter", (tester) async {
      var (c, engine) = await open(tester, mixerMasterKey);
      var loudest = find.byKey(const ValueKey("meterLoudest-masterMeter"));
      String reading() => tester
          .widget<Text>(
              find.descendant(of: loudest, matching: find.byType(Text)))
          .data!;
      await soundRestSound(tester, engine, resting: () async {
        // Cleared while it rests, so what it reads next is new.
        await tester.ensureVisible(loudest);
        await tester.pump();
        await tester.tap(loudest);
        await tester.pump();
        expect(reading(), "−∞  −∞");
      });
      expect(reading(), "-6.0  -6.0");
      await tester.pumpWidget(const SizedBox());
    });
  });
}

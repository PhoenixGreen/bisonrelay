import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
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
}

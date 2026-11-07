import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_timeline_clips_test.dart is a sound on the timeline as a clip (Ken,
// 2026-11-07: "a clip and a timeline clip are interchangeable"): opened in
// the clip editor from the Chain's Clip tab with no clip in a slot, its
// settings kept on it, and what the timeline plays the clip rendered.

CanvasController _make() => CanvasController(
    CanvasDocument(
        frames: 600,
        frameRate: 60,
        audio: const AudioSettings(tempo: 120),
        elements: [
          AudioElement(const ElementBase(id: "m", name: "Impact"),
              clip: const MediaClip(playlist: [
                MediaSource(assetId: "impact.wav", name: "Impact", length: 4)
              ], timed: true, at: 60)),
        ]),
    audioEngine: FakeEngine({"impact.wav": 4}));

Future<void> show(WidgetTester tester, CanvasController c,
    {double height = 420}) async {
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
                        controller: c, height: height, onResize: (_) {}))))),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

AudioElement _sound(CanvasController c) =>
    c.document.elementById("m") as AudioElement;

void main() {
  test("its settings kept on it; what it plays follows them; one undo", () {
    var c = _make();
    addTearDown(c.dispose);
    expect(c.timelineSoundOf("m")?.id, "m");
    c.openClipEditor("m", timelineRow);
    expect(c.clipEditing?.row, timelineRow);
    var clip = c.editedClip!;
    expect(clip.sound!.assetId, "impact.wav");
    // Four seconds at 120: two bars.
    expect(clip.bars, closeTo(2, 1e-9));
    expect(clip.gain, closeTo(gainToDb(0.8), 0.05),
        reason: "as loud as it played");
    // Started a beat in, and 3 dB down.
    c.editClip((x) => x.copyWith(start: 1, gain: -3));
    var source = _sound(c).clip.playlist.single;
    expect(source.clip!.start, 1);
    expect(source.start, closeTo(0.5, 1e-9), reason: "a beat at 120");
    expect(_sound(c).clip.volume, closeTo(dbToGain(-3), 1e-9));
    c.undo();
    expect(_sound(c).clip.playlist.single.clip, isNull);
    expect(_sound(c).clip.playlist.single.start, 0);
  });

  test("faded or warped, it plays what it renders to, the original kept",
      () async {
    var audioWas = CanvasController.clipAudio;
    var storeWas = CanvasController.partStore;
    addTearDown(() {
      CanvasController.clipAudio = audioWas;
      CanvasController.partStore = storeWas;
    });
    CanvasController.clipAudio = (id) async {
      var x = Float32List(4 * 48000);
      for (var i = 0; i < x.length; i++) {
        x[i] = 0.3 * math.sin(i * 0.05);
      }
      return (x, Float32List.fromList(x));
    };
    CanvasController.partStore = (wav) async => "made.wav";
    var c = _make();
    addTearDown(c.dispose);
    c.openClipEditor("m", timelineRow);
    c.editClip((x) => x.copyWith(fadeIn: 0.5, pitch: 2));
    await c.renderTimelineClip("m");
    var source = _sound(c).clip.playlist.single;
    expect(source.assetId, "made.wav");
    expect(source.clip!.sound!.assetId, "impact.wav",
        reason: "its own sound kept, to make it again from");
    expect(_sound(c).clip.mediaIds, containsAll(["impact.wav", "made.wav"]));
    expect(_sound(c).clip.fadeIn, 0.5,
        reason: "its fades the timeline's own, not made into it");
    // Kept with the canvas.
    var back = MediaSource.fromJson(source.toJson());
    expect(back.clip!.warped!.assetId, "made.wav");
  });

  // Ken: the timeline's fades editable as ever -- and the same fades as the
  // clip editor's.
  test("its fades are the timeline's: set in either, seen in both", () {
    var c = _make();
    addTearDown(c.dispose);
    c.openClipEditor("m", timelineRow);
    c.editClip((x) => x.copyWith(fadeIn: 0.25, fadeOut: 1));
    expect(_sound(c).clip.fadeIn, 0.25);
    expect(_sound(c).clip.fadeOut, 1);
    expect(_sound(c).clip.playlist.single.clip!.needsRender, isFalse,
        reason: "fades are played, not made");
    // Dragged on the timeline: the clip editor has it.
    c.setTimedClip(_sound(c), _sound(c).clip.copyWith(fadeIn: 0.75));
    expect(c.editedClip!.fadeIn, 0.75);
  });

  testWidgets("with no clip in a slot, the Chain's Clip tab opens its sound",
      (tester) async {
    var c = _make();
    addTearDown(c.dispose);
    c.openEffects("m");
    await show(tester, c, height: 420);
    var tab = find.byKey(const ValueKey("chainTabClip"));
    expect(tab, findsOneWidget);
    await tester.tap(tab);
    await tester.pump();
    expect(c.clipEditorShown, isTrue);
    expect(find.byKey(const ValueKey("clipSample")), findsOneWidget);
    expect(find.byKey(const ValueKey("clipInspector")), findsOneWidget);
    expect(find.byKey(const ValueKey("launchColumn")), findsNothing,
        reason: "on the timeline it plays where it is, not launched");
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
}

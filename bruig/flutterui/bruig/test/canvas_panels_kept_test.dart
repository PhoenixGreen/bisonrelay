import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_audio_fake.dart';

// canvas_panels_kept_test.dart is how the panels under the canvas are kept
// between visits -- the mixer and effects as they were left, and each
// canvas's channel heights, narrow strips and zoom -- and the mixer at its
// smallest: its meters alone.

CanvasController _make() => CanvasController(
    CanvasDocument(frames: 200, frameRate: 25, elements: [
      for (var (id, n) in [("a", "Narrator"), ("b", "Music")])
        AudioElement(ElementBase(id: id, name: n),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: "t", length: 2)], timed: true)),
    ]),
    audioEngine: FakeEngine({"t": 2}));

void main() {
  group("kept", () {
    test("the panels, whatever canvas is open", () {
      var c = _make();
      addTearDown(c.dispose);
      c.mixerOpen = true;
      c.mixerMinimised = true;
      c.mixerSmallest = true;
      c.openEffects("a", device: "eq");
      c.foldDevice("comp", true);
      c.nextLaneSize();
      c.headerWidth = 210;
      var kept = c.panelState;
      var back = _make();
      addTearDown(back.dispose);
      back.restorePanels(kept);
      expect((back.mixerOpen, back.mixerMinimised, back.mixerSmallest),
          (true, true, true));
      expect(back.effectsOpen, isTrue);
      expect(back.foldedDevices, {"comp"});
      expect(back.laneSize, 1);
      expect(back.headerWidth, 210);
      expect(back.panelState, kept);
    });

    test("each canvas's channels, narrow strips, zoom and effects channel", () {
      var c = _make();
      addTearDown(c.dispose);
      c.setLaneHeight("a", 88);
      c.toggleNarrow("b");
      c.timelineView = const TimelineView(12, 50);
      c.openEffects("b");
      var kept = c.canvasView;
      var back = _make();
      addTearDown(back.dispose);
      var set = back.timelineViewSet;
      back.restoreCanvasView(kept);
      expect(back.laneHeights, {"a": 88.0});
      expect(back.narrowStrips, {"b"});
      expect((back.timelineView!.first, back.timelineView!.span), (12.0, 50.0));
      expect(back.timelineViewSet, set + 1,
          reason: "for the timeline to take it up");
      expect(back.effectsOf, "b");
      // A canvas never looked at starts as it starts.
      back.restoreCanvasView(const {});
      expect(back.laneHeights, isEmpty);
      expect(back.narrowStrips, isEmpty);
      expect(back.timelineView, isNull);
    });

    test("in the preferences: the latest forty canvases", () async {
      SharedPreferences.setMockInitialValues({});
      var prefs = CanvasPreferences();
      prefs.panels = {"mixer": "minimised"};
      for (var i = 0; i < 45; i++) {
        prefs.setCanvasView("/c$i", {
          "lanes": {"a": i.toDouble()}
        });
      }
      // Looked at again, the oldest is kept as the latest.
      prefs.setCanvasView("/c5", {
        "lanes": {"a": 5.0}
      });
      await Future<void>.delayed(Duration.zero);
      var loaded = CanvasPreferences();
      await loaded.load();
      expect(loaded.panels, {"mixer": "minimised"});
      expect(loaded.canvasView("/c44"), isNotNull);
      expect(loaded.canvasView("/c5"), isNotNull);
      expect(loaded.canvasView("/c4"), isNull, reason: "past the forty");
      expect(loaded.canvasView("/c44")!["lanes"], {"a": 44.0});
    });
  });

  group("the mixer at its smallest", () {
    test("the Mixer button steps through it, before hidden", () {
      var c = _make();
      addTearDown(c.dispose);
      var steps = <(bool, bool, bool)>[];
      for (var i = 0; i < 4; i++) {
        c.cycleMixer();
        steps.add((c.mixerOpen, c.mixerMinimised, c.mixerSmallest));
      }
      expect(steps, [
        (true, false, false),
        (true, true, false),
        (true, true, true),
        (false, false, false),
      ]);
    });

    testWidgets("its meters alone: no names, no narrow arrows, no rail",
        (tester) async {
      var c = _make();
      addTearDown(c.dispose);
      // Ken's bands: the mixer minimised, the others hidden.
      c.restoreMixer(["hidden", "hidden", "minimised", "hidden"], false);
      tester.view.physicalSize = const Size(1300, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> show() => tester.pumpWidget(
            ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false),
              child: MaterialApp(
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => CanvasMixer(
                          controller: c,
                          height: mixerLeastHeight(c),
                          onResize: (_) {},
                          onClose: () {}),
                    ),
                  ),
                ),
              ),
            ),
          );
      c.mixerMinimised = true;
      await show();
      await tester.pump();
      var minimised = mixerLeastHeight(c);
      expect(find.text("Narrator"), findsOneWidget);
      expect(find.byKey(const ValueKey("narrow-a")), findsOneWidget);
      expect(find.byKey(const ValueKey("narrowAll")), findsOneWidget);
      c.mixerSmallest = true;
      await show();
      await tester.pump();
      expect(mixerLeastHeight(c), lessThan(minimised - 30));
      expect(find.text("Narrator"), findsNothing);
      expect(find.byKey(const ValueKey("narrow-a")), findsNothing);
      expect(find.byKey(const ValueKey("narrowAll")), findsNothing,
          reason: "the rail of bands is gone");
      expect(find.text("S"), findsNothing, reason: "no buttons either");
      expect(find.byKey(const ValueKey("miniFader")), findsNWidgets(3),
          reason: "two channels and the master: their meters");
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

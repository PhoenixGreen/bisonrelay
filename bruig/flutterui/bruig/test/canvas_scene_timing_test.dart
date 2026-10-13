import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_scene_timing_test.dart is time across the scenes of a run: stepping
// through a join, transitions sized on the scene strip without moving the
// scenes after them, and the timeline keeping the playhead in view.

const _fade = SceneTransition(kind: SceneTransitionKind.fade);

CanvasDocument _four() => const CanvasDocument(
      frameRate: 10,
      scenes: [
        CanvasScene(id: "s0", frames: 100, transition: _fade),
        CanvasScene(id: "s1", frames: 100, transition: _fade),
        CanvasScene(id: "s2", frames: 100, transition: _fade),
        CanvasScene(id: "s3", frames: 100),
      ],
    );

List<int> _starts(CanvasDocument d) =>
    [for (var i = 0; i < d.allScenes.length; i++) d.startOfScene(i)];

void main() {
  group("start times", () {
    test("a longer transition is taken from the scene before it", () {
      var d = _four();
      var longer = d.withScene(1,
          d.allScenes[1].copyWith(transition: _fade.copyWith(frames: 30, overlap: 30)));
      expect(_starts(longer), isNot(_starts(d)),
          reason: "left alone, everything after it moves");
      var kept = longer.keepingStarts(d);
      expect(_starts(kept), _starts(d));
      expect(kept.allScenes[1].frames, 118);
    });

    test("changing a transition, or the default, never moves a scene", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      var before = _starts(c.document);
      c.setSceneTransition(0, _fade.copyWith(frames: 24, overlap: 24));
      c.setDefaultTransition(_fade.copyWith(frames: 6, overlap: 6));
      expect(_starts(c.document), before);
    });

    test("the Length field changes the scene's length, as it always did", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      c.goToScene(1);
      c.setSceneLength(140);
      expect(c.document.allScenes[1].frames, 140);
      expect(c.document.allScenes[2].frames, 100);
    });
  });

  group("stepping with every scene playing", () {
    test("goes through a join in the run's time, and shows the transition",
        () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      c.playAll = true;
      var join = c.document.startOfScene(1);
      // The last frame of scene one, which is inside its transition.
      c.goToRunFrame(join + 11);
      var runs = <int>[];
      for (var i = 0; i < 6; i++) {
        runs.add(c.document.startOfScene(c.sceneAt) + c.frame);
        c.stepFrame(1);
      }
      for (var i = 1; i < runs.length; i++) {
        expect(runs[i], runs[i - 1] + 1, reason: "never back: $runs");
      }
      c.goToRunFrame(join + 4);
      expect(c.previewAt, join + 4, reason: "inside the transition, it is shown");
      c.goToRunFrame(join + 40);
      expect(c.previewAt, isNull, reason: "and outside it, the scene is");
    });

    test("the button after Play goes to the next scene in one press", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      c.playAll = true;
      c.forward();
      expect((c.sceneAt, c.frame), (1, 0));
      c.forward();
      expect((c.sceneAt, c.frame), (2, 0));
      c.playAll = false;
      c.forward();
      expect(c.frame, 99, reason: "one scene at a time, its end");
    });

    test("steps back through a join the same way", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      c.playAll = true;
      c.goToRunFrame(c.document.startOfScene(2) + 2);
      var before = c.document.startOfScene(c.sceneAt) + c.frame;
      for (var i = 0; i < 20; i++) {
        c.stepFrame(-1);
      }
      expect(c.document.startOfScene(c.sceneAt) + c.frame, before - 20);
    });
  });

  group("the timeline", () {
    Future<CanvasController> show(WidgetTester tester) async {
      var c = CanvasController(_four(), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
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
              child: CanvasTimeline(controller: c, height: timelineHeight + 120),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("playAll")));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets("a transition's grip on the scene strip sizes it in place",
        (tester) async {
      var c = await show(tester);
      var before = _starts(c.document);
      var grip = find.byKey(const ValueKey("sceneTransitionGrip1"));
      expect(grip, findsOneWidget);
      await tester.drag(grip, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(c.document.transitionAfter(1).frames, greaterThan(12),
          reason: "dragged longer");
      expect(_starts(c.document), before, reason: "every scene where it was");
      c.undo();
      expect(c.document.transitionAfter(1).frames, 12, reason: "one change");
    });

    testWidgets("keeps the playhead in view when the scene changes",
        (tester) async {
      var c = await show(tester);
      // Zoomed in on the start of the run, then taken to the last scene.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const ValueKey("timelineZoomIn")));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      c.goToScene(3);
      c.frame = 50;
      await tester.pumpAndSettle();
      var timeline =
          tester.state<CanvasTimelineState>(find.byType(CanvasTimeline));
      var view = timeline.shownView;
      expect(view.span, lessThan(c.document.sequenceFrames / 4),
          reason: "zoomed in");
      expect(timeline.playheadFrame,
          inInclusiveRange(view.first, view.first + view.span));
    });
  });
}

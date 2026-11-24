import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/canvas_panel_helpers.dart';
import 'support/canvas_timeline_menus.dart';

// canvas_editor_timeline_test.dart is the timeline: its controls, a path on
// it, and channels.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);

  testWidgets("a zoom along every scene is kept when the timeline is rebuilt",
      (tester) async {
    // Ken, 2026-11-24: with every scene showing, zoomed in on one, opening
    // the mixer beside the timeline put the zoom back to the whole run. A
    // timeline built afresh took its kept view for one scene's.
    var controller = CanvasController(const CanvasDocument().withScenes([
      for (var i = 0; i < 4; i++)
        CanvasScene(id: "s$i", frames: 240, elements: const []),
    ]));
    addTearDown(controller.dispose);
    controller.playAll = true;
    // The playhead in the stretch zoomed to, as it is when working there.
    controller.goToScene(1);
    controller.frame = 60;
    await pump(tester, CanvasTimeline(controller: controller, showBar: true));
    // Zoomed in, as a pinch or the zoom keys leave it.
    controller.timelineView = const TimelineView(240, 120);
    controller.timelineViewRuns = true;
    controller.timelineViewSet++;
    await pump(tester, CanvasTimeline(controller: controller, showBar: true));
    expect(controller.timelineView, const TimelineView(240, 120));
    // Another panel opened: the timeline is a new one.
    await pump(tester, const SizedBox());
    await pump(
        tester,
        CanvasTimeline(
            key: UniqueKey(), controller: controller, showBar: true));
    expect(controller.timelineView, const TimelineView(240, 120),
        reason: "the zoom kept, counted along every scene as it was");
  });

  group("the timeline", () {
    testWidgets("the master canvas's length is a reading, not a field",
        (tester) async {
      // It is as long as the scenes it covers, worked out rather than kept.
      // As a field it took a number and put the old one back, which reads as
      // the field being broken -- reported as "when I change this it reverts
      // to 3600", alongside the real bug: the run was being clamped to the
      // limit on one scene, so six scenes of 720 came to 3600 and playing the
      // whole document stopped in the middle of the sixth.
      var controller = CanvasController(const CanvasDocument().withScenes([
        for (var i = 0; i < 6; i++)
          CanvasScene(id: "s$i", frames: 720, elements: const []),
      ]).copyWith(
        master: const CanvasScene(id: "m", name: "Master"),
        masterOn: true,
        onMaster: true,
      ));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));
      await openTiming(tester);

      expect(find.byKey(const ValueKey("canvasFrames")), findsNothing,
          reason: "nothing to type into");
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFramesMaster")),
              matching: find.text("4320")),
          findsOneWidget,
          reason: "six scenes of seven hundred and twenty");
    });

    // Adding and removing a keyframe from the bar's diamond: the bar control
    // was removed for the clips system.

    testWidgets("changes the frame count and the frame rate", (tester) async {
      // Both moved here from the settings band: they describe the strip they
      // now sit on.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));
      await openTiming(tester);

      expect(find.text("Still"), findsOneWidget);

      await enterValue(
          tester, find.byKey(const ValueKey("canvasFrames")), "24");
      await tester.pump();
      expect(controller.document.frames, 24);
      expect(find.text("Still"), findsNothing);

      await enterValue(
          tester, find.byKey(const ValueKey("canvasFrameRate")), "30");
      await tester.pump();
      expect(controller.document.frameRate, 30);
      expect(find.text("0.8 s"), findsOneWidget);
    });

    testWidgets("the playhead and the length are one editable control",
        (tester) async {
      // They were a readout and a separate Frames field a few pixels apart,
      // saying the same number twice -- and the field was too narrow for four
      // digits, so a long document showed "10000" clipped to "1000".
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));

      var playhead = find.byKey(const ValueKey("transportPosition"));
      var length = find.byKey(const ValueKey("canvasFrames"));
      // One-based on screen: the first frame is frame 1 to everybody except a
      // computer.
      expect(find.descendant(of: playhead, matching: find.text("13 / 40")),
          findsOneWidget);

      // Double-clicked, the position is a field to type where to go.
      await tester.tap(playhead);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(playhead);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey("positionField")), "25");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.frame, 24);

      // The length, behind the readout's arrow.
      await openTiming(tester);
      expect(find.descendant(of: length, matching: find.text("40")),
          findsOneWidget);
      await enterValue(tester, length, "600");
      await tester.pump();
      expect(controller.document.frames, 600);
    });

    testWidgets("a long document's numbers still fit", (tester) async {
      var controller =
          CanvasController(const CanvasDocument(frames: maxFrameCount));
      addTearDown(controller.dispose);
      controller.frame = maxFrameCount - 1;
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));
      await openTiming(tester);

      expect(tester.takeException(), isNull);
      var length = find.byKey(const ValueKey("canvasFrames"));
      expect(find.descendant(of: length, matching: find.text("$maxFrameCount")),
          findsOneWidget);
      // One line: the control plus its caption. Two would be a caption and
      // two rows of field.
      expect(tester.getSize(length).height,
          lessThan(controlHeight + controlLabelHeight + 4));
    });

    testWidgets("typing in a field keeps its own arrow keys and space bar",
        (tester) async {
      // The transport's Focus sits below the app's text-editing shortcuts, so
      // its handler ran first: an arrow pressed while typing a frame number
      // scrubbed the timeline instead of moving the caret, and a space started
      // playback instead of typing.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));
      await openTiming(tester);

      await tester.tap(find.byKey(const ValueKey("canvasFrameRate")));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(controller.frame, 12, reason: "the playhead did not move");
      expect(controller.playing, isFalse, reason: "and nothing started");
    });

    // Stepping the playhead a frame at a time: the bar control was removed
    // for the clips system.

    testWidgets(
        "the transport row does not move when the playhead lands on a "
        "keyframe", (tester) async {
      // The reported problem: the pose controls sat on the transport row and
      // appeared as the playhead crossed a keyframe, so the row changed width
      // under the pointer and the play buttons moved while scrubbing.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));

      var playAt = tester.getTopLeft(find.byKey(const ValueKey("play")));
      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const ValueKey("play"))), playAt,
          reason: "landing on a keyframe must not move the transport");
      expect(find.text("Easing"), findsNothing,
          reason: "the pose controls are not on the bar");
    });

    // The pose bar's toggle on the play bar: the bar control was removed for
    // the clips system.

    // Auto-keyframe from the transport: the bar control was removed for the
    // clips system.

    // A focused player's keyframe added from the bar's diamond: the bar
    // control was removed for the clips system.

    testWidgets("adds a timeline marker and lets it be removed",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 30));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));

      // The Marker menu is a panel (Ken, 2026-11-08): five buttons say what
      // the marker does; the fields for the one chosen are under them.
      await openMarker(tester);
      expect(find.text("Add a marker at 13"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("markerKind-stop")));
      await tester.pumpAndSettle();
      expect(controller.document.actions.single.frame, 12);
      expect(controller.document.actions.single.kind, TimelineActionKind.stop);
      expect(find.byKey(const ValueKey("actionWaitsFor")), findsOneWidget,
          reason: "a stop says what it waits for");

      await tester.tap(find.byKey(const ValueKey("markerKind-loop")));
      await tester.pumpAndSettle();
      expect(controller.document.actions.single.kind, TimelineActionKind.loop);
      expect(find.byKey(const ValueKey("actionTarget")), findsOneWidget);
      expect(find.byKey(const ValueKey("actionRepeats")), findsOneWidget);
      expect(find.text(TimelineActionKind.loop.description), findsOneWidget,
          reason: "a line says what the chosen kind does");
      expect(find.byKey(const ValueKey("markerRow-12")), findsOneWidget,
          reason: "listed among the canvas's markers");

      await tester.tap(find.byKey(const ValueKey("markerRemove")));
      await tester.pumpAndSettle();
      expect(controller.document.actions, isEmpty);
    });
  });

  group("a path on the timeline", () {
    (CanvasController, PathElement) withPath() {
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0.5, frame: 10),
          PathNode(x: 1, y: 1, frame: 20),
        ],
      );
      var controller =
          CanvasController(const CanvasDocument(frames: 30).addElement(path));
      controller.selectOnly("p");
      return (controller, path);
    }

    // Its points are retimed on the Chain's Keyframes card now, keyframing
    // being the Chain's (Ken, 2026-11-09): see
    // canvas_keyframes_card_test.dart. The ruler still scrubs.

    testWidgets("a drag away from the marks still scrubs", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller, showBar: true));

      var ruler = find.byKey(const ValueKey("keyframeStrip"));
      var box = tester.getRect(ruler);

      // On the ruler: the playhead is grabbed there, and nothing on the
      // path is retimed.
      await tester.dragFrom(
          Offset(box.left + 12, box.top + 4), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(controller.frame, greaterThan(0));
      var after = controller.document.elements.single as PathElement;
      expect(after.nodes.map((n) => n.frame).toList(), [0, 10, 20],
          reason: "nothing was retimed");
    });
  });

  // The channels are part of the timeline now: lanes under the keyframe strip,
  // in the room the timeline is dragged open to, with Add audio where the
  // Channels toggle was.
  group("channels in the timeline", () {
    Widget host(CanvasController c) {
      var height = timelineHeight;
      return StatefulBuilder(
        builder: (context, set) => Align(
          alignment: Alignment.bottomCenter,
          child: CanvasTimeline(
            controller: c,
            showBar: true,
            height: height,
            onResize: (h) =>
                set(() => height = h.clamp(timelineHeight, 600).toDouble()),
          ),
        ),
      );
    }

    // No button to press for a channel: there is always an empty one at the
    // bottom, and nothing is put on the canvas until a sound is.
    testWidgets("an empty channel is always there, and is not an element",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100));
      addTearDown(c.dispose);
      await pump(tester, host(c));
      expect(find.byKey(const ValueKey("addAudioChannel")), findsNothing);
      await tester.drag(
          find.byKey(const ValueKey("timelineGrip")), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("lane-new")), findsOneWidget);
      // Its + adds a channel of either kind: see the + menu's own tests.
      expect(find.text("Add a channel"), findsOneWidget);
      expect(find.byKey(const ValueKey("addChannel")), findsOneWidget);
      expect(c.document.elements, isEmpty);
    });

    // Ken: a channel for the sample slots alone, its timeline unused --
    // greyed, and saying so -- and the master's channels changed from any
    // scene, as a game is played on one.
    testWidgets("a channel of slots alone is greyed: Sample slots in use",
        (tester) async {
      var c = CanvasController(CanvasDocument(
          masterOn: true,
          master: const CanvasScene(id: "m", elements: [
            AudioElement(ElementBase(id: "fx", name: "Effects", visible: false),
                clip: MediaClip(
                    timed: true, channel: "fx", channelName: "Effects"),
                controls: []),
          ]),
          session: const SessionGrid().put(
              "fx",
              0,
              const SessionClip(
                  id: "coin",
                  name: "Coin",
                  sound: MediaSource(assetId: "x", name: "coin.wav"))),
          scenes: const [CanvasScene(id: "one", frames: 100)]));
      addTearDown(c.dispose);
      await pump(tester, host(c));
      await tester.drag(
          find.byKey(const ValueKey("timelineGrip")), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(c.document.editingMaster, isFalse);
      var channel = c.timelineChannels.single;
      expect(channel.editable, isTrue,
          reason: "the master's channel, from a scene");
      var lane = find.byKey(const ValueKey("lane-fx"));
      expect(lane, findsOneWidget);
      expect(
          find.descendant(
              of: lane,
              matching: find.byWidgetPredicate((w) =>
                  w is CustomPaint &&
                  "${w.foregroundPainter.runtimeType}" ==
                      "_InteractiveLanePainter")),
          findsOneWidget);

      // A sound put on its timeline: in use again.
      var e = c.document.master!.elements.single as AudioElement;
      c.setTimedClip(
          e,
          e.clip.copyWith(
              playlist: const [MediaSource(assetId: "x", name: "coin.wav")]));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("lane-fx")),
              matching: find.byWidgetPredicate((w) =>
                  w is CustomPaint &&
                  "${w.foregroundPainter.runtimeType}" ==
                      "_InteractiveLanePainter")),
          findsNothing);
      expect((c.document.master!.elements.single as AudioElement).clip.playlist,
          hasLength(1),
          reason: "written to the master, from the scene");
    });

    testWidgets("the top edge drags the timeline open and shut",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100));
      addTearDown(c.dispose);
      await pump(tester, host(c));
      expect(find.byKey(const ValueKey("lane-new")), findsNothing,
          reason: "no room for channels yet");

      var grip = find.byKey(const ValueKey("timelineGrip"));
      await tester.drag(grip, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CanvasTimeline)).height,
          closeTo(timelineHeight + 100, 25));
      expect(find.byKey(const ValueKey("lane-new")), findsOneWidget);

      await tester.drag(grip, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CanvasTimeline)).height, timelineHeight,
          reason: "never shorter than the keyframe strip");
    });

    // Ken's Game rules board: a stop that waits for an action.
    testWidgets("a stop is set to wait for an action", (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100, actions: [
        TimelineAction(frame: 0, kind: TimelineActionKind.stop),
      ]));
      addTearDown(c.dispose);
      await pump(tester, host(c));
      await openMarker(tester);
      var waits = find.byKey(const ValueKey("actionWaitsFor"));
      await tester.tap(waits);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Jump is pressed").last);
      await tester.pumpAndSettle();
      expect(c.document.actions.single.waitsFor, "jump");
      expect(tester.takeException(), isNull);
    });

    // Ken: the play bar over the timeline, or under it.
    testWidgets("the play bar goes under the timeline, and back over it",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100));
      addTearDown(c.dispose);
      await pump(tester, host(c));
      await tester.drag(
          find.byKey(const ValueKey("timelineGrip")), const Offset(0, -150));
      await tester.pumpAndSettle();
      double barY() => tester.getCenter(find.byKey(const ValueKey("play"))).dy;
      double laneY() =>
          tester.getCenter(find.byKey(const ValueKey("lane-new"))).dy;
      expect(barY(), lessThan(laneY()), reason: "over it, to begin with");
      await tapTimelineItem(tester, "barBelow");
      expect(barY(), greaterThan(laneY()), reason: "under the channels");
      expect(barY(),
          greaterThan(tester.getRect(find.byType(CanvasTimeline)).bottom - 50),
          reason: "at the bottom of the timeline");
      // Still the play bar: Play plays.
      await tester.tap(find.byKey(const ValueKey("play")));
      await tester.pump();
      expect(c.playing, isTrue);
      c.pause();
      // And the edge still drags it.
      var before = tester.getSize(find.byType(CanvasTimeline)).height;
      await tester.drag(
          find.byKey(const ValueKey("timelineGrip")), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CanvasTimeline)).height,
          greaterThan(before));
      await tapTimelineItem(tester, "barBelow");
      expect(barY(), lessThan(laneY()), reason: "back over it");
      expect(tester.takeException(), isNull);
    });
  });
}

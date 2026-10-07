import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_channels.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/space_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_timeline_view_test.dart is the timeline as one piece: a view of the
// frames shared by the keyframe strip and the channels, zoomed and scrolled;
// each channel's strip down the left; a level typed in; and the space bar
// playing from wherever the reader happens to be.

const song = "aaaaaaaaaaaaaaaa.mp3";

void main() {
  group("the view", () {
    test("whole is every frame, and the two directions agree", () {
      var v = TimelineView.whole(100);
      expect(v.isWhole(100), isTrue);
      expect(v.frameAt(v.centreOf(37, 500), 500, 100), 37);
      expect(v.xOf(0, 500), 0);
      expect(v.xOf(100, 500), 500);
    });

    // The playhead, a keyframe, the start of a sound and a cut are all on a
    // frame's leading edge. The playhead was drawn in the middle of its
    // frame, half a frame right of every cut made at it.
    test("the playhead is on the line a cut is made on", () {
      var v = const TimelineView(40, 8);
      expect(v.centreOf(42, 800), v.xOf(42, 800));
      expect(v.frameAt(v.xOf(42, 800) + 30, 800, 100), 42,
          reason: "nearer 42's line than 43's");
    });

    test("zooming keeps the frame under the pointer where it was", () {
      var v = TimelineView.whole(100);
      var z = v.zoomed(4, 40, 100);
      expect(z.span, 25);
      expect(z.xOf(40, 500), closeTo(v.xOf(40, 500), 0.001));
      expect(z.isWhole(100), isFalse);
    });

    test("it never goes past either end, or in past a few frames", () {
      var v = const TimelineView(90, 20).fitted(100);
      expect((v.first, v.span), (80.0, 20.0));
      expect(const TimelineView(-5, 20).fitted(100).first, 0);
      expect(
          TimelineView.whole(100).zoomed(1000, 50, 100).span, timelineMinSpan);
      expect(TimelineView.whole(100).zoomed(0.1, 50, 100).isWhole(100), isTrue);
    });

    test("playing, it pages on to keep the playhead on screen", () {
      var v = const TimelineView(0, 20);
      expect(v.following(10, 100), v, reason: "already on screen");
      var on = v.following(30, 100);
      expect(30 >= on.first && 31 <= on.first + on.span, isTrue);
    });
  });

  test("a typed level is read however it is written", () {
    expect(parseDb("-6"), -6);
    expect(parseDb("−6.5 dB"), -6.5);
    expect(parseDb("+3"), 3);
    expect(parseDb("12"), 6, reason: "no louder than the fader goes");
    expect(parseDb("-inf"), -90);
    expect(parseDb("-200"), -90);
    expect(parseDb("loud"), isNull);
  });

  group("on the timeline", () {
    Future<CanvasController> show(WidgetTester tester,
        {List<CanvasElement> elements = const []}) async {
      var c = CanvasController(
          CanvasDocument(frames: 100, frameRate: 10, elements: elements),
          audioEngine: FakeEngine(const {song: 10}));
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
              child:
                  CanvasTimeline(controller: c, height: timelineHeight + 120),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    AudioElement channel(String id, String name) =>
        AudioElement(ElementBase(id: id, name: name, visible: false),
            clip: const MediaClip(
                timed: true,
                playlist: [MediaSource(assetId: song, length: 4)]));

    /// frameAtEnd is the frame under the far right of the keyframe strip.
    Future<int> frameAtEnd(WidgetTester tester, CanvasController c) async {
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      await tester.tapAt(Offset(strip.right - 2, strip.top + 5));
      await tester.pump();
      return c.frame;
    }

    testWidgets("the strip and the lanes start at the same place",
        (tester) async {
      await show(tester, elements: [channel("a", "Music")]);
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      var lane = tester.getRect(find.byKey(const ValueKey("lane-a")));
      expect(lane.left, closeTo(strip.left, 0.5));
      expect(lane.right, closeTo(strip.right, 0.5));
      expect(lane.top - strip.bottom, lessThan(4),
          reason: "the first channel sits close under the strip");
    });

    // A channel's strip: an edge in its colour, S1 (the scene its clips are
    // on), its name when there is
    // room for a second line (double-clicked to rename it), its level, and
    // lock, solo and mute.
    testWidgets(
        "each channel's strip: its code, its name, and lock, solo "
        "and mute", (tester) async {
      var c = await show(tester, elements: [channel("a", "Music")]);
      var strip = find.byKey(const ValueKey("channelStrip-a"));
      Finder inStrip(String key) =>
          find.descendant(of: strip, matching: find.byKey(ValueKey(key)));
      expect(find.descendant(of: strip, matching: find.text("S1")), findsOne);
      expect(inStrip("channelName"), findsNothing,
          reason: "the name only once the lane is tall enough");
      // Its level as a number, which takes a typed one.
      await tester.tap(inStrip("channelLevel"));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey("dbEntry")), "-6");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((c.document.elements.single as AudioElement).clip.mix.gainDb, -6);
      expect(find.byKey(const ValueKey("channelGain")), findsNothing,
          reason: "no slider on the strip");

      await tester.tap(inStrip("channelMute"));
      await tester.pump();
      expect(
          (c.document.elements.single as AudioElement).clip.mix.mute, isTrue);
      await tester.tap(inStrip("channelSolo"));
      await tester.pump();
      expect(c.solo, {"a"});
      await tester.tap(inStrip("channelLock"));
      await tester.pump();
      expect(c.document.elements.single.locked, isTrue);

      c.setLaneHeight("a", 60);
      await tester.pump();
      expect(
          find.descendant(of: strip, matching: find.text("Music")), findsOne);
      await tester.tap(inStrip("channelName"));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(inStrip("channelName"));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("channelNameField")), "Drums");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect((c.document.elements.single as AudioElement).clip.channelName,
          "Drums");
    });

    testWidgets("zooming in shows fewer frames, on the strip and the lanes",
        (tester) async {
      var c = await show(tester, elements: [channel("a", "Music")]);
      expect(await frameAtEnd(tester, c), 99);

      c.frame = 0;
      await tester.tap(find.byKey(const ValueKey("timelineZoomIn")));
      await tester.pump();
      var end = await frameAtEnd(tester, c);
      expect(end, inInclusiveRange(45, 55), reason: "half the frames");

      await tester.tap(find.byKey(const ValueKey("timelineZoomFit")));
      await tester.pump();
      expect(await frameAtEnd(tester, c), 99);
    });

    // The play bar scrolls sideways itself, to reach what is along it --
    // an action's settings, say. That is not the frames being scrolled.
    // The length in seconds is level with the rate it is worked out from --
    // it sat a caption's height lower, the caption no longer being there.
    testWidgets("the seconds sit level with the rate", (tester) async {
      await show(tester);
      var rate = tester.getRect(find.byKey(const ValueKey("canvasFrameRate")));
      var seconds = tester.getRect(find.text("10.0s"));
      expect(seconds.center.dy, closeTo(rate.center.dy, 3));
    });

    testWidgets("the wheel over the play bar leaves the frames alone",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.byKey(const ValueKey("trackpadScrolls")));
      await tester.pump();
      c.frame = 0;
      await tester.tap(find.byKey(const ValueKey("timelineZoomIn")));
      await tester.pump();
      var end = await frameAtEnd(tester, c);

      var play = tester.getCenter(find.byKey(const ValueKey("play")));
      var mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(play));
      await tester.sendEventToBinding(mouse.scroll(const Offset(300, 0)));
      await tester.pump();
      expect(await frameAtEnd(tester, c), end);
    });

    testWidgets("Ctrl and the wheel zoom; the wheel scrolls only if allowed",
        (tester) async {
      var c = await show(tester);
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      var at = Offset(strip.left + 10, strip.center.dy);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      var mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -400)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      var end = await frameAtEnd(tester, c);
      expect(end, lessThan(60), reason: "zoomed in");

      // Off to begin with: a swipe up and down is for the channels, and
      // somebody who swipes finds the frames sliding under them.
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
      await tester.pump();
      expect(await frameAtEnd(tester, c), end, reason: "not scrolled");

      await tester.tap(find.byKey(const ValueKey("trackpadScrolls")));
      await tester.pump();
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
      await tester.pump();
      expect(await frameAtEnd(tester, c), greaterThan(end),
          reason: "switched on, it scrolls along");
    });
  });

  group("the space bar", () {
    Future<CanvasController> show(WidgetTester tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasSpaceBar(
            controller: c,
            child: Column(children: [
              TextButton(
                  key: const ValueKey("button"),
                  onPressed: () {},
                  child: const Text("A button")),
              const TextField(key: ValueKey("field")),
            ]),
          ),
        ),
      ));
      return c;
    }

    testWidgets("plays and stops with a button focused, and does not press it",
        (tester) async {
      var c = await show(tester);
      var pressed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CanvasSpaceBar(
            controller: c,
            child: TextButton(
                key: const ValueKey("button"),
                onPressed: () => pressed++,
                child: const Text("A button")),
          ),
        ),
      ));
      Focus.of(tester.element(find.text("A button"))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isTrue);
      expect(pressed, 0, reason: "the button did not take the space");

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isFalse);
    });

    // The chat beside the canvas is outside it. With its box focused, a
    // click on the canvas -- somewhere that takes no focus of its own, like
    // the empty part of the timeline -- left the focus in the chat, and
    // space went there.
    testWidgets("a click inside brings the focus back from outside",
        (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const SizedBox(width: 200, child: TextField(key: ValueKey("chat"))),
            Expanded(
              child: CanvasSpaceBar(
                controller: c,
                child:
                    Container(key: const ValueKey("empty"), color: Colors.grey),
              ),
            ),
          ]),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey("chat")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("empty")));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isTrue);
      c.pause();
    });

    testWidgets("types a space in a field, and leaves the timeline alone",
        (tester) async {
      var c = await show(tester);
      await tester.tap(find.byKey(const ValueKey("field")));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isFalse);
    });

    testWidgets("does nothing under a dialog", (tester) async {
      var c = await show(tester);
      showDialog<void>(
          context: tester.element(find.byKey(const ValueKey("button"))),
          builder: (_) => const AlertDialog(content: Text("Over it")));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isFalse);
    });
  });

  group("channels", () {
    AudioElement onChannel(String id, String channel,
            {int at = 0, double seconds = 4}) =>
        AudioElement(ElementBase(id: id, name: id, visible: false),
            clip: MediaClip(
                timed: true,
                at: at,
                channel: channel,
                channelName: "Audio $channel",
                playlist: [
                  MediaSource(assetId: song, length: seconds, name: id)
                ]));

    CanvasController made(List<CanvasElement> elements) {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 10, elements: elements),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(c.dispose);
      return c;
    }

    test("sounds sharing a channel are one channel, in the order they come",
        () {
      var c = made([
        onChannel("a", "1"),
        onChannel("b", "2", at: 10),
        onChannel("c", "1", at: 60),
      ]);
      var channels = c.timelineChannels;
      expect([for (var ch in channels) ch.key], ["1", "2"]);
      expect([for (var l in channels.first.lanes) l.element.id], ["a", "c"]);
      expect(channels.first.name, "Audio 1");
    });

    test("a channel's level is every sound's on it, in one undo step", () {
      var c = made([onChannel("a", "1"), onChannel("b", "1", at: 60)]);
      c.setChannelMix(c.timelineChannels.single, const ChannelMix(gainDb: -6));
      for (var e in c.document.elements.cast<AudioElement>()) {
        expect(e.clip.mix.gainDb, -6);
      }
      c.undo();
      for (var e in c.document.elements.cast<AudioElement>()) {
        expect(e.clip.mix.gainDb, 0);
      }
    });

    test(
        "a sound moved off its channel takes the new one's strip; the "
        "channel it leaves goes when it was the last", () {
      var c = made([
        onChannel("a", "1"),
        onChannel("b", "2", at: 60),
      ]);
      c.setChannelMix(c.timelineChannels.last, const ChannelMix(gainDb: -3));
      var a = c.timedLanes.firstWhere((l) => l.element.id == "a");
      c.moveClipToChannel(a, c.timelineChannels.last);
      expect([for (var ch in c.timelineChannels) ch.key], ["2"],
          reason: "channel 1 had nothing left on it");
      var moved = c.document.elementById("a") as AudioElement;
      expect(moved.clip.mix.gainDb, -3);
      expect(moved.clip.channelName, "Audio 2");

      c.moveClipToChannel(
          c.timedLanes.firstWhere((l) => l.element.id == "a"), null);
      expect(c.timelineChannels, hasLength(2), reason: "a channel of its own");
    });

    test("the knife cuts a sound in two where it is pressed", () {
      var c = made([onChannel("a", "1", at: 20, seconds: 4)]);
      var lane = c.timedLanes.single;
      expect(c.splitClip(lane, 35), isTrue);
      var sounds = c.document.elements.cast<AudioElement>().toList();
      expect(sounds, hasLength(2));
      expect(sounds.first.clip.playlist.single.end, closeTo(1.5, 0.001));
      expect(sounds.last.clip.at, 35);
      expect(sounds.last.clip.playlist.single.start, closeTo(1.5, 0.001));
      expect(sounds.last.clip.channel, "1", reason: "on the same channel");
      expect(c.timelineChannels.single.lanes, hasLength(2));
      c.undo();
      expect(c.document.elements, hasLength(1), reason: "one undo step");
    });

    test("a sound pasted goes to the playhead, on its channel", () {
      var c = made([onChannel("a", "1", at: 0)]);
      c.selectOnly("a");
      c.copySelected();
      c.frame = 90;
      c.paste();
      var sounds = c.document.elements.cast<AudioElement>().toList();
      expect(sounds, hasLength(2));
      expect(sounds.last.clip.at, 90);
      expect(sounds.last.clip.channel, "1");
    });

    test("the empty channels Add audio used to leave are cleared on opening",
        () {
      var c = made(const []);
      c.load(CanvasDocument(frames: 100, elements: [
        AudioElement(const ElementBase(id: "empty", visible: false),
            clip: const MediaClip(timed: true)),
        onChannel("a", "1"),
      ]));
      expect([for (var e in c.document.elements) e.id], ["a"]);
    });

    Future<CanvasController> show(
        WidgetTester tester, List<CanvasElement> elements) async {
      var c = made(elements);
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
            body: CanvasSpaceBar(
              controller: c,
              child: Align(
                alignment: Alignment.bottomCenter,
                child:
                    CanvasTimeline(controller: c, height: timelineHeight + 160),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    // Two fingers on a trackpad scroll the channels. A drag recognizer takes
    // a trackpad's pan as a drag, so a swipe over the strip scrubbed the
    // playhead back towards the start, and one over a sound dragged it.
    testWidgets("a two-finger swipe neither scrubs nor drags", (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 20, seconds: 4)]);
      c.frame = 80;
      await tester.pump();
      for (var at in [
        tester.getCenter(find.byKey(const ValueKey("keyframeStrip"))),
        tester.getRect(find.byKey(const ValueKey("lane-1"))).centerLeft +
            const Offset(60, 0),
      ]) {
        var fingers =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await fingers.panZoomStart(at);
        for (var i = 1; i <= 6; i++) {
          await fingers.panZoomUpdate(at, pan: Offset(0, -12.0 * i));
          await tester.pump();
        }
        await fingers.panZoomEnd();
        await tester.pumpAndSettle();
        expect(c.frame, 80, reason: "the playhead stays where it was");
        expect((c.document.elements.single as AudioElement).clip.at, 20,
            reason: "and the sound where it was");
      }
    });

    // A sound on the timeline is on a channel, not on the canvas: not in the
    // layers, not taken by select-all, and its settings are a sound's --
    // no speaker, no place on the page.
    test("select-all takes the canvas, not the soundtrack", () {
      var c = made([
        onChannel("a", "1"),
        AudioElement(const ElementBase(id: "speaker"),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: song, length: 4)])),
      ]);
      c.selectAll();
      expect(c.selection, {"speaker"});
    });

    // Picked on its channel, a sound is selected -- and is still not on the
    // canvas: a box with handles for it was an empty element on the page.
    testWidgets("a selected timeline sound has no box on the canvas",
        (tester) async {
      var c = made([onChannel("a", "1")]);
      c.selectOnly("a");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 800,
                    height: 600,
                    child: CanvasStage(controller: c)))),
      ));
      await tester.pump();
      var painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<StagePainter>()
          .single;
      expect(painter.selectionBounds, isNull);
      expect(painter.selection, isEmpty);
      expect(c.selection, {"a"}, reason: "still selected, for its settings");
    });

    testWidgets("the layers list leaves the timeline's sounds out",
        (tester) async {
      var c = made([
        onChannel("a", "1"),
        AudioElement(const ElementBase(id: "speaker", name: "Speaker"),
            clip: const MediaClip(
                playlist: [MediaSource(assetId: song, length: 4)])),
      ]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 300,
                    height: 500,
                    child: CanvasLayersPanel(controller: c)))),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey("speaker")), findsOneWidget);
      expect(find.byKey(const ValueKey("a")), findsNothing);
    });

    testWidgets("a timeline sound's settings are a sound's, not a speaker's",
        (tester) async {
      var c = made([onChannel("a", "1")]);
      c.selectOnly("a");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: Column(
                    children: elementSettings(
                        context, c, c.document.elementById("a")!)),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text("Reader's controls"), findsNothing);
      expect(find.text("Icon"), findsNothing);
      expect(find.text("Volume"), findsOneWidget, reason: "how it plays");
    });

    // K -- or T -- cuts the channel picked where the playhead is. The knife
    // on the tools is for cutting where the pointer is.
    testWidgets(
        "K cuts the picked channel at the playhead; the knife where "
        "it is clicked", (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      await tester.tapAt(Offset(lane.left + lane.width / 4, lane.center.dy));
      await tester.pump();
      expect(c.selectedChannel, "1");
      c.frame = 30;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(c.timelineTool, TimelineTool.select, reason: "no tool change");
      var sounds = c.document.elements.cast<AudioElement>().toList();
      expect(sounds, hasLength(2));
      expect(sounds.last.clip.at, 30);

      await tester.tap(find.byKey(const ValueKey("toolKnife")));
      await tester.pump();
      // A quarter of the way along a two-hundred-frame view is frame 50.
      await tester.tapAt(Offset(lane.left + lane.width / 4, lane.center.dy));
      await tester.pump();
      expect(c.document.elements, hasLength(3));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      expect(c.timelineTool, TimelineTool.select);
    });

    // A sound's own line: dragged down, that sound is quieter -- the
    // channel's strip, and every other sound on it, are left alone.
    testWidgets("a sound's volume line turns that sound alone down",
        (tester) async {
      var c = await show(tester, [
        onChannel("a", "1", at: 0, seconds: 5),
        onChannel("b", "1", at: 100, seconds: 5),
      ]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      // Where the line of a sound at 0.8 is: a straight fade below nought
      // decibels, which sits 0.45 of the way down, inset eight pixels.
      var h = lane.height;
      var lineY = lane.top + 8 + (0.45 + 0.2 * 0.55) * (h - 16);
      // A mouse, as it is at a desk: a finger's short vertical drag is the
      // list's, to scroll the channels.
      await tester.dragFrom(
          Offset(lane.left + lane.width / 8, lineY), const Offset(0, 6),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      var a = c.document.elementById("a") as AudioElement;
      var b = c.document.elementById("b") as AudioElement;
      expect(a.clip.volume, lessThan(0.75));
      expect(a.clip.at, 0, reason: "a volume, not a move");
      expect(b.clip.volume, 0.8, reason: "the other sound is untouched");
      expect(a.clip.mix.gainDb, 0, reason: "and so is the channel's strip");
    });

    testWidgets("with snapping on, a dragged sound lands on the playhead",
        (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      c.frame = 47;
      c.snapping = true;
      await tester.pump();
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var perFrame = lane.width / 200;
      await tester.dragFrom(Offset(lane.left + lane.width / 8, lane.bottom - 6),
          Offset(perFrame * 46, 0));
      await tester.pumpAndSettle();
      expect((c.document.elements.single as AudioElement).clip.at, 47);

      c.snapping = false;
      c.undo();
      await tester.pump();
      await tester.dragFrom(Offset(lane.left + lane.width / 8, lane.bottom - 6),
          Offset(perFrame * 46, 0));
      await tester.pumpAndSettle();
      expect(
          (c.document.elements.single as AudioElement).clip.at, closeTo(46, 1));
    });

    testWidgets("a locked channel's sounds stay where they are",
        (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      c.lockChannel(c.timelineChannels.single, true);
      await tester.pump();
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      await tester.dragFrom(Offset(lane.left + lane.width / 8, lane.bottom - 6),
          const Offset(80, 0));
      await tester.pumpAndSettle();
      expect((c.document.elements.single as AudioElement).clip.at, 0);
      c.frame = 30;
      expect(c.cutAtPlayhead(), isFalse, reason: "nor are they cut");
    });

    test("a video's channel is yellow, a sound's green", () {
      expect(channelColour(true), isNot(channelColour(false)));
    });

    testWidgets("a sound clicked stays picked, and Backspace takes it",
        (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      await tester.tapAt(Offset(lane.left + lane.width / 4, lane.center.dy));
      await tester.pump();
      expect(c.selection, {"a"});
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(c.document.elements, isEmpty);
      expect(c.timelineChannels, isEmpty, reason: "and its channel with it");
      c.undo();
      expect(c.document.elements, hasLength(1));
    });

    testWidgets("the top corner of a sound drags a fade in", (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var perFrame = lane.width / 200;
      await tester.dragFrom(
          lane.topLeft + const Offset(2, 4), Offset(perFrame * 20, 0));
      await tester.pumpAndSettle();
      var clip = (c.document.elements.single as AudioElement).clip;
      expect(clip.fadeIn, closeTo(2, 0.3),
          reason: "twenty frames at ten a "
              "second");
      expect(clip.at, 0, reason: "a fade, not a move");
    });

    // Every width the strips can be dragged to, at a short lane and a tall
    // one: nothing in them overflows. At the narrowest the code alone was
    // wider than the room left for it, and the empty lane's strip was a
    // pixel over too.
    testWidgets("the strips fit at every width and height", (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      for (var h in [26.0, 60.0, 160.0]) {
        c.setLaneHeight("1", h);
        for (var w = timelineHeaderMin; w <= timelineHeaderMax; w += 3) {
          c.headerWidth = w;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: "at $w wide, $h tall");
        }
      }
    });

    testWidgets("a lane is dragged taller, and a strip narrowed to its code",
        (tester) async {
      var c = await show(tester, [onChannel("a", "1", at: 0, seconds: 10)]);
      var before = tester.getSize(find.byKey(const ValueKey("lane-1"))).height;
      await tester.drag(
          find.byKey(const ValueKey("laneGrip-1")), const Offset(0, 40));
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey("lane-1"))).height,
          greaterThan(before + 30));

      var strip = find.byKey(const ValueKey("channelStrip-1"));
      bool has(String key) => find
          .descendant(of: strip, matching: find.byKey(ValueKey(key)))
          .evaluate()
          .isNotEmpty;
      expect([has("channelLock"), has("channelSolo"), has("channelMute")],
          [true, true, true]);
      c.headerWidth = 120;
      await tester.pump();
      expect([
        has("channelLock"),
        has("channelSolo"),
        has("channelMute")
      ], [
        false,
        true,
        true
      ], reason: "the lock goes first");
      c.headerWidth = 90;
      await tester.pump();
      expect([has("channelSolo"), has("channelMute")], [false, true]);
      c.headerWidth = 40;
      await tester.pump();
      expect(has("channelMute"), isFalse);
      expect(find.descendant(of: strip, matching: find.text("S1")), findsOne,
          reason: "and it is its code");
    });
  });

  group("the channels, picked and turned up", () {
    AudioElement sound(String id, String channel, {int at = 0}) =>
        AudioElement(ElementBase(id: id, name: id, visible: false),
            clip: MediaClip(
                timed: true,
                at: at,
                volume: 1,
                channel: channel,
                channelName: "Audio $channel",
                playlist: const [MediaSource(assetId: song, length: 4)]));

    Future<CanvasController> show(
        WidgetTester tester, List<CanvasElement> elements) async {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 10, elements: elements),
          audioEngine: FakeEngine(const {song: 10}));
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
            body: CanvasSpaceBar(
              controller: c,
              child: Align(
                alignment: Alignment.bottomCenter,
                child:
                    CanvasTimeline(controller: c, height: timelineHeight + 160),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    // Nought decibels sits a little above the middle, so a quiet sound can
    // be turned up -- six decibels at the top.
    testWidgets("a sound's line goes up past nought, to six decibels",
        (tester) async {
      var c = await show(tester, [sound("a", "1")]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var lineY = lane.top + 8 + 0.45 * (lane.height - 16);
      expect(lineY - lane.top, lessThan(lane.height / 2),
          reason: "nought is above the middle");
      await tester.dragFrom(Offset(lane.left + 40, lineY), const Offset(0, -40),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      var clip = (c.document.elements.single as AudioElement).clip;
      expect(clip.volume, closeTo(2, 0.01), reason: "six decibels up");
      expect(MediaClip.fromJson(clip.toJson()).volume, closeTo(2, 0.01),
          reason: "and kept that way");
    });

    testWidgets("a box dragged across the lanes picks what it touches",
        (tester) async {
      var c = await show(tester, [
        sound("a", "1"),
        sound("b", "2", at: 10),
        sound("c", "2", at: 150),
      ]);
      var one = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var two = tester.getRect(find.byKey(const ValueKey("lane-2")));
      // From empty lane past the end of "a", up over both, back across them.
      var from = Offset(one.left + one.width * 0.6, one.top + 4);
      var to = Offset(one.left + 20, two.bottom - 4);
      await tester.dragFrom(from, to - from, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(c.selection, {"a", "b"});
      expect(c.selectedChannels, {"1", "2"});
    });

    testWidgets(
        "shift adds a sound to what is picked; dragging one moves "
        "them all", (tester) async {
      var c = await show(tester, [sound("a", "1"), sound("b", "2", at: 10)]);
      var one = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var two = tester.getRect(find.byKey(const ValueKey("lane-2")));
      await tester.tapAt(Offset(one.left + 20, one.bottom - 6));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(Offset(two.left + 60, two.bottom - 6));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.selection, {"a", "b"});
      expect(c.selectedChannels, {"1", "2"});

      var perFrame = one.width / 200;
      await tester.dragFrom(
          Offset(one.left + 20, one.bottom - 6), Offset(perFrame * 20, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      int at(String id) => (c.document.elementById(id) as AudioElement).clip.at;
      expect(at("a"), closeTo(20, 1));
      expect(at("b"), closeTo(30, 1), reason: "moved with it");
    });

    testWidgets("the pointer says what a press would take hold of",
        (tester) async {
      await show(tester, [sound("a", "1", at: 0)]);
      var lane = tester.getRect(find.byKey(const ValueKey("lane-1")));
      var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      // The lane's own pointer, as it is set from what is under it.
      MouseCursor cursorAt(Offset at) => tester
          .widget<MouseRegion>(find
              .descendant(
                  of: find.byKey(const ValueKey("lane-1")),
                  matching: find.byType(MouseRegion))
              .first)
          .cursor;

      var lineY = lane.top + 8 + 0.45 * (lane.height - 16);
      var perFrame = lane.width / 200;
      for (var (at, want) in [
        (Offset(lane.left + 60, lane.bottom - 6), SystemMouseCursors.basic),
        (Offset(lane.left + 60, lineY), SystemMouseCursors.resizeUpDown),
        (
          Offset(lane.left + perFrame * 40, lane.bottom - 6),
          SystemMouseCursors.resizeLeftRight
        ),
      ]) {
        await mouse.moveTo(at);
        await tester.pump();
        expect(cursorAt(at), want, reason: "at $at");
      }
    });

    testWidgets("a flag is dragged along the ruler, and keeps a label",
        (tester) async {
      var c = await show(tester, const []);
      c.apply(c.document.copyWith(actions: const [
        TimelineAction(frame: 10, kind: TimelineActionKind.stop),
      ]));
      c.frame = 10;
      await tester.pump();
      var strip = tester.getRect(find.byKey(const ValueKey("keyframeStrip")));
      var perFrame = strip.width / 200;
      await tester.dragFrom(
          Offset(strip.left + perFrame * 10 + 4, strip.top + 5),
          Offset(perFrame * 20, 0),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(c.document.actions.single.frame, closeTo(30, 1));
      expect(c.frame, c.document.actions.single.frame,
          reason: "the playhead goes with it, so its settings are showing");

      var label = find.byKey(const ValueKey("actionLabel"));
      await tester.ensureVisible(label);
      await tester.enterText(
          find.descendant(of: label, matching: find.byType(TextField)),
          "Chorus");
      await tester.pump();
      expect(c.document.actions.single.label, "Chorus");
      expect(c.document.actions.single.showLabel, isTrue);
      var round = TimelineAction.fromJson(c.document.actions.single.toJson());
      expect(round.label, "Chorus");
    });

    testWidgets("the timeline goes down to its play bar alone", (tester) async {
      var c = CanvasController(const CanvasDocument(frames: 100),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
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
              child: CanvasTimeline(
                  controller: c, height: timelineCollapsedHeight),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CanvasTimeline)).height,
          closeTo(timelineCollapsedHeight, 0.5));
      expect(find.byKey(const ValueKey("keyframeStrip")), findsNothing);
      expect(find.byKey(const ValueKey("toFirstFrame")), findsOneWidget,
          reason: "the play bar is all there is");
    });
  });

  group("video on the timeline", () {
    VideoElement video({int at = 20}) => VideoElement(
        const ElementBase(id: "v", x: 10, y: 10, width: 160, height: 90),
        clip: MediaClip(
            timed: true,
            at: at,
            playlist: const [MediaSource(assetId: song, length: 4)]));

    // Cut in two, a video is two videos in the same place: the second half
    // starts where the cut was, and each is on screen while its half plays.
    test("the knife cuts a video into two halves", () {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 10, elements: [video()]),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(c.dispose);
      var lane = c.timedLanes.single;
      expect(c.splitClip(lane, 35), isTrue);
      var halves = c.document.elements.cast<VideoElement>().toList();
      expect(halves, hasLength(2));
      expect(halves.last.clip.at, 35);
      expect(halves.last.bounds, halves.first.bounds,
          reason: "the same place on the canvas");
      expect(halves.first.clip.playlist.single.end, closeTo(1.5, 0.001));
    });

    // A video put on the timeline from its settings has no channel of its
    // own; cut, both halves go on one, rather than the second starting
    // another lane.
    test("both halves stay on one channel", () {
      var c = CanvasController(
          CanvasDocument(frames: 200, frameRate: 10, elements: [video()]),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(c.dispose);
      expect(c.splitClip(c.timedLanes.single, 35), isTrue);
      expect(c.timelineChannels, hasLength(1));
      expect(c.timelineChannels.single.lanes, hasLength(2));
      var after = c.timedLanes.last;
      expect(c.splitClip(after, 45), isTrue, reason: "and cut again");
      expect(c.timelineChannels, hasLength(1));
      expect(c.timelineChannels.single.lanes, hasLength(3));
    });

    test("a video can join a sound's channel, one after the other", () {
      var sound = AudioElement(const ElementBase(id: "s"),
          clip: const MediaClip(
              timed: true,
              at: 100,
              channel: "ch1",
              channelName: "Channel 1",
              playlist: [MediaSource(assetId: song, length: 4)]));
      var c = CanvasController(
          CanvasDocument(
              frames: 200, frameRate: 10, elements: [video(), sound]),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(c.dispose);
      expect(c.timelineChannels, hasLength(2));
      var lane = c.timedLanes.firstWhere((l) => l.element.id == "v");
      var to = c.timelineChannels.firstWhere((ch) => ch.key == "ch1");
      c.moveClipToChannel(lane, to);
      expect(c.timelineChannels, hasLength(1));
      expect(c.timelineChannels.single.name, "Channel 1");
      expect(c.timelineChannels.single.lanes, hasLength(2));
    });

    // A clip longer than the scene: the timeline runs on to its end, so the
    // rest of it can be scrolled to and trimmed.
    test("the timeline reaches the end of a clip past the scene", () {
      var c = CanvasController(
          CanvasDocument(
              frames: 200, frameRate: 10, elements: [video(at: 180)]),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(c.dispose);
      expect(c.timelineReach, 220, reason: "180 plus four seconds at ten");
      expect(c.document.frames, 200, reason: "the scene is not lengthened");

      var short = CanvasController(
          CanvasDocument(frames: 200, frameRate: 10, elements: [video()]),
          audioEngine: FakeEngine(const {song: 10}));
      addTearDown(short.dispose);
      expect(short.timelineReach, 200);
    });

    test("a video on the timeline is on screen only while it plays", () {
      var doc = CanvasDocument(frames: 200, frameRate: 10, elements: [video()]);
      var clip = (doc.elements.single as VideoElement).clip;
      expect(doc.offTimeline(clip, 10), isTrue, reason: "before it starts");
      expect(doc.offTimeline(clip, 30), isFalse, reason: "while it plays");
      expect(doc.offTimeline(clip, 70), isTrue, reason: "after it ends");
      expect(doc.offTimeline(clip.copyWith(timed: false), 10), isFalse,
          reason: "a video not on the timeline is always there");
    });
  });
}

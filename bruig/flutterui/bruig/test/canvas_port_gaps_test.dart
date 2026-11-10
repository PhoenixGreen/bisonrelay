import 'dart:convert';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/dock_switcher.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/marker_note.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart';
import 'package:bruig/plugin_system/canvas/ui/play_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/row_header.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_port_gaps_test.dart is the approved mixer/timeline design's pieces
// the audit found missing (BUILD_PLAN "Port gaps" 6-13): a strip's ×N and
// All; an element's motion devices first in its devices band; a minimised
// devices band saying how many; a fold arrow on every row; the cue column's
// "?" and scroll bar; "not in cues" under the Scenes strip's slots; the
// minimised lines; a ✕ on every help note.

AudioElement sound(String id, String name) =>
    AudioElement(ElementBase(id: id, name: name, visible: false),
        clip: MediaClip(timed: true, channelName: name), controls: const []);

/// coin is reused three times and wiggles; leaf oscillates, with no sound.
CanvasController make() {
  var c = CanvasController(
      CanvasDocument(
        frames: 240,
        scenes: [
          CanvasScene(id: "one", elements: [
            ShapeElement(ElementBase(
                id: "a",
                name: "Coin",
                motion: ElementMotion(
                    devices: const [MotionDevice(MotionDeviceKind.wiggle)],
                    instances: const InstanceSet().withCount(3, gap: 40)))),
            const ShapeElement(ElementBase(
                id: "b",
                name: "Leaf",
                motion: ElementMotion(
                    devices: [MotionDevice(MotionDeviceKind.oscillate)]))),
          ]),
          const CanvasScene(id: "two"),
        ],
        master: CanvasScene(id: "m", elements: [sound("music", "Music")]),
        masterOn: true,
      ),
      audioEngine: FakeEngine({}));
  c.ensureElementSound("a");
  return c;
}

Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: child))),
    );

void main() {
  Future<CanvasController> mixer(WidgetTester tester,
      {double height = 720}) async {
    var c = make();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(CanvasMixer(
        controller: c, height: height, onResize: (_) {}, onClose: () {})));
    await tester.pump();
    return c;
  }

  Finder inStrip(String strip, Finder f) =>
      find.descendant(of: find.byKey(ValueKey(strip)), matching: f);

  testWidgets("a reused element's strip says ×3; the master's sound, All",
      (tester) async {
    await mixer(tester);
    expect(inStrip("motionStrip-a", find.text("×3")), findsWidgets);
    expect(find.byKey(const ValueKey("stripAll-music")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "its motion devices come first in its devices band, and open the "
      "Chain on its motion", (tester) async {
    var c = await mixer(tester);
    var instances = inStrip("motionStrip-a",
        find.byKey(const ValueKey("motionDeviceSlot-a-instances")));
    var wiggle = inStrip(
        "motionStrip-a", find.byKey(const ValueKey("motionDeviceSlot-a-0")));
    // Its sound's first slot: where the sound goes.
    var out = inStrip(
        "motionStrip-a", find.byKey(const ValueKey("elementSoundOut-a")));
    expect(instances, findsOneWidget);
    expect(wiggle, findsOneWidget);
    expect(find.descendant(of: wiggle, matching: find.text("Wiggle")),
        findsOneWidget);
    expect(tester.getRect(instances).top, lessThan(tester.getRect(wiggle).top),
        reason: "its Instances first");
    expect(tester.getRect(wiggle).top, lessThan(tester.getRect(out).top),
        reason: "the motion's devices before the sound's");
    // The element with no sound of its own: its motion devices too.
    expect(
        inStrip("motionStrip-b",
            find.byKey(const ValueKey("motionDeviceSlot-b-0"))),
        findsOneWidget);
    await tester.tap(wiggle);
    await tester.pump();
    expect(c.selection, {"a"});
    expect(c.animationOpen, isTrue, reason: "the Chain on its motion");
  });

  testWidgets("devices minimised: how many there are, motion and sound",
      (tester) async {
    var c = await mixer(tester);
    c.setMixerSection(MixerSection.devices, BandState.minimised);
    await tester.pump();
    expect(inStrip("motionStrip-a", find.byKey(const ValueKey("devicesCount"))),
        findsOneWidget);
    expect(inStrip("motionStrip-b", find.text("1 device")), findsOneWidget,
        reason: "the leaf's one motion device");
    expect(
        inStrip(
            "motionStrip-a", find.byKey(const ValueKey("elementSoundOut-a"))),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "the mixer minimised: the scenes' transitions counted, and no sound "
      "said", (tester) async {
    var c = await mixer(tester);
    c.setMixerSection(MixerSection.mixer, BandState.minimised);
    await tester.pump();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("sceneMotionLine")),
            matching: find.text("1 transition")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("noSound-b")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "the Scenes strip's slots are not in cues; the cue column has a ? "
      "and a scroll bar", (tester) async {
    await mixer(tester);
    expect(find.byKey(const ValueKey("sceneNotInCues")), findsOneWidget);
    expect(find.byKey(const ValueKey("cueScrollbar")), findsOneWidget);
    expect(find.byKey(const ValueKey("help-cues")), findsOneWidget);
  });

  testWidgets(
      "a rail band's picker: a picture of each choice, a note, a ✕; amber "
      "when stepped down for room", (tester) async {
    var c = await mixer(tester);
    await tester.tap(find.byKey(const ValueKey("section-devices")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("railPicker-devices")), findsOneWidget);
    expect(find.textContaining("how many devices"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("section-devices-minimised")));
    await tester.pumpAndSettle();
    expect(c.mixerBandNames[MixerSection.devices.index], "minimised");
    expect(find.byKey(const ValueKey("railPicker-devices")), findsNothing,
        reason: "a choice closes it");
    await tester.tap(find.byKey(const ValueKey("section-devices")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("railPickerClose-devices")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("railPicker-devices")), findsNothing);
    // Short of height: a band stepped down, its picker saying so.
    await tester.pumpWidget(host(CanvasMixer(
        controller: c, height: 300, onResize: (_) {}, onClose: () {})));
    await tester.pump();
    var stepped = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith("railAuto-"));
    expect(stepped, findsWidgets);
    var band = (tester.widget(stepped.first).key as ValueKey<String>)
        .value
        .substring("railAuto-".length);
    await tester.tap(find.byKey(ValueKey("section-$band")));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey("railPickerAuto-$band")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a help note closes from its ✕", (tester) async {
    await mixer(tester);
    await tester.tap(find.byKey(const ValueKey("help-cues")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("helpText-cues")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("helpClose-cues")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("helpText-cues")), findsNothing);
  });

  testWidgets(
      "at M the layers share one band, \"2 layers\"; at L a band each, by "
      "name, a pinned one's bar striped", (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 240, elements: [
          const ShapeElement(ElementBase(id: "a", name: "Coin")),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    var spin = c.newClip("a", kind: MotionKind.loop, layer: 0);
    var bob = c.newClip("a", kind: MotionKind.action, layer: 1);
    c.placeClip("a", spin, seconds: 0);
    c.placeClip("a", bob, seconds: 1);
    c.pinLayer("a", 1, true);
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(CanvasTimeline(controller: c, height: 500)));
    await tester.pumpAndSettle();
    expect(c.laneSize, 1);
    expect(find.text("2 layers"), findsWidgets);
    var m = c.motionOf("a");
    var paint = find.byKey(const ValueKey("motionLanesPaint-a"));
    var shared = tester.getSize(paint).height;
    c.nextLaneSize();
    await tester.pumpAndSettle();
    expect(c.laneSize, 2);
    expect(find.text(motionLayerName(m, 0)), findsWidgets);
    expect(find.text(motionLayerName(m, 1)), findsWidgets);
    expect(tester.getSize(paint).height, greaterThan(shared),
        reason: "a band for each layer");
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "a level held by hand: an amber ◉; muted, M lit; the tempo, metre and "
      "frame rate on the bar", (tester) async {
    var c = CanvasController(
        CanvasDocument(frames: 300, frameRate: 30, elements: [
          AudioElement(const ElementBase(id: "v", name: "Vocals"),
              clip: const MediaClip(
                  playlist: [MediaSource(assetId: "t", length: 10)],
                  timed: true,
                  mix: ChannelMix(gainDb: -3, automation: [
                    AutomationLane("volume", [(0, -30), (2, 0)]),
                  ]))),
        ]),
        audioEngine: FakeEngine({"t": 10}));
    addTearDown(c.dispose);
    // Wide enough for the bar to show its tempo.
    tester.view.physicalSize = const Size(2200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      CanvasPlayBar(controller: c),
      CanvasMixer(controller: c, height: 600, onResize: (_) {}, onClose: () {}),
    ])));
    await tester.pump();
    expect(find.byKey(const ValueKey("faderAutomated")), findsOneWidget);
    expect(find.byKey(const ValueKey("faderHeld")), findsNothing);
    c.frame = 30;
    var shown = c.mixNow(c.timelineChannels.single);
    c.changeChannelMix(
        c.timelineChannels.single, shown, shown.copyWith(gainDb: -8));
    await tester.pump();
    expect(find.byKey(const ValueKey("faderHeld")), findsOneWidget);
    expect(find.byKey(const ValueKey("faderAutomated")), findsNothing);
    // M: not lit, then lit once muted.
    var mute = inStrip("strip-v", find.byKey(const ValueKey("mute")));
    expect(find.descendant(of: mute, matching: find.text("M")), findsOneWidget);
    await tester.tap(mute);
    await tester.pump();
    expect(c.timelineChannels.single.mix.mute, isTrue);
    // The tempo, its metre and the frame rate, on any canvas.
    // The bar measures itself before it shows what fits.
    await tester.pump();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("playBarTempo")),
            matching: find.text("4/4 · 30 fps")),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group("a marker's label on the canvas", () {
    CanvasController held({bool shown = true}) => CanvasController(
        CanvasDocument(frames: 40, actions: [
          TimelineAction(
              frame: 3,
              kind: TimelineActionKind.stop,
              label: "Press to jump",
              showLabel: shown),
          const TimelineAction(
              frame: 10,
              kind: TimelineActionKind.pause,
              label: "Get ready",
              holdFrames: 4),
        ]),
        audioEngine: FakeEngine({}));

    test("while a stop holds playback, or a pause, where it is shown", () {
      var c = held();
      addTearDown(c.dispose);
      expect(c.holdingMarker, isNull);
      c.play();
      for (var i = 0; i < 3; i++) {
        c.tickForTest();
      }
      expect(c.frame, 3);
      expect(c.playing, isFalse, reason: "the stop stopped it");
      expect(c.holdingMarker?.label, "Press to jump");
      c.frame = 5;
      expect(c.holdingMarker, isNull, reason: "moved off it");
      c.play();
      for (var i = 0; i < 5; i++) {
        c.tickForTest();
      }
      expect(c.frame, 10);
      expect(c.holdingMarker?.label, "Get ready", reason: "the pause holds");
      for (var i = 0; i < 5; i++) {
        c.tickForTest();
      }
      expect(c.holdingMarker, isNull, reason: "and goes on");
      c.pause();
    });

    test("hidden on the canvas: none", () {
      var c = held(shown: false);
      addTearDown(c.dispose);
      c.play();
      for (var i = 0; i < 3; i++) {
        c.tickForTest();
      }
      expect(c.frame, 3);
      expect(c.holdingMarker, isNull);
    });

    // Ken: the note "can't be moved or scaled on the canvas ... when the
    // screen is small it covers the whole screen rather than keeps its
    // proportions like the other elements do". It is on the canvas, in its
    // units, where its marker puts it, as big as it says.
    test("the note is on the canvas, where and as big as its marker says", () {
      const a = TimelineAction(
          frame: 3, kind: TimelineActionKind.stop, label: "Press to jump");
      var big = markerNoteLayout(const Size(1920, 1080), a);
      var small = markerNoteLayout(const Size(960, 540), a);
      expect(small.box.height, closeTo(big.box.height / 2, 1),
          reason: "half the canvas, half the note");
      expect(big.box.center, const Offset(960, 1080 * 0.92),
          reason: "the foot of the canvas, in the middle, at first");
      var moved = a.copyWith(noteAt: const Offset(0.25, 0.1), noteSize: 2);
      var there = markerNoteLayout(const Size(1920, 1080), moved);
      expect(there.box.center, const Offset(480, 108));
      expect(there.box.height, closeTo(big.box.height * 2, 2));
      var back = TimelineAction.fromJson(
          jsonDecode(jsonEncode(moved.toJson())) as Map<String, dynamic>);
      expect((back.noteAt, back.noteSize), (const Offset(0.25, 0.1), 2.0));
      expect(a.toJson().containsKey("noteAt"), isFalse, reason: "as it was");
    });
  });

  group("each row its colour", () {
    test("given, the same for a row every time; picked, kept with it", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.rowColour("a"), givenRowColour("a"));
      expect(givenRowColour("a"), givenRowColour("a"));
      expect(rowPalette, contains(c.rowColour("b")));
      c.setRowColour("a", rowPalette[2]);
      expect(c.rowColour("a"), rowPalette[2]);
      var json = c.document.elementById("a")!.toJson();
      expect(elementFromJson(json).base.rowColour, rowPalette[2].toARGB32(),
          reason: "saved with the canvas");
      expect(c.canUndo, isTrue);
      c.setRowColour("a", null);
      expect(c.rowColour("a"), givenRowColour("a"), reason: "its own again");
    });

    test("a sound's, on every sound in its channel", () {
      var c = CanvasController(
          CanvasDocument(frames: 240, elements: [
            for (var id in ["m1", "m2"])
              AudioElement(ElementBase(id: id, name: id, visible: false),
                  clip: const MediaClip(
                      timed: true, channel: "mus", channelName: "Music"),
                  controls: const []),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      var key = c.timelineChannels.single.key;
      c.setRowColour(key, rowPalette[4]);
      expect(c.rowColour(key), rowPalette[4]);
      for (var id in ["m1", "m2"]) {
        expect(c.document.elementById(id)!.base.rowColour,
            rowPalette[4].toARGB32());
      }
    });

    testWidgets("picked from its header's right-click menu", (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 240, elements: [
            sound("m", "Music"),
            const ShapeElement(ElementBase(id: "a", name: "Coin")),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.ensureElementSound("a");
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(CanvasTimeline(controller: c, height: 500)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("motionRow-a")),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("rowColour-3")));
      await tester.pumpAndSettle();
      expect(c.rowColour("a"), rowPalette[3]);
      // A sound's, from its menu.
      await tester.tap(find.byKey(const ValueKey("channelStrip-m")),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("rowColour-5")));
      await tester.pumpAndSettle();
      expect(c.rowColour("m"), rowPalette[5]);
      expect(tester.takeException(), isNull);
    });
  });

  group("linked slots", () {
    test("kept with the motion, and moved with their rows", () {
      var m = const ElementMotion().linkedAs(2, true).linkedAs(0, true);
      expect(m.links, [0, 2]);
      expect(ElementMotion.fromJson(m.toJson()).links, [0, 2]);
      var slotted = m.copyWith(slots: ["a", "b", "c"]);
      expect(slotted.withCueAt(1).links, [0, 3], reason: "past it, down one");
      expect(slotted.withoutCue(0).links, [1], reason: "its own goes");
      expect(m.linkedAs(2, false).links, [0]);
    });

    CanvasController linked() {
      var c = CanvasController(
          CanvasDocument(frames: 240, elements: [
            const ShapeElement(ElementBase(id: "a", name: "Coin")),
          ]),
          audioEngine: FakeEngine({}));
      c.ensureElementSound("a");
      c.newClip("a", kind: MotionKind.action, slot: 0);
      c.setSessionClip(elementSoundKey("a"), 0, const SessionClip(id: "chime"));
      return c;
    }

    test("pressed, either side launches the other", () {
      var c = linked();
      addTearDown(c.dispose);
      var own = elementSoundKey("a");
      c.pressMotionSlot("a", 0);
      expect(c.clipState(own, 0), ClipState.stopped,
          reason: "not linked: the motion alone");
      c.stopAllClips();
      c.linkMotionSlot("a", 0, true);
      expect(c.motionOf("a").isLinked(0), isTrue);
      c.pressMotionSlot("a", 0);
      expect(c.clipState(own, 0), isNot(ClipState.stopped),
          reason: "its sound with it");
      c.stopAllClips();
      c.pause();
    });

    testWidgets("linked from a slot's menu, and drawn so", (tester) async {
      var c = linked();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(CanvasMixer(
          controller: c, height: 720, onResize: (_) {}, onClose: () {})));
      await tester.pump();
      expect(find.byKey(const ValueKey("motionLink-a-0")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("motionName-a-0")),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("motionSlotLink")));
      await tester.pumpAndSettle();
      expect(c.motionOf("a").isLinked(0), isTrue);
      expect(find.byKey(const ValueKey("motionLink-a-0")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group("linked clips on the timeline", () {
    // Coin's motion clip at 1 s; a chime of its own at 2 s (frame 48).
    Future<(CanvasController, String)> timeline(WidgetTester tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            const ShapeElement(ElementBase(id: "a", name: "Coin")),
            AudioElement(const ElementBase(id: "chime", name: "Chime"),
                clip: const MediaClip(
                    timed: true,
                    at: 48,
                    channel: "snd-a",
                    channelName: "Coin",
                    playlist: [MediaSource(assetId: "x", length: 2)]),
                controls: const []),
          ]),
          audioEngine: FakeEngine({"x": 2}));
      addTearDown(c.dispose);
      var clip = c.newClip("a", kind: MotionKind.action);
      var placed = c.placeClip("a", clip, seconds: 1);
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(CanvasTimeline(controller: c, height: 500)));
      await tester.pumpAndSettle();
      return (c, placed);
    }

    int chimeAt(CanvasController c) =>
        (c.document.elementById("chime") as AudioElement).clip.at;

    test("a placement's link is kept with it", () {
      const p = ClipPlacement(id: "p", clip: "c", link: "chime");
      expect(ClipPlacement.fromJson(p.toJson())!.link, "chime");
      expect(ClipPlacement.fromJson(p.copyWith(link: "").toJson())!.link, "");
    });

    testWidgets(
        "linked from the clip's menu with the sound picked; dragged, either "
        "moves the other", (tester) async {
      var (c, placed) = await timeline(tester);
      expect(c.timedLanes.any((l) => l.channelKey == "snd-a"), isTrue);
      // The chime picked, then the motion clip right-clicked.
      c.selectOnly("chime");
      await tester.pump();
      var paint =
          tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a")));
      double xOf(double seconds) =>
          paint.left + seconds * 24 / c.timelineReach * paint.width;
      var on = Offset(xOf(c.spanOf(placed)!.start + 0.2), paint.center.dy);
      await tester.tapAt(on, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("placementLink")));
      await tester.pumpAndSettle();
      expect(c.motionOf("a").placed.single.link, "chime");
      expect(c.linkedSound("a", placed)?.element.id, "chime");
      expect(c.placementsLinkedTo("chime"), [("a", placed)]);
      // The motion clip dragged a second later: the chime with it.
      var start = c.spanOf(placed)!.start;
      var g = await tester.startGesture(on);
      await tester.pump();
      await g.moveTo(on + Offset((xOf(1) - xOf(0)) / 2, 0));
      await tester.pump();
      await g.moveTo(on + Offset(xOf(1) - xOf(0), 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      var moved = c.spanOf(placed)!.start - start;
      expect(moved, greaterThan(0.5));
      expect(chimeAt(c), closeTo(48 + moved * 24, 1.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets("the sound dragged, its linked motion clip with it",
        (tester) async {
      var (c, placed) = await timeline(tester);
      c.linkPlacement("a", placed, "chime");
      await tester.pump();
      var lane = tester.getRect(find.byKey(const ValueKey("lane-snd-a")));
      double xOf(double frame) =>
          lane.left + frame / c.timelineReach * lane.width;
      var start = c.spanOf(placed)!.start;
      // Low on the clip: its middle is the volume line, a grip of its own.
      var from = Offset(xOf(72), lane.top + lane.height * 0.85);
      var g = await tester.startGesture(from);
      await tester.pump();
      await g.moveTo(from + Offset((xOf(24) - xOf(0)) / 2, 0));
      await tester.pump();
      await g.moveTo(from + Offset(xOf(24) - xOf(0), 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      var moved = chimeAt(c) - 48;
      expect(moved, greaterThan(12));
      expect(c.spanOf(placed)!.start, closeTo(start + moved / 24, 0.1));
      expect(tester.takeException(), isNull);
    });
  });

  // Ken, 2026-11-10: a panel's button dragged, the places to drop it on
  // ran off the window's left and top.
  for (var (where, align) in [
    ("top left", Alignment.topLeft),
    ("bottom left", Alignment.bottomLeft),
    ("top right", Alignment.topRight),
  ]) {
    testWidgets("a panel's drop map stays in the window: button at $where",
        (tester) async {
      var c = make();
      addTearDown(c.dispose);
      c.dock = c.dock.copyWith(places: DockPlaces.three);
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Align(
                    alignment: align,
                    child: DockPanelButton(
                        controller: c, panel: DockPanel.slots)))),
      ));
      var button = find.byKey(ValueKey(DockPanel.slots.key));
      var g = await tester.startGesture(tester.getCenter(button));
      await tester.pump();
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      var map = tester.getRect(find.byType(DockDropMap));
      expect(map.left, greaterThanOrEqualTo(0), reason: "$map");
      expect(map.top, greaterThanOrEqualTo(0), reason: "$map");
      expect(map.right, lessThanOrEqualTo(900), reason: "$map");
      expect(map.bottom, lessThanOrEqualTo(600), reason: "$map");
      await g.up();
      await tester.pumpAndSettle();
    });
  }

  testWidgets("no scroll bars on the Slots panel", (tester) async {
    var c = make();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(SizedBox(
        height: 320,
        child:
            CanvasSlotsPanel(controller: c, height: 320, onResize: (_) {}))));
    await tester.pump();
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    expect(tester.takeException(), isNull);
    // On a desktop, where Flutter adds them by itself.
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  group("a fold arrow on every row", () {
    test("folded as the channel height says, unless turned the other way", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.laneSize, 1, reason: "M to begin with");
      expect(c.rowFolded("music"), isFalse);
      c.toggleRowFold("music");
      expect(c.rowFolded("music"), isTrue);
      c.toggleRowFold("scenes");
      expect(c.rowFolded("scenes"), isTrue);
      // The height button puts them all back.
      c.nextLaneSize();
      expect(c.rowFolded("music"), isFalse);
      expect(c.rowFolded("scenes"), isFalse);
    });

    testWidgets(
        "a sound's row folds to one line; an element's own sound with it",
        (tester) async {
      var c = CanvasController(
          CanvasDocument(frames: 240, elements: [
            sound("m", "Music"),
            const ShapeElement(ElementBase(id: "a", name: "Coin")),
          ]),
          audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.ensureElementSound("a");
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(CanvasTimeline(controller: c, height: 500)));
      await tester.pumpAndSettle();
      double rowOf(String key) =>
          tester.getSize(find.byKey(ValueKey("channelStrip-$key"))).height;
      var music = rowOf("m");
      var own = rowOf(elementSoundKey("a"));
      expect(find.byKey(const ValueKey("rowFold-m")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("rowFold-m")));
      await tester.pumpAndSettle();
      expect(rowOf("m"), lessThan(music));
      expect(c.rowFolded("m"), isTrue);
      // The element's own sound has no arrow: its element's folds it.
      expect(find.byKey(ValueKey("rowFold-${elementSoundKey("a")}")),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey("motionFold-a")));
      await tester.pumpAndSettle();
      expect(rowOf(elementSoundKey("a")), lessThan(own));
      expect(tester.takeException(), isNull);
    });
  });
}

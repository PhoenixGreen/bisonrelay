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
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
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

    testWidgets("the note shows it, over the canvas", (tester) async {
      var c = held();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(MarkerNote(controller: c)));
      expect(find.byKey(const ValueKey("markerNote")), findsNothing);
      c.play();
      for (var i = 0; i < 3; i++) {
        c.tickForTest();
      }
      await tester.pump();
      expect(find.text("Press to jump"), findsOneWidget);
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

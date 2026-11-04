import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// An element's own sound: a channel it owns, under its rows on the timeline
// and beside its strip in the mixer; gone with it; sent whole into a return
// as a group bus. And the Show filter: only the animation, or only the
// sound.

CanvasController make() {
  var c = CanvasController(
      CanvasDocument(frames: 240, frameRate: 24, elements: [
        ShapeElement(
            const ElementBase(id: "a", name: "Robot", width: 10, height: 10)),
        // A channel of the canvas's own, not an element's.
        AudioElement(const ElementBase(id: "m", name: "Music", visible: false),
            clip: const MediaClip(timed: true, channelName: "Music"),
            controls: const []),
      ]),
      audioEngine: FakeEngine({}));
  c.ensureElementSound("a");
  return c;
}

Future<CanvasController> pumpBoth(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var c = make();
  addTearDown(c.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: Scaffold(
            body: Column(children: [
      Expanded(
          child: CanvasMixer(
              controller: c, height: 420, onResize: (_) {}, onClose: () {})),
      CanvasTimeline(controller: c, height: 360),
    ]))),
  ));
  await tester.pump();
  return c;
}

void main() {
  test("given a sound, an element has a channel of its own", () {
    var c = make();
    addTearDown(c.dispose);
    expect(c.soundChannelOf("a")?.name, "Robot");
    expect(c.ensureElementSound("a"), elementSoundKey("a"),
        reason: "one channel, however often asked");
    expect(
        c.document.elements
            .whereType<AudioElement>()
            .where((e) => e.clip.channel == elementSoundKey("a")),
        hasLength(1));
    c.addElementSound("a", const MediaSource(assetId: "x", name: "Beep"), 48);
    var placed = c.soundChannelOf("a")!.lanes.where((l) => l.clip.at == 48);
    expect(placed, hasLength(1));
  });

  test("deleted, an element takes its sound with it", () {
    var c = make();
    addTearDown(c.dispose);
    c.selectOnly("a");
    c.deleteSelected();
    expect(c.soundChannelOf("a"), isNull);
    expect(c.timelineChannels.map((ch) => ch.key), ["m"]);
    c.undo();
    expect(c.soundChannelOf("a"), isNotNull);
  });

  test("sent to a return, its sound is heard only through it", () {
    var c = make();
    addTearDown(c.dispose);
    c.setSoundOutput("a", "bus");
    expect(c.soundOutputOf("a"), "bus");
    expect(c.soundChannelOf("a")!.mix.output, "bus");
    // Through the graph: a return turned right down silences it.
    double heard(String output) {
      var g = MixGraph()
        ..setMaster(const MasterMix(limiter: false))
        ..setReturns(const [
          ReturnChannel("bus", mix: ChannelMix(gainDb: -90)),
        ])
        ..setChannel("a", ChannelMix(output: output));
      g.begin(256);
      var (l, r) = g.input("a", 256);
      l.fillRange(0, 256, 0.5);
      r.fillRange(0, 256, 0.5);
      var ol = Float32List(256), or = Float32List(256);
      g.finish(ol, or, 256);
      return ol.fold(0.0, (m, v) => v.abs() > m ? v.abs() : m);
    }

    expect(heard(""), greaterThan(0.1), reason: "to the master");
    expect(heard("bus"), lessThan(1e-3), reason: "only through the return");
    expect(ChannelMix.fromJson(const ChannelMix(output: "bus").toJson()).output,
        "bus");
  });

  testWidgets("on the timeline its sound is under its rows", (tester) async {
    await pumpBoth(tester);
    var row = tester.getRect(find.byKey(const ValueKey("motionRow-a")));
    var own = tester
        .getRect(find.byKey(ValueKey("channelStrip-${elementSoundKey("a")}")));
    var music = tester.getRect(find.byKey(const ValueKey("channelStrip-m")));
    expect(own.top, closeTo(row.bottom, 1), reason: "straight under it");
    expect(music.top, greaterThanOrEqualTo(own.bottom - 1));
  });

  testWidgets("in the mixer its sound's strip is beside its own",
      (tester) async {
    await pumpBoth(tester);
    var strip = tester.getRect(find.byKey(const ValueKey("motionStrip-a")));
    var own =
        tester.getRect(find.byKey(ValueKey("strip-${elementSoundKey("a")}")));
    var music = tester.getRect(find.byKey(const ValueKey("strip-m")));
    expect(own.left, greaterThan(strip.left));
    expect(own.left - strip.right, lessThan(12), reason: "next to it");
    expect(music.right, lessThan(strip.left), reason: "the others first");
    expect(find.byKey(const ValueKey("elementSoundOut-a")), findsOneWidget);
  });

  testWidgets("Show: only the animation, or only the sound", (tester) async {
    var c = await pumpBoth(tester);
    c.timelineShow = TimelineShow.animation;
    await tester.pump();
    expect(find.byKey(const ValueKey("channelStrip-m")), findsNothing);
    expect(find.byKey(const ValueKey("strip-m")), findsNothing);
    expect(find.byKey(const ValueKey("motionStrip-a")), findsOneWidget);
    expect(find.byKey(const ValueKey("lit-show")), findsOneWidget);
    c.timelineShow = TimelineShow.sound;
    await tester.pump();
    expect(find.byKey(const ValueKey("motionStrip-a")), findsNothing);
    expect(find.byKey(const ValueKey("motionRow-a")), findsNothing);
    expect(find.byKey(ValueKey("channelStrip-${elementSoundKey("a")}")),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("lit-show")));
    await tester.pump();
    expect(c.timelineShow, TimelineShow.everything);
  });

  testWidgets("side by side: every row has its slots, the lanes still level",
      (tester) async {
    var c = await pumpBoth(tester);
    var before =
        tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a"))).left;
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await tester.pump();
    // The element's slots, and a channel's, a cue each.
    expect(find.byKey(const ValueKey("rowSlot-a-0")), findsOneWidget);
    expect(find.byKey(const ValueKey("rowClip-m-0")), findsOneWidget);
    expect(find.byKey(ValueKey("rowClip-${elementSoundKey("a")}-7")),
        findsOneWidget);
    expect(find.byKey(const ValueKey("cueLaunch-0")), findsOneWidget);
    // The lanes moved over by the slots, every row alike.
    var lanes =
        tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a"))).left;
    expect(lanes - before, closeTo(c.slotsWidth, 1));
    var cue = tester.getRect(find.byKey(const ValueKey("cueLaunch-0")));
    var slot = tester.getRect(find.byKey(const ValueKey("rowSlot-a-0")));
    expect(cue.left, closeTo(slot.left - 3, 4), reason: "over its column");
    expect(tester.takeException(), isNull);
  });

  test("the effects take the Animation panel's place, however opened", () {
    var c = make();
    addTearDown(c.dispose);
    c.animationOpen = true;
    c.openEffects(elementSoundKey("a"));
    expect((c.animationOpen, c.effectsOpen), (false, true));
    c.animationOpen = true;
    expect((c.animationOpen, c.effectsOpen), (true, false));
  });
}

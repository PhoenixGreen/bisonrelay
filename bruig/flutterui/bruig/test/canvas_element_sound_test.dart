import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Ken, 2026-11-08: one row for an element, its motion and its sound --
  // one header, whose sound and solo buttons are its own sound's; at the
  // channel height S, the motion alone.
  testWidgets("on the timeline one header for an element and its sound",
      (tester) async {
    var c = await pumpBoth(tester);
    var own = elementSoundKey("a");
    expect(c.laneSize, 1, reason: "the timeline opens at M");
    expect(find.byKey(ValueKey("channelStrip-$own")), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(ValueKey("channelStrip-$own")),
            matching: find.byKey(const ValueKey("channelMute"))),
        findsNothing,
        reason: "its buttons are on the element's header, above");

    await tester.tap(find.byKey(const ValueKey("rowMute-a")));
    await tester.pump();
    expect(c.soundChannelOf("a")!.mix.mute, isTrue);
    await tester.tap(find.byKey(const ValueKey("rowSolo-a")));
    await tester.pump();
    expect(c.solo, {own});

    // S: the element's motion alone.
    while (c.laneSize != 0) {
      c.nextLaneSize();
    }
    await tester.pump();
    expect(find.byKey(const ValueKey("motionRow-a")), findsOneWidget);
    expect(find.byKey(ValueKey("channelStrip-$own")), findsNothing);
    expect(find.byKey(const ValueKey("channelStrip-m")), findsOneWidget,
        reason: "a sound that is nobody's is still shown");
  });

  // The approved design (Ken, 2026-11-08): one strip per element, its
  // motion half over its own sound's half.
  testWidgets("in the mixer an element and its sound are one strip",
      (tester) async {
    await pumpBoth(tester);
    var strip = tester.getRect(find.byKey(const ValueKey("motionStrip-a")));
    var own =
        tester.getRect(find.byKey(ValueKey("strip-${elementSoundKey("a")}")));
    var music = tester.getRect(find.byKey(const ValueKey("strip-m")));
    expect(own, strip, reason: "the one strip");
    var motion = tester.getRect(find.byKey(const ValueKey("motionHalf-a")));
    var sound = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("motionStrip-a")),
        matching: find.byKey(const ValueKey("soundHalf"))));
    expect(motion.bottom, lessThanOrEqualTo(sound.top),
        reason: "its motion over its sound");
    var musicSound = tester.getRect(find.descendant(
        of: find.byKey(const ValueKey("strip-m")),
        matching: find.byKey(const ValueKey("soundHalf"))));
    expect(musicSound.top, closeTo(sound.top, 0.5),
        reason: "a sound with no motion has a well there: the sound halves "
            "start on one line");
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("strip-m")),
            matching: find.text("No motion")),
        findsOneWidget);
    expect(music.left, greaterThan(own.right),
        reason: "the sounds that are nobody's after the elements', as on the "
            "timeline (see canvas_rows.dart)");
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

  // Ken, 2026-11-08: beside the rows as in the mixer -- an empty slot
  // double-clicked has a clip made in it; a clip clicked takes Delete.
  testWidgets(
      "side by side, an empty slot double-clicked makes a clip; "
      "Delete empties it", (tester) async {
    var c = await pumpBoth(tester);
    c.apply(c.document.copyWith(elements: [
      for (var e in c.document.elements)
        if (e.id == "m" && e is AudioElement)
          AudioElement(e.base,
              clip: const MediaClip(
                  timed: true,
                  channelName: "Music",
                  playlist: [
                    MediaSource(assetId: "x", name: "Loop", length: 8)
                  ]),
              controls: const [])
        else
          e,
      AudioElement(const ElementBase(id: "keys", name: "Keys"),
          clip: const MediaClip(timed: true),
          instrument: const InstrumentPart()),
    ]));
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await tester.pump();
    for (var ch in ["m", "keys"]) {
      var cell = find.byKey(ValueKey("rowClipNew-$ch-0"));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(cell);
      await tester.pump(const Duration(milliseconds: 400));
      var made = c.session.at(ch, 0);
      expect(made, isNotNull, reason: ch);
      expect(made!.midi, ch == "keys");
      expect(c.selectedSlot, (ch, 0));
    }
    expect(c.session.at("m", 0)!.name, "Loop");
    await tester.tap(find.byKey(const ValueKey("rowClipName-m-0")));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(c.session.at("m", 0), isNull);
    expect(c.document.elementById("m"), isNotNull, reason: "the channel stays");
    expect(tester.takeException(), isNull);
  });

  // Ken, 2026-11-08: a sound on the timeline double-clicked opens its
  // channel's chain, as an element's clip opens its own.
  testWidgets("a sound double-clicked on the timeline opens its chain",
      (tester) async {
    var c = await pumpBoth(tester);
    c.apply(c.document.copyWith(elements: [
      for (var e in c.document.elements)
        if (e.id == "m" && e is AudioElement)
          AudioElement(e.base,
              clip: const MediaClip(
                  timed: true,
                  channelName: "Music",
                  playlist: [
                    MediaSource(assetId: "x", name: "Loop", length: 4)
                  ]),
              controls: const [])
        else
          e,
    ]));
    await tester.pump();
    var lane = tester.getRect(find.byKey(const ValueKey("lane-m")).first);
    var spot = Offset(lane.left + lane.width * 0.1, lane.center.dy);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.effectsOpen, isFalse, reason: "once, picked only");
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.effectsOpen, isTrue);
    expect(c.effectsOf, "m");
    expect(c.selection, contains("m"), reason: "the sound picked");
  });

  // Ken: no Stop all over the slots.
  testWidgets("over the slots, Stop all stops every channel's clips",
      (tester) async {
    var c = await pumpBoth(tester);
    c.apply(c.document.copyWith(elements: [
      for (var e in c.document.elements)
        if (e.id == "m" && e is AudioElement)
          AudioElement(e.base,
              clip: const MediaClip(
                  timed: true,
                  channelName: "Music",
                  playlist: [
                    MediaSource(assetId: "x", name: "Loop", length: 8)
                  ]),
              controls: const [])
        else
          e,
    ]));
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await tester.pump();
    expect(c.makeSessionClip("m", 0), isTrue);
    c.pressClip("m", 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.clipPlaying("m"), isTrue);
    await tester.tap(find.byKey(const ValueKey("stopAllClips")));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.clipState("m", 0), isNot(ClipState.playing));
    c.pause();
    await tester.pump(const Duration(milliseconds: 100));
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
    // As many as are shown: the last, empty one past what is used.
    expect(
        find.byKey(
            ValueKey("rowClip-${elementSoundKey("a")}-${c.slotsShown - 1}")),
        findsOneWidget);
    expect(
        find.byKey(ValueKey("rowClip-${elementSoundKey("a")}-${c.slotsShown}")),
        findsNothing);
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

  test(
      "sharing a place, the effects take the Animation panel's, however "
      "opened", () {
    var c = make();
    addTearDown(c.dispose);
    c.moveDockPanel(DockPanel.chain, DockPlace.main);
    c.openEffects(elementSoundKey("a"));
    expect((c.animationOpen, c.effectsOpen), (false, true));
    c.animationOpen = true;
    expect((c.animationOpen, c.effectsOpen), (true, false));
  });
}

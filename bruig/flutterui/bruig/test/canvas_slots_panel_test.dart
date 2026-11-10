import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/slot_face.dart';
import 'package:bruig/plugin_system/canvas/ui/scene_transition_parts.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/element_sound.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_slots_panel_test.dart is the Slots panel as the approved design has
// it (Ken, 2026-11-08: "like Bitwig's clip launcher"): a column for each row
// the timeline shows, each slot a motion part over a sound part; the cues
// on the left; the transitions in a Scenes column outside the cue rows; a
// header to narrow the columns, step the slots' height and show the motion.

MotionClip clip(String id, int layer) =>
    MotionClip.ofKind(id, MotionKind.action, name: id)
        .copyWith(length: 1, layer: layer, quantise: () => Quantise.off.name);

AudioElement sound(String id, String name) =>
    AudioElement(ElementBase(id: id, name: name, visible: false),
        clip: MediaClip(
            timed: true,
            channelName: name,
            playlist: const [MediaSource(assetId: "x", length: 4)]),
        controls: const []);

Future<CanvasController> pump(WidgetTester tester,
    {double width = 1400, double height = 420, CanvasDocument? doc}) async {
  var c = CanvasController(
      doc ??
          CanvasDocument(frameRate: 24, scenes: [
            CanvasScene(id: "s0", name: "Meadow", frames: 100, elements: [
              ShapeElement(ElementBase(
                  id: "coin",
                  name: "Coin",
                  width: 20,
                  height: 20,
                  motion: ElementMotion(
                      clips: [clip("Spin", 0), clip("Bob", 1)],
                      slots: const ["Spin", "Bob"]))),
              sound("m", "Music"),
            ]),
            const CanvasScene(id: "s1", name: "Chase", frames: 80),
            const CanvasScene(id: "s2", name: "Home", frames: 60),
          ]),
      audioEngine: FakeEngine(const {"x": 4}));
  addTearDown(c.dispose);
  if (doc == null) c.ensureElementSound("coin");
  tester.view.physicalSize = Size(width, height + 100);
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
          child:
              CanvasSlotsPanel(controller: c, height: height, onResize: (_) {}),
        ),
      ),
    ),
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets("a column for each row, the cues on the left, the scenes last",
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
    var cues = at("slotsCues");
    var coin = at("slotsColumn-coin");
    var music = at("slotsColumn-m");
    var scenes = at("slotsColumn-scenes");
    expect(cues.right, lessThanOrEqualTo(coin.left));
    expect(coin.right, lessThanOrEqualTo(music.left),
        reason: "the timeline's order: the elements first");
    expect(music.right, lessThanOrEqualTo(scenes.left));
    // One column, an element: its motion over its own sound.
    var motion = at("motionSlot-coin-0");
    var own = at("clip-${elementSoundKey("coin")}-0");
    expect(motion.bottom, lessThanOrEqualTo(own.top));
    expect(motion.left, greaterThanOrEqualTo(coin.left));
    // The joins, outside the cue rows.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("slotsColumn-scenes")),
            matching: find.byKey(const ValueKey("join-1"))),
        findsOneWidget);
    expect(find.text("transitions, not in cues"), findsOneWidget);
    // Cues a whole row, level with the slots.
    expect(at("scene-0").bottom, closeTo(own.bottom, 1));
    expect(find.byKey(const ValueKey("clipStopAll")), findsOneWidget);
    expect(find.byKey(const ValueKey("slotsStop-m")), findsOneWidget);
    // The columns fill the width, within their least and most.
    expect(coin.width, inInclusiveRange(132, 300));
  });

  testWidgets("narrow, the slots' height and the motion, from the header",
      (tester) async {
    var c = await pump(tester);
    double rowStep() =>
        tester.getRect(find.byKey(const ValueKey("clip-m-1"))).top -
        tester.getRect(find.byKey(const ValueKey("clip-m-0"))).top;

    var medium = rowStep();
    await tester.tap(find.byKey(const ValueKey("slotsHeight")));
    await tester.pump();
    expect(c.slotsPanelSize, 2);
    expect(rowStep(), greaterThan(medium), reason: "large");

    await tester.tap(find.byKey(const ValueKey("slotsNarrow")));
    await tester.pump();
    expect(
        tester.getRect(find.byKey(const ValueKey("slotsColumn-m"))).width, 84);

    expect(find.byKey(const ValueKey("motionSlot-coin-0")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("slotsMotion")));
    await tester.pump();
    expect(c.motionSlots, BandState.minimised);
    await tester.tap(find.byKey(const ValueKey("slotsMotion")));
    await tester.pump();
    expect(c.motionSlots, BandState.hidden);
    expect(find.byKey(const ValueKey("motionSlot-coin-0")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // The approved design: the slots come to rest on whole rows, and the
  // wheel moves them a row a notch.
  testWidgets("the slots come to rest on whole rows", (tester) async {
    var c = await pump(tester, height: 260);
    c.slotsPanelSize = 2;
    for (var i = 0; i < 6; i++) {
      c.addClipScene();
    }
    await tester.pumpAndSettle();
    var step = tester.getRect(find.byKey(const ValueKey("clip-m-1"))).top -
        tester.getRect(find.byKey(const ValueKey("clip-m-0"))).top;
    var list = find.descendant(
        of: find.byKey(const ValueKey("slotsColumn-m")),
        matching: find.byType(Scrollable));
    double offset() =>
        tester.state<ScrollableState>(list.first).position.pixels;
    await tester.drag(list.first, Offset(0, -step * 1.4));
    await tester.pumpAndSettle();
    expect(offset() % step, closeTo(0, 0.5), reason: "on a whole row");
    expect(offset(), greaterThan(0));
    expect(offset(), greaterThan(0));

    var before = offset();
    var at = tester.getCenter(list.first);
    var mouse = TestPointer(7, PointerDeviceKind.mouse);
    mouse.hover(at);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 30)));
    await tester.pumpAndSettle();
    expect(offset() - before, closeTo(step, 0.5), reason: "a row a notch");
    // Every column with it.
    var cues = find.descendant(
        of: find.byKey(const ValueKey("slotsCues")),
        matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(cues.first).position.pixels,
        closeTo(offset(), 0.5));
  });

  testWidgets("the cue column is dragged wider or narrower", (tester) async {
    var c = await pump(tester);
    var wide = tester.getRect(find.byKey(const ValueKey("slotsCues"))).width;
    expect(wide, 120);
    await tester.drag(
        find.byKey(const ValueKey("slotsCueGrip")), const Offset(-200, 0));
    await tester.pump();
    expect(c.slotsCueWidth, CanvasController.cueColumnLeast);
    expect(tester.takeException(), isNull);
  });

  for (var (w, h) in [(300.0, 200.0), (700.0, 260.0), (1400.0, 700.0)]) {
    testWidgets("it fits at $w by $h", (tester) async {
      var c = await pump(tester, width: w, height: h);
      expect(tester.takeException(), isNull);
      for (var size = 0; size < 4; size++) {
        c.slotsPanelSize = size;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: "size $size");
      }
    });
  }

  test("how the mixer and the slots were left is kept, and read back", () {
    var c = CanvasController(CanvasDocument(frames: 10),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    c.motionSlots = BandState.minimised;
    c.cueColumnWidth = 150;
    c.slotsCueWidth = 60;
    c.slotsPanelSize = 3;
    c.slotsPanelNarrow = true;
    c.mixerRailFolded = true;
    var look = c.mixerLook;
    var d = CanvasController(CanvasDocument(frames: 10),
        audioEngine: FakeEngine(const {}));
    addTearDown(d.dispose);
    d.restoreMixerLook(look);
    expect(d.motionSlots, BandState.minimised);
    expect(d.cueColumnWidth, 150);
    expect(d.slotsCueWidth, 60);
    expect(d.slotsPanelSize, 3);
    expect(d.slotsPanelNarrow, isTrue);
    expect(d.mixerRailFolded, isTrue);
    d.restoreMixerLook("cue=9999;what=1;motion=sideways");
    expect(d.cueColumnWidth, CanvasController.cueColumnMost,
        reason: "held to its most; the rest passed by");
    expect(d.motionSlots, BandState.minimised);
  });

  // Ken, 2026-11-10: per-canvas cues. On a scene of a game whose master has
  // the music, the scene's cues on the left are its own, and the master's
  // stand before the master's channels, launching them.
  testWidgets("on a scene, the master's cues before the master's channels",
      (tester) async {
    var c = await pump(tester,
        doc: CanvasDocument(
            frameRate: 24,
            game: true,
            masterOn: true,
            master: CanvasScene(id: "master", elements: [
              sound("music", "Music"),
            ]),
            scenes: [
              CanvasScene(id: "s0", name: "Woods", frames: 100, elements: [
                ShapeElement(ElementBase(
                    id: "coin",
                    name: "Coin",
                    width: 20,
                    height: 20,
                    motion: ElementMotion(
                        clips: [clip("Spin", 0)], slots: const ["Spin"]))),
              ]),
              const CanvasScene(id: "s1", name: "Ruins", frames: 80),
            ]).copyWith(
            session: const SessionGrid(scenes: ["Title", "Woods"]).put(
                "music",
                0,
                const SessionClip(
                    id: "m0",
                    sound: MediaSource(assetId: "x", length: 4),
                    bars: 2))));
    expect(tester.takeException(), isNull);
    expect(c.cuesApart, isTrue);
    Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
    var mine = at("slotsCues");
    var coin = at("slotsColumn-coin");
    var masters = at("slotsMasterCues");
    var music = at("slotsColumn-music");
    expect(mine.right, lessThanOrEqualTo(coin.left));
    expect(coin.right, lessThanOrEqualTo(masters.left),
        reason: "the scene's own first");
    expect(masters.right, lessThanOrEqualTo(music.left),
        reason: "the master's cues just before its channels");
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("slotsCues")),
            matching: find.text("Title")),
        findsNothing,
        reason: "the scene's cues are its own, numbered");
    expect(
        find.descendant(
            of: find.byKey(const ValueKey("slotsMasterCues")),
            matching: find.text("Title")),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("masterCue-0")));
    await tester.pump();
    expect(c.clipState("music", 0), isIn([ClipState.queued, ClipState.playing]),
        reason: "the master's cue plays the master's music");
    expect(c.motionPlayer.isPlaying("coin"), isFalse,
        reason: "not the scene's elements");
    // Each cue column its own width (Ken, 2026-11-10).
    var ownWidth = c.slotsCueWidth, masterWidth = c.slotsMasterCueWidth;
    await tester.drag(
        find.byKey(const ValueKey("slotsMasterCueGrip")), const Offset(30, 0));
    await tester.pump();
    expect(c.slotsMasterCueWidth, closeTo(masterWidth + 30, 1));
    expect(c.slotsCueWidth, ownWidth);
    c.stopChannelClips("music", now: true);
    c.pause();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  // Ken: "The transition clips on the mixer and slots don't highlight when
  // they are selected and the play button doesn't show when they are
  // playing."
  testWidgets("a transition's slot is outlined picked, and lit playing",
      (tester) async {
    var c = await pump(tester);
    BoxBorder? border() => (tester
            .widget<DecoratedBox>(find.byKey(const ValueKey("joinSlot-0")))
            .decoration as BoxDecoration)
        .border;
    bool lit() => tester
        .widget<SlotFace>(find.descendant(
            of: find.byKey(const ValueKey("joinSlot-0")),
            matching: find.byType(SlotFace)))
        .playing;
    expect(border(), isNull);
    expect(lit(), isFalse);
    c.pickScene(0);
    await tester.pump();
    expect(border(), isNotNull, reason: "picked: open in the Chain");
    c.previewTransitionAfter(0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.joinPlaying(0), isTrue);
    expect(lit(), isTrue, reason: "playing");
    expect(c.joinPlaying(1), isFalse);
    c.stopPreview();
    await tester.pump();
    expect(lit(), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  // Ken: "Selecting a transition on the scene channel is a little flaky on
  // both the mixer and slots panels. Sometimes it doesn't select it first
  // time and sometimes it selects a different transition ... when you are
  // on another channel and then you select a transition, it doesn't select
  // the transition on the first click."
  for (var mixer in [false, true]) {
    testWidgets(
        "${mixer ? "the mixer" : "the Slots panel"}: one click picks the "
        "transition clicked", (tester) async {
      var c = await pump(tester);
      if (mixer) {
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: CanvasMixer(
                    controller: c,
                    height: 420,
                    onResize: (_) {},
                    onClose: () {}),
              ),
            ),
          ),
        ));
        await tester.pump();
      }
      // As a hand clicks: pressed, the panel built again under it, then let
      // go -- the strip's pick on the press rebuilt the slot, and the slot's
      // own pick (on the release) was lost or came second.
      Future<void> click(String key) async {
        var g = await tester
            .startGesture(tester.getCenter(find.byKey(ValueKey(key))));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await g.up();
        await tester.pump();
      }

      // On another channel first.
      c.selectOnly("coin");
      await tester.pump();
      await click("joinOpen-1");
      expect(c.pickedScene, 1, reason: "the one clicked, the first time");
      expect(c.animationOpen, isTrue);
      // With the Chain open on it: another, at once -- not the scene shown.
      await click("joinOpen-0");
      expect(c.pickedScene, 0);
      c.goToScene(1);
      await tester.pump();
      await click("joinOpen-0");
      expect(c.pickedScene, 0, reason: "not the scene shown's");
      // Anywhere on the card, not only its name or its launch strip: below
      // the name, a press went by to the strip, which picked the join after
      // the scene shown (Ken, 2026-11-10: the Woods and Citadel transitions
      // took two clicks -- Sunken Ruins, from the Woods, was picked).
      for (var join in [1, 0]) {
        var card = tester.getRect(find.byKey(ValueKey("joinSlot-$join")));
        var g = await tester.startGesture(
            Offset(card.center.dx, card.top + card.height * 0.85));
        await tester.pump();
        await g.up();
        await tester.pump();
        expect(c.pickedScene, join, reason: "pressed below join $join's name");
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  // On the master, a transition clicked on the Scenes strip is that join's:
  // every one showed the default (every scene's), as if another were picked.
  testWidgets("on the master, a join's slot opens that join's transition",
      (tester) async {
    var c = await pump(tester,
        doc: CanvasDocument(
          frameRate: 24,
          masterOn: true,
          master: CanvasScene(id: "m", elements: [sound("music", "Music")]),
          scenes: const [
            CanvasScene(id: "a", name: "Title", frames: 48),
            CanvasScene(
                id: "b",
                name: "Woods",
                frames: 48,
                transition: SceneTransition(
                    kind: SceneTransitionKind.shapeWipe, frames: 12)),
            CanvasScene(id: "c", name: "Ruins", frames: 48),
          ],
        ));
    c.showMaster();
    await tester.pump();
    expect(c.document.editingMaster, isTrue);
    await tester.tap(find.byKey(const ValueKey("joinOpen-1")));
    await tester.pump();
    expect(c.pickedScene, 1);
    expect(c.transitionsAsDefault, isFalse);
    var target = SceneTransitionTarget(c, 1);
    expect(target.value.kind, SceneTransitionKind.shapeWipe,
        reason: "Woods's own, not the default");
    // Picked from a scene on the timeline, on the master: the default.
    c.pickScene(1);
    expect(c.transitionsAsDefault, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

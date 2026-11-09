import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
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
    {double width = 1400, double height = 420}) async {
  var c = CanvasController(
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
  c.ensureElementSound("coin");
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
}

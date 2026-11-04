import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// An element's strip in the mixer: its slots on the cue rows, launched by
// their triangle, opened by their name, a clip made in an empty one; its
// layers' faders; a slot dragged onto the timeline, placed there; and the
// slots beside the rows, launched from there too.

MotionClip across(String id, double by) =>
    MotionClip.ofKind(id, MotionKind.action, name: id)
        .copyWith(length: 1, quantise: () => Quantise.off.name, keys: {
      MotionProp.x: [
        const MotionKey(0, MotionNumber(0)),
        MotionKey(1, MotionNumber(by)),
      ],
    });

CanvasController make() => CanvasController(
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(ElementBase(
          id: "a",
          name: "Logo",
          width: 10,
          height: 10,
          motion:
              ElementMotion(clips: [across("go", 100)], slots: const ["go"]))),
    ]),
    audioEngine: FakeEngine({}));

Future<CanvasController> pumpBoth(WidgetTester tester,
    {double scale = 1}) async {
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
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: Column(children: [
          Expanded(
              child: CanvasMixer(
                  controller: c,
                  height: 420,
                  onResize: (_) {},
                  onClose: () {})),
          CanvasTimeline(controller: c, height: 360),
        ]))),
  ));
  await tester.pump();
  return c;
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets("its triangle launches the slot; its name opens it",
      (tester) async {
    var c = await pumpBoth(tester);
    expect(find.byKey(const ValueKey("motionStrip-a")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("motionLaunch-a-0")));
    await frames(tester);
    expect(c.motionSlotState("a", 0), MotionSlotState.playing);
    await tester.tap(find.byKey(const ValueKey("motionName-a-0")));
    await frames(tester);
    expect((c.pickedMotion, c.animationOpen), ("go", true));
    c.pause();
  });

  testWidgets("an empty slot, double-clicked, makes a clip in it",
      (tester) async {
    var c = await pumpBoth(tester);
    var slot = find.byKey(const ValueKey("motionSlot-a-2"));
    await tester.tap(slot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(slot);
    await frames(tester);
    await tester.tap(find.text("Arriving").first);
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey("slotMotion-Pop")));
    await frames(tester);
    expect(c.motionOf("a").slot(2)?.name, "Pop");
    expect(c.animationOpen, isTrue, reason: "opened to be shaped");
  });

  testWidgets("a layer's fader sets how much it counts", (tester) async {
    var c = await pumpBoth(tester);
    var fader = find.byKey(const ValueKey("layerFader-a-1"));
    var box = tester.getRect(fader);
    await tester.tapAt(Offset(box.center.dx, box.top + box.height * 0.2));
    // Past the wait for a second click: a double-click is all of it.
    await tester.pump(const Duration(milliseconds: 400));
    await frames(tester);
    expect(c.motionOf("a").weight(1), lessThan(0.9));
    expect(c.motionOf("a").weight(1), greaterThan(0.5));
    c.undo();
    expect(c.motionOf("a").weight(1), 1);
  });

  testWidgets("a slot dragged onto the element's row is placed there",
      (tester) async {
    var c = await pumpBoth(tester);
    var lanes =
        tester.getRect(find.byKey(const ValueKey("motionLanesPaint-a")));
    var from = tester.getCenter(find.byKey(const ValueKey("motionName-a-0")));
    // Two seconds in, on its first lane.
    var to = Offset(lanes.left + lanes.width * 48 / 240, lanes.top + 12);
    var g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await frames(tester);
    var placed = c.motionOf("a").placed.single;
    expect(placed.clip, "go");
    expect(c.spanOf(placed.id)!.start, closeTo(2, 0.3));
  });

  testWidgets("beside the rows, the slots launch there too", (tester) async {
    var c = await pumpBoth(tester);
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await frames(tester);
    expect(c.slotsBeside, isTrue);
    await tester.tap(find.byKey(const ValueKey("rowSlot-a-0")));
    await frames(tester);
    expect(c.motionSlotState("a", 0), MotionSlotState.playing);
    c.pause();
  });

  for (var scale in [0.65, 1.5]) {
    testWidgets("at text size $scale, the strip fits", (tester) async {
      await pumpBoth(tester, scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  test("a cue put in or taken away moves the elements' slots with it", () {
    var c = make();
    addTearDown(c.dispose);
    c.newClip("a", preset: null, slot: 2);
    c.addClipScene(after: 0);
    expect(c.motionOf("a").slot(0)?.id, "go");
    expect(c.motionOf("a").slot(3), isNotNull, reason: "moved down a row");
    c.removeClipScene(0);
    expect(c.motionOf("a").clip("go"), isNull,
        reason: "its clip, on no timeline, went with it");
    expect(c.motionOf("a").slot(2), isNotNull);
  });
}

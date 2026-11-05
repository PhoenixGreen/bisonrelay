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
import 'package:shared_preferences/shared_preferences.dart';

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
  // The timeline keeps its widths and switches in the settings: each test
  // starts on the defaults, not on what the one before it dragged them to.
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    // The empty one shown past the last used.
    var row = c.slotsShown - 1;
    expect(c.motionOf("a").slot(row), isNull);
    var slot = find.byKey(ValueKey("motionSlot-a-$row"));
    await tester.tap(slot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(slot);
    await frames(tester);
    await tester.tap(find.text("Arriving").first);
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey("slotMotion-Pop")));
    await frames(tester);
    expect(c.motionOf("a").slot(row)?.name, "Pop");
    expect(c.slotsShown, row + 2, reason: "and one more slot shown");
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

  testWidgets("an empty slot beside the rows makes a clip, and opens it",
      (tester) async {
    var c = await pumpBoth(tester);
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await frames(tester);
    var empty = [
      for (var i = 0; i < c.session.rows; i++)
        if (c.motionOf("a").slot(i) == null) i
    ].first;
    await tester.tap(find.byKey(ValueKey("rowSlotNew-a-$empty")));
    await frames(tester);
    var made = c.motionOf("a").slot(empty);
    expect(made, isNotNull, reason: "a clip in the slot pressed");
    expect(c.pickedMotion, made!.id);
    expect(c.animationOpen, isTrue);
  });

  testWidgets("the strips and the slots each have a grip", (tester) async {
    var c = await pumpBoth(tester);
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await frames(tester);
    var header = c.headerWidth, slots = c.slotsWidth;
    await tester.drag(
        find.byKey(const ValueKey("headerGrip")), const Offset(-30, 0));
    await frames(tester);
    expect(c.headerWidth, lessThan(header));
    expect(c.slotsWidth, slots, reason: "the slots keep their width");
    await tester.drag(
        find.byKey(const ValueKey("slotsGrip")), const Offset(-60, 0));
    await frames(tester);
    expect(c.slotsWidth, lessThan(slots));
    expect(c.headerWidth, lessThan(header), reason: "and the strips theirs");
  });

  testWidgets("the channel-height button sizes every element's rows too",
      (tester) async {
    var c = await pumpBoth(tester);
    double row() =>
        tester.getSize(find.byKey(const ValueKey("motionRow-a"))).height;
    Future<void> next() async {
      await tester.tap(find.byKey(const ValueKey("timelineLaneHeight")));
      await frames(tester);
    }

    // Small: folded to one line, however many layers it has.
    expect(c.laneSize, 0);
    var small = row();
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    await next();
    var medium = row();
    expect(medium, greaterThan(small), reason: "opened");
    await next();
    var large = row();
    expect(large, greaterThan(medium), reason: "its lanes taller");
    // One folded by hand, then the button: all alike again.
    await tester.tap(find.byKey(const ValueKey("motionFold-a")));
    await frames(tester);
    expect(row(), lessThan(large), reason: "one line, at the large size");
    await next();
    expect(c.laneSize, 0);
    expect(row(), small);
    await next();
    expect(row(), medium,
        reason: "the one folded by hand opened with the rest");
    expect(tester.takeException(), isNull);
  });

  test("slots start at two, and one more shows as the last fills", () {
    var c = make();
    addTearDown(c.dispose);
    expect(c.slotsShown, 2, reason: "one used, one to fill");
    c.newClip("a", slot: 1);
    expect(c.slotsShown, 3);
    var rows = c.session.rows;
    c.newClip("a", slot: rows - 1);
    expect(c.session.rows, rows + 1, reason: "a cue added past the last");
    expect(c.slotsShown, rows + 1);
    c.undo();
    expect(c.session.rows, rows, reason: "one step with the clip");
  });

  test("a cue added at the end is one of the slots shown", () {
    var c = make();
    addTearDown(c.dispose);
    c.addClipScene();
    expect(c.slotsShown, 4, reason: "the new cue, and one empty past it");
    expect(c.session.sceneName(2), "3");
  });

  testWidgets("the slots beside the rows keep one size and scroll together",
      (tester) async {
    var c = await pumpBoth(tester);
    c.newClip("a", slot: 1);
    c.newClip("a", slot: 2);
    await tester.tap(find.byKey(const ValueKey("slotsToggle")));
    await frames(tester);
    // Narrower than the slots: they scroll rather than shrink.
    c.slotsColumn = CanvasController.slotsColumnMin;
    await frames(tester);
    expect(c.slotsWidth, lessThan(c.slotsContent));
    var slot = find.byKey(const ValueKey("rowSlotName-a-1"));
    var cue = find.byKey(const ValueKey("cueLaunch-1"));
    var size = tester.getSize(slot);
    var (slotX, cueX) = (tester.getRect(slot).left, tester.getRect(cue).left);
    c.scrollSlots(CanvasController.slotCellWidth + 3);
    await frames(tester);
    expect(tester.getRect(slot).left,
        closeTo(slotX - CanvasController.slotCellWidth - 3, 0.5));
    expect(tester.getRect(cue).left,
        closeTo(cueX - slotX + tester.getRect(slot).left, 0.5),
        reason: "the cues over them with them");
    // Taller rows, the same slots.
    c.nextLaneSize();
    c.nextLaneSize();
    await frames(tester);
    expect(tester.getSize(slot), size);
    // Pressed where it has scrolled to, it still opens.
    await tester.tap(slot);
    await frames(tester);
    expect(c.pickedMotion, c.motionOf("a").slot(1)!.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets("an element's strip is picked by a press anywhere on it",
      (tester) async {
    var c = await pumpBoth(tester);
    c.clearSelection();
    c.selectedChannel = "x";
    await frames(tester);
    var strip = tester.getRect(find.byKey(const ValueKey("motionStrip-a")));
    // Below its slots: the faders' band, not its name.
    await tester.tapAt(Offset(strip.center.dx, strip.bottom - 40));
    await frames(tester);
    expect(c.selection, {"a"});
    expect(c.selectedChannel, isNull, reason: "the channel's pick moves off");
  });

  testWidgets("an element's strip narrows as a channel's does", (tester) async {
    var c = await pumpBoth(tester);
    var strip = find.byKey(const ValueKey("motionStrip-a"));
    var wide = tester.getSize(strip).width;
    expect(find.text("L1 100"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("narrow-motion:a")));
    await frames(tester);
    expect(tester.getSize(strip).width, lessThan(wide));
    expect(
        find.descendant(of: strip, matching: find.text("L1")), findsOneWidget,
        reason: "its faders by layer");
    expect(c.narrowStrips, contains("motion:a"));
    expect(tester.takeException(), isNull);
  });

  testWidgets("a clip starting before the frames shown stays in its lane",
      (tester) async {
    await pumpBoth(tester);
    var lanes = find.byKey(const ValueKey("motionLanesPaint-a"));
    expect(lanes, paints..clipRect(rect: Offset.zero & tester.getSize(lanes)));
  });

  for (var scale in [0.65, 1.5]) {
    testWidgets("at text size $scale, the strip fits", (tester) async {
      var c = await pumpBoth(tester, scale: scale);
      expect(tester.takeException(), isNull);
      // Narrow, and with the slots beside the rows.
      c.toggleNarrow(motionStripKey("a"));
      c.slotsBeside = true;
      await frames(tester);
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

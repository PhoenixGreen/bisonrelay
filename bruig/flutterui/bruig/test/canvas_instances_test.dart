import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart'
    show StageHandle;
import 'package:bruig/plugin_system/canvas/ui/motion_lanes.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Canvas, Paint;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';

// canvas_instances_test.dart is an element reused: one element drawn many
// times, each copy with its own place and start, and -- Ken, 2026-11-08 --
// whatever else it has of its own, any knob of its chain among them. Its
// Instances is first of its chain, the picker for what the chain edits;
// copies are objects on the canvas, picked, dragged and placed there.

/// across moves 100 to the right over 4 seconds, placed at the start.
const MotionClip across = MotionClip(
  id: "go",
  kind: MotionKind.action,
  length: 4,
  keys: {
    MotionProp.x: [
      MotionKey(0, MotionNumber(0)),
      MotionKey(4, MotionNumber(100))
    ],
  },
);

InstanceSet three({Map<VaryWhat, Vary> vary = const {}}) => InstanceSet(
      items: const [
        ElementInstance("i0"),
        ElementInstance("i1", dx: 50),
        ElementInstance("i2", dx: 100, start: 1),
      ],
      vary: vary,
    );

CanvasDocument doc(InstanceSet? set,
        {List<MotionDevice> devices = const [], bool clip = true}) =>
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(
          ElementBase(
              id: "a",
              x: 10,
              y: 10,
              width: 20,
              height: 20,
              motion: ElementMotion(
                  clips: clip ? const [across] : const [],
                  placed: clip
                      ? const [ClipPlacement(id: "p", clip: "go", length: 4)]
                      : const [],
                  devices: devices,
                  instances: set)),
          fill: const Color(0xFF000000)),
    ]);

double dx(CanvasDocument d, int frame, int? instance) =>
    poseWithMotion(d.elementById("a")!, frame, d, instance: instance).dx;

Future<ByteData> draw(CanvasDocument d, int frame) async {
  var rec = PictureRecorder();
  var canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 100),
      Paint()..color = const Color(0xFFFFFFFF));
  paintElement(canvas, d.elementById("a")!, frame, document: d, frameRate: 24);
  var img = await rec.endRecording().toImage(300, 100);
  return (await img.toByteData())!;
}

int red(ByteData px, int x, int y) => px.getUint8((y * 300 + x) * 4);

void main() {
  group("the model", () {
    test("kept, and dropped when empty", () {
      var set = three(vary: {VaryWhat.size: const Vary(VaryHow.random, 0.5)});
      var back = InstanceSet.fromJson(set.toJson())!;
      expect(back.items.map((x) => x.id), ["i0", "i1", "i2"]);
      expect(back.items[2].start, 1);
      expect(back.varyOf(VaryWhat.size).how, VaryHow.random);
      expect(InstanceSet.fromJson(const {"items": []}), isNull);
      var m = ElementMotion.fromJson(ElementMotion(instances: set).toJson());
      expect(m.instances!.count, 3);
      expect(m.moves, isTrue);
      expect(m.isBlank, isFalse);
    });

    test("more keep their ids and their step; fewer drop the last", () {
      var set = const InstanceSet().withCount(3, gap: 40);
      expect(set.items.map((x) => (x.id, x.dx)),
          [("i0", 0.0), ("i1", 40.0), ("i2", 80.0)]);
      set = set.withCount(4);
      expect(set.items.last.dx, 120, reason: "the last two's step");
      expect(set.withCount(2).items.map((x) => x.id), ["i0", "i1"]);
    });

    test("each way of differing", () {
      var set = const InstanceSet().withCount(5);
      expect(set.share(VaryWhat.size, 2), 0, reason: "same for all");
      var byOrder =
          set.withVary(VaryWhat.starts, const Vary(VaryHow.byOrder, 2));
      expect(byOrder.startOf(4), 2);
      expect(byOrder.startOf(2), 1);
      var middle =
          set.withVary(VaryWhat.size, const Vary(VaryHow.fromMiddle, 1));
      expect(middle.sizeOf(2), 1, reason: "the middle one as it is");
      expect(middle.sizeOf(0), 2);
      var random =
          set.withVary(VaryWhat.colour, const Vary(VaryHow.random, 90));
      expect(random.hueOf(1), isNot(random.hueOf(2)));
      expect(random.hueOf(1), random.hueOf(1), reason: "the same each time");
      expect(set.uniform, isTrue);
      expect(byOrder.uniform, isFalse);
    });

    test("laid out in a line, a grid, a circle", () {
      var set = const InstanceSet().withCount(4);
      expect(
          set
              .laidOut(InstanceLayout.grid, gap: 10, columns: 2)
              .items
              .map((x) => (x.dx, x.dy)),
          [(0.0, 0.0), (10.0, 0.0), (0.0, 10.0), (10.0, 10.0)]);
      var circle = set.laidOut(InstanceLayout.circle, gap: 10);
      expect(circle.items.first.dx, closeTo(0, 1e-9));
      expect(circle.items.first.dy, closeTo(0, 1e-9),
          reason: "the first where the element is");
    });
  });

  group("rule 3", () {
    test("each instance at its place, and at its own start", () {
      var d = doc(three());
      expect(dx(d, 48, 0), closeTo(50, 0.01), reason: "two seconds in");
      expect(dx(d, 48, 1), closeTo(100, 0.01), reason: "50 to the right");
      expect(dx(d, 48, 2), closeTo(125, 0.01),
          reason: "a second behind, 100 to the right");
      expect(dx(d, 12, 2), closeTo(100, 0.01),
          reason: "before its start it holds its first frame");
      expect(dx(d, 48, null), closeTo(50, 0.01),
          reason: "the element as placed");
    });

    // Rule 3's movable split is gone (Ken, 2026-11-08): Instances is
    // always first. One an older canvas kept as a device, wherever it was,
    // is dropped as the canvas is read.
    test("Instances is first of the chain, wherever it was kept", () {
      var time = const MotionDevice(MotionDeviceKind.time,
          id: "m0", values: {"speed": 2});
      var old = const ElementMotion(devices: [
        MotionDevice(MotionDeviceKind.time, id: "m0", values: {"speed": 2}),
        MotionDevice(MotionDeviceKind.instances, id: "m1"),
      ]);
      var read = ElementMotion.fromJson(old.toJson());
      expect(read.devices.map((d) => d.kind), [MotionDeviceKind.time]);
      var chain = doc(three(), devices: [time]);
      // Time speeds each copy's moment up: 4 s asked for, less copy 2's
      // second, 3 s in.
      expect(dx(chain, 48, 2), closeTo(100 + 75, 0.01));
      expect(chain.elementById("a")!.base.motion.poseDevices.first.kind,
          MotionDeviceKind.instances);
    });

    test("a copy's own values win over the set's, and its own knobs", () {
      var set = three(vary: {VaryWhat.starts: const Vary(VaryHow.byOrder, 2)})
          .withCopy("i1", (x) => x.withOwn(CopyValue.start.name, 0.5))
          .withCopy("i2", (x) => x.withOwn(CopyValue.speed.name, 2));
      expect(set.startOf(1), 0.5, reason: "its own, not by order's 1 s");
      expect(set.startOf(2), 1 + 2,
          reason: "its place's second, and 2 by order");
      expect(set.speedOf(2), 2);
      expect(set.uniform, isFalse);
      // Its own Oscillate amount: the others' is nothing.
      var wave = const MotionDevice(MotionDeviceKind.oscillate,
          id: "m0", values: {"amount": 0, "rate": 1, "moves": 1});
      var own = three()
          .withCopy("i1", (x) => x.withOwn(deviceOwnKey("m0", "amount"), 30));
      var d = doc(own, devices: [wave], clip: false);
      // A quarter second in, the wave is at its height.
      expect(dx(d, 6, 0), closeTo(0, 0.01), reason: "the shared amount");
      expect(dx(d, 6, 1), closeTo(50 + 30, 0.5), reason: "its own amount");
      // Kept with the canvas.
      var back = InstanceSet.fromJson(own.toJson())!;
      expect(back.items[1].own[deviceOwnKey("m0", "amount")], 30);
      // Reverted: its place kept, its own values gone.
      expect(own.items[1].reverted.own, isEmpty);
      expect(own.items[1].reverted.dx, 50);
    });

    test("its box is all of them; one is found by where it is", () {
      var d = doc(three(), clip: false);
      var e = d.elementById("a")!;
      var b = e.movedBoundsAt(0, d);
      expect(b.left, 10);
      expect(b.right, 130);
      expect(e.instanceAt(const Offset(70, 20), 0, d), 1);
      expect(e.instanceAt(const Offset(45, 20), 0, d), isNull);
    });
  });

  // Ken, 2026-11-08: Arrives > Slide in left copies on the page at the
  // start: "off the left edge" was worked out from the element, not from
  // each copy.
  test("a place off the page is off it for every copy", () {
    var c = CanvasController(doc(three(), clip: false),
        audioEngine: FakeEngine(const {}));
    addTearDown(c.dispose);
    var id = c.newClip("a", preset: presetNamed("Slide in"), slot: 0);
    c.placeClip("a", id, seconds: 0);
    var e = c.document.elementById("a")!;
    for (var i = 0; i < 3; i++) {
      var box = e.boundsWith(poseWithMotion(e, 0, c.document, instance: i));
      expect(box.right, lessThan(0), reason: "copy $i starts off the left");
      var end = e.boundsWith(poseWithMotion(e, 48, c.document, instance: i));
      expect(end.left, closeTo(10 + 50.0 * i, 0.5), reason: "and lands home");
    }
  });

  // Ken, 2026-11-08: launched from their slot, the copies moved as one --
  // their starts and speeds were put on the timeline's clock, not the
  // slots'.
  group("launched from a slot", () {
    CanvasController launched() {
      var c = CanvasController(doc(three(), clip: false),
          audioEngine: FakeEngine(const {}));
      c.setMotion("a",
          c.motionOf("a").copyWith(clips: const [across], slots: const ["go"]));
      return c;
    }

    double at(CanvasController c, int i) =>
        poseWithMotion(c.document.elementById("a")!, c.frame, c.document,
                live: c.liveMotion, instance: i)
            .dx;

    testWidgets("each copy plays at its own start and speed", (tester) async {
      var c = launched();
      addTearDown(c.dispose);
      c.setInstances(
          "a",
          c
              .motionOf("a")
              .instances!
              .withCopy("i1", (x) => x.withOwn(CopyValue.speed.name, 2)));
      c.pressMotionSlot("a", 0);
      await tester.pump(const Duration(milliseconds: 2000));
      var clock = c.motionPlayer.clock;
      expect(clock, greaterThan(1.5));
      // Across: 25 a second, from each one's place.
      expect(at(c, 0), closeTo(25 * clock, 1.5));
      expect(at(c, 1), closeTo(50 + 50 * clock, 3), reason: "twice as fast");
      expect(at(c, 2), closeTo(100 + 25 * (clock - 1), 1.5),
          reason: "a second behind");
      c.pause();
    });

    testWidgets("a copy started later is still playing a clip played once",
        (tester) async {
      var c = launched();
      addTearDown(c.dispose);
      c.setInstances(
          "a",
          c
              .motionOf("a")
              .instances!
              .withCopy("i2", (x) => x.withOwn(CopyValue.start.name, 2)));
      c.pressMotionSlot("a", 0);
      // Past the clip's four seconds: over for the element, not for copy 2.
      await tester.pump(const Duration(milliseconds: 5000));
      var clock = c.motionPlayer.clock;
      expect(clock, greaterThan(4.5));
      expect(at(c, 2), closeTo(100 + 25 * (clock - 2), 2));
      c.pause();
    });
  });

  group("drawn", () {
    test("each instance is drawn where it is", () async {
      var px = await draw(doc(three(), clip: false), 0);
      for (var x in [20, 70, 120]) {
        expect(red(px, x, 20), 0, reason: "an instance at $x");
      }
      expect(red(px, 45, 20), 255, reason: "nothing between");
    });

    test("alike, they are stamped; differing, drawn one by one", () async {
      var stamped = InstanceSet(items: const [
        ElementInstance("i0"),
        ElementInstance("i1", dx: 50),
      ]);
      expect(stamped.uniform, isTrue);
      var px = await draw(doc(stamped, clip: false), 0);
      expect(red(px, 70, 20), 0);
      var coloured =
          stamped.withVary(VaryWhat.colour, const Vary(VaryHow.byOrder, 120));
      expect(coloured.uniform, isFalse);
      // Black stays black whatever its hue: the colour varies, the places
      // hold.
      px = await draw(doc(coloured, clip: false), 0);
      expect(red(px, 70, 20), 0);
    });
  });

  group("the controller", () {
    test("reuse, lay out, and place once", () {
      var c = CanvasController(doc(null, clip: false),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.reuseElement("a", 4);
      var set = c.motionOf("a").instances!;
      expect(set.count, 4);
      expect(set.items[1].dx, 30, reason: "half as far again as it is big");
      c.layOutInstances("a", InstanceLayout.grid);
      expect(c.motionOf("a").instances!.items[2].dy, 30);
      c.setInstances("a", null);
      expect(c.motionOf("a").instances, isNull);
      expect(c.motionOf("a").devices, isEmpty,
          reason: "its Instances gone with them");
      c.undo();
      expect(c.motionOf("a").instances, isNotNull);
    });
  });

  group("the card", () {
    for (var scale in [1.0, 1.5]) {
      testWidgets("reuse it from its Instances card, at $scale",
          (tester) async {
        var c = CanvasController(doc(null, clip: false),
            audioEngine: FakeEngine(const {}));
        addTearDown(c.dispose);
        c.selectOnly("a");
        tester.view.physicalSize = const Size(2400, 300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) =>
                          AnimationPanel(controller: c, height: 300)))),
        ));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byKey(const ValueKey("instancesCard")), findsOneWidget);
        // First of the chain, before its Source.
        expect(
            tester.getRect(find.byKey(const ValueKey("instancesCard"))).left,
            lessThan(tester
                .getRect(find.byKey(const ValueKey("motionZone-Source")))
                .left));
        await tester.tap(find.byKey(const ValueKey("instancesReuse")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionOf("a").instances!.count, 5);
        // + Add: placing, until pressed again.
        await tester.tap(find.byKey(const ValueKey("instancesPlace")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.placingCopies, "a");
        await tester.tap(find.byKey(const ValueKey("instancesPlace")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.placingCopies, isNull);
        // How their starts differ.
        tester
            .widget<StudioDrop<VaryHow>>(
                find.byKey(const ValueKey("vary-starts")))
            .onChanged(VaryHow.byOrder);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionOf("a").instances!.varyOf(VaryWhat.starts).how,
            VaryHow.byOrder);
        expect(
            find.byKey(const ValueKey("vary-starts-amount")), findsOneWidget);
        // A copy picked in the table: its own knobs, its own start.
        await tester.ensureVisible(find.byKey(const ValueKey("copyRow-i2")));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("copyRow-i2")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.pickedCopiesOf("a"), {"i2"});
        expect(find.byKey(const ValueKey("copyKnob-start")), findsOneWidget);
        expect(find.byKey(const ValueKey("vary-starts")), findsNothing);
        c.setCopyOwn("a", CopyValue.start.name, 3);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionOf("a").instances!.startOf(2), 3);
        expect(find.byKey(const ValueKey("copyOwn-i2")), findsOneWidget,
            reason: "a dot in its row");
        expect(
            find.descendant(
                of: find.byKey(const ValueKey("copyKnob-start")),
                matching: find.byKey(const ValueKey("knobOwn"))),
            findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey("copiesRevert")));
        await tester.tap(find.byKey(const ValueKey("copiesRevert")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionOf("a").instances!.items[2].own, isEmpty);
        // Back to all of them, and then to one.
        await tester.ensureVisible(find.byKey(const ValueKey("copyRow-all")));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("copyRow-all")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.pickedCopiesOf("a"), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey("instancesOnce")));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey("instancesOnce")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionOf("a").instances, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  // Ken, 2026-11-08: copies are objects on the canvas.
  group("on the canvas", () {
    Future<(CanvasController, CanvasStageState)> stage(
        WidgetTester tester) async {
      // Big enough that a click on a copy is not on the selection's handles.
      var c = CanvasController(
          CanvasDocument(frames: 240, frameRate: 24, elements: [
            ShapeElement(
                const ElementBase(
                    id: "a",
                    x: 100,
                    y: 100,
                    width: 100,
                    height: 100,
                    motion: ElementMotion(
                        instances: InstanceSet(items: [
                      ElementInstance("i0"),
                      ElementInstance("i1", dx: 250),
                      ElementInstance("i2", dx: 500),
                    ]))),
                fill: const Color(0xFF000000)),
          ]),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = const Size(900, 700);
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
                body: SizedBox(
                    width: 900,
                    height: 700,
                    child: CanvasStage(key: key, controller: c)))),
      ));
      await tester.pumpAndSettle();
      return (c, key.currentState!);
    }

    // The copies' middles: 150,150 · 400,150 · 650,150.
    Offset copy(int i) => Offset(150 + 250.0 * i, 150);

    // Ken, 2026-11-08: each copy its own thing on the canvas -- the box
    // round them all only with All chosen in its Instances.
    testWidgets("the box round every copy only with All chosen",
        (tester) async {
      var (c, s) = await stage(tester);
      Rect? box() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<StagePainter>()
          .single
          .selectionBounds;
      c.selectOnly("a");
      await tester.pumpAndSettle();
      expect(box(), isNull, reason: "selected: each copy outlined alone");
      c.pickAllCopies("a");
      await tester.pumpAndSettle();
      expect(box(), isNotNull, reason: "All chosen: the box round them all");
      await tester.tapAt(s.toStagePoint(copy(1)));
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), {"i1"});
      expect(box(), const Rect.fromLTWH(350, 100, 100, 100),
          reason: "one picked, a box of its own");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), isEmpty);
      expect(box(), isNull, reason: "Escape: all again, but no box");
    });

    // Ken, 2026-11-08: "Individual instances should get a box when
    // selected this allows users to resize, move, rotate".
    testWidgets("one copy picked: its box sizes and turns it alone",
        (tester) async {
      var (c, s) = await stage(tester);
      await tester.tapAt(s.toStagePoint(copy(1)));
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), {"i1"});
      var scale =
          (s.toStagePoint(const Offset(100, 0)) - s.toStagePoint(Offset.zero))
                  .dx /
              100;
      // A corner pulled out to twice as far from its middle: twice the size.
      var corner = s.handleAt(StageHandle.bottomRight);
      await tester.timedDragFrom(corner, const Offset(50, 50) * scale,
          const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      var set = c.motionOf("a").instances!;
      expect(set.sizeOf(1), closeTo(2, 0.02));
      expect(set.sizeOf(0), 1, reason: "the others keep theirs");
      expect(set.sizeOf(2), 1);
      expect(c.document.elementById("a")!.bounds,
          const Rect.fromLTWH(100, 100, 100, 100),
          reason: "the element itself is not resized");
      expect(
          s.handleAt(StageHandle.bottomRight),
          offsetMoreOrLessEquals(s.toStagePoint(const Offset(500, 250)),
              epsilon: 1),
          reason: "the box goes with it");
      // The ring, from above its middle round to its right: a quarter turn.
      var mid = s.toStagePoint(copy(1));
      var ring = s.handleAt(StageHandle.rotate);
      var to = mid + Offset((ring - mid).distance, 0);
      await tester.timedDragFrom(
          ring, to - ring, const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      set = c.motionOf("a").instances!;
      expect(set.turnOf(1), closeTo(90, 1));
      expect(set.turnOf(0), 0);
      expect(c.document.elementById("a")!.rotation, 0);
      c.undo();
      expect(c.motionOf("a").instances!.turnOf(1), 0, reason: "one step");
      expect(c.motionOf("a").instances!.sizeOf(1), closeTo(2, 0.02));
      c.undo();
      expect(c.motionOf("a").instances!.sizeOf(1), 1);
    });

    testWidgets("a click picks a copy; Shift-click another; Escape, all",
        (tester) async {
      var (c, s) = await stage(tester);
      await tester.tapAt(s.toStagePoint(copy(1)));
      await tester.pumpAndSettle();
      expect(c.selection, {"a"});
      expect(c.pickedCopiesOf("a"), {"i1"});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(s.toStagePoint(copy(2)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), {"i1", "i2"});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.pickedCopiesOf("a"), isEmpty, reason: "back to all of them");
      expect(c.selection, {"a"});
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.selection, isEmpty);
    });

    testWidgets("a picked copy dragged moves alone; none picked, all move",
        (tester) async {
      var (c, s) = await stage(tester);
      Future<void> drag(Offset from, Offset by) async {
        var a = s.toStagePoint(from), b = s.toStagePoint(from + by);
        await tester.timedDragFrom(a, b - a, const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }

      // Not picked yet: the press takes the element, all of them.
      await drag(copy(1), const Offset(0, 40));
      expect(c.document.elementById("a")!.base.y, closeTo(140, 0.5));
      expect(c.motionOf("a").instances!.items[1].dy, 0);
      c.undo();
      // Picked, it goes alone.
      await tester.tapAt(s.toStagePoint(copy(1)));
      await tester.pumpAndSettle();
      await drag(copy(1), const Offset(0, 40));
      var set = c.motionOf("a").instances!;
      expect(set.items[1].dy, closeTo(40, 0.5));
      expect(set.items[0].dy, 0);
      expect(c.document.elementById("a")!.base.y, 100, reason: "the rest stay");
      c.undo();
      expect(c.motionOf("a").instances!.items[1].dy, 0, reason: "one step");
    });

    testWidgets("Alt-drag a copy for a new one; Delete takes picked copies",
        (tester) async {
      var (c, s) = await stage(tester);
      await tester.tapAt(s.toStagePoint(copy(2)));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      var a = s.toStagePoint(copy(2)),
          b = s.toStagePoint(copy(2) + const Offset(0, 50));
      await tester.timedDragFrom(a, b - a, const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      var set = c.motionOf("a").instances!;
      expect(set.count, 4);
      expect(set.items.last.dx, 500);
      expect(set.items.last.dy, closeTo(50, 0.5));
      expect(set.items[2].dy, 0, reason: "the one dragged from stays");
      expect(c.pickedCopiesOf("a"), {set.items.last.id});
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(c.motionOf("a").instances!.count, 3);
      expect(c.document.elementById("a"), isNotNull,
          reason: "the element stays");
    });

    testWidgets("placing: each click puts a copy there; Escape stops",
        (tester) async {
      var (c, s) = await stage(tester);
      c.selectOnly("a");
      c.placingCopies = "a";
      await tester.pump();
      await tester.tapAt(s.toStagePoint(const Offset(300, 400)));
      await tester.pumpAndSettle();
      await tester.tapAt(s.toStagePoint(const Offset(500, 400)));
      await tester.pumpAndSettle();
      var set = c.motionOf("a").instances!;
      expect(set.count, 5);
      expect(set.items[3].dx, closeTo(150, 0.5), reason: "its middle there");
      expect(set.items[3].dy, closeTo(250, 0.5));
      expect(c.placingCopies, "a", reason: "still placing");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.placingCopies, isNull);
      // Placed once, it becomes two.
      c.setInstances("a", null);
      c.selectOnly("a");
      c.placingCopies = "a";
      await tester.pump();
      await tester.tapAt(s.toStagePoint(const Offset(300, 400)));
      await tester.pumpAndSettle();
      expect(c.motionOf("a").instances!.count, 2);
    });
  });

  // Ken's systems review, 2026-11-08: a Spring worked its chain out again
  // for sixteen frames at every frame; its poses are kept per document now.
  test("a Spring's kept poses are the ones worked out fresh", () {
    CanvasDocument withSpring(double stiffness) => CanvasDocument(elements: [
          ShapeElement(ElementBase(
              id: "s",
              width: 20,
              height: 20,
              motion: ElementMotion(clips: const [
                MotionClip(id: "go", length: 1, keys: {
                  MotionProp.x: [
                    MotionKey(0, MotionNumber(0)),
                    MotionKey(1, MotionNumber(200)),
                  ],
                }),
              ], placed: const [
                ClipPlacement(id: "p", clip: "go")
              ], devices: [
                MotionDevice(MotionDeviceKind.spring,
                    id: "sp", values: {"stiffness": stiffness}),
              ]))),
        ]);
    var doc = withSpring(12);
    var e = doc.elementById("s")!;
    // Fresh: with something live (the pointer) nothing is kept.
    const fresh = PointerLive(null);
    for (var f = 0; f < 40; f++) {
      expect(poseWithMotion(e, f, doc).dx,
          closeTo(poseWithMotion(e, f, doc, live: fresh).dx, 1e-9),
          reason: "frame $f");
    }
    // Another document -- stiffer -- is not answered from the last one's.
    var stiff = withSpring(30);
    var a = poseWithMotion(e, 10, doc).dx;
    var b = poseWithMotion(stiff.elementById("s")!, 10, stiff).dx;
    expect(a, isNot(closeTo(b, 1e-6)));
  });

  // Ken, 2026-11-08: a sound placed by its element's place on the page
  // goes with it when a slot sends it across.
  test("a sound placed on the page follows its element launched from a slot",
      () {
    var doc = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "car",
          x: 0,
          y: 0,
          width: 20,
          height: 20,
          motion: ElementMotion(clips: [
            MotionClip(id: "drive", length: 1, keys: {
              MotionProp.x: [
                MotionKey(0, MotionNumber(1200)),
                MotionKey(1, MotionNumber(1200)),
              ],
            }),
          ]))),
    ]);
    var car = doc.elementById("car")!;
    const place = SoundPlacement(by: PlaceBy.canvas, arc: 60);
    var still = heardAt(doc, car, place, 0)!.angle;
    expect(still, lessThan(-20), reason: "at the left edge, from the left");
    var p = MotionPlayer()..step(doc, 0, 0);
    p.launch(doc, 0, "car", "drive", 0);
    p.step(doc, 0, 0.5);
    expect(heardAt(doc, car, place, 0, live: p)!.angle, greaterThan(still + 20),
        reason: "driven right by its slot, heard from further right");
  });

  // Ken's systems review, 2026-11-08: "on" another element went where its
  // timeline had it, not where a slot had sent it.
  test("a place on a launched element is where that element is", () {
    var doc = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "cam",
          x: 0,
          y: 0,
          width: 20,
          height: 20,
          motion: ElementMotion(clips: [
            MotionClip(id: "follow", length: 4, keys: {
              MotionProp.x: [
                MotionKey(0, MotionPlace(MotionPlaceKind.on, target: "ball")),
                MotionKey(4, MotionPlace(MotionPlaceKind.on, target: "ball")),
              ],
            }),
          ], placed: [
            ClipPlacement(id: "p", clip: "follow"),
          ]))),
      ShapeElement(const ElementBase(
          id: "ball",
          x: 100,
          y: 0,
          width: 20,
          height: 20,
          motion: ElementMotion(clips: [
            MotionClip(id: "roll", length: 1, keys: {
              MotionProp.x: [
                MotionKey(0, MotionNumber(200)),
                MotionKey(1, MotionNumber(200)),
              ],
            }),
          ]))),
    ]);
    var cam = doc.elementById("cam")!;
    expect(poseWithMotion(cam, 12, doc).dx, closeTo(100, 1),
        reason: "on the ball where it is set");
    var p = MotionPlayer()..step(doc, 0, 0);
    p.launch(doc, 0, "ball", "roll", 0);
    p.step(doc, 0, 0.5);
    expect(poseWithMotion(cam, 12, doc, live: p).dx, closeTo(300, 1),
        reason: "on the ball where its slot has rolled it");
  });

  // Ken's systems review, 2026-11-08: a Look at aimed where its target's
  // timeline had it, not where a slot had sent it.
  test("a Look at follows a target launched from its slot", () {
    var doc = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "eye",
          x: 0,
          y: 0,
          width: 20,
          height: 20,
          motion: ElementMotion(devices: [
            MotionDevice(MotionDeviceKind.lookAt,
                id: "l", target: "ball", values: {"smooth": 0}),
          ]))),
      ShapeElement(const ElementBase(
          id: "ball",
          x: 300,
          y: 0,
          width: 20,
          height: 20,
          motion: ElementMotion(clips: [
            MotionClip(id: "drop", length: 1, keys: {
              MotionProp.y: [
                MotionKey(0, MotionNumber(300)),
                MotionKey(1, MotionNumber(300)),
              ],
            }),
          ]))),
    ]);
    var eye = doc.elementById("eye")!;
    var still = poseWithMotion(eye, 0, doc).rotate;
    expect(still, closeTo(0, 1e-6), reason: "the ball level with it");
    var p = MotionPlayer()..step(doc, 0, 0);
    p.launch(doc, 0, "ball", "drop", 0);
    p.step(doc, 0, 0.5);
    var after = poseWithMotion(eye, 0, doc, live: p).rotate;
    expect(after, closeTo(45, 1), reason: "the ball dropped, down and across");
  });

  // Ken's systems review, 2026-11-08: a game's scene left snapped its
  // slot-launched elements back as the next one's start cleared them.
  test("what plays, frozen, outlasts the player being cleared", () {
    var doc = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "coin",
          width: 20,
          height: 20,
          motion: ElementMotion(clips: [MotionClip(id: "pop", length: 1)]))),
    ]);
    var p = MotionPlayer()..step(doc, 0, 0);
    p.launch(doc, 0, "coin", "pop", 0);
    p.step(doc, 0, 0.5);
    var held = p.frozen();
    p.clear();
    expect(p.of("coin"), isNull);
    expect(held.of("coin"), isNotNull);
    expect(held.clock, 0.5);
  });

  // Ken's systems review, 2026-11-08: stamped, every copy wiggled as one.
  group("drawn once and stamped, or each in turn", () {
    ShapeElement coins({List<MotionDevice> devices = const []}) => ShapeElement(
        ElementBase(
            id: "coin",
            x: 0,
            y: 100,
            width: 20,
            height: 20,
            motion: ElementMotion(
                devices: devices,
                instances: const InstanceSet(items: [
                  ElementInstance("i0"),
                  ElementInstance("i1", dx: 100),
                ]))),
        fill: const Color(0xFF000000));
    const each = MotionDevice(MotionDeviceKind.wiggle,
        id: "w", values: {"seed": 1, "amount": 30, "speed": 3});

    test("only where they would look the same", () {
      expect(stampsCopies(coins(), null), isTrue);
      expect(stampsCopies(coins(devices: [each]), null), isFalse,
          reason: "a wiggle each its own");
      expect(stampsCopies(coins(devices: [each.withValue("seed", 0)]), null),
          isTrue,
          reason: "a wiggle the same for all");
      expect(
          stampsCopies(
              coins(devices: const [
                MotionDevice(MotionDeviceKind.lookAt, id: "l")
              ]),
              null),
          isFalse);
    });

    test("each its own wiggle, each drawn where its own puts it", () async {
      var e = coins(devices: [each]);
      var doc = CanvasDocument(frames: 100, elements: [e]);
      var p0 = poseWithMotion(e, 7, doc, instance: 0);
      var p1 = poseWithMotion(e, 7, doc, instance: 1);
      expect((p0.dx - (p1.dx - 100)).abs(), greaterThan(1),
          reason: "the two wiggle apart");
      var rec = PictureRecorder();
      paintElement(Canvas(rec), e, 7, document: doc);
      var img = await rec.endRecording().toImage(300, 300);
      var px = (await img.toByteData())!.buffer.asUint8List();
      bool inked(double x, double y) =>
          px[(y.round() * 300 + x.round()) * 4 + 3] > 128;
      // Each copy's middle, where its own pose has it.
      for (var p in [p0, p1]) {
        expect(inked(10 + p.dx, 110 + p.dy), isTrue,
            reason: "drawn at (${p.dx}, ${p.dy})");
      }
    });
  });

  // Ken's systems review, 2026-11-08: a coin touched held its pop for as
  // long as the latest-starting copy would have taken.
  test("one copy's own play ends at its own length", () {
    var doc = CanvasDocument(elements: [
      ShapeElement(const ElementBase(
          id: "coin",
          width: 20,
          height: 20,
          motion: ElementMotion(
              clips: [MotionClip(id: "pop", length: 1)],
              instances: InstanceSet(items: [
                ElementInstance("i0"),
                ElementInstance("i1", start: 5),
              ])))),
    ]);
    var p = MotionPlayer()..step(doc, 0, 0);
    p.launch(doc, 0, instanceKey("coin", "i0"), "pop", 0);
    p.step(doc, 0, 0);
    expect(p.isPlaying(instanceKey("coin", "i0")), isTrue);
    p.step(doc, 0, 1.2);
    expect(p.isPlaying(instanceKey("coin", "i0")), isFalse,
        reason: "done at one second, not six");
    // The element's own play waits for its last copy.
    p.launch(doc, 0, "coin", "pop", 2);
    p.step(doc, 0, 2);
    p.step(doc, 0, 4);
    expect(p.isPlaying("coin"), isTrue);
  });

  group("in a game", () {
    CanvasDocument world() => CanvasDocument(
          game: true,
          counts: const [GameCount("coins", "Coins")],
          elements: [
            ShapeElement(const ElementBase(
                id: "hero",
                x: 100,
                y: 600,
                width: 40,
                height: 60,
                play: PlaySpec(as: PlayAs.platformer))),
            ShapeElement(const ElementBase(
                id: "coin",
                x: 300,
                y: 680,
                width: 20,
                height: 20,
                play: PlaySpec(
                    as: PlayAs.pickup,
                    touched: GameEffect(does: GameDoes.add, count: "coins")),
                motion: ElementMotion(
                    instances: InstanceSet(items: [
                  ElementInstance("i0"),
                  ElementInstance("i1", dx: 100),
                  ElementInstance("i2", dx: 700),
                ])))),
          ],
        );

    void run(GameRun g, CanvasDocument doc, double seconds,
        {bool right = false}) {
      g.input.keys
        ..clear()
        ..addAll([if (right) LogicalKeyboardKey.arrowRight.keyId]);
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.step(doc, 0, 1 / 60);
      }
    }

    test("each instance is collected on its own, and comes back", () {
      var g = GameRun();
      var doc = world();
      run(g, doc, 0.2);
      run(g, doc, 1.2, right: true);
      expect(g.countOf(doc, "coins"), 2, reason: "the two in reach");
      expect(g.gone, {"coin#i0", "coin#i1"});
      var seen = g.view(doc).elementById("coin")!;
      expect(seen.base.motion.instances!.items.map((x) => x.id), ["i2"],
          reason: "the one not taken is still drawn");
      // Started again: every coin back.
      g.reset();
      run(g, doc, 0.1);
      expect(g.view(doc).elementById("coin")!.base.motion.instances!.count, 3);
      expect(g.countOf(doc, "coins"), 0);
    });

    test("an instance's sound is set off from where it is", () {
      var doc = world();
      var coin = doc.elementById("coin")!;
      doc = doc.withElement(coin.rebase(
          coin.base.copyWith(play: coin.base.play.copyWith(sound: "ding"))));
      var g = GameRun();
      run(g, doc, 0.2);
      g.events.clear();
      run(g, doc, 1.2, right: true);
      var from = [
        for (var e in g.events)
          if (e.sound == "ding") e.soundFrom
      ];
      expect(from, [310, 410], reason: "each coin's middle across the page");
    });
  });

  group("elsewhere", () {
    test("an EPUB's picture of it holds each instance at its place", () async {
      // Its pose is the EPUB's to move: each instance still at its own
      // place from the element.
      var d = doc(three(vary: {VaryWhat.size: const Vary(VaryHow.byOrder, 0)}),
          clip: false);
      var rec = PictureRecorder();
      var canvas = Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 100),
          Paint()..color = const Color(0xFFFFFFFF));
      paintElement(canvas, d.elementById("a")!, 0,
          document: d, poseOutside: true);
      var px =
          (await (await rec.endRecording().toImage(300, 100)).toByteData())!;
      for (var x in [20, 70, 120]) {
        expect(red(px, x, 20), 0, reason: "an instance at $x");
      }
    });

    test("a reused element has a row on the timeline", () {
      var c = CanvasController(doc(three(), clip: false),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      expect(motionRowsOf(c).map((e) => e.id), ["a"]);
    });

    test("its sound is heard from the middle of its instances", () {
      var d = CanvasDocument(elements: [
        ShapeElement(const ElementBase(
            id: "a",
            x: 0,
            width: 40,
            height: 40,
            motion: ElementMotion(
                instances: InstanceSet(items: [
              ElementInstance("i0"),
              ElementInstance("i1", dx: 1200),
            ])))),
      ]);
      var heard = heardAt(d, d.elementById("a")!,
          const SoundPlacement(by: PlaceBy.canvas, arc: 60), 0)!;
      // Its instances' middles at 20 and 1220: 620 across 1280.
      expect(heard.angle, closeTo((620 / 1280 - 0.5) * 60, 0.01));
    });
  });
}

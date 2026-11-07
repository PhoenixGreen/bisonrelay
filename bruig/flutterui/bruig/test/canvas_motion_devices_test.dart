import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/motion_looks.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_cards.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Canvas, Paint;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_audio_fake.dart';
import 'canvas_chain_helpers.dart';

// canvas_motion_devices_test.dart is an element's motion chain beyond its
// clips: pose devices left of its drawing, pulled -- a Time device asking
// those to its left for another moment -- and looks right of it, laid on
// what is drawn in their order.

/// across moves 100 to the right over [length] seconds, placed at the start.
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

CanvasDocument doc(List<MotionDevice> devices, {bool clip = true}) =>
    CanvasDocument(frames: 240, frameRate: 24, elements: [
      ShapeElement(
          ElementBase(
              id: "a",
              width: 10,
              height: 10,
              motion: ElementMotion(
                  clips: clip ? const [across] : const [],
                  placed: clip
                      ? const [ClipPlacement(id: "p", clip: "go", length: 4)]
                      : const [],
                  devices: devices)),
          fill: const Color(0xFF000000)),
    ]);

double dxAt(CanvasDocument d, int frame, {int? upto}) =>
    poseWithMotion(d.elementById("a")!, frame, d, upto: upto).dx;

/// square is a 40-wide black square at (130, 130) with [looks] on it.
ShapeElement square(List<MotionDevice> looks) => ShapeElement(
    ElementBase(
        id: "s",
        x: 130,
        y: 130,
        width: 40,
        height: 40,
        motion: ElementMotion(devices: looks)),
    fill: const Color(0xFF000000));

Future<ByteData> draw(CanvasElement e) async {
  var rec = PictureRecorder();
  var canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 300),
      Paint()..color = const Color(0xFFFFFFFF));
  paintElement(canvas, e, 0);
  var img = await rec.endRecording().toImage(300, 300);
  return (await img.toByteData())!;
}

/// red, green and blue of the pixel at [x], [y].
(int, int, int) rgb(ByteData px, int x, int y) {
  var i = (y * 300 + x) * 4;
  return (px.getUint8(i), px.getUint8(i + 1), px.getUint8(i + 2));
}

void main() {
  group("the model", () {
    test("devices are kept, with their ids, and an element of devices alone",
        () {
      var m = const ElementMotion(devices: [
        MotionDevice(MotionDeviceKind.glow, values: {"radius": 20}),
        MotionDevice(MotionDeviceKind.time, on: false),
      ]);
      var back = ElementMotion.fromJson(m.toJson());
      expect(back.devices.map((d) => d.kind),
          [MotionDeviceKind.glow, MotionDeviceKind.time]);
      expect(back.devices.first.value("radius"), 20);
      expect(back.devices.last.on, isFalse);
      expect(back.devices.map((d) => d.id).toSet().length, 2,
          reason: "each its own id");
      var e = ShapeElement(ElementBase(id: "x", motion: back));
      expect(e.base.toJson().containsKey("motion"), isTrue,
          reason: "no clips, but devices to keep");
    });

    test("pose devices run left of the drawing, looks right of it", () {
      var order = motionDevicesInOrder(const [
        MotionDevice(MotionDeviceKind.shadow),
        MotionDevice(MotionDeviceKind.time),
        MotionDevice(MotionDeviceKind.glow),
      ]);
      expect(order.map((d) => d.kind), [
        MotionDeviceKind.time,
        MotionDeviceKind.shadow,
        MotionDeviceKind.glow,
      ]);
      expect(MotionDeviceKind.on(MotionDeviceSide.pose),
          containsAll([MotionDeviceKind.time, MotionDeviceKind.wiggle]));
      expect(MotionDeviceKind.on(MotionDeviceSide.pose),
          isNot(contains(MotionDeviceKind.instances)),
          reason: "always there, as Reuse");
      expect(MotionDeviceKind.on(MotionDeviceSide.look),
          isNot(contains(MotionDeviceKind.time)));
    });

    test("only a pose device makes it move", () {
      expect(
          const ElementMotion(devices: [MotionDevice(MotionDeviceKind.glow)])
              .moves,
          isFalse);
      expect(
          const ElementMotion(devices: [MotionDevice(MotionDeviceKind.time)])
              .moves,
          isTrue);
      expect(
          const ElementMotion(
              devices: [MotionDevice(MotionDeviceKind.time, on: false)]).moves,
          isFalse);
    });
  });

  group("Time", () {
    MotionDevice time(Map<String, double> v) =>
        MotionDevice(MotionDeviceKind.time, values: v);

    test("asks for another moment", () {
      expect(retimed(time({"speed": 2}), 1), 2);
      expect(retimed(time({"offset": 1.5}), 1), 2.5);
      expect(retimed(time({"offset": -3}), 1), 0, reason: "not before nought");
      expect(retimed(time({"loop": 1, "every": 2}), 5), closeTo(1, 1e-9));
      expect(retimed(time({"loop": 2, "every": 2}), 3), closeTo(1, 1e-9),
          reason: "there and back");
      expect(retimed(time({"hold": 3}), 0.2), closeTo(0.125, 1e-9),
          reason: "held in steps of three frames at 24");
    });

    test("the clips to its left play at its time (rule 2)", () {
      var plain = doc(const []);
      var fast = doc(const [
        MotionDevice(MotionDeviceKind.time, values: {"speed": 2})
      ]);
      expect(dxAt(plain, 24), closeTo(25, 0.01));
      expect(dxAt(fast, 24), closeTo(50, 0.01), reason: "twice as far on");
      expect(dxAt(fast, 24, upto: 0), closeTo(25, 0.01),
          reason: "asked at the join before it, as it was");
    });

    test("two in a row compose, the right one asking the left", () {
      var d = doc(const [
        MotionDevice(MotionDeviceKind.time, values: {"speed": 2}),
        MotionDevice(MotionDeviceKind.time, values: {"offset": 0.5}),
      ]);
      // (1 + 0.5) seconds, then twice that: 3 seconds into the clip.
      expect(dxAt(d, 24), closeTo(75, 0.01));
    });

    test("where it is drawn is where it is picked", () {
      var d = doc(const [
        MotionDevice(MotionDeviceKind.time, values: {"speed": 2})
      ]);
      var b = d.elementById("a")!.movedBoundsAt(24, d);
      expect(b.left, closeTo(50, 0.01));
    });

    test("an element with only a Time device and no clips stays put", () {
      var d = doc(const [MotionDevice(MotionDeviceKind.time)], clip: false);
      expect(dxAt(d, 48), 0);
    });
  });

  group("looks", () {
    test("each reaches as far as it draws", () {
      expect(looksReach(const []), 0);
      expect(
          looksReach(const [
            MotionDevice(MotionDeviceKind.shadow,
                values: {"distance": 10, "blur": 5}),
          ]),
          20);
      expect(looksReach(const [MotionDevice(MotionDeviceKind.colour)]), 0);
    });

    test("a shadow falls where the light puts it", () async {
      // Straight down: the angle is from the top, clockwise.
      var px = await draw(square(const [
        MotionDevice(MotionDeviceKind.shadow,
            values: {"distance": 30, "blur": 0, "angle": 180, "strength": 1}),
      ]));
      expect(rgb(px, 150, 150), (0, 0, 0), reason: "the square");
      expect(rgb(px, 150, 190).$1, lessThan(40), reason: "its shadow below");
      expect(rgb(px, 150, 115).$1, greaterThan(240), reason: "none above");
    });

    test("a shadow keeps to its light when the element turns", () async {
      var turned = ShapeElement(
          ElementBase(
              id: "s",
              x: 130,
              y: 130,
              width: 40,
              height: 40,
              rotation: 90,
              motion: const ElementMotion(devices: [
                MotionDevice(MotionDeviceKind.shadow, values: {
                  "distance": 30,
                  "blur": 0,
                  "angle": 180,
                  "strength": 1
                }),
              ])),
          fill: const Color(0xFF000000));
      var px = await draw(turned);
      expect(rgb(px, 150, 190).$1, lessThan(40), reason: "still below");
      expect(rgb(px, 190, 150).$1, greaterThan(240), reason: "not beside");
    });

    test("an outline grows round it in its colour", () async {
      var px = await draw(square(const [
        MotionDevice(MotionDeviceKind.outline,
            values: {"width": 6}, colour: 0xFFFF0000),
      ]));
      var (r, g, b) = rgb(px, 133 - 6, 150);
      expect(r, greaterThan(200));
      expect(g, lessThan(60));
      expect(rgb(px, 150, 150), (0, 0, 0), reason: "itself on top");
    });

    test("colour turns its colours", () async {
      var red = ShapeElement(
          ElementBase(
              id: "s",
              x: 130,
              y: 130,
              width: 40,
              height: 40,
              motion: const ElementMotion(devices: [
                MotionDevice(MotionDeviceKind.colour, values: {"hue": 120}),
              ])),
          fill: const Color(0xFFFF0000));
      var (r, g, _) = rgb(await draw(red), 150, 150);
      expect(g, greaterThan(r), reason: "red turned towards green");
    });

    test("a look switched off draws nothing", () async {
      var px = await draw(square(const [
        MotionDevice(MotionDeviceKind.shadow,
            on: false, values: {"distance": 30, "blur": 0, "angle": 180}),
      ]));
      expect(rgb(px, 150, 190).$1, greaterThan(240));
    });
  });

  group("the controller", () {
    test("adds each kind on its own side, moves it only there, removes it", () {
      var c = CanvasController(doc(const [], clip: false),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var glow = c.addMotionDevice("a", MotionDeviceKind.glow);
      var time = c.addMotionDevice("a", MotionDeviceKind.time);
      var blur = c.addMotionDevice("a", MotionDeviceKind.blur);
      expect(c.motionDevicesOf("a").map((d) => d.id), [time, glow, blur]);
      c.moveMotionDevice("a", blur, -1);
      expect(c.motionDevicesOf("a").map((d) => d.id), [time, blur, glow]);
      c.moveMotionDevice("a", blur, -1);
      expect(c.motionDevicesOf("a").map((d) => d.id), [time, blur, glow],
          reason: "a look never crosses the drawing");
      c.removeMotionDevice("a", glow);
      expect(c.motionDevicesOf("a").map((d) => d.id), [time, blur]);
      c.undo();
      expect(c.motionDevicesOf("a").length, 3);
    });
  });

  group("the Motion view", () {
    Future<CanvasController> pump(WidgetTester tester,
        {double scale = 1, double height = 300, bool clip = false}) async {
      var c = CanvasController(doc(const [], clip: clip),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly("a");
      tester.view.physicalSize = Size(2400, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: height)))),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      return c;
    }

    for (var (scale, height) in [(1.0, 300.0), (1.5, 300.0), (1.0, 170.0)]) {
      testWidgets(
          "an element with no clips shows its chain, at $scale, $height",
          (tester) async {
        var c = await pump(tester, scale: scale, height: height);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey("drawingCard")), findsOneWidget);
        // Only moves are offered before the drawing, only looks after.
        await openAdd(
            tester,
            find.descendant(
                of: find.byKey(const ValueKey("addMotionPose")),
                matching: find.byKey(const ValueKey("addMoveOpen"))));
        expect(find.byKey(const ValueKey("addMotion-glow")), findsNothing);
        await tester.tap(find.byKey(const ValueKey("addMotion-time")));
        await tester.pump(const Duration(milliseconds: 100));
        await openAdd(
            tester,
            find.descendant(
                of: find.byKey(const ValueKey("addMotionLook")),
                matching: find.byKey(const ValueKey("addLookOpen"))));
        expect(find.byKey(const ValueKey("addMotion-time")), findsNothing);
        await tester.tap(find.byKey(const ValueKey("addMotion-shadow")));
        await tester.pump(const Duration(milliseconds: 100));
        var devices = c.motionDevicesOf("a");
        expect(devices.map((d) => d.kind),
            [MotionDeviceKind.time, MotionDeviceKind.shadow]);
        expect(tester.takeException(), isNull);
        // The time device left of the drawing, the shadow right of it.
        var drawing =
            tester.getCenter(find.byKey(const ValueKey("drawingCard"))).dx;
        expect(
            tester
                .getCenter(find.byKey(ValueKey("mdevCard-${devices[0].id}")))
                .dx,
            lessThan(drawing));
        expect(
            tester
                .getCenter(find.byKey(ValueKey("mdevCard-${devices[1].id}")))
                .dx,
            greaterThan(drawing));
        // Switched off, and taken off.
        await tester.tap(find.byKey(ValueKey("mdevPower-${devices[1].id}")));
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionDevicesOf("a")[1].on, isFalse);
        await revealInMenu(tester, "mdevRemove-${devices[1].id}");
        await tester.tap(find.byKey(ValueKey("mdevRemove-${devices[1].id}")));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.motionDevicesOf("a").length, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("with a clip, its chain follows the clip's cards",
        (tester) async {
      var c = await pump(tester, clip: true);
      c.pickMotion("a", "go");
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey("motionClipsCard")), findsOneWidget);
      // Past the clip's cards, along the row.
      var row = find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.right)
          .first;
      // Jumped, not dragged: a drag there is the Keys editor's.
      var position = tester.state<ScrollableState>(row).position;
      // A lazy row learns how long it is as it lays out: jumped to the end
      // until the end stays put.
      for (var i = 0; i < 4; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
      }
      expect(find.byKey(const ValueKey("drawingCard")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group("preview from here", () {
    var twice = const [
      MotionDevice(MotionDeviceKind.time, values: {"speed": 2})
    ];

    test("how fast it goes at each join", () {
      var d = doc(twice);
      var e = d.elementById("a")!;
      expect(motionSpeedAt(e, 24, d, upto: 0).$1, closeTo(25, 0.5),
          reason: "after its clip: 100 across in 4 seconds");
      expect(motionSpeedAt(e, 24, d, upto: 1).$1, closeTo(50, 0.5),
          reason: "after Time at twice the speed");
    });

    test("the stage is shown the chain as it stands at a join", () {
      var c = CanvasController(doc(twice), audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      var e = c.document.elementById("a")!;
      expect(c.liveMotion, isNull, reason: "nothing playing, nothing shown");
      var tick = c.motionTick;
      c.previewMotionFrom("a", 0);
      expect(c.motionTick, greaterThan(tick), reason: "the stage repaints");
      expect(poseWithMotion(e, 24, c.document, live: c.liveMotion).dx,
          closeTo(25, 0.01));
      expect(poseWithMotion(e, 24, c.document).dx, closeTo(50, 0.01),
          reason: "an export, given nothing, draws the chain whole");
      c.previewMotionFrom("a", null);
      expect(c.liveMotion, isNull);
      expect(poseWithMotion(e, 24, c.document, live: c.liveMotion).dx,
          closeTo(50, 0.01));
    });

    testWidgets("a join after the clips and after each move, clicked",
        (tester) async {
      var c = CanvasController(doc(twice, clip: false),
          audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly("a");
      tester.view.physicalSize = const Size(2000, 300);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: 300)))),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey("motionJoin-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("motionJoin-1")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("motionJoin-1")));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.motionPreview, ("a", 1));
      await tester.tap(find.byKey(const ValueKey("motionJoin-1")));
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.motionPreview, isNull, reason: "clicked again, whole");
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // Ken, 2026-11-08: the motion chain's pass against the prototype.
  group("the pass", () {
    Future<CanvasController> panel(WidgetTester tester, CanvasDocument d,
        {String pick = "a"}) async {
      var c = CanvasController(d, audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly(pick);
      tester.view.physicalSize = const Size(2400, 300);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: 300)))),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      return c;
    }

    testWidgets("a device switched off or a modulator: no join after it",
        (tester) async {
      var c = await panel(
          tester,
          doc([
            const MotionDevice(MotionDeviceKind.wiggle, id: "m0", on: false),
            const MotionDevice(MotionDeviceKind.lfo, id: "m1"),
            const MotionDevice(MotionDeviceKind.oscillate, id: "m2"),
          ], clip: false));
      // Before them, and after the oscillate (two on: the LFO counted).
      expect(find.byKey(const ValueKey("motionJoin-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("motionJoin-1")), findsNothing);
      expect(find.byKey(const ValueKey("motionJoin-2")), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(c.motionPreview, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("every move has a screen; Time's Every only while looping",
        (tester) async {
      await panel(
          tester,
          doc([
            const MotionDevice(MotionDeviceKind.time, id: "m0"),
            const MotionDevice(MotionDeviceKind.spring, id: "m1"),
            const MotionDevice(MotionDeviceKind.lookAt, id: "m2"),
          ], clip: false));
      for (var id in ["m0", "m1", "m2"]) {
        expect(find.byKey(ValueKey("mdevScreen-$id")), findsOneWidget);
      }
      expect(find.byKey(const ValueKey("mdev-m0-every")), findsNothing,
          reason: "Loop is Off");
      expect(find.byKey(const ValueKey("mdev-m0-speed")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("folded on one element is not folded on the next",
        (tester) async {
      var d = CanvasDocument(frames: 240, frameRate: 24, elements: [
        for (var id in ["a", "b"])
          ShapeElement(
              ElementBase(
                  id: id,
                  width: 10,
                  height: 10,
                  motion: const ElementMotion(devices: [
                    MotionDevice(MotionDeviceKind.wiggle, id: "m0"),
                  ])),
              fill: const Color(0xFF000000)),
      ]);
      var c = await panel(tester, d);
      await tester.tap(find.byKey(ValueKey("deviceFold-mdev:m0")));
      await tester.pump();
      expect(find.byKey(const ValueKey("mdev-m0-speed")), findsNothing);
      c.selectOnly("b");
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey("mdev-m0-speed")), findsOneWidget,
          reason: "b's wiggle is its own");
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("a camera has no looks to add", (tester) async {
      var d = CanvasDocument(frames: 240, frameRate: 24, elements: [
        const CameraElement(ElementBase(id: "cam", width: 160, height: 90)),
      ]);
      await panel(tester, d, pick: "cam");
      expect(find.byKey(const ValueKey("cameraNoLooks")), findsOneWidget);
      expect(find.byKey(const ValueKey("addMotionLook")), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test("a shadow turning with it, and a zoom's centre, kept", () {
      var shadow =
          const MotionDevice(MotionDeviceKind.shadow, values: {"turns": 1});
      expect(MotionDevice.fromJson(shadow.toJson())!.value("turns"), 1);
      var zoom = const SceneTransition(
          kind: SceneTransitionKind.zoomIn, centreX: 0.2, centreY: 0.8);
      var back = SceneTransition.fromJson(zoom.toJson());
      expect((back.centreX, back.centreY), (0.2, 0.8));
      expect(SceneTransitionKind.zoomIn.takesCentre, isTrue);
      expect(motionFamily(MotionDeviceKind.lfo), "Modulators");
    });
  });

  // Ken, 2026-11-08: the prototype's Motion clips card -- arriving, looping,
  // leaving among them -- and its Curves tab.
  group("motion clips", () {
    /// still is a clip holding x at [x] for four seconds.
    MotionClip still(String id, double x, {bool replace = false}) => MotionClip(
            id: id,
            kind: MotionKind.action,
            length: 4,
            replace: replace,
            keys: {
              MotionProp.x: [
                MotionKey(0, MotionNumber(x)),
                MotionKey(4, MotionNumber(x))
              ],
            });
    CanvasDocument layered({required bool replace}) =>
        CanvasDocument(frames: 240, frameRate: 24, elements: [
          ShapeElement(
              ElementBase(
                  id: "a",
                  width: 10,
                  height: 10,
                  motion: ElementMotion(clips: [
                    still("base", 100),
                    still("over", 30, replace: replace),
                  ], placed: const [
                    ClipPlacement(id: "p1", clip: "base", length: 4),
                    ClipPlacement(id: "p2", clip: "over", layer: 1, length: 4),
                  ])),
              fill: const Color(0xFF000000)),
        ]);

    test("a layer that replaces takes over from the one under it", () {
      expect(dxAt(layered(replace: false), 24), closeTo(130, 0.01),
          reason: "added: 100 and 30");
      expect(dxAt(layered(replace: true), 24), closeTo(30, 0.01),
          reason: "replacing: its 30 alone");
      var back = MotionClip.fromJson(still("x", 1, replace: true).toJson());
      expect(back!.replace, isTrue, reason: "kept with the canvas");
    });

    testWidgets("its card sets what it is, how it mixes and launches; Curves",
        (tester) async {
      var d = CanvasDocument(frames: 240, frameRate: 24, elements: [
        ShapeElement(
            ElementBase(
                id: "a",
                width: 10,
                height: 10,
                motion: ElementMotion(
                    clips: [still("go", 0)], slots: const ["go", "", "", ""])),
            fill: const Color(0xFF000000)),
      ]);
      var c = CanvasController(d, audioEngine: FakeEngine(const {}));
      addTearDown(c.dispose);
      c.selectOnly("a");
      c.pickMotion("a", "go");
      tester.view.physicalSize = const Size(2600, 420);
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
                body: ListenableBuilder(
                    listenable: c,
                    builder: (context, _) =>
                        AnimationPanel(controller: c, height: 420)))),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      MotionClip clip() => c.document.elementById("a")!.base.motion.clip("go")!;
      expect(find.byKey(const ValueKey("motionClipsCard")), findsOneWidget);
      expect(find.byKey(const ValueKey("motionClipsPick-go")), findsOneWidget);
      expect(find.byKey(const ValueKey("animDevice-arrives")), findsNothing,
          reason: "how it arrives is its clip's now");
      void pick<T>(String key, T v) =>
          tester.widget<StudioDrop<T>>(find.byKey(ValueKey(key))).onChanged(v);
      pick<MotionKind?>("motionClipsKind", MotionKind.arrive);
      await tester.pump();
      expect(clip().kind, MotionKind.arrive);
      expect(clip().keys, isNotEmpty, reason: "a ready-made arrival");
      // Its own arrival, a style of the element's, played across the clip
      // (Ken: converted -- the clip holds it).
      pick("motionClipsPreset", "own:wipe");
      await tester.pump();
      expect(clip().inside["own"], isTrue);
      expect(clip().keys, isEmpty, reason: "its own, not keys");
      expect(
          CanvasController.elementAnimationOf(c.document.elementById("a")!)
              .preset,
          ElementAnimationPreset.wipe);
      c.undo();
      expect(clip().inside["own"], isNot(true), reason: "one undo, both");
      expect(
          CanvasController.elementAnimationOf(c.document.elementById("a")!)
              .preset,
          ElementAnimationPreset.none);
      pick("motionClipsLayer", true);
      await tester.pump();
      expect(clip().replace, isTrue);
      tester
          .widget<StudioDrop<ClipLaunch>>(
              find.byKey(const ValueKey("animLaunch")))
          .onChanged(ClipLaunch.gate);
      await tester.pump();
      expect(clip().launch, ClipLaunch.gate);
      c.undo();
      expect(clip().launch, ClipLaunch.trigger, reason: "one undo each");
      // Its Curves, across the panel.
      c.showMotionCurves("a", "go");
      await tester.pump();
      expect(find.byKey(const ValueKey("motionCurves")), findsOneWidget);
      expect(find.byKey(const ValueKey("motionClipsCard")), findsNothing);
      c.closeMotionCurves();
      await tester.pump();
      expect(find.byKey(const ValueKey("motionClipsCard")), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

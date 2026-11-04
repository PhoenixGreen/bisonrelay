import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Animation panel: the picked clip as a row of devices. A ready-made
// motion picked writes its keys; a click on a Keys row adds one, a drag
// retimes it; the Keys device is dragged wider; each change one undo step.

Future<(CanvasController, String)> pump(WidgetTester tester,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  var c =
      CanvasController(CanvasDocument(frames: 240, frameRate: 24, elements: [
    ShapeElement(const ElementBase(
        id: "a", name: "Logo", x: 100, y: 100, width: 50, height: 50)),
    ShapeElement(const ElementBase(
        id: "b", name: "Box", x: 400, y: 100, width: 50, height: 50)),
  ]));
  addTearDown(c.dispose);
  var clip = c.newClip("a", preset: presetNamed("Pop"), slot: 0);
  c.pickMotion("a", clip);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
    ],
    child: MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(
          size: const Size(1600, 900), textScaler: TextScaler.linear(scale)),
      child: Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter,
              child: AnimationPanel(controller: c, height: 360))),
    )),
  ));
  await tester.pumpAndSettle();
  return (c, clip);
}

void main() {
  testWidgets("nothing picked, it says how to pick something", (tester) async {
    var (c, _) = await pump(tester);
    c.pickMotion(null, null);
    await tester.pump();
    expect(find.textContaining("Pick a slot"), findsOneWidget);
  });

  testWidgets("a ready-made motion picked writes the clip's keys",
      (tester) async {
    var (c, clip) = await pump(tester);
    expect(find.text("Logo · Pop"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("animPreset-Slide in")));
    await tester.pumpAndSettle();
    var m = c.motionOf("a").clip(clip)!;
    expect(m.preset, "Slide in");
    expect(m.keys[MotionProp.x]!.first.value, isA<MotionPlace>(),
        reason: "it slides in from off an edge");
    c.undo();
    expect(c.motionOf("a").clip(clip)!.preset, "Pop", reason: "one step");
  });

  testWidgets("a click on a Keys row adds a key, picked to be changed",
      (tester) async {
    var (c, clip) = await pump(tester);
    var row = find.byKey(const ValueKey("animKeysRow-turn"));
    var box = tester.getRect(row);
    await tester.tapAt(Offset(box.left + box.width / 2, box.center.dy));
    await tester.pumpAndSettle();
    var m = c.motionOf("a").clip(clip)!;
    expect(m.keys[MotionProp.turn], hasLength(1));
    expect(m.edited, isTrue, reason: "keys by hand");
    expect(find.byKey(const ValueKey("animKeyEase")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("animKeyRemove")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(clip)!.keys[MotionProp.turn], isNull);
  });

  testWidgets("a key dragged along is retimed, as one step", (tester) async {
    var (c, clip) = await pump(tester);
    var before = c.motionOf("a").clip(clip)!;
    var prop = before.keys.keys.first;
    var k = before.keys[prop]!.first; // at 0, the row's left edge
    var box = tester.getRect(find.byKey(ValueKey("animKeysRow-${prop.name}")));
    var x = box.left + k.t / before.length * box.width + 2;
    await tester.timedDragFrom(Offset(x, box.center.dy),
        Offset(box.width / 4, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    var moved = c.motionOf("a").clip(clip)!.keys[prop]!;
    expect(moved.map((m) => m.t), isNot(before.keys[prop]!.map((m) => m.t)));
    c.undo();
    expect(c.motionOf("a").clip(clip)!.keys[prop]!.map((m) => m.t),
        before.keys[prop]!.map((m) => m.t));
  });

  testWidgets("the Keys device is dragged wider", (tester) async {
    await pump(tester);
    var keys = find.byKey(const ValueKey("animDevice-keys"));
    var was = tester.getSize(keys).width;
    await tester.drag(
        find.byKey(const ValueKey("animKeysGrip")), const Offset(200, 0));
    await tester.pumpAndSettle();
    // Less the drag's slop.
    expect(tester.getSize(keys).width, closeTo(was + 200, 25));
  });

  testWidgets("placed, its start is pinned to a marker", (tester) async {
    var (c, clip) = await pump(tester);
    var m = c.addMarker(48);
    var p = c.placeClip("a", clip, seconds: 0);
    c.pickMotion("a", clip, placement: p);
    await tester.pumpAndSettle();
    c.pinPlacement("a", p, ClipPin(PinKind.marker, target: m));
    await tester.pumpAndSettle();
    expect(c.spanOf(p)!.start, 2);
    // Keys folded, for Timing to be in view beside it.
    await tester.tap(find.byKey(const ValueKey("deviceFold-anim-keys")));
    await tester.pumpAndSettle();
    expect(find.textContaining("2.00–"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("deviceFold-anim-keys")));
    await tester.pumpAndSettle();
  });

  for (var scale in [0.65, 1.5]) {
    testWidgets("at text size $scale, nothing overflows", (tester) async {
      await pump(tester, scale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("Keys has the room the others leave; double-clicked, again",
      (tester) async {
    await pump(tester);
    // Its width is kept for the session: as it starts, filling.
    Future<void> doubleTap() async {
      await tester.tap(find.byKey(const ValueKey("animKeysGrip")));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey("animKeysGrip")));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    var keys = find.byKey(const ValueKey("animDevice-keys"));
    var panel = tester.getRect(find.byKey(const ValueKey("animationPanel")));
    expect(
        tester.getSize(keys).width, greaterThanOrEqualTo(panel.width / 2 - 10),
        reason: "half the panel at least, the devices after it scrolled");
    expect(tester.getRect(keys).left, lessThan(panel.width / 2),
        reason: "and in view");
    var was = tester.getSize(keys).width;
    await tester.drag(
        find.byKey(const ValueKey("animKeysGrip")), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(keys).width, lessThan(was - 100));
    await doubleTap();
    expect(tester.getSize(keys).width, closeTo(was, 1));
  });

  testWidgets("Inside it: an arrival plays the element's own", (tester) async {
    var (c, _) = await pump(tester);
    var id = c.newClip("a", kind: MotionKind.arrive);
    c.pickMotion("a", id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("animDevice-inside")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("animInside-own")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(id)!.inside["own"], isTrue);
    await tester.tap(find.byKey(const ValueKey("animInside-own")));
    await tester.pumpAndSettle();
    expect(c.motionOf("a").clip(id)!.inside, isEmpty,
        reason: "turned off, nothing left behind");
  });

  testWidgets("a move has nothing inside it for a shape", (tester) async {
    var (c, _) = await pump(tester);
    var id = c.newClip("a", preset: presetNamed("Shake"));
    c.pickMotion("a", id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("animDevice-inside")), findsNothing,
        reason: "a shake is a move: a shape has nothing more to do in it");
  });
}

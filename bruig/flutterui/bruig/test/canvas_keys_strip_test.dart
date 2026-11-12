import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show elementPhaseSpans;
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/ui/keys_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_keys_strip_test.dart is the Chain's Keys strip (Ken, 2026-11-12,
// the approved chain prototype), which took the Keyframes card's place: the
// element's own keyframes -- picked, moved keeping their spacing, refused
// where they would land on another, deleted, copied and pasted at the
// playhead -- and a row for each keyed setting of its chain, its keys
// coloured by where they play; and the controller's calls it makes.

ShapeElement logo() => ShapeElement(ElementBase(
    id: "logo",
    name: "Logo",
    width: 20,
    height: 20,
    track: ElementTrack(const [
      Keyframe(frame: 0),
      Keyframe(frame: 24, dx: 100),
      Keyframe(frame: 48, dx: 100, rotate: 90),
    ])));

CanvasController make() {
  var c = CanvasController(
      CanvasDocument(frames: 100, frameRate: 24, elements: [logo()]));
  c.selectOnly("logo");
  return c;
}

List<int> framesOf(CanvasController c) =>
    [for (var k in c.keyframeTarget!.track.keys) k.frame];

void main() {
  group("the controller", () {
    test("what the card edits: the picked element's own keyframes", () {
      var c = make();
      addTearDown(c.dispose);
      var t = c.keyframeTarget!;
      expect(t.name, "Logo");
      expect(t.points, isFalse);
      expect(framesOf(c), [0, 24, 48]);
      c.selectOnly("nothing");
      expect(c.keyframeTarget, isNull);
    });

    test("moves keep their spacing, and are refused onto another", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.moveTargetKeyframes([24, 48], 10), isTrue);
      expect(framesOf(c), [0, 34, 58]);
      expect(c.moveTargetKeyframes([34], -34), isFalse,
          reason: "onto the keyframe at 0");
      expect(c.moveTargetKeyframes([58], 60), isFalse, reason: "off the scene");
      expect(framesOf(c), [0, 34, 58], reason: "nothing moved");
    });

    test("the diamond adds one at the playhead holding the pose there", () {
      var c = make();
      addTearDown(c.dispose);
      c.frame = 12;
      c.toggleTargetKeyframe();
      expect(framesOf(c), [0, 12, 24, 48]);
      var k = c.keyframeTarget!.track.keyAt(12)!;
      expect(k.dx, greaterThan(0), reason: "on the way to 100");
      c.toggleTargetKeyframe();
      expect(framesOf(c), [0, 24, 48], reason: "and takes it away");
    });

    test("copied and pasted at the playhead, never over another", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.copyTargetKeys([24, 48]), 2);
      c.frame = 60;
      var (landed, why) = c.pasteTargetKeys();
      expect(why, isNull);
      expect(landed, [60, 84]);
      expect(c.keyframeTarget!.track.keyAt(84)!.rotate, 90);
      c.frame = 0;
      var (_, refused) = c.pasteTargetKeys();
      expect(refused, contains("already"));
      c.frame = 90;
      var (_, noRoom) = c.pasteTargetKeys();
      expect(noRoom, contains("not room"));
    });

    test("removed, and the track with the last", () {
      var c = make();
      addTearDown(c.dispose);
      c.removeTargetKeyframes([0, 24]);
      expect(framesOf(c), [48]);
      c.removeTargetKeyframes([48]);
      expect(c.document.elementById("logo")!.track, isNull,
          reason: "no empty track kept");
    });

    test("the loop: shown where the element loops, its ends moved", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.keyframeLoop, isNull, reason: "no loop yet");
      c.setElementLoop(
          c.selected!,
          const ElementLoop(
              preset: LoopPreset.float, cycle: 10, from: 10, to: 59));
      expect(c.keyframeLoop, (10, 59, 10, 0));
      c.moveKeyframeLoopEnd(true, 80);
      expect(c.keyframeLoop!.$2, 79, reason: "it stops before the frame");
      c.moveKeyframeLoopEnd(false, 30);
      expect(c.keyframeLoop!.$1, 30);
      c.moveKeyframeLoopEnd(false, 95);
      expect(c.keyframeLoop!.$1, 79, reason: "never past its stop");
    });

    test("eased from the picked keyframes", () {
      var c = make();
      addTearDown(c.dispose);
      c.easeTargetKeyframes([24], KeyframeEasing.easeOut);
      expect(c.keyframeTarget!.track.keyAt(24)!.easing, KeyframeEasing.easeOut);
    });
  });

  group("the strip", () {
    Future<CanvasController> show(WidgetTester tester,
        {CanvasController Function()? making}) async {
      var c = (making ?? make)();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1000, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1000,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => KeysStrip(
                      controller: c,
                      element: c.selected!,
                      height: KeysStrip.heightFor(
                          KeysStrip.rowsFor(c, c.selected!), 300)),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return c;
    }

    /// at is where frame [f] is drawn on row [row] (0 the keyframes).
    Offset at(WidgetTester tester, int f, {int row = 0}) {
      var r = tester.getRect(find.byKey(const ValueKey("keysLanes")));
      return Offset(r.left + 8 + f / 100 * (r.width - 16),
          r.top + KeysStrip.rulerHeight + (row + 1.5) * KeysStrip.rowHeight);
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      var g = await tester.startGesture(from);
      await tester.pump();
      await g.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await g.moveTo(to);
      await tester.pump();
      await g.up();
      await tester.pump();
    }

    testWidgets("a keyframe clicked: picked, and the playhead goes to it",
        (tester) async {
      var c = await show(tester);
      expect(find.byKey(const ValueKey("keysHint")), findsOneWidget);
      expect(find.byKey(const ValueKey("keysLabel-keyframes")), findsOneWidget);
      await tester.tapAt(at(tester, 24));
      await tester.pump();
      expect(c.frame, 24);
      expect(find.byKey(const ValueKey("keysPicked")), findsOneWidget);
      expect(find.byKey(const ValueKey("keysCurves")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("dragged, a keyframe is retimed, as one change",
        (tester) async {
      var c = await show(tester);
      await drag(tester, at(tester, 24), at(tester, 36));
      expect(framesOf(c), [0, 36, 48]);
      expect(c.canUndo, isTrue);
      c.undo();
      expect(framesOf(c), [0, 24, 48], reason: "one undo puts it back");
    });

    testWidgets("Delete takes the picked keyframe; double-click adds one",
        (tester) async {
      var c = await show(tester);
      await tester.tapAt(at(tester, 48));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(framesOf(c), [0, 24]);
      expect(c.document.elementById("logo"), isNotNull,
          reason: "the keyframe, not the element");
      expect(find.byKey(const ValueKey("keysSaid")), findsOneWidget);
      await tester.tapAt(at(tester, 70));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at(tester, 70));
      await tester.pump();
      expect(framesOf(c), [0, 24, 70]);
    });

    testWidgets("a path's points: dragged, a point is retimed", (tester) async {
      var c = await show(tester, making: () {
        var c = CanvasController(CanvasDocument(frames: 100, elements: [
          PathElement(const ElementBase(id: "p", width: 200, height: 200),
              nodes: const [
                PathNode(x: 0, y: 0, frame: 0),
                PathNode(x: 0.5, y: 0.5, frame: 30),
                PathNode(x: 1, y: 1, frame: 60),
              ]),
        ]));
        c.selectOnly("p");
        return c;
      });
      expect(c.keyframeTarget!.points, isTrue);
      expect(find.byKey(const ValueKey("keysLabel-keyframes")), findsOneWidget);
      await drag(tester, at(tester, 30), at(tester, 40));
      var path = c.document.elementById("p") as PathElement;
      expect([for (var n in path.nodes) n.frame], [0, 40, 60]);
      expect(find.byKey(const ValueKey("keysCurves")), findsNothing,
          reason: "a path's points have times only");
    });

    testWidgets(
        "the loop's stop dragged later, on the clips row, as one change",
        (tester) async {
      var c = await show(tester);
      c.setElementLoop(
          c.selected!,
          const ElementLoop(
              preset: LoopPreset.float, cycle: 10, from: 10, to: 59));
      await tester.pump();
      var undoBefore = c.canUndo;
      await drag(tester, at(tester, 60, row: -1), at(tester, 80, row: -1));
      expect(c.keyframeLoop!.$2, 79);
      c.undo();
      expect(c.keyframeLoop!.$2, 59, reason: "one undo puts it back");
      expect(undoBefore, isTrue);
    });

    testWidgets("shift picks several; Spread evenly evens them out",
        (tester) async {
      var c = await show(tester);
      c.frame = 30;
      c.toggleTargetKeyframe(); // 0, 24, 30, 48
      await tester.pump();
      await tester.tapAt(at(tester, 24));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tapAt(at(tester, 30));
      await tester.pump();
      await tester.tapAt(at(tester, 48));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      expect(find.text("3 keyframes"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("keysSpread")));
      await tester.pump();
      expect(framesOf(c), [0, 24, 36, 48]);
    });

    testWidgets("a keyed setting has a row; its key dragged, picked, deleted",
        (tester) async {
      var c = await show(tester, making: () {
        var c = make();
        c.setMotionDevices("logo", [
          const MotionDevice(MotionDeviceKind.glow, id: "m0")
              .withKey("strength", 0.5, 0.2)
              .withKey("strength", 1.5, 0.8),
        ]);
        return c;
      });
      expect(
          find.byKey(const ValueKey("keysLabel-m0-strength")), findsOneWidget);
      // 0.5 s is frame 12 of 100 at 24 a second.
      await drag(tester, at(tester, 12, row: 1), at(tester, 24, row: 1));
      var d = c.motionDevicesOf("logo").single;
      expect(d.keys["strength"]!.first.t, closeTo(1, 1e-9));
      expect(find.byKey(const ValueKey("keysInspector-key")), findsOneWidget);
      expect(find.text("Glow · Strength · Independent"), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      d = c.motionDevicesOf("logo").single;
      expect(d.keys["strength"], hasLength(1));
    });

    testWidgets("a key in the arrival is drawn in it, and filtered",
        (tester) async {
      var c = await show(tester, making: () {
        var c = make();
        c.applyElementAnimation(c.selected!, ElementAnimationPreset.fadeIn);
        var spans = elementPhaseSpans(c.selected!, c.document);
        c.setMotionDevices("logo", [
          const MotionDevice(MotionDeviceKind.glow, id: "m0")
              .withPlaying(MotionPhase.arrive, true)
              .withKey("radius", 0, 4, spans: spans),
        ]);
        return c;
      });
      var d = c.motionDevicesOf("logo").single;
      expect(d.keyedIn("radius", MotionPhase.arrive), isTrue,
          reason: "keyed in the clip playing there");
      expect(find.byKey(const ValueKey("keysLabel-m0-radius")), findsOneWidget);
      c.chainPhase = MotionPhase.leave;
      addTearDown(() => c.chainPhase = null);
      await tester.pump();
      expect(find.byKey(const ValueKey("keysLabel-m0-radius")), findsNothing,
          reason: "only what plays in the leaving");
      expect(find.byKey(const ValueKey("keysLabel-keyframes")), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // Ken, 2026-11-12: a short Chain with Keys open squeezed the cards below
  // their headers -- a red screen. The cards keep their room, or the strip
  // shows alone.
  group("Keys open in a short Chain", () {
    for (var clip in [false, true]) {
      for (var scale in [1.0, 1.5]) {
        for (var height in [120.0, 170.0, 240.0, 260.0, 320.0, 480.0]) {
          testWidgets("clip $clip, text $scale, $height tall", (tester) async {
            var c = make();
            addTearDown(c.dispose);
            c.setMotionDevices("logo", const [
              MotionDevice(MotionDeviceKind.wiggle, id: "m0"),
              MotionDevice(MotionDeviceKind.glow, id: "m1"),
            ]);
            if (clip) {
              c.applyElementAnimation(
                  c.selected!, ElementAnimationPreset.fadeIn);
            }
            c.keysShown = true;
            addTearDown(() => c.keysShown = false);
            tester.view.physicalSize = Size(1600, height + 40);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeNotifier>(
                    create: (c) => ThemeNotifier(doLoad: false)),
                ChangeNotifierProvider<SnackBarModel>(
                    create: (c) => SnackBarModel()),
              ],
              child: MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(1600, height + 40),
                      textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      body: Align(
                          alignment: Alignment.topLeft,
                          child:
                              AnimationPanel(controller: c, height: height))),
                ),
              ),
            ));
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.byKey(const ValueKey("keysStrip")), findsOneWidget);
            if (height >= 240) {
              // Along the row to its end: every card laid out at this height.
              var row = find
                  .byWidgetPredicate((w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.right)
                  .first;
              var position = tester.state<ScrollableState>(row).position;
              for (var i = 0; i < 4; i++) {
                position.jumpTo(position.maxScrollExtent);
                await tester.pump();
              }
              expect(tester.takeException(), isNull);
              expect(find.byKey(const ValueKey("motionOutputCard")),
                  findsOneWidget,
                  reason: "room for the cards under the strip");
            }
          });
        }
      }
    }
  });

  testWidgets("it opens small, and its bottom edge drags it taller",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.keysShown = true;
    addTearDown(() {
      c.keysShown = false;
      c.keysHeight = null;
    });
    tester.view.physicalSize = const Size(1600, 540);
    tester.view.devicePixelRatio = 1.0;
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
                  alignment: Alignment.topLeft,
                  child: AnimationPanel(controller: c, height: 500)))),
    ));
    await tester.pump();
    double strip() =>
        tester.getSize(find.byKey(const ValueKey("keysStrip"))).height;
    expect(strip(), lessThanOrEqualTo(KeysStrip.startHeight));
    var was = strip();
    await tester.drag(
        find.byKey(const ValueKey("keysGrip")), const Offset(0, 80));
    await tester.pump();
    expect(strip(), greaterThan(was + 40));
    await tester.drag(
        find.byKey(const ValueKey("keysGrip")), const Offset(0, 900));
    await tester.pump();
    expect(strip(), 500 - AnimationPanel.cardsLeast,
        reason: "the cards keep their room");
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets("in a short Chain, its grip still drags (Ken's log)",
      (tester) async {
    // Tall enough for the strip and the cards, too short for the strip's
    // least height besides: the grip clamped from 100 to less, and threw.
    var height = AnimationPanel.cardsLeast +
        KeysStrip.rulerHeight +
        2 * KeysStrip.rowHeight +
        2;
    expect(height, lessThan(AnimationPanel.cardsLeast + KeysStrip.leastHeight),
        reason: "the height the clamp crossed at");
    var c = make();
    addTearDown(c.dispose);
    c.keysShown = true;
    addTearDown(() {
      c.keysShown = false;
      c.keysHeight = null;
    });
    tester.view.physicalSize = const Size(1600, 540);
    tester.view.devicePixelRatio = 1.0;
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
                  alignment: Alignment.topLeft,
                  child: AnimationPanel(controller: c, height: height)))),
    ));
    await tester.pump();
    for (var by in [20.0, -20.0, 200.0]) {
      await tester.drag(find.byKey(const ValueKey("keysGrip")), Offset(0, by));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: "dragged $by");
    }
    expect(c.keysHeight, lessThanOrEqualTo(height - AnimationPanel.cardsLeast),
        reason: "the cards keep their room");
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets("+ Row keys a setting at the playhead: a row for it",
      (tester) async {
    var c = make();
    addTearDown(c.dispose);
    c.setMotionDevices("logo", const [
      MotionDevice(MotionDeviceKind.glow, id: "m0"),
    ]);
    c.keysShown = true;
    addTearDown(() => c.keysShown = false);
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1.0;
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
                  alignment: Alignment.topLeft,
                  child: AnimationPanel(controller: c, height: 560)))),
    ));
    await tester.pump();
    c.frame = 24;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("keysAddRow")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("keysAdd-m0-radius")));
    await tester.pumpAndSettle();
    var d = c.motionDevicesOf("logo").single;
    expect(d.keyAt("radius", 1), isTrue);
    expect(find.byKey(const ValueKey("keysLabel-m0-radius")), findsOneWidget);
    // Design, made by its first key.
    await tester.ensureVisible(find.byKey(const ValueKey("keysAddRow")));
    await tester.tap(find.byKey(const ValueKey("keysAddRow")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("keysAdd-design-x")));
    await tester.pumpAndSettle();
    expect(c.designOf("logo")!.keyed("x"), isTrue);
    expect(tester.takeException(), isNull);
  });
}

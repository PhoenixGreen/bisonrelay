import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/keyframes_card.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_keyframes_card_test.dart is the Chain's Keyframes card (Ken,
// 2026-11-09: keyframing in the Chain; the approved keyframes prototype):
// what the timeline's keyframe row did -- the marks of what is picked,
// picked, moved keeping their spacing, refused where they would land on
// another, deleted, copied and pasted at the playhead, the diamond at the
// playhead -- and the controller's calls it makes.

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

    test("eased from the picked keyframes", () {
      var c = make();
      addTearDown(c.dispose);
      c.easeTargetKeyframes([24], KeyframeEasing.easeOut);
      expect(c.keyframeTarget!.track.keyAt(24)!.easing, KeyframeEasing.easeOut);
    });
  });

  group("the card", () {
    Future<CanvasController> show(WidgetTester tester) async {
      var c = make();
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
              child: ListenableBuilder(
                listenable: c,
                builder: (context, _) => KeyframesCard(
                    controller: c, height: 300, folded: false, onFold: () {}),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return c;
    }

    /// markAt is where frame [f]'s mark is drawn.
    Offset markAt(WidgetTester tester, int f) {
      var r =
          tester.getRect(find.byKey(const ValueKey("keyframesLanes-paint")));
      return Offset(r.left + 70 + f / 99 * (r.width - 76), r.top + 16 + 14);
    }

    testWidgets("a mark clicked: picked, and the playhead goes to it",
        (tester) async {
      var c = await show(tester);
      expect(find.byKey(const ValueKey("keyframesHint")), findsOneWidget);
      await tester.tapAt(markAt(tester, 24));
      await tester.pump();
      expect(c.frame, 24);
      expect(find.byKey(const ValueKey("keyframesFrame")), findsOneWidget);
      expect(find.text("Across"), findsWidgets, reason: "what it holds");
      expect(tester.takeException(), isNull);
    });

    testWidgets("dragged, a mark retimes its keyframe", (tester) async {
      var c = await show(tester);
      var from = markAt(tester, 24);
      var to = markAt(tester, 36);
      var g = await tester.startGesture(from);
      await tester.pump();
      await g.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await g.moveTo(to);
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(framesOf(c), [0, 36, 48]);
      expect(c.canUndo, isTrue, reason: "one step to undo");
    });

    testWidgets("Delete takes the picked keyframes; the diamond adds one",
        (tester) async {
      var c = await show(tester);
      await tester.tapAt(markAt(tester, 48));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(framesOf(c), [0, 24]);
      expect(find.byKey(const ValueKey("keyframesSaid")), findsOneWidget);
      c.frame = 60;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("keyframesHere")));
      await tester.pump();
      expect(framesOf(c), [0, 24, 60]);
    });

    testWidgets("a box picks several; Spread evenly evens them out",
        (tester) async {
      var c = await show(tester);
      c.frame = 30;
      c.toggleTargetKeyframe(); // 0, 24, 30, 48
      await tester.pump();
      // From past the last keyframe, back: where no band is.
      var a = markAt(tester, 70);
      var b = markAt(tester, 10);
      var g = await tester.startGesture(a);
      await tester.pump();
      await g.moveTo(Offset.lerp(a, b, 0.5)!);
      await tester.pump();
      await g.moveTo(b);
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(find.byKey(const ValueKey("keyframesPicked")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("keyframesSpread")));
      await tester.pump();
      expect(framesOf(c), [0, 24, 36, 48]);
    });
  });
}

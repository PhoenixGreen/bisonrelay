import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/track_marks.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/chain_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/keys_strip.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/track_curves.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_keys_copy_test.dart is working with an element's own keys (Ken,
// 2026-11-25): copied with ⌘C and pasted with ⌘V on another element (scene
// 11's "New block" and "New block, approved" want the same moves) -- the
// paste heard wherever the keyboard is once the other element is clicked;
// a keyed path dragged on the canvas whole, its location keys picked; the
// Keys strip on its own, without the Chain's cards; and the inspectors of
// the strip and the Curves shut for room.

ShapeElement block(String id, {ElementTrack? track}) => ShapeElement(
    ElementBase(id: id, name: id, width: 40, height: 40, track: track));

final _moves = ElementTrack(const [
  Keyframe(frame: 0),
  Keyframe(frame: 24, dx: 100),
  Keyframe(frame: 48, dx: 100, dy: 50),
]);

CanvasController make() {
  var c = CanvasController(
      CanvasDocument(frames: 100, frameRate: 24, elements: [
        block("new", track: _moves),
        block("approved"),
        block("third"),
      ]),
      audioEngine: FakeEngine({}));
  c.selectOnly("new");
  return c;
}

ElementTrack trackOf(CanvasController c, String id) =>
    c.document.elementById(id)!.track!;

void main() {
  group("copied to another element", () {
    test("⌘V anywhere lays the keys copied on what is picked", () {
      var c = make();
      addTearDown(c.dispose);
      var all = trackOf(c, "new").allMarks;
      expect(c.copyTargetMarks(all), all.length);
      c.selectOnly("approved");
      c.frame = 0;
      expect(c.pastesKeys, isTrue);
      // The page's paste, as ⌘V on the canvas runs it.
      c.paste();
      var t = trackOf(c, "approved");
      expect([for (var k in t.keys) k.frame], [0, 24, 48]);
      for (var f in [12, 24, 36, 48]) {
        expect(t.at(f).dx, trackOf(c, "new").at(f).dx);
        expect(t.at(f).dy, trackOf(c, "new").at(f).dy);
      }
      expect(c.document.elements, hasLength(3), reason: "no element pasted");
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.document.elementById("approved")!.track, isNull,
          reason: "one undo takes the paste back");
    });

    test("with several picked, each has them", () {
      var c = make();
      addTearDown(c.dispose);
      c.copyTargetMarks(trackOf(c, "new").allMarks);
      c.selectMany({"approved", "third"});
      c.frame = 10;
      c.paste();
      expect(trackOf(c, "approved").keyAt(34)!.dx, 100);
      expect(trackOf(c, "third").keyAt(58)!.dy, 50);
    });

    test("elements copied after keys: a paste lays the elements", () {
      var c = make();
      addTearDown(c.dispose);
      c.copyTargetMarks(trackOf(c, "new").allMarks);
      c.selectOnly("third");
      c.copySelected();
      expect(c.pastesKeys, isFalse);
      c.paste();
      expect(c.document.elements, hasLength(4));
    });
  });

  group("a keyed path dragged whole", () {
    test("its location keys picked, a drag moves them all", () {
      var c = make();
      addTearDown(c.dispose);
      c.frame = 24;
      c.pickedMarks = trackOf(c, "new").allMarks;
      var e = c.document.elementById("new")!;
      var before = trackOf(c, "new");
      // Drawn at (100, 0) from its rest at (0, 0) on frame 24: put at
      // (130, 20), every key goes 30 across and 20 down.
      var moved = c.movedTo(e, const Offset(130, 20));
      var t = moved.track!;
      expect([for (var k in t.keys) k.frame], [0, 24, 48]);
      for (var f in [0, 24, 48]) {
        expect(t.keyAt(f)!.dx, before.keyAt(f)!.dx + 30);
        expect(t.keyAt(f)!.dy, before.keyAt(f)!.dy + 20);
      }
    });

    test("none picked, a drag keys the location where the playhead is", () {
      var c = make();
      addTearDown(c.dispose);
      c.frame = 12;
      var moved =
          c.movedTo(c.document.elementById("new")!, const Offset(10, 10));
      var t = moved.track!;
      expect([for (var k in t.keys) k.frame], [0, 12, 24, 48]);
      expect(t.keyAt(12)!.pins, KeyProp.location.bit);
      expect(t.at(12).dx, 10);
    });

    test("picks belong to the element picked: another has none", () {
      var c = make();
      addTearDown(c.dispose);
      c.pickedMarks = trackOf(c, "new").allMarks;
      expect(c.pickedLocationFrames("new"), [0, 24, 48]);
      c.selectOnly("approved");
      expect(c.pickedMarks, isEmpty);
      expect(c.pickedLocationFrames("new"), isNull);
    });
  });

  group("the strip's keyboard", () {
    Future<CanvasController> strip(WidgetTester tester) async {
      var c = make();
      addTearDown(c.dispose);
      setTestScreen(tester, const Size(1000, 400));
      await tester.pumpWidget(canvasApp(Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 1000,
              child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => c.selected == null
                      ? const SizedBox()
                      : KeysStrip(
                          key: ValueKey("strip-${c.selected!.id}"),
                          controller: c,
                          element: c.selected!,
                          height: 300))))));
      await tester.pump();
      return c;
    }

    Offset keyAt(WidgetTester tester, int f) {
      var r = tester.getRect(find.byKey(const ValueKey("keysLanes")));
      return Offset(
          r.left + 8 + f / 100 * (r.width - 16),
          r.top +
              KeysStrip.rulerHeight +
              KeysStrip.clipsHeight +
              0.5 * KeysStrip.rowHeight);
    }

    testWidgets("⌘A picks them all; ⌘C, another element, ⌘V", (tester) async {
      var c = await strip(tester);
      await tester.tapAt(keyAt(tester, 24));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(c.pickedMarks, hasLength(3));
      expect(find.textContaining("3 keys copied"), findsOneWidget);
      // The other element, picked: its own strip, and the keys pasted.
      c.selectOnly("approved");
      c.frame = 0;
      await tester.pump();
      await tester.tapAt(keyAt(tester, 90));
      await tester.pump();
      c.frame = 0;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(trackOf(c, "approved").marksOn("location"), [0, 24, 48]);
      expect(c.pickedMarks, hasLength(3), reason: "what landed, picked");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a row a property, each named", (tester) async {
      await strip(tester);
      expect(find.text("Location"), findsOneWidget);
      expect(find.text("Keyframes"), findsNothing);
    });
  });

  group("room to work", () {
    Future<CanvasController> chain(WidgetTester tester) async {
      var c = make();
      addTearDown(c.dispose);
      addTearDown(() {
        c.keysOnly = false;
        c.keysShown = false;
        c.keyInspectorShut = false;
      });
      c.showChain(motion: true);
      setTestScreen(tester, const Size(1400, 600));
      await tester.pumpWidget(canvasApp(Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 1400,
              height: 420,
              child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => ChainPanel(
                      controller: c, height: 400, onResize: (_) {}))))));
      await tester.pump(const Duration(milliseconds: 300));
      return c;
    }

    testWidgets("Keys: the strip alone, filling the Chain", (tester) async {
      var c = await chain(tester);
      expect(find.byType(KeysStrip), findsNothing);
      await tester.tap(find.byKey(const ValueKey("chainTabKeys")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.keysOnly, isTrue);
      expect(find.byType(KeysStrip), findsOneWidget);
      expect(find.byKey(const ValueKey("chainKeys")), findsNothing,
          reason: "Keys above is the Chain tab's");
      var strip = tester.getSize(find.byKey(const ValueKey("keysStrip")));
      expect(strip.height, greaterThan(300), reason: "the whole Chain");
      // The Chain tab: the cards again.
      await tester.tap(find.byKey(const ValueKey("chainTabMotionChain")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.keysOnly, isFalse);
      expect(find.byType(KeysStrip), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the inspector shut to its edge, in the strip and Curves",
        (tester) async {
      var c = await chain(tester);
      await tester.tap(find.byKey(const ValueKey("chainTabKeys")));
      await tester.pump(const Duration(milliseconds: 300));
      var lanes = tester.getSize(find.byKey(const ValueKey("keysLanes")));
      expect(find.byKey(const ValueKey("keysInspector-none")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("keysInspectorFold")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.keyInspectorShut, isTrue);
      expect(find.byKey(const ValueKey("keysInspector-none")), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey("keysLanes"))).width,
          greaterThan(lanes.width + 200),
          reason: "the keys have its room");
      // The Curves shut the same way, and open again from their edge.
      c.showTrackCurves(frame: 24);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TrackCurves), findsOneWidget);
      expect(find.byKey(const ValueKey("trackCurvesKeyName")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("trackCurvesInspectorFold")));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.keyInspectorShut, isFalse);
      expect(find.byKey(const ValueKey("trackCurvesKeyName")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

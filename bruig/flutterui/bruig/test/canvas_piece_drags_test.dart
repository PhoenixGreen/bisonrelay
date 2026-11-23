import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

import 'support/canvas_app.dart';

// canvas_piece_drags_test.dart is a text element's picture piece taken by
// its own box on the stage, as the person doing it sees it: moved from
// inside the box, sized by a corner, turned by the ring. Each is held as
// let go (the piece changed, the text did not, and it is one undo step), as
// cancelled by the system (what it did is kept and the step closed), and as
// a still press (nothing changes and no step is made). The pointer's look
// while each is under way is held too.

const _viewport = Size(1280, 800);

const _text = TextElement(
  ElementBase(id: "t", x: 200, y: 200, width: 800, height: 400),
  text: "Words",
  box: BoxSpec(padding: 20),
  items: [
    TextItem(
        id: "pic",
        slot: TextSlot.topRight,
        icon: TextIcon(assetId: "asset1", size: 100)),
  ],
);

void main() {
  /// pump shows the text on a stage with its picture picked, and hands back
  /// the controller and the stage's state.
  Future<(CanvasController, CanvasStageState)> pump(WidgetTester tester) async {
    var c = CanvasController(const CanvasDocument().addElement(_text));
    addTearDown(c.dispose);
    c.selectOnly("t");
    c.pickTextLayer("t", "pic");
    var key = GlobalKey<CanvasStageState>();
    setTestScreen(tester, _viewport);
    await tester.pumpWidget(canvasApp(SizedBox(
        width: _viewport.width,
        height: _viewport.height,
        child: CanvasStage(key: key, controller: c))));
    await tester.pumpAndSettle();
    return (c, key.currentState!);
  }

  /// cursor is the pointer's look over the stage's page.
  MouseCursor cursor(WidgetTester tester) => tester
      .widgetList<MouseRegion>(find.descendant(
          of: find.byType(CanvasStage), matching: find.byType(MouseRegion)))
      .firstWhere((m) => m.child is ClipRect)
      .cursor;

  /// drag presses at [from] and takes the pointer [by] on the stage, in two
  /// steps, then lets go there or, with [cancel], has the system take it.
  /// [during] is called with the pointer still down, after the last step.
  Future<void> drag(WidgetTester tester, Offset from, Offset by,
      {bool cancel = false, void Function()? during}) async {
    var g = await tester.startGesture(from,
        buttons: kPrimaryButton, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    await g.moveBy(by / 2);
    await tester.pump();
    during?.call();
    if (cancel) {
      await g.cancel();
    } else {
      await g.up();
    }
    await tester.pumpAndSettle();
  }

  /// settled is that nothing of the last press is left: no gesture under
  /// way and no undo step open.
  void settled(CanvasStageState stage, CanvasController c, String how) {
    expect(stage.gestureUnderWay, isFalse, reason: "$how: no gesture left");
    expect(c.interacting, isFalse, reason: "$how: no undo step left open");
  }

  TextElement text(CanvasController c) =>
      c.document.elementById("t") as TextElement;
  TextItem pic(CanvasController c) => text(c).items.single;
  Rect picture(CanvasController c) =>
      textItemRects(text(c), text(c).bounds).single;
  double scaleOf(CanvasStageState s, CanvasController c) =>
      s.pageRect.width / c.document.size.width;

  /// kinds is each of the three: its name, where its press lands, the
  /// pointer's travel from there, and what the drag did to the piece, given
  /// how far its middle moved on the page.
  final kinds = <(
    String,
    Offset Function(CanvasStageState, CanvasController),
    Offset Function(CanvasStageState, CanvasController),
    void Function(TextItem was, TextItem now, Offset moved),
  )>[
    (
      "moved from inside",
      (s, c) => s.toStagePoint(picture(c).center),
      (s, c) => const Offset(-60, 40) * scaleOf(s, c),
      (was, now, moved) {
        expect(moved, offsetMoreOrLessEquals(const Offset(-60, 40), epsilon: 1),
            reason: "moved with the pointer");
        expect(now.icon!.size, was.icon!.size);
        expect(now.icon!.turn, was.icon!.turn);
      },
    ),
    (
      "sized by a corner",
      (s, c) => s.handleAt(StageHandle.bottomRight),
      // Pulled to twice as far from its middle: twice the size.
      (s, c) => const Offset(50, 50) * scaleOf(s, c),
      (was, now, moved) {
        expect(now.icon!.size, closeTo(200, 2), reason: "twice the size");
        expect(now.icon!.turn, was.icon!.turn);
      },
    ),
    (
      "turned by the ring",
      (s, c) => s.handleAt(StageHandle.rotate),
      // From above its middle round to its right: a quarter turn.
      (s, c) {
        var mid = s.toStagePoint(picture(c).center);
        var ring = s.handleAt(StageHandle.rotate);
        return mid + Offset((ring - mid).distance, 0) - ring;
      },
      (was, now, moved) {
        expect(now.icon!.turn, closeTo(90, 1), reason: "a quarter turn");
        expect(now.icon!.size, was.icon!.size);
        expect(now.side, was.side);
        expect(now.down, was.down);
      },
    ),
  ];

  for (var (name, at, by, changed) in kinds) {
    group("a picture piece $name", () {
      for (var cancel in [false, true]) {
        var how = cancel ? "cancelled" : "let go";
        testWidgets("$how: the piece changes, not the text, one step",
            (tester) async {
          var (c, s) = await pump(tester);
          var was = pic(c), from = picture(c).center;
          await drag(tester, at(s, c), by(s, c), cancel: cancel, during: () {
            expect(s.gestureUnderWay, isTrue, reason: "a gesture under way");
            expect(c.interacting, isTrue, reason: "an undo step open");
            expect(cursor(tester), SystemMouseCursors.basic);
          });
          changed(was, pic(c), picture(c).center - from);
          expect(text(c).bounds, _text.bounds, reason: "the text stays put");
          expect(text(c).rotation, 0, reason: "the text is not turned");
          expect(c.textLayer(text(c))?.id, "pic", reason: "still picked");
          settled(s, c, how);
          c.undo();
          expect(pic(c), was, reason: "one undo puts it back");
          expect(c.canUndo, isFalse, reason: "and it was one step");
        });
      }

      testWidgets("pressed and let go still: nothing changes, no step",
          (tester) async {
        var (c, s) = await pump(tester);
        var was = pic(c);
        await drag(tester, at(s, c), Offset.zero, during: () {
          expect(s.gestureUnderWay, isTrue, reason: "a gesture under way");
        });
        expect(pic(c), was);
        expect(c.textLayer(text(c))?.id, "pic", reason: "still picked");
        settled(s, c, "clicked");
        expect(c.canUndo, isFalse);
        await drag(tester, at(s, c), Offset.zero, cancel: true);
        expect(pic(c), was);
        settled(s, c, "cancelled");
        expect(c.canUndo, isFalse);
      });
    });
  }
  group("on a frame where the text's keys have taken it from rest", () {
    // The piece is laid out in the text's own box and drawn wherever the
    // keys have put the text; the size kept its middle by the box at rest.
    // Sized there, the picture must stay where it is drawn on this frame.
    // A narrow text holds its picture to the width of its box at rest, the
    // width it is laid out at whatever size its keys draw it.
    var narrow = _text.copyWith(items: [
      _text.items.single
          .copyWith(icon: _text.items.single.icon!.copyWith(size: 200))
    ]).withBase(width: 300) as TextElement;
    for (var (name, start, pose) in [
      ("moved", _text, const Keyframe(frame: 20, dx: -150, dy: 120)),
      (
        "moved and grown",
        _text,
        const Keyframe(frame: 20, dx: -150, dy: 120, scale: 1.5)
      ),
      (
        "grown, past its box's width",
        narrow,
        const Keyframe(frame: 20, dx: 100, scale: 1.5)
      ),
    ]) {
      testWidgets("$name: the picture keeps its middle", (tester) async {
        var keyed = start.withBase(
            track: ElementTrack([const Keyframe(frame: 0), pose]));
        var c = CanvasController(
            const CanvasDocument(frames: 24).addElement(keyed));
        addTearDown(c.dispose);
        c.frame = 20;
        c.selectOnly("t");
        c.pickTextLayer("t", "pic");
        var key = GlobalKey<CanvasStageState>();
        setTestScreen(tester, _viewport);
        await tester.pumpWidget(canvasApp(SizedBox(
            width: _viewport.width,
            height: _viewport.height,
            child: CanvasStage(key: key, controller: c))));
        await tester.pumpAndSettle();
        var s = key.currentState!;

        // Where the picture is drawn on this frame: laid out in the box at
        // rest, then moved and grown about the text's middle as its pose is.
        Offset drawn() {
          var e = text(c);
          var at = textItemRects(e, e.bounds).single.center;
          var middle = e.bounds.center;
          return middle + (at - middle) * pose.scale + Offset(pose.dx, pose.dy);
        }

        var before = drawn();
        await drag(tester, s.handleAt(StageHandle.bottomRight),
            const Offset(50, 50) * scaleOf(s, c));
        expect(pic(c).icon!.size, greaterThan(start.items.single.icon!.size),
            reason: "it was sized");
        expect(drawn(), offsetMoreOrLessEquals(before, epsilon: 1));
      });
    }
  });
}

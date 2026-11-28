import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';

import 'support/canvas_app.dart';

// canvas_box_drags_on_page_test.dart is the selection box's handles taken on
// a frame where the element is drawn away from where it rests: turned by its
// keys about a corner, sized by them, squashed, spun or swung by its loop,
// moved by a clip, and one copy of several. Each drag goes through the real
// stage and is read back by where the painter lays the element out after
// it: a resize keeps the side or corner opposite the one pulled where it is
// drawn and puts the one pulled under the pointer; a turn sweeps what is
// drawn about its anchor as drawn; a slant leans the side held, the other
// kept; the anchor goes under the pointer and what is drawn stays. An
// element at rest, turned or slanted as it rests, is the same check, which
// it has always met. Each drag is one undo step that puts the document back.

const _page = 300;
const _orange = Color(0xFFFFA726);

/// _midway is the frame each is dragged on: half-way through its keys and
/// its clip, and a quarter of the way round a loop of four seconds.
const _midway = 12;

/// _near is how close, in document units, what is drawn must come to where
/// it should be.
const _near = 0.5;

CanvasDocument _pageOf(List<CanvasElement> elements) => CanvasDocument(
    size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
    elements: elements,
    frames: 48,
    frameRate: 12,
    guides: const CanvasGuides(snap: false));

/// _keyed is [base] with a key at rest on frame 0 and [to] on frame 24.
ElementBase _keyed(ElementBase base, Keyframe to) => base.copyWith(
    track: ElementTrack([const Keyframe(frame: 0), to.copyWith(frame: 24)]));

/// _clip carries an element [x] across and [y] down in two seconds.
ElementMotion _clip(double x, double y) => ElementMotion(clips: [
      MotionClip(id: "go", kind: MotionKind.action, length: 2, keys: {
        MotionProp.x: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(x))
        ],
        MotionProp.y: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(y))
        ],
      }),
    ], placed: const [
      ClipPlacement(id: "p", clip: "go", length: 2)
    ]);

const _none = ElementLoop();
const _spin = ElementLoop(preset: LoopPreset.spin, cycle: 48);
const _swing = ElementLoop(preset: LoopPreset.swing, cycle: 48, strength: 3);

/// _Motion is one way a rectangle is laid out on [_midway], and whether it
/// is one an element has always been dragged right in (a control).
typedef _Motion = (String, ElementBase, ElementLoop, bool);

List<_Motion> _motions() {
  const box = ElementBase(id: "e", x: 100, y: 110, width: 100, height: 80);
  const corner = ElementBase(
      id: "e", x: 100, y: 110, width: 100, height: 80, anchorX: 0, anchorY: 0);
  return [
    ("at rest", box, _none, true),
    ("turned as it rests", box.copyWith(rotation: 30), _none, true),
    ("slanted as it rests", box.copyWith(skewX: 25), _none, true),
    (
      "turned by its keys about an anchor at its corner",
      _keyed(corner, const Keyframe(frame: 0, rotate: 70)),
      _none,
      false
    ),
    (
      "turned as it rests and sized by its keys about an anchor at its corner",
      _keyed(
          corner.copyWith(rotation: 30), const Keyframe(frame: 0, scale: 1.6)),
      _none,
      false
    ),
    (
      "slanted as it rests and turned by its keys",
      _keyed(box.copyWith(skewX: 25), const Keyframe(frame: 0, rotate: 50)),
      _none,
      false
    ),
    (
      "squashed by its keys",
      _keyed(
          box,
          const Keyframe(frame: 0, values: {
            KeyframeChannel.squash: 1.8,
            KeyframeChannel.squashAngle: 0,
          })),
      _none,
      false
    ),
    ("spun by its loop", box, _spin, false),
    ("swung from its top by its loop", box, _swing, false),
    ("moved by a clip", box.copyWith(motion: _clip(60, 30)), _none, false),
  ];
}

ShapeElement _shape(ElementBase base, ElementLoop loop) =>
    ShapeElement(base, fill: _orange, animation: ElementAnimation(loop: loop));

/// _Stage is a controller on a real stage, and the way between the page and
/// the stage's points.
class _Stage {
  final CanvasController c;
  final CanvasStageState stage;
  _Stage(this.c, this.stage);

  double get scale => stage.pageRect.width / _page;
  Offset toScreen(Offset doc) => stage.toStagePoint(doc);
  Offset toDoc(Offset screen) =>
      (screen - stage.toStagePoint(Offset.zero)) / scale;
}

Future<_Stage> _open(WidgetTester tester, CanvasElement e,
    {String? copy, bool slants = false, bool anchor = false}) async {
  var c = CanvasController(_pageOf([e]));
  addTearDown(c.dispose);
  c.frame = _midway;
  c.selectOnly("e");
  if (copy != null) c.pickCopy("e", copy);
  if (slants) c.skewHandles = true;
  if (anchor) c.showAnchor("e", true);
  var key = GlobalKey<CanvasStageState>();
  const viewport = Size(800, 600);
  setTestScreen(tester, viewport);
  await tester.pumpWidget(canvasApp(SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: CanvasStage(key: key, controller: c))));
  await tester.pumpAndSettle();
  return _Stage(c, key.currentState!);
}

/// _drag presses at [from] on the page and takes the pointer [by], in
/// document units, in two steps, with Shift held where [shift] says.
Future<void> _drag(WidgetTester tester, _Stage s, Offset from, Offset by,
    {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  var g = await tester.startGesture(s.toScreen(from));
  await tester.pump();
  await g.moveBy(by * s.scale / 2);
  await tester.pump();
  await g.moveBy(by * s.scale / 2);
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

/// _on is the element, or its copy [instance], as the painter lays it out
/// on [_midway] now.
ElementOnPage _on(_Stage s, {int? instance}) =>
    placeOnPage(s.c.document.elementById("e")!, _midway, s.c.document, null,
        instance: instance);

/// _at is the point [f] of the way across and down [on]'s box, where it is
/// drawn.
Offset _at(ElementOnPage on, Offset f) => on.place.place(Offset(
    on.box.left + on.box.width * f.dx, on.box.top + on.box.height * f.dy));

/// _fromLine is how far [p] is from the line through [a] and [b].
double _fromLine(Offset p, Offset a, Offset b) {
  var d = b - a;
  if (d.distance < 1e-9) return (p - a).distance;
  return ((p - a).dx * d.dy - (p - a).dy * d.dx).abs() / d.distance;
}

/// _undone undoes the drag once and expects the document as it was.
void _undone(_Stage s, CanvasElement was) {
  s.c.undo();
  expect(s.c.document.elementById("e"), was, reason: "one undo puts it back");
  expect(s.c.canUndo, isFalse, reason: "and it was one step");
}

String _n(double v) => v.toStringAsFixed(1);

void main() {
  group("a handle taken on a frame where the element moves", () {
    for (var (motion, base, loop, _) in _motions()) {
      var e = _shape(base, loop);

      // A corner or a side pulled, and how the proportions are held: let
      // go, held with Shift, or held by the element.
      for (var (handle, pulled, held, side) in [
        (
          StageHandle.bottomRight,
          const Offset(1, 1),
          const Offset(0, 0),
          false
        ),
        (
          StageHandle.centerRight,
          const Offset(1, 0.5),
          const Offset(0, 0.5),
          true
        ),
      ]) {
        for (var (how, shift, locked) in [
          ("let go", false, false),
          ("held with Shift", true, false),
          ("held by the element", false, true),
        ]) {
          var keeps = shift || locked;
          var what = side ? "a side" : "a corner";
          testWidgets(
              "$motion, $what pulled with its proportions $how: the other "
              "side stays where it is drawn and the pulled one goes under "
              "the pointer", (tester) async {
            var start = locked ? e.withBase(lockAspect: true) : e;
            var s = await _open(tester, start);
            var before = _on(s);
            // Held proportions hold the top left of a side pulled.
            var keep = side && keeps ? const Offset(0, 0) : held;
            var heldWas = _at(before, keep);
            var from = _at(before, pulled);
            expect((s.toDoc(s.stage.handleAt(handle)) - from).distance,
                lessThan(_near),
                reason: "the handle is where it is drawn");
            // Out along the box as it is drawn, and a little down it, so a
            // corner pulled must follow both ways.
            var by = _at(before, pulled + const Offset(0.2, 0.1)) - from;
            if (side) by = _at(before, pulled + const Offset(0.2, 0)) - from;
            var pointer = from + by;
            await _drag(tester, s, from, by, shift: shift);

            var after = _on(s);
            expect(after.box.width, greaterThan(before.box.width + 5),
                reason: "it was resized");
            var drift = (_at(after, keep) - heldWas).distance;
            double off;
            if (side) {
              // The pulled side, a line, passes under the pointer.
              off = _fromLine(pointer, _at(after, const Offset(1, 0)),
                  _at(after, const Offset(1, 1)));
            } else if (keeps) {
              // Held in proportion, the corner stays on its diagonal.
              off = _fromLine(_at(after, pulled), heldWas, from);
            } else {
              off = (_at(after, pulled) - pointer).distance;
            }
            expect(math.max(drift, off), lessThan(_near),
                reason: "the held side drifts ${_n(drift)}, the pulled one "
                    "is ${_n(off)} off the pointer");
            expect(s.c.document.elementById("e")!.base.track, start.base.track,
                reason: "a resize sizes the element, not its pose");
            _undone(s, start);
          });
        }
      }

      testWidgets(
          "$motion, turned: what is drawn turns about its anchor as drawn by "
          "the angle swept", (tester) async {
        var s = await _open(tester, e);
        var before = _on(s);
        var anchor = Offset(e.base.anchorX, e.base.anchorY);
        var pivot = _at(before, anchor);
        var knob = s.toDoc(s.stage.handleAt(StageHandle.rotate));
        // The point of the element under the knob, in its box.
        var held = before.place.unplace(knob) - before.box.topLeft;
        // A quarter of the way round, about where it is drawn turning.
        var arm = knob - pivot;
        var by = Offset(-arm.dy, arm.dx) * 0.3;
        var pointer = knob + by;
        await _drag(tester, s, knob, by);

        var after = _on(s);
        expect(s.c.document.elementById("e")!.rotation, isNot(e.rotation),
            reason: "it was turned");
        var drift = (_at(after, anchor) - pivot).distance;
        var swept = after.place.place(after.box.topLeft + held);
        var off = _fromLine(swept, pivot, pointer);
        var ahead = (swept - pivot).dx * (pointer - pivot).dx +
            (swept - pivot).dy * (pointer - pivot).dy;
        expect(ahead, greaterThan(0), reason: "on the pointer's side");
        expect(math.max(drift, off), lessThan(_near),
            reason: "the anchor drifts ${_n(drift)}, the point pressed is "
                "${_n(off)} off the line to the pointer");
        _undone(s, e);
      });

      testWidgets(
          "$motion, slanted by its top handle: the bottom stays where it is "
          "drawn and the top goes with the pointer", (tester) async {
        var s = await _open(tester, e, slants: true);
        var before = _on(s);
        var bottom = _at(before, const Offset(0.5, 1));
        var top = _at(before, const Offset(0.5, 0));
        // Along a way a slant can take the top: a slant shears the element
        // along its own across, or down, as it rests, after what its keys
        // and its loop do, so the top travels along one line on the page for
        // each; the one that takes it further.
        Offset travel(double moreX, double moreY) {
          var b = before.drawn.base;
          double deg(double was, double more) =>
              math.atan(math.tan(was * math.pi / 180) + more) * 180 / math.pi;
          var slanted = before.drawn
              .withBase(skewX: deg(b.skewX, moreX), skewY: deg(b.skewY, moreY))
              .placedIn(before.box, before.pose);
          Offset span(ElementPlace p) =>
              p.place(before.box.topCenter) - p.place(before.box.bottomCenter);
          return span(slanted) - span(before.place);
        }

        var x = travel(1, 0), y = travel(0, 1);
        var lean = x.distance >= y.distance ? x : y;
        var by = lean / lean.distance * 16;
        var pointer = top + by;
        var handle = s.toDoc(s.stage.handleAt(StageHandle.topCenter));
        expect((handle - top).distance, lessThan(_near),
            reason: "the handle is on the top as drawn");
        await _drag(tester, s, top, by);

        var after = _on(s);
        var now = s.c.document.elementById("e")!;
        expect(now.base.skewX != e.base.skewX || now.base.skewY != e.base.skewY,
            isTrue,
            reason: "it was slanted");
        var drift = (_at(after, const Offset(0.5, 1)) - bottom).distance;
        var off = (_at(after, const Offset(0.5, 0)) - pointer).distance;
        expect(math.max(drift, off), lessThan(_near),
            reason: "the bottom drifts ${_n(drift)}, the top is ${_n(off)} "
                "off the pointer");
        _undone(s, e);
      });

      testWidgets(
          "$motion, its anchor dragged: the mark is where it is drawn, goes "
          "under the pointer, and what is drawn stays", (tester) async {
        var s = await _open(tester, e, anchor: true);
        var before = _on(s);
        var anchor = Offset(e.base.anchorX, e.base.anchorY);
        var mark = _at(before, anchor);
        var shown = s.stage.anchorMarks.single;
        var markOff = (shown - mark).distance;
        const by = Offset(14, 9);
        await _drag(tester, s, mark, by);

        var after = _on(s);
        var now = s.c.document.elementById("e")!;
        var off = (_at(after, Offset(now.base.anchorX, now.base.anchorY)) -
                (mark + by))
            .distance;
        var moved = 0.0;
        for (var f in const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(1, 1),
          Offset(0, 1)
        ]) {
          moved = math.max(moved, (_at(after, f) - _at(before, f)).distance);
        }
        expect(math.max(markOff, math.max(off, moved)), lessThan(_near),
            reason: "the mark is ${_n(markOff)} off the anchor as drawn, the "
                "anchor ${_n(off)} off the pointer, and what is drawn moved "
                "${_n(moved)}");
        _undone(s, e);
      });
    }
  });

  group("one copy of several, turned, taken by its own box", () {
    // Turned as it rests about an anchor at its corner, and the copy picked
    // turned by its own Turn too: a copy is sized and turned about its
    // anchor by its own Size and Turn.
    var e = ShapeElement(
        const ElementBase(
            id: "e",
            x: 30,
            y: 110,
            width: 60,
            height: 50,
            rotation: 20,
            anchorX: 0,
            anchorY: 0,
            motion: ElementMotion(
                instances: InstanceSet(items: [
              ElementInstance("a"),
              ElementInstance("b", dx: 130, own: {"turn": 40}),
              ElementInstance("c", dx: 60, dy: 100),
            ]))),
        fill: _orange);

    testWidgets(
        "a corner pulled sizes it about its anchor as drawn, the corner "
        "under the pointer", (tester) async {
      var s = await _open(tester, e, copy: "b");
      var before = _on(s, instance: 1);
      var pivot = _at(before, Offset.zero);
      var corner = _at(before, const Offset(1, 1));
      expect(
          (s.toDoc(s.stage.handleAt(StageHandle.bottomRight)) - corner)
              .distance,
          lessThan(_near),
          reason: "the handle is on the copy's corner as drawn");
      // Out along the line from its anchor, which a copy's one Size follows.
      var by = (corner - pivot) * 0.2;
      await _drag(tester, s, corner, by);

      var after = _on(s, instance: 1);
      var drift = (_at(after, Offset.zero) - pivot).distance;
      var off = (_at(after, const Offset(1, 1)) - (corner + by)).distance;
      expect(math.max(drift, off), lessThan(_near),
          reason: "the anchor drifts ${_n(drift)}, the corner is ${_n(off)} "
              "off the pointer");
      _undone(s, e);
    });

    testWidgets("turned, it turns about its anchor as drawn", (tester) async {
      var s = await _open(tester, e, copy: "b");
      var before = _on(s, instance: 1);
      var pivot = _at(before, Offset.zero);
      var knob = s.toDoc(s.stage.handleAt(StageHandle.rotate));
      var held = before.place.unplace(knob) - before.box.topLeft;
      var arm = knob - pivot;
      var by = Offset(-arm.dy, arm.dx) * 0.3;
      var pointer = knob + by;
      await _drag(tester, s, knob, by);

      var after = _on(s, instance: 1);
      var drift = (_at(after, Offset.zero) - pivot).distance;
      var swept = after.place.place(after.box.topLeft + held);
      var off = _fromLine(swept, pivot, pointer);
      expect(math.max(drift, off), lessThan(_near),
          reason: "the anchor drifts ${_n(drift)}, the point pressed is "
              "${_n(off)} off the line to the pointer");
      _undone(s, e);
    });
  });
}

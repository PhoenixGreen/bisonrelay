import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stroke.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

import 'support/canvas_app.dart';

// canvas_stroke_on_page_test.dart is a line's and a path's curve where it
// is drawn: through the element's turn and slant, as paintElement lays it
// out. Whatever asks where the curve is (the selection box, the press, text
// set on it, something following it) is held to the ink on the page.

const _page = 240;
const _orange = Color(0xFFFFA726);

/// _Ink is a page as drawn, to ask which pixels are inked.
class _Ink {
  final Uint8List rgba;
  _Ink(this.rgba);

  bool at(int x, int y) {
    if (x < 0 || y < 0 || x >= _page || y >= _page) return false;
    var i = (y * _page + x) * 4;
    var d = 0;
    for (var c = 0; c < 3; c++) {
      d += (rgba[i + c] - rgba[c]).abs();
    }
    return d > 90;
  }

  /// near is whether any pixel within [radius] of [p] is inked.
  bool near(Offset p, double radius) {
    var r = radius.ceil();
    for (var y = p.dy.floor() - r; y <= p.dy.floor() + r; y++) {
      for (var x = p.dx.floor() - r; x <= p.dx.floor() + r; x++) {
        if (!at(x, y)) continue;
        if ((Offset(x + 0.5, y + 0.5) - p).distance <= radius) return true;
      }
    }
    return false;
  }

  /// pixels is the centre of every inked pixel.
  List<Offset> get pixels => [
        for (var y = 0; y < _page; y++)
          for (var x = 0; x < _page; x++)
            if (at(x, y)) Offset(x + 0.5, y + 0.5),
      ];
}

CanvasDocument _pageOf(List<CanvasElement> elements) => CanvasDocument(
    size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
    elements: elements,
    frames: 48);

Future<_Ink> _draw(CanvasElement e) async {
  var recorder = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(recorder), _pageOf([e]));
  var image = await recorder.endRecording().toImage(_page, _page);
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _Ink(data!.buffer.asUint8List());
}

/// _along is the points a share of the way along [points], by index, from
/// a tenth to nine tenths: clear of the ends, where a cap or a cut-back
/// leaves the curve's own end bare.
List<Offset> _along(List<Offset> points) => [
      for (var k = 1; k <= 9; k++)
        () {
          var at = (points.length - 1) * k / 10;
          var i = at.floor();
          var j = math.min(i + 1, points.length - 1);
          return Offset.lerp(points[i], points[j], at - i)!;
        }(),
    ];

LineElement _line(ElementBase base, {double curvature = 0}) =>
    LineElement(base, color: _orange, strokeWidth: 6, curvature: curvature);

PathElement _path(ElementBase base) => PathElement(base,
    nodes: PathElement.defaultNodes(),
    color: _orange,
    strokeWidth: 6,
    endEnd: LineEnd.none);

/// _strokes are a line and a path laid out every way a frame lays them:
/// slanted each way, turned and slanted, and a bowed line slanted.
List<(String, StrokedElement)> _strokes() {
  const box = ElementBase(id: "e", x: 70, y: 80, width: 100, height: 80);
  return [
    ("a line slanted across", _line(box.copyWith(skewX: 35))),
    ("a line slanted down", _line(box.copyWith(skewY: 30))),
    ("a line turned and slanted", _line(box.copyWith(rotation: 30, skewX: 30))),
    ("a bowed line slanted", _line(box.copyWith(skewX: 35), curvature: 0.3)),
    ("a path slanted across", _path(box.copyWith(skewX: 35))),
    ("a path turned and slanted", _path(box.copyWith(rotation: 50, skewY: 25))),
  ];
}

/// _midway is the frame the moving strokes are drawn on: half-way through
/// their keys and their clip.
const _midway = 12;

Future<_Ink> _drawAt(CanvasDocument doc, int frame) async {
  var recorder = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(recorder), doc, frame: frame);
  var image = await recorder.endRecording().toImage(_page, _page);
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return _Ink(data!.buffer.asUint8List());
}

/// _keyed is [base] with a key at rest on frame 0 and [to] on frame 24.
ElementBase _keyed(ElementBase base, Keyframe to) => base.copyWith(
    track: ElementTrack([const Keyframe(frame: 0), to.copyWith(frame: 24)]));

/// _clipMoved is [base] carried 80 across and 40 down over a clip of two
/// seconds, which at 12 frames a second is half done on [_midway].
ElementBase _clipMoved(ElementBase base) => base.copyWith(
        motion: const ElementMotion(clips: [
      MotionClip(id: "go", kind: MotionKind.action, length: 2, keys: {
        MotionProp.x: [
          MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(80))
        ],
        MotionProp.y: [
          MotionKey(0, MotionNumber(0)),
          MotionKey(2, MotionNumber(40))
        ],
      }),
    ], placed: [
      ClipPlacement(id: "p", clip: "go", length: 2)
    ]));

/// _moving is a line and a path each moved every way motion moves an
/// element: a keyed move, size and turn, a turn about an anchor off its
/// middle, a clip, and a keyed turn on a slanted one; and a line bowed and
/// moved by its keys together. Each on a page of its own at 12 frames a
/// second.
List<(String, CanvasDocument)> _moving() {
  const box = ElementBase(id: "e", x: 60, y: 70, width: 100, height: 80);
  CanvasDocument page(CanvasElement e) => CanvasDocument(
      size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
      elements: [e],
      frames: 48,
      frameRate: 12);
  var out = <(String, CanvasDocument)>[];
  for (var (kind, make) in <(String, StrokedElement Function(ElementBase))>[
    ("a line", (b) => _line(b)),
    ("a path", (b) => _path(b)),
  ]) {
    out.addAll([
      (
        "$kind moved by its keys",
        page(make(_keyed(box, const Keyframe(frame: 0, dx: 60, dy: 40))))
      ),
      (
        "$kind sized by its keys",
        page(make(_keyed(box, const Keyframe(frame: 0, scale: 1.6))))
      ),
      (
        "$kind turned by its keys",
        page(make(_keyed(box, const Keyframe(frame: 0, rotate: 70))))
      ),
      (
        "$kind turned by its keys about an anchor at its corner",
        page(make(_keyed(box.copyWith(anchorX: 0, anchorY: 0),
            const Keyframe(frame: 0, rotate: 70))))
      ),
      ("$kind moved by a clip", page(make(_clipMoved(box)))),
      (
        "$kind slanted and turned by its keys",
        page(make(_keyed(
            box.copyWith(skewX: 25), const Keyframe(frame: 0, rotate: 50))))
      ),
    ]);
  }
  out.add((
    "a line bowed and moved by its keys",
    page(_line(_keyed(
        box,
        const Keyframe(
            frame: 0, dx: 50, dy: 30, values: {KeyframeChannel.bow: 0.5}))))
  ));
  return out;
}

void main() {
  group("an element's place on a frame is where the painter lays it out", () {
    // Every step a frame's place takes, alone and together, about an anchor
    // off the middle: the canvas the painter lays out (ElementPlace.applyTo)
    // takes each point of the box where ElementPlace.place says, and
    // unplace brings it back.
    const box = ElementBase(
        id: "e", x: 40, y: 60, width: 120, height: 70, anchorX: 0.2);
    var poses = <(String, ElementBase, Keyframe)>[
      ("at rest", box, Keyframe.rest),
      (
        "turned and slanted",
        box.copyWith(rotation: 30, skewX: 20),
        Keyframe.rest
      ),
      ("moved", box, const Keyframe(frame: 0, dx: 25, dy: -10)),
      (
        "turned and sized",
        box,
        const Keyframe(frame: 0, rotate: 35, scale: 1.4)
      ),
      (
        "squashed",
        box,
        const Keyframe(frame: 0, values: {
          KeyframeChannel.squash: 1.3,
          KeyframeChannel.squashAngle: 0.6,
        })
      ),
      (
        "swung by a loop",
        box.copyWith(anchorX: 0.5),
        const Keyframe(frame: 0, values: {
          KeyframeChannel.loopTurn: 12,
          KeyframeChannel.loopSx: 1.1,
          KeyframeChannel.loopSy: 0.9,
          KeyframeChannel.loopPivotX: 0.5,
          KeyframeChannel.loopPivotY: 0,
        })
      ),
      (
        "all at once",
        box.copyWith(rotation: -20, skewY: 15),
        const Keyframe(
            frame: 0,
            dx: 9,
            dy: 14,
            rotate: -50,
            scale: 0.7,
            values: {
              KeyframeChannel.squash: 0.8,
              KeyframeChannel.squashAngle: -1.1,
              KeyframeChannel.loopTurn: -8,
              KeyframeChannel.loopSx: 1.2,
            })
      ),
    ];
    for (var (name, base, pose) in poses) {
      test(name, () {
        var e = _line(base);
        var place = e.placedBy(pose);
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        place.applyTo(canvas);
        var m = canvas.getTransform();
        recorder.endRecording().dispose();
        for (var p in [
          e.bounds.topLeft,
          e.bounds.bottomRight,
          e.bounds.center,
          const Offset(-30, 500),
        ]) {
          var painted = Offset(m[0] * p.dx + m[4] * p.dy + m[12],
              m[1] * p.dx + m[5] * p.dy + m[13]);
          var placed = place.place(p);
          expect((painted - placed).distance, lessThan(1e-3),
              reason: "$p: painted at $painted, placed at $placed");
          expect((place.unplace(placed) - p).distance, lessThan(1e-6));
        }
      });

      // An outline laid out by the place (placePath) lands where the canvas
      // the painter lays out draws it, and a box laid on the page
      // (boxOnPage) has its corners there too.
      test("$name: an outline and a box", () {
        var e = _line(base);
        var place = e.placedBy(pose);
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        place.applyTo(canvas);
        var m = canvas.getTransform();
        recorder.endRecording().dispose();
        Offset painted(Offset p) => Offset(m[0] * p.dx + m[4] * p.dy + m[12],
            m[1] * p.dx + m[5] * p.dy + m[13]);
        var corners = [
          e.bounds.topLeft,
          e.bounds.topRight,
          const Offset(-30, 500),
        ];
        for (var (i, p) in corners.indexed) {
          // A path of one point each, so its bounds are that point.
          var dot = Path()
            ..moveTo(p.dx, p.dy)
            ..lineTo(p.dx, p.dy);
          var at = place.placePath(dot).getBounds().topLeft;
          expect((at - painted(p)).distance, lessThan(1e-3),
              reason: "corner $i: drawn at ${painted(p)}, laid at $at");
        }
        var cell = Rect.fromLTWH(e.bounds.left + 10, e.bounds.top + 5, 50, 30);
        for (var turn in [0.0, 25.0]) {
          var (box, frame) = place.boxOnPage(cell, turn: turn);
          var turned = BoxFrame(turn, 0, 0).corners(cell);
          var laid = frame.corners(box);
          for (var p in turned) {
            var want = painted(p);
            expect(laid.any((q) => (q - want).distance < 1e-3), isTrue,
                reason: "turned $turn: $want is a corner of $laid");
          }
        }
      });

      // The place as one matrix, which lays a widget over the element where
      // it is drawn (the text editor, a cell's), takes each point of the box
      // where place does.
      test("$name: one matrix", () {
        var e = _line(base);
        var place = e.placedBy(pose);
        for (var p in [
          e.bounds.topLeft,
          e.bounds.bottomRight,
          e.bounds.center,
          const Offset(-30, 500),
        ]) {
          var mapped = MatrixUtils.transformPoint(place.matrix, p);
          expect((mapped - place.place(p)).distance, lessThan(1e-6),
              reason: "$p: by the matrix $mapped, placed ${place.place(p)}");
        }
      });
    }
  });

  group("a line's and a path's curve is where it is drawn", () {
    for (var (name, e) in _strokes()) {
      testWidgets("$name: along its ink", (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _draw(e));
        for (var p in _along(curveOfElement(e)!)) {
          expect(ink.near(p, 1.5), isTrue, reason: "$p is on the line");
        }
      });

      testWidgets("$name: its selection box holds all of it", (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _draw(e));
        var box = visualBoundsOf(e, _pageOf([e]), 0);
        for (var p in ink.pixels) {
          expect(box.contains(p), isTrue, reason: "$p is inside $box");
        }
      });

      testWidgets("$name: pressed where it is drawn, and only there",
          (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _draw(e));
        var hits = StageHitTest(document: _pageOf([e]), frame: 0, scale: 1);
        for (var p in ink.pixels) {
          expect(hits.contains(e, p), isTrue, reason: "$p is inked");
        }
        // Nothing pressed further from the ink than the press reaches.
        var reach = e.strokeWidth / 2 + strokeHitSlop + 1.5;
        for (var y = 2.0; y < _page; y += 4) {
          for (var x = 2.0; x < _page; x += 4) {
            var p = Offset(x, y);
            if (!hits.contains(e, p)) continue;
            expect(ink.near(p, reach), isTrue, reason: "$p is near no ink");
          }
        }
      });
    }
  });

  group("a stroke's ends are pressed where they are drawn", () {
    // Every end at each end, large, on a line and a path, upright and
    // turned and slanted: each inked pixel is pressed, and nothing further
    // from the ink than the press reaches but the inside of a hollow end.
    const box = ElementBase(id: "e", x: 50, y: 70, width: 140, height: 100);
    for (var end in LineEnd.values) {
      for (var (name, e) in <(String, StrokedElement)>[
        ("a line", _line(box)),
        ("a path", _path(box)),
        (
          "a turned and slanted path",
          _path(box.copyWith(rotation: 30, skewX: 20))
        ),
      ]) {
        var ended = e.withStroke(
            e.stroke.copyWith(startEnd: end, endEnd: end, endSize: 2.5));
        testWidgets("${end.name} on $name", (tester) async {
          late _Ink ink;
          await tester.runAsync(() async => ink = await _draw(ended));
          var hits =
              StageHitTest(document: _pageOf([ended]), frame: 0, scale: 1);
          for (var p in ink.pixels) {
            expect(hits.contains(ended, p), isTrue, reason: "$p is inked");
          }
          var reach = ended.strokeWidth / 2 + strokeHitSlop + 1.5;
          // A hollow end is pressed inside, as a shape with no fill is.
          var curve = curveOfElement(ended)!;
          bool inHollow(Offset p) =>
              end.name.startsWith("hollow") &&
              [curve.first, curve.last].any((tip) =>
                  (p - tip).distance <= ended.strokeWidth * 2.5 * end.reach);
          for (var y = 2.0; y < _page; y += 4) {
            for (var x = 2.0; x < _page; x += 4) {
              var p = Offset(x, y);
              if (!hits.contains(ended, p) || inHollow(p)) continue;
              expect(ink.near(p, reach), isTrue, reason: "$p is near no ink");
            }
          }
        });
      }
    }
  });

  testWidgets("text set on a slanted line rides it as it is drawn",
      (tester) async {
    var line = _line(const ElementBase(
        id: "line", x: 70, y: 80, width: 100, height: 80, skewX: 35));
    var text = TextElement(const ElementBase(id: "t", width: 100, height: 20),
        text: "Along", curve: const TextOnCurve(elementId: "line"));
    late _Ink ink;
    await tester.runAsync(() async => ink = await _draw(line));
    var under = curveUnderText(text, _pageOf([line, text]), 0)!;
    for (var p in _along(under)) {
      expect(ink.near(p, 1.5), isTrue, reason: "$p is on the line");
    }
  });

  group("something following a path by the Follow path device", () {
    // A shape 20 square at the page's corner, sent along the path in
    // a second: at the end of it, its middle is on the path's end as drawn.
    Offset arrived(StrokedElement path) {
      var doc = _pageOf([
        ShapeElement(ElementBase(
            id: "a",
            width: 20,
            height: 20,
            motion: const ElementMotion(devices: [
              MotionDevice(MotionDeviceKind.followPath,
                  target: "e", values: {"lap": 1, "loop": 1})
            ]))),
        path,
      ]);
      var a = doc.elementById("a")!;
      return a.boundsWith(poseWithMotion(a, doc.frameRate, doc)).center;
    }

    for (var (name, e) in _strokes()) {
      if (e is! PathElement) continue;
      testWidgets("$name: arrives at its end as drawn", (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _draw(e));
        var end = arrived(e);
        expect(ink.near(end, 2), isTrue, reason: "$end is on the path");
        // Its last point, laid out as paintElement lays out the canvas.
        var last = e.pointOf(e.nodes.last);
        expect(
            (end - e.boxFrame.place(last, e.center)).distance, lessThan(0.01));
      });
    }

    test("a turned path is ridden turned", () {
      var turned = _path(const ElementBase(
          id: "e", x: 70, y: 80, width: 100, height: 80, rotation: 90));
      var end = turned.onPage(turned.pointOf(turned.nodes.last));
      expect((arrived(turned) - end).distance, lessThan(0.01));
    });
  });

  group("a line's and a path's curve under motion is where it is drawn", () {
    // Each drawn on a frame part-way through its motion.
    for (var (name, doc) in _moving()) {
      var e = doc.elementById("e")!;
      testWidgets("$name: along its ink", (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _drawAt(doc, _midway));
        var curve = curveOfElement(e, _midway, doc)!;
        for (var p in _along(curve)) {
          expect(ink.near(p, 1.5), isTrue, reason: "$p is on the line");
        }
      });

      testWidgets("$name: its selection box holds all of it", (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _drawAt(doc, _midway));
        var box = visualBoundsOf(e, doc, _midway);
        for (var p in ink.pixels) {
          expect(box.contains(p), isTrue, reason: "$p is inside $box");
        }
      });

      testWidgets("$name: pressed where it is drawn, and only there",
          (tester) async {
        late _Ink ink;
        await tester.runAsync(() async => ink = await _drawAt(doc, _midway));
        var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
        for (var p in ink.pixels) {
          expect(hits.contains(e, p), isTrue, reason: "$p is inked");
        }
        var reach =
            (e as StrokedElement).strokeWidth * 1.5 / 2 + strokeHitSlop + 1.5;
        for (var y = 2.0; y < _page; y += 4) {
          for (var x = 2.0; x < _page; x += 4) {
            var p = Offset(x, y);
            if (!hits.contains(e, p)) continue;
            expect(ink.near(p, reach), isTrue, reason: "$p is near no ink");
          }
        }
      });
    }
  });

  group("what rides a stroke rides it where it is drawn on the frame", () {
    const box = ElementBase(id: "e", x: 60, y: 70, width: 100, height: 80);
    CanvasDocument page(List<CanvasElement> elements) => CanvasDocument(
        size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
        elements: elements,
        frames: 48,
        frameRate: 12);

    testWidgets("text set on a line its keys move and turn", (tester) async {
      var line = _line(
          _keyed(box, const Keyframe(frame: 0, dx: 60, dy: 40, rotate: 40)));
      var text = TextElement(const ElementBase(id: "t", width: 100, height: 20),
          text: "Along", curve: const TextOnCurve(elementId: "e"));
      late _Ink ink;
      await tester.runAsync(() async => ink = await _drawAt(page([line]), 12));
      var under = curveUnderText(text, page([line, text]), 12)!;
      for (var p in _along(under)) {
        expect(ink.near(p, 1.5), isTrue, reason: "$p is on the line");
      }
    });

    testWidgets("a follower of a path its keys move", (tester) async {
      // Sent along it in a second, which is frame 12: there its middle is on
      // the path's end as the path is drawn then.
      var path = _path(_keyed(box, const Keyframe(frame: 0, dx: 60, dy: 40)));
      var doc = page([
        ShapeElement(ElementBase(
            id: "a",
            width: 20,
            height: 20,
            motion: const ElementMotion(devices: [
              MotionDevice(MotionDeviceKind.followPath,
                  target: "e", values: {"lap": 1, "loop": 1})
            ]))),
        path,
      ]);
      late _Ink ink;
      await tester.runAsync(() async => ink = await _drawAt(page([path]), 12));
      var a = doc.elementById("a")!;
      var end = a.boundsWith(poseWithMotion(a, 12, doc)).center;
      expect(ink.near(end, 2), isTrue, reason: "$end is on the path");
      // Half-way through its keys, the path is drawn 30 across and 20 down.
      var resting = curveOfElement(path)!.last;
      expect((end - (resting + const Offset(30, 20))).distance, lessThan(0.01),
          reason: "at the end of the path as it is drawn");
    });
  });

  group("a stroke posed by what rides it is not asked about for ever", () {
    CanvasDocument page(List<CanvasElement> elements) =>
        CanvasDocument(elements: elements, frames: 48, frameRate: 12);
    MotionDevice follow(String target) =>
        MotionDevice(MotionDeviceKind.followPath,
            target: target, values: const {"lap": 1});
    const box = ElementBase(id: "p", x: 60, y: 70, width: 100, height: 80);

    test("two paths each following the other", () {
      var doc = page([
        _path(box.copyWith(motion: ElementMotion(devices: [follow("q")]))),
        _path(box.copyWith(
            id: "q", x: 300, motion: ElementMotion(devices: [follow("p")]))),
      ]);
      expect(curveOfElement(doc.elementById("p"), 6, doc), isNotNull);
      expect(visualBoundsOf(doc.elementById("q")!, doc, 6).isFinite, isTrue);
    });

    test("a path following itself", () {
      var doc = page([
        _path(box.copyWith(motion: ElementMotion(devices: [follow("p")]))),
      ]);
      expect(curveOfElement(doc.elementById("p"), 6, doc), isNotNull);
    });

    test("a line turned to look at the text set on it", () {
      var doc = page([
        _line(box.copyWith(
            id: "l",
            motion: const ElementMotion(devices: [
              MotionDevice(MotionDeviceKind.lookAt, target: "t"),
            ]))),
        TextElement(
            const ElementBase(
                id: "t",
                width: 100,
                height: 20,
                motion: ElementMotion(devices: [
                  MotionDevice(MotionDeviceKind.followPath,
                      target: "l", values: {"lap": 1}),
                ])),
            text: "Along",
            curve: const TextOnCurve(elementId: "l")),
      ]);
      var text = doc.elementById("t")! as TextElement;
      expect(curveUnderText(text, doc, 6), isNotNull);
      expect(visualBoundsOf(text, doc, 6).isFinite, isTrue);
    });
  });

  test("a keyed bow is part of where a line is", () {
    var line = _line(
        const ElementBase(id: "e", x: 70, y: 80, width: 100, height: 80)
            .copyWith(
                track: ElementTrack(const [
      Keyframe(frame: 0, values: {KeyframeChannel.bow: 0.4}),
    ])));
    var resting = curveOfElement(line)!;
    var keyed = curveOfElement(line, 0)!;
    expect(resting.length, 2, reason: "as it rests, straight");
    expect(keyed.length, greaterThan(2), reason: "bowed on the frame");
  });

  group("a turned or slanted line or path selected on the stage", () {
    const viewport = Size(800, 600);

    Future<(CanvasController, CanvasStageState)> onStage(
        WidgetTester tester, StrokedElement e) async {
      var controller = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(controller.dispose);
      controller.selectOnly(e.id);
      var key = GlobalKey<CanvasStageState>();
      setTestScreen(tester, viewport);
      await tester.pumpWidget(canvasApp(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: controller))));
      await tester.pumpAndSettle();
      return (controller, key.currentState!);
    }

    const box = ElementBase(id: "e", x: 400, y: 300, width: 300, height: 200);
    for (var (name, e) in <(String, StrokedElement)>[
      ("a turned line", _line(box.copyWith(rotation: 35))),
      ("a slanted line", _line(box.copyWith(skewX: 30))),
      ("a turned path", _path(box.copyWith(rotation: 35))),
      ("a slanted path", _path(box.copyWith(skewY: 25))),
    ]) {
      testWidgets("$name: its corner handle is on the box round it as drawn",
          (tester) async {
        var (c, stage) = await onStage(tester, e);
        // The corner furthest from any point of a path, which a press
        // there would take instead.
        var seen = visualBoundsOf(e, c.document, 0);
        var grips = [
          if (e is PathElement)
            for (var n in e.nodes)
              for (var g in PathGrip.values) e.gripOnPage(n, g),
        ];
        double clear(Offset p) => grips.isEmpty
            ? 0
            : grips.map((g) => (g - p).distance).reduce(math.min);
        var corner = [
          seen.topLeft,
          seen.topRight,
          seen.bottomLeft,
          seen.bottomRight
        ].reduce((a, b) => clear(a) >= clear(b) ? a : b);
        var out = corner - seen.center;
        out = out / out.distance;
        var drag = await tester.startGesture(stage.toStagePoint(corner));
        await drag.moveTo(stage.toStagePoint(corner + out * 20));
        await drag.moveTo(stage.toStagePoint(corner + out * 60));
        await drag.up();
        await tester.pumpAndSettle();
        var now = c.document.elementById("e")!;
        expect(now.width, greaterThan(e.width), reason: "resized, wider");
        expect(now.height, greaterThan(e.height), reason: "and taller");
      });
    }
  });
}

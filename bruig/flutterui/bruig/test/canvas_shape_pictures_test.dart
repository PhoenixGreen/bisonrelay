import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_wrap.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

import 'support/kept_pictures.dart';

// canvas_shape_pictures_test.dart keeps what the renderer draws of a shape,
// a line and a path, to the byte, in each of several hundred states: every
// kind of shape in a square box and an oblong one, with each way of filling
// and outlining it; a star at several depths and point counts; corners;
// a label set in each kind's own room and in padding; a turned and a
// slanted shape; every speech bubble body with every tail at many angles,
// lengths and widths; a line with every end at each end, at three sizes, on
// a thin and a thick stroke, with each cap, dashed, bowed, faded, flipped,
// level, upright and turned; a path open and closed, straight and curved,
// with every end, each cap, dashed, faded, turned, slanted and as a guide;
// and each with its outline run round by a loop, which is the only way to
// see the outline a loop follows. Beside each picture it keeps the numbers
// the stage and the words ask of the same element: where it is drawn
// (visualBoundsOf), what the stage's press counts as on it, what words
// wrapped beside it go round, and for a line or a path where its ends are
// and how long it is. It is the proof that a change meant only to move or
// merge how these are drawn draws and measures exactly what it did before.
//
// To use it, set SHAPE_PICTURES to a folder and run this file on the code
// as it is: each state's picture (<state>.rgba and .png) and numbers
// (<state>.txt) are written there. Run it again to see that every one is
// stable from run to run. Then make the change and run it after each step:
// a state whose picture differs fails, saying how many pixels changed and
// where, and leaves the new picture beside the kept one as <state>.new.png;
// numbers that differ fail with both. Without SHAPE_PICTURES each state is
// still drawn and measured, and nothing is kept, so the test is harmless in
// the whole suite.
//
// Every kind, end, cap, body and tail is taken from its enum's values, so a
// new one gets its states without anyone remembering to add them.

const _blue = Color(0xFF3D7EFF);
const _orange = Color(0xFFFFA726);
const _red = Color(0xFFE53935);
const _green = Color(0xFF66BB6A);
const _paper = Color(0xFFEEEEEE);
const _clear = Color(0x00000000);

/// _State is one thing kept: a page drawn on frame 0, [editing] where it
/// is drawn as the editor draws it rather than as it is published.
typedef _State = ({String name, CanvasDocument doc, bool editing});

_State _state(String name, CanvasDocument doc, {bool editing = false}) =>
    (name: name, doc: doc, editing: editing);

/// _page is a page [w] by [h] holding [elements].
CanvasDocument _page(int w, int h, List<CanvasElement> elements) =>
    CanvasDocument(
        size:
            CanvasSize(width: w, ratio: CanvasRatio.custom, customRatio: w / h),
        elements: elements,
        frames: 48);

ElementBase _at(Rect r, {String id = "e"}) =>
    ElementBase(id: id, x: r.left, y: r.top, width: r.width, height: r.height);

/// _loop is an outline run round with marching ants, drawn from frame 0.
const _loop = ElementAnimation(
    loop: ElementLoop(
        preset: LoopPreset.marchingAnts, colour: PaintSpec(Color(0xFFFFEB3B))));

String _short(double v) =>
    v == v.roundToDouble() ? "${v.round()}" : "$v".replaceAll(".", "_");

String _signed(double v) => v < 0 ? "minus-${_short(-v)}" : _short(v);

// Shapes, on a page 240 by 160.

const _shapeW = 240, _shapeH = 160;
const _square = Rect.fromLTWH(65, 25, 110, 110);
const _oblong = Rect.fromLTWH(20, 30, 200, 100);
const _boxes = [("square", _square), ("oblong", _oblong)];

/// _looks are the ways a shape is filled and outlined, one per state.
List<(String, ShapeElement Function(ShapeElement))> _looks() => [
      ("filled", (e) => e),
      (
        "outlined",
        (e) => e.copyWith(strokeWidth: 8, strokeColor: _orange),
      ),
      (
        "outline-only",
        (e) => e.copyWith(fill: _clear, strokeWidth: 6, strokeColor: _orange),
      ),
      (
        "fill-faded",
        (e) => e.copyWith(fillFade: const GradientSpec(to: _red, angle: 90)),
      ),
      (
        "outline-faded",
        (e) => e.copyWith(
            fill: _clear,
            strokeWidth: 8,
            strokeColor: _orange,
            strokeFade: const GradientSpec(to: _green, angle: 0)),
      ),
      (
        "painted",
        (e) => e.copyWith(
            painted: const TextFill(
                kind: TextFillKind.pattern,
                pattern: ProceduralSpec(
                    style: ProceduralStyle.lineGrid,
                    background: Color(0xFF1E4A7A),
                    foreground: Color(0xFFFFFFFF)))),
      ),
    ];

ShapeElement _shape(ShapeKind kind, Rect box) =>
    ShapeElement(_at(box), shape: kind, fill: _blue);

CanvasDocument _shapePage(ShapeElement e) => _page(_shapeW, _shapeH, [e]);

const _label = TextSpec(
    fontSize: 16,
    weight: 700,
    color: Color(0xFFFFFFFF),
    align: TextAlignSpec.center,
    verticalAlign: VerticalAlignSpec.middle);

List<_State> _shapeStates() {
  var out = <_State>[];
  for (var kind in ShapeKind.values) {
    for (var (boxName, box) in _boxes) {
      for (var (look, apply) in _looks()) {
        out.add(_state("shape-${kind.name}-$boxName-$look",
            _shapePage(apply(_shape(kind, box)))));
      }
    }
  }

  // A star's points and depth.
  for (var points in [3, 5, 12]) {
    for (var depth in [0.2, 0.42, 0.7]) {
      out.add(_state(
          "shape-star-points-$points-depth-${_short(depth)}",
          _shapePage(_shape(ShapeKind.star, _square).copyWith(
              points: points,
              innerRatio: depth,
              strokeWidth: 4,
              strokeColor: _orange))));
    }
  }

  // Corners: one radius for all four, and four of their own.
  for (var kind
      in ShapeKind.values.where((k) => k.hasCornersWith(BubbleBody.rounded))) {
    if (kind == ShapeKind.speechBubble) continue;
    for (var (boxName, box) in _boxes) {
      out.add(_state("shape-${kind.name}-$boxName-corners-even",
          _shapePage(_shape(kind, box).copyWith(cornerRadius: 24))));
      out.add(_state(
          "shape-${kind.name}-$boxName-corners-four",
          _shapePage(_shape(kind, box)
              .copyWith(radTL: 0, radTR: 12, radBR: 30, radBL: 50))));
    }
  }

  // A label in the room each kind keeps for itself, and in padding.
  for (var kind in ShapeKind.values) {
    var labelled = _shape(kind, _oblong)
        .copyWith(text: "Words set in a shape", textSpec: _label);
    out.add(_state("label-${kind.name}-own-room", _shapePage(labelled)));
    out.add(_state(
        "label-${kind.name}-padded",
        _shapePage(labelled.copyWith(
            padding: 6, padL: 4, padT: 20, padR: 30, padB: 8))));
  }
  for (var body in BubbleBody.values) {
    out.add(_state(
        "label-bubble-${body.name}-own-room",
        _shapePage(_shape(ShapeKind.speechBubble, _oblong).copyWith(
            fill: _paper,
            text: "Words set in a bubble",
            textSpec: _label.copyWith(color: const Color(0xFF212121)),
            bubble: SpeechBubbleSpec(body: body)))));
  }

  // Turned and slanted.
  for (var kind in ShapeKind.values) {
    var outlined =
        _shape(kind, _oblong).copyWith(strokeWidth: 4, strokeColor: _orange);
    out.add(_state("shape-${kind.name}-turned",
        _shapePage(outlined.withBase(rotation: 30) as ShapeElement)));
    out.add(_state("shape-${kind.name}-slanted",
        _shapePage(outlined.withBase(skewX: 20) as ShapeElement)));
  }

  // The outline a loop runs round.
  for (var kind in ShapeKind.values) {
    for (var (boxName, box) in _boxes) {
      out.add(_state("loop-${kind.name}-$boxName",
          _shapePage(_shape(kind, box).copyWith(animation: _loop))));
    }
  }
  out.add(_state(
      "loop-star-points-7-depth-0_7",
      _shapePage(_shape(ShapeKind.star, _oblong)
          .copyWith(points: 7, innerRatio: 0.7, animation: _loop))));
  for (var body in BubbleBody.values) {
    out.add(_state(
        "loop-bubble-${body.name}",
        _shapePage(_shape(ShapeKind.speechBubble, _oblong).copyWith(
            fill: _paper,
            bubble: SpeechBubbleSpec(body: body, tailAngle: 45),
            animation: _loop))));
  }
  return out;
}

// Speech bubbles, on a page 240 square.

const _bubbleSide = 240;
const _wide = Rect.fromLTWH(45, 70, 150, 100);
const _tall = Rect.fromLTWH(75, 40, 90, 160);
const _bubbleBoxes = [("wide", _wide), ("tall", _tall)];
const _angles = [0.0, 45.0, 90.0, 180.0, 270.0, 333.0, -30.0];

ShapeElement _bubble(Rect box, SpeechBubbleSpec spec) => ShapeElement(_at(box),
    shape: ShapeKind.speechBubble,
    fill: _paper,
    strokeWidth: 3,
    strokeColor: _orange,
    bubble: spec);

CanvasDocument _bubblePage(ShapeElement e) =>
    _page(_bubbleSide, _bubbleSide, [e]);

List<_State> _bubbleStates() {
  var out = <_State>[];
  var tails = BubbleTail.values.where((t) => t != BubbleTail.none);
  for (var body in BubbleBody.values) {
    for (var (boxName, box) in _bubbleBoxes) {
      out.add(_state(
          "bubble-${body.name}-none-$boxName",
          _bubblePage(_bubble(
              box, SpeechBubbleSpec(body: body, tail: BubbleTail.none)))));
      for (var tail in tails) {
        for (var angle in _angles) {
          out.add(_state(
              "bubble-${body.name}-${tail.name}-angle-${_signed(angle)}-$boxName",
              _bubblePage(_bubble(
                  box,
                  SpeechBubbleSpec(
                      body: body, tail: tail, tailAngle: angle)))));
        }
      }
    }
  }

  // Two lengths and two widths of tail.
  for (var body in BubbleBody.values) {
    for (var tail in tails) {
      for (var (lengthName, length) in [("short", 0.2), ("long", 1.0)]) {
        for (var (widthName, width) in [("narrow", 0.12), ("broad", 0.8)]) {
          out.add(_state(
              "bubble-${body.name}-${tail.name}-$lengthName-$widthName",
              _bubblePage(_bubble(
                  _wide,
                  SpeechBubbleSpec(
                      body: body,
                      tail: tail,
                      tailLength: length,
                      tailWidth: width)))));
        }
      }
    }
  }

  // A curved tail's curl, either way and none.
  for (var body in BubbleBody.values) {
    for (var curl in [0.0, 1.2, -1.2]) {
      out.add(_state(
          "bubble-${body.name}-curved-curl-${_signed(curl)}",
          _bubblePage(_bubble(
              _wide,
              SpeechBubbleSpec(
                  body: body, tail: BubbleTail.curved, curl: curl)))));
    }
  }

  // Corners: a rounded body takes one radius; four of their own, and any
  // corners on a body that is not rounded, are kept as drawn.
  for (var (boxName, box) in _bubbleBoxes) {
    out.add(_state(
        "bubble-rounded-corners-even-$boxName",
        _bubblePage(_bubble(box, const SpeechBubbleSpec())
            .copyWith(cornerRadius: 30))));
    out.add(_state(
        "bubble-rounded-corners-four-$boxName",
        _bubblePage(_bubble(box, const SpeechBubbleSpec())
            .copyWith(radTL: 0, radTR: 10, radBR: 30, radBL: 50))));
  }
  out.add(_state(
      "bubble-oval-corners-even",
      _bubblePage(_bubble(_wide, const SpeechBubbleSpec(body: BubbleBody.oval))
          .copyWith(cornerRadius: 30))));
  return out;
}

// Lines, on a page 320 by 240.

const _lineW = 320, _lineH = 240;
const _lineBox = Rect.fromLTWH(90, 80, 140, 70);
const _thin = 2.0, _thick = 8.0;
const _sizes = [("size-1", 1.0), ("size-2", 2.0), ("size-half", 0.5)];
const _strokes = [("thin", _thin), ("thick", _thick)];

LineElement _line({
  double width = _thick,
  LineStrokeCap cap = LineStrokeCap.flat,
  LineEnd start = LineEnd.none,
  LineEnd end = LineEnd.none,
  double endSize = 1,
  double dash = 0,
  double curvature = 0,
  bool flipped = false,
  GradientSpec? fade,
}) =>
    LineElement(_at(_lineBox),
        color: _orange,
        fade: fade,
        strokeWidth: width,
        cap: cap,
        startEnd: start,
        endEnd: end,
        endSize: endSize,
        dash: dash,
        curvature: curvature,
        flipped: flipped);

CanvasDocument _linePage(LineElement e) => _page(_lineW, _lineH, [e]);

List<_State> _lineStates() {
  var out = <_State>[];
  for (var end in LineEnd.values) {
    for (var (sizeName, size) in _sizes) {
      for (var (strokeName, width) in _strokes) {
        out.add(_state("line-start-${end.name}-$sizeName-$strokeName",
            _linePage(_line(width: width, start: end, endSize: size))));
        out.add(_state("line-end-${end.name}-$sizeName-$strokeName",
            _linePage(_line(width: width, end: end, endSize: size))));
      }
    }
  }
  for (var cap in LineStrokeCap.values) {
    for (var end in LineEnd.values) {
      out.add(_state("line-cap-${cap.name}-end-${end.name}",
          _linePage(_line(cap: cap, end: end))));
    }
  }
  for (var (strokeName, width) in _strokes) {
    out.add(_state("line-dashed-$strokeName",
        _linePage(_line(width: width, dash: 12, end: LineEnd.arrow))));
  }
  out.add(_state(
      "line-dashed-round-cap",
      _linePage(
          _line(dash: 12, cap: LineStrokeCap.round, end: LineEnd.circle))));
  for (var curvature in [0.4, -0.4]) {
    out.add(_state(
        "line-bowed-${_signed(curvature)}",
        _linePage(_line(
            curvature: curvature,
            start: LineEnd.hollowCircle,
            end: LineEnd.arrow))));
  }
  const fade = GradientSpec(to: _blue, angle: 0);
  out.add(_state("line-faded", _linePage(_line(fade: fade))));
  out.add(_state("line-faded-arrow",
      _linePage(_line(fade: fade, end: LineEnd.arrow, endSize: 1.5))));
  out.add(_state(
      "line-faded-bowed-ends",
      _linePage(_line(
          fade: fade,
          curvature: 0.4,
          start: LineEnd.square,
          end: LineEnd.diamond))));
  out.add(_state(
      "line-flipped",
      _linePage(
          _line(flipped: true, start: LineEnd.arrow, end: LineEnd.circle))));
  out.add(_state(
      "line-flipped-bowed",
      _linePage(_line(
          flipped: true,
          curvature: 0.4,
          start: LineEnd.arrow,
          end: LineEnd.circle))));
  var ended = _line(start: LineEnd.bar, end: LineEnd.arrow);
  out.add(_state(
      "line-level",
      _linePage(
          ended.withEnds(const Offset(60, 120), const Offset(260, 120)))));
  out.add(_state(
      "line-upright",
      _linePage(
          ended.withEnds(const Offset(160, 40), const Offset(160, 200)))));
  out.add(_state(
      "line-level-backwards",
      _linePage(
          ended.withEnds(const Offset(260, 120), const Offset(60, 120)))));
  out.add(_state(
      "line-turned", _linePage(ended.withBase(rotation: 40) as LineElement)));
  out.add(_state(
      "line-turned-bowed",
      _linePage(ended.copyWith(curvature: 0.4).withBase(rotation: 40)
          as LineElement)));
  out.add(_state(
      "line-slanted", _linePage(ended.withBase(skewX: 20) as LineElement)));
  out.add(_state("loop-line-bowed",
      _linePage(_line(curvature: 0.4).copyWith(animation: _loop))));
  return out;
}

// Paths, on a page 320 by 240.

const _pathBox = Rect.fromLTWH(40, 40, 240, 160);
const _straight = [
  PathNode(x: 0.05, y: 0.8, frame: 0),
  PathNode(x: 0.35, y: 0.2, frame: 8),
  PathNode(x: 0.65, y: 0.8, frame: 16),
  PathNode(x: 0.95, y: 0.2, frame: 24),
];

PathElement _path({
  List<PathNode>? nodes,
  double width = 4,
  LineStrokeCap cap = LineStrokeCap.round,
  LineEnd start = LineEnd.none,
  LineEnd end = LineEnd.none,
  double endSize = 1,
  double dash = 0,
  bool closed = false,
  bool guide = false,
  GradientSpec? fade,
}) =>
    PathElement(_at(_pathBox),
        nodes: nodes ?? PathElement.defaultNodes(),
        color: _orange,
        fade: fade,
        strokeWidth: width,
        cap: cap,
        startEnd: start,
        endEnd: end,
        endSize: endSize,
        dash: dash,
        closed: closed,
        guide: guide);

CanvasDocument _pathPage(PathElement e) => _page(_lineW, _lineH, [e]);

List<_State> _pathStates() {
  var out = <_State>[];
  for (var (shapeName, nodes) in [
    ("straight", _straight),
    ("curved", PathElement.defaultNodes()),
  ]) {
    out.add(_state("path-$shapeName-open", _pathPage(_path(nodes: nodes))));
    out.add(_state("path-$shapeName-closed",
        _pathPage(_path(nodes: nodes, closed: true))));
    out.add(_state(
        "path-$shapeName-closed-ends",
        _pathPage(_path(
            nodes: nodes,
            closed: true,
            start: LineEnd.arrow,
            end: LineEnd.arrow))));
  }
  // Every end at each end, at two sizes.
  for (var end in LineEnd.values) {
    for (var (sizeName, size) in [("size-1", 1.0), ("size-2_5", 2.5)]) {
      out.add(_state("path-start-${end.name}-$sizeName",
          _pathPage(_path(start: end, endSize: size))));
      out.add(_state("path-end-${end.name}-$sizeName",
          _pathPage(_path(end: end, endSize: size))));
    }
  }
  for (var cap in LineStrokeCap.values) {
    out.add(_state("path-cap-${cap.name}",
        _pathPage(_path(nodes: _straight, width: 12, cap: cap))));
  }
  out.add(
      _state("path-dashed", _pathPage(_path(dash: 14, end: LineEnd.arrow))));
  out.add(_state(
      "path-faded",
      _pathPage(_path(
          width: 8,
          fade: const GradientSpec(to: _blue, angle: 0),
          end: LineEnd.arrow))));
  var ended = _path(start: LineEnd.circle, end: LineEnd.arrow);
  out.add(_state(
      "path-turned", _pathPage(ended.withBase(rotation: 25) as PathElement)));
  out.add(_state(
      "path-slanted", _pathPage(ended.withBase(skewX: 20) as PathElement)));
  out.add(_state("path-guide-published", _pathPage(_path(guide: true))));
  out.add(_state("path-guide-editing", _pathPage(_path(guide: true)),
      editing: true));
  out.add(_state(
      "loop-path-curved", _pathPage(_path().copyWith(animation: _loop))));
  return out;
}

/// _states is every state kept.
List<_State> _states() => [
      ..._shapeStates(),
      ..._bubbleStates(),
      ..._lineStates(),
      ..._pathStates(),
    ];

// The numbers kept beside each picture.

/// _gridStep is how far apart the points a press or a wrap is asked about
/// are, in design units: fine enough that a point moved, a corner rounded
/// differently or a tail turned shows.
const _gridStep = 4.0;

/// _n is [v] to a ten-thousandth: far finer than a pixel, and coarse enough
/// that the same sum done in another order still agrees.
String _n(double v) {
  var s = v.toStringAsFixed(4);
  return s == "-0.0000" ? "0.0000" : s;
}

String _point(Offset p) => "(${_n(p.dx)}, ${_n(p.dy)})";

String _rect(Rect r) =>
    "[${_n(r.left)}, ${_n(r.top)}, ${_n(r.right)}, ${_n(r.bottom)}]";

/// _digest is which points of a grid over [page] [inside] holds for: how
/// many, and a hash of which, so any point that changes changes it.
String _digest(Rect page, bool Function(Offset) inside) {
  var hash = 0x811c9dc5, count = 0, total = 0;
  for (var y = page.top + _gridStep / 2; y < page.bottom; y += _gridStep) {
    for (var x = page.left + _gridStep / 2; x < page.right; x += _gridStep) {
      var hit = inside(Offset(x, y));
      total++;
      if (hit) count++;
      hash = ((hash ^ (hit ? 1 : 0)) * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return "$count/$total #${hash.toRadixString(16).padLeft(8, "0")}";
}

double _lengthOf(List<Offset> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i] - points[i - 1]).distance;
  }
  return total;
}

/// _numbers is what the stage and the words ask of each element in [doc],
/// one line each.
String _numbers(CanvasDocument doc) {
  var out = StringBuffer();
  var page = doc.size.rect;
  var hits = StageHitTest(document: doc, frame: 0, scale: 1);
  for (var e in doc.elements) {
    out.writeln("${e.id} drawn ${_rect(visualBoundsOf(e, doc, 0))}");
    out.writeln("${e.id} pressed ${_digest(page, (p) => hits.contains(e, p))}");

    // Words wrapped over the whole page, beside this element alone.
    var words = TextElement(
        ElementBase(id: "words", width: page.width, height: page.height),
        text: "Words",
        wrap: const TextWrap(on: true, gap: 8));
    var beside = CanvasDocument(size: doc.size, elements: [e, words]);
    for (var obstacle in wrapObstacles(words, beside, 0, page)) {
      out.writeln("${e.id} wrap box ${_rect(obstacle.bounds)}");
      var outline = obstacle.path;
      if (outline == null) {
        out.writeln("${e.id} wrap outline none");
      } else {
        out.writeln("${e.id} wrap outline ${_rect(outline.getBounds())} "
            "${_digest(page, outline.contains)}");
      }
    }

    if (e is LineElement || e is PathElement) {
      var curve = curveOfElement(e);
      if (curve == null || curve.isEmpty) {
        out.writeln("${e.id} curve none");
      } else {
        out.writeln("${e.id} ends ${_point(curve.first)} ${_point(curve.last)} "
            "length ${_n(_lengthOf(curve))}");
      }
    }
  }
  return out.toString();
}

void main() {
  /// keep draws [state] and compares the picture and numbers with those
  /// kept under its name, or keeps them.
  Future<void> keep(_State state) async {
    var size = state.doc.size;
    var recorder = ui.PictureRecorder();
    paintCanvasDocument(ui.Canvas(recorder), state.doc, editing: state.editing);
    var (raw, png) = await imageBytes(
        await recorder.endRecording().toImage(size.width, size.height));
    keepOrCompare("SHAPE_PICTURES", state.name,
        raw: raw, png: png, width: size.width, numbers: _numbers(state.doc));
  }

  var states = _states();
  test("there are as many states as meant", () {
    expect(states.length, greaterThan(600));
    expect({for (var s in states) s.name}.length, states.length,
        reason: "every state has a name of its own");
  });
  for (var state in states) {
    test(state.name, () => keep(state));
  }
}

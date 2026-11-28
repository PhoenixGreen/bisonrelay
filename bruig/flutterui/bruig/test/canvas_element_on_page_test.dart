import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_align.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_selection.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';

import 'support/canvas_app.dart';

// canvas_element_on_page_test.dart is an element that is not a stroke where
// it is drawn: a filled rectangle, a filled triangle, a picture filling its
// box, and a text with a filled box and without one, each drawn through the
// real renderer part-way through each way motion lays it out. Whatever asks
// where it is (the press, the selection box the stage lays its handles on)
// is held to the ink on the page; and a drag of it at a moved frame moves
// what is drawn by as far as the pointer goes.

const _page = 300;
const _orange = Color(0xFFFFA726);
const _blue = Color(0xFF1E5EFF);

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

  /// solid is the centre of every inked pixel whose four neighbours are
  /// inked too: the ink, less the softened pixels along its edge, which a
  /// turned edge leaves part-covered and half outside where it runs.
  List<Offset> get solid => [
        for (var y = 0; y < _page; y++)
          for (var x = 0; x < _page; x++)
            if (at(x, y) &&
                at(x - 1, y) &&
                at(x + 1, y) &&
                at(x, y - 1) &&
                at(x, y + 1))
              Offset(x + 0.5, y + 0.5),
      ];
}

/// _Pictures hands the painter one picture, whatever is asked for.
class _Pictures implements CanvasImageSource {
  final ui.Image image;
  _Pictures(this.image);

  @override
  bool get loading => false;

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId.isEmpty ? null : image;

  @override
  CanvasVector? resolveVector(String assetId) => null;

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

/// _solidPicture is a picture of one colour, which drawn stretched fills
/// the box it is drawn in.
Future<ui.Image> _solidPicture() {
  var recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = _orange);
  return recorder.endRecording().toImage(16, 16);
}

/// _midway is the frame everything is drawn on: half-way through its keys
/// and its clip, and a quarter of the way round a loop of four seconds.
const _midway = 12;

CanvasDocument _pageOf(List<CanvasElement> elements) => CanvasDocument(
    size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
    elements: elements,
    frames: 48,
    frameRate: 12,
    guides: const CanvasGuides(snap: false));

Future<_Ink> _drawAt(CanvasDocument doc, int frame) async {
  var picture = await _solidPicture();
  var recorder = ui.PictureRecorder();
  paintCanvasDocument(ui.Canvas(recorder), doc,
      frame: frame, images: _Pictures(picture));
  var image = await recorder.endRecording().toImage(_page, _page);
  var data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return _Ink(data!.buffer.asUint8List());
}

/// _keyed is [base] with a key at rest on frame 0 and [to] on frame 24.
ElementBase _keyed(ElementBase base, Keyframe to) => base.copyWith(
    track: ElementTrack([const Keyframe(frame: 0), to.copyWith(frame: 24)]));

/// _clip is a clip of two seconds carrying an element [x] across and [y]
/// down, which at 12 frames a second is half done on [_midway].
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

/// _Motion is one way an element is laid out on [_midway]: its box with
/// its keys, clip and turn, and the loop it plays.
typedef _Motion = (String, ElementBase, ElementLoop);

const _none = ElementLoop();

/// _spin turns once round in four seconds: a quarter turn on [_midway].
const _spin = ElementLoop(preset: LoopPreset.spin, cycle: 48);

/// _swing swings from its top, furthest on [_midway]: 36 degrees.
const _swing = ElementLoop(preset: LoopPreset.swing, cycle: 48, strength: 3);

List<_Motion> _motions() {
  const box = ElementBase(id: "e", x: 100, y: 110, width: 100, height: 80);
  return [
    ("at rest", box, _none),
    ("turned as it rests", box.copyWith(rotation: 30), _none),
    ("slanted as it rests", box.copyWith(skewX: 25), _none),
    (
      "moved by its keys",
      _keyed(box, const Keyframe(frame: 0, dx: 60, dy: 40)),
      _none
    ),
    (
      "sized by its keys",
      _keyed(box, const Keyframe(frame: 0, scale: 1.6)),
      _none
    ),
    (
      "turned by its keys",
      _keyed(box, const Keyframe(frame: 0, rotate: 70)),
      _none
    ),
    (
      "turned by its keys about an anchor at its corner",
      _keyed(box.copyWith(anchorX: 0, anchorY: 0),
          const Keyframe(frame: 0, rotate: 70)),
      _none
    ),
    (
      "turned as it rests and sized by its keys about an anchor at its corner",
      _keyed(box.copyWith(rotation: 30, anchorX: 0, anchorY: 0),
          const Keyframe(frame: 0, scale: 1.6)),
      _none
    ),
    (
      "slanted as it rests and turned by its keys",
      _keyed(box.copyWith(skewX: 25), const Keyframe(frame: 0, rotate: 50)),
      _none
    ),
    ("spun by its loop", box, _spin),
    ("swung from its top by its loop", box, _swing),
    (
      "squashed by its keys",
      _keyed(
          box,
          const Keyframe(frame: 0, values: {
            KeyframeChannel.squash: 1.8,
            KeyframeChannel.squashAngle: 0,
          })),
      _none
    ),
    ("moved by a clip", box.copyWith(motion: _clip(80, 40)), _none),
    (
      "moved every way at once",
      _keyed(
          const ElementBase(
              id: "e",
              x: 90,
              y: 100,
              width: 80,
              height: 60,
              rotation: 20,
              skewY: 12,
              anchorX: 0.2,
              anchorY: 0.3),
          const Keyframe(
              frame: 0,
              dx: 30,
              dy: 16,
              rotate: 40,
              scale: 1.3,
              values: {
                KeyframeChannel.squash: 1.4,
                KeyframeChannel.squashAngle: 0.5,
              })).copyWith(motion: _clip(40, 20)),
      const ElementLoop(preset: LoopPreset.swing, cycle: 48, strength: 2)
    ),
  ];
}

/// _Kind is a kind of element made in a box: whether it is pressed only on
/// its ink (a shape by its outline, a picture or a filled box by its box),
/// whether its box is all ink (so the selection box is no bigger than it),
/// and how it is made.
typedef _Kind = (
  String,
  bool,
  bool,
  CanvasElement Function(ElementBase, ElementLoop)
);

final List<_Kind> _kinds = [
  (
    "a rectangle",
    true,
    true,
    (b, loop) =>
        ShapeElement(b, fill: _orange, animation: ElementAnimation(loop: loop)),
  ),
  (
    "a triangle",
    true,
    false,
    (b, loop) => ShapeElement(b,
        shape: ShapeKind.triangle,
        fill: _orange,
        animation: ElementAnimation(loop: loop)),
  ),
  (
    "a picture",
    true,
    true,
    (b, loop) => ImageElement(b,
        assetId: "solid",
        fit: ImageFit.stretch,
        animation: ElementAnimation(loop: loop)),
  ),
  (
    "a text in a filled box",
    true,
    true,
    (b, loop) => TextElement(b,
        text: "HHHH HHHH",
        textSpec: const TextSpec(fontSize: 18, color: _orange),
        box: const BoxSpec(fill: _blue),
        animation: TextAnimation(loop: loop)),
  ),
  (
    "a text",
    false,
    false,
    (b, loop) => TextElement(b,
        text: "HHHH HHHH",
        textSpec: const TextSpec(fontSize: 18, color: _orange),
        animation: TextAnimation(loop: loop)),
  ),
];

/// _reach is how far from its ink [e] may be pressed: a shape is pressed
/// near enough its edge to pick a thin one, anything else in its box.
double _reach(CanvasElement e) => (e is ShapeElement ? strokeHitSlop : 0) + 1.5;

/// _Quad is the selection box as the stage lays its handles on it, on the
/// page: its corners in order round it.
typedef _Quad = List<Offset>;

/// _inside is whether [p] is inside [quad] or within [slack] of it.
bool _inside(_Quad quad, Offset p, {double slack = 0.75}) {
  // The quad's winding, so inside is the same side of every edge.
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    var a = quad[i], b = quad[(i + 1) % 4];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  var sign = area >= 0 ? 1 : -1;
  for (var i = 0; i < 4; i++) {
    var a = quad[i], b = quad[(i + 1) % 4];
    var ab = b - a;
    var cross = ab.dx * (p.dy - a.dy) - ab.dy * (p.dx - a.dx);
    if (sign * cross / ab.distance < -slack) return false;
  }
  return true;
}

/// _selectionOnStage is [doc]'s element "e" selected on a stage on [frame]:
/// the box its handles are laid on, brought back to the page.
Future<_Quad> _selectionOnStage(
    WidgetTester tester, CanvasDocument doc, int frame) async {
  // The stage is asked only where the box is; a picture with nothing to
  // show, moving as it does, has the same box, and asks no storage for one.
  var e = doc.elementById("e")!;
  if (e is ImageElement) {
    doc = doc
        .withElement(ImageElement(e.base, fit: e.fit, animation: e.animation));
  }
  var controller = CanvasController(doc);
  addTearDown(controller.dispose);
  controller.frame = frame;
  controller.selectOnly("e");
  var key = GlobalKey<CanvasStageState>();
  const viewport = Size(800, 600);
  setTestScreen(tester, viewport);
  await tester.pumpWidget(canvasApp(SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: CanvasStage(key: key, controller: controller))));
  await tester.pumpAndSettle();
  var stage = key.currentState!;
  var origin = stage.toStagePoint(Offset.zero);
  var scale =
      (stage.toStagePoint(const Offset(_page * 1.0, 0)) - origin).dx / _page;
  Offset back(Offset screen) => (screen - origin) / scale;
  var quad = [
    for (var h in [
      StageHandle.topLeft,
      StageHandle.topRight,
      StageHandle.bottomRight,
      StageHandle.bottomLeft,
    ])
      back(stage.handleAt(h)),
  ];
  await tester.pumpWidget(const SizedBox());
  return quad;
}

/// _quads keeps each state's selection box once asked, so the two checks
/// made of it pump one stage between them.
final _quads = <String, _Quad>{};

Future<_Quad> _quadOf(
    WidgetTester tester, String name, CanvasDocument doc) async {
  if (_quads[name] case var known?) return known;
  return _quads[name] = await _selectionOnStage(tester, doc, _midway);
}

/// _onStage shows [c] on a stage the size the other tests use, and hands
/// back its state.
Future<CanvasStageState> _onStage(
    WidgetTester tester, CanvasController c) async {
  var key = GlobalKey<CanvasStageState>();
  const viewport = Size(800, 600);
  setTestScreen(tester, viewport);
  await tester.pumpWidget(canvasApp(SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: CanvasStage(key: key, controller: c))));
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// _painterOf is the stage's page painter as last built.
StagePainter _painterOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .expand((p) => [p.painter, p.foregroundPainter])
    .whereType<StagePainter>()
    .first;

/// _marksOf is what [paint] draws on a clear page, a document unit to a
/// pixel: whether each pixel is marked at all.
Future<List<bool>> _marksOf(
    WidgetTester tester, void Function(Canvas canvas) paint) async {
  late List<bool> marked;
  await tester.runAsync(() async {
    var recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder));
    var image = await recorder.endRecording().toImage(_page, _page);
    var data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    image.dispose();
    marked = [for (var i = 3; i < data.length; i += 4) data[i] > 40];
  });
  return marked;
}

/// _offEdge is how far [p] is from the nearest edge of [quad].
double _offEdge(_Quad quad, Offset p) {
  var best = double.infinity;
  for (var i = 0; i < 4; i++) {
    var a = quad[i], b = quad[(i + 1) % 4];
    var ab = b - a;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        (ab.dx * ab.dx + ab.dy * ab.dy);
    var q = a + ab * t.clamp(0.0, 1.0);
    best = math.min(best, (p - q).distance);
  }
  return best;
}

/// _expectOutlined checks that [marked] is an outline round each of
/// [quads] and nothing else: every mark on one of their edges, within
/// [near], and every corner of each marked.
void _expectOutlined(List<bool> marked, List<_Quad> quads, {double near = 2}) {
  var stray = <Offset>[];
  for (var i = 0; i < marked.length; i++) {
    if (!marked[i]) continue;
    var p = Offset(i % _page + 0.5, i ~/ _page + 0.5);
    if (quads.every((q) => _offEdge(q, p) > near)) stray.add(p);
  }
  expect(stray, isEmpty,
      reason: "${stray.length} marks off every outline, "
          "the first ${stray.take(3).toList()}");
  for (var quad in quads) {
    for (var corner in quad) {
      var found = false;
      for (var y = (corner.dy - near).floor();
          y <= (corner.dy + near).ceil() && !found;
          y++) {
        for (var x = (corner.dx - near).floor();
            x <= (corner.dx + near).ceil() && !found;
            x++) {
          if (x < 0 || y < 0 || x >= _page || y >= _page) continue;
          found = marked[y * _page + x] &&
              (Offset(x + 0.5, y + 0.5) - corner).distance <= near + 0.8;
        }
      }
      expect(found, isTrue, reason: "the corner $corner is outlined");
    }
  }
}

/// _drawnQuad is [e]'s box, or its copy [instance]'s, where the painter
/// lays it out on [_midway], its corners in order round it.
_Quad _drawnQuad(CanvasElement e, CanvasDocument doc, {int? instance}) {
  var on = placeOnPage(e, _midway, doc, null, instance: instance);
  var b = on.box;
  return [
    for (var p in [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
      on.place.place(p),
  ];
}

/// _round is the upright box round [quad].
Rect _round(_Quad quad) => Rect.fromLTRB(
    quad.map((p) => p.dx).reduce(math.min),
    quad.map((p) => p.dy).reduce(math.min),
    quad.map((p) => p.dx).reduce(math.max),
    quad.map((p) => p.dy).reduce(math.max));

/// _drawnWays are three elements drawn well off their resting box at
/// [_midway], so an outline, a marquee or a snap by that box would miss
/// them: one turned by its keys about its corner, one spun by its loop and
/// one squashed by its keys; each with two boxes
/// for a marquee near it there, drawn from empty page: one reaching the
/// element as drawn and not its resting box, one the other way about.
List<(String, CanvasElement, Rect, Rect)> _drawnWays() {
  const box = ElementBase(id: "e", x: 100, y: 110, width: 100, height: 80);
  return [
    (
      "one turned by its keys about its corner",
      ShapeElement(
          _keyed(box.copyWith(anchorX: 0, anchorY: 0),
              const Keyframe(frame: 0, rotate: 70)),
          fill: _orange),
      const Rect.fromLTRB(30, 165, 62, 185),
      const Rect.fromLTRB(192, 100, 205, 118),
    ),
    (
      "one spun by its loop",
      ShapeElement(box,
          fill: _orange, animation: const ElementAnimation(loop: _spin)),
      const Rect.fromLTRB(140, 90, 160, 104),
      const Rect.fromLTRB(92, 115, 104, 130),
    ),
    (
      "one squashed by its keys",
      ShapeElement(
          _keyed(
              box,
              const Keyframe(frame: 0, values: {
                KeyframeChannel.squash: 1.8,
                KeyframeChannel.squashAngle: 0,
              })),
          fill: _orange),
      const Rect.fromLTRB(40, 135, 66, 150),
      const Rect.fromLTRB(192, 100, 205, 118),
    ),
  ];
}

/// _apart is whether [quad] and [box] are well clear of each other: no
/// corner of either within the other, nor an edge of one crossing the
/// other's middle.
bool _apart(_Quad quad, Rect box) =>
    quad.every((p) => !box.inflate(1).contains(p)) &&
    [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight, box.center]
        .every((p) => !_inside(quad, p, slack: 1));

/// _grown is [quad] grown out by [by] on every side.
_Quad _grown(_Quad quad, double by) {
  var middle = (quad[0] + quad[2]) / 2;
  return [
    for (var i = 0; i < 4; i++)
      () {
        var a = quad[(i + 3) % 4], p = quad[i], b = quad[(i + 1) % 4];
        Offset out(Offset from, Offset to) {
          var d = to - from;
          var n = Offset(-d.dy, d.dx) / d.distance;
          return (p - middle).dx * n.dx + (p - middle).dy * n.dy >= 0 ? n : -n;
        }

        // Out along both sides' normals, to where the grown sides meet.
        var n1 = out(a, p), n2 = out(p, b);
        var bisect = n1 + n2;
        var cos = (n1.dx * bisect.dx + n1.dy * bisect.dy) / bisect.distance;
        return p + bisect / bisect.distance * (by / cos);
      }(),
  ];
}

void main() {
  group("an element is pressed and boxed where it is drawn", () {
    for (var (motion, base, loop) in _motions()) {
      for (var (kind, onlyInk, boxIsInk, make) in _kinds) {
        var e = make(base, loop);
        var doc = _pageOf([e]);
        var name = "$kind $motion";

        test("$name: every inked pixel is pressed", () async {
          var ink = await _drawAt(doc, _midway);
          var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
          var missed = [
            for (var p in ink.solid)
              if (!hits.contains(e, p)) p
          ];
          expect(missed, isEmpty,
              reason: "${missed.length} inked pixels not pressed, "
                  "the first ${missed.take(3).toList()}");
        });

        if (onlyInk) {
          test("$name: nothing is pressed far from its ink", () async {
            var ink = await _drawAt(doc, _midway);
            var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
            var far = <Offset>[];
            for (var y = 2.0; y < _page; y += 4) {
              for (var x = 2.0; x < _page; x += 4) {
                var p = Offset(x, y);
                if (hits.contains(e, p) && !ink.near(p, _reach(e))) far.add(p);
              }
            }
            expect(far, isEmpty,
                reason: "${far.length} points pressed far from ink, "
                    "the first ${far.take(3).toList()}");
          });
        }

        testWidgets("$name: its selection box holds its ink", (tester) async {
          var quad = await _quadOf(tester, name, doc);
          late _Ink ink;
          await tester.runAsync(() async => ink = await _drawAt(doc, _midway));
          var out = [
            for (var p in ink.solid)
              if (!_inside(quad, p)) p
          ];
          expect(out, isEmpty,
              reason: "${out.length} inked pixels outside $quad, "
                  "the first ${out.take(3).toList()}");
        });

        if (boxIsInk) {
          testWidgets("$name: its selection box is no bigger than its ink",
              (tester) async {
            var quad = await _quadOf(tester, name, doc);
            late _Ink ink;
            await tester
                .runAsync(() async => ink = await _drawAt(doc, _midway));
            for (var corner in quad) {
              expect(ink.near(corner, 2), isTrue,
                  reason: "the box's corner $corner is on ink");
            }
          });
        }
      }
    }
  });

  group("a lone element's handles are pressed where they are drawn", () {
    testWidgets(
        "a corner of one turned by its keys about its corner is pressed where "
        "it is drawn, and sizes it", (tester) async {
      var e = ShapeElement(
          _keyed(
              const ElementBase(
                  id: "e",
                  x: 100,
                  y: 110,
                  width: 100,
                  height: 80,
                  anchorX: 0,
                  anchorY: 0),
              const Keyframe(frame: 0, rotate: 70)),
          fill: _orange);
      var doc = _pageOf([e]);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.frame = _midway;
      c.selectOnly("e");
      var key = GlobalKey<CanvasStageState>();
      const viewport = Size(800, 600);
      setTestScreen(tester, viewport);
      await tester.pumpWidget(canvasApp(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: c))));
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / _page;
      // Its far corner, as the painter lays it out: turned about the near
      // one, well away from where a box turned about its middle has it.
      var place = placeOnPage(e, _midway, doc, null).place;
      var corner = place.place(e.bounds.bottomRight);
      expect(
          (stage.handleAt(StageHandle.bottomRight) - stage.toStagePoint(corner))
              .distance,
          lessThan(1),
          reason: "the handle is drawn on the corner");
      // Pulled out along its own diagonal.
      var out =
          place.place(e.bounds.bottomRight + const Offset(20, 16)) - corner;
      var g = await tester.startGesture(stage.toStagePoint(corner));
      await tester.pump();
      await g.moveBy(out * scale);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      var now = c.document.elementById("e")!;
      expect(now.width, greaterThan(110), reason: "sized, not moved");
      expect(now.height, greaterThan(88), reason: "sized, not moved");
    });
  });

  group("a selected shape is taken anywhere in its box as it is drawn", () {
    // A triangle turned as it rests leaves its box's corners empty: pressed
    // there, selected, it is moved; pressed beside its box, where the box
    // upright would reach, it is not.
    for (var (name, local, takes) in [
      ("in a corner of its turned box", const Offset(110, 118), true),
      ("beside its turned box", const Offset(198, 188), false),
    ]) {
      testWidgets("a triangle turned as it rests, pressed $name",
          (tester) async {
        var e = ShapeElement(
            const ElementBase(
                id: "e", x: 100, y: 110, width: 100, height: 80, rotation: 40),
            shape: ShapeKind.triangle,
            fill: _orange);
        var doc = _pageOf([e]);
        var c = CanvasController(doc);
        addTearDown(c.dispose);
        c.selectOnly("e");
        var key = GlobalKey<CanvasStageState>();
        const viewport = Size(800, 600);
        setTestScreen(tester, viewport);
        await tester.pumpWidget(canvasApp(SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: CanvasStage(key: key, controller: c))));
        await tester.pumpAndSettle();
        var stage = key.currentState!;
        var scale = stage.pageRect.width / _page;
        // Where the point is: in the box turned or not, never on the ink.
        var at = takes ? e.onPage(local) : local;
        var hits = StageHitTest(document: doc, frame: 0, scale: scale);
        expect(hits.contains(e, at), isFalse, reason: "off its outline");
        var g = await tester.startGesture(stage.toStagePoint(at));
        await tester.pump();
        await g.moveBy(Offset(20 * scale, 0));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
        var now = c.document.elementById("e")!;
        expect(now.x, takes ? closeTo(120, 0.5) : 100);
      });
    }
  });

  group("an element reused is pressed where each copy is drawn", () {
    ShapeElement copies(List<ElementInstance> items) => ShapeElement(
        ElementBase(
            id: "e",
            x: 30,
            y: 110,
            width: 60,
            height: 60,
            motion: ElementMotion(instances: InstanceSet(items: items))),
        fill: _orange);
    var side = copies(const [
      ElementInstance("a"),
      ElementInstance("b", dx: 120),
    ]);
    var turned = copies(const [
      ElementInstance("a"),
      ElementInstance("b", dx: 140, own: {"turn": 40}),
    ]);

    for (var (name, e) in [
      ("two copies side by side", side),
      ("a copy turned", turned)
    ]) {
      test("$name: every inked pixel is pressed", () async {
        var doc = _pageOf([e]);
        var ink = await _drawAt(doc, _midway);
        var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
        var missed = [
          for (var p in ink.solid)
            if (!hits.contains(e, p)) p
        ];
        expect(missed, isEmpty,
            reason: "${missed.length} inked pixels not pressed, "
                "the first ${missed.take(3).toList()}");
      });

      test("$name: nothing is pressed far from their ink", () async {
        var doc = _pageOf([e]);
        var ink = await _drawAt(doc, _midway);
        var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
        var far = <Offset>[];
        for (var y = 2.0; y < _page; y += 4) {
          for (var x = 2.0; x < _page; x += 4) {
            var p = Offset(x, y);
            if (hits.contains(e, p) && !ink.near(p, _reach(e))) far.add(p);
          }
        }
        expect(far, isEmpty,
            reason: "${far.length} points pressed far from ink, "
                "the first ${far.take(3).toList()}");
      });
    }

    test("the gap between two copies is not pressed", () {
      var doc = _pageOf([side]);
      var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
      // Between the first, 30 to 90 across, and the second, 150 to 210.
      expect(hits.contains(side, const Offset(120, 140)), isFalse);
      expect(hits.contains(side, const Offset(60, 140)), isTrue,
          reason: "the first copy is");
      expect(hits.contains(side, const Offset(180, 140)), isTrue,
          reason: "the second copy is");
    });
  });

  group("where an element is drawn on a frame is one answer", () {
    // The place placeOnPage hands back is the one the painter lays the
    // element out by: a filled rectangle's corners laid by it are the
    // corners of its ink, under every motion.
    for (var (motion, base, loop) in _motions()) {
      test("a rectangle $motion: its corners are where it is drawn", () async {
        var e = ShapeElement(base,
            fill: _orange, animation: ElementAnimation(loop: loop));
        var doc = _pageOf([e]);
        var ink = await _drawAt(doc, _midway);
        var place = placeOnPage(e, _midway, doc, null).place;
        var b = e.bounds;
        for (var corner in [
          b.topLeft,
          b.topRight,
          b.bottomRight,
          b.bottomLeft
        ]) {
          var at = place.place(corner);
          expect(ink.near(at, 2), isTrue, reason: "$corner is drawn at $at");
        }
      });
    }

    test("each copy of an element reused is placed where it is drawn",
        () async {
      var e = ShapeElement(
          const ElementBase(
              id: "e",
              x: 30,
              y: 110,
              width: 60,
              height: 60,
              motion: ElementMotion(
                  instances: InstanceSet(items: [
                ElementInstance("a"),
                ElementInstance("b", dx: 140, own: {"turn": 40}),
              ]))),
          fill: _orange);
      var doc = _pageOf([e]);
      var ink = await _drawAt(doc, _midway);
      for (var i in [0, 1]) {
        var place = placeOnPage(e, _midway, doc, null, instance: i).place;
        var b = e.bounds;
        for (var corner in [
          b.topLeft,
          b.topRight,
          b.bottomRight,
          b.bottomLeft
        ]) {
          var at = place.place(corner);
          expect(ink.near(at, 2), isTrue,
              reason: "copy $i: $corner is drawn at $at");
        }
      }
    });

    test("an answer is kept for its document, frame and copy", () {
      var e = ShapeElement(
          _keyed(const ElementBase(id: "e", width: 50, height: 40),
              const Keyframe(frame: 0, dx: 60, rotate: 30)),
          fill: _orange);
      var doc = _pageOf([e]);
      var on = placeOnPage(e, _midway, doc, null);
      expect(on.kept, isTrue);
      expect(identical(placeOnPage(e, _midway, doc, null), on), isTrue,
          reason: "asked again, the same answer");
      expect(identical(placeOnPage(e, 6, doc, null), on), isFalse,
          reason: "another frame, another answer");
      var alike = placeOnPage(e, _midway, _pageOf([e]), null);
      expect(identical(alike, on), isFalse, reason: "another document");
      expect((alike.pose.dx, alike.pose.rotate), (on.pose.dx, on.pose.rotate),
          reason: "another document alike, an answer alike");
      var live = placeOnPage(e, _midway, doc, const PointerLive(Offset.zero));
      expect(live.kept, isFalse, reason: "not while something plays live");
      expect((live.pose.dx, live.pose.rotate), (on.pose.dx, on.pose.rotate));
    });

    test("a line slanted by its Design is pressed where it is drawn", () async {
      var line = LineElement(
          const ElementBase(
              id: "e",
              x: 70,
              y: 80,
              width: 100,
              height: 80,
              motion: ElementMotion(devices: [
                MotionDevice(MotionDeviceKind.design,
                    id: "d", values: {"skewX": 40}),
              ])),
          color: _orange,
          strokeWidth: 6);
      var doc = _pageOf([line]);
      var ink = await _drawAt(doc, _midway);
      var hits = StageHitTest(document: doc, frame: _midway, scale: 1);
      var missed = [
        for (var p in ink.solid)
          if (!hits.contains(line, p)) p
      ];
      expect(missed, isEmpty,
          reason: "${missed.length} inked pixels not pressed, "
              "the first ${missed.take(3).toList()}");
    });

    test("a stroke first asked about from inside a pose is kept as it is drawn",
        () {
      // A line facing what rides it, a quarter of the way along, and
      // something else looking at the rider: asked first for where the rider
      // is, the line is worked out from inside a Look at, a round deeper.
      // What is kept for it is still the line as drawn, asked from outside.
      var line = LineElement(
          const ElementBase(
              id: "l",
              x: 60,
              y: 70,
              width: 160,
              height: 10,
              motion: ElementMotion(devices: [
                MotionDevice(MotionDeviceKind.lookAt,
                    target: "s", values: {"smooth": 0}),
              ])),
          color: _orange,
          strokeWidth: 4);
      var rider = ShapeElement(const ElementBase(
          id: "s",
          width: 20,
          height: 20,
          motion: ElementMotion(devices: [
            MotionDevice(MotionDeviceKind.followPath,
                target: "l", values: {"lap": 4, "loop": 1}),
          ])));
      var watcher = ShapeElement(const ElementBase(
          id: "x",
          x: 300,
          y: 300,
          width: 20,
          height: 20,
          motion: ElementMotion(devices: [
            MotionDevice(MotionDeviceKind.lookAt, target: "s"),
          ])));
      var elements = <CanvasElement>[line, rider, watcher];
      var asked = _pageOf(elements);
      var fresh = curveOfElement(line, _midway, _pageOf(elements))!;
      poseWithMotion(watcher, _midway, asked);
      var kept = curveOfElement(line, _midway, asked)!;
      expect((kept.first - fresh.first).distance, lessThan(1e-6),
          reason: "kept ${kept.first}, drawn from ${fresh.first}");
      expect((kept.last - fresh.last).distance, lessThan(1e-6),
          reason: "kept ${kept.last}, drawn to ${fresh.last}");
    });
  });

  group("an element dragged on a frame where it moves", () {
    // Each dragged 40 to the right on the frame part-way through its motion,
    // in two steps of 20: what is drawn goes with the pointer, step by step.
    const box = ElementBase(id: "e", x: 100, y: 110, width: 100, height: 80);
    // Each with keying on the frame on or off, and whether the drag then
    // poses it there or moves where it rests: a track that poses it is
    // always posed.
    var cases = <(String, ElementBase, bool, bool)>[
      (
        "sized by its keys, posed",
        _keyed(box, const Keyframe(frame: 0, scale: 1.6)),
        false,
        true
      ),
      (
        "moved by a clip, posed",
        box.copyWith(motion: _clip(80, 40)),
        true,
        true
      ),
      (
        "moved by a clip, moved",
        box.copyWith(motion: _clip(80, 40)),
        false,
        false
      ),
    ];
    for (var (name, base, autoKey, poses) in cases) {
      testWidgets("$name: what is drawn moves with the pointer",
          (tester) async {
        var doc = _pageOf([ShapeElement(base, fill: _orange)]);
        var c = CanvasController(doc);
        addTearDown(c.dispose);
        c.frame = _midway;
        c.autoKeyframe = autoKey;
        c.selectOnly("e");
        var key = GlobalKey<CanvasStageState>();
        const viewport = Size(800, 600);
        setTestScreen(tester, viewport);
        await tester.pumpWidget(canvasApp(SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: CanvasStage(key: key, controller: c))));
        await tester.pumpAndSettle();
        var stage = key.currentState!;
        var scale = stage.pageRect.width / _page;
        // Where its middle is drawn, as the painter lays it out.
        Offset drawn() {
          var now = c.document.elementById("e")!;
          return now.placeAt(_midway, c.document).place(now.bounds.center);
        }

        var start = drawn();
        var g = await tester.startGesture(stage.toStagePoint(start));
        await tester.pump();
        await g.moveBy(Offset(20 * scale, 0));
        await tester.pump();
        var first = drawn() - start;
        await g.moveBy(Offset(20 * scale, 0));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
        var all = drawn() - start;
        expect(c.posesRatherThanMoves(c.document.elementById("e")!), poses);
        expect(first.dx, closeTo(20, 0.5), reason: "first step: $first");
        expect(first.dy, closeTo(0, 0.5), reason: "first step: $first");
        expect(all.dx, closeTo(40, 0.5), reason: "both steps: $all");
        expect(all.dy, closeTo(0, 0.5), reason: "both steps: $all");
      });
    }
  });
  group("what the stage outlines, takes and snaps to is as drawn", () {
    // A plain partner, at rest, to select beside each.
    var partner = ShapeElement(
        const ElementBase(id: "p", x: 20, y: 20, width: 40, height: 30),
        fill: _blue);

    for (var (name, e, reaches, misses) in _drawnWays()) {
      testWidgets("several selected, $name is outlined where it is drawn",
          (tester) async {
        var doc = _pageOf([e, partner]);
        var c = CanvasController(doc);
        addTearDown(c.dispose);
        c.frame = _midway;
        c.selectOnly("e");
        c.toggleSelected("p");
        await _onStage(tester, c);
        var inputs = _painterOf(tester).inputs;
        var marked = await _marksOf(
            tester,
            (canvas) => paintChosenBoxes(canvas, inputs.selection.ids,
                inputs.shown, null, 1, Offset.zero));
        _expectOutlined(marked, [_drawnQuad(e, doc), _drawnQuad(partner, doc)]);
      });

      testWidgets("with every box shown, $name is outlined where it is drawn",
          (tester) async {
        var doc = _pageOf([e, partner]);
        var c = CanvasController(doc);
        addTearDown(c.dispose);
        c.frame = _midway;
        c.showAllBounds = true;
        await _onStage(tester, c);
        var inputs = _painterOf(tester).inputs;
        var marked = await _marksOf(
            tester,
            (canvas) => paintKeptBoxes(
                canvas, true, const {}, inputs.shown, null, 1, Offset.zero));
        _expectOutlined(marked, [_drawnQuad(e, doc), _drawnQuad(partner, doc)]);
      });

      testWidgets("several selected with $name are boxed round them as drawn",
          (tester) async {
        var doc = _pageOf([e, partner]);
        var c = CanvasController(doc);
        addTearDown(c.dispose);
        c.frame = _midway;
        c.selectOnly("e");
        c.toggleSelected("p");
        var stage = await _onStage(tester, c);
        var origin = stage.toStagePoint(Offset.zero);
        var scale =
            (stage.toStagePoint(const Offset(_page * 1.0, 0)) - origin).dx /
                _page;
        Offset back(Offset screen) => (screen - origin) / scale;
        var box = Rect.fromPoints(back(stage.handleAt(StageHandle.topLeft)),
            back(stage.handleAt(StageHandle.bottomRight)));
        var drawn = _round(_drawnQuad(e, doc)).expandToInclude(partner.bounds);
        for (var (got, want) in [
          (box.left, drawn.left),
          (box.top, drawn.top),
          (box.right, drawn.right),
          (box.bottom, drawn.bottom),
        ]) {
          expect(got, closeTo(want, 0.5), reason: "$box round $drawn");
        }
      });

      for (var (what, marquee, takes) in [
        ("a marquee reaching it as drawn takes it", reaches, true),
        ("a marquee reaching only where it rests leaves it", misses, false),
      ]) {
        testWidgets("$name: $what", (tester) async {
          var doc = _pageOf([e]);
          var quad = _drawnQuad(e, doc);
          var resting = e.bounds;
          // Each marquee reaches one and not the other.
          expect(_apart(quad, marquee), !takes, reason: "the drawn one");
          expect(resting.overlaps(marquee), !takes, reason: "the resting one");
          // Drawn from empty page, so it is a marquee and not a move.
          var from = takes ? marquee.topLeft : marquee.topRight;
          expect(_inside(quad, from, slack: 4), isFalse);
          var c = CanvasController(doc);
          addTearDown(c.dispose);
          c.frame = _midway;
          var stage = await _onStage(tester, c);
          var g = await tester.startGesture(stage.toStagePoint(from));
          await tester.pump();
          await g.moveTo(stage
              .toStagePoint(takes ? marquee.bottomRight : marquee.bottomLeft));
          await tester.pump();
          await g.up();
          await tester.pumpAndSettle();
          expect(c.selection.contains("e"), takes);
          expect(c.document.elementById("e")!.x, e.x, reason: "not moved");
        });
      }
    }

    // A small square dragged up to the one turned by its keys about its
    // corner, its left side brought just past where that is drawn furthest
    // right, snaps there: the edge that shows, not its resting box's.
    testWidgets(
        "a square dragged beside one turned by its keys about its corner "
        "snaps to its edge as drawn", (tester) async {
      var turned = _drawnWays().first.$2;
      var square = ShapeElement(
          const ElementBase(id: "s", x: 180, y: 30, width: 30, height: 30),
          fill: _blue);
      var doc = CanvasDocument(
          size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
          elements: [turned, square],
          frames: 48,
          frameRate: 12,
          guides: const CanvasGuides(snapTo: SnapTo(centres: false)));
      var right = _round(_drawnQuad(turned, doc)).right;
      expect((right - turned.bounds.right).abs(), greaterThan(10),
          reason: "drawn well inside where it rests");
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.frame = _midway;
      c.selectOnly("s");
      var stage = await _onStage(tester, c);
      var scale = stage.pageRect.width / _page;
      var travel = right + 1.3 - 180;
      var g =
          await tester.startGesture(stage.toStagePoint(square.bounds.center));
      await tester.pump();
      await g.moveBy(Offset(travel / 2 * scale, 0));
      await tester.pump();
      await g.moveBy(Offset(travel / 2 * scale, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(c.document.elementById("s")!.x, closeTo(right, 0.01));
    });

    // The one turned by its keys about its corner, dragged so its drawn
    // left comes just past the page's edge, snaps by that drawn left.
    testWidgets(
        "one turned by its keys about its corner, dragged, snaps by its "
        "edge as drawn", (tester) async {
      var turned = _drawnWays().first.$2;
      var doc = CanvasDocument(
          size: const CanvasSize(width: _page, ratio: CanvasRatio.square),
          elements: [turned],
          frames: 48,
          frameRate: 12,
          guides: const CanvasGuides(snapTo: SnapTo(centres: false)));
      var left = _round(_drawnQuad(turned, doc)).left;
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.frame = _midway;
      c.selectOnly("e");
      var stage = await _onStage(tester, c);
      var scale = stage.pageRect.width / _page;
      var quad = _drawnQuad(turned, doc);
      var middle = (quad[0] + quad[2]) / 2;
      var travel = 1.3 - left;
      var g = await tester.startGesture(stage.toStagePoint(middle));
      await tester.pump();
      await g.moveBy(Offset(travel / 2 * scale, 0));
      await tester.pump();
      await g.moveBy(Offset(travel / 2 * scale, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      var now = c.document;
      expect(_round(_drawnQuad(now.elementById("e")!, now)).left,
          closeTo(0, 0.01));
    });

    // Two copies, the second turned: each ringed where it is drawn.
    testWidgets("an element reused has each copy ringed where it is drawn",
        (tester) async {
      var e = ShapeElement(
          const ElementBase(
              id: "e",
              x: 30,
              y: 110,
              width: 60,
              height: 60,
              motion: ElementMotion(
                  instances: InstanceSet(items: [
                ElementInstance("a"),
                ElementInstance("b", dx: 140, own: {"turn": 40}),
              ]))),
          fill: _orange);
      var doc = _pageOf([e]);
      var c = CanvasController(doc);
      addTearDown(c.dispose);
      c.frame = _midway;
      c.selectOnly("e");
      c.pickCopies("e", {"a", "b"});
      await _onStage(tester, c);
      var inputs = _painterOf(tester).inputs;
      var marked = await _marksOf(
          tester,
          (canvas) => paintCopies(
              canvas, inputs.selection, inputs.shown, null, 1, Offset.zero));
      // The rings stand off the copies a little, and each number sits on a
      // tag above the upright box round its copy: only the rings' own
      // pixels are asked about.
      var copies = [
        for (var i in [0, 1]) _drawnQuad(e, doc, instance: i)
      ];
      var rings = [for (var q in copies) _grown(q, 3)];
      var numbers = [
        for (var q in copies)
          Rect.fromLTRB(_round(q).left - 4, _round(q).top - 18,
              _round(q).left + 26, _round(q).top - 3)
      ];
      var ringOnly = [
        for (var i = 0; i < marked.length; i++)
          marked[i] &&
              !numbers.any(
                  (n) => n.contains(Offset(i % _page + 0.5, i ~/ _page + 0.5))),
      ];
      _expectOutlined(ringOnly, rings, near: 3);
    });
  });

  group("align and spread line up what is drawn", () {
    // At rest; moved by a clip, resting where it was; and turned by its keys
    // about its corner, which poses it.
    ShapeElement still() => ShapeElement(
        const ElementBase(id: "a", x: 20, y: 10, width: 40, height: 30),
        fill: _blue);
    ShapeElement clipped() => ShapeElement(
        ElementBase(
            id: "b",
            x: 120,
            y: 200,
            width: 50,
            height: 40,
            motion: _clip(80, 40)),
        fill: _blue);
    var turned = _drawnWays().first.$2;

    CanvasController controllerOf(List<CanvasElement> elements) {
      var c = CanvasController(_pageOf(elements));
      addTearDown(c.dispose);
      c.frame = _midway;
      c.selectOnly("a");
      c.toggleSelected("b");
      c.toggleSelected("e");
      return c;
    }

    Rect drawnOf(CanvasController c, String id) =>
        _round(_drawnQuad(c.document.elementById(id)!, c.document));

    test("align left puts every drawn left side on the leftmost", () {
      var c = controllerOf([still(), clipped(), turned]);
      c.alignSelected(CanvasAlign.left);
      for (var id in ["a", "b", "e"]) {
        expect(drawnOf(c, id).left, closeTo(20, 0.01), reason: id);
      }
      var b = c.document.elementById("b")!;
      expect(c.posesRatherThanMoves(b), isFalse);
      expect(b.track, isNull, reason: "moved where it rests");
      var e = c.document.elementById("e")!;
      expect(e.x, turned.x, reason: "posed where it is, its rest kept");
    });

    test("spread down leaves even gaps between what is drawn", () {
      var c = controllerOf([still(), clipped(), turned]);
      c.spreadSelected(false);
      var boxes = [
        for (var id in ["a", "b", "e"]) drawnOf(c, id)
      ]..sort((x, y) => x.top.compareTo(y.top));
      var first = boxes[1].top - boxes[0].bottom;
      var second = boxes[2].top - boxes[1].bottom;
      expect(first, closeTo(second, 0.01), reason: "$boxes");
    });
  });
}

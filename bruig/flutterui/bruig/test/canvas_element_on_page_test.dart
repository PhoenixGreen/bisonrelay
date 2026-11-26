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
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';

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

/// _dragsWaiting are the drags that wait, with what is wrong.
const _dragsWaiting = <String, String>{
  "sized by its keys, posed":
      "the drag writes the box where it is drawn as the key's move, so the "
          "shift its size makes about its anchor is added again: it jumps on "
          "the first step",
  "moved by a clip, posed":
      "the drag writes where the clip has moved it as the key's move, so "
          "the clip's move is added again: it jumps on the first step",
  "moved by a clip, moved":
      "the drag writes where the clip has moved it as where it rests, so "
          "the clip's move is added again: it jumps on the first step",
};

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
      }, skip: _dragsWaiting.containsKey(name));
    }
  });
}

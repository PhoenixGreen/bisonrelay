import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_image_frame_grow_test.dart is a picture's frame taking in what is
// put past it -- a stroke, a layer -- rather than cutting it off; clipping
// where it is asked to; and its border drawn over the picture.

class _Pictures implements CanvasImageSource {
  final Map<String, ui.Image> images;
  _Pictures(this.images);
  @override
  bool get loading => false;
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      images[assetId];
  @override
  CanvasVector? resolveVector(String assetId) => null;
  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      null;
}

Future<ui.Image> _solid(int w, int h, List<int> rgba) {
  var pixels = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    pixels.setRange(i * 4, i * 4 + 4, rgba);
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// _paintAt is a stroke of red at [points], fractions of the frame.
ImageLayer _paintAt(List<Offset> points, {double radius = 0.05}) =>
    ImageLayer(id: "paint", kind: LayerKind.paint, strokes: [
      StrokeMark(
          kind: StrokeKind.paint,
          points: points,
          radius: radius,
          hardness: 1,
          colour: const Color(0xFFFF0000)),
    ]);

/// _onPage is where [f], a fraction of [e]'s frame, is on the page.
Offset _onPage(ImageElement e, Offset f) {
  var inner = e.box.inner(e.bounds);
  var p =
      Offset(inner.left + f.dx * inner.width, inner.top + f.dy * inner.height);
  if (e.rotation == 0) return p;
  var c = e.bounds.center, t = e.rotation * math.pi / 180;
  var d = p - c;
  return c +
      Offset(d.dx * math.cos(t) - d.dy * math.sin(t),
          d.dx * math.sin(t) + d.dy * math.cos(t));
}

void main() {
  group("the frame", () {
    ImageElement painted({double rotation = 0}) => ImageElement(
            ElementBase(
                id: "i",
                x: 100,
                y: 100,
                width: 200,
                height: 100,
                rotation: rotation),
            assetId: "white",
            fit: ImageFit.stretch,
            layers: [
              ImageLayer.base,
              _paintAt(const [Offset(0.5, 0.5), Offset(1.5, 0.5)]),
            ]);

    test("grows to take in a stroke painted past it, and nothing moves", () {
      var e = painted();
      var end = _onPage(e, const Offset(1.5, 0.5));
      var corner = _onPage(e, Offset.zero);
      var grown = e.grownToFit();
      // A stroke to 1.5 of the way across, and the brush's reach past it.
      expect(grown.width, closeTo(200 * 1.5 + 0.05 * 100, 0.01));
      expect(grown.x, 100);
      var stroke = grown.stack.last.strokes.single;
      expect(
          (_onPage(grown, stroke.points.last) - end).distance, lessThan(0.01));
      expect(stroke.radius * grown.height, closeTo(0.05 * 100, 0.01),
          reason: "the brush the same size on the page");
      var base = grown.stack.first;
      expect(
          layerRect(grown.box.inner(grown.bounds), base.place).topLeft, corner,
          reason: "the base picture where it was");
    });

    test("turned, it grows and everything stays where it was seen", () {
      var e = painted(rotation: 30);
      var end = _onPage(e, const Offset(1.5, 0.5));
      var start = _onPage(e, const Offset(0.5, 0.5));
      var grown = e.grownToFit();
      var points = grown.stack.last.strokes.single.points;
      expect((_onPage(grown, points.first) - start).distance, lessThan(0.01));
      expect((_onPage(grown, points.last) - end).distance, lessThan(0.01));
    });

    test("never shrinks by itself, and fits to its content when asked", () {
      var e = ImageElement(const ElementBase(id: "i", width: 400, height: 400),
          assetId: "white",
          layers: [
            ImageLayer.base
                .copyWith(basePlace: const Rect.fromLTWH(250, 250, 500, 500)),
            ImageLayer.solid(const PaintSpec(Color(0xFF00FF00))),
          ]);
      expect(identical(e.grownToFit(), e), isTrue);
      var fitted = e.fittedToContent();
      expect(fitted.bounds, const Rect.fromLTWH(100, 100, 200, 200));
    });

    test("moved, everything in it goes with it", () {
      // Edges far from round numbers: the frame's size, worked out from its
      // edges, comes out a hair different where it is moved to -- which read
      // as a resize, and left the layers behind on the page.
      var e = ImageElement(
          const ElementBase(
              id: "i",
              x: 374.6223314829666,
              y: 133.4284666657575,
              width: 612.7139758032177,
              height: 349.7104735245903),
          assetId: "white",
          layers: [
            ImageLayer.base.copyWith(
                basePlace: const Rect.fromLTWH(219.56, 527.77, 780.43, 472.22)),
            ImageLayer.picture("white", const Rect.fromLTWH(0, 0, 400, 400)),
          ]);
      var moved = e.withBase(x: e.x + 41.44, y: e.y + 24.11) as ImageElement;
      for (var i = 0; i < e.stack.length; i++) {
        expect(moved.stack[i].place, e.stack[i].place,
            reason: "${e.stack[i].kind} in the same place in the frame");
      }
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.beginInteraction();
      c.replaceElement(moved, transient: true);
      c.endInteraction();
      expect(c.document.elementById("i")!.bounds, moved.bounds,
          reason: "not pulled back and grown round where it was");
    });

    test("does not grow when it clips", () {
      var e = painted().copyWith(clip: true);
      expect(identical(e.grownToFit(), e), isTrue);
    });

    test("an adjustment's mask stays where it was painted", () {
      var mask = const ImageMask(marks: [
        MaskMark(
            kind: MaskMarkKind.brush, points: [Offset(0.5, 0.5)], radius: 0.1),
      ]);
      var e = painted().withLayers([
        ...painted().stack,
        ImageLayer(id: "adj", kind: LayerKind.adjustment, mask: mask),
      ]);
      var at = _onPage(e, const Offset(0.5, 0.5));
      var grown = e.grownToFit();
      var mark = grown.layerById("adj")!.mask.marks.single;
      expect(
          (_onPage(grown, mark.points.single) - at).distance, lessThan(0.01));
    });

    test("an old picture cut to a shape still clips; a plain one does not", () {
      var shaped =
          const ImageElement(ElementBase(id: "a"), frame: ShapeKind.ellipse);
      var old = shaped.toJson()..remove("clip");
      expect((elementFromJson(old) as ImageElement).clip, isTrue);
      var plain = const ImageElement(ElementBase(id: "b")).toJson();
      expect((elementFromJson(plain) as ImageElement).clip, isFalse);
      var unclipped = shaped.copyWith(clip: false);
      expect(
          (elementFromJson(unclipped.toJson()) as ImageElement).clip, isFalse);
    });
  });

  group("drawing", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({
        "white": await _solid(4, 4, [255, 255, 255, 255]),
        "blue": await _solid(4, 4, [0, 0, 255, 255]),
      });
    });

    Future<List<int>> pixel(ImageElement e, int x, int y) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        var i = (y * 100 + x) * 4;
        var p = raw!.buffer.asUint8List();
        return [p[i], p[i + 1], p[i + 2], p[i + 3]];
      } finally {
        image.dispose();
      }
    }

    ImageElement spilling({bool clip = false}) => ImageElement(
            const ElementBase(id: "i", x: 20, y: 20, width: 40, height: 40),
            assetId: "white",
            fit: ImageFit.stretch,
            clip: clip,
            layers: [
              ImageLayer.base,
              // Half of it past the right of the frame.
              ImageLayer.picture(
                  "blue", const Rect.fromLTWH(750, 250, 500, 500)),
            ]);

    test("a layer past the frame is drawn there, unless it clips", () async {
      expect(await pixel(spilling(), 65, 40), [0, 0, 255, 255]);
      expect(await pixel(spilling(clip: true), 65, 40), isNot([0, 0, 255, 255]),
          reason: "cut to the frame");
      expect(await pixel(spilling(clip: true), 55, 40), [0, 0, 255, 255]);
    });

    test("the border is drawn over the picture, with no padding", () async {
      var e = ImageElement(
          const ElementBase(id: "i", x: 20, y: 20, width: 40, height: 40),
          assetId: "blue",
          fit: ImageFit.stretch,
          box: const BoxSpec(
              padding: 0, borderWidth: 4, borderColor: Color(0xFFFF0000)));
      expect(await pixel(e, 21, 40), [255, 0, 0, 255]);
      expect(await pixel(e, 40, 40), [0, 0, 255, 255]);
    });
  });

  testWidgets("a stroke painted out past the frame grows it, in one step",
      (tester) async {
    var key = GlobalKey<CanvasStageState>();
    var c = CanvasController(const CanvasDocument().addElement(ImageElement(
        const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
        assetId: "white",
        fit: ImageFit.stretch)));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(800, 600);
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
          body: SizedBox(
              width: 800,
              height: 600,
              child: CanvasStage(key: key, controller: c)),
        ),
      ),
    ));
    await tester.runAsync(() async {
      c.images.putForTest("white", await _solid(4, 4, [200, 200, 200, 255]));
    });
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    c.selectOnly("i");
    c.editImage("i");
    c.imageTool = ImageTool.paint;
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    var scale = stage.pageRect.width / c.document.size.width;
    Offset screen(Offset p) => stage.pageRect.topLeft + p * scale;

    // From inside the frame out past its right edge...
    await tester.dragFrom(
        screen(const Offset(250, 200)), const Offset(150, 0) * scale);
    await tester.pumpAndSettle();
    var e = c.document.elementById("i") as ImageElement;
    expect(e.width, greaterThan(240), reason: "grown to take the stroke in");
    expect(e.x, 100);
    expect(c.imageEditing, "i", reason: "still painting");

    // ...and from outside it altogether.
    await tester.dragFrom(
        screen(const Offset(150, 380)), const Offset(0, 60) * scale);
    await tester.pumpAndSettle();
    e = c.document.elementById("i") as ImageElement;
    expect(e.height, greaterThan(330));

    c.undo();
    c.undo();
    e = c.document.elementById("i") as ImageElement;
    expect(e.bounds, const Rect.fromLTWH(100, 100, 200, 200),
        reason: "each stroke and its frame one step");
  });
}

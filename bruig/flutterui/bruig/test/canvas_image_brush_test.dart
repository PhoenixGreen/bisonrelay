import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/render/raster_cache.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_image_brush_test.dart is brushwork: paint on a paint layer, and the
// retouching done to a picture -- drawn, and drawn with on the stage.

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

Future<ui.Image> _picture(int w, int h, List<int> Function(int x, int y) f) {
  var pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var p = f(x, y);
      var i = (y * w + x) * 4;
      for (var c = 0; c < 4; c++) {
        pixels[i + c] = p[c];
      }
    }
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

const _box = ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100);

StrokeMark _across(StrokeKind kind,
        {double y = 0.5,
        double strength = 1,
        ui.Color colour = const ui.Color(0xFFFF0000),
        Offset source = Offset.zero}) =>
    StrokeMark(
        kind: kind,
        points: [Offset(0.1, y), Offset(0.9, y)],
        radius: 0.1,
        hardness: 1,
        strength: strength,
        colour: colour,
        source: source);

void main() {
  test("strokes come back as they were saved", () {
    var paint = ImageLayer.painting().copyWith(strokes: [
      const StrokeMark(
          kind: StrokeKind.paint,
          points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
          pressure: [0.5, 1],
          colour: ui.Color(0xFF00FF00),
          strength: 0.5),
    ]);
    var e = ImageElement(_box, assetId: "white", retouch: [
      const StrokeMark(
          kind: StrokeKind.clone,
          points: [Offset(0.5, 0.5)],
          source: Offset(-0.25, 0.1)),
    ], layers: [
      ImageLayer.base,
      paint
    ]);
    var back = elementFromJson(e.toJson()) as ImageElement;
    var s = back.layers[1].strokes.single;
    expect(back.layers[1].kind, LayerKind.paint);
    expect(s.points, paint.strokes.single.points);
    expect(s.pressure, [0.5, 1]);
    expect(s.colour, const ui.Color(0xFF00FF00));
    expect(s.strength, 0.5);
    expect(back.retouch.single.kind, StrokeKind.clone);
    expect(back.retouch.single.source, const Offset(-0.25, 0.1));
  });

  group("drawing", () {
    late _Pictures images;
    setUpAll(() async {
      images = _Pictures({
        "white": await _picture(10, 10, (x, y) => [255, 255, 255, 255]),
        "grey": await _picture(20, 20, (x, y) => [100, 100, 100, 255]),
        "halves": await _picture(
            20, 20, (x, y) => x < 10 ? [255, 0, 0, 255] : [0, 0, 255, 255]),
        "ramp": await _picture(40, 40, (x, y) {
          // Dark grey to light over four pixels: an edge, a little soft.
          var v = (60 + (x - 18) / 4 * 140).clamp(60, 200).round();
          return [v, v, v, 255];
        }),
        "spot": await _picture(40, 40, (x, y) {
          var d = (Offset(x + 0.5, y + 0.5) - const Offset(20, 20)).distance;
          return d < 3 ? [0, 0, 0, 255] : [100, 160, 100, 255];
        }),
      });
    });

    Future<Uint8List> render(ImageElement e) async {
      var document = CanvasDocument(
          size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
          elements: [e]);
      var image = await renderFrame(document, images: images);
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        return raw!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    List<int> at(Uint8List p, int x, int y) {
      var i = (y * 100 + x) * 4;
      return [p[i], p[i + 1], p[i + 2]];
    }

    ImageElement painted(List<StrokeMark> strokes, {String id = "i"}) =>
        ImageElement(ElementBase(id: id, x: 0, y: 0, width: 100, height: 100),
            assetId: "white",
            fit: ImageFit.stretch,
            layers: [
              ImageLayer.base,
              ImageLayer(id: "paint", kind: LayerKind.paint, strokes: strokes),
            ]);

    test("a brush's tip and the pen's lean come back as they were saved", () {
      const tip = BrushTip(
          roundness: 0.2,
          angle: 30,
          followTilt: true,
          spacing: 0.1,
          scatter: 0.4,
          grain: 0.5,
          pressureSize: 0.3,
          pressureOpacity: 0.6,
          pressureCurve: 1.5,
          tiltSize: 1);
      var s = const StrokeMark(
          kind: StrokeKind.paint,
          points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
          tip: tip,
          tilt: [Offset(0.5, -0.25), Offset(0.25, 0)]);
      var back = StrokeMark.fromJson(s.toJson());
      expect(back.tip, tip);
      expect(back.tilt, s.tilt);
      // And a stroke from before there were tips is the round brush.
      expect(StrokeMark.fromJson(_across(StrokeKind.paint).toJson()).tip,
          const BrushTip());
    });

    // Ten pixels either side of the line at y = 50 for a round brush; how far
    // the paint reaches up from it tells a round tip from a flat one.
    int reachUp(Uint8List p) {
      var up = 0;
      for (var y = 50; y >= 30; y--) {
        if (at(p, 50, y)[1] < 128) up = 50 - y;
      }
      return up;
    }

    StrokeMark tipped(BrushTip tip,
            {List<Offset> tilt = const [], List<double> pressure = const []}) =>
        StrokeMark(
            kind: StrokeKind.paint,
            points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            pressure: pressure,
            radius: 0.1,
            hardness: 1,
            colour: const ui.Color(0xFFFF0000),
            tip: tip,
            tilt: tilt);

    test("a flat nib lying along the line is thin across it", () async {
      var round = reachUp(await render(painted([tipped(const BrushTip())])));
      var flat = reachUp(await render(
          painted([tipped(const BrushTip(roundness: 0.2, spacing: 0.1))])));
      expect(round, greaterThanOrEqualTo(8));
      expect(flat, lessThanOrEqualTo(3), reason: "a fifth as tall: $flat");
    });

    test("a nib that follows the pen turns as the pen leans", () async {
      const nib = BrushTip(roundness: 0.2, spacing: 0.1, followTilt: true);
      // Leaning across: the nib stands upright, broad across the line.
      var leaning = reachUp(await render(painted([
        tipped(nib, tilt: const [Offset(1, 0), Offset(1, 0)])
      ])));
      // Upright, with no lean to follow, it lies at its own angle.
      var upright = reachUp(await render(painted([tipped(nib)])));
      expect(leaning, greaterThanOrEqualTo(8));
      expect(upright, lessThanOrEqualTo(3));
    });

    test("grain leaves gaps in the paint", () async {
      int red(Uint8List p) {
        var n = 0;
        for (var x = 15; x < 85; x++) {
          for (var y = 42; y < 58; y++) {
            if (at(p, x, y)[1] < 128) n++;
          }
        }
        return n;
      }

      var solid = red(await render(painted([tipped(const BrushTip())])));
      var grainy = red(await render(
          painted([tipped(const BrushTip(grain: 0.9, spacing: 0.6))])));
      expect(grainy, lessThan(solid * 0.9), reason: "$grainy of $solid");
    });

    test("a light touch fades the paint where the brush says so", () async {
      var firm = await render(painted([
        tipped(const BrushTip(pressureSize: 0, pressureOpacity: 1),
            pressure: const [1, 1])
      ]));
      var light = await render(painted([
        tipped(const BrushTip(pressureSize: 0, pressureOpacity: 1),
            pressure: const [0.3, 0.3])
      ]));
      expect(at(firm, 50, 50), [255, 0, 0]);
      expect(at(light, 50, 50)[1], greaterThan(60),
          reason: "lighter, the white showing through");
    });

    test("paint lies where it was painted", () async {
      var p = await render(painted([_across(StrokeKind.paint)]));
      expect(at(p, 50, 50), [255, 0, 0]);
      expect(at(p, 50, 20), [255, 255, 255]);
    });

    test("the eraser takes paint off, and nothing under it", () async {
      var p = await render(painted([
        _across(StrokeKind.paint),
        const StrokeMark(
            kind: StrokeKind.erase,
            points: [Offset(0.5, 0.3), Offset(0.5, 0.7)],
            radius: 0.1,
            hardness: 1),
      ]));
      expect(at(p, 50, 50), [255, 255, 255], reason: "the picture shows");
      expect(at(p, 20, 50), [255, 0, 0], reason: "and the rest of the paint");
    });

    test("strength is how much one stroke lays down", () async {
      var p = await render(painted([_across(StrokeKind.paint, strength: 0.5)]));
      expect(at(p, 50, 50)[1], closeTo(128, 4));
    });

    test("strokes drawn on to a long list draw what a fresh one would",
        () async {
      // The strokes before the last are kept flattened from frame to frame;
      // a pile grown one at a time must come out as the whole pile does.
      var strokes = [
        for (var i = 0; i < 30; i++)
          _across(StrokeKind.paint,
              y: 0.05 + i * 0.03,
              colour: ui.Color.fromARGB(255, i * 8, 255 - i * 8, 100))
      ];
      for (var n = 1; n <= strokes.length; n++) {
        await render(painted(strokes.sublist(0, n)));
      }
      var grown = await render(painted(strokes));
      var fresh = await render(painted(strokes, id: "fresh"));
      // Flattened, the older strokes are drawn from pixels a little finer
      // than the canvas: an edge may differ by a few levels, nothing more.
      var worst = 0;
      for (var i = 0; i < grown.length; i++) {
        var d = (grown[i] - fresh[i]).abs();
        if (d > worst) worst = d;
      }
      expect(worst, lessThan(48));
      var off = 0;
      for (var i = 0; i < grown.length; i++) {
        if ((grown[i] - fresh[i]).abs() > 6) off++;
      }
      expect(off / grown.length, lessThan(0.01));
    });

    ImageElement retouched(String asset, List<StrokeMark> marks) =>
        ImageElement(_box,
            assetId: asset, fit: ImageFit.stretch, retouch: marks);

    test("clone copies from where its source is", () async {
      // Over the blue right half, copying from half the picture to the left.
      var p = await render(retouched("halves", [
        const StrokeMark(
            kind: StrokeKind.clone,
            points: [Offset(0.75, 0.3), Offset(0.75, 0.7)],
            radius: 0.1,
            hardness: 1,
            source: Offset(-0.5, 0)),
      ]));
      expect(at(p, 75, 50), [255, 0, 0]);
      expect(at(p, 90, 50), [0, 0, 255], reason: "only where it went");
    });

    test("retouching on a paint layer works on every layer under it", () async {
      // Green painted on the left, on a layer of its own over the picture;
      // a clone on a second paint layer copies it to the right.
      var e =
          ImageElement(_box, assetId: "white", fit: ImageFit.stretch, layers: [
        ImageLayer.base,
        ImageLayer(id: "paint", kind: LayerKind.paint, strokes: [
          StrokeMark(
              kind: StrokeKind.paint,
              points: const [Offset(0.1, 0.3), Offset(0.4, 0.3)],
              radius: 0.08,
              hardness: 1,
              colour: const ui.Color(0xFF00FF00)),
        ]),
        ImageLayer(id: "retouch", kind: LayerKind.paint, strokes: [
          const StrokeMark(
              kind: StrokeKind.clone,
              points: [Offset(0.6, 0.3), Offset(0.9, 0.3)],
              radius: 0.08,
              hardness: 1,
              source: Offset(-0.5, 0)),
        ]),
      ]);
      var p = await render(e);
      expect(at(p, 25, 30), [0, 255, 0]);
      expect(at(p, 75, 30), [0, 255, 0], reason: "copied from the layer under");
      expect(at(p, 75, 70), [255, 255, 255], reason: "only where it went");
    });

    test("a drift loop pans across the picture the length of the scene",
        () async {
      // Red on the left half, blue on the right, held twice as close: the
      // middle of the frame is red at the start and blue by the end.
      var e = ImageElement(_box,
          assetId: "halves",
          fit: ImageFit.cover,
          animation: ElementAnimation(
              loop: ElementLoop(
                  preset: LoopPreset.driftRight,
                  strength: 1 / driftPerStrength)));
      Future<List<int>> middleAt(int frame) async {
        var document = CanvasDocument(
            size: const CanvasSize(width: 100, ratio: CanvasRatio.square),
            frames: 11,
            elements: [e]);
        var image = await renderFrame(document, images: images, frame: frame);
        try {
          var raw = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba);
          return at(raw!.buffer.asUint8List(), 50, 50);
        } finally {
          image.dispose();
        }
      }

      expect(await middleAt(0), [255, 0, 0]);
      expect(await middleAt(10), [0, 0, 255]);
      var back = elementFromJson(e.toJson()) as ImageElement;
      expect(back.animation.loop.preset, LoopPreset.driftRight);
    });

    test("a zoom drift starts where the framing is and closes in", () {
      const framing = ImageFraming(x: 0.3, zoom: 1.5);
      expect(driftedFraming(framing, LoopPreset.driftIn, 0.2, 0).zoom, 1.5);
      expect(driftedFraming(framing, LoopPreset.driftIn, 0.2, 1).zoom,
          closeTo(1.8, 1e-9));
      expect(driftedFraming(framing, LoopPreset.driftIn, 0.2, 1).x, 0.3);
      expect(
          driftedFraming(const ImageFraming(), LoopPreset.driftOut, 0.2, 1)
              .zoom,
          1);
    });

    test("a drift goes once across its span, and holds at the end", () {
      const loop = ElementLoop(preset: LoopPreset.driftIn, from: 10, to: 20);
      expect(loop.driftAt(0, last: 99), 0);
      expect(loop.driftAt(15, last: 99), closeTo(0.5, 1e-9));
      expect(loop.driftAt(60, last: 99), 1);
      expect(loop.phaseAt(15, last: 99), isNull,
          reason: "it does not go round");
    });

    test("a picture saved with a drift of its own comes back with the loop",
        () {
      var json = const ImageElement(_box, assetId: "halves").toJson()
        ..["drift"] = {"kind": "panLeft", "amount": 0.3};
      var back = elementFromJson(json) as ImageElement;
      expect(back.animation.loop.preset, LoopPreset.driftLeft);
      expect(back.animation.loop.strength, closeTo(2, 1e-9));
    });

    test("strokes kept as pixels draw what drawing them all afresh does",
        () async {
      var picture = images.images["halves"]!;
      const size = Size(20, 20);
      var marks = [
        _across(StrokeKind.blur, y: 0.2),
        _across(StrokeKind.dodge, y: 0.45),
        _across(StrokeKind.clone, y: 0.7, source: const Offset(0.3, 0)),
        _across(StrokeKind.blur, y: 0.85),
      ];
      Future<Uint8List> draw(void Function(Canvas) paint) async {
        var recorder = ui.PictureRecorder();
        var canvas = Canvas(recorder);
        canvas.drawImage(picture, Offset.zero, Paint());
        paint(canvas);
        var image = await recorder.endRecording().toImage(20, 20);
        try {
          return (await image.toByteData(
                  format: ui.ImageByteFormat.rawStraightRgba))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }

      var fresh =
          await draw((c) => paintRetouch(c, picture, size, marks, null));
      var drawn = RasterCache.instance.drawn;
      var kept =
          await draw((c) => paintRetouchKept(c, picture, size, marks, null));
      expect(RasterCache.instance.drawn, drawn + 1);
      var worst = 0;
      for (var i = 0; i < fresh.length; i++) {
        worst = math.max(worst, (fresh[i] - kept[i]).abs());
      }
      expect(worst, lessThan(6));

      // The next stroke grows: the ones before it are not drawn again.
      var grown = [
        ...marks.sublist(0, 3),
        marks.last.copyWith(points: [
          ...marks.last.points,
          const Offset(0.95, 0.9),
        ])
      ];
      await draw((c) => paintRetouchKept(c, picture, size, grown, null));
      expect(RasterCache.instance.drawn, drawn + 1);
    });

    test("the base picture flipped is drawn mirrored", () async {
      ImageElement halves({bool flip = false}) => ImageElement(_box,
          assetId: "halves",
          fit: ImageFit.stretch,
          layers: [ImageLayer.base.copyWith(flipX: flip)]);
      var plain = await render(halves());
      expect(at(plain, 20, 50), [255, 0, 0]);
      var flipped = await render(halves(flip: true));
      expect(at(flipped, 20, 50), [0, 0, 255], reason: "blue on the left now");
      expect(at(flipped, 80, 50), [255, 0, 0]);
    });

    test("a picture with layers is cropped, not zoomed", () async {
      // Red on the left half, blue on the right, under an empty paint layer.
      ImageElement halves({bool flip = false}) =>
          ImageElement(_box, assetId: "halves", fit: ImageFit.stretch, layers: [
            ImageLayer.base.copyWith(flipX: flip),
            const ImageLayer(id: "paint", kind: LayerKind.paint),
          ]);
      bool red(List<int> p) => p[0] > 200 && p[2] < 60;
      bool blue(List<int> p) => p[2] > 200 && p[0] < 60;

      // The left half of the picture cropped off: the blue stays where it
      // was, and the red is gone -- not the blue blown up to fill the frame.
      var cropped = halves().croppedTo(const ImageCrop(left: 0.5, right: 1));
      expect(cropped.bounds, halves().bounds, reason: "the frame stays");
      var p = await render(cropped);
      expect(blue(at(p, 75, 50)), isTrue);
      expect(blue(at(p, 25, 50)) || red(at(p, 25, 50)), isFalse,
          reason: "nothing where the red was: ${at(p, 25, 50)}");

      // Flipped, the picture's left -- the red -- is on the right.
      var flipped = await render(
          halves(flip: true).croppedTo(const ImageCrop(left: 0.5, right: 1)));
      expect(blue(at(flipped, 25, 50)), isTrue);
      expect(blue(at(flipped, 75, 50)) || red(at(flipped, 75, 50)), isFalse);
    });

    test("spot heal fills the spot with what is round it", () async {
      var plain = await render(retouched("spot", const []));
      expect(at(plain, 50, 50)[1], lessThan(30));
      var p = await render(retouched("spot", [
        const StrokeMark(
            kind: StrokeKind.heal,
            points: [Offset(0.5, 0.5)],
            radius: 0.12,
            hardness: 0.8),
      ]));
      var healed = at(p, 50, 50);
      expect(healed[1], closeTo(160, 25), reason: "$healed");
      expect(healed[0], closeTo(100, 25));
    });

    test("dodge lightens and burn darkens", () async {
      var light = await render(retouched("grey", [_across(StrokeKind.dodge)]));
      var dark = await render(retouched("grey", [_across(StrokeKind.burn)]));
      expect(at(light, 50, 50)[0], greaterThan(150));
      expect(at(dark, 50, 50)[0], lessThan(70));
      expect(at(light, 50, 15)[0], closeTo(100, 3), reason: "only on the way");
    });

    test("sharpening pushes an edge apart, and leaves flat alone", () async {
      // A ramp from dark grey to light: an unsharp mask works at its bends,
      // darkening the foot and lightening the shoulder.
      var p = await render(retouched("ramp", [
        const StrokeMark(
            kind: StrokeKind.sharpen,
            points: [Offset(0.5, 0.1), Offset(0.5, 0.9)],
            radius: 0.45,
            hardness: 1),
      ]));
      var plain = await render(retouched("ramp", const []));
      expect(at(p, 44, 50)[0], lessThan(at(plain, 44, 50)[0] - 3),
          reason: "the foot darker");
      expect(at(p, 56, 50)[0], greaterThan(at(plain, 56, 50)[0] + 3),
          reason: "the shoulder lighter");
      var flat = await render(retouched("grey", [
        const StrokeMark(
            kind: StrokeKind.sharpen,
            points: [Offset(0.5, 0.5)],
            radius: 0.3,
            hardness: 1),
      ]));
      expect(at(flat, 50, 50)[0], closeTo(100, 3));
    });

    test("smudging carries a colour along the stroke", () async {
      // Dragged from the red half into the blue.
      var p = await render(retouched("halves", [
        const StrokeMark(
            kind: StrokeKind.smudge,
            points: [Offset(0.3, 0.5), Offset(0.7, 0.5)],
            radius: 0.12,
            hardness: 0.6),
      ]));
      var carried = at(p, 62, 50);
      expect(carried[0], greaterThan(60), reason: "red in the blue: $carried");
      expect(at(p, 62, 15)[0], lessThan(10), reason: "only where it went");
    });

    test("the blur brush softens an edge", () async {
      var p = await render(retouched("halves", [
        const StrokeMark(
            kind: StrokeKind.blur,
            points: [Offset(0.5, 0.2), Offset(0.5, 0.8)],
            radius: 0.15,
            hardness: 1),
      ]));
      var edge = at(p, 48, 50);
      expect(edge[0], lessThan(240));
      expect(edge[2], greaterThan(15));
    });
  });

  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> open(
        WidgetTester tester, ImageTool tool,
        {String asset = "white"}) async {
      var key = GlobalKey<CanvasStageState>();
      var c = CanvasController(const CanvasDocument().addElement(ImageElement(
          const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
          assetId: asset,
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
        c.images.putForTest(
            asset, await _picture(40, 40, (x, y) => [200, 200, 200, 255]));
      });
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      c.selectOnly("i");
      c.editImage("i");
      c.imageTool = tool;
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      return (c, (Offset p) => stage.pageRect.topLeft + p * scale);
    }

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    testWidgets("painting on a picture makes a paint layer for it",
        (tester) async {
      var (c, screen) = await open(tester, ImageTool.paint);
      await tester.dragFrom(
          screen(const Offset(150, 200)), const Offset(60, 0));
      await tester.pumpAndSettle();
      var paint = now(c).stack.last;
      expect(paint.kind, LayerKind.paint);
      expect(c.imageLayer, paint.id);
      expect(paint.strokes.single.kind, StrokeKind.paint);
      expect(paint.strokes.single.points.first.dx, closeTo(0.25, 0.02));
      expect(paint.strokes.single.colour, c.paintColour);

      c.undo();
      expect(now(c).stack, hasLength(1),
          reason: "the layer and the stroke are one step");
    });

    testWidgets("Option paints with the eraser", (tester) async {
      var (c, screen) = await open(tester, ImageTool.paint);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(
          screen(const Offset(150, 200)), const Offset(60, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(now(c).stack.last.strokes.single.kind, StrokeKind.erase);
    });

    testWidgets("clone wants a source, then keeps its distance from it",
        (tester) async {
      var (c, screen) = await open(tester, ImageTool.clone);
      await tester.dragFrom(
          screen(const Offset(250, 200)), const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(now(c).retouch, isEmpty);
      expect(c.maskNote, contains("Option-click"));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(screen(const Offset(150, 200)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(c.cloneFrom!.dx, closeTo(0.25, 0.02));

      await tester.dragFrom(
          screen(const Offset(250, 200)), const Offset(20, 0));
      await tester.pumpAndSettle();
      await tester.dragFrom(
          screen(const Offset(250, 250)), const Offset(20, 0));
      await tester.pumpAndSettle();
      var marks = now(c).retouch;
      expect(marks, hasLength(2));
      expect(marks[0].source.dx, closeTo(-0.5, 0.03));
      expect(marks[1].source, marks[0].source, reason: "aligned");

      // Escape deselects the point, then puts the tool down, and only then
      // closes the picture.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.cloneFrom, isNull);
      expect(c.imageEditing, "i");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.imageTool, ImageTool.move);
      expect(c.imageEditing, "i");
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.imageEditing, isNull);
    });

    testWidgets("cloning every layer goes on a Retouch layer of the frame",
        (tester) async {
      var (c, screen) = await open(tester, ImageTool.clone);
      c.retouchWholeFrame = true;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(screen(const Offset(150, 200)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(c.cloneFrom!.dx, closeTo(0.25, 0.02));

      await tester.dragFrom(
          screen(const Offset(250, 200)), const Offset(20, 0));
      await tester.pumpAndSettle();
      var layer = now(c).stack.last;
      expect(layer.kind, LayerKind.paint);
      expect(layer.name, "Retouch");
      expect(c.imageLayer, layer.id);
      expect(layer.strokes.single.kind, StrokeKind.clone);
      expect(layer.strokes.single.points.first.dx, closeTo(0.75, 0.02));
      expect(layer.strokes.single.source.dx, closeTo(-0.5, 0.03));
      expect(now(c).retouch, isEmpty, reason: "not the picture's own");

      // The next stroke goes on the same layer.
      await tester.dragFrom(
          screen(const Offset(250, 250)), const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(now(c).stack, hasLength(2));
      expect(now(c).stack.last.strokes, hasLength(2));

      c.undo();
      c.undo();
      expect(now(c).stack, hasLength(1),
          reason: "the layer and its first stroke are one step");
    });

    testWidgets("the brush's ring stays under the pointer through a stroke",
        (tester) async {
      var (c, screen) = await open(tester, ImageTool.brush);
      Offset? ring() {
        for (var w
            in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
          if (w.painter case StagePainter p) {
            if (p.editingLayers?.ring case (var at, _)) return at;
          }
        }
        return null;
      }

      var g = await tester.startGesture(screen(const Offset(150, 200)));
      await tester.pump();
      await g.moveTo(screen(const Offset(200, 220)));
      await tester.pump();
      await g.moveTo(screen(const Offset(240, 240)));
      await tester.pump();
      var at = ring();
      expect(at, isNotNull);
      expect((at! - const Offset(240, 240)).distance, lessThan(1),
          reason: "where the pointer is, not where the stroke began");
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets("Option turns dodging into burning", (tester) async {
      var (c, screen) = await open(tester, ImageTool.dodge);
      await tester.dragFrom(
          screen(const Offset(150, 200)), const Offset(30, 0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(
          screen(const Offset(150, 250)), const Offset(30, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect([for (var m in now(c).retouch) m.kind],
          [StrokeKind.dodge, StrokeKind.burn]);
    });

    testWidgets("the tools' keys", (tester) async {
      var (c, _) = await open(tester, ImageTool.move);
      for (var (key, tool) in const [
        (LogicalKeyboardKey.keyP, ImageTool.paint),
        (LogicalKeyboardKey.keyE, ImageTool.erase),
        (LogicalKeyboardKey.keyS, ImageTool.clone),
        (LogicalKeyboardKey.keyJ, ImageTool.heal),
        (LogicalKeyboardKey.keyO, ImageTool.dodge),
        (LogicalKeyboardKey.keyU, ImageTool.soften),
        (LogicalKeyboardKey.keyY, ImageTool.sharpen),
        (LogicalKeyboardKey.keyM, ImageTool.smudge),
      ]) {
        await tester.sendKeyEvent(key);
        expect(c.imageTool, tool);
      }
      var size = c.paintSize;
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      expect(c.paintSize, greaterThan(size));
    });
  });

  testWidgets("a paint layer's strokes are taken back from the panel",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var layer = ImageLayer(id: "paint", kind: LayerKind.paint, strokes: [
      _across(StrokeKind.paint),
      _across(StrokeKind.paint, y: 0.2)
    ]);
    var c = CanvasController(const CanvasDocument().addElement(ImageElement(
        _box,
        assetId: "white",
        layers: [ImageLayer.base, layer])));
    addTearDown(c.dispose);
    c.selectOnly("i");
    c.editImage("i", layer: "paint");
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 420, child: CanvasDesignPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    var undo = find.byKey(const ValueKey("strokesUndo-Paint"));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    ImageLayer paint() => (c.document.elementById("i")! as ImageElement)
        .stack
        .firstWhere((l) => l.id == "paint");
    expect(paint().strokes, hasLength(1));
    await tester.tap(find.byKey(const ValueKey("strokesClear-Paint")));
    await tester.pumpAndSettle();
    expect(paint().strokes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

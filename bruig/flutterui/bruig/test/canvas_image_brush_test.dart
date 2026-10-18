import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/render/image_silhouette.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
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
    var e = ImageElement(_box,
        assetId: "white",
        retouch: [
          const StrokeMark(
              kind: StrokeKind.clone,
              points: [Offset(0.5, 0.5)],
              source: Offset(-0.25, 0.1)),
        ],
        layers: [ImageLayer.base, paint]);
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

    test("a brush's tip and the pen's lean come back as they were saved",
        () {
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
      var flat = reachUp(await render(painted(
          [tipped(const BrushTip(roundness: 0.2, spacing: 0.1))])));
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
      var grainy = red(await render(painted([
        tipped(const BrushTip(grain: 0.9, spacing: 0.6))
      ])));
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
        WidgetTester tester, ImageTool tool, {String asset = "white"}) async {
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
          ChangeNotifierProvider<SnackBarModel>(
              create: (c) => SnackBarModel()),
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
      await tester.dragFrom(screen(const Offset(150, 200)), const Offset(60, 0));
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
      await tester.dragFrom(screen(const Offset(150, 200)), const Offset(60, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(now(c).stack.last.strokes.single.kind, StrokeKind.erase);
    });

    testWidgets("clone wants a source, then keeps its distance from it",
        (tester) async {
      var (c, screen) = await open(tester, ImageTool.clone);
      await tester.dragFrom(screen(const Offset(250, 200)), const Offset(20, 0));
      await tester.pumpAndSettle();
      expect(now(c).retouch, isEmpty);
      expect(c.maskNote, contains("Option-click"));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(screen(const Offset(150, 200)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(c.cloneFrom!.dx, closeTo(0.25, 0.02));

      await tester.dragFrom(screen(const Offset(250, 200)), const Offset(20, 0));
      await tester.pumpAndSettle();
      await tester.dragFrom(screen(const Offset(250, 250)), const Offset(20, 0));
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

    testWidgets("Option turns dodging into burning", (tester) async {
      var (c, screen) = await open(tester, ImageTool.dodge);
      await tester.dragFrom(screen(const Offset(150, 200)), const Offset(30, 0));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(screen(const Offset(150, 250)), const Offset(30, 0));
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
    var layer = ImageLayer(
        id: "paint",
        kind: LayerKind.paint,
        strokes: [_across(StrokeKind.paint), _across(StrokeKind.paint, y: 0.2)]);
    var c = CanvasController(const CanvasDocument().addElement(
        ImageElement(_box, assetId: "white", layers: [ImageLayer.base, layer])));
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

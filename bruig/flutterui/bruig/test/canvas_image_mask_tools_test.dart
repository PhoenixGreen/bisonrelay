import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_masking.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_image_mask_tools_test.dart is the mask tools used as they are used:
// strokes, lassos and fades dragged across a picture on the stage, a subject
// clicked, and the mask's own settings in the panel.

const _viewport = Size(800, 600);
const _asset = "picturepicture01";

Future<ui.Image> _solid(int w, int h) {
  var pixels = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    pixels[i * 4] = 200;
    pixels[i * 4 + 3] = 255;
  }
  var done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

ImageElement _picture({List<ImageLayer> layers = const []}) => ImageElement(
      const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
      assetId: _asset,
      fit: ImageFit.stretch,
      layers: layers,
    );

void main() {
  group("on the stage", () {
    Future<(CanvasController, Offset Function(Offset))> open(
        WidgetTester tester, ImageElement e,
        {String layer = baseLayerId, required ImageTool tool}) async {
      var key = GlobalKey<CanvasStageState>();
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      tester.view.physicalSize = _viewport;
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
              width: _viewport.width,
              height: _viewport.height,
              child: CanvasStage(key: key, controller: c),
            ),
          ),
        ),
      ));
      await tester.runAsync(() async {
        c.images.putForTest(_asset, await _solid(40, 40));
      });
      // A click off the page first, so the keys come to the canvas.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      c.selectOnly("i");
      c.editImage("i", layer: layer);
      c.imageTool = tool;
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      return (c, (Offset p) => stage.pageRect.topLeft + p * scale);
    }

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    testWidgets("a brush stroke is a mark, made as one step", (tester) async {
      var (c, screen) = await open(tester, _picture(), tool: ImageTool.brush);
      var g = await tester.startGesture(screen(const Offset(120, 200)));
      for (var x = 130; x <= 280; x += 10) {
        await g.moveTo(screen(Offset(x.toDouble(), 200)));
      }
      await g.up();
      await tester.pumpAndSettle();

      var marks = now(c).mask.marks;
      expect(marks, hasLength(1));
      expect(marks.single.kind, MaskMarkKind.brush);
      expect(marks.single.hide, isTrue);
      expect(marks.single.points.length, greaterThan(5));
      expect(marks.single.points.first.dx, closeTo(0.1, 0.02));
      expect(marks.single.points.first.dy, closeTo(0.5, 0.02));
      expect(marks.single.radius, c.maskBrushSize);

      c.undo();
      expect(now(c).mask.marks, isEmpty, reason: "one undo step");
    });

    testWidgets("Option turns the brush over for the one stroke",
        (tester) async {
      var (c, screen) = await open(tester, _picture(), tool: ImageTool.brush);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(screen(const Offset(150, 150)), const Offset(60, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(now(c).mask.marks.single.hide, isFalse, reason: "put back");
      expect(c.maskHide, isTrue, reason: "and only for that stroke");
    });

    testWidgets("a lasso keeps the line drawn round", (tester) async {
      var (c, screen) = await open(tester, _picture(), tool: ImageTool.lasso);
      var g = await tester.startGesture(screen(const Offset(120, 120)));
      for (var p in const [
        Offset(200, 120),
        Offset(200, 200),
        Offset(120, 200),
      ]) {
        await g.moveTo(screen(p));
      }
      await g.up();
      await tester.pumpAndSettle();
      var mark = now(c).mask.marks.single;
      expect(mark.kind, MaskMarkKind.lasso);
      expect(mark.points.length, greaterThanOrEqualTo(4));
    });

    testWidgets("a gradient runs from the press to the release",
        (tester) async {
      var (c, screen) = await open(tester, _picture(), tool: ImageTool.fade);
      c.maskRadial = true;
      await tester.dragFrom(screen(const Offset(200, 200)), const Offset(80, 0));
      await tester.pumpAndSettle();
      var mark = now(c).mask.marks.single;
      expect(mark.kind, MaskMarkKind.fade);
      expect(mark.radial, isTrue);
      expect(mark.points, hasLength(2));
      expect(mark.points.first.dx, closeTo(0.5, 0.02));
      expect(mark.points.last.dx, greaterThan(0.6));
    });

    testWidgets("a mark on a flipped layer lands where it was drawn",
        (tester) async {
      // A layer over the left half, flipped: its picture's right side is on
      // the canvas's left.
      var layer =
          ImageLayer.picture(_asset, const Rect.fromLTWH(0, 0, 500, 1000))
              .copyWith(flipX: true);
      var (c, screen) = await open(tester, _picture(layers: [ImageLayer.base, layer]),
          layer: layer.id, tool: ImageTool.lasso);
      // Round the left quarter of the picture element.
      var g = await tester.startGesture(screen(const Offset(102, 110)));
      for (var p in const [Offset(140, 110), Offset(140, 290), Offset(102, 290)]) {
        await g.moveTo(screen(p));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(now(c).mask.marks, isEmpty, reason: "not on the base");
      var mark = now(c).layerById(layer.id)!.look!.mask.marks.single;
      expect(mark.points.first.dx, greaterThan(0.9),
          reason: "the layer's picture is mirrored, so its right edge");
    });

    testWidgets("X turns the tools over and the brackets size the brush",
        (tester) async {
      var (c, _) = await open(tester, _picture(), tool: ImageTool.brush);
      var size = c.maskBrushSize;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(c.maskHide, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      expect(c.maskBrushSize, greaterThan(size));
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      expect(c.maskBrushSize, closeTo(size, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      expect(c.imageTool, ImageTool.lasso);
    });

    testWidgets("a click with Select subject keeps the subject found there",
        (tester) async {
      var root = Directory.systemTemp.createTempSync("mask_subject");
      addTearDown(() => root.deleteSync(recursive: true));
      CanvasStorage.rootOverride = root.path;
      addTearDown(() => CanvasStorage.rootOverride = null);
      // The picture's file, for the finder to be pointed at.
      var pictures =
          Directory(path.join(root.path, "Canvas", "Pictures"))..createSync(recursive: true);
      File(path.join(pictures.path, _asset)).writeAsBytesSync([1, 2, 3]);

      late Uint8List found;
      await tester.runAsync(() async {
        found = (await maskPng(const Size(40, 40), (canvas) {
          canvas.drawRect(const Rect.fromLTWH(0, 0, 20, 40),
              Paint()..color = const Color(0xFFFFFFFF));
        }))!;
      });
      Object? asked;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel("bruig/vision"), (call) async {
        if (call.method == "available") return true;
        asked = call.arguments;
        return {"instances": 1, "mask": found, "width": 40, "height": 40};
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel("bruig/vision"), null));

      var (c, screen) =
          await open(tester, _picture(), tool: ImageTool.subject);
      await tester.tapAt(screen(const Offset(150, 250)));
      // Real files on the way: each step of the chain needs the real loop
      // turned and the fake one drained.
      for (var i = 0; i < 60 && now(c).mask.subject.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect((asked as Map)["x"], closeTo(0.25, 0.02));
      expect((asked as Map)["y"], closeTo(0.75, 0.02));
      var subject = now(c).mask.subject;
      expect(subject, endsWith(".mask"));
      expect(File(path.join(pictures.path, subject)).existsSync(), isTrue);
      expect(c.maskBusy, isNull);
    });
  });

  group("tools that cut", () {
    Future<(CanvasController, Offset Function(Offset))> openWithFiles(
        WidgetTester tester, ImageElement e, ImageTool tool) async {
      var root = Directory.systemTemp.createTempSync("mask_cut");
      addTearDown(() => root.deleteSync(recursive: true));
      CanvasStorage.rootOverride = root.path;
      addTearDown(() => CanvasStorage.rootOverride = null);
      var key = GlobalKey<CanvasStageState>();
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      tester.view.physicalSize = _viewport;
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
              width: _viewport.width,
              height: _viewport.height,
              child: CanvasStage(key: key, controller: c),
            ),
          ),
        ),
      ));
      // A red disc on blue: a subject with an edge to find.
      await tester.runAsync(() async {
        var pixels = Uint8List(80 * 80 * 4);
        for (var y = 0; y < 80; y++) {
          for (var x = 0; x < 80; x++) {
            var i = (y * 80 + x) * 4;
            var inDisc = (Offset(x + 0.5, y + 0.5) - const Offset(40, 40))
                    .distance <
                20;
            pixels[i] = inDisc ? 210 : 30;
            pixels[i + 1] = 40;
            pixels[i + 2] = inDisc ? 40 : 200;
            pixels[i + 3] = 255;
          }
        }
        var done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            pixels, 80, 80, ui.PixelFormat.rgba8888, done.complete);
        c.images.putForTest(_asset, await done.future);
      });
      c.selectOnly("i");
      c.editImage("i");
      c.imageTool = tool;
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      return (c, (Offset p) => stage.pageRect.topLeft + p * scale);
    }

    Future<void> settle(WidgetTester tester, CanvasController c) async {
      // Real work off the main thread and real files: each step needs the
      // real loop turned and the fake one drained.
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        if (c.maskBusy == null && i > 3) break;
      }
      await tester.pumpAndSettle();
    }

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    testWidgets("a quick-select stroke keeps the subject it went over",
        (tester) async {
      var (c, screen) = await openWithFiles(tester, _picture(), ImageTool.quick);
      await tester.dragFrom(
          screen(const Offset(190, 200)), const Offset(20, 0));
      await settle(tester, c);
      var mask = now(c).mask;
      expect(mask.subject, endsWith(".mask"));
      expect(mask.marks, isEmpty);
      expect(c.maskNote, isNull);
      c.undo();
      expect(now(c).mask.empty, isTrue, reason: "one undo step");
    });

    testWidgets("the refining brush asks for a mask to refine first",
        (tester) async {
      var (c, screen) =
          await openWithFiles(tester, _picture(), ImageTool.refine);
      await tester.dragFrom(
          screen(const Offset(150, 150)), const Offset(30, 0));
      await settle(tester, c);
      expect(now(c).mask.empty, isTrue);
      expect(c.maskNote, contains("find the subject first"));
    });

    testWidgets("the refining brush works an existing mask's edge",
        (tester) async {
      var mask = const ImageMask(marks: [
        MaskMark(
            kind: MaskMarkKind.lasso,
            hide: false,
            points: [Offset(0.3, 0.3), Offset(0.7, 0.3), Offset(0.7, 0.7), Offset(0.3, 0.7)]),
        MaskMark(kind: MaskMarkKind.fade, points: [Offset(0, 0), Offset(0, 0.0001)]),
      ]);
      var (c, screen) = await openWithFiles(
          tester, _picture().copyWith(mask: mask), ImageTool.refine);
      await tester.dragFrom(
          screen(const Offset(160, 200)), const Offset(0, 40));
      await settle(tester, c);
      expect(now(c).mask.subject, endsWith(".mask"),
          reason: "the refined edge is kept as the subject");
      expect(now(c).mask.marks, isEmpty, reason: "with the marks worked in");
    });
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(WidgetTester tester, ImageMask mask,
        {ImageTool tool = ImageTool.brush}) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument()
          .addElement(_picture().copyWith(mask: mask)));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.editImage("i");
      c.imageTool = tool;
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(
              create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    ImageMask now(CanvasController c) =>
        (c.document.elementById("i")! as ImageElement).mask;

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    const mark = MaskMark(
        kind: MaskMarkKind.lasso,
        points: [Offset(0, 0), Offset(1, 0), Offset(1, 1)]);

    testWidgets("the brush's settings sit under the tools", (tester) async {
      var c = await pumpPanel(tester, const ImageMask());
      expect(find.byKey(const ValueKey("maskBrushSize")), findsOneWidget);
      expect(find.byKey(const ValueKey("maskView")), findsOneWidget);
      await tapKey(tester, "maskShow");
      expect(c.maskHide, isFalse);
      await tapKey(tester, "imageTool-fade");
      expect(find.byKey(const ValueKey("maskBrushSize")), findsNothing);
      expect(find.byKey(const ValueKey("maskRadial")), findsOneWidget);
      // Refine edge, Clean colour among it, is there before any mask is.
      expect(find.byKey(const ValueKey("maskDecontaminate")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("Clean colour is there with the layers shut", (tester) async {
      var c = await pumpPanel(tester, const ImageMask(marks: [mark]));
      c.editImage(null);
      await tester.pumpAndSettle();
      expect(c.imageEditing, isNull);
      await openSection(tester, "image.picture.mask");
      var field = find.byKey(const ValueKey("maskDecontaminate"));
      expect(field, findsOneWidget);
      var clean = tester.widget<CanvasStepper>(field);
      clean.onChanged(80);
      clean.onCommit?.call();
      await tester.pumpAndSettle();
      expect(now(c).refine.decontaminate, closeTo(0.8, 1e-9));
    });

    testWidgets("marks can be taken back, inverted and refined",
        (tester) async {
      var c = await pumpPanel(tester, const ImageMask(marks: [mark, mark]));
      await tapKey(tester, "maskUndoMark");
      expect(now(c).marks, hasLength(1));
      await tapKey(tester, "maskInvert");
      expect(now(c).invert, isTrue);

      var feather = tester.widget<CanvasStepper>(
          find.byKey(const ValueKey("maskFeather")));
      feather.onChanged(6);
      feather.onCommit?.call();
      await tester.pumpAndSettle();
      expect(now(c).refine.feather, 6);

      await tapKey(tester, "maskClear");
      expect(now(c).empty, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

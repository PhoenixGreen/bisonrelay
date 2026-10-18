import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_layer_arrange_test.dart is several of a picture's layers worked on
// at once: picked together on the canvas and in the panel, lined up and
// spread with the align tools, dragged together, and reordered in the strip
// with a long press.

/// _a is over the picture's top-left quarter, _b its bottom-right.
final _a =
    ImageLayer.picture("aaaaaaaaaaaaaaa1", const Rect.fromLTWH(0, 0, 500, 500));
final _b = ImageLayer.picture(
    "bbbbbbbbbbbbbbb1", const Rect.fromLTWH(600, 600, 300, 300));

ImageElement _element({List<ImageLayer>? layers}) => ImageElement(
      const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
      assetId: "basebasebasebase",
      layers: layers ?? [ImageLayer.base, _a, _b],
    );

ImageElement _now(CanvasController c) =>
    c.document.elementById("i")! as ImageElement;

Future<void> _seed(WidgetTester tester, CanvasController c) async {
  await tester.runAsync(() async {
    for (var id in ["basebasebasebase", _a.look!.assetId, _b.look!.assetId]) {
      var pixels = Uint8List(16 * 16 * 4);
      for (var i = 0; i < 16 * 16; i++) {
        pixels[i * 4 + 3] = 255;
      }
      var done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          pixels, 16, 16, ui.PixelFormat.rgba8888, done.complete);
      c.images.putForTest(id, await done.future);
    }
  });
}

Widget _host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group("lining layers up", () {
    test("aligned left, each meets the leftmost; the leftmost stays", () {
      var e = withLayersAligned(_element(), [_a.id, _b.id], CanvasAlign.left);
      expect(e.layerById(_a.id)!.place.left, closeTo(0, 1e-6));
      expect(e.layerById(_b.id)!.place.left, closeTo(0, 1e-6));
      expect(e.layerById(_b.id)!.place.top, 600, reason: "only sideways");
    });

    test("aligned to the bottom, each meets the lowest", () {
      var e =
          withLayersAligned(_element(), [_a.id, _b.id], CanvasAlign.bottom);
      expect(e.layerById(_a.id)!.place.bottom, closeTo(900, 1e-6));
      expect(e.layerById(_b.id)!.place.bottom, closeTo(900, 1e-6));
    });

    test("a turned layer lines up by where it shows, not its rectangle", () {
      // Four hundred wide and a hundred high, turned upright: it shows a
      // hundred wide, from 150 to 250 across.
      var long = ImageLayer.picture(
              "ccccccccccccccc1", const Rect.fromLTWH(0, 0, 400, 100))
          .placed(const Rect.fromLTWH(0, 0, 400, 100), turn: 90);
      var e = withLayersAligned(
          _element(layers: [ImageLayer.base, long, _b]),
          [long.id, _b.id],
          CanvasAlign.left);
      expect(e.layerById(_b.id)!.place.left, closeTo(150, 1e-6));
      expect(e.layerById(long.id)!.place, long.place, reason: "outermost");
    });

    test("spread, the gaps come out even and the ends stay", () {
      var c1 = ImageLayer.picture(
          "ccccccccccccccc1", const Rect.fromLTWH(100, 0, 100, 100));
      var e = withLayersSpread(
          _element(layers: [ImageLayer.base, _a, c1, _b]),
          [_a.id, c1.id, _b.id],
          true);
      var a = e.layerById(_a.id)!.place;
      var c = e.layerById(c1.id)!.place;
      var b = e.layerById(_b.id)!.place;
      expect(a, _a.place);
      expect(b, _b.place);
      expect(c.left - a.right, closeTo(b.left - c.right, 1e-6));
    });
  });

  group("picking several", () {
    test("Shift adds a layer and lets it go again; a plain pick lets all go",
        () {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.editImage("i", layer: _a.id);
      c.pickImageLayer(_b.id, add: true);
      expect(c.imageLayers, [_a.id, _b.id]);
      expect(c.aligning, 2);
      expect(c.imageLayer, _a.id, reason: "the settings are still the first's");

      c.pickImageLayer(_b.id, add: true);
      expect(c.imageLayers, [_a.id]);

      c.pickImageLayer(_b.id, add: true);
      c.pickImageLayer(_a.id);
      expect(c.imageLayers, [_a.id], reason: "a plain pick is one layer");
    });

    test("the align tools line up the picked layers, as one step", () {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.editImage("i", layer: _a.id);
      c.pickImageLayer(_b.id, add: true);
      c.alignSelected(CanvasAlign.top);
      expect(_now(c).layerById(_b.id)!.place.top, closeTo(0, 1e-6));
      c.undo();
      expect(_now(c).layerById(_b.id)!.place, _b.place);
    });
  });

  group("on the stage", () {
    const viewport = Size(800, 600);

    Future<Offset Function(Offset)> pump(
        WidgetTester tester, CanvasController c) async {
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CanvasStage(key: key, controller: c))));
      await _seed(tester, c);
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      return (p) => stage.pageRect.topLeft + p * scale;
    }

    testWidgets("Shift-click picks a second layer, and a drag moves both",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var screen = await pump(tester, c);
      c.editImage("i", layer: _a.id);
      await tester.pumpAndSettle();

      // The bottom-right layer: three quarters of the way across and down.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(screen(const Offset(260, 260)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(c.imageLayers, [_a.id, _b.id]);

      var scale = (screen(const Offset(1, 0)) - screen(Offset.zero)).dx;
      await tester.dragFrom(
          screen(const Offset(150, 150)), Offset(40 * scale, 0));
      await tester.pumpAndSettle();
      var a = _now(c).layerById(_a.id)!.place;
      var b = _now(c).layerById(_b.id)!.place;
      expect(a.left, greaterThan(100), reason: "the one held moved");
      expect(b.left - _b.place.left, closeTo(a.left - _a.place.left, 1e-6),
          reason: "and the other with it, as far");
      expect(a.top, _a.place.top);

      c.undo();
      expect(_now(c).layerById(_a.id)!.place, _a.place, reason: "one step");
      expect(_now(c).layerById(_b.id)!.place, _b.place);
    });
  });

  group("the arrow keys", () {
    testWidgets("move the layers picked, a canvas unit at a time",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.editImage("i", layer: _a.id);
      c.pickImageLayer(_b.id, add: true);
      // A frame two hundred wide is a thousand layer units: five a unit.
      c.nudgeSelected(1, 0);
      expect(_now(c).layerById(_a.id)!.place.left, closeTo(5, 1e-6));
      expect(_now(c).layerById(_b.id)!.place.left, closeTo(605, 1e-6));
      expect(_now(c).x, 100, reason: "the picture itself stays");
      c.nudgeSelected(0, 10);
      expect(_now(c).layerById(_a.id)!.place.top, closeTo(50, 1e-6));

      // With the base picked, the picture moves.
      c.pickImageLayer(baseLayerId);
      c.nudgeSelected(1, 0);
      expect(_now(c).x, 101);
    });

    testWidgets("work from the layers list as from the canvas",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _host(SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await _seed(tester, c);
      await tester.pumpAndSettle();
      var chip = find.byKey(ValueKey("imageLayer-${_a.id}"));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_now(c).layerById(_a.id)!.place.left, closeTo(5, 1e-6));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(_now(c).layerById(_a.id)!.place.top, closeTo(50, 1e-6));
    });
  });

  group("the base picture on the stage", () {
    testWidgets("with layers round it, is dragged about its frame",
        (tester) async {
      var key = GlobalKey<CanvasStageState>();
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      await tester.pumpWidget(_host(SizedBox(
          width: 800,
          height: 600,
          child: CanvasStage(key: key, controller: c))));
      await _seed(tester, c);
      await tester.pumpAndSettle();
      c.editImage("i");
      await tester.pumpAndSettle();
      var stage = key.currentState!;
      var scale = stage.pageRect.width / c.document.size.width;
      Offset screen(Offset p) => stage.pageRect.topLeft + p * scale;

      // Over the base alone: right of the top-left layer, above the other.
      await tester.dragFrom(
          screen(const Offset(240, 140)), Offset(30 * scale, 0));
      await tester.pumpAndSettle();
      var base = _now(c).layerById(baseLayerId)!.place;
      expect(base.left, greaterThan(50), reason: "the base moved: $base");
      expect(base.width, layerUnits, reason: "its size kept");
      expect(_now(c).layerById(_a.id)!.place, _a.place,
          reason: "and nothing else");
      expect(_now(c).x, 100, reason: "the frame stayed put");
    });
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _host(SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await _seed(tester, c);
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    testWidgets("Shift-clicking the strip picks layers together, to Arrange",
        (tester) async {
      var c = await pumpPanel(tester);
      if (find.byKey(const ValueKey("imageLayersRows")).evaluate().isNotEmpty) {
        await tapKey(tester, "imageLayersOpen");
      }
      await tapKey(tester, "imageLayer-${_a.id}");
      expect(find.byKey(const ValueKey("imageSection-arrange")), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tapKey(tester, "imageLayer-${_b.id}");
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.imageLayers, [_a.id, _b.id]);
      expect(find.byKey(const ValueKey("imageSection-arrange")), findsOneWidget);

      await tapKey(tester, "layerAlign-left");
      expect(_now(c).layerById(_b.id)!.place.left, closeTo(0, 1e-6));
      expect(tester.takeException(), isNull);
    });

    testWidgets("a long press carries a layer along the strip",
        (tester) async {
      var c = await pumpPanel(tester);
      if (find.byKey(const ValueKey("imageLayersRows")).evaluate().isNotEmpty) {
        await tapKey(tester, "imageLayersOpen");
      }
      // The strip reads front first: _b, _a, the base. _b carried past _a
      // goes behind it.
      var chip = find.byKey(ValueKey("imageLayer-${_b.id}"));
      var next = find.byKey(ValueKey("imageLayer-${_a.id}"));
      var gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump(const Duration(milliseconds: 700));
      var by = tester.getCenter(next).dx - tester.getCenter(chip).dx;
      for (var i = 1; i <= 10; i++) {
        await gesture.moveBy(Offset(by * 1.2 / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect([for (var l in _now(c).stack) l.id], [baseLayerId, _b.id, _a.id]);
      expect(tester.takeException(), isNull);
    });

    testWidgets("every number in a card is a stepper -- the crop's too",
        (tester) async {
      var c = await pumpPanel(tester);
      c.editImage("i", layer: _a.id);
      await tester.pumpAndSettle();
      await openSection(tester, "image.picture.position");
      var crop = find.byWidgetPredicate(
          (w) => w is CanvasControlGroup && w.label == "Crop");
      expect(find.descendant(of: crop, matching: find.byType(CanvasStepper)),
          findsNWidgets(4));
      expect(find.descendant(of: crop, matching: find.byType(TextField)),
          findsNothing);
      // And it writes the crop.
      await typeInto(
          tester,
          find
              .descendant(of: crop, matching: find.byType(CanvasStepper))
              .first,
          "0.25");
      expect(_now(c).layerById(_a.id)!.look!.crop.left, closeTo(0.25, 1e-6));
    });
  });
}

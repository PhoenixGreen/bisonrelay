import 'dart:async';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_image_layers_editing_test.dart is a picture's layers worked on the
// way they are worked on: opened with a double click, dragged about on the
// stage, and changed from the panel.

const _viewport = Size(800, 600);

/// _picture is the layer over the top-left quarter of the picture.
final _layer =
    ImageLayer.picture("toptoptoptoptop1", const Rect.fromLTWH(0, 0, 500, 500));

ImageElement _element() => ImageElement(
      const ElementBase(id: "i", x: 100, y: 100, width: 200, height: 200),
      assetId: "basebasebasebase",
      layers: [ImageLayer.base, _layer],
    );

Future<void> _seed(WidgetTester tester, CanvasController c) async {
  await tester.runAsync(() async {
    for (var id in ["basebasebasebase", "toptoptoptoptop1"]) {
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

void main() {
  group("on the stage", () {
    Future<CanvasStageState> pump(
        WidgetTester tester, CanvasController controller) async {
      var key = GlobalKey<CanvasStageState>();
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
              child: CanvasStage(key: key, controller: controller),
            ),
          ),
        ),
      ));
      await _seed(tester, controller);
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    /// open double-clicks the picture at [doc] and returns how to turn
    /// document points into the screen's.
    Future<Offset Function(Offset)> open(WidgetTester tester,
        CanvasController c, CanvasStageState stage, Offset doc) async {
      var scale = stage.pageRect.width / c.document.size.width;
      Offset screen(Offset p) => stage.pageRect.topLeft + p * scale;
      await tester.tapAt(screen(doc));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(screen(doc));
      await tester.pumpAndSettle();
      return screen;
    }

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    testWidgets("a double click opens the layers on the one under it",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var stage = await pump(tester, c);

      await open(tester, c, stage, const Offset(150, 150));
      expect(c.imageEditing, "i");
      expect(c.imageLayer, _layer.id);

      // And on the bottom-right quarter, where only the base picture is.
      c.editImage(null);
      await tester.pumpAndSettle();
      await open(tester, c, stage, const Offset(250, 250));
      expect(c.imageEditing, "i");
      expect(c.imageLayer, baseLayerId);
    });

    testWidgets("dragging a layer moves the layer, not the picture",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var stage = await pump(tester, c);
      var screen = await open(tester, c, stage, const Offset(150, 150));

      var scale = stage.pageRect.width / c.document.size.width;
      await tester.dragFrom(screen(const Offset(150, 150)),
          Offset(50 * scale, 20 * scale));
      await tester.pumpAndSettle();

      var e = now(c);
      expect(e.bounds, _element().bounds, reason: "the picture stayed put");
      var place = e.layerById(_layer.id)!.place;
      // Fifty canvas units across a frame two hundred wide is 250 layer
      // units; the drag's first few pixels go to telling it from a click.
      expect(place.left, closeTo(250, 15));
      expect(place.top, closeTo(100, 15));
      expect(place.size, _layer.place.size);

      c.undo();
      expect(now(c).layerById(_layer.id)!.place, _layer.place,
          reason: "one undo step");
    });

    testWidgets("a corner handle resizes it in proportion, from the far corner",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var stage = await pump(tester, c);
      var screen = await open(tester, c, stage, const Offset(150, 150));

      // The bottom-right corner of the layer is the middle of the picture.
      await tester.dragFrom(screen(const Offset(200, 200)), const Offset(60, 20));
      await tester.pumpAndSettle();

      var place = now(c).layerById(_layer.id)!.place;
      expect(place.topLeft, const Offset(0, 0), reason: "the far corner held");
      expect(place.width, greaterThan(500));
      expect(place.width, closeTo(place.height, 1e-6),
          reason: "a corner keeps the proportions");
    });

    testWidgets("the knob turns it", (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var stage = await pump(tester, c);
      var screen = await open(tester, c, stage, const Offset(150, 150));

      // Above the middle of the layer's top, as far as the knob stands.
      var knob = screen(const Offset(150, 100)) -
          const Offset(0, shapeTurnReach);
      // Round to level with the layer's middle, on its right.
      var to = screen(const Offset(260, 150));
      await tester.dragFrom(knob, to - knob);
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.turn, closeTo(90, 3));
    });

    testWidgets("Delete takes the layer; Escape closes the layers",
        (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      var stage = await pump(tester, c);
      await open(tester, c, stage, const Offset(150, 150));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(c.document.elementById("i"), isNotNull, reason: "not the picture");
      expect(now(c).layerById(_layer.id), isNull);
      expect(c.imageLayer, baseLayerId);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.imageEditing, isNull);
      expect(c.selection, {"i"}, reason: "still selected");
    });

    testWidgets("picking something else closes the layers", (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.editImage("i", layer: _layer.id);
      c.clearSelection();
      expect(c.imageEditing, isNull);
      expect(c.imageLayer, baseLayerId);
    });
  });

  group("in the panel", () {
    Widget panel(CanvasController c) => MultiProvider(
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
        );

    Future<CanvasController> pumpPanel(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_element()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await _seed(tester, c);
      await tester.pumpAndSettle();
      return c;
    }

    ImageElement now(CanvasController c) =>
        c.document.elementById("i")! as ImageElement;

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    testWidgets("the layers are always listed; picking one opens them",
        (tester) async {
      var c = await pumpPanel(tester);
      expect(c.imageEditing, isNull);
      expect(find.byKey(const ValueKey("imageLayersEdit")), findsNothing,
          reason: "no button to open and close them");
      // Shut, a strip with what is in front first.
      var top =
          tester.getTopLeft(find.byKey(ValueKey("imageLayer-${_layer.id}")));
      var base =
          tester.getTopLeft(find.byKey(const ValueKey("imageLayer-base")));
      expect(top.dx, lessThan(base.dx), reason: "what is in front is first");

      // Opened, a list with what is in front on top.
      await openLayerList(tester);
      top = tester.getTopLeft(find.byKey(ValueKey("imageLayer-${_layer.id}")));
      base = tester.getTopLeft(find.byKey(const ValueKey("imageLayer-base")));
      expect(top.dy, lessThan(base.dy), reason: "what is in front is on top");

      await tapKey(tester, "imageLayer-${_layer.id}");
      expect(c.imageEditing, "i");
      expect(c.imageLayer, _layer.id);
      await openSection(tester, "image.picture.mask");
      expect(find.byKey(const ValueKey("imageTool-subject")), findsOneWidget);
      await tapKey(tester, "imageLayersAdd");
      expect(find.byKey(const ValueKey("imageAddRecent")), findsOneWidget,
          reason: "a layer can come from the pictures already added");
      expect(tester.takeException(), isNull);
    });

    testWidgets("a picture layer's place is in its Position",
        (tester) async {
      var c = await pumpPanel(tester);
      await tapKey(tester, "imageLayer-${_layer.id}");
      expect(find.byKey(const ValueKey("elementX")), findsNothing);
      var x = tester.widget<CanvasStepper>(
          find.byKey(const ValueKey("layerX")));
      var w = tester.widget<CanvasStepper>(
          find.byKey(const ValueKey("layerW")));
      // The top-left quarter of a picture at (100, 100), 200 across.
      expect(x.value, 100);
      expect(w.value, 100);
      x.onChanged(130);
      x.onCommit?.call();
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.place.left, closeTo(150, 1e-9));

      // Proportions held: a new width brings the height with it.
      w = tester.widget<CanvasStepper>(
          find.byKey(const ValueKey("layerW")));
      w.onChanged(150);
      w.onCommit?.call();
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.place.height, closeTo(750, 1e-9));

      // The base picked, the place is the element's again.
      await tapKey(tester, "imageLayer-base");
      expect(find.byKey(const ValueKey("elementX")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a blend mode is seen on the canvas before it is chosen",
        (tester) async {
      var c = await pumpPanel(tester);
      await tapKey(tester, "imageLayer-${_layer.id}");
      await openSection(tester, "image.picture.colour");
      var undoable = c.canUndo;

      var screen = find.byKey(const ValueKey("imageLayerBlend-screen"));
      await tester.ensureVisible(screen);
      await tester.pumpAndSettle();
      var gesture =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(screen));
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.blend, LayerBlend.screen,
          reason: "shown while the pointer is on it");
      expect(c.canUndo, undoable, reason: "but not an edit");

      // Left without choosing: back as it was.
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.blend, LayerBlend.normal);
      expect(c.trying, isFalse);

      // Chosen: kept, as one undo step.
      var multiply = find.byKey(const ValueKey("imageLayerBlend-multiply"));
      await gesture.moveTo(tester.getCenter(multiply));
      await tester.pumpAndSettle();
      await tester.tap(multiply);
      await tester.pumpAndSettle();
      expect(now(c).layerById(_layer.id)!.blend, LayerBlend.multiply);
      expect(c.trying, isFalse);
      c.undo();
      expect(now(c).layerById(_layer.id)!.blend, LayerBlend.normal);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a colour layer is added above the one picked, and picked",
        (tester) async {
      var c = await pumpPanel(tester);
      await tapKey(tester, "imageLayer-base");
      expect(c.imageLayer, baseLayerId);

      await addLayer(tester, "imageAddFill");
      var stack = now(c).stack;
      expect(stack.length, 3);
      expect(stack[1].kind, LayerKind.fill, reason: "just above the base");
      expect(c.imageLayer, stack[1].id);
      // Its own settings, not a picture's.
      expect(find.byKey(const ValueKey("imageLayerColour")), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("rows hide, reorder and delete their layers", (tester) async {
      var c = await pumpPanel(tester);
      await openLayerList(tester);

      await tapKey(tester, "imageLayerShow-${_layer.id}");
      expect(now(c).layerById(_layer.id)!.visible, isFalse);

      // The picked row has the arrows.
      await tapKey(tester, "imageLayer-${_layer.id}");
      await tapKey(tester, "imageLayerDown-${_layer.id}");
      expect(now(c).stack.first.id, _layer.id, reason: "now at the back");
      await tapKey(tester, "imageLayerUp-${_layer.id}");
      expect(now(c).stack.last.id, _layer.id, reason: "and back in front");

      await tapKey(tester, "imageLayer-${_layer.id}");
      await tapKey(tester, "imageLayerDuplicate");
      expect(now(c).stack.length, 3);
      await tapKey(tester, "imageLayerDelete");
      expect(now(c).stack.length, 2);
      // The base cannot be deleted.
      await tapKey(tester, "imageLayer-base");
      expect(
          tester
              .widget<InkWell>(find.byKey(const ValueKey("imageLayerDelete")))
              .onTap,
          isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the picked layer's clipping and placement change it",
        (tester) async {
      var c = await pumpPanel(tester);
      await tapKey(tester, "imageLayer-${_layer.id}");
      await openSection(tester, "image.picture.colour");

      await tapKey(tester, "imageLayerClip");
      expect(now(c).layerById(_layer.id)!.clip, isTrue);

      await tapKey(tester, "imageLayerFlipX");
      expect(now(c).layerById(_layer.id)!.flipX, isTrue);

      await tapKey(tester, "imageLayerFill");
      var place = now(c).layerById(_layer.id)!.place;
      expect(place, const Rect.fromLTWH(0, 0, layerUnits, layerUnits),
          reason: "a square picture filling a square frame");

      // Its own place, and none of the brushes that paint on the base.
      expect(find.byKey(const ValueKey("layerX")), findsOneWidget);
      expect(find.byIcon(Icons.auto_fix_high), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a picture with no layers keeps its panel as it was",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(
          const ImageElement(
              ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
              assetId: "basebasebasebase")));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("imageLayers")), findsOneWidget);
      // The old removal brushes are gone: the mask tools do their work.
      expect(find.byIcon(Icons.auto_fix_high), findsNothing);
      expect(tester.takeException(), isNull);

      // A colour layer added straight from Add opens the layers.
      await addLayer(tester, "imageAddFill");
      expect(c.imageEditing, "i");
      expect(now(c).stack.length, 2);
      expect(
          now(c).stack.last.fill, const PaintSpec(ui.Color(0xFF1E2A38)));
    });
  });
}

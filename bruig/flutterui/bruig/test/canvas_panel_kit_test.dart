import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_tool_hint.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'canvas_panel_helpers.dart';

// canvas_panel_kit_test.dart is the sectioned settings panel's parts, pumped
// and pressed: the stepper, the sections, the search and fold-all over them,
// the tiles that try a choice on the canvas, and the hint over the canvas.

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

/// _Stepped holds a stepper's value the way a panel does: written on every
/// change, with each commit counted.
class _Stepped extends StatefulWidget {
  final double start;
  final void Function(double value, int commits) report;
  const _Stepped({required this.start, required this.report});

  @override
  State<_Stepped> createState() => _SteppedState();
}

class _SteppedState extends State<_Stepped> {
  late double value = widget.start;
  int commits = 0;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 160,
          child: CanvasStepper(
            key: const ValueKey("s"),
            label: "Opacity",
            value: value,
            min: 0,
            max: 100,
            step: 5,
            dragStep: 1,
            defaultValue: 100,
            onChanged: (v) {
              setState(() => value = v);
              widget.report(value, commits);
            },
            onCommit: () {
              commits++;
              widget.report(value, commits);
            },
          ),
        ),
      );
}

ImageElement _picture() => ImageElement(
    const ElementBase(id: "i", x: 0, y: 0, width: 200, height: 200),
    assetId: "abcdefghij123456",
    layers: [
      ImageLayer.base,
      ImageLayer.picture(
          "toptoptoptoptop1", const Rect.fromLTWH(0, 0, 500, 500)),
    ]);

void main() {
  group("the stepper", () {
    late double value;
    late int commits;
    Future<void> pump(WidgetTester tester, double start) async {
      value = start;
      commits = 0;
      await tester.pumpWidget(_host(_Stepped(
          start: start,
          report: (v, c) {
            value = v;
            commits = c;
          })));
    }

    testWidgets("an arrow nudges it a step, and commits", (tester) async {
      await pump(tester, 50);
      await tester.tap(find.byKey(const ValueKey("s-more")));
      await tester.pump();
      expect(value, 55);
      expect(commits, 1, reason: "one undo step per press");
      await tester.tap(find.byKey(const ValueKey("s-less")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("s-less")));
      await tester.pump();
      expect(value, 45);
    });

    testWidgets("held, an arrow repeats", (tester) async {
      await pump(tester, 10);
      var gesture = await tester
          .startGesture(tester.getCenter(find.byKey(const ValueKey("s-more"))));
      await tester.pump(const Duration(milliseconds: 1000));
      await gesture.up();
      await tester.pump();
      expect(value, greaterThan(30), reason: "kept going while held");
      expect(commits, 1, reason: "and is still one step");
    });

    testWidgets("it stops at its ends", (tester) async {
      await pump(tester, 98);
      await tester.tap(find.byKey(const ValueKey("s-more")));
      await tester.pump();
      expect(value, 100);
    });

    testWidgets("the number drags sideways", (tester) async {
      await pump(tester, 40);
      var number = find.text("40");
      await tester.drag(number, const Offset(30, 0));
      await tester.pump();
      expect(value, closeTo(70, 1), reason: "a pixel a unit");
      expect(commits, 1, reason: "committed when let go");
      // The double-click's wait for a second press runs out.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets("double-clicked, a number is typed", (tester) async {
      await pump(tester, 40);
      await tester.tap(find.text("40"));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text("40"));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), "12");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(value, 12);
      expect(commits, 1);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets("away from its default, it offers to go back", (tester) async {
      await pump(tester, 100);
      expect(find.byKey(const ValueKey("s-reset")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("s-less")));
      await tester.pump();
      expect(find.byKey(const ValueKey("s-reset")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("s-reset")));
      await tester.pump();
      expect(value, 100);
      expect(find.byKey(const ValueKey("s-reset")), findsNothing);
    });
  });

  group("the sides field", () {
    testWidgets("one number for four, a link to split them and join them",
        (tester) async {
      var values = [4.0, 4.0, 4.0, 4.0];
      await tester.pumpWidget(_host(StatefulBuilder(
          builder: (context, set) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: CanvasSidesField(
                    name: "pad",
                    label: "Padding",
                    values: values,
                    parts: const ["Top", "Right", "Bottom", "Left"],
                    partKeys: const ["padT", "padR", "padB", "padL"],
                    onChanged: (side, v) => set(() {
                      if (side == null) {
                        values = [v, v, v, v];
                      } else {
                        values = [...values]..[side] = v;
                      }
                    }),
                  ),
                ),
              ))));
      expect(find.byKey(const ValueKey("padT")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("pad-more")));
      await tester.pump();
      expect(values, [5, 5, 5, 5], reason: "one number for all four");

      await tester.tap(find.byKey(const ValueKey("padLink")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("padT")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("padB-more")));
      await tester.pump();
      expect(values, [5, 5, 6, 5], reason: "one side on its own");
      expect(tester.takeException(), isNull);

      // Joined, on the first.
      await tester.tap(find.byKey(const ValueKey("padLink")));
      await tester.pumpAndSettle();
      expect(values, [5, 5, 5, 5]);
      expect(find.byKey(const ValueKey("padT")), findsNothing);
    });
  });

  group("the picture's sections", () {
    Future<CanvasController> pumpPanel(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(_picture()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _host(SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    bool open(String section) =>
        find.byKey(ValueKey("sectionBody-$section")).evaluate().isNotEmpty;

    testWidgets("a picture has its seven, each saying how it is set",
        (tester) async {
      await pumpPanel(tester);
      for (var s in [
        "position", "mask", "retouch", "colour", "effects", "animation", //
        "frame",
      ]) {
        expect(find.byKey(ValueKey("imageSection-$s")), findsOneWidget,
            reason: s);
      }
      expect(find.text("Nothing hidden"), findsOneWidget,
          reason: "the Mask's summary, shut");
      expect(find.text("Whole image"), findsOneWidget, reason: "Frame's tag");
      expect(tester.takeException(), isNull);
    });

    testWidgets("an adjustment has its own sections instead",
        (tester) async {
      var c = await pumpPanel(tester);
      await addLayer(tester, "imageAddAdjustment");
      expect(c.pickedLayer?.kind, LayerKind.adjustment);
      expect(find.byKey(const ValueKey("imageSection-adjustment")),
          findsOneWidget);
      expect(find.byKey(const ValueKey("imageSection-blend")), findsOneWidget);
      expect(find.byKey(const ValueKey("imageSection-retouch")), findsNothing);
      expect(find.byKey(const ValueKey("imageSection-effects")), findsNothing,
          reason: "an adjustment has nothing of its own to shadow");
    });

    testWidgets("a section folds and stays as it was left", (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.retouch");
      expect(open("image.picture.retouch"), isTrue);
      await tapKey(tester, "section-image.picture.retouch");
      expect(open("image.picture.retouch"), isFalse);
      await tapKey(tester, "section-image.picture.retouch");
      // Rebuilt from scratch, as the panel is on every new selection.
      c.clearSelection();
      await tester.pumpAndSettle();
      c.selectOnly("i");
      await tester.pumpAndSettle();
      expect(open("image.picture.retouch"), isTrue);
    });

    testWidgets("a section changed has a dot and a reset", (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.colour");
      expect(find.byKey(const ValueKey("sectionChanged-image.picture.colour")),
          findsNothing);
      await tapKey(tester, "imageFilter-sepia");
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      expect(now().filter, ImageFilterPreset.sepia);
      expect(find.byKey(const ValueKey("sectionChanged-image.picture.colour")),
          findsOneWidget);
      await tapKey(tester, "sectionReset-image.picture.colour");
      expect(now().filter, ImageFilterPreset.none);
      expect(find.byKey(const ValueKey("sectionChanged-image.picture.colour")),
          findsNothing);
    });

    testWidgets("strokes are work, not a change: no dot, no reset",
        (tester) async {
      var c = await pumpPanel(tester);
      var e = c.document.elementById("i")! as ImageElement;
      c.changeImage(e.copyWith(retouch: const [
        StrokeMark(kind: StrokeKind.heal, points: [Offset(0.5, 0.5)]),
      ]));
      await tester.pumpAndSettle();
      await openSection(tester, "image.picture.retouch");
      expect(find.text("1 stroke"), findsOneWidget, reason: "still counted");
      expect(find.byKey(const ValueKey("sectionChanged-image.picture.retouch")),
          findsNothing);
      expect(find.byKey(const ValueKey("sectionReset-image.picture.retouch")),
          findsNothing);
    });

    testWidgets("open, a tile card is clicked too, never tried on a hover",
        (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.colour");
      await openTiles(tester, "image.tiles.filter");
      var noir = find.byKey(const ValueKey("imageFilter-noir"));
      await tester.ensureVisible(noir);
      await tester.pumpAndSettle();
      var mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(noir));
      await tester.pumpAndSettle();
      expect(c.trying, isFalse,
          reason: "a hover tried it, and the highlight followed the pointer");
      await mouse.moveTo(Offset.zero);
    });

    testWidgets("a tile kept from an earlier build picks with what is set now",
        (tester) async {
      var c = await pumpPanel(tester);
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      await openSection(tester, "image.picture.colour");
      await openTiles(tester, "image.tiles.filter");
      // Changed from outside the tiles -- the tiles show the same, and are
      // kept as they were built.
      c.changeImage(now().copyWith(brightness: 1.4));
      await tester.pumpAndSettle();
      var sepia = find.byKey(const ValueKey("imageFilter-sepia"));
      await tester.ensureVisible(sepia);
      await tester.tap(sepia);
      await tester.pumpAndSettle();
      expect(now().filter, ImageFilterPreset.sepia);
      expect(now().brightness, 1.4,
          reason: "the pick of the build it was kept from wrote back the "
              "brightness that build knew");
    });

    testWidgets(
        "an effect's tile puts it on once, then opens and shuts its settings",
        (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.effects");
      ImageLayer base() => (c.document.elementById("i")! as ImageElement)
          .stack
          .firstWhere((l) => l.isBase);
      bool lit(String kind) => tester
          .widget<CanvasTiles<EffectKind>>(
              find.byKey(const ValueKey("imageEffects")))
          .selected(EffectKind.values.byName(kind));
      bool ticked(String kind) => tester
          .widget<CanvasTiles<EffectKind>>(
              find.byKey(const ValueKey("imageEffects")))
          .ticked!(EffectKind.values.byName(kind));

      // The first press: on, its settings open, lit and ticked.
      await tapKey(tester, "effectTile-outerGlow");
      expect(base().effects.single.kind.name, "outerGlow");
      expect(find.byKey(const ValueKey("effect-outerGlow")), findsOneWidget);
      expect(lit("outerGlow"), isTrue);
      expect(ticked("outerGlow"), isTrue);

      // The second: its settings shut -- and the effect still on, ticked.
      await tapKey(tester, "effectTile-outerGlow");
      expect(base().effects.single.on, isTrue);
      expect(find.byKey(const ValueKey("effect-outerGlow")), findsNothing);
      expect(lit("outerGlow"), isFalse);
      expect(ticked("outerGlow"), isTrue);

      // A second effect on, with the first shut: both on at once.
      await tapKey(tester, "effectTile-dropShadow");
      expect(base().effects, hasLength(2));
      expect(find.byKey(const ValueKey("effect-dropShadow")), findsOneWidget);
      expect(find.byKey(const ValueKey("effect-outerGlow")), findsNothing);

      // Only its switch turns it off; the tick goes with it.
      await tapKey(tester, "effectOn-dropShadow");
      expect(
          base().effects.firstWhere((f) => f.kind.name == "dropShadow").on,
          isFalse);
      expect(ticked("dropShadow"), isFalse);
    });

    testWidgets("shut, a tile card is a strip with the one chosen in view",
        (tester) async {
      var c = await pumpPanel(tester);
      var e = c.document.elementById("i")! as ImageElement;
      // The last filter, so the strip has to be scrolled to show it.
      c.changeImage(e.copyWith(filter: ImageFilterPreset.values.last));
      await tester.pumpAndSettle();
      await openSection(tester, "image.picture.colour");
      // Shut it, if an earlier test opened it.
      if (find
          .byKey(const ValueKey("tilesStrip-image.tiles.filter"))
          .evaluate()
          .isEmpty) {
        await tapKey(tester, "tilesFold-image.tiles.filter");
      }
      expect(find.byKey(const ValueKey("tilesStrip-image.tiles.filter")),
          findsOneWidget);
      var name = ImageFilterPreset.values.last.label;
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("tilesFold-image.tiles.filter")),
              matching: find.text(name)),
          findsOneWidget,
          reason: "the heading says which is in use");
      var strip = tester
          .getRect(find.byKey(const ValueKey("tilesStrip-image.tiles.filter")));
      var tile = tester.getRect(find.byKey(
          ValueKey("imageFilter-${ImageFilterPreset.values.last.name}")));
      expect(strip.contains(tile.center), isTrue, reason: "scrolled to it");

      // Opened, every one of them.
      await openTiles(tester, "image.tiles.filter");
      for (var f in ImageFilterPreset.values) {
        expect(find.byKey(ValueKey("imageFilter-${f.name}")), findsOneWidget);
      }
    });

    testWidgets("shut, a strip is clicked, never tried on a hover",
        (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.colour");
      if (find
          .byKey(const ValueKey("tilesStrip-image.tiles.filter"))
          .evaluate()
          .isEmpty) {
        await tapKey(tester, "tilesFold-image.tiles.filter");
      }
      var sepia = find.byKey(const ValueKey("imageFilter-sepia"));
      await tester.ensureVisible(sepia);
      await tester.pumpAndSettle();
      var mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(sepia));
      await tester.pumpAndSettle();
      expect(c.trying, isFalse,
          reason: "a hover tried it, the strip scrolled to it, and on again");
      await tester.tap(sepia);
      await tester.pumpAndSettle();
      expect((c.document.elementById("i")! as ImageElement).filter,
          ImageFilterPreset.sepia);
    });

    testWidgets("the animation's kinds are tiles, with the kind's own card",
        (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.animation");
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      expect(find.byKey(const ValueKey("elementArriveHow")), findsNothing);
      await tapKey(tester, "elementArrive-slide");
      expect(now().animation.on, isTrue);
      expect(now().animation.preset.family.name, "slide");
      expect(find.byKey(const ValueKey("elementArriveHow")), findsOneWidget);
      expect(find.byKey(const ValueKey("elementAnimationLength")),
          findsOneWidget);
      await tapKey(tester, "elementArrive-none");
      expect(now().animation.on, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets("a dropdown's arrows step through its options",
        (tester) async {
      var c = await pumpPanel(tester);
      await tester.pumpAndSettle();
      await openSection(tester, "image.picture.position");
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      var fit = find.ancestor(
          of: find.text("Fit"), matching: find.byType(CanvasDropdown<ImageFit>));
      var before = now().fit;
      var more = find.descendant(
          of: fit,
          matching: find.byWidgetPredicate((w) =>
              w is Semantics && w.properties.label == "Next Fit"));
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(now().fit, ImageFit.values[ImageFit.values.indexOf(before) + 1]);
      var less = find.descendant(
          of: fit,
          matching: find.byWidgetPredicate((w) =>
              w is Semantics && w.properties.label == "Previous Fit"));
      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(now().fit, before);
    });

    testWidgets("a \"?\" opens on a click, never on a hover",
        (tester) async {
      await pumpPanel(tester);
      await openSection(tester, "image.picture.position");
      var hint = find
          .descendant(
              of: find.byKey(const ValueKey("sectionBody-image.picture.position")),
              matching: find.byType(CanvasHint))
          .first;
      var message = tester.widget<CanvasHint>(hint).message;
      await tester.ensureVisible(hint);
      await tester.pumpAndSettle();
      var mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(hint));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(message), findsNothing, reason: "not on a hover");
      await tester.tap(hint);
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: "on a click");
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing, reason: "and shut by another");
    });

    testWidgets("a tool picked from the keys opens its section",
        (tester) async {
      var c = await pumpPanel(tester);
      if (open("image.picture.retouch")) {
        await tapKey(tester, "section-image.picture.retouch");
      }
      c.editImage("i");
      c.imageTool = ImageTool.heal;
      await tester.pumpAndSettle();
      expect(open("image.picture.retouch"), isTrue);
      expect(find.byKey(const ValueKey("paintSize")), findsOneWidget,
          reason: "the tool's own settings under its tiles");

      // And pressing the tool in hand puts it down.
      await tapKey(tester, "imageTool-heal");
      expect(c.imageTool, ImageTool.move);
    });

    testWidgets("picking a tool opens the picture's layers", (tester) async {
      var c = await pumpPanel(tester);
      expect(c.imageEditing, isNull);
      await openSection(tester, "image.picture.mask");
      await tapKey(tester, "imageTool-lasso");
      expect(c.imageEditing, "i");
      expect(c.imageTool, ImageTool.lasso);
    });
  });

  group("the paint brushes", () {
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<CanvasController> pumpPaint(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(ImageElement(
          const ElementBase(id: "i", x: 0, y: 0, width: 200, height: 200),
          assetId: "abcdefghij123456",
          layers: [
            ImageLayer.base,
            const ImageLayer(id: "paint", kind: LayerKind.paint),
          ])));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.editImage("i", layer: "paint");
      c.imageTool = ImageTool.paint;
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _host(SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await idle(tester);
      return c;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    testWidgets("a brush is picked, changed, kept, and taken away",
        (tester) async {
      var root = Directory.systemTemp.createTempSync("brushes");
      addTearDown(() => root.deleteSync(recursive: true));
      CanvasStorage.rootOverride = root.path;
      addTearDown(() => CanvasStorage.rootOverride = null);
      SavedPresetStore.paintBrushes.forget();

      var c = await pumpPaint(tester);
      await openTiles(tester, "image.tiles.brush");
      await tapKey(tester, "paintBrush-calligraphy");
      expect(c.paintBrush, "calligraphy");
      expect(c.paintTip.followTilt, isTrue);
      expect(c.paintTip.roundness, closeTo(0.15, 1e-9));

      // Changed by hand, it is a brush of its own.
      await tapKey(tester, "paintRound-more");
      expect(c.paintTip.roundness, closeTo(0.2, 1e-9));
      expect(c.paintBrush, "");

      // Kept, it is among the brushes, and picked.
      await tapKey(tester, "paintBrushSave");
      await idle(tester);
      expect(SavedPresetStore.paintBrushes.presets, hasLength(1));
      var kept = SavedPresetStore.paintBrushes.presets.single;
      expect(c.paintBrush, kept.id);
      expect(find.byKey(ValueKey("paintBrush-${kept.id}")), findsOneWidget);

      // A stroke painted now carries the brush's tip.
      expect(c.paintTip.roundness, closeTo(0.2, 1e-9));

      await tapKey(tester, "paintBrushDelete");
      await idle(tester);
      expect(SavedPresetStore.paintBrushes.presets, isEmpty);
      expect(c.paintBrush, "round");
      expect(tester.takeException(), isNull);
    });
  });

  group("the hint over the canvas", () {
    Future<CanvasController> pumpHint(WidgetTester tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_picture()));
      addTearDown(c.dispose);
      c.selectOnly("i");
      await tester.pumpWidget(_host(Center(child: ImageToolHint(controller: c))));
      return c;
    }

    testWidgets("it is there only while a picture is being edited",
        (tester) async {
      var c = await pumpHint(tester);
      expect(find.byKey(const ValueKey("imageToolHint")), findsNothing);
      c.editImage("i");
      await tester.pump();
      expect(find.byKey(const ValueKey("imageToolHint")), findsOneWidget);
      expect(find.byKey(const ValueKey("imageToolDone")), findsNothing,
          reason: "nothing in hand to put down");
    });

    testWidgets("it says what the tool does, and Done puts it down",
        (tester) async {
      var c = await pumpHint(tester);
      c.editImage("i");
      c.imageTool = ImageTool.clone;
      await tester.pump();
      expect(find.text("Option-click where to copy from"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("imageToolDone")));
      await tester.pump();
      expect(c.imageTool, ImageTool.move);
    });

    testWidgets("held, compare shows the picture as it was put in",
        (tester) async {
      var c = await pumpHint(tester);
      c.editImage("i");
      await tester.pump();
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      expect(now().stack, hasLength(2));
      var hold = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey("imageCompare"))));
      await tester.pump();
      expect(now().stack, hasLength(1), reason: "only the picture");
      expect(c.trying, isTrue, reason: "shown, not done");
      await hold.up();
      await tester.pump();
      expect(now().stack, hasLength(2));
      expect(c.trying, isFalse);
    });
  });
}

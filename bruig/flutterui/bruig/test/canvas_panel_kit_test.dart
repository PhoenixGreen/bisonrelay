import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_tool_hint.dart';
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

    testWidgets("a filter is tried on the canvas while pointed at",
        (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.colour");
      ImageElement now() => c.document.elementById("i")! as ImageElement;
      var undoable = c.canUndo;
      var noir = find.byKey(const ValueKey("imageFilter-noir"));
      await tester.ensureVisible(noir);
      await tester.pumpAndSettle();
      var mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(noir));
      await tester.pumpAndSettle();
      expect(now().filter, ImageFilterPreset.noir);
      expect(c.canUndo, undoable, reason: "tried, not done");
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(now().filter, ImageFilterPreset.none);
    });

    testWidgets("an effect's tile switches it on and off", (tester) async {
      var c = await pumpPanel(tester);
      await openSection(tester, "image.picture.effects");
      ImageLayer base() => (c.document.elementById("i")! as ImageElement)
          .stack
          .firstWhere((l) => l.isBase);
      await tapKey(tester, "effectTile-outerGlow");
      expect(base().effects.single.kind.name, "outerGlow");
      expect(find.byKey(const ValueKey("effect-outerGlow")), findsOneWidget,
          reason: "its settings, now it is on");
      await tapKey(tester, "effectTile-outerGlow");
      expect(base().effects, isEmpty);
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

import 'package:bruig/components/color_picker.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_colour_panel_test.dart is the Design sidebar's Colour section: the
// selected element's colours as a pair of swatches, the picker for the one
// in front, None, Swap, and the eyedropper that takes a colour off the
// canvas.

VectorElement drawing() => VectorElement(
        const ElementBase(id: "v", x: 100, y: 100, width: 200, height: 100),
        viewBox: const Rect.fromLTWH(0, 0, 200, 100),
        shapes: [
          shapeOf(VectorShapeKind.box, const Rect.fromLTWH(0, 0, 100, 100),
              fill: const Color(0xFFE53935), stroke: const Color(0xFF1E88E5)),
          shapeOf(VectorShapeKind.box, const Rect.fromLTWH(100, 0, 100, 100),
              fill: const Color(0xFF43A047)),
        ]);

Widget host(CanvasController c, {bool stage = false}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Row(children: [
        SizedBox(
            width: 320,
            child: SingleChildScrollView(child: ColourPanel(controller: c))),
        if (stage)
          Expanded(
              child: CanvasStage(key: const ValueKey("stage"), controller: c)),
      ]))),
    );

void main() {
  test("each element's colours: a drawing's shape, a shape, none", () {
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
    addTearDown(c.dispose);
    var e = c.document.elementById("v")!;
    var slots = colourSlotsFor(c, e);
    expect([for (var s in slots) s.label], ["Fill", "Line"]);
    // No shape picked: every shape takes it.
    var all = slots.first.withColour(const Color(0xFF000000)) as VectorElement;
    expect(all.shapes!.every((s) => s.fill == const Color(0xFF000000)), isTrue);
    // A shape picked: that one alone.
    c.editVector("v");
    c.pickVectorShape(1);
    var one = colourSlotsFor(c, c.document.elementById("v")!)
        .first
        .withColour(const Color(0xFF000000)) as VectorElement;
    expect(one.shapes![1].fill, const Color(0xFF000000));
    expect(one.shapes![0].fill, const Color(0xFFE53935));

    var shape = ShapeElement(const ElementBase(id: "s"),
        fill: const Color(0xFF0000FF), strokeWidth: 0);
    var s = colourSlotsFor(c, shape);
    expect([for (var x in s) x.label], ["Fill", "Outline"]);
    expect(s[1].color, isNull, reason: "no line yet: none");
    var lined = s[1].withColour(const Color(0xFFFF0000)) as ShapeElement;
    expect(lined.strokeWidth, greaterThan(0), reason: "given one to be seen");
    expect((s[0].withColour(null) as ShapeElement).fill.a, 0);
  });

  testWidgets("a swatch picked is the one the picker sets; none; swap",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(c));
    await tester.pumpAndSettle();
    VectorShape first() =>
        (c.document.elementById("v") as VectorElement).shapes!.first;

    expect(tester.widget<Text>(find.byKey(const ValueKey("colourActive"))).data,
        "Fill");
    await tester.tap(find.byKey(const ValueKey("colourSlot-line")));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey("colourActive"))).data,
        "Line");
    tester
        .widget<AppColorPicker>(find.byType(AppColorPicker))
        .onChanged(const Color(0xFFFFEB3B));
    await tester.pump(const Duration(seconds: 1));
    expect(first().stroke, const Color(0xFFFFEB3B));
    expect(first().fill, const Color(0xFFE53935), reason: "the line alone");

    await tester.tap(find.byKey(const ValueKey("colourNone")));
    await tester.pumpAndSettle();
    expect(first().stroke, isNull, reason: "none");
    c.undo();
    expect(first().stroke, const Color(0xFFFFEB3B), reason: "one undo step");
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("colourSwap")));
    await tester.pumpAndSettle();
    expect(first().fill, const Color(0xFFFFEB3B));
    expect(first().stroke, const Color(0xFFE53935));
    expect(tester.takeException(), isNull);
  });

  testWidgets("the eyedropper takes a colour off the canvas", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(c, stage: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colourSlot-line")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colourDropper")));
    await tester.pumpAndSettle();
    expect(c.sampling, isTrue);

    // On the green square, at (250, 150) on the canvas.
    var view =
        tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
    var page = view.pageRect;
    var at = tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
        page.topLeft +
        const Offset(250, 150) * (page.width / c.document.size.size.width);
    await tester.tapAt(at);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(c.sampling, isFalse, reason: "one colour, then put away");
    expect(c.sampled, const Color(0xFF43A047));
    var first = (c.document.elementById("v") as VectorElement).shapes!.first;
    expect(first.stroke, const Color(0xFF43A047),
        reason: "given to the colour being chosen");
    expect(c.selection, {"v"}, reason: "the press picked nothing else");
    expect(tester.takeException(), isNull);
  });
}

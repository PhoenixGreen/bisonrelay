import 'dart:ui' as ui;
import 'package:bruig/components/color_picker.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/colour_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
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
    c.selectOnly("v");
    VectorElement v() => c.document.elementById("v") as VectorElement;
    var slots = colourSlotsFor(c);
    expect([for (var s in slots) s.label], ["Fill", "Line"]);
    // No shape picked: every shape takes it.
    slots.first.setColour(const Color(0xFF000000), transient: false);
    expect(v().shapes!.every((s) => s.fill == const Color(0xFF000000)), isTrue);
    c.undo();
    // A shape picked: that one alone.
    c.editVector("v");
    c.pickVectorShape(1);
    colourSlotsFor(c)
        .first
        .setColour(const Color(0xFF000000), transient: false);
    expect(v().shapes![1].fill, const Color(0xFF000000));
    expect(v().shapes![0].fill, const Color(0xFFE53935));
    // And a fade, which a drawing's shape takes now as well.
    colourSlotsFor(c).first.setGradient(
        const GradientSpec(to: Color(0xFFFFFFFF)),
        transient: false);
    expect(v().shapes![1].fillFade, isNotNull);

    var shapes = CanvasController(const CanvasDocument().addElement(
        ShapeElement(const ElementBase(id: "s"),
            fill: const Color(0xFF0000FF), strokeWidth: 0)));
    addTearDown(shapes.dispose);
    shapes.selectOnly("s");
    ShapeElement s() => shapes.document.elementById("s") as ShapeElement;
    var slots2 = colourSlotsFor(shapes);
    expect([for (var x in slots2) x.label], ["Fill", "Outline"]);
    expect(slots2[1].color, isNull, reason: "no line yet: none");
    slots2[1].setColour(const Color(0xFFFF0000), transient: false);
    expect(s().strokeWidth, greaterThan(0), reason: "given one to be seen");
    colourSlotsFor(shapes)[0].setColour(null, transient: false);
    expect(s().fill.a, 0);
  });

  test("nothing selected: the background's three, each with a fade", () {
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
    addTearDown(c.dispose);
    var slots = colourSlotsFor(c);
    expect([for (var s in slots) s.label], ["Base", "Main", "Accent"]);
    slots[2].setColour(const Color(0xFF00FF00), transient: false);
    colourSlotsFor(c)[1].setGradient(const GradientSpec(to: Color(0xFFFF00FF)),
        transient: false);
    var spec = c.document.editedBackground.spec;
    expect(spec.accent, const Color(0xFF00FF00));
    expect(spec.foregroundFade, isNotNull);
    expect(ProceduralSpec.fromJson(spec.toJson()).foregroundFade, isNotNull,
        reason: "kept");
    // None: the colour gone clear.
    colourSlotsFor(c)[0].setColour(null, transient: false);
    expect(c.document.editedBackground.spec.background.a, 0);
    expect(colourSlotsFor(c)[0].color, isNull, reason: "shown as none");
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

    var fillAt =
        tester.getTopLeft(find.byKey(const ValueKey("colourSlot-fill")));
    var lineAt =
        tester.getTopLeft(find.byKey(const ValueKey("colourSlot-line")));
    await tester.tap(find.byKey(const ValueKey("colourSlot-line")));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey("colourSlot-fill"))),
        fillAt,
        reason: "picked, a swatch comes to the front where it is");
    expect(tester.getTopLeft(find.byKey(const ValueKey("colourSlot-line"))),
        lineAt);
    expect(tester.widget<AppColorPicker>(find.byType(AppColorPicker)).color,
        const Color(0xFF1E88E5),
        reason: "the line is the colour being chosen");
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

  test("a background's Main fades where the pattern draws it, and only there",
      () async {
    Future<List<int>> draw(ProceduralSpec spec) async {
      var rec = ui.PictureRecorder();
      paintProcedural(Canvas(rec), const Rect.fromLTWH(0, 0, 200, 120), spec);
      var img = await rec.endRecording().toImage(200, 120);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    const flat = ProceduralSpec(
        style: ProceduralStyle.dotGrid,
        background: Color(0xFF000000),
        foreground: Color(0xFFFF0000),
        accent: Color(0xFFFF0000));
    var faded = flat.copyWith(
        foregroundFade: const GradientSpec(to: Color(0xFF0000FF)));
    var a = await draw(flat), b = await draw(faded);
    var blueDots = 0, baseChanged = 0;
    for (var i = 0; i < a.length; i += 4) {
      var wasBase = a[i] < 8 && a[i + 1] < 8 && a[i + 2] < 8;
      if (wasBase && (b[i] > 8 || b[i + 2] > 8)) baseChanged++;
      // Bluer than it was: the far end of the fade.
      if (b[i + 2] > a[i + 2] + 20) blueDots++;
    }
    expect(blueDots, greaterThan(0), reason: "the fade reached the dots");
    expect(baseChanged, lessThan(a.length ~/ 4 ~/ 200),
        reason: "and not the base between them");
  });

  testWidgets("a playlist row with a gap fits a narrow sidebar",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var e = drawing();
    e = e.copyWith(shapes: [
      e.shapes![0],
      e.shapes![1].copyWith(cue: VectorCue.gap, cueGap: -120),
    ]);
    var c = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(260, 2400);
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
                  width: 240,
                  child: SingleChildScrollView(
                      child: ListenableBuilder(
                          listenable: c,
                          builder: (context, _) => Column(
                              children: elementSettings(
                                  context, c, c.selected!))))))),
    ));
    await tester.pumpAndSettle();
    var heading = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? "").toLowerCase() == "playlist");
    if (find.byKey(const ValueKey("vectorPlaylist-1")).evaluate().isEmpty) {
      await tester.tap(heading.first);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey("vectorGap-1")), findsOneWidget);
    expect(tester.takeException(), isNull, reason: "no overflow");
  });

  testWidgets("a channel's number is dragged, held a moment first",
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
    // The R box, under its letter.
    var box = tester.getCenter(find.byKey(const ValueKey("channelR"))) +
        const Offset(0, 22);
    var g = await tester.startGesture(box);
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    expect((first().fill!.r * 255).round(), 0xE5 - 30,
        reason: "thirty to the left, thirty less red");
    expect(tester.takeException(), isNull);
  });

  testWidgets("the ways of choosing are one icon that opens to them all",
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
    var menu = find.byKey(const ValueKey("colorModeMenu"));
    expect(menu, findsOneWidget);
    expect(find.text("Wheel"), findsNothing, reason: "shut: the icon alone");
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text("Wheel"), findsWidgets, reason: "open: each by name");
    expect(find.text("Reset"), findsWidgets);
    await tester.tap(find.text("Wheel").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("colorShade")), findsNothing,
        reason: "the wheel in place of the sliders' field");
    // The notation and its value on one row.
    var format = tester.getRect(find.byKey(const ValueKey("colorFormat")));
    var value = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect((format.center.dy - value.center.dy).abs(), lessThan(2));
    expect(tester.takeException(), isNull);
  });

  for (var width in [320.0, 260.0, 230.0]) {
    testWidgets(
        "at ${width.round()} wide: Greyscale on one line, the value "
        "ending with A, nothing over", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var c = CanvasController(const CanvasDocument().addElement(drawing()));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 1600);
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
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: width,
                        height: 800,
                        child: ColourPanel(controller: c))))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("colorFormat")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Greyscale").last);
      await tester.pumpAndSettle();
      var format = tester.getRect(find.byKey(const ValueKey("colorFormat")));
      expect(format.height, lessThan(26), reason: "one line");
      var value = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
      var alpha = tester.getRect(find.byKey(const ValueKey("channelA")));
      expect(value.right, closeTo(alpha.right, 1),
          reason: "the value ends where the channels do");
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("squeezed very narrow, nothing in it overflows", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(drawing()));
    addTearDown(c.dispose);
    c.selectOnly("v");
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var width in [100.0, 150.0, 180.0, 200.0, 240.0]) {
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
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: width,
                        height: 800,
                        child: ColourPanel(controller: c))))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: "at $width wide");
    }
  });

  test("a new, empty drawing: the colours its shapes will be drawn in", () {
    var e = VectorElement(
        const ElementBase(id: "n", x: 100, y: 100, width: 200, height: 200));
    var c = CanvasController(const CanvasDocument().addElement(e));
    addTearDown(c.dispose);
    c.selectOnly("n");
    var slots = colourSlotsFor(c);
    expect([for (var s in slots) s.label], ["Fill", "Line"]);
    slots[0].setColour(const Color(0xFF00FF00), transient: false);
    slots[1].setColour(const Color(0xFFFF00FF), transient: false);
    expect(c.vectorShapeFill, const Color(0xFF00FF00));
    expect(c.vectorPencilFill, const Color(0xFF00FF00));
    expect(c.vectorShapeLine, const Color(0xFFFF00FF));
    expect(c.vectorPencilColour, const Color(0xFFFF00FF));
    expect(colourSlotsFor(c)[1].color, const Color(0xFFFF00FF),
        reason: "shown as set");
  });

  testWidgets("the pen's first line is drawn in the Line colour set",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(VectorElement(
        const ElementBase(id: "n", x: 100, y: 100, width: 300, height: 300))));
    addTearDown(c.dispose);
    c.selectOnly("n");
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(c, stage: true));
    await tester.pumpAndSettle();
    colourSlotsFor(c)[1].setColour(const Color(0xFFFF6D00), transient: false);
    // As Edit points opens an empty drawing: blank, for the pen.
    c.replaceElement(
        blankDrawing(c.document.elementById("n") as VectorElement));
    c.editVector("n");
    c.vectorTool = VectorTool.pen;
    await tester.pumpAndSettle();
    var view =
        tester.state<CanvasStageState>(find.byKey(const ValueKey("stage")));
    Offset at(Offset doc) =>
        tester.getTopLeft(find.byKey(const ValueKey("stage"))) +
        view.pageRect.topLeft +
        doc * (view.pageRect.width / c.document.size.size.width);
    await tester.tapAt(at(const Offset(150, 150)));
    await tester.pumpAndSettle();
    var shapes = (c.document.elementById("n") as VectorElement).shapes!;
    expect(shapes.single.stroke, const Color(0xFFFF6D00));
    expect(tester.takeException(), isNull);
  });
}

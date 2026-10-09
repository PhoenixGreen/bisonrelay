import 'dart:io';
import 'dart:ui';

import 'package:bruig/models/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/model/font_outlines.dart';
import 'package:bruig/plugin_system/canvas/model/vector_text.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Color, Offset, Rect;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_vector_text_test.dart is a drawing's text: the words set in the
// font's own outlines, kept as text until its points are edited, and typed
// on the drawing with the text tool.

FontPick inter() => FontPick(
    FontFace.parse(File("assets/fonts/Inter-Regular.otf").readAsBytesSync())!);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("set in the font: a letter's runs, the caret's places, two lines", () {
    var t = const VectorText(text: "Hi\nyo", size: 100);
    var laid = layoutVectorText(t, const Offset(10, 200), inter());
    // H is three runs' worth of outline? One: an H is a single outline; i
    // is two (stem and dot); y one; o two (outside and counter).
    expect(laid.runs.length, 1 + 2 + 1 + 2);
    expect(laid.carets.length, t.text.length + 1);
    expect(laid.carets.first, const Offset(10, 200));
    expect(laid.carets[3].dx, 10, reason: "the second line starts back");
    expect(laid.carets[3].dy, greaterThan(200), reason: "and further down");
    // The H's left edge and its height, as Inter draws it.
    var h = VectorShape(paths: [laid.runs.first]).path.getBounds();
    expect(h.bottom, closeTo(200, 0.5), reason: "on the baseline");
    expect(h.height, closeTo(72.7, 1.5), reason: "Inter's cap height");
  });

  test("text until its points are edited; moved, still text", () {
    var shape = typed(const VectorShape(paths: []),
        const VectorText(text: "A", size: 50), const Offset(0, 100), inter());
    expect(shape.liveText?.text, "A");
    var moved = shape.copyWith(paths: [
      for (var r in shape.paths)
        r.copyWith(nodes: [
          for (var n in r.nodes) n.copyWith(x: n.x + 30, y: n.y - 10)
        ]),
    ]);
    expect(moved.liveText, isNotNull, reason: "moved whole");
    expect((moved.textOrigin! - const Offset(30, 90)).distance, lessThan(1e-6));
    var edited = shape.copyWith(paths: [
      shape.paths.first.copyWith(nodes: [
        shape.paths.first.nodes.first.copyWith(x: 99),
        ...shape.paths.first.nodes.skip(1),
      ]),
      ...shape.paths.skip(1),
    ]);
    expect(edited.liveText, isNull, reason: "a point moved: a shape now");
    expect(edited.toJson().containsKey("text"), isFalse);
  });

  testWidgets("typed on the drawing with the text tool, as one change",
      (tester) async {
    var c = CanvasController(const CanvasDocument().addElement(VectorElement(
        const ElementBase(id: "v", x: 100, y: 100, width: 400, height: 200),
        viewBox: const Rect.fromLTWH(0, 0, 400, 200),
        shapes: const [])));
    addTearDown(c.dispose);
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = const Size(1200, 900);
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
                  width: 1200,
                  height: 900,
                  child: CanvasStage(key: key, controller: c)))),
    ));
    await tester.pumpAndSettle();
    c.selectOnly("v");
    c.editVector("v");
    c.vectorTool = VectorTool.text;
    await tester.pumpAndSettle();
    var view = key.currentState!;
    var page = view.pageRect;
    var at = page.topLeft +
        const Offset(150, 250) * (page.width / c.document.size.size.width);
    await tester.runAsync(() => FontFiles.instance.load("Inter", 400, false));
    await tester.tapAt(at);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(c.vectorTyping, 0, reason: "new text, being typed");
    await tester.enterText(
        find.byKey(const ValueKey("vectorTypingField")), "Go");
    await tester.pump();
    VectorShape shape() =>
        (c.document.elementById("v") as VectorElement).shapes!.single;
    expect(shape().liveText?.text, "Go");
    expect(shape().paths.length, 3, reason: "G, and o's two");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.vectorTyping, -1);
    c.undo();
    expect((c.document.elementById("v") as VectorElement).shapes, isEmpty,
        reason: "the typing, one undo step");
    expect(tester.takeException(), isNull);
  });

  testWidgets("typed again and again -- after a setting is changed too",
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var c = CanvasController(const CanvasDocument().addElement(VectorElement(
        const ElementBase(id: "v", x: 100, y: 100, width: 400, height: 200),
        viewBox: const Rect.fromLTWH(0, 0, 400, 200),
        shapes: const [])));
    addTearDown(c.dispose);
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
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
              body: Row(children: [
        SizedBox(width: 420, child: CanvasDesignPanel(controller: c)),
        Expanded(child: CanvasStage(key: key, controller: c)),
      ]))),
    ));
    await tester.pumpAndSettle();
    c.selectOnly("v");
    c.editVector("v");
    await tester.pumpAndSettle();
    await tester.runAsync(() => FontFiles.instance.load("Inter", 400, false));
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    Offset at(double x, double y) {
      var page = key.currentState!.pageRect;
      var origin = tester.getTopLeft(find.byType(CanvasStage));
      return origin +
          page.topLeft +
          Offset(x, y) * (page.width / c.document.size.size.width);
    }

    VectorElement e() => c.document.elementById("v") as VectorElement;
    String state() =>
        "focus=${FocusManager.instance.primaryFocus?.debugLabel} typing=${c.vectorTyping} texts=${[
          for (var s in e().shapes!) s.liveText?.text ?? "<${s.text?.text}>"
        ]}";
    Future<void> pickTool() async {
      var b = find.byKey(const ValueKey("vectorTool-text"));
      await tester.ensureVisible(b);
      await tester.tap(b);
      await settle();
    }

    Future<void> click(double x, double y) async {
      var g =
          await tester.startGesture(at(x, y), kind: PointerDeviceKind.mouse);
      await settle();
      await g.up();
      await settle();
    }

    await pickTool();
    await click(150, 250);
    tester.testTextInput.enterText("One");
    await settle();
    expect(state(), "focus=vectorTyping typing=0 texts=[One]");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(state(), "focus=canvas stage typing=-1 texts=[One]");
    await pickTool();
    await click(150, 180);
    tester.testTextInput.enterText("Two");
    await settle();
    expect(state(), "focus=vectorTyping typing=1 texts=[One, Two]");
    // The size typed in the panel, then a click on the canvas.
    var size = find.byKey(const ValueKey("vectorTextSize"));
    await tester.ensureVisible(size);
    await tester
        .tap(find.descendant(of: size, matching: find.byType(EditableText)));
    await settle();
    tester.testTextInput.enterText("30");
    await settle();
    await click(300, 150);
    tester.testTextInput.enterText("Three");
    await settle();
    expect(state(), "focus=vectorTyping typing=2 texts=[One, Two, Three]",
        reason: "new text after the size was changed: still typed into");
    await click(160, 245);
    tester.testTextInput.enterText("One more");
    await settle();
    expect(state(), "focus=vectorTyping typing=0 texts=[One more, Two, Three]",
        reason: "clicked again, the first text is typed into");
    expect(tester.takeException(), isNull);
  });
}

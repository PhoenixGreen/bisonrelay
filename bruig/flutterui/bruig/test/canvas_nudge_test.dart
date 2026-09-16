import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_nudge_test.dart is the arrow keys.
//
// They used to walk the playhead, and moved the selected element only with
// Alt held -- a shortcut nobody finds, when the arrows are the one thing
// everybody reaches for to shift a thing a pixel. They move what is chosen
// now and walk the frames when nothing is, with Alt asking for the other one.

void main() {
  Future<CanvasController> show(WidgetTester tester,
      {bool selected = true}) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var controller = CanvasController(const CanvasDocument(
      frames: 40,
      // No grid, so a one-pixel nudge is not snapped back onto a line.
      guides: CanvasGuides(snap: false),
      elements: [
        ShapeElement(
            ElementBase(id: "a", x: 100, y: 100, width: 60, height: 60)),
      ],
    ));
    addTearDown(controller.dispose);
    controller.frame = 12;
    if (selected) controller.selectOnly("a");

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(body: CanvasStage(controller: controller)),
      ),
    ));
    await tester.pumpAndSettle();
    // The stage answers the keyboard through its own Focus, and a Focus that
    // has never been reached for answers nothing. A tap on the canvas is how
    // anybody gets there.
    await tester.tapAt(tester.getCenter(find.byType(CanvasStage)));
    await tester.pumpAndSettle();
    if (selected) controller.selectOnly("a");
    await tester.pumpAndSettle();
    return controller;
  }

  double xOf(CanvasController controller) =>
      controller.document.elementById("a")!.base.x;
  double yOf(CanvasController controller) =>
      controller.document.elementById("a")!.base.y;

  testWidgets("move the chosen element", (tester) async {
    var controller = await show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(xOf(controller), 101);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(yOf(controller), 101);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(xOf(controller), 100);
    expect(yOf(controller), 100);
  });

  testWidgets("and leave the playhead alone while they do", (tester) async {
    var controller = await show(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.frame, 12);
  });

  testWidgets("ten pixels with Shift", (tester) async {
    // A pixel at a time for placing, ten for moving.
    var controller = await show(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(xOf(controller), 110);
  });

  testWidgets("with nothing chosen they walk the frames", (tester) async {
    var controller = await show(tester, selected: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.frame, 13);
    expect(xOf(controller), 100, reason: "and move nothing");
  });

  testWidgets("Alt asks for the other one", (tester) async {
    // Both are still reachable: with something chosen, Alt steps the frame.
    var controller = await show(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(controller.frame, 13);
    expect(xOf(controller), 100);
  });
}

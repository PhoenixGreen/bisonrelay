import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Ken, 2026-11-11: six elements picked in Layers, then dragged on the canvas
// -- and the first drag picked the element lying over them instead. What is
// selected comes first under the pointer; with nothing selected there, the
// topmost thing still wins.

ShapeElement box(String id, double x) =>
    ShapeElement(ElementBase(id: id, x: x, y: 100, width: 200, height: 200),
        fill: const Color(0xFFFF0000), strokeWidth: 0);

Future<(CanvasController, CanvasStageState)> show(WidgetTester tester) async {
  var key = GlobalKey<CanvasStageState>();
  // "under" and "beside" are picked; "over" lies across "under".
  var c = CanvasController(const CanvasDocument()
      .addElement(box("under", 100))
      .addElement(box("beside", 500))
      .addElement(box("over", 100)));
  addTearDown(c.dispose);
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
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
                width: 1000,
                height: 800,
                child: CanvasStage(key: key, controller: c)))),
  ));
  await tester.pumpAndSettle();
  return (c, key.currentState!);
}

void main() {
  testWidgets("the selection is dragged, not what lies over it",
      (tester) async {
    var (c, stage) = await show(tester);
    c.selectOnly("under");
    c.toggleSelected("beside");
    await tester.pump();
    var from = stage.toStagePoint(const Offset(200, 200));
    var to = stage.toStagePoint(const Offset(260, 200));
    await tester.dragFrom(from, to - from);
    await tester.pumpAndSettle();
    expect(c.selection, {"under", "beside"}, reason: "still the two picked");
    var moved = to.dx - from.dx;
    expect(c.document.elementById("under")!.base.x, greaterThan(100));
    expect(c.document.elementById("beside")!.base.x, greaterThan(500),
        reason: "the whole selection moved together");
    expect(c.document.elementById("over")!.base.x, 100,
        reason: "what lay over them stayed put");
    expect(moved, greaterThan(0));
  });

  testWidgets("with nothing selected there, the topmost is picked",
      (tester) async {
    var (c, stage) = await show(tester);
    c.selectOnly("beside");
    await tester.pump();
    await tester.tapAt(stage.toStagePoint(const Offset(200, 200)));
    await tester.pumpAndSettle();
    expect(c.selection, {"over"});
  });
}

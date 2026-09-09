import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_text_flow_stage_test.dart is the gesture that makes a chain of text
// boxes: a line dragged out of one box's overflow grip and dropped on
// another.
//
// A widget test rather than a model one, because the whole feature is the
// grip: a model that can hold a link nobody can draw is a model with a field
// in it. See the two dead controls in bisonrelay_widget_tests_vs_controls.

const _lorem =
    "The quick brown fox jumps over the lazy dog while the rain in Spain "
    "falls mainly on the plain and nobody at all is watching this happen.";

void main() {
  const viewport = Size(800, 600);

  Future<CanvasStageState> pump(
      WidgetTester tester, CanvasController controller) async {
    var key = GlobalKey<CanvasStageState>();
    tester.view.physicalSize = viewport;
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
            width: viewport.width,
            height: viewport.height,
            child: CanvasStage(key: key, controller: controller),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  CanvasController twoBoxes() {
    var a = TextElement(
      const ElementBase(id: "a", x: 40, y: 40, width: 300, height: 60),
      text: _lorem,
      box: const BoxSpec(padding: 0),
      textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
    );
    var b = TextElement(
      const ElementBase(id: "b", x: 40, y: 260, width: 300, height: 200),
      text: "Its own words",
      box: const BoxSpec(padding: 0),
      textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
    );
    return CanvasController(CanvasDocument(
      size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
      elements: [a, b],
    ));
  }

  TextElement boxIn(CanvasController c, String id) =>
      c.document.elementById(id) as TextElement;

  testWidgets("the overflow grip says when words are hidden", (tester) async {
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("b");
    await tester.pumpAndSettle();
    expect(stage.textFlowGrips, isNotNull);
    expect(stage.textFlowGrips!.overflowing, isFalse,
        reason: "a short line in a tall box shows all of itself");

    controller.selectOnly("a");
    await tester.pumpAndSettle();
    expect(stage.textFlowGrips!.overflowing, isTrue,
        reason: "a long paragraph in a short box does not");
    expect(stage.textFlowGrips!.linked, isFalse);
    expect(stage.textFlowGrips!.receiving, isFalse);
  });

  testWidgets("dragging it onto another box flows the words into it",
      (tester) async {
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.selectOnly("a");
    await tester.pumpAndSettle();

    var from = stage.textFlowGrips!.outAt;
    var onto = stage.toStagePoint(const Offset(190, 360));
    await tester.dragFrom(from, onto - from);
    await tester.pumpAndSettle();

    expect(boxIn(controller, "a").flowTo, "b");

    // And the second box now says so: it is receiving, and the words it draws
    // are not its own.
    controller.selectOnly("b");
    await tester.pumpAndSettle();
    expect(stage.textFlowGrips!.receiving, isTrue);
  });

  testWidgets("and dragging it onto nothing takes the link away",
      (tester) async {
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.selectOnly("a");
    await tester.pumpAndSettle();
    expect(stage.textFlowGrips!.linked, isTrue);

    var from = stage.textFlowGrips!.outAt;
    await tester.dragFrom(from, const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(boxIn(controller, "a").flowTo, "",
        reason: "pulling the line off is how a chain is taken apart");
  });

  testWidgets("a link that would make a ring is refused", (tester) async {
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.selectOnly("b");
    await tester.pumpAndSettle();

    // b back onto a would close the ring, and a ring has no first box.
    var from = stage.textFlowGrips!.outAt;
    var onto = stage.toStagePoint(const Offset(190, 70));
    await tester.dragFrom(from, onto - from);
    await tester.pumpAndSettle();

    expect(boxIn(controller, "b").flowTo, "");
    expect(boxIn(controller, "a").flowTo, "b",
        reason: "and nothing else moved");
  });
}

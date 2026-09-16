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

  group("on a box too short for both", () {
    // The grips sit half way between a corner and the middle handle, so on a
    // short box they land on top of the middle handle -- and the grip was
    // asked first, so dragging the side of a short box started a link
    // instead of resizing it.
    CanvasController shortBox() {
      var a = TextElement(
        const ElementBase(id: "a", x: 100, y: 100, width: 300, height: 34),
        text: _lorem,
        box: const BoxSpec(padding: 0),
        textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
      );
      var b = TextElement(
        const ElementBase(id: "b", x: 100, y: 300, width: 300, height: 200),
        text: "Its own words",
        box: const BoxSpec(padding: 0),
        textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
      );
      return CanvasController(CanvasDocument(
        size: const CanvasSize(width: 800, ratio: CanvasRatio.wide),
        elements: [a, b],
      ));
    }

    testWidgets("the middle handle still resizes it", (tester) async {
      var controller = shortBox();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      controller.selectOnly("a");
      await tester.pumpAndSettle();

      var before = boxIn(controller, "a").base.width;
      // The middle-right handle, which on this box is a few pixels from the
      // outgoing grip.
      // The middle of the box's right edge, in document units: this box is
      // at x 100 and 300 wide, 34 high from y 100.
      var middle = stage.toStagePoint(const Offset(400, 117));
      expect((middle - stage.textFlowGrips!.outAt).distance, lessThan(20),
          reason: "otherwise this test is not asking anything");

      await tester.dragFrom(middle, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(boxIn(controller, "a").base.width, greaterThan(before + 30),
          reason: "the drag resized the box rather than pulling a link out");
      expect(boxIn(controller, "a").flowTo, isEmpty);
    });

    testWidgets("and the grip still works when it is what was aimed at",
        (tester) async {
      var controller = shortBox();
      addTearDown(controller.dispose);
      var stage = await pump(tester, controller);
      controller.selectOnly("a");
      await tester.pumpAndSettle();

      var from = stage.textFlowGrips!.outAt;
      var onto = stage.toStagePoint(const Offset(250, 400));
      await tester.dragFrom(from, onto - from);
      await tester.pumpAndSettle();
      expect(boxIn(controller, "a").flowTo, "b");
    });
  });

  testWidgets("a box being flowed into cannot be typed into", (tester) async {
    // It does not own the words it is showing: they belong to the box in
    // front of it, and typing here would be edited away by the next layout
    // with no sign it ever happened. The same goes for a box reading a
    // document -- see TextDocumentRef.
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.selectOnly("b");
    await tester.pumpAndSettle();

    // Two clicks on the selected box, which is what opens the editor.
    var at = stage.toStagePoint(const Offset(190, 360));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);

    // And the box the words belong to still opens.
    controller.selectOnly("a");
    await tester.pumpAndSettle();
    var head = stage.toStagePoint(const Offset(190, 70));
    await tester.tapAt(head);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(head);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets("the link is drawn from either end, and for a kept box",
      (tester) async {
    // A link belongs to two boxes. Drawn only from the one the words leave,
    // a chain vanished as soon as the box they arrive in was the one being
    // worked on -- and vanished entirely while something else was selected,
    // which is exactly when somebody is lining the two up.
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);
    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));

    controller.selectOnly("a");
    await tester.pumpAndSettle();
    expect(stage.textFlowLines.length, 1, reason: "the box they leave");

    controller.selectOnly("b");
    await tester.pumpAndSettle();
    expect(stage.textFlowLines.length, 1, reason: "and the box they arrive in");

    controller.clearSelection();
    await tester.pumpAndSettle();
    expect(stage.textFlowLines, isEmpty, reason: "neither, and nothing kept");

    controller.showAllBounds = true;
    await tester.pumpAndSettle();
    expect(stage.textFlowLines.length, 1,
        reason: "every box in sight keeps every link in sight with it");
    expect(stage.textFlowLines.single.overflowing, isTrue,
        reason: "and it is red, because the words do not all fit");
  });

  testWidgets("the arriving end can be dragged off to disconnect",
      (tester) async {
    // A link has two ends and either is a way to take hold of it. Without
    // this, disconnecting a box meant going to find the box in front of it
    // first -- which is the one that is somewhere else on the page.
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.selectOnly("b");
    await tester.pumpAndSettle();
    expect(stage.textFlowGrips!.receiving, isTrue);

    // Off its incoming grip and into empty space.
    await tester.dragFrom(stage.textFlowGrips!.inAt, const Offset(-260, -30));
    await tester.pumpAndSettle();
    expect(boxIn(controller, "a").flowTo, "",
        reason: "the link the words arrived by is gone");
  });

  testWidgets("and dragged onto another box to move it", (tester) async {
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);

    // A third box to move the link to.
    controller.addElement(TextElement(
      const ElementBase(id: "c", x: 420, y: 260, width: 300, height: 200),
      text: "Somewhere else",
      box: const BoxSpec(padding: 0),
      textSpec: const TextSpec(fontSize: 16, align: TextAlignSpec.left),
    ));
    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.selectOnly("b");
    await tester.pumpAndSettle();

    var from = stage.textFlowGrips!.inAt;
    var onto = stage.toStagePoint(const Offset(570, 360));
    await tester.dragFrom(from, onto - from);
    await tester.pumpAndSettle();
    expect(boxIn(controller, "a").flowTo, "c");
  });

  testWidgets("a locked join cannot be dragged, and a hidden one is not drawn",
      (tester) async {
    // A connector is structural -- the words in several boxes depend on it --
    // and it is dragged from a dot eight pixels across sitting on the same
    // outline as the resize handles.
    var controller = twoBoxes();
    addTearDown(controller.dispose);
    var stage = await pump(tester, controller);
    controller.replaceElement(boxIn(controller, "a").copyWith(flowTo: "b"));
    controller.lockJoins = true;
    controller.selectOnly("a");
    await tester.pumpAndSettle();

    await tester.dragFrom(stage.textFlowGrips!.outAt, const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(boxIn(controller, "a").flowTo, "b",
        reason: "locked, the drag does not take the link away");
    expect(stage.textFlowLines.length, 1, reason: "and it is still drawn");

    // Hidden: the line goes, the grips stay.
    controller.lockJoins = false;
    controller.hideJoins = true;
    await tester.pumpAndSettle();
    expect(stage.textFlowLines, isEmpty);
    expect(stage.textFlowGrips!.linked, isTrue,
        reason: "the grips still say there is a chain");
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

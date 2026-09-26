import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_responsive_bar_test.dart is the settings band's half of designing
// one canvas for several shapes: which shapes are marked, and the way out of
// one.

void main() {
  // The element settings' half: the two controls that only exist while a
  // document is being laid out for more than one shape.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CanvasController> bar(WidgetTester tester) async {
    var controller = CanvasController(CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.feedAd, width: 1000),
      elements: [
        ShapeElement(
            const ElementBase(id: "s", x: 100, y: 50, width: 400, height: 200)),
      ],
    ));
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1600, 900);
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
          body: CanvasSettingsPanel(controller: controller),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets("choosing another shape keeps the one being left",
      (tester) async {
    var controller = await bar(tester);
    await tester.tap(find.byKey(const ValueKey("canvasRatio")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("16:9").last);
    await tester.pumpAndSettle();

    expect(controller.document.size.ratio, CanvasRatio.wide);
    expect(controller.document.elements.single.base.layouts.keys,
        contains("feedAd"));
    expect(controller.document.targets, ["feedAd", "wide"]);
  });

  testWidgets("the shapes in play are marked in the list they come from",
      (tester) async {
    var controller = await bar(tester);
    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("canvasRatio")));
    await tester.pumpAndSettle();

    // Each marked shape carries a cross: one list, which is both the choice
    // and the set of layouts.
    expect(find.byTooltip("Stop laying out for 4:5 · Feed ad"), findsOneWidget);
    expect(find.byTooltip("Stop laying out for 1:1"), findsNothing,
        reason: "nothing is being laid out for that one");
    // The shape being looked at cannot be dropped; its cross starts it again.
    expect(find.byTooltip("Lay 16:9 out again from another shape"),
        findsOneWidget);
  });

  testWidgets("and giving one up takes its layouts with it", (tester) async {
    var controller = await bar(tester);
    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await tester.pumpAndSettle();
    expect(controller.document.elements.single.base.layouts.keys,
        contains("feedAd"));

    await tester.tap(find.byKey(const ValueKey("canvasRatio")));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Stop laying out for 4:5 · Feed ad"));
    await tester.pumpAndSettle();

    expect(controller.document.targets, isEmpty,
        reason: "one shape left is not a responsive document");
    expect(controller.document.elements.single.base.layouts, isEmpty);
  });

  testWidgets("the shape being looked at is laid out again from another",
      (tester) async {
    var controller = await bar(tester);
    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await tester.pumpAndSettle();
    // Dragged into a mess on the 16:9.
    controller.replaceElement(controller.document.elements.single
        .withBase(x: 900, y: 900, width: 20, height: 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("canvasRatio")));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Lay 16:9 out again from another shape"));
    await tester.pumpAndSettle();

    expect(controller.document.elements.single.x, isNot(900));
    expect(controller.document.targets, ["feedAd", "wide"],
        reason: "it is still a shape being designed for");
  });

  testWidgets("the element settings offer type and words per shape",
      (tester) async {
    var controller = CanvasController(CanvasDocument(
      size: const CanvasSize(ratio: CanvasRatio.feedAd, width: 1000),
      elements: [
        TextElement(const ElementBase(id: "t", width: 400, height: 100),
            text: "Spend or burn", textSpec: const TextSpec(fontSize: 60)),
      ],
    ));
    addTearDown(controller.dispose);
    controller.selectOnly("t");

    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> show() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
          home: Scaffold(body: CanvasDesignPanel(controller: controller)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // On a document made for one shape there is nothing to say.
    await show();
    expect(find.byKey(const ValueKey("elementTypeScale")), findsNothing);
    expect(find.byKey(const ValueKey("textOwnWordsHere")), findsNothing);

    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await show();

    var type = find.byKey(const ValueKey("elementTypeScale"));
    expect(type, findsOneWidget);
    await tester.ensureVisible(type);
    await tester.pumpAndSettle();
    await tester.enterText(type, "0.5");
    await tester.pump();

    var words = controller.document.elements.single as TextElement;
    expect(words.base.typeScale, 0.5);
    expect(words.textSpec.fontSize, lessThan(60),
        reason: "the type came down with the number");

    var own = find.byKey(const ValueKey("textOwnWordsHere"));
    await tester.ensureVisible(own);
    await tester.pumpAndSettle();
    await tester.tap(own);
    await tester.pumpAndSettle();
    expect((controller.document.elements.single as TextElement).base.ownText,
        isTrue);
  });
}

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
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

  testWidgets("and the list marks the shapes with a layout waiting",
      (tester) async {
    var controller = await bar(tester);
    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("canvasRatio")));
    await tester.pumpAndSettle();
    expect(find.text("• 4:5 · Feed ad"), findsWidgets,
        reason: "designed at, so marked");
    expect(find.text("1:1"), findsWidgets, reason: "and this one is not");
  });

  testWidgets("the Layouts group lists them and can give one up",
      (tester) async {
    var controller = await bar(tester);
    controller.setShape(const CanvasSize(ratio: CanvasRatio.wide, width: 1000));
    await tester.pumpAndSettle();

    expect(find.text("LAYOUTS"), findsOneWidget);
    var chip = find.byKey(const ValueKey("layoutTarget:feedAd"));
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(controller.document.targets, isEmpty,
        reason: "one shape left is not a responsive document");
  });
}

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_batch2_panels_test.dart is batch 2 of the settings panel rebuild
// (Ken, 2026-11-11): the shape, the line, the path, the button and the
// counter in the Text panel's shape -- a quick strip, then Content, Look,
// Layout, Motion and More -- their looks the Chain's, their arrival and
// leaving chosen in two, as a text's are.

void main() {
  for (var kind in [
    ElementKind.shape,
    ElementKind.line,
    ElementKind.path,
    ElementKind.button,
    ElementKind.counter,
    // Batch 3.
    ElementKind.chart,
    ElementKind.table,
  ]) {
    testWidgets("${kind.label}: a quick strip, its looks, its arrival",
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      CanvasSection.openAll = true;
      addTearDown(() => CanvasSection.openAll = false);
      var document = const CanvasDocument(frames: 96);
      var element = newElement(kind, document);
      var c = CanvasController(document.addElement(element));
      addTearDown(c.dispose);
      c.selectOnly(element.id);
      tester.view.physicalSize = const Size(420, 6000);
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
        child:
            MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("quickStrip")), findsOneWidget);
      expect(find.byKey(ValueKey("${kind.name}Looks")), findsOneWidget);
      // Its arrival, its family then which -- a chart's, its own few.
      if (kind == ElementKind.chart) {
        tester
            .widget<CanvasDropdown<ChartAnimationPreset>>(
                find.byKey(const ValueKey("chartArrival")))
            .onChanged(ChartAnimationPreset.grow);
      } else {
        var family = find.byKey(ValueKey("${kind.name}ArrivalFamily"));
        expect(family, findsOneWidget);
        tester
            .widget<CanvasDropdown<String>>(family)
            .onChanged(ElementAnimationPreset.fadeIn.family.label);
      }
      await tester.pumpAndSettle();
      var now = c.document.elementById(element.id)!;
      expect(ownClipOf(now, MotionKind.arrive), isNotNull,
          reason: "an arrival laid down");
      expect(tester.takeException(), isNull);
    });
  }
}

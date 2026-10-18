import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_element_sections_test.dart is every element's panel built the way
// a picture's is: sections that fold, each a stack of cards -- where it is
// first, the designs saved of its kind last -- and every one of them, open,
// inside an ordinary sidebar.

void main() {
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, CanvasController c) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(380, 9000);
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
          home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
  }

  /// titles is the sections' titles, down the panel.
  List<String> titles(WidgetTester tester) {
    var found = [
      for (var element in find.byType(CanvasSection).evaluate())
        (
          tester.getTopLeft(find.byWidget(element.widget)).dy,
          (element.widget as CanvasSection).title,
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (var (_, title) in found) title];
  }

  for (var kind in ElementKind.values) {
    if (kind == ElementKind.image) continue; // see canvas_panel_kit_test
    testWidgets("${kind.label} is sections of cards, open in a sidebar",
        (tester) async {
      var document = const CanvasDocument();
      var element = newElement(kind, document);
      var c = CanvasController(document.addElement(element));
      addTearDown(c.dispose);
      c.selectOnly(element.id);
      await pump(tester, c);

      var all = titles(tester);
      expect(all.first, "Position", reason: "$all");
      expect(all.last, "Presets", reason: "$all");
      expect(all.length, greaterThan(3), reason: "its own sections: $all");
      // No rule inside a section: a card is its own edge.
      expect(
          find.descendant(
              of: find.byType(CanvasSection),
              matching: find.byType(CanvasGroupRule)),
          findsNothing);
      expect(tester.takeException(), isNull,
          reason: "nothing overruns the sidebar with every section open");
    });
  }

  testWidgets("the canvas's own background is sections too", (tester) async {
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    await pump(tester, c);
    var all = titles(tester);
    expect(all, containsAllInOrder(["Pattern", "Presets"]));
    expect(all, contains("Picture"));
    expect(tester.takeException(), isNull);
  });
}

import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_editor_height_scope_test.dart is how tall a data grid opens.
//
// Reported: dragging one chart's table taller left every other chart's table
// tall too, so a chart of three rows had a hole under its settings. The
// height is kept per element now; grid-or-text is still kept per editor,
// because that is a way of working rather than a fact about what is in front
// of you.

void main() {
  group("the height a grid opens at", () {
    test("is what it wants, where nothing has been dragged or stored", () {
      expect(editorHeight(wanted: 300), 300);
    });

    test("never shorter than a floor, however little is in it", () {
      // A grid of one row is still a grid, with a header and a toolbar.
      expect(editorHeight(wanted: 10), greaterThan(100));
    });

    test("a stored height is a floor, not a ceiling", () {
      // Somebody who dragged it to 200 wants at least 200; a table that needs
      // 400 still gets 400 rather than a scrollbar.
      expect(editorHeight(stored: 200, wanted: 120), 200);
      expect(editorHeight(stored: 200, wanted: 400), 400);
    });

    test("and a height dragged this sitting is the answer", () {
      // A drag is somebody saying how tall they want it now, which beats both
      // what the content wants and what was stored.
      expect(editorHeight(dragged: 150, stored: 400, wanted: 500), 150);
    });
  });

  group("whose height it is", () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<double> show(WidgetTester tester, String scope) async {
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasDataEditorShell(
                remember: "testEditor",
                scope: scope,
                wanted: 140,
                gridTooltip: "grid",
                textTooltip: "text",
                text: (_) => const SizedBox(key: ValueKey("body")),
                grid: (_) => const SizedBox(key: ValueKey("body")),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester
          .getRect(find.byKey(const ValueKey("dataEditorBody")))
          .height;
    }

    testWidgets("one element's drag is not every element's height",
        (tester) async {
      // The complaint, stated as a test: a chart of twenty rows dragged open
      // left a chart of three with a hole under its settings.
      var first = await show(tester, "chartA");

      // Drag the grip down.
      var grip = find.byKey(const ValueKey("dataEditorGrip"));
      await tester.drag(grip, const Offset(0, 160));
      await tester.pumpAndSettle();
      var dragged =
          tester.getRect(find.byKey(const ValueKey("dataEditorBody"))).height;
      expect(dragged, greaterThan(first + 100), reason: "it did get taller");

      var second = await show(tester, "chartB");
      expect(second, first,
          reason: "another chart opens at its own height, not this one's");
    });
  });
}

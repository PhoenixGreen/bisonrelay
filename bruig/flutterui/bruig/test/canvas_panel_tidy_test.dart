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

import 'canvas_panel_helpers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_panel_tidy_test.dart is the small things about where settings sit:
// a section heading's buttons and its arrow, a dropdown or a field alone on
// its line, and a button beside a field standing on the same line as it.

void main() {
  setUpAll(() {
    CanvasSection.openAll = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDownAll(() => CanvasSection.openAll = false);

  Future<CanvasController> panel(WidgetTester tester, ElementKind kind,
      {double width = 380}) async {
    var document = const CanvasDocument();
    var element = newElement(kind, document);
    var controller = CanvasController(document.addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly(element.id);
    tester.view.physicalSize = Size(width, 6000);
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
          home: Scaffold(body: CanvasDesignPanel(controller: controller))),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  Rect at(WidgetTester tester, Finder f) => tester.getRect(f);

  group("a section's heading", () {
    testWidgets("keeps its arrow at the far right, its buttons beside it",
        (tester) async {
      // Reported on a table's Order: the refresh sat right of the arrow and
      // lower than it. The arrow is the heading's last thing, whatever
      // buttons a section has, and they stand level with it.
      // Order is a fold of the table's Content now (batch 3): its button
      // at the right end of its heading, level with it.
      await panel(tester, ElementKind.table);
      var heading =
          at(tester, find.byKey(const ValueKey("expander-tableSort")));
      var refresh = at(tester, find.byKey(const ValueKey("tableSortApply")));
      expect(refresh.left, greaterThanOrEqualTo(heading.right - 0.5));
      expect(refresh.center.dy, closeTo(heading.center.dy, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets("carries the data source's refresh, not the panel under it",
        (tester) async {
      var controller = await panel(tester, ElementKind.table);
      var id = controller.selected!.id;
      var refresh = find.byKey(ValueKey("refresh-$id"));
      expect(refresh, findsOneWidget,
          reason: "on the heading even before a source is chosen -- and "
              "only there, not a second inside the section");
      var heading =
          at(tester, find.byKey(const ValueKey("expander-tableSource")));
      expect(at(tester, refresh).center.dy, closeTo(heading.center.dy, 1));
      expect(
          at(tester, refresh).left, greaterThanOrEqualTo(heading.right - 0.5));
    });

    testWidgets("an Order's help is beside Order by, not on the heading",
        (tester) async {
      await panel(tester, ElementKind.table);
      var heading = find.byKey(const ValueKey("expander-tableSort"));
      var headingRow =
          find.ancestor(of: heading, matching: find.byType(Row)).first;
      expect(
          find.descendant(
              of: headingRow,
              matching: find.byWidgetPredicate(
                  (w) => w is CanvasHint && w.message.contains("league"))),
          findsNothing);
      // Inside the Order fold, its caption in small capitals (batch 3).
      await openFold(tester, "tableSort", shows: find.text("ORDER BY"));
      var card = find.ancestor(
          of: find.text("ORDER BY"), matching: find.byType(CanvasControlGroup));
      expect(
          find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                  (w) => w is CanvasHint && w.message.contains("league"))),
          findsOneWidget);
    });
  });

  group("a control alone on its line", () {
    testWidgets("a dropdown fills the line rather than cut its name",
        (tester) async {
      // A path's "Who follows" read "Noth…" with half its line empty: held
      // to what the Start and End under it could afford.
      await panel(tester, ElementKind.path);
      var who = at(
          tester,
          find
              .ancestor(
                  of: find.text("Who follows"),
                  matching: find.byType(CanvasDropdown<String>))
              .first);
      var space = at(tester, find.text("Space the points evenly"));
      var start = at(tester, find.byKey(const ValueKey("pathStartFrame")));
      var end = at(tester, find.byKey(const ValueKey("pathEndFrame")));
      expect(who.left, closeTo(start.left, 0.5));
      expect(who.right, closeTo(end.right, 0.5), reason: "$who vs $end");
      expect(space.width, greaterThan(0));
    });

    testWidgets("a text field fills the line", (tester) async {
      // The chart's axis names sat alone on their lines at seventy pixels,
      // cutting "Price - Year" to "rice - Yea".
      await panel(tester, ElementKind.chart);
      var x = find.byWidgetPredicate(
          (w) => w is CanvasTextField && w.hint == "X label");
      var title = find
          .byWidgetPredicate((w) => w is CanvasTextField && w.hint == "Title");
      expect(at(tester, x).width, closeTo(at(tester, title).width, 0.5));
    });
  });

  testWidgets("a video's Add stands on the line its link is typed on",
      (tester) async {
    // The button's box ended ten pixels below the link's underline: the
    // field was drawn at its own height at the top of its box.
    await panel(tester, ElementKind.video);
    var add = at(tester, find.byKey(const ValueKey("videoAdd")));
    var link = find.byKey(const ValueKey("videoLink"));
    var words = at(
        tester, find.descendant(of: link, matching: find.byType(EditableText)));
    // In a rebuilt (dense) panel the field is a box with its words inside
    // it: the button stands level with the box, and the words are in it.
    var field = at(tester, link);
    expect(add.bottom, closeTo(field.bottom, 1),
        reason: "button $add, field $field");
    expect(words.bottom, lessThanOrEqualTo(field.bottom),
        reason: "words $words inside $field");
  });
}

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'canvas_panel_helpers.dart';

// canvas_control_wrap_test.dart is the settings panel filling the width it has
// been given.
//
// A sidebar is a column of unknown width that people drag. A row of
// fixed-width boxes in one leaves a ragged margin down the right that gets
// wider the wider the panel is -- and the wider it gets, the more it reads as
// a panel that has not been finished.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 420}) async {
    tester.view.physicalSize = Size(width, 1400);
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
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> panel(WidgetTester tester, {double width = 420}) async {
    // A shape, its Layout open: where every element's place is laid out
    // since the rebuild, as the prototype's rows.
    var document = const CanvasDocument();
    var element = newElement(ElementKind.shape, document);
    var controller = CanvasController(document.addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly(element.id);
    await pump(tester, CanvasDesignPanel(controller: controller), width: width);
    await openSection(tester, "shape.layout");
  }

  Rect at(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  group("where it is", () {
    testWidgets(
        "its place and turn on one line, its size and opacity on the next, "
        "in the same columns", (tester) async {
      await panel(tester, width: 420);
      var top = [
        for (var k in ["elementX", "elementY", "elementAngle"]) at(tester, k)
      ];
      var next = [
        for (var k in ["elementW", "elementH", "elementOpacity"]) at(tester, k)
      ];
      for (var row in [top, next]) {
        for (var r in row) {
          expect(r.top, closeTo(row.first.top, 0.5), reason: "$row");
          expect(r.width, closeTo(row.first.width, 0.5), reason: "$row");
        }
      }
      expect(next.first.top, greaterThan(top.first.bottom));
      for (var i = 0; i < 3; i++) {
        expect(next[i].left, closeTo(top[i].left, 0.5), reason: "column $i");
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets("and narrows again with the sidebar", (tester) async {
      await panel(tester, width: 420);
      var wide = at(tester, "elementX").width;
      await panel(tester, width: 300);
      var narrow = at(tester, "elementX").width;
      expect(narrow, lessThan(wide));
      expect(tester.takeException(), isNull);
    });
  });

  group("the text element's type card", () {
    testWidgets("has the face and its size on one line, neither cut",
        (tester) async {
      // As the prototype's quick strip: the face and its size side by side,
      // each filling its share; too narrow for both, one under the other
      // rather than a name cut short (see panelRow).
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller), width: 360);

      var font = tester.getRect(find.byKey(const ValueKey("typeFont")));
      // A new text is fitted to its box, and its Size says so.
      expect(find.text("Size (fitted)"), findsOneWidget);
      var size = tester.getRect(find.byKey(const ValueKey("typeSize")));
      expect(size.top, closeTo(font.top, 0.5), reason: "one line");
      expect(font.right, lessThanOrEqualTo(size.left + 0.5));
      expect(font.width, greaterThanOrEqualTo(110), reason: "room for a name");
      expect(size.right, lessThanOrEqualTo(360 + 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group("a path's settings", () {
    Future<String> path(WidgetTester tester, double width) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.path, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller),
          width: width);
      return element.id;
    }

    testWidgets("give each point's numbers the room the line has",
        (tester) async {
      // One point is a row of three numbers and two buttons, and it was a
      // plain Wrap -- so where every other line of settings reached the
      // right-hand margin, the list of points stopped a third of the way
      // across and left the rest of every row empty.
      var id = await path(tester, 420);
      var frame = tester.getRect(find.byKey(ValueKey("node-frame-0-$id")));
      var x = tester.getRect(find.byKey(ValueKey("node-x-0-$id")));
      var y = tester.getRect(find.byKey(ValueKey("node-y-0-$id")));
      // The frame and X share a line and reach the card's far side...
      expect(x.top, closeTo(frame.top, 0.5));
      expect(x.right, greaterThan(420 - 60), reason: "$x");
      // ...and Y, wrapped under them, keeps their column rather than
      // filling a line of its own: a list of points is read down the page.
      expect(y.left, closeTo(frame.left, 0.5));
      expect(y.width, closeTo(frame.width, 0.5));

      // Narrower, a number with a line to itself has the whole of it.
      id = await path(tester, 300);
      var narrow = tester.getRect(find.byKey(ValueKey("node-x-0-$id")));
      expect(narrow.right, greaterThan(300 - 60), reason: "$narrow");
    });

    testWidgets("keep the two frames on one line", (tester) async {
      // Who follows has the width of the card to itself; the start and the
      // end of the run share the line under it.
      await path(tester, 380);
      var start = tester.getRect(find.byKey(const ValueKey("pathStartFrame")));
      var end = tester.getRect(find.byKey(const ValueKey("pathEndFrame")));
      expect(end.top, closeTo(start.top, 0.5));
      expect(end.right, lessThanOrEqualTo(380 + 0.5));
    });
  });

  group("opening a more-settings button", () {
    Future<void> text(WidgetTester tester, double width) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller),
          width: width);
    }

    testWidgets("in a card, there is no button: everything is out",
        (tester) async {
      // A section already folds; a button inside a card hiding the rest was
      // a setting found twice over.
      await text(tester, 300);
      expect(find.byKey(const ValueKey("more-textBox")), findsNothing);
      expect(find.byKey(const ValueKey("boxBorder")), findsOneWidget);
    });

    testWidgets("and the sides, the corners and the room line up",
        (tester) async {
      // Split into one each, the border's sides, the corners and the
      // padding's sides are three blocks of four, one under another, in the
      // same columns.
      await text(tester, 360);
      for (var link in ["boxBorderLink", "boxRadiusLink", "boxPaddingLink"]) {
        await tester.ensureVisible(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
      }

      var sides = tester.getRect(find.byKey(const ValueKey("boxBorderTop")));
      for (var key in ["boxRadius↖", "boxPadTop"]) {
        var box = tester.getRect(find.byKey(ValueKey(key)));
        expect(box.left, closeTo(sides.left, 0.5), reason: key);
        expect(box.width, closeTo(sides.width, 0.5), reason: key);
      }
      expect(tester.takeException(), isNull);

      // Joined again, for the tests after this one.
      for (var link in ["boxBorderLink", "boxRadiusLink", "boxPaddingLink"]) {
        await tester.ensureVisible(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(link)));
        await tester.pumpAndSettle();
      }
    });
  });

  // Outside a section -- several elements picked, a dialog -- groups are
  // still a run of captioned lines, ruled off and spaced by the numbers in
  // controls.dart. A host of their own, since no element's panel is one.
  Future<void> flat(WidgetTester tester) => pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: CanvasControlScope(
              maxWidth: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CanvasControlGroup(label: "One", children: [
                    CanvasNumberField(
                        key: const ValueKey("a"),
                        label: "A",
                        value: 1,
                        onChanged: (v) {}),
                    const CanvasLineBreak(),
                    CanvasNumberField(
                        key: const ValueKey("b"),
                        label: "B",
                        value: 2,
                        onChanged: (v) {}),
                  ]),
                  CanvasControlGroup(label: "Two", rule: false, children: [
                    CanvasNumberField(
                        key: const ValueKey("c"),
                        label: "C",
                        value: 3,
                        onChanged: (v) {}),
                  ]),
                  CanvasMoreGroup(
                    label: "Three",
                    remember: "flatMore",
                    row: [
                      CanvasNumberField(
                          key: const ValueKey("d"),
                          label: "D",
                          value: 4,
                          onChanged: (v) {}),
                    ],
                    more: [
                      CanvasNumberField(
                          key: const ValueKey("e"),
                          label: "E",
                          value: 5,
                          onChanged: (v) {}),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  group("the space between groups", () {
    testWidgets("is the same above a rule as below it", (tester) async {
      // Nearer one group than the other, a rule reads as belonging to that
      // one -- which is the opposite of what a divider is for.
      await flat(tester);
      var rule = tester.getRect(find.byType(CanvasGroupRule).first);
      var above = tester.getRect(find.byKey(const ValueKey("b")));
      var below = tester.getRect(find.text("TWO"));
      expect(rule.top, closeTo(above.bottom, 0.5));
      expect(rule.height, closeTo(canvasGroupGap + 1, 0.5),
          reason: "the gap above the line, and the line");
      expect(below.top - rule.bottom, closeTo(canvasGroupGap, 0.5));
    });

    testWidgets("and the same below a group with no rule under it",
        (tester) async {
      await flat(tester);
      var c = tester.getRect(find.byKey(const ValueKey("c")));
      var three = tester.getRect(find.text("THREE"));
      expect(three.top - c.bottom, closeTo(canvasGroupGap, 1.5));
    });

    testWidgets("and a line of a group is the row gap from the next",
        (tester) async {
      await flat(tester);
      var a = tester.getRect(find.byKey(const ValueKey("a")));
      var b = tester.getRect(find.byKey(const ValueKey("b")));
      expect(b.top - a.bottom, closeTo(canvasRowGap, 0.5));
    });
  });

  group("an opened more-settings area", () {
    testWidgets("is drawn on a ground of its own", (tester) async {
      // Opened, these settings run straight into whatever is below them, and
      // a reader who has scrolled past the button has nothing saying which of
      // the controls in front of them came out of it.
      await flat(tester);
      Finder ground() => find.byKey(const ValueKey("more-ground"));
      expect(ground(), findsNothing);

      var button = find.byKey(const ValueKey("more-flatMore"));
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(ground(), findsOneWidget);
      var area = tester.getRect(ground());
      var inner = tester.getRect(find.byKey(const ValueKey("e")));
      expect(area.top, lessThan(inner.top),
          reason: "the settings it holds are inside it");
      expect(area.bottom, greaterThan(inner.bottom));
      expect(area.width, greaterThan(300),
          reason: "the width of the panel, not of a control: $area");
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(area.top),
          reason: "and it starts under the button that opened it");

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(ground(), findsNothing);
    });
  });

  group("a dropdown whose options are drawn", () {
    testWidgets("fits a slot narrower than its picture", (tester) async {
      // A style's picture is wider than the room a narrow panel leaves the
      // name of the one chosen: cut off, not an overflow.
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 60,
            child: CanvasDropdown<int>(
              label: "Style",
              value: 1,
              width: 41,
              grow: false,
              options: const [(1, "Dots"), (2, "Rings")],
              leading: (v) => const SizedBox(width: 36, height: 16),
              onChanged: (v) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group("a control that is not in one", () {
    testWidgets("stays the width it asked for", (tester) async {
      // A field in a dialog, or anywhere else that is not a line of settings,
      // has nothing to fill: "however much room there is" in an unknown
      // parent is how a sixty-pixel field ends up four hundred wide.
      await pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: Wrap(children: [
              CanvasNumberField(
                key: const ValueKey("loose"),
                label: "X",
                value: 4,
                onChanged: (v) {},
              ),
            ]),
          ),
        ),
      );
      // 62 as asked, and the room a captioned control keeps to its right.
      expect(at(tester, "loose").width, closeTo(62 + canvasCaptionedGap, 0.5));
    });
  });
}

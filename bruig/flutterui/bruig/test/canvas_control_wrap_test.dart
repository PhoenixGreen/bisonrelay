import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_control_wrap_test.dart is the settings panel filling the width it has
// been given.
//
// A sidebar is a column of unknown width that people drag. A row of
// fixed-width boxes in one leaves a ragged margin down the right that gets
// wider the wider the panel is -- and the wider it gets, the more it reads as
// a panel that has not been finished.

void main() {
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
    var element = ChartElement(
      const ElementBase(id: "c", width: 400, height: 300),
      data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
    );
    var controller =
        CanvasController(const CanvasDocument().addElement(element));
    addTearDown(controller.dispose);
    controller.selectOnly("c");
    await pump(tester, CanvasDesignPanel(controller: controller), width: width);
  }

  Rect at(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  group("a row of controls", () {
    testWidgets("fills the width it is given", (tester) async {
      // The four that say where the element is and how big it is are one line,
      // and between them they reach the right-hand margin.
      await panel(tester, width: 420);
      var row = ["elementX", "elementY", "elementW", "elementH"];
      var boxes = [for (var key in row) at(tester, key)];

      for (var i = 1; i < boxes.length; i++) {
        expect(boxes[i].top, closeTo(boxes[0].top, 0.5),
            reason: "${row[i]} wrapped onto a line of its own");
      }
      expect(boxes.last.right, greaterThan(420 - 60),
          reason: "the line stops well short of the margin: ${boxes.last}");
    });

    testWidgets("and gives the same width to each of them", (tester) async {
      await panel(tester, width: 420);
      var widths = [
        for (var key in ["elementX", "elementY", "elementW", "elementH"])
          at(tester, key).width
      ];
      for (var width in widths) {
        expect(width, closeTo(widths.first, 0.5), reason: "$widths");
      }
    });

    testWidgets("so the line below it lands in the same columns",
        (tester) async {
      // Angle under X and Opacity under Y. The room left over is shared out
      // by the same amount on every line rather than by filling each one, so
      // a line of four and a line of two come out in the same columns.
      await panel(tester, width: 420);
      var x = at(tester, "elementX");
      var angle = at(tester, "elementAngle");

      expect(angle.left, closeTo(x.left, 0.5));
      expect(angle.width, closeTo(x.width, 0.5));
      expect(angle.top, greaterThan(x.bottom), reason: "on the line below");
    });

    testWidgets("and narrows again with the sidebar", (tester) async {
      await panel(tester, width: 420);
      var wide = at(tester, "elementX").width;

      await panel(tester, width: 300);
      var narrow = at(tester, "elementX").width;

      expect(narrow, lessThan(wide));
      expect(narrow, greaterThanOrEqualTo(67),
          reason: "never below the width it asked for");
    });
  });

  group("a field", () {
    testWidgets("is drawn the full height of the row it sits in",
        (tester) async {
      // A field is given a row's height to sit in, but the decoration is drawn
      // at whatever its own padding adds up to and sits at the top of that
      // row. With no padding at all -- which is what every number on this
      // panel had -- that is eighteen pixels of field in a twenty-seven pixel
      // row: a line under the words sitting nine pixels high of where the eye
      // puts it, beside a button that does fill the row.
      await panel(tester, width: 420);

      for (var key in ["elementX", "elementY", "elementAngle"]) {
        var slot = find.byKey(ValueKey(key));
        await tester.ensureVisible(slot);
        await tester.pumpAndSettle();
        // The border is painted by the decoration, not by the box around it.
        var drawn = tester.getRect(
            find.descendant(of: slot, matching: find.byType(CustomPaint)));
        expect(drawn.height, closeTo(controlHeight, 0.5), reason: key);
        expect(drawn.bottom, closeTo(tester.getRect(slot).bottom, 0.5),
            reason: "$key is drawn short of the foot of its row");
      }
    });

    testWidgets("and stands level with the button beside it", (tester) async {
      await panel(tester, width: 420);
      var field = find.byKey(const ValueKey("elementH"));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      var drawn = tester.getRect(
          find.descendant(of: field, matching: find.byType(CustomPaint)));
      var lock = tester.getRect(find.byIcon(Icons.link_off).first);
      expect(drawn.height, greaterThanOrEqualTo(lock.height - 0.5));
      expect(drawn.center.dy, closeTo(lock.center.dy, 1.5));
    });
  });

  group("every element's settings", () {
    testWidgets("stay inside a narrow sidebar", (tester) async {
      // Every kind, from the factory the Add panel uses, so a kind added later
      // is covered by this without anybody remembering to list it here.
      //
      // A control wider than the line it is on is not something a wrapping
      // layout can fix: it overflows, and what that looks like is a field with
      // its right-hand edge off the panel and a number nobody can finish
      // typing.
      const width = 300.0;
      for (var kind in ElementKind.values) {
        var document = const CanvasDocument();
        var element = newElement(kind, document);
        var controller = CanvasController(document.addElement(element));
        addTearDown(controller.dispose);
        controller.selectOnly(element.id);
        await pump(tester, CanvasDesignPanel(controller: controller),
            width: width);

        for (var of in [
          find.byType(CanvasNumberField),
          find.byType(CanvasTextField),
          find.byType(CanvasToggle),
          find.byType(CanvasIconButton),
        ]) {
          for (var i = 0; i < of.evaluate().length; i++) {
            var box = tester.getRect(of.at(i));
            expect(box.right, lessThanOrEqualTo(width + 0.5),
                reason: "${kind.label}: a control runs off the panel: $box");
          }
        }
      }
    });
  });

  group("the text element's type line", () {
    Future<void> text(WidgetTester tester, double width) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller),
          width: width);
    }

    testWidgets("holds all five settings and the button in a narrow sidebar",
        (tester) async {
      // The face, the size, the weight, italic, underline and the button that
      // opens the rest. The first dropdown asked for a hundred and eighteen
      // pixels, which is what pushed the two switches onto a line of their
      // own the moment anybody pulled the sidebar in.
      await text(tester, 300);

      // The whole control, not the caption or the icon inside it: a caption
      // is eleven pixels tall and the switch beside it twenty-seven, so on
      // one line their tops are fourteen apart. Every control on this panel
      // reserves the caption's height above itself, words or no words, so
      // the boxes are all the same height and start level.
      Finder box(Finder of, Type type) =>
          find.ancestor(of: of, matching: find.byType(type));
      var top =
          tester.getRect(box(find.text("Font"), CanvasDropdown<String>)).top;
      for (var (what, of) in <(String, Finder)>[
        ("Size", box(find.text("Size"), CanvasNumberField)),
        ("Weight", box(find.text("Weight"), CanvasDropdown<int>)),
        ("Italic", box(find.byTooltip("Italic"), CanvasIconButton)),
        ("Underline", box(find.byTooltip("Underline"), CanvasIconButton)),
        ("the button", find.byKey(const ValueKey("more-textType"))),
      ]) {
        expect(tester.getRect(of).top, closeTo(top, 0.5),
            reason: "$what is on a line of its own");
      }
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
      var id = await path(tester, 300);
      var narrow = tester.getRect(find.byKey(ValueKey("node-x-0-$id"))).width;

      id = await path(tester, 420);
      var wide = tester.getRect(find.byKey(ValueKey("node-x-0-$id"))).width;
      expect(wide, greaterThan(narrow));

      // And the three of them in columns, which is what makes a list of
      // points readable down the page rather than across it.
      var frame = tester.getRect(find.byKey(ValueKey("node-frame-0-$id")));
      for (var key in ["node-x-0-$id", "node-y-0-$id"]) {
        expect(tester.getRect(find.byKey(ValueKey(key))).width,
            closeTo(frame.width, 0.5),
            reason: key);
      }
    });

    testWidgets("keep Who follows on one line with the frames and the button",
        (tester) async {
      // The dropdown asked for a hundred and seventy-six pixels, which pushed
      // the two frame fields and the button onto a line of their own the
      // moment anybody pulled the sidebar in.
      await path(tester, 300);
      var foot = tester
          .getRect(find.ancestor(
              of: find.text("Who follows"),
              matching: find.byType(CanvasDropdown<String>)))
          .bottom;
      for (var (what, of) in <(String, Finder)>[
        ("Start", find.byKey(const ValueKey("pathStartFrame"))),
        ("End", find.byKey(const ValueKey("pathEndFrame"))),
        ("the button", find.byKey(const ValueKey("more-pathFollowMore"))),
      ]) {
        expect(tester.getRect(of).bottom, closeTo(foot, 0.5),
            reason: "$what is on a line of its own");
      }
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

    Future<void> open(WidgetTester tester, String key) async {
      var button = find.byKey(ValueKey(key));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets("leaves the row the button is on exactly as it was",
        (tester) async {
      // The room left over is shared by the smallest amount any line can
      // afford, so that the lines of a group come out in the same columns.
      // Across the button that is wrong: the line revealed afforded less, so
      // opening it pulled the row above in. Settings already on screen moving
      // when something appears under them is the one thing a reveal must not
      // do.
      // Narrow enough that the four side fields the button reveals afford
      // less than the row above them, which is the case this is about. On a
      // wide panel there is slack everywhere and nothing moves either way.
      await text(tester, 300);
      var field = find.byKey(const ValueKey("boxBorder"));
      var shut = tester.getRect(field);

      await open(tester, "more-textBox");
      expect(tester.getRect(field).width, closeTo(shut.width, 0.5));
      expect(tester.getRect(field).left, closeTo(shut.left, 0.5));

      // Shut again: an opened area stays open for the rest of the file.
      await open(tester, "more-textBox");
    });

    testWidgets("and the sides, the corners and the room line up",
        (tester) async {
      // Three rows of four numbers, one under another. The corners asked for
      // fifty pixels against the sides' fifty-six, which is six pixels a
      // column and a row visibly out of step with the two around it.
      await text(tester, 360);
      await open(tester, "more-textBox");

      var sides = tester.getRect(find.byKey(const ValueKey("boxBorderLeft")));
      for (var key in ["boxRadius↖", "boxPadLeft"]) {
        var box = tester.getRect(find.byKey(ValueKey(key)));
        expect(box.left, closeTo(sides.left, 0.5), reason: key);
        expect(box.width, closeTo(sides.width, 0.5), reason: key);
      }

      await open(tester, "more-textBox");
    });
  });

  group("the lines down a panel", () {
    testWidgets("are one: the one under where the element sits",
        (tester) async {
      // Most elements are one run of lines answering one question -- what is
      // this path, what is this button, what does this picture look like --
      // and a rule between each pair turned that into five answers. What is
      // left is the gap, which is why it is three times the gap between two
      // lines of one group.
      //
      // The position row keeps its rule, because where an element sits really
      // is a different subject from what it is.
      //
      // Not every kind: a chart and a table are several subjects and say so.
      for (var kind in [
        ElementKind.line,
        ElementKind.button,
        ElementKind.shape,
        ElementKind.path,
        ElementKind.image,
        ElementKind.counter,
        ElementKind.player,
      ]) {
        var document = const CanvasDocument();
        var element = newElement(kind, document);
        var controller = CanvasController(document.addElement(element));
        addTearDown(controller.dispose);
        controller.selectOnly(element.id);
        await pump(tester, CanvasDesignPanel(controller: controller),
            width: 420);

        expect(find.byType(CanvasGroupRule), findsOneWidget,
            reason: "${kind.label} draws more than the position rule");
      }
    });
  });

  group("the space between groups", () {
    testWidgets("is the same above a rule as below it", (tester) async {
      // Nearer one group than the other, a rule reads as belonging to that
      // one -- which is the opposite of what a divider is for. It was twelve
      // above and sixteen below, on every group in the panel.
      await panel(tester, width: 420);

      var rules = find.byType(CanvasGroupRule);
      expect(rules, findsWidgets);
      // The rule carries the gap above the line inside itself, so its box
      // starts where the group above it ends.
      var rule = tester.getRect(rules.first);
      var above = tester.getRect(find.byKey(const ValueKey("elementAngle")));
      var below = tester.getRect(find.byKey(const ValueKey("elementPresets")));

      expect(rule.top, closeTo(above.bottom, 0.5));
      expect(rule.height, closeTo(canvasGroupGap + 1, 0.5),
          reason: "the gap above the line, and the line");
      expect(below.top - rule.bottom, closeTo(canvasGroupGap, 0.5));
    });

    testWidgets("and the same below a group with no rule under it",
        (tester) async {
      // Two groups with nothing between them used to sit a row gap apart, on
      // the grounds that an unruled group is one the next continues. That is
      // true of two groups and false of five: a run of them reads as one
      // undivided block, and the rules were the only thing holding it apart.
      await panel(tester, width: 420);

      // The text element's box row, and the columns line under it. Neither
      // has a rule: they are two of the five lines that answer "how do these
      // words look".
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller), width: 420);

      var box = tester.getRect(find.byKey(const ValueKey("boxBorder")));
      var columns = tester.getRect(find.text("COLUMNS"));
      expect(find.byType(CanvasGroupRule), findsWidgets);
      expect(columns.top - box.bottom, closeTo(canvasGroupGap, 1.5));
    });

    testWidgets("and a line of a group is the row gap from the next",
        (tester) async {
      // X Y W H, then Angle and Opacity under them: two lines of one group,
      // which is a closer thing than two groups.
      await panel(tester, width: 420);
      var x = tester.getRect(find.byKey(const ValueKey("elementX")));
      var angle = tester.getRect(find.byKey(const ValueKey("elementAngle")));
      expect(angle.top - x.bottom, closeTo(canvasRowGap, 0.5));
    });
  });

  group("an opened more-settings area", () {
    testWidgets("is closed off by a line across the foot of it",
        (tester) async {
      // Opened, these settings run straight into whatever is below them, and
      // a reader who has scrolled past the button has nothing saying where
      // one group's overflow stops and the next group starts.
      await panel(tester, width: 420);
      expect(find.byType(CanvasMoreEnd), findsNothing);

      var button = find.byKey(const ValueKey("more-chartGridMore"));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(CanvasMoreEnd), findsOneWidget);
      var line = tester.getRect(find.byType(CanvasMoreEnd));
      var lines = tester.getRect(find.byKey(const ValueKey("chartAxisSteps")));
      expect(line.top, greaterThan(lines.bottom - 0.5),
          reason: "under the settings it closes off");
      expect(line.width, greaterThan(300),
          reason: "the width of the panel, not of a control: $line");

      // Shut it again: an open button stays open for the rest of the file.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(CanvasMoreEnd), findsNothing);
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
      // 62 as asked, and the five pixels of room every control keeps to its
      // right.
      expect(at(tester, "loose").width, closeTo(67, 0.5));
    });
  });
}

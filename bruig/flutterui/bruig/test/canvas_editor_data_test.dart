import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'dart:io';
import 'dart:convert';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/data/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/data/table_data_editor.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart' show OwnStyle;
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/canvas_panel_helpers.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';

// canvas_editor_data_test.dart is a table's and a chart's settings: their
// look, numbers, animation and own data source.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);

  group("a table's settings", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var element = TableElement(
        const ElementBase(id: "t", width: 400, height: 200),
        rows: const [
          ["Team", "Points"],
          ["Hull City", "6"],
        ],
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    TableElement tableIn(CanvasController controller) =>
        controller.document.elements.single as TableElement;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// showStyle opens the Style section if it is shut, and hands back what
    /// closes it again.
    ///
    /// Only if, and only what this test opened: an expander remembers whether
    /// it was open and that memory outlives the test, so a blind tap leaves
    /// the next test looking at a panel it did not ask for.
    Future<Future<void> Function()> showStyle(WidgetTester tester) async {
      var open =
          find.byKey(const ValueKey("tablePadding")).evaluate().isNotEmpty;
      if (!open) await press(tester, find.text("STYLE"));
      return () async {
        if (!open) await press(tester, find.text("STYLE"));
      };
    }

    testWidgets("the padding can be asked for a side at a time",
        (tester) async {
      // One figure until somebody wants four: almost every table wants the
      // same room on every side.
      var controller = await panel(tester);
      var shut = await showStyle(tester);
      expect(find.byKey(const ValueKey("tablePadding")), findsOneWidget);
      expect(find.byKey(const ValueKey("tablePadTop")), findsNothing);

      await press(tester, find.byKey(const ValueKey("tableSidedPadding")));
      for (var side in ["Top", "Right", "Bottom", "Left"]) {
        expect(find.byKey(ValueKey("tablePad$side")), findsOneWidget);
      }
      // Switched on, nothing has changed yet: each side starts where the one
      // figure left it.
      expect(tableIn(controller).topPad, tableIn(controller).cellPadding);

      await enterValue(tester, find.byKey(const ValueKey("tablePadTop")), "30");
      await tester.pumpAndSettle();
      expect(tableIn(controller).topPad, 30);
      expect(tableIn(controller).leftPad, tableIn(controller).cellPadding,
          reason: "one side, not all of them");

      await press(tester, find.byKey(const ValueKey("tableSidedPadding")));
      expect(tableIn(controller).evenPadding, isTrue);
      expect(find.byKey(const ValueKey("tablePadTop")), findsNothing);
      await shut();
    });

    testWidgets("and the columns can be put back", (tester) async {
      // A column width is dragged on the table itself, and there was no way
      // back from it.
      var controller = await panel(tester);
      controller.replaceElement(
          tableIn(controller).copyWith(columnWidths: const [0.8, 0.2]));
      await tester.pumpAndSettle();
      var shut = await showStyle(tester);

      var sizing = find.byKey(const ValueKey("tableColumnSizing"));
      expect(sizing, findsOneWidget);
      // Three states, and the third only while the columns are in it: a
      // dragged table is neither of the two a reader can ask for.
      expect(
          tester
              .widget<CanvasDropdown<String>>(sizing)
              .options
              .map((o) => o.$1),
          ["fit", "even", "dragged"]);

      await press(tester, sizing);
      await press(tester, find.text("All the same").last);
      expect(tableIn(controller).columnWidths, [0.5, 0.5]);

      await press(tester, find.byKey(const ValueKey("tableColumnSizing")));
      await press(tester, find.text("Fit to contents").last);
      expect(tableIn(controller).evenColumns, isTrue);
      expect(
          tester
              .widget<CanvasDropdown<String>>(
                  find.byKey(const ValueKey("tableColumnSizing")))
              .options
              .map((o) => o.$1),
          ["fit", "even"],
          reason: "nothing is dragged any more, so there is no such state");
      await shut();
    });

    testWidgets("Refresh is on the Table section as well as the Data one",
        (tester) async {
      // Where somebody is standing when they want the numbers again: looking
      // at the cells. Sending them to another section to press the same
      // button is asking them to know which section owns the wire.
      var controller = await panel(tester);
      // Nothing to read yet, so no button: a heading does not carry one that
      // could never do anything.
      expect(byTip("Read the data and put it in the table"), findsNothing);

      controller.replaceElement(tableIn(controller).copyWith(
          source: const DataSource(kind: DataKind.file)
              .copyWith(where: "/nowhere/none.json")));
      await tester.pumpAndSettle();

      // One on the Table section and one on the Data section, both saying
      // the same thing.
      expect(byTip("Read the data and put it in the table"), findsNWidgets(2));
    });

    testWidgets("typing a coin offers the coins", (tester) async {
      // Only where the rows are what the source is asked for, and only in the
      // column that names one: a suggestion against a column of numbers is a
      // list nobody wants over their typing.
      var controller = await panel(tester);
      controller.replaceElement(tableIn(controller).copyWith(
        rows: const [
          ["Coin", "Price"],
          ["", "0"],
        ],
        source: coinGeckoMarkets
            .applyTo(const DataSource(), coinGeckoMarkets.choices.first.$1)
            .copyWith(fromRows: true),
      ));
      await tester.pumpAndSettle();

      var toGrid = byTip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      // The empty cell under the Coin heading.
      var cells = find.byType(CanvasGridCell);
      expect(cells, findsWidgets);
      var named = tester
          .widgetList<CanvasGridCell>(cells)
          .where((cell) => cell.suggestions.isNotEmpty)
          .toList();
      expect(named, isNotEmpty, reason: "the column that names a row");
      expect(named.first.suggestions, contains("Decred"));
      expect(named.length, 1,
          reason: "one cell: the body of the match column, not its heading "
              "and not the column of prices");
    });

    testWidgets("and a table of typed numbers offers none", (tester) async {
      var controller = await panel(tester);
      await tester.pumpAndSettle();
      var toGrid = byTip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);
      for (var cell
          in tester.widgetList<CanvasGridCell>(find.byType(CanvasGridCell))) {
        expect(cell.suggestions, isEmpty);
      }
      expect(controller.document.elements, hasLength(1));
    });

    testWidgets("a row and a column can be moved", (tester) async {
      // Buttons rather than dragging: a row added at the end and wanted
      // second is one press away either way, and a drag inside a grid of text
      // fields has to be told apart from selecting text in one of them.
      var controller = await panel(tester);
      var toGrid = byTip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      expect(tableIn(controller).rows.first.first, "Team");
      await press(tester, byTip("Move this row down").first);
      expect(tableIn(controller).rows.first.first, "Hull City",
          reason: "the header has gone under the row that was below it");

      await press(tester, byTip("Move this column right").first);
      expect(tableIn(controller).rows.first, ["6", "Hull City"]);
    });

    testWidgets("the ends of the table have nowhere further to go",
        (tester) async {
      var controller = await panel(tester);
      var toGrid = byTip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      // The first row's "up" and the last row's "down" are there and do
      // nothing, rather than being missing and shuffling the other buttons
      // along by one on every row.
      var up = tester.widget<CanvasIconButton>(find
          .ancestor(
              of: byTip("Move this row up").first,
              matching: find.byType(CanvasIconButton))
          .first);
      expect(up.onPressed, isNull);
      expect(tableIn(controller).rows.first.first, "Team");
    });

    testWidgets("a rule can be added and taken away from the same line",
        (tester) async {
      // Adding and removing in the same place, rather than one here and one
      // at the foot of a section that has to be opened first.
      var controller = await panel(tester);
      // In the Special cells fold of its Content (batch 3).
      await openFold(tester, "tableRules", shows: byTip("Add a rule"));
      expect(byTip("Add a rule"), findsOneWidget);

      await press(tester, byTip("Add a rule"));
      expect(tableIn(controller).rules.length, 1);

      // At the foot of the rule it removes rather than beside Add: one button
      // per rule on one line is fine for two rules and is twenty buttons for
      // twenty.
      expect(byTip("Remove this rule"), findsNothing,
          reason: "the rule is closed");
      await openFold(tester, "tableRule0", shows: byTip("Remove this rule"));
      await press(tester, byTip("Remove this rule"));
      expect(tableIn(controller).rules, isEmpty);
    });

    /// sections is every section's title, in the order they are laid out
    /// down the panel.
    List<String> sections(WidgetTester tester) {
      var found = [
        for (var element in find.byType(CanvasSection).evaluate())
          (
            tester.getTopLeft(find.byWidget(element.widget)).dy,
            (element.widget as CanvasSection).title,
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (var (_, label) in found) label];
    }

    testWidgets("the cells are a section of their own", (tester) async {
      // The longest thing in these settings and the least often changed once
      // it is right, so it was pushing everything else off the bottom.
      await panel(tester);
      // A fold of their own, open, at the head of its Content.
      expect(sections(tester), contains("Content"));
      expect(find.text("2 rows, 2 columns"), findsOneWidget);
      expect(find.byType(TableDataEditor), findsOneWidget);
    });

    testWidgets("the presets list says what it is for", (tester) async {
      // The list is never blank. With nothing saved it offers to save this
      // design -- an empty box at the top of every element's settings says
      // nothing at all -- and nothing to rename or throw away until
      // something has been chosen.
      //
      // Nothing ships with the app any more, so this is what a fresh
      // install shows. What a saved one does is in
      // canvas_element_presets_test, where there is a temp folder to save
      // into.
      await panel(tester);
      var list = find.byKey(const ValueKey("elementPresets"));
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();

      expect(find.text("Save this design"), findsOneWidget);
      expect(find.byKey(const ValueKey("elementPresetSave")), findsOneWidget,
          reason: "and the button that does it");
      expect(find.byKey(const ValueKey("elementPresetRename")), findsNothing);
      expect(find.byKey(const ValueKey("elementPresetRemove")), findsNothing);
    });

    testWidgets("the panel is ordered by what it is about", (tester) async {
      // The cells, then where they come from, then their order -- what the
      // table says -- and only after that how it looks. The look is two sets
      // of type controls and a dozen colour rows, which is what pushed the
      // data and the order off the bottom of the panel.
      await panel(tester);
      // Presets is not among them: it is one uncaptioned line at the top of
      // the panel rather than a section that has to be opened to find one
      // button.
      expect(find.byKey(const ValueKey("elementPresets")), findsOneWidget);
      // Batch 3 of the rebuild: the Text panel's sections, and in its
      // Content the cells, where they come from, their order and its
      // special cells, in that order.
      expect(sections(tester), ["Content", "Look", "Layout", "Motion", "More"]);
      double top(String fold) =>
          tester.getTopLeft(find.byKey(ValueKey("expander-$fold"))).dy;
      expect(top("tableCells"), lessThan(top("tableSource")));
      expect(top("tableSource"), lessThan(top("tableSort")));
      expect(top("tableSort"), lessThan(top("tableRules")));
    });

    testWidgets("the two sets of type controls fold away inside Style",
        (tester) async {
      await panel(tester);
      // Inside Style, each a card that folds: listed, but folded away.
      expect(find.text("Cell type"), findsOneWidget);
      expect(find.text("Header type"), findsOneWidget);
      expect(find.text("Weight"), findsNothing,
          reason: "listed, but still folded away");

      await openFold(tester, "tableCellType", shows: find.text("Weight"));
      expect(find.text("Weight"), findsOneWidget);
    });

    testWidgets("the data settings fit a narrow sidebar", (tester) async {
      // Controls ask CanvasControlScope for their width and are clamped to
      // the column. A raw SizedBox bypasses that, and the key field's did --
      // 190 pixels plus a save button in a sidebar narrower than either,
      // which is an overflow stripe across the panel rather than a field
      // that is merely too wide. It now sizes itself from the room it is
      // actually given.
      var element = TableElement(
        const ElementBase(id: "t", width: 400, height: 200),
        rows: const [
          ["Team", "Points"],
          ["Hull City", "6"],
        ],
        source: footballData.applyTo(const DataSource(), "PL"),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");

      // Constrained here rather than by shrinking the view, which the pump
      // helper sets for itself.
      await pump(
          tester,
          SizedBox(
              width: 200, child: CanvasDesignPanel(controller: controller)));

      // The panel already overflows by 32 pixels at this width with every
      // section shut, and has since before any of this existed -- something
      // in the layers list rather than in these settings. Taken and thrown
      // away here so that this test is about the sections it opens; it is not
      // a licence for a new one, which is what the checks below catch.
      tester.takeException();

      // Where the cells come from, a fold of its Content (batch 3).
      // Its caption in the rebuilt panel's small capitals.
      await openFold(tester, "tableSource", shows: find.text("KEY"));
      tester.takeException();
      expect(find.text("KEY"), findsOneWidget,
          reason: "the key field only exists once the source is an address, "
              "so without it this test is testing nothing");
      expect(tester.takeException(), isNull);

      await press(
          tester, find.byKey(const ValueKey("expander-tableSourceColumns")));
      expect(tester.takeException(), isNull);

      // Shut again: a fold remembers whether it is open in a static map that
      // outlives one test.
      await press(
          tester, find.byKey(const ValueKey("expander-tableSourceColumns")));
    });

    testWidgets("a table is refreshed from its heading; ordered by Rows shown",
        (tester) async {
      // Both without opening anything: pressing a button inside a section
      // means opening it, finding the button, and closing it again, every
      // time.
      var controller = await panel(tester);
      controller.replaceElement((tableIn(controller)).copyWith(
        headerRow: true,
        sort: const TableSort(levels: [TableSortLevel(column: 1)]),
      ));
      await tester.pumpAndSettle();

      // A table showing a sheet reads its rows from it at every change: the
      // old Order section, which sorted the table's own rows, is gone, and
      // Rows shown orders it (Ken, 2026-11-17).
      expect(byTip("Put the rows back in this order"), findsNothing);
      expect(find.byKey(const ValueKey("dataRowsSort")), findsOneWidget);
      // Where the numbers come from is the sheet's connection now (Connect
      // data, in the Data Studio): the table says so, with the way there.
      expect(find.byKey(const ValueKey("tableSheetSource")), findsOneWidget);
    });

    testWidgets("a row and a column can be added and taken away",
        (tester) async {
      var controller = await panel(tester);
      var toGrid = byTip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      await press(tester, byTip("Add a row"));
      expect(tableIn(controller).rows.length, 3);

      await press(tester, byTip("Add a column"));
      expect(tableIn(controller).columnCount, 3);
      expect(tableIn(controller).rows.every((r) => r.length == 3), isTrue,
          reason: "every row gains the column, or the grid goes ragged");

      await press(tester, byTip("Remove this column").first);
      expect(tableIn(controller).columnCount, 2);

      await press(tester, byTip("Remove this row").first);
      expect(tableIn(controller).rows.length, 2);
    });
  });

  group("the chart settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {ChartElement Function(ChartElement)? shape}) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        description: "By week",
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      if (shape != null) element = shape(element);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    /// press scrolls the settings to a control and taps it. A chart has more
    /// settings than fit in the panel, so most of them start off screen.
    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// labels opens the section the title, the description and the key are
    /// now gathered in. Closed to begin with, like the other sections.
    Future<void> labels(WidgetTester tester) async {
      // Keyed off the "over the chart" switch at the foot of the section
      // rather than off a caption: the title and the description have no
      // captions any more, only placeholders inside their own fields.
      if (find.text("Over the chart").evaluate().isEmpty) {
        await press(tester, find.text("LABELS"));
      }
    }

    /// grid opens the section the rules, the scale and the way a number is
    /// written are gathered in.
    Future<void> grid(WidgetTester tester) async {
      if (find.text("Log scale").evaluate().isEmpty) {
        await press(tester, find.text("GRID"));
      }
    }

    /// axisMore opens the button on the end of the X and Y labels line, which
    /// is where everything about how the writing on the axes looks now lives.
    Future<void> axisMore(WidgetTester tester) async {
      await labels(tester);
      if (find.text("Label size").evaluate().isEmpty) {
        await press(
            tester, find.byKey(const ValueKey("more-chartAxisLabelsMore")));
      }
    }

    /// legendMore opens the button on the end of the Legend line, which holds
    /// the key's own settings.
    Future<void> legendMore(WidgetTester tester) async {
      await labels(tester);
      if (find.text("Place").evaluate().isEmpty) {
        await press(tester, find.byKey(const ValueKey("more-chartLegendMore")));
      }
    }

    testWidgets("smooth is behind the series it curves", (tester) async {
      // It was a chart setting in a group called Lines, which on a chart of
      // bars with a line over it said nothing about which half of the chart
      // it meant. It is on the series now.
      await panel(tester, shape: (e) => e.copyWith(type: ChartType.line));
      expect(find.text("Smooth"), findsNothing,
          reason: "not until the series is opened");

      await press(tester, find.byKey(const ValueKey("seriesMore0")));
      expect(find.text("Smooth"), findsOneWidget);
      expect(find.text("Width"), findsOneWidget,
          reason: "the rest of how a line is drawn is in there with it");
    });

    testWidgets("and a set of bars is offered what bars have instead",
        (tester) async {
      // A switch that does nothing is indistinguishable from a broken one,
      // and bars have nothing to curve.
      await panel(tester);
      await press(tester, find.byKey(const ValueKey("seriesMore0")));
      expect(find.text("Smooth"), findsNothing);
      expect(find.text("Corner"), findsOneWidget);
      expect(find.text("Spacing"), findsOneWidget);
    });

    testWidgets("grouped bars say what they need", (tester) async {
      // They draw exactly what plain bars draw until there is a second series
      // to group, so choosing one on a one-series chart looks like the setting
      // doing nothing at all.
      var controller =
          await panel(tester, shape: (e) => e.copyWith(type: ChartType.bar));
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message)
          .where((m) => m.contains("Grouped and stacked"));
      expect(hints(), isEmpty);

      controller.replaceElement(
          chartIn(controller).copyWith(type: ChartType.groupedBar));
      await tester.pumpAndSettle();
      expect(hints(), isNotEmpty);

      controller.replaceElement(chartIn(controller)
          .copyWith(data: ChartData.parse("Cat\tA\tB\nx\t10\t5\ny\t6\t9")));
      await tester.pumpAndSettle();
      expect(hints(), isEmpty, reason: "with two series it has its answer");
    });

    testWidgets(
        "the grid card carries the switches, the lines and their colour",
        (tester) async {
      // In a card, everything at once: the Grid section already folds, and
      // a button inside it hiding the rest was a setting found twice over.
      var controller = await panel(tester);
      Finder toggle(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(CanvasToggle));
      for (var label in ["Grid", "Axes", "Log scale", "Values"]) {
        expect(toggle(label), findsOneWidget, reason: label);
      }
      expect(find.byKey(const ValueKey("more-chartGridMore")), findsNothing);
      expect(find.byKey(const ValueKey("chartAxisSteps")), findsOneWidget);
      // The rules' colour with them. It was in a section called Style, two
      // headings away from the switch it belongs to.
      expect(find.byKey(const ValueKey("chartGridColour")), findsOneWidget);

      // Values is the chart's own, not the key's.
      var was = chartIn(controller).showValues;
      await press(tester, toggle("Values"));
      expect(chartIn(controller).showValues, !was);
    });

    testWidgets("the first series' Drawn as is the chart's own type",
        (tester) async {
      // There was a Type dropdown as well, three sections above the series
      // list, and the two said the same thing in two places: a one-series
      // chart set to bars with its series set to "As the chart" has one
      // answer and two controls for it that could disagree.
      var controller = await panel(tester);
      expect(find.text("TYPE"), findsNothing);

      var drawnAs = find.byKey(const ValueKey("chartType"));
      expect(drawnAs, findsOneWidget);
      // Every kind, including the circular ones no later series can be: this
      // is the chart's own setting, not a series' override.
      expect(tester.widget<CanvasDropdown<String>>(drawnAs).options.length,
          ChartType.values.length);

      await press(tester, drawnAs);
      await tester.tap(find.text(ChartType.pie.label).last);
      await tester.pumpAndSettle();
      expect(chartIn(controller).type, ChartType.pie);

      // And the series goes back to following the chart in the same write.
      // Left pinned to what it was, choosing here would change the chart and
      // draw the first series the old way.
      controller.replaceElement(chartIn(controller).copyWith(
          data: ChartData(
        categories: chartIn(controller).data.categories,
        series: [
          chartIn(controller).data.series.first.copyWith(type: ChartType.bar),
          ...chartIn(controller).data.series.skip(1),
        ],
      )));
      await tester.pumpAndSettle();

      await press(tester, find.byKey(const ValueKey("chartType")));
      await tester.tap(find.text(ChartType.area.label).last);
      await tester.pumpAndSettle();
      expect(chartIn(controller).type, ChartType.area);
      expect(chartIn(controller).data.series.first.type, isNull);
    });

    testWidgets("the title and the description can be switched off",
        (tester) async {
      var controller = await panel(tester);
      await labels(tester);
      // No captions at all now: an empty field says which it is, and a full
      // one says what it says.
      expect(find.text("TITLE"), findsNothing);
      expect(find.text("DESCRIPTION"), findsNothing);
      var hints = tester
          .widgetList<CanvasTextField>(find.byType(CanvasTextField))
          .map((f) => f.hint);
      expect(hints, containsAll(["Title", "Description"]));
      expect(chartIn(controller).titleBox.show, isTrue);

      // Two "Show" toggles, one per label, so the title's is the first.
      await press(tester, find.text("Show").first);
      expect(chartIn(controller).titleBox.show, isFalse);
      expect(chartIn(controller).descriptionBox.show, isTrue,
          reason: "one switch each");
    });

    testWidgets("floating offers where each label goes", (tester) async {
      // There used to be a "place it yourself" button per label, which was a
      // second switch saying the same thing as "Over the chart": a label that
      // floats is one that sits where it is put.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse);
      // Two X already: the element's own position at the top of the panel,
      // and the switch that shows the X axis' title.
      expect(find.text("X"), findsNWidgets(2));
      expect(find.text("H"), findsOneWidget);
      expect(byTip("Place it yourself — then drag it on the canvas"),
          findsNothing);

      await press(tester, find.text("Over the chart"));

      // And now one for the title and one for the description as well.
      expect(find.text("X"), findsNWidgets(4));
      expect(find.text("H"), findsNWidgets(3));
    });

    testWidgets("switching it off keeps where they were put", (tester) async {
      // The switch goes both ways without losing anything: off puts the chart
      // back exactly as it was, and on again finds the labels where they were
      // dragged rather than back at their defaults.
      var controller = await panel(tester);
      await labels(tester);
      await press(tester, find.text("Over the chart"));

      controller.replaceElement(chartIn(controller).copyWith(
          titleBox:
              const ChartLabel(x: 0.4, y: 0.5, width: 0.3, height: 0.12)));
      await tester.pumpAndSettle();

      // And the box goes back round the chart, rather than staying as big as
      // the labels made it while they were floating.
      controller.replaceElement(chartIn(controller).copyWith(
          body: const ChartBody(x: 0.1, y: 0.1, width: 0.9, height: 0.9)));
      await tester.pumpAndSettle();

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isFalse);
      expect(chartIn(controller).body.isWhole, isTrue,
          reason: "the chart fills its element again");
      expect(chartIn(controller).titleBox.x, 0.4,
          reason: "kept, not thrown away");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).titleBox.x, 0.4);
    });

    testWidgets("how a number is written is a setting", (tester) async {
      // The decimals only appear once there is a style to apply them to:
      // automatic picks its own, so a box under it would do nothing.
      var controller = await panel(tester);
      // It sits with the gridlines and the scale -- how this chart is
      // measured -- which is a section that starts shut.
      await grid(tester);
      expect(find.text("Decimal places"), findsNothing);

      await press(tester, find.text("Automatic — 1000000, 12.5"));
      await tester.tap(find.text("Millions — 1.0M").last);
      await tester.pumpAndSettle();

      var chart = chartIn(controller);
      expect(chart.numbers.style, NumberStyle.millions);
      expect(chart.numbers.decimals, 1,
          reason: "seeded from what automatic was doing rather than reset to "
              "none");
      expect(find.text("Decimal places"), findsOneWidget);
      expect(chart.numbers.format(1000000), "1.0M");
    });

    testWidgets("and the list shows what it is set to do", (tester) async {
      // Listed with a fixed example, "Millions — 1.0M" reads as the only
      // thing millions can be, and the places beside it look like something
      // else's setting -- which is how somebody wanting 1.00M concludes they
      // cannot have it.
      await panel(tester,
          shape: (e) => e.copyWith(
              numbers: const ChartNumbers(
                  style: NumberStyle.millions, decimals: 2)));
      await grid(tester);

      expect(find.text("Millions — 1.00M"), findsOneWidget);
      expect(find.text("Millions — 1.0M"), findsNothing);
      // Automatic keeps its own, because what it does is vary: one example
      // would be a promise it does not make.
      await press(tester, find.text("Millions — 1.00M"));
      expect(find.text("Automatic — 1000000, 12.5"), findsWidgets);
      expect(find.text("In full — 1,000,000.00"), findsWidgets,
          reason: "the same two places, in the style beside it");
    });

    testWidgets("the axis can be set apart from the values", (tester) async {
      // An exact reading on the bar, a round number on the scale, which is
      // the pairing anybody setting these separately is after.
      var controller = await panel(tester,
          shape: (e) => e.copyWith(
              numbers: const ChartNumbers(
                  style: NumberStyle.millions, decimals: 3)));
      await grid(tester);

      expect(find.text("Axis numbers"), findsNothing,
          reason: "it follows the values until told not to");
      await press(tester, find.text("Axis the same"));

      expect(find.text("Axis numbers"), findsOneWidget);
      var chart = chartIn(controller);
      expect(chart.axisNumbers, isNotNull);
      expect(chart.axisFigures.decimals, 3,
          reason: "it starts as a copy of the values rather than as nothing");

      // And back again.
      await press(tester, find.text("Axis the same"));
      expect(chartIn(controller).axisNumbers, isNull);
    });

    testWidgets("the axis titles have a size and a distance", (tester) async {
      var controller = await panel(tester);
      await axisMore(tester);

      expect(find.text("Label size"), findsOneWidget);
      expect(find.text("Label gap"), findsOneWidget);
      expect(chartIn(controller).axisSpec, isNull,
          reason: "following the label size, which is where they started");
    });

    testWidgets("a pie is offered no axes, but still its values",
        (tester) async {
      // The switches are all the same question -- what does this chart write
      // on itself -- so they are one group, and a pie keeps the half of it
      // that applies.
      // "Grid" twice over: the switch here and the colour in Style, so it is
      // found by the control it belongs to rather than by its word.
      Finder toggle(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(CanvasToggle));

      await panel(tester);
      expect(toggle("Grid"), findsOneWidget);
      expect(toggle("Values"), findsOneWidget);
      await axisMore(tester);
      expect(find.text("X label"), findsOneWidget);
      // "X values", not "X labels": beside a switch called X, which shows the
      // word naming the axis, "X labels" was the same thing said twice.
      expect(find.text("X values"), findsOneWidget);

      // A pie has no axes to rule or to name, so neither the section about
      // the grid nor the line about the axis labels is offered at all. What
      // it writes on its slices still is.
      await panel(tester, shape: (e) => e.copyWith(type: ChartType.pie));
      expect(find.text("GRID"), findsNothing);
      await labels(tester);
      expect(find.text("X label"), findsNothing);
      expect(find.text("X values"), findsNothing);
      // Its switch moves to the Numbers line, which a pie does have.
      expect(toggle("Values"), findsOneWidget);
    });

    testWidgets("each axis' labels can be switched off on their own",
        (tester) async {
      // One switch each. It was one for both, and often enough they are not
      // read together: a bar chart named by its categories does not always
      // want the figures up the side as well.
      var controller = await panel(tester);
      await axisMore(tester);
      expect(chartIn(controller).showXLabels, isTrue);
      expect(chartIn(controller).showYLabels, isTrue);

      await press(tester, find.text("X values"));
      expect(chartIn(controller).showXLabels, isFalse);
      expect(chartIn(controller).showYLabels, isTrue,
          reason: "the other axis is not touched");

      await press(tester, find.text("Y values"));
      expect(chartIn(controller).showYLabels, isFalse);
      expect(chartIn(controller).showAxisLabels, isFalse,
          reason: "and with both off, on a chart whose axes are unnamed, "
              "there is no writing on the axes at all");
    });

    testWidgets("a radial bar says how it is drawn", (tester) async {
      // Its values were once only in the legend; now each bar has its name
      // at its start and its value past its end (Ken, 2026-11-14), and the
      // hint says so whatever the legend.
      const hint =
          "Each bar bends round three quarters of a turn at most -- to "
          "the axis's top value where one is set, else the largest -- with its "
          "name at its start and its value past its end.";
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message);

      for (var legend in [false, true]) {
        await panel(tester,
            shape: (e) =>
                e.copyWith(type: ChartType.radialBar, showLegend: legend));
        await labels(tester);
        expect(hints(), contains(hint), reason: "legend $legend");
      }
    });

    testWidgets("one switch decides whether the labels take room",
        (tester) async {
      // The three of them together, because taking room is what made every
      // one of their settings a setting that resized the chart.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse,
          reason: "stacked above the plot is what a chart looks like");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isTrue);
    });

    testWidgets("a section remembers whether it was open", (tester) async {
      // The panel is rebuilt from scratch whenever the selection changes, so
      // a section opened, deselected and selected again used to be shut --
      // the stored answer arrives asynchronously and the default is what
      // anybody saw.
      var controller = await panel(tester);
      await labels(tester);
      expect(find.text("Over the chart"), findsOneWidget);

      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(find.text("Over the chart"), findsNothing);

      controller.selectOnly("c");
      await tester.pumpAndSettle();
      expect(find.text("Over the chart"), findsOneWidget,
          reason: "still open, without waiting for a preference to load");
    });

    testWidgets("a closed section still fills the column", (tester) async {
      // The settings are a Column of start-aligned children, so a box left to
      // size itself shrank to fit its own heading -- and a closed section
      // narrower than the one above it does not read as a section, it reads
      // as a button somebody has left lying there.
      await panel(tester);

      var panelWidth = tester.getSize(find.byType(CanvasLayersPanel)).width;
      for (var name in ["content", "look"]) {
        var section = find.byKey(ValueKey("elementSection-$name"));
        await tester.ensureVisible(section);
        await tester.pumpAndSettle();
        expect(tester.getSize(section).width, greaterThan(panelWidth * 0.8),
            reason: name);
      }
    });

    testWidgets("the legend is in with the other words on the chart",
        (tester) async {
      // The title, the description and the key are the same kind of thing --
      // writing laid over a picture -- and were three clusters and an
      // expander scattered down the panel with the data between them.
      var controller = await panel(tester);
      await labels(tester);

      // One switch on the line, with everything else about the key behind the
      // button at the end of it. A section of its own for what is mostly two
      // dropdowns and a size was a heading for each of them.
      //
      // Last of the label lines, because it is the last thing anybody sets:
      // what the chart says, how it is measured, how it is written, and then
      // where the key for all of it sits.
      expect(find.text("Over the chart"), findsOneWidget,
          reason: "and the switch that places them, on the same line");
      expect(find.byKey(const ValueKey("chartShowLegend")), findsOneWidget);
      expect(find.text("Place"), findsNothing, reason: "the key is off");

      await press(tester, find.byKey(const ValueKey("chartShowLegend")));
      expect(chartIn(controller).showLegend, isTrue);

      await legendMore(tester);
      expect(find.text("Place"), findsOneWidget);
      expect(find.text("Along"), findsOneWidget);
      expect(find.byType(CanvasDropdown<LegendPlacement>), findsOneWidget);
      expect(find.text("Between"), findsNothing,
          reason: "nothing to separate until the key shows values");

      // Two "Values" on the panel now: the chart's own on the Grid line, in
      // Look, and the key's in here, in Content -- the first of the two.
      await press(tester, find.text("Values").first);
      expect(chartIn(controller).legend.values, isTrue);
      expect(find.text("Between"), findsOneWidget);
    });

    testWidgets("the title and the description size separately",
        (tester) async {
      // The description took the label size, which is also the tick labels'
      // -- so making the description bigger made the numbers up the side of
      // the chart bigger with it.
      var controller = await panel(tester);
      await labels(tester);
      var before = chartIn(controller).labelSpec.fontSize;

      // By name rather than by counting: there are four Size fields in this
      // section -- the title's, the description's, and one per axis -- and
      // counting finds a different one every time a field is added.
      await enterValue(
          tester, find.byKey(const ValueKey("chartDescriptionSize")), "44");
      await tester.pump();

      var after = chartIn(controller);
      expect(after.descriptionText.fontSize, 44);
      expect(after.labelSpec.fontSize, before,
          reason: "and the axis labels are where they were");
    });

    testWidgets(
        "a series is added beside the data, not in a section of its "
        "own", (tester) async {
      // A series is a column of the table, so it is added where the table is
      // -- and its name, colour and type are the section directly under it
      // rather than three headings away.
      var controller = await panel(tester);
      expect(chartIn(controller).data.series.length, 1);
      expect(
          tester.getTopLeft(find.text("SERIES")).dy.compareTo(
              tester.getTopLeft(find.byType(ChartDataEditor).first).dy),
          1,
          reason: "directly under the numbers it names");

      await press(
          tester,
          byTip("Add a series — give it its own type below to lay "
              "one kind of chart over another"));

      var data = chartIn(controller).data;
      expect(data.series.length, 2);
      expect(data.series[1].type, isNull, reason: "following the chart");
      expect(data.series[1].values.length, data.categories.length,
          reason: "a value per row, so it lines up with what is there");

      // Two "Drawn as" dropdowns now, one per series, under the table. Found
      // inside the series list rather than by type: the presets line at the
      // top of the panel is a dropdown of strings as well.
      expect(
          find.descendant(
              of: find.byType(ChartDataEditor).last,
              matching: find.byType(CanvasDropdown<String>)),
          findsNWidgets(2));
    });
  });

  group("a chart's animation", () {
    (CanvasController, ChartElement) build({int frames = 1}) {
      var document = CanvasDocument(frames: frames);
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller = CanvasController(document.addElement(chart));
      return (controller, chart);
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    (int, int)? arrival(CanvasController c) =>
        ownSpan(chartIn(c), MotionKind.arrive, c.document.frameRate);

    test("choosing a preset lays its arrival on the timeline", () {
      // One gesture, because it is one decision. A preset with nothing
      // pinning the reveal channel draws exactly what a still chart draws, so
      // applying it separately from keying it would be asking somebody to
      // know how this is implemented.
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      var after = chartIn(controller);
      expect(after.animation.preset, ChartAnimationPreset.grow);

      var (_, took) = arrival(controller)!;
      expect(took, greaterThan(0), reason: "a clip as long as the animation");
    });

    test("a still document is given frames to play it in", () {
      // An animation on a one-frame canvas is an animation nobody can watch.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      expect(controller.document.isAnimated, isFalse);

      controller.applyChartAnimation(chart, ChartAnimationPreset.wipe);

      expect(controller.document.isAnimated, isTrue);
      expect(arrival(controller), isNotNull);
    });

    test("it starts from where the reader is looking", () {
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);
      controller.frame = 20;

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      expect(arrival(controller)!.$1, 20,
          reason: "rather than jumping the playhead back to the start");
    });

    test("and keeps a pose that was put there by hand", () {
      // Choosing None used to clear the whole track. A chart that had been
      // moved or faded by keyframe lost all of that for choosing a word on a
      // dropdown, which is not what None means: it means no arrival.
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);
      controller.replaceElement(chart.withBase(
          track: ElementTrack([
        const Keyframe(frame: 0, dx: -40),
        const Keyframe(frame: 30),
      ])));

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.grow);
      expect(arrival(controller), isNotNull);
      expect(chartIn(controller).track!.keys.first.dx, -40,
          reason: "the arrival is laid beside the pose, not over it");

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.none);
      expect(arrival(controller), isNull, reason: "the arrival is taken away");
      expect(chartIn(controller).track!.keys.first.dx, -40,
          reason: "the pose is untouched");
    });

    test("trying another preset leaves the timing where it was put", () {
      // The Length setting is for laying a new one down. Once it is on the
      // timeline the keyframes are where somebody has put them, and trying
      // the next preset in the list must not shove them about.
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow,
          length: 12);
      var (from, span) = controller.elementAnimationSpan(chartIn(controller));
      expect(span, 12);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.wipe);
      expect(controller.elementAnimationSpan(chartIn(controller)), (from, 12));
    });

    test("choosing None takes the keyframes away with it", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);
      expect(arrival(controller), isNotNull);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.none);

      expect(chartIn(controller).animation.on, isFalse);
      expect(arrival(controller), isNull);
      expect(chartIn(controller).base.motion.clips, isEmpty,
          reason: "no animation left, so no empty clip in the saved file");
    });

    test("it is one undo step", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      controller.undo();
      var back = controller.document.elements.single as ChartElement;
      expect(back.animation.on, isFalse);
      expect(back.track, isNull);
    });
  });

  group("the chart's numbers", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ChartData dataIn(CanvasController controller) =>
        (controller.document.elements.single as ChartElement).data;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// grid switches to the table, if it is not already showing one.
    ///
    /// Which view the editor is in is remembered for the session, deliberately
    /// -- somebody who works in the grid works in the grid, whatever chart
    /// they open next -- so a test cannot assume it starts in the text one.
    Future<void> grid(WidgetTester tester) async {
      var toTable = byTip("Edit the numbers in a table");
      if (toTable.evaluate().isNotEmpty) await press(tester, toTable);
    }

    testWidgets("the numbers are a section of their own", (tester) async {
      // They are the longest thing in a chart's settings and the least often
      // changed once they are right, so they were pushing everything else off
      // the bottom of the panel.
      //
      // Called Table, because that is what is in it: the numbers in rows and
      // columns, with what they are drawn as above them and how that drawing
      // looks below.
      await panel(tester);
      // A fold of their own in its Content (batch 3 of the rebuild); the
      // source's fold, left open by an earlier test, may show them too.
      expect(find.byType(ChartDataEditor), findsWidgets);
      expect(find.textContaining("2 rows, 1 series"), findsWidgets);
    });

    testWidgets("it switches between pasted text and a table", (tester) async {
      // Pasted text is the fast way in; it is a bad way to change one number
      // in the middle of forty, which is the other thing people do all day.
      var controller = await panel(tester);
      // Two of them: the numbers in the Table section, and the series list
      // under it, which is the same widget showing only its series rows.
      expect(find.byType(ChartDataEditor), findsNWidgets(2));
      expect(byTip("Add a row"), findsOneWidget,
          reason: "rows and series are added the same way in either view");

      await grid(tester);
      // "Raw table", not "Edit the numbers as pasted text": the button sits
      // on a line of three and the sentence was longer than the row.
      expect(byTip("Raw table"), findsOneWidget);

      // The first row's category, then its value.
      await enterValue(
          tester,
          find
              .descendant(
                  of: find.byType(ChartDataEditor).first,
                  matching: find.byType(TextField))
              .at(2),
          "42");
      await tester.pumpAndSettle();
      expect(dataIn(controller).valueAt(0, 0), 42);
    });

    testWidgets("a row can be added and taken away", (tester) async {
      var controller = await panel(tester);
      await grid(tester);

      await press(tester, byTip("Add a row"));
      expect(dataIn(controller).categories.length, 3);

      await press(tester, byTip("Remove this row").first);
      expect(dataIn(controller).categories.length, 2);
      expect(dataIn(controller).series.single.values.length, 2,
          reason: "the series loses the row too, or the data goes ragged");
    });
  });

  group("a chart's own data source", () {
    // A chart used to have two ways to get numbers: typed in, or read off a
    // table on the same canvas. Neither covers a chain's history, which has
    // no table beside it and would not want one four thousand rows long.
    //
    // What is tested here is the wiring, since the mapping itself is model
    // work and is tested against the real responses in
    // canvas_chart_source_test.dart.

    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp("canvas_chart_source");
    });
    tearDown(() => dir.delete(recursive: true));

    /// idle turns the real event loop, because a file is read on it while a
    /// widget test runs in a fake one. See the note in the notes tests: one
    /// step of an I/O chain needs one runAsync and one pump.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<CanvasController> panel(WidgetTester tester,
        {DataSource source = const DataSource(),
        ChartSourceMap map = const ChartSourceMap()}) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        source: source,
        fromSource: map,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      // In its Content, a fold of its own (batch 3 of the rebuild).
      await openFold(tester, "chartSource",
          shows: find.byKey(const ValueKey("source-c")));
      return controller;
    }

    ChartElement chartIn(CanvasController c) =>
        c.document.elements.single as ChartElement;

    /// openColumn opens one column's line in the Columns list.
    ///
    /// A column remembers whether it was open by its *name*, so that the one
    /// left open stays open when a column is moved past it -- which means the
    /// memory outlives a test, exactly as a section's does.
    Future<void> openColumn(WidgetTester tester, String name) =>
        openFold(tester, "chartSourceCol:$name", shows: find.text("Header"));

    /// open opens the section if it is not already open.
    ///
    /// Sections remember whether they were open, and the memory outlives one
    /// test: tapping unconditionally shut the section that the test before
    /// had left open, and the controls inside it were then nowhere to be
    /// found. [probe] is something only that section has, which is how "is it
    /// already open" is asked.
    Future<void> open(WidgetTester tester, String section,
        [String probe = "Preset"]) async {
      if (find.text(probe).evaluate().isNotEmpty) return;
      // The sections are open; Columns is a card that folds inside one.
      if (section == "COLUMNS") {
        await openFold(tester, "chartSourceColumns", shows: find.text(probe));
      }
    }

    // Batch 3 of the rebuild (Ken, 2026-11-12): both in its Content, each
    // a fold of its own, where its numbers come from over the numbers.
    testWidgets("it is a fold of its own, over the numbers", (tester) async {
      await panel(tester);
      var source = find.byKey(const ValueKey("expander-chartSource"));
      var numbers = find.byType(ChartDataEditor).first;
      expect(source, findsOneWidget);
      // The numbers, and the source's own mapping of them in its fold.
      expect(find.byType(ChartDataEditor), findsWidgets);
      expect(tester.getTopLeft(source).dy,
          lessThan(tester.getTopLeft(numbers).dy));
    });

    testWidgets("the sections read in the order the work happens",
        (tester) async {
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      expect(controller.document.elements.single, isA<ChartElement>());
      expect(find.byKey(const ValueKey("expander-chartSourceColumns")),
          findsOneWidget,
          reason: "the mapping, a card that folds in Data source");
      var headings = [
        for (var it
            in tester.widgetList<CanvasSection>(find.byType(CanvasSection)))
          it.title,
      ];
      expect(headings.where((h) => h != "Content"),
          ["Look", "Layout", "Motion", "More"],
          reason: "$headings");
    });

    testWidgets("and the mapping is hidden while the numbers are typed in",
        (tester) async {
      // A mapping with nothing to map is two sections that only ever say
      // nothing.
      await panel(tester);
      expect(find.text("COLUMNS"), findsNothing);
      expect(find.text("CUSTOM FIELDS"), findsNothing);
    });

    testWidgets("each column is a line that opens", (tester) async {
      // Laid out in full, a dozen columns of seven settings each is eighty
      // rows of controls to change one heading -- and the one being looked
      // for has to be found by counting.
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      expect(controller.document.elements.single, isA<ChartElement>());
      await open(tester, "COLUMNS", "Path to the list");

      // Closed, each says its name and what it is mapped to.
      expect(find.text("Coin supply (DCR)"), findsWidgets);
      expect(find.text("Header"), findsNothing,
          reason: "the settings are behind the line, not spread down it");

      await openColumn(tester, "Coin supply (DCR)");
      expect(find.text("Header"), findsOneWidget);
      // A cell can hold a club badge and a badge chosen by hand has to
      // survive a refresh. Neither is true of a number on a chart, so on one
      // they are two switches that do nothing.
      expect(find.text("A picture"), findsNothing);
      expect(find.text("Keep mine"), findsNothing);
      // And a custom field is an ordinary column with a recipe, edited here
      // rather than listed a second time in a section of its own.
      expect(find.text("Built from fields"), findsOneWidget);
    });

    testWidgets("a column can be moved, and the drawing follows it",
        (tester) async {
      // There was no way to reorder a mapping at all: a column in the wrong
      // place had to be deleted and the rest re-done by hand.
      var controller = await panel(
        tester,
        source: dcrdataChart.applyTo(const DataSource(), "coin-supply"),
        map: const ChartSourceMap(categoryColumn: 0, valueColumns: [1]),
      );
      await open(tester, "COLUMNS", "Path to the list");
      await openColumn(tester, "Coin supply (DCR)");

      var earlier = byTip("Move this column earlier");
      await tester.ensureVisible(earlier.last);
      await tester.pumpAndSettle();
      await tester.tap(earlier.last);
      await tester.pumpAndSettle();

      var chart = controller.document.elements.single as ChartElement;
      expect([for (var c in chart.source.columns) c.header],
          ["Coin supply (DCR)", "Date"]);
      expect(chart.fromSource.categoryColumn, 1,
          reason: "the date is still the axis, at its new number");
      expect(chart.fromSource.valueColumns, [0],
          reason: "and the supply is still the series");
    });

    // Ken, 2026-11-08: the way out's order is the chain's own style card's
    // now; the same switch, read and written through OwnStyle.
    test("which end a chart empties from is its own switch", () {
      var chart = ChartElement(const ElementBase(id: "c"),
          data: ChartData.parse("Cat\tA\nx\t10\ny\t6"));
      var style = OwnStyle(chart);
      expect(style.inOrder, isFalse);
      var after = style.withPreset("grow", leaving: true) as ChartElement;
      after = OwnStyle(after).withInOrder(true) as ChartElement;
      expect(after.animation.exitInOrder, isTrue);
      expect(after.animation.leaving.flipOrder, isTrue,
          reason: "which is what the painter draws the way out with");
    });

    testWidgets("a date axis can be read at intervals", (tester) async {
      // Thinning evenly gives a readable chart and a meaningless axis: the
      // points land wherever the arithmetic put them. One a year, on a date
      // chosen, gives an axis that says 2020, 2021, 2022.
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      await open(tester, "DATA SOURCE");

      var reading = find.text("A reading");
      expect(reading, findsOneWidget,
          reason: "the axis is the date column, so this can mean something");
      // Which axis, on a chart that has two of them.
      expect(find.text("Along the x axis"), findsOneWidget);

      // The anchor only appears once there is an interval to anchor.
      expect(find.text("On the"), findsNothing);
      await tester.ensureVisible(find.text("Every point"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Every point"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Yearly").last);
      await tester.pumpAndSettle();

      var chart = controller.document.elements.single as ChartElement;
      expect(chart.fromSource.interval.unit, IntervalUnit.year);
      expect(find.text("On the"), findsOneWidget,
          reason: "a yearly reading is on a day of a month");
      expect(find.text("In"), findsOneWidget);
      expect(find.text("Most points"), findsNothing,
          reason: "two answers to the same question, so only one is offered");
      // The count says what it is counting. On its own the number read as a
      // number of readings, which is not what it is.
      expect(find.text("Each one is"), findsOneWidget,
          reason: "adding a year of transactions up is the point of the "
              "feature, and it cannot be guessed from the numbers");
      expect(find.text("1 year"), findsOneWidget,
          reason: "a reading every N *years* — one of them, so singular");
      // The hint is behind a question mark, so what it says is read off the
      // widget rather than off the screen.
      var hints = [
        for (var it in tester.widgetList<CanvasHint>(find.byType(CanvasHint)))
          it.message,
      ];
      expect(hints.any((m) => m.contains("One reading a year, on 1 January")),
          isTrue,
          reason: "it should say the interval in words: $hints");
    });

    testWidgets("and a column of names cannot be", (tester) async {
      // On a column of team names an interval is a control that could not do
      // anything.
      await panel(tester,
          source: coinGeckoMarkets.applyTo(const DataSource(), "decred"));
      await open(tester, "DATA SOURCE");
      expect(find.text("A reading"), findsNothing);
      expect(find.text("Most points"), findsOneWidget);
    });

    testWidgets("choosing a preset fills in the address and the mapping",
        (tester) async {
      // The choice decides the mapping as well as the address: dcrdata keeps
      // every series in an array named after itself, so a preset that only
      // set the URL would fetch four thousand rows and draw none of them.
      var controller = await panel(tester);
      await open(tester, "DATA SOURCE");

      await tester.ensureVisible(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text(dcrdataChart.label).last);
      await tester.pumpAndSettle();

      var source = chartIn(controller).source;
      expect(source.preset, dcrdataChart.id);
      expect(source.shape, DataShape.columns);
      expect(source.where, contains("dcrdata.decred.org"));
      expect(source.columns.length, 2);
      expect(chartIn(controller).fromSource.valueColumns, [1]);
      expect(chartIn(controller).fromSource.maxPoints, greaterThan(0),
          reason: "a daily series since 2016 has to be thinned to be drawn");
    });

    testWidgets("a league table is not offered to a chart", (tester) async {
      // A chart of a league table comes from the table beside it -- one
      // request, one set of figures, and they cannot disagree.
      await panel(tester);
      await open(tester, "DATA SOURCE");
      await tester.ensureVisible(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("None — set it up myself"));
      await tester.pumpAndSettle();

      expect(find.text(footballData.label), findsNothing);
      expect(find.text(dcrdataChart.label), findsWidgets);
    });

    testWidgets("refreshing draws what came back", (tester) async {
      // End to end through the panel, over a file rather than the network:
      // the fetching is the same code either way and a test that needed the
      // internet would be a test that fails on a train.
      // Written synchronously. A dart:io future completes on the real event
      // loop and its continuation is a microtask in the fake one, so awaiting
      // one in the body of a widget test hangs the whole suite with no error
      // at all -- which is exactly what this did.
      var file = File("${dir.path}/supply.json");
      file.writeAsStringSync(jsonEncode({
        "t": [1454889600, 1454976000, 1455062400],
        "supply": [168720623595120, 169504574718296, 170288525841472],
      }));

      SharedPreferences.setMockInitialValues({});
      var controller = await panel(
        tester,
        source: dcrdataChart
            .applyTo(const DataSource(), "coin-supply")
            .copyWith(kind: DataKind.file, where: file.path),
        map: const ChartSourceMap(valueColumns: [1]),
      );
      expect(chartIn(controller).data.isEmpty, isTrue);

      // Two of them now: the Data source section's and the one on the Table
      // section, which is where somebody looking at the numbers is standing.
      var refresh = byTip("Read the data and put it in the chart").first;
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await idle(tester);
      // A path not chosen here is asked about first: the canvas may be
      // someone else's.
      expect(chartIn(controller).data.isEmpty, isTrue);
      await tester.tap(find.text("Read it"));
      await idle(tester);

      var data = chartIn(controller).data;
      expect(data.categories.length, 3);
      expect(data.series.single.name, "Coin supply (DCR)");
      // In DCR rather than in atoms, which is what the chain counts in.
      expect(data.series.single.values.first, closeTo(1687206.2, 0.1));
      expect(chartIn(controller).source.fetchedAt, isNotNull,
          reason: "so the heading can say how old the numbers are");
    });

    testWidgets("and the columns can be changed without fetching again",
        (tester) async {
      var file = File("${dir.path}/two.json");
      file.writeAsStringSync(jsonEncode({
        "t": [1454889600, 1454976000],
        "supply": [100000000, 200000000],
        "count": [7, 9],
      }));
      SharedPreferences.setMockInitialValues({});
      await DataFiles.allow(file.path);

      var controller = await panel(
        tester,
        source: const DataSource(
          kind: DataKind.file,
          columns: [
            SourceColumn(header: "Date", path: "t", date: "MMM yy"),
            SourceColumn(header: "Supply", path: "supply", divide: 1e8),
            SourceColumn(header: "Transactions", path: "count"),
          ],
          shape: DataShape.columns,
        ).copyWith(where: file.path),
        map: const ChartSourceMap(valueColumns: [1]),
      );

      // Two of them now: the Data source section's and the one on the Table
      // section, which is where somebody looking at the numbers is standing.
      // This presses the Table section's, which is the one that is *not*
      // inside the data panel -- so what follows also pins that a refresh
      // from there leaves the mapping controls able to redraw.
      var refresh = byTip("Read the data and put it in the chart").first;
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await idle(tester);
      expect(chartIn(controller).data.series.single.name, "Supply");

      // Adding a second series redraws from the rows already in hand. It is a
      // row per series now rather than a switch per column, so the gesture is
      // "add one" and it lands on the first column not already drawn.
      await open(tester, "DATA SOURCE");
      var add = find.byKey(const ValueKey("chartSeriesAdd"));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      var data = chartIn(controller).data;
      expect([for (var s in data.series) s.name], ["Supply", "Transactions"]);
      expect(data.series[1].values, [7, 9]);
      expect(chartIn(controller).fromSource.valueColumns, [1, 2]);
    });
  });
}

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_data.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_chart_series_row_test.dart is the list of series under a chart's
// grid: which one is which, and where the rest of each one's settings live.
//
// The row is read far more often than it is changed. What anybody scans the
// list for is which series is which -- the name, the colour, the kind of
// drawing -- and laying every setting beside those buried the answer in a
// thicket: three series with five controls each is fifteen controls to look
// past. So the row carries what identifies a series, and the rest is behind
// that series' own button.
//
// The arrival offset is the exception and stays on the row: it is the one
// setting that is about this series *against the others*, set by looking down
// the column and comparing, which cannot be done one flyout at a time.
//
// Every labelled control reserves the caption's height above itself whether
// it has words in it or not, which is what puts a row of them on one
// baseline. A control put beside them has to reserve the same.

void main() {
  Future<void> show(WidgetTester tester, ChartData data,
      {ChartType type = ChartType.line,
      ChartStyleDefaults style = const ChartStyleDefaults(),
      bool animated = false,
      double width = 240}) async {
    tester.view.physicalSize = Size(width * 3, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(
          body: SingleChildScrollView(
            child: CanvasControlScope(
              maxWidth: width,
              child: SizedBox(
                width: width,
                child: ChartDataEditor(
                  data: data,
                  chartType: type,
                  style: style,
                  animated: animated,
                  onChanged: (_) {},
                  onCommit: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double topOf(WidgetTester tester, Finder what) =>
      tester.getRect(what.first).top;

  testWidgets("the name stands on the line the dropdown is on", (tester) async {
    await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"));

    // A labelled control's box starts at the caption; the cell inside one
    // starts below it. So the cell is on its neighbours' line when it sits
    // exactly one caption lower than the box beside it -- and off it by
    // whatever else anybody pads it with by hand.
    var drawn = topOf(tester, find.byType(CanvasDropdown<String>));
    var name = topOf(tester, find.byKey(const ValueKey("seriesName0")));
    expect(name, closeTo(drawn + controlLabelHeight + controlLabelGap, 1.5));
  });

  testWidgets("colour sits on that line too, at the end of it", (tester) async {
    await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"));

    var drawn = tester.getRect(find.byType(CanvasDropdown<String>));
    var colour = tester.getRect(find.byType(CanvasColorButton));
    expect(colour.top, closeTo(drawn.top, 0.5));
    expect(colour.left, greaterThan(drawn.left));
  });

  testWidgets("and the row fits a sidebar without wrapping", (tester) async {
    await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"));
    var drawn = tester.getRect(find.byType(CanvasDropdown<String>));
    var colour = tester.getRect(find.byType(CanvasColorButton));
    expect(colour.right, lessThanOrEqualTo(240));
    expect(colour.top, closeTo(drawn.top, 0.5));
  });

  group("the rest of a series' settings", () {
    testWidgets("are behind a button", (tester) async {
      await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"));
      expect(find.byKey(const ValueKey("seriesWidth0")), findsNothing);

      await tester.tap(find.byKey(const ValueKey("seriesMore0")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("seriesWidth0")), findsOneWidget);
      expect(find.text("Width"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey("seriesMore0")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("seriesWidth0")), findsNothing,
          reason: "and the button shuts them again");
    });

    testWidgets("open from a button that is on the row's own line",
        (tester) async {
      // A button reserves the caption's height itself. Reserving it a second
      // time on the way in put it a caption lower than everything beside it,
      // far enough that the middle of the button was empty space.
      await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"));
      var more = tester.getRect(find.byKey(const ValueKey("seriesMore0")));
      var colour = tester.getRect(find.byType(CanvasColorButton));
      expect(more.center.dy, closeTo(colour.center.dy, 2));
    });

    testWidgets("open on what the series is actually drawn at", (tester) async {
      // Never a bare nought that has to be decoded: a series takes the
      // chart's own width until it is given one of its own.
      await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"),
          style: const ChartStyleDefaults(width: 6));
      await tester.tap(find.byKey(const ValueKey("seriesMore0")));
      await tester.pumpAndSettle();
      expect(find.text("6.0"), findsOneWidget);
    });

    testWidgets("are the ones that belong to how it is drawn", (tester) async {
      // A set of bars has no thickness and a line has no corners, and a
      // control that does nothing is indistinguishable from a broken one.
      await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"),
          type: ChartType.bar);
      await tester.tap(find.byKey(const ValueKey("seriesMore0")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("seriesCorner0")), findsOneWidget);
      expect(find.byKey(const ValueKey("seriesWidth0")), findsNothing);
    });

    testWidgets("and a series with nothing to set has no button",
        (tester) async {
      // A slice of a pie is neither drawn with a line nor shaped like a bar,
      // and a button that opens an empty flyout is worse than no button.
      await show(tester, ChartData.parse("Cat\tTreasury in\nx\t10"),
          type: ChartType.pie);
      expect(find.byKey(const ValueKey("seriesMore0")), findsNothing);
    });

    testWidgets("one series' settings do not open another's", (tester) async {
      await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"));
      await tester.tap(find.byKey(const ValueKey("seriesMore1")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("seriesWidth1")), findsOneWidget);
      expect(find.byKey(const ValueKey("seriesWidth0")), findsNothing);
    });
  });

  testWidgets("the offset stays out on the row", (tester) async {
    // It is the one setting about this series against the others, set by
    // looking down the column and comparing.
    await show(tester, ChartData.parse("Cat\tOne\tTwo\nx\t10\t4"),
        animated: true);
    expect(find.byKey(const ValueKey("seriesDelay1")), findsOneWidget);
    expect(find.byKey(const ValueKey("seriesDelay0")), findsNothing,
        reason: "the first series is what the rest are offset against");
  });

  testWidgets("series are further apart than the controls within one",
      (tester) async {
    await show(tester, ChartData.parse("Cat\tOne\tTwo\tThree\nx\t10\t4\t7"));

    var one = topOf(tester, find.byKey(const ValueKey("seriesName1")));
    var two = topOf(tester, find.byKey(const ValueKey("seriesName2")));
    var drawn = topOf(tester, find.byType(CanvasDropdown<String>).at(1));
    expect(two - one, greaterThan((one - drawn) * 2),
        reason: "a series reads as one block, not as loose controls");
  });

  testWidgets("no gradient controls beside the swatch", (tester) async {
    var data = ChartData.parse("Cat\tTreasury in\nx\t10");
    data = ChartData(categories: data.categories, series: [
      data.series.single
          .copyWith(gradient: const GradientSpec(to: Color(0xFFFF3DAA))),
    ]);
    await show(tester, data);

    // The second colour is chosen in the picker. Four controls beside every
    // swatch is four controls for something most series never use.
    expect(find.byKey(const ValueKey("seriesGradient0")), findsNothing);
    expect(find.byKey(const ValueKey("seriesRadial0")), findsNothing);
    expect(find.byType(CanvasColorButton), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_parts.dart';

// canvas_stage_parts_test.dart pins what the stage's part sums do (taking
// hold of a chart's labels, dragging them and a table's column rules,
// finding and writing a table's cells), each asked directly rather than
// through a press on the stage.

/// _chart is a chart whose labels float over it: a title and a description
/// placed well inside its box, and a key where the chart puts it.
ChartElement _chart() => ChartElement(
      const ElementBase(id: "c", x: 40, y: 40, width: 600, height: 340),
      title: "Title",
      description: "Some words",
      titleBox: const ChartLabel(x: 0.05, y: 0.05, width: 0.3, height: 0.1),
      descriptionBox:
          const ChartLabel(x: 0.05, y: 0.2, width: 0.4, height: 0.1),
      floatingLabels: true,
      showLegend: true,
      data: ChartData.parse("Cat\tOne\tTwo\n2019\t10\t200\n2020\t20\t400"),
    );

/// _table is three columns of equal share, 300 wide, two rows.
TableElement _table({double width = 300}) => TableElement(
      ElementBase(id: "t", x: 0, y: 0, width: width, height: 120),
      rows: const [
        ["a", "b", "c"],
        ["d", "e", "f"],
      ],
      columnWidths: const [1, 1, 1],
    );

void main() {
  group("chartLabelGrabAt", () {
    test("a point inside a label takes it by its body", () {
      var e = _chart();
      var title = chartLabelPlaces(e, e.bounds)[ChartLabelPart.title]!;
      var doc = title.center;
      var grab = chartLabelGrabAt(e, e.bounds, doc, 4)!;
      expect(grab.part, ChartLabelPart.title);
      expect(grab.resizing, isFalse);
      expect(grab.grab, doc - title.topLeft);
    });

    test("a point by a label's corner takes it to resize; never the key's", () {
      var e = _chart();
      var places = chartLabelPlaces(e, e.bounds);
      var title = places[ChartLabelPart.title]!;
      var doc = title.bottomRight + const Offset(2, 2);
      var grab = chartLabelGrabAt(e, e.bounds, doc, 4)!;
      expect(grab.part, ChartLabelPart.title);
      expect(grab.resizing, isTrue);
      expect(grab.grab, doc - title.bottomRight);

      var key = places[ChartLabelPart.legend]!;
      var inKey = key.bottomRight - const Offset(1, 1);
      var held = chartLabelGrabAt(e, e.bounds, inKey, 4)!;
      expect(held.part, ChartLabelPart.legend);
      expect(held.resizing, isFalse);
    });

    test("where labels overlap the one drawn last wins", () {
      const same = ChartLabel(x: 0.1, y: 0.1, width: 0.5, height: 0.2);
      var e = _chart().copyWith(titleBox: same, descriptionBox: same);
      var doc = same.rectIn(e.bounds).center;
      expect(chartLabelGrabAt(e, e.bounds, doc, 4)!.part,
          ChartLabelPart.description);
    });

    test("a point outside every label, or on a chart with none, is null", () {
      var e = _chart();
      expect(
          chartLabelGrabAt(e, e.bounds, const Offset(-500, -500), 4), isNull);
      var plain = ChartElement(
          const ElementBase(id: "p", width: 600, height: 340),
          title: "Title");
      expect(chartLabelGrabAt(plain, plain.bounds, plain.bounds.center, 4),
          isNull);
    });
  });

  group("chartLabelDragged", () {
    test("a chart with no area is not dragged", () {
      var e = ChartElement(const ElementBase(id: "c", width: 0, height: 100),
          title: "Title", floatingLabels: true);
      var grab = ChartLabelGrab(ChartLabelPart.title, false, Offset.zero);
      expect(
          chartLabelDragged(e, e.bounds, grab, const Offset(10, 10)), isNull);
    });

    test("moving a label inside the box writes its place as fractions", () {
      var e = _chart();
      var b = e.bounds;
      var grab =
          ChartLabelGrab(ChartLabelPart.title, false, const Offset(5, 5));
      var doc = b.topLeft + const Offset(65, 39);
      var next = chartLabelDragged(e, b, grab, doc)!;
      expect(next.titleBox.x, closeTo(60 / b.width, 1e-9));
      expect(next.titleBox.y, closeTo(34 / b.height, 1e-9));
      expect(next.bounds, b);

      var keyGrab = ChartLabelGrab(ChartLabelPart.legend, false, Offset.zero);
      var moved =
          chartLabelDragged(e, b, keyGrab, b.topLeft + const Offset(30, 34))!;
      expect(moved.legend.x, closeTo(30 / b.width, 1e-9));
      expect(moved.legend.y, closeTo(34 / b.height, 1e-9));
      expect(moved.bounds, b);
    });

    test("a label dragged off the side grows the box and leaves the plot", () {
      var e = _chart();
      var b = e.bounds;
      var grab = ChartLabelGrab(ChartLabelPart.title, false, Offset.zero);
      var next =
          chartLabelDragged(e, b, grab, b.topRight + const Offset(-100, 20))!;
      expect(next.x, e.x);
      expect(next.y, e.y);
      expect(next.width, greaterThan(e.width));
      var plot = next.body.rectIn(next.bounds);
      var was = e.body.rectIn(b);
      expect(plot.left, closeTo(was.left, 1e-6));
      expect(plot.top, closeTo(was.top, 1e-6));
      expect(plot.width, closeTo(was.width, 1e-6));
      expect(plot.height, closeTo(was.height, 1e-6));
    });

    test("resizing past the label's smallest stops there", () {
      var e = _chart();
      var b = e.bounds;
      var grab = ChartLabelGrab(ChartLabelPart.title, true, Offset.zero);
      var next =
          chartLabelDragged(e, b, grab, b.topLeft - const Offset(50, 50))!;
      expect(next.titleBox.width, closeTo(0.05, 1e-9));
      expect(next.titleBox.height, closeTo(0.03, 1e-9));
    });
  });

  group("tableColumnDragged", () {
    test("the first rule moves between its two columns; the rest stay", () {
      var e = _table();
      var next = tableColumnDragged(e, e.bounds, 0, const Offset(150, 60))!;
      expect(next.columnWidths[0], closeTo(150 / 300, 1e-9));
      expect(next.columnWidths[1], closeTo(50 / 300, 1e-9));
      expect(next.columnWidths[2], closeTo(100 / 300, 1e-9));
    });

    test("the last rule moves; there is none past the last column", () {
      var e = _table();
      var next = tableColumnDragged(e, e.bounds, 1, const Offset(250, 60))!;
      expect(next.columnWidths[0], closeTo(100 / 300, 1e-9));
      expect(next.columnWidths[1], closeTo(150 / 300, 1e-9));
      expect(next.columnWidths[2], closeTo(50 / 300, 1e-9));
      expect(tableColumnDragged(e, e.bounds, 2, const Offset(250, 60)), isNull);
    });

    test("a drag past either neighbour leaves it 2% of the table", () {
      var e = _table();
      var right = tableColumnDragged(e, e.bounds, 0, const Offset(1000, 60))!;
      expect(right.columnWidths[0], closeTo(194 / 300, 1e-9));
      expect(right.columnWidths[1], closeTo(6 / 300, 1e-9));
      var left = tableColumnDragged(e, e.bounds, 0, const Offset(-50, 60))!;
      expect(left.columnWidths[0], closeTo(6 / 300, 1e-9));
      expect(left.columnWidths[1], closeTo(194 / 300, 1e-9));
    });

    test("a table with no width is not dragged", () {
      var e = _table(width: 0);
      expect(tableColumnDragged(e, e.bounds, 0, const Offset(10, 10)), isNull);
    });
  });

  group("tableCellRect", () {
    test("the first cell starts at the table's corner", () {
      var e = _table();
      var heights = tableRowHeights(e, e.bounds);
      var r = tableCellRect(e, e.bounds, 0, 0);
      expect(r.topLeft, e.bounds.topLeft);
      expect(r.width, closeTo(100, 1e-9));
      expect(r.height, closeTo(heights[0], 1e-9));
    });

    test("the last cell ends at the table's far corner", () {
      var e = _table();
      var heights = tableRowHeights(e, e.bounds);
      var r = tableCellRect(e, e.bounds, 1, 2);
      expect(r.left, closeTo(200, 1e-9));
      expect(r.top, closeTo(heights[0], 1e-9));
      expect(r.right, closeTo(300, 1e-9));
    });

    test("a cell outside the grid is the whole table", () {
      var e = _table();
      expect(tableCellRect(e, e.bounds, 2, 0), e.bounds);
      expect(tableCellRect(e, e.bounds, 0, 3), e.bounds);
    });
  });

  group("tableWithCell", () {
    test("a cell inside the grid is rewritten and nothing else", () {
      var e = _table();
      var next = tableWithCell(e, 1, 2, "z");
      expect(next.rows, [
        ["a", "b", "c"],
        ["d", "e", "z"],
      ]);
      expect(e.rows[1][2], "f");
    });

    test("a cell past the grid grows it with empty cells", () {
      var e = _table();
      var next = tableWithCell(e, 3, 4, "z");
      expect(next.rows, [
        ["a", "b", "c", "", ""],
        ["d", "e", "f", "", ""],
        ["", "", "", "", ""],
        ["", "", "", "", "z"],
      ]);
    });

    test("short rows are filled out to the widest", () {
      var e = TableElement(const ElementBase(id: "t"), rows: const [
        ["a", "b", "c"],
        ["d"],
      ]);
      expect(tableWithCell(e, 0, 0, "z").rows, [
        ["z", "b", "c"],
        ["d", "", ""],
      ]);
    });
  });
}

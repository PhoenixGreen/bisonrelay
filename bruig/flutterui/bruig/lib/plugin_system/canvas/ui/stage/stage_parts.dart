import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';

// stage_parts.dart is dragging a part of an element rather than the element: a
// chart's title, description or key, a table's column rules, and which table
// cell a point is in.
//
// These pieces are placed inside a box by the painters, so the questions are
// asked of the same code that draws them (chartLabelPlaces, tableColumnWidths),
// and a label is picked up exactly where it is seen. Nothing here touches the
// controller or the widget: each function takes the element and its rectangle
// and returns an answer or a new element; committing it stays with the stage.

/// ChartLabelGrab is which of a chart's three pieces of writing is being
/// dragged, and whether by its body or by its corner.
class ChartLabelGrab {
  final ChartLabelPart part;
  final bool resizing;

  /// grab is where in the label the pointer took hold, in document units, so
  /// the label does not jump its own corner under the pointer.
  final Offset grab;

  const ChartLabelGrab(this.part, this.resizing, this.grab);
}

/// chartLabelGrabAt is which of the three a document point lands on, if any.
/// Corners before bodies, in reverse drawing order, so the one on top wins.
/// The key is moved but not resized: its size comes from its setting and its
/// words. [slop] is the corner's reach in document units (the stage's
/// screen-pixel allowance over the zoom).
ChartLabelGrab? chartLabelGrabAt(
    ChartElement e, Rect bounds, Offset doc, double slop) {
  var rects = chartLabelPlaces(e, bounds);
  for (var part in ChartLabelPart.values.reversed) {
    var rect = rects[part];
    if (rect == null || rect.isEmpty) continue;
    if (part != ChartLabelPart.legend &&
        (doc - rect.bottomRight).distance <= slop) {
      return ChartLabelGrab(part, true, doc - rect.bottomRight);
    }
    if (rect.contains(doc)) {
      return ChartLabelGrab(part, false, doc - rect.topLeft);
    }
  }
  return null;
}

/// chartLabelDragged is [e] with the drag written onto the held label, in
/// fractions of the chart's box so it stays put when the chart is resized.
/// Null for a chart with no area, where every fraction divides by zero.
ChartElement? chartLabelDragged(
    ChartElement e, Rect bounds, ChartLabelGrab grab, Offset doc) {
  if (bounds.width <= 0 || bounds.height <= 0) return null;

  var at = doc - grab.grab;
  var x = (at.dx - bounds.left) / bounds.width;
  var y = (at.dy - bounds.top) / bounds.height;

  if (grab.part == ChartLabelPart.legend) {
    return grownFor(e.copyWith(legend: e.legend.copyWith(x: x, y: y)), bounds);
  }

  // Where it is drawn now (its own place or the chart's default), so a
  // label dragged for the first time moves from where it is seen.
  var drawn = chartLabelPlaces(e, bounds)[grab.part]!;
  var box = (grab.part == ChartLabelPart.title ? e.titleBox : e.descriptionBox)
      .copyWith(
    x: (drawn.left - bounds.left) / bounds.width,
    y: (drawn.top - bounds.top) / bounds.height,
    width: drawn.width / bounds.width,
    height: drawn.height / bounds.height,
  );

  var next = grab.resizing
      ? box.copyWith(
          width: ((doc.dx - grab.grab.dx - bounds.left) / bounds.width - box.x)
              .clamp(0.05, 2.0),
          height: ((doc.dy - grab.grab.dy - bounds.top) / bounds.height - box.y)
              .clamp(0.03, 2.0),
        )
      : box.copyWith(x: x, y: y);

  return grownFor(
      grab.part == ChartLabelPart.title
          ? e.copyWith(titleBox: next)
          : e.copyWith(descriptionBox: next),
      bounds);
}

/// grownFor sizes the chart's box to exactly hold the chart and its placed
/// labels, keeping everything where it looks to be, so a label dragged off
/// the side stays inside the selection and moves with the chart.
///
/// It shrinks as well as grows, back to the chart's own rectangle once the
/// labels are inside again. That is safe only because the chart's rectangle
/// is its own (see ChartBody), so the plot does not follow the box.
ChartElement grownFor(ChartElement e, Rect bounds) {
  var rects = chartLabelPlaces(e, bounds);
  if (rects.isEmpty) return e;

  var wanted = e.body.rectIn(bounds);
  for (var rect in rects.values) {
    wanted = wanted.expandToInclude(rect);
  }
  if (wanted == bounds) return e;

  /// refit rewrites a label's fractions against the new box, so it stays
  /// exactly where it is on screen while the box moves under it.
  ChartLabel refit(ChartLabel label) {
    if (!label.hasPlace) return label;
    var rect = label.rectIn(bounds);
    return label.copyWith(
      x: (rect.left - wanted.left) / wanted.width,
      y: (rect.top - wanted.top) / wanted.height,
      width: rect.width / wanted.width,
      height: rect.height / wanted.height,
    );
  }

  return e
      .copyWith(
        titleBox: refit(e.titleBox),
        descriptionBox: refit(e.descriptionBox),
        // The chart itself stays exactly where it is: a drag about the words
        // must not resize the plot.
        body: ChartBody.fitting(e.body.rectIn(bounds), wanted),
      )
      .withBase(
        x: e.x + (wanted.left - bounds.left),
        y: e.y + (wanted.top - bounds.top),
        width: wanted.width,
        height: wanted.height,
      ) as ChartElement;
}

/// tableColumnDividers is where a table's inner column rules fall, in
/// document units. The outer two are the element's edges, which have resize
/// handles already.
List<double> tableColumnDividers(TableElement e, Rect bounds) {
  var widths = tableColumnWidths(e, bounds);
  var out = <double>[];
  var x = bounds.left;
  for (var i = 0; i < widths.length - 1; i++) {
    x += widths[i];
    out.add(x);
  }
  return out;
}

/// tableColumnAt is which divider a document point is on, if any, given the
/// pointer's reach in document units. The reach is narrowed to a quarter of
/// the thinner column either side, so narrow columns (a league table's GD)
/// can still be clicked.
int? tableColumnAt(TableElement e, Rect bounds, Offset doc, double slop) {
  if (!bounds.inflate(slop).contains(doc)) return null;
  var widths = tableColumnWidths(e, bounds);
  var dividers = tableColumnDividers(e, bounds);
  for (var i = 0; i < dividers.length; i++) {
    var near = math.min(
        slop,
        math.min(i < widths.length ? widths[i] : slop,
                i + 1 < widths.length ? widths[i + 1] : slop) *
            0.25);
    if ((doc.dx - dividers[i]).abs() <= near) return i;
  }
  return null;
}

/// tableColumnDragged is [e] with the drag written onto the two columns
/// either side of divider [at], leaving every other column where it is: a
/// table fills its element, so widening one narrows its neighbour.
TableElement? tableColumnDragged(
    TableElement e, Rect bounds, int at, Offset doc) {
  if (bounds.width <= 0) return null;

  // Seeded from the measured widths, so a drag starts from the table as
  // it looks rather than from equal columns.
  var widths = tableColumnWidths(e, bounds);
  if (at + 1 >= widths.length) return null;

  var pair = widths[at] + widths[at + 1];
  var left = (doc.dx - (bounds.left + _sumTo(widths, at)))
      .clamp(bounds.width * 0.02, pair - bounds.width * 0.02);

  widths[at] = left;
  widths[at + 1] = pair - left;

  return e.copyWith(columnWidths: [for (var w in widths) w / bounds.width]);
}

/// tableCellAt is which cell of a table a document point is in.
(int, int)? tableCellAt(TableElement e, Rect bounds, Offset doc) {
  if (!bounds.contains(doc) || e.rows.isEmpty) return null;

  var widths = tableColumnWidths(e, bounds);
  var heights = tableRowHeights(e, bounds);

  var row = 0;
  var y = bounds.top;
  for (; row < heights.length - 1; row++) {
    if (doc.dy < y + heights[row]) break;
    y += heights[row];
  }

  var col = 0;
  var x = bounds.left;
  for (; col < widths.length - 1; col++) {
    if (doc.dx < x + widths[col]) break;
    x += widths[col];
  }
  return (row, col);
}

/// tableCellRect is where that cell is, in document units.
Rect tableCellRect(TableElement e, Rect bounds, int row, int col) {
  var widths = tableColumnWidths(e, bounds);
  var heights = tableRowHeights(e, bounds);
  if (row >= heights.length || col >= widths.length) return bounds;
  return Rect.fromLTWH(
    bounds.left + _sumTo(widths, col),
    bounds.top + _sumTo(heights, row),
    widths[col],
    heights[row],
  );
}

/// tableWithCell is [e] with one cell rewritten, growing the grid to reach it.
TableElement tableWithCell(TableElement e, int row, int col, String text) {
  var width = math.max(e.columnCount, col + 1);
  var rows = [
    for (var r in e.rows) [...r, for (var i = r.length; i < width; i++) ""],
  ];
  while (rows.length <= row) {
    rows.add(List.filled(width, ""));
  }
  rows[row][col] = text;
  return e.copyWith(rows: rows);
}

double _sumTo(List<double> widths, int end) {
  var total = 0.0;
  for (var i = 0; i < end; i++) {
    total += widths[i];
  }
  return total;
}

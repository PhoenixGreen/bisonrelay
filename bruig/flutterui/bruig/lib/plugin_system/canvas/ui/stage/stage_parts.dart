import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';

// stage_parts.dart is dragging part of an element: a chart's title,
// description or key, a table's column rules, and finding a table's cells.
// Places come from the painters' own code (chartLabelPlaces,
// tableColumnWidths), so a part is picked up exactly where it is seen. Each
// function takes the element and its rectangle and returns an answer or a
// new element; committing it is the stage's job.

/// ChartLabelGrab is which of a chart's three labels is being dragged, and
/// whether by its body or its corner.
class ChartLabelGrab {
  final ChartLabelPart part;

  /// resizing is whether it was taken by its corner, to size it.
  final bool resizing;

  /// grab is where in the label the pointer took hold, in document units, so
  /// the label does not jump under the pointer.
  final Offset grab;

  const ChartLabelGrab(this.part, this.grab, {required this.resizing});
}

/// chartLabelGrabAt is which label a document point lands on, if any, in
/// reverse drawing order so the one on top wins. The key is moved but never
/// resized: its size comes from its setting and words. [slop] is the
/// corner's reach in document units.
ChartLabelGrab? chartLabelGrabAt(
    ChartElement e, Rect bounds, Offset doc, double slop) {
  var rects = chartLabelPlaces(e, bounds);
  for (var part in ChartLabelPart.values.reversed) {
    var rect = rects[part];
    if (rect == null || rect.isEmpty) continue;
    if (part != ChartLabelPart.legend &&
        (doc - rect.bottomRight).distance <= slop) {
      return ChartLabelGrab(part, doc - rect.bottomRight, resizing: true);
    }
    if (rect.contains(doc)) {
      return ChartLabelGrab(part, doc - rect.topLeft, resizing: false);
    }
  }
  return null;
}

/// chartLabelDragged is [e] with the drag written onto the held label, in
/// fractions of the chart's box so it stays put when the chart is resized.
/// Null for a chart with no area.
ChartElement? chartLabelDragged(
    ChartElement e, Rect bounds, ChartLabelGrab grab, Offset doc) {
  if (bounds.width <= 0 || bounds.height <= 0) return null;

  var at = doc - grab.grab;
  var x = (at.dx - bounds.left) / bounds.width;
  var y = (at.dy - bounds.top) / bounds.height;

  if (grab.part == ChartLabelPart.legend) {
    return _grownFor(e.copyWith(legend: e.legend.copyWith(x: x, y: y)), bounds);
  }

  // From where it is drawn (its own place or the default), so a first drag
  // starts where it is seen.
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

  return _grownFor(
      grab.part == ChartLabelPart.title
          ? e.copyWith(titleBox: next)
          : e.copyWith(descriptionBox: next),
      bounds);
}

/// _grownFor sizes the chart's box to hold the chart and its placed labels,
/// leaving everything where it is on screen, so a label dragged off the side
/// stays in the selection. It shrinks too, which is safe only because the
/// plot has its own rectangle (ChartBody) and does not follow the box.
ChartElement _grownFor(ChartElement e, Rect bounds) {
  var rects = chartLabelPlaces(e, bounds);
  if (rects.isEmpty) return e;

  var wanted = e.body.rectIn(bounds);
  for (var rect in rects.values) {
    wanted = wanted.expandToInclude(rect);
  }
  if (wanted == bounds) return e;

  /// refit rewrites a label's fractions against the new box, so it stays
  /// put on screen.
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
        // Dragging a label must not move or resize the plot.
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
/// document units; the outer edges have resize handles already.
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

/// tableColumnAt is which divider a document point is on, if any, within
/// [slop] document units narrowed to a quarter of the thinner column either
/// side, so narrow columns can still be clicked.
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
/// either side of divider [at]: a table fills its element, so widening one
/// narrows its neighbour and the rest stay put.
TableElement? tableColumnDragged(
    TableElement e, Rect bounds, int at, Offset doc) {
  if (bounds.width <= 0) return null;

  // From the measured widths, so a drag starts from the table as it looks. A
  // copy: the painter keeps the list it measured, and draws from it again.
  var widths = [...tableColumnWidths(e, bounds)];
  if (at + 1 >= widths.length) return null;

  var pair = widths[at] + widths[at + 1];
  var left = (doc.dx - (bounds.left + _sumTo(widths, at)))
      .clamp(bounds.width * 0.02, pair - bounds.width * 0.02);

  widths[at] = left;
  widths[at + 1] = pair - left;

  return e.copyWith(columnWidths: [for (var w in widths) w / bounds.width]);
}

/// tableCellAt is the (row, column) a document point is in, or null.
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

/// tableCellRect is a cell's rectangle, in document units.
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

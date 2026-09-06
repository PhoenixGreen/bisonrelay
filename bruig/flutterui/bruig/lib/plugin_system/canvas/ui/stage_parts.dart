import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';

// stage_parts.dart is dragging a *part* of an element rather than the element:
// a chart's title, description or key, a table's column rules, and which cell
// of a table a point is in.
//
// These are their own file because they are the one kind of gesture the stage
// cannot answer out of an element's rectangle. Everything else it drags is a
// box with a position and a size; these are pieces drawn inside a box, whose
// places are decided by the painters. So the questions are asked of the same
// code that draws them -- chartLabelPlaces, tableColumnWidths -- and a label
// is picked up exactly where it can be seen rather than where a second,
// separately maintained idea of its place says it should be.
//
// Nothing here touches the controller or the widget. Each function is given
// the element and the rectangle it is drawn in and returns either an answer
// or a new element; committing that to the document, and deciding whether the
// change is transient, stays with the stage.

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
///
/// The corner is tried before the body, and they are tried in reverse drawing
/// order, so the one on top is the one picked up when they overlap.
///
/// The key is moved but not resized: its size is decided by its own setting
/// and by the words in it, so a corner to drag would be a corner that argued
/// with the number in the panel.
///
/// [slop] is the corner's reach in document units -- the stage's screen-pixel
/// allowance divided by the zoom, so it is the same size under the pointer at
/// every scale.
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

/// chartLabelDragged is [e] with the drag written onto whichever label is
/// held, in fractions of the chart's own box so that it stays put when the
/// chart is resized.
///
/// Null when there is nothing sensible to write -- a chart with no area is
/// one where every fraction would be a division by zero.
ChartElement? chartLabelDragged(
    ChartElement e, Rect bounds, ChartLabelGrab grab, Offset doc) {
  if (bounds.width <= 0 || bounds.height <= 0) return null;

  var at = doc - grab.grab;
  var x = (at.dx - bounds.left) / bounds.width;
  var y = (at.dy - bounds.top) / bounds.height;

  if (grab.part == ChartLabelPart.legend) {
    return grownFor(e.copyWith(legend: e.legend.copyWith(x: x, y: y)), bounds);
  }

  // Where it is drawn now, which is its own place or the chart's idea of one
  // -- a label dragged for the first time must move from where it can be seen
  // rather than from a corner it has never been in.
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
/// labels, keeping everything where it looks like it is.
///
/// Without it a title dragged off the side sat outside the element's box. It
/// still drew -- nothing clips it -- but it was outside the selection outline
/// and outside what a marquee or a group move would pick up, so it read as a
/// separate thing that happened to be near the chart. The box is what says
/// "this text belongs to this chart".
///
/// It shrinks as well as grows, back to the chart's own rectangle once the
/// labels are inside it again. Growing only was the first attempt and left a
/// box that could be stretched but never put back, so an experimental drag out
/// and back cost a chart a margin of empty selection for good. Shrinking is
/// only safe because the chart's own rectangle is a thing in its own right --
/// see ChartBody -- so the plot does not follow the box in either direction.
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
        // The chart itself stays exactly where it is. Growing the box grew the
        // plot with it, so dragging a title off the corner made the bars
        // taller -- a resize nobody asked for, from a drag that was about the
        // words.
        body: ChartBody.fitting(e.body.rectIn(bounds), wanted),
      )
      .withBase(
        x: e.x + (wanted.left - bounds.left),
        y: e.y + (wanted.top - bounds.top),
        width: wanted.width,
        height: wanted.height,
      ) as ChartElement;
}

/// tableColumnDividers is where a table's column rules fall, in document
/// units.
///
/// Only the inner ones. The outer two are the element's own edges, which
/// already have resize handles on them and would be two controls doing
/// different things in the same place.
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
/// pointer's reach in document units.
int? tableColumnAt(TableElement e, Rect bounds, Offset doc, double slop) {
  if (!bounds.inflate(slop).contains(doc)) return null;
  var dividers = tableColumnDividers(e, bounds);
  for (var i = 0; i < dividers.length; i++) {
    if ((doc.dx - dividers[i]).abs() <= slop) return i;
  }
  return null;
}

/// tableColumnDragged is [e] with the drag written onto the two columns
/// either side of divider [at], leaving every other column where it is.
///
/// Either side, because a table fills its element: making one column wider
/// has to make another narrower, and taking it from its neighbour is the only
/// choice that does not shuffle the whole table sideways.
TableElement? tableColumnDragged(
    TableElement e, Rect bounds, int at, Offset doc) {
  if (bounds.width <= 0) return null;

  // Seeded from the measured widths the first time, so a drag starts from the
  // table as it looks rather than from equal columns.
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

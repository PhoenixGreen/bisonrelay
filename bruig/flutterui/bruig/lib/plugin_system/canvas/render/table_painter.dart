import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// table_painter.dart draws a TableElement.
//
// Columns are sized by their contents unless the element says otherwise,
// because equal columns waste half a table whose first column is "Q1" and
// whose second is "Average possession in the opposition half". The measuring
// is capped so one very long cell cannot squeeze every other column to
// nothing, which is the failure mode of every content-sized table.

/// paintTable draws [e] filling [rect].
void paintTable(ui.Canvas canvas, Rect rect, TableElement e) {
  if (rect.width <= 4 || rect.height <= 4 || e.rows.isEmpty) {
    if (e.rows.isEmpty) _placeholder(canvas, rect, e);
    return;
  }

  var cols = e.columnCount;
  if (cols == 0) return;

  var widths = _columnWidths(e, rect, cols);
  var heights = _rowHeights(e, rect);
  var radius = Radius.circular(e.cornerRadius);
  var outer = RRect.fromRectAndRadius(rect, radius);

  canvas.save();
  canvas.clipRRect(outer);

  if (e.cellFill.a > 0) canvas.drawRect(rect, Paint()..color = e.cellFill);

  // Row fills first, so the grid and the text land on top of them rather than
  // being covered by the next row's zebra tint.
  var y = rect.top;
  for (var r = 0; r < e.rows.length; r++) {
    var h = heights[r];
    var isHeader = e.headerRow && r == 0;
    Color? fill;
    if (isHeader) {
      fill = e.headerFill;
    } else if (e.zebra && ((e.headerRow ? r - 1 : r).isOdd)) {
      fill = e.zebraFill;
    }
    if (fill != null && fill.a > 0) {
      canvas.drawRect(Rect.fromLTWH(rect.left, y, rect.width, h),
          Paint()..color = fill);
    }
    y += h;
  }

  // Cells.
  y = rect.top;
  for (var r = 0; r < e.rows.length; r++) {
    var h = heights[r];
    var x = rect.left;
    for (var c = 0; c < cols; c++) {
      var w = widths[c];
      var isHeader = (e.headerRow && r == 0) || (e.headerColumn && c == 0);
      var spec = isHeader ? e.headerSpec : e.cellSpec;
      paintTextInBox(
        canvas,
        e.cell(r, c),
        spec.copyWith(verticalAlign: VerticalAlignSpec.middle),
        Rect.fromLTWH(x + e.cellPadding, y, w - e.cellPadding * 2, h),
        clip: true,
      );
      x += w;
    }
    y += h;
  }

  // Rules.
  if (e.grid != TableGrid.none && e.gridWidth > 0) {
    var paint = Paint()
      ..color = e.gridColor
      ..strokeWidth = e.gridWidth;

    if (e.grid.drawsHorizontal) {
      var ry = rect.top;
      for (var r = 0; r < e.rows.length - 1; r++) {
        ry += heights[r];
        canvas.drawLine(Offset(rect.left, ry), Offset(rect.right, ry), paint);
      }
    }
    if (e.grid.drawsVertical) {
      var rx = rect.left;
      for (var c = 0; c < cols - 1; c++) {
        rx += widths[c];
        canvas.drawLine(Offset(rx, rect.top), Offset(rx, rect.bottom), paint);
      }
    }
  }

  canvas.restore();

  if (e.grid.drawsOuter && e.gridWidth > 0) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(e.gridWidth / 2), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.gridWidth
          ..color = e.gridColor);
  }
}

void _placeholder(ui.Canvas canvas, Rect rect, TableElement e) {
  canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(e.cornerRadius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = e.gridColor);
  paintTextInBox(
      canvas,
      "No table data yet",
      e.cellSpec.copyWith(
          align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle),
      rect,
      clip: true);
}

/// _columnWidths sizes the columns to their contents, or to the fractions the
/// element carries when it has any.
List<double> _columnWidths(TableElement e, Rect rect, int cols) {
  if (e.columnWidths.length == cols) {
    var total = e.columnWidths.fold<double>(0, (t, v) => t + v);
    if (total > 0) {
      return [for (var w in e.columnWidths) rect.width * w / total];
    }
  }

  // Measured against a third of the table, so one long cell wraps rather than
  // taking the whole width and starving its neighbours.
  var cap = rect.width / 3;
  var natural = List.filled(cols, 0.0);
  for (var r = 0; r < e.rows.length; r++) {
    var spec = e.headerRow && r == 0 ? e.headerSpec : e.cellSpec;
    for (var c = 0; c < cols; c++) {
      var text = e.cell(r, c);
      if (text.isEmpty) continue;
      var w = layoutText(text, spec, maxWidth: cap).width;
      natural[c] = math.max(natural[c], w + e.cellPadding * 2);
    }
  }

  var sum = natural.fold<double>(0, (t, v) => t + v);
  if (sum <= 0) return List.filled(cols, rect.width / cols);
  // Scaled to fill the element exactly, whether the natural widths came to
  // more than there is room for or less.
  return [for (var w in natural) rect.width * w / sum];
}

/// _rowHeights splits the height evenly, giving the header its extra share.
List<double> _rowHeights(TableElement e, Rect rect) {
  var n = e.rows.length;
  var headerShare = e.headerRow ? e.headerHeightRatio : 1.0;
  var units = (n - (e.headerRow ? 1 : 0)) + headerShare;
  var unit = rect.height / (units <= 0 ? 1 : units);
  return [
    for (var r = 0; r < n; r++)
      (e.headerRow && r == 0) ? unit * headerShare : unit,
  ];
}

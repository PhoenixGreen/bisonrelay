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

  // The header column's fill, down the first column.
  //
  // It had none: the switch changed the type in column one and nothing else,
  // so on a table whose header type and cell type had been made to match it
  // did nothing anybody could see. The header *row* has had a fill all along,
  // and a header column is the same idea turned ninety degrees.
  if (e.headerColumn && e.headerFill.a > 0 && widths.isNotEmpty) {
    var top = rect.top + (e.headerRow ? heights.first : 0);
    canvas.drawRect(
        Rect.fromLTRB(rect.left, top, rect.left + widths.first, rect.bottom),
        Paint()..color = e.headerFill);
  }

  // A rule that picks out a whole row is drawn as one band across the table
  // rather than cell by cell, so its border is a border round the row and not
  // a border round each of its cells.
  y = rect.top;
  for (var r = 0; r < e.rows.length; r++) {
    var h = heights[r];
    for (var rule in e.rules) {
      if (!rule.wholeRow || rule.row - 1 != r) continue;
      _paintStyleBox(canvas, Rect.fromLTWH(rect.left, y, rect.width, h),
          rule.style);
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

      // Whatever the rules say about this one. Drawn under its own text and
      // over the row's fill, which is what makes a chip a chip.
      var style = e.styleFor(r, c);
      if (style != null) {
        if (style.paintsBox && !_isWholeRowOnly(e, r, c)) {
          _paintStyleBox(
              canvas, Rect.fromLTWH(x, y, w, h), style);
        }
        if (style.changesType) {
          spec = spec.copyWith(
            fontSize: spec.fontSize * style.fontScale,
            weight: style.weight == 0 ? spec.weight : style.weight,
            color: style.textColor.a > 0 ? style.textColor : spec.color,
          );
        }
      }
      // The spec's own vertical alignment, not the middle regardless. It was
      // forced here, so the Vertical setting on a table's type did nothing at
      // all -- and a table of one-line cells does want the middle, which is
      // why it is the default rather than an override.
      paintTextInBox(
        canvas,
        e.cell(r, c),
        spec,
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

/// _isWholeRowOnly is whether the only rules touching this cell are ones that
/// already drew a band across its row -- so the band is not drawn again, once
/// per cell, with a border between each.
bool _isWholeRowOnly(TableElement e, int row, int col) {
  var head = e.header;
  for (var rule in e.rules) {
    if (rule.row >= 1 && rule.row - 1 != row) continue;
    var wanted = rule.columnIndex(head);
    if (wanted == -2 || (wanted >= 0 && wanted != col)) continue;
    if (!rule.matches(e.cell(row, col))) continue;
    if (!rule.wholeRow && rule.style.paintsBox) return false;
  }
  return true;
}

/// _paintStyleBox fills and outlines one rule's box.
void _paintStyleBox(ui.Canvas canvas, Rect cell, TableCellStyle style) {
  var box = cell.deflate(style.inset.clamp(0.0, cell.shortestSide / 2));
  if (box.width <= 0 || box.height <= 0) return;
  var rounded = RRect.fromRectAndRadius(box, Radius.circular(style.radius));

  if (style.background.a > 0) {
    canvas.drawRRect(rounded, Paint()..color = style.background);
  }
  if (style.borderColor.a > 0 && style.borderWidth > 0) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(box.deflate(style.borderWidth / 2),
            Radius.circular(style.radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.borderWidth
          ..color = style.borderColor);
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

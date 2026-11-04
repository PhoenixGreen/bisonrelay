import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// table_painter.dart draws a TableElement.
//
// Columns are sized by their contents unless the element gives fractions.
// The measuring is capped so one very long cell cannot squeeze every other
// column to nothing.

/// paintTable draws [e] filling [rect].
///
/// [images] is where a cell holding a picture gets it from; without it (or
/// while loading) such cells get the missing-picture mark, never their asset
/// id as text.
void paintTable(ui.Canvas canvas, Rect rect, TableElement e,
    {CanvasImageSource? images}) {
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

  // Both fills are shaded across the whole table, so a fade runs once top to
  // bottom rather than restarting on every row.
  var cellPaint = PaintSpec(e.cellFill, gradient: e.cellFade);
  var headerPaint = PaintSpec(e.headerFill, gradient: e.headerFade);
  var header = headerPaint.shaderFor(rect);

  // A fade of its own counts as a fill, and where there is one the paint is
  // left opaque: a paint's alpha multiplies its shader. See PaintSpec.into.
  if (cellPaint.shows) {
    canvas.drawRect(rect, cellPaint.into(Paint(), rect));
  }

  // Row fills first, so the grid and text land on top of them.
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
    if (fill != null && (fill.a > 0 || (isHeader && header != null))) {
      canvas.drawRect(Rect.fromLTWH(rect.left, y, rect.width, h),
          isHeader ? headerPaint.into(Paint(), rect) : (Paint()..color = fill));
    }
    y += h;
  }

  // The header column's fill, down the first column, as the header row has.
  if (e.headerColumn && headerPaint.shows && widths.isNotEmpty) {
    var top = rect.top + (e.headerRow ? heights.first : 0);
    canvas.drawRect(
        Rect.fromLTRB(rect.left, top, rect.left + widths.first, rect.bottom),
        headerPaint.into(Paint(), rect));
  }

  // A rule with no word to look for is drawn as one box around everything it
  // picks out, not a box per cell: a row is a band across, a column a band
  // down, both the cell where they cross.
  for (var rule in e.rules) {
    if (!rule.banded || !rule.style.paintsBox) continue;
    var box = _bandFor(e, rule, rect, widths, heights, cols);
    if (box != null) _paintStyleBox(canvas, box, rule.style);
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

      // A picture, if the cell names one: inside the cell's padding and
      // centred, so a column of badges lines up whatever their shapes.
      var asset = TableElement.pictureIn(e.cell(r, c));
      if (asset != null) {
        var cell = Rect.fromLTWH(x, y, w, h).deflateSides(e);
        var scale = e.pictureScale.clamp(0.05, 1.0);
        var box = Rect.fromCenter(
            center: cell.center,
            width: cell.width * scale,
            height: cell.height * scale);
        // A vector first: sharp at any export scale and no bitmap to hold.
        var vector = images?.resolveVector(asset);
        if (vector != null) {
          _paintCellVector(canvas, vector, box);
        } else {
          var image = images?.resolve(asset, const BackgroundRemoval());
          if (image != null) {
            _paintCellImage(canvas, image, box);
          } else {
            // Not arrived, or never will. Marked rather than blank, so a
            // missing picture can be told from an empty cell.
            _paintMissingPicture(canvas, box, e);
          }
        }
        x += w;
        continue;
      }

      // Everything the rules say about this cell, worked out once (see
      // TableCellLook).
      var look = e.lookAt(r, c);
      var style = look.style;
      if (style != null) {
        if (style.changesType) {
          spec = spec.copyWith(
            fontSize: spec.fontSize * style.fontScale,
            weight: style.weight == 0 ? spec.weight : style.weight,
            color: style.textColor.a > 0 ? style.textColor : spec.color,
            align: style.align ?? spec.align,
            verticalAlign: style.verticalAlign ?? spec.verticalAlign,
            letterSpacing: style.letterSpacing != 0
                ? style.letterSpacing
                : spec.letterSpacing,
          );
        }
      }
      // The table's padding on all four sides, plus whatever a rule adds
      // (without which a rule's left or right alignment sits on the edge).
      var extra = style?.textPad ?? 0;
      var left = e.leftPad + extra, right = e.rightPad + extra;
      var top = e.topPad + extra, bottom = e.bottomPad + extra;
      var textBox = Rect.fromLTWH(x + left, y + top,
          math.max(1, w - left - right), math.max(1, h - top - bottom));

      // A header kept but not shown (TableElement.hiddenHeaders): background,
      // rules and width still apply; only the writing is left out.
      if (!e.shows(r, c)) {
        x += w;
        continue;
      }

      // Chips round the words, drawn before the words. Each word rule draws
      // its own chips in its own style, not the merged style, so "D L W"
      // with a rule per letter gets three colours.
      var slots = _slotsIn(e.cell(r, c), spec, textBox, style?.letterWidth ?? 0,
          style?.letterSpacing ?? 0);
      _paintChips(canvas, look, e.cell(r, c), spec, textBox,
          Rect.fromLTWH(x, y, w, h), slots);

      // On a fixed pitch, if a rule asked for one: a slot per character, so
      // the boxes round them line up.
      if (slots != null) {
        _paintSlots(canvas, look, e.cell(r, c), spec, slots);
        x += w;
        continue;
      }

      // Where rules style parts of the cell, it is laid out as one paragraph
      // of styled runs, so the line still aligns as a whole.
      var runs = _runsOf(look, e.cell(r, c), spec);
      if (runs != null) {
        paintRunsInBox(canvas, runs, spec, textBox, clip: true);
        x += w;
        continue;
      }

      // The spec's own vertical alignment (middle is its default, not forced).
      paintTextInBox(
        canvas,
        e.cell(r, c),
        spec,
        textBox,
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

  if (e.grid.drawsOuter && e.showOutline && e.gridWidth > 0) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(e.gridWidth / 2), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.gridWidth
          ..color = e.gridColor);
  }
}

/// _paintCellImage draws a picture inside a cell, contained rather than
/// cropped: a badge with its sides cut off is not a badge.
void _paintCellImage(ui.Canvas canvas, ui.Image image, Rect box) {
  if (box.width <= 0 || box.height <= 0) return;
  var size = Size(image.width.toDouble(), image.height.toDouble());
  if (size.isEmpty) return;

  var scale = math.min(box.width / size.width, box.height / size.height);
  var drawn = Rect.fromCenter(
      center: box.center,
      width: size.width * scale,
      height: size.height * scale);
  canvas.drawImageRect(image, Offset.zero & size, drawn,
      Paint()..filterQuality = FilterQuality.high);
}

/// _paintMissingPicture is the mark left where a picture has not arrived: a
/// rounded frame crossed corner to corner, in the grid colour.
void _paintMissingPicture(ui.Canvas canvas, Rect box, TableElement e) {
  var side = math.min(box.width, box.height) * 0.7;
  if (side < 6) return;
  var frame = Rect.fromCenter(center: box.center, width: side, height: side);
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, side * 0.06)
    ..color = e.gridColor;

  canvas.drawRRect(
      RRect.fromRectAndRadius(frame, Radius.circular(side * 0.12)), paint);
  canvas.drawLine(frame.topLeft, frame.bottomRight, paint);
}

/// _paintCellVector draws a vector inside a cell, contained rather than
/// cropped, at whatever size the cell happens to be.
void _paintCellVector(ui.Canvas canvas, CanvasVector vector, Rect box) {
  if (box.width <= 0 || box.height <= 0 || vector.size.isEmpty) return;
  var scale =
      math.min(box.width / vector.size.width, box.height / vector.size.height);
  var drawn = Size(vector.size.width * scale, vector.size.height * scale);

  canvas.save();
  canvas.translate(
      box.center.dx - drawn.width / 2, box.center.dy - drawn.height / 2);
  canvas.scale(scale);
  canvas.drawPicture(vector.picture);
  canvas.restore();
}

/// _bandFor is the rectangle a banded rule covers: every cell it picks out,
/// taken together.
Rect? _bandFor(TableElement e, TableRule rule, Rect rect, List<double> widths,
    List<double> heights, int cols) {
  var head = e.header;

  var top = rect.top;
  double? fromY, toY;
  for (var r = 0; r < heights.length; r++) {
    if (rule.matchesRow(r)) {
      fromY ??= top;
      toY = top + heights[r];
    }
    top += heights[r];
  }
  if (fromY == null || toY == null) return null;

  // Every column the rule names, taken together into one band.
  var left = rect.left;
  double? fromX, toX;
  for (var c = 0; c < cols; c++) {
    if (rule.matchesColumn(c, head)) {
      fromX ??= left;
      toX = left + widths[c];
    }
    left += widths[c];
  }
  if (fromX == null || toX == null) return null;

  return Rect.fromLTRB(fromX, fromY, toX, toY);
}

/// _paintChips draws the boxes for every rule that names a word in this cell,
/// each in its own style, at every occurrence. Hugging boxes come from the
/// glyph boxes (textRunBox), or the slots on a fixed pitch.
void _paintChips(ui.Canvas canvas, TableCellLook look, String text,
    TextSpec spec, Rect textBox, Rect cell, List<Rect>? slots) {
  for (var (rule, runs) in look.words) {
    if (!rule.style.paintsBox) continue;

    for (var (from, to) in runs) {
      var box = !rule.style.hug
          ? cell
          // On a fixed pitch the box is the slots themselves.
          : (slots != null
              ? _slotSpan(slots, from, to)
              : (textRunBox(text, spec, textBox, from, to) ??
                  _wordsIn(text, spec, textBox)));
      if (box == null) continue;
      _paintStyleBox(canvas, box, rule.style, hug: rule.style.hug);
    }
  }
}

/// _slotsIn is one rectangle per character when a rule asked for a fixed
/// pitch ([width] > 0), and null when it did not. Slots are what line up the
/// boxes round letters of different widths.
List<Rect>? _slotsIn(
    String text, TextSpec spec, Rect box, double width, double gap) {
  if (width <= 0 || text.isEmpty) return null;

  var pitch = width + gap;
  var total = text.length * width + (text.length - 1) * gap;
  var left = switch (spec.align) {
    TextAlignSpec.center => box.center.dx - total / 2,
    TextAlignSpec.right => box.right - total,
    _ => box.left,
  };

  // As tall as the letters, not the row; min height makes a chip taller.
  var height = math.min(
      box.height, layoutText(text, spec, maxWidth: double.infinity).height);
  var top = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => box.top,
    VerticalAlignSpec.bottom => box.bottom - height,
    VerticalAlignSpec.middle => box.center.dy - height / 2,
  };

  return [
    for (var i = 0; i < text.length; i++)
      Rect.fromLTWH(left + pitch * i, top, width, height),
  ];
}

/// _slotSpan is the slots a run covers, taken together.
Rect? _slotSpan(List<Rect> slots, int from, int to) {
  if (from < 0 || to > slots.length || to <= from) return null;
  var out = slots[from];
  for (var i = from + 1; i < to; i++) {
    out = out.expandToInclude(slots[i]);
  }
  return out;
}

/// _paintSlots draws each character in the middle of its own slot, moved by
/// whatever nudge the rule that claims it asks for.
///
/// The nudge moves the letter, not its box, so the slots stay in line.
void _paintSlots(ui.Canvas canvas, TableCellLook look, String text,
    TextSpec spec, List<Rect> slots) {
  var centred = spec.copyWith(
      align: TextAlignSpec.center,
      verticalAlign: VerticalAlignSpec.middle,
      letterSpacing: 0);

  for (var i = 0; i < text.length && i < slots.length; i++) {
    if (text[i].trim().isEmpty) continue;
    var rule = look.ruleAt(i);
    var nudge = rule == null
        ? Offset.zero
        : Offset(rule.style.nudgeX, rule.style.nudgeY);
    // Each character in the type its own rule asks for.
    paintTextInBox(canvas, text[i], _typed(centred, _typeAt(look, i)),
        nudge == Offset.zero ? slots[i] : slots[i].shift(nudge));
  }
}

/// _runsOf splits a cell into stretches of differently styled text, or null
/// when every character is the same.
List<(String, TextSpec)>? _runsOf(
    TableCellLook look, String text, TextSpec spec) {
  if (text.isEmpty || look.words.isEmpty) return null;

  var styles = [
    for (var i = 0; i < text.length; i++) _typeAt(look, i),
  ];
  if (styles.every((s) => s == null)) return null;

  var runs = <(String, TextSpec)>[];
  var from = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i < text.length && identical(styles[i], styles[from])) continue;
    runs.add((text.substring(from, i), _typed(spec, styles[from])));
    from = i;
  }
  return runs;
}

/// _typed is [spec] with one rule's type changes applied.
TextSpec _typed(TextSpec spec, TableCellStyle? style) {
  if (style == null) return spec;
  return spec.copyWith(
    fontSize: spec.fontSize * style.fontScale,
    weight: style.weight == 0 ? spec.weight : style.weight,
    color: style.textColor.a > 0 ? style.textColor : spec.color,
  );
}

/// _typeAt is the type change that belongs to one character, or null.
TableCellStyle? _typeAt(TableCellLook look, int index) {
  var rule = look.ruleAt(index);
  return rule != null && rule.style.changesType ? rule.style : null;
}

/// _wordsIn is the box the words actually occupy inside their cell, which is
/// what a chip is drawn round.
Rect _wordsIn(String text, TextSpec spec, Rect box) {
  if (text.trim().isEmpty) return box;
  var painter = layoutText(text, spec, maxWidth: box.width);
  var width = math.min(box.width, painter.width);
  var height = math.min(box.height, painter.height);
  var dx = switch (spec.align) {
    TextAlignSpec.center => box.center.dx - width / 2,
    TextAlignSpec.right => box.right - width,
    _ => box.left,
  };
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => box.top,
    VerticalAlignSpec.bottom => box.bottom - height,
    _ => box.center.dy - height / 2,
  };
  return Rect.fromLTWH(dx, dy, width, height);
}

/// _paintStyleBox fills and outlines one rule's box.
void _paintStyleBox(ui.Canvas canvas, Rect cell, TableCellStyle style,
    {bool hug = false}) {
  // The one inset number is padding outward round a chip and an inset
  // inward inside a band.
  var box = hug
      ? cell.inflate(style.inset.clamp(0.0, 200.0))
      : cell.inflate(-style.inset.clamp(-200.0, cell.shortestSide / 2));

  // A minimum size, so chips round letters of different widths match.
  if (hug && (style.minWidth > 0 || style.minHeight > 0)) {
    box = Rect.fromCenter(
      center: box.center,
      width: math.max(box.width, style.minWidth),
      height: math.max(box.height, style.minHeight),
    );
  }
  if (box.width <= 0 || box.height <= 0) return;

  if (style.background.a > 0) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(style.radius)),
        Paint()..color = style.background);
  }
  if (style.borderColor.a <= 0 || style.borderWidth <= 0) return;

  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.borderWidth
    ..color = style.borderColor;

  // All four sides is a rounded rectangle; anything else is straight lines,
  // since a rounded corner belongs to two sides.
  if (style.allSides) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            box.deflate(style.borderWidth / 2), Radius.circular(style.radius)),
        paint);
    return;
  }

  var inner = box.deflate(style.borderWidth / 2);
  if (style.sides[0]) {
    canvas.drawLine(inner.topLeft, inner.topRight, paint);
  }
  if (style.sides[1]) {
    canvas.drawLine(inner.topRight, inner.bottomRight, paint);
  }
  if (style.sides[2]) {
    canvas.drawLine(inner.bottomLeft, inner.bottomRight, paint);
  }
  if (style.sides[3]) {
    canvas.drawLine(inner.topLeft, inner.bottomLeft, paint);
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

/// tableColumnWidths is where a table's columns fall. Public so the stage's
/// divider grips use this calculation rather than a second one that drifts.
List<double> tableColumnWidths(TableElement e, Rect rect) =>
    _columnWidths(e, rect, e.columnCount);

// The last content-sized answer, for one element at one width. Measuring lays
// out every cell, so it is not done per frame; a second table just measures
// again.
TableElement? _measuredOf;
double _measuredWidth = 0;
List<double>? _measured;

/// _columnWidths sizes the columns to their contents, or to the fractions the
/// element carries when it has any.
List<double> _columnWidths(TableElement e, Rect rect, int cols) {
  if (e.columnWidths.length == cols) {
    var total = e.columnWidths.fold<double>(0, (t, v) => t + v);
    if (total > 0) {
      return [for (var w in e.columnWidths) rect.width * w / total];
    }
  }

  if (identical(_measuredOf, e) &&
      _measuredWidth == rect.width &&
      _measured?.length == cols) {
    return _measured!;
  }

  // Measured against a third of the table, so one long cell wraps rather than
  // taking the whole width and starving its neighbours.
  var cap = rect.width / 3;
  var natural = List.filled(cols, 0.0);
  for (var r = 0; r < e.rows.length; r++) {
    var spec = e.headerRow && r == 0 ? e.headerSpec : e.cellSpec;
    for (var c = 0; c < cols; c++) {
      // A hidden header is not measured either: a badge column would
      // otherwise be as wide as the word nobody can see in it.
      if (!e.shows(r, c)) continue;
      var text = e.cell(r, c);
      if (text.isEmpty) continue;
      var w = layoutText(text, spec, maxWidth: cap).width;
      natural[c] = math.max(natural[c], w + e.leftPad + e.rightPad);
    }
  }

  var sum = natural.fold<double>(0, (t, v) => t + v);
  // Scaled to fill the element exactly.
  var out = sum <= 0
      ? List.filled(cols, rect.width / cols)
      : [for (var w in natural) rect.width * w / sum];

  _measuredOf = e;
  _measuredWidth = rect.width;
  _measured = out;
  return out;
}

/// deflateSides takes each of a cell's four paddings off it.
extension on Rect {
  Rect deflateSides(TableElement e) => Rect.fromLTRB(
        left + e.leftPad,
        top + e.topPad,
        math.max(left + e.leftPad + 1, right - e.rightPad),
        math.max(top + e.topPad + 1, bottom - e.bottomPad),
      );
}

/// tableRowHeights is where a table's rows fall, public for the stage's cell
/// editor (see [tableColumnWidths]).
List<double> tableRowHeights(TableElement e, Rect rect) => _rowHeights(e, rect);

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

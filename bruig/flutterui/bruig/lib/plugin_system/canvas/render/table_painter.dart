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
// Columns are sized by their contents unless the element says otherwise,
// because equal columns waste half a table whose first column is "Q1" and
// whose second is "Average possession in the opposition half". The measuring
// is capped so one very long cell cannot squeeze every other column to
// nothing, which is the failure mode of every content-sized table.

/// paintTable draws [e] filling [rect].
///
/// [images] is where a cell holding a picture gets it from. Null draws those
/// cells as nothing rather than as their own asset id, which is the right
/// answer while a picture is still loading and the only answer in a context
/// with no store at all.
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

  // A rule with no word to look for is drawn as one box around everything it
  // picks out, rather than a box per cell.
  //
  // A rule naming a row is a band across the table; one naming a column is a
  // band down it; one naming both is the cell where they cross. Per cell, a
  // column border came out as a border round each of its cells, which is a
  // stack of boxes rather than a column with a line round it.
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

      // A picture, if the cell names one. Fitted inside the cell's padding
      // and centred, so a column of badges lines up whatever shape each of
      // them happens to be.
      var asset = TableElement.pictureIn(e.cell(r, c));
      if (asset != null) {
        // Its share of the cell, inside the cell's own padding. A badge that
        // touches the rules either side of it reads as a mistake.
        var cell = Rect.fromLTWH(x, y, w, h).deflate(e.cellPadding);
        var scale = e.pictureScale.clamp(0.05, 1.0);
        var box = Rect.fromCenter(
            center: cell.center,
            width: cell.width * scale,
            height: cell.height * scale);
        // A vector first, and kept as one: a badge drawn from its own
        // drawing is sharp at any export scale and costs no bitmap at all,
        // which is the difference between a squad of twenty-two badges and
        // twenty-two half-megabyte images.
        var vector = images?.resolveVector(asset);
        if (vector != null) {
          _paintCellVector(canvas, vector, box);
        } else {
          var image = images?.resolve(asset, const BackgroundRemoval());
          if (image != null) {
            _paintCellImage(canvas, image, box);
          } else {
            // Nothing to draw yet, or nothing to draw ever. Marked rather
            // than left blank: a cell that names a picture and shows nothing
            // is indistinguishable from a cell that was never told about one,
            // which is a fault that cannot be told from a typo.
            _paintMissingPicture(canvas, box, e);
          }
        }
        x += w;
        continue;
      }

      // Whatever the rules say about this one. Drawn under its own text and
      // over the row's fill, which is what makes a chip a chip.
      var style = e.styleFor(r, c);
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
      // The table's own padding, and whatever a rule adds on top of it.
      // Alignment is unusable without the second: pushed left or right the
      // words sit against the edge, and the table's padding is one number for
      // every cell in it.
      var pad = e.cellPadding + (style?.textPad ?? 0);
      var textBox = Rect.fromLTWH(x + pad, y, math.max(1, w - pad * 2), h);

      // A chip round the word, drawn before the word itself.
      //
      // Fitted to the words rather than to the cell, because the thing
      // anybody asks for by naming a word is a green box behind the W and not
      // a green cell with a W in it. A rule about a whole column has no word
      // and is a band above; one that has been told to fill takes the cell.
      // Every rule that names a word, each drawing its own chips in its own
      // colours.
      //
      // Not the merged style: a form guide has a rule for W, one for D and
      // one for L, and merging them gave every chip in the cell the last
      // rule's background -- and only that rule's chips were drawn at all, so
      // a row reading "D L W" showed one letter marked and two bare.
      _paintChips(canvas, e, r, c, spec, textBox, Rect.fromLTWH(x, y, w, h),
          _slotsIn(e.cell(r, c), spec, textBox, style?.letterWidth ?? 0,
              style?.letterSpacing ?? 0));

      // On a fixed pitch, if a rule asked for one: each character in a slot
      // of its own, so a W and an L land in the same places and the boxes
      // round them line up.
      var slots = _slotsIn(e.cell(r, c), spec, textBox, style?.letterWidth ?? 0,
          style?.letterSpacing ?? 0);
      if (slots != null) {
        _paintSlots(canvas, e.cell(r, c), spec, slots);
        x += w;
        continue;
      }

      // The spec's own vertical alignment, not the middle regardless. It was
      // forced here, so the Vertical setting on a table's type did nothing at
      // all -- and a table of one-line cells does want the middle, which is
      // why it is the default rather than an override.
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
  canvas.drawImageRect(
      image, Offset.zero & size, drawn, Paint()..filterQuality =
          FilterQuality.high);
}

/// _paintMissingPicture is the mark left where a picture has not arrived.
///
/// A frame with a corner cut off, at the size the picture would have been --
/// small, grey, and unmistakably not a photograph. It says "there is meant to
/// be something here", which a blank cell does not.
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
  var scale = math.min(
      box.width / vector.size.width, box.height / vector.size.height);
  var drawn = Size(vector.size.width * scale, vector.size.height * scale);

  canvas.save();
  canvas.translate(box.center.dx - drawn.width / 2,
      box.center.dy - drawn.height / 2);
  canvas.scale(scale);
  canvas.drawPicture(vector.picture);
  canvas.restore();
}

/// _bandedHere is whether every rule touching this cell was already drawn as
/// a band -- so the band is not drawn again, once per cell, with a border
/// between each.
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

  // Every column the rule names, taken together -- so a rule about columns
  // two to four is one band three columns wide rather than three bands.
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

/// _paintChips draws the boxes for every rule that names a word in this cell.
///
/// Each with its own style, and every occurrence of each: a form guide has a
/// rule per result, and a cell reading "D L W" wants three boxes in three
/// colours rather than one.
///
/// Off the words' own glyph boxes rather than a guess from the character
/// count, since a W and a full stop are not the same width -- see textRunBox.
void _paintChips(ui.Canvas canvas, TableElement e, int row, int col,
    TextSpec spec, Rect textBox, Rect cell, List<Rect>? slots) {
  var text = e.cell(row, col);
  var head = e.header;

  for (var rule in e.rules) {
    if (rule.banded || !rule.style.paintsBox) continue;
    if (!rule.matchesRow(row) || !rule.matchesColumn(col, head)) continue;

    for (var (from, to) in rule.runsIn(text)) {
      var box = !rule.style.hug
          ? cell
          // On a fixed pitch the box is the slots themselves, which is the
          // point of the pitch: the letters are already in line, so the boxes
          // round them are too.
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
/// pitch, and null when it did not.
///
/// A W is wider than an L, so however carefully the spacing is set the boxes
/// round a row of letters come out at different places -- lining them up by
/// eye is a job that cannot be finished. A slot each makes it arithmetic.
List<Rect>? _slotsIn(String text, TextSpec spec, Rect box, double width,
    double gap) {
  if (width <= 0 || text.isEmpty) return null;

  var pitch = width + gap;
  var total = text.length * width + (text.length - 1) * gap;
  var left = switch (spec.align) {
    TextAlignSpec.center => box.center.dx - total / 2,
    TextAlignSpec.right => box.right - total,
    _ => box.left,
  };

  return [
    for (var i = 0; i < text.length; i++)
      Rect.fromLTWH(left + pitch * i, box.top, width, box.height),
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

/// _paintSlots draws each character in the middle of its own slot.
void _paintSlots(
    ui.Canvas canvas, String text, TextSpec spec, List<Rect> slots) {
  var centred = spec.copyWith(
      align: TextAlignSpec.center, letterSpacing: 0);
  for (var i = 0; i < text.length && i < slots.length; i++) {
    if (text[i].trim().isEmpty) continue;
    paintTextInBox(canvas, text[i], centred, slots[i]);
  }
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
  // Padding round a chip, and an inset inside a band. The same number, and it
  // has to work both ways round: a box drawn round the letters and then
  // *shrunk* by three is a box smaller than the letters, which is a chip
  // nobody can see because the letters are sitting on top of it.
  var box = hug
      ? cell.inflate(style.inset.clamp(0.0, 200.0))
      : cell.inflate(-style.inset.clamp(-200.0, cell.shortestSide / 2));

  // A minimum, so a row of chips is a row of chips. Hugging the letters
  // exactly is right for one box and wrong for a set of them: a W is wider
  // than an L, so a form guide came out as three different sizes.
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

  // All four sides is a rounded rectangle; anything else is the lines that
  // were asked for. A rounded corner belongs to two sides at once, so there
  // is no honest way to round one when only one of them is drawn.
  if (style.allSides) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(box.deflate(style.borderWidth / 2),
            Radius.circular(style.radius)),
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

/// tableColumnWidths is where a table's columns actually fall.
///
/// Public because the stage has to put a grip on each divider, and a grip
/// that worked out the widths for itself would be a grip that drifted off the
/// line it is meant to be on the moment either calculation changed.
List<double> tableColumnWidths(TableElement e, Rect rect) =>
    _columnWidths(e, rect, e.columnCount);

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

/// tableRowHeights is where a table's rows fall, for the same reason
/// tableColumnWidths is public: the stage has to put an editor exactly over a
/// cell, and a second calculation would be a second answer.
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

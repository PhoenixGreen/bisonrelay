import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
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
  if (e.cards && cols > 1) {
    _paintCards(canvas, rect, e, cols, images);
    return;
  }

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
    if (rule.off || !rule.banded || !rule.style.paintsBox) continue;
    for (var box in _bandsFor(e, rule, rect, widths, heights, cols)) {
      _paintStyleBox(canvas, box, rule.style);
    }
  }

  // Cells.
  var drawn = _DrawnCells(e);
  y = rect.top;
  for (var r = 0; r < e.rows.length; r++) {
    var h = heights[r];
    var x = rect.left;
    // A heading across the table (TableElement.groupRows).
    if (drawn.groupRow(r)) {
      var band = Rect.fromLTWH(rect.left, y, rect.width, h);
      canvas.drawRect(
          band,
          Paint()
            ..color = e.headerFill.withValues(alpha: e.headerFill.a * 0.55));
      paintTextInBox(
          canvas,
          e.cell(r, 0),
          e.headerSpec.copyWith(align: TextAlignSpec.left, weight: 700),
          Rect.fromLTWH(
              rect.left + e.leftPad,
              y + e.topPad,
              math.max(1, rect.width - e.leftPad - e.rightPad),
              math.max(1, h - e.topPad - e.bottomPad)),
          clip: true);
      y += h;
      continue;
    }
    for (var c = 0; c < cols; c++) {
      var w = widths[c];
      var isHeader = (e.headerRow && r == 0) || (e.headerColumn && c == 0);
      var spec = isHeader ? e.headerSpec : e.cellSpec;
      // Drawn rather than written, by its column's kind.
      var kind = isHeader ? "" : (e.columnKinds[c] ?? "");
      if (kind == "merge") {
        if (drawn.continues(r, c)) {
          x += w;
          continue;
        }
        var run = drawn.runLength(r, c);
        var tall = heights.skip(r).take(run).fold(0.0, (a, b) => a + b);
        if (run > 1) {
          // Over the rows it spans, hiding their own fills.
          canvas.drawRect(
              Rect.fromLTWH(x, y, w, tall),
              Paint()
                ..color =
                    e.cellFill.a > 0 ? e.cellFill : const Color(0x00000000));
        }
        paintTextInBox(
            canvas,
            e.cell(r, c),
            spec.copyWith(verticalAlign: VerticalAlignSpec.middle),
            Rect.fromLTWH(
                x + e.leftPad,
                y + e.topPad,
                math.max(1, w - e.leftPad - e.rightPad),
                math.max(1, tall - e.topPad - e.bottomPad)),
            clip: true);
        x += w;
        continue;
      }
      // Shaded by its size among its column's numbers, then written over
      // in an ink that reads on the shade (a heatmap table).
      if (kind == "heat") {
        var v = _number(e.cell(r, c));
        var (lo, hi) = drawn.range(c);
        if (v != null && hi >= lo) {
          var f = hi - lo <= 0 ? 0.5 : (v - lo) / (hi - lo);
          var high =
              dataStyleNamed(e.style)?.palette.first ?? const Color(0xFF2667FF);
          var low = Color.lerp(
              e.cellFill.a > 0 ? e.cellFill : const Color(0xFFFFFFFF),
              high,
              0.07)!;
          var fill = Color.lerp(low, high, f.clamp(0.0, 1.0))!;
          canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = fill);
          spec = spec.copyWith(
              color: fill.computeLuminance() > 0.45
                  ? const Color(0xFF1B1B1B)
                  : const Color(0xFFFFFFFF));
        }
        kind = "";
      }
      if (kind.isNotEmpty) {
        var box = Rect.fromLTWH(
            x + e.leftPad,
            y + e.topPad,
            math.max(1, w - e.leftPad - e.rightPad),
            math.max(1, h - e.topPad - e.bottomPad));
        if (paintCellKind(canvas, kind, e.cell(r, c), spec, box, e)) {
          x += w;
          continue;
        }
      }

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
      // Its sheet's colour rules (Data element): a colour behind it, a bar
      // along it under the words.
      if (e.sheetLookAt(r, c) case var sl?) {
        var box = Rect.fromLTWH(x, y, w, h);
        if (sl.fill case var fill?) {
          canvas.drawRect(box, Paint()..color = fill.withValues(alpha: 0.85));
          // Light words on a light colour can't be read: dark ones there.
          if (fill.computeLuminance() > 0.45 &&
              spec.color.computeLuminance() > 0.45) {
            spec = spec.copyWith(color: const Color(0xFF1D2127));
          }
        }
        if (sl.bar case var bar? when bar > 0) {
          var inner = box.deflate(math.min(w, h) * 0.14);
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(
                      inner.left, inner.top, inner.width * bar, inner.height),
                  Radius.circular(inner.height * 0.2)),
              Paint()..color = sl.barColour.withValues(alpha: 0.55));
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

      // Kept back: a bar over each line where the words would be.
      if (style?.redact ?? false) {
        paintRedacted(canvas, e.cell(r, c), spec, textBox);
        x += w;
        continue;
      }

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

    // Each line in pieces where a merged cell runs on across it, or a
    // group heading spans the row.
    if (e.grid.drawsHorizontal) {
      var ry = rect.top;
      for (var r = 0; r < e.rows.length - 1; r++) {
        ry += heights[r];
        var rx = rect.left;
        for (var c = 0; c < cols; c++) {
          if (!drawn.continues(r + 1, c)) {
            canvas.drawLine(Offset(rx, ry), Offset(rx + widths[c], ry), paint);
          }
          rx += widths[c];
        }
      }
    }
    if (e.grid.drawsVertical) {
      var rx = rect.left;
      for (var c = 0; c < cols - 1; c++) {
        rx += widths[c];
        var ry = rect.top;
        for (var r = 0; r < e.rows.length; r++) {
          if (!drawn.groupRow(r)) {
            canvas.drawLine(Offset(rx, ry), Offset(rx, ry + heights[r]), paint);
          }
          ry += heights[r];
        }
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

/// tableCardLayout is where a table drawn as cards (TableElement.cards)
/// puts its columns: the table they are cut from, lowered to leave room
/// over it for the raised card and its ribbon ([inner]); each column's
/// place in it ([from]) and its card's ([to]). A column keeps its place
/// across -- the gaps come out of the cards' own widths, so a click finds
/// the same cell as in the table drawn plain. The first column, the rows'
/// names, has no card.
({Rect inner, List<Rect> from, List<Rect> to}) tableCardLayout(
    TableElement e, Rect rect, int cols, TableElement inner) {
  var gap = math.max(4.0, rect.width * 0.025);
  var top = tableCardRoom(e, rect, cols);
  var lift = e.picked > 0 && e.picked < cols ? top.lift : 0.0;
  var innerRect =
      Rect.fromLTRB(rect.left, rect.top + top.room, rect.right, rect.bottom);
  var widths = _columnWidths(inner, innerRect, cols);
  var from = <Rect>[], to = <Rect>[];
  var x = innerRect.left;
  for (var c = 0; c < cols; c++) {
    var r = Rect.fromLTWH(x, innerRect.top, widths[c], innerRect.height);
    from.add(r);
    to.add(c == 0
        ? r
        : Rect.fromLTRB(r.left + gap / 2, r.top - (c == e.picked ? lift : 0),
            r.right - (c < cols - 1 ? gap / 2 : 0), r.bottom));
    x += widths[c];
  }
  return (inner: innerRect, from: from, to: to);
}

/// tableCardRoom is how much a table drawn as cards leaves over itself:
/// the picked card's [lift] and half its ribbon. Nothing drawn plain.
({double room, double lift}) tableCardRoom(
    TableElement e, Rect rect, int cols) {
  if (!e.cards || cols < 2 || e.picked <= 0 || e.picked >= cols) {
    return (room: 0, lift: 0);
  }
  var lift = math.min(rect.height * 0.04, 10.0);
  var ribbonH = e.ribbon.trim().isNotEmpty ? e.headerSpec.fontSize * 1.5 : 0.0;
  return (room: lift + ribbonH / 2, lift: lift);
}

/// _paintCards draws [e] as cards: the table painted once a column, each
/// time cut to that column and moved to its card, with no lines down it;
/// then each card's edge, the picked one's in the style's accent and
/// raised, under its ribbon.
void _paintCards(ui.Canvas canvas, Rect rect, TableElement e, int cols,
    CanvasImageSource? images) {
  var inner = e.copyWith(
      cards: false,
      cornerRadius: 0,
      showOutline: false,
      grid: e.grid.drawsHorizontal ? TableGrid.horizontal : TableGrid.none);
  var at = tableCardLayout(e, rect, cols, inner);
  var round = Radius.circular(math.max(e.cornerRadius, 6));
  var accent = dataStyleNamed(e.style)?.accent ?? const Color(0xFFF2B33D);
  var edge = e.gridColor.a > 0
      ? e.gridColor
      : e.cellSpec.color.withValues(alpha: 0.25);
  for (var c = 0; c < cols; c++) {
    var card = at.to[c];
    var raised = card.top < at.from[c].top;
    canvas.save();
    if (c == 0) {
      canvas.clipRect(card);
    } else {
      canvas.clipRRect(RRect.fromRectAndRadius(card, round));
    }
    // Raised, its rows move up with it; the cells' fill behind covers the
    // room left at its foot.
    if (c > 0 && e.cellFill.a > 0) {
      canvas.drawRect(card, Paint()..color = e.cellFill);
    }
    canvas.translate(0, card.top - at.from[c].top);
    paintTable(canvas, at.inner, inner, images: images);
    canvas.restore();
    if (c == 0) continue;
    canvas.drawRRect(
        RRect.fromRectAndRadius(card.deflate(raised ? 1 : 0.5), round),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = raised ? 2 : 1
          ..color = raised ? accent : edge);
    if (raised && e.ribbon.trim().isNotEmpty) {
      var h = e.headerSpec.fontSize * 1.5;
      var words = e.ribbon.trim().toUpperCase();
      var size = e.headerSpec.fontSize * 0.7;
      var spec = e.headerSpec.copyWith(
          fontSize: size,
          weight: 800,
          letterSpacing: 0.8,
          align: TextAlignSpec.center,
          verticalAlign: VerticalAlignSpec.middle,
          color: accent.computeLuminance() > 0.45
              ? const Color(0xFF1B1B1B)
              : const Color(0xFFFFFFFF));
      // On one line: the band as wide as its words, up to the card's
      // width, and the words smaller where even that is too narrow.
      var w = layoutText(words, spec, maxWidth: double.infinity).width;
      var room = card.width - 4;
      if (w + h > room) {
        // Too narrow for any words (a gallery's thumbnail): the band alone.
        var fit = w <= 0 ? 0.0 : (room - h) / w;
        spec = spec.copyWith(fontSize: math.max(0.0, size * fit));
        w = math.max(0.0, room - h);
      }
      var band = Rect.fromCenter(
          center: Offset(card.center.dx, card.top), width: w + h, height: h);
      canvas.drawRRect(RRect.fromRectAndRadius(band, Radius.circular(h / 2)),
          Paint()..color = accent);
      if (spec.fontSize >= 4) {
        paintTextInBox(canvas, words, spec, band.inflate(2), clip: true);
      }
    }
  }
}

/// paintRedacted draws [text] laid out in [box] as [spec] would, but as a
/// solid bar over each line, in the text's colour: the words' own extent,
/// so a short answer gets a short bar and the alignment still shows.
/// paintCellPicture draws the picture [asset] fitted in [box] -- a vector
/// first, else the picture -- and says whether it had one to draw. For the
/// Data Studio's sheet, which shows a picture cell's badge rather than its
/// name.
bool paintCellPicture(
    ui.Canvas canvas, CanvasImageSource images, String asset, Rect box) {
  var vector = images.resolveVector(asset);
  if (vector != null) {
    _paintCellVector(canvas, vector, box);
    return true;
  }
  var image = images.resolve(asset, const BackgroundRemoval());
  if (image == null) return false;
  _paintCellImage(canvas, image, box);
  return true;
}

void paintRedacted(ui.Canvas canvas, String text, TextSpec spec, Rect box) {
  if (text.trim().isEmpty || box.width <= 0) return;
  // Shared with the paragraph cache: not this function's to dispose.
  var painter = layoutText(text, spec, maxWidth: box.width, fillWidth: true);
  var offset = textOffsetIn(box, painter, spec);
  var paint = Paint()..color = spec.color;
  canvas.save();
  canvas.clipRect(box);
  for (var line in painter.computeLineMetrics()) {
    if (line.width <= 0) continue;
    var height = line.ascent + line.descent;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(offset.dx + line.left,
                offset.dy + line.baseline - line.ascent, line.width, height),
            Radius.circular(height * 0.12)),
        paint);
  }
  canvas.restore();
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
List<Rect> _bandsFor(TableElement e, TableRule rule, Rect rect,
    List<double> widths, List<double> heights, int cols) {
  var head = e.header;

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
  if (fromX == null || toX == null) return const [];

  // A band for each run of rows it reaches: one for a block of rows, one
  // each for teams it follows that are apart.
  var out = <Rect>[];
  var top = rect.top;
  double? fromY;
  for (var r = 0; r <= heights.length; r++) {
    var reached = r < heights.length &&
        rule.matchesRow(r) &&
        (!rule.readsRows || rule.reachesRow(r, head, (c) => e.cell(r, c)));
    if (reached) {
      fromY ??= top;
    } else if (fromY != null) {
      out.add(Rect.fromLTRB(fromX, fromY, toX, top));
      fromY = null;
    }
    if (r < heights.length) top += heights[r];
  }
  return out;
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
List<double> tableRowHeights(TableElement e, Rect rect) {
  // Drawn as cards, the rows lie lower by the room over them, taken into
  // the first row so a click on it still finds it.
  var room = tableCardRoom(e, rect, e.columnCount).room;
  if (room <= 0) return _rowHeights(e, rect);
  var inner =
      Rect.fromLTRB(rect.left, rect.top + room, rect.right, rect.bottom);
  var h = _rowHeights(e, inner);
  return h.isEmpty ? h : [h.first + room, ...h.skip(1)];
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

/// _DrawnCells is what the cell kinds and group rows change about which
/// cells a table draws (TableElement.columnKinds, groupRows).
class _DrawnCells {
  final TableElement e;
  _DrawnCells(this.e);

  bool _header(int r) => e.headerRow && r == 0;

  /// groupRow is whether row [r] is a heading across the table: only its
  /// first cell filled.
  bool groupRow(int r) {
    if (!e.groupRows || _header(r) || r >= e.rows.length) return false;
    if (e.cell(r, 0).trim().isEmpty) return false;
    for (var c = 1; c < e.columnCount; c++) {
      if (e.cell(r, c).trim().isNotEmpty) return false;
    }
    return true;
  }

  /// continues is whether cell [r], [c] is part of a merged run begun
  /// above it: the same value as the cell above, in a "merge" column.
  bool continues(int r, int c) {
    if (e.columnKinds[c] != "merge" || r <= 0 || r >= e.rows.length) {
      return false;
    }
    if (_header(r - 1) || groupRow(r) || groupRow(r - 1)) return false;
    var v = e.cell(r, c).trim();
    return v.isNotEmpty && v == e.cell(r - 1, c).trim();
  }

  final Map<int, (double, double)> _ranges = {};

  /// range is the least and most of column [c]'s numbers, below the
  /// header.
  (double, double) range(int c) => _ranges.putIfAbsent(c, () {
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var r = e.headerRow ? 1 : 0; r < e.rows.length; r++) {
          if (groupRow(r)) continue;
          var v = _number(e.cell(r, c));
          if (v == null) continue;
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
        return (lo, hi);
      });

  /// runLength is how many rows the run begun at [r] spans.
  int runLength(int r, int c) {
    var n = 1;
    while (continues(r + n, c)) {
      n++;
    }
    return n;
  }
}

/// paintCellKind draws [text] as a column's kind says (see
/// TableElement.columnKinds) in [box], answering whether it did: a cell
/// that can't be read that way is written as words instead.
bool paintCellKind(ui.Canvas canvas, String kind, String text, TextSpec spec,
    Rect box, TableElement e) {
  var style = dataStyleNamed(e.style);
  var ink = spec.color;
  var accent = style?.accent ?? ink;
  var quiet = ink.withValues(alpha: ink.a * 0.32);
  var t = text.trim();
  switch (kind) {
    case "spark":
      var nums = [
        for (var part in t.split(RegExp(r"[,;\s]+")))
          if (double.tryParse(part.replaceAll(RegExp(r"[^0-9.\-]"), ""))
              case var v?)
            v
      ];
      if (nums.length < 2) return false;
      var lo = nums.reduce(math.min), hi = nums.reduce(math.max);
      var line = Rect.fromCenter(
          center: box.center,
          width: box.width,
          height: math.min(box.height, spec.fontSize * 1.6));
      var pts = [
        for (var i = 0; i < nums.length; i++)
          Offset(
              line.left + line.width * i / (nums.length - 1),
              line.bottom -
                  (hi - lo <= 0 ? 0.5 : (nums[i] - lo) / (hi - lo)) *
                      line.height)
      ];
      var path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, spec.fontSize * 0.09)
            ..strokeJoin = StrokeJoin.round
            ..color = ink.withValues(alpha: ink.a * 0.75));
      canvas.drawCircle(
          pts.last, math.max(2, spec.fontSize * 0.16), Paint()..color = accent);
      return true;
    case "ticks":
      if (t.isEmpty || t == "-" || t == "—") {
        paintTextInBox(canvas, "—",
            spec.copyWith(align: TextAlignSpec.center, color: quiet), box,
            clip: true);
        return true;
      }
      var yes = RegExp(r"^(y|yes|true|1|✓|✔|x|on|tick)$", caseSensitive: false)
          .hasMatch(t);
      var no = RegExp(r"^(n|no|false|0|✗|✘|off|cross)$", caseSensitive: false)
          .hasMatch(t);
      if (!yes && !no) return false;
      var s = math.min(box.height, spec.fontSize * 1.1) * 0.5;
      var c = box.center;
      var paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, s * 0.28)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = yes ? accent : quiet;
      canvas.drawPath(
          yes
              ? (Path()
                ..moveTo(c.dx - s * 0.8, c.dy)
                ..lineTo(c.dx - s * 0.2, c.dy + s * 0.6)
                ..lineTo(c.dx + s * 0.9, c.dy - s * 0.7))
              : (Path()
                ..moveTo(c.dx - s * 0.6, c.dy - s * 0.6)
                ..lineTo(c.dx + s * 0.6, c.dy + s * 0.6)
                ..moveTo(c.dx + s * 0.6, c.dy - s * 0.6)
                ..lineTo(c.dx - s * 0.6, c.dy + s * 0.6)),
          paint);
      return true;
    case "harvey":
      var v = double.tryParse(t.replaceAll("%", ""));
      if (v == null) return false;
      // A share: whole steps out of 4 (a Harvey ball's), a fraction of 1,
      // or a percentage.
      var f = t.contains("%") || v > 4
          ? v / 100
          : v == v.roundToDouble()
              ? v / 4
              : v;
      f = f.clamp(0.0, 1.0);
      var r = math.min(box.height, spec.fontSize * 1.2) * 0.5;
      var c = box.center;
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, r * 0.14)
            ..color = ink);
      if (f > 0) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
            math.pi * 2 * f, true, Paint()..color = ink);
      }
      return true;
    case "change":
      var v = double.tryParse(t.replaceAll(RegExp(r"[^0-9.\-+]"), ""));
      if (v == null) return false;
      var up = v > 0, down = v < 0;
      var colour = up
          ? (style?.rise ?? const Color(0xFF2EA44F))
          : down
              ? (style?.fall ?? const Color(0xFFE5534B))
              : quiet;
      var size = v.abs();
      var said = size == size.roundToDouble()
          ? size.toStringAsFixed(0)
          : size.toString();
      paintTextInBox(
          canvas,
          up
              ? "▲ $said"
              : down
                  ? "▼ $said"
                  : "–",
          spec.copyWith(color: colour, weight: 700),
          box,
          clip: true);
      return true;
  }
  return false;
}

/// _number is the number [text] says ("£1,200", "45%", "−3"), or null.
double? _number(String text) {
  var t = text.trim().replaceAll("−", "-").replaceAll(RegExp(r"[^0-9.\-]"), "");
  return t.isEmpty ? null : double.tryParse(t);
}

part of 'paint_util.dart';

// Flowing one paragraph across columns: where its lines break between them,
// drawing each column, and the rules in the gutters. Part of paint_util.dart.

/// lineEdges is where each line of a laid-out paragraph gives way to the
/// next, plus the top of the first and bottom of the last. Not the line box
/// boundaries: with tight line height a descender hangs into the next box,
/// and a column cut there starts with a sliver of the line before. So the
/// edge is the later of the boundary and the bottom of the ink above.
List<double> lineEdges(List<ui.LineMetrics> metrics) {
  var edges = <double>[0];
  var at = 0.0;
  for (var (i, line) in metrics.indexed) {
    at += line.height;

    // Half a pixel past the ink, so an antialiased descender row is not
    // left along the top of the next column.
    var edge = math.max(at, line.baseline + line.descent) + 0.5;

    // But never into the capitals below (about 0.78 of the ascent): when
    // lines overlap, a descender loses a sliver rather than the capitals.
    if (i + 1 < metrics.length) {
      var below = metrics[i + 1];
      edge = math.min(edge, below.baseline - below.ascent * 0.78);
    }
    edges.add(math.max(edge, edges.last));
  }
  return edges;
}

/// columnRuns is which lines of a laid-out paragraph go in which column, as
/// (first, end) ranges: whole lines, from the line metrics; a line that
/// does not fit goes to the next column. [noBlankStart] drops a blank line
/// that would begin a later column, such as the gap between paragraphs.
List<(int, int)> columnRuns(
    List<ui.LineMetrics> metrics, double height, int columns,
    {bool noBlankStart = false}) {
  if (metrics.isEmpty || columns <= 0) return const [];

  bool blank(int line) => metrics[line].width <= 0.5;

  // top is where a line starts, from the paragraph's top. See lineEdges.
  var tops = lineEdges(metrics);
  double top(int line) => tops[line.clamp(0, tops.length - 1)];

  var runs = <(int, int)>[];
  var at = 0;
  for (var c = 0; c < columns && at < metrics.length; c++) {
    if (noBlankStart && c > 0) {
      while (at < metrics.length - 1 && blank(at)) {
        at++;
      }
    }
    var end = at;
    // At least one line per column even where it does not fit, or a box
    // shorter than a line would draw nothing.
    while (end < metrics.length &&
        (end == at || top(end + 1) - top(at) <= height + 0.5)) {
      end++;
    }
    runs.add((at, end));
    at = end;
  }
  return runs;
}

/// paintTextInColumns flows one paragraph across [columns] columns of [box]:
/// laid out once at a column's width, then drawn per column, clipped and
/// shifted up by the lines already used (columnRuns). The arrival's pieces are
/// worked out for the whole paragraph, so a stagger runs on across columns.
void paintTextInColumns(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box,
  TextColumns columns, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  required List<TextPart> parts,
  List<PartTiming> timings = const [],
  bool asOne = false,
  CanvasImageSource? images,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return;

  var width = columns.columnWidth(box.width);
  if (width <= 0) return;

  var words = layOutWords(text, spec,
      parts: parts,
      maxWidth: width,
      scale: scale,
      fillWidth: true,
      // The whole box, not a column: the shader is where the canvas is, so
      // the columns together show one fade.
      over: box);
  var metrics = words.lines;
  if (metrics.isEmpty) return;

  var runs = columnRuns(metrics, box.height, columns.count,
      noBlankStart: columns.noBlankStart);

  var outline = outlineFor(text, spec,
      maxWidth: width,
      scale: scale,
      parts: parts,
      animation: animation,
      reveal: reveal);

  var soft = softFor(text, spec, maxWidth: width, scale: scale, parts: parts);

  var tops = lineEdges(metrics);
  double top(int line) => tops[line.clamp(0, tops.length - 1)];

  // A whole-paragraph arrival is applied once, around every column, so the
  // per-column clips travel with the motion.
  var moving =
      animation != null && animation.on && (reveal < 1 || animation.keeps);
  var asBlock = moving && movesAsOneBlock(animation);
  var depth = 0;
  if (asBlock) {
    var carried = applyMotionSpec(
        canvas, box, animation.spec, animation.progressAt(reveal, 0, 1),
        from: animation.spec.from);
    depth = carried.depth;
    if (carried.alpha <= 0) {
      for (var r = 0; r < depth; r++) {
        canvas.restore();
      }
      return;
    }
    if (carried.alpha < 1) {
      canvas.saveLayer(box.inflate(box.height),
          Paint()..color = Color.fromRGBO(0, 0, 0, carried.alpha));
      depth++;
    }
  }

  for (var i = 0; i < runs.length; i++) {
    var (from, to) = runs[i];
    var left = box.left + i * (width + columns.gap);

    // The lines this column holds, which is what it is clipped to.
    var used = top(to) - top(from);
    var dy = switch (spec.verticalAlign) {
      VerticalAlignSpec.top => 0.0,
      VerticalAlignSpec.middle => (box.height - used) / 2,
      VerticalAlignSpec.bottom => box.height - used,
    };

    canvas.save();
    // Room at the ends for highlights (marksRoom), at most half the gutter;
    // none above or below, which keep the column to its own lines.
    var room = marksRoom(parts);
    var ends = math.min(columns.gap / 2, math.max(room.left, room.right));
    canvas.clipRect(
        Rect.fromLTWH(left - ends, box.top + dy, width + ends * 2, used));
    var at = Offset(left, box.top + dy - top(from));

    // Marks for the whole paragraph; the clip keeps each column to its own.
    var marksMove = animation != null && animation.on && reveal < 1;
    paintPartMarks(canvas, words, parts, spec, at,
        behind: true,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);

    // drawn draws this column's share, a closure as in paintWordsInBox.
    void drawn({TextDrawPhase phase = TextDrawPhase.all}) {
      // A block motion is applied outside; parts arriving alone animate here.
      var animating = (!asBlock && moving) || (!asOne && partsAnimate(parts));
      if (animating) {
        // Only the pieces whose lines fall in this column; their places in
        // the whole paragraph set their progress.
        paintAnimatedText(
            canvas, words, spec, at, animation ?? const TextAnimation(), reveal,
            maxWidth: width,
            outline: outline,
            soft: soft,
            timings: timings,
            asOne: asOne,
            phase: phase, keep: (piece) {
          // A block-scoped piece covers the paragraph, which every column
          // shares: it moves or uncovers the same way in each.
          if (piece.box.height >= words.height - 0.5) return true;
          var middle = piece.box.center.dy;
          return middle >= top(from) - 0.5 && middle < top(to) + 0.5;
        });
        return;
      }
      if (phase.drawsOutline) soft?.paint(canvas, at);
      if (phase.drawsOutline) outline?.paint(canvas, at);
      if (phase.drawsLetters) words.paintAsWords(canvas, at);
    }

    var column = Rect.fromLTWH(left, box.top + dy, width, used);
    if (!spec.fill.on) {
      drawn();
    } else {
      drawn(phase: TextDrawPhase.behind);
      paintThroughText(canvas, column, spec.fill, images,
          () => drawn(phase: TextDrawPhase.letters),
          // Under a block motion (applied outside) the words here are
          // still, so the fill has nothing to follow.
          animation: asBlock ? null : animation,
          reveal: reveal,
          moving: at & words.size);
    }

    paintPartMarks(canvas, words, parts, spec, at,
        behind: false,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);
    canvas.restore();
  }

  // Rules run down the text (the tallest column), not the whole box.
  var tallest = 0.0;
  for (var (from, to) in runs) {
    tallest = math.max(tallest, top(to) - top(from));
  }
  // Starting where that column's text starts under the vertical alignment.
  var above = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.middle => (box.height - tallest) / 2,
    VerticalAlignSpec.bottom => box.height - tallest,
  };
  _paintColumnRules(canvas, box, columns, width, above, tallest);

  // Restored only after the rules, so they arrive with the columns.
  for (var r = 0; r < depth; r++) {
    canvas.restore();
  }
}

/// _paintColumnRules draws the line down the middle of each gutter, from
/// [above] for [textHeight], how far the text reaches.
void _paintColumnRules(ui.Canvas canvas, Rect box, TextColumns columns,
    double width, double above, double textHeight) {
  if (columns.ruleStyle == ColumnRuleStyle.none ||
      columns.ruleWidth <= 0 ||
      columns.gap <= 0) {
    return;
  }

  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = columns.ruleWidth
    ..strokeCap = columns.ruleStyle == ColumnRuleStyle.dotted
        ? StrokeCap.round
        : StrokeCap.butt
    ..color = columns.ruleColor;

  // A little past the last line, which otherwise reads as too short.
  var from = box.top + (textHeight <= 0 ? 0 : above.clamp(0, box.height));
  var reach = textHeight <= 0
      ? box.height
      : math.min(box.bottom - from, textHeight * 1.02 + columns.ruleWidth * 2);

  for (var i = 1; i < columns.count; i++) {
    var x = box.left + i * (width + columns.gap) - columns.gap / 2;
    var line = ui.Path()
      ..moveTo(x, from)
      ..lineTo(x, from + reach);
    canvas.drawPath(
      switch (columns.ruleStyle) {
        ColumnRuleStyle.dashed =>
          _dashPath(line, columns.ruleWidth * 4, columns.ruleWidth * 3),
        // Near-zero dashes with a round cap are dots.
        ColumnRuleStyle.dotted => _dashPath(line, 0.01, columns.ruleWidth * 3),
        _ => line,
      },
      paint,
    );
  }
}

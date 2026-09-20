import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:flutter/foundation.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_cartesian.dart draws every chart type that has an x and a y axis:
// bars, grouped and stacked bars, horizontal bars, lines, areas and scatter.
//
// The part worth reading twice is the value axis. Its range is chosen to end
// on round numbers -- see _niceRange -- because an axis running to 8.3714 is
// not readable at any size, and a chart on a canvas is going to be looked at
// rather than hovered over.
//
// Everything else here is measurement: the plot rectangle is what is left
// once the axis titles, the tick labels and the category names have taken the
// room they actually need, never a guessed margin, so a chart with long
// category names and a chart with none both use the space they have.

/// _ValueRange is the axis and its ticks, worked out together.
class _ValueRange {
  final double min;
  final double max;
  final List<double> ticks;

  /// log is whether the axis is spaced by decades. See [_logRange].
  final bool log;

  const _ValueRange(this.min, this.max, this.ticks, {this.log = false});

  double get span => max - min == 0 ? 1 : max - min;

  /// fraction is where [v] sits along the axis, 0 at the bottom.
  ///
  /// Zero and everything below it sits *at* the bottom of a log axis rather
  /// than off it: there is no such place, and the alternative is an infinity
  /// travelling into a rectangle and taking the frame with it. Nothing on a
  /// log chart is ever zero -- see ChartElement.logs, which is what refuses
  /// the whole scale when something is -- but a bar's base is asked for as
  /// fraction(0) whatever the data holds.
  double fraction(double v) {
    if (!log) return (v - min) / span;
    if (v <= 0 || min <= 0 || max <= min) return 0;
    return (math.log(v) - math.log(min)) / (math.log(max) - math.log(min));
  }
}

/// _stepFor is the roundest step that rules [lo]..[hi] into about [want]
/// lines.
///
/// Searched rather than worked out, because the two requirements pull against
/// each other: the lines have to land on numbers somebody can read, and there
/// has to be about the number of them that was asked for. Rounding the step
/// to the nearest 1, 2, 2.5 or 5 answers the first and ignores the second --
/// half the numbers anybody types give back the answer they already had. This
/// tries every round step near the right size and keeps whichever comes
/// closest to the count, preferring the larger where two are equally close:
/// given a choice, fewer and rounder.
double _stepFor(double lo, double hi, int want) {
  var span = hi - lo;
  if (span <= 0 || !span.isFinite) return 1;
  var lines = want.clamp(2, 40);
  var mag =
      math.pow(10, (math.log(span / lines) / math.ln10).floor()).toDouble();

  // More multiples than the walk allows, because 3, 4 and 6 are perfectly
  // readable steps -- 0, 30, 60, 90 is an axis anybody can read -- and
  // without them there is nothing between 2.5 and 5.
  const nice = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0];
  double? best;
  var bestScore = double.infinity;
  for (var scale in [mag / 10, mag, mag * 10]) {
    for (var m in nice) {
      var step = m * scale;
      if (step <= 0 || !step.isFinite) continue;
      var min = (lo / step).floor() * step;
      var max = (hi / step).ceil() * step;
      var count = ((max - min) / step).round() + 1;
      if (count < 2 || count > 200) continue;
      // Nearest to what was asked, *and* fitting the numbers. A big step can
      // always hit a small count by running the axis far past the data --
      // two lines over a range of a hundred by ruling it to a thousand --
      // which answers the question asked and ruins the chart. The room it
      // wastes counts against it heavily enough that an axis which fits
      // beats one that is nearer the number.
      var waste = (max - min) / span - 1;
      var score = (count - lines).abs() + math.max(0.0, waste) * 6;
      // A tie goes to the finer step: asked for more lines than the round
      // numbers can give exactly, somebody would rather have one too many
      // than one too few.
      if (score < bestScore ||
          (score == bestScore && step < (best ?? double.infinity))) {
        best = step;
        bestScore = score;
      }
    }
  }
  return best ?? span / lines;
}

/// _logRange picks an axis by decades: 1, 10, 100, 1000.
///
/// The ends are pushed out to whole powers of ten, which is what makes the
/// labels readable and the gridlines mean something -- each line is ten times
/// the one below it. Within a single decade that would be one gridline, so a
/// narrow range is ruled at 1, 2 and 5 of each instead.
_ValueRange _logRange(double lo, double hi, {int want = 0}) {
  if (!lo.isFinite || !hi.isFinite || lo <= 0 || hi <= 0) {
    return _niceRange(lo, hi);
  }
  var low = math.pow(10, (math.log(lo) / math.ln10).floor()).toDouble();
  var high = math.pow(10, (math.log(hi) / math.ln10).ceil()).toDouble();
  if (high <= low) high = low * 10;

  var decades = (math.log(high / low) / math.ln10).round();
  var ticks = <double>[];
  // Every decade below four of them; every second, then every fifth, above
  // that, so a chart spanning eight decades is not a solid band of writing.
  // Asked for a number of divisions, every so many decades is the closest a
  // log axis can come to it: the lines are powers of ten and there is nothing
  // between them to move. Nought is the chart's own judgement.
  var every = want > 0
      ? math.max(1, (decades / math.max(1, want)).round())
      : (decades <= 6 ? 1 : (decades <= 12 ? 2 : 5));
  for (var i = 0; i <= decades; i++) {
    if (i % every != 0 && i != decades) continue;
    var at = low * math.pow(10, i);
    if (decades <= 2) {
      // Room for the intermediate lines, and a single decade needs them or
      // the chart has a gridline at each end and nothing between.
      for (var m in const [1, 2, 5]) {
        var v = at * m;
        if (v <= high) ticks.add(v.toDouble());
      }
    } else {
      ticks.add(at.toDouble());
    }
  }
  if (!ticks.contains(high)) ticks.add(high);
  return _ValueRange(low, high, ticks, log: true);
}

/// axisTicksForTest is the value axis a chart would be ruled with: the
/// numbers the gridlines are drawn at.
///
/// A seam, like legendEntriesForTest. What is being asked is arithmetic --
/// how many lines, and at what round numbers -- and reading it off a picture
/// would be counting rows of pixels to check a division.
@visibleForTesting
List<double> axisTicksForTest(double lo, double hi,
        {int want = 0, bool log = false, bool fromZero = true}) =>
    (log
            ? _logRange(lo, hi, want: want)
            : _niceRange(lo, hi, fromZero: fromZero, want: want))
        .ticks;

/// _niceRange picks an axis that ends on round numbers.
///
/// The standard "nice numbers" walk: take the rough step the data implies,
/// round it up to the next 1, 2, 2.5 or 5 times a power of ten, then push the
/// ends of the axis out to multiples of it. The alternative -- running the
/// axis from the smallest value to the largest -- gives labels like 3.7, 5.4,
/// 7.1, which nobody can read a value off.
///
/// [fromZero] is what a bar chart needs and a candlestick chart must not
/// have: a bar is read as a length and one drawn from 12 to 16 on an axis
/// starting at 12 says four times what it means, while a price forced down to
/// zero is a flat line along the top with the whole month in a tenth of the
/// plot.
_ValueRange _niceRange(double lo, double hi,
    {int target = 5, int want = 0, bool fromZero = true}) {
  if (!lo.isFinite || !hi.isFinite || lo == hi) {
    var base = lo.isFinite ? lo : 0.0;
    lo = fromZero ? math.min(0, base) : base * 0.9;
    hi = base == 0 ? 1 : base * 1.2;
  }
  if (fromZero) {
    if (lo > 0) lo = 0; // Bars must start from zero or they lie about ratios.
    if (hi < 0) hi = 0;
  } else if (hi > lo) {
    // A tenth of the range as air above and below, so the highest wick is not
    // drawn along the top edge of the plot.
    var air = (hi - lo) * 0.1;
    lo -= air;
    hi += air;
  }

  var rough = (hi - lo) / target;
  var mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  var norm = rough / mag;
  var step = (norm <= 1
          ? 1
          : norm <= 2
              ? 2
              : norm <= 2.5
                  ? 2.5
                  : norm <= 5
                      ? 5
                      : 10) *
      mag;

  // Asked for a particular number of lines, the walk above is too coarse to
  // answer with: it rounds the step to 1, 2, 2.5 or 5 times a power of ten,
  // and over 0 to 100 that means five lines, six, seven, eight and nine all
  // come out as the same six. Asked, it searches instead -- see _stepFor.
  if (want > 0) step = _stepFor(lo, hi, want);

  var min = (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  var ticks = <double>[];
  for (var v = min; v <= max + step * 0.001; v += step) {
    ticks.add(v.abs() < step * 1e-9 ? 0 : v);
  }
  return _ValueRange(min, max, ticks);
}

/// paintCartesian draws every type that has an x and a y axis.
void paintCartesian(
    ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var data = e.data;
  var horizontal = e.type == ChartType.horizontalBar;

  // The range covers every series, or their running totals when stacked.
  //
  // Starting at zero for the types that are read as lengths, and starting
  // nowhere for the one that is read as a position: seeded with zero, the
  // smallest price on a candlestick chart could never be above it, and a
  // month of trading between 12 and 16 was drawn as a smudge along the top of
  // an axis that began at nothing.
  //
  // A log axis takes its bottom from the data too, whatever the type: there
  // is no zero on one to start from.
  var fromZero = e.type.startsAtZero && !e.logs;
  var lo = fromZero ? 0.0 : double.infinity;
  var hi = fromZero ? 0.0 : double.negativeInfinity;
  if (e.type.isStacked) {
    for (var i = 0; i < data.categories.length; i++) {
      var pos = 0.0, neg = 0.0;
      for (var s = 0; s < data.series.length; s++) {
        if (data.series[s].hidden) continue;
        var v = data.valueAt(s, i);
        // A gap adds nothing to the pile it is missing from.
        if (v.isNaN) continue;
        v >= 0 ? pos += v : neg += v;
      }
      hi = math.max(hi, pos);
      lo = math.min(lo, neg);
    }
  } else {
    for (var s in data.series) {
      // A series nobody is looking at does not get to decide how tall the
      // axis is. That is the point of switching one off: isolating a pot
      // worth two hundred thousand against a stream worth five hundred should
      // actually show the pot.
      if (s.hidden) continue;
      for (var v in s.values) {
        // A log axis takes its bottom from the smallest number it can
        // describe. Seeded with a zero -- which a row nobody has filled in
        // yet puts in every series -- the range falls back to a linear one
        // and the scale quietly stops being a log scale. The zeros are still
        // drawn; they sit on the floor. See _ValueRange.fraction.
        if (e.logs && v <= 0) continue;
        // A cell nobody filled in is not a number the axis has to reach.
        if (v.isNaN) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
  }
  if (!e.yMin.isNaN) lo = e.yMin;
  if (!e.yMax.isNaN) hi = e.yMax;
  var range = e.logs
      ? _logRange(lo, hi, want: e.axisSteps)
      : _niceRange(lo, hi, fromZero: fromZero, want: e.axisSteps);
  if (!e.yMin.isNaN || !e.yMax.isNaN) {
    range = _ValueRange(e.yMin.isNaN ? range.min : e.yMin,
        e.yMax.isNaN ? range.max : e.yMax, range.ticks,
        log: range.log);
  }

  // Which axis carries what depends on which way the chart is drawn: on
  // horizontal bars the categories run up the side and the values along the
  // bottom. The switches and the type are the axis', not the writing's, so
  // "the X labels" means whatever is written along the bottom either way.
  var sideSpec = e.yLabels, bottomSpec = e.xLabels;
  var sideOn = e.showYLabels, bottomOn = e.showXLabels;

  // Reserve room by measuring, not by guessing: the value labels are as wide
  // as the widest of them and no wider.
  var valueGutter = 0.0;
  var valueSide = horizontal ? bottomOn : sideOn;
  var valueSpec = horizontal ? bottomSpec : sideSpec;
  if (valueSide && !horizontal) {
    for (var t in range.ticks) {
      var p = layoutText(formatAxis(e, t), valueSpec, maxWidth: area.width / 3);
      valueGutter = math.max(valueGutter, p.width);
    }
    valueGutter += valueSpec.fontSize * 0.5;
  }

  // No writing, no gutters. Switching one axis' labels off and keeping the
  // room they took would be a chart with a margin of nothing down that side.
  var categoryGutter = bottomOn ? bottomSpec.fontSize * 1.6 : 0.0;
  // The axis titles have their own type and their own distance from the plot:
  // one and a half times their height to sit against it, plus whatever room
  // has been asked for to push them out. A title an inch clear of the plot is
  // a layout decision and the chart cannot make it -- how much air a design
  // wants is not a thing a drawing routine knows.
  var axisSpec = e.axisText;
  var axisTitleGutter = axisSpec.fontSize * 1.5 + math.max(0, e.axisGap);

  // No writing, no gutter. Room kept for labels that are switched off is a
  // margin of nothing down one side, which looks like a chart that has been
  // pushed off centre.
  var left = area.left +
      (horizontal
          ? (sideOn ? _widestCategory(data.categories, sideSpec, area) : 0.0)
          : valueGutter) +
      (e.showsYTitle ? axisTitleGutter : 0);
  // The title's own switch, not whether anybody has typed one. A chart with a
  // name for its x axis and the titles switched off kept the room the title
  // would have taken, which is a strip of nothing along the bottom -- and the
  // strip is what made the element's box sit away from the chart in it.
  var bottom =
      area.bottom - categoryGutter - (e.showsXTitle ? axisTitleGutter : 0);

  // The air over the top tick and past the last category, so neither is cut
  // in half by the edge. Only where there are labels to cut: with them off it
  // is a margin around nothing, and the box the chart is aligned and snapped
  // by is the box it is drawn in.
  // The air over the top tick belongs to the axis the ticks are written on,
  // and the air past the last category to the one the categories are on.
  var topAir = sideOn ? sideSpec.fontSize : 0.0;
  var rightAir = bottomOn ? bottomSpec.fontSize : 0.0;
  var plot = Rect.fromLTRB(
      left, area.top + topAir * 0.6, area.right - rightAir * 0.5, bottom);
  if (plot.width <= 4 || plot.height <= 4) return;

  _grid(canvas, plot, range, e, horizontal);
  if (e.showAxisLabels) {
    _axisLabels(canvas, area, plot, range, e, horizontal, valueGutter,
        categoryGutter, axisTitleGutter);
  }

  // Split by how each series is drawn rather than by what the chart is, so a
  // set of bars can have a line over it. A series with no type of its own is
  // drawn as the chart is, which is every series until somebody says
  // otherwise.
  var bars = <int>[];
  var lines = <int>[];
  var plainBarTaken = false;
  for (var i = 0; i < data.series.length; i++) {
    var series = data.series[i];
    // Switched off from the key. It keeps its place in the table and its
    // entry in the key -- there has to be something to press to bring it
    // back -- and is simply not among the things drawn.
    if (series.hidden) continue;
    var kind = series.typeIn(e.type);
    if (kind.isBar) {
      // "Bars" means one bar per category, so a chart set to it draws its
      // first series and no more -- that is the whole difference between it
      // and "Grouped bars", and letting it quietly group as well would make
      // choosing between them do nothing.
      //
      // A series with a type of its own is exempt. Asking for bars over a
      // line chart is asking for those bars specifically, not for the chart's
      // idea of how many series it draws.
      if (e.type == ChartType.bar && series.type == null) {
        if (plainBarTaken) continue;
        plainBarTaken = true;
      }
      bars.add(i);
    } else if (kind.isLinear) {
      lines.add(i);
    }
  }

  // Bars first. A line drawn under a bar is a line nobody can see, and the
  // reason for putting the two on one pair of axes is to read the line
  // against the bars.
  if (bars.isNotEmpty) {
    _bars(canvas, plot, range, e, horizontal, bars, reveal);
  }
  // Candles under the lines for the same reason bars are: the point of
  // putting a moving average over a price chart is to read the line against
  // the candles.
  if (e.type.isCandles) _candles(canvas, plot, range, e, reveal);
  if (lines.isNotEmpty) _lines(canvas, plot, range, e, lines, reveal);
}

double _widestCategory(List<String> categories, TextSpec spec, Rect area) {
  var w = 0.0;
  for (var c in categories) {
    w = math.max(w, layoutText(c, spec, maxWidth: area.width / 3).width);
  }
  return w + spec.fontSize * 0.5;
}

/// _grid is the ruled matrix behind the plot, plus the two axis lines.
void _grid(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal) {
  if (e.showGrid) {
    var paint = Paint()
      ..color = e.gridColor
      ..strokeWidth = 1;
    for (var t in range.ticks) {
      var f = range.fraction(t);
      if (horizontal) {
        var x = plot.left + plot.width * f;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
      } else {
        var y = plot.bottom - plot.height * f;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      }
    }
  }
  if (e.showAxes) {
    var paint = Paint()
      ..color = e.axisColor
      ..strokeWidth = math.max(1, e.strokeWidth * 0.4);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, paint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, paint);
  }
}

/// _axisLabels writes the tick values, the category names and the two axis
/// titles.
void _axisLabels(
  ui.Canvas canvas,
  Rect area,
  Rect plot,
  _ValueRange range,
  ChartElement e,
  bool horizontal,
  double valueGutter,
  double categoryGutter,
  double axisTitleGutter,
) {
  // The ticks are written on whichever axis carries the values, and the
  // category names on the other one, each in that axis' own type.
  var tickSpec = horizontal ? e.xLabels : e.yLabels;
  var nameSpec = horizontal ? e.yLabels : e.xLabels;
  var showTicks = horizontal ? e.showXLabels : e.showYLabels;
  var showNames = horizontal ? e.showYLabels : e.showXLabels;
  var categories = e.data.categories;

  var spec = tickSpec;
  for (var t in showTicks ? range.ticks : const <double>[]) {
    var f = range.fraction(t);
    var text = formatAxis(e, t);
    if (horizontal) {
      var x = plot.left + plot.width * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x - spec.fontSize * 2,
              plot.bottom + spec.fontSize * 0.3,
              spec.fontSize * 4,
              categoryGutter));
    } else {
      var y = plot.bottom - plot.height * f;
      paintTextInBox(
          canvas,
          text,
          spec.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTWH(plot.left - valueGutter, y - spec.fontSize,
              valueGutter - spec.fontSize * 0.4, spec.fontSize * 2));
    }
  }

  spec = nameSpec;
  var slots = showNames ? categories.length : 0;
  for (var i = 0; i < slots; i++) {
    if (horizontal) {
      var slot = plot.height / slots;
      var y = plot.top + slot * i;
      paintTextInBox(
          canvas,
          categories[i],
          spec.copyWith(
              align: TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          Rect.fromLTWH(
              area.left, y, plot.left - area.left - spec.fontSize * 0.4, slot),
          clip: true);
    } else {
      var slot = plot.width / slots;
      var x = plot.left + slot * i;
      paintTextInBox(
          canvas,
          categories[i],
          spec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.top),
          Rect.fromLTWH(
              x, plot.bottom + spec.fontSize * 0.35, slot, categoryGutter),
          clip: true);
    }
  }

  // The titles are set in their own type -- see ChartElement.axisSpec -- so
  // making the writing on the axes smaller does not shrink the words naming
  // them with it.
  var titleSpec = e.axisText;
  if (e.showsXTitle) {
    paintTextInBox(
        canvas,
        e.xAxisLabel,
        titleSpec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.bottom,
            weight: 600),
        Rect.fromLTRB(
            plot.left, area.bottom - axisTitleGutter, plot.right, area.bottom));
  }
  if (e.showsYTitle) {
    // Turned on its side against the axis, which is where a value-axis title
    // belongs and the only way it fits without eating a third of the plot.
    canvas.save();
    canvas.translate(area.left + axisTitleGutter * 0.5, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    paintTextInBox(
        canvas,
        e.yAxisLabel,
        titleSpec.copyWith(
            align: TextAlignSpec.center,
            verticalAlign: VerticalAlignSpec.middle,
            weight: 600),
        Rect.fromCenter(
            center: Offset.zero, width: plot.height, height: axisTitleGutter));
    canvas.restore();
  }
}

/// _candles draws the open, high, low and close of each period as one mark.
///
/// A thin wick from the low to the high with a body between the open and the
/// close over it, coloured by whether the period closed up or down. The four
/// numbers come from four series -- see ChartData.ohlcAt -- so a candlestick
/// chart is fed exactly like every other type: four columns mapped, or four
/// columns pasted.
///
/// A period that opened and closed at the same price has a body of no height,
/// which is drawn as a line rather than as nothing: it is a real reading, and
/// on a quiet day it is most of them.
void _candles(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    double reveal) {
  var slots = e.data.categories.length;
  if (slots == 0 || e.data.series.length < 4) return;

  var slotSize = plot.width / slots;
  var bodyWidth = math.max(1.0, slotSize * (1 - e.barGap.clamp(0.0, 0.9)));
  // The wick is a fraction of the body rather than a fixed width, so a chart
  // of two hundred candles does not become a solid block of wicks.
  var wickWidth = math.max(1.0, math.min(bodyWidth * 0.18, e.strokeWidth));

  double y(double v) => plot.bottom - plot.height * range.fraction(v);

  for (var i = 0; i < slots; i++) {
    var ohlc = e.data.ohlcAt(i);
    if (ohlc == null) continue;

    var centre = plot.left + slotSize * (i + 0.5);
    var colour = ohlc.rose ? e.riseColor : e.fallColor;

    var arrived = 1.0;
    if (e.animation.on && reveal < 1) {
      var p = e.animation.progressAt(reveal, i, slots);
      if (p <= 0) continue;
      switch (e.animation.preset) {
        case ChartAnimationPreset.fadeIn:
          colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
        case ChartAnimationPreset.drawOn:
          // About its own middle. A candle growing out of the axis would
          // travel through prices the period never traded at.
          arrived = p.clamp(0.0, 1.0);
        case ChartAnimationPreset.none:
        case ChartAnimationPreset.wipe:
        case ChartAnimationPreset.sweep:
          break;
      }
    }

    var paint = Paint()..color = colour;
    var top = y(ohlc.top);
    var bottom = y(ohlc.bottom);
    var middle = (top + bottom) / 2;

    var wickTop = y(ohlc.high);
    var wickBottom = y(ohlc.low);
    if (arrived < 1) {
      var wickMiddle = (wickTop + wickBottom) / 2;
      wickTop = wickMiddle + (wickTop - wickMiddle) * arrived;
      wickBottom = wickMiddle + (wickBottom - wickMiddle) * arrived;
      top = middle + (top - middle) * arrived;
      bottom = middle + (bottom - middle) * arrived;
    }

    canvas.drawRect(
        Rect.fromLTRB(centre - wickWidth / 2, wickTop, centre + wickWidth / 2,
            wickBottom),
        paint);

    var body = Rect.fromLTRB(centre - bodyWidth / 2, top,
        centre + bodyWidth / 2, math.max(bottom, top + wickWidth));
    var r = math.min(e.barRadius, math.min(body.width, body.height) / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(math.max(0, r))), paint);

    if (e.showValues) {
      // The close, and only the close. Four numbers over every candle is a
      // wall of digits; the close is the one a price chart is read for.
      paintTextInBox(
          canvas,
          formatSeries(e, 0, ohlc.close),
          e.valueSpec.copyWith(
              align: TextAlignSpec.center,
              verticalAlign: VerticalAlignSpec.bottom),
          Rect.fromLTWH(
              centre - slotSize / 2,
              wickTop - e.valueSpec.fontSize * 1.5,
              slotSize,
              e.valueSpec.fontSize * 1.4));
    }
  }
}

/// _bars draws the bar types, for the series in [which].
///
/// [which] rather than every series, because a chart may be a set of bars with
/// a line over it -- see paintCartesian. It is also what decides whether the bars
/// are side by side: two bar series share a slot however the chart's own type
/// is set, since drawing them on top of each other would hide one of them.
void _bars(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    bool horizontal, List<int> which, double reveal) {
  var data = e.data;
  var slots = data.categories.length;
  if (slots == 0 || which.isEmpty) return;

  var stacked = e.type.isStacked && which.length > 1;
  var grouped = !stacked && which.length > 1;
  var seriesCount = grouped ? which.length : 1;

  var slotSize = (horizontal ? plot.height : plot.width) / slots;
  var barSpan = slotSize * (1 - e.barGap.clamp(0.0, 0.9));
  var barSize = barSpan / seriesCount;
  var zero = range.fraction(0).clamp(0.0, 1.0);

  for (var i = 0; i < slots; i++) {
    var slotStart = (horizontal ? plot.top : plot.left) + slotSize * i;
    var inset = (slotSize - barSpan) / 2;

    var stackPos = 0.0, stackNeg = 0.0;
    for (var at = 0; at < which.length; at++) {
      var s = which[at];
      var series = data.series[s];
      var v = data.valueAt(s, i);
      // No bar at all where there is no reading. A pot that did not exist in
      // 2019 and one that held nothing in 2019 are different facts, and a bar
      // of no height says the second about both.
      if (v.isNaN) continue;

      double from, to;
      if (stacked) {
        var base = v >= 0 ? stackPos : stackNeg;
        from = range.fraction(base);
        to = range.fraction(base + v);
        v >= 0 ? stackPos += v : stackNeg += v;
      } else {
        from = zero;
        to = range.fraction(v);
      }

      var lo = math.min(from, to), hi = math.max(from, to);
      // A reading of nought still makes a mark, where the chart asks for one.
      // A bar of no height has no pixels, so a measured nought and a year
      // nobody has a figure for looked identical -- and Dash's budget, which
      // is never retained and so is nought every year by design, drew nothing
      // at all where the whole point was to show that it was nought.
      //
      // Grown from the baseline in the direction the bar would have gone, so
      // a floor on a chart with negative readings pushes down rather than up.
      if (e.barFloor > 0) {
        var span = horizontal ? plot.width : plot.height;
        var least = span <= 0 ? 0.0 : e.barFloor / span;
        if (hi - lo < least) {
          if (to < from) {
            lo = hi - least;
          } else {
            hi = lo + least;
          }
        }
      }

      Rect bar;
      if (horizontal) {
        var y = slotStart + inset + (grouped ? barSize * at : 0);
        bar = Rect.fromLTWH(plot.left + plot.width * lo, y,
            plot.width * (hi - lo), grouped ? barSize : barSpan);
      } else {
        var x = slotStart + inset + (grouped ? barSize * at : 0);
        bar = Rect.fromLTWH(x, plot.bottom - plot.height * hi,
            grouped ? barSize : barSpan, plot.height * (hi - lo));
      }

      // Where this bar has got to. Staggered by category rather than by
      // series, which is what "one bar after another, left to right" means --
      // grouped bars in the same slot arrive together, as a group.
      var colour = series.color;
      var arrived = 1.0;
      if (e.animation.on && reveal < 1) {
        // This series' own place in the animation, which is the whole of it
        // unless it has been shifted. See ChartSeries.delay.
        var p = e.animation.progressAt(series.revealAt(reveal), i, slots);
        if (p <= 0) continue;
        switch (e.animation.preset) {
          case ChartAnimationPreset.fadeIn:
            // Fading, not growing. The number is already its full self and
            // counting it up would say something the bar does not.
            colour = colour.withValues(alpha: colour.a * p.clamp(0.0, 1.0));
          case ChartAnimationPreset.popIn:
          case ChartAnimationPreset.random:
            arrived = p;
            // About its own centre, so it springs where it stands rather than
            // sliding in from the axis.
            bar = Rect.fromCenter(
                center: bar.center,
                width: bar.width * p,
                height: bar.height * p);
          case ChartAnimationPreset.grow:
          case ChartAnimationPreset.drawOn:
            arrived = p;
            // Out of the axis. An overshoot goes past the true height and
            // settles back, which is the whole reason the ease is a setting.
            bar = horizontal
                ? Rect.fromLTWH(bar.left, bar.top, bar.width * p, bar.height)
                : Rect.fromLTWH(bar.left, bar.bottom - bar.height * p,
                    bar.width, bar.height * p);
          case ChartAnimationPreset.none:
          case ChartAnimationPreset.wipe:
          case ChartAnimationPreset.sweep:
            break;
        }
      }

      // A year worked out rather than looked up is drawn faint. The weight
      // of the mark is how certain the figure is, which is a thing a chart
      // can say without a word of explanation -- and the alternative, a
      // footnote naming the estimated years, is a footnote nobody reads
      // against the bar they are looking at.
      if (data.isEstimated(i)) {
        colour = colour.withValues(alpha: colour.a * estimatedFade);
      }

      var r = math.min(
          series.cornerOn(e.barRadius), math.min(bar.width, bar.height) / 2);
      // Across the bar rather than across the plot: a gradient set on a
      // series is a gradient on each of its bars, which is what a chart of
      // bars fading into the background looks like. Across the plot they
      // would each be a different flat colour.
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, Radius.circular(math.max(0, r))),
          Paint()
            ..color = colour
            ..shader = seriesShader(series, bar,
                alpha: series.color.a == 0 ? 1 : colour.a / series.color.a));

      if (e.showValues && v != 0) {
        // Counting up with the bar. Clamped to the real value even when the
        // curve overshoots: a bar may stand a little proud of its mark for a
        // moment and be read as a flourish, and a number that says 21 where
        // the data says 20 is simply wrong.
        var label = formatTick(e, v * arrived.clamp(0.0, 1.0));
        var box = horizontal
            ? Rect.fromLTWH(
                bar.right + e.valueSpec.fontSize * 0.3,
                bar.center.dy - e.valueSpec.fontSize,
                e.valueSpec.fontSize * 5,
                e.valueSpec.fontSize * 2)
            : Rect.fromLTWH(bar.left, bar.top - e.valueSpec.fontSize * 1.5,
                bar.width, e.valueSpec.fontSize * 1.4);
        paintTextInBox(
            canvas,
            label,
            e.valueSpec.copyWith(
                align: horizontal ? TextAlignSpec.left : TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle),
            box);
      }
    }
  }
}

/// _lines draws the line, area and scatter types, for the series in [which].
///
/// Each of them by its *own* type rather than by the chart's, so one series
/// can be an area and the next a scatter over the same axes.
void _lines(ui.Canvas canvas, Rect plot, _ValueRange range, ChartElement e,
    List<int> which, double reveal) {
  var data = e.data;
  var n = data.categories.length;
  if (n == 0) return;

  // Points sit in the middle of their slot, not on the axis ends, so a line
  // chart and a bar chart of the same numbers line up with each other.
  double xAt(int i) => plot.left + plot.width * (n == 1 ? 0.5 : (i + 0.5) / n);
  double yAt(double v) =>
      plot.bottom - plot.height * range.fraction(v).clamp(-0.2, 1.2);

  var animation = e.animation;
  var animating = animation.on && reveal < 1;

  for (var at = 0; at < which.length; at++) {
    var s = which[at];
    var series = data.series[s];
    var kind = series.typeIn(e.type);
    // A cell nobody filled in is a hole in the line, not a reading of nought.
    // The points stay a full-length list so that a row and its dot and its
    // written value keep the same index; what says whether each one is there
    // is [present], and every step below asks it.
    var present = [for (var i = 0; i < n; i++) data.hasValueAt(s, i)];
    var points = [
      for (var i = 0; i < n; i++)
        Offset(xAt(i), yAt(present[i] ? data.valueAt(s, i) : 0)),
    ];
    if (points.isEmpty || !present.contains(true)) continue;

    // A line is staggered by *series*, not by point: the points of one line
    // are one movement, and drawing them in turn is what "draw on" already
    // does along the length of it.
    //
    // A scattered cloud is the exception, and Random is the preset for it:
    // there every dot is its own item and they are counted across the series
    // as well as along them, so two series fill in together rather than one
    // after the other.
    var perPoint = animation.preset.scrambles && kind == ChartType.scatter;
    var mine = series.revealAt(reveal);
    var progress = animating && !perPoint
        ? animation.progressAt(mine, at, which.length)
        : 1.0;
    if (animating && !perPoint && progress <= 0) continue;

    var alpha = 1.0;
    if (animating) {
      switch (animation.preset) {
        case ChartAnimationPreset.fadeIn:
          alpha = progress.clamp(0.0, 1.0);
        case ChartAnimationPreset.grow:
        case ChartAnimationPreset.popIn:
        case ChartAnimationPreset.random:
          // Up out of the baseline, so a line arrives the way the bars beside
          // it do. A scattered cloud never gets here -- it is dealt dot by dot
          // below.
          points = [
            for (var point in points)
              Offset(
                  point.dx, plot.bottom - (plot.bottom - point.dy) * progress),
          ];
        case ChartAnimationPreset.drawOn:
        case ChartAnimationPreset.none:
        case ChartAnimationPreset.wipe:
        case ChartAnimationPreset.sweep:
          break;
      }
    }
    var colour = alpha >= 1
        ? series.color
        : series.color.withValues(alpha: series.color.a * alpha);
    // This series' own thickness where it has been given one, so a line laid
    // over a set of bars can be heavy enough to read against them without
    // every other line on the chart thickening with it.
    var weight = series.widthOn(e.strokeWidth);

    // The runs of consecutive readings. A line drawn straight across a year
    // nobody has a figure for is a line claiming a figure, so each run is its
    // own path -- and a run of one has no line at all, only its dot.
    var runs = <List<int>>[];
    for (var i = 0; i < n; i++) {
      if (!present[i]) continue;
      if (runs.isEmpty || i == 0 || !present[i - 1]) runs.add(<int>[]);
      runs.last.add(i);
    }

    if (kind != ChartType.scatter) {
      var smooth = series.smoothOn(e.smooth) && kind.usesSmooth;
      // path is the whole line, which is what the area under it is closed
      // from and what the drawing-on measures along. Where the chart marks
      // its estimates the stroke is split in two -- the stretches either end
      // of which was worked out rather than looked up are drawn as dashes --
      // and where it does not, solid is the whole line and the split costs
      // nothing.
      var path = Path();
      var solid = Path();
      var dashed = Path();
      var marks = data.marksEstimates;
      for (var run in runs) {
        if (run.length < 2) continue;
        var pts = [for (var i in run) points[i]];
        path.addPath(_linePath(pts, smooth), Offset.zero);
        if (!marks) continue;
        for (var k = 0; k < run.length - 1; k++) {
          // Either end: a stretch running into an estimated year is as
          // uncertain as the year itself.
          var soft = data.isEstimated(run[k]) || data.isEstimated(run[k + 1]);
          (soft ? dashed : solid)
              .addPath(_segmentPath(pts, k, smooth), Offset.zero);
        }
      }
      // Traced from its start rather than grown from the axis: the line is
      // cut short at the point it has reached, and the area under it with it.
      if (animating &&
          animation.preset == ChartAnimationPreset.drawOn &&
          progress < 1) {
        path = _trimmed(path, progress);
        solid = _trimmed(solid, progress);
        dashed = _trimmed(dashed, progress);
        // A point the line has not reached yet is not there yet, which is the
        // same thing as a point with no reading as far as the dots and the
        // written values are concerned. Marked rather than dropped, so that
        // every point keeps the index of the row it came from.
        var tip = _lastX(path);
        for (var i = 0; i < n; i++) {
          if (points[i].dx > tip) present[i] = false;
        }
      }
      var shader = seriesShader(series, plot, alpha: alpha);
      if (kind == ChartType.area) {
        // Closed at the line's own tip rather than at the last point it has
        // passed. Using the last *data* point left the fill's right edge
        // standing still while the line ran on ahead of it, so the area
        // caught up in jumps -- one jump per category.
        var drawn = [
          for (var i = 0; i < n; i++)
            if (present[i]) points[i]
        ];
        if (drawn.isEmpty) drawn = [points.first];
        var tip = _pathEnd(path) ?? drawn.last;
        var fill = Path.from(path)
          ..lineTo(tip.dx, plot.bottom)
          ..lineTo(drawn.first.dx, plot.bottom)
          ..close();
        // The series' own gradient where it has one; otherwise the fade
        // into nothing that is what an area chart has always been.
        canvas.drawPath(
            fill,
            Paint()
              ..shader = shader ??
                  ui.Gradient.linear(
                      Offset(0, plot.top), Offset(0, plot.bottom), [
                    colour.withValues(alpha: 0.45 * alpha),
                    colour.withValues(alpha: 0.02 * alpha),
                  ]));
      }
      var stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = weight
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colour
        // Across the plot, so the line changes colour along its length
        // rather than each segment being its own gradient.
        ..shader = shader;
      if (!marks) {
        canvas.drawPath(path, stroke);
      } else {
        canvas.drawPath(solid, stroke);
        // Dashed *and* faint, the same two things the bars say: how certain
        // the figure is, said in the weight of the mark.
        canvas.drawPath(
            _dashed(dashed, weight),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = weight
              ..strokeCap = StrokeCap.butt
              ..strokeJoin = StrokeJoin.round
              ..color = colour.withValues(alpha: colour.a * estimatedFade * 2)
              ..shader = shader);
      }
    }

    // A scatter is all dots; a chart writing its values has to put them
    // somewhere; and a line or an area marks its readings where it is asked
    // to. Eleven points joined up look like a hundred until the dots are on
    // them.
    if (kind == ChartType.scatter ||
        e.showValues ||
        series.pointsOn(e.showPoints)) {
      for (var i = 0; i < points.length; i++) {
        if (!present[i]) continue;
        // Each dot's own arrival, when they are being dealt one at a time.
        var dot = perPoint
            ? animation.progressAt(mine, at * n + i, which.length * n)
            : progress;
        if (animating && dot <= 0) continue;

        var swelling = animating &&
            (animation.preset == ChartAnimationPreset.popIn ||
                animation.preset == ChartAnimationPreset.random);
        // The size asked for, or the line's own weight as it always was.
        var size = series.pointSizeOn(e.pointSize);
        var radius = size > 0 ? size : weight * 1.4;
        // And the colour asked for, or the series' -- which is what a dot on
        // a line is unless somebody says otherwise. Whatever the arrival has
        // done to the line is done to the dot as well, so the two come on
        // together.
        var dotPaint = series.pointColorOn(e.pointColor);
        var dotColour = dotPaint.a > 0
            ? dotPaint.withValues(
                alpha: dotPaint.a *
                    (colour.a / (series.color.a == 0 ? 1 : series.color.a)))
            : colour;
        canvas.drawCircle(
            points[i],
            radius * (swelling ? dot.clamp(0.0, 1.4) : 1),
            Paint()
              ..color = perPoint && dot < 1
                  ? dotColour.withValues(
                      alpha: dotColour.a * dot.clamp(0.0, 1.0))
                  : dotColour);
        if (e.showValues) {
          // Counting up only where the point itself is growing. Drawn on, a
          // point that has been passed is at its full value and saying
          // otherwise would contradict the line running through it.
          var shown = swelling ||
                  (animating &&
                      !perPoint &&
                      animation.preset == ChartAnimationPreset.grow)
              ? dot.clamp(0.0, 1.0)
              : 1.0;
          paintTextInBox(
              canvas,
              formatSeries(e, s, data.valueAt(s, i) * shown),
              e.valueSpec.copyWith(
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.bottom),
              Rect.fromCenter(
                  center: points[i].translate(0, -e.valueSpec.fontSize * 1.4),
                  width: e.valueSpec.fontSize * 6,
                  height: e.valueSpec.fontSize * 1.6));
        }
      }
    }
  }
}

/// estimatedFade is how much of its colour a mark keeps where the figure
/// behind it was worked out rather than looked up.
///
/// A third, which is enough to read as the same series and not enough to be
/// mistaken for a sourced one. See ChartData.estimated.
const double estimatedFade = 0.34;

/// estimatedDash is the on-off pattern an estimated stretch of line is drawn
/// with, in multiples of the line's own weight.
const List<double> estimatedDash = [2.2, 1.8];

/// _segmentPath is the one stretch from `points[i]` to `points[i + 1]`, drawn
/// exactly as [_linePath] would draw it.
///
/// The same control points, so that splitting a smoothed line into solid and
/// dashed stretches does not change its shape: a curve through its
/// neighbours, cut where the certainty changes rather than re-fitted.
Path _segmentPath(List<Offset> points, int i, bool smooth) {
  var p1 = points[i], p2 = points[i + 1];
  var path = Path()..moveTo(p1.dx, p1.dy);
  if (!smooth || points.length < 3) {
    path.lineTo(p2.dx, p2.dy);
    return path;
  }
  var p0 = i == 0 ? p1 : points[i - 1];
  var p3 = i + 2 < points.length ? points[i + 2] : p2;
  var c1 = p1 + (p2 - p0) / 6;
  var c2 = p2 - (p3 - p1) / 6;
  path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  return path;
}

/// _dashed is [path] as a run of dashes, or the path itself where the weight
/// makes no sense.
Path _dashed(Path path, double weight) {
  if (weight <= 0) return path;
  var on = estimatedDash[0] * weight, off = estimatedDash[1] * weight;
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var at = 0.0;
    while (at < metric.length) {
      out.addPath(metric.extractPath(at, math.min(at + on, metric.length)),
          Offset.zero);
      at += on + off;
    }
  }
  return out;
}

/// _trimmed is the first [fraction] of a path, by length. What draws a line on
/// rather than growing it out of the axis.
Path _trimmed(Path path, double fraction) {
  var out = Path();
  for (var metric in path.computeMetrics()) {
    var want = metric.length * fraction.clamp(0.0, 1.0);
    if (want <= 0) continue;
    out.addPath(metric.extractPath(0, want), Offset.zero);
  }
  return out;
}

/// _lastX is how far along the drawn part has got, which is what decides
/// which of the line's points have arrived and may be dotted or labelled.
double _lastX(Path path) => path.getBounds().right;

/// _pathEnd is where a path actually stops.
///
/// Off the metrics rather than off the bounding box, which is the same thing
/// only for a line that runs left to right and never comes back -- and a
/// smoothed line overshoots its own points, so even that one is not quite
/// true.
Offset? _pathEnd(Path path) {
  Offset? out;
  for (var metric in path.computeMetrics()) {
    var tangent = metric.getTangentForOffset(metric.length);
    if (tangent != null) out = tangent.position;
  }
  return out;
}

/// _linePath joins the points, optionally through a Catmull-Rom style smooth.
///
/// The control points are a fraction of the gap to each neighbour, which keeps
/// the curve from overshooting past a peak -- overshoot on a chart is not a
/// style choice, it draws a value that is not in the data.
Path _linePath(List<Offset> points, bool smooth) {
  var path = Path()..moveTo(points.first.dx, points.first.dy);
  if (!smooth || points.length < 3) {
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }
  for (var i = 0; i < points.length - 1; i++) {
    var p0 = i == 0 ? points[i] : points[i - 1];
    var p1 = points[i];
    var p2 = points[i + 1];
    var p3 = i + 2 < points.length ? points[i + 2] : p2;
    var c1 = p1 + (p2 - p0) / 6;
    var c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

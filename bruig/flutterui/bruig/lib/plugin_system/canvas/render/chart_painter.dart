import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/chart_words.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_cartesian.dart';
import 'package:bruig/plugin_system/canvas/render/chart_circular.dart';
import 'package:bruig/plugin_system/canvas/render/chart_infographic.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/chart_notes.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:bruig/plugin_system/canvas/export/vector_canvas.dart';

// chart_painter.dart draws a ChartElement's frame: the title, description,
// legend and empty placeholder, and the room they leave for the picture,
// drawn by chart_cartesian.dart (x and y axes) or chart_circular.dart (round
// a centre). What they share with the legend (item progress, colours,
// number formats) is in chart_common.dart, so the key matches the picture.

/// paintChart draws [e] filling [rect]. [reveal] is how much has arrived,
/// 0 to 1 (KeyframeChannel.reveal); 1 for a chart with no animation.
/// [close] is how far through leaving it is (KeyframeChannel.close): above
/// zero the closing preset runs in reverse. [seriesReveal] is reveal per
/// series offset by ChartSeries.delay, or null; the renderer works it out
/// (see chartSeriesReveal) because the delay is in seconds.
/// chartInner is where a chart in [rect] lays out its title, key and plot:
/// inside its card's padding (ChartElement.box).
Rect chartInner(ChartElement e, Rect rect) =>
    chartBoxIsPlain(e.box) ? rect : e.box.inner(rect);

void paintChart(ui.Canvas canvas, Rect rect, ChartElement e,
    {double reveal = 1, double close = 0, List<double>? seriesReveal}) {
  // The card behind it all, then everything inside its padding.
  if (!chartBoxIsPlain(e.box)) {
    paintBox(canvas, rect, e.box);
    rect = e.box.inner(rect);
  }
  // A scatter sized by a third number: its first series drawn, each point
  // as big as the second says (by area); the second is no axis's.
  if (e.type == ChartType.scatter &&
      modeOf(e.design, "scatter") == "sized" &&
      e.data.series.length > 1) {
    var v = [
      for (var i = 0; i < e.data.categories.length; i++)
        e.data.valueAt(1, i).isNaN ? 0.0 : e.data.valueAt(1, i).abs()
    ];
    var most = v.fold(0.0, math.max);
    e = e.copyWith(
        data: e.data.copyWith(
            series: [e.data.series.first],
            sizes: [for (var x in v) most <= 0 ? 0.0 : math.sqrt(x / most)]));
  }
  // An area of shares of the whole: each band its running total of the
  // shares, the largest drawn first so each smaller lies over it.
  if (e.type == ChartType.area &&
      modeOf(e.design, "area") == "share" &&
      e.data.series.length > 1) {
    var d = e.data, n = d.categories.length, k = d.series.length;
    var totals = [
      for (var i = 0; i < n; i++)
        [for (var s = 0; s < k; s++) d.valueAt(s, i)]
            .where((v) => !v.isNaN && v > 0)
            .fold(0.0, (a, b) => a + b)
    ];
    var running = List.filled(n, 0.0);
    var stacked = <ChartSeries>[];
    for (var s = 0; s < k; s++) {
      for (var i = 0; i < n; i++) {
        var v = d.valueAt(s, i);
        if (!v.isNaN && v > 0 && totals[i] > 0) {
          running[i] += v / totals[i] * 100;
        }
      }
      stacked.add(d.series[s].copyWith(values: [...running]));
    }
    e = e.copyWith(
        yMin: 0,
        yMax: 100,
        data: d.copyWith(series: stacked.reversed.toList(), named: const []));
  }
  // A morph is the renderer's (chart_morph.dart); anywhere else (a
  // thumbnail, the Studio) it comes up as a fade.
  if (e.animation.preset == ChartAnimationPreset.morph) {
    e = e.copyWith(
        animation: e.animation.copyWith(preset: ChartAnimationPreset.fadeIn));
  }
  if (rect.width <= 8 || rect.height <= 8) return;

  // Leaving: the exit preset replaces the entrance one for all that follows.
  var leaving = e.animation.closes && close > 0;
  if (leaving) {
    e = e.copyWith(animation: e.animation.leaving);
    reveal = 1 - close.clamp(0.0, 1.0);
    // The whole chart leaves together; series delays apply only on arrival.
    seriesReveal = null;
  }

  var animation = e.animation;
  var showing = animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  // The furthest on: a series brought forward arrives before the chart does.
  var furthest = showing;
  for (var r in seriesReveal ?? const <double>[]) {
    furthest = math.max(furthest, r.clamp(0.0, 1.0));
  }
  // Nothing has arrived: the axes and labels arrive with the chart.
  if (animation.on && furthest <= 0) return;
  // Its own ground, behind everything (a style's panel).
  if (e.panel.a > 0) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.min(12, rect.shortestSide * 0.04))),
        Paint()..color = e.panel);
  }
  var data = e.data;
  if (data.series.isEmpty) {
    _placeholder(canvas, e.body.rectIn(rect), e);
    return;
  }

  // Everything but a placed label is drawn in the body, which differs from
  // the box only once a label is dragged outside it. See ChartBody.
  var body = e.body.rectIn(rect);
  var area = body;

  // Labels either stack above the chart, taking height, or float over it,
  // taking none and drawn after it so they stay readable.
  var floating = e.floatingLabels;
  if (!floating) {
    var was = area;
    area = _flowLabel(
        canvas, area, body, liveWords(data, e.title), e.titleBox, e.titleSpec);
    if (area.top > was.top) {
      notePart(ChartPartKind.title,
          Rect.fromLTRB(was.left, was.top, was.right, area.top));
    }
    was = area;
    area = _flowLabel(canvas, area, body, liveWords(data, e.description),
        e.descriptionBox, descriptionSpec(e));
    if (area.top > was.top) {
      notePart(ChartPartKind.description,
          Rect.fromLTRB(was.left, was.top, was.right, area.top));
    }
    // A one-series chart gets a legend too. A legend dragged off its slot
    // takes no room and is drawn over the plot below.
    if (e.showLegend && data.series.isNotEmpty && !e.legend.hasPlace) {
      was = area;
      area = _legend(canvas, area, e, showing);
      notePart(ChartPartKind.legend, _legendBlock(e, was, 1));
    }
  } else if (chartParts != null) {
    for (var MapEntry(:key, :value) in _labelPlaces(e, rect).entries) {
      notePart(
          switch (key) {
            ChartLabelPart.title => ChartPartKind.title,
            ChartLabelPart.description => ChartPartKind.description,
            ChartLabelPart.legend => ChartPartKind.legend,
          },
          value);
    }
  }

  // Wipe and sweep are a clip round the whole plot; every other preset is
  // per item, where the items are drawn.
  var clipping = animation.on &&
      showing < 1 &&
      (animation.preset == ChartAnimationPreset.wipe ||
          animation.preset == ChartAnimationPreset.sweep);
  if (clipping) {
    canvas.save();
    if (animation.preset == ChartAnimationPreset.wipe) {
      canvas.clipRect(Rect.fromLTWH(area.left, area.top,
          area.width * animation.ease.apply(showing), area.height));
    } else {
      canvas.clipPath(_wedge(area, animation.ease.apply(showing)));
    }
  }

  // Notes bound to the data on an axisless kind find their items where it
  // draws them (chart_notes.dart), added to any gathering already going.
  var axisless = data.panels.isEmpty && e.type.isCircular;
  var noting = axisless && boundNotes(e).isNotEmpty;
  var gathering = chartParts;
  var mine = <ChartPart>[];
  if (noting) chartParts = mine;
  if (data.panels.isNotEmpty) {
    _paintPanels(canvas, area, e);
  } else if (e.type.isInfographic) {
    paintInfographic(canvas, area, e, showing);
  } else if (e.type.isCircular) {
    paintCircular(canvas, area, e, showing);
  } else {
    paintCartesian(canvas, area, e, showing, seriesReveal);
  }
  if (noting) {
    chartParts = gathering;
    gathering?.addAll(mine);
    paintBoundNotes(canvas, area, e, mine,
        animation.on ? ((showing - 0.6) / 0.4).clamp(0.0, 1.0) : 1.0);
  }

  if (clipping) canvas.restore();

  if (floating) {
    _placedLabel(canvas, rect, liveWords(data, e.title), e.titleBox,
        defaultTitlePlacement, e.titleSpec);
    _placedLabel(
        canvas,
        rect,
        liveWords(data, e.description),
        e.descriptionBox,
        defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty),
        descriptionSpec(e));
    if (e.showLegend && data.series.isNotEmpty) {
      _legend(canvas, rect, e, showing);
    }
  } else if (e.showLegend && data.series.isNotEmpty && e.legend.hasPlace) {
    // A key dragged off its slot on a chart with stacked labels.
    _legend(canvas, rect, e, showing);
  }
}

/// chartLabelPlaces is where a floating chart draws its three pieces of
/// writing, in the element's own coordinates. The stage hit-tests these, so
/// they come from the painter's own measurement.
Map<ChartLabelPart, Rect> chartLabelPlaces(ChartElement e, Rect rect) =>
    _labelPlaces(e, chartInner(e, rect));

Map<ChartLabelPart, Rect> _labelPlaces(ChartElement e, Rect rect) {
  if (!e.floatingLabels) {
    // With stacked labels only a key dragged off its slot floats to grab.
    if (e.showLegend && e.legend.hasPlace && e.data.series.isNotEmpty) {
      return {ChartLabelPart.legend: _legendBlock(e, rect, 1)};
    }
    return const {};
  }
  return {
    if (e.titleBox.show && e.title.isNotEmpty)
      ChartLabelPart.title: _placeOf(e.titleBox, defaultTitlePlacement, rect),
    if (e.descriptionBox.show && e.description.isNotEmpty)
      ChartLabelPart.description: _placeOf(e.descriptionBox,
          defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty), rect),
    if (e.showLegend && e.data.series.isNotEmpty)
      ChartLabelPart.legend: _legendBlock(e, rect, 1),
  };
}

/// ChartLabelPart names the three things a chart writes over itself, so the
/// stage can say which of them a pointer has taken hold of.
enum ChartLabelPart { title, description, legend }

Rect _placeOf(ChartLabel box, ChartLabel fallback, Rect rect) =>
    (box.hasPlace ? box : fallback).rectIn(rect);

/// descriptionSpec is the description's type: the label size, softened, so
/// it reads as a note under the title, not a second title.
TextSpec descriptionSpec(ChartElement e) => e.descriptionText.copyWith(
      color: e.descriptionText.color.withValues(alpha: 0.75),
      verticalAlign: VerticalAlignSpec.top,
    );

/// _flowLabel draws a label the chart lays out itself, and returns what is
/// left below it. A hidden, empty or placed label takes no room here.
Rect _flowLabel(ui.Canvas canvas, Rect area, Rect rect, String text,
    ChartLabel box, TextSpec spec) {
  if (!box.show || text.isEmpty) return area;
  // Top-aligned: the box is the rest of the area; a TextSpec would centre.
  var h = paintTextInBox(
      canvas,
      text,
      spec.copyWith(verticalAlign: VerticalAlignSpec.top),
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      clip: true);
  return Rect.fromLTRB(
      area.left, area.top + h + rect.height * 0.02, area.right, area.bottom);
}

/// _placedLabel draws a moved label in its own box over everything else.
void _placedLabel(ui.Canvas canvas, Rect rect, String text, ChartLabel box,
    ChartLabel fallback, TextSpec spec) {
  if (!box.show || text.isEmpty) return;
  // Where it was put, or the default place if it has never been dragged.
  paintTextInBox(canvas, text, spec, _placeOf(box, fallback, rect), clip: true);
}

/// _wedge is a pie slice from the top, for a sweep. A full turn is the whole
/// area, so the clip stops mattering exactly when the animation ends.
Path _wedge(Rect area, double turn) {
  if (turn >= 1) return Path()..addRect(area);
  var centre = area.center;
  // Long enough to reach any corner.
  var reach = area.longestSide;
  return Path()
    ..moveTo(centre.dx, centre.dy)
    ..lineTo(centre.dx, centre.dy - reach)
    ..arcTo(Rect.fromCircle(center: centre, radius: reach), -math.pi / 2,
        math.pi * 2 * turn.clamp(0.0, 1.0), false)
    ..close();
}

/// _placeholder is an empty chart: a labelled frame, so a new chart is
/// visible and selectable before it has data.
void _placeholder(ui.Canvas canvas, Rect rect, ChartElement e) {
  canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = e.axisColor);
  paintTextInBox(
      canvas,
      "No chart data yet",
      e.labelSpec.copyWith(
          align: TextAlignSpec.center, verticalAlign: VerticalAlignSpec.middle),
      rect,
      clip: true);
}

/// LegendEntry is one line of the key: its swatch, its name, and [series],
/// the series it stands for, which makes it pressable (chartLegendRects);
/// -1 for a pie's categories or a candlestick's up and down.
class LegendEntry {
  final Color colour;
  final String name;
  final int series;
  final bool hidden;

  const LegendEntry(this.colour, this.name,
      {this.series = -1, this.hidden = false});
}

/// _legendEntries is the key's lines: series for types drawn as series,
/// categories for types coloured by value (a pie). Radial bars have no room
/// for numbers on the rings, so their values are written in the key.
List<LegendEntry> _legendEntries(ChartElement e, double reveal) {
  var data = e.data;
  // A candlestick's colours mean closed up or down, not its four series.
  if (e.type.isCandles && data.series.length >= 4) {
    return [
      LegendEntry(e.riseColor, "Closed up"),
      LegendEntry(e.fallColor, "Closed down"),
    ];
  }
  if (!colouredByValue(e.type)) {
    return [
      for (var (i, s) in data.series.indexed)
        LegendEntry(s.color, s.name, series: i, hidden: s.hidden),
    ];
  }

  var values =
      data.series.isEmpty ? const <double>[] : data.series.first.values;
  return [
    for (var i = 0; i < values.length; i++)
      LegendEntry(
        sliceColour(e, i),
        _legendName(
            e, i, values[i], sliceProgress(e, reveal, i, values.length)),
      ),
  ];
}

String _legendName(ChartElement e, int i, double value, SliceProgress slice) {
  var name = i < e.data.categories.length && e.data.categories[i].isNotEmpty
      ? e.data.categories[i]
      : "${i + 1}";
  // The key's own switch, separate from the chart's showValues.
  if (!e.legend.values) return name;
  // Counts up with its slice or ring.
  return "$name${e.legend.separator}"
      "${formatSeries(e, 0, value * slice.size.clamp(0.0, 1.0))}";
}

/// legendEntriesForTest is [_legendEntries], for tests.
@visibleForTesting
List<LegendEntry> legendEntriesForTest(ChartElement e, double reveal) =>
    _legendEntries(e, reveal);

/// legendLeavesForTest is the area left for the chart once the key has
/// taken its share: a bitmap test would find the swatches, not the bars.
@visibleForTesting
Rect legendLeavesForTest(ChartElement e, Rect area, {double reveal = 1}) =>
    _legend(ui.Canvas(ui.PictureRecorder()), area, e, reveal);

/// _LegendLayout is the key measured but not yet drawn: its rows and size.
/// Shared by drawing, layout and the stage's hit-testing.
class _LegendLayout {
  final List<List<(LegendEntry, TextPainter)>> rows;
  final double swatch;
  final double gap;
  final double rowHeight;
  final double between;
  final double rowGap;
  final Size size;

  const _LegendLayout(this.rows, this.swatch, this.gap, this.rowHeight,
      this.between, this.rowGap, this.size);
}

_LegendLayout? _measureLegend(ChartElement e, Rect area, double reveal) {
  var legend = e.legend;
  var spec = e.labelSpec
      .copyWith(fontSize: e.labelSpec.fontSize * legend.scale.clamp(0.3, 4.0));
  var entries = _legendEntries(e, reveal);
  if (entries.isEmpty || spec.fontSize <= 0) return null;

  var swatch = spec.fontSize * 0.7;
  var gap = spec.fontSize * 0.5;
  var rowHeight = spec.fontSize * 1.6;
  var between = spec.fontSize * legend.spacing.clamp(0.0, 6.0);

  // A side key wraps within a third of the width; a top or bottom one within
  // all of it. It takes only the width it needs.
  var room = legend.placement.isSide ? area.width * 0.34 : area.width;

  var items = [
    for (var entry in entries)
      (
        entry,
        layoutText(
            entry.name,
            // A hidden series stays in the key, faint, to be shown again.
            entry.hidden
                ? spec.copyWith(color: spec.color.withValues(alpha: 0.4))
                : spec,
            maxWidth: math.max(1, room - swatch - gap))
      ),
  ];

  var rows = <List<(LegendEntry, TextPainter)>>[];
  var row = <(LegendEntry, TextPainter)>[];
  var used = 0.0;
  for (var item in items) {
    if (legend.vertical) {
      rows.add([item]);
      continue;
    }
    var width = swatch + gap * 0.6 + item.$2.width;
    if (row.isNotEmpty && used + between + width > room) {
      rows.add(row);
      row = [];
      used = 0;
    }
    used += (row.isEmpty ? 0 : between) + width;
    row.add(item);
  }
  if (row.isNotEmpty) rows.add(row);

  var rowGap = legend.vertical ? between * 0.35 : 0.0;
  var height = rows.length * rowHeight + (rows.length - 1) * rowGap;
  var width = 0.0;
  for (var r in rows) {
    var w = 0.0;
    for (var i = 0; i < r.length; i++) {
      w += (i > 0 ? between : 0) + swatch + gap * 0.6 + r[i].$2.width;
    }
    width = math.max(width, w);
  }

  return _LegendLayout(
      rows, swatch, gap, rowHeight, between, rowGap, Size(width, height));
}

/// chartLegendRects is where each key entry was drawn, in the element's own
/// coordinates, paired with its series. Measured by the function that draws, so
/// hit areas cannot drift. Entries that are not series are left out.
List<(int, Rect)> chartLegendRects(ChartElement e, Rect bounds,
    {double reveal = 1}) {
  if (!e.showLegend || e.data.series.isEmpty) return const [];

  var area = _legendArea(e, chartInner(e, bounds));
  var layout = _measureLegend(e, area, reveal);
  if (layout == null) return const [];

  var origin = _legendOrigin(e, area, layout.size);
  var out = <(int, Rect)>[];
  var y = origin.dy;
  for (var r in layout.rows) {
    var x = origin.dx;
    for (var i = 0; i < r.length; i++) {
      if (i > 0) x += layout.between;
      var (entry, painter) = r[i];
      var width = layout.swatch + layout.gap * 0.6 + painter.width;
      if (entry.series >= 0) {
        out.add((entry.series, Rect.fromLTWH(x, y, width, layout.rowHeight)));
      }
      x += width;
    }
    y += layout.rowHeight + layout.rowGap;
  }
  return out;
}

/// _legendArea is the rectangle the key is laid out in: the whole box once
/// it floats, else what the stacked title and description leave. Found by
/// the painter's own walk into a throwaway canvas.
Rect _legendArea(ChartElement e, Rect bounds) {
  if (e.floatingLabels || e.legend.hasPlace) return bounds;
  var body = e.body.rectIn(bounds);
  var scratch = ui.Canvas(ui.PictureRecorder());
  var area = _flowLabel(scratch, body, body, e.title, e.titleBox, e.titleSpec);
  return _flowLabel(
      scratch, area, body, e.description, e.descriptionBox, descriptionSpec(e));
}

Offset _legendOrigin(ChartElement e, Rect area, Size size) {
  // A dragged key keeps its place whether or not the labels float.
  if (e.legend.hasPlace) {
    return Offset(area.left + e.legend.x * area.width,
        area.top + e.legend.y * area.height);
  }
  return switch (e.legend.placement) {
    LegendPlacement.top => Offset(area.left, area.top),
    LegendPlacement.bottom => Offset(area.left, area.bottom - size.height),
    LegendPlacement.left => Offset(area.left, area.top),
    LegendPlacement.right => Offset(area.right - size.width, area.top),
  };
}

/// _legendBlock is where the key is drawn, for the stage to take hold of.
Rect _legendBlock(ChartElement e, Rect area, double reveal) {
  var layout = _measureLegend(e, area, reveal);
  if (layout == null) return Rect.zero;
  return _legendOrigin(e, area, layout.size) & layout.size;
}

/// chartLegendBlock is where the whole key is drawn, in element coordinates,
/// for the stage on a key's first drag, so it does not jump.
Rect chartLegendBlock(ChartElement e, Rect bounds, {double reveal = 1}) {
  if (!e.showLegend || e.data.series.isEmpty) return Rect.zero;
  return _legendBlock(e, _legendArea(e, chartInner(e, bounds)), reveal);
}

/// _legend draws the key and returns what is left for the chart.
Rect _legend(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var layout = _measureLegend(e, area, reveal);
  if (layout == null) return area;

  var origin = _legendOrigin(e, area, layout.size);
  var y = origin.dy;
  for (var r in layout.rows) {
    var x = origin.dx;
    for (var i = 0; i < r.length; i++) {
      if (i > 0) x += layout.between;
      var (entry, painter) = r[i];
      var box = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y + (layout.rowHeight - layout.swatch) / 2,
              layout.swatch, layout.swatch),
          Radius.circular(layout.swatch * 0.25));
      // Hollow for a hidden series.
      canvas.drawRRect(
        box,
        entry.hidden
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, layout.swatch * 0.18)
              ..color = entry.colour.withValues(alpha: entry.colour.a * 0.55))
            : (Paint()..color = entry.colour),
      );
      paintTp(
          painter,
          canvas,
          Offset(x + layout.swatch + layout.gap * 0.6,
              y + (layout.rowHeight - painter.height) / 2));
      x += layout.swatch + layout.gap * 0.6 + painter.width;
    }
    y += layout.rowHeight + layout.rowGap;
  }

  // Floating, it takes no room.
  if (e.floatingLabels) return area;

  var pad = e.labelSpec.fontSize * 0.5;
  var left = switch (e.legend.placement) {
    LegendPlacement.top => Rect.fromLTRB(area.left,
        area.top + layout.size.height + pad, area.right, area.bottom),
    LegendPlacement.bottom => Rect.fromLTRB(area.left, area.top, area.right,
        area.bottom - layout.size.height - pad),
    LegendPlacement.left => Rect.fromLTRB(
        area.left + layout.size.width + pad, area.top, area.right, area.bottom),
    LegendPlacement.right => Rect.fromLTRB(
        area.left, area.top, area.right - layout.size.width - pad, area.bottom),
  };

  // A key leaving the chart under 35% either way takes no room: drawn over.
  if (left.width < area.width * 0.35 || left.height < area.height * 0.35) {
    return area;
  }
  return left;
}

/// _paintPanels draws a split chart (ChartData.panels): a small chart for
/// each in a grid, all on one scale so they compare, each named at its top
/// with where it ends and lit in its highlight's colour.
void _paintPanels(ui.Canvas canvas, Rect area, ChartElement e) {
  var panels = e.data.panels;
  var n = panels.length;
  var cols = math.max(
      1, math.sqrt(n * area.width / math.max(1.0, area.height)).round());
  var rows = (n / cols).ceil();
  const gap = 8.0;
  var w = (area.width - gap * (cols - 1)) / cols;
  var h = (area.height - gap * (rows - 1)) / rows;
  if (w <= 8 || h <= 8) return;

  // One scale for them all.
  var lo = 0.0, hi = 0.0;
  for (var p in panels) {
    for (var s in p.data.series) {
      for (var v in s.values) {
        if (v.isNaN) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
  }
  if (hi <= lo) hi = lo + 1;
  var size = math.max(8.0, e.labelSpec.fontSize * 0.9);

  void write(String text, Color colour, Offset at, {bool right = false}) {
    var tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: colour,
                fontFamily: e.labelSpec.fontFamily)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: "…")
      ..layout(maxWidth: math.max(1.0, w * 0.6));
    paintTp(tp, canvas, right ? at - Offset(tp.width, 0) : at);
    tp.dispose();
  }

  for (var (i, p) in panels.indexed) {
    var cell = Rect.fromLTWH(area.left + (i % cols) * (w + gap),
        area.top + (i ~/ cols) * (h + gap), w, h);
    var lit = p.colour != null && p.colour!.a > 0.5;
    canvas.drawRRect(RRect.fromRectAndRadius(cell, const Radius.circular(6)),
        Paint()..color = e.gridColor);
    if (lit) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(cell.deflate(0.75), const Radius.circular(6)),
          Paint()
            ..color = p.colour!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    write(p.name, lit ? p.colour! : e.labelSpec.color,
        cell.topLeft + const Offset(6, 4));
    var series = p.data.series;
    if (series.isNotEmpty) {
      var last = series.first.values
          .lastWhere((v) => !v.isNaN, orElse: () => double.nan);
      if (!last.isNaN) {
        write(
            last == last.roundToDouble()
                ? "${last.round()}"
                : last.toStringAsFixed(1),
            lit ? p.colour! : e.labelSpec.color,
            cell.topRight + const Offset(-6, 4),
            right: true);
      }
    }
    var inner = Rect.fromLTRB(
        cell.left + 4, cell.top + size * 1.8, cell.right - 4, cell.bottom - 4);
    if (inner.height > 8 && series.isNotEmpty) {
      var mini = e.copyWith(
        data: p.data.copyWith(series: [
          for (var (j, s) in series.indexed)
            j == 0 && p.colour != null ? s.copyWith(color: p.colour) : s,
        ]),
        title: "",
        description: "",
        showLegend: false,
        showXLabels: false,
        showYLabels: false,
        showValues: false,
        yMin: lo,
        yMax: hi,
        highlights: const [],
        notes: const [],
      );
      // The small chart's own parts are not the big one's.
      var noting = chartParts;
      chartParts = null;
      try {
        paintChart(canvas, inner, mini);
      } finally {
        chartParts = noting;
      }
    }
    notePart(ChartPartKind.mark, cell, series: 0, index: i);
  }
}

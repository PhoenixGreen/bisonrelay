import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_cartesian.dart';
import 'package:bruig/plugin_system/canvas/render/chart_circular.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

// chart_painter.dart draws a ChartElement.
//
// It is the frame round a chart rather than the chart itself: the title, the
// description, the legend, the empty-chart placeholder, and the arithmetic
// that decides how much room is left for the picture once all of those have
// taken their share. Everything here is measured, nothing is a guessed
// margin, so a chart with a three-line key and a chart with none both use the
// space they have.
//
// The picture itself is drawn by one of two painters, which have almost
// nothing in common beyond the animation: chart_cartesian.dart for the types
// with an x and a y axis, chart_circular.dart for the ones arranged round a
// centre. What they do share -- how far through its arrival one item is, what
// colour it takes, how a number is written -- is in chart_common.dart, so the
// legend here can ask the same questions and its swatches cannot drift out of
// step with the picture.

/// paintChart draws [e] filling [rect].
///
/// [reveal] is how much of the chart has arrived, 0 to 1, which comes off the
/// element's keyframes -- see KeyframeChannel.reveal. One means "all of it",
/// which is what a chart with no animation on it always gets.
void paintChart(ui.Canvas canvas, Rect rect, ChartElement e,
    {double reveal = 1}) {
  if (rect.width <= 8 || rect.height <= 8) return;
  var animation = e.animation;
  var showing = animation.on ? reveal.clamp(0.0, 1.0) : 1.0;
  // Nothing at all yet. Returning rather than drawing zero-height bars,
  // because the axes and the labels arrive with the chart -- a chart whose
  // grid appears a second before anything is in it looks broken rather than
  // early.
  if (animation.on && showing <= 0) return;
  var data = e.data;
  if (data.series.isEmpty) {
    _placeholder(canvas, e.body.rectIn(rect), e);
    return;
  }

  // Everything but a placed label is drawn in the body rather than in the
  // whole box. They are the same rectangle until a label has been dragged
  // outside the element, at which point the box grew to hold the label and the
  // body kept the plot where it was. See ChartBody.
  var body = e.body.rectIn(rect);
  var area = body;

  // The two labels, each either laid out by the chart or sitting where it was
  // put. A placed label is drawn last, over the plot, because a label somebody
  // has dragged onto the plot was dragged there on purpose -- and because
  // taking room away from the plot for a label that is no longer above it
  // would leave a band of nothing where it used to be.
  // Stacked above the chart, taking their share of the height -- or floating
  // over it, taking none. Floating, they are drawn *after* the chart rather
  // than before it, since a title behind a bar is a title nobody can read.
  var floating = e.floatingLabels;
  if (!floating) {
    area = _flowLabel(canvas, area, body, e.title, e.titleBox, e.titleSpec);
    area = _flowLabel(canvas, area, body, e.description, e.descriptionBox,
        descriptionSpec(e));
    // Not "and more than one series". A one-series chart with the legend
    // turned on used to draw nothing at all, which reads as the switch being
    // broken rather than as the legend being unnecessary -- and a single
    // series with a name worth reading is a good reason to want one.
    if (e.showLegend && data.series.isNotEmpty) {
      area = _legend(canvas, area, e, showing);
    }
  }

  // A wipe and a sweep are one edge travelling over everything, so they are a
  // clip round the whole plot rather than anything the series need to know
  // about. Everything else is per item and is handled where the items are
  // drawn.
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

  if (e.type.isCircular) {
    paintCircular(canvas, area, e, showing);
  } else {
    paintCartesian(canvas, area, e, showing);
  }

  if (clipping) canvas.restore();

  // On top of everything, and only when they are floating.
  if (floating) {
    _placedLabel(
        canvas, rect, e.title, e.titleBox, defaultTitlePlacement, e.titleSpec);
    _placedLabel(
        canvas,
        rect,
        e.description,
        e.descriptionBox,
        defaultDescriptionPlacement(e.titleBox, e.title.isNotEmpty),
        descriptionSpec(e));
    if (e.showLegend && data.series.isNotEmpty) {
      _legend(canvas, rect, e, showing);
    }
  }
}

/// chartLabelPlaces is where a floating chart draws its three pieces of
/// writing, in the element's own coordinates.
///
/// Asked of the painter rather than worked out again by the stage, because
/// the stage has to hit-test exactly what was drawn -- and a legend's size is
/// decided by measuring its own text, which is not something to reimplement.
Map<ChartLabelPart, Rect> chartLabelPlaces(ChartElement e, Rect rect) {
  if (!e.floatingLabels) return const {};
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

/// descriptionSpec is the description's type: the label size, softened, so it
/// reads as a note under the title rather than as a second title.
TextSpec descriptionSpec(ChartElement e) => e.descriptionText.copyWith(
      color: e.descriptionText.color.withValues(alpha: 0.75),
      verticalAlign: VerticalAlignSpec.top,
    );

/// _flowLabel draws a label the chart is laying out itself, and returns what
/// is left below it. A hidden, empty or placed label takes no room and draws
/// nothing here.
Rect _flowLabel(ui.Canvas canvas, Rect area, Rect rect, String text,
    ChartLabel box, TextSpec spec) {
  if (!box.show || text.isEmpty) return area;
  // Against the top of what is left, always.
  //
  // The box handed to paintTextInBox is the whole remaining area, and a
  // TextSpec is vertically centred unless it says otherwise -- so the title
  // was drawn down the middle of the plot while the description, which did
  // say otherwise, sat at the top above it. A title under its own description,
  // over the bars.
  var h = paintTextInBox(
      canvas,
      text,
      spec.copyWith(verticalAlign: VerticalAlignSpec.top),
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      clip: true);
  return Rect.fromLTRB(
      area.left, area.top + h + rect.height * 0.02, area.right, area.bottom);
}

/// _placedLabel draws a label that has been moved, in its own box over
/// everything else.
void _placedLabel(ui.Canvas canvas, Rect rect, String text, ChartLabel box,
    ChartLabel fallback, TextSpec spec) {
  if (!box.show || text.isEmpty) return;
  // Where it was put, or where the chart would have put it. A label that has
  // never been dragged still has to land somewhere sensible the moment the
  // switch is thrown.
  paintTextInBox(canvas, text, spec, _placeOf(box, fallback, rect), clip: true);
}

/// _wedge is a pie slice from the top, for a sweep. A full turn is the whole
/// area, so the clip stops mattering exactly when the animation ends.
Path _wedge(Rect area, double turn) {
  if (turn >= 1) return Path()..addRect(area);
  var centre = area.center;
  // Long enough to reach any corner, so the wedge clips the whole rectangle
  // rather than a circle inscribed in it.
  var reach = area.longestSide;
  return Path()
    ..moveTo(centre.dx, centre.dy)
    ..lineTo(centre.dx, centre.dy - reach)
    ..arcTo(Rect.fromCircle(center: centre, radius: reach), -math.pi / 2,
        math.pi * 2 * turn.clamp(0.0, 1.0), false)
    ..close();
}

/// _placeholder is what an empty chart looks like: a labelled frame rather
/// than nothing, so a chart just dragged in is visible and selectable before
/// any numbers have been typed into it.
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

/// _legendEntries is what a legend has one line of: a colour and a name.
///
/// Series for the types drawn as series, and *categories* for the ones whose
/// colours belong to the values rather than to the series -- a pie of one
/// series has one entry naming that series and five slices nobody has a key
/// for, which is a legend answering a question nobody asked.
///
/// It is also where the radial bars get their numbers. They are rings a few
/// pixels thick with no room to write on and no axis to read against, so a
/// value written here is the only place it can go.
List<(Color, String)> _legendEntries(ChartElement e, double reveal) {
  var data = e.data;
  if (!colouredByValue(e.type)) {
    return [for (var s in data.series) (s.color, s.name)];
  }

  var values =
      data.series.isEmpty ? const <double>[] : data.series.first.values;
  return [
    for (var i = 0; i < values.length; i++)
      (
        sliceColour(e, i),
        _legendName(e, i, values[i], sliceProgress(e, reveal, i, values.length))
      ),
  ];
}

String _legendName(ChartElement e, int i, double value, SliceProgress slice) {
  var name = i < e.data.categories.length && e.data.categories[i].isNotEmpty
      ? e.data.categories[i]
      : "${i + 1}";
  // The key's own switch, not the chart's. A bar chart may well want numbers
  // on its bars and a key without them, and a radial bar has nowhere to put a
  // number except the key -- one switch answering both meant neither could be
  // had on its own.
  if (!e.legend.values) return name;
  // Counting with its ring, like every other number on an animating chart.
  return "$name${e.legend.separator}"
      "${formatTick(value * slice.size.clamp(0.0, 1.0))}";
}

/// legendEntriesForTest is [_legendEntries], which decides what a legend says
/// and is worth checking without reading it off a bitmap.
@visibleForTesting
List<(Color, String)> legendEntriesForTest(ChartElement e, double reveal) =>
    _legendEntries(e, reveal);

/// legendLeavesForTest is what the chart gets once the key has taken its
/// share -- which is the whole of what placement, direction, size and spacing
/// actually decide.
///
/// Asked of the layout rather than read off a bitmap, because the key's own
/// swatches are drawn in the series' colours: a test looking for "where the
/// blue starts" finds the swatch, not the bars.
@visibleForTesting
Rect legendLeavesForTest(ChartElement e, Rect area, {double reveal = 1}) =>
    _legend(ui.Canvas(ui.PictureRecorder()), area, e, reveal);

/// _LegendLayout is the key measured but not yet drawn: the rows it will take
/// and how much room they need.
///
/// Split out because three callers want it and only one of them draws --
/// where the chart goes, where the key goes, and what the stage must hit-test
/// are the same measurement asked three ways.
class _LegendLayout {
  final List<List<(Color, TextPainter)>> rows;
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

  // Down the side, the key gets a third of the width to wrap its names in;
  // along the top it gets all of it. Either way the width it *takes* is the
  // width it turns out to need.
  var room = legend.placement.isSide ? area.width * 0.34 : area.width;

  var items = [
    for (var (colour, name) in entries)
      (
        colour,
        layoutText(name, spec, maxWidth: math.max(1, room - swatch - gap))
      ),
  ];

  var rows = <List<(Color, TextPainter)>>[];
  var row = <(Color, TextPainter)>[];
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

/// _legendOrigin is the top left corner the key is drawn from.
Offset _legendOrigin(ChartElement e, Rect area, Size size) {
  // Dragged somewhere of its own, once the labels are floating.
  if (e.floatingLabels && e.legend.hasPlace) {
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

/// _legend draws the key and returns what is left for the chart.
///
/// Laid out by measuring rather than into a reserved margin, in whichever
/// direction it has been put, so a key of eleven names down the right takes
/// the width it needs and a key of two along the top takes one line.
Rect _legend(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var layout = _measureLegend(e, area, reveal);
  if (layout == null) return area;

  var origin = _legendOrigin(e, area, layout.size);
  var y = origin.dy;
  for (var r in layout.rows) {
    var x = origin.dx;
    for (var i = 0; i < r.length; i++) {
      if (i > 0) x += layout.between;
      var (colour, painter) = r[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y + (layout.rowHeight - layout.swatch) / 2,
                layout.swatch, layout.swatch),
            Radius.circular(layout.swatch * 0.25)),
        Paint()..color = colour,
      );
      painter.paint(
          canvas,
          Offset(x + layout.swatch + layout.gap * 0.6,
              y + (layout.rowHeight - painter.height) / 2));
      x += layout.swatch + layout.gap * 0.6 + painter.width;
    }
    y += layout.rowHeight + layout.rowGap;
  }

  // Floating, it takes no room at all -- that is what floating means.
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

  // Never all of it. A key given more room than the chart is a key with a
  // chart in the corner, and a key sized up until there is nothing left draws
  // over an empty rectangle rather than reporting an error nobody can act on.
  if (left.width < area.width * 0.35 || left.height < area.height * 0.35) {
    return area;
  }
  return left;
}

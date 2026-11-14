import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_circular.dart draws the types arranged round a centre: pie, donut,
// radial bars and radar.
//
// What they share with the legend (slice progress and colour) is in
// chart_common.dart.

/// paintCircular draws the pie, donut, radial-bar and radar types.
void paintCircular(ui.Canvas canvas, Rect area, ChartElement e, double reveal) {
  var side = math.min(area.width, area.height);
  var box = Rect.fromCenter(center: area.center, width: side, height: side)
      .deflate(side * 0.06);
  var centre = box.center;
  var radius = box.width / 2;
  var data = e.data;

  switch (e.type) {
    case ChartType.pie:
    case ChartType.donut:
      var values = data.series.first.values;
      var total = values.fold<double>(0, (t, v) => t + v.abs());
      if (total <= 0) return;
      var start = -math.pi / 2;
      // Names round the outside, where the legend does not have them (Ken,
      // 2026-11-14: names were only in the legend): room made for them.
      var named = e.showXLabels && !e.showLegend;
      if (named) radius *= 0.72;
      var inner = e.type == ChartType.donut ? radius * e.innerRadius : 0.0;
      var names = <(double, double, String, bool)>[];

      for (var i = 0; i < values.length; i++) {
        var sweep = values[i].abs() / total * math.pi * 2;
        var color = sliceColour(e, i);

        // Each slice opens out of the middle in turn. A sweep is the clip in
        // paintChart.
        var slice = sliceProgress(e, reveal, i, values.length);
        if (slice.gone) {
          start += sweep;
          continue;
        }
        var sliceRadius = radius * slice.size;
        var sliceInner = inner * slice.size;
        color = slice.tint(color);

        var path = Path()
          ..moveTo(centre.dx + math.cos(start) * sliceInner,
              centre.dy + math.sin(start) * sliceInner)
          ..lineTo(centre.dx + math.cos(start) * sliceRadius,
              centre.dy + math.sin(start) * sliceRadius)
          ..arcTo(Rect.fromCircle(center: centre, radius: sliceRadius), start,
              sweep, false);
        if (sliceInner > 0) {
          path.arcTo(Rect.fromCircle(center: centre, radius: sliceInner),
              start + sweep, -sweep, false);
        } else {
          path.lineTo(centre.dx, centre.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = color);

        if (e.showValues) {
          var mid = start + sweep / 2;
          var at = centre +
              Offset(math.cos(mid), math.sin(mid)) * (radius + inner) / 2;
          paintTextInBox(
              canvas,
              "${(values[i].abs() / total * 100 * slice.size.clamp(0.0, 1.0)).round()}%",
              e.valueSpec.copyWith(
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.middle),
              Rect.fromCenter(
                  center: at, width: radius, height: e.valueSpec.fontSize * 2));
        }
        if (named && i < data.categories.length && slice.size > 0.5) {
          var mid = start + sweep / 2;
          names.add((mid, sweep, data.categories[i], true));
        }
        start += sweep;
      }
      if (inner > 0 && e.centreLabel.trim().isNotEmpty) {
        paintCentreLabel(canvas, centre, inner, e, values, total, reveal);
      }
      if (named) _sliceNames(canvas, centre, radius, e, names);

    case ChartType.radialBar:
      // Bars bent round three quarters of a turn, to the chart's top value
      // or the largest: the quarter left over holds each bar's name at its
      // start, and its value follows its end (Ken, 2026-11-14: the largest
      // was a whole ring, and nothing said what any of them were).
      var values = data.series.first.values;
      var maxV = values.fold<double>(0, (m, v) => math.max(m, v.abs()));
      if (e.yMax.isFinite && e.yMax > 0) maxV = e.yMax;
      if (maxV <= 0) return;
      const most = math.pi * 1.5;
      var ring = radius * (1 - e.innerRadius) / math.max(1, values.length);
      var fs = e.valueSpec.fontSize;
      for (var i = 0; i < values.length; i++) {
        var r = radius - ring * i - ring / 2;
        var color = sliceColour(e, i);
        var slice = sliceProgress(e, reveal, i, values.length);
        if (slice.gone) continue;
        color = slice.tint(color);
        var track = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring * 0.7
          ..color = e.gridColor;
        var bounds = Rect.fromCircle(center: centre, radius: r);
        canvas.drawArc(bounds, -math.pi / 2, most, false, track);
        var share = (values[i].abs() / maxV).clamp(0.0, 1.0);
        var sweep = most * share * slice.size;
        canvas.drawArc(
            bounds,
            -math.pi / 2,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring * 0.7
              ..strokeCap = StrokeCap.round
              ..color = color);
        // Its name, to the left of where it starts -- where the legend
        // does not have it.
        if (e.showXLabels && !e.showLegend && i < data.categories.length) {
          var size = math.min(e.labelSpec.fontSize, ring * 0.75);
          paintTextInBox(
              canvas,
              data.categories[i],
              e.labelSpec.copyWith(
                  fontSize: size,
                  align: TextAlignSpec.right,
                  verticalAlign: VerticalAlignSpec.middle),
              Rect.fromLTRB(centre.dx - radius * 1.1, centre.dy - r - ring / 2,
                  centre.dx - ring * 0.5, centre.dy - r + ring / 2),
              clip: true);
        }
        // Its value, just past where it ends, counting up as it grows.
        if (e.showValues) {
          var size = math.min(fs, ring * 0.75);
          var past = sweep + (ring * 0.35 + size * 1.4) / r;
          var at = centre +
              Offset(math.cos(-math.pi / 2 + past),
                      math.sin(-math.pi / 2 + past)) *
                  r;
          paintTextInBox(
              canvas,
              formatTick(e, values[i] * slice.size.clamp(0.0, 1.0)),
              e.valueSpec.copyWith(
                  fontSize: size,
                  align: TextAlignSpec.center,
                  verticalAlign: VerticalAlignSpec.middle),
              Rect.fromCenter(center: at, width: size * 5, height: size * 1.6));
        }
      }

    case ChartType.waffle:
      // Ten rows of ten, filled a category at a time from the top left,
      // each square its category's colour; each square arriving in turn.
      var values = data.series.first.values;
      var shares = waffleCells(values);
      var cell = box.width / 10;
      var gap = cell * 0.12;
      var k = 0;
      for (var (i, n) in shares.indexed) {
        var colour = sliceColour(e, i);
        for (var j = 0; j < n && k < 100; j++, k++) {
          var slice = sliceProgress(e, reveal, k, 100);
          if (slice.gone) continue;
          var at =
              Offset(box.left + (k % 10) * cell, box.top + (k ~/ 10) * cell);
          var square = Rect.fromLTWH(at.dx, at.dy, cell, cell).deflate(gap / 2);
          square = Rect.fromCenter(
              center: square.center,
              width: square.width * slice.size,
              height: square.height * slice.size);
          canvas.drawRRect(
              RRect.fromRectAndRadius(square, Radius.circular(cell * 0.12)),
              Paint()..color = slice.tint(colour));
        }
      }

    case ChartType.radar:
      var axes = data.categories.length;
      if (axes < 3) return;
      var maxV = 0.0;
      for (var s in data.series) {
        for (var v in s.values) {
          maxV = math.max(maxV, v.abs());
        }
      }
      if (maxV <= 0) return;

      Offset spoke(int i, double frac) {
        var a = -math.pi / 2 + i * 2 * math.pi / axes;
        return centre + Offset(math.cos(a), math.sin(a)) * radius * frac;
      }

      var web = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = e.gridColor;
      // The rings are its grid, the spokes its axes and their names its
      // labels, each with the chart's own switch -- so radars laid over one
      // another can leave all that to the first (the privacy video drew the
      // web and the names five times over, doubled while one arrived).
      for (var ringIndex = 1; e.showGrid && ringIndex <= 4; ringIndex++) {
        var path = Path();
        for (var i = 0; i <= axes; i++) {
          var p = spoke(i % axes, ringIndex / 4);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, web);
      }
      // One scale up the twelve o'clock spoke, not a number at every corner,
      // which would overlap.
      if (e.showValues) {
        for (var ringIndex = 1; ringIndex <= 4; ringIndex++) {
          var at = spoke(0, ringIndex / 4);
          paintTextInBox(
              canvas,
              formatAxis(e, maxV * ringIndex / 4),
              e.valueSpec.copyWith(
                  align: TextAlignSpec.left,
                  verticalAlign: VerticalAlignSpec.middle),
              Rect.fromLTWH(
                  at.dx + e.valueSpec.fontSize * 0.35,
                  at.dy - e.valueSpec.fontSize,
                  e.valueSpec.fontSize * 5,
                  e.valueSpec.fontSize * 2));
        }
      }

      for (var i = 0; i < axes; i++) {
        if (e.showAxes) canvas.drawLine(centre, spoke(i, 1), web);
        if (!e.showXLabels) continue;
        paintTextInBox(
            canvas,
            data.categories[i],
            e.labelSpec.copyWith(
                align: TextAlignSpec.center,
                verticalAlign: VerticalAlignSpec.middle),
            Rect.fromCenter(
                center: spoke(i, 1.14),
                width: radius * 0.7,
                height: e.labelSpec.fontSize * 2));
      }

      for (var s = 0; s < data.series.length; s++) {
        // One shape per series: staggered by series, grown from the centre
        // -- or, in turn, each in its own share of the arrival.
        var slice = e.animation.seriesInTurn
            ? sliceProgress(
                e, seriesInTurnReveal(reveal, s, data.series.length), 0, 1)
            : sliceProgress(e, reveal, s, data.series.length);
        if (slice.gone) continue;

        var path = Path();
        for (var i = 0; i <= axes; i++) {
          var p = spoke(
              i % axes, data.valueAt(s, i % axes).abs() / maxV * slice.size);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        var colour = slice.tint(data.series[s].color);
        canvas.drawPath(
            path, Paint()..color = colour.withValues(alpha: colour.a * 0.28));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = data.series[s].widthOn(e.strokeWidth)
              ..color = colour);
      }

    default:
      break;
  }
}

/// paintCentreLabel writes a donut's centre label in its hole of [radius]:
/// "{total}" as the slices that have arrived added up, so the total counts
/// up as they open. Sized to the hole, in the values' type.
void paintCentreLabel(ui.Canvas canvas, Offset centre, double radius,
    ChartElement e, List<double> values, double total, double reveal) {
  var arrived = 0.0;
  for (var i = 0; i < values.length; i++) {
    var slice = sliceProgress(e, reveal, i, values.length);
    if (!slice.gone) arrived += values[i].abs() * slice.size.clamp(0.0, 1.0);
  }
  var words =
      e.centreLabel.replaceAll("{total}", e.numbers.format(arrived)).trim();
  var lines = words.split("\n");
  var longest = lines.fold<int>(1, (m, l) => math.max(m, l.length));
  var across = radius * 1.5;
  var size = math.min(radius * 0.7 / lines.length, across / (longest * 0.58));
  paintTextInBox(
      canvas,
      words,
      e.valueSpec.copyWith(
          fontSize: size,
          align: TextAlignSpec.center,
          verticalAlign: VerticalAlignSpec.middle),
      Rect.fromCenter(center: centre, width: across, height: radius * 1.5));
}

/// _sliceNames writes each slice's name outside the pie of [radius], on a
/// short line from the slice's middle, nudged apart where neighbours would
/// overlap: down the right for those on the right, the left for the left.
void _sliceNames(ui.Canvas canvas, Offset centre, double radius, ChartElement e,
    List<(double, double, String, bool)> names) {
  var spec = e.labelSpec;
  var fs = spec.fontSize;
  var line = Paint()
    ..strokeWidth = 1
    ..color = e.axisColor.withValues(alpha: 0.8);
  for (var right in [true, false]) {
    var side = [
      for (var n in names)
        if ((math.cos(n.$1) >= 0) == right) n,
    ]..sort((a, b) => math.sin(a.$1).compareTo(math.sin(b.$1)));
    var lastY = -double.infinity;
    for (var (mid, _, name, _) in side) {
      var edge = centre + Offset(math.cos(mid), math.sin(mid)) * radius;
      var elbow = centre + Offset(math.cos(mid), math.sin(mid)) * radius * 1.12;
      var y = math.max(elbow.dy, lastY + fs * 1.3);
      lastY = y;
      var x = right ? centre.dx + radius * 1.2 : centre.dx - radius * 1.2;
      canvas.drawLine(edge, Offset(elbow.dx, y), line);
      canvas.drawLine(Offset(elbow.dx, y), Offset(x, y), line);
      paintTextInBox(
          canvas,
          name,
          spec.copyWith(
              align: right ? TextAlignSpec.left : TextAlignSpec.right,
              verticalAlign: VerticalAlignSpec.middle),
          right
              ? Rect.fromLTWH(x + fs * 0.3, y - fs, radius * 1.4, fs * 2)
              : Rect.fromLTWH(
                  x - fs * 0.3 - radius * 1.4, y - fs, radius * 1.4, fs * 2));
    }
  }
}

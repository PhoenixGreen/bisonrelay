import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_common.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:flutter/painting.dart';

// chart_circular.dart draws the types arranged round a centre: pie, donut,
// radial bars and radar.
//
// They share almost nothing with the cartesian types beyond the animation --
// no axes, no plot rectangle, no ticks -- which is why they are their own
// file. What they do share is how far through its arrival each slice is, and
// that lives in chart_common.dart so the legend can ask the same question.

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
      var inner = e.type == ChartType.donut ? radius * e.innerRadius : 0.0;

      for (var i = 0; i < values.length; i++) {
        var sweep = values[i].abs() / total * math.pi * 2;
        var color = sliceColour(e, i);

        // Each slice opens out of the middle in turn. A sweep is handled by
        // the clip around the whole chart -- see paintChart -- so it is not
        // one of the cases here.
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
        start += sweep;
      }

    case ChartType.radialBar:
      var values = data.series.first.values;
      var maxV = values.fold<double>(0, (m, v) => math.max(m, v.abs()));
      if (maxV <= 0) return;
      var ring = radius * (1 - e.innerRadius) / math.max(1, values.length);
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
        canvas.drawCircle(centre, r, track);
        canvas.drawArc(
            Rect.fromCircle(center: centre, radius: r),
            -math.pi / 2,
            math.pi * 2 * (values[i].abs() / maxV) * slice.size,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring * 0.7
              ..strokeCap = StrokeCap.round
              ..color = color);
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
      for (var ringIndex = 1; ringIndex <= 4; ringIndex++) {
        var path = Path();
        for (var i = 0; i <= axes; i++) {
          var p = spoke(i % axes, ringIndex / 4);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, web);
      }
      // The scale, up the spoke that points at twelve o'clock.
      //
      // Not a number at every corner of every shape, which is where these
      // started: a radar of three series is thirty numbers scattered round a
      // ring, most of them sitting on a line or on each other. One scale on
      // one spoke is what the rings already mean, written down.
      if (e.showValues) {
        for (var ringIndex = 1; ringIndex <= 4; ringIndex++) {
          var at = spoke(0, ringIndex / 4);
          paintTextInBox(
              canvas,
              formatTick(maxV * ringIndex / 4),
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
        canvas.drawLine(centre, spoke(i, 1), web);
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
        // A radar has one shape per series, so it is staggered by series and
        // grows out of the centre -- the only direction a radar has.
        var slice = sliceProgress(e, reveal, s, data.series.length);
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
              ..strokeWidth = e.strokeWidth
              ..color = colour);
      }

    default:
      break;
  }
}

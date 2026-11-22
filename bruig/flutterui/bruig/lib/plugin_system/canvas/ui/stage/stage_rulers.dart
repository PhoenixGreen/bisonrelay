import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';

// stage_rulers.dart is the rulers along the page's edges: how deep a strip
// is, where each strip lies, the gap between their numbers, and how they
// are drawn, by the stage's painter or, over a page that scrolls, by a
// layer of their own. The strips come from one function, which pressing a
// ruler asks too, so what can be dragged from is what is seen.

/// rulerThickness is how deep a ruler strip is, in screen pixels.
const double rulerThickness = 18;

/// rulerStep picks the gap between numbered ticks: the smallest 1, 2, 5, 10
/// ... multiple of [every] (the grid's spacing, so each number has a grid
/// line under it) that leaves numbers about [wanted] pixels apart.
double rulerStep(double scale, double every, {double wanted = 80}) {
  if (!every.isFinite || every <= 0) every = 100;
  if (!scale.isFinite || scale <= 0) return every;

  var want = wanted / scale / every;
  if (want <= 1) return every;

  var magnitude = math.pow(10, (math.log(want) / math.ln10).floor()).toDouble();
  var norm = want / magnitude;
  var step = norm <= 1
      ? 1
      : norm <= 2
          ? 2
          : norm <= 5
              ? 5
              : 10;
  return every * step * magnitude;
}

/// RulerBands is where the four strips are drawn and hit-tested; null for an
/// edge that is switched off.
class RulerBands {
  final Rect? top;
  final Rect? left;
  final Rect? right;
  final Rect? bottom;

  const RulerBands({this.top, this.left, this.right, this.bottom});

  /// axisAt is the guide a press at [at] would make, or null off the rulers:
  /// side strips make upright lines, top and bottom ones level lines.
  GuideAxis? axisAt(Offset at) {
    if (left?.contains(at) ?? false) return GuideAxis.vertical;
    if (right?.contains(at) ?? false) return GuideAxis.vertical;
    if (top?.contains(at) ?? false) return GuideAxis.horizontal;
    if (bottom?.contains(at) ?? false) return GuideAxis.horizontal;
    return null;
  }
}

/// rulerBandsFor lays the strips against the page's edges, not the window's,
/// so the ruler sits beside what it measures; clamped inside the viewport
/// for a page zoomed to fill it.
RulerBands rulerBandsFor(Rect page, Size viewport, CanvasRulers rulers) {
  const t = rulerThickness;
  double x0 = page.left.clamp(0.0, math.max(0.0, viewport.width));
  double x1 = page.right.clamp(0.0, math.max(0.0, viewport.width));
  double y0 = page.top.clamp(0.0, math.max(0.0, viewport.height));
  double y1 = page.bottom.clamp(0.0, math.max(0.0, viewport.height));

  double down(double at) =>
      at.clamp(0.0, math.max(0.0, viewport.height - t)).toDouble();
  double across(double at) =>
      at.clamp(0.0, math.max(0.0, viewport.width - t)).toDouble();

  return RulerBands(
    top: rulers.top
        ? Rect.fromLTWH(x0, down(page.top - t), math.max(0.0, x1 - x0), t)
        : null,
    bottom: rulers.bottom
        ? Rect.fromLTWH(x0, down(page.bottom), math.max(0.0, x1 - x0), t)
        : null,
    left: rulers.left
        ? Rect.fromLTWH(across(page.left - t), y0, t, math.max(0.0, y1 - y0))
        : null,
    right: rulers.right
        ? Rect.fromLTWH(across(page.right), y0, t, math.max(0.0, y1 - y0))
        : null,
  );
}

/// paintStageRulers draws [rulers] along the edges of [page], inside a view
/// [size] across, numbered from the page's top-left (so they agree with the
/// X and Y fields) at [scale] pixels a unit of a [sheet] whose top-left is
/// at [origin], with a tick at every [gridSize] (the canvas's grid). Over a
/// page that scrolls, the stage calls it in a layer of its own, so rulers
/// stay at the window edges.
void paintStageRulers(Canvas canvas, Size size, CanvasRulers rulers,
    double gridSize, Size sheet, double scale, Offset origin, Rect page) {
  if (!rulers.drawn) return;
  var bands = rulerBandsFor(page, size, rulers);
  var step = rulerStep(scale, gridSize);

  var strip = Paint()..color = const Color(0xF01A1A1E);
  var edge = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x33FFFFFF);
  var tick = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x66FFFFFF);
  // The unnumbered ticks are the grid itself, fainter.
  var fine = Paint()
    ..strokeWidth = 1
    ..color = const Color(0x33FFFFFF);
  var minor = gridSize;
  var showFine = minor > 0 && minor < step && minor * scale >= 6;

  // The page starts at (0, 0) in document units, so its screen origin is
  // [origin]; transforming the frame's corner again would push every tick
  // off the page.
  var zero = origin;

  void number(double at, Offset where, {required bool vertical}) {
    // Shared and kept (see labelPainter): the same few numbers come round
    // on every repaint of the stage.
    var painter =
        labelPainter("${at.round()}", size: 8, colour: const Color(0xAAFFFFFF));
    if (vertical) {
      // Turned on its side, so the numbers read up the strip.
      canvas.save();
      canvas.translate(where.dx, where.dy);
      canvas.rotate(-math.pi / 2);
      painter.paint(canvas, Offset(-painter.width - 2, 0));
      canvas.restore();
    } else {
      painter.paint(canvas, where);
    }
  }

  for (var top in [true, false]) {
    var band = top ? bands.top : bands.bottom;
    if (band == null) continue;
    canvas.drawRect(band, strip);
    canvas.drawLine(Offset(band.left, top ? band.bottom : band.top),
        Offset(band.right, top ? band.bottom : band.top), edge);

    canvas.save();
    canvas.clipRect(band);
    // Only across the page, not the grey round it.
    if (showFine) {
      for (var i = 0; i * minor <= sheet.width; i++) {
        var x = zero.dx + i * minor * scale;
        canvas.drawLine(Offset(x, top ? band.bottom - 3 : band.top),
            Offset(x, top ? band.bottom : band.top + 3), fine);
      }
    }
    for (var i = 0; i * step <= sheet.width; i++) {
      var at = i * step;
      var x = zero.dx + at * scale;
      canvas.drawLine(Offset(x, top ? band.bottom - 6 : band.top),
          Offset(x, top ? band.bottom : band.top + 6), tick);
      number(at, Offset(x + 2, band.top + 3), vertical: false);
    }
    canvas.restore();
  }

  for (var left in [true, false]) {
    var band = left ? bands.left : bands.right;
    if (band == null) continue;
    canvas.drawRect(band, strip);
    canvas.drawLine(Offset(left ? band.right : band.left, band.top),
        Offset(left ? band.right : band.left, band.bottom), edge);

    canvas.save();
    canvas.clipRect(band);
    if (showFine) {
      for (var i = 0; i * minor <= sheet.height; i++) {
        var y = zero.dy + i * minor * scale;
        canvas.drawLine(Offset(left ? band.right - 3 : band.left, y),
            Offset(left ? band.right : band.left + 3, y), fine);
      }
    }
    for (var i = 0; i * step <= sheet.height; i++) {
      var at = i * step;
      var y = zero.dy + at * scale;
      canvas.drawLine(Offset(left ? band.right - 6 : band.left, y),
          Offset(left ? band.right : band.left + 6, y), tick);
      number(at, Offset(band.right - 3, y - 2), vertical: true);
    }
    canvas.restore();
  }
}

/// StageRulerLayer draws the rulers over a scrolling page, at the window's
/// edges: see paintStageRulers.
class StageRulerLayer extends CustomPainter {
  final CanvasRulers rulers;
  final double gridSize;
  final Size sheet;
  final double scale;
  final Offset origin;
  final Rect page;
  const StageRulerLayer(
      {required this.rulers,
      required this.gridSize,
      required this.sheet,
      required this.scale,
      required this.origin,
      required this.page});

  @override
  void paint(Canvas canvas, Size size) => paintStageRulers(
      canvas, size, rulers, gridSize, sheet, scale, origin, page);

  @override
  bool shouldRepaint(StageRulerLayer old) =>
      old.rulers != rulers ||
      old.gridSize != gridSize ||
      old.sheet != sheet ||
      old.scale != scale ||
      old.origin != origin ||
      old.page != page;
}

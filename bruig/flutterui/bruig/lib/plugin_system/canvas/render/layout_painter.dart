import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:flutter/painting.dart';

// layout_painter.dart draws a Layout (layout_element.dart): its gutters and
// margin, where it has a colour for them, then each cell -- its fill, a
// picture or pattern through it, and its border inside its edge. Cells are
// where layout_geometry.dart puts them. dockClip is a docked element's cell
// on the page, which the scene clips it to.

void paintLayout(ui.Canvas canvas, Rect box, LayoutElement e,
    {CanvasImageSource? images}) {
  var places = layoutPlaces(e, box);

  // What is round the cells: the box less every cell.
  if (e.gutterColor.a > 0) {
    var cells = Path();
    for (var p in places) {
      cells.addPath(p.path, Offset.zero);
    }
    var round =
        Path.combine(PathOperation.difference, Path()..addRect(box), cells);
    canvas.drawPath(round, Paint()..color = e.gutterColor);
  }

  for (var p in places) {
    paintLayoutCell(canvas, p, e.styleOf(p.cell), images);
  }
}

/// paintLayoutCell draws one cell in [style]: as a BoxSpec draws a box, but
/// cut to the cell's outline, whatever its shape.
void paintLayoutCell(
    ui.Canvas canvas, LayoutPlace p, BoxSpec style, CanvasImageSource? images) {
  var bounds = p.bounds;
  if (bounds.width <= 0 || bounds.height <= 0) return;
  var filled = PaintSpec(style.fill, gradient: style.fillFade);
  if (filled.shows) canvas.drawPath(p.path, filled.into(Paint(), bounds));
  if (style.painted.on) {
    paintThroughText(canvas, bounds, style.painted, images,
        () => canvas.drawPath(p.path, Paint()));
  }
  // The border inside the edge: twice as wide, clipped to the cell.
  var width = style.evenBorder ?? style.borderWidth;
  if (style.hasBorder && width > 0) {
    canvas.save();
    canvas.clipPath(p.path);
    canvas.drawPath(
        p.path,
        PaintSpec(style.borderColor, gradient: style.borderFade).into(
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = width * 2,
            bounds));
    canvas.restore();
  }
}

/// dockedCell is the layout and cell [e] is docked in among [elements],
/// or null where it is not docked, its layout has gone, or it breaks out.
(LayoutElement, LayoutPlace)? dockedCell(
    CanvasElement e, List<CanvasElement> elements) {
  if (e.base.dock.isEmpty || e.base.dockOut) return null;
  var dock = dockOf(e.base.dock);
  if (dock == null) return null;
  for (var l in elements) {
    if (l is LayoutElement && l.id == dock.$1) {
      var place = layoutPlaceOf(l, l.bounds, dock.$2);
      return place == null ? null : (l, place);
    }
  }
  return null;
}

/// dockClip is the outline [e] is drawn through on the page: its cell,
/// turned with its layout. Null where it is not clipped.
Path? dockClip(CanvasElement e, List<CanvasElement> elements) {
  var found = dockedCell(e, elements);
  if (found == null) return null;
  var (layout, place) = found;
  if (layout.rotation == 0) return place.path;
  var c = layout.bounds.center;
  var a = layout.rotation * math.pi / 180;
  var cs = math.cos(a), sn = math.sin(a);
  return place.path.transform(Float64List.fromList([
    cs, sn, 0, 0, //
    -sn, cs, 0, 0,
    0, 0, 1, 0,
    c.dx - cs * c.dx + sn * c.dy, c.dy - sn * c.dx - cs * c.dy, 0, 1,
  ]));
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/layout_presets.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show LiveMotion, MovedElement;
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:flutter/painting.dart';

// layout_painter.dart draws a Layout (layout_element.dart): its gutters and
// margin, where it has a colour for them, then each cell -- its fill, a
// picture or pattern through it, and its border inside its edge. Cells are
// where layout_geometry.dart puts them. dockClip is a docked element's cell
// on the page as the layout is drawn on the frame, which the scene clips it
// to.

/// paintLayout draws [e] in [box]: its gutters, where they have a colour,
/// then each cell.
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
    _paintLayoutCell(canvas, p, e.styleOf(p.cell), images);
  }
}

/// _paintLayoutCell draws one cell in [style]: as a BoxSpec draws a box, but
/// cut to the cell's outline, whatever its shape.
void _paintLayoutCell(
    ui.Canvas canvas, LayoutPlace p, BoxSpec style, CanvasImageSource? images) {
  var bounds = p.bounds;
  if (bounds.width <= 0 || bounds.height <= 0) return;
  var filled = PaintSpec(style.fill, gradient: style.fillFade);
  if (filled.shows) canvas.drawPath(p.path, filled.into(Paint(), bounds));
  if (style.painted.on) {
    paintThroughText(canvas, bounds, style.painted, images,
        () => canvas.drawPath(p.path, Paint()));
  }
  // The border inside the edge: twice as wide, clipped to the cell. One
  // width all round, as the panel sets it: sides saved apart are drawn at
  // the widest of them.
  var width = style.borders.widest;
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
/// or null where it is not docked, its layout has gone or is hidden, or it
/// breaks out.
(LayoutElement, LayoutPlace)? dockedCell(
    CanvasElement e, List<CanvasElement> elements) {
  if (e.base.dockOut) return null;
  var dock = e.base.docked;
  if (dock == null) return null;
  for (var l in elements) {
    if (l is LayoutElement && l.id == dock.layout) {
      // Hidden, it hides nothing: what is docked shows whole, to be moved
      // back inside its cell.
      if (!l.visible) return null;
      var place = layoutPlaceOf(l, l.bounds, dock.cell);
      return place == null ? null : (l, place);
    }
  }
  return null;
}

/// dockClip is the outline [e] is drawn through on the page: its cell where
/// the painter draws it, laid out by its layout's place on the frame
/// ([placeOf], as layoutFrameAt gives it). Null where it is not clipped.
Path? dockClip(CanvasElement e, List<CanvasElement> elements,
    ElementPlace Function(LayoutElement layout) placeOf) {
  var found = dockedCell(e, elements);
  if (found == null) return null;
  var (layout, place) = found;
  return LayoutFrame(layout, placeOf(layout)).pathOnPage(place.path);
}

/// layoutFrameAt is [layout] on the page on [frame] of [doc]: laid out by
/// the place the painter draws it by there, keys, clips and devices and all
/// (placeAt).
LayoutFrame layoutFrameAt(LayoutElement layout, int frame, CanvasDocument? doc,
        {LiveMotion? live}) =>
    LayoutFrame(layout, layout.placeAt(frame, doc, live: live));

/// _previewPage is the page a preset's preview is drawn on: dark, so
/// white gutters and light cards both show.
const _previewPage = Color(0xFF454C5C);

/// paintLayoutPreview draws preset [p] fitted in [size], laid out in a box
/// of [boxSize] (the layout it would replace) so its gutters and lines are
/// in the same proportion as they would be on the page -- that box held to
/// at most 700 across, where they would vanish in a small picture.
void paintLayoutPreview(ui.Canvas canvas, Size size, LayoutPreset p,
    {Size boxSize = const Size(1116, 1579)}) {
  if (size.isEmpty || boxSize.isEmpty) return;
  var shrink = math.min(1.0, 700 / math.max(boxSize.width, boxSize.height));
  var w = boxSize.width * shrink, h = boxSize.height * shrink;
  var e = layoutFrom(ElementBase(id: "preview", width: w, height: h), p);
  var fit = math.min((size.width - 6) / w, (size.height - 6) / h);
  canvas.save();
  canvas.translate((size.width - w * fit) / 2, (size.height - h * fit) / 2);
  canvas.scale(fit);
  var box = Rect.fromLTWH(0, 0, w, h);
  canvas.drawRect(box, Paint()..color = _previewPage);
  paintLayout(canvas, box, e);
  canvas.restore();
}

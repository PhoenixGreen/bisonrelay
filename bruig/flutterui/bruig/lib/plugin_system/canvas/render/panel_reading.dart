import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/layout_painter.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show settledFrameOf;
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/scene_sequence.dart'
    show paintLeaf;
import 'package:flutter/painting.dart';

// panel_reading.dart is Panel mode, a comic read panel by panel: each page
// seen whole, then each cell of its Layouts in their reading order
// (LayoutElement.reading), zoomed to fill the view with the rest of the
// page dimmed. The in-app reader (panel_reader.dart) and the EPUB's panel
// pages (document_export.dart) both draw through paintPanelView. Ken,
// 2026-11-18.

/// PanelStep is one stop: page [scene] seen whole ([cell] null), or one
/// cell of Layout [layout], [focus] its box on the page and [outline] its
/// edge.
class PanelStep {
  final int scene;
  final Rect focus;
  final String? layout, cell;
  final Path? outline;
  const PanelStep(this.scene, this.focus,
      {this.layout, this.cell, this.outline});

  bool get whole => cell == null;
}

/// panelSteps is every stop in [doc], page by page: each page whole, then
/// its Layouts' cells as they are read -- the Layouts top to bottom, left
/// to right, not one docked in another's cell (a diagram drawn as one), nor
/// a hidden one, nor a cell that is most of the page (the page whole
/// already shows it).
List<PanelStep> panelSteps(CanvasDocument doc) {
  var size = doc.size.size;
  var page = Offset.zero & size;
  var out = <PanelStep>[];
  for (var i = 0; i < doc.allScenes.length; i++) {
    out.add(PanelStep(i, page));
    var layouts = [
      for (var e in doc.allScenes[i].elements)
        if (e is LayoutElement && e.visible && e.base.dock.isEmpty) e
    ]..sort((a, b) =>
        (a.y - b.y).abs() > 40 ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    for (var l in layouts) {
      var places = {for (var p in layoutPlaces(l, l.bounds)) p.cell.id: p};
      for (var c in l.reading) {
        var place = places[c.id];
        if (place == null) continue;
        var outline = onPageOf(l, place.path);
        var focus = outline.getBounds().intersect(page);
        if (focus.width < 8 || focus.height < 8) continue;
        if (focus.width * focus.height >= 0.85 * size.width * size.height) {
          continue;
        }
        out.add(
            PanelStep(i, focus, layout: l.id, cell: c.id, outline: outline));
      }
    }
  }
  return out;
}

/// hasPanels is whether [doc] has a cell to read panel by panel.
bool hasPanels(CanvasDocument doc) => panelSteps(doc).any((s) => !s.whole);

/// panelView is the part of the page shown for [step]: its cell with a
/// little room round it, widened to the page's shape, kept on the page
/// where it fits so no edge of the page shows.
Rect panelView(PanelStep step, Size page) {
  var all = Offset.zero & page;
  if (step.whole || page.isEmpty) return all;
  var f = step.focus;
  var room = f.inflate(math.max(f.width, f.height) * 0.04);
  var aspect = page.width / page.height;
  var w = room.width, h = room.height;
  if (w / h > aspect) {
    h = w / aspect;
  } else {
    w = h * aspect;
  }
  double fit(double start, double length, double max) =>
      length >= max ? (max - length) / 2 : start.clamp(0.0, max - length);
  return Rect.fromLTWH(fit(room.center.dx - w / 2, w, page.width),
      fit(room.center.dy - h / 2, h, page.height), w, h);
}

/// panelDim is how dark the page round the panel being read is drawn.
const panelDim = Color(0xA8000000);

/// paintPanelView draws page [scene] of [doc] as it settles, its part
/// [view] filling [size], with the page outside each of [lit] dimmed by
/// its share (two while one panel gives way to the next).
void paintPanelView(
  ui.Canvas canvas,
  Size size,
  CanvasDocument doc,
  int scene,
  Rect view, {
  List<(Path, double)> lit = const [],
  CanvasImageSource? images,
}) {
  if (view.isEmpty || size.isEmpty) return;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  var scale = size.width / view.width;
  canvas.scale(scale, size.height / view.height);
  canvas.translate(-view.left, -view.top);
  paintLeaf(canvas, doc, scene,
      frameOf: (i) => settledFrameOf(doc.goToScene(i)), images: images);
  var round = Path()..addRect(view.inflate(4));
  for (var (outline, share) in lit) {
    if (share <= 0) continue;
    canvas.drawPath(Path.combine(PathOperation.difference, round, outline),
        Paint()..color = panelDim.withValues(alpha: panelDim.a * share));
  }
  canvas.restore();
}

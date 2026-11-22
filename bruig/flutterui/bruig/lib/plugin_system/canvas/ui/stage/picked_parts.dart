import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// picked_parts.dart is the parts picked inside one selected element (warp
// grid points, a text element's picture piece, a Layout's cell) and what the
// keys do to them, worked out from the controller alone. It is a library of
// its own so that the keys (stage_keys.dart) can reach these without
// importing the stage, which imports the keys.

/// chosenOf is the selection on the canvas: a timeline sound is selected
/// from its channel and has no box.
List<CanvasElement> chosenOf(CanvasController c) => [
      for (var e in c.selectedElements)
        if (!isTimelineSound(e)) e,
    ];

/// warpSpace maps the warp grid of layer [id] of [e] between fractions of
/// the picture's box and canvas points, and back, through the element's turn
/// and slant and the layer's turn and mirror.
(Offset Function(Offset), Offset Function(Offset)) warpSpace(
    ImageElement e, String id) {
  var layer = e.layerById(id) ?? ImageLayer.base;
  var space = LayerSpace(e, layer);
  var r = space.rect;
  Offset mirror(Offset f) =>
      Offset(layer.flipX ? 1 - f.dx : f.dx, layer.flipY ? 1 - f.dy : f.dy);
  Offset toDoc(Offset f) {
    var m = mirror(f);
    return space.fromLayer(r.topLeft + Offset(m.dx * r.width, m.dy * r.height));
  }

  Offset toFrac(Offset doc) {
    var l = space.toLayer(doc) - r.topLeft;
    return mirror(Offset(
        l.dx / math.max(1e-9, r.width), l.dy / math.max(1e-9, r.height)));
  }

  return (toDoc, toFrac);
}

/// nudgingWarp is whether the arrows move warp grid points: a picture's
/// grid is shown with points picked on it.
bool nudgingWarp(CanvasController c) =>
    c.editingImage != null && c.warpLayer != null && c.warpPicks.isNotEmpty;

/// nudgeWarpPicks moves the picked warp grid points by [by], in canvas units;
/// nothing unless nudgingWarp.
void nudgeWarpPicks(CanvasController c, Offset by) {
  var e = c.editingImage, id = c.warpLayer;
  if (e == null || id == null || c.warpPicks.isEmpty) return;
  var (toDoc, toFrac) = warpSpace(e, id);
  var picks = c.warpPicks;
  c.changeWarp((w) => w.withPoints([
        for (var (k, f) in w.grid.indexed)
          picks.contains(k) ? toFrac(toDoc(f) + by) : f
      ]));
}

/// pickedPiece is (element, index) when the one selected text element has a
/// picture piece picked in its Layers that the canvas can handle.
(TextElement, int)? pickedPiece(CanvasController c) {
  var chosen = chosenOf(c);
  if (chosen.length != 1) return null;
  var e = chosen.first;
  if (e is! TextElement || e.locked || e.curve != null) return null;
  var item = c.textLayer(e);
  if (item == null || !item.isIcon || item.hidden || item.locked) {
    return null;
  }
  if (!item.icon!.on) return null;
  var i = e.items.indexOf(item);
  return i < 0 ? null : (e, i);
}

/// removePickedPiece takes the picked picture piece out, as Delete does to a
/// picked element; nothing if none is picked (see pickedPiece).
void removePickedPiece(CanvasController c) {
  var piece = pickedPiece(c);
  if (piece == null) return;
  var (e, i) = piece;
  c.beginInteraction();
  c.replaceElement(e.copyWith(items: [
    for (var (n, it) in e.items.indexed)
      if (n != i) it,
  ]));
  c.endInteraction();
  c.pickTextLayer(e.id, null);
}

/// chosenLayout is the one selected Layout, unlocked, or null.
LayoutElement? chosenLayout(CanvasController c) {
  var chosen = chosenOf(c);
  if (chosen.length != 1) return null;
  var e = chosen.first;
  return e is LayoutElement && !e.locked ? e : null;
}

/// removableLayoutCell is the selected Layout's picked cell, when Delete
/// would take it out: not its last.
String? removableLayoutCell(CanvasController c) {
  var e = chosenLayout(c);
  if (e == null || e.shownCells.length < 2) return null;
  return c.layoutCell(e.id);
}

/// removePickedLayoutCell takes the selected Layout's picked cell out, as
/// Delete does; nothing if there is none to take (see removableLayoutCell).
void removePickedLayoutCell(CanvasController c) {
  var e = chosenLayout(c), id = removableLayoutCell(c);
  if (e == null || id == null) return;
  c.removeLayoutCell(e, id);
}

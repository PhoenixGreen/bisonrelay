import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/edge_mask.dart';
import 'package:flutter/painting.dart';

// edge_mask_painter.dart draws an EdgeMask: what is drawn in [paint] kept
// where the mask is solid and gone where it is clear.

/// paintEdgeMasked draws [paint] into [box] through [mask]: nothing of it
/// outside the box survives a mask, which is clear past its edges.
void paintEdgeMasked(
    ui.Canvas canvas, Rect box, EdgeMask mask, void Function() paint) {
  if (!mask.on || box.isEmpty) {
    paint();
    return;
  }
  canvas.saveLayer(box, Paint());
  paint();
  canvas.saveLayer(box, Paint()..blendMode = BlendMode.dstIn);
  _paintEdgeMask(canvas, box, mask);
  canvas.restore();
  canvas.restore();
}

/// _paintEdgeMask draws [mask] over [box]: white what is kept.
void _paintEdgeMask(ui.Canvas canvas, Rect box, EdgeMask mask) {
  var soft = mask.feather * box.shortestSide;
  // The soft edge: a rectangle drawn in from the box by the feather and
  // blurred out to it, so the box's edge is where it has all but gone.
  if (soft > 0.5) {
    canvas.drawRect(
        box.deflate(soft * 0.5),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, soft * 0.35));
  } else {
    canvas.drawRect(box, Paint()..color = const Color(0xFFFFFFFF));
  }
  if (mask.fade == EdgeFade.none) return;

  const clear = Color(0x00FFFFFF), solid = Color(0xFFFFFFFF);
  var r = mask.reach;
  ui.Shader shader;
  ui.Gradient across(
          Offset from, Offset to, List<Color> colours, List<double> stops) =>
      ui.Gradient.linear(from, to, colours, stops);
  switch (mask.fade) {
    case EdgeFade.left:
      shader = across(
          box.centerLeft, box.centerRight, [clear, solid], [0, math.min(1, r)]);
    case EdgeFade.right:
      shader = across(
          box.centerRight, box.centerLeft, [clear, solid], [0, math.min(1, r)]);
    case EdgeFade.top:
      shader = across(
          box.topCenter, box.bottomCenter, [clear, solid], [0, math.min(1, r)]);
    case EdgeFade.bottom:
      shader = across(
          box.bottomCenter, box.topCenter, [clear, solid], [0, math.min(1, r)]);
    case EdgeFade.sides:
      shader = across(box.centerLeft, box.centerRight,
          [clear, solid, solid, clear], [0, r / 2, 1 - r / 2, 1]);
    case EdgeFade.topBottom:
      shader = across(box.topCenter, box.bottomCenter,
          [clear, solid, solid, clear], [0, r / 2, 1 - r / 2, 1]);
    case EdgeFade.middle:
      // Whole in the middle, gone by the rim: an oval the box's shape.
      canvas.save();
      canvas.translate(box.center.dx, box.center.dy);
      canvas.scale(box.width / box.shortestSide, box.height / box.shortestSide);
      var radius = box.shortestSide / 2;
      shader = ui.Gradient.radial(
          Offset.zero, radius, [solid, clear], [math.max(0, 1 - r), 1]);
      canvas.drawRect(
          Rect.fromCircle(center: Offset.zero, radius: radius * 2),
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.dstIn);
      canvas.restore();
      return;
    case EdgeFade.none:
      return;
  }
  canvas.drawRect(
      box,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.dstIn);
}

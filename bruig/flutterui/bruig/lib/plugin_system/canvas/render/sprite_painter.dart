import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';

// sprite_painter.dart draws a Sprite element: the frame of its sheet its
// action has got to on the frame drawn, facing the way it faces -- see
// sprite_element.dart.

/// paintSprite draws [e] in [box] on [frame] of a canvas played at
/// [frameRate]: its frame as big as the box allows, standing on the box's
/// bottom, its pixels square when it is pixel art. A sprite with no sheet
/// yet -- or one still being read -- is a dashed outline of a figure.
void paintSprite(Canvas canvas, Rect box, SpriteElement e, int frame,
    {int frameRate = 12, CanvasImageSource? images}) {
  var image = e.hasSheet ? images?.resolve(e.sheet, const BackgroundRemoval()) : null;
  var at = e.sheetFrameAt(frame, frameRate);
  if (image == null || at == null) {
    _paintEmpty(canvas, box);
    return;
  }
  var (index, flipped) = at;
  var src = spriteSource(e, index, image);
  if (src.isEmpty) return;
  var dst = spriteFit(src.size, box);
  canvas.save();
  if (flipped) {
    canvas.translate(dst.center.dx, 0);
    canvas.scale(-1, 1);
    canvas.translate(-dst.center.dx, 0);
  }
  canvas.drawImageRect(image, src, dst,
      Paint()..filterQuality = e.pixelArt ? FilterQuality.none : FilterQuality.medium);
  canvas.restore();
}

/// spriteSource is where frame [index] of [e] is on [image]: as [e] slices
/// its sheet, scaled to the picture as stored -- a sheet stored smaller or
/// larger than it was measured is still sliced the same.
Rect spriteSource(SpriteElement e, int index, ui.Image image) {
  var r = e.frameRect(index);
  var sx = image.width / math.max(1, e.sheetW), sy = image.height / math.max(1, e.sheetH);
  return Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy)
      .intersect(Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
}

/// spriteFit is a frame [size] across fitted into [box], standing on its
/// bottom, in the middle across.
Rect spriteFit(Size size, Rect box) {
  var k = math.min(box.width / size.width, box.height / size.height);
  var w = size.width * k, h = size.height * k;
  return Rect.fromLTWH(box.center.dx - w / 2, box.bottom - h, w, h);
}

void _paintEmpty(Canvas canvas, Rect box) {
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, box.shortestSide * 0.012)
    ..color = const Color(0x998A8F99);
  // Dashes round the box.
  var path = Path()..addRRect(RRect.fromRectAndRadius(box.deflate(2), Radius.circular(box.shortestSide * 0.06)));
  for (var m in path.computeMetrics()) {
    var dash = box.shortestSide * 0.05;
    for (var d = 0.0; d < m.length; d += dash * 2) {
      canvas.drawPath(m.extractPath(d, d + dash), line);
    }
  }
  // A running figure, plainly drawn.
  var c = box.center, u = box.shortestSide * 0.1;
  var figure = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, u * 0.35)
    ..strokeCap = StrokeCap.round
    ..color = const Color(0x998A8F99);
  canvas.drawCircle(c + Offset(u * 0.4, -u * 1.9), u * 0.45, figure);
  canvas.drawLine(c + Offset(u * 0.2, -u * 1.3), c + Offset(-u * 0.2, u * 0.3), figure);
  canvas.drawPath(
      Path()
        ..moveTo(c.dx - u * 0.9, c.dy - u * 0.3)
        ..lineTo(c.dx + u * 0.1, c.dy - u * 1.0)
        ..lineTo(c.dx + u * 1.0, c.dy - u * 0.4),
      figure);
  canvas.drawPath(
      Path()
        ..moveTo(c.dx - u * 1.0, c.dy + u * 1.6)
        ..lineTo(c.dx - u * 0.2, c.dy + u * 0.3)
        ..lineTo(c.dx + u * 0.5, c.dy + u * 1.0)
        ..lineTo(c.dx + u * 0.4, c.dy + u * 1.8),
      figure);
}

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';

// sprite_painter.dart draws a Sprite element: the frame of its sheet its
// action has got to on the frame drawn, facing the way it faces -- see
// sprite_element.dart.

/// SpritePaintView is what the renderer needs to show a sprite being
/// painted: the frame, its pixels as they are now, the frame before it to
/// show faintly, and whether to rule the pixels. See sprite_painting.dart.
typedef SpritePaintView = ({int frame, ui.Image? live, int? onion, bool grid});

/// spritePaintingOf is how the sprite [SpriteElement] is shown while it is
/// painted in the editor, set by it; null for one not being painted.
SpritePaintView? Function(SpriteElement e)? spritePaintingOf;

/// paintSprite draws [e] in [box] on [frame] of a canvas played at
/// [frameRate]: its frame as big as the box allows, standing on the box's
/// bottom, its pixels square when it is pixel art. A sprite with no sheet
/// yet -- or one still being read -- is a dashed outline of a figure.
/// [editing], one being painted is shown as its painter shows it.
void paintSprite(Canvas canvas, Rect box, SpriteElement e, int frame,
    {int frameRate = 12, CanvasImageSource? images, bool editing = false}) {
  var image = e.hasSheet ? images?.resolve(e.sheet, const BackgroundRemoval()) : null;
  var view = editing ? spritePaintingOf?.call(e) : null;
  if (view != null) {
    var sheet = view.live ?? image;
    if (sheet != null) {
      _paintPainted(canvas, box, e, sheet, view);
      return;
    }
  }
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
  canvas.drawImageRect(image, src, dst, spritePaint(e));
  canvas.restore();
}

/// spritePaint is how [e]'s frames are laid on: square pixels or smooth,
/// tinted, and as light when it glows.
Paint spritePaint(SpriteElement e) {
  var p = Paint()..filterQuality = e.pixelArt ? FilterQuality.none : FilterQuality.medium;
  if (e.tint case var t?) p.colorFilter = ColorFilter.mode(t, BlendMode.modulate);
  if (e.glow) p.blendMode = BlendMode.screen;
  return p;
}

/// _paintPainted shows [e] being painted: the frame painted, still, on a
/// board of squares where it is clear, the frame before it faint under it,
/// and the pixels ruled where they are big enough to see.
void _paintPainted(Canvas canvas, Rect box, SpriteElement e, ui.Image sheet, SpritePaintView view) {
  var src = spriteSource(e, view.frame, sheet);
  if (src.isEmpty) return;
  var dst = spriteFit(src.size, box);
  canvas.save();
  canvas.clipRect(dst);
  var square = math.max(4.0, dst.width / math.max(1, src.width) * 2);
  var light = Paint()..color = const Color(0xFFF2F2F4), dark = Paint()..color = const Color(0xFFDADCE2);
  canvas.drawRect(dst, light);
  for (var y = 0; y * square < dst.height; y++) {
    for (var x = 0; x * square < dst.width; x++) {
      if ((x + y).isOdd) {
        canvas.drawRect(Rect.fromLTWH(dst.left + x * square, dst.top + y * square, square, square), dark);
      }
    }
  }
  canvas.restore();
  var pixel = Paint()..filterQuality = FilterQuality.none;
  if (view.onion case var before?) {
    canvas.drawImageRect(sheet, spriteSource(e, before, sheet), dst,
        Paint()
          ..filterQuality = FilterQuality.none
          ..color = const Color(0x55000000));
  }
  canvas.drawImageRect(sheet, src, dst, pixel);
  // Each pixel ruled, where one is big enough to see the lines between.
  var cell = dst.width / src.width;
  if (view.grid && cell >= 5) {
    var rule = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x22000000);
    for (var x = 1; x < src.width; x++) {
      canvas.drawLine(Offset(dst.left + x * cell, dst.top), Offset(dst.left + x * cell, dst.bottom), rule);
    }
    for (var y = 1; y < src.height; y++) {
      canvas.drawLine(Offset(dst.left, dst.top + y * cell), Offset(dst.right, dst.top + y * cell), rule);
    }
  }
  canvas.drawRect(
      dst,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x553D7EFF));
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

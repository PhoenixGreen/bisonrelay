import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

// stage_paint_retouch.dart is the retouching brush on a picture as the
// stage draws it: what a held stroke would do, and the stroke being drawn.
// Drawn from the retouching marks, in stage pixels: [scale] pixels to a
// document unit, the document's top-left at [origin].

/// paintRetouchMarks draws what a held stroke would do, then the stroke
/// being drawn over it.
void paintRetouchMarks(
    Canvas canvas, StageRetouchMarks retouch, double scale, Offset origin) {
  // What a held stroke would do, drawn from the brush's own output so
  // preview and result cannot drift apart (see strokePreview).
  if (retouch.preview case var preview?) {
    var to = preview.dst;
    canvas.drawImageRect(
        preview.image,
        preview.src,
        Rect.fromLTRB(
          to.left * scale + origin.dx,
          to.top * scale + origin.dy,
          to.right * scale + origin.dx,
          to.bottom * scale + origin.dy,
        ),
        Paint()..filterQuality = FilterQuality.medium);
  }

  // The stroke being drawn, inside the page clip, or it runs over the
  // sidebar when zoomed. A thick round-capped line, not a stamp per point,
  // reads the same as the dabbed brush at any speed.
  var liveStroke = retouch.stroke.value;
  if (liveStroke.length > 1 && retouch.radius > 0) {
    canvas.drawPath(
        lineOnScreen(liveStroke, scale, origin),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = retouch.radius * 2 * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = retouch.keeps
              ? const Color(0x6633DD88)
              : const Color(0x66FF5544));
  }
}

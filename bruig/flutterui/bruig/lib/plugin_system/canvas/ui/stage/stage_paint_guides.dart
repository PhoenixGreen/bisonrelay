import 'package:flutter/painting.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_paint_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter_inputs.dart';

// stage_paint_guides.dart is the grid, the guides and the line a drag is
// caught on, as the stage draws them over the page; the rulers along its
// edges are stage_rulers.dart. Drawn from the guides' marks and the page's
// size, in stage pixels: [scale] pixels to a document unit, the document's
// top-left at [origin].

/// paintGuideMarks draws the grid, guides and whatever a drag is caught on:
/// over the document, so a photograph cannot hide a guide, and under the
/// selection, so handles stay findable.
void paintGuideMarks(Canvas canvas, StageGuideMarks guides, Size docSize,
    double scale, Offset origin) {
  saveInDocument(canvas, scale, origin);

  // In document units. [page] is the frame on screen; adding its offset
  // would shift every guide with the window.
  var sheet = Offset.zero & docSize;
  var size = sheet.size;
  canvas.clipRect(sheet);
  // Hairlines: divided by the zoom, one pixel on screen at any zoom.
  var thin = 1 / scale;

  if (guides.inView && guides.canvas.showGrid) {
    var (majorX, minorX) = gridLines(
        size.width, guides.canvas.gridSize, guides.canvas.subdivisions);
    var (majorY, minorY) = gridLines(
        size.height, guides.canvas.gridSize, guides.canvas.subdivisions);
    var minor = Paint()
      ..strokeWidth = thin
      ..color = const Color(0x22FFFFFF);
    var major = Paint()
      ..strokeWidth = thin
      ..color = const Color(0x40FFFFFF);

    for (var x in minorX) {
      canvas.drawLine(Offset(sheet.left + x, sheet.top),
          Offset(sheet.left + x, sheet.bottom), minor);
    }
    for (var y in minorY) {
      canvas.drawLine(Offset(sheet.left, sheet.top + y),
          Offset(sheet.right, sheet.top + y), minor);
    }
    for (var x in majorX) {
      canvas.drawLine(Offset(sheet.left + x, sheet.top),
          Offset(sheet.left + x, sheet.bottom), major);
    }
    for (var y in majorY) {
      canvas.drawLine(Offset(sheet.left, sheet.top + y),
          Offset(sheet.right, sheet.top + y), major);
    }
  }

  if (guides.inView && guides.canvas.showGuides) {
    var paint = Paint()
      ..strokeWidth = thin
      ..color = const Color(0xAA35C4F0);
    for (var guide in guides.canvas.guides) {
      if (guide.axis == GuideAxis.vertical) {
        canvas.drawLine(Offset(sheet.left + guide.at, sheet.top),
            Offset(sheet.left + guide.at, sheet.bottom), paint);
      } else {
        canvas.drawLine(Offset(sheet.left, sheet.top + guide.at),
            Offset(sheet.right, sheet.top + guide.at), paint);
      }
    }
  }

  // What the drag has caught, in a colour nothing else uses.
  if (guides.snapped case var it? when it.caught) {
    var paint = Paint()
      ..strokeWidth = thin * 1.5
      ..color = const Color(0xFFFF4081);
    if (it.vertical case var x?) {
      canvas.drawLine(Offset(sheet.left + x, sheet.top),
          Offset(sheet.left + x, sheet.bottom), paint);
    }
    if (it.horizontal case var y?) {
      canvas.drawLine(Offset(sheet.left, sheet.top + y),
          Offset(sheet.right, sheet.top + y), paint);
    }
  }
  canvas.restore();
}

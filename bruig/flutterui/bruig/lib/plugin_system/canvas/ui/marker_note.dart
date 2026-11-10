import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart'
    show markerKindColours;
import 'package:flutter/material.dart';

// marker_note.dart is a marker's label on the canvas while playback holds
// at it (Ken, 2026-11-10): a stop's "Press Space to begin", a pause's "Get
// ready", where the marker says it is shown on the canvas. See
// CanvasController.holdingMarker.
//
// Drawn on the canvas itself, in its units, where the marker puts it
// (TimelineAction.noteAt and noteSize): it scales with the canvas as every
// element does, on a small screen as on a large one, and is dragged on the
// stage to move it, or by its corner to size it (Ken: "can't be moved or
// scaled on the canvas ... when the screen is small it covers the whole
// screen").

/// markerNoteHeight is the note's type size at size 1, as a share of the
/// canvas's height: 28 points on a 1080 canvas.
const double markerNoteHeight = 0.026;

/// MarkerNoteLayout is a marker's note laid out on a page: its box, and the
/// words in it.
class MarkerNoteLayout {
  final Rect box;
  final TextPainter text;
  final double radius;
  const MarkerNoteLayout(this.box, this.text, this.radius);

  /// corner is the grip that sizes it, at its bottom right.
  Rect get corner => Rect.fromCircle(
      center: box.bottomRight, radius: math.max(6.0, box.height * 0.35));
}

/// markerNoteLayout is where [a]'s note goes on a page [page] big: centred
/// on its place, as big as its size says.
MarkerNoteLayout markerNoteLayout(Size page, TimelineAction a) {
  var size = page.height * markerNoteHeight * a.noteSize;
  var text = TextPainter(
    text: TextSpan(
        text: a.label,
        style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF2F0FA))),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: page.width * 0.9);
  var padX = size * 1, padY = size * 0.5;
  var w = text.width + padX * 2, h = text.height + padY * 2;
  var centre = Offset(a.noteAt.dx * page.width, a.noteAt.dy * page.height);
  return MarkerNoteLayout(
      Rect.fromCenter(center: centre, width: w, height: h), text, h / 2);
}

/// paintMarkerNote draws [a]'s note on [canvas], in the page's own units, in
/// its kind's colour -- with its grip, [selected], for dragging.
void paintMarkerNote(Canvas canvas, Size page, TimelineAction a,
    {bool selected = false}) {
  var laid = markerNoteLayout(page, a);
  var colour = markerKindColours[a.kind]!;
  var r = RRect.fromRectAndRadius(laid.box, Radius.circular(laid.radius));
  canvas.drawRRect(r, Paint()..color = const Color(0xE6151320));
  canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, laid.box.height * 0.04)
        ..color = colour.withValues(alpha: 0.8));
  laid.text.paint(
      canvas,
      Offset(laid.box.center.dx - laid.text.width / 2,
          laid.box.center.dy - laid.text.height / 2));
  if (selected) {
    var grip = laid.corner;
    canvas.drawCircle(grip.center, grip.width / 2 * 0.6,
        Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
        grip.center,
        grip.width / 2 * 0.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, grip.width * 0.08)
          ..color = colour);
  }
}

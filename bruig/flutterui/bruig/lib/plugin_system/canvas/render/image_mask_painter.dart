import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:flutter/painting.dart';

// image_mask_painter.dart draws a picture's mask -- see image_mask.dart --
// with the compositor rather than with pixels.
//
// The mask is recorded once, in the picture's own pixels, as a picture of
// its own: the subject drawn as alpha, and every mark over it in order. It is
// then drawn through the same placement as the picture, as a layer whose
// blend keeps the picture only where the mask has something, with the edge
// refinements as filters on that layer. So it is as sharp as the canvas is
// drawn, whatever size the picture is, and redrawing it as a brush moves is
// the brush's new dabs and nothing more expensive.

/// _subjectAlpha turns a grey mask picture into alpha: white kept, black
/// gone, whatever colour -- the colour is never looked at, only the alpha.
const _subjectAlpha = ColorFilter.matrix([
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  0, 0, 0, 0, 255, //
  1, 0, 0, 0, 0, //
]);

class _Recorded {
  final ui.Image? subject;
  final Size size;
  final ui.Picture picture;
  _Recorded(this.subject, this.size, this.picture);
}

final Expando<_Recorded> _recorded = Expando("maskPicture");

/// maskPicture is [mask] recorded for a picture of [size] pixels, with
/// [subject] the decoded subject mask where it has one. Kept with the mask,
/// which never changes: a new mark is a new mask.
ui.Picture maskPicture(ImageMask mask, Size size, ui.Image? subject) {
  var kept = _recorded[mask];
  if (kept != null && kept.size == size && identical(kept.subject, subject)) {
    return kept.picture;
  }
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  var whole = Offset.zero & size;
  paintMaskMarks(canvas, mask, size, subject);
  if (mask.invert) {
    // White over the lot with xor leaves white where there was nothing and
    // nothing where there was white: the alpha turned over.
    canvas.drawRect(
        whole,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..blendMode = BlendMode.xor);
  }
  var picture = recorder.endRecording();
  _recorded[mask] = _Recorded(subject, size, picture);
  return picture;
}

/// paintMaskMarks draws [mask]'s subject and marks, as alpha, into a picture
/// of [size] pixels. Not inverted -- see maskPicture.
void paintMaskMarks(
    ui.Canvas canvas, ImageMask mask, Size size, ui.Image? subject) {
  var whole = Offset.zero & size;
  if (subject != null) {
    canvas.drawImageRect(
        subject,
        Offset.zero & Size(subject.width.toDouble(), subject.height.toDouble()),
        whole,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = _subjectAlpha);
  } else {
    canvas.drawRect(whole, Paint()..color = const Color(0xFFFFFFFF));
  }
  for (var mark in mask.marks) {
    paintMaskMark(canvas, mark, size);
  }
}

/// paintMaskMark draws one mark onto a mask of [size] pixels.
void paintMaskMark(ui.Canvas canvas, MaskMark mark, Size size) {
  if (mark.points.isEmpty) return;
  Offset at(Offset f) => Offset(f.dx * size.width, f.dy * size.height);
  // Each mark is laid down in a layer of its own: its strength is the
  // layer's, so a stroke's dabs build up to it and no further, and hiding
  // takes away from what is under the layer rather than painting black.
  canvas.saveLayer(
      null,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, mark.strength)
        ..blendMode = mark.hide ? BlendMode.dstOut : BlendMode.srcOver);
  var white = Paint()..color = const Color(0xFFFFFFFF);
  switch (mark.kind) {
    case MaskMarkKind.brush:
      _paintDabs(canvas, mark, size, at);
    case MaskMarkKind.lasso:
      if (mark.points.length >= 3) {
        canvas.drawPath(
            Path()..addPolygon([for (var p in mark.points) at(p)], true),
            white);
      }
    case MaskMarkKind.fade:
      if (mark.points.length >= 2) {
        var from = at(mark.points[0]), to = at(mark.points[1]);
        var shader = mark.radial
            // Whole in the middle, all of it done by the rim.
            ? ui.Gradient.radial(from, math.max(1, (to - from).distance),
                const [Color(0x00FFFFFF), Color(0xFFFFFFFF)])
            : ui.Gradient.linear(
                from, to, const [Color(0xFFFFFFFF), Color(0x00FFFFFF)]);
        // A gradient carries on as its end colours past its ends, so one
        // rectangle covers the lot: a line's hidden side wholly hidden, a
        // radial fade wholly hidden past its rim.
        canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      }
  }
  canvas.restore();
}

/// _paintDabs lays a brush stroke down as dabs along its path, each as wide
/// as the pen was pressed there.
void _paintDabs(
    ui.Canvas canvas, MaskMark mark, Size size, Offset Function(Offset) at) {
  var full = mark.radius * math.min(size.width, size.height);
  if (full <= 0) return;
  var soft = (1 - mark.hardness).clamp(0.0, 1.0);
  double pressureAt(int i) => mark.pressure.isEmpty
      ? 1
      : mark.pressure[math.min(i, mark.pressure.length - 1)];

  void dab(Offset c, double p) {
    // Lighter pressure is a thinner line, never less than a quarter of the
    // brush, which is where a pen's first touch starts.
    var r = full * (0.25 + 0.75 * p);
    var sigma = r * soft * 0.35;
    var paint = Paint()..color = const Color(0xFFFFFFFF);
    if (sigma > 0.3) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    canvas.drawCircle(c, math.max(0.5, r - sigma), paint);
  }

  var points = [for (var p in mark.points) at(p)];
  dab(points.first, pressureAt(0));
  for (var i = 1; i < points.length; i++) {
    var a = points[i - 1], b = points[i];
    var pa = pressureAt(i - 1), pb = pressureAt(i);
    var gap = math.max(0.5, full * (0.25 + 0.75 * math.min(pa, pb)) * 0.2);
    var length = (b - a).distance;
    var steps = (length / gap).ceil();
    for (var s = 1; s <= steps; s++) {
      var t = s / steps;
      dab(Offset.lerp(a, b, t)!, pa + (pb - pa) * t);
    }
  }
}

/// refineFilter is [refine] as filters on the layer the mask is drawn in,
/// with [scale] canvas units to a picture pixel. Null when there is nothing
/// to do.
ui.ImageFilter? refineFilter(MaskRefine refine, double scale) {
  var steps = <ui.ImageFilter>[];
  var shift = refine.shift * scale;
  if (shift > 0.05) {
    steps.add(ui.ImageFilter.dilate(radiusX: shift, radiusY: shift));
  } else if (shift < -0.05) {
    steps.add(ui.ImageFilter.erode(radiusX: -shift, radiusY: -shift));
  }
  if (refine.smooth > 0) {
    // Blurred and then pulled back to an edge: the jags are averaged away
    // and the edge stays where the average put it, as hard as it was.
    var s = refine.smooth * scale * 0.5;
    steps.add(
        ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.decal));
    steps.add(_alphaContrast(4));
  }
  if (refine.feather > 0) {
    var s = refine.feather * scale * 0.5;
    steps.add(
        ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.decal));
  }
  if (refine.contrast > 0) steps.add(_alphaContrast(1 + refine.contrast * 9));
  if (steps.isEmpty) return null;
  var filter = steps.first;
  for (var next in steps.skip(1)) {
    filter = ui.ImageFilter.compose(outer: next, inner: filter);
  }
  return filter;
}

/// _alphaContrast steepens alpha about half: a soft edge made harder.
ColorFilter _alphaContrast(double k) => ColorFilter.matrix([
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, k, 127.5 * (1 - k), //
    ]);

/// pictureToPlacement is the transform from a picture's own pixels onto the
/// canvas where [placement] draws it.
Matrix4Like pictureToPlacement(ImagePlacement placement) {
  var src = placement.src, dst = placement.dst;
  var sx = src.width == 0 ? 1.0 : dst.width / src.width;
  var sy = src.height == 0 ? 1.0 : dst.height / src.height;
  return (
    sx: sx,
    sy: sy,
    dx: dst.left - src.left * sx,
    dy: dst.top - src.top * sy
  );
}

typedef Matrix4Like = ({double sx, double sy, double dx, double dy});

/// paintMaskLayer draws [mask] as alpha where [placement] draws the picture,
/// with [blend] -- dstIn to keep a picture already drawn only where the mask
/// is, or anything else to see the mask itself.
void paintMaskLayer(ui.Canvas canvas, ImageMask mask, Size picture,
    ui.Image? subject, ImagePlacement placement,
    {BlendMode blend = BlendMode.dstIn, Rect? bounds}) {
  var m = pictureToPlacement(placement);
  var scale = math.min(m.sx.abs(), m.sy.abs());
  canvas.saveLayer(
      bounds,
      Paint()
        ..blendMode = blend
        ..imageFilter = refineFilter(mask.refine, scale));
  canvas.save();
  // Nothing of the mask past the part of the picture that is drawn -- a
  // crop's mask must not reach out over the frame.
  canvas.clipRect(placement.dst);
  canvas.translate(m.dx, m.dy);
  canvas.scale(m.sx, m.sy);
  canvas.drawPicture(maskPicture(mask, picture, subject));
  canvas.restore();
  canvas.restore();
}

import 'dart:collection';
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

/// _recorded is the masks last drawn, recorded, the most recently drawn
/// last.
///
/// It was kept on each mask, for as long as the mask lived -- and the undo
/// history keeps every mask there has been: a hundred strokes was a hundred
/// recordings, of one stroke, of two, ... of a hundred, every one of them
/// held. Only a mask being drawn needs its recording; a few are kept, for a
/// canvas with a few masked pictures on it.
final Map<ImageMask, _Recorded> _recorded = LinkedHashMap.identity();
const int _recordedMost = 16;

/// maskPicture is [mask] recorded for a picture of [size] pixels, with
/// [subject] the decoded subject mask where it has one. Kept with the mask,
/// which never changes: a new mark is a new mask.
ui.Picture maskPicture(ImageMask mask, Size size, ui.Image? subject) {
  var kept = _recorded.remove(mask);
  if (kept != null && kept.size == size && identical(kept.subject, subject)) {
    _recorded[mask] = kept;
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
  while (_recorded.length > _recordedMost) {
    _recorded.remove(_recorded.keys.first);
  }
  return picture;
}

/// _Rastered is a mask drawn into pixels: what it was drawn for, and them.
class _Rastered {
  final ui.Image? subject;
  final Size size;
  final Rect area;
  final ui.Image image;

  /// over is the part of the picture, in its own pixels, [image] covers.
  final Rect over;
  _Rastered(this.subject, this.size, this.area, this.image, this.over);
}

/// _rastered is the masks last drawn, as pixels, the most recently drawn
/// last -- let go of as they fall out.
final Map<ImageMask, _Rastered> _rastered = LinkedHashMap.identity();

/// _maskSide is the most a mask is drawn into across: a mask is an edge's
/// softness, not a photograph's detail.
const double _maskSide = 2048;

/// maskImage is [mask] for a picture of [size] pixels as pixels, white what
/// is kept, at most [_maskSide] across -- drawn once, then kept with the
/// mask -- cut to [area] of the picture (the part of it drawn: its crop) and
/// refined, with [over] the part of the picture, in its own pixels, the
/// image covers: the area and as far as the refining spreads past it.
///
/// Drawn as its recording on every frame instead, a mask was its every mark
/// again: a brush stroke is a soft dab at every step along it, each blurred
/// on its own, and a picture of six masked photographs was thousands of
/// them -- a second of the graphics card's time whenever it was drawn
/// anywhere but straight to the screen.
///
/// And refined here, in the picture's own pixels, not as a filter where it
/// is drawn: under a picture turned and drifting closer, the engine works a
/// filter at whole pixels of a place that moves a little every frame, and a
/// feathered or grown mask -- the picture it cuts out with it -- shook by a
/// pixel or two from frame to frame instead of gliding.
({ui.Image image, Rect over}) maskImage(
    ImageMask mask, Size size, ui.Image? subject,
    {Rect? area}) {
  area ??= Offset.zero & size;
  var kept = _rastered.remove(mask);
  if (kept != null &&
      kept.size == size &&
      kept.area == area &&
      identical(kept.subject, subject)) {
    _rastered[mask] = kept;
    return (image: kept.image, over: kept.over);
  }
  kept?.image.dispose();
  var r = mask.refine;
  var over = area.inflate(r.feather * 1.5 + r.smooth + r.shift.abs() + 2);
  var k = math.min(1.0, _maskSide / math.max(size.width, size.height));
  var w = math.max(1, (over.width * k).ceil());
  var h = math.max(1, (over.height * k).ceil());
  var recorder = ui.PictureRecorder();
  var canvas = ui.Canvas(recorder);
  // The refining in the raster's own pixels, k of the picture's.
  var refine = refineFilter(r, k);
  if (refine != null) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..imageFilter = refine);
  }
  canvas.scale(w / over.width, h / over.height);
  canvas.translate(-over.left, -over.top);
  // Nothing of the mask past the part of the picture that is drawn -- a
  // crop's mask must not reach out over the frame. A hard clip: a smoothed
  // one does not soften the mask along its edge, it softens how much of the
  // mask is applied there -- so the pixel the edge crossed kept part of the
  // picture whatever the mask said, a hairline round every faded picture.
  canvas.clipRect(area, doAntiAlias: false);
  canvas.drawPicture(maskPicture(mask, size, subject));
  if (refine != null) canvas.restore();
  var picture = recorder.endRecording();
  var image = picture.toImageSync(w, h);
  picture.dispose();
  _rastered[mask] = _Rastered(subject, size, area, image, over);
  while (_rastered.length > _recordedMost) {
    _rastered.remove(_rastered.keys.first)!.image.dispose();
  }
  return (image: image, over: over);
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
    // Past the picture's edges, as a fade's is -- see paintMaskMark.
    canvas.drawRect(_beyond(whole), Paint()..color = const Color(0xFFFFFFFF));
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
        // radial fade wholly hidden past its rim. Drawn past the picture's
        // edges: drawn to them, the half-covered pixel along each edge was
        // half hidden of a half-shown base -- a quarter of the picture left
        // showing, a hairline round every faded picture. The mask is clipped
        // to the picture where it is used.
        canvas.drawRect(_beyond(Offset.zero & size), Paint()..shader = shader);
      }
  }
  canvas.restore();
}

/// _beyond is [r] grown well past its edges, so nothing drawn to cover it
/// leaves a part-covered pixel along them.
Rect _beyond(Rect r) => r.inflate(math.max(4, r.longestSide * 0.01));

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
  // The layer only as large as the picture and as far as its edge is
  // softened past it: left unbounded, each masked picture's feathering was
  // a blur over everything it was drawn in, once a frame no longer cut its
  // layers to it.
  var r = mask.refine;
  var reach = (r.feather * 1.5 + r.smooth + r.shift.abs()) * scale + 2;
  canvas.saveLayer(
      bounds ?? placement.dst.inflate(reach), Paint()..blendMode = blend);
  canvas.translate(m.dx, m.dy);
  canvas.scale(m.sx, m.sy);
  // As pixels, cut to what is drawn and refined, once and kept: see
  // maskImage.
  var (:image, :over) = maskImage(mask, picture, subject, area: placement.src);
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      over,
      Paint()..filterQuality = FilterQuality.medium);
  canvas.restore();
}

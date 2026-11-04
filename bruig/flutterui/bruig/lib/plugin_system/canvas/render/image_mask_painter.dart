import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:flutter/painting.dart';

// image_mask_painter.dart draws a picture's mask (see image_mask.dart).
//
// The mask is recorded in the picture's own pixels (the subject as alpha,
// then every mark in order), rasterised and refined once (see maskImage),
// and drawn through the picture's placement as a layer whose blend keeps the
// picture only where the mask is.

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

/// _recorded is the recordings of the masks last drawn, most recent last.
/// A bounded cache rather than a field on the mask: undo history keeps every
/// mask there has been.
final Map<ImageMask, _Recorded> _recorded = LinkedHashMap.identity();
const int _recordedMost = 16;

/// maskPicture is [mask] recorded for a picture of [size] pixels, with
/// [subject] the decoded subject mask where it has one. Cached by mask
/// identity, which is safe because a new mark makes a new mask.
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
    // White with xor inverts the alpha.
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

/// _rastered is the masks last drawn, as pixels, most recent last; disposed
/// as they fall out.
final Map<ImageMask, _Rastered> _rastered = LinkedHashMap.identity();

/// _maskSide is the most a mask is drawn into across: a mask is an edge's
/// softness, not a photograph's detail.
const double _maskSide = 2048;

/// maskImage is [mask] for a picture of [size] pixels as pixels (white is
/// kept), at most [_maskSide] across, cut to [area] (the crop) and refined.
/// [over] is the part of the picture, in its own pixels, the image covers:
/// the area plus the refining's spread.
///
/// Rasterised once because replaying every blurred dab each frame is far too
/// slow. Refined here, in picture pixels, because a filter applied where a
/// moving picture is drawn snaps to whole screen pixels and the edge shakes.
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
  // Clipped to the drawn part, so a crop's mask does not reach over the
  // frame. A hard clip: an anti-aliased one leaves a hairline of picture
  // round every faded edge.
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
    // Past the picture's edges, as a fade is (see paintMaskMark).
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
  // A layer per mark: dabs build up to its strength and no further, and a
  // hiding mark removes alpha rather than painting black.
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
        // A gradient clamps past its ends, so one rectangle covers the lot.
        // Drawn past the picture's edges, or the half-covered edge pixels
        // leave a hairline; the mask is clipped where it is used.
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
    // Lighter pressure thins the line to a quarter of the brush at least.
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
    // Blurred, then hardened again: the jags are averaged away.
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
  // The layer bounded to the picture plus the refining's spread.
  var r = mask.refine;
  var reach = (r.feather * 1.5 + r.smooth + r.shift.abs()) * scale + 2;
  canvas.saveLayer(
      bounds ?? placement.dst.inflate(reach), Paint()..blendMode = blend);
  canvas.translate(m.dx, m.dy);
  canvas.scale(m.sx, m.sy);
  // See maskImage.
  var (:image, :over) = maskImage(mask, picture, subject, area: placement.src);
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      over,
      Paint()..filterQuality = FilterQuality.medium);
  canvas.restore();
}

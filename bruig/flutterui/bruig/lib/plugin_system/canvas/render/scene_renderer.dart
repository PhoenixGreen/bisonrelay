import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:flutter/painting.dart';

// scene_renderer.dart draws a whole document at one frame.
//
// It is the single place a canvas becomes pixels, and everything that shows a
// canvas goes through it: the editing stage, the sidebar's thumbnails, the PNG
// export, every frame of the GIF export, and a published interactive canvas
// being replayed inside a chat message. One renderer is what makes "what you
// see is what gets sent" true rather than aspirational -- two would drift, and
// the drift would only ever be discovered after something had been published.
//
// It draws in the document's own design coordinates and knows nothing about
// zoom, scroll, selection handles or the widget tree. The caller sets up
// whatever transform it wants first. That is also why it takes no
// BuildContext: the export runs with no widget tree at all.

/// CanvasImageSource hands the renderer decoded pictures.
///
/// An interface rather than a map because a picture may not be ready -- it is
/// decoded off the main thread, and a cut-out is recomputed when its settings
/// change. Returning null for "not yet" lets the renderer draw a placeholder
/// and the stage redraw a moment later, rather than either blocking a frame or
/// making the whole document wait on an image.
abstract class CanvasImageSource {
  /// resolve returns the picture for [assetId] with [removal] applied, or null
  /// when it is not decoded yet.
  ui.Image? resolve(String assetId, BackgroundRemoval removal);
}

/// paintCanvasDocument draws [doc] at [frame].
///
/// [hoveredButton] is the id of the button under the pointer, if any. It is
/// the one piece of interaction state the renderer takes, because a button's
/// hover colours are part of its design and have to be visible while they are
/// being chosen.
void paintCanvasDocument(
  ui.Canvas canvas,
  CanvasDocument doc, {
  int frame = 0,
  CanvasImageSource? images,
  String? hoveredButton,
}) {
  var rect = doc.size.rect;
  var time = frame / (doc.frameRate <= 0 ? 1 : doc.frameRate);

  _paintDocumentBackground(canvas, rect, doc, time, images);

  for (var element in doc.elements) {
    if (!element.visible) continue;
    paintElement(canvas, element, frame,
        frameRate: doc.frameRate,
        images: images,
        hovered: element.id == hoveredButton);
  }
}

void _paintDocumentBackground(ui.Canvas canvas, Rect rect, CanvasDocument doc,
    double time, CanvasImageSource? images) {
  var bg = doc.background;
  if (bg.isImage) {
    var image = images?.resolve(bg.imageAssetId, const BackgroundRemoval());
    if (image != null) {
      _drawImage(canvas, image, rect, bg.imageFit);
      return;
    }
    // Falling through to the generator while the picture decodes means the
    // canvas is never briefly blank, which on a dark document reads as the
    // whole design having disappeared.
  }
  paintProcedural(canvas, rect, bg.spec, time: time);
}

/// paintElement draws one element, with its animation pose applied.
void paintElement(
  ui.Canvas canvas,
  CanvasElement element,
  int frame, {
  int frameRate = 12,
  CanvasImageSource? images,
  bool hovered = false,
}) {
  var pose = element.track?.at(frame) ?? Keyframe.rest;
  var alpha = (element.opacity * pose.opacity).clamp(0.0, 1.0);
  if (alpha <= 0.002) return;

  var bounds = element.bounds;
  if (bounds.width <= 0 || bounds.height <= 0) return;

  canvas.save();

  // The pose's shift is applied in document space, then the rotation and the
  // scale about the element's own centre. In that order, so that an element
  // moved by a keyframe rotates about where it now is rather than swinging
  // around where it was drawn.
  if (pose.dx != 0 || pose.dy != 0) canvas.translate(pose.dx, pose.dy);

  var spin = element.rotationRadians + pose.rotate * math.pi / 180;
  if (spin != 0 || pose.scale != 1) {
    var c = bounds.center;
    canvas.translate(c.dx, c.dy);
    if (spin != 0) canvas.rotate(spin);
    if (pose.scale != 1) canvas.scale(pose.scale);
    canvas.translate(-c.dx, -c.dy);
  }

  var layered = alpha < 0.999;
  if (layered) {
    // Grown before saving the layer, because a shadow, an outline or a glow
    // reaches outside the element's own bounds and a layer clipped to them
    // would cut it off -- visible as a shadow that vanishes the moment an
    // element is faded.
    canvas.saveLayer(bounds.inflate(math.max(bounds.width, bounds.height)),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
  }

  var time = frame / (frameRate <= 0 ? 1 : frameRate);
  switch (element) {
    case TextElement e:
      _paintText(canvas, bounds, e);
    case ShapeElement e:
      _paintShape(canvas, bounds, e);
    case LineElement e:
      _paintLine(canvas, e);
    case ImageElement e:
      _paintImage(canvas, bounds, e, images);
    case ChartElement e:
      paintChart(canvas, bounds.deflate(bounds.shortestSide * 0.02), e);
    case TableElement e:
      paintTable(canvas, bounds, e);
    case ButtonElement e:
      _paintButton(canvas, bounds, e, hovered);
    case BackgroundElement e:
      _paintBackgroundElement(canvas, bounds, e, time);
    case TeamElement e:
      _paintTeam(canvas, bounds, e, frame);
    default:
      break;
  }

  if (layered) canvas.restore();
  canvas.restore();
}

// --------------------------------------------------------------------------

void _paintText(ui.Canvas canvas, Rect bounds, TextElement e) {
  paintBox(canvas, bounds, e.box);
  var inner = bounds.deflate(e.box.padding);
  if (inner.width <= 0 || inner.height <= 0) return;

  var spec = e.textSpec;
  if (e.autoSize) {
    spec = spec.copyWith(
        fontSize: fitFontSize(e.displayText, spec, inner.size));
  }
  paintTextInBox(canvas, e.displayText, spec, inner);
}

void _paintShape(ui.Canvas canvas, Rect bounds, ShapeElement e) {
  var rect = bounds;
  if (e.shape.isRegular) {
    var side = rect.shortestSide;
    rect = Rect.fromCenter(center: rect.center, width: side, height: side);
  }

  var path = shapePath(e.shape, rect,
      points: e.points, inner: e.innerRatio, cornerRadius: e.cornerRadius);

  if (e.fill.a > 0) canvas.drawPath(path, Paint()..color = e.fill);
  if (e.strokeWidth > 0 && e.strokeColor.a > 0) {
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = e.strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = e.strokeColor);
  }

  if (e.text.isNotEmpty) {
    // Inset to the largest rectangle comfortably inside the shape rather than
    // to its bounds, so a label in a circle or a triangle does not run out
    // over the edge. A crude fraction is right here: the alternative is
    // solving for the inscribed rectangle of an arbitrary path.
    var inset = switch (e.shape) {
      ShapeKind.circle || ShapeKind.ellipse => 0.15,
      ShapeKind.triangle => 0.24,
      ShapeKind.diamond || ShapeKind.star => 0.26,
      ShapeKind.pentagon || ShapeKind.hexagon => 0.16,
      _ => 0.06,
    };
    var box = rect.deflate(rect.shortestSide * inset);
    if (e.shape == ShapeKind.triangle) box = box.translate(0, rect.height * 0.1);
    paintTextInBox(canvas, e.textSpec.textCase.apply(e.text), e.textSpec, box);
  }
}

void _paintLine(ui.Canvas canvas, LineElement e) {
  var a = e.start, b = e.end;
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = e.strokeWidth
    ..color = e.color
    ..strokeCap = switch (e.cap) {
      LineCapStyle.round || LineCapStyle.dot => StrokeCap.round,
      LineCapStyle.square => StrokeCap.square,
      _ => StrokeCap.butt,
    };

  var path = Path()..moveTo(a.dx, a.dy);
  if (e.curvature == 0) {
    path.lineTo(b.dx, b.dy);
  } else {
    // The control point is pushed out perpendicular to the chord, so the bow
    // is symmetrical whichever way round the line runs.
    var mid = (a + b) / 2;
    var d = b - a;
    var len = d.distance;
    if (len > 0) {
      var normal = Offset(-d.dy / len, d.dx / len);
      var control = mid + normal * (len * e.curvature);
      path.quadraticBezierTo(control.dx, control.dy, b.dx, b.dy);
    } else {
      path.lineTo(b.dx, b.dy);
    }
  }

  canvas.drawPath(
      e.dash > 0 ? dashPath(path, e.dash, e.dash * 0.8) : path, paint);

  var angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  if (e.cap.hasEndArrow) {
    arrowHead(canvas, b, angle, e.strokeWidth * 3.5, paint);
  }
  if (e.cap.hasStartArrow) {
    arrowHead(canvas, a, angle + math.pi, e.strokeWidth * 3.5, paint);
  }
  if (e.cap == LineCapStyle.dot) {
    var dot = Paint()..color = e.color;
    canvas.drawCircle(a, e.strokeWidth * 1.1, dot);
    canvas.drawCircle(b, e.strokeWidth * 1.1, dot);
  }
}

void _paintImage(ui.Canvas canvas, Rect bounds, ImageElement e,
    CanvasImageSource? images) {
  paintBox(canvas, bounds, e.box);
  var inner = bounds.deflate(e.box.padding);
  if (inner.width <= 0 || inner.height <= 0) return;

  var image = e.hasImage ? images?.resolve(e.assetId, e.removal) : null;
  if (image == null) {
    _imagePlaceholder(canvas, inner, e);
    return;
  }

  canvas.save();
  if (e.box.borderRadius > 0) {
    canvas.clipRRect(RRect.fromRectAndRadius(
        inner, Radius.circular(math.max(0, e.box.borderRadius - e.box.padding))));
  } else {
    canvas.clipRect(inner);
  }
  _drawImage(canvas, image, inner, e.fit,
      tint: e.tint, saturation: e.saturation, brightness: e.brightness);
  canvas.restore();
}

void _imagePlaceholder(ui.Canvas canvas, Rect rect, ImageElement e) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(e.box.borderRadius)),
    Paint()..color = const Color(0x1AFFFFFF),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(e.box.borderRadius)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF),
  );
  paintTextInBox(
      canvas,
      e.hasImage ? "Loading…" : "No picture yet",
      TextSpec(
          fontSize: math.max(9, rect.shortestSide * 0.09),
          weight: 500,
          color: const Color(0xAAFFFFFF)),
      rect,
      clip: true);
}

/// _drawImage covers or contains [image] in [rect], with the colour
/// adjustments applied through a matrix rather than by touching the pixels.
void _drawImage(ui.Canvas canvas, ui.Image image, Rect rect, ImageFit fit,
    {Color tint = const Color(0x00000000),
    double saturation = 1,
    double brightness = 1}) {
  var src = Rect.fromLTWH(
      0, 0, image.width.toDouble(), image.height.toDouble());
  Rect dst;

  switch (fit) {
    case ImageFit.stretch:
      dst = rect;
    case ImageFit.contain:
      var scale = math.min(rect.width / src.width, rect.height / src.height);
      dst = Rect.fromCenter(
          center: rect.center,
          width: src.width * scale,
          height: src.height * scale);
    case ImageFit.cover:
      // Cover crops the source rather than overflowing the destination, so
      // the caller does not have to clip and an unclipped cover cannot spill
      // over its neighbours.
      var scale = math.max(rect.width / src.width, rect.height / src.height);
      var w = rect.width / scale, h = rect.height / scale;
      src = Rect.fromCenter(center: src.center, width: w, height: h);
      dst = rect;
  }

  var paint = Paint()..filterQuality = FilterQuality.high;
  if (saturation != 1 || brightness != 1) {
    paint.colorFilter = ColorFilter.matrix(_colorMatrix(saturation, brightness));
  }
  canvas.drawImageRect(image, src, dst, paint);

  if (tint.a > 0) {
    canvas.drawRect(dst, Paint()..color = tint..blendMode = BlendMode.modulate);
  }
}

/// _colorMatrix is saturation and brightness as one 4x5 filter.
///
/// The luminance weights are the usual perceptual ones -- desaturating with
/// equal thirds turns a red shirt and a blue shirt into the same grey, which
/// on a tactics diagram is the whole point of the two colours gone.
List<double> _colorMatrix(double sat, double bri) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  var s = sat.clamp(0.0, 4.0);
  var b = bri.clamp(0.0, 4.0);
  return [
    (lr + (1 - lr) * s) * b, (lg - lg * s) * b, (lb - lb * s) * b, 0, 0,
    (lr - lr * s) * b, (lg + (1 - lg) * s) * b, (lb - lb * s) * b, 0, 0,
    (lr - lr * s) * b, (lg - lg * s) * b, (lb + (1 - lb) * s) * b, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

void _paintButton(
    ui.Canvas canvas, Rect bounds, ButtonElement e, bool hovered) {
  var box = e.box;
  if (hovered && e.hoverFill.a > 0) box = box.copyWith(fill: e.hoverFill);
  paintBox(canvas, bounds, box);

  var spec = e.textSpec;
  if (hovered && e.hoverTextColor.a > 0) {
    spec = spec.copyWith(color: e.hoverTextColor);
  }
  var inner = bounds.deflate(e.box.padding);
  if (inner.width <= 0 || inner.height <= 0) return;
  paintTextInBox(canvas, spec.textCase.apply(e.label), spec, inner, clip: true);
}

void _paintBackgroundElement(
    ui.Canvas canvas, Rect bounds, BackgroundElement e, double time) {
  if (e.cornerRadius > 0) {
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(e.cornerRadius)));
  }
  paintProcedural(canvas, bounds, e.spec, time: time);
  if (e.cornerRadius > 0) canvas.restore();
}

/// _paintTeam draws every player in a team.
///
/// The players are laid out as fractions of the element's box, so this is
/// where "the team" becomes "eleven dots": the box is the region they occupy,
/// and moving, resizing or rotating it moves all of them together without any
/// player having been touched.
///
/// Drawn in list order, which is what Bring forward and Send to back move a
/// player through -- a striker overlapping a centre back needs one of them to
/// be on top, and which one is a choice.
void _paintTeam(ui.Canvas canvas, Rect bounds, TeamElement e, int frame) {
  var r = e.dotRadius;
  if (r <= 0) return;

  for (var i = 0; i < e.players.length; i++) {
    var spot = e.players[i];
    if (spot.hidden) continue;

    var c = Offset(bounds.left + spot.dx * bounds.width,
        bounds.top + spot.dy * bounds.height);

    // Each player carries their own keyframes, so a run is one player moving
    // while the rest of the team holds its shape. The offsets are in design
    // units on top of where the player lines up, which is why they survive the
    // team being moved or resized afterwards.
    var track = spot.track;
    if (track != null && !track.isEmpty) {
      var pose = track.at(frame);
      c = c.translate(pose.dx, pose.dy);
    }

    // The first player is the goalkeeper, and is the only one in a different
    // shirt. Everything else about them is the same, ring included.
    var fill = i == 0 ? e.keeperColor : e.playerColor;

    canvas.drawOval(
        Rect.fromCenter(center: c, width: e.dotWidth, height: e.dotHeight),
        Paint()..color = fill);

    if (e.ringWidth > 0 && e.outlineColor.a > 0) {
      canvas.drawOval(
          Rect.fromCenter(
              center: c,
              width: e.dotWidth - e.ringWidth,
              height: e.dotHeight - e.ringWidth),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = e.ringWidth
            ..color = e.outlineColor);
    }

    _paintPlayerLabels(canvas, e, spot, c, r);
  }
}

/// _paintPlayerLabels draws one player's number and name.
///
/// Both use the team's single [TeamElement.labelSpec] and rotate together --
/// they are one piece of lettering that happens to be in two places, and
/// having had two specs meant a team's names could end up in a different face
/// from its numbers without anybody having chosen that.
void _paintPlayerLabels(
    ui.Canvas canvas, TeamElement e, PlayerSpot spot, Offset c, double r) {
  var rotate = e.labelRotation * math.pi / 180;

  if (e.showNumbers && spot.number.isNotEmpty) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (rotate != 0) canvas.rotate(rotate);
    // Centred on the ink rather than on the line box -- see
    // paintCentredGlyphs. A digit centred by its box sits high in the circle,
    // because the box reserves room for a descender the digit does not have.
    paintCentredGlyphs(canvas, spot.number, e.labelSpec, Offset.zero);
    canvas.restore();
  }

  if (!e.showNames ||
      spot.name.isEmpty ||
      e.namePosition == LabelPosition.none) {
    return;
  }

  var spec = e.labelSpec;
  var painter = layoutText(spec.textCase.apply(spot.name), spec,
      maxWidth: math.max(40, r * 8));
  // Placed from the dot's edge rather than from the element's bounds, so a
  // name stays the same distance from its player whatever the dot's size --
  // which is what makes changing the size of every dot on a pitch not also
  // require moving every name.
  var gapX = e.dotWidth / 2 + e.nameGap;
  var gapY = e.dotHeight / 2 + e.nameGap;
  var half = Offset(painter.width / 2, painter.height / 2);

  var at = switch (e.namePosition) {
    LabelPosition.above => c.translate(0, -gapY - half.dy),
    LabelPosition.below => c.translate(0, gapY + half.dy),
    LabelPosition.left => c.translate(-gapX - half.dx, 0),
    LabelPosition.right => c.translate(gapX + half.dx, 0),
    LabelPosition.none => c,
  };

  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (rotate != 0) canvas.rotate(rotate);
  if (spec.outlineWidth > 0) {
    layoutText(spec.textCase.apply(spot.name), spec,
            maxWidth: math.max(40, r * 8), outline: true)
        .paint(canvas, -half);
  }
  painter.paint(canvas, -half);
  canvas.restore();
}


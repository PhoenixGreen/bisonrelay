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
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
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
  bool editing = false,

  /// skipElement is left out of the drawing. The editor exists for one case --
  /// a text element being typed into has a real text field over it, and
  /// painting the words underneath as well shows the sentence twice.
  String? skipElement,
}) {
  var rect = doc.size.rect;
  var time = frame / (doc.frameRate <= 0 ? 1 : doc.frameRate);

  _paintDocumentBackground(canvas, rect, doc, time, images);

  // Lines that are only there to carry somebody's text, and have been asked to
  // stay out of the picture. Collected first because the text that hides a line
  // may be drawn after it.
  var hidden = <String>{
    for (var e in doc.elements)
      if (e is TextElement && e.curve?.hideHost == true) e.curve!.elementId,
  };

  for (var element in doc.elements) {
    if (!element.visible ||
        element.id == skipElement ||
        hidden.contains(element.id)) {
      continue;
    }
    paintElement(canvas, element, frame,
        frameRate: doc.frameRate,
        images: images,
        editing: editing,
        document: doc,
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

  /// editing is true on the stage and false everywhere a document is turned
  /// into a file. Only a guide path reads it -- see _paintPath.
  bool editing = false,

  /// document is needed only by text that has been attached to a line, which
  /// has to go and find it. Null elsewhere -- a thumbnail of one element has
  /// no document to look in, and text on a curve simply falls back to its own
  /// box there.
  CanvasDocument? document,
}) {
  var pose = element.track?.at(frame) ?? Keyframe.rest;
  var alpha = (element.opacity * pose.opacity).clamp(0.0, 1.0);
  if (alpha <= 0.002) return;

  var bounds = element.bounds;
  if (bounds.width <= 0 || bounds.height <= 0) return;

  // Text riding a line has no transform of its own. Where it is, how it is
  // turned and how big it is are all the line's to decide -- that is the whole
  // point of attaching it -- so applying the element's own position and angle
  // on top moved the words off the line they were supposed to be on, and
  // turned them independently of it.
  //
  // The fade is kept: an entrance is a property of the text rather than of the
  // line it happens to be sitting on.
  if (element is TextElement && _curveFor(element, document, frame) != null) {
    canvas.saveLayer(
        null,
        Paint()
          ..color =
              const Color(0xFF000000).withValues(alpha: alpha.toDouble()));
    _paintText(canvas, bounds, element, document, pose: pose, frame: frame);
    canvas.restore();
    return;
  }

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
      _paintText(canvas, bounds, e, document, pose: pose, frame: frame);
    case ShapeElement e:
      _paintShape(canvas, bounds, e);
    case LineElement e:
      _paintLine(canvas, _bowed(e, pose));
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
    case PathElement e:
      _paintPath(canvas, bounds, e, editing);
    case TeamElement e:
      _paintTeam(canvas, bounds, e, frame);
    default:
      break;
  }

  if (layered) canvas.restore();
  canvas.restore();
}

// --------------------------------------------------------------------------

void _paintText(ui.Canvas canvas, Rect bounds, TextElement e,
    CanvasDocument? doc,
    {Keyframe pose = Keyframe.rest, int frame = 0}) {
  // Text on a curve has no box of its own to fill or frame: it belongs to the
  // line it is riding, and drawing its rectangle behind the line would be a
  // panel nobody asked for sitting across the design.
  var curve = _curveFor(e, doc, frame);
  if (curve != null) {
    // A keyframe may be sliding the words along the line -- see
    // KeyframeChannel.slide. Absolute rather than an offset, because a
    // position along a line has no resting value to be measured from.
    var on = e.curve!;
    var slide = pose.values[KeyframeChannel.slide];
    paintTextOnPath(canvas, e.displayText, e.textSpec, curve,
        slide == null ? on : on.copyWith(offset: slide));
    return;
  }

  paintBox(canvas, bounds, e.box);
  var inner = bounds.deflate(e.box.padding);
  if (inner.width <= 0 || inner.height <= 0) return;

  var spec = e.textSpec;
  if (e.autoSize) {
    // Measured against one column rather than the whole box, or a headline set
    // in two columns is sized to fill a width it will never be given.
    var column = Size(e.columns.columnWidth(inner.width), inner.height);
    spec = spec.copyWith(fontSize: fitFontSize(e.displayText, spec, column));
  }

  if (e.columns.isSingle) {
    paintTextInBox(canvas, e.displayText, spec, inner);
    return;
  }
  paintTextInColumns(canvas, e.displayText, spec, inner, e.columns);
}

/// lineWithPose is [e] with whatever its keyframes say about its bow on
/// [frame], so the hit test catches the curve where it is drawn.
LineElement lineWithPose(LineElement e, int frame) => _bowed(e, e.poseAt(frame));

/// _bowed applies a keyed curvature to a line. See KeyframeChannel.bow.
LineElement _bowed(LineElement e, Keyframe pose) {
  var bow = pose.values[KeyframeChannel.bow];
  return bow == null ? e : e.copyWith(curvature: bow);
}

/// curveOfElement is [element]'s own line as a polyline in document space, or
/// null when it has none.
///
/// Public because the stage needs it to hit-test: a curved line or path bows
/// *outside* its own bounding box, so clicking where the stroke visibly is
/// missed the element and clicking a corner of the empty box selected it. The
/// renderer already knows how to walk one, and two answers to "where is this
/// curve" would be one answer too many.
List<Offset>? curveOfElement(CanvasElement element) {
  var points = _curvePoints(element);
  if (points == null) return null;
  return _rotatedWith(element, points);
}

/// curveUnderText is the line a text element is riding, in document space.
List<Offset>? curveUnderText(TextElement e, CanvasDocument? doc, int frame) =>
    _curveFor(e, doc, frame);

/// _rotatedWith turns [points] about [host]'s centre, the way the painter
/// turns the host itself.
List<Offset> _rotatedWith(CanvasElement host, List<Offset> points) {
  if (host.rotation == 0) return points;
  var centre = host.center;
  var cos = math.cos(host.rotationRadians);
  var sin = math.sin(host.rotationRadians);
  return [
    for (var p in points)
      Offset(
        centre.dx + (p.dx - centre.dx) * cos - (p.dy - centre.dy) * sin,
        centre.dy + (p.dx - centre.dx) * sin + (p.dy - centre.dy) * cos,
      ),
  ];
}

/// _curveFor is the line a text element is riding, as a list of points in
/// document space, or null when it is an ordinary paragraph.
///
/// Named rather than copied, so moving or reshaping the line carries its text
/// with it. A curve that has been deleted since simply stops being found, and
/// the text falls back to its own box -- which is visible and fixable, where
/// vanishing would not be.
List<Offset>? _curveFor(TextElement e, CanvasDocument? doc, int frame) {
  var on = e.curve;
  if (on == null || doc == null) return null;
  var host = doc.elementById(on.elementId);
  // The host's own keyframes count: a line whose bow is animated has to carry
  // its text through the bend rather than leaving it on the shape the line had
  // at frame zero.
  if (host is LineElement) host = _bowed(host, host.poseAt(frame));
  var points = _curvePoints(host);
  if (points == null) return null;

  // Turned with the line, about the line's own centre -- the same transform
  // the painter applies when it draws it. Without this, changing a line's
  // angle moved the line and left its text lying flat where the line used to
  // be, which is the one thing attaching text to a line is supposed to prevent.
  return _rotatedWith(host!, points);
}

/// _curvePoints is the host's line as a polyline in its own unrotated
/// coordinates.
List<Offset>? _curvePoints(CanvasElement? host) {
  if (host is PathElement && host.nodes.length >= 2) {
    return [
      for (var i = 0; i < host.segments; i++)
        for (var step = 0; step <= _curveSamplesPerSegment; step++)
          if (i == 0 || step > 0)
            host.pointOnSegment(i, step / _curveSamplesPerSegment),
    ];
  }
  if (host is LineElement) {
    // A line's own curvature is a quadratic bow between its ends, so it is
    // sampled rather than taken as two points -- otherwise text on a bent line
    // runs straight through the bend.
    var a = host.start, b = host.end;
    if (host.curvature == 0) return [a, b];
    var mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    var normal = Offset(-(b.dy - a.dy), b.dx - a.dx);
    var length = normal.distance;
    var control = length == 0
        ? mid
        : mid + normal / length * (host.curvature * (b - a).distance);
    return [
      for (var i = 0; i <= _curveSamplesPerSegment * 2; i++)
        _quadratic(a, control, b, i / (_curveSamplesPerSegment * 2)),
    ];
  }
  return null;
}

/// _curveSamplesPerSegment is how finely a curve is walked when text is placed
/// along it. Sixteen a segment keeps the letters on the line at any size a
/// canvas is exported at, without turning a paragraph into thousands of points.
const int _curveSamplesPerSegment = 16;

Offset _quadratic(Offset a, Offset control, Offset b, double t) {
  var u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
    u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
  );
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

/// _paintPath draws a bezier curve.
///
/// A path whose job is to describe a movement is scaffolding rather than
/// artwork, so [PathElement.guide] leaves it out of anything published while
/// keeping it on screen while the document is being worked on. That is what
/// [editing] is for -- the exporter passes false, the stage passes true, and
/// neither has to know why.
void _paintPath(ui.Canvas canvas, Rect bounds, PathElement e, bool editing) {
  if (e.nodes.length < 2) return;
  if (e.guide && !editing) return;

  var path = ui.Path();
  Offset at(PathNode n) =>
      Offset(bounds.left + n.x * bounds.width, bounds.top + n.y * bounds.height);
  Offset handle(PathNode n, double dx, double dy) => Offset(
      bounds.left + (n.x + dx) * bounds.width,
      bounds.top + (n.y + dy) * bounds.height);

  path.moveTo(at(e.nodes.first).dx, at(e.nodes.first).dy);
  for (var i = 0; i < e.segments; i++) {
    var a = e.nodes[i % e.nodes.length];
    var b = e.nodes[(i + 1) % e.nodes.length];
    var c1 = a.outDx == 0 && a.outDy == 0 ? at(a) : handle(a, a.outDx, a.outDy);
    var c2 = b.inDx == 0 && b.inDy == 0 ? at(b) : handle(b, b.inDx, b.inDy);
    var end = at(b);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  }
  if (e.closed) path.close();

  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = e.strokeWidth
    ..strokeCap = switch (e.cap) {
      LineCapStyle.round || LineCapStyle.dot => StrokeCap.round,
      LineCapStyle.square => StrokeCap.square,
      _ => StrokeCap.butt,
    }
    ..color = e.color;

  canvas.drawPath(e.dash > 0 ? dashPath(path, e.dash, e.dash) : path, paint);

  // The arrowhead points along the last segment's own direction rather than at
  // the straight line between the last two nodes, which on a curve that
  // doubles back would point roughly backwards.
  if (e.cap.hasEndArrow && !e.closed) {
    var last = e.segments - 1;
    var tip = e.pointOnSegment(last, 1);
    var just = e.pointOnSegment(last, 0.94);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
  if (e.cap.hasStartArrow && !e.closed) {
    var tip = e.pointOnSegment(0, 0);
    var just = e.pointOnSegment(0, 0.06);
    var shift = Offset(bounds.left - e.x, bounds.top - e.y);
    _paintArrowHead(canvas, just + shift, tip + shift, e.strokeWidth, e.color);
  }
}

/// _paintArrowHead draws a solid head at [tip], pointing away from [from].
void _paintArrowHead(
    ui.Canvas canvas, Offset from, Offset tip, double width, Color color) {
  var direction = tip - from;
  if (direction.distance < 0.001) return;
  var angle = math.atan2(direction.dy, direction.dx);
  var size = math.max(6.0, width * 3);
  var head = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - size * math.cos(angle - 0.4),
        tip.dy - size * math.sin(angle - 0.4))
    ..lineTo(tip.dx - size * math.cos(angle + 0.4),
        tip.dy - size * math.sin(angle + 0.4))
    ..close();
  canvas.drawPath(head, Paint()..color = color);
}

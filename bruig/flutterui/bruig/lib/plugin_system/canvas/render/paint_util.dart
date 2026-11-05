import 'package:bruig/plugin_system/canvas/render/image_look.dart';
import 'package:bruig/components/paint_spec.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart'
    show CanvasImageSource;
import 'package:bruig/plugin_system/canvas/render/text_animator.dart';
import 'package:flutter/painting.dart';

// paint_util.dart is the drawing every element does the same way: laying out
// a string, filling a box, and turning a shape's name into a path.
//
// Every text drawer (text elements, labels, buttons, chart axes, table
// cells) goes through layoutText, so outline, shadow, spacing and line height
// are implemented once.
//
// Nothing here touches a BuildContext or a theme: the same code paints the
// stage and the export, and an export must not depend on the app's theme.

// _layouts memoises laid-out paragraphs, the most expensive thing this file
// does and repeated every frame for unchanged text.
//
// The key is every input that can change the result, so nothing has to
// remember to clear it. Painters are only read from, so sharing one between
// callers is safe; evicted ones are dropped, not disposed, as a caller may
// still hold one from an earlier frame.
typedef _LayoutKey = (
  String,
  TextSpec,
  double,
  double,
  Color?,
  bool,
  bool,
  bool,
  // The size of the box a fading colour runs across. Not its place: the
  // shader is in paragraph coordinates. The height matters and nothing else
  // in the key carries it.
  Size?,
  // The parts, written out.
  String,
);

final _layouts = <_LayoutKey, TextPainter>{};

/// clearTextLayouts lets go of every text laid out and kept.
void clearTextLayouts() {
  for (var painter in _layouts.values) {
    painter.dispose();
  }
  _layouts.clear();
}

/// _layoutCap is the number of paragraphs kept (a busy table is a few
/// hundred cells); the oldest inserted go first.
const _layoutCap = 512;

/// layoutText builds a laid-out paragraph from a [TextSpec].
///
/// The outline is a second painter ([outline]) drawn behind, not a stroke on
/// the letters: a stroke is centred on the glyph edge and would thin the
/// letterform by half its width.
TextPainter layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,

  /// soft lays out the shadow and the glow on their own, with the letters
  /// themselves left clear. See textStyleOf.
  bool soft = false,

  /// fillWidth lays the paragraph out at exactly [maxWidth] rather than its
  /// intrinsic width. A TextPainter aligns within its own width, so without
  /// this every alignment looks like left; measuring wants it off.
  bool fillWidth = false,

  /// parts are the runs of the text that are drawn differently -- a word in
  /// another colour, a phrase in bold. Empty for almost every paragraph.
  List<TextPart> parts = const [],

  /// over is the box the words are drawn in, for a colour that fades. See
  /// textStyleOf.
  Rect? over,
}) {
  var key = (
    text,
    spec,
    maxWidth,
    scale,
    colorOverride,
    outline,
    soft,
    fillWidth,
    // The gradient is baked into the style. See _LayoutKey.
    over?.size,
    parts.isEmpty ? "" : [for (var p in parts) p.toJson()].toString(),
  );
  var hit = _layouts[key];
  if (hit != null) return hit;
  var painter = _layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      soft: soft,
      fillWidth: fillWidth,
      parts: parts,
      over: over);
  if (_layouts.length >= _layoutCap) {
    _layouts.remove(_layouts.keys.first);
  }
  _layouts[key] = painter;
  return painter;
}

TextPainter _layoutText(
  String text,
  TextSpec spec, {
  required double maxWidth,
  Rect? over,
  double scale = 1,
  Color? colorOverride,
  bool outline = false,
  bool soft = false,
  bool fillWidth = false,
  List<TextPart> parts = const [],
}) {
  // The case transform is applied here so no caller can forget it. It is
  // idempotent, so a caller that also applies it does no harm.
  text = spec.textCase.apply(text);

  var style = textStyleOf(spec,
      scale: scale,
      colorOverride: colorOverride,
      outline: outline,
      soft: soft,
      over: over);

  var painter = TextPainter(
    text: parts.isEmpty
        ? TextSpan(text: text, style: style)
        : _partedSpan(text, spec, parts, style, colorOverride, scale),
    textAlign: spec.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: null,
  );
  var width = math.max(0.0, maxWidth);
  painter.layout(
      minWidth: fillWidth && width.isFinite ? width : 0, maxWidth: width);
  return painter;
}

/// paintThroughText draws [fill] and cuts it to the shape of the letters.
///
/// Two layers: the words, then the fill composited onto them with srcIn. A
/// shader on the text paint could not draw a pattern made of many strokes.
/// The fill spans the whole box, not each letter, so it runs through the word.
///
/// [animation] and [reveal] are what the words are doing, for a fill locked
/// to them (TextFill.locked). [moving] is the paragraph's own box, which the
/// motions are fractions of, so the fill travels exactly as the letters do.
void paintThroughText(ui.Canvas canvas, Rect box, TextFill fill,
    CanvasImageSource? images, void Function() words,
    {TextAnimation? animation, double reveal = 1, Rect? moving}) {
  if (!fill.on) {
    words();
    return;
  }

  // Room for wherever the letters go outside their box -- shadow, outline,
  // and anywhere the animation takes them (motionRoom) -- or the fill is
  // clipped while the outline, drawn outside this layer, is not.
  var area = (animation == null || moving == null
          ? box
          : box.expandToInclude(motionRoom(moving, animation)))
      .inflate(box.shortestSide * 0.5 + 8);
  canvas.saveLayer(area, Paint());
  words();
  // srcIn cuts what is drawn here to the letters. The opacity is on the layer,
  // not each draw, so a pattern's ground and ink fade together.
  var through = fill.opacity.clamp(0.0, 1.0);
  canvas.saveLayer(
      area,
      Paint()
        ..blendMode = ui.BlendMode.srcIn
        ..color = ui.Color.fromRGBO(0, 0, 0, through));

  // Zoomed about the middle: 1 fits what is drawn across the words, 2 shows a
  // quarter of it at twice the size.
  var zoom = fill.zoom <= 0 ? 1.0 : fill.zoom;
  var frame = Rect.fromCenter(
      center: box.center, width: box.width * zoom, height: box.height * zoom);

  // Locked: the words' movement applied to the fill too, so it arrives with
  // the letters rather than the letters sweeping across it.
  var depth = 0;
  if (fill.locked &&
      animation != null &&
      moving != null &&
      movesAsOneBlock(animation) &&
      (reveal < 1 || animation.keeps)) {
    var carried = applyMotionSpec(
        canvas, moving, animation.spec, animation.progressAt(reveal, 0, 1),
        from: animation.spec.from);
    depth = carried.depth;
  }

  // What has to be covered: the frame the fill is sized to, and everywhere
  // the words can be while they arrive.
  var reach = frame.expandToInclude(area);

  switch (fill.kind) {
    case TextFillKind.pattern:
      // The pattern's ground under the whole reach, so a letter outside the
      // frame is not hollow. The pattern keeps the frame: drawn across the
      // changing reach it would resize every frame.
      if (reach != frame) {
        canvas.drawRect(reach, Paint()..color = fill.pattern.background);
      }
      paintProcedural(canvas, frame, fill.pattern);
    case TextFillKind.image:
      var image = images?.resolve(fill.assetId, const BackgroundRemoval());
      if (image != null) {
        // The same named look and the same two sliders a picture element
        // has, as one matrix -- see image_look.dart.
        var matrix = combineMatrices(presetMatrix(fill.filter),
            colorMatrix(fill.saturation, fill.brightness));
        _paintFillImage(canvas, reach, frame, image, fill.tile,
            matrix == null ? null : ColorFilter.matrix(matrix));

        // The overlay, inside this layer so it blends only with the picture
        // and not with everything already on the canvas.
        if (fill.blend != OverlayBlend.none &&
            (fill.overlay.a > 0 || fill.overlayFade != null)) {
          canvas.drawRect(
              reach,
              PaintSpec(fill.overlay, gradient: fill.overlayFade)
                  .into(Paint(), frame)
                ..blendMode = fill.blend.flutter);
        }
      }
    case TextFillKind.color:
      break;
  }

  for (var i = 0; i < depth; i++) {
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// _paintFillImage covers the words with a picture, or tiles it across them.
///
/// [reach] is everywhere that has to be covered -- the frame the picture is
/// sized to, grown to take in wherever the words go while they arrive.
void _paintFillImage(ui.Canvas canvas, Rect reach, Rect frame, ui.Image image,
    bool tile, ColorFilter? look) {
  var size = Size(image.width.toDouble(), image.height.toDouble());
  if (size.isEmpty) return;

  if (tile) {
    // A repeating fill is drawn by a shader rather than in a loop, so the
    // number of copies costs nothing.
    var scale = frame.width / size.width;
    canvas.drawRect(
        reach,
        Paint()
          ..colorFilter = look
          ..shader = ui.ImageShader(
              image,
              ui.TileMode.repeated,
              ui.TileMode.repeated,
              // Column-major, which is what ImageShader wants: scale, then
              // put the first copy where the frame starts.
              Float64List.fromList([
                scale, 0, 0, 0, //
                0, scale, 0, 0, //
                0, 0, 1, 0, //
                frame.left, frame.top, 0, 1, //
              ])));
    return;
  }

  // Covering: the frame filled, overspill cropped, aspect kept. A clamped
  // shader rather than drawImageRect, so a letter out past the picture is
  // filled with its edge rather than nothing.
  var scale = math.max(frame.width / size.width, frame.height / size.height);
  var wide = size.width * scale, tall = size.height * scale;
  var left = frame.center.dx - wide / 2, top = frame.center.dy - tall / 2;
  canvas.drawRect(
      reach,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = look
        ..shader = ui.ImageShader(
            image,
            ui.TileMode.clamp,
            ui.TileMode.clamp,
            // Column-major, as ImageShader wants: scale, then put the
            // picture's corner where the covering rectangle starts.
            Float64List.fromList([
              scale, 0, 0, 0, //
              0, scale, 0, 0, //
              0, 0, 1, 0, //
              left, top, 0, 1, //
            ])));
}

/// _usable is whether a picture's own size can be scaled to fit a box.
bool _usable(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;

/// paintTextIcon draws the picture a text element carries.
///
/// A vector where the asset is one, so it is sharp at any size.
void paintTextIcon(ui.Canvas canvas, Rect box, TextIcon icon,
    CanvasImageSource? images, TextSpec spec) {
  if (!icon.on || box.width <= 0 || box.height <= 0) return;

  paintBox(canvas, box, icon.box, images);
  var inner = icon.box.inner(box);
  if (inner.width <= 0 || inner.height <= 0) return;

  // The drawing where the asset is one, else the rasterised copy. A drawing
  // with no usable size (an .svg with no width, height or viewBox) cannot be
  // scaled, so it falls back to the raster too.
  var vector = images?.resolveVector(icon.assetId);
  if (vector != null && !_usable(vector.size)) vector = null;
  var bitmap = vector == null
      ? images?.resolve(icon.assetId, const BackgroundRemoval())
      : null;
  if (vector == null && bitmap == null) return;

  var size =
      vector?.size ?? Size(bitmap!.width.toDouble(), bitmap.height.toDouble());
  if (!_usable(size)) return;

  // Fitted inside its room, never stretched.
  var scale = math.min(inner.width / size.width, inner.height / size.height);
  var at = Rect.fromCenter(
      center: inner.center,
      width: size.width * scale,
      height: size.height * scale);

  void draw(Color? tint) {
    if (tint != null) canvas.saveLayer(at.inflate(4), Paint());
    if (vector != null) {
      canvas.save();
      canvas.translate(at.left, at.top);
      canvas.scale(scale, scale);
      canvas.drawPicture(vector.picture);
      canvas.restore();
    } else {
      canvas.drawImageRect(bitmap!, Offset.zero & size, at,
          Paint()..filterQuality = FilterQuality.medium);
    }
    if (tint != null) {
      // Cut to the drawing's own shape and filled.
      canvas.drawRect(
          at.inflate(4),
          Paint()
            ..color = tint
            ..blendMode = ui.BlendMode.srcIn);
      canvas.restore();
    }
  }

  // The sticker outline: the shape in the outline colour, offset in eight
  // directions behind the icon (its paths are opaque here).
  if (icon.outlineWidth > 0) {
    for (var i = 0; i < 8; i++) {
      var a = i / 8 * 2 * math.pi;
      canvas.save();
      canvas.translate(
          math.cos(a) * icon.outlineWidth, math.sin(a) * icon.outlineWidth);
      draw(icon.outlineColor);
      canvas.restore();
    }
  }

  draw(icon.color);

  if (icon.underline != null) {
    _paintPartUnderline(canvas, at, icon.underline!, icon.color ?? spec.color);
  }
}

/// marksRoom is how far outside the words the parts' own marks reach, the
/// largest of each side over every part, for a clip to grow by. Without it a
/// highlight's padding is clipped off at the box edge of a left- or
/// right-aligned line.
EdgeInsets marksRoom(List<TextPart> parts) {
  var room = EdgeInsets.zero;
  for (var part in parts) {
    var mark = part.highlight;
    if (mark != null) {
      room = EdgeInsets.fromLTRB(
        math.max(room.left, mark.padLeft),
        math.max(room.top, mark.padTop),
        math.max(room.right, mark.padRight),
        math.max(room.bottom, mark.padBottom),
      );
    }
    var line = part.underline;
    if (line != null) {
      room = room.copyWith(
          bottom: math.max(room.bottom, line.away + line.width + 1));
    }
  }
  return room;
}

/// paintPartMarks draws the highlights behind, or the underlines under, the
/// element's parts.
///
/// Called twice: [behind] for highlights before the words, then underlines
/// after them so a descender does not sit on top of the line. Rectangles are
/// the paragraph's selection boxes, so a part across a line break is marked
/// per line.
///
/// [timings] says how much of each mark has been drawn on, from its start.
/// [moving] and [at] are the element's animation and how far through it is:
/// a mark arrives and leaves with its words.
void paintPartMarks(
  ui.Canvas canvas,
  TextPainter painter,
  String text,
  List<TextPart> parts,
  TextSpec spec,
  Offset offset, {
  required bool behind,
  List<PartTiming> timings = const [],
  TextAnimation? moving,
  double at = 1,
}) {
  if (parts.isEmpty || text.isEmpty) return;

  for (var (i, part) in parts.indexed) {
    var mark = behind ? part.highlight : part.underline;
    if (mark == null) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    var drawn = i < timings.length ? timings[i].mark : 1.0;
    if (drawn <= 0) continue;

    var boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.$1, extentOffset: range.$2));
    // Drawn on along the first line, then the second, not both at once.
    var total = 0.0;
    for (var b in boxes) {
      total += b.toRect().width;
    }
    var reached = total * drawn;
    for (var b in boxes) {
      var box = b.toRect().shift(offset);
      if (box.width <= 0) continue;
      if (reached < box.width) {
        if (reached <= 0) break;
        box = Rect.fromLTWH(box.left, box.top, reached, box.height);
      }
      reached -= b.toRect().width;

      // Carried by the words' motion, as one piece rather than per letter.
      var frame = moving == null || !moving.on
          ? const MotionFrame(1, 0, false)
          : applyMotionSpec(
              canvas, box, moving.spec, moving.progressAt(at, 0, 1),
              from: moving.spec.from);
      _fadeInto(canvas, box, frame.alpha, () {
        if (behind) {
          _paintPartHighlight(canvas, box, part.highlight!);
        } else {
          _paintPartUnderline(
              canvas, box, part.underline!, part.color ?? spec.color);
        }
      });
      for (var r = 0; r < frame.depth; r++) {
        canvas.restore();
      }
      if (reached <= 0) break;
    }
  }
}

/// _fadeInto draws [what] at [alpha], through a layer where it has to be.
void _fadeInto(ui.Canvas canvas, Rect box, double alpha, void Function() what) {
  if (alpha <= 0) return;
  if (alpha >= 1) {
    what();
    return;
  }
  canvas.saveLayer(box.inflate(box.height * 2),
      Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  what();
  canvas.restore();
}

void _paintPartHighlight(ui.Canvas canvas, Rect box, PartHighlight mark) {
  var band = Rect.fromLTRB(
    box.left - mark.padLeft,
    box.top - mark.padTop,
    box.right + mark.padRight,
    box.bottom + mark.padBottom,
  );
  // Shaded across the whole band, not per word.
  var paint = PaintSpec(mark.color, gradient: mark.fade).into(Paint(), band);
  if (mark.radius <= 0) {
    canvas.drawRect(band, paint);
    return;
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(band, Radius.circular(mark.radius)), paint);
}

void _paintPartUnderline(
    ui.Canvas canvas, Rect box, PartUnderline mark, Color fallback) {
  var width = math.max(0.1, mark.width);
  var y = box.bottom + mark.away;
  var line = Rect.fromLTRB(box.left, y - width / 2, box.right, y + width / 2);
  // Along the line, so a fade runs its length rather than its thickness.
  var paint = PaintSpec(mark.color ?? fallback, gradient: mark.fade).into(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
      line);

  // Phase from position, not randomness, so a frame redraws identically.
  var phase = (box.left * 0.7 + box.top * 1.3) % (2 * math.pi);

  switch (mark.style) {
    case PartLineStyle.solid:
      paint.strokeCap = StrokeCap.butt;
      canvas.drawRect(Rect.fromLTWH(box.left, y - width / 2, box.width, width),
          paint..style = PaintingStyle.fill);

    case PartLineStyle.dashed:
      paint.strokeCap = StrokeCap.butt;
      canvas.drawPath(
          dashPath(_straight(box.left, box.right, y), width * 4, width * 3),
          paint);

    case PartLineStyle.dotted:
      canvas.drawPath(
          dashPath(_straight(box.left, box.right, y), 0.01, width * 3), paint);

    case PartLineStyle.twin:
      paint
        ..strokeWidth = width * 0.55
        ..strokeCap = StrokeCap.butt;
      canvas.drawPath(_straight(box.left, box.right, y - width * 0.7), paint);
      canvas.drawPath(_straight(box.left, box.right, y + width * 0.7), paint);

    case PartLineStyle.wavy:
      canvas.drawPath(
          _wobble(box.left, box.right, y,
              amplitude: width * 1.1, wavelength: width * 7, phase: 0),
          paint);

    case PartLineStyle.hand:
      // One pass, barely off straight, overshooting the last letter.
      canvas.drawPath(
          _wobble(
              box.left - width * 0.4, box.right + width * 1.2, y + width * 0.2,
              amplitude: width * 0.45,
              wavelength: box.width / 1.7 + width * 8,
              phase: phase,
              tilt: -width * 0.5),
          paint);

    case PartLineStyle.marker:
      // A filled brush shape, so the thickness varies and the ends taper.
      canvas.drawPath(
          _brush(box.left - width * 0.5, box.right + width * 1.5,
              y + width * 0.3, width * 1.6, phase),
          Paint()..color = mark.color ?? fallback);

    case PartLineStyle.sketch:
      // Two passes that do not quite agree.
      paint.strokeWidth = width * 0.8;
      canvas.drawPath(
          _wobble(box.left - width * 0.3, box.right + width, y,
              amplitude: width * 0.5,
              wavelength: box.width / 1.4 + width * 6,
              phase: phase,
              tilt: -width * 0.6),
          paint);
      canvas.drawPath(
          _wobble(
              box.left + width * 0.6, box.right + width * 0.4, y + width * 0.9,
              amplitude: width * 0.6,
              wavelength: box.width / 2.1 + width * 5,
              phase: phase + 2.1,
              tilt: width * 0.7),
          paint);
  }
}

Path _straight(double from, double to, double y) => Path()
  ..moveTo(from, y)
  ..lineTo(to, y);

/// _wobble is a line that is not quite straight.
///
/// Two sines of different lengths, so it wanders rather than waves; [tilt]
/// leans the whole line.
Path _wobble(double from, double to, double y,
    {required double amplitude,
    required double wavelength,
    required double phase,
    double tilt = 0}) {
  var path = Path();
  var span = to - from;
  if (span <= 0) {
    return path
      ..moveTo(from, y)
      ..lineTo(from, y);
  }
  var steps = math.max(6, (span / 6).round());
  var length = math.max(1.0, wavelength);
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    var x = from + span * t;
    var wave = math.sin(phase + t * span / length * 2 * math.pi) +
        math.sin(phase * 1.7 + t * span / (length * 0.37) * 2 * math.pi) * 0.35;
    var dy = y + wave * amplitude + tilt * (t - 0.5) * 2;
    i == 0 ? path.moveTo(x, dy) : path.lineTo(x, dy);
  }
  return path;
}

/// _brush is a marker stroke: a filled shape whose thickness varies and whose
/// ends taper away to nothing.
Path _brush(double from, double to, double y, double thick, double phase) {
  var span = to - from;
  if (span <= 0) return Path();
  var steps = math.max(8, (span / 5).round());
  var top = <Offset>[];
  var bottom = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    var t = i / steps;
    var x = from + span * t;
    // Thick in the middle, thin at both ends, and slightly uneven.
    var taper = math.sin(t * math.pi);
    var vary = 0.8 + 0.2 * math.sin(phase + t * 9);
    var half = thick / 2 * math.pow(taper, 0.45).toDouble() * vary;
    var drift = math.sin(phase * 1.3 + t * 4) * thick * 0.12;
    top.add(Offset(x, y + drift - half));
    bottom.add(Offset(x, y + drift + half));
  }
  var path = Path()..moveTo(top.first.dx, top.first.dy);
  for (var p in top.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (var p in bottom.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// textOffsetIn is where a laid-out paragraph is drawn inside [box].
///
/// Only the vertical alignment moves it: the painter (laid out with
/// fillWidth) has already aligned horizontally. Public so things that move
/// with the words (an icon, a locked fill) use the same paragraph rectangle
/// the motions are fractions of.
Offset textOffsetIn(Rect box, TextPainter painter, TextSpec spec) {
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => box.top,
    VerticalAlignSpec.middle => box.top + (box.height - painter.height) / 2,
    VerticalAlignSpec.bottom => box.bottom - painter.height,
  };
  return Offset(box.left, dy);
}

/// outlineSpecFor is the type a paragraph's outline is drawn in, or null where
/// there is no outline to draw.
///
/// Shared by every text layout (box, columns, wrap, curve) so they agree. It
/// is the type's own outline where it has one; for a stroke-on (draw the
/// outline) arrival, a stroke in the colour the animation's draw settings
/// give; or the paragraph spec where only a part asks for an outline. It
/// never invents a colour: with none given there is nothing to draw.
TextSpec? outlineSpecFor(TextSpec spec,
    {List<TextPart> parts = const [],
    TextAnimation? animation,
    double reveal = 1}) {
  if (spec.outlineWidth > 0) return spec;
  var drawing = animation != null &&
      animation.on &&
      animation.preset.motion == TextMotion.strokeOn &&
      animation.draw.color != null;
  if (drawing) {
    return spec.copyWith(
        outlineWidth: math.max(1.5, spec.fontSize * 0.06),
        outlineColor: animation.draw.color);
  }
  // A part may want an outline in a paragraph that has none: the paragraph
  // is stroked with nothing and only the part's run has a width.
  return partsOutline(parts) ? spec : null;
}

/// outlineFor is [outlineSpecFor] laid out, or null where there is none.
TextPainter? outlineFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    List<TextPart> parts = const [],
    TextAnimation? animation,
    double reveal = 1}) {
  var outlineSpec =
      outlineSpecFor(spec, parts: parts, animation: animation, reveal: reveal);
  if (outlineSpec == null) return null;
  return layoutText(text, outlineSpec,
      maxWidth: maxWidth,
      scale: scale,
      outline: true,
      fillWidth: true,
      parts: parts);
}

/// softFor lays out the shadow and the glow on their own, or returns null
/// where the type has neither.
///
/// The same paragraph as the words with clear glyphs, so it lines up exactly.
/// See textStyleOf's soft for why.
TextPainter? softFor(String text, TextSpec spec,
    {required double maxWidth,
    double scale = 1,
    bool fillWidth = true,
    List<TextPart> parts = const []}) {
  if (!spec.softPasses) return null;
  return layoutText(text, spec,
      maxWidth: maxWidth,
      scale: scale,
      soft: true,
      fillWidth: fillWidth,
      parts: parts);
}

/// paintTextInBox lays [text] out inside [box] and draws it, honouring both
/// alignments and the outline.
///
/// Returns the height the text took, for the chart and table to lay out the
/// rest. [animation] and [reveal] draw it part way through arriving (see
/// text_animator.dart).
double paintTextInBox(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box, {
  double scale = 1,
  Color? colorOverride,
  bool clip = false,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],

  /// timings are where each part has got to, for parts that arrive on their
  /// own account. See TextPartAnimation.
  List<PartTiming> timings = const [],

  /// asOne makes the parts arrive with everything else, as on the way out.
  /// See paintAnimatedText.
  bool asOne = false,

  /// images is where a picture used as a fill comes from. See TextFill.
  CanvasImageSource? images,
}) {
  if (text.isEmpty || box.width <= 0) return 0;

  var painter = layoutText(text, spec,
      maxWidth: box.width,
      scale: scale,
      colorOverride: colorOverride,
      fillWidth: true,
      parts: parts,
      // So a fade runs across the box the words are drawn in.
      over: box);

  var offset = textOffsetIn(box, painter, spec);

  if (clip) {
    canvas.save();
    // With room for the parts' marks. See marksRoom.
    var room = marksRoom(parts);
    canvas.clipRect(Rect.fromLTRB(box.left - room.left, box.top - room.top,
        box.right + room.right, box.bottom + room.bottom));
  }

  var outline = outlineFor(text, spec,
      maxWidth: box.width,
      scale: scale,
      parts: parts,
      animation: animation,
      reveal: reveal);

  var soft =
      softFor(text, spec, maxWidth: box.width, scale: scale, parts: parts);

  // Highlights behind the words now, underlines after them; they move with
  // the words while the arrival is under way.
  var marksMove = animation != null && animation.on && reveal < 1;
  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: true,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  // words draws the paragraph, through the animator (with its outline and
  // soft passes) whenever anything moves: an arrival under way, a motion that
  // [keeps] something, or a part arriving on its own. A closure because a
  // filled paragraph is drawn twice, once per TextDrawPhase, by the same
  // code so the two passes stay in register.
  void words({TextDrawPhase phase = TextDrawPhase.all}) {
    if (animation != null &&
        ((animation.on && (reveal < 1 || animation.keeps)) ||
            (!asOne && partsAnimate(parts)))) {
      paintAnimatedText(canvas, painter, text, spec, offset, animation, reveal,
          maxWidth: box.width,
          outline: outline,
          soft: soft,
          parts: parts,
          timings: timings,
          asOne: asOne,
          phase: phase);
      return;
    }
    if (phase.drawsOutline) soft?.paint(canvas, offset);
    if (phase.drawsOutline) outline?.paint(canvas, offset);
    if (phase.drawsLetters) painter.paint(canvas, offset);
  }

  if (!spec.fill.on) {
    words();
  } else {
    // The outline and soft passes first, outside the layer the fill is cut
    // to, so they keep their own colours rather than taking the fill's.
    words(phase: TextDrawPhase.behind);
    paintThroughText(canvas, box, spec.fill, images,
        () => words(phase: TextDrawPhase.letters),
        animation: animation, reveal: reveal, moving: offset & painter.size);
  }

  paintPartMarks(canvas, painter, text, parts, spec, offset,
      behind: false,
      timings: timings,
      moving: marksMove ? animation : null,
      at: reveal);

  if (clip) canvas.restore();
  return painter.height;
}

/// fitFontSize is the largest size at which [text] fits inside [box], for a
/// text element with autoSize on.
///
/// A bisection, since wrapped height steps as words change lines. [columns]
/// is how many columns the text is flowed into; [box] is one column's box.
double fitFontSize(String text, TextSpec spec, Size box, {int columns = 1}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return spec.fontSize;
  var count = math.max(1, columns);
  var low = 4.0, high = box.height * 2 * count;
  for (var i = 0; i < 14; i++) {
    var mid = (low + high) / 2;
    var p = layoutText(text, spec.copyWith(fontSize: mid), maxWidth: box.width);
    if (p.width > box.width + 0.5) {
      high = mid;
      continue;
    }
    if (count == 1) {
      p.height <= box.height ? low = mid : high = mid;
      continue;
    }
    // Against the real packing, since a column holds whole lines only.
    var runs = columnRuns(p.computeLineMetrics(), box.height, count);
    var carried = runs.isEmpty ? 0 : runs.last.$2;
    carried >= p.computeLineMetrics().length ? low = mid : high = mid;
  }
  return low;
}

/// _partedSpan builds the paragraph out of runs, so a few words in it can be
/// a different colour or weight from the rest.
///
/// One span per run of characters with the same part (see partAt), not one
/// per letter.
TextSpan _partedSpan(String text, TextSpec spec, List<TextPart> parts,
    TextStyle style, Color? colorOverride, double scale) {
  var children = <TextSpan>[];
  var from = 0;
  TextPart? current = partAt(text, parts, 0);

  TextStyle styleFor(TextPart? part) {
    // An outline paragraph has a foreground paint, and a TextStyle cannot
    // carry both that and a colour (it throws): take the part's size, family,
    // weight and slant and its own stroke, and never set color.
    if (style.foreground != null) {
      var width = part?.outlineWidth ?? spec.outlineWidth;
      var out = part == null
          ? style
          : style.copyWith(
              fontSize: part.scale == null
                  ? style.fontSize
                  : (style.fontSize ?? spec.fontSize) * part.scale!,
              fontFamily: part.family ?? style.fontFamily,
              fontWeight: part.weight == null
                  ? style.fontWeight
                  : FontWeight.values[((part.weight! ~/ 100) - 1)
                      .clamp(0, FontWeight.values.length - 1)],
              fontStyle: part.italic == null
                  ? style.fontStyle
                  : (part.italic! ? FontStyle.italic : FontStyle.normal),
            );
      // A width of zero is drawn transparent: a zero-width stroke is a
      // hairline.
      return out.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width * 2 * scale
          ..color = width <= 0
              ? const Color(0x00000000)
              : (part?.outlineColor ?? spec.outlineColor),
      );
    }
    if (part == null) return style;
    return style.copyWith(
      // colorOverride wins, so a one-colour preview (a ghost) has no
      // coloured words.
      color: colorOverride ?? part.color ?? style.color,
      fontFamily: part.family ?? style.fontFamily,
      fontSize: part.scale == null
          ? style.fontSize
          : (style.fontSize ?? 0) * part.scale!,
      fontWeight: part.weight == null
          ? style.fontWeight
          : FontWeight.values[((part.weight! ~/ 100) - 1)
              .clamp(0, FontWeight.values.length - 1)],
      fontStyle: part.italic == null
          ? style.fontStyle
          : (part.italic! ? FontStyle.italic : FontStyle.normal),
    );
  }

  for (var i = 1; i <= text.length; i++) {
    var here = i == text.length ? null : partAt(text, parts, i);
    if (i == text.length || !identical(here, current)) {
      children.add(
          TextSpan(text: text.substring(from, i), style: styleFor(current)));
      from = i;
      current = here;
    }
  }
  return TextSpan(children: children, style: style);
}

/// paintBox draws a [BoxSpec]: the fill, then the border, both rounded.
void paintBox(ui.Canvas canvas, Rect rect, BoxSpec box,
    [CanvasImageSource? images]) {
  paintBoxFill(canvas, rect, box, images);
  paintBoxBorder(canvas, rect, box);
}

/// paintBoxFill is the inside of a box -- its colour, and a picture or a
/// pattern over that -- without its border, for an element that draws
/// between the two. See paintBoxBorder.
void paintBoxFill(ui.Canvas canvas, Rect rect, BoxSpec box,
    [CanvasImageSource? images]) {
  if (rect.width <= 0 || rect.height <= 0) return;
  var filled = PaintSpec(box.fill, gradient: box.fillFade);
  if (filled.shows) {
    canvas.drawRRect(box.rounded(rect), filled.into(Paint(), rect));
  }
  // A picture or pattern over that, cut to the box's shape as paintThroughText
  // cuts it to letters.
  if (box.painted.on) {
    paintThroughText(canvas, rect, box.painted, images,
        () => canvas.drawRRect(box.rounded(rect), Paint()));
  }
}

/// paintBoxBorder is a box's border alone, inside its edge.
void paintBoxBorder(ui.Canvas canvas, Rect rect, BoxSpec box) {
  if (rect.width <= 0 || rect.height <= 0) return;
  if (!box.hasBorder) return;

  var paint =
      PaintSpec(box.borderColor, gradient: box.borderFade).into(Paint(), rect);

  var even = box.evenBorder;
  if (even != null) {
    // Inset by half the stroke so the border sits inside the bounds and is
    // not half cut off on a full-bleed element.
    canvas.drawRRect(
      box.rounded(rect, by: even / 2),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = even,
    );
    return;
  }

  // Uneven sides are four strips inside the bounds, square where they meet:
  // two widths meeting at a rounded corner have no agreed shape, so the
  // corner radius is left to the fill.
  var sides = box.borders;
  paint.style = PaintingStyle.fill;
  if (sides.top > 0) {
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, sides.top), paint);
  }
  if (sides.bottom > 0) {
    canvas.drawRect(
        Rect.fromLTWH(
            rect.left, rect.bottom - sides.bottom, rect.width, sides.bottom),
        paint);
  }
  if (sides.left > 0) {
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, sides.left, rect.height), paint);
  }
  if (sides.right > 0) {
    canvas.drawRect(
        Rect.fromLTWH(
            rect.right - sides.right, rect.top, sides.right, rect.height),
        paint);
  }
}

/// shapePath turns a [ShapeKind] into a path filling [rect].
///
/// Each shape is built in [rect] itself rather than a scaled unit square, so
/// a stroke on a stretched shape stays even.
Path shapePath(ShapeKind kind, Rect rect,
    {int points = 5,
    double inner = 0.42,
    double cornerRadius = 0,

    /// corners rounds each corner on its own; null means [cornerRadius] for
    /// all four.
    Corners? corners,
    SpeechBubbleSpec bubble = const SpeechBubbleSpec()}) {
  var path = Path();
  var c = rect.center;
  var rx = rect.width / 2, ry = rect.height / 2;

  switch (kind) {
    case ShapeKind.rectangle:
    case ShapeKind.square:
      var round = corners ?? Corners(all: cornerRadius);
      if (round.isRounded) {
        path.addRRect(round.rrect(rect));
      } else {
        path.addRect(rect);
      }

    case ShapeKind.ellipse:
    case ShapeKind.circle:
      path.addOval(rect);

    case ShapeKind.triangle:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.close();

    case ShapeKind.diamond:
      path.moveTo(c.dx, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(c.dx, rect.bottom);
      path.lineTo(rect.left, c.dy);
      path.close();

    case ShapeKind.pentagon:
      _regular(path, c, rx, ry, 5);
    case ShapeKind.hexagon:
      _regular(path, c, rx, ry, 6);

    case ShapeKind.star:
      var n = points.clamp(3, 24);
      var ratio = inner.clamp(0.05, 0.95).toDouble();
      for (var i = 0; i < n * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / n;
        var r = i.isEven ? 1.0 : ratio;
        var p =
            Offset(c.dx + math.cos(a) * rx * r, c.dy + math.sin(a) * ry * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();

    case ShapeKind.arrow:
      // A shaft along the middle third with a head taking the last quarter.
      var headStart = rect.left + rect.width * 0.72;
      var shaft = rect.height * 0.34;
      path.moveTo(rect.left, c.dy - shaft / 2);
      path.lineTo(headStart, c.dy - shaft / 2);
      path.lineTo(headStart, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(headStart, rect.bottom);
      path.lineTo(headStart, c.dy + shaft / 2);
      path.lineTo(rect.left, c.dy + shaft / 2);
      path.close();

    case ShapeKind.chevron:
      var notch = rect.width * 0.28;
      path.moveTo(rect.left, rect.top);
      path.lineTo(rect.right - notch, rect.top);
      path.lineTo(rect.right, c.dy);
      path.lineTo(rect.right - notch, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
      path.lineTo(rect.left + notch, c.dy);
      path.close();

    case ShapeKind.cross:
      var t = math.min(rx, ry) * 0.42;
      path.addRect(Rect.fromLTRB(c.dx - t, rect.top, c.dx + t, rect.bottom));
      path.addRect(Rect.fromLTRB(rect.left, c.dy - t, rect.right, c.dy + t));

    case ShapeKind.speechBubble:
      return bubblePath(rect, bubble, cornerRadius);
  }
  return path;
}

void _regular(Path path, Offset c, double rx, double ry, int sides) {
  for (var i = 0; i < sides; i++) {
    var a = -math.pi / 2 + i * 2 * math.pi / sides;
    var p = Offset(c.dx + math.cos(a) * rx, c.dy + math.sin(a) * ry);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
}

/// dashPath breaks [source] into dashes of [on] followed by gaps of [off].
Path dashPath(Path source, double on, double off) {
  if (!(on > 0) || !off.isFinite) return source;
  off = math.max(0.0, off);
  // Past this many dashes the line is drawn whole, so a tiny dash from a
  // received document cannot hang the paint.
  const most = 20000;
  var metrics = source.computeMetrics().toList();
  var total = metrics.fold(0.0, (n, m) => n + m.length);
  if (total / (on + off) > most) return source;
  var out = Path();
  for (var metric in metrics) {
    var d = 0.0;
    while (d < metric.length) {
      var next = math.min(d + on, metric.length);
      out.addPath(metric.extractPath(d, next), Offset.zero);
      d = next + off;
    }
  }
  return out;
}

/// arrowSpread is the half-angle between an arrowhead's axis and each barb
/// (radians), shared with the line ends in scene_renderer.dart. LineEnd.cover
/// trims the stroke back to where the barbs meet, assuming this value.
const double arrowSpread = 0.42;

/// arrowHead is a filled (or, with [filled] false, stroked) triangle at
/// [tip], pointing along [angle].
void arrowHead(
    ui.Canvas canvas, Offset tip, double angle, double size, Paint paint,
    {bool filled = true}) {
  var back = angle + math.pi;
  var spread = arrowSpread;
  var path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + math.cos(back - spread) * size,
        tip.dy + math.sin(back - spread) * size)
    ..lineTo(tip.dx + math.cos(back + spread) * size,
        tip.dy + math.sin(back + spread) * size)
    ..close();
  canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth
        ..strokeJoin = StrokeJoin.miter);
}

/// _capHeightRatio is how much of a font's size the capitals and digits
/// actually occupy, measured from the baseline.
///
/// A constant because Flutter does not expose cap height; the faces offered
/// all fall between 0.70 and 0.73, close enough for centring a squad number.
const double _capHeightRatio = 0.71;

/// paintCentredGlyphs draws [text] with its *ink* centred on [center].
///
/// Not the laid-out box, which grows with line height: a team's numbers and
/// names share one TextSpec (TeamElement.labelSpec), so a line height set for
/// the names would slide the number out of its dot. Digits and capitals sit
/// between the baseline and one cap height above it, so
/// `baseline - capHeight / 2` is put on the centre.
void paintCentredGlyphs(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Offset center, {
  double scale = 1,
}) {
  if (text.isEmpty) return;

  // Unconstrained, so "10" never wraps inside a dot barely wider than it.
  var painter = layoutText(text, spec, maxWidth: double.infinity, scale: scale);
  var baseline =
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  if (!baseline.isFinite) baseline = painter.height;

  var capHeight = spec.fontSize * scale * _capHeightRatio;
  var at = Offset(
    center.dx - painter.width / 2,
    center.dy - (baseline - capHeight / 2),
  );

  softFor(text, spec, maxWidth: double.infinity, scale: scale, fillWidth: false)
      ?.paint(canvas, at);
  if (spec.outlineWidth > 0) {
    layoutText(text, spec,
            maxWidth: double.infinity, scale: scale, outline: true)
        .paint(canvas, at);
  }
  painter.paint(canvas, at);
}

/// lineEdges is where one line of a laid-out paragraph gives way to the next,
/// with an entry for the top of the first and the bottom of the last.
///
/// Not the line boxes' boundaries: with tight line height the descenders of
/// one line hang into the next line's box, and a column cut there starts with
/// a sliver of the line before. So the edge is the later of the box boundary
/// and the bottom of the ink above.
List<double> lineEdges(List<ui.LineMetrics> metrics) {
  var edges = <double>[0];
  var at = 0.0;
  for (var (i, line) in metrics.indexed) {
    at += line.height;

    // Half a pixel past the ink, so an antialiased descender row is not
    // left along the top of the next column.
    var edge = math.max(at, line.baseline + line.descent) + 0.5;

    // But never into the capitals below (about 0.78 of the ascent): when
    // lines overlap, a descender loses a sliver rather than the capitals.
    if (i + 1 < metrics.length) {
      var below = metrics[i + 1];
      edge = math.min(edge, below.baseline - below.ascent * 0.78);
    }
    edges.add(math.max(edge, edges.last));
  }
  return edges;
}

/// columnRuns is which lines of a laid-out paragraph go in which column, as
/// (first, end) line ranges. Whole lines only, measured from the line metrics
/// (lines differ in height); a line that does not fit goes to the next column.
///
/// [noBlankStart] drops a blank (zero-width) line that would begin a column
/// after the first, such as the gap between two paragraphs.
List<(int, int)> columnRuns(
    List<ui.LineMetrics> metrics, double height, int columns,
    {bool noBlankStart = false}) {
  if (metrics.isEmpty || columns <= 0) return const [];

  bool blank(int line) => metrics[line].width <= 0.5;

  // top is where a line starts, from the paragraph's top. See lineEdges.
  var tops = lineEdges(metrics);
  double top(int line) => tops[line.clamp(0, tops.length - 1)];

  var runs = <(int, int)>[];
  var at = 0;
  for (var c = 0; c < columns && at < metrics.length; c++) {
    if (noBlankStart && c > 0) {
      while (at < metrics.length - 1 && blank(at)) {
        at++;
      }
    }
    var end = at;
    // At least one line per column even where it does not fit, or a box
    // shorter than a line would draw nothing.
    while (end < metrics.length &&
        (end == at || top(end + 1) - top(at) <= height + 0.5)) {
      end++;
    }
    runs.add((at, end));
    at = end;
  }
  return runs;
}

/// paintTextInColumns flows one paragraph across [columns] columns of [box].
///
/// The paragraph is laid out once at a column's width, then drawn once per
/// column, clipped to it and shifted up by the lines already used (see
/// columnRuns). [animation] and [reveal] draw it part way through arriving;
/// the pieces are worked out for the whole paragraph, so a stagger runs on
/// across columns rather than restarting in each.
void paintTextInColumns(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  Rect box,
  TextColumns columns, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],
  List<PartTiming> timings = const [],
  bool asOne = false,
  CanvasImageSource? images,
}) {
  if (text.isEmpty || box.width <= 0 || box.height <= 0) return;

  var width = columns.columnWidth(box.width);
  if (width <= 0) return;

  var painter = layoutText(text, spec,
      maxWidth: width, scale: scale, fillWidth: true, parts: parts);
  var metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) return;

  var runs = columnRuns(metrics, box.height, columns.count,
      noBlankStart: columns.noBlankStart);

  var outline = outlineFor(text, spec,
      maxWidth: width,
      scale: scale,
      parts: parts,
      animation: animation,
      reveal: reveal);

  var soft = softFor(text, spec, maxWidth: width, scale: scale, parts: parts);

  var tops = lineEdges(metrics);
  double top(int line) => tops[line.clamp(0, tops.length - 1)];

  // A whole-paragraph arrival is applied once, around every column, so the
  // per-column clips travel with the motion rather than cutting it off.
  var moving =
      animation != null && animation.on && (reveal < 1 || animation.keeps);
  var asBlock = moving && movesAsOneBlock(animation);
  var depth = 0;
  if (asBlock) {
    var carried = applyMotionSpec(
        canvas, box, animation.spec, animation.progressAt(reveal, 0, 1),
        from: animation.spec.from);
    depth = carried.depth;
    if (carried.alpha <= 0) {
      for (var r = 0; r < depth; r++) {
        canvas.restore();
      }
      return;
    }
    if (carried.alpha < 1) {
      canvas.saveLayer(box.inflate(box.height),
          Paint()..color = Color.fromRGBO(0, 0, 0, carried.alpha));
      depth++;
    }
  }

  for (var i = 0; i < runs.length; i++) {
    var (from, to) = runs[i];
    var left = box.left + i * (width + columns.gap);

    // The lines this column holds, which is what it is clipped to.
    var used = top(to) - top(from);
    var dy = switch (spec.verticalAlign) {
      VerticalAlignSpec.top => 0.0,
      VerticalAlignSpec.middle => (box.height - used) / 2,
      VerticalAlignSpec.bottom => box.height - used,
    };

    canvas.save();
    // Room at the ends for highlights (marksRoom), at most half the gutter.
    // None above or below: that edge keeps the column to its own lines.
    var room = marksRoom(parts);
    var ends = math.min(columns.gap / 2, math.max(room.left, room.right));
    canvas.clipRect(
        Rect.fromLTWH(left - ends, box.top + dy, width + ends * 2, used));
    var at = Offset(left, box.top + dy - top(from));

    // Marks for the whole paragraph; the clip keeps each column to its own.
    var marksMove = animation != null && animation.on && reveal < 1;
    paintPartMarks(canvas, painter, text, parts, spec, at,
        behind: true,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);

    // words draws this column's share, a closure as in paintTextInBox.
    void words({TextDrawPhase phase = TextDrawPhase.all}) {
      // A block motion is already applied outside; parts arriving on their
      // own still animate here.
      var animating = (!asBlock && moving) || (!asOne && partsAnimate(parts));
      if (animating) {
        // Only the pieces whose lines fall in this column; their places in
        // the whole paragraph set their progress.
        paintAnimatedText(canvas, painter, text, spec, at,
            animation ?? const TextAnimation(), reveal,
            maxWidth: width,
            outline: outline,
            soft: soft,
            parts: parts,
            timings: timings,
            asOne: asOne,
            phase: phase, keep: (piece) {
          // A block-scoped piece covers the paragraph, which every column
          // shares: it moves or uncovers the same way in each.
          if (piece.box.height >= painter.height - 0.5) return true;
          var middle = piece.box.center.dy;
          return middle >= top(from) - 0.5 && middle < top(to) + 0.5;
        });
        return;
      }
      if (phase.drawsOutline) soft?.paint(canvas, at);
      if (phase.drawsOutline) outline?.paint(canvas, at);
      if (phase.drawsLetters) painter.paint(canvas, at);
    }

    var column = Rect.fromLTWH(left, box.top + dy, width, used);
    if (!spec.fill.on) {
      words();
    } else {
      words(phase: TextDrawPhase.behind);
      paintThroughText(canvas, column, spec.fill, images,
          () => words(phase: TextDrawPhase.letters),
          // Under a block motion (applied outside) the words here are
          // still, so the fill has nothing to follow.
          animation: asBlock ? null : animation,
          reveal: reveal,
          moving: at & painter.size);
    }

    paintPartMarks(canvas, painter, text, parts, spec, at,
        behind: false,
        timings: timings,
        moving: marksMove ? animation : null,
        at: reveal);
    canvas.restore();
  }

  // Rules run down the text (the tallest column), not the whole box.
  var tallest = 0.0;
  for (var (from, to) in runs) {
    tallest = math.max(tallest, top(to) - top(from));
  }
  // Starting where that column's text starts under the vertical alignment.
  var above = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.middle => (box.height - tallest) / 2,
    VerticalAlignSpec.bottom => box.height - tallest,
  };
  _paintColumnRules(canvas, box, columns, width, above, tallest);

  // Restored only after the rules, so they arrive with the columns.
  for (var r = 0; r < depth; r++) {
    canvas.restore();
  }
}

/// _paintColumnRules draws the line down the middle of each gutter, from
/// [above] for [textHeight], how far the text reaches.
void _paintColumnRules(ui.Canvas canvas, Rect box, TextColumns columns,
    double width, double above, double textHeight) {
  if (columns.ruleStyle == ColumnRuleStyle.none ||
      columns.ruleWidth <= 0 ||
      columns.gap <= 0) {
    return;
  }

  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = columns.ruleWidth
    ..strokeCap = columns.ruleStyle == ColumnRuleStyle.dotted
        ? StrokeCap.round
        : StrokeCap.butt
    ..color = columns.ruleColor;

  // A little past the last line, which otherwise reads as too short.
  var from = box.top + (textHeight <= 0 ? 0 : above.clamp(0, box.height));
  var reach = textHeight <= 0
      ? box.height
      : math.min(box.bottom - from, textHeight * 1.02 + columns.ruleWidth * 2);

  for (var i = 1; i < columns.count; i++) {
    var x = box.left + i * (width + columns.gap) - columns.gap / 2;
    var line = ui.Path()
      ..moveTo(x, from)
      ..lineTo(x, from + reach);
    canvas.drawPath(
      switch (columns.ruleStyle) {
        ColumnRuleStyle.dashed =>
          dashPath(line, columns.ruleWidth * 4, columns.ruleWidth * 3),
        // Near-zero dashes with a round cap are dots.
        ColumnRuleStyle.dotted => dashPath(line, 0.01, columns.ruleWidth * 3),
        _ => line,
      },
      paint,
    );
  }
}

/// PlacedGlyph is one letter of text on a curve, placed by placeTextOnPath.
class PlacedGlyph {
  final String glyph;

  /// at is where the glyph's baseline centre sits, and angle is the heading of
  /// the curve there.
  final Offset at;
  final double angle;
  final Size size;

  /// index is where this glyph starts in the text it came from, so the
  /// parts covering it can be found.
  final int index;

  /// spec is what this glyph is drawn in, the element's own unless a part
  /// says otherwise: carried so the letter measured is the letter drawn.
  final TextSpec spec;

  const PlacedGlyph(this.glyph, this.at, this.angle, this.size,
      {this.index = 0, this.spec = const TextSpec()});
}

/// placeTextOnPath works out where every letter of [text] goes along [curve].
///
/// Separate from the drawing so the selection box and the painter agree on
/// where the letters are. [curve] is a polyline in document space, sampled
/// finely enough to walk in straight steps (see scene_renderer.dart's
/// _curveSamplesPerSegment).
List<PlacedGlyph> placeTextOnPath(
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,

  /// parts colour, embolden or italicise some letters (TextPart); needed
  /// here because they change letter widths.
  List<TextPart> parts = const [],
}) {
  if (text.isEmpty || curve.length < 2) return const [];

  // Cumulative distance along the polyline, so a position in length can be
  // turned into a point and a direction.
  var lengths = <double>[0];
  var total = 0.0;
  for (var i = 1; i < curve.length; i++) {
    total += (curve[i] - curve[i - 1]).distance;
    lengths.add(total);
  }
  if (total <= 0) return const [];

  var glyphs = <String>[];
  var at0 = <int>[];
  var offset = 0;
  for (var rune in text.runes) {
    var g = String.fromCharCode(rune);
    glyphs.add(g);
    at0.add(offset);
    offset += g.length;
  }
  var specs = [
    for (var i = 0; i < glyphs.length; i++)
      _specForPart(spec, partAt(text, parts, at0[i])),
  ];
  var painters = [
    for (var i = 0; i < glyphs.length; i++)
      layoutText(glyphs[i], specs[i], maxWidth: double.infinity, scale: scale),
  ];
  var widths = [for (var p in painters) p.width + on.spacing * scale];
  var runLength = widths.fold(0.0, (sum, w) => sum + w);

  // Where the run starts, from the spec's own alignment plus the slide.
  var at = switch (spec.align) {
        TextAlignSpec.left => 0.0,
        TextAlignSpec.center => (total - runLength) / 2,
        TextAlignSpec.right => total - runLength,
        TextAlignSpec.justify => 0.0,
      } +
      on.offset * total;

  var out = <PlacedGlyph>[];
  for (var i = 0; i < glyphs.length; i++) {
    var centre = at + widths[i] / 2;
    at += widths[i];
    // Past the ends of the line the letters carry straight on rather than
    // being dropped, so a slide travels off the line -- see _alongPolyline.
    var (point, angle) = _alongPolyline(curve, lengths, centre);
    out.add(PlacedGlyph(
        glyphs[i], point, angle, Size(painters[i].width, painters[i].height),
        index: at0[i], spec: specs[i]));
  }
  return out;
}

/// _animatedPartAt is which part arriving on its own account covers the
/// character at [index], or -1 for none.
int _animatedPartAt(String text, List<TextPart> parts, int index) {
  var found = -1;
  for (var (i, part) in parts.indexed) {
    if (!part.animation.on) continue;
    var range = rangeOf(text, part);
    if (range == null) continue;
    if (index >= range.$1 && index < range.$2) found = i;
  }
  return found;
}

/// _specForPart is [spec] with whatever [part] says about these letters.
TextSpec _specForPart(TextSpec spec, TextPart? part) {
  if (part == null) return spec;
  return spec.copyWith(
    color: part.color ?? spec.color,
    weight: part.weight ?? spec.weight,
    italic: part.italic ?? spec.italic,
    outlineWidth: part.outlineWidth ?? spec.outlineWidth,
    outlineColor: part.outlineColor ?? spec.outlineColor,
  );
}

/// textOnPathBounds is the rectangle the placed letters occupy.
///
/// Round every glyph's four turned corners, not just the points they sit on.
Rect? textOnPathBounds(List<PlacedGlyph> glyphs, TextOnCurve on) {
  if (glyphs.isEmpty) return null;
  double? left, top, right, bottom;

  for (var g in glyphs) {
    var dy = on.away ? 0.0 : -g.size.height;
    var cos = math.cos(g.angle);
    var sin = math.sin(g.angle);
    for (var corner in [
      Offset(-g.size.width / 2, dy),
      Offset(g.size.width / 2, dy),
      Offset(-g.size.width / 2, dy + g.size.height),
      Offset(g.size.width / 2, dy + g.size.height),
    ]) {
      var x = g.at.dx + corner.dx * cos - corner.dy * sin;
      var y = g.at.dy + corner.dx * sin + corner.dy * cos;
      left = left == null ? x : math.min(left, x);
      right = right == null ? x : math.max(right, x);
      top = top == null ? y : math.min(top, y);
      bottom = bottom == null ? y : math.max(bottom, y);
    }
  }
  return Rect.fromLTRB(left!, top!, right!, bottom!);
}

/// paintTextOnPath lays [text] out along [curve], one glyph at a time.
///
/// Glyph by glyph so each letter turns with the line. [animation] and
/// [reveal] draw it part way through arriving: the paragraph motions (see
/// applyMotion) applied in each glyph's turned frame, so a letter on a bend
/// rises along the line.
void paintTextOnPath(
  ui.Canvas canvas,
  String text,
  TextSpec spec,
  List<Offset> curve,
  TextOnCurve on, {
  double scale = 1,
  TextAnimation? animation,
  double reveal = 1,
  List<TextPart> parts = const [],
  List<PartTiming> timings = const [],
  bool asOne = false,
  CanvasImageSource? images,

  /// outlineOnly and fillOnly are the two passes for a filled run: the
  /// outlines in their own colour, then the letters inside the fill's layer.
  bool outlineOnly = false,
  bool fillOnly = false,
}) {
  var glyphs =
      placeTextOnPath(text, spec, curve, on, scale: scale, parts: parts);
  if (glyphs.isEmpty) return;

  // The line as a window: whatever has slid off its ends is cut off by a
  // ribbon round the polyline (not a box), so a bend masks along the bend.
  var masked = on.mask;
  if (masked) {
    canvas.save();
    canvas.clipPath(_curveRibbon(curve, spec.fontSize * scale * 3));
  }
  if (masked) {
    // The mask is this call's own; the two passes a fill makes are inside it.
    paintTextOnPath(canvas, text, spec, curve, on.copyWith(mask: false),
        scale: scale,
        animation: animation,
        reveal: reveal,
        parts: parts,
        timings: timings,
        asOne: asOne,
        images: images,
        outlineOnly: outlineOnly,
        fillOnly: fillOnly);
    canvas.restore();
    return;
  }

  if (spec.fill.on && !outlineOnly && !fillOnly) {
    var box = textOnPathBounds(glyphs, on) ?? _boundsOf(curve);
    paintTextOnPath(canvas, text, spec, curve, on,
        scale: scale,
        animation: animation,
        reveal: reveal,
        parts: parts,
        timings: timings,
        asOne: asOne,
        outlineOnly: true);
    paintThroughText(
        canvas,
        box,
        spec.fill,
        images,
        () => paintTextOnPath(canvas, text, spec, curve, on,
            scale: scale,
            animation: animation,
            reveal: reveal,
            parts: parts,
            timings: timings,
            asOne: asOne,
            fillOnly: true));
    return;
  }

  var moving =
      animation != null && animation.on && (reveal < 1 || animation.keeps);

  // Which layer each letter belongs to: the index of a part arriving on its
  // own account, or -1 for the paragraph's arrival.
  var layer = <int>[
    for (var g in glyphs) asOne ? -1 : _animatedPartAt(text, parts, g.index),
  ];

  // animationOf is what moves a layer and revealOf how far through it is.
  TextAnimation? animationOf(int of) =>
      of < 0 ? (moving ? animation : null) : parts[of].animation.asAnimation;
  double revealOf(int of) =>
      of < 0 ? reveal : (of < timings.length ? timings[of].words : 1);

  // Each letter's place in its layer's order, and how many places the layer
  // has: words for a word scope, letters for a letter scope, one for a block.
  var place = List<int>.filled(glyphs.length, 0);
  var places = <int, int>{};
  for (var of in layer.toSet()) {
    var mine = [
      for (var i = 0; i < glyphs.length; i++)
        if (layer[i] == of) i,
    ];
    var scope = animationOf(of)?.preset.scope ?? TextAnimationScope.block;
    if (scope == TextAnimationScope.word) {
      var word = -1;
      var inWord = false;
      for (var i in mine) {
        var space = glyphs[i].glyph.trim().isEmpty;
        if (!space && !inWord) word++;
        inWord = !space;
        place[i] = math.max(0, word);
      }
      places[of] = math.max(1, word + 1);
    } else if (scope == TextAnimationScope.letter) {
      for (var (n, i) in mine.indexed) {
        place[i] = n;
      }
      places[of] = math.max(1, mine.length);
    } else {
      for (var i in mine) {
        place[i] = 0;
      }
      places[of] = 1;
    }
  }

  for (var (i, g) in glyphs.indexed) {
    var dy = on.away ? 0.0 : -g.size.height;
    // The glyph's rectangle in its own frame, origin at its baseline centre.
    var local = Rect.fromLTWH(
        -g.size.width / 2, dy, g.size.width, math.max(1, g.size.height));

    // anim is null exactly when this letter is not moving.
    var mine = layer[i];
    var anim = animationOf(mine);
    var over = revealOf(mine);
    if (anim != null && !anim.on) anim = null;
    if (anim != null && over >= 1 && !anim.keeps) anim = null;
    var p =
        anim == null ? 1.0 : anim.progressAt(over, place[i], places[mine] ?? 1);
    if (p <= 0 && anim != null && !anim.keeps) continue;

    canvas.save();
    canvas.translate(g.at.dx, g.at.dy);
    canvas.rotate(g.angle);

    var frame = anim == null
        ? const MotionFrame(1, 0, false)
        : applyMotionSpec(canvas, local, anim.spec, p,
            from: anim.spec.from, seed: g.index);

    // A mark is drawn a letter at a time in each letter's frame, so it
    // follows the curve. It sweeps in letter order whatever the scope, or a
    // block underline would grow under every letter at once.
    var sweep =
        anim == null ? 1.0 : (p * glyphs.length - i).clamp(0.0, 1.0).toDouble();
    // Only on the pass outside the fill's layer, so a translucent band is
    // laid once and in its own colour.
    if (anim != null &&
        anim.preset.motion == TextMotion.highlight &&
        !fillOnly) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: false);
    }

    // An echo's or trail's copies, in the turned frame so they fan along the
    // line, and before the letter so they sit behind it.
    if (anim != null &&
        (anim.preset.motion == TextMotion.echo ||
            anim.preset.motion == TextMotion.trail)) {
      _paintCurveCopies(canvas, g, dy, scale, local, anim, p,
          outlineOnly: outlineOnly, fillOnly: fillOnly);
    }

    // Stroke-on: the outline is written letter after letter (applyMotion
    // leaves opacity alone, so it is done here). The letters are already
    // there unless TextDrawStart.fadeText brings them in with it. The outline
    // colour comes from outlineSpecFor.
    var strokeOn = anim != null && anim.preset.motion == TextMotion.strokeOn;
    double? outlineAlpha, fillAlpha;
    if (strokeOn) {
      outlineAlpha = ((p * glyphs.length) - i).clamp(0.0, 1.0).toDouble();
      fillAlpha = anim.draw.start == TextDrawStart.fadeText ? p : null;
    }
    _paintGlyph(canvas, g, dy, scale, frame.alpha,
        outlineOnly: outlineOnly,
        fillOnly: fillOnly,
        outlineAlpha: outlineAlpha,
        fillAlpha: fillAlpha);

    if (anim != null &&
        anim.preset.motion == TextMotion.underline &&
        !fillOnly) {
      _paintCurveMark(canvas, local, anim.draw, spec, sweep, under: true);
    }

    for (var r = 0; r < frame.depth; r++) {
      canvas.restore();
    }
    canvas.restore();
  }
}

/// _curveRibbon is a band of width [thick] following [curve], used as the mask
/// that keeps a sliding caption inside its line.
///
/// Built from the polyline's normals, giving a fill shape to clip with.
/// Self-crossing on a tight bend is harmless under the non-zero rule.
Path _curveRibbon(List<Offset> curve, double thick) {
  var path = Path();
  if (curve.length < 2) return path;
  var half = math.max(1.0, thick) / 2;

  Offset normalAt(int i) {
    var a = curve[i == 0 ? 0 : i - 1];
    var b = curve[i == curve.length - 1 ? i : i + 1];
    var d = b - a;
    var length = d.distance;
    if (length <= 0) return const Offset(0, -1);
    return Offset(-d.dy / length, d.dx / length);
  }

  var left = <Offset>[];
  var right = <Offset>[];
  for (var i = 0; i < curve.length; i++) {
    var n = normalAt(i) * half;
    left.add(curve[i] + n);
    right.add(curve[i] - n);
  }

  path.moveTo(left.first.dx, left.first.dy);
  for (var p in left.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (var p in right.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// _boundsOf is a box round a polyline, for a run with nothing placed on it.
Rect _boundsOf(List<Offset> curve) {
  var box = Rect.fromLTWH(curve.first.dx, curve.first.dy, 1, 1);
  for (var p in curve.skip(1)) {
    box = box.expandToInclude(Rect.fromLTWH(p.dx, p.dy, 1, 1));
  }
  return box;
}

/// _paintGlyph draws one placed letter, and its outline where it has one.
/// [outlineAlpha] and [fillAlpha] fade the stroke and the fill separately,
/// for stroke-on; null for every other preset.
void _paintGlyph(
    ui.Canvas canvas, PlacedGlyph g, double dy, double scale, double alpha,
    {bool outlineOnly = false,
    bool fillOnly = false,
    double? outlineAlpha,
    double? fillAlpha}) {
  var at = Offset(-g.size.width / 2, dy);
  var room = Rect.fromLTWH(at.dx, at.dy, g.size.width, g.size.height)
      .inflate(g.size.height * 2);

  // half draws one of the two at its own opacity, through a layer if needed.
  void half(double at2, void Function() what) {
    if (at2 <= 0) return;
    if (at2 >= 1) {
      what();
      return;
    }
    canvas.saveLayer(room, Paint()..color = Color.fromRGBO(0, 0, 0, at2));
    what();
    canvas.restore();
  }

  var faded = alpha < 1;
  if (faded) {
    if (alpha <= 0) return;
    canvas.saveLayer(
        room, Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)));
  }
  if (!fillOnly) {
    softFor(g.glyph, g.spec,
            maxWidth: double.infinity, scale: scale, fillWidth: false)
        ?.paint(canvas, at);
  }
  if (g.spec.outlineWidth > 0 && !fillOnly) {
    half(
        outlineAlpha ?? 1,
        () => layoutText(g.glyph, g.spec,
                maxWidth: double.infinity, scale: scale, outline: true)
            .paint(canvas, at));
  }
  if (!outlineOnly) {
    half(
        fillAlpha ?? 1,
        () =>
            layoutText(g.glyph, g.spec, maxWidth: double.infinity, scale: scale)
                .paint(canvas, at));
  }
  if (faded) canvas.restore();
}

/// _paintCurveMark is an underline or a highlight under one letter of a
/// curve, [sweep] of the way drawn.
void _paintCurveMark(ui.Canvas canvas, Rect local, TextDrawSpec mark,
    TextSpec spec, double sweep,
    {required bool under}) {
  if (sweep <= 0) return;
  // The letter's share of the mark, widened by the mark's padding.
  var left = local.left - mark.padLeft;
  var right = local.right + mark.padRight;
  var width = (right - left) * sweep;
  if (under) {
    var y = local.bottom + mark.padBottom;
    canvas.drawRect(
        Rect.fromLTWH(left, y, width, math.max(1, local.height * 0.06)),
        Paint()..color = mark.color ?? spec.color);
    return;
  }
  var band = Rect.fromLTWH(left, local.top - mark.padTop, width,
      local.height + mark.padTop + mark.padBottom);
  var paint = Paint()..color = mark.color ?? spec.color.withValues(alpha: 0.25);
  if (mark.radius <= 0) {
    canvas.drawRect(band, paint);
    return;
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(band, Radius.circular(mark.radius)), paint);
}

/// _paintCurveCopies draws an echo's or a trail's copies of one letter.
void _paintCurveCopies(ui.Canvas canvas, PlacedGlyph g, double dy, double scale,
    Rect local, TextAnimation animation, double p,
    {bool outlineOnly = false, bool fillOnly = false}) {
  var echo = animation.echo;
  var preset = animation.preset;
  var trail = preset.motion == TextMotion.trail;
  var step = trail
      ? Offset(local.width * preset.dx * (1 - p),
              local.height * preset.dy * (1 - p)) *
          (echo.spacing / math.max(1, echo.copies))
      : Offset(
          preset.dx * local.height * echo.spacing,
          preset.dy == 0
              ? local.height * echo.spacing
              : preset.dy * local.height * echo.spacing,
        );
  var ways = preset.turns > 0 && !trail ? const [1.0, -1.0] : const [1.0];

  // See the same two halves in _paintPiece: fan out, then go.
  var resolving = echo.resolve && !trail;
  var fanning = resolving ? (p * 2).clamp(0.0, 1.0) : p;
  var going = resolving ? (p * 2 - 1).clamp(0.0, 1.0) : 0.0;

  for (var way in ways) {
    for (var c = echo.copies; c >= 1; c--) {
      var arrived =
          trail ? 1.0 : (fanning * (echo.copies + 1) - (c - 1)).clamp(0.0, 1.0);
      if (arrived <= 0) continue;
      var strength = echo.fade;
      for (var i = 1; i < c; i++) {
        strength *= echo.fade;
      }
      if (trail) strength *= (1 - p);
      if (going > 0) strength *= (1 - going) * (1 - going);
      if (strength <= 0.002) continue;

      var away = step * (c * arrived * (1 + going * 2.5)) * way;
      var size = math.pow(echo.shrink, c).toDouble();
      canvas.save();
      canvas.translate(away.dx, away.dy);
      if (size != 1) canvas.scale(size, size);
      _paintGlyph(canvas, g, dy, scale, (strength * arrived).clamp(0.0, 1.0),
          outlineOnly: outlineOnly, fillOnly: fillOnly);
      canvas.restore();
    }
  }
}

/// _alongPolyline is the point and heading at [distance] along [curve].
/// Before the start and past the end it carries on along the heading there
/// rather than clamping, so a caption slid off the line keeps travelling.
(Offset, double) _alongPolyline(
    List<Offset> curve, List<double> lengths, double distance) {
  for (var i = 1; i < lengths.length; i++) {
    if (lengths[i] < distance) continue;
    var span = lengths[i] - lengths[i - 1];
    var t = span <= 0 ? 0.0 : (distance - lengths[i - 1]) / span;
    var a = curve[i - 1], b = curve[i];
    var direction = b - a;
    return (
      Offset(a.dx + direction.dx * t, a.dy + direction.dy * t),
      math.atan2(direction.dy, direction.dx),
    );
  }
  var last = curve.last - curve[curve.length - 2];
  var length = last.distance;
  var beyond = distance - lengths.last;
  var heading = math.atan2(last.dy, last.dx);
  if (length <= 0) return (curve.last, heading);
  return (curve.last + last / length * beyond, heading);
}

/// bubbleBodyRect is the part of a speech bubble the words go in.
///
/// The box holds the tail too, so the body gives up room only on the sides
/// the tail points towards.
Rect bubbleBodyRect(Rect rect, SpeechBubbleSpec bubble) {
  if (bubble.tail == BubbleTail.none) return rect;
  var radians = bubble.tailAngle * math.pi / 180;
  var dx = math.cos(radians);
  var dy = math.sin(radians);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  return Rect.fromLTRB(
    rect.left + (dx < 0 ? -dx * reach : 0),
    rect.top + (dy < 0 ? -dy * reach : 0),
    rect.right - (dx > 0 ? dx * reach : 0),
    rect.bottom - (dy > 0 ? dy * reach : 0),
  );
}

/// bubblePath is a speech bubble as one outline.
///
/// Body and tail are unioned (Path.combine) so a stroke draws one boundary,
/// with no line across the join.
Path bubblePath(Rect rect, SpeechBubbleSpec bubble, double cornerRadius) {
  var body = bubbleBodyRect(rect, bubble);
  var shape = _bubbleBody(body, bubble.body, cornerRadius);
  if (bubble.tail == BubbleTail.none) return shape;

  var radians = bubble.tailAngle * math.pi / 180;
  var out = Offset(math.cos(radians), math.sin(radians));
  // Where the tail leaves the body: on the body's ellipse in that direction,
  // so a tail at 45 degrees leaves from the corner.
  var anchor = Offset(body.center.dx + out.dx * body.width / 2,
      body.center.dy + out.dy * body.height / 2);
  var reach = rect.shortestSide / 2 * bubble.tailLength;
  var tip = anchor + out * reach;

  // A thought bubble's tail is a trail of separate shrinking circles.
  if (bubble.tail == BubbleTail.thought) {
    var trail = Path();
    var count = 3;
    var unit = rect.shortestSide / 2 * bubble.tailWidth * 0.5;
    // From the body's rectangle edge, not the ellipse the pointer uses, which
    // most bodies reach past, so the dots do not weld to the body.
    var edge = _rayToRect(body, out);
    for (var i = 0; i < count; i++) {
      var t = i / (count - 1);
      var at = edge + out * (unit * 1.6 + reach * 0.9 * t);
      trail.addOval(Rect.fromCircle(center: at, radius: unit * (1 - t * 0.4)));
    }
    return Path.combine(PathOperation.union, shape, trail);
  }

  var across =
      Offset(-out.dy, out.dx) * (rect.shortestSide / 2 * bubble.tailWidth / 2);
  // Started inside the body so the union leaves no hairline at the join.
  var root = anchor - out * (reach * 0.35);
  var tail = Path()..moveTo(root.dx + across.dx, root.dy + across.dy);

  if (bubble.tail == BubbleTail.curved) {
    // A hooked tail: it leaves the body square and bends as it narrows.
    var bend = Offset(-out.dy, out.dx) * (reach * bubble.curl);
    tail
      ..quadraticBezierTo(
          anchor.dx + bend.dx, anchor.dy + bend.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(anchor.dx + bend.dx * 0.35,
          anchor.dy + bend.dy * 0.35, root.dx - across.dx, root.dy - across.dy);
  } else {
    tail
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(root.dx - across.dx, root.dy - across.dy);
  }
  tail.close();

  return Path.combine(PathOperation.union, shape, tail);
}

/// _rayToRect is where a ray from [rect]'s centre in direction [out] crosses
/// its edge.
Offset _rayToRect(Rect rect, Offset out) {
  var half = Offset(rect.width / 2, rect.height / 2);
  var scaleX = out.dx == 0 ? double.infinity : (half.dx / out.dx).abs();
  var scaleY = out.dy == 0 ? double.infinity : (half.dy / out.dy).abs();
  var scale = math.min(scaleX, scaleY);
  if (!scale.isFinite) return rect.center;
  return rect.center + out * scale;
}

Path _bubbleBody(Rect body, BubbleBody kind, double cornerRadius) {
  var path = Path();
  switch (kind) {
    case BubbleBody.rounded:
      var r = math.min(
          cornerRadius > 0 ? cornerRadius : body.shortestSide * 0.22,
          body.shortestSide / 2);
      path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(r)));
    case BubbleBody.oval:
      path.addOval(body);
    case BubbleBody.cloud:
      // Overlapping circles round the rim, unioned into one puffy outline.
      var lumps = Path()..addOval(body.deflate(body.shortestSide * 0.14));
      const count = 11;
      for (var i = 0; i < count; i++) {
        var a = i * 2 * math.pi / count;
        var at = Offset(body.center.dx + math.cos(a) * body.width * 0.36,
            body.center.dy + math.sin(a) * body.height * 0.36);
        lumps = Path.combine(
            PathOperation.union,
            lumps,
            Path()
              ..addOval(Rect.fromCircle(
                  center: at, radius: body.shortestSide * 0.19)));
      }
      return lumps;
    case BubbleBody.burst:
      // A shout: alternating long and short points all the way round.
      const spikes = 12;
      for (var i = 0; i < spikes * 2; i++) {
        var a = -math.pi / 2 + i * math.pi / spikes;
        var far = i.isEven ? 1.0 : 0.74;
        var p = Offset(body.center.dx + math.cos(a) * body.width / 2 * far,
            body.center.dy + math.sin(a) * body.height / 2 * far);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
  }
  return path;
}

/// textRunBox is where a stretch of [text] lands inside [box], laid out and
/// aligned exactly as paintTextInBox would lay it out.
///
/// For drawing something behind part of a line, such as a table chip, from
/// the glyphs' own boxes. Null when the range is empty or outside the text.
Rect? textRunBox(String text, TextSpec spec, Rect box, int start, int end) {
  var shown = spec.textCase.apply(text);
  if (start < 0 || end > shown.length || end <= start || box.width <= 0) {
    return null;
  }

  var painter = layoutText(shown, spec, maxWidth: box.width, fillWidth: true);
  var boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end));
  if (boxes.isEmpty) return null;

  // The same vertical placement as textOffsetIn.
  var dy = switch (spec.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  var out = boxes.first.toRect();
  for (var b in boxes.skip(1)) {
    out = out.expandToInclude(b.toRect());
  }
  return out.translate(box.left, box.top + dy);
}

/// _fades is whether the letters are painted with a gradient rather than one
/// colour: one is set, there is a box to run it across, and no override
/// colour has claimed them.
bool _fades(TextSpec spec, Color? colorOverride, Rect? over) =>
    spec.fade != null && colorOverride == null && over != null && !over.isEmpty;

/// textStyleOf is one TextSpec as Flutter sees it, the one place a spec's
/// settings become a TextStyle (paintRunsInBox uses it per run too).
TextStyle textStyleOf(
  TextSpec spec, {
  double scale = 1,
  Color? colorOverride,
  bool outline = false,

  /// over is the box the words are drawn in, for a colour that fades across
  /// the whole box (a style is built before layout, so the letters have no
  /// bounds yet). Null gives a flat colour.
  Rect? over,

  /// soft draws the shadow and the glow with clear glyphs. A pass of its own
  /// so the order is shadow, outline, words, and so a fill layer does not
  /// recolour the glow.
  bool soft = false,
}) =>
    TextStyle(
      fontFamily: spec.fontFamily,
      fontSize: spec.fontSize * scale,
      fontWeight: spec.fontWeight,
      fontStyle: spec.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          spec.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: colorOverride ?? spec.color,
      letterSpacing: spec.letterSpacing * scale,
      height: spec.lineHeight,
      // A fade is a foreground shader, the slot the outline uses, so the
      // outline wins; an override colour wins too. A TextStyle cannot have
      // both color and foreground.
      color: soft
          ? const Color(0x00000000)
          : (outline || _fades(spec, colorOverride, over)
              ? null
              : (colorOverride ?? spec.color)),
      foreground: soft
          ? null
          : outline
              ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = spec.outlineWidth * 2 * scale
                ..color = spec.outlineColor)
              : _fades(spec, colorOverride, over)
                  ? (Paint()
                    ..shader = PaintSpec(spec.color, gradient: spec.fade)
                        .shaderFor(over!))
                  : null,
      shadows: soft ? softShadows(spec, scale) : null,
    );

/// softShadows is what falls behind the letters: the glow first, then the
/// shadow over it.
List<Shadow> softShadows(TextSpec spec, double scale) => [
      if (spec.glowBlur > 0)
        Shadow(
          color: spec.glowColor,
          blurRadius: spec.glowBlur * scale,
        ),
      if (spec.shadowBlur > 0 || spec.shadowDistance > 0)
        Shadow(
          color: spec.shadowColor,
          blurRadius: spec.shadowBlur * scale,
          offset: spec.shadowOffset * scale,
        ),
    ];

/// paintRunsInBox draws one line made of stretches of differently styled
/// text, laid out and aligned as paintTextInBox would lay out one stretch.
///
/// One paragraph of spans, not pieces placed by adding widths, so the line
/// still aligns as a whole. Used by table cells whose rules style parts.
double paintRunsInBox(
  ui.Canvas canvas,
  List<(String, TextSpec)> runs,
  TextSpec base,
  Rect box, {
  bool clip = false,
}) {
  if (runs.isEmpty || box.width <= 0) return 0;

  var painter = TextPainter(
    text: TextSpan(
      style: textStyleOf(base),
      children: [
        for (var (text, spec) in runs)
          TextSpan(text: spec.textCase.apply(text), style: textStyleOf(spec)),
      ],
    ),
    textAlign: base.align.flutter,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(minWidth: box.width, maxWidth: box.width);

  var dy = switch (base.verticalAlign) {
    VerticalAlignSpec.top => 0.0,
    VerticalAlignSpec.bottom => box.height - painter.height,
    VerticalAlignSpec.middle => (box.height - painter.height) / 2,
  };

  if (clip) {
    canvas.save();
    canvas.clipRect(box);
  }
  painter.paint(canvas, Offset(box.left, box.top + dy));
  if (clip) canvas.restore();
  return painter.height;
}

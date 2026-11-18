part of 'paint_util.dart';

// What is laid on or behind the words: a picture or pattern filling the
// letters, the icon a text element carries, and the highlights and underlines
// that mark its parts. Part of paint_util.dart.

/// paintThroughText draws [fill] cut to the shape of the letters: the words,
/// then the fill composited onto them with srcIn, since a shader on the
/// text paint could not draw a pattern of many strokes. The fill spans the
/// whole box, so it runs through the word. [animation] and [reveal] are
/// what the words are doing, for a fill locked to them (TextFill.locked);
/// [moving] is the paragraph's box, so the fill travels as the letters do.
void paintThroughText(ui.Canvas canvas, Rect box, TextFill fill,
    CanvasImageSource? images, void Function() words,
    {TextAnimation? animation, double reveal = 1, Rect? moving}) {
  if (!fill.on) {
    words();
    return;
  }

  // Room for wherever the letters go (shadow, outline, motionRoom), or the
  // fill is clipped while the outline, drawn outside this layer, is not.
  var area = (animation == null || moving == null
          ? box
          : box.expandToInclude(motionRoom(moving, animation)))
      .inflate(box.shortestSide * 0.5 + 8);
  canvas.saveLayer(area, Paint());
  words();
  // srcIn cuts what is drawn here to the letters. The opacity is on the
  // layer, so a pattern's ground and ink fade together.
  var through = fill.opacity.clamp(0.0, 1.0);
  canvas.saveLayer(
      area,
      Paint()
        ..blendMode = ui.BlendMode.srcIn
        ..color = ui.Color.fromRGBO(0, 0, 0, through));

  // Zoomed about the middle: 1 fits what is drawn across the words, 2 shows
  // a quarter of it at twice the size.
  var zoom = fill.zoom <= 0 ? 1.0 : fill.zoom;
  var frame = Rect.fromCenter(
      center:
          box.center + Offset(fill.panX * box.width, fill.panY * box.height),
      width: box.width * zoom,
      height: box.height * zoom);

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
      // The pattern's ground under the whole reach, so no letter outside the
      // frame is hollow; the pattern keeps the frame, or it would resize.
      if (reach != frame) {
        canvas.drawRect(reach, Paint()..color = fill.pattern.background);
      }
      paintProcedural(canvas, frame, fill.pattern);
    case TextFillKind.image:
      var image = images?.resolve(fill.assetId, const BackgroundRemoval());
      if (image != null) {
        // A picture element's look and two sliders as one matrix (image_look).
        var matrix = combineMatrices(presetMatrix(fill.filter),
            colorMatrix(fill.saturation, fill.brightness));
        _paintFillImage(canvas, reach, frame, image, fill.tile,
            matrix == null ? null : ColorFilter.matrix(matrix));

        // The overlay, inside this layer so it blends only with the picture.
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

/// _paintFillImage covers the words with a picture, or tiles it. [reach] is
/// everywhere to cover: the frame the picture is sized to, grown to take in
/// wherever the words go while they arrive.
void _paintFillImage(ui.Canvas canvas, Rect reach, Rect frame, ui.Image image,
    bool tile, ColorFilter? look) {
  var size = Size(image.width.toDouble(), image.height.toDouble());
  if (size.isEmpty) return;

  if (tile) {
    // A repeating fill is a shader, not a loop, so copies cost nothing.
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

  // Covering: frame filled, overspill cropped, aspect kept. A clamped shader,
  // not drawImageRect, so a letter past the picture takes its edge.
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

/// paintTextIcon draws the picture a text element carries: a vector where
/// the asset is one, so it is sharp at any size.
void paintTextIcon(ui.Canvas canvas, Rect box, TextIcon icon,
    CanvasImageSource? images, TextSpec spec) {
  if (!icon.on || box.width <= 0 || box.height <= 0) return;

  paintBox(canvas, box, icon.box, images);
  var inner = icon.box.inner(box);
  if (inner.width <= 0 || inner.height <= 0) return;

  // The drawing where the asset is one, else the raster, also for a drawing
  // with no usable size (an .svg with no width, height or viewBox).
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

  // Turned about its middle: the outline and tint turn with it, the
  // underline below stays level.
  var turned = icon.turn != 0;
  if (turned) {
    canvas.save();
    canvas.translate(at.center.dx, at.center.dy);
    canvas.rotate(icon.turn * math.pi / 180);
    canvas.translate(-at.center.dx, -at.center.dy);
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
  if (turned) canvas.restore();

  if (icon.underline != null) {
    _paintPartUnderline(canvas, at, icon.underline!, icon.color ?? spec.color);
  }
}

/// marksRoom is how far outside the words the parts' marks reach, per side,
/// for a clip to grow by: otherwise a highlight's padding is clipped at the
/// box edge of a left- or right-aligned line.
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

/// paintPartMarks draws highlights behind, or underlines under, the parts:
/// called with [behind] before the words, then after, so a descender does
/// not sit on the line. Marks follow the selection boxes, so a part across
/// a line break is marked per line. [timings] is how much of each is drawn
/// on; [moving] and [at] the animation, so a mark moves with its words.
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

/// _wobble is a line not quite straight: two sines of different lengths, so
/// it wanders rather than waves; [tilt] leans the whole line.
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

/// _brush is a marker stroke: a filled shape, its thickness varying, tapered.
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

part of 'scene_renderer.dart';

// Drawing a picture or video element: fitting and colouring the picture, its
// warp, outline and placeholder, its drift and per-layer loops, and layers
// arriving one at a time. Part of scene_renderer.dart.

/// _LayerArrive draws one layer of a picture coming in a layer at a time:
/// [draw] as [layer] is at this frame of its own arrival, about [box].
typedef _LayerArrive = void Function(
    ImageLayer layer, Rect box, void Function() draw);

/// _layerByLayer is how [e]'s layers come in one after another -- its arrival
/// played for each in turn, about the layer's own box -- or null where it
/// comes in as one or is leaving. See layerTimes.
_LayerArrive? _layerByLayer(ImageElement e, Keyframe pose) {
  if (!e.layered || !e.animation.on) return null;
  if ((pose.values[KeyframeChannel.close] ?? 0) > 0) return null;
  var stack = e.stack;
  if (!layersSequenced(stack)) return null;
  var (from, to) = _arrivalFrames(e, pose);
  if (from == null || to == null || to <= from) return null;
  var span = to - from;
  var times = layerTimes(stack, span);
  var through = pose.values[KeyframeChannel.reveal] ?? 1;
  var turns = {
    for (var (i, l) in stack.indexed) l.id: times[i],
  };
  return (layer, box, draw) {
    var (start, length) = turns[layer.id] ?? (0.0, span.toDouble());
    var reveal = ((through * span - start) / length).clamp(0.0, 1.0);
    // Nothing yet: not even a frame of it before its turn.
    if (reveal <= 0 && e.animation.preset != ElementAnimationPreset.none) {
      return;
    }
    paintArriving(
        _arrivingCanvas!,
        box,
        e.animation,
        pose.copyWith(values: {...pose.values, KeyframeChannel.reveal: reveal}),
        draw);
  };
}

/// _arrivingCanvas is the canvas a picture's layers are drawn on while they
/// arrive in turn, so the arrival draws wherever the layer is going.
ui.Canvas? _arrivingCanvas;

void _paintImage(
    ui.Canvas canvas, Rect bounds, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive}) {
  // The border goes over the picture, or the picture would cover it.
  paintBoxFill(canvas, bounds, e.box, images);
  // A drift on the whole picture (ElementLoop.driftAt) zooms or pans it as
  // one, like a documentary camera; a layered picture may pass its frame.
  var drift = _drifting(e.animation.loop);
  var steady = adjustSteadily;
  if (drift != null) {
    var inner = e.box.inner(bounds);
    canvas.save();
    // The frame is cut where the picture stands, before the drift moves it:
    // cut after, a round frame would zoom with the picture and be squared
    // off by the box (a circle drifting in came out an octagon).
    if (!e.layered || e.clip) _clipToFrame(canvas, inner, e, drifting: true);
    _applyDrift(canvas, inner, e.animation.loop, drift);
    // Its adjustments moved with it as pixels, not filtered where they
    // land: see adjustSteadily.
    adjustSteadily = true;
  }
  try {
    _paintImageInside(canvas, bounds, e, images,
        arrive: arrive, framed: drift != null);
  } finally {
    adjustSteadily = steady;
  }
  if (drift != null) canvas.restore();
  paintBoxBorder(canvas, bounds, e.box);
}

/// betweenFrames is how far past the drawn frame the editor's playhead is
/// (0 to 1) while it plays; 0 otherwise and in an export. Drifts use it so a
/// slow zoom does not step at the frame rate on a fast screen. Set round the
/// stage's drawing, as RasterCache.drafting is.
double betweenFrames = 0;

/// _drifting is how far through [loop]'s drift the picture is, or null.
double? _drifting(ElementLoop loop) {
  var clock = _imageClock;
  if (clock == null || !loop.preset.drifts) return null;
  return loop.driftAt(clock.at, arrived: clock.arrived, last: clock.last);
}

/// _applyDrift sets [canvas] to draw [box] [t] through [loop]'s drift: zoomed
/// about its middle, or held closer and panned; the box moves, uncut.
void _applyDrift(ui.Canvas canvas, Rect box, ElementLoop loop, double t) {
  var a = (driftPerStrength * loop.strength).clamp(0.0, 1.0);
  double s;
  var shift = Offset.zero;
  switch (loop.preset) {
    case LoopPreset.driftIn:
      s = 1 + a * t;
    case LoopPreset.driftOut:
      s = 1 + a * (1 - t);
    // The camera moves left: the picture slides right under it.
    case LoopPreset.driftLeft:
      s = 1 + a;
      shift = Offset((0.5 - t) * a * box.width, 0);
    case LoopPreset.driftRight:
      s = 1 + a;
      shift = Offset((t - 0.5) * -a * box.width, 0);
    case LoopPreset.driftUp:
      s = 1 + a;
      shift = Offset(0, (0.5 - t) * a * box.height);
    case LoopPreset.driftDown:
      s = 1 + a;
      shift = Offset(0, (t - 0.5) * -a * box.height);
    default:
      return;
  }
  var c = box.center;
  canvas.translate(c.dx + shift.dx, c.dy + shift.dy);
  canvas.scale(s);
  canvas.translate(-c.dx, -c.dy);
}

/// _layerLooped draws a layer of a picture -- [draw] -- by its own loop:
/// drifted, moved, or lit, about [box], its place.
void _layerLooped(ui.Canvas canvas, ImageLayer layer, Rect box, int seed,
    void Function() draw) {
  var clock = _imageClock, loop = layer.loop;
  if (clock == null || !loop.on || !layer.visible) return draw();
  if (loop.preset.drifts) {
    var t = _drifting(loop);
    if (t == null) return draw();
    canvas.save();
    _applyDrift(canvas, box, loop, t);
    var steady = adjustSteadily;
    adjustSteadily = true;
    try {
      draw();
    } finally {
      adjustSteadily = steady;
    }
    canvas.restore();
    return;
  }
  if (loop.preset.moves) {
    var swing =
        loop.poseAt(clock.frame, arrived: clock.arrived, last: clock.last);
    if (swing == null) return draw();
    canvas.save();
    _applyLoopPose(canvas, box, swing);
    var faded = swing.opacity < 0.999;
    if (faded) {
      canvas.saveLayer(box.inflate(box.longestSide),
          Paint()..color = Color.fromRGBO(0, 0, 0, swing.opacity));
    }
    draw();
    if (faded) canvas.restore();
    canvas.restore();
    return;
  }
  var phase =
      loop.phaseAt(clock.frame, arrived: clock.arrived, last: clock.last);
  if (phase == null) return draw();
  paintLoopEffect(
      canvas, box, loop, phase.$1, phase.$2, seed, Path()..addRect(box), draw);
}

/// _throughAdjustments draws [draw] through [adjustments], nearest first,
/// each at its own strength, blend and mask: for a picture whose layers move
/// on their own, so each comes in or loops already adjusted.
void _throughAdjustments(ui.Canvas canvas, Rect inner, Rect room,
    List<ImageLayer> adjustments, void Function(ui.Canvas) draw) {
  void through(ui.Canvas c, int k) {
    if (k < 0) return draw(c);
    var adj = adjustments[k];
    var covers =
        adj.opacity >= 1 && adj.blend == LayerBlend.normal && !adj.mask.active;
    if (covers) {
      c.saveLayer(room, _over(adj));
      paintAdjustedLive(c, room, adj.adjust, (a) => through(a, k - 1));
      _frameMasked(c, inner, adj);
      c.restore();
      return;
    }
    // What is under it is drawn once and shown twice -- as it is, and
    // adjusted -- or each adjustment would double the drawing beneath it.
    var below = recordedFor(c, (r) => through(r, k - 1));
    c.drawPicture(below);
    c.saveLayer(room, _over(adj));
    paintAdjustedLive(c, room, adj.adjust, (a) => a.drawPicture(below));
    _frameMasked(c, inner, adj);
    c.restore();
    below.dispose();
  }

  through(canvas, adjustments.length - 1);
}

/// _clipToFrame cuts [canvas] to [e]'s frame about [inner]: its shape, its
/// box's rounded corners, or the box itself -- with room for an outside
/// outline, except while drifting, where the picture is larger than its box
/// and would show in that room.
void _clipToFrame(ui.Canvas canvas, Rect inner, ImageElement e,
    {bool drifting = false}) {
  // A frame cuts the picture to a shape -- the same shapes an element can be
  // drawn as, so anything added there is a frame here for nothing.
  if (e.frame != null) {
    canvas
        .clipPath(shapePath(e.frame!, inner, bubble: const SpeechBubbleSpec()));
  } else if (e.box.isRounded) {
    // The picture's corners follow the box's, pulled in by the padding so a
    // rounded frame stays concentric with the border drawn round it.
    canvas.clipRRect(e.box.insetRounded(inner));
  } else if (drifting) {
    canvas.clipRect(inner);
  } else {
    // Room for an outside outline: a picture filling its box (Cover) has its
    // edge on the clip. The picture itself stays inside the box.
    canvas.clipRect(inner.inflate(_outlineRoom(e)));
  }
}

/// _paintImageInside draws [e]'s picture in its box; [framed] when the
/// caller has already cut it to its frame (a drift, cut before it moves).
void _paintImageInside(
    ui.Canvas canvas, Rect bounds, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive, bool framed = false}) {
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return;

  if (e.layered) {
    _paintLayered(canvas, inner, e, images, arrive: arrive);
    return;
  }

  var image = e.hasImage ? images?.resolve(e.assetId, e.removal) : null;
  if (image == null) {
    _imagePlaceholder(canvas, inner, e);
    return;
  }

  canvas.save();
  if (!framed) _clipToFrame(canvas, inner, e);
  _paintPicture(canvas, inner, e, image, images);
  canvas.restore();
}

/// _paintPicture draws [image] into [inner] with all [e] does to it (fit,
/// crop, colours, overlay, outline) but no frame; also used for layers.
void _paintPicture(ui.Canvas canvas, Rect inner, ImageElement e, ui.Image image,
    CanvasImageSource? images) {
  if (e.warp.active) {
    _paintWarped(canvas, inner, e, image, images);
    return;
  }
  _paintPictureFlat(canvas, inner, e, image, images);
}

/// _paintWarped draws [e]'s picture as _paintPictureFlat would, bent by its
/// warp: drawn once into pixels, kept while its look is unchanged, and laid
/// through the warp's mesh each frame, so moving a grid point is cheap.
void _paintWarped(ui.Canvas canvas, Rect inner, ImageElement e, ui.Image image,
    CanvasImageSource? images) {
  var room = inner.inflate(_outlineRoom(e));
  if (room.isEmpty) return;
  var most = math.min(4096 / math.max(room.width, room.height),
      math.sqrt(16e6 / (room.width * room.height)));
  if (RasterCache.drafting) {
    most = math.min(
        most, RasterCache.draftSide / math.max(room.width, room.height));
  }
  var scale = math.max(0.05, math.min(deviceScaleOf(canvas), most));
  var w = math.max(1, (room.width * scale).ceil());
  var h = math.max(1, (room.height * scale).ceil());
  // Kept against everything the picture is drawn from but the warp; and
  // not kept while anything it draws is still loading.
  var key = "warp|${identityHashCode(image)}|${room.size}";
  var from = [room.size, image, ...pictureLookFrom(e)];
  var keep = !(images?.loading ?? false);
  var flat = keep ? RasterCache.instance.sized(key, from, w, h) : null;
  var kept = flat != null;
  if (flat == null) {
    var recorder = ui.PictureRecorder();
    var c = ui.Canvas(recorder);
    c.scale(w / room.width, h / room.height);
    c.translate(-room.left, -room.top);
    _paintPictureFlat(c, inner, e, image, images);
    var picture = recorder.endRecording();
    flat = picture.toImageSync(w, h);
    picture.dispose();
    if (keep) {
      RasterCache.instance.putSized(key, from, flat);
      kept = true;
    }
  }
  var k = flat.width / room.width;
  canvas.drawVertices(
      warpMesh(e.warp, inner, room, k),
      BlendMode.srcOver,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..shader = ui.ImageShader(
            flat,
            TileMode.decal,
            TileMode.decal,
            Float64List.fromList(
                const [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
            filterQuality: FilterQuality.medium));
  if (!kept) flat.dispose();
}

void _paintPictureFlat(ui.Canvas canvas, Rect inner, ImageElement e,
    ui.Image image, CanvasImageSource? images) {
  var overlaid = e.blend != OverlayBlend.none && e.overlay.a > 0;

  // The mask over everything the picture draws: the outline traces what it
  // leaves, and an overlay tints only that. A subject still loading is drawn
  // without, whole for a moment rather than gone.
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var maskSubject = e.mask.subject.isEmpty
      ? null
      : images?.resolve(e.mask.subject, const BackgroundRemoval());
  var masking =
      e.mask.active && (e.mask.subject.isEmpty || maskSubject != null);
  void masked(void Function() draw) {
    if (!masking) {
      draw();
      return;
    }
    // The picture never reaches past its frame, so neither need the layer.
    canvas.saveLayer(inner, Paint());
    draw();
    paintMaskLayer(canvas, e.mask, size, maskSubject,
        placeImage(size, inner, e.fit, crop: e.crop, framing: e.framing));
    canvas.restore();
  }

  void shape(Color colour) =>
      masked(() => _drawImage(canvas, image, inner, e.fit,
          crop: e.crop, framing: e.framing, silhouette: colour));

  // Behind the picture, so the band only shows where the picture is not.
  if (e.outline.on &&
      (e.outline.style == OutlineStyle.outside ||
          e.outline.style == OutlineStyle.glow)) {
    _paintOutline(canvas, shape, inner, e, outward: true);
  }

  // The picture with the background's colour cleaned from its edge where
  // its mask asks and it is ready (edge_cleaning.dart); colours only.
  var shown = masking ? cleanedFor(images, e, image) : image;
  masked(() {
    // With an overlay the picture goes on its own layer, so the overlay
    // blends with the picture alone, not every element painted before it.
    if (overlaid) canvas.saveLayer(inner, Paint());

    _drawImage(canvas, shown, inner, e.fit,
        retouch: e.retouch,
        tint: e.tint,
        saturation: e.saturation,
        brightness: e.brightness,
        crop: e.crop,
        framing: e.framing,
        filter: e.filter);

    if (overlaid) {
      canvas.drawRect(
          inner,
          Paint()
            ..color = e.overlay
            ..blendMode = e.blend.flutter);

      // Then cut back to the picture's own shape: a blend mode leaves its
      // colour on transparent pixels, which would fill a removed background.
      _drawImage(canvas, image, inner, e.fit,
          crop: e.crop, framing: e.framing, maskOnly: true);
      canvas.restore();
    }
  });

  // After the overlay, so the overlay does not tint an inside band.
  if (e.outline.on &&
      (e.outline.style == OutlineStyle.inside ||
          e.outline.style == OutlineStyle.centred)) {
    _paintOutline(canvas, shape, inner, e, outward: false);
  }
}

/// _frameId names the video frame while the image painter draws it.
const _frameId = "\u0000video-frame";

/// _OneFrame is the picture store plus the video's frame under [_frameId];
/// everything else is asked of the store as usual.
class _OneFrame extends CanvasImageSource {
  final ui.Image frame;
  final CanvasImageSource? store;
  _OneFrame(this.frame, this.store);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) =>
      assetId == _frameId ? frame : store?.resolve(assetId, removal);

  @override
  CanvasVector? resolveVector(String assetId) =>
      assetId == _frameId ? null : store?.resolveVector(assetId);
}

/// _paintVideo draws a video's frame, or its poster while it has none, keyed
/// and with its look as a picture is, and its controls over the top.
void _paintVideo(ui.Canvas canvas, Rect bounds, VideoElement e, VideoShow show,
    CanvasImageSource? images,
    {bool placeholder = true}) {
  if (show.hidden) return;
  var poster = e.isLink ? e.look.assetId : show.poster;
  var frame = show.frame ??
      (poster.isEmpty
          ? null
          : images?.resolve(poster, const BackgroundRemoval()));

  // A background video with nothing to show yet shows nothing, and the
  // pattern under it is the page in the meantime.
  if (frame == null && !placeholder) return;
  if (frame == null) {
    paintBox(canvas, bounds, e.look.box, images);
    var inner = e.look.box.inner(bounds);
    if (inner.width > 0 && inner.height > 0) {
      // A ground of its own while there is nothing to show, so an empty video
      // reads as a screen rather than as a hole in the canvas.
      canvas.drawRect(inner, Paint()..color = const Color(0xFF101418));
      paintTextInBox(
          canvas,
          e.isLink
              ? VideoHost.of(e.link).label
              : e.clip.isEmpty
                  ? "No video yet"
                  : "Loading…",
          TextSpec(
              fontSize: math.max(9, inner.shortestSide * 0.08),
              weight: 500,
              color: const Color(0xAAFFFFFF)),
          inner,
          clip: true);
    }
    if (show.controls) {
      paintVideoControls(canvas, e, videoParts(e, bounds), show);
    }
    return;
  }

  // Keyed before the look: the look grades what is left of the picture, the
  // same as it grades a photograph with its background taken out.
  if (!e.isLink && e.key.on) frame = VideoKey.keyed(frame, e.key);

  var fading = show.opacity < 1;
  if (fading) {
    canvas.saveLayer(bounds.inflate(bounds.shortestSide),
        Paint()..color = Color.fromRGBO(0, 0, 0, show.opacity.clamp(0.0, 1.0)));
  }
  _paintImage(
      canvas,
      bounds,
      e.picture.copyWith(assetId: _frameId, removal: const BackgroundRemoval()),
      _OneFrame(frame, images));
  if (fading) canvas.restore();

  if (show.controls) {
    paintVideoControls(canvas, e, videoParts(e, bounds), show);
  }
}

/// _effectsReach is how far [e]'s layer effects reach past them at [inner].
double _effectsReach(ImageElement e, Rect inner) {
  var unit = math.min(inner.width, inner.height) / 1000;
  var most = 0.0;
  for (var l in e.stack) {
    for (var f in l.effects) {
      if (!f.on) continue;
      var reach = 0.0;
      for (var name in const ["distance", "blur", "size", "spread", "amount"]) {
        if (f.kind.params.any((p) => p.key == name)) {
          // Blurs are a sigma of half the figure, and fade out by about
          // three of those.
          reach += f.value(name) * (name == "blur" || name == "size" ? 1.5 : 1);
        }
      }
      // A zoom's amount is how much bigger its last copy is: of the whole
      // frame, not of a thousandth of it.
      if (f.kind == EffectKind.zoomBlur) reach = f.value("amount") * 1000;
      most = math.max(most, reach);
    }
  }
  return most * unit;
}

/// _outlineRoom is how far outside its box a picture's outline may reach.
double _outlineRoom(ImageElement e) {
  if (!e.outline.on) return 0;
  switch (e.outline.style) {
    case OutlineStyle.inside:
      return 0;
    case OutlineStyle.centred:
      return e.outline.width / 2 * 1.3;
    case OutlineStyle.glow:
      // Blur reaches well past the spread that fed it.
      return e.outline.width * 2;
    case OutlineStyle.outside:
      // The fade happens within the width, but a blur's tail runs a little
      // past where it is meant to stop.
      return e.outline.width * 1.3;
  }
}

/// _paintOutline traces the edge of the picture's alpha channel with the
/// compositor (a dilate on a layer), so it is drawn at the canvas's
/// resolution and not recomputed when a colour changes. An outward band is a
/// blurred fade with a solid band laid over its inside, since one blurred
/// pass fades at both edges and lets a cut-out's soft rim show through.
void _paintOutline(
    ui.Canvas canvas, void Function(Color) shape, Rect inner, ImageElement e,
    {required bool outward}) {
  var outline = e.outline;
  // Centred splits the band between the two sides.
  var width =
      outline.style == OutlineStyle.centred ? outline.width / 2 : outline.width;
  if (width <= 0) return;

  void silhouette(Color colour, ui.ImageFilter? filter) {
    canvas.saveLayer(
        inner, filter == null ? Paint() : (Paint()..imageFilter = filter));
    shape(colour);
    canvas.restore();
  }

  if (outward) {
    // A glow is all fade and no band.
    var glow = outline.style == OutlineStyle.glow;
    // Otherwise never all fade, however far the feather is pushed: the band
    // must meet the subject at full strength.
    var solid = glow ? 0.0 : width * (1 - outline.feather * 0.8);
    var fade = width - solid;

    if (glow || fade > 0) {
      // Dilate to the middle of the fade and blur across it, so the feather
      // does not make the outline wider than asked.
      var spread = glow ? width * 0.35 : solid + fade / 2;
      var sigma = glow ? width * (0.25 + outline.feather * 0.4) : fade / 4;
      silhouette(
          outline.color,
          ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(
                sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
            inner: ui.ImageFilter.dilate(radiusX: spread, radiusY: spread),
          ));
    }

    // The solid part, over the inside of the fade. Drawn even with no width
    // (a glow) to back the subject's soft rim with the outline's colour, or
    // the rim shows as a second, dimmer line.
    silhouette(
        outline.color,
        solid > 0
            ? ui.ImageFilter.dilate(radiusX: solid, radiusY: solid)
            : null);
    return;
  }

  // A band that touches the picture is drawn over it as one ring, not as two
  // halves, whose join over the soft rim would show as a gap. The ring is the
  // silhouette grown by `grow` with a copy shrunk by `shrink` punched out.
  var grow = outline.style == OutlineStyle.centred ? width : 0.0;
  var shrink = width;
  var blur = width * outline.feather / 2;

  canvas.saveLayer(inner, Paint());

  // Feathering fades the edge facing away from the subject (outwards for a
  // centred band, inwards for an inside one); the traced edge stays crisp.
  var fill = <ui.ImageFilter>[
    if (grow > 0) ui.ImageFilter.dilate(radiusX: grow, radiusY: grow),
    if (grow > 0 && blur > 0)
      ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
  ];
  silhouette(
      outline.color,
      fill.isEmpty
          ? null
          : fill.length == 1
              ? fill.first
              : ui.ImageFilter.compose(outer: fill.last, inner: fill.first));

  var punch = ui.ImageFilter.erode(radiusX: shrink, radiusY: shrink);
  canvas.saveLayer(
      inner,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..imageFilter = grow == 0 && blur > 0
            ? ui.ImageFilter.compose(
                outer: ui.ImageFilter.blur(
                    sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
                inner: punch)
            : punch);
  shape(const Color(0xFF000000));
  canvas.restore();
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

/// _drawImage fits [image] in [rect], adjusting colours by matrix, not pixels.
void _drawImage(ui.Canvas canvas, ui.Image image, Rect rect, ImageFit fit,
    {Color tint = const Color(0x00000000),
    double saturation = 1,
    double brightness = 1,
    ImageCrop crop = const ImageCrop(),
    ImageFraming framing = const ImageFraming(),
    ImageFilterPreset filter = ImageFilterPreset.none,

    /// retouch is cloning, healing and the like done to the picture, drawn
    /// over it in its own pixels -- see brush_painter.dart.
    List<StrokeMark> retouch = const [],

    /// maskOnly draws the picture's shape with dstIn, so the layer survives
    /// only where it has pixels: keeps an overlay off a removed background.
    bool maskOnly = false,

    /// silhouette draws the picture's shape filled with one colour, keeping
    /// its alpha and throwing its own colours away. What an outline traces.
    Color? silhouette}) {
  // Shared with the retouching brush, which maps it backwards: see
  // ImagePlacement.toImage.
  var placement = placeImage(
      Size(image.width.toDouble(), image.height.toDouble()), rect, fit,
      crop: crop, framing: framing);
  var src = placement.src;
  var dst = placement.dst;

  var paint = Paint()..filterQuality = FilterQuality.high;

  if (maskOnly) {
    canvas.drawImageRect(image, src, dst, paint..blendMode = BlendMode.dstIn);
    return;
  }

  // srcIn keeps the source's alpha and takes the colour from the filter, so a
  // half-transparent strand of hair gives a half-transparent piece of outline.
  if (silhouette != null) {
    canvas.drawImageRect(image, src, dst,
        paint..colorFilter = ColorFilter.mode(silhouette, BlendMode.srcIn));
    return;
  }

  // One colour matrix for the preset and both sliders, not a layer each.
  var matrix = lookMatrix(filter, saturation, brightness);
  if (matrix != null) paint.colorFilter = ColorFilter.matrix(matrix);
  canvas.drawImageRect(image, src, dst, paint);

  if (retouch.isNotEmpty) {
    var m = pictureToPlacement(placement);
    canvas.save();
    canvas.clipRect(dst);
    canvas.translate(m.dx, m.dy);
    canvas.scale(m.sx, m.sy);
    paintRetouchKept(
        canvas,
        image,
        Size(image.width.toDouble(), image.height.toDouble()),
        retouch,
        paint.colorFilter);
    canvas.restore();
  }

  if (tint.a > 0) {
    canvas.drawRect(
        dst,
        Paint()
          ..color = tint
          ..blendMode = BlendMode.modulate);
  }
}

/// _imageClock is the frame a picture is drawn on, its scene's last frame
/// and where its arrival ends, set round drawing an image element for its
/// drift and loops. [at] adds how far past it the playhead is (betweenFrames).
({int frame, double at, int last, int? arrived})? _imageClock;

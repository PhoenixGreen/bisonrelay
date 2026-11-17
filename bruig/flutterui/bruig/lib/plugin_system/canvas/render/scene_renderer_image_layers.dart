part of 'scene_renderer.dart';

// A picture made of layers: the stack drawn back to front through its
// adjustments, clipping groups, masks and the mask view, and each layer with
// its effects. Part of scene_renderer.dart.

/// _paintLayered draws a picture of layers into its frame [inner]. The
/// frame's shape clips the composite, drawn in a layer of its own so a
/// layer's blend mode blends with the layers below, not the canvas.
void _paintLayered(
    ui.Canvas canvas, Rect inner, ImageElement e, CanvasImageSource? images,
    {_LayerArrive? arrive}) {
  var stack = e.stack;
  // Nothing in it at all is an empty picture, and says so. An adjustment
  // alone has nothing to adjust.
  var anything = stack.any((l) => switch (l.kind) {
        LayerKind.base => e.hasImage,
        LayerKind.picture => l.look?.hasImage ?? false,
        LayerKind.fill || LayerKind.texture => true,
        LayerKind.paint => l.strokes.isNotEmpty,
        LayerKind.adjustment => false,
      });
  if (!anything) {
    _imagePlaceholder(canvas, inner, e);
    return;
  }

  canvas.save();
  Rect room;
  if (!e.clip) {
    // Nothing cut: what runs past the frame (a layer dragged out, a stroke,
    // a shadow) is drawn where it is. See ImageElement.grownToFit.
    room = inner
        .expandToInclude(contentRectOf(e, inner) ?? inner)
        .inflate(math.max(_outlineRoom(e), _effectsReach(e, inner)));
  } else {
    if (e.frame != null) {
      canvas.clipPath(
          shapePath(e.frame!, inner, bubble: const SpeechBubbleSpec()));
    } else if (e.box.isRounded) {
      canvas.clipRRect(e.box.insetRounded(inner));
    } else {
      canvas.clipRect(inner.inflate(_outlineRoom(e)));
    }
    room = inner.inflate(_outlineRoom(e));
  }
  canvas.saveLayer(room, Paint());
  var watched = _Watched(images);
  _paintStack(canvas, inner, e, stack, watched, room, arrive);
  canvas.restore();
  canvas.restore();
}

Paint _over(ImageLayer layer) => Paint()
  ..blendMode = layer.blend.flutter
  ..color = Color.fromRGBO(0, 0, 0, layer.opacity);

ui.Picture _record(void Function(ui.Canvas) draw) {
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  return recorder.endRecording();
}

/// _paintStack draws [stack], back to front, split at its topmost adjustment
/// layer: what is under is drawn as itself and again through the adjustment
/// (at its opacity and blend), then what is over. The part under is drawn
/// the same way.
void _paintStack(ui.Canvas canvas, Rect inner, ImageElement e,
    List<ImageLayer> stack, _Watched images, Rect room, _LayerArrive? arrive) {
  // Layers arriving in turn or looping on their own: each is drawn with the
  // adjustments over it worked in, so it arrives or moves already adjusted.
  if (arrive != null || stack.any((l) => l.visible && l.loop.on)) {
    _paintGroups(canvas, inner, e, stack, images, room, arrive,
        adjustEach: true);
    return;
  }
  var at = -1;
  for (var i = stack.length - 1; i >= 0; i--) {
    var l = stack[i];
    // A clipped adjustment changes only the layer it is clipped to, and is
    // drawn with it -- see _paintGroups. A paint layer retouching what is
    // under it works on everything under it, as an adjustment does.
    if (l.visible &&
        (l.kind == LayerKind.adjustment && !(l.clip && i > 0) ||
            l.retouchesUnder)) {
      at = i;
      break;
    }
  }
  if (at < 0) {
    _paintGroups(canvas, inner, e, stack, images, room, arrive);
    return;
  }
  var misses = images.misses;
  var below = _record((c) =>
      _paintStack(c, inner, e, stack.sublist(0, at), images, room, arrive));
  // What is under it changes frame by frame while layers arrive, so the
  // adjusted picture is not kept then.
  var complete = images.misses == misses && arrive == null;
  // What is under is drawn as it is only where it shows through the adjusted
  // picture (part strength, blended, masked, arriving); else it is skipped.
  var top = stack[at];
  var covers = !top.retouchesUnder &&
      top.opacity >= 1 &&
      top.blend == LayerBlend.normal &&
      !top.mask.active &&
      arrive == null &&
      AdjustShader.ready.value;
  if (!covers) canvas.drawPicture(below);
  if (stack[at].retouchesUnder) {
    // The clone, heal or dodge works on everything under the layer as one
    // picture, across the whole frame, with the layer's own paint over that.
    var layer = stack[at];
    canvas.saveLayer(room, _over(layer));
    _arriving(canvas, arrive, layer, room, () {
      paintRetouchUnder(canvas, inner, below, layer.strokes,
          key: complete ? "${e.id}|${layer.id}|under" : null,
          from: layersFrom(e, stack.sublist(0, at)));
      paintPaintLayer(canvas, inner, layer.strokes, "${e.id}|${layer.id}");
      _frameMasked(canvas, inner, layer);
    });
    canvas.restore();
    below.dispose();
    _paintGroups(canvas, inner, e, stack.sublist(at + 1), images, room, arrive);
    return;
  }
  var adjustment = stack[at];
  canvas.saveLayer(room, _over(adjustment));
  _arriving(canvas, arrive, adjustment, room, () {
    paintAdjusted(canvas, room, adjustment.adjust, below,
        // Kept only once everything under it has loaded: kept earlier, the
        // picture that arrived late would never be adjusted.
        key: complete ? "${e.id}|${adjustment.id}|$at" : null,
        from: layersFrom(e, stack.sublist(0, at)));
    _frameMasked(canvas, inner, adjustment);
  });
  canvas.restore();
  below.dispose();
  _paintGroups(canvas, inner, e, stack.sublist(at + 1), images, room, arrive);
}

/// _arriving draws [draw] for [layer] at its arrival turn, if any.
void _arriving(ui.Canvas canvas, _LayerArrive? arrive, ImageLayer layer,
    Rect box, void Function() draw) {
  if (arrive == null) return draw();
  var was = _arrivingCanvas;
  _arrivingCanvas = canvas;
  try {
    arrive(layer, box, draw);
  } finally {
    _arrivingCanvas = was;
  }
}

/// renderUnder is the layers of [e] below [layerId] as a [w] x [h] picture,
/// for an adjustment's histogram; null where there is no such layer.
Future<ui.Image?> renderUnder(ImageElement e, String layerId,
    CanvasImageSource? images, int w, int h) async {
  var stack = e.stack;
  var at = stack.indexWhere((l) => l.id == layerId);
  if (at < 0) return null;
  var inner = e.box.inner(e.bounds);
  if (inner.width <= 0 || inner.height <= 0) return null;
  var picture = _record((c) {
    c.scale(w / inner.width, h / inner.height);
    c.translate(-inner.left, -inner.top);
    c.clipRect(inner);
    _paintStack(
        c, inner, e, stack.sublist(0, at), _Watched(images), inner, null);
  });
  try {
    return await picture.toImage(w, h);
  } finally {
    picture.dispose();
  }
}

/// _paintFrameMaskView is paintMaskView for a frame-masked layer.
void _paintFrameMaskView(ui.Canvas canvas, ImageElement e, ImageLayer layer,
    {required bool overlay}) {
  canvas.save();
  var bounds = e.bounds;
  // Turned and slanted as the picture is drawn -- see BoxFrame.
  BoxFrame(e.rotation, e.base.skewX, e.base.skewY)
      .applyTo(canvas, bounds.center);
  var inner = e.box.inner(bounds);
  var size = Size(inner.width, inner.height);
  var placement = placeImage(size, inner, ImageFit.stretch);
  canvas.saveLayer(inner, Paint());
  if (overlay) {
    canvas.drawRect(inner, Paint()..color = const Color(0x88FF2020));
    if (!layer.mask.empty) {
      paintMaskLayer(canvas, layer.mask, size, null, placement,
          blend: BlendMode.dstOut);
    } else {
      canvas.drawRect(inner, Paint()..blendMode = BlendMode.clear);
    }
  } else {
    canvas.drawRect(inner, Paint()..color = const Color(0xFF000000));
    canvas.saveLayer(inner, Paint());
    canvas.drawRect(inner, Paint()..color = const Color(0xFFFFFFFF));
    if (!layer.mask.empty) {
      paintMaskLayer(canvas, layer.mask, size, null, placement);
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// _frameMasked cuts what has just been drawn of [layer] in the current
/// layer back to its frame mask -- see ImageLayer.mask -- where it has one.
void _frameMasked(ui.Canvas canvas, Rect inner, ImageLayer layer) {
  if (!layer.framed || !layer.mask.active) return;
  var size = Size(inner.width, inner.height);
  paintMaskLayer(canvas, layer.mask, size, null,
      placeImage(size, inner, ImageFit.stretch));
}

/// _layerBox is a picture layer's place in [inner]; the frame for others.
Rect _layerBox(Rect inner, ImageLayer layer) =>
    layer.kind == LayerKind.picture ? layerRect(inner, layer.place) : inner;

/// _paintGroups draws [stack], which holds no adjustment over everything
/// under it, a layer and the layers clipped to it at a time.
void _paintGroups(ui.Canvas canvas, Rect inner, ImageElement e,
    List<ImageLayer> stack, _Watched images, Rect room, _LayerArrive? arrive,
    {bool adjustEach = false}) {
  var i = 0;
  while (i < stack.length) {
    var layer = stack[i];
    // Worked into each layer instead, an adjustment over everything under
    // it draws nothing of its own -- see _paintStack.
    if (adjustEach &&
        layer.kind == LayerKind.adjustment &&
        !(layer.clip && i > 0)) {
      i++;
      continue;
    }
    var over = !adjustEach
        ? const <ImageLayer>[]
        : [
            for (var (k, l) in stack.indexed)
              if (k > i &&
                  l.visible &&
                  l.kind == LayerKind.adjustment &&
                  !l.clip)
                l
          ];
    // The layers clipped to this one, which go wherever it goes.
    var j = i + 1;
    while (j < stack.length && stack[j].clip) {
      j++;
    }
    var clipped = [
      for (var c in stack.sublist(i + 1, j))
        if (c.visible) c
    ];
    // A clipped layer at the bottom has nothing to clip to: drawn plainly.
    if (layer.visible) {
      canvas.saveLayer(room, _over(layer));
      var box = _layerBox(inner, layer);
      _arriving(canvas, arrive, layer, box, () {
        _layerLooped(canvas, layer, box, Object.hash(e.id, layer.id), () {
          void dressed(ui.Canvas c) {
            _paintDressed(c, inner, e, layer, images, room);
            _frameMasked(c, inner, layer);
          }

          if (over.isEmpty) {
            dressed(canvas);
          } else {
            _throughAdjustments(canvas, inner, room, over, dressed);
          }
        });
      });
      for (var c in clipped) {
        canvas.saveLayer(room, _over(c));
        if (c.kind == LayerKind.adjustment) {
          // Clipped, an adjustment changes the one layer under it.
          var misses = images.misses;
          var base = _record((r) => _paintLayer(r, inner, e, layer, images));
          _arriving(canvas, arrive, c, room, () {
            paintAdjusted(canvas, room, c.adjust, base,
                key: images.misses == misses && arrive == null
                    ? "${e.id}|${c.id}|clip"
                    : null,
                from: layersFrom(e, [layer]));
            _frameMasked(canvas, inner, c);
          });
          base.dispose();
        } else {
          _arriving(canvas, arrive, c, _layerBox(inner, c), () {
            _paintDressed(canvas, inner, e, c, images, room);
            _frameMasked(canvas, inner, c);
          });
        }
        // Cut back to the layer it is clipped to: its own shape, drawn again
        // as a mask over the clipped layer before it is blended down.
        canvas.saveLayer(room, Paint()..blendMode = BlendMode.dstIn);
        _paintLayer(canvas, inner, e, layer, images);
        _frameMasked(canvas, inner, layer);
        canvas.restore();
        canvas.restore();
      }
      canvas.restore();
    }
    i = j;
  }
}

/// _paintDressed draws [layer] with its effects (shadows, glows, blurs).
void _paintDressed(ui.Canvas canvas, Rect inner, ImageElement e,
    ImageLayer layer, _Watched images, Rect room) {
  if (!layer.effects.any((f) => f.on)) {
    _paintLayer(canvas, inner, e, layer, images);
    return;
  }
  var misses = images.misses;
  var content = _record((r) => _paintLayer(r, inner, e, layer, images));
  paintWithEffects(canvas, room, math.min(inner.width, inner.height) / 1000,
      layer.effects, content,
      key: images.misses == misses ? "${e.id}|${layer.id}|fx" : null,
      from: layersFrom(e, [layer]),
      lightening: layer.blend.lightens ? layer.blend.flutter : null);
  content.dispose();
}

/// _Watched is a picture source that counts what it could not hand over
/// yet, so an adjustment drawn over a picture still loading is not kept.
class _Watched extends CanvasImageSource implements CleansEdges {
  final CanvasImageSource? source;
  int misses = 0;
  _Watched(this.source);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) {
    var image = source?.resolve(assetId, removal);
    if (image == null) {
      misses++;
      CanvasPerf.count("miss $assetId");
    }
    return image;
  }

  @override
  CanvasVector? resolveVector(String assetId) => source?.resolveVector(assetId);

  @override
  ImageSilhouette? resolveOutline(String assetId, BackgroundRemoval removal) =>
      source?.resolveOutline(assetId, removal);

  @override
  bool get loading => source?.loading ?? false;

  @override
  ui.Image? cleaned(ImageElement look, ui.Image picture) {
    var s = source;
    if (s is CleansEdges) {
      var image = (s as CleansEdges).cleaned(look, picture);
      if (image == null) {
        misses++;
        CanvasPerf.count("miss cleaned ${look.assetId}");
      }
      return image;
    }
    return null;
  }
}

/// paintMaskView draws the mask of [e]'s layer [layerId] where the picture
/// is, in document units: what it hides in translucent red ([overlay]), or
/// the mask alone in black and white. See MaskView.
void paintMaskView(
    ui.Canvas canvas, ImageElement e, String layerId, CanvasImageSource? images,
    {required bool overlay}) {
  var layer = e.layerById(layerId);
  if (layer == null) return;
  if (layer.framed) {
    _paintFrameMaskView(canvas, e, layer, overlay: overlay);
    return;
  }
  var look = switch (layer.kind) {
    LayerKind.base => e,
    LayerKind.picture => layer.look,
    LayerKind.fill ||
    LayerKind.adjustment ||
    LayerKind.texture ||
    LayerKind.paint =>
      null,
  };
  if (look == null || !look.hasImage) return;
  var image = images?.resolve(look.assetId, look.removal);
  if (image == null) return;
  var size = Size(image.width.toDouble(), image.height.toDouble());
  var subject = look.mask.subject.isEmpty
      ? null
      : images?.resolve(look.mask.subject, const BackgroundRemoval());

  canvas.save();
  var bounds = e.bounds;
  // Turned and slanted as the picture is drawn -- see BoxFrame.
  BoxFrame(e.rotation, e.base.skewX, e.base.skewY)
      .applyTo(canvas, bounds.center);
  var inner = e.box.inner(bounds);
  var rect = layerRect(inner, layer.place);
  if (!layer.isBase || layer.flipX || layer.flipY) {
    canvas.translate(rect.center.dx, rect.center.dy);
    if (layer.turn != 0) canvas.rotate(layer.turn * math.pi / 180);
    if (layer.flipX || layer.flipY) {
      canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
    }
    canvas.translate(-rect.center.dx, -rect.center.dy);
  }
  var placement =
      placeImage(size, rect, look.fit, crop: look.crop, framing: look.framing);
  var dst = placement.dst;
  canvas.saveLayer(dst, Paint());
  if (overlay) {
    canvas.drawRect(dst, Paint()..color = const Color(0x88FF2020));
    if (!look.mask.empty) {
      paintMaskLayer(canvas, look.mask, size, subject, placement,
          blend: BlendMode.dstOut);
    } else {
      canvas.drawRect(dst, Paint()..blendMode = BlendMode.clear);
    }
  } else {
    canvas.drawRect(dst, Paint()..color = const Color(0xFF000000));
    canvas.saveLayer(dst, Paint());
    canvas.drawRect(dst, Paint()..color = const Color(0xFFFFFFFF));
    if (!look.mask.empty) {
      paintMaskLayer(canvas, look.mask, size, subject, placement);
    }
    canvas.restore();
  }
  canvas.restore();
  canvas.restore();
}

/// _paintLayer draws one layer of [e], with blend and opacity the caller's.
void _paintLayer(ui.Canvas canvas, Rect inner, ImageElement e, ImageLayer layer,
    CanvasImageSource? images) {
  switch (layer.kind) {
    case LayerKind.base:
      var image = e.hasImage ? images?.resolve(e.assetId, e.removal) : null;
      // In its own place: the frame, until it is moved or sized on its own
      // -- mirrored there, where it is flipped.
      if (image != null) {
        var rect = layerRect(inner, layer.place);
        var flipped = layer.flipX || layer.flipY;
        if (flipped) {
          canvas.save();
          canvas.translate(rect.center.dx, rect.center.dy);
          canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
          canvas.translate(-rect.center.dx, -rect.center.dy);
        }
        _paintPicture(canvas, rect, e, image, images);
        if (flipped) canvas.restore();
      }
    case LayerKind.fill:
      canvas.drawRect(inner, layer.fill.into(Paint(), inner));
    case LayerKind.adjustment:
      // Drawn by what is under it -- see _paintStack.
      break;
    case LayerKind.texture:
      paintTexture(canvas, inner, layer.texture);
    case LayerKind.paint:
      paintPaintLayer(canvas, inner, layer.strokes, "${e.id}|${layer.id}");
    case LayerKind.picture:
      var look = layer.look;
      if (look == null || !look.hasImage) return;
      var image = images?.resolve(look.assetId, look.removal);
      if (image == null) return;
      var rect = layerRect(inner, layer.place);
      if (rect.width <= 0 || rect.height <= 0) return;
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      if (layer.turn != 0) canvas.rotate(layer.turn * math.pi / 180);
      if (layer.flipX || layer.flipY) {
        canvas.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1);
      }
      canvas.translate(-rect.center.dx, -rect.center.dy);
      if (look.frame != null) {
        canvas.clipPath(
            shapePath(look.frame!, rect, bubble: const SpeechBubbleSpec()));
      }
      _paintPicture(canvas, rect, look, image, images);
      canvas.restore();
  }
}

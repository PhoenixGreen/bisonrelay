part of 'canvas_stage.dart';

// Editing a picture on the canvas: its layers, the warp grid, masks and
// brushwork. Part of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension StagePictureTools on CanvasStageState {
  /// _selectedPicture is the one selected element if it is a picture with
  /// something in it.
  ImageElement? _selectedPicture() {
    var selected = controller.selected;
    return selected is ImageElement && selected.hasImage ? selected : null;
  }

  /// _paintStrokeAt adds a point to the live stroke ([_commitStroke] commits
  /// it on pointer up). Points are stored in picture coordinates, so the
  /// stroke stays put when the element is resized, refitted or recropped;
  /// ImagePlacement converts, as the painter does.
  void _paintStrokeAt(Offset doc, {bool start = false}) {
    var id = _painting;
    if (id == null) return;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return;

    var image = controller.images.original(picture.assetId);
    if (image == null) return;

    var inner = picture.box.inner(_hit.posed(picture));
    var size = Size(image.width.toDouble(), image.height.toDouble());
    var placement = placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
    var at = placement.toImage(doc, size);
    // Off the picture the stroke touches nothing but goes on.
    if (at == null) return;

    if (start) {
      // The brush is a fraction of the picture's shorter side, converted once
      // to canvas units for the preview.
      var shorter = math.min(size.width, size.height);
      var scale = placement.scaleToImage();
      _liveRadius = controller.brushSize * shorter / (scale == 0 ? 1 : scale);
    }

    setState(() {
      _liveImage.add(at);
      _liveCanvas.add(doc);
    });
  }

  /// _layerReach is how near a layer handle, in document units, a press is.
  double get _layerReach => (handleSize / 2 + handleHitSlop) / _scale;

  /// _layerKnob is [space]'s turning knob, above the middle of its top.
  Offset _layerKnob(LayerSpace space) {
    var corners = space.corners;
    var top = (corners[0] + corners[1]) / 2;
    var middle = (corners[0] + corners[2]) / 2;
    var up = top - middle;
    var length = up.distance;
    var away = length == 0 ? const Offset(0, -1) : up / length;
    return top + away * (shapeTurnReach / _scale);
  }

  /// _layerBoxes is what the painter draws over a picture whose layers are
  /// open. See StageLayers.
  StageLayers? _layerBoxes() {
    var e = controller.editingImage;
    if (e == null) return null;
    if (controller.warpLayer case var id?) return _warpView(e, id);
    var picked = controller.pickedLayer;
    // A brush in hand: its ring and, cloning, where it copies from.
    if (controller.imageTool.paints && picked != null) {
      var tool = controller.imageTool;
      var hover = _toDocument(_hoverAt);
      if (!tool.retouches) {
        var inner = e.box.inner(e.bounds);
        return StageLayers(ring: (
          hover,
          controller.paintSize * math.min(inner.width, inner.height)
        ));
      }
      var on = controller.retouchesFrame
          ? LayerPicture.frame(e, picked)
          : _maskPicture(e);
      if (on == null) return const StageLayers();
      Offset? marker;
      if (tool == ImageTool.clone && controller.cloneFrom != null) {
        var offset = controller.cloneOffset;
        marker = offset == null
            ? on.fromPicture(controller.cloneFrom!)
            : on.fromPicture(on.toPicture(hover) + offset);
      }
      return StageLayers(ring: (
        hover,
        controller.paintSize * on.shortSide * on.canvasPerPixel
      ), marker: marker);
    }
    // A mask tool in hand: no boxes, just the picture, its mask and the ring.
    if (controller.imageTool.masks && picked != null) {
      var on = _maskPicture(e);
      if (controller.maskBusy == null && _mode != _DragMode.imageQuick) {
        _quickTrail = const [];
      }
      var brushes = controller.imageTool == ImageTool.brush ||
          controller.imageTool == ImageTool.quick ||
          controller.imageTool == ImageTool.refine;
      List<Offset>? lasso;
      if (_mode == _DragMode.imageMask &&
          controller.imageTool == ImageTool.lasso &&
          on != null) {
        var mask = picked.framed ? picked.mask : lookOf(e, picked.id)?.mask;
        var last = mask?.marks.lastOrNull;
        if (last != null && last.kind == MaskMarkKind.lasso) {
          lasso = [for (var f in last.points) on.fromPicture(f)];
        }
      }
      return StageLayers(
        lasso: lasso,
        masking: (
          element: e,
          layer: picked.id,
          view: controller.maskView,
        ),
        trail: on == null || _quickTrail.isEmpty
            ? null
            : (
                [for (var f in _quickTrail) on.fromPicture(f)],
                controller.maskBrushSize * on.shortSide * on.canvasPerPixel,
                _quickSubtract,
              ),
        ring: brushes && on != null
            ? (
                _toDocument(_hoverAt),
                controller.maskBrushSize * on.shortSide * on.canvasPerPixel
              )
            : null,
      );
    }
    var also = controller.imageLayers.skip(1).toSet();
    var others = [
      for (var l in e.stack)
        if (l.kind == LayerKind.picture &&
            l.visible &&
            l.id != picked?.id &&
            !also.contains(l.id))
          LayerSpace(e, l).corners
    ];
    var chosen = [
      for (var l in e.stack)
        if (l.kind == LayerKind.picture && l.visible && also.contains(l.id))
          LayerSpace(e, l).corners
    ];
    // Layered, the base picture has its own place (see ImageLayer.basePlace)
    // and is handled as a picture layer, without the knob: it turns with the
    // element.
    var handled = picked != null &&
        (picked.kind == LayerKind.picture || (picked.isBase && e.layered));
    if (!handled) {
      var inner = e.box.inner(e.bounds);
      var space = LayerSpace(e, ImageLayer.base);
      return StageLayers(
          others: others,
          chosen: chosen,
          picked: [
            inner.topLeft,
            inner.topRight,
            inner.bottomRight,
            inner.bottomLeft
          ].map(space.fromFrame).toList());
    }
    var space = LayerSpace(e, picked);
    var held = controller.layerLocked(picked);
    return StageLayers(
      others: others,
      chosen: chosen,
      picked: space.corners,
      handles: held
          ? const []
          : [for (var h in boxHandles(space.rect)) space.fromLayer(h)],
      knob: picked.isBase || held ? null : _layerKnob(space),
    );
  }

  /// _warpSpace maps the warp grid of layer [id] of [e] between fractions of
  /// the picture's box and canvas points, and back, through the element's
  /// turn and slant and the layer's turn and mirror.
  (Offset Function(Offset), Offset Function(Offset)) _warpSpace(
      ImageElement e, String id) {
    var layer = e.layerById(id) ?? ImageLayer.base;
    var space = LayerSpace(e, layer);
    var r = space.rect;
    Offset mirror(Offset f) =>
        Offset(layer.flipX ? 1 - f.dx : f.dx, layer.flipY ? 1 - f.dy : f.dy);
    Offset toDoc(Offset f) {
      var m = mirror(f);
      return space
          .fromLayer(r.topLeft + Offset(m.dx * r.width, m.dy * r.height));
    }

    Offset toFrac(Offset doc) {
      var l = space.toLayer(doc) - r.topLeft;
      return mirror(Offset(
          l.dx / math.max(1e-9, r.width), l.dy / math.max(1e-9, r.height)));
    }

    return (toDoc, toFrac);
  }

  List<Offset> _warpPoints(ImageElement e, String id) {
    var (toDoc, _) = _warpSpace(e, id);
    return [for (var f in controller.warpOf(e, id).grid) toDoc(f)];
  }

  /// _warpBox is the box and knob round two or more picked warp points.
  (Rect, Offset)? _warpBox(List<Offset> points) {
    var picks = controller.warpPicks;
    if (picks.length < 2) return null;
    var picked = [
      for (var k in picks)
        if (k < points.length) points[k]
    ];
    if (picked.length < 2) return null;
    var box = Rect.fromLTRB(
        picked.map((p) => p.dx).reduce(math.min),
        picked.map((p) => p.dy).reduce(math.min),
        picked.map((p) => p.dx).reduce(math.max),
        picked.map((p) => p.dy).reduce(math.max));
    // Room round points in a line, so the box has corners to hold.
    var least = 12 / _scale;
    if (box.width < least || box.height < least) {
      box = Rect.fromCenter(
          center: box.center,
          width: math.max(box.width, least),
          height: math.max(box.height, least));
    }
    return (box, box.topCenter - Offset(0, 24 / _scale));
  }

  StageLayers _warpView(ImageElement e, String id) {
    var warp = controller.warpOf(e, id);
    var (toDoc, _) = _warpSpace(e, id);
    var g = warp.grid;
    var points = [for (var f in g) toDoc(f)];
    const fine = 12;
    var lines = <List<Offset>>[
      for (var i = 0; i <= warp.rows; i++)
        [
          for (var k = 0; k <= warp.cols * fine; k++)
            toDoc(warp.sample(k / (warp.cols * fine), i / warp.rows, g))
        ],
      for (var j = 0; j <= warp.cols; j++)
        [
          for (var k = 0; k <= warp.rows * fine; k++)
            toDoc(warp.sample(j / warp.cols, k / (warp.rows * fine), g))
        ],
    ];
    var box = _warpBox(points);
    return StageLayers(
        warp: StageWarp(
            lines: lines,
            points: points,
            picks: controller.warpPicks,
            box: box == null
                ? null
                : [
                    box.$1.topLeft,
                    box.$1.topRight,
                    box.$1.bottomRight,
                    box.$1.bottomLeft
                  ],
            knob: box?.$2));
  }

  /// _pressWarp is a press on a shown warp grid: the box's knob or a corner
  /// turns or sizes the picked points; a point is picked (Shift toggles) and
  /// dragged; inside the box drags them all; elsewhere a box picks points.
  bool _pressWarp(ImageElement e, String id, Offset doc) {
    var points = _warpPoints(e, id);
    var reach = 10 / _scale;
    var shift = _shiftHeld;
    void hold(_DragMode mode) {
      _mode = mode;
      _warpStartPoints = [...controller.warpOf(e, id).grid];
      _warpGrab = doc;
      controller.beginInteraction();
    }

    if (_warpBox(points) case (var box, var knob)) {
      if ((doc - knob).distance <= reach) {
        _warpPivot = box.center;
        hold(_DragMode.warpTurn);
        return true;
      }
      for (var c in [
        box.topLeft,
        box.topRight,
        box.bottomLeft,
        box.bottomRight
      ]) {
        if ((doc - c).distance <= reach) {
          _warpPivot = box.center;
          hold(_DragMode.warpScale);
          return true;
        }
      }
    }
    var nearest = -1;
    var best = reach;
    for (var (k, p) in points.indexed) {
      var d = (p - doc).distance;
      if (d <= best) {
        best = d;
        nearest = k;
      }
    }
    if (nearest >= 0) {
      var picks = {...controller.warpPicks};
      if (shift) {
        picks.contains(nearest) ? picks.remove(nearest) : picks.add(nearest);
        controller.warpPicks = picks;
        _mode = _DragMode.none;
        return true;
      }
      if (!picks.contains(nearest)) controller.warpPicks = {nearest};
      hold(_DragMode.warpMove);
      return true;
    }
    if (_warpBox(points) case (var box, _) when box.contains(doc)) {
      hold(_DragMode.warpMove);
      return true;
    }
    if (!shift) controller.warpPicks = const {};
    _mode = _DragMode.warpMarquee;
    _warpGrab = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    return true;
  }

  /// _dragWarp carries the picked points to [doc]: moved, sized about their
  /// box's middle by the pointer's change in distance, or turned about it.
  void _dragWarp(Offset doc) {
    var e = controller.editingImage, id = controller.warpLayer;
    if (e == null || id == null) return;
    if (_mode == _DragMode.warpMarquee) {
      setState(() => _marquee = Rect.fromPoints(_warpGrab, doc));
      return;
    }
    var (toDoc, toFrac) = _warpSpace(e, id);
    var start = [for (var f in _warpStartPoints) toDoc(f)];
    Offset carried(Offset p) {
      switch (_mode) {
        case _DragMode.warpMove:
          return p + (doc - _warpGrab);
        case _DragMode.warpScale:
          var from = (_warpGrab - _warpPivot).distance;
          var k = from < 1e-9 ? 1.0 : (doc - _warpPivot).distance / from;
          return _warpPivot + (p - _warpPivot) * k;
        case _DragMode.warpTurn:
          var a =
              (doc - _warpPivot).direction - (_warpGrab - _warpPivot).direction;
          if (_shiftHeld) a = (a / (math.pi / 12)).round() * (math.pi / 12);
          var d = p - _warpPivot;
          return _warpPivot +
              Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
                  d.dx * math.sin(a) + d.dy * math.cos(a));
        default:
          return p;
      }
    }

    var picks = controller.warpPicks;
    controller.changeWarp(
        (w) => w.withPoints([
              for (var (k, f) in _warpStartPoints.indexed)
                picks.contains(k) ? toFrac(carried(start[k])) : f
            ]),
        transient: true);
  }

  /// _finishWarpMarquee lets go of the box, picking the points in it unless
  /// [pick] is false (a press the system took away).
  void _finishWarpMarquee({bool pick = true}) {
    var box = _marquee;
    var e = controller.editingImage, id = controller.warpLayer;
    setState(() => _marquee = null);
    if (!pick || box == null || e == null || id == null) return;
    var picks = {...controller.warpPicks};
    for (var (k, p) in _warpPoints(e, id).indexed) {
      if (box.contains(p)) picks.add(k);
    }
    controller.warpPicks = picks;
  }

  /// _nudgeWarp moves the picked points by [by], in canvas units.
  bool _nudgeWarp(Offset by) {
    var e = controller.editingImage, id = controller.warpLayer;
    if (e == null || id == null || controller.warpPicks.isEmpty) return false;
    var (toDoc, toFrac) = _warpSpace(e, id);
    var picks = controller.warpPicks;
    controller.changeWarp((w) => w.withPoints([
          for (var (k, f) in w.grid.indexed)
            picks.contains(k) ? toFrac(toDoc(f) + by) : f
        ]));
    return true;
  }

  /// _pressLayers is a press at [doc] on [e] with its layers open: the picked
  /// layer's knob or handles, then the topmost picture layer under it, then
  /// the base picture. False if it missed the picture, which closes it.
  bool _pressLayers(ImageElement e, Offset doc) {
    if (controller.warpLayer case var id?) return _pressWarp(e, id, doc);
    var picked = controller.pickedLayer;
    // A locked layer is not drawn on, masked or moved. The press is still the
    // picture's, so it stays open.
    if (picked != null &&
        controller.layerLocked(picked) &&
        (controller.imageTool.masks || controller.imageTool.paints)) {
      controller.noteForBrush(controller.imageSolo
          ? "Another layer is soloed: pick this one, or turn Solo off."
          : "This layer is locked: unlock it in the layers list to work on "
              "it.");
      _mode = _DragMode.none;
      return true;
    }
    if (controller.imageTool.masks) return _pressMask(e, doc);
    if (controller.imageTool.paints) return _pressBrush(e, doc);
    if (picked != null &&
        (picked.kind == LayerKind.picture || (picked.isBase && e.layered)) &&
        picked.visible &&
        !controller.layerLocked(picked)) {
      var space = LayerSpace(e, picked);
      if (!picked.isBase && (doc - _layerKnob(space)).distance <= _layerReach) {
        return _holdLayer(picked, _DragMode.imageLayerTurn, -1);
      }
      for (var (i, h) in boxHandles(space.rect).indexed) {
        if ((doc - space.fromLayer(h)).distance <= _layerReach) {
          return _holdLayer(picked, _DragMode.imageLayerSize, i);
        }
      }
    }
    var under = layerAt(e, doc, locked: controller.layerLocked);
    if (!under.isBase) {
      // Shift or Command toggles it into the picks; a press on one already
      // picked keeps the others, so they move together.
      if (_shiftHeld || HardwareKeyboard.instance.isMetaPressed) {
        controller.pickImageLayer(under.id, add: true);
        if (!controller.imageLayers.contains(under.id)) {
          _mode = _DragMode.none;
          return true;
        }
      } else if (!controller.imageLayers.contains(under.id)) {
        controller.pickImageLayer(under.id);
      }
      return _holdLayer(under, _DragMode.imageLayerMove, -1);
    }
    if (!_containsPoint(e, doc)) return false;
    // A locked base picture is not picked or moved; the press only keeps the
    // picture open.
    if (controller.layerLocked(under)) {
      _mode = _DragMode.none;
      return true;
    }
    controller.pickImageLayer(baseLayerId);
    // Layered, the base picture moves about the frame like a picture layer.
    if (e.layered) {
      var base = e.layerById(baseLayerId)!;
      if (LayerSpace(e, base).contains(doc)) {
        return _holdLayer(base, _DragMode.imageLayerMove, -1);
      }
      _mode = _DragMode.none;
      return true;
    }
    // Otherwise the base picture fills its frame, so moving it shifts it
    // inside the frame, which only a cover-fitted picture has room to do. See
    // ImageFraming.
    if (e.hasImage && e.fit == ImageFit.cover) {
      _framingStart = e.framing;
      _mode = _DragMode.imageFrame;
      controller.beginInteraction();
    } else {
      _mode = _DragMode.none;
    }
    return true;
  }

  /// _maskPicture is where the picked layer draws its picture, once loaded.
  LayerPicture? _maskPicture(ImageElement e) {
    var picked = controller.pickedLayer;
    if (picked != null && picked.framed) return LayerPicture.frame(e, picked);
    var look = lookOf(e, controller.imageLayer);
    if (look == null || !look.hasImage) return null;
    var image = controller.images.original(look.assetId);
    if (image == null) return null;
    return LayerPicture.of(e, controller.imageLayer,
        Size(image.width.toDouble(), image.height.toDouble()));
  }

  /// _pressMask is a press with a mask tool: a click for a subject, or a
  /// mark's start. On the picture, or near enough for a stroke to start off
  /// its edge; further off it misses.
  bool _pressMask(ImageElement e, Offset doc) {
    var on = _maskPicture(e);
    if (on == null) return _containsPoint(e, doc);
    var f = on.toPicture(doc);
    bool within(double v) => v >= 0 && v <= 1;
    var inside = within(f.dx) && within(f.dy);
    if (!inside && !_containsPoint(e, doc)) return false;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var hide = controller.maskHide != alt;
    // Pixel-reading tools have no pixels on an adjustment, a texture, a
    // colour or paint.
    if ((controller.pickedLayer?.framed ?? false) &&
        (controller.imageTool == ImageTool.subject ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine)) {
      _mode = _DragMode.none;
      controller.noteForBrush("${controller.imageTool.label} looks for a "
          "subject in a picture. On this layer, mask with the brush, the "
          "lasso or a gradient.");
      return true;
    }
    MaskMark mark;
    switch (controller.imageTool) {
      case ImageTool.subject:
        _mode = _DragMode.none;
        if (inside) {
          unawaited(controller.findSubject(
              at: f,
              how: _shiftHeld
                  ? MaskCombine.add
                  : alt
                      ? MaskCombine.subtract
                      : MaskCombine.replace));
        }
        return true;
      case ImageTool.quick || ImageTool.refine:
        _maskOn = on;
        _quickTrail = [f];
        _quickSubtract = alt;
        _mode = _DragMode.imageQuick;
        setState(() {});
        return true;
      case ImageTool.brush:
        var pressure = _penSample(doc).pressure;
        mark = MaskMark(
            kind: MaskMarkKind.brush,
            points: [f],
            pressure: pressure == null ? const [] : [pressure],
            radius: controller.maskBrushSize,
            hardness: controller.maskHardness,
            strength: controller.maskStrength,
            hide: hide);
      case ImageTool.lasso:
        mark = MaskMark(kind: MaskMarkKind.lasso, points: [f], hide: hide);
      case ImageTool.fade:
        mark = MaskMark(
            kind: MaskMarkKind.fade,
            points: [f, f],
            radial: controller.maskRadial,
            strength: controller.maskStrength,
            hide: hide);
      default:
        return false;
    }
    _maskOn = on;
    _mode = _DragMode.imageMask;
    controller.beginInteraction();
    controller.changeMask((m) => m.withMark(mark).copyWith(on: true),
        transient: true);
    return true;
  }

  void _dragMask(Offset doc) {
    var on = _maskOn;
    if (on == null) return;
    var f = on.toPicture(doc);
    var pressure = _penSample(doc).pressure;
    controller.changeMask((m) {
      if (m.marks.isEmpty) return m;
      var last = m.marks.last;
      if (last.kind == MaskMarkKind.fade) {
        return m.withLastMark(last.copyWith(points: [last.points.first, f]));
      }
      // A point every half picture pixel or so is all a stroke can show, and
      // strokes are kept in the document.
      var was = last.points.last;
      var gap = Offset(
          (f.dx - was.dx) * on.size.width, (f.dy - was.dy) * on.size.height);
      if (gap.distance < 0.75) return m;
      return m.withLastMark(last.copyWith(
          points: [...last.points, f],
          pressure: last.pressure.isEmpty || pressure == null
              ? last.pressure
              : [...last.pressure, pressure]));
    }, transient: true);
  }

  Offset _frameFraction(ImageElement e, Offset doc) {
    var space = LayerSpace(e, ImageLayer.base);
    var p = space.toFrame(doc) - space.inner.topLeft;
    return Offset(p.dx / math.max(1e-9, space.inner.width),
        p.dy / math.max(1e-9, space.inner.height));
  }

  /// _pressBrush starts a paint or retouch stroke, or, cloning with Option,
  /// sets where to copy from.
  bool _pressBrush(ImageElement e, Offset doc) {
    var tool = controller.imageTool;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var pressure = _penSample(doc).pressure;
    if (!tool.retouches) {
      // Anywhere on a picture that does not clip: the frame grows to take
      // the paint. One that clips paints only inside itself.
      if (e.clip && !_containsPoint(e, doc)) return false;
      controller.beginInteraction();
      // Paint goes on a paint layer: one is made over the picked layer if it
      // is not one, in the same step as the stroke.
      if (controller.pickedLayer?.kind != LayerKind.paint) {
        controller.addImageLayer(ImageLayer.painting());
      }
      var f = _frameFraction(controller.editingImage!, doc);
      var mark = StrokeMark(
          kind: tool == ImageTool.erase || alt
              ? StrokeKind.erase
              : StrokeKind.paint,
          points: [f],
          pressure: pressure == null ? const [] : [pressure],
          radius: controller.paintSize,
          hardness: controller.paintHardness,
          strength: controller.paintStrength,
          colour: controller.paintColour,
          tip: controller.paintTip,
          tilt: [if (_penLean() case var lean?) lean]);
      controller.changePaint((s) => [...s, mark], transient: true);
      _strokeAt = (doc) => _frameFraction(controller.editingImage!, doc);
      _mode = _DragMode.imageBrush;
      return true;
    }
    // Across the whole frame, strokes belong to a paint layer, in fractions
    // of the frame; on one picture, to it, in fractions of it.
    var whole = controller.retouchesFrame;
    var on = whole
        ? LayerPicture.frame(e, controller.pickedLayer ?? ImageLayer.base)
        : _maskPicture(e);
    if (on == null) return _containsPoint(e, doc);
    var f = on.toPicture(doc);
    bool within(double v) => v >= 0 && v <= 1;
    if (!(whole && !e.clip) &&
        !(within(f.dx) && within(f.dy)) &&
        !_containsPoint(e, doc)) {
      return false;
    }
    var source = Offset.zero;
    if (tool == ImageTool.clone) {
      _mode = _DragMode.none;
      if (alt) {
        controller.cloneFrom = f;
        return true;
      }
      var from = controller.cloneFrom;
      if (from == null) {
        controller.noteForBrush(
            "Option-click first, on what to copy from -- then paint where it "
            "is to go.");
        return true;
      }
      source = controller.cloneOffset ??= from - f;
    }
    // A heal takes its texture from beside where it starts: see healSource.
    if (tool == ImageTool.heal) {
      source = healSource(f, controller.paintSize, on.size);
    }
    var mark = StrokeMark(
        kind: switch (tool) {
          ImageTool.clone => StrokeKind.clone,
          ImageTool.heal => StrokeKind.heal,
          ImageTool.dodge =>
            controller.burning != alt ? StrokeKind.burn : StrokeKind.dodge,
          ImageTool.sharpen => StrokeKind.sharpen,
          ImageTool.smudge => StrokeKind.smudge,
          _ => StrokeKind.blur,
        },
        points: [f],
        pressure: pressure == null ? const [] : [pressure],
        radius: controller.paintSize,
        hardness: controller.paintHardness,
        strength: controller.paintStrength,
        source: source);
    controller.beginInteraction();
    if (whole) {
      // Its own layer at the top of the picture, in the same step as the
      // stroke, unless a paint layer is picked. See
      // CanvasController.retouchLayerForFrame.
      controller.retouchLayerForFrame();
      controller.changePaint((s) => [...s, mark], transient: true);
    } else {
      controller.changeRetouch((s) => [...s, mark], transient: true);
    }
    // Across the whole frame, measured in the frame at each step: it grows
    // as the stroke passes its edge.
    _strokeAt = whole
        ? (doc) => _frameFraction(controller.editingImage!, doc)
        : on.toPicture;
    _mode = _DragMode.imageBrush;
    return true;
  }

  void _dragBrush(Offset doc) {
    var at = _strokeAt;
    if (at == null) return;
    var f = at(doc);
    var pressure = _penSample(doc).pressure;
    var lean = _penLean();
    List<StrokeMark> grown(List<StrokeMark> strokes) {
      if (strokes.isEmpty) return strokes;
      var last = strokes.last;
      if ((f - last.points.last).distance < 0.0005) return strokes;
      return [
        ...strokes.sublist(0, strokes.length - 1),
        last.copyWith(
            points: [...last.points, f],
            pressure: last.pressure.isEmpty || pressure == null
                ? last.pressure
                : [...last.pressure, pressure],
            tilt: last.tilt.isEmpty || lean == null
                ? last.tilt
                : [...last.tilt, lean]),
      ];
    }

    if (controller.imageTool.retouches &&
        controller.pickedLayer?.kind != LayerKind.paint) {
      controller.changeRetouch(grown, transient: true);
    } else {
      controller.changePaint(grown, transient: true);
    }
  }

  bool _holdLayer(ImageLayer layer, _DragMode mode, int handle) {
    _layerStart = layer;
    _layersMoved = mode == _DragMode.imageLayerMove
        ? [
            for (var l in controller.pickedLayers)
              if (l.kind == LayerKind.picture &&
                  l.id != layer.id &&
                  !controller.layerLocked(l))
                l
          ]
        : const [];
    _layerHandle = handle;
    _mode = mode;
    controller.beginInteraction();
    return true;
  }

  void _dragLayer(Offset doc) {
    var e = controller.editingImage, was = _layerStart;
    if (e == null || was == null) return;
    var start = e.withLayer(was.id, (_) => was);
    var space = LayerSpace(start, was);
    var carried = e;
    ImageLayer next;
    switch (_mode) {
      case _DragMode.imageLayerMove:
        // The travel in the frame's unturned space, so a turned picture moves
        // the way the pointer does.
        var travel = space.toFrame(doc) - space.toFrame(_dragStart);
        var rect = space.rect.shift(travel);
        next = was.placed(layerPlace(space.inner, rect), turn: was.turn);
        for (var other in _layersMoved) {
          var at = layerRect(space.inner, other.place).shift(travel);
          carried = carried.withLayer(
              other.id,
              (_) =>
                  other.placed(layerPlace(space.inner, at), turn: other.turn));
        }
      case _DragMode.imageLayerSize:
        // Corners keep proportions if the picture holds them (Keep its
        // proportions); Shift does the opposite.
        var holds = (was.look ?? e).base.lockAspect;
        var even = _layerHandle < 4 && (holds ? !_shiftHeld : _shiftHeld);
        var rect = space.resized(doc, _layerHandle,
            (r, h, p) => boxResized(r, h, p, even: even, least: 4));
        next = was.placed(layerPlace(space.inner, rect), turn: was.turn);
      case _DragMode.imageLayerTurn:
        var turn = space.turnTo(doc);
        if (_shiftHeld) turn = (turn / 15).round() * 15.0;
        turn = ((turn + 180) % 360) - 180;
        next = was.placed(was.place, turn: turn);
      default:
        return;
    }
    controller.changeImage(carried.withLayer(was.id, (_) => next),
        transient: true);
  }

  /// _framedPicture is the element being reframed and its picture.
  (ImageElement, ui.Image)? _framedPicture() {
    var id = _framing;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! ImageElement) return null;
    var image = controller.images.original(element.assetId);
    return image == null ? null : (element, image);
  }
}

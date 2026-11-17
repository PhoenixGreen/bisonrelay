part of 'canvas_stage.dart';

// Editing a drawing on the canvas: points and handles, the pen, pencil, eraser,
// tint, corner, knife and scale tools. Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

extension StageVectorTools on CanvasStageState {
  PathElement? _selectedPath() {
    var selected = controller.selected;
    return selected is PathElement ? selected : null;
  }

  /// _hitPathControl is the point or handle under [doc], as (index, isHandle,
  /// isOutHandle). Handles first, so one on top of an unbent node's point
  /// can still be pulled out.
  (int, bool, bool)? _hitPathControl(PathElement path, Offset doc) {
    // In document units, so the grab area is one size on screen at any zoom.
    var reach = (handleSize / 2 + handleHitSlop) / _scale;
    for (var i = 0; i < path.nodes.length; i++) {
      var node = path.nodes[i];
      if ((doc - path.outHandleOf(node)).distance <= reach &&
          (node.outDx != 0 || node.outDy != 0)) {
        return (i, true, true);
      }
      if ((doc - path.inHandleOf(node)).distance <= reach &&
          (node.inDx != 0 || node.inDy != 0)) {
        return (i, true, false);
      }
    }
    for (var i = 0; i < path.nodes.length; i++) {
      if ((doc - path.pointOf(path.nodes[i])).distance <= reach) {
        return (i, false, false);
      }
    }
    return null;
  }

  /// _pressVector answers a press on a drawing being edited, and says
  /// whether it took it.
  ///
  /// With the pen out, a press puts a point down. Otherwise a point or handle
  /// is taken (Shift toggles it; one of several picked drags them all); a
  /// second click on the picked point toggles corner/smooth; a double-click
  /// on a line adds a point; a press on a shape picks and drags it; and empty
  /// space drags a box to pick points. Outside the drawing, editing ends and
  /// the press goes on.
  bool _pressVector(VectorElement e, Offset doc) {
    var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
    var twice = clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow;
    // A double-click here is two clicks on one spot.
    var sameSpot = (doc - _lastVectorClick).distance * _scale <= CanvasStageState._penPullMin;
    _lastClickAt = clock.now();
    _lastVectorClick = doc;
    // The pen takes hold of points and handles as picking does, and its next
    // point joins on from the one it took.
    VectorHit? penHit;
    switch (controller.vectorTool) {
      case VectorTool.pen:
        // A double-click finishes the line, as Escape does.
        if (twice && sameSpot) {
          controller.finishPenShape();
          _mode = _DragMode.none;
          return true;
        }
        if (_penCloses(e, doc, reach)) return true;
        penHit = hitVector(e, doc, reach,
            shape: controller.vectorShape,
            picked: controller.vectorPick,
            picks: controller.vectorPicks);
        if (penHit == null) {
          if (anyPointAt(e, doc, reach) case var on?) {
            penHit = VectorHit(on, VectorPart.point);
          }
        }
        if (penHit == null) {
          _penPut(e, doc);
          return true;
        }
      case VectorTool.scale when _pressScale(e, doc, reach):
        return true;
      case VectorTool.boolean:
        _pressCombine(e, doc, reach);
        return true;
      case VectorTool.eraser:
        _pressEraser(e, doc, reach);
        return true;
      case VectorTool.selectShapes:
        _pressItems(e, doc, reach);
        return true;
      case VectorTool.align when controller.vectorAlignsShapes:
        _pressItems(e, doc, reach);
        return true;
      case VectorTool.text:
        var under = shapeAt(e, doc, reach);
        var shapes = e.shapes ?? const <VectorShape>[];
        if (under >= 0 && shapes[under].liveText != null) {
          controller.startVectorTyping(under);
          _typingFor = -2;
        } else {
          controller.newVectorText(VectorSpace(e).toDrawing(doc));
          _typingFor = -2;
        }
        _mode = _DragMode.none;
        return true;
      case VectorTool.knife:
        _knife = [doc];
        _mode = _DragMode.vectorKnife;
        return true;
      case VectorTool.shapes:
        _vectorBefore = e;
        _shapeFrom = doc;
        controller.beginInteraction();
        // On the shape just drawn or picked, or its box's handle: moved or
        // resized, not another drawn.
        if (_shapeGrabbed(e, doc) case (var group, var box, var handle)?) {
          _shapeGroup = group;
          _shapeBox = box;
          _shapeHandle = handle;
          _mode = _DragMode.vectorShapeFit;
          return true;
        }
        _mode = _DragMode.vectorShapeDraw;
        return true;
      case VectorTool.pencil when controller.vectorQuickFill:
        _pressQuickFill(e, doc, reach);
        return true;
      case VectorTool.pencil:
        _pressPencil(e, doc);
        return true;
      case VectorTool.corner when _pressCorner(e, doc, reach):
        return true;
      case VectorTool.tint || VectorTool.shadow || VectorTool.highlight
          when _pressTint(e, doc):
        return true;
      default:
        // Otherwise as the select tool (a scale with nothing to scale, a tint
        // off any point): a box, a shape picked, a click off.
        break;
    }
    var hit = penHit ??
        hitVector(e, doc, reach,
            shape: controller.vectorShape,
            picked: controller.vectorPick,
            picks: controller.vectorPicks);
    var pen = controller.vectorTool == VectorTool.pen;
    if (hit != null) {
      var point = hit.part == VectorPart.point;
      if (point && _shiftHeld) {
        controller.pickVectorPoint(hit.pick, toggle: true);
        if (pen) controller.penFrom(controller.vectorPick);
        _mode = _DragMode.none;
        return true;
      }
      if (twice && point && controller.vectorPick == hit.pick) {
        controller.replaceElement(withSmoothToggled(e, hit.pick));
        _mode = _DragMode.none;
        return true;
      }
      if (point &&
          controller.vectorPicks.length > 1 &&
          controller.vectorPicks.contains(hit.pick)) {
        _vectorBefore = e;
        _vectorFrom = doc;
        _mode = _DragMode.vectorPoints;
        controller.beginInteraction();
        return true;
      }
      if (point) controller.pickVectorPoint(hit.pick);
      if (pen) controller.penFrom(hit.pick);
      _vectorPart = hit.part;
      _mode = _DragMode.vectorPoint;
      controller.beginInteraction();
      return true;
    }
    // Inside the box round several picked points drags them all, by their
    // middle as well as any one of them.
    if (!twice && !_shiftHeld) {
      var box = picksBox(e, controller.vectorPicks);
      // As far out as the box is drawn: a handle's width round the points.
      if (box != null && box.inflate(e.handleSize / _scale).contains(doc)) {
        _vectorBefore = e;
        _vectorFrom = doc;
        _mode = _DragMode.vectorPoints;
        controller.beginInteraction();
        return true;
      }
    }
    // A double-click on a shape's line adds a point there; on its fill, it
    // picks every point connected to the part clicked. Both clicks on one
    // spot.
    if (twice && sameSpot) {
      var shape = controller.vectorShape >= 0
          ? controller.vectorShape
          : shapeAt(e, doc, reach);
      var shapes = e.shapes ?? const <VectorShape>[];
      if (shape >= 0 && shape < shapes.length) {
        var space = VectorSpace(e);
        var onLine = math.max(
            shapes[shape].strokeWidth / 2 / space.unitsPer, reach * 0.5);
        var at = nearestSegment(e, shape, doc, onLine);
        if (at != null) {
          var (next, pick) = withPointAdded(e, shape, at.$1, at.$2, at.$3);
          controller.replaceElement(next);
          controller.pickVectorPoint(pick);
          _mode = _DragMode.none;
          return true;
        }
      }
      var under = shapeAt(e, doc, reach);
      if (under >= 0) {
        controller.pickVectorPoints(
            connectedPicks(e, under, VectorSpace(e).toDrawing(doc)));
        _mode = _DragMode.none;
        return true;
      }
    }
    // A shape cut into pieces: a press picks a piece's points, and a drag
    // moves it alone. See vector_cut.dart.
    if (!twice && !_shiftHeld && controller.vectorTool == VectorTool.select) {
      var under = shapeAt(e, doc, reach);
      var shapes = e.shapes ?? const <VectorShape>[];
      if (under >= 0 && partsOf(shapes[under]).length > 1) {
        var space = VectorSpace(e);
        var shape = shapes[under];
        if (partAt(shape, space.toDrawing(doc), reach * space.unitsPer)
            case var part?) {
          controller.pickVectorPoints({
            for (var (p, run) in shape.paths.indexed)
              if (run.part == part)
                for (var n = 0; n < run.nodes.length; n++)
                  VectorPick(under, p, n),
          });
          _vectorBefore = e;
          _vectorFrom = doc;
          _mode = _DragMode.vectorPoints;
          controller.beginInteraction();
          return true;
        }
      }
    }
    // Anywhere else starts a box to pick points; released without moving it
    // is a click, which on a shape picks the shape. See _onPointerUp.
    _vectorShapeUnder = shapeAt(e, doc, reach);
    // A box from off the drawing can sweep up its edge points; a still click
    // off it finishes editing. The picks stay until the box is let go.
    _vectorPressedOutside = !_visualBounds(e).contains(doc);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorMarquee;
    return true;
  }

  /// _penLean is the pen's lean across and down, each -1 to 1, or null for a
  /// mouse or a pen that does not say.
  Offset? _penLean() {
    var tablet = TabletInput.instance;
    if (tablet.fresh) return Offset(tablet.tiltX, tablet.tiltY);
    var ev = _pointer;
    if (ev == null ||
        (ev.kind != PointerDeviceKind.stylus &&
            ev.kind != PointerDeviceKind.invertedStylus)) {
      return null;
    }
    // Flutter's tilt: how far over (a quarter turn at most), and which way.
    var lean = (ev.tilt / (math.pi / 2)).clamp(0.0, 1.0);
    return Offset(math.sin(ev.orientation), -math.cos(ev.orientation)) * lean;
  }

  /// _penSample is the pen as [_pointer] last reported it, at [doc]: pressure
  /// and tilt are null for a mouse or a platform that gives neither, and the
  /// brush then makes do with speed.
  PenSample _penSample(Offset doc) {
    var ev = _pointer;
    // On macOS the runner reads the pen: see TabletInput.
    var tablet = TabletInput.instance;
    if (tablet.fresh) {
      return PenSample(doc,
          pressure: tablet.pressure,
          tilt: tablet.tilt,
          time: ev?.timeStamp ?? Duration.zero);
    }
    var pen = ev != null &&
        (ev.kind == PointerDeviceKind.stylus ||
            ev.kind == PointerDeviceKind.invertedStylus);
    double? pressure;
    if (pen && ev.pressureMax > ev.pressureMin) {
      pressure =
          (ev.pressure - ev.pressureMin) / (ev.pressureMax - ev.pressureMin);
    }
    return PenSample(doc,
        pressure: pressure,
        tilt: pen ? ev.tilt : null,
        time: ev?.timeStamp ?? Duration.zero);
  }

  /// _pressEraser starts the eraser: rubbing out lines, fills or both as
  /// set, or, set to whole lines, removing each line and shape it touches.
  /// On the page only, as the pencil is.
  void _pressEraser(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    if (!_onPage(doc)) return;
    controller.beginInteraction();
    if (controller.vectorEraseWhole) {
      _eraseReach = math.max(reach, controller.vectorEraseSize / 2 / _scale);
      controller.replaceElement(withoutShapesAt(e, doc, _eraseReach),
          transient: true);
      _mode = _DragMode.vectorErase;
      return;
    }
    _startStroke(
        e,
        doc,
        VectorTint(
            points: const [],
            paint: const PaintSpec(Color(0xFF000000)),
            width:
                controller.vectorEraseSize / _scale * VectorSpace(e).unitsPer,
            soft: controller.vectorEraseSoft,
            line: controller.vectorEraseLine,
            fill: controller.vectorEraseFill,
            erase: true),
        rubOut: true);
    _mode = _DragMode.vectorRub;
  }

  /// _picksShapes is whether presses pick whole shapes: the select shapes
  /// tool, or align after it.
  bool get _picksShapes =>
      controller.vectorTool == VectorTool.selectShapes ||
      (controller.vectorTool == VectorTool.align &&
          controller.vectorAlignsShapes);

  /// _pressItems is a press with the select shapes tool: a handle of the
  /// picked box takes that handle; a shape is held to move (Shift toggles
  /// it); inside the box, everything picked is held; elsewhere, nothing.
  void _pressItems(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var space = VectorSpace(e);
    var items = controller.vectorItems;
    var box = itemsExtent(e, items);
    void hold(Rect box, int? handle) {
      _vectorBefore = e;
      _shapeFrom = doc;
      _itemsBox = box;
      _itemsHandle = handle;
      controller.beginInteraction();
      _mode = _DragMode.vectorItems;
    }

    if (box != null && !_shiftHeld) {
      var top = space.toCanvas(box.topCenter) * _scale;
      if ((doc * _scale - (top - const Offset(0, shapeTurnReach))).distance <=
          8) {
        return hold(box, -1);
      }
      for (var (i, h) in boxHandles(box).indexed) {
        if ((space.toCanvas(h) - doc).distance * _scale <= 7) {
          return hold(box, i);
        }
      }
    }
    var under = itemAt(e, doc, reach);
    if (under != null) {
      if (_shiftHeld) {
        controller.pickVectorItem(under, toggle: true);
        return;
      }
      if (!items.contains(under)) controller.pickVectorItem(under);
      var now = itemsExtent(e, controller.vectorItems);
      if (now != null) hold(now, null);
      return;
    }
    if (box != null && box.contains(space.toDrawing(doc)) && !_shiftHeld) {
      return hold(box, null);
    }
    // Empty space: a box picks every shape it touches.
    if (!_shiftHeld) controller.pickVectorItem(null);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorItemsBox;
  }

  /// _dragItems moves, sizes or turns the picked shapes to follow [doc]: a
  /// handle keeps its opposite side put (Shift keeps a corner's proportions);
  /// the turning handle turns about the middle (Shift in 15-degree steps);
  /// held inside moves the whole.
  void _dragItems(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var space = VectorSpace(before);
    var at = space.toDrawing(doc);
    var from = space.toDrawing(_shapeFrom);
    var box = _itemsBox;
    var items = controller.vectorItems;
    VectorElement next;
    if (_itemsHandle == -1) {
      var c = box.center;
      var turn = math.atan2(at.dy - c.dy, at.dx - c.dx) -
          math.atan2(from.dy - c.dy, from.dx - c.dx);
      if (_shiftHeld) {
        const step = math.pi / 12;
        turn = (turn / step).round() * step;
      }
      next = withItemsTurned(before, items, c, turn);
    } else {
      var to = _itemsHandle == null
          ? box.shift(at - from)
          : boxResized(box, _itemsHandle!, at,
              even: _shiftHeld, least: space.unitsPer);
      next = withItemsFitted(before, items, box, to);
    }
    controller.replaceElement(next, transient: true);
  }

  /// _shapeGrabbed is (group, box, handle) when [doc] is on the picked shape
  /// (the shapes tool's last, or whatever was picked) or a handle of its box;
  /// handle is null inside it. Null elsewhere, which draws a new shape.
  (int, Rect, int?)? _shapeGrabbed(VectorElement e, Offset doc) {
    var picked = controller.vectorShapeMade;
    if (picked < 0) return null;
    var group = groupStarts(e).indexOf(groupOf(e, picked));
    var box = groupExtent(e, group);
    if (group < 0 || box == null) return null;
    var space = VectorSpace(e);
    for (var (i, h) in boxHandles(box).indexed) {
      if ((space.toCanvas(h) - doc).distance * _scale <= 7) {
        return (group, box, i);
      }
    }
    if (box.contains(space.toDrawing(doc))) return (group, box, null);
    return null;
  }

  /// _fitShape moves or resizes the held shape to follow [doc]: a handle
  /// keeps its opposite side put (Shift keeps a corner's proportions); held
  /// inside moves the whole.
  void _fitShape(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var space = VectorSpace(before);
    var at = space.toDrawing(doc);
    var box = _shapeBox;
    var next = _shapeHandle == null
        ? box.shift(at - space.toDrawing(_shapeFrom))
        : boxResized(box, _shapeHandle!, at,
            even: _shiftHeld, least: space.unitsPer);
    controller.replaceElement(withGroupFitted(before, _shapeGroup, box, next),
        transient: true);
  }

  /// _drawShape draws the shapes tool's shape from the drag's start to [doc]:
  /// in the box between, or end to end for a line or arrow. Shift keeps a box
  /// square and a line to 45-degree steps; Alt draws from the middle.
  /// [clicked] draws one of a good size round a click that never dragged.
  void _drawShape(Offset doc, {bool clicked = false}) {
    var before = _vectorBefore;
    if (before == null) return;
    var kind = controller.vectorShapeKind;
    var shift = _shiftHeld, alt = HardwareKeyboard.instance.isAltPressed;
    var a = _shapeFrom, b = doc;
    if (clicked) {
      var half = 40 / _scale;
      a = _shapeFrom - Offset(half, kind.fromEnds ? 0 : half);
      b = _shapeFrom + Offset(half, kind.fromEnds ? 0 : half);
    } else if (kind.fromEnds) {
      var d = b - a;
      if (shift && d.distance > 0) {
        const step = math.pi / 4;
        var angle = (math.atan2(d.dy, d.dx) / step).round() * step;
        d = Offset(math.cos(angle), math.sin(angle)) * d.distance;
      }
      b = a + d;
      if (alt) a = a - d;
    } else {
      var d = b - a;
      if (kind.even || shift) {
        var m = math.max(d.dx.abs(), d.dy.abs());
        d = Offset(d.dx < 0 ? -m : m, d.dy < 0 ? -m : m);
      }
      b = a + d;
      if (alt) a = a - d;
    }
    var space = VectorSpace(before);
    var from = space.toDrawing(a), to = space.toDrawing(b);
    var box = Rect.fromPoints(from, to);
    var shape = shapeOf(kind, box,
        from: from,
        to: to,
        sides: controller.vectorShapeSides,
        inner: controller.vectorStarInner,
        corner: controller.vectorShapeCorner * math.min(box.width, box.height),
        fill: controller.vectorShapeFill,
        stroke: controller.vectorShapeLine,
        strokeWidth: controller.vectorShapeWidth / _scale * space.unitsPer);
    controller.replaceElement(
        before.copyWith(shapes: [...?before.shapes, shape]),
        transient: true);
  }

  /// _typedLayout is the text being typed, laid out, with its drawing.
  (VectorElement, VectorTextLayout)? _typedLayout() {
    var e = controller.editingVector;
    var i = controller.vectorTyping;
    var shapes = e?.shapes;
    if (e == null || shapes == null || i < 0 || i >= shapes.length) {
      return null;
    }
    var s = shapes[i];
    var t = s.liveText;
    if (t == null) return null;
    var pick = FontFiles.instance.cached(t.family, t.weight, t.italic);
    if (pick == null) return null;
    return (e, layoutVectorText(t, s.textOrigin ?? t.origin, pick));
  }

  /// _caret is the caret's top and bottom on the page.
  (Offset, Offset)? _caret() {
    if (_typedLayout() case (var e, var laid)?) {
      var at =
          _typing.selection.baseOffset.clamp(0, laid.carets.length - 1).toInt();
      var p = laid.carets[at];
      var space = VectorSpace(e);
      return (
        space.toCanvas(p - Offset(0, laid.ascent)),
        space.toCanvas(p + Offset(0, laid.descent)),
      );
    }
    return null;
  }

  Widget? _typingField() {
    var i = controller.vectorTyping;
    if (i < 0) {
      _typingFor = -1;
      return null;
    }
    var e = controller.editingVector;
    var t = (e?.shapes != null && i < e!.shapes!.length)
        ? e.shapes![i].liveText
        : null;
    if (_typingFor != i) {
      _typingFor = i;
      var text = t?.text ?? "";
      // Filled during the build, so _filling keeps its listener from
      // asking for another.
      _filling = true;
      _typing.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      _filling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _typingFocus.requestFocus();
      });
    }
    var caret = _caret();
    var at = caret == null ? Offset.zero : _toStage(caret.$1);
    return Positioned(
      left: at.dx,
      top: at.dy,
      width: 2,
      height: 2,
      child: Opacity(
        opacity: 0,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              controller.stopVectorTyping();
              _focus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey("vectorTypingField"),
            controller: _typing,
            focusNode: _typingFocus,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            onChanged: (v) {
              var e = controller.editingVector;
              var i = controller.vectorTyping;
              var shape = e?.shapes != null && i >= 0 && i < e!.shapes!.length
                  ? e.shapes![i]
                  : null;
              var t = shape?.liveText;
              if (t != null) {
                controller.retypeVectorText(i, t.copyWith(text: v));
              }
            },
          ),
        ),
      ),
    );
  }

  /// _sampleAt takes the colour at [doc], as drawn at this frame, for the
  /// eyedropper.
  Future<void> _sampleAt(Offset doc) async {
    var rec = ui.PictureRecorder();
    var canvas = Canvas(rec);
    canvas.translate(-doc.dx, -doc.dy);
    paintCanvasDocument(canvas, controller.document,
        frame: controller.frame, images: controller.images);
    var picture = rec.endRecording();
    var image = await picture.toImage(1, 1);
    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null || !mounted) return;
    controller.sampledColour(Color.fromARGB(bytes.getUint8(3),
        bytes.getUint8(0), bytes.getUint8(1), bytes.getUint8(2)));
  }

  /// _finishKnife cuts the picked shape, or every shape the knife crossed.
  void _finishKnife() {
    var line = _knife;
    setState(() => _knife = const []);
    var e = controller.editingVector;
    if (e == null || line.length < 2) return;
    var space = VectorSpace(e);
    var drawn = simplifiedKnife([for (var p in line) space.toDrawing(p)],
        0.5 / _scale * space.unitsPer);
    var gap = controller.vectorKnifeGap * space.unitsPer;
    var shapes = e.shapes ?? const <VectorShape>[];
    var only = controller.vectorShape;
    var next = <VectorShape>[];
    var cut = false;
    for (var (i, s) in shapes.indexed) {
      var pieces = only >= 0 && i != only ? null : cutShape(s, drawn, gap);
      cut |= pieces != null;
      next.add(pieces ?? s);
    }
    if (!cut) return;
    controller.replaceElement(e.copyWith(shapes: next));
    // The points are renumbered: none stays picked.
    controller.pickVectorShape(only);
  }

  /// _pressQuickFill fills the area the lines close round the click, or
  /// recolours an earlier quick fill (a fill with no line). An open area is
  /// reported and left unfilled.
  void _pressQuickFill(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var colour = controller.vectorPencilFill;
    var hit = shapeAt(e, doc, reach);
    if (hit >= 0) {
      var s = e.shapes![hit];
      if (s.fill != null && s.stroke == null) {
        controller.replaceElement(e.withShape(hit, s.copyWith(fill: colour)));
        return;
      }
    }
    var gap = controller.vectorFillGap / _scale * VectorSpace(e).unitsPer;
    var snack = SnackBarModel.of(context);
    quickFilled(e, doc, colour, gap: gap).then((next) {
      // Only onto the drawing it was worked out from: later edits win.
      if (!mounted || !identical(controller.editingVector, e)) return;
      if (next == null) {
        snack.error("That area isn't closed: no fill");
        return;
      }
      controller.replaceElement(next);
    });
  }

  /// _onPage is whether [doc] is on the page, the only place the pencil
  /// draws: a resting hand or a pen run off the edge puts nothing down.
  bool _onPage(Offset doc) =>
      (Offset.zero & controller.document.size.size).contains(doc);

  void _pressPencil(VectorElement e, Offset doc) {
    if (!_onPage(doc)) {
      _mode = _DragMode.none;
      return;
    }
    var space = VectorSpace(e);
    _vectorBefore = e;
    _penInto = controller.vectorSelectedShapes;
    _penWidth = controller.vectorBrush.size / _scale * space.unitsPer;
    _penSamples = [_penSample(doc)];
    _penRuns = [_penSamples];
    controller.beginInteraction();
    _drawPencil();
    _mode = _DragMode.vectorPencil;
  }

  /// _mergePencil adds the pencil's new stroke to the one picked filled shape
  /// where it touches it, as a blob brush does.
  void _mergePencil() {
    var before = _vectorBefore, e = controller.editingVector;
    if (before == null || e == null || _penInto.length != 1) return;
    var was = before.shapes ?? const <VectorShape>[];
    var now = e.shapes ?? const <VectorShape>[];
    var base = _penInto.first;
    if (now.length <= was.length || base >= was.length) return;
    if (groupMembers(before, base).length != 1) return;
    var target = was[base];
    // Only in its own colour: a line in another (an eye on a face) is a
    // shape of its own.
    var fill = target.fill, ink = controller.vectorPencilColour;
    if (fill == null ||
        (fill.r - ink.r).abs() > 0.01 ||
        (fill.g - ink.g).abs() > 0.01 ||
        (fill.b - ink.b).abs() > 0.01) {
      return;
    }
    Path area(VectorShape s) {
      var out = Path();
      if (s.fill != null) {
        out = Path.combine(PathOperation.union, out, vectorShapePath(s));
      }
      if (s.stroke != null) {
        out = Path.combine(PathOperation.union, out, vectorLinePath(s));
      }
      return out;
    }

    var added = now.sublist(was.length);
    if (added.isEmpty) return;
    var into = vectorShapePath(target);
    var stroke = added
        .map(area)
        .reduce((a, b) => Path.combine(PathOperation.union, a, b));
    if (Path.combine(PathOperation.intersect, into, stroke)
        .getBounds()
        .isEmpty) {
      return;
    }
    var merged = Path.combine(PathOperation.union, into, stroke);
    var paths =
        vectorPathsOf(merged, tolerance: 0.35 * VectorSpace(before).unitsPer);
    if (paths.isEmpty) return;
    controller.replaceElement(
        before.copyWith(shapes: [
          for (var (i, s) in was.indexed)
            i == base ? s.copyWith(paths: paths) : s,
        ]),
        transient: true);
  }

  void _applyPencil(Offset doc) {
    if (!_onPage(doc)) {
      // Off the page the stretch ends; back on, another starts.
      _penSamples = [];
      return;
    }
    var last = _penSamples.lastOrNull;
    if (last != null && (doc - last.at).distance * _scale < 1) return;
    if (_penSamples.isEmpty) _penRuns.add(_penSamples);
    _penSamples.add(_penSample(doc));
    _drawPencil();
  }

  void _drawPencil() {
    var before = _vectorBefore;
    if (before == null) return;
    // The stroke and its mirror images, each its own line.
    var drawn = [
      for (var run in _penRuns)
        for (var (samples, brush) in mirroredStrokes(
            before, run, controller.vectorBrush,
            across: controller.vectorMirrorAcross,
            down: controller.vectorMirrorDown))
          if (pencilShape(before, samples, brush, controller.vectorPencilColour,
                  _penWidth,
                  fillColour: controller.vectorPencilFill)
              case var shape?)
            shape,
    ];
    if (drawn.isEmpty) return;
    controller.replaceElement(
        before.copyWith(shapes: [...?before.shapes, ...drawn]),
        transient: true);
  }

  /// _modifierButton is the pen button a key held as the pen touches stands
  /// for (Shift first, Option second, Control third), or null. Command is
  /// left for shortcuts.
  int? _modifierButton() {
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed) return null;
    if (keys.isShiftPressed) return 0;
    if (keys.isAltPressed) return 1;
    if (keys.isControlPressed) return 2;
    return null;
  }

  /// _tabletButton is the pen button (0 to 2) the tablet says is held.
  int? _tabletButton() {
    var t = TabletInput.instance;
    if (!t.fresh) return null;
    for (var (i, bit) in const [(0, 2), (1, 4), (2, 8)]) {
      if (t.buttons & bit != 0) return i;
    }
    return null;
  }

  /// _stylusPress does what a pen button (or its other end) is set to, with
  /// the pencil out, and says whether it took the press. Tablet drivers send
  /// pen buttons as mouse buttons (right, middle, back) as mapped in their
  /// settings.
  bool _stylusPress(PointerDownEvent event, Offset doc) {
    var e = controller.editingVector;
    if (e == null || controller.vectorTool != VectorTool.pencil) return false;
    var b = event.buttons;
    var buttons = controller.stylusButtons;
    StylusAction? action;
    if (event.kind == PointerDeviceKind.invertedStylus ||
        (TabletInput.instance.eraser && TabletInput.instance.near)) {
      action = controller.stylusEraser;
    } else if (_tabletButton() case var i?) {
      action = buttons[i];
    } else if (b & kSecondaryButton != 0) {
      action = buttons[0];
    } else if (b & kMiddleMouseButton != 0) {
      action = buttons[1];
    } else if (b & (kBackMouseButton | kForwardMouseButton) != 0) {
      action = buttons[2];
    } else if (_modifierButton() case var i?) {
      // A key held as the pen touches stands in for a button, for pen
      // displays whose own buttons are taken (a MovinkPad's open its key
      // sidebar).
      action = buttons[i];
    }
    if (action == null || action == StylusAction.draw) return false;
    var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
    _mode = _DragMode.none;
    switch (action) {
      case StylusAction.draw:
        return false;
      case StylusAction.erase:
        _eraseReach = math.max(reach, controller.vectorBrush.size / 2 / _scale);
        controller.beginInteraction();
        controller.replaceElement(withoutShapesAt(e, doc, _eraseReach),
            transient: true);
        _mode = _DragMode.vectorErase;
      case StylusAction.pickColour:
        var hit = shapeAt(e, doc, reach);
        if (hit >= 0) {
          var s = e.shapes![hit];
          if ((s.stroke ?? s.fill) case var c?) {
            controller.vectorPencilColour = c.withValues(alpha: 1);
          }
        }
      case StylusAction.pan:
        _mode = _DragMode.pan;
        _startPan = _clampedPan;
        _dragStart = event.localPosition;
      case StylusAction.undo:
        controller.undo();
      case StylusAction.select:
        controller.vectorTool = VectorTool.select;
      case StylusAction.nothing:
        break;
    }
    return true;
  }

  /// _pressCorner rounds (or cuts) the corner at the pressed point by the
  /// corner size; the following drag sets how far. While the corner made is
  /// still picked, a press on it (either point, or where the corner was)
  /// goes on shaping it. Off any point it declines, and the press picks as
  /// the select tool would.
  bool _pressCorner(VectorElement e, Offset doc, double reach) {
    var on = anyPointAt(e, doc, reach);
    if (controller.vectorCornerPoint case var was?) {
      var at = VectorSpace(e).toCanvas(was);
      if ((on != null && controller.vectorPicks.contains(on)) ||
          (doc - at).distance <= reach * 2) {
        controller.beginInteraction();
        _cornerFrom = at;
        _mode = _DragMode.vectorCorner;
        return true;
      }
    }
    if (on == null) return false;
    _mode = _DragMode.none;
    // A corner already rounded (earlier, or a rounded box's) is taken up to
    // reshape, not rounded again.
    if (controller.adoptCorner(on)) {
      if (controller.vectorCornerPoint case var was?) {
        controller.beginInteraction();
        _cornerFrom = VectorSpace(e).toCanvas(was);
        _mode = _DragMode.vectorCorner;
      }
      return true;
    }
    var node = vectorNodeAt(e, on);
    if (node == null) return true;
    controller.beginInteraction();
    if (!controller.roundCorner(on, transient: true)) {
      controller.endInteraction();
      return true;
    }
    _cornerFrom = VectorSpace(e).toCanvas(node.point);
    _mode = _DragMode.vectorCorner;
    return true;
  }

  void _applyCorner(Offset doc) {
    controller.sizeCorner(
        math.max(0.5, (doc - _cornerFrom).distance).roundToDouble(),
        transient: true);
  }

  /// _pressCombine is a Boolean-tool click: on a shape it toggles that shape
  /// for combining (a combined shape whole, never a part); on empty space it
  /// unpicks all; off the drawing it finishes editing.
  void _pressCombine(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var hit = shapeAt(e, doc, reach);
    if (hit >= 0) {
      controller.toggleCombining(groupOf(e, hit));
    } else if (_visualBounds(e).contains(doc)) {
      controller.clearCombining();
    } else {
      controller.editVector(null);
    }
  }

  /// _penCloses closes the pen's run on a press at its first point.
  bool _penCloses(VectorElement e, Offset doc, double reach) {
    var from = controller.vectorPenFrom;
    var shapes = e.shapes ?? const <VectorShape>[];
    if (from == null ||
        from.shape >= shapes.length ||
        from.path >= shapes[from.shape].paths.length) {
      return false;
    }
    var run = shapes[from.shape].paths[from.path];
    var first = VectorSpace(e).toCanvas(run.nodes.first.point);
    if (run.closed ||
        run.nodes.length < 3 ||
        from.node != run.nodes.length - 1 ||
        (first - doc).distance > reach) {
      return false;
    }
    controller.replaceElement(withPenClosed(e, from));
    controller.finishPenShape();
    _mode = _DragMode.none;
    return true;
  }

  /// _penPut puts the pen's next point at [doc], joined from the point last
  /// put or taken, or starting a shape. The following drag pulls out its
  /// handles; press and drag are one undo step.
  void _penPut(VectorElement e, Offset doc) {
    var from = controller.vectorPenFrom;
    var shapes = e.shapes ?? const <VectorShape>[];
    if (from != null && vectorNodeAt(e, from) == null) from = null;
    var picked = controller.vectorShape;
    // A new shape copies the picked shape, or the colours set for new shapes.
    // See ColourPanel.
    var view = e.viewBox;
    var like = from == null && picked >= 0 && picked < shapes.length
        ? shapes[picked]
        : VectorShape(
            paths: const [],
            stroke: controller.vectorShapeLine ?? const Color(0xFF000000),
            strokeWidth: math.max(1.0, math.min(view.width, view.height) / 100),
            cap: StrokeCap.round,
            join: StrokeJoin.round);
    controller.beginInteraction();
    _vectorFrom = doc;
    var (next, pick) = withPenPoint(e, from, doc, like: like);
    controller.replaceElement(next, transient: true);
    controller.penFrom(pick);
    controller.pickVectorPoint(pick);
    _mode = _DragMode.vectorPen;
  }

  /// _pressScale starts the line thickness tool on the picked points (or,
  /// with none, the point nearest the press) and every point the drag passes
  /// near.
  bool _pressScale(VectorElement e, Offset doc, double reach) {
    // The reach is wider than a point's handle: a drag sweeps across a
    // line's points as a brush would.
    var near = math.max(reach, CanvasStageState._thicknessReach / _scale);
    var picks = controller.vectorPicks;
    var hit = anyPointAt(e, doc, reach);
    if (hit != null && _shiftHeld) {
      controller.pickVectorPoint(hit, toggle: true);
      _mode = _DragMode.none;
      return true;
    }
    Set<VectorPick> those;
    if (hit != null) {
      if (!picks.contains(hit)) controller.pickVectorPoint(hit);
      those = controller.vectorPicks;
    } else if (picks.isNotEmpty) {
      those = picks;
    } else {
      var nearest = anyPointAt(e, doc, near);
      those = nearest == null ? const {} : {nearest};
    }
    // Only a drag with nothing picked sweeps up the points it passes.
    _sweeping = hit == null && picks.isEmpty;
    // A click off every point unpicks them. See _onPointerUp.
    _scaleLetsGo = hit == null && picks.isNotEmpty;
    _widths = {
      for (var p in joinedTo(e, those))
        if (vectorNodeAt(e, p) case var n?) p: n.width,
    };
    _scaleReach = near;
    _vectorBefore = e;
    _vectorFrom = doc;
    _mode = _DragMode.vectorScale;
    controller.beginInteraction();
    return true;
  }

  /// _applyScale scales by the pointer's travel: right or up larger, left or
  /// down smaller, doubling or halving every 150 screen pixels at any zoom.
  void _applyScale(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var moved = (doc - _vectorFrom) * _scale;
    var factor = math.pow(2, (moved.dx - moved.dy) / 150).toDouble();
    // A point passed near joins in from its own width.
    for (var over in _sweeping
        ? pointsNear(before, doc, _scaleReach)
        : const <VectorPick>{}) {
      if (_widths.containsKey(over)) continue;
      for (var p in joinedTo(before, {over})) {
        _widths[p] = vectorNodeAt(before, p)?.width ?? 1;
      }
    }
    if (_widths.isEmpty) return;
    controller.replaceElement(withWidths(before, _widths, factor),
        transient: true);
  }

  /// _pressTint starts a tint stroke (an eraser's, with Alt).
  bool _pressTint(VectorElement e, Offset doc) {
    controller.beginInteraction();
    _mode = _DragMode.vectorTint;
    // Off the drawing nothing paints until the brush reaches it; a still
    // release is a click off it. The brush never picks.
    if (!_visualBounds(e).contains(doc)) {
      _tintWaiting = doc;
      return true;
    }
    _tintWaiting = null;
    _startTint(e, doc);
    return true;
  }

  /// _shade is the stroke's kind: a tint (0), a shadow (-1) or a highlight
  /// (1). See VectorTool.shadow.
  int get _shade => switch (controller.vectorTool) {
        VectorTool.shadow => -1,
        VectorTool.highlight => 1,
        _ => 0,
      };

  void _startTint(VectorElement e, Offset doc) {
    var space = VectorSpace(e);
    var unit =
        (space.toDrawing(doc + const Offset(1, 0)) - space.toDrawing(doc))
            .distance;
    _startStroke(
        e,
        doc,
        VectorTint(
          points: const [],
          paint: controller.vectorTint,
          width: controller.vectorBrushSize / _scale * unit,
          // Drawn-on shading is cel shading: hard-edged unless softened.
          soft: _shade != 0
              ? controller.vectorBrushSoft * 0.5
              : controller.vectorBrushSoft,
          line: controller.vectorTintLine,
          fill: controller.vectorTintFill,
          erase: HardwareKeyboard.instance.isAltPressed,
        ));
  }

  void _applyTint(Offset doc) {
    var e = controller.editingVector;
    if (e == null) return;
    if (_tintWaiting case var from?) {
      _tintWaiting = null;
      _startTint(e, from);
    }
    _carryStroke(doc);
  }

  void _startStroke(VectorElement e, Offset doc, VectorTint like,
      {bool rubOut = false}) {
    var at = VectorSpace(e).toDrawing(doc);
    _vectorBefore = e;
    _strokeRubs = rubOut;
    _stroke = VectorTint(
        points: [at],
        paint: like.paint,
        width: like.width,
        soft: like.soft,
        line: like.line,
        fill: like.fill,
        erase: like.erase);
    _strokeOn = _onPicked(shapesUnder(e, at, like.width / 2));
    controller.replaceElement(
        withStrokeOn(e, _strokeOn, _stroke!,
            rubOut: rubOut, shade: rubOut ? 0 : _shade),
        transient: true);
  }

  /// _onPicked keeps [under] to the picked shapes, if any.
  Set<int> _onPicked(Set<int> under) {
    var picked = controller.vectorSelectedShapes;
    return picked.isEmpty ? under : under.intersection(picked);
  }

  void _carryStroke(Offset doc) {
    var before = _vectorBefore, stroke = _stroke;
    if (before == null || stroke == null) return;
    var at = VectorSpace(before).toDrawing(doc);
    if ((at - stroke.points.last).distance < stroke.width / 10) return;
    _stroke = stroke.withPoint(at);
    _strokeOn = {
      ..._strokeOn,
      ..._onPicked(shapesUnder(before, at, stroke.width / 2))
    };
    controller.replaceElement(
        withStrokeOn(before, _strokeOn, _stroke!,
            rubOut: _strokeRubs, shade: _strokeRubs ? 0 : _shade),
        transient: true);
  }

  void _moveBrush(Offset stage) {
    var on = controller.editingVector != null &&
        (controller.vectorTool == VectorTool.tint ||
            controller.vectorTool == VectorTool.shadow ||
            controller.vectorTool == VectorTool.highlight ||
            controller.vectorTool == VectorTool.pencil ||
            controller.vectorTool == VectorTool.eraser);
    var at = on ? stage : null;
    if (at != _brushAt) setState(() => _brushAt = at);
  }

  /// _brushRing is the brush outline under the pointer, a stroke's width.
  Widget? _brushRing() {
    var at = _brushAt;
    var pencil = controller.vectorTool == VectorTool.pencil &&
        !controller.vectorQuickFill;
    if (controller.vectorTool == VectorTool.pencil && !pencil) return null;
    var eraser = controller.vectorTool == VectorTool.eraser;
    if (at == null ||
        controller.editingVector == null ||
        (controller.vectorTool != VectorTool.tint &&
            controller.vectorTool != VectorTool.shadow &&
            controller.vectorTool != VectorTool.highlight &&
            !pencil &&
            !eraser)) {
      return null;
    }
    var d = math.max(
        4.0,
        pencil
            ? controller.vectorBrush.size
            : eraser
                ? controller.vectorEraseSize
                : controller.vectorBrushSize);
    return Positioned(
      left: at.dx - d / 2,
      top: at.dy - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xCCFFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), spreadRadius: 0.5),
            ],
          ),
        ),
      ),
    );
  }

  /// _applyVectorMove drags the picked point, or one of its handles. Alt
  /// moves a smooth point's handle alone, making it a corner.
  void _applyVectorMove(Offset doc) {
    var e = controller.editingVector, pick = controller.vectorPick;
    if (e == null || pick == null) return;
    controller.replaceElement(
        movedVector(e, pick, _vectorPart, doc,
            breakHandles: HardwareKeyboard.instance.isAltPressed,
            drag: controller.vectorHandleDrag,
            snap: controller.vectorHandleSnap || _shiftHeld),
        transient: true);
  }

  void _applyNodeMove(Offset doc, {required bool handle}) {
    var path = _selectedPath();
    if (path == null || _nodeIndex < 0 || _nodeIndex >= path.nodes.length) {
      return;
    }
    var w = path.width == 0 ? 1.0 : path.width;
    var h = path.height == 0 ? 1.0 : path.height;
    var fraction = Offset((doc.dx - path.x) / w, (doc.dy - path.y) / h);
    var node = path.nodes[_nodeIndex];

    // Alt breaks the handle pair, making a corner.
    var next = handle
        ? (HardwareKeyboard.instance.isAltPressed
            ? (_nodeHandleOut
                ? node.copyWith(
                    outDx: fraction.dx - node.x, outDy: fraction.dy - node.y)
                : node.copyWith(
                    inDx: fraction.dx - node.x, inDy: fraction.dy - node.y))
            : node.withMirroredHandle(out: _nodeHandleOut, to: fraction))
        : node.copyWith(x: fraction.dx, y: fraction.dy);

    controller.replaceElement(path.withNode(_nodeIndex, next), transient: true);
  }

  /// _selectedPicture is the one selected element if it is a picture with
  /// something in it.
  ImageElement? _selectedPicture() {
    var selected = controller.selected;
    return selected is ImageElement && selected.hasImage ? selected : null;
  }
}

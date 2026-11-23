part of '../canvas_controller.dart';

// Part of CanvasController: drawings -- editing a vector element's shapes,
// points and text. Its state is _VectorState, at the end of this file.

extension CanvasVectors on CanvasController {
  /// vectorEditing is the id of the Vector element being edited point by
  /// point, or null; vectorShape its shape picked, vectorPicks its points.
  String? get vectorEditing => _vectorEditing;

  int get vectorShape => _vectors.shape;

  Set<VectorPick> get vectorPicks => _vectors.picks;

  /// vectorPick is the one point picked, if exactly one: its handles shown.
  VectorPick? get vectorPick =>
      _vectors.picks.length == 1 ? _vectors.picks.first : null;

  /// vectorSolo holds every layer of the drawing being edited but the one
  /// picked, as a picture's Solo does. For this run of the app only.
  bool get vectorSolo => _vectors.solo;

  set vectorSolo(bool on) {
    if (_vectors.solo == on) return;
    _vectors.solo = on;
    if (on) {
      vectorSoloOf = _soloHook;
    } else if (vectorSoloOf == _soloHook) {
      vectorSoloOf = null;
    }
    notifyListeners();
  }

  int? _soloOf(VectorElement e) =>
      _vectors.solo && e.id == _vectorEditing && _vectors.shape >= 0
          ? groupOf(e, _vectors.shape)
          : null;

  /// vectorTool is what a press on the drawing being edited does: pick and
  /// move points, put them down with the pen, scale them, or tint them.
  VectorTool get vectorTool => _vectors.tool;

  set vectorTool(VectorTool tool) {
    if (_vectors.tool == tool) return;
    // The align tool lines up what the last of the two select tools picked.
    if (tool == VectorTool.select || tool == VectorTool.selectShapes) {
      _vectors.lastSelect = tool;
    }
    if (tool != VectorTool.text) stopVectorTyping();
    _vectors.tool = tool;
    // The pen taken out with one point picked carries on from that point.
    _vectors.penFrom = tool == VectorTool.pen && _vectors.picks.length == 1
        ? _vectors.picks.first
        : null;
    // The corner tool taken out with a rounded corner's point picked takes
    // that corner up, to be reshaped.
    if (tool == VectorTool.corner && _vectors.picks.length <= 2) {
      if (_vectors.picks.firstOrNull case var p?) {
        if (editingVector case var e? when cornerAt(e, p) != null) {
          _vectors.tool = tool;
          adoptCorner(p);
          return;
        }
      }
    }
    // The Boolean tool taken out with a shape picked starts from that one.
    var e = editingVector;
    _vectors.combining = tool == VectorTool.boolean &&
            e != null &&
            _vectors.shape >= 0 &&
            _vectors.shape < (e.shapes?.length ?? 0)
        ? {groupOf(e, _vectors.shape)}
        : const {};
    notifyListeners();
  }

  /// vectorPen is whether the pen is out. See vectorTool.
  bool get vectorPen => _vectors.tool == VectorTool.pen;

  set vectorPen(bool on) =>
      vectorTool = on ? VectorTool.pen : VectorTool.select;

  /// vectorPenFrom is the point the pen's next point joins on from, or null
  /// when the next point starts a new shape.
  VectorPick? get vectorPenFrom => _vectors.penFrom;

  /// vectorPenShape is the shape the pen is drawing, or -1.
  int get vectorPenShape => _vectors.penFrom?.shape ?? -1;

  /// penFrom says where the pen's next point joins on from: the point just
  /// put down, or a point picked to carry on from.
  void penFrom(VectorPick? pick) {
    _vectors.penFrom = pick;
    if (pick != null) _vectors.shape = pick.shape;
    notifyListeners();
  }

  /// finishPenShape ends the pen's run; the pen stays out for another.
  void finishPenShape() {
    if (_vectors.penFrom == null) return;
    _vectors.penFrom = null;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// vectorCornerRound is whether the corner tool rounds a corner or cuts
  /// it, and vectorCornerSize how far back along each side it starts, in
  /// canvas units. Both reshape the corner the tool last made while it is
  /// still picked (see vectorCornerActive).
  bool get vectorCornerRound => _vectors.cornerRound;

  set vectorCornerRound(bool on) {
    if (_vectors.cornerRound == on) return;
    _vectors.cornerRound = on;
    if (!reshapeCorner()) notifyListeners();
  }

  double get vectorCornerSize => _vectors.cornerSize;

  set vectorCornerSize(double v) => sizeCorner(v);

  /// sizeCorner sets the corner size and reshapes the corner being made.
  void sizeCorner(double v, {bool transient = false}) {
    if (_vectors.cornerSize == v) return;
    _vectors.cornerSize = v;
    if (!reshapeCorner(transient: transient)) notifyListeners();
  }

  /// vectorCornerActive is whether the corner the tool last made is still
  /// being made: its size and kind reshape it, and a drag on it goes on
  /// shaping it. Picking anything else finishes it.
  bool get vectorCornerActive {
    var c = _vectors.corner;
    return c != null &&
        identical(editingVector, c.after) &&
        c.picks.length == _vectors.picks.length &&
        c.picks.containsAll(_vectors.picks);
  }

  /// vectorCornerPoint is where the corner being made was, or null.
  Offset? get vectorCornerPoint {
    if (!vectorCornerActive) return null;
    var c = _vectors.corner!;
    return vectorNodeAt(c.before, c.at)?.point;
  }

  /// adoptCorner takes up the rounded corner the point at [pick] ends (one
  /// made before, or a rounded box's) as the corner being made, its size set
  /// to its own. Answers whether the point was one.
  bool adoptCorner(VectorPick pick) {
    var e = editingVector;
    if (e == null) return false;
    var found = cornerAt(e, pick);
    if (found == null) return false;
    var (before, at, reach, picks) = found;
    _vectors.corner = (before: before, at: at, after: e, picks: picks);
    _vectors.picks = picks;
    _vectors.shape = pick.shape;
    _vectors.cornerRound = true;
    _vectors.cornerSize = (reach / VectorSpace(e).unitsPer).roundToDouble();
    notifyListeners();
    return true;
  }

  /// roundCorner rounds -- or cuts -- the corner at [at] as the corner
  /// settings say, picking the two points it makes and keeping it open to
  /// reshaping. Answers whether there was a corner there to round.
  bool roundCorner(VectorPick at, {bool transient = false}) {
    var e = editingVector;
    if (e == null) return false;
    return _shapeCorner(e, at, transient: transient);
  }

  /// reshapeCorner makes the corner being made again, from the drawing as it
  /// was before it, at the size and kind now set. Answers whether there was.
  bool reshapeCorner({bool transient = false}) {
    if (!vectorCornerActive) return false;
    var c = _vectors.corner!;
    return _shapeCorner(c.before, c.at, transient: transient);
  }

  bool _shapeCorner(VectorElement before, VectorPick at,
      {bool transient = false}) {
    var done = withCornered(
        before, at, _vectors.cornerSize * VectorSpace(before).unitsPer,
        round: _vectors.cornerRound);
    if (done == null) return false;
    var (after, picks) = done;
    _vectors.corner = (before: before, at: at, after: after, picks: picks);
    _vectors.picks = picks;
    _vectors.shape = at.shape;
    replaceElement(after, transient: transient);
    return true;
  }

  /// vectorHandleDrag is what dragging a handle may change, and
  /// vectorHandleSnap whether it turns in fifteen-degree steps.
  VectorHandleDrag get vectorHandleDrag => _vectors.handleDrag;

  set vectorHandleDrag(VectorHandleDrag d) {
    if (_vectors.handleDrag == d) return;
    _vectors.handleDrag = d;
    notifyListeners();
  }

  bool get vectorHandleSnap => _vectors.handleSnap;

  set vectorHandleSnap(bool on) {
    if (_vectors.handleSnap == on) return;
    _vectors.handleSnap = on;
    notifyListeners();
  }

  /// copyVectorPoints copies the picked points (see copiedShapes), answering
  /// whether there was anything to copy.
  bool copyVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    // Shapes picked whole: every point of them.
    var picks = _vectors.picks.isEmpty && _picksShapes
        ? itemPicks(e, vectorItems)
        : _vectors.picks;
    if (picks.isEmpty) return false;
    var copied = copiedShapes(e, picks);
    if (copied.isEmpty) return false;
    _vectors.copiedShapes = copied;
    _vectors.pastes = 0;
    return true;
  }

  /// cutVectorPoints copies the points picked and takes them out.
  bool cutVectorPoints() {
    if (!copyVectorPoints()) return false;
    if (_vectors.picks.isEmpty && _picksShapes) {
      if (editingVector case var e?) _vectors.picks = itemPicks(e, vectorItems);
      _vectors.items = const {};
    }
    deleteVectorPoint();
    _vectors.pastes = -1;
    return true;
  }

  /// pasteVectorPoints puts the copied points in the drawing being edited, a
  /// little down and right of where they were, picked. Answers whether any.
  bool pasteVectorPoints() {
    var e = editingVector;
    if (e == null || _vectors.copiedShapes.isEmpty) return false;
    _vectors.pastes++;
    var step = 10 * VectorSpace(e).unitsPer * _vectors.pastes;
    var (next, picks) =
        withPasted(e, _vectors.copiedShapes, Offset(step, step));
    // Picking shapes, what is pasted is picked as shapes -- its box to move
    // it by; picking points, its points.
    if (_picksShapes) {
      _vectors.items = itemsOf(next, picks);
      _vectors.picks = const {};
    } else {
      _vectors.picks = picks;
    }
    _vectors.shape = picks.isEmpty ? -1 : picks.first.shape;
    replaceElement(next);
    return true;
  }

  bool pickAllVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    if (_picksShapes) {
      _vectors.items = allItems(e);
      notifyListeners();
      return true;
    }
    pickVectorPoints(allPicks(e));
    return true;
  }

  /// editPickedPoints applies [edit] to the drawing and its picked points,
  /// as one undo step.
  void editPickedPoints(
      VectorElement Function(VectorElement, Set<VectorPick>) edit) {
    var e = editingVector;
    if (e == null || _vectors.picks.isEmpty) return;
    var next = edit(e, _vectors.picks);
    if (!identical(next, e)) replaceElement(next);
  }

  /// vectorBrush is the pencil's brush as it is now -- one picked, then
  /// changed or not -- and vectorPencilColour the colour it draws in.
  VectorBrush get vectorBrush => _vectors.brush;

  set vectorBrush(VectorBrush b) {
    _vectors.brush = b;
    notifyListeners();
  }

  /// vectorPencilPoints is whether the drawing's points are shown while the
  /// pencil is out. Off to start with: drawing, they are in the way.
  bool get vectorPencilPoints => _vectors.pencilPoints;

  set vectorPencilPoints(bool on) {
    if (_vectors.pencilPoints == on) return;
    _vectors.pencilPoints = on;
    notifyListeners();
  }

  /// vectorLanes is how much of a drawing's shapes the timeline shows under
  /// its own keyframes: none, the shape picked, or all (see VectorShapeLanes).
  VectorLanes get vectorLanes => _vectors.lanes;

  set vectorLanes(VectorLanes l) {
    if (_vectors.lanes == l) return;
    _vectors.lanes = l;
    notifyListeners();
  }

  /// retimeShapes changes when [e]'s shapes come in by [edit]: their timing
  /// written out in the timeline's frames first (see withTimingBaked), then
  /// the drawing's arrival fitted round them, the timeline lengthened where
  /// needed. [transient] while a drag is still making it.
  void retimeShapes(VectorElement e, VectorElement Function(VectorElement) edit,
      {bool transient = false}) {
    var next = withSpanFitted(
        edit(withTimingBaked(e, _document.frameRate)), _document.frameRate);
    var document = _document;
    if (vectorArrivalSpan(next, _document.frameRate) case (var at, var span)
        when at + span > document.frames - 1) {
      document = document.copyWith(frames: at + span + 1);
    }
    apply(document.withElement(next), transient: transient);
  }

  /// retimeLayers changes when a picture's layers come in by [edit], worked
  /// in the timeline's frames, the arrival fitted round them after and the
  /// scene lengthened where needed. See withLayerTimingBaked.
  void retimeLayers(ImageElement e, ImageElement Function(ImageElement) edit,
      {bool transient = false}) {
    var next = withLayerSpanFitted(
        edit(withLayerTimingBaked(e, _document.frameRate)),
        _document.frameRate);
    var document = _document;
    if (imageArrivalSpan(next, _document.frameRate) case (var at, var span)
        when at + span > document.frames - 1) {
      document = document.copyWith(frames: at + span + 1);
    }
    apply(document.withElement(next), transient: transient);
  }

  /// vectorShapeMade is the shape the shapes tool last drew, while it is
  /// still the one picked: the one its box moves and resizes. -1 with none.
  int get vectorShapeMade =>
      _vectors.shapeMade >= 0 && _vectors.shapeMade == _vectors.shape
          ? _vectors.shapeMade
          : -1;

  set vectorShapeMade(int i) => _vectors.shapeMade = i;

  /// vectorShapeKind is the shape the shapes tool draws; vectorShapeSides a
  /// polygon's sides and a star's points; vectorStarInner a star's inner
  /// points as a share of its outer; vectorShapeCorner a rounded box's
  /// corners as a share of its shorter side.
  VectorShapeKind get vectorShapeKind => _vectors.shapeKind;

  set vectorShapeKind(VectorShapeKind k) {
    if (_vectors.shapeKind == k) return;
    _vectors.shapeKind = k;
    notifyListeners();
  }

  int get vectorShapeSides => _vectors.shapeSides;

  set vectorShapeSides(int n) {
    if (_vectors.shapeSides == n) return;
    _vectors.shapeSides = n;
    notifyListeners();
  }

  double get vectorStarInner => _vectors.starInner;

  set vectorStarInner(double v) {
    if (_vectors.starInner == v) return;
    _vectors.starInner = v;
    notifyListeners();
  }

  double get vectorShapeCorner => _vectors.shapeCorner;

  set vectorShapeCorner(double v) {
    if (_vectors.shapeCorner == v) return;
    _vectors.shapeCorner = v;
    notifyListeners();
  }

  /// vectorShapeFill and vectorShapeLine are the colours a new shape is
  /// drawn in, or null for none; vectorShapeWidth its line's width, in
  /// pixels on screen as it is drawn. A line, an arrow or a mark is always
  /// a line, whatever the fill is set to.
  Color? get vectorShapeFill => _vectors.shapeFill;

  set vectorShapeFill(Color? c) {
    if (_vectors.shapeFill == c) return;
    _vectors.shapeFill = c;
    notifyListeners();
  }

  Color? get vectorShapeLine => _vectors.shapeLine;

  set vectorShapeLine(Color? c) {
    if (_vectors.shapeLine == c) return;
    _vectors.shapeLine = c;
    notifyListeners();
  }

  double get vectorShapeWidth => _vectors.shapeWidth;

  set vectorShapeWidth(double v) {
    if (_vectors.shapeWidth == v) return;
    _vectors.shapeWidth = v;
    notifyListeners();
  }

  /// vectorEraseWhole is whether the eraser takes out whole lines and shapes
  /// it touches rather than rubbing out what it goes over; vectorEraseSize
  /// and vectorEraseSoft are its screen size and edge fade; vectorEraseLine
  /// and vectorEraseFill whether it rubs out lines, fills, or both.
  bool get vectorEraseWhole => _vectors.eraseWhole;

  set vectorEraseWhole(bool on) {
    if (_vectors.eraseWhole == on) return;
    _vectors.eraseWhole = on;
    notifyListeners();
  }

  double get vectorEraseSize => _vectors.eraseSize;

  set vectorEraseSize(double v) {
    if (_vectors.eraseSize == v) return;
    _vectors.eraseSize = v;
    notifyListeners();
  }

  double get vectorEraseSoft => _vectors.eraseSoft;

  set vectorEraseSoft(double v) {
    if (_vectors.eraseSoft == v) return;
    _vectors.eraseSoft = v;
    notifyListeners();
  }

  bool get vectorEraseLine => _vectors.eraseLine;

  set vectorEraseLine(bool on) {
    if (_vectors.eraseLine == on) return;
    _vectors.eraseLine = on;
    notifyListeners();
  }

  bool get vectorEraseFill => _vectors.eraseFill;

  set vectorEraseFill(bool on) {
    if (_vectors.eraseFill == on) return;
    _vectors.eraseFill = on;
    notifyListeners();
  }

  /// clearVectorErasures takes every rub-out off the drawing being edited.
  void clearVectorErasures() {
    var e = editingVector;
    if (e == null || !hasErasures(e)) return;
    replaceElement(withoutErasures(e));
  }

  /// vectorMirrorAcross and vectorMirrorDown are the pencil's symmetry: a
  /// stroke mirrored left to right, top to bottom, or both.
  bool get vectorMirrorAcross => _vectors.mirrorAcross;

  set vectorMirrorAcross(bool on) {
    if (_vectors.mirrorAcross == on) return;
    _vectors.mirrorAcross = on;
    notifyListeners();
  }

  bool get vectorMirrorDown => _vectors.mirrorDown;

  set vectorMirrorDown(bool on) {
    if (_vectors.mirrorDown == on) return;
    _vectors.mirrorDown = on;
    notifyListeners();
  }

  /// vectorQuickFill is whether a pencil click fills the area the lines
  /// close round it (the paint bucket) rather than drawing; vectorFillGap is
  /// the widest opening, in screen pixels, still counted as closed.
  bool get vectorQuickFill => _vectors.quickFill;

  set vectorQuickFill(bool on) {
    if (_vectors.quickFill == on) return;
    _vectors.quickFill = on;
    notifyListeners();
  }

  /// vectorTextStyle is the type new text in a drawing is set in -- its
  /// size in the canvas's own pixels -- and vectorTextColour its colour.
  VectorText get vectorTextStyle => _vectors.textStyle;

  Color get vectorTextColour => _vectors.textColour;

  set vectorTextColour(Color c) {
    _vectors.textColour = c;
    var e = editingVector;
    var i = _vectors.typing >= 0 ? _vectors.typing : _vectors.shape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      if (shapes[i].liveText != null) {
        replaceElement(e!.withShape(i, shapes[i].copyWith(fill: c)),
            transient: _vectors.typing >= 0);
      }
    }
    notifyListeners();
  }

  /// vectorTyping is the shape being typed into with the text tool, or -1.
  int get vectorTyping => _vectors.typing;

  /// _typedShape is the drawing, shape index and shape being typed into.
  (VectorElement, int, VectorShape)? _typedShape() {
    var e = editingVector;
    var i = _vectors.typing;
    var shapes = e?.shapes;
    if (e == null || shapes == null || i < 0 || i >= shapes.length) {
      return null;
    }
    return (e, i, shapes[i]);
  }

  /// typedText is the text being typed, or the text of the shape picked
  /// where it is still text: what the text tool's settings show.
  VectorText? get typedText {
    if (_typedShape() case (_, _, var s)?) return s.liveText;
    var e = editingVector;
    var i = _vectors.shape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      return shapes[i].liveText;
    }
    return null;
  }

  /// setVectorTextStyle sets the type new text is set in -- [size] here in
  /// the canvas's pixels -- and the text being typed, or picked, with it.
  void setVectorTextStyle(VectorText style) {
    // The type and nothing else: the words, place and signature belong to
    // the text the settings were showing, and new text started with
    // another's signature could not be typed into.
    _vectors.textStyle = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align);
    var e = editingVector;
    var i = _vectors.typing >= 0 ? _vectors.typing : _vectors.shape;
    var s = e?.shapes != null && i >= 0 && i < e!.shapes!.length
        ? e.shapes![i]
        : null;
    var t = s?.liveText;
    if (e != null && t != null) {
      var px = VectorSpace(e).unitsPer;
      retypeVectorText(
          i,
          t.copyWith(
              family: style.family,
              weight: style.weight,
              italic: style.italic,
              size: style.size * px,
              spacing: style.spacing,
              leading: style.leading,
              align: style.align));
    }
    notifyListeners();
  }

  /// retypeVectorText lays shape [shape] out again as [t] -- once its font
  /// is read, which is at once where it has been already.
  void retypeVectorText(int shape, VectorText t) {
    var pick = FontFiles.instance.cached(t.family, t.weight, t.italic);
    if (pick == null) {
      // Laid out once the font is read, if the drawing it was for is still
      // on the canvas open: shape [shape] of another is not this one.
      var loads = _loads;
      FontFiles.instance.load(t.family, t.weight, t.italic).then((p) {
        if (p != null && _stillOn(loads)) retypeVectorText(shape, t);
      });
      return;
    }
    var e = editingVector;
    var shapes = e?.shapes;
    if (e == null || shapes == null || shape >= shapes.length) return;
    var s = shapes[shape];
    var origin = s.textOrigin ?? s.text?.origin ?? t.origin;
    replaceElement(e.withShape(shape, typed(s, t, origin, pick)),
        transient: true);
  }

  /// newVectorText starts new text in the drawing being edited, its first
  /// line at [at] in the drawing's units, and starts typing into it.
  Future<void> newVectorText(Offset at) async {
    stopVectorTyping();
    var e = editingVector;
    if (e == null) return;
    var style = _vectors.textStyle;
    var t = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size * VectorSpace(e).unitsPer,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align,
        origin: at);
    var loads = _loads;
    await FontFiles.instance.load(t.family, t.weight, t.italic);
    e = editingVector;
    if (e == null || !_stillOn(loads)) return;
    var shapes = e.shapes ?? const <VectorShape>[];
    beginInteraction();
    replaceElement(
        e.copyWith(shapes: [
          ...shapes,
          VectorShape(paths: const [], fill: _vectors.textColour, text: t),
        ]),
        transient: true);
    _vectors.typing = shapes.length;
    _vectors.shape = shapes.length;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// startVectorTyping types into shape [shape], text already.
  void startVectorTyping(int shape) {
    if (_vectors.typing == shape) return;
    stopVectorTyping();
    beginInteraction();
    _vectors.typing = shape;
    _vectors.shape = shape;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// stopVectorTyping finishes the typing as one change; empty text goes.
  void stopVectorTyping() {
    if (_vectors.typing < 0) return;
    if (_typedShape() case (var e, var i, var s)?
        when (s.liveText?.text.trim() ?? "x").isEmpty) {
      var shapes = [...e.shapes!]..removeAt(i);
      replaceElement(e.copyWith(shapes: shapes), transient: true);
      if (_vectors.shape == i) _vectors.shape = -1;
    }
    _vectors.typing = -1;
    endInteraction();
    notifyListeners();
  }

  /// sampling is whether the eyedropper is out: the next press on the canvas
  /// gives the colour under it to [_vectors.onSampled]. sampled is its last colour.
  bool get sampling => _vectors.onSampled != null;

  Color? get sampled => _vectors.sampled;

  void startSampling(ValueChanged<Color> onSampled) {
    _vectors.onSampled = onSampled;
    notifyListeners();
  }

  void stopSampling() {
    if (_vectors.onSampled == null) return;
    _vectors.onSampled = null;
    notifyListeners();
  }

  /// sampledColour hands the eyedropper what it took, and puts it away.
  void sampledColour(Color c) {
    var give = _vectors.onSampled;
    _vectors.onSampled = null;
    _vectors.sampled = c;
    give?.call(c);
    notifyListeners();
  }

  /// vectorKnifeGap is the gap the knife leaves in a cut, in canvas pixels.
  double get vectorKnifeGap => _vectors.knifeGap;

  set vectorKnifeGap(double v) {
    if (_vectors.knifeGap == v) return;
    _vectors.knifeGap = v;
    notifyListeners();
  }

  double get vectorFillGap => _vectors.fillGap;

  set vectorFillGap(double v) {
    if (_vectors.fillGap == v) return;
    _vectors.fillGap = v;
    notifyListeners();
  }

  /// vectorPencilFill is the colour a fill brush fills its strokes with, and
  /// the quick fill fills an area with.
  Color get vectorPencilFill => _vectors.pencilFill;

  set vectorPencilFill(Color c) {
    if (_vectors.pencilFill == c) return;
    _vectors.pencilFill = c;
    notifyListeners();
  }

  Color get vectorPencilColour => _vectors.pencilColour;

  set vectorPencilColour(Color c) {
    if (_vectors.pencilColour == c) return;
    _vectors.pencilColour = c;
    notifyListeners();
  }

  /// stylusButtons is what the pen's three buttons do with the pencil out,
  /// in the order the pen reports them (right, middle and back click, as a
  /// tablet's driver sends them); stylusEraser what its other end does.
  List<StylusAction> get stylusButtons => _vectors.stylusButtons;

  void setStylusButton(int index, StylusAction action) {
    if (index < 0 || index >= _vectors.stylusButtons.length) return;
    _vectors.stylusButtons = [
      for (var (i, a) in _vectors.stylusButtons.indexed)
        i == index ? action : a,
    ];
    notifyListeners();
  }

  StylusAction get stylusEraser => _vectors.stylusEraser;

  set stylusEraser(StylusAction a) {
    if (_vectors.stylusEraser == a) return;
    _vectors.stylusEraser = a;
    notifyListeners();
  }

  /// vectorCombining is the shapes picked with the Boolean tool, to be
  /// combined -- each the first of its run of combined shapes.
  Set<int> get vectorCombining => _vectors.combining;

  /// toggleCombining picks shape [shape] for combining, or unpicks it.
  void toggleCombining(int shape) {
    var next = {..._vectors.combining};
    if (!next.remove(shape)) next.add(shape);
    _vectors.combining = next;
    notifyListeners();
  }

  void clearCombining() {
    if (_vectors.combining.isEmpty) return;
    _vectors.combining = const {};
    notifyListeners();
  }

  /// combineVector combines the picked shapes by [op], the result picked.
  void combineVector(VectorCombine op) {
    var e = editingVector;
    if (e == null || _vectors.combining.length < 2) return;
    var (next, at) = withCombined(e, _vectors.combining, op);
    _vectors.combining = at >= 0 ? {at} : const {};
    _vectors.picks = const {};
    _vectors.shape = -1;
    replaceElement(next);
  }

  /// separateVector undoes the combining of every picked result.
  void separateVector() {
    var e = editingVector;
    if (e == null || _vectors.combining.isEmpty) return;
    var next = e;
    for (var base in _vectors.combining) {
      next = withSeparated(next, base);
    }
    _vectors.combining = const {};
    replaceElement(next);
  }

  /// vectorTint is the tint brush's colour -- or gradient, laid across each
  /// stroke as the colour picker sets it.
  PaintSpec get vectorTint => _vectors.tint;

  set vectorTint(PaintSpec p) {
    if (_vectors.tint == p) return;
    _vectors.tint = p;
    notifyListeners();
  }

  /// vectorBrushSize is the tint brush's width on screen, in pixels: the
  /// same brush however far in the canvas is zoomed. vectorBrushSoft is how
  /// far its edge fades, 0 to 1.
  double get vectorBrushSize => _vectors.brushSize;

  set vectorBrushSize(double v) {
    if (_vectors.brushSize == v) return;
    _vectors.brushSize = v;
    notifyListeners();
  }

  double get vectorBrushSoft => _vectors.brushSoft;

  set vectorBrushSoft(double v) {
    if (_vectors.brushSoft == v) return;
    _vectors.brushSoft = v;
    notifyListeners();
  }

  /// vectorTintLine and vectorTintFill are where the brush's tint shows: on
  /// the drawing's lines, in its fills. Both is both.
  bool get vectorTintLine => _vectors.tintLine;

  set vectorTintLine(bool on) {
    if (_vectors.tintLine == on) return;
    _vectors.tintLine = on;
    notifyListeners();
  }

  bool get vectorTintFill => _vectors.tintFill;

  set vectorTintFill(bool on) {
    if (_vectors.tintFill == on) return;
    _vectors.tintFill = on;
    notifyListeners();
  }

  void clearVectorTints() {
    var e = editingVector;
    if (e == null || !hasTints(e)) return;
    replaceElement(withoutTints(e));
  }

  /// spritePaint is the Sprite element being painted frame by frame on the
  /// canvas (see sprite_painting.dart); paintSprite starts or (null) stops.
  SpritePaintSession? get spritePaint => _spritePaint;

  void paintSprite(String? id) {
    if (_spritePaint?.id == id) return;
    _spritePaint?.removeListener(notifyListeners);
    _spritePaint?.dispose();
    _spritePaint = id == null
        ? null
        : (SpritePaintSession(this, id)..addListener(notifyListeners));
    spritePaintingOf = _spritePaint == null
        ? null
        : (e) => e.id == _spritePaint?.id ? _spritePaint!.view(e) : null;
    notifyListeners();
  }

  /// tilePaint is the Tile map being painted on the canvas (see
  /// tile_painting.dart); paintTiles starts or (null) stops.
  TilePaintSession? get tilePaint => _tilePaint;

  void paintTiles(String? id) {
    if (_tilePaint?.id == id) return;
    _tilePaint?.removeListener(notifyListeners);
    _tilePaint?.dispose();
    _tilePaint = id == null
        ? null
        : (TilePaintSession(this, id)..addListener(notifyListeners));
    tileMapEditingOf = _tilePaint == null
        ? null
        : (e) => e.id == _tilePaint?.id ? _tilePaint!.view(e) : null;
    notifyListeners();
  }

  /// studio3dDesign is the character the Studio opens with:
  /// [studio3dElement]'s, or null for a new one.
  CharacterDesign? get studio3dDesign {
    var id = studio3dElement;
    var e = id == null ? null : _elementAnywhere(id);
    return e is Character3dElement ? e.design : null;
  }

  /// openStudio3d gives the page to the Character Studio: to change
  /// [element], a 3D character on the canvas, or to make a new character.
  void openStudio3d({String? element}) {
    pause();
    studio3dElement = element;
    studio3dOpen.value = true;
  }

  /// studio3dPerformance is what [studio3dElement] does in its scene, for
  /// the Studio's Test step to try; null where it was opened for none.
  CharacterPerformance? get studio3dPerformance {
    var id = studio3dElement;
    var e = id == null ? null : _elementAnywhere(id);
    return e is Character3dElement ? e.performance : null;
  }

  /// closeStudio3d gives the page back to the canvas. With [kept], every
  /// copy of the character on the canvas, and the element it was opened
  /// for, is made as the Studio kept it; with [performance], that element
  /// does it in its scene as the Test step left it. One step to undo.
  void closeStudio3d(
      [CharacterDesign? kept, CharacterPerformance? performance]) {
    var opened = studio3dElement;
    studio3dElement = null;
    studio3dOpen.value = false;
    if (kept == null && performance == null) return;
    var before = _document;
    // Each copy of the character made as it now is where it is: in its own
    // scene or on the master. An element's id is only its scene's own (a
    // game may have a "vivi" in every scene), so a copy is never written
    // back by id alone. Only the one the Studio was opened for, on the
    // canvas being edited, takes [performance].
    var changed = false;
    List<CanvasElement> remade(List<CanvasElement> list, {required bool here}) {
      var out = <CanvasElement>[];
      for (var e in list) {
        if (e is! Character3dElement) {
          out.add(e);
          continue;
        }
        var mine = here && e.id == opened;
        if (!mine &&
            (kept == null || e.design.id.isEmpty || e.design.id != kept.id)) {
          out.add(e);
          continue;
        }
        var made = kept == null ? e : e.copyWith(design: kept);
        if (mine && performance != null) made = made.performing(performance);
        // Named for the character, unless it was named for itself.
        CanvasElement next = made;
        if (kept != null &&
            (e.base.name.isEmpty || e.base.name == e.design.name)) {
          next = made.rebase(made.base.copyWith(name: kept.name));
        }
        changed = true;
        out.add(next);
      }
      return out;
    }

    var doc = before.copyWith(elements: remade(before.elements, here: true));
    for (var (i, scene) in before.allScenes.indexed) {
      if (!before.editingMaster && i == before.at) continue;
      doc = doc.withScene(
          i, scene.copyWith(elements: remade(scene.elements, here: false)));
    }
    if (before.master case var m? when !before.editingMaster) {
      doc = doc.copyWith(
          master: m.copyWith(elements: remade(m.elements, here: false)));
    }
    if (!changed) return;
    // The Cast's members with them: a copy made as the character now is
    // takes its member along, and the member every other copy.
    doc = castSynced(before, doc);
    _undo.add(before);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
    _document = doc;
    _edits++;
    scheduleAutosave();
    notifyListeners();
  }

  /// _elementAnywhere is element [id] in this scene, the master, or another.
  CanvasElement? _elementAnywhere(String id) {
    var doc = _document;
    for (var e in [
      ...doc.elements,
      ...?doc.master?.elements,
      for (var sc in doc.allScenes) ...sc.elements,
    ]) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// placeCharacter3d puts library character [design] in the scene, at
  /// [center] or in the middle, picked: one step to undo.
  void placeCharacter3d(CharacterDesign design, {Offset? center}) {
    var made = newElement(ElementKind.character3d, _document, center: center)
        as Character3dElement;
    addElement(made
        .copyWith(design: design)
        .rebase(made.base.copyWith(name: design.name)));
  }

  /// editingVector is the drawing being edited, where there is one and it has
  /// been taken apart -- which editing it always has. See startVectorEditing.
  VectorElement? get editingVector {
    var id = _vectorEditing;
    var e = id == null ? null : _document.elementById(id);
    return e is VectorElement && e.edited ? e : null;
  }

  /// editVector starts editing the drawing [id], or stops with null.
  void editVector(String? id) {
    if (_vectorEditing == id) return;
    stopVectorTyping();
    _fitEditedVector();
    _vectorEditing = id;
    _resetVectorEditing();
    // Edited is selected: the drawing being edited is the one thing picked,
    // so the settings beside it are its own. See notifyListeners.
    if (id != null) {
      _selection = {id};
      _backgroundSelected = false;
    }
    notifyListeners();
  }

  void _resetVectorEditing() {
    // Typing ends with the editing: left open, it would swallow every later
    // change into one undo step.
    if (_vectors.typing >= 0) {
      _vectors.typing = -1;
      endInteraction();
    }
    if (_vectors.solo) {
      _vectors.solo = false;
      if (vectorSoloOf == _soloHook) vectorSoloOf = null;
    }
    _vectors.items = const {};
    _vectors.lastSelect = VectorTool.select;
    _vectors.shape = -1;
    _vectors.picks = const {};
    _vectors.tool = VectorTool.select;
    _vectors.penFrom = null;
    _vectors.combining = const {};
    _vectors.shapeMade = -1;
  }

  /// vectorItems is what the select shapes tool has picked: whole shapes,
  /// and pieces of cut ones. See VectorItem.
  Set<VectorItem> get vectorItems {
    var e = editingVector;
    if (e == null) return const {};
    return liveItems(e, _vectors.items);
  }

  /// pickVectorItem picks [item] alone -- or, with [toggle], adds it to
  /// what is picked or takes it out; null lets everything go.
  void pickVectorItem(VectorItem? item, {bool toggle = false}) {
    if (item == null) {
      _vectors.items = const {};
    } else if (toggle) {
      var next = {...vectorItems};
      if (!next.remove(item)) next.add(item);
      _vectors.items = next;
    } else {
      _vectors.items = {item};
    }
    // The shape's own settings follow the last one picked.
    _vectors.shape = item?.shape ?? -1;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// vectorAlignsShapes is whether the align tool lines up shapes -- the
  /// select shapes tool was the last select tool used -- or points.
  bool get vectorAlignsShapes => _vectors.lastSelect == VectorTool.selectShapes;

  /// _picksShapes is whether what is picked is shapes rather than points:
  /// the select shapes tool, or the align tool after it.
  bool get _picksShapes =>
      _vectors.tool == VectorTool.selectShapes ||
      (_vectors.tool == VectorTool.align && vectorAlignsShapes);

  /// pickVectorItems picks [items] -- or, with [add], adds them.
  void pickVectorItems(Set<VectorItem> items, {bool add = false}) {
    _vectors.items = add ? {...vectorItems, ...items} : {...items};
    _vectors.shape = items.isEmpty ? _vectors.shape : items.first.shape;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// alignVectorItems lines the shapes picked up as [how] says.
  void alignVectorItems(VectorAlign how) {
    var e = editingVector;
    var items = vectorItems.toList();
    if (e == null || items.length < 2) return;
    replaceElement(withItemsAligned(e, items, how));
  }

  /// vectorSelectedShapes is the shapes picked -- each the first of its
  /// run of combined shapes -- whichever select tool picked them: what the
  /// tint, the rub-out and the pencil work on, where any are. Empty for
  /// none, when they work on whatever they go over.
  Set<int> get vectorSelectedShapes {
    var e = editingVector;
    if (e == null) return const {};
    var items = vectorItems;
    if (items.isNotEmpty) return {for (var i in items) groupOf(e, i.shape)};
    if (_vectors.shape >= 0 && _vectors.shape < (e.shapes?.length ?? 0)) {
      return {groupOf(e, _vectors.shape)};
    }
    return const {};
  }

  void pickVectorShape(int shape) {
    if (_vectors.shape == shape && _vectors.picks.isEmpty) return;
    _vectors.shape = shape;
    _vectors.picks = const {};
    notifyListeners();
  }

  /// pickVectorPoint picks [pick] alone -- or, with [toggle], adds it to the
  /// points picked or takes it out, which is Shift and a click.
  void pickVectorPoint(VectorPick? pick, {bool toggle = false}) {
    Set<VectorPick> next;
    if (pick == null) {
      next = const {};
    } else if (toggle) {
      next = {..._vectors.picks};
      if (!next.remove(pick)) next.add(pick);
    } else {
      next = {pick};
    }
    if (setEquals(next, _vectors.picks)) return;
    _vectors.picks = next;
    if (pick != null) _vectors.shape = pick.shape;
    notifyListeners();
  }

  /// pickVectorPoints picks [picks] at once: a box dragged across them.
  void pickVectorPoints(Set<VectorPick> picks) {
    _vectors.picks = {...picks};
    if (picks.isNotEmpty) _vectors.shape = picks.first.shape;
    notifyListeners();
  }

  /// deleteVectorPoint takes out the picked points, answering whether any.
  bool deleteVectorPoint() {
    var e = editingVector, picks = _vectors.picks;
    if (e == null) return false;
    // A shape picked whole, with no points: every point of it.
    if (picks.isEmpty && _vectors.shape >= 0) {
      var shape = e.shapes?.elementAtOrNull(_vectors.shape);
      if (shape != null) {
        picks = {
          for (var (p, run) in shape.paths.indexed)
            for (var n = 0; n < run.nodes.length; n++)
              VectorPick(_vectors.shape, p, n),
        };
      }
    }
    if (picks.isEmpty) return false;
    var next = withoutPoints(e, picks);
    _vectors.picks = const {};
    _vectors.penFrom = null;
    if ((next.shapes?.length ?? 0) < (e.shapes?.length ?? 0)) {
      _vectors.shape = -1;
    }
    replaceElement(next);
    return true;
  }

  /// _leaveVectorIfUnpicked stops editing a drawing that is no longer the one
  /// selected: picking something else is how editing is finished.
  void _leaveVectorIfUnpicked() {
    var id = _vectorEditing;
    if (id == null) return;
    if (_selection.length == 1 && _selection.first == id) return;
    _fitEditedVector();
    _vectorEditing = null;
    _resetVectorEditing();
  }

  /// _fitEditedVector grows the box of the drawing being left to take in
  /// whatever the editing carried past it. See boxedToDrawing.
  void _fitEditedVector() {
    var e = editingVector;
    if (e == null) return;
    var fitted = boxedToDrawing(e);
    if (identical(fitted, e)) return;
    apply(_document.withElement(fitted));
  }

  /// isOnlySelected is whether [id] is the one element selected.
  bool isOnlySelected(String id) =>
      _selection.length == 1 && _selection.first == id;

  /// selectAlone selects [id] alone unless it already is the one element
  /// selected, when it leaves the selection as it is: a press on a control
  /// of the element picked keeps what else selectOnly would clear.
  void selectAlone(String id) {
    if (!isOnlySelected(id)) selectOnly(id);
  }

  void selectOnly(String id) {
    if (_selection.length == 1 &&
        _selection.first == id &&
        !_backgroundSelected &&
        _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {id};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  /// selectMany picks out a set at once, for the things that work on several
  /// -- the alignment tools, and a sweep over empty space.
  void selectMany(Set<String> ids) {
    _backgroundSelected = false;
    _offCanvas = const {};
    _selection = {...ids};
    _leaveVectorIfUnpicked();
    _focusedPlayer = null;
    notifyListeners();
  }

  void toggleSelected(String id) {
    _backgroundSelected = false;
    _selection = {..._selection};
    _selection.contains(id) ? _selection.remove(id) : _selection.add(id);
    notifyListeners();
  }

  /// clipSelection is every clip picked on the timeline: the selection, and
  /// the clips picked on another canvas (another scene's, or the master's
  /// seen from a scene). Those are not in the selection, which is only ever
  /// the canvas in front of the reader, but are lit and moved with the rest.
  Set<String> get clipSelection =>
      _offCanvas.isEmpty ? _selection : {..._selection, ..._offCanvas};

  bool _onCanvas(String id) => _document.indexOf(id) >= 0;

  /// pickClip picks the clip [id] on the timeline, wherever it is -- or,
  /// with [toggle], adds it to what is picked or takes it out.
  void pickClip(String id, {bool toggle = false}) {
    if (_onCanvas(id)) {
      toggle ? toggleSelected(id) : selectOnly(id);
      return;
    }
    if (toggle) {
      var next = {..._offCanvas};
      if (!next.remove(id)) next.add(id);
      _offCanvas = next;
    } else {
      _backgroundSelected = false;
      _focusedPlayer = null;
      _selection = {};
      _offCanvas = {id};
    }
    notifyListeners();
  }

  /// pickedClip is the one clip picked on the timeline from another canvas
  /// -- the master's music, seen from a scene -- when it is the only thing
  /// picked, so its settings can be shown and changed from here.
  CanvasElement? get pickedClip {
    if (_selection.isNotEmpty || _offCanvas.length != 1) return null;
    var id = _offCanvas.single;
    CanvasElement? found;
    _everyElement(_document, (e, _) {
      if (e.id == id) found = e;
      return e;
    });
    return found;
  }

  /// replaceAnywhere changes element [next] wherever it is: here, on the
  /// master or in another scene.
  void replaceAnywhere(CanvasElement next, {bool transient = false}) {
    var doc = _replacedAnywhere(_document, next);
    if (doc == null) return;
    apply(doc, transient: transient);
  }

  /// pickClips picks [ids] on the timeline, wherever each is: a lanes box.
  void pickClips(Set<String> ids) {
    _backgroundSelected = false;
    _focusedPlayer = null;
    _selection = {
      for (var id in ids)
        if (_onCanvas(id)) id
    };
    _offCanvas = {
      for (var id in ids)
        if (!_onCanvas(id)) id
    };
    notifyListeners();
  }
}

/// _VectorState is what CanvasVectors keeps between calls: the tool in hand
/// and each tool's settings, what is picked, what was copied. The
/// controller holds one, as _vectors. Most fields are read and set through
/// CanvasVectors' getters and setters above, which say what each is.
class _VectorState {
  int shape = -1;

  Set<VectorPick> picks = const {};

  bool solo = false;

  VectorTool tool = VectorTool.select;

  VectorPick? penFrom;

  bool cornerRound = true;

  double cornerSize = 20;

  /// corner is the corner the corner tool last made: the drawing before,
  /// the point, the drawing after and its two new points. Still in the
  /// making while those points alone are picked and the drawing unchanged.
  ({
    VectorElement before,
    VectorPick at,
    VectorElement after,
    Set<VectorPick> picks
  })? corner;

  VectorHandleDrag handleDrag = VectorHandleDrag.any;

  bool handleSnap = false;

  /// copiedShapes is the last points copied, and pastes how many times
  /// they have been pasted since: each paste lands a step further off.
  List<VectorShape> copiedShapes = const [];
  int pastes = 0;

  VectorBrush brush = builtInBrushes.first;

  bool pencilPoints = false;

  VectorLanes lanes = VectorLanes.none;

  int shapeMade = -1;

  VectorShapeKind shapeKind = VectorShapeKind.box;

  int shapeSides = 5;

  double starInner = 0.45;

  double shapeCorner = 0.2;

  Color? shapeFill = const Color(0xFF8AB4F8);

  Color? shapeLine = const Color(0xFF202124);

  double shapeWidth = 3;

  bool eraseWhole = false;

  double eraseSize = 20;

  double eraseSoft = 0;

  bool eraseLine = true;

  bool eraseFill = true;

  bool mirrorAcross = false;

  bool mirrorDown = false;

  bool quickFill = false;

  VectorText textStyle = const VectorText();

  Color textColour = const Color(0xFF000000);

  int typing = -1;

  ValueChanged<Color>? onSampled;

  Color? sampled;

  double knifeGap = 1;

  double fillGap = 3;

  Color pencilFill = const Color(0xFF8AB4F8);

  Color pencilColour = const Color(0xFF202124);

  List<StylusAction> stylusButtons = const [
    StylusAction.pickColour,
    StylusAction.pan,
    StylusAction.undo,
  ];

  StylusAction stylusEraser = StylusAction.erase;

  Set<int> combining = const {};

  PaintSpec tint = const PaintSpec(Color(0xFFE5484D));

  double brushSize = 24;

  double brushSoft = 0.5;

  bool tintLine = true;

  bool tintFill = true;

  Set<VectorItem> items = const {};

  VectorTool lastSelect = VectorTool.select;
}

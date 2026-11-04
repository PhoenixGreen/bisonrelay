part of '../canvas_controller.dart';

// Drawings: editing a vector element's shapes, points and text.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasVectors on CanvasController {
  /// vectorEditing is the Vector element being edited point by point, by id,
  /// or null. vectorShape is the shape of it picked, and vectorPicks the
  /// points -- one, several, or none.
  String? get vectorEditing => _vectorEditing;

  int get vectorShape => _vectorShape;

  Set<VectorPick> get vectorPicks => _vectorPicks;

  /// vectorPick is the one point picked, where exactly one is: the point
  /// whose handles are shown and can be pulled.
  VectorPick? get vectorPick =>
      _vectorPicks.length == 1 ? _vectorPicks.first : null;

  /// vectorSolo holds every layer of the drawing being edited but the one
  /// picked, as a picture's Solo does: only it can be picked or edited on
  /// the canvas. For this run of the app; off when the drawing is put down.
  bool get vectorSolo => _vectorSolo;

  set vectorSolo(bool on) {
    if (_vectorSolo == on) return;
    _vectorSolo = on;
    if (on) {
      vectorSoloOf = _soloOf;
    } else if (vectorSoloOf == _soloOf) {
      vectorSoloOf = null;
    }
    notifyListeners();
  }

  int? _soloOf(VectorElement e) =>
      _vectorSolo && e.id == _vectorEditing && _vectorShape >= 0
          ? groupOf(e, _vectorShape)
          : null;

  /// vectorTool is what a press on the drawing being edited does: pick and
  /// move points, put them down with the pen, scale them, or tint them.
  VectorTool get vectorTool => _vectorTool;

  set vectorTool(VectorTool tool) {
    if (_vectorTool == tool) return;
    // The align tool lines up what the last of the two select tools picked.
    if (tool == VectorTool.select || tool == VectorTool.selectShapes) {
      _lastSelect = tool;
    }
    if (tool != VectorTool.text) stopVectorTyping();
    _vectorTool = tool;
    // The pen taken out with one point picked carries on from that point.
    _vectorPenFrom = tool == VectorTool.pen && _vectorPicks.length == 1
        ? _vectorPicks.first
        : null;
    // The corner tool taken out with a rounded corner's point picked takes
    // that corner up, to be reshaped.
    if (tool == VectorTool.corner && _vectorPicks.length <= 2) {
      if (_vectorPicks.firstOrNull case var p?) {
        if (editingVector case var e? when cornerAt(e, p) != null) {
          _vectorTool = tool;
          adoptCorner(p);
          return;
        }
      }
    }
    // The Boolean tool taken out with a shape picked starts from that one.
    var e = editingVector;
    _vectorCombining = tool == VectorTool.boolean &&
            e != null &&
            _vectorShape >= 0 &&
            _vectorShape < (e.shapes?.length ?? 0)
        ? {groupOf(e, _vectorShape)}
        : const {};
    notifyListeners();
  }

  /// vectorPen is whether the pen is out. See vectorTool.
  bool get vectorPen => _vectorTool == VectorTool.pen;

  set vectorPen(bool on) =>
      vectorTool = on ? VectorTool.pen : VectorTool.select;

  /// vectorPenFrom is the point the pen's next point joins on from, or null
  /// before it has one -- when the next point starts a new shape.
  VectorPick? get vectorPenFrom => _vectorPenFrom;

  /// vectorPenShape is the shape the pen is drawing, or -1.
  int get vectorPenShape => _vectorPenFrom?.shape ?? -1;

  /// penFrom says where the pen's next point joins on from: the point just
  /// put down, or a point picked to carry on from.
  void penFrom(VectorPick? pick) {
    _vectorPenFrom = pick;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// finishPenShape ends the run the pen is drawing; the pen stays out,
  /// ready to start another.
  void finishPenShape() {
    if (_vectorPenFrom == null) return;
    _vectorPenFrom = null;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// vectorCornerRound is whether the corner tool rounds a corner or cuts
  /// it, and vectorCornerSize how far back along each side it starts, in
  /// canvas units.
  ///
  /// Both reshape the corner the tool last made while it is still picked --
  /// see vectorCornerActive.
  bool get vectorCornerRound => _vectorCornerRound;

  set vectorCornerRound(bool on) {
    if (_vectorCornerRound == on) return;
    _vectorCornerRound = on;
    if (!reshapeCorner()) notifyListeners();
  }

  double get vectorCornerSize => _vectorCornerSize;

  set vectorCornerSize(double v) => sizeCorner(v);

  /// sizeCorner sets the corner size and reshapes the corner being made by
  /// it -- [transient] while a drag is still setting it.
  void sizeCorner(double v, {bool transient = false}) {
    if (_vectorCornerSize == v) return;
    _vectorCornerSize = v;
    if (!reshapeCorner(transient: transient)) notifyListeners();
  }

  /// vectorCornerActive is whether the corner the tool last made is still
  /// being made: its size and kind reshape it, and a drag on it goes on
  /// shaping it. Picking anything else finishes it.
  bool get vectorCornerActive {
    var c = _corner;
    return c != null &&
        identical(editingVector, c.after) &&
        c.picks.length == _vectorPicks.length &&
        c.picks.containsAll(_vectorPicks);
  }

  /// vectorCornerPoint is where the corner being made was, in the drawing's
  /// units, or null with none.
  Offset? get vectorCornerPoint {
    if (!vectorCornerActive) return null;
    var c = _corner!;
    return vectorNodeAt(c.before, c.at)?.point;
  }

  /// adoptCorner takes up the rounded corner the point at [pick] is one end
  /// of -- one made before, or a rounded box's -- as the corner being made,
  /// so its size and a drag reshape it: the size set to its own. Answers
  /// whether the point was one.
  bool adoptCorner(VectorPick pick) {
    var e = editingVector;
    if (e == null) return false;
    var found = cornerAt(e, pick);
    if (found == null) return false;
    var (before, at, reach, picks) = found;
    _corner = (before: before, at: at, after: e, picks: picks);
    _vectorPicks = picks;
    _vectorShape = pick.shape;
    _vectorCornerRound = true;
    _vectorCornerSize = (reach / VectorSpace(e).unitsPer).roundToDouble();
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

  /// reshapeCorner makes the corner being made again from the drawing as it
  /// was before it, at the size and kind now set. Answers whether there was
  /// one being made.
  bool reshapeCorner({bool transient = false}) {
    if (!vectorCornerActive) return false;
    var c = _corner!;
    return _shapeCorner(c.before, c.at, transient: transient);
  }

  bool _shapeCorner(VectorElement before, VectorPick at,
      {bool transient = false}) {
    var done = withCornered(
        before, at, _vectorCornerSize * VectorSpace(before).unitsPer,
        round: _vectorCornerRound);
    if (done == null) return false;
    var (after, picks) = done;
    _corner = (before: before, at: at, after: after, picks: picks);
    _vectorPicks = picks;
    _vectorShape = at.shape;
    replaceElement(after, transient: transient);
    return true;
  }

  /// vectorHandleDrag is what dragging a handle may change, and
  /// vectorHandleSnap whether it turns in fifteen-degree steps.
  VectorHandleDrag get vectorHandleDrag => _vectorHandleDrag;

  set vectorHandleDrag(VectorHandleDrag d) {
    if (_vectorHandleDrag == d) return;
    _vectorHandleDrag = d;
    notifyListeners();
  }

  bool get vectorHandleSnap => _vectorHandleSnap;

  set vectorHandleSnap(bool on) {
    if (_vectorHandleSnap == on) return;
    _vectorHandleSnap = on;
    notifyListeners();
  }

  /// copyVectorPoints copies the points picked -- see copiedShapes --
  /// answering whether there was anything to copy.
  bool copyVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    // Shapes picked whole: every point of them.
    var picks = _vectorPicks.isEmpty && _picksShapes
        ? itemPicks(e, vectorItems)
        : _vectorPicks;
    if (picks.isEmpty) return false;
    var copied = copiedShapes(e, picks);
    if (copied.isEmpty) return false;
    _copiedShapes = copied;
    _pastes = 0;
    return true;
  }

  /// cutVectorPoints copies the points picked and takes them out.
  bool cutVectorPoints() {
    if (!copyVectorPoints()) return false;
    if (_vectorPicks.isEmpty && _picksShapes) {
      if (editingVector case var e?) _vectorPicks = itemPicks(e, vectorItems);
      _vectorItems = const {};
    }
    deleteVectorPoint();
    _pastes = -1;
    return true;
  }

  /// pasteVectorPoints puts the points copied into the drawing being
  /// edited, a little down and to the right of where they were, and picks
  /// them -- answering whether there was anything to paste.
  bool pasteVectorPoints() {
    var e = editingVector;
    if (e == null || _copiedShapes.isEmpty) return false;
    _pastes++;
    var step = 10 * VectorSpace(e).unitsPer * _pastes;
    var (next, picks) = withPasted(e, _copiedShapes, Offset(step, step));
    // Picking shapes, what is pasted is picked as shapes -- its box to move
    // it by; picking points, its points.
    if (_picksShapes) {
      _vectorItems = itemsOf(next, picks);
      _vectorPicks = const {};
    } else {
      _vectorPicks = picks;
    }
    _vectorShape = picks.isEmpty ? -1 : picks.first.shape;
    replaceElement(next);
    return true;
  }

  /// pickAllVectorPoints picks every point of the drawing being edited.
  bool pickAllVectorPoints() {
    var e = editingVector;
    if (e == null) return false;
    if (_picksShapes) {
      _vectorItems = allItems(e);
      notifyListeners();
      return true;
    }
    pickVectorPoints(allPicks(e));
    return true;
  }

  /// editPickedPoints replaces the drawing being edited with what [edit]
  /// makes of it and the points picked, as one undo step.
  void editPickedPoints(
      VectorElement Function(VectorElement, Set<VectorPick>) edit) {
    var e = editingVector;
    if (e == null || _vectorPicks.isEmpty) return;
    var next = edit(e, _vectorPicks);
    if (!identical(next, e)) replaceElement(next);
  }

  /// vectorBrush is the pencil's brush as it is now -- one picked, then
  /// changed or not -- and vectorPencilColour the colour it draws in.
  VectorBrush get vectorBrush => _vectorBrush;

  set vectorBrush(VectorBrush b) {
    _vectorBrush = b;
    notifyListeners();
  }

  /// vectorPencilPoints is whether the drawing's points are shown while the
  /// pencil is out. Off to start with: drawing, they are in the way.
  bool get vectorPencilPoints => _vectorPencilPoints;

  set vectorPencilPoints(bool on) {
    if (_vectorPencilPoints == on) return;
    _vectorPencilPoints = on;
    notifyListeners();
  }

  /// vectorLanes is how much of a drawing's shapes the timeline shows
  /// under the drawing's own keyframes: none of them, the shape picked, or
  /// every one. See VectorShapeLanes.
  VectorLanes get vectorLanes => _vectorLanes;

  set vectorLanes(VectorLanes l) {
    if (_vectorLanes == l) return;
    _vectorLanes = l;
    notifyListeners();
  }

  /// retimeShapes changes when [e]'s shapes come in by [edit]. Their timing
  /// is first written out in the timeline's frames as it plays now (see
  /// withTimingBaked), then the drawing's arrival is fitted round all of them
  /// again, lengthening the timeline where needed. [transient] while a drag
  /// is still making it.
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

  /// retimeLayers changes when a picture's layers come in, as [edit] says
  /// -- worked in the timeline's frames, with the arrival fitted round them
  /// all again after, and the scene lengthened where it has to be. See
  /// withLayerTimingBaked.
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
      _vectorShapeMade >= 0 && _vectorShapeMade == _vectorShape
          ? _vectorShapeMade
          : -1;

  set vectorShapeMade(int i) => _vectorShapeMade = i;

  /// vectorShapeKind is the shape the shapes tool draws; vectorShapeSides a
  /// polygon's sides and a star's points; vectorStarInner how far in a
  /// star's inner points sit, as a share of its outer ones; and
  /// vectorShapeCorner a rounded box's corners, as a share of its shorter
  /// side.
  VectorShapeKind get vectorShapeKind => _vectorShapeKind;

  set vectorShapeKind(VectorShapeKind k) {
    if (_vectorShapeKind == k) return;
    _vectorShapeKind = k;
    notifyListeners();
  }

  int get vectorShapeSides => _vectorShapeSides;

  set vectorShapeSides(int n) {
    if (_vectorShapeSides == n) return;
    _vectorShapeSides = n;
    notifyListeners();
  }

  double get vectorStarInner => _vectorStarInner;

  set vectorStarInner(double v) {
    if (_vectorStarInner == v) return;
    _vectorStarInner = v;
    notifyListeners();
  }

  double get vectorShapeCorner => _vectorShapeCorner;

  set vectorShapeCorner(double v) {
    if (_vectorShapeCorner == v) return;
    _vectorShapeCorner = v;
    notifyListeners();
  }

  /// vectorShapeFill and vectorShapeLine are the colours a new shape is
  /// drawn in, or null for none; vectorShapeWidth its line's width, in
  /// pixels on screen as it is drawn. A line, an arrow or a mark is always
  /// a line, whatever the fill is set to.
  Color? get vectorShapeFill => _vectorShapeFill;

  set vectorShapeFill(Color? c) {
    if (_vectorShapeFill == c) return;
    _vectorShapeFill = c;
    notifyListeners();
  }

  Color? get vectorShapeLine => _vectorShapeLine;

  set vectorShapeLine(Color? c) {
    if (_vectorShapeLine == c) return;
    _vectorShapeLine = c;
    notifyListeners();
  }

  double get vectorShapeWidth => _vectorShapeWidth;

  set vectorShapeWidth(double v) {
    if (_vectorShapeWidth == v) return;
    _vectorShapeWidth = v;
    notifyListeners();
  }

  /// vectorEraseWhole is whether the eraser takes out whole lines and
  /// shapes, where it touches them, rather than rubbing out what it goes
  /// over; vectorEraseSize and vectorEraseSoft are its size on screen and
  /// how far its edge fades; vectorEraseLine and vectorEraseFill whether it
  /// rubs out lines, fills, or both.
  bool get vectorEraseWhole => _vectorEraseWhole;

  set vectorEraseWhole(bool on) {
    if (_vectorEraseWhole == on) return;
    _vectorEraseWhole = on;
    notifyListeners();
  }

  double get vectorEraseSize => _vectorEraseSize;

  set vectorEraseSize(double v) {
    if (_vectorEraseSize == v) return;
    _vectorEraseSize = v;
    notifyListeners();
  }

  double get vectorEraseSoft => _vectorEraseSoft;

  set vectorEraseSoft(double v) {
    if (_vectorEraseSoft == v) return;
    _vectorEraseSoft = v;
    notifyListeners();
  }

  bool get vectorEraseLine => _vectorEraseLine;

  set vectorEraseLine(bool on) {
    if (_vectorEraseLine == on) return;
    _vectorEraseLine = on;
    notifyListeners();
  }

  bool get vectorEraseFill => _vectorEraseFill;

  set vectorEraseFill(bool on) {
    if (_vectorEraseFill == on) return;
    _vectorEraseFill = on;
    notifyListeners();
  }

  /// clearVectorErasures takes every rub-out off the drawing being edited.
  void clearVectorErasures() {
    var e = editingVector;
    if (e == null || !hasErasures(e)) return;
    replaceElement(withoutErasures(e));
  }

  /// vectorMirrorAcross and vectorMirrorDown are the pencil's symmetry: a
  /// stroke drawn is mirrored across the drawing's upright middle line, its
  /// level middle line, or both -- left and right, top and bottom, all four.
  bool get vectorMirrorAcross => _vectorMirrorAcross;

  set vectorMirrorAcross(bool on) {
    if (_vectorMirrorAcross == on) return;
    _vectorMirrorAcross = on;
    notifyListeners();
  }

  bool get vectorMirrorDown => _vectorMirrorDown;

  set vectorMirrorDown(bool on) {
    if (_vectorMirrorDown == on) return;
    _vectorMirrorDown = on;
    notifyListeners();
  }

  /// vectorQuickFill is whether a click with the pencil fills the area the
  /// lines close round it, rather than drawing -- the paint bucket -- and
  /// vectorFillGap the widest opening, in pixels on screen, it still counts
  /// as closed.
  bool get vectorQuickFill => _vectorQuickFill;

  set vectorQuickFill(bool on) {
    if (_vectorQuickFill == on) return;
    _vectorQuickFill = on;
    notifyListeners();
  }

  /// vectorTextStyle is the type new text in a drawing is set in -- its
  /// size in the canvas's own pixels -- and vectorTextColour its colour.
  VectorText get vectorTextStyle => _vectorTextStyle;

  Color get vectorTextColour => _vectorTextColour;

  set vectorTextColour(Color c) {
    _vectorTextColour = c;
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
    if (e?.shapes case var shapes? when i >= 0 && i < shapes.length) {
      if (shapes[i].liveText != null) {
        replaceElement(e!.withShape(i, shapes[i].copyWith(fill: c)),
            transient: _vectorTyping >= 0);
      }
    }
    notifyListeners();
  }

  /// vectorTyping is the shape of the drawing being typed into with the
  /// text tool, or -1.
  int get vectorTyping => _vectorTyping;

  /// _typedShape is the drawing, the shape being typed into and its index,
  /// while there is one.
  (VectorElement, int, VectorShape)? _typedShape() {
    var e = editingVector;
    var i = _vectorTyping;
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
    var i = _vectorShape;
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
    _vectorTextStyle = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align);
    var e = editingVector;
    var i = _vectorTyping >= 0 ? _vectorTyping : _vectorShape;
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
      FontFiles.instance.load(t.family, t.weight, t.italic).then((p) {
        if (p != null) retypeVectorText(shape, t);
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
  /// line starting at [at] in the drawing's own units, and starts typing
  /// into it.
  Future<void> newVectorText(Offset at) async {
    stopVectorTyping();
    var e = editingVector;
    if (e == null) return;
    var style = _vectorTextStyle;
    var t = VectorText(
        family: style.family,
        weight: style.weight,
        italic: style.italic,
        size: style.size * VectorSpace(e).unitsPer,
        spacing: style.spacing,
        leading: style.leading,
        align: style.align,
        origin: at);
    await FontFiles.instance.load(t.family, t.weight, t.italic);
    e = editingVector;
    if (e == null) return;
    var shapes = e.shapes ?? const <VectorShape>[];
    beginInteraction();
    replaceElement(
        e.copyWith(shapes: [
          ...shapes,
          VectorShape(paths: const [], fill: _vectorTextColour, text: t),
        ]),
        transient: true);
    _vectorTyping = shapes.length;
    _vectorShape = shapes.length;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// startVectorTyping types into shape [shape], text already.
  void startVectorTyping(int shape) {
    if (_vectorTyping == shape) return;
    stopVectorTyping();
    beginInteraction();
    _vectorTyping = shape;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// stopVectorTyping finishes the text being typed: what was typed is one
  /// change, and text left empty is taken away.
  void stopVectorTyping() {
    if (_vectorTyping < 0) return;
    if (_typedShape() case (var e, var i, var s)?
        when (s.liveText?.text.trim() ?? "x").isEmpty) {
      var shapes = [...e.shapes!]..removeAt(i);
      replaceElement(e.copyWith(shapes: shapes), transient: true);
      if (_vectorShape == i) _vectorShape = -1;
    }
    _vectorTyping = -1;
    endInteraction();
    notifyListeners();
  }

  /// sampling is whether the eyedropper is out: the next press on the canvas
  /// takes the colour under it, and gives it to [_onSampled]. sampled is
  /// the colour it last took.
  bool get sampling => _onSampled != null;

  Color? get sampled => _sampled;

  void startSampling(ValueChanged<Color> onSampled) {
    _onSampled = onSampled;
    notifyListeners();
  }

  void stopSampling() {
    if (_onSampled == null) return;
    _onSampled = null;
    notifyListeners();
  }

  /// sampledColour hands the eyedropper what it took, and puts it away.
  void sampledColour(Color c) {
    var give = _onSampled;
    _onSampled = null;
    _sampled = c;
    give?.call(c);
    notifyListeners();
  }

  /// vectorKnifeGap is how far apart the knife leaves the two sides of a
  /// cut, in the canvas's own pixels.
  double get vectorKnifeGap => _vectorKnifeGap;

  set vectorKnifeGap(double v) {
    if (_vectorKnifeGap == v) return;
    _vectorKnifeGap = v;
    notifyListeners();
  }

  double get vectorFillGap => _vectorFillGap;

  set vectorFillGap(double v) {
    if (_vectorFillGap == v) return;
    _vectorFillGap = v;
    notifyListeners();
  }

  /// vectorPencilFill is the colour a fill brush fills its strokes with, and
  /// the quick fill fills an area with.
  Color get vectorPencilFill => _vectorPencilFill;

  set vectorPencilFill(Color c) {
    if (_vectorPencilFill == c) return;
    _vectorPencilFill = c;
    notifyListeners();
  }

  Color get vectorPencilColour => _vectorPencilColour;

  set vectorPencilColour(Color c) {
    if (_vectorPencilColour == c) return;
    _vectorPencilColour = c;
    notifyListeners();
  }

  /// stylusButtons is what the pen's three buttons do with the pencil out,
  /// in the order the pen reports them -- a right click, a middle click, a
  /// back click, which is what a tablet's driver sends for them -- and
  /// stylusEraser what its other end does.
  List<StylusAction> get stylusButtons => _stylusButtons;

  void setStylusButton(int index, StylusAction action) {
    if (index < 0 || index >= _stylusButtons.length) return;
    _stylusButtons = [
      for (var (i, a) in _stylusButtons.indexed) i == index ? action : a,
    ];
    notifyListeners();
  }

  StylusAction get stylusEraser => _stylusEraser;

  set stylusEraser(StylusAction a) {
    if (_stylusEraser == a) return;
    _stylusEraser = a;
    notifyListeners();
  }

  /// vectorCombining is the shapes picked with the Boolean tool, to be
  /// combined -- each the first of its run of combined shapes.
  Set<int> get vectorCombining => _vectorCombining;

  /// toggleCombining picks shape [shape] for combining, or unpicks it.
  void toggleCombining(int shape) {
    var next = {..._vectorCombining};
    if (!next.remove(shape)) next.add(shape);
    _vectorCombining = next;
    notifyListeners();
  }

  /// clearCombining unpicks every shape picked for combining.
  void clearCombining() {
    if (_vectorCombining.isEmpty) return;
    _vectorCombining = const {};
    notifyListeners();
  }

  /// combineVector combines the shapes picked by [op], leaving the result
  /// picked.
  void combineVector(VectorCombine op) {
    var e = editingVector;
    if (e == null || _vectorCombining.length < 2) return;
    var (next, at) = withCombined(e, _vectorCombining, op);
    _vectorCombining = at >= 0 ? {at} : const {};
    _vectorPicks = const {};
    _vectorShape = -1;
    replaceElement(next);
  }

  /// separateVector undoes the combining of every picked result.
  void separateVector() {
    var e = editingVector;
    if (e == null || _vectorCombining.isEmpty) return;
    var next = e;
    for (var base in _vectorCombining) {
      next = withSeparated(next, base);
    }
    _vectorCombining = const {};
    replaceElement(next);
  }

  /// vectorTint is the tint brush's colour -- or gradient, laid across each
  /// stroke as the colour picker sets it.
  PaintSpec get vectorTint => _vectorTint;

  set vectorTint(PaintSpec p) {
    if (_vectorTint == p) return;
    _vectorTint = p;
    notifyListeners();
  }

  /// vectorBrushSize is the tint brush's width on screen, in pixels: the
  /// same brush however far in the canvas is zoomed. vectorBrushSoft is how
  /// far its edge fades, 0 to 1.
  double get vectorBrushSize => _vectorBrushSize;

  set vectorBrushSize(double v) {
    if (_vectorBrushSize == v) return;
    _vectorBrushSize = v;
    notifyListeners();
  }

  double get vectorBrushSoft => _vectorBrushSoft;

  set vectorBrushSoft(double v) {
    if (_vectorBrushSoft == v) return;
    _vectorBrushSoft = v;
    notifyListeners();
  }

  /// vectorTintLine and vectorTintFill are where the brush's tint shows: on
  /// the drawing's lines, in its fills. Both is both.
  bool get vectorTintLine => _vectorTintLine;

  set vectorTintLine(bool on) {
    if (_vectorTintLine == on) return;
    _vectorTintLine = on;
    notifyListeners();
  }

  bool get vectorTintFill => _vectorTintFill;

  set vectorTintFill(bool on) {
    if (_vectorTintFill == on) return;
    _vectorTintFill = on;
    notifyListeners();
  }

  /// clearVectorTints takes every tint off the drawing being edited.
  void clearVectorTints() {
    var e = editingVector;
    if (e == null || !hasTints(e)) return;
    replaceElement(withoutTints(e));
  }

  /// spritePaint is the Sprite element being painted frame by frame on the
  /// canvas, when one is -- see sprite_painting.dart -- and paintSprite
  /// starts painting one, or with null stops.
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

  /// tilePaint is the Tile map being painted on the canvas, when one is --
  /// see tile_painting.dart -- and paintTiles starts painting one, or with
  /// null stops.
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

  /// studio3dDesign is the character the Studio opens with: [studio3dElement]'s,
  /// or null for a new one.
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

  /// closeStudio3d gives the page back to the canvas. With [kept], the
  /// character as the Studio kept it, every copy of it on the canvas -- and
  /// the element it was opened for -- is made as it now is; with
  /// [performance], the element it was opened for does that in its scene,
  /// as the Test step left it: one step to undo.
  void closeStudio3d(
      [CharacterDesign? kept, CharacterPerformance? performance]) {
    var opened = studio3dElement;
    studio3dElement = null;
    studio3dOpen.value = false;
    if (kept == null && performance == null) return;
    var before = _document;
    var doc = before;
    for (var e in [
      ...doc.elements,
      ...?doc.master?.elements,
      for (var sc in doc.allScenes) ...sc.elements,
    ]) {
      if (e is! Character3dElement) continue;
      var mine = e.id == opened;
      if (!mine &&
          (kept == null || e.design.id.isEmpty || e.design.id != kept.id)) {
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
      doc = _replacedAnywhere(doc, next) ?? doc;
    }
    if (identical(doc, before)) return;
    _undo.add(before);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
    _document = doc;
    _edits++;
    scheduleAutosave();
    notifyListeners();
  }

  /// _elementAnywhere is element [id] in the scene being edited, the master,
  /// or any other scene.
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
    if (_vectorTyping >= 0) {
      _vectorTyping = -1;
      endInteraction();
    }
    if (_vectorSolo) {
      _vectorSolo = false;
      if (vectorSoloOf == _soloOf) vectorSoloOf = null;
    }
    _vectorItems = const {};
    _lastSelect = VectorTool.select;
    _vectorShape = -1;
    _vectorPicks = const {};
    _vectorTool = VectorTool.select;
    _vectorPenFrom = null;
    _vectorCombining = const {};
    _vectorShapeMade = -1;
  }

  /// vectorItems is what the select shapes tool has picked: whole shapes,
  /// and pieces of cut ones. See VectorItem.
  Set<VectorItem> get vectorItems {
    var e = editingVector;
    if (e == null) return const {};
    return liveItems(e, _vectorItems);
  }

  /// pickVectorItem picks [item] alone -- or, with [toggle], adds it to
  /// what is picked or takes it out; null lets everything go.
  void pickVectorItem(VectorItem? item, {bool toggle = false}) {
    if (item == null) {
      _vectorItems = const {};
    } else if (toggle) {
      var next = {...vectorItems};
      if (!next.remove(item)) next.add(item);
      _vectorItems = next;
    } else {
      _vectorItems = {item};
    }
    // The shape's own settings follow the last one picked.
    _vectorShape = item?.shape ?? -1;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// vectorAlignsShapes is whether the align tool lines up shapes -- the
  /// select shapes tool was the last select tool used -- or points.
  bool get vectorAlignsShapes => _lastSelect == VectorTool.selectShapes;

  /// _picksShapes is whether what is picked is shapes rather than points:
  /// the select shapes tool, or the align tool after it.
  bool get _picksShapes =>
      _vectorTool == VectorTool.selectShapes ||
      (_vectorTool == VectorTool.align && vectorAlignsShapes);

  /// pickVectorItems picks [items] -- or, with [add], adds them.
  void pickVectorItems(Set<VectorItem> items, {bool add = false}) {
    _vectorItems = add ? {...vectorItems, ...items} : {...items};
    _vectorShape = items.isEmpty ? _vectorShape : items.first.shape;
    _vectorPicks = const {};
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
    if (_vectorShape >= 0 && _vectorShape < (e.shapes?.length ?? 0)) {
      return {groupOf(e, _vectorShape)};
    }
    return const {};
  }

  void pickVectorShape(int shape) {
    if (_vectorShape == shape && _vectorPicks.isEmpty) return;
    _vectorShape = shape;
    _vectorPicks = const {};
    notifyListeners();
  }

  /// pickVectorPoint picks [pick] alone -- or, with [toggle], adds it to the
  /// points picked or takes it out, which is Shift and a click.
  void pickVectorPoint(VectorPick? pick, {bool toggle = false}) {
    Set<VectorPick> next;
    if (pick == null) {
      next = const {};
    } else if (toggle) {
      next = {..._vectorPicks};
      if (!next.remove(pick)) next.add(pick);
    } else {
      next = {pick};
    }
    if (setEquals(next, _vectorPicks)) return;
    _vectorPicks = next;
    if (pick != null) _vectorShape = pick.shape;
    notifyListeners();
  }

  /// pickVectorPoints picks [picks], all at once: a box dragged across the
  /// drawing.
  void pickVectorPoints(Set<VectorPick> picks) {
    _vectorPicks = {...picks};
    if (picks.isNotEmpty) _vectorShape = picks.first.shape;
    notifyListeners();
  }

  /// deleteVectorPoint takes out the points picked in the drawing being
  /// edited, returning whether there were any to take.
  bool deleteVectorPoint() {
    var e = editingVector, picks = _vectorPicks;
    if (e == null) return false;
    // A shape picked whole, with no points: every point of it.
    if (picks.isEmpty && _vectorShape >= 0) {
      var shape = e.shapes?.elementAtOrNull(_vectorShape);
      if (shape != null) {
        picks = {
          for (var (p, run) in shape.paths.indexed)
            for (var n = 0; n < run.nodes.length; n++)
              VectorPick(_vectorShape, p, n),
        };
      }
    }
    if (picks.isEmpty) return false;
    var next = withoutPoints(e, picks);
    _vectorPicks = const {};
    _vectorPenFrom = null;
    if ((next.shapes?.length ?? 0) < (e.shapes?.length ?? 0)) {
      _vectorShape = -1;
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
  /// whatever the editing carried out past it, so the box drawn round it is
  /// round all of it. See boxedToDrawing.
  void _fitEditedVector() {
    var e = editingVector;
    if (e == null) return;
    var fitted = boxedToDrawing(e);
    if (identical(fitted, e)) return;
    apply(_document.withElement(fitted));
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

  /// replaceAnywhere changes element [next] wherever it is -- this canvas,
  /// the master or another scene.
  void replaceAnywhere(CanvasElement next, {bool transient = false}) {
    var doc = _replacedAnywhere(_document, next);
    if (doc == null) return;
    apply(doc, transient: transient);
  }

  /// pickClips picks [ids] on the timeline, wherever each one is: a box
  /// dragged across the lanes.
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

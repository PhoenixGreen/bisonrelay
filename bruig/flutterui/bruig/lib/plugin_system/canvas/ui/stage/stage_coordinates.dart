part of 'canvas_stage.dart';

// The page and the screen: the view (stage_transform.dart) made from the
// controller, the document and the stage's layout, which says where a
// document point is drawn and which point a pointer is over; the scroll kept
// in step with it (stage_scroll.dart); and the selection's box. Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StageCoordinates on CanvasStageState {
  /// _view is how the page sits in the window now: see StageTransform. Asked
  /// many times a frame, and the facing leaf it reads walks the document's
  /// scenes, so the last one made is kept while what it is made from holds.
  StageTransform get _view {
    var level = _level;
    var rest = (
      controller.fit,
      controller.zoom,
      controller.showOverspill,
      controller.previewAt != null,
      _visible,
      _viewport,
      level,
    );
    if (_viewKept case ((var doc, var made), var known)
        when identical(doc, document) && made == rest) {
      return known;
    }
    var view = StageTransform.of(
      document,
      fit: rest.$1,
      zoom: rest.$2,
      overspill: rest.$3,
      previewing: rest.$4,
      visible: _visible,
      viewport: _viewport,
      level: level,
    );
    _viewKept = ((document, rest), view);
    return view;
  }

  /// _level is a game scene's reach past the page, in document units, so it
  /// can be scrolled to; null if it fits, for a non-game, and during play.
  Rect? get _level {
    if (!document.game || controller.gaming || document.editingMaster) {
      return null;
    }
    // Asked several times a build: cached per document, frame and live clock.
    var key = (document, controller.frame, controller.liveMotion?.clock);
    if (_levelOf case (var k, var known)
        when identical(k.$1, key.$1) && k.$2 == key.$2 && k.$3 == key.$3) {
      return known;
    }
    var made = _levelNow();
    _levelOf = (key, made);
    return made;
  }

  Rect? _levelNow() {
    var page = Offset.zero & document.size.size;
    var reach = page;
    for (var e in document.elements) {
      // Sounds are kept off the canvas, and a backdrop fills the page.
      if (e is AudioElement || e is BackgroundElement) continue;
      // Where it is drawn, as StageHitTest.posed has it. Not through _hit:
      // its scale comes from the view this level is made into.
      reach = reach.expandToInclude(e.movedBoundsAt(controller.frame, document,
          live: controller.liveMotion));
    }
    return reach == page ? null : reach;
  }

  /// _facingPage is the page drawn beside the edited one, or null when it
  /// stands alone (scenes, facing pages off, a cover, the first leaf, or the
  /// master, which would otherwise look different by where it was opened
  /// from). See CanvasDocument.facingAt. The neighbour is only drawn.
  int? get _facingPage =>
      document.editingMaster ? null : document.facingAt(document.at);

  /// _pageRect is the page on screen: see StageTransform.pageRect.
  Rect get _pageRect => _view.pageRect;

  /// _scale is one document unit on screen: see StageTransform.scale.
  double get _scale => _view.scale;

  /// _tellControllerTheScale reports the fitted scale to the controller after
  /// the frame: notifying during layout is "setState called during build".
  void _tellControllerTheScale() {
    var found = _view.fitScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.reportFitScale(found);
    });
  }

  /// _clampedPan is the view as CanvasController.pan holds it: the page's
  /// middle from the window's, in screen pixels.
  Offset get _clampedPan => _scroller.panOf(_view);

  /// _setPan moves the view as near [pan] as the page can be scrolled.
  void _setPan(Offset pan) {
    controller.pan = _scroller.moveTo(_view, pan);
  }

  /// _syncScroll scrolls to the view once the page is laid out at its size.
  void _syncScroll() {
    if (!mounted) return;
    _scroller.jumpTo(_view.scrollFor(controller.pan));
  }

  /// _scaleOrOne is a stage length's divisor: see StageTransform.scaleOrOne.
  double get _scaleOrOne => _view.scaleOrOne;

  /// _toDocument is stage point [stage] in document space.
  Offset _toDocument(Offset stage) => _view.toDocument(stage);

  /// _toStage is document point [doc] in stage space.
  Offset _toStage(Offset doc) => _view.toStage(doc);

  /// _toStageRect is document rect [doc] on the stage.
  Rect _toStageRect(Rect doc) => _view.toStageRect(doc);

  /// toDocumentPoint is a widget point in document space, for sidebar drops.
  Offset toDocumentPoint(Offset local) => _toDocument(local + _scrolled);

  /// pageRect is the canvas's frame in widget coordinates, for tests: the
  /// canvas is painted, so there is no render box to measure.
  @visibleForTesting
  Rect get pageRect => _pageRect.shift(-_scrolled);

  @visibleForTesting
  Rect get contentRect {
    var view = _view;
    return (view.origin & view.scaledSize).shift(-_scrolled);
  }

  /// spreadRect is the page and facing leaf's frame together, for tests.
  @visibleForTesting
  Rect get spreadRect => _view.viewRect.shift(-_scrolled);

  /// textFlowGrips is a selected text box's overflow dots, for tests.
  @visibleForTesting
  TextFlowGrips? get textFlowGrips => _flowGrips();

  /// textFlowLines is the chain links drawn, for tests.
  @visibleForTesting
  List<FlowLine> get textFlowLines => _flowLines();

  /// gizmo is the gizmo on the selected staged element, for tests.
  @visibleForTesting
  StageGizmo? get gizmo => _gizmo();

  /// toStagePoint is a document point on screen, for tests.
  @visibleForTesting
  Offset toStagePoint(Offset doc) => _toStage(doc) - _scrolled;

  /// handleAt is [handle] on screen, for tests: turned or slanted, it is off
  /// the box's corner.
  @visibleForTesting
  Offset handleAt(StageHandle handle) {
    var bounds = _selectionBounds;
    return bounds == null ? Offset.zero : _handlePosition(handle, bounds);
  }

  List<CanvasElement> get _chosen => chosenOf(controller);

  /// _selectionBounds is the axis-aligned box round the selection, in
  /// document space; rotation is ignored for several.
  Rect? get _selectionBounds {
    var elements = _chosen;
    if (elements.isEmpty) return null;
    // A team on a pitch has no box: the pitch places it.
    if (elements.length == 1 &&
        elements.first is TeamElement &&
        (elements.first as TeamElement).linked) {
      return null;
    }
    // A reused element's copies are each outlined and picked alone; a box
    // round them all shows only with every copy picked, as it would be
    // clutter. One copy picked gets its own box to size, turn and move.
    if (_oneCopy case (var e, var i)?) {
      return e.boundsWith(_copyPose(e, i));
    }
    // A picture piece picked in a text: its own box (stage_text_pieces.dart).
    if (_onePiece case (var e, var i)?) return _pieceBounds(e, i);
    // A Free cell picked in a Layout (stage_layouts.dart).
    if (_oneFreeCell case (var e, var c)?) return _freeCellBounds(e, c);
    if (elements.length == 1) {
      var e = elements.first;
      if (e.base.motion.instances case var set? when set.count > 1) {
        if (!controller.allCopiesChosen(e.id) &&
            controller.pickedCopiesOf(e.id).length < set.count) {
          return null;
        }
      }
    }
    // Where they are on this frame, so the box follows an animated element.
    var box = _visualBounds(elements.first);
    for (var e in elements.skip(1)) {
      box = box.expandToInclude(_visualBounds(e));
    }
    return box;
  }

  /// _oneCopy is (element, index) when one copy of the one selected reused
  /// element is picked: the one copy that has a box.
  (CanvasElement, int)? get _oneCopy {
    var elements = _chosen;
    if (elements.length != 1) return null;
    var e = elements.first;
    var set = e.base.motion.instances;
    if (set == null || set.count < 2) return null;
    var picked = controller.pickedCopiesOf(e.id);
    if (picked.length != 1) return null;
    var i = set.items.indexWhere((x) => x.id == picked.first);
    return i < 0 ? null : (e, i);
  }

  Keyframe _copyPose(CanvasElement e, int i) =>
      poseWithMotion(e, controller.frame, controller.document,
          live: controller.liveMotion, instance: i);

  /// _boxIsNotTheShape marks elements whose selection box is bigger than what
  /// the pointer can land on: see _onPointerDown. A shape is pressed by its
  /// outline (StageHitTest.contains), which leaves its box's corners empty.
  bool _boxIsNotTheShape(CanvasElement e) =>
      e is LineElement ||
      e is PathElement ||
      e is ShapeElement ||
      (e is TextElement && e.wordsSetIn(document) == WordsSet.onLine);

  /// _visualBounds is where an element is drawn: outside its rectangle for a
  /// bowed line, a path or text on a line. See visualBoundsOf.
  Rect _visualBounds(CanvasElement e) =>
      visualBoundsOf(e, document, controller.frame,
          live: controller.liveMotion);

  /// _selectionHasOwnGeometry is whether handles are worth showing. See
  /// hasOwnGeometry.
  bool get _selectionHasOwnGeometry {
    var elements = _chosen;
    if (elements.isEmpty) return false;
    return elements.every((e) => hasOwnGeometry(e, document, controller.frame));
  }

  /// _rotationOfSelection is the lone selection's rotation in radians, or 0.
  double get _rotationOfSelection {
    if (_onePiece case (var e, var i)?) return _pieceTurn(e, i) * math.pi / 180;
    if (_oneFreeCell case (var e, var c)?) {
      return (e.rotation + c.turn) * math.pi / 180;
    }
    if (_oneCopy case (var e, var i)?) {
      return (e.rotation + _copyPose(e, i).rotate) * math.pi / 180;
    }
    if (_boxIsDrawn) return 0;
    return _chosen.length == 1
        ? _chosen.first.movedRotationAt(controller.frame, controller.document,
                live: controller.liveMotion) *
            math.pi /
            180
        : 0;
  }

  /// _skewOfSelection is the lone selection's slant in degrees, or zero.
  Offset get _skewOfSelection => _chosen.length == 1 &&
          _onePiece == null &&
          _oneFreeCell == null &&
          !_boxIsDrawn
      ? Offset(_chosen.first.base.skewX, _chosen.first.base.skewY)
      : Offset.zero;

  /// _boxIsDrawn is whether the lone selection's box is already round it as
  /// it is drawn on the page, turned and slanted: a line's or a path's,
  /// which is round its curve (visualBoundsOf), so it is not laid out by
  /// the element's turn and slant again. Not one copy of a reused one,
  /// which has a box of its own.
  bool get _boxIsDrawn =>
      _chosen.length == 1 &&
      _chosen.first is StrokedElement &&
      _oneCopy == null;

  /// _frameOfSelection is the selection box's turn and slant on the page.
  BoxFrame get _frameOfSelection => BoxFrame(
      _rotationOfSelection * 180 / math.pi,
      _skewOfSelection.dx,
      _skewOfSelection.dy);
}

part of 'canvas_stage.dart';

// The page and the screen: where a document point is drawn, and which point a
// pointer is over. Part of CanvasStageState: its fields, lifecycle and build
// are in canvas_stage.dart.

extension StageCoordinates on CanvasStageState {
  /// _fitScale is the scale at which the whole canvas fits, with
  /// [CanvasStageState._stageMargin] to spare. Worked out on every build: it changes with the
  /// window and sidebar, which the controller does not know.
  double get _fitScale {
    var size = document.size.size;
    if (size.width <= 0 || size.height <= 0) return 1;
    // A spread is two pages across: only the width makes room.
    var across = size.width * (_spreadShown ? 2 : 1);
    var byWidth = (_visible.width - CanvasStageState._stageMargin * 2) / across;
    // Fit to width ignores the height: a 9:16 story would be a narrow strip.
    var fit = controller.fit == CanvasFit.width
        ? byWidth
        : math.min(
            byWidth,
            (_visible.height - CanvasStageState._stageMargin * 2) /
                size.height);
    // The page gives up room for the overspill, not the margin.
    if (controller.showOverspill) {
      fit /= 1 + CanvasStageState._overspillFraction * 2;
    }
    return fit.isFinite && fit > 0 ? fit : 1;
  }

  /// _viewRect is everything drawn: the page, plus overspill when showing.
  /// Clipped and hit-tested against, so off-page elements are grabbable
  /// exactly when seen.
  Rect get _viewRect {
    var page = _pageRect;
    // The neighbour's half of the spread, on its own side. The edited page
    // keeps its frame and origin, so the pointer code knows of one leaf.
    if (_spreadShown) {
      page = _facingOnLeft
          ? Rect.fromLTWH(page.left, page.top, page.width * 2, page.height)
          : Rect.fromLTWH(
              page.left - page.width, page.top, page.width * 2, page.height);
    }
    var shown = !controller.showOverspill
        ? page
        : Rect.fromCenter(
            center: page.center,
            width: page.width * (1 + CanvasStageState._overspillFraction * 2),
            height: page.height * (1 + CanvasStageState._overspillFraction * 2),
          );
    // A game's level, drawn, grabbable and scrollable while not played.
    if (_level case var level?) {
      shown = shown.expandToInclude(Rect.fromPoints(
          _toStage(level.topLeft), _toStage(level.bottomRight)));
    }
    return shown;
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
    var hit = _hit;
    for (var e in document.elements) {
      // Sounds are kept off the canvas, and a backdrop fills the page.
      if (e is AudioElement || e is BackgroundElement) continue;
      reach = reach.expandToInclude(hit.posed(e));
    }
    return reach == page ? null : reach;
  }

  /// _levelShown is whether a game's level reaches past the page.
  bool get _levelShown => _level != null;

  /// _contentSize is the room the canvas and margins need, the excess over
  /// the visible box scrolled.
  Size _contentSize(Size visible) {
    if (visible.width <= 0 || visible.height <= 0) return visible;
    var spill = controller.showOverspill
        ? 1 + CanvasStageState._overspillFraction * 2
        : 1.0;
    var page = document.size.size * _scale;
    var wide = page.width * spill * (_spreadShown ? 2 : 1) +
        CanvasStageState._stageMargin * 2;
    var tall = page.height * spill + CanvasStageState._stageMargin * 2;
    // A game's level: the page stays centred, so each side gets as much room
    // as the level reaches past the far side.
    if (_level case var level?) {
      var doc = document.size.size;
      var across = math.max(-level.left, level.right - doc.width) * _scale;
      var down = math.max(-level.top, level.bottom - doc.height) * _scale;
      wide = math.max(
          wide, page.width + across * 2 + CanvasStageState._stageMargin * 2);
      tall = math.max(
          tall, page.height + down * 2 + CanvasStageState._stageMargin * 2);
    }
    // Zoomed, room to move it about: half a window past its edges, so it can
    // be lifted clear of the timeline and mixer. Unzoomed it stays centred.
    if ((controller.zoom - 1).abs() > 0.001) {
      wide = math.max(wide, visible.width * 2 - wide) + visible.width;
      tall = math.max(tall, visible.height * 2 - tall) + visible.height;
    }
    return Size(math.max(visible.width, wide), math.max(visible.height, tall));
  }

  /// _facingPage is the page drawn beside the edited one, or null when it
  /// stands alone (scenes, facing pages off, a cover, the first leaf, or the
  /// master, which would otherwise look different by where it was opened
  /// from). See CanvasDocument.facingAt. The neighbour is only drawn.
  int? get _facingPage =>
      document.editingMaster ? null : document.facingAt(document.at);

  /// _bookPreview is whether the document plays as a book: every leaf drawn
  /// in its spread place, so a transition between spreads moves both.
  bool get _bookPreview => controller.previewAt != null && document.hasSpread;

  /// _spreadShown is whether room is given to the facing leaf. Fitted to
  /// width there is none, but the neighbour is still drawn, since a picture
  /// across the gutter is part of this page.
  bool get _spreadShown =>
      (_facingPage != null || _bookPreview) &&
      controller.fit != CanvasFit.width;

  /// _facingOnLeft is whether the edited page is the left leaf.
  bool get _facingOnLeft {
    if (_bookPreview) {
      return document.spreadOf(document.at)?.left == document.at;
    }
    if (document.editingMaster) return false;
    return document.facingIsLeft(document.at) ?? false;
  }

  /// _onFacingPage is whether a stage point is over the facing leaf.
  bool _onFacingPage(Offset stage) {
    if (!_spreadShown) return false;
    var page = _pageRect;
    if (stage.dy < page.top || stage.dy > page.bottom) return false;
    return _facingOnLeft ? stage.dx > page.right : stage.dx < page.left;
  }

  /// _pageRect is the page on screen at [_scale], centred in the viewport.
  Rect get _pageRect {
    var size = document.size.size * _scale;
    // The spread is centred, the edited page taking its half, so it does not
    // shift when the edited page changes sides.
    var across = !_spreadShown
        ? 0.0
        : (_facingOnLeft ? -size.width / 2 : size.width / 2);
    return Rect.fromCenter(
      center: Offset(_viewport.width / 2 + across, _viewport.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  /// _scale is one document unit on screen: the fit times the zoom.
  double get _scale => _fitScale * controller.zoom;

  /// _tellControllerTheScale reports the fitted scale to the controller after
  /// the frame: notifying during layout is "setState called during build".
  void _tellControllerTheScale() {
    var found = _fitScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.reportFitScale(found);
    });
  }

  Size get _scaledSize => document.size.size * _scale;

  /// _origin is the document's top-left in stage space: the page's own.
  Offset get _origin => _pageRect.topLeft;

  /// _clampedPan is the view as CanvasController.pan holds it: the page's
  /// middle from the window's, in screen pixels.
  Offset get _clampedPan {
    var page = _pageRect.center;
    var at = _scrolled + Offset(_visible.width / 2, _visible.height / 2);
    return page - at;
  }

  /// _scrollFor is the scroll that puts the view at [pan], within range.
  Offset _scrollFor(Offset pan) {
    var page = _pageRect.center;
    var want = page - Offset(_visible.width / 2, _visible.height / 2) - pan;
    return Offset(
      want.dx
          .clamp(0.0, math.max(0.0, _viewport.width - _visible.width))
          .toDouble(),
      want.dy
          .clamp(0.0, math.max(0.0, _viewport.height - _visible.height))
          .toDouble(),
    );
  }

  /// _setPan moves the view as near [pan] as the page can be scrolled.
  void _setPan(Offset pan) {
    var to = _scrollFor(pan);
    _jumpTo(to);
    var page = _pageRect.center;
    var at = page - Offset(_visible.width / 2, _visible.height / 2) - to;
    controller.pan = at;
  }

  void _jumpTo(Offset to) {
    _syncing = true;
    if (_scrollX.hasClients && (_scrollX.offset - to.dx).abs() > 0.5) {
      _scrollX.jumpTo(to.dx.clamp(0.0, _scrollX.position.maxScrollExtent));
    }
    if (_scroll.hasClients && (_scroll.offset - to.dy).abs() > 0.5) {
      _scroll.jumpTo(to.dy.clamp(0.0, _scroll.position.maxScrollExtent));
    }
    _syncing = false;
  }

  /// _syncScroll scrolls to the view once the page is laid out at its size.
  void _syncScroll() {
    if (!mounted) return;
    _jumpTo(_scrollFor(controller.pan));
  }

  /// _scaleOrOne is _scale, or 1 while it is 0 (before the page is laid
  /// out): what a stage length is divided by to give a document length.
  double get _scaleOrOne => _scale == 0 ? 1 : _scale;

  Offset _toDocument(Offset stage) => (stage - _origin) / _scaleOrOne;

  Offset _toStage(Offset doc) => doc * _scale + _origin;

  /// _toStageRect is document rect [doc] on the stage: its corner moved
  /// like a point, its size scaled.
  Rect _toStageRect(Rect doc) {
    var tl = _toStage(doc.topLeft);
    return Rect.fromLTWH(tl.dx, tl.dy, doc.width * _scale, doc.height * _scale);
  }

  /// toDocumentPoint is a widget point in document space, for sidebar drops.
  Offset toDocumentPoint(Offset local) => _toDocument(local + _scrolled);

  /// pageRect is the canvas's frame in widget coordinates, for tests: the
  /// canvas is painted, so there is no render box to measure.
  @visibleForTesting
  Rect get pageRect => _pageRect.shift(-_scrolled);

  @visibleForTesting
  Rect get contentRect => (_origin & _scaledSize).shift(-_scrolled);

  /// spreadRect is the page and facing leaf's frame together, for tests.
  @visibleForTesting
  Rect get spreadRect => _viewRect.shift(-_scrolled);

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
  /// the pointer can land on: see _onPointerDown.
  bool _boxIsNotTheShape(CanvasElement e) =>
      e is LineElement ||
      e is PathElement ||
      (e is TextElement && e.curve != null);

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
    return _chosen.length == 1
        ? _chosen.first.movedRotationAt(controller.frame, controller.document,
                live: controller.liveMotion) *
            math.pi /
            180
        : 0;
  }

  /// _skewOfSelection is the lone selection's slant in degrees, or zero.
  Offset get _skewOfSelection =>
      _chosen.length == 1 && _onePiece == null && _oneFreeCell == null
          ? Offset(_chosen.first.base.skewX, _chosen.first.base.skewY)
          : Offset.zero;

  /// _frameOfSelection is the selection box's turn and slant on the page.
  BoxFrame get _frameOfSelection => BoxFrame(
      _rotationOfSelection * 180 / math.pi,
      _skewOfSelection.dx,
      _skewOfSelection.dy);
}

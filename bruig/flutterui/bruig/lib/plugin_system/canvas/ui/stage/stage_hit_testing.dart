part of 'canvas_stage.dart';

// What is under the pointer: elements, the selection's handles and flow grips
// and which of them wins, a text's pieces, and the part of an element at a
// point (a counter's buttons and loose pieces, a chart's key entries, a
// speaker's and a video's controls, a Code pane, a master speaker or video).
// With them, where the handles, flow grips and flow links are drawn, which
// the tests share. What a press on an element's own controls does is in
// stage_synth_controls, stage_code_controls and stage_element_controls. Part
// of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension StageHitTesting on CanvasStageState {
  /// _hit is what is where on the page now. Made afresh each time, being a
  /// few reads: one kept would go stale as the frame or document changes.
  StageHitTest get _hit => StageHitTest(
      document: document,
      frame: controller.frame,
      live: controller.liveMotion,
      scale: _scale,
      cameras: _camerasShown);

  /// _directed is whether the page is seen through the scene's camera:
  /// while it plays, or in camera view, unless the master is edited.
  bool get _directed =>
      (controller.playing || controller.cameraView) && !document.editingMaster;

  /// _camerasShown is whether each Camera's frame is drawn over the page,
  /// and so whether one can be taken there: not with helpers hidden, nor
  /// while the page is seen through a camera (the scene's, or a game's own
  /// framing), nor on a 3D stage, where a camera is in the scene. The
  /// painter and the hit test both ask this.
  bool get _camerasShown =>
      controller.showHelpers &&
      !_directed &&
      !(controller.gaming && controller.gameFraming != null) &&
      !isStageScene(document);

  /// _hitElement is the topmost element under a document point.
  CanvasElement? _hitElement(Offset point) => _hit.topmost(point);

  /// _selectedAt is the topmost selected element under [point], which a
  /// press takes before anything drawn over it. Not a hidden one: picked in
  /// Layers, it would be moved unseen by a press on what is drawn there.
  CanvasElement? _selectedAt(Offset point) {
    var picked = controller.selection;
    if (picked.isEmpty) return null;
    return _hit.topmost(point, where: (e) => picked.contains(e.id));
  }

  /// _containsPoint is whether [point] is inside [e] as drawn, turn and slant
  /// undone.
  bool _containsPoint(CanvasElement e, Offset point) => _hit.contains(e, point);

  /// _onSelectionGrip is whether a press takes hold of the selection: a
  /// handle, a flow grip, or a path's points.
  bool _onSelectionGrip(Offset stage, Offset doc) {
    if (controller.selection.isEmpty) return false;
    if (_hitHandle(stage) != null || _hitFlowGrip(stage) != null) return true;
    var path = _selectedPath();
    return path != null && _hitPathControl(path, doc) != null;
  }

  StageHandle? _hitHandle(Offset stage) => _nearestHandle(stage)?.$1;

  /// _nearestHandle is the closest grip in reach and its distance: closest,
  /// since on a small element handle targets overlap; the distance lets the
  /// flow grips on the same outline tell whether they are nearer.
  (StageHandle, double)? _nearestHandle(Offset stage) {
    if (!_selectionHasOwnGeometry) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;
    var reach = handleReach();

    // Hidden helpers cannot be grabbed: see CanvasController.showHelpers.
    if (!controller.showHelpers) return null;

    // The middle is not a handle: on a one-line text box the top and bottom
    // targets would meet, and every press would resize instead of move.
    if (_insideCore(stage, bounds, reach)) return null;

    StageHandle? best;
    var away = double.infinity;
    for (var handle in StageHandle.values) {
      var at = _handlePosition(handle, bounds);
      // Clipped out of sight is out of reach.
      if (!_view.viewRect.inflate(reach).contains(at)) continue;
      var d = (stage - at).distance;
      if (d <= reach && d < away) {
        best = handle;
        away = d;
      }
    }
    return best == null ? null : (best, away);
  }

  /// _insideCore is whether a stage point is deep enough inside [bounds] that
  /// no grip can have meant it. Each direction gives at most a third to its
  /// grips, so a middle is always left to press.
  bool _insideCore(Offset stage, Rect bounds, double reach) {
    var on = Offset(bounds.width, bounds.height) * _scale;
    if (on.dx <= 0 || on.dy <= 0) return false;
    var keepX = math.min(reach, on.dx / 3);
    var keepY = math.min(reach, on.dy / 3);

    // In the selection's own frame, so a rotated box keeps its middle.
    var d = stage - _toStage(bounds.center);
    var local = _frameOfSelection.invert(d);
    return local.dx.abs() < on.dx / 2 - keepX &&
        local.dy.abs() < on.dy / 2 - keepY;
  }

  /// _selectedText is the lone selected text element, which shows flow grips.
  TextElement? _selectedText() {
    if (controller.selection.length != 1) return null;
    var element = document.elementById(controller.selection.first);
    return element is TextElement ? element : null;
  }

  /// _flowGrips is a selected text box's two dots and what they say, or null.
  TextFlowGrips? _flowGrips() {
    if (!controller.showHelpers) return null;
    var e = _selectedText();
    if (e == null || _onePiece != null) return null;
    if (e.wordsSetIn(document) == WordsSet.onLine) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;

    var inner = e.box.inner(e.bounds);
    var flow = flowFor(
        e, document, inner, drawnTextSpec(e, e.bounds, doc: document),
        frame: controller.frame, images: controller.images);

    return TextFlowGrips(
      inAt: _gripPosition(bounds, top: true),
      outAt: _gripPosition(bounds, top: false),
      overflowing: flow.overflows,
      receiving: flow.receiving,
      linked: e.flowsOnIn(document) && document.elementById(e.flowTo) != null,
    );
  }

  /// _flowDragLine is the link being dragged, from its box to the pointer.
  FlowLine? _flowDragLine() {
    if (_gesture case _FlowLinkDrag(:var fromId, :var at)) {
      var box = document.elementById(fromId);
      if (box == null) return null;
      return FlowLine(_toStage(_flowPointOf(_hit.posed(box), top: false)), at);
    }
    return null;
  }

  /// _flowLines is every text link worth drawing: either box selected, or
  /// all boxes shown (see CanvasController.showAllBounds).
  List<FlowLine> _flowLines() {
    // Hidden joins hide only the lines that cross the design; the grips
    // still say there is a chain and whether the words fit.
    if (!controller.showHelpers || controller.hideJoins) return const [];
    var out = <FlowLine>[];

    for (var e in document.elements) {
      if (e is! TextElement || !e.flowsOnIn(document)) continue;
      var into = document.elementById(e.flowTo);
      if (into == null || !e.visible || !into.visible) continue;

      // Not the one in hand: that is drawn from the pointer.
      if (_gesture case _FlowLinkDrag(:var fromId) when e.id == fromId) {
        continue;
      }

      var shown = controller.showAllBounds ||
          controller.selection.contains(e.id) ||
          controller.selection.contains(into.id);
      if (!shown) continue;

      var inner = e.box.inner(e.bounds);
      var flow = flowFor(
          e, document, inner, drawnTextSpec(e, e.bounds, doc: document),
          frame: controller.frame);
      out.add(FlowLine(
        _toStage(_flowPointOf(_hit.posed(e), top: false)),
        _toStage(_flowPointOf(_hit.posed(into), top: true)),
        overflowing: flow.overflows,
      ));
    }
    return out;
  }

  Offset _flowPointOf(Rect bounds, {required bool top}) => top
      ? Offset(bounds.left, bounds.top + bounds.height / 4)
      : Offset(bounds.right, bounds.bottom - bounds.height / 4);

  /// _gripPosition puts a flow grip between two resize handles, in at upper
  /// left and out at lower right, clear of the corners.
  Offset _gripPosition(Rect bounds, {required bool top}) {
    var centre = _toStage(bounds.center);
    var half = Offset(bounds.width, bounds.height) * _scale / 2;
    var local =
        top ? Offset(-half.dx, -half.dy / 2) : Offset(half.dx, half.dy / 2);
    return centre + _frameOfSelection.apply(local);
  }

  /// _textPieceOwner is the frontmost text element with a piece under the
  /// pointer outside its box. Any one, not only the selected: a piece pushed
  /// outside its box may be all of it near the pointer, and must take a
  /// first click.
  TextElement? _textPieceOwner(Offset doc) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var element = document.elements[i];
      if (element is! TextElement || element.locked || !element.visible) {
        continue;
      }
      if (_textItemAt(element, doc) != null) return element;
    }
    return null;
  }

  /// _looseTextPiece is a text element with a piece under the pointer drawn
  /// outside its box. It beats the resize handles, whose outline a piece
  /// pushed out sits against; inside the box they win (see _insideCore).
  TextElement? _looseTextPiece(Offset doc) {
    var owner = _textPieceOwner(doc);
    if (owner == null) return null;
    return _hit.posed(owner).contains(doc) ? null : owner;
  }

  /// _textItemAt is [e]'s extra piece at a document point, or null, from
  /// what draws them (see textItemRects): none where its pieces are not
  /// drawn (TextElement.showsPiecesIn). A locked piece is passed over unless
  /// [locked], for a click that must know it landed on one.
  TextItem? _textItemAt(TextElement e, Offset doc, {bool locked = false}) {
    if (!e.showsPiecesIn(document)) return null;
    // Where it is drawn, its fields filled in.
    e = textWithFields(e, document);
    var bounds = _hit.posed(e);
    var rects = textItemRects(e, bounds, doc: document);
    // Backwards: the last drawn is on top.
    for (var i = e.items.length - 1; i >= 0; i--) {
      // Hidden or locked in the Layers, it cannot be pressed.
      if (e.items[i].hidden || (e.items[i].locked && !locked)) continue;
      if (!rects[i].isEmpty && rects[i].inflate(2).contains(doc)) {
        return e.items[i];
      }
    }
    return null;
  }

  /// _topmostOf is whichever of the two is drawn in front, or the non-null one.
  CanvasElement? _topmostOf(CanvasElement? box, CanvasElement? piece) {
    if (box == null || piece == null) return box ?? piece;
    if (box.id == piece.id) return box;
    var elements = document.elements;
    return elements.indexWhere((e) => e.id == piece.id) >
            elements.indexWhere((e) => e.id == box.id)
        ? piece
        : box;
  }

  /// _hitFlowGrip is the flow grip under the pointer, if any: the outgoing
  /// grip starts or moves a link, the incoming one picks up the arriving
  /// link to disconnect it.
  ///
  /// [beat] is how close the nearest resize handle is: a grip answers only
  /// when nearer, since on a short box they nearly overlap; ties go to the
  /// handle.
  ({bool out})? _hitFlowGrip(Offset stage, {double beat = double.infinity}) {
    var grips = _flowGrips();
    if (grips == null) return null;
    var reach = flowGripSize / 2 + flowGripHitSlop;
    // On the resize grips' outline, so it keeps off the middle too.
    var bounds = _selectionBounds;
    if (bounds != null && _insideCore(stage, bounds, reach)) return null;
    var out = (stage - grips.outAt).distance;
    var into = (stage - grips.inAt).distance;
    if (out <= reach && out < beat && (!grips.receiving || out <= into)) {
      return (out: true);
    }
    if (grips.receiving && into <= reach && into < beat) return (out: false);
    return null;
  }

  /// _counterLaidOut is [e] laid out where it is drawn, showing what it
  /// shows: what the painter draws it from (counterLaidOut).
  CounterLaidOut? _counterLaidOut(CounterElement e) => counterLaidOut(
      e,
      _hit.drawn(e),
      e.shownValue(
          page: document.pageNumber,
          pose: poseWithMotion(e, controller.frame, document,
              live: controller.liveMotion),
          live: controller.counterValue));

  /// _counterPieceUnder is the loosely placed piece of [e] at document
  /// point [doc], where it is drawn, if any.
  CounterPiece? _counterPieceUnder(CounterElement e, Offset doc) {
    for (var (piece, rect)
        in _counterLaidOut(e)?.pieces(e) ?? const <(CounterPiece, Rect)>[]) {
      if (rect.contains(doc)) return piece;
    }
    return null;
  }

  /// _codePaneAt is the Code element's pane under document point [doc], as
  /// (id, pane), when its code is shown rather than its tabs; null while a
  /// pane is being typed in.
  (String, int)? _codePaneAt(Offset doc) {
    var e = _hitElement(doc);
    if (e is CodeElement && controller.codeEditing == null) {
      if (codeHitAt(e, doc, box: _hit.posed(e))
          case CodePaneHit(:var pane, inTabs: false)) {
        return (e.id, pane);
      }
    }
    return null;
  }

  /// _legendSeriesAt is the series whose key entry is at a document point,
  /// from the painter, or -1.
  int _legendSeriesAt(ChartElement e, Offset doc) {
    for (var (series, box) in chartLegendRects(e, _hit.posed(e))) {
      if (box.contains(doc)) return series;
    }
    return -1;
  }

  /// _audioPartAt is the speaker control at a document point, or null (see
  /// audioParts).
  AudioControl? _audioPartAt(AudioElement e, Offset doc) {
    var parts = audioParts(e, _hit.posed(e));
    if (parts.volume case var v? when v.contains(doc)) {
      return AudioControl.volume;
    }
    if (parts.mute case var m? when m.contains(doc)) return AudioControl.mute;
    if (e.has(AudioControl.playPause) && parts.icon.contains(doc)) {
      return AudioControl.playPause;
    }
    return null;
  }

  /// _masterAudioAt is a master speaker and control under a document point.
  (AudioElement, AudioControl)? _masterAudioAt(Offset doc) {
    if (document.editingMaster) return null;
    var master = document.masterScene;
    if (master == null) return null;
    for (var e in master.elements.reversed) {
      if (e is! AudioElement || !e.visible) continue;
      var part = _audioPartAt(e, doc);
      if (part != null) return (e, part);
    }
    return null;
  }

  /// _videoPartAt is the video part at a document point. A link answers
  /// anywhere on it.
  VideoPart? _videoPartAt(VideoElement e, Offset doc) =>
      videoPartAt(videoParts(e, _hit.posed(e)), doc,
          clickable:
              e.isLink || (e.has(VideoControl.clickToggle) && !e.clip.timed));

  /// _masterVideoAt is a master video under a document point.
  (VideoElement, VideoPart)? _masterVideoAt(Offset doc) {
    if (document.editingMaster) return null;
    var master = document.masterScene;
    if (master == null) return null;
    for (var e in master.elements.reversed) {
      if (e is! VideoElement || !e.visible) continue;
      var part = _videoPartAt(e, doc);
      if (part != null) return (e, part);
    }
    return null;
  }

  /// _anchorUnder is the element whose shown, unlocked anchor is at [stage].
  String? _anchorUnder(Offset stage) {
    for (var id in controller.selection) {
      if (!controller.anchorShown(id)) continue;
      var e = document.elementById(id);
      if (e == null || e.base.anchorLocked || e.locked) continue;
      if ((_toStage(e.anchorAt(controller.frame)) - stage).distance <=
          anchorReach) {
        return id;
      }
    }
    return null;
  }

  /// _counterButtonAt is the counter button at a document point, or -1.
  int _counterButtonAt(CounterElement e, Offset doc) {
    var rects = counterButtonRects(e, _hit.drawn(e));
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(doc)) return i;
    }
    return -1;
  }

  /// _handlePosition is where a grip is drawn, in stage space.
  Offset _handlePosition(StageHandle handle, Rect bounds) =>
      stageHandleAt(handle, bounds, _frameOfSelection,
          scale: _scale, origin: _view.origin);
}

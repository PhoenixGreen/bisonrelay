part of 'canvas_stage.dart';

// What the pointer is doing on the stage, as one value from the press that
// begins it to its release or cancel: StageGesture, its cases, and the
// State's two steps that hand a move or an end to the one under way. The
// kinds not yet made cases still run through _DragMode, in the switch in
// stage_drag.dart and the branches in stage_release.dart. Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

/// StageGesture is what the pointer is doing on the stage, from the press
/// that began it to its release or cancel. Each kind is a case that holds
/// what it needs while it runs, so nothing of a gesture outlives it and
/// two cannot be under way at once.
sealed class StageGesture {
  /// opensUndoStep is whether it began an undo step, which its end closes.
  bool get opensUndoStep;

  /// waitsToTravel is whether it does nothing until the press has gone the
  /// drag threshold, so a click does not move what it lands on.
  bool get waitsToTravel;

  /// move is the pointer moved, the button still down: to [at] on the
  /// stage, [doc] the same point in the document.
  void move(CanvasStageState stage, Offset at, Offset doc);

  /// release is the pointer let go at [at] on the stage: what the gesture
  /// does on finishing. [travelled] is whether the press went the drag
  /// threshold on the way.
  void release(CanvasStageState stage, Offset at, {required bool travelled});

  /// cancel is the system taking the pointer away. The gesture ends without
  /// the click, drop or selection a release would make. What a drag has
  /// already changed is kept, and a case that must tidy that up (a guide
  /// dragged off the page, a path whose follower is re-made) does so here
  /// as in [release].
  void cancel(CanvasStageState stage);
}

extension StageGestureSteps on CanvasStageState {
  /// _moveGesture hands a move of the pointer to [at] to [gesture], once the
  /// press has gone the drag threshold if it waits for that.
  void _moveGesture(StageGesture gesture, Offset at) {
    if (gesture.waitsToTravel && !_hasTravelled(at)) return;
    gesture.move(this, at, _toDocument(at));
  }

  /// _endGesture ends [gesture], let go at [at] or, [cancelled], taken away:
  /// it is no longer under way, it finishes (or, cancelled, does not), and
  /// then the undo step it opened is closed, so what it does on finishing
  /// is part of that step.
  void _endGesture(StageGesture gesture, Offset at, {required bool cancelled}) {
    _gesture = null;
    if (cancelled) {
      gesture.cancel(this);
    } else {
      gesture.release(this, at, travelled: _travelled);
    }
    if (gesture.opensUndoStep) controller.endInteraction();
  }
}

/// _Pan is the view slid under the pointer, by the pan tool, the middle
/// button or a pen's button. Its travel is measured on the stage, not in the
/// document, which moves with it.
class _Pan extends StageGesture {
  _Pan({required this.startPan, required this.from});

  /// startPan is the controller's pan when it began.
  final Offset startPan;

  /// from is where the pointer was then, in stage pixels.
  final Offset from;

  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    var delta = at - from;
    stage._setPan(Offset(startPan.dx + delta.dx, startPan.dy + delta.dy));
  }

  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _ElementsMarquee is a box dragged over the page from a press on no
/// element, which selects what it takes in when let go.
class _ElementsMarquee extends StageGesture {
  _ElementsMarquee(this.start) : box = Rect.fromPoints(start, start);

  /// start is where the press landed, in document space: one corner.
  final Offset start;

  /// box is the box as far as it has been dragged, in document space.
  Rect box;

  @override
  bool get opensUndoStep => false;

  /// waitsToTravel is false: the box is drawn from the press itself.
  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    stage.setState(() => box = Rect.fromPoints(start, doc));
  }

  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) {
    stage._selectWithin(box);
    // The box goes with the gesture.
    stage.setState(() {});
  }

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

/// _GuideDrag is a guide line moved, or a new one pulled from a ruler.
class _GuideDrag extends StageGesture {
  _GuideDrag(this.index);

  /// index is the guide's place in the document's list of guides.
  final int index;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyGuide(index, doc);

  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) =>
      stage._finishGuide(index);

  /// cancel drops the guide as a release does: a cancel keeps what the drag
  /// did, so a guide dragged off the page goes all the same.
  @override
  void cancel(CanvasStageState stage) => stage._finishGuide(index);
}

/// _AnchorDrag is an element's anchor point dragged. See
/// ElementBase.anchorX.
class _AnchorDrag extends StageGesture {
  _AnchorDrag(this.elementId);

  /// elementId is the element whose anchor it is.
  final String elementId;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyAnchor(elementId, doc);

  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _PathPointDrag is a point of the selected path dragged, or one of its
/// handles. The path stays selected.
class _PathPointDrag extends StageGesture {
  _PathPointDrag(this.index, {required this.isHandle, required this.handleOut});

  /// index is the point's place in the path.
  final int index;

  /// isHandle is whether a handle of the point is dragged, not the point,
  /// and handleOut whether it is the outgoing one.
  final bool isHandle, handleOut;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyNodeMove(doc, index, handle: isHandle, out: handleOut);

  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) =>
      stage._bakePathFollow();

  /// cancel bakes the follower as a release does: a cancel keeps what the
  /// drag did, and the follower must go where the points now are.
  @override
  void cancel(CanvasStageState stage) => stage._bakePathFollow();
}

/// _FlowLinkDrag is a link pulled from a text box's flow grip, carried to
/// the box it is to flow into, or off to nothing to take it away.
class _FlowLinkDrag extends StageGesture {
  _FlowLinkDrag(this.fromId, this.at);

  /// fromId is the box the link is pulled from.
  final String fromId;

  /// at is where the link's loose end is, the pointer, in stage pixels.
  Offset at;

  @override
  bool get opensUndoStep => false;

  /// waitsToTravel is false: the line follows the pointer from the press.
  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    stage.setState(() => this.at = at);
  }

  /// release links the box to the one let go on, or unlinks it: the change
  /// is an undo step of its own, made there.
  @override
  void release(CanvasStageState stage, Offset at, {required bool travelled}) {
    stage._dropFlow(fromId, at);
    // The line goes with the gesture.
    stage.setState(() {});
  }

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

part of 'canvas_stage.dart';

// What the pointer is doing on the stage, as one value from the press that
// begins it to its release or cancel: StageGesture, the State's steps that
// hand a move or an end to the one under way or hand one over to another,
// the clicks a gesture carries, and the cases with no better home. Cases
// that belong with their subject sit in its part: a synth module's
// (stage_synth_controls.dart), a Code panel's (stage_code_controls.dart), a
// counter's piece (stage_element_controls.dart), a team's player
// (stage_team_players.dart), the retouching stroke (stage_retouch.dart). The
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
  /// threshold on the way, and [clicked] whether it was let go within the
  /// click slop of where it began: a press can travel and come back.
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked});

  /// cancel is the system taking the pointer away. The gesture ends without
  /// the click, drop or selection a release would make. What a drag has
  /// already changed is kept, and a case that must tidy that up (a guide
  /// dragged off the page, a path whose follower is re-made) does so here
  /// as in [release].
  void cancel(CanvasStageState stage);

  /// endsRelease is whether, once it has ended, the rest of _onPointerUp is
  /// skipped: the resets there that the kinds still told by _DragMode need.
  /// Read after [release] or [cancel], which may decide it.
  bool get endsRelease => false;

  /// takesAll is whether every move and the release are handed to it at the
  /// very top of _onPointerMove and _onPointerUp, before anything of the
  /// stage's own, and nothing else in them runs: no hover, no brush ring,
  /// none of the release's resets. For a press that is not on the page as
  /// it is drawn: the held marker's note over it, a live preview.
  bool get takesAll => false;
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
  /// is part of that step. [clicked] is whether it was let go within the
  /// click slop of where it began.
  void _endGesture(StageGesture gesture, Offset at,
      {required bool cancelled, required bool clicked}) {
    _gesture = null;
    if (cancelled) {
      gesture.cancel(this);
    } else {
      gesture.release(this, at, travelled: _travelled, clicked: clicked);
    }
    if (gesture.opensUndoStep) controller.endInteraction();
  }

  /// _handOver puts [next] in place of the gesture under way, for a press
  /// that turns out partway to be something else. The one under way ends
  /// without finishing (nothing it would do on release is done), and the
  /// undo step it opened stays open: [next]'s end closes it, so the two are
  /// one step to take back.
  void _handOver(StageGesture next) {
    assert(_gesture?.opensUndoStep ?? false, "no open undo step to hand on");
    assert(next.opensUndoStep, "the handed-on undo step would stay open");
    setState(() => _gesture = next);
  }
}

/// _CarriesClicks is a gesture that carries the clicks its press armed (see
/// PendingClick), settled in turn as it ends: each is made if the press
/// ended as its click, and dropped otherwise.
mixin _CarriesClicks on StageGesture {
  /// carried is the clicks it carries, in the order they are tried.
  Iterable<PendingClick> get carried;

  /// endsRelease is set when a click it carried is made that ends the
  /// release.
  @override
  bool endsRelease = false;

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      _settle(stage, clicked: clicked, travelled: travelled, cancelled: false);

  /// cancel makes no click, except one made however the press ends: an
  /// instrument's key, let go.
  @override
  void cancel(CanvasStageState stage) => _settle(stage,
      clicked: false, travelled: stage._travelled, cancelled: true);

  /// _settle makes or drops each click [carried] as the press ends. A click
  /// that is made and ends the release stops there.
  void _settle(CanvasStageState stage,
      {required bool clicked,
      required bool travelled,
      required bool cancelled}) {
    for (var c in carried) {
      if (!c.madeBy(stage,
          clicked: clicked, travelled: travelled, cancelled: cancelled)) {
        c.dropped(stage);
        continue;
      }
      // Closed early, the drag's undo step does not take the click in;
      // _endGesture's closing it again does nothing.
      if (!c.inStep) stage.controller.endInteraction();
      c.click(stage);
      if (c.endsRelease) {
        endsRelease = true;
        return;
      }
    }
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
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

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
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {
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
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
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
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

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
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
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

  /// endsRelease is true: dropping the link is the whole of its release.
  @override
  bool get endsRelease => true;

  /// release links the box to the one let go on, or unlinks it: the change
  /// is an undo step of its own, made there.
  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {
    stage._dropFlow(fromId, at);
    // The line goes with the gesture.
    stage.setState(() {});
  }

  @override
  void cancel(CanvasStageState stage) => stage.setState(() {});
}

/// _ChartLabelDrag is one of the selected chart's placed labels (its title,
/// description or key) moved, or resized by its corner. One undo step.
class _ChartLabelDrag extends StageGesture with _CarriesClicks {
  _ChartLabelDrag(this.grab, {this.click});

  /// grab is the label taken, how, and where in it.
  final ChartLabelGrab grab;

  /// click is the switch of the key's entry the press landed on, if any:
  /// made if the press is let go where it began.
  final _LegendClick? click;

  @override
  Iterable<PendingClick> get carried => [click].nonNulls;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyChartLabel(grab, doc);
}

/// _TableColumnDrag is the rule between two of the selected table's
/// columns dragged, widening one and narrowing its neighbour. One undo
/// step.
class _TableColumnDrag extends StageGesture {
  _TableColumnDrag(this.column);

  /// column is the index of the column to the rule's left.
  final int column;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyTableColumn(column, doc);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _MarkerNoteDrag is the held marker's label on the page moved, or sized
/// by its corner grip, measured from the press. One undo step. The label
/// is drawn over everything and is no element's, so it takes every move
/// and the release first.
class _MarkerNoteDrag extends StageGesture {
  _MarkerNoteDrag(this.was, {required this.sizing, required this.from});

  /// was is the marker as it was at the press.
  final TimelineAction was;

  /// sizing is whether the label's grip was taken, to size it.
  final bool sizing;

  /// from is where the press began, in the document.
  final Offset from;

  @override
  bool get takesAll => true;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._dragMarkerNote(this, doc);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _BoxStart is the selection as a press on its box found it, which every
/// step of a move, resize, slant or turn works from, so that rounding does
/// not build up. Made by _beginTransform.
class _BoxStart {
  _BoxStart({
    required this.bounds,
    required this.elements,
    required this.posed,
    required this.visual,
    required this.rotation,
  });

  /// bounds is each element's resting box, by id.
  final Map<String, Rect> bounds;

  /// elements is each element as it was, for a resize that scales what is
  /// inside and for what a line or camera does instead of a box.
  final Map<String, CanvasElement> elements;

  /// posed is where each element is drawn on this frame, which a move works
  /// from.
  final Map<String, Rect> posed;

  /// visual is the box each element's handles are on: see _visualBounds.
  final Map<String, Rect> visual;

  /// rotation is each element's turn, in degrees.
  final Map<String, double> rotation;
}

/// _BoxDrag is the selection's box taken hold of: moved from inside, or
/// resized, slanted or turned by a handle. Each is one undo step, opened as
/// it begins (_beginTransform), and works from [start].
sealed class _BoxDrag extends StageGesture {
  _BoxDrag(this.start);

  /// start is the selection when the box was pressed.
  final _BoxStart start;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _BoxMove is the selection moved by a press inside its box. A press that
/// does not travel only selects, or makes the click it armed.
class _BoxMove extends _BoxDrag with _CarriesClicks {
  _BoxMove(super.start, {this.click, this.copy});

  /// click is the click the press armed on a control of what it landed on,
  /// if any: see PendingClick. A press that travels may drop it.
  PendingClick? click;

  /// copy is the copy of a reused element the press landed on, picked if
  /// the press never travels. It is tried after [click]: a Code panel's
  /// code, on a panel that is reused, arms both.
  final _CopyPick? copy;

  @override
  Iterable<PendingClick> get carried => [click, copy].nonNulls;

  /// waitsToTravel is false: it waits for the drag threshold itself, after
  /// telling its click the pointer has moved, which is measured against the
  /// click slop instead.
  @override
  bool get waitsToTravel => false;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    if (click case var c?
        when (at - stage._pressedAt).distance >
                CanvasStageState._buttonClickSlop &&
            !c.travelled(stage)) {
      click = null;
    }
    if (!stage._hasTravelled(at)) return;
    stage._applyMove(doc - stage._dragStart, start);
  }
}

/// _BoxResize is the selection resized by one of its handles, [handle].
class _BoxResize extends _BoxDrag {
  _BoxResize(super.start, this.handle);

  /// handle is the handle held.
  final StageHandle handle;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyResize(doc - stage._dragStart, handle, start);
}

/// _BoxSlant is the one element selected slanted by a side handle,
/// [handle]: see _applySkew.
class _BoxSlant extends _BoxDrag {
  _BoxSlant(super.start, this.handle);

  /// handle is the side handle held.
  final StageHandle handle;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applySkew(doc - stage._dragStart, handle, start);
}

/// _BoxTurn is the selection turned by its turning handle.
class _BoxTurn extends _BoxDrag {
  _BoxTurn(super.start);

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyRotate(doc, start);
}

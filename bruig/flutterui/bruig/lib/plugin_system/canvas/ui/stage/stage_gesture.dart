part of 'canvas_stage.dart';

// What the pointer is doing on the stage, as one value from the press that
// begins it to its release or cancel: StageGesture, the State's steps that
// hand a move or an end to the one under way or hand one over to another,
// the clicks a gesture carries, and the cases with no better home. Cases
// that belong with their subject sit in its part: a synth module's
// (stage_synth_controls.dart), a Code panel's (stage_code_controls.dart), a
// counter's piece (stage_element_controls.dart), a text's picture piece
// (stage_text_pieces.dart), a team's player (stage_team_players.dart), the
// retouching stroke (stage_retouch.dart), a 3D stage's camera, parallax
// scenery's and the gizmo (stage_3d_view.dart). The kinds not yet made
// cases still run through _DragMode, in the switch in stage_drag.dart and
// the branches in stage_release.dart. Part of CanvasStageState: its fields,
// lifecycle and build are in canvas_stage.dart.

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
  /// threshold on the way, and [clicked] whether it ended as a click: it
  /// never travelled and was let go within the click slop of where it
  /// began. A press that travels and comes back is not a click.
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked});

  /// cancel is the system taking the pointer away. The gesture ends without
  /// the click, drop or selection a release would make. What a drag has
  /// already changed is kept, and a case that must tidy that up (a guide
  /// dragged off the page, a path whose follower is re-made) does so here
  /// as in [release].
  void cancel(CanvasStageState stage);

  /// endsRelease is whether, once it has ended, the rest of _onPointerUp is
  /// skipped. All of that is for the kinds still told by _DragMode, so a
  /// gesture loses nothing by skipping it. Read after [release] or
  /// [cancel], which may decide it.
  bool get endsRelease => false;

  /// takesAll is whether every move and the release are handed to it at the
  /// very top of _onPointerMove and _onPointerUp, before anything of the
  /// stage's own, and nothing else in them runs: no hover, no brush ring,
  /// none of the release's resets. For a press that is not on the page as
  /// it is drawn: the held marker's note over it, a live preview.
  bool get takesAll => false;

  /// cursor is the pointer's look while it is under way, shown over what
  /// the tool in hand or the hover would show, or null to leave it to the
  /// stage: see _cursor.
  MouseCursor? get cursor => null;
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
  /// is part of that step. [clicked] is whether the press ended as a click
  /// (see StageGesture.release).
  void _endGesture(StageGesture gesture, Offset at,
      {required bool cancelled, required bool clicked}) {
    // Rebuilt, so what showed it was under way (its cursor, what is drawn
    // for it) goes with it, whether or not its end changes anything else.
    setState(() => _gesture = null);
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
      _settle(stage, clicked: clicked, cancelled: false);

  /// cancel makes no click, except one made however the press ends: an
  /// instrument's key, let go.
  @override
  void cancel(CanvasStageState stage) =>
      _settle(stage, clicked: false, cancelled: true);

  /// _settle makes or drops each click [carried] as the press ends. A click
  /// that is made and ends the release stops there.
  void _settle(CanvasStageState stage,
      {required bool clicked, required bool cancelled}) {
    for (var c in carried) {
      if (!c.madeBy(stage, clicked: clicked, cancelled: cancelled)) {
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
  MouseCursor get cursor => SystemMouseCursors.grabbing;

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

  /// release selects what the box takes in. The box goes with the
  /// gesture, in the rebuild every gesture's end makes.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._selectWithin(box);

  @override
  void cancel(CanvasStageState stage) {}
}

/// _GuideDrag is a guide line moved, or a new one pulled from a ruler.
class _GuideDrag extends StageGesture {
  _GuideDrag(this.index, Snapper this.snapper)
      : pulled = null,
        unpulled = null;

  /// _GuideDrag.pulled is a new guide along [pulled] pulled out of a ruler,
  /// from a canvas that was [unpulled]. It is put down by the first move, so
  /// a click makes none.
  _GuideDrag.pulled(GuideAxis this.pulled, CanvasDocument this.unpulled)
      : index = -1;

  /// index is the guide's place in the document's list of guides, or -1
  /// for a pulled one not yet put down.
  int index;

  /// snapper is what the guide lands on, leaving out the guide itself:
  /// made at the press for a guide on the page, and as a pulled one is put
  /// down, since putting it down shows the guides.
  Snapper? snapper;

  /// pulled is the axis of a guide pulled out of a ruler, or null for one
  /// already on the page.
  final GuideAxis? pulled;

  /// unpulled is the document as the press on the ruler found it, which a
  /// pulled guide let go off the page puts back; null for one already on
  /// the page.
  final CanvasDocument? unpulled;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  MouseCursor get cursor => SystemMouseCursors.grabbing;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    if (pulled case var axis? when index < 0) {
      index = stage._putGuide(axis, doc);
      snapper = stage._guideSnapper(index);
    }
    if (snapper case var s?) stage._applyGuide(index, doc, s);
  }

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._finishGuide(index, unpulled: unpulled);

  /// cancel drops the guide as a release does: a cancel keeps what the drag
  /// did, so a guide dragged off the page goes all the same.
  @override
  void cancel(CanvasStageState stage) =>
      stage._finishGuide(index, unpulled: unpulled);
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
  /// is an undo step of its own, made there. The line goes with the
  /// gesture.
  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage._dropFlow(fromId, at);

  @override
  void cancel(CanvasStageState stage) {}
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
    required this.seen,
    required this.rotation,
    required this.snapper,
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

  /// seen is the upright box each element is seen in, turned and slanted
  /// as it is drawn: see _seenBounds.
  final Map<String, Rect> seen;

  /// rotation is each element's turn, in degrees.
  final Map<String, double> rotation;

  /// snapper is what a move or a resize lands on: the page, the grid, the
  /// guides and everything not selected, as they were at the press.
  final Snapper snapper;

  /// seenBox is the whole selection's box as it is seen, which a move
  /// snaps by; visualBox the box its handles are on, which a resize is
  /// measured against and snaps by. Null for nothing selected.
  late final Rect? seenBox = _unionOf(seen.values);
  late final Rect? visualBox = _unionOf(visual.values);
}

/// _unionOf is the least box that holds every one of [boxes], or null for
/// none.
Rect? _unionOf(Iterable<Rect> boxes) =>
    boxes.isEmpty ? null : boxes.reduce((a, b) => a.expandToInclude(b));

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

  /// snapped is the lines a move or resize is caught on, which the stage
  /// draws while it runs (see _stagePainter); it goes with the gesture.
  SnapLines snapped = SnapLines.none;

  /// _caught makes [lines] the snap mark, rebuilding the stage when they
  /// differ, so the mark never waits on a change to the document, which a
  /// step need not make: locked elements in the selection stay put.
  void _caught(CanvasStageState stage, SnapLines lines) {
    if (lines == snapped) return;
    stage.setState(() => snapped = lines);
  }

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
  MouseCursor get cursor => SystemMouseCursors.move;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    if (click case var c?
        when (at - stage._pressedAt).distance >
                CanvasStageState._buttonClickSlop &&
            !c.travelled(stage)) {
      click = null;
    }
    if (!stage._hasTravelled(at)) return;
    _caught(stage, stage._applyMove(doc - stage._dragStart, start));
  }
}

/// _BoxResize is the selection resized by one of its handles, [handle].
class _BoxResize extends _BoxDrag {
  _BoxResize(super.start, this.handle);

  /// handle is the handle held.
  final StageHandle handle;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      _caught(stage, stage._applyResize(doc - stage._dragStart, handle, start));
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
  MouseCursor get cursor => SystemMouseCursors.grabbing;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyRotate(doc, start);
}

/// _CopiesDrag is copies of a reused element moved on their own: those
/// picked, or the new ones an Alt-drag makes of them. One undo step, opened
/// as it begins (_pressCopy).
class _CopiesDrag extends StageGesture with _CarriesClicks {
  _CopiesDrag(this.start, this.dragged, {this.click, this.copying});

  /// start is the element's copies as they were when the drag began, which
  /// every step works from.
  InstanceSet? start;

  /// dragged is which of them move, by id.
  Set<String> dragged;

  /// copying is the copies an Alt-press copies, by id, until it has: they
  /// are copied as the press travels and the new ones dragged (see
  /// _moveCopies), so a press that never travels makes no copy.
  Set<String>? copying;

  /// click is the click an earlier step of the press armed on the
  /// element's own controls, if any: a Code panel's code, opened for
  /// typing if the press stays put.
  final PendingClick? click;

  @override
  Iterable<PendingClick> get carried => [click].nonNulls;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._moveCopies(this, doc - stage._dragStart);
}

/// _CopyBoxDrag is the one picked copy of a reused element sized or turned
/// by its own box (see _oneCopy), by the copy's own Size and Turn, not the
/// element's. One undo step, opened as it begins (_beginCopyBox).
class _CopyBoxDrag extends StageGesture {
  _CopyBoxDrag(
      {required this.turning,
      required this.pivot,
      required this.size,
      required this.turn});

  /// turning is whether the box's turning handle was taken; otherwise one
  /// of its corners or sides, which size it.
  final bool turning;

  /// pivot is the copy's anchor, which it is sized and turned about and
  /// which stays put (see CanvasElement.boundsWith).
  final Offset pivot;

  /// size and turn are the copy's own Size and Turn when it was pressed.
  final double size, turn;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyCopyBox(this, doc);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _SpritePaint is a stroke on the Sprite being painted (see
/// sprite_painting.dart). The session keeps the stroke as one change of its
/// own when the pen lifts, so the gesture opens no undo step.
class _SpritePaint extends StageGesture {
  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) {
    if (stage.controller.spritePaint case var session?) {
      unawaited(session.strokeTo(doc));
    }
  }

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      _lift(stage);

  /// cancel lifts the pen as a release does: a cancel keeps what the drag
  /// painted.
  @override
  void cancel(CanvasStageState stage) => _lift(stage);

  /// _lift lifts the session's pen, if the sprite is still being painted.
  void _lift(CanvasStageState stage) {
    if (stage.controller.spritePaint case var session?) {
      unawaited(session.strokeEnd());
    }
  }
}

/// _TilePaint is a stroke on the Tile map being painted (see
/// tile_painting.dart). As for a sprite, the session keeps the stroke as
/// one change of its own when the pen lifts.
class _TilePaint extends StageGesture {
  @override
  bool get opensUndoStep => false;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage.controller.tilePaint?.strokeTo(doc);

  @override
  void release(CanvasStageState stage, Offset at,
          {required bool travelled, required bool clicked}) =>
      stage.controller.tilePaint?.strokeEnd();

  /// cancel lifts the pen as a release does: a cancel keeps what the drag
  /// laid.
  @override
  void cancel(CanvasStageState stage) =>
      stage.controller.tilePaint?.strokeEnd();
}

part of 'canvas_stage.dart';

// A picture piece of a text element (TextItem.icon), handled on the canvas by
// a box of its own. Double-clicking the picture, or picking it in the text's
// Layers, gives it the selection's handles: dragged inside it moves (its
// side and down), a corner sizes it, the round handle turns it, and Delete
// takes it out. Pressing anywhere else on the element goes back to the
// element's own box. The three drags are cases of StageGesture, at the
// foot. Part of CanvasStageState: its fields, lifecycle and build are in
// canvas_stage.dart.

extension StageTextPieces on CanvasStageState {
  (TextElement, int)? get _onePiece => pickedPiece(controller);

  /// _pieceBounds is the picture's square on the page, upright: its middle
  /// turned with the element, its own turn left to _rotationOfSelection.
  Rect _pieceBounds(TextElement e, int i) {
    var bounds = _hit.posed(e);
    var rect = e.items[i].box.inner(textItemRects(e, bounds)[i]);
    var turn = _pieceElementTurn(e) * math.pi / 180;
    var d = rect.center - bounds.center;
    var c = math.cos(turn), s = math.sin(turn);
    var centre =
        bounds.center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
    return Rect.fromCenter(
        center: centre, width: rect.width, height: rect.height);
  }

  double _pieceElementTurn(TextElement e) =>
      e.movedRotationAt(controller.frame, controller.document,
          live: controller.liveMotion);

  /// _pieceTurn is the picture's turn on the page, in degrees: the element's
  /// and its own.
  double _pieceTurn(TextElement e, int i) =>
      _pieceElementTurn(e) + (e.items[i].icon?.turn ?? 0);

  /// _pressPiece starts on the picked picture piece's box, if the press is
  /// on it: a handle sizes or turns it, inside moves it. A press elsewhere
  /// puts the box away, and is the element's. Answers whether it was taken.
  bool _pressPiece(Offset stage, Offset doc) {
    var piece = _onePiece;
    if (piece == null) return false;
    var (e, i) = piece;
    var start = e.items[i], box = _pieceBounds(e, i);
    var handle = _hitHandle(stage);
    if (handle != null) {
      _beginPiece(handle == StageHandle.rotate
          ? _PieceTurn(start, box.center)
          : _PieceSize(start, box.center));
      return true;
    }
    var local = BoxFrame(_pieceTurn(e, i), 0, 0).invert(doc - box.center);
    if (local.dx.abs() <= box.width / 2 && local.dy.abs() <= box.height / 2) {
      _beginPiece(_PieceMove(start, box.center));
      return true;
    }
    controller.pickTextLayer(e.id, null);
    return false;
  }

  /// _beginPiece makes [drag] the gesture under way and opens its undo
  /// step.
  void _beginPiece(_PieceDrag drag) {
    _gesture = drag;
    controller.beginInteraction();
  }

  /// _applyPiece puts the picked picture as [drag] makes it with the
  /// pointer at [doc], as a step of the drag's undo step.
  void _applyPiece(_PieceDrag drag, Offset doc) {
    var piece = _onePiece;
    if (piece == null) return;
    var (e, i) = piece;
    var moved = drag._moved(this, e, i, doc);
    if (moved == null) return;
    controller.replaceElement(
        e.copyWith(items: [
          for (var (n, it) in e.items.indexed) n == i ? moved : it,
        ]),
        transient: true);
  }

  /// _keptMiddle is [sized] moved so its middle is where [start]'s was: a
  /// slot holds a piece by an edge, so it would otherwise grow away from
  /// it, out from under the handle being dragged.
  TextItem _keptMiddle(TextElement e, int i, TextItem start, TextItem sized) {
    var bounds = e.bounds;
    TextElement put(TextItem it) => e.copyWith(items: [
          for (var (n, x) in e.items.indexed) n == i ? it : x,
        ]);
    var was = textItemRects(put(start), bounds)[i].center;
    var now = textItemRects(put(sized), bounds)[i].center;
    var d = was - now;
    var across = start.slot.across == TextAlignSpec.right ? -1 : 1;
    return sized.copyWith(
        side: sized.side + d.dx * across, down: sized.down + d.dy);
  }
}

/// _PieceDrag is the picked picture piece of a text taken by its own box:
/// moved from inside, sized by a corner or side, or turned by the round
/// handle. Each is one undo step, opened as it begins (_beginPiece), and
/// works from the piece as the press found it, so that rounding does not
/// build up.
sealed class _PieceDrag extends StageGesture {
  _PieceDrag(this.start, this.middle);

  /// start is the piece as it was when its box was pressed.
  final TextItem start;

  /// middle is the piece's middle on the page at the press: what it is
  /// sized and turned about.
  final Offset middle;

  @override
  bool get opensUndoStep => true;

  @override
  bool get waitsToTravel => true;

  @override
  void move(CanvasStageState stage, Offset at, Offset doc) =>
      stage._applyPiece(this, doc);

  /// _moved is piece [i] of [e] with the pointer at [doc], worked out from
  /// [start], or null to leave it as it is.
  TextItem? _moved(CanvasStageState stage, TextElement e, int i, Offset doc);

  @override
  void release(CanvasStageState stage, Offset at,
      {required bool travelled, required bool clicked}) {}

  @override
  void cancel(CanvasStageState stage) {}
}

/// _PieceMove is the picture moved by the drag in the element's own frame,
/// along one axis with Shift.
class _PieceMove extends _PieceDrag {
  _PieceMove(super.start, super.middle);

  @override
  TextItem _moved(CanvasStageState stage, TextElement e, int i, Offset doc) {
    var delta = doc - stage._dragStart;
    if (stage._shiftHeld) {
      delta = delta.dx.abs() >= delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    return start.movedBy(delta, stage._pieceElementTurn(e));
  }
}

/// _PieceSize is the picture sized by how much farther from its middle the
/// pointer is along the line pressed on.
class _PieceSize extends _PieceDrag {
  _PieceSize(super.start, super.middle);

  @override
  TextItem? _moved(CanvasStageState stage, TextElement e, int i, Offset doc) {
    var icon = start.icon!;
    var from = stage._dragStart - middle, to = doc - middle;
    var along = from.distanceSquared;
    if (along < 1e-6) return null;
    var f = (to.dx * from.dx + to.dy * from.dy) / along;
    return stage._keptMiddle(
        e,
        i,
        start,
        start.copyWith(
            icon: icon.copyWith(size: (icon.size * f).clamp(4.0, 4000.0))));
  }
}

/// _PieceTurn is the picture turned by the angle swept about its middle, in
/// 15-degree steps with Shift.
class _PieceTurn extends _PieceDrag {
  _PieceTurn(super.start, super.middle);

  @override
  TextItem _moved(CanvasStageState stage, TextElement e, int i, Offset doc) {
    var icon = start.icon!;
    var from = stage._dragStart - middle, to = doc - middle;
    var swept = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
        180 /
        math.pi;
    var turn = icon.turn + swept;
    if (stage._shiftHeld) turn = steppedTurn(turn);
    turn = (turn + 180) % 360 - 180;
    return start.copyWith(icon: icon.copyWith(turn: turn));
  }
}

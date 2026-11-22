part of 'canvas_stage.dart';

// A picture piece of a text element (TextItem.icon), handled on the canvas by
// a box of its own. Double-clicking the picture, or picking it in the text's
// Layers, gives it the selection's handles: dragged inside it moves (its
// side and down), a corner sizes it, the round handle turns it, and Delete
// takes it out. Pressing anywhere else on the element goes back to the
// element's own box. Part of CanvasStageState: its fields, lifecycle and
// build are in canvas_stage.dart.

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
    var handle = _hitHandle(stage);
    if (handle != null) {
      _beginPiece(
          e,
          i,
          handle == StageHandle.rotate
              ? _DragMode.pieceTurn
              : _DragMode.pieceSize);
      return true;
    }
    var box = _pieceBounds(e, i);
    var local = BoxFrame(_pieceTurn(e, i), 0, 0).invert(doc - box.center);
    if (local.dx.abs() <= box.width / 2 && local.dy.abs() <= box.height / 2) {
      _beginPiece(e, i, _DragMode.pieceMove);
      return true;
    }
    controller.pickTextLayer(e.id, null);
    return false;
  }

  void _beginPiece(TextElement e, int i, _DragMode mode) {
    _mode = mode;
    _pieceStart = e.items[i];
    _pieceMiddle = _pieceBounds(e, i).center;
    controller.beginInteraction();
  }

  /// _applyPiece moves, sizes or turns the picture as the pointer is dragged
  /// to [doc]: moved by the drag in the element's own frame (along one axis
  /// with Shift); sized by how much farther from its middle the pointer is
  /// along the line pressed on; turned by the angle swept about its middle,
  /// in 15-degree steps with Shift.
  void _applyPiece(Offset doc) {
    var piece = _onePiece, start = _pieceStart;
    if (piece == null || start == null) return;
    var (e, i) = piece;
    var icon = start.icon!;
    TextItem moved;
    switch (_mode) {
      case _DragMode.pieceMove:
        var delta = doc - _dragStart;
        if (_shiftHeld) {
          delta = delta.dx.abs() >= delta.dy.abs()
              ? Offset(delta.dx, 0)
              : Offset(0, delta.dy);
        }
        var local = BoxFrame(_pieceElementTurn(e), 0, 0).invert(delta);
        // A piece held to the right-hand edge counts its side leftwards.
        var across = start.slot.across == TextAlignSpec.right ? -1 : 1;
        moved = start.copyWith(
            side: start.side + local.dx * across, down: start.down + local.dy);
      case _DragMode.pieceTurn:
        var from = _dragStart - _pieceMiddle, to = doc - _pieceMiddle;
        var swept = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
            180 /
            math.pi;
        var turn = icon.turn + swept;
        if (_shiftHeld) turn = steppedTurn(turn);
        turn = (turn + 180) % 360 - 180;
        moved = start.copyWith(icon: icon.copyWith(turn: turn));
      default:
        var from = _dragStart - _pieceMiddle, to = doc - _pieceMiddle;
        var along = from.distanceSquared;
        if (along < 1e-6) return;
        var f = (to.dx * from.dx + to.dy * from.dy) / along;
        moved = _keptMiddle(
            e,
            i,
            start,
            start.copyWith(
                icon: icon.copyWith(size: (icon.size * f).clamp(4.0, 4000.0))));
    }
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

  /// _pressPlayTask ticks a play task's step the student marks, or starts it
  /// again, if the press is on one. Not a text piece, but as small a thing
  /// pressed inside an element. Answers whether it was taken.
  bool _pressPlayTask(PlayTaskElement e, Offset doc) {
    // From where it is drawn now, which its motion may have moved.
    var at = doc - _hit.posed(e).topLeft;
    var show = controller.playTaskShowFor(e);
    if (playTaskAgainAt(e, at, show)) {
      controller.startPlayTaskAgain(e);
    } else if (playTaskMarkAt(e, at, show) case var i?) {
      controller.tickPlayStep(e, i);
    } else {
      return false;
    }
    _mode = _DragMode.none;
    return true;
  }
}

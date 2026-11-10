part of '../canvas_controller.dart';

// The Cast (Ken, 2026-11-10): elements kept once for the whole document --
// a game's hero -- with linked copies in its scenes, each its own place,
// size and doings, the rest shared. See model/cast.dart.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasCast on CanvasController {
  /// cast is the document's Cast.
  List<CanvasElement> get cast => _document.cast;

  /// castOf is the Cast member element [id] on the canvas being edited is a
  /// copy of, or null.
  CanvasElement? castOf(String id) {
    var e = _document.elementById(id);
    return e == null ? null : castMember(_document, e.base.cast);
  }

  /// castCopiesOf is how many copies of member [id] there are, everywhere.
  int castCopiesOf(String id) => castCopies(_document, id);

  /// addToCast makes element [id] on the canvas being edited a Cast member,
  /// and links it and every copy of it in the other scenes and on the
  /// master (same id or kind, or the same 3D character): one step to undo.
  /// The member's id, or null where there is no such element or it is in
  /// the Cast already.
  String? addToCast(String id) {
    var e = _document.elementById(id);
    if (e == null || e.base.cast.isNotEmpty) return null;
    var (next, member) = castAdded(_document, e, id: newElementId());
    apply(next);
    return member;
  }

  /// unlinkFromCast makes copy [id] its own: as it is, linked no more.
  void unlinkFromCast(String id) => apply(castUnlinked(_document, id));

  /// removeFromCast takes member [id] out of the Cast; every copy stays, as
  /// it is, its own.
  void removeFromCast(String id) => apply(castRemoved(_document, id));

  /// placeFromCast puts a linked copy of member [id] on the canvas being
  /// edited, at [center] -- the page's middle where none is given -- as the
  /// member is, and picks it.
  void placeFromCast(String id, {Offset? center}) {
    var m = castMember(_document, id);
    if (m == null) return;
    var at = center ?? _document.size.rect.center;
    var copy = m.rebase(m.base.copyWith(
        id: newElementId(),
        cast: id,
        x: at.dx - m.width / 2,
        y: at.dy - m.height / 2));
    addElement(copy);
  }
}

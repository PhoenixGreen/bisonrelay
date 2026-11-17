part of '../canvas_controller.dart';

// The Cast: elements kept once for the whole document (a game's hero), with
// linked copies in its scenes, each with its own place, size and doings,
// the rest shared. See model/cast.dart. Part of CanvasController.

extension CanvasCast on CanvasController {
  List<CanvasElement> get cast => _document.cast;

  /// castOf is the Cast member element [id] on the canvas being edited is a
  /// copy of, or null.
  CanvasElement? castOf(String id) {
    var e = _document.elementById(id);
    return e == null ? null : castMember(_document, e.base.cast);
  }

  /// castCopiesOf is how many copies of member [id] there are, everywhere.
  int castCopiesOf(String id) => castCopies(_document, id);

  /// addToCast makes element [id] on the canvas being edited a Cast member
  /// and links it and every copy of it in other scenes and on the master
  /// (same id or kind, or the same 3D character), as one undo step. Returns
  /// the member's id, or null if there is no such element or it is already
  /// a member.
  String? addToCast(String id) {
    var e = _document.elementById(id);
    if (e == null || e.base.cast.isNotEmpty) return null;
    var (next, member) = castAdded(_document, e, id: newElementId());
    apply(next);
    return member;
  }

  /// unlinkFromCast makes copy [id] its own, as it is.
  void unlinkFromCast(String id) => apply(castUnlinked(_document, id));

  /// removeFromCast takes member [id] out of the Cast; every copy stays as
  /// its own.
  void removeFromCast(String id) => apply(castRemoved(_document, id));

  /// placeFromCast puts a linked copy of member [id] on the canvas being
  /// edited at [center] (the page's middle by default), and picks it.
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

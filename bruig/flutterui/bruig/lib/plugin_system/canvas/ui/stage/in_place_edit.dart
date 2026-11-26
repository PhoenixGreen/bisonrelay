import 'dart:ui';

/// InPlaceEdit is what the stage has open for typing where it is drawn: a
/// text's words, a table's cell, or a counter's Set field. One at a time, so
/// one value: opening one closes another, and a new kind is a new case each
/// switch over it is asked for.
///
/// Each names its element by id, since the element is replaced on every
/// keystroke.
sealed class InPlaceEdit {
  /// elementId is the element typed into.
  final String elementId;

  const InPlaceEdit(this.elementId);
}

/// TextEdit is a text element's words typed into, opened by a second click.
class TextEdit extends InPlaceEdit {
  /// itemId is the id of the element's extra piece typed into, or null for
  /// its own paragraph. See TextItem.
  final String? itemId;

  /// click is where the click that opened the editor landed, globally, so
  /// the caret goes there. See CanvasTextEditor.clickAt.
  final Offset? click;

  /// frozenRect is where the editor opened, in document space, once worked
  /// out: for text on a line the box follows the letters, which move as you
  /// type, so it is kept where it was. Null until the editor is first built.
  final Rect? frozenRect;

  const TextEdit(super.elementId, {this.itemId, this.click, this.frozenRect});

  /// frozenAt is this edit with its box kept at [rect].
  TextEdit frozenAt(Rect rect) =>
      TextEdit(elementId, itemId: itemId, click: click, frozenRect: rect);
}

/// CellEdit is a table's cell typed into: by row and column, since a cell
/// has no identity of its own.
class CellEdit extends InPlaceEdit {
  /// row is the cell's row.
  final int row;

  /// column is the cell's column.
  final int column;

  const CellEdit(super.elementId, {required this.row, required this.column});
}

/// CounterSet is the field on a run's Set button, typed into in
/// place of a dialog that would cover the counter.
class CounterSet extends InPlaceEdit {
  /// at is which of the counter's buttons the field is on.
  final int at;

  const CounterSet(super.elementId, {required this.at});
}

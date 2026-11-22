import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart'
    show baseLayerId;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show isTypingInAField;
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart'
    show ImageTool;
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart'
    show VectorTool;
import 'package:bruig/plugin_system/canvas/ui/stage/picked_parts.dart'
    show
        nudgeWarpPicks,
        nudgingWarp,
        pickedPiece,
        removableLayoutCell,
        removePickedLayoutCell,
        removePickedPiece;

// stage_keys.dart is every key the Canvas page answers, in one table: what
// is pressed, when it applies, and what it does. Three handlers hand their
// keys here, each saying where the keyboard is (ShortcutReach): the canvas
// (canvas_stage.dart), the play bar and timeline (transportKey in
// play_bar.dart), and the page round them (space_bar.dart). The first line
// that means the key now is the one done. Two things take the keyboard for
// themselves before any of this: a field being typed in, the text editor on
// the canvas among them (canvas_text_editor.dart), and a running game
// (CanvasController.gameKey in controller/game.dart).

/// ShortcutReach is how far out on the page a shortcut is heard.
enum ShortcutReach {
  /// canvas is only while the canvas itself has the keyboard.
  canvas,

  /// transport is only while the play bar or the timeline has it.
  transport,

  /// page is anywhere on the Canvas page: after the canvas's or the
  /// transport's own lines when one of them has the keyboard, alone when
  /// something else on the page does.
  page,
}

/// KeyHeld is what a shortcut does while its key is held down.
enum KeyHeld {
  /// again does it again on each repeat: an arrow nudges on.
  again,

  /// taken does it once, and takes the repeats and the release too, doing
  /// nothing with them, so none reaches the focused button: Space.
  taken,

  /// once does it once, and leaves the repeats and the release to whatever
  /// is further out.
  once,
}

/// CanvasShortcut is one key the Canvas page answers: what is pressed, when
/// it applies, what it does (said in words, for a list of shortcuts), and
/// the doing of it.
class CanvasShortcut {
  /// keys are the keys that mean it, any one of them (Delete and Backspace).
  final List<LogicalKeyboardKey> keys;

  /// command, shift and alt are the modifiers it needs: true, held; false,
  /// not held; null, either way. Command is Cmd or Control, so a Mac with a
  /// PC keyboard works too.
  final bool? command, shift, alt;

  /// held is what holding the key down does after the first press.
  final KeyHeld held;

  /// reach is how far out it is heard: the whole page, or only while the
  /// canvas, or the play bar and timeline, have the keyboard.
  final ShortcutReach reach;

  /// when is whether it applies now; the first in the table that does is
  /// the one done.
  final bool Function(CanvasController c) when;

  /// does is what it does, in a few words.
  final String does;

  /// act does it.
  final void Function(CanvasController c, KeyEvent event) act;

  const CanvasShortcut({
    required this.keys,
    this.command = false,
    this.shift,
    this.alt,
    this.held = KeyHeld.again,
    this.reach = ShortcutReach.canvas,
    this.when = always,
    required this.does,
    required this.act,
  });

  /// heardAt is whether a key handed in from [where] can mean it.
  bool heardAt(ShortcutReach where) =>
      reach == where || reach == ShortcutReach.page;
}

/// always is the [CanvasShortcut.when] of a line that always applies.
/// Named, so that a test can tell when a line takes every press of its keys
/// from those after it.
bool always(CanvasController c) => true;

/// canvasKey finds the first shortcut that [event] means now, heard from
/// [reach], and does it: handled, or ignored when there is none.
KeyEventResult canvasKey(CanvasController c, KeyEvent event,
    {required ShortcutReach reach}) {
  // A running game has every key: Space jumps, the arrows run, Escape
  // stops it. See CanvasController.gameKey.
  if (c.gaming) return KeyEventResult.handled;
  // These handlers run before the app's text-editing keys, so they step
  // aside while somebody types, in the band, a sidebar or a dialog.
  if (isTypingInAField()) return KeyEventResult.ignored;
  var line = _lineFor(c, event.logicalKey, reach);
  if (line == null) return KeyEventResult.ignored;
  switch (event) {
    case KeyDownEvent():
    case KeyRepeatEvent() when line.held == KeyHeld.again:
      line.act(c, event);
      return KeyEventResult.handled;
    case _ when line.held == KeyHeld.taken:
      return KeyEventResult.handled;
    default:
      return KeyEventResult.ignored;
  }
}

/// _lineFor is the first line of canvasShortcuts that [key] means now, with
/// the modifiers held, heard from [reach].
CanvasShortcut? _lineFor(
    CanvasController c, LogicalKeyboardKey key, ShortcutReach reach) {
  var keys = HardwareKeyboard.instance;
  var command = keys.isMetaPressed || keys.isControlPressed;
  bool fits(bool? wanted, bool held) => wanted == null || wanted == held;
  for (var line in canvasShortcuts) {
    if (!line.heardAt(reach) || !line.keys.contains(key)) continue;
    if (!fits(line.command, command) ||
        !fits(line.shift, keys.isShiftPressed) ||
        !fits(line.alt, keys.isAltPressed)) {
      continue;
    }
    if (line.when(c)) return line;
  }
  return null;
}

/// canvasShortcuts is every key the page answers, in the order they are
/// tried. A key with several meanings (Escape, Delete, the arrows) is
/// several lines, the most particular first. The canvas's lines come
/// before the page's, so the canvas has first say while it has the
/// keyboard.
final List<CanvasShortcut> canvasShortcuts = [
  // While a drawing is edited, Command A, C, X and V act on its points, and
  // with none picked do nothing: never the whole drawing.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyA],
      command: true,
      when: _drawing,
      does: "Pick every point of the drawing",
      act: (c, _) => c.pickAllVectorPoints()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyC],
      command: true,
      when: _drawing,
      does: "Copy the drawing's picked points",
      act: (c, _) => c.copyVectorPoints()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyX],
      command: true,
      when: _drawing,
      does: "Cut the drawing's picked points",
      act: (c, _) => c.cutVectorPoints()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyV],
      command: true,
      when: _drawing,
      does: "Paste points into the drawing",
      act: (c, _) => c.pasteVectorPoints()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyC],
      command: true,
      does: "Copy",
      act: (c, _) => c.copySelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyX],
      command: true,
      does: "Cut",
      act: (c, _) => c.cutSelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyV],
      command: true,
      does: "Paste",
      act: (c, _) => c.paste()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyD],
      command: true,
      does: "Duplicate the selection",
      act: (c, _) => c.duplicateSelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyA],
      command: true,
      does: "Select every element",
      act: (c, _) => c.selectAll()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyZ],
      command: true,
      shift: false,
      does: "Undo",
      act: (c, _) => c.undo()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyZ],
      command: true,
      shift: true,
      does: "Redo",
      act: (c, _) => c.redo()),

  // The arrows: a warp grid's picked points; else the selection, or the
  // frame with nothing selected, Alt asking for the other one. Shift is ten
  // times as far; up and down step the frame by ten.
  CanvasShortcut(
      keys: _arrows,
      when: nudgingWarp,
      does: "Move the warp grid's picked points (Shift: ten)",
      act: (c, e) => nudgeWarpPicks(c, _nudge(e))),
  CanvasShortcut(
      keys: _arrows,
      alt: false,
      when: (c) => c.selection.isNotEmpty,
      does: "Move the selection (Shift: ten)",
      act: (c, e) => c.nudgeSelected(_nudge(e).dx, _nudge(e).dy)),
  CanvasShortcut(
      keys: _arrows,
      alt: true,
      when: (c) => c.selection.isEmpty,
      does: "Move the selection (Shift: ten)",
      act: (c, e) => c.nudgeSelected(_nudge(e).dx, _nudge(e).dy)),
  CanvasShortcut(
      keys: _arrows,
      does: "Step the frame: left and right one, up and down ten",
      act: (c, e) => c.stepFrame(_frames(e))),

  // The page's and the 3D stage's letters, unless a picture or drawing is
  // edited: those have letters of their own.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyL],
      alt: false,
      when: _plain,
      does: "Lock or unlock the page",
      act: (c, _) => c.pageLocked = !c.pageLocked),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyS],
      shift: true,
      alt: false,
      when: _plain,
      does: "Snap on or off",
      act: (c, _) => c.canvasSnap = !c.canvasSnap),
  for (var t in StageTool.values)
    CanvasShortcut(
        keys: [_letter(t.key)],
        alt: false,
        when: _onStage,
        does: "3D stage: ${t.label}",
        act: (c, _) => c.stageTool = t),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyF],
      alt: false,
      when: _onStage,
      does: "3D stage: frame the selection",
      act: (c, _) => c.frameSelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.home],
      alt: false,
      when: _onStage,
      does: "3D stage: reset the camera",
      act: (c, _) => c.resetCamera()),

  CanvasShortcut(
      keys: const [LogicalKeyboardKey.space],
      held: KeyHeld.taken,
      does: "Play or stop",
      act: (c, _) => c.togglePlay()),

  // Delete takes the smallest thing picked: a picture's layer, picked
  // copies, a text's picture piece, a Layout's cell, then the selection.
  CanvasShortcut(
      keys: _delete,
      when: (c) => c.editingImage != null && c.imageLayer != baseLayerId,
      does: "Delete the picture's picked layer",
      act: (c, _) => c.removeImageLayer(c.imageLayer)),
  CanvasShortcut(
      keys: _delete,
      when: (c) => c.selected != null && c.copiesPicked(c.selected!.id),
      does: "Delete the picked copies",
      act: (c, _) {
        var id = c.selected!.id;
        c.beginInteraction();
        c.removeCopies(id, c.pickedCopiesOf(id));
        c.endInteraction();
      }),
  CanvasShortcut(
      keys: _delete,
      when: (c) => pickedPiece(c) != null,
      does: "Delete the text's picked picture piece",
      act: (c, _) => removePickedPiece(c)),
  CanvasShortcut(
      keys: _delete,
      when: (c) => removableLayoutCell(c) != null,
      does: "Delete the Layout's picked cell",
      act: (c, _) => removePickedLayoutCell(c)),
  CanvasShortcut(
      keys: _delete,
      does: "Delete the selection",
      act: (c, _) => c.deleteSelected()),

  CanvasShortcut(
      keys: _enter,
      when: (c) => c.vectorPenShape >= 0,
      does: "Finish the pen's shape",
      act: (c, _) => c.finishPenShape()),

  // A picture's tools, while its layers are open.
  for (var t in ImageTool.values)
    CanvasShortcut(
        keys: [_letter(t.key)],
        when: _picture,
        does: "Picture: ${t.label}",
        act: (c, _) => c.imageTool = t),
  // X inverts the mask tools, as it swaps colours elsewhere.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyX],
      when: _picture,
      does: "Picture: mask tools hide or show",
      act: (c, _) => c.maskHide = !c.maskHide),
  // The brackets size the brush, as in every painting program.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.bracketLeft],
      when: _picture,
      does: "Picture: a smaller brush",
      act: (c, _) => _sizeBrush(c, bigger: false)),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.bracketRight],
      when: _picture,
      does: "Picture: a larger brush",
      act: (c, _) => _sizeBrush(c, bigger: true)),

  // A drawing's tools, while it is edited. A tool's key again goes back to
  // picking points, except Select shapes', which is picking already.
  for (var t in VectorTool.values)
    if (t.key case var key?)
      CanvasShortcut(
          keys: [_letter(key)],
          when: _drawing,
          does: "Drawing: ${t.label}",
          act: (c, _) => c.vectorTool =
              c.vectorTool == t && t != VectorTool.selectShapes
                  ? VectorTool.select
                  : t),

  // Setting a layout's reading order: Enter keeps it, Escape does not.
  CanvasShortcut(
      keys: _enter,
      when: (c) => c.orderingLayout != null,
      does: "Keep the reading order",
      act: (c, _) => c.finishReadingOrder()),

  // Escape lets go of one thing at a time, the smallest first.
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.orderingLayout != null,
      does: "Drop the reading order",
      act: (c, _) => c.finishReadingOrder(keep: false)),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.warpLayer != null && c.warpPicks.isNotEmpty,
      does: "Let go of the warp grid's picked points",
      act: (c, _) => c.warpPicks = const {}),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.warpLayer != null,
      does: "Put the warp grid away",
      act: (c, _) => c.editWarp("", "", on: false)),
  CanvasShortcut(
      keys: _escape,
      when: (c) =>
          _picture(c) && c.imageTool == ImageTool.clone && c.cloneFrom != null,
      does: "Forget where Clone copies from",
      act: (c, _) => c.cloneFrom = null),
  CanvasShortcut(
      keys: _escape,
      when: (c) => _picture(c) && c.imageTool != ImageTool.move,
      does: "Picture: back to Move",
      act: (c, _) => c.imageTool = ImageTool.move),
  CanvasShortcut(
      keys: _escape,
      when: _picture,
      does: "Close the picture's layers",
      act: (c, _) => c.editImage(null)),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.vectorEditing != null && c.vectorPenShape >= 0,
      does: "Finish the pen's shape",
      act: (c, _) => c.finishPenShape()),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.vectorEditing != null && c.vectorTool != VectorTool.select,
      does: "Drawing: back to Select points",
      act: (c, _) => c.vectorTool = VectorTool.select),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.vectorEditing != null && c.vectorPicks.isNotEmpty,
      does: "Let go of the drawing's picked points",
      act: (c, _) => c.pickVectorPoint(null)),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.vectorEditing != null,
      does: "Stop editing the drawing",
      act: (c, _) => c.editVector(null)),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.placingCopies != null,
      does: "Stop placing copies",
      act: (c, _) => c.placingCopies = null),
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.selected != null && c.copiesPicked(c.selected!.id),
      does: "Back to all the copies",
      act: (c, _) => c.pickCopies(c.selected!.id, const {})),
  // Only with something to clear: else Escape goes on to the page's.
  CanvasShortcut(
      keys: _escape,
      when: (c) => c.somethingSelected,
      does: "Clear the selection",
      act: (c, _) => c.clearSelection()),

  // The play bar's and timeline's own: Space and the arrows with any
  // modifier, so that Flutter does not spend the arrows moving the focus
  // between the bar's buttons.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.space],
      command: null,
      held: KeyHeld.taken,
      reach: ShortcutReach.transport,
      does: "Play or stop",
      act: (c, _) => c.togglePlay()),
  CanvasShortcut(
      keys: _arrows,
      command: null,
      reach: ShortcutReach.transport,
      does: "Step the frame: left and right one, up and down ten",
      act: (c, e) => c.stepFrame(_frames(e))),

  // Anywhere on the page. Copy, paste, undo and Delete here are for when
  // the canvas does not have the keyboard: after a click on the timeline, a
  // picked sound is copied, pasted on its channel at the playhead, or
  // deleted.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.space],
      alt: false,
      held: KeyHeld.taken,
      reach: ShortcutReach.page,
      does: "Play or stop",
      act: (c, _) => c.togglePlay()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyC],
      command: true,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Copy",
      act: (c, _) => c.copySelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyX],
      command: true,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Cut",
      act: (c, _) => c.cutSelected()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyV],
      command: true,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Paste",
      act: (c, _) => c.paste()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyZ],
      command: true,
      shift: false,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Undo",
      act: (c, _) => c.undo()),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyZ],
      command: true,
      shift: true,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Redo",
      act: (c, _) => c.redo()),
  // What is picked anywhere on the timeline, another scene's clips included:
  // see CanvasController.clipSelection.
  CanvasShortcut(
      keys: _delete,
      alt: false,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      when: (c) => c.clipSelection.isNotEmpty,
      does: "Delete the clips picked on the timeline",
      act: (c, _) => c.deleteSelected()),
  // A cut on the selected channel at the playhead: K (the knife's letter)
  // or T. The knife tool itself cuts where the pointer is.
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyT],
      alt: false,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Cut the selected channel at the playhead",
      act: (c, _) {
        c.pause();
        c.cutAtPlayhead();
      }),
  CanvasShortcut(
      keys: const [LogicalKeyboardKey.keyV],
      alt: false,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      does: "Timeline: the Select tool",
      act: (c, _) => c.timelineTool = TimelineTool.select),
  CanvasShortcut(
      keys: _escape,
      alt: false,
      held: KeyHeld.once,
      reach: ShortcutReach.page,
      when: (c) => c.timelineTool != TimelineTool.select,
      does: "Timeline: back to the Select tool",
      act: (c, _) => c.timelineTool = TimelineTool.select),
];

const _arrows = [
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
];
const _delete = [LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace];
const _enter = [LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter];
const _escape = [LogicalKeyboardKey.escape];

/// _letter is the key of [letter], A to Z, as the tools give theirs.
LogicalKeyboardKey _letter(String letter) =>
    LogicalKeyboardKey.findKeyByKeyId(letter.toLowerCase().codeUnitAt(0))!;

bool _picture(CanvasController c) => c.editingImage != null;

bool _drawing(CanvasController c) => c.editingVector != null;

/// _plain is neither a picture nor a drawing being edited.
bool _plain(CanvasController c) => !_picture(c) && !_drawing(c);

bool _onStage(CanvasController c) => _plain(c) && c.onStage3d;

/// _nudge is how far an arrow moves something: a unit, or ten with Shift.
Offset _nudge(KeyEvent e) {
  var step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
  return switch (e.logicalKey) {
    LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
    LogicalKeyboardKey.arrowRight => Offset(step, 0),
    LogicalKeyboardKey.arrowUp => Offset(0, -step),
    _ => Offset(0, step),
  };
}

/// _frames is how many frames an arrow steps the playhead.
int _frames(KeyEvent e) => switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -10,
      _ => 10,
    };

/// _sizeBrush makes the picture's brush a fifth bigger or smaller: the
/// paint brush, or the mask brush.
void _sizeBrush(CanvasController c, {required bool bigger}) {
  if (c.imageTool.paints) {
    c.paintSize = bigger ? c.paintSize * 1.2 : c.paintSize / 1.2;
  } else {
    c.maskBrushSize = bigger ? c.maskBrushSize * 1.2 : c.maskBrushSize / 1.2;
  }
}

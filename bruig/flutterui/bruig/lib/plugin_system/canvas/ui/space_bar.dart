import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// space_bar.dart is the space bar playing and stopping the timeline from
// anywhere on the Canvas page -- and the few other keys the page answers
// wherever the focus is: a cut at the playhead, the timeline's tools, and
// copy, paste, undo and delete for what is selected.
//
// A focus scope round the page, answering space. The stage and the timeline
// each answered it too, but only while they held the focus, so after a click
// in the sidebar or the mixer the space bar did nothing -- or pressed
// whichever button had the focus, which is what the app does with a space.
// This is between any of those and the app: it hears what nothing inside has
// taken, before the app's own shortcuts would.
//
// It never hears a space being typed. A text field -- a note, a text element,
// a setting's field -- keeps its spaces, so typing is left alone without
// having to be recognised. Nor anything in a dialog, a menu or the chat beside
// the canvas: those are not inside it.
//
// A scope rather than a plain Focus so that it is where the focus falls back
// to: when a field inside is left, the focus lands here rather than outside
// the page, and the next space still plays.

/// CanvasSpaceBar makes space play and stop [controller] anywhere in [child].
class CanvasSpaceBar extends StatefulWidget {
  final CanvasController controller;
  final Widget child;
  const CanvasSpaceBar(
      {required this.controller, required this.child, super.key});

  @override
  State<CanvasSpaceBar> createState() => _CanvasSpaceBarState();
}

class _CanvasSpaceBarState extends State<CanvasSpaceBar> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: "canvas");

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_typing()) return KeyEventResult.ignored;
    var keys = HardwareKeyboard.instance;
    var command = keys.isControlPressed || keys.isMetaPressed;
    var c = widget.controller;
    var key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      if (command || keys.isAltPressed) return KeyEventResult.ignored;
      if (event is KeyDownEvent) c.togglePlay();
      // The repeats and the release too, so none of them reach a button.
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // What the canvas does with these when it has the focus, for when it has
    // not: after a click on the timeline -- a sound picked there, most of
    // all, which is copied, pasted onto its channel at the playhead, or
    // deleted from here.
    if (command) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          c.copySelected();
        case LogicalKeyboardKey.keyX:
          c.cutSelected();
        case LogicalKeyboardKey.keyV:
          c.paste();
        case LogicalKeyboardKey.keyZ:
          keys.isShiftPressed ? c.redo() : c.undo();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (keys.isAltPressed) return KeyEventResult.ignored;
    switch (key) {
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        if (c.selection.isEmpty) return KeyEventResult.ignored;
        c.deleteSelected();
      // A cut on the selected channel where the playhead is -- K, the
      // knife's letter, or T. The knife itself is on the timeline's tools,
      // for cutting where the pointer is; V or Escape goes back to select.
      case LogicalKeyboardKey.keyK || LogicalKeyboardKey.keyT:
        c.pause();
        c.cutAtPlayhead();
      case LogicalKeyboardKey.keyV:
        c.timelineTool = TimelineTool.select;
      case LogicalKeyboardKey.escape:
        if (c.timelineTool == TimelineTool.select) {
          return KeyEventResult.ignored;
        }
        c.timelineTool = TimelineTool.select;
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// _claim brings the focus onto the page when a press lands anywhere on it
  /// while the focus is somewhere else -- the chat box beside the canvas,
  /// most often. A press on the empty part of the timeline takes no focus of
  /// its own, so the focus stayed in the chat and the space bar typed there.
  /// A press on a field inside still takes the focus after this, for itself.
  ///
  /// On the release, not the press: the chat box lets go of the focus on the
  /// same press, and its letting go -- to the app, outside the page -- landed
  /// after a request made then.
  void _claim(PointerUpEvent _) {
    var now = FocusManager.instance.primaryFocus;
    if (now == _scope || (now != null && now.ancestors.contains(_scope))) {
      return;
    }
    _scope.requestFocus();
  }

  /// _typing is whether the focus is in something being typed into -- for a
  /// field that lets its spaces through, which the app's do not.
  static bool _typing() {
    var at = FocusManager.instance.primaryFocus?.context;
    if (at == null) return false;
    return at.widget is EditableText ||
        at.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: _claim,
        child: FocusScope(
          node: _scope,
          autofocus: true,
          onKeyEvent: _key,
          child: widget.child,
        ),
      );
}

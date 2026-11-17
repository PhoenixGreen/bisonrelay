import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// space_bar.dart has space play and stop the timeline anywhere on the Canvas
// page, with the few other keys the page answers wherever the focus is: a
// cut at the playhead, the timeline's tools, and copy, paste, undo and
// delete. A FocusScope round the page hears what nothing inside took,
// before the app's shortcuts would press the focused button. A text field
// keeps its spaces; dialogs, menus and the chat are outside it. A scope, so
// focus falls back here when a field inside is left.

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
    // A game playing has the keys: Space jumps. See CanvasController.gameKey.
    if (widget.controller.gaming) return KeyEventResult.handled;
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

    // For when the canvas is not focused: after a click on the timeline, a
    // picked sound is copied, pasted on its channel at the playhead, or
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
        // What is picked anywhere on the timeline, another scene's clips
        // included -- see CanvasController.clipSelection.
        if (c.clipSelection.isEmpty) return KeyEventResult.ignored;
        c.deleteSelected();
      // A cut on the selected channel at the playhead: K (the knife's
      // letter) or T. The knife tool itself cuts where the pointer is.
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

  /// _claim brings the focus to the page when a press lands on it while the
  /// focus is elsewhere (often the chat box): an empty part of the timeline
  /// takes none of its own. A field inside still takes it after this. On
  /// the release, not the press: the chat box lets go of focus on the press,
  /// which would land after a request made then.
  void _claim(PointerUpEvent _) {
    var now = FocusManager.instance.primaryFocus;
    if (now == _scope || (now != null && now.ancestors.contains(_scope))) {
      return;
    }
    _scope.requestFocus();
  }

  /// _typing is whether the focus is in something being typed into, for a
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

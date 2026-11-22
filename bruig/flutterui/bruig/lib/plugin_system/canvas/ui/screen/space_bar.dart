import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';
import 'package:flutter/material.dart';

// space_bar.dart has space play and stop the timeline anywhere on the Canvas
// page, with the few other keys the page answers wherever the focus is: a
// cut at the playhead, the timeline's tools, and copy, paste, undo and
// delete. They are the page's lines of canvasShortcuts (stage_keys.dart).
// A FocusScope round the page hears what nothing inside took, before the
// app's shortcuts would press the focused button. A text field keeps its
// spaces; dialogs, menus and the chat are outside it. A scope, so focus
// falls back here when a field inside is left.

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

  /// _key is the page's keyboard: the lines of canvasShortcuts heard
  /// anywhere on the page (stage_keys.dart).
  KeyEventResult _key(FocusNode node, KeyEvent event) =>
      canvasKey(widget.controller, event, reach: ShortcutReach.page);

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

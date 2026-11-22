import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';
import 'package:flutter/material.dart';

// page_keys.dart is the Canvas page's keyboard: a FocusScope round the page
// that hears what nothing inside it took and hands it to canvasKey as the
// page's (stage_keys.dart, the one table of keys: what each does is there),
// before the app's shortcuts would press the focused button. A scope, so
// focus falls back here when a field inside is left; and a press on the page
// brings the focus back to it from outside (the chat box, say).

/// CanvasPageKeys hears the page's keys for [controller] anywhere in [child]
/// and claims the keyboard for it when the page is pressed.
class CanvasPageKeys extends StatefulWidget {
  final CanvasController controller;
  final Widget child;
  const CanvasPageKeys(
      {required this.controller, required this.child, super.key});

  @override
  State<CanvasPageKeys> createState() => _CanvasPageKeysState();
}

class _CanvasPageKeysState extends State<CanvasPageKeys> {
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

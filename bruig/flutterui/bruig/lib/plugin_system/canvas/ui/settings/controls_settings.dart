import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// controls_settings.dart is a game's controls, in Canvas settings: each
// action, the keys that press it and the controller buttons. An action is
// pressed by any of them.

/// keyLabel is a key as it is written on it.
String keyLabel(int id) {
  var key = LogicalKeyboardKey.findKeyByKeyId(id);
  if (key == null) return "Key $id";
  var label = key.keyLabel;
  return switch (key) {
    LogicalKeyboardKey.arrowLeft => "←",
    LogicalKeyboardKey.arrowRight => "→",
    LogicalKeyboardKey.arrowUp => "↑",
    LogicalKeyboardKey.arrowDown => "↓",
    LogicalKeyboardKey.space => "Space",
    _ => label.isEmpty ? key.debugName ?? "Key" : label.toUpperCase(),
  };
}

/// GameControlsGroup is each player's controls, one player at a time.
class GameControlsGroup extends StatefulWidget {
  final CanvasController controller;
  const GameControlsGroup({required this.controller, super.key});

  @override
  State<GameControlsGroup> createState() => _GameControlsGroupState();
}

class _GameControlsGroupState extends State<GameControlsGroup> {
  /// _player is whose controls are shown.
  int _player = 1;

  @override
  Widget build(BuildContext context) {
    var controller = widget.controller;
    var doc = controller.document;
    var player = _player;
    var actions = doc.controlsFor(player);
    var changed = player == 1
        ? doc.controls != null
        : doc.playerControls.containsKey(player);
    void set(List<ControlAction> next) => controller.apply(player == 1
        ? doc.copyWith(controls: next)
        : doc.copyWith(playerControls: {...doc.playerControls, player: next}));
    void change(int i, ControlAction next) => set([...actions]..[i] = next);
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var playing = doc.players;
    return CanvasControlGroup(label: "Controls", children: [
      // Whose controls: a chip each, the players the game has brighter.
      SizedBox(
        width: double.infinity,
        child: Row(children: [
          for (var p = 1; p <= 4; p++) ...[
            if (p > 1) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: p == player
                    ? colors.secondaryContainer
                    : colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: ValueKey("controlsPlayer-$p"),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _player = p),
                  child: SizedBox(
                    height: 28,
                    child: Center(
                      child: Text(p <= 2 ? "Player $p" : "$p",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: p == player
                                  ? colors.onSecondaryContainer
                                  : playing.contains(p)
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant
                                          .withValues(alpha: 0.6))),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
      for (var (i, a) in actions.indexed)
        _ActionRow(
          key: ValueKey("control-$player-${a.id}"),
          action: a,
          theme: theme,
          onChanged: (next) => change(i, next),
        ),
      CanvasTextButton(
        key: const ValueKey("controlsReset"),
        label: "Reset",
        icon: Icons.restart_alt,
        onPressed: !changed
            ? null
            : () => controller.apply(player == 1
                ? doc.copyWith(controls: defaultControls)
                : doc.copyWith(
                    playerControls: {...doc.playerControls}..remove(player))),
      ),
      const CanvasHint(
          "What drives the canvas played as a game. An action is pressed by "
          "any of its keys or controller buttons; press + key and then the "
          "key to add one. Any controller the system knows works: Xbox, "
          "PlayStation, Switch Pro. With more than one player, each "
          "controller is a player's, in the order they are first used; "
          "the second player shares the keyboard, on WASD."),
    ]);
  }
}

class _ActionRow extends StatefulWidget {
  final ControlAction action;
  final ThemeNotifier theme;
  final ValueChanged<ControlAction> onChanged;
  const _ActionRow(
      {required this.action,
      required this.theme,
      required this.onChanged,
      super.key});

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  final FocusNode _listen = FocusNode();
  bool _waiting = false;

  @override
  void dispose() {
    _listen.dispose();
    super.dispose();
  }

  Widget _chip(String text, VoidCallback onRemove, Key key) {
    var colors = widget.theme.colors;
    return Container(
      key: key,
      height: 22,
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontSize: 11, color: colors.onSurface)),
        InkWell(
          onTap: onRemove,
          child: Icon(Icons.close, size: 13, color: colors.onSurfaceVariant),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    var a = widget.action;
    var colors = widget.theme.colors;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 86,
          child: Text(a.name,
              style: TextStyle(fontSize: 12, color: colors.onSurface)),
        ),
        for (var k in a.keys)
          _chip(
              keyLabel(k),
              () => widget.onChanged(a.copyWith(keys: [...a.keys]..remove(k))),
              ValueKey("key-${a.id}-$k")),
        for (var p in a.pad)
          _chip(
              p.label,
              () => widget.onChanged(a.copyWith(pad: [...a.pad]..remove(p))),
              ValueKey("pad-${a.id}-${p.name}")),
        // The next key pressed, while waiting for one.
        Focus(
          focusNode: _listen,
          onKeyEvent: (node, event) {
            if (!_waiting || event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            var id = event.logicalKey.keyId;
            setState(() => _waiting = false);
            _listen.unfocus();
            if (event.logicalKey != LogicalKeyboardKey.escape &&
                !a.keys.contains(id)) {
              widget.onChanged(a.copyWith(keys: [...a.keys, id]));
            }
            return KeyEventResult.handled;
          },
          child: TextButton(
            key: ValueKey("addKey-${a.id}"),
            onPressed: () {
              setState(() => _waiting = true);
              _listen.requestFocus();
            },
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11)),
            child: Text(_waiting ? "Press a key…" : "+ key"),
          ),
        ),
        PopupMenuButton<PadInput>(
          key: ValueKey("addPad-${a.id}"),
          tooltip: "Add a controller button",
          onSelected: (p) {
            if (!a.pad.contains(p)) {
              widget.onChanged(a.copyWith(pad: [...a.pad, p]));
            }
          },
          itemBuilder: (context) => [
            for (var p in PadInput.values)
              PopupMenuItem(
                  value: p,
                  child: Text(p.label, style: const TextStyle(fontSize: 12))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text("+ button",
                style: TextStyle(fontSize: 11, color: colors.primary)),
          ),
        ),
      ],
    );
  }
}

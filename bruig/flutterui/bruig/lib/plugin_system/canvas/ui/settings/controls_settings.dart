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

class GameControlsGroup extends StatelessWidget {
  final CanvasController controller;
  const GameControlsGroup({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var doc = controller.document;
    var actions = doc.controlsNow;
    void set(List<ControlAction> next) =>
        controller.apply(doc.copyWith(controls: next));
    void change(int i, ControlAction next) =>
        set([...actions]..[i] = next);
    var theme = ThemeNotifier.of(context);
    return CanvasControlGroup(label: "Controls", children: [
      for (var (i, a) in actions.indexed)
        _ActionRow(
          key: ValueKey("control-${a.id}"),
          action: a,
          theme: theme,
          onChanged: (next) => change(i, next),
        ),
      CanvasTextButton(
        key: const ValueKey("controlsReset"),
        label: "Reset",
        icon: Icons.restart_alt,
        onPressed: doc.controls == null
            ? null
            : () => controller.apply(doc.copyWith(controls: defaultControls)),
      ),
      const CanvasHint(
          "What drives the canvas played as a game. An action is pressed by "
          "any of its keys or controller buttons; press + key and then the "
          "key to add one. Any controller the system knows works: Xbox, "
          "PlayStation, Switch Pro."),
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
              () => widget.onChanged(
                  a.copyWith(keys: [...a.keys]..remove(k))),
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

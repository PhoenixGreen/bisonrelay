import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';

// button_action_controls.dart is what a press does, as a ButtonAction, and
// what it does it to: a button's (button_settings.dart) and a game
// element's press (play_settings.dart) are set by the same controls. What
// each action does is the controller's (controller/button_actions.dart).

/// actionDoes is the choice of what a press does: in the quick strip
/// ([quick]) as wide as its row gives it, in a section a set width.
Widget actionDoes(ButtonActionKind kind, ValueChanged<ButtonActionKind> set,
        {required bool quick, Key? key}) =>
    CanvasDropdown<ButtonActionKind>(
      key: key,
      label: "Does",
      value: kind,
      width: quick ? 130 : 150,
      options: [for (var k in ButtonActionKind.values) (k, k.label)],
      onChanged: set,
    );

/// _playable is whether media actions can target [e]: a sound, or a file
/// video. A linked video is another site's player, beyond our control.
bool _playable(CanvasElement e) =>
    e is AudioElement || (e is VideoElement && !e.isLink);

/// buttonActionControls are what a press does and its target. [set] writes
/// live, [commit] when the field is left. [key] names the controls' keys
/// ("$key-does", "-frame", "-element", "-link"); the sound's and the
/// scene's are buttonSound and buttonScene whoever shows them.
List<Widget> buttonActionControls(
    CanvasController controller,
    ButtonAction action,
    String selfId,
    void Function(ButtonAction next, {bool live}) set,
    VoidCallback commit,
    {required String key}) {
  return [
    actionDoes(action.kind, (v) => set(action.copyWith(kind: v)),
        quick: false, key: ValueKey("$key-does")),
    if (action.kind.needsFrame)
      CanvasNumberField(
        key: ValueKey("$key-frame"),
        label: "Frame",
        value: action.frame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => set(action.copyWith(frame: v.round()), live: true),
        onCommit: commit,
      ),
    // A sound is an Audio element on this canvas or the master under it, so
    // a button on page three can pause the master's music.
    if (action.kind.needsSound)
      CanvasDropdown<String>(
        key: const ValueKey("buttonSound"),
        label: "Sound or video",
        value: action.elementId,
        width: 170,
        options: [
          ("", "Nothing"),
          for (var other in controller.document.elements)
            if (_playable(other)) (other.id, other.name),
          if (!controller.document.editingMaster)
            for (var other in controller.document.masterScene?.elements ??
                const <CanvasElement>[])
              if (_playable(other)) (other.id, "${other.name} (master)"),
          // What the background plays: a stop-the-music button is most of
          // what a music bed needs.
          for (var other in controller.document.drawnBackground.media)
            (other.id, other.name),
        ],
        onChanged: (v) => set(action.copyWith(elementId: v)),
      ),
    if (action.kind.needsElement && !action.kind.needsSound)
      CanvasDropdown<String>(
        key: ValueKey("$key-element"),
        label: "Element",
        value: action.elementId,
        width: 150,
        options: [
          ("", "Nothing"),
          for (var other in controller.document.elements)
            if (other.id != selfId) (other.id, other.name),
        ],
        onChanged: (v) => set(action.copyWith(elementId: v)),
      ),
    // Which scene to show, held by id rather than order, so reordering the
    // scenes cannot silently retarget the button.
    if (action.kind.needsScene)
      CanvasDropdown<String>(
        key: const ValueKey("buttonScene"),
        label: "Scene",
        value: action.elementId,
        width: 170,
        options: [
          ("", "Nothing"),
          for (var (i, scene) in controller.document.allScenes.indexed)
            (scene.id, controller.document.nameOf(i)),
        ],
        onChanged: (v) => set(action.copyWith(elementId: v)),
      ),
    if (action.kind.needsUrl)
      CanvasTextField(
        key: ValueKey("$key-link"),
        label: "Link",
        value: action.url,
        width: 220,
        hint: "https://",
        onChanged: (v) => set(action.copyWith(url: v), live: true),
        onCommit: commit,
      ),
  ];
}

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// button settings.dart is a button's settings.

List<Widget> buttonSettings(
    BuildContext context,
    CanvasController controller,
    ButtonElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var action = e.action;
  return [
    section(e, "button",
        icon: Icons.smart_button_outlined,
        title: "Button",
        summary: "\"${e.label}\" · ${action.kind.label}",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "What it says and does",
            help: "The words on the button, and what pressing it does -- "
                "jump to a frame or a scene, play or stop a sound, show or "
                "hide an element, open a link.",
            rule: false,
            children: [
              CanvasTextField(
                label: "Label",
                value: e.label,
                width: 150,
                onChanged: (v) => write(e.copyWith(label: v)),
                onCommit: commit,
              ),
              ...buttonActionControls(controller, action, e.id, (next,
                  {live = false}) {
                begin();
                write(e.copyWith(action: next));
                if (!live) commit();
              }, commit),
            ],
          ),
          CanvasControlGroup(
            label: "Under the pointer",
            help: "The colours it turns while the pointer is over it, so a "
                "reader can tell it can be pressed.",
            rule: false,
            children: [
              CanvasColorButton(
                label: "Hover fill",
                color: e.hoverFill,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(hoverFill: c));
                  commit();
                },
              ),
              CanvasColorButton(
                label: "Hover text",
                color: e.hoverTextColor,
                onChanged: (c) {
                  begin();
                  write(e.copyWith(hoverTextColor: c));
                  commit();
                },
              ),
            ],
          ),
        ]),
    section(e, "type",
        icon: Icons.text_fields,
        title: "Label type",
        summary: typeSummary(e.textSpec),
        children: typeGroups(e.textSpec,
            (spec) => write(e.copyWith(textSpec: spec)), begin, commit,
            label: "Label type", remember: "buttonLabel", rule: false)),
    section(e, "box",
        icon: Icons.crop_square,
        title: "Box",
        summary: boxSummary(e.box),
        children: [
          boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit,
              remember: "button", rule: false),
        ]),
    animationPanelSection(controller, e, e.animation,
        (a) => write(e.copyWith(animation: a)), begin, commit),
  ];
}

/// _teamSettings is a whole team's controls.
///
/// Ordered the way a team is actually set up: which game, what shape, who is
/// in it, what colour they are, and how big the dots are. The squad list is
/// behind an expander because eleven rows of four fields is more than every
/// other element's settings put together, and somebody opening a team is
/// usually there for the formation or the kit.

/// _playable is whether a button's media actions can be aimed at [e]: a
/// sound, or a video made from files. A linked video is somebody else's
/// player, which a button on this canvas cannot start or stop.
bool _playable(CanvasElement e) =>
    e is AudioElement || (e is VideoElement && !e.isLink);

/// buttonActionControls are what a press does -- a button's, or an element
/// pressed in a game -- and what it does it to: a frame, a sound, an
/// element other than [selfId], a scene, a link. [set] writes the change;
/// live, for a field being typed into, with [commit] when it is left. [key],
/// where given, starts the Does dropdown's key.
List<Widget> buttonActionControls(
    CanvasController controller,
    ButtonAction action,
    String selfId,
    void Function(ButtonAction next, {bool live}) set,
    VoidCallback commit,
    {String? key}) {
  return [
    CanvasDropdown<ButtonActionKind>(
      key: key == null ? null : ValueKey("$key-does"),
      label: "Does",
      value: action.kind,
      width: 150,
      options: [for (var k in ButtonActionKind.values) (k, k.label)],
      onChanged: (v) => set(action.copyWith(kind: v)),
    ),
    if (action.kind.needsFrame)
      CanvasNumberField(
        label: "Frame",
        value: action.frame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => set(action.copyWith(frame: v.round()), live: true),
        onCommit: commit,
      ),
    // A sound is an Audio element, on this canvas or on the master under
    // it -- a button on page three can pause the music the master plays
    // on every page.
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
          // What the background plays: a button that stops the music is
          // most of what a music bed needs.
          for (var other in controller.document.drawnBackground.media)
            (other.id, other.name),
        ],
        onChanged: (v) => set(action.copyWith(elementId: v)),
      ),
    if (action.kind.needsElement && !action.kind.needsSound)
      CanvasDropdown<String>(
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
    // Which canvas of this document to show. Held by id rather than by
    // place in the order, so rearranging the scenes does not quietly point
    // the button at a different one.
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
        label: "Link",
        value: action.url,
        width: 220,
        hint: "https://",
        onChanged: (v) => set(action.copyWith(url: v), live: true),
        onCommit: commit,
      ),
  ];
}

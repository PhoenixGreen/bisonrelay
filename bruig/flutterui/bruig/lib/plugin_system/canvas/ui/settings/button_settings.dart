import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// button settings.dart is a button's settings.

List<Widget> buttonSettings(CanvasController controller, ButtonElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var action = e.action;
  return [
    // No caption: the panel header says "Button settings" already, and a
    // group called Button directly under it was the word twice.
    CanvasControlGroup(label: "Button", hideCaption: true, children: [
      CanvasTextField(
        label: "Label",
        value: e.label,
        width: 150,
        onChanged: (v) => write(e.copyWith(label: v)),
        onCommit: commit,
      ),
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
    ]),
    CanvasControlGroup(label: "Action", children: [
      CanvasDropdown<ButtonActionKind>(
        label: "Does",
        value: action.kind,
        width: 150,
        options: [for (var k in ButtonActionKind.values) (k, k.label)],
        onChanged: (v) {
          begin();
          write(e.copyWith(action: action.copyWith(kind: v)));
          commit();
        },
      ),
      if (action.kind.needsFrame)
        CanvasNumberField(
          label: "Frame",
          value: action.frame.toDouble(),
          min: 0,
          max: (controller.document.frames - 1).toDouble(),
          width: 54,
          onChanged: (v) =>
              write(e.copyWith(action: action.copyWith(frame: v.round()))),
          onCommit: commit,
        ),
      if (action.kind.needsElement)
        CanvasDropdown<String>(
          label: "Element",
          value: action.elementId,
          width: 150,
          options: [
            ("", "Nothing"),
            for (var other in controller.document.elements)
              if (other.id != e.id) (other.id, other.name),
          ],
          onChanged: (v) {
            begin();
            write(e.copyWith(action: action.copyWith(elementId: v)));
            commit();
          },
        ),
      if (action.kind.needsUrl)
        CanvasTextField(
          label: "Link",
          value: action.url,
          width: 220,
          hint: "https://",
          onChanged: (v) => write(e.copyWith(action: action.copyWith(url: v))),
          onCommit: commit,
        ),
    ]),
    ...typeGroups(
        e.textSpec, (spec) => write(e.copyWith(textSpec: spec)), begin, commit,
        label: "Label type"),
    boxGroup(e.box, (box) => write(e.copyWith(box: box)), begin, commit),
  ];
}

/// _teamSettings is a whole team's controls.
///
/// Ordered the way a team is actually set up: which game, what shape, who is
/// in it, what colour they are, and how big the dots are. The squad list is
/// behind an expander because eleven rows of four fields is more than every
/// other element's settings put together, and somebody opening a team is
/// usually there for the formation or the kit.

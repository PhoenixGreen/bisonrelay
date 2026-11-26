import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_action_controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart'
    show typeSummary;
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/type_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/box_group.dart';

// button_settings.dart is a button's panel (see element_panel.dart): quick
// strip, Content (words and action) and Look (type, box, hover colours).
// Its label and what it does are each built once for the quick strip and
// for Content (_label, actionDoes); its fill and its words' colour in the
// quick strip stand for the box's and the type's own, in Look.

/// _Button is a button in its panel and how to write it: what each piece of
/// the panel is handed.
class _Button {
  final BuildContext context;
  final CanvasController controller;
  final ButtonElement e;
  final SettingsWrite write;
  final VoidCallback begin;
  final VoidCallback commit;
  const _Button(this.context, this.controller, this.e, this.write, this.begin,
      this.commit);

  /// now writes [next] as one step: a choice made in one press.
  void now(ButtonElement next) {
    begin();
    write(next);
    commit();
  }
}

/// buttonPanel is [e]'s panel (see element_panel.dart).
Widget buttonPanel(
        BuildContext context,
        CanvasController controller,
        ButtonElement e,
        SettingsWrite write,
        VoidCallback begin,
        VoidCallback commit) =>
    _panel(_Button(context, controller, e, write, begin, commit));

Widget _panel(_Button b) =>
    elementPanel(b.context, b.controller, b.e, b.write, b.begin, b.commit,
        quick: _quick(b), bits: [_contentBit(b), _lookBit(b)]);

/// _quick is the quick strip: its label and fill, what it does and the
/// colour of its words.
Widget _quick(_Button b) {
  var e = b.e;
  return CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
    panelRow([
      cell(_label(b, quick: true), flex: 3, min: 110),
      cell(
          CanvasColorButton(
            key: const ValueKey("quickButtonFill"),
            label: "Fill",
            color: e.box.fill,
            onChanged: (c) => b.now(e.copyWith(box: e.box.copyWith(fill: c))),
          ),
          width: 104),
    ]),
    const SizedBox(height: 8),
    panelRow([
      cell(
          actionDoes(e.action.kind,
              (k) => b.now(e.copyWith(action: e.action.copyWith(kind: k))),
              quick: true, key: const ValueKey("quickButtonDoes")),
          flex: 3,
          min: 120),
      cell(
          CanvasColorButton(
            key: const ValueKey("quickButtonText"),
            label: "Text",
            color: e.textSpec.color,
            onChanged: (c) =>
                b.now(e.copyWith(textSpec: e.textSpec.copyWith(color: c))),
          ),
          width: 104),
    ]),
  ]);
}

/// _label is the words on it: in the quick strip ([quick]) or in Content.
Widget _label(_Button b, {required bool quick}) => CanvasTextField(
      key: ValueKey(quick ? "quickButtonLabel" : "buttonLabel"),
      label: "Label",
      value: b.e.label,
      width: 150,
      onChanged: (v) => b.write(b.e.copyWith(label: v)),
      onCommit: b.commit,
    );

/// _contentBit is what it says and what pressing it does.
PanelBit _contentBit(_Button b) {
  var e = b.e;
  return PanelBit(PanelSection.content,
      summary: "\"${e.label}\" · ${e.action.kind.label}",
      children: [
        CanvasControlGroup(
          label: "What it says and does",
          help: "The words on the button, and what pressing it does -- "
              "jump to a frame or a scene, play or stop a sound, show or "
              "hide an element, open a link.",
          rule: false,
          children: [
            _label(b, quick: false),
            ...buttonActionControls(b.controller, e.action, e.id, (next,
                {live = false}) {
              b.begin();
              b.write(e.copyWith(action: next));
              if (!live) b.commit();
            }, b.commit, key: "button"),
          ],
        ),
      ]);
}

/// _lookBit is how its words and its box are drawn, and the colours it
/// turns under the pointer.
PanelBit _lookBit(_Button b) {
  var e = b.e;
  return PanelBit(PanelSection.look,
      summary: typeSummary(e.textSpec),
      children: [
        labelType(
            TypeEdit(e.textSpec, (spec) => b.write(e.copyWith(textSpec: spec)),
                b.begin, b.commit),
            remember: "buttonLabel"),
        boxGroup(
            e.box, (box) => b.write(e.copyWith(box: box)), b.begin, b.commit,
            remember: "button",
            rule: false,
            fillPickedIn: b.context,
            compact: true),
        _hoverGroup(b),
      ]);
}

/// _hoverGroup is the colours it turns while the pointer is over it.
Widget _hoverGroup(_Button b) {
  var e = b.e;
  return CanvasControlGroup(
    label: "Under the pointer",
    help: "The colours it turns while the pointer is over it, so a "
        "reader can tell it can be pressed.",
    rule: false,
    children: [
      CanvasColorButton(
        key: const ValueKey("buttonHoverFill"),
        label: "Hover fill",
        color: e.hoverFill,
        onChanged: (c) => b.now(e.copyWith(hoverFill: c)),
      ),
      CanvasColorButton(
        key: const ValueKey("buttonHoverText"),
        label: "Hover text",
        color: e.hoverTextColor,
        onChanged: (c) => b.now(e.copyWith(hoverTextColor: c)),
      ),
    ],
  );
}

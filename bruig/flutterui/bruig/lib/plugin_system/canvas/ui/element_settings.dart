import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/chart_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/path_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/shape_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/table_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_settings.dart';

// element_settings.dart is the controls for whichever element is selected.
//
// One function per element kind, each returning the groups that go into the
// settings bar. They are grouped by what somebody is thinking about rather
// than by which class the field is declared on -- so a text element's colour
// sits with its outline and its shadow under "Colour", not with its font size
// under "Type", even though all four are fields of the same TextSpec.
//
// Every control writes a transient edit and commits on release, so dragging a
// slider updates the canvas continuously and lands as one undo step. That
// pairing is why almost every control here passes both onChanged and
// onCommit; a control that only did the first would make an undo history
// forty steps long for one adjustment.

/// elementSettings is the groups for [element].
List<Widget> elementSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement element,
) {
  // Opening the undo step here rather than leaving it to each control.
  // beginInteraction is idempotent, and forgetting it is silent: a transient
  // edit made outside an interaction is never pushed onto the history, so the
  // control works and is simply not undoable. With forty controls in this
  // file, doing it once is the only way it stays true.
  void write(CanvasElement next) {
    controller.beginInteraction();
    controller.replaceElement(next, transient: true);
  }

  void commit() => controller.endInteraction();
  void begin() => controller.beginInteraction();

  return [
    positionGroup(controller, element, write, begin, commit),
    ...switch (element) {
      TextElement e => textSettings(controller, e, write, begin, commit),
      ShapeElement e => shapeSettings(e, write, begin, commit),
      LineElement e => lineSettings(controller, e, write, begin, commit),
      ImageElement e =>
        imageSettings(context, controller, e, write, begin, commit),
      ChartElement e =>
        chartSettings(context, controller, e, write, begin, commit),
      TableElement e =>
        tableSettings(context, controller, e, write, begin, commit),
      ButtonElement e => buttonSettings(controller, e, write, begin, commit),
      BackgroundElement e => [
          ProceduralSettings(
            spec: e.spec,
            onChanged: (spec) => write(e.copyWith(spec: spec)),
            onBegin: begin,
            onCommit: commit,
          ),
          CanvasControlGroup(label: "Panel", children: [
            CanvasNumberField(
              label: "Radius",
              value: e.cornerRadius,
              min: 0,
              max: 400,
              onChanged: (v) => write(e.copyWith(cornerRadius: v)),
              onCommit: commit,
            ),
          ]),
        ],
      TeamElement e => teamSettings(e, write, begin, commit),
      PathElement e => pathSettings(controller, e, write, begin, commit),
      _ => const <Widget>[],
    },
  ];
}

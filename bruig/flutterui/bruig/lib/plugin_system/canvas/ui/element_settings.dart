import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart';
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
import 'package:bruig/plugin_system/canvas/ui/settings/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/button_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/video_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/chart_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/counter_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/path_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/shape_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/table_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/text_layers.dart';
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

  // A sound on the timeline is not on the canvas: no place on it, no presets
  // for a speaker, no speaker. What it has is its files, how it plays, and
  // where on the timeline -- the same as a backdrop's sound.
  if (element is AudioElement && isTimelineSound(element)) {
    return audioSettings(context, controller, element, write, begin, commit,
        background: true);
  }

  // A picture is all sections, its place and its presets among them -- see
  // image_sections.dart.
  if (element is ImageElement) {
    return imageSettings(context, controller, element, write, begin, commit);
  }

  // Every other element in sections, as a picture is: where it is, its
  // own subjects, how it arrives, and the designs saved of its kind -- see
  // element_sections.dart.
  return [
    CanvasSections(
      key: const ValueKey("elementSections"),
      // A drawing's layers over its sections, as a picture's are -- once it
      // has been taken apart into shapes to have any.
      parts: element is TextElement
          // A text's layers -- its own words, and every piece of writing or
          // picture added to its box -- over its sections, as a picture's
          // are.
          ? TextLayersList(
              key: const ValueKey("textLayersList"),
              controller: controller,
              element: element,
              onChanged: (next) {
                begin();
                write(next);
                commit();
              })
          : element is VectorElement &&
              element.edited &&
              (element.shapes?.isNotEmpty ?? false)
          ? VectorLayersList(
              key: const ValueKey("vectorLayersList"),
              controller: controller,
              element: element,
              onChanged: (next) {
                begin();
                write(next);
                commit();
              })
          : null,
      children: [
        positionSection(controller, element, write, begin, commit,
            // An element with no arrival of its own still waits on a cue.
            extra: [
              if (controller.cues.isNotEmpty &&
                  (element is BackgroundElement || element is TeamElement))
                elementCueCard(controller, element),
              // A drawing's file and how it sits in its box, at the foot
              // of where the box is.
              if (element is VectorElement)
                vectorDrawingControls(
                    context, controller, element, write, begin, commit),
              if (element is VectorElement && element.hasDrawing)
                vectorCropControls(controller, element, write, begin, commit),
              // Where a text's words come from and how they sit in its box.
              if (element is TextElement)
                textWordsCard(
                    context, controller, element, write, begin, commit),
            ]),
        ...switch (element) {
          TextElement e =>
            textSettings(context, controller, e, write, begin, commit),
          ShapeElement e =>
            shapeSettings(context, controller, e, write, begin, commit),
          LineElement e =>
            lineSettings(context, controller, e, write, begin, commit),
          VectorElement e =>
            vectorSettings(context, controller, e, write, begin, commit),
          ChartElement e =>
            chartSettings(context, controller, e, write, begin, commit),
          TableElement e =>
            tableSettings(context, controller, e, write, begin, commit),
          ButtonElement e =>
            buttonSettings(context, controller, e, write, begin, commit),
          CounterElement e =>
            counterSettings(context, controller, e, write, begin, commit),
          AudioElement e =>
            audioSettings(context, controller, e, write, begin, commit),
          VideoElement e =>
            videoSettings(context, controller, e, write, begin, commit),
          BackgroundElement e => [
              ProceduralSettings(
                sections: true,
                rememberAs: "backgroundElement",
                spec: e.spec,
                onChanged: (spec) => write(e.copyWith(spec: spec)),
                onBegin: begin,
                onCommit: commit,
              ),
              section(e, "panel",
                  icon: Icons.crop_square,
                  title: "Panel",
                  summary: e.cornerRadius > 0
                      ? "Corners ${e.cornerRadius.round()}"
                      : "Square corners",
                  children: [
                    CanvasControlGroup(
                        label: "Corners",
                        help: "How round the panel's corners are.",
                        children: [
                          CanvasNumberField(
                            label: "Radius",
                            value: e.cornerRadius,
                            min: 0,
                            max: 400,
                            onChanged: (v) =>
                                write(e.copyWith(cornerRadius: v)),
                            onCommit: commit,
                          ),
                        ]),
                  ]),
              edgeMaskSection(
                  e, e.mask, (m) => write(e.copyWith(mask: m)), begin, commit),
            ],
          TeamElement e =>
            teamSettings(context, controller, e, write, begin, commit),
          PathElement e =>
            pathSettings(context, controller, e, write, begin, commit),
          _ => const <Widget>[],
        },
        presetsPanelSection(context, controller, element, extra: [
          // A text's named styles, under the designs kept of its kind: the
          // other way its look is kept to use again.
          if (element is TextElement) textStyleCard(controller, element),
        ]),
      ],
    ),
  ];
}

/// elementCueGroup is which cue [element] arrives on.
Widget elementCueGroup(CanvasController controller, CanvasElement element) =>
    CanvasControlGroup(
        key: const ValueKey("elementCue"),
        label: "Cue",
        hideCaption: true,
        rule: false,
        children: [
          CanvasDropdown<String>(
            label: "Arrives on cue",
            value: controller.cues.any((c) => c.id == element.base.cue)
                ? element.base.cue
                : "",
            width: 150,
            options: [
              ("", "None"),
              for (var c in controller.cues) (c.id, c.name),
            ],
            onChanged: (v) =>
                controller.cueTo(element.id, v.isEmpty ? null : v),
          ),
        ]);

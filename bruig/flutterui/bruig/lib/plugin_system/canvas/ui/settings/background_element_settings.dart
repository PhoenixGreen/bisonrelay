import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/backdrop_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/parallax_settings.dart';

/// backgroundElementSettings is a Background element's own sections: its
/// pattern, 3D stage or scenery (whichever it shows), its panel's corners
/// and its edges.
List<Widget> backgroundElementSettings(
  BuildContext context,
  CanvasController controller,
  BackgroundElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) =>
    [
      ..._backgroundElementBackdrop(
          context, controller, e, write, begin, commit),
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
                    onChanged: (v) => write(e.copyWith(cornerRadius: v)),
                    onCommit: commit,
                  ),
                ]),
          ]),
      edgeMaskSection(
          e, e.mask, (m) => write(e.copyWith(mask: m)), begin, commit),
    ];

/// _backgroundElementBackdrop is a Background element's pattern, or its
/// stage, under the choice between them.
List<Widget> _backgroundElementBackdrop(
  BuildContext context,
  CanvasController controller,
  BackgroundElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var picker = backdropKindPicker(e.backdrop, (kind) {
    begin();
    write(e.copyWith(
        backdrop: kind,
        stage: e.stage ?? const StageElement(ElementBase(id: "")),
        parallax: kind == BackdropKind.parallax
            ? e.parallax ?? parallaxLooks.first.scenery
            : null));
    commit();
  });
  if (e.isParallax) {
    return [
      ParallaxSettings(
        key: ValueKey("parallaxSettings-${e.id}"),
        controller: controller,
        scenery: e.parallaxed,
        picker: picker,
        write: (p) => write(e.withParallax(p)),
        begin: begin,
        commit: commit,
        rememberAs: "backgroundElement",
      ),
    ];
  }
  if (e.isStage) {
    return stageBackdropSettings(context, controller, e.staged,
        picker: picker,
        write: (stage) => write(e.withStage(stage)),
        begin: begin,
        commit: commit,
        rememberAs: "backgroundElement");
  }
  return [
    ProceduralSettings(
      kindPicker: picker,
      sections: true,
      rememberAs: "backgroundElement",
      spec: e.spec,
      onChanged: (spec) => write(e.copyWith(spec: spec)),
      onBegin: begin,
      onCommit: commit,
    ),
  ];
}

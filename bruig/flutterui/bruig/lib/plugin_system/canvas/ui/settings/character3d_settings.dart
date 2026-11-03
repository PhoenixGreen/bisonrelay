import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// character3d_settings.dart is a 3D character's settings on the canvas: the
// character itself, changed in the Character Studio, and how the box shows
// it -- how much of it, from which side, how close.

List<Widget> character3dSettings(
  BuildContext context,
  CanvasController controller,
  Character3dElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(Character3dElement next) {
    begin();
    write(next);
    commit();
  }

  var changes = (e.framing != Character3dFraming.body ? 1 : 0) +
      (e.turn != 0 ? 1 : 0) +
      (e.tilt != 0 ? 1 : 0) +
      (e.zoom != 1 ? 1 : 0);
  return [
    section(e, "character",
        icon: Icons.view_in_ar_outlined,
        title: "Character",
        summary: e.design.name,
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
              label: "In the Character Studio",
              help: "Its body, hair, clothes, look and decals are changed in "
                  "the Character Studio. Done there changes every copy of "
                  "it, in every scene, and the one kept in Assets.",
              children: [
                CanvasTextButton(
                  key: const ValueKey("character3dEdit"),
                  label: "Change in the Studio",
                  icon: Icons.edit_outlined,
                  primary: true,
                  onPressed: () => controller.openStudio3d(element: e.id),
                ),
              ]),
        ]),
    section(e, "view",
        icon: Icons.videocam_outlined,
        title: "View",
        summary: [
          e.framing.label,
          if (e.turn != 0) "turned ${(e.turn * 180).round()}°",
        ].join(", "),
        changes: changes,
        onReset: changes == 0
            ? null
            : () => now(e.copyWith(
                framing: Character3dFraming.body, turn: 0, tilt: 0, zoom: 1)),
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
              label: "Shows",
              help: "How much of the character the box shows. The box keeps "
                  "its size; the character is drawn closer.",
              children: [
                CanvasSegmented<Character3dFraming>(
                  key: const ValueKey("character3dFraming"),
                  options: [
                    for (var f in Character3dFraming.values) (f, f.label)
                  ],
                  value: e.framing,
                  keyOf: (f) => "character3dFraming-${f.name}",
                  onChanged: (f) => now(e.copyWith(framing: f)),
                ),
              ]),
          CanvasControlGroup(
              label: "Seen from",
              help: "Turn goes round the character, half a turn either way "
                  "from the front. Tilt looks from above, or below. Zoom "
                  "comes closer than the framing.",
              children: [
                CanvasSlider(
                  key: const ValueKey("character3dTurn"),
                  label: "Turn",
                  value: e.turn,
                  min: -1,
                  max: 1,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(turn: v));
                  },
                  onCommit: commit,
                ),
                CanvasSlider(
                  key: const ValueKey("character3dTilt"),
                  label: "Tilt",
                  value: e.tilt,
                  min: -0.5,
                  max: 1,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(tilt: v));
                  },
                  onCommit: commit,
                ),
                CanvasSlider(
                  key: const ValueKey("character3dZoom"),
                  label: "Zoom",
                  value: e.zoom,
                  min: 0.5,
                  max: 3,
                  onChanged: (v) {
                    begin();
                    write(e.copyWith(zoom: v));
                  },
                  onCommit: commit,
                ),
              ]),
        ]),
  ];
}

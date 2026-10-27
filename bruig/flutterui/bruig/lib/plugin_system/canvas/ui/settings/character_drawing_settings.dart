import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart';
import 'package:flutter/material.dart';

// character_drawing_settings.dart is a sketched character's Drawing
// section: drawing on it by hand, panel by panel, with a drawing's own
// tools -- the very ones; see vectorSettings -- and the panel, the zoom and
// what of the generated drawing is left out under it. The bar over the
// canvas has the same; see character_draw_bar.dart.

/// panelOptions is every panel a sketch is drawn in, named, each marked as
/// drawn on or mirrored from the other side.
List<(String, String)> panelOptions(CharacterElement e) => [
      for (var tilt in CharacterPose.panelTilts)
        for (var turn in CharacterPose.panelTurns)
          (
            panelKey(turn, tilt),
            switch (e.drawingFor(turn, tilt)) {
              (var d, _) when d.isEmpty => panelLabel(turn, tilt),
              (_, true) => "${panelLabel(turn, tilt)} · mirrored",
              _ => "${panelLabel(turn, tilt)} · drawn",
            },
          ),
    ];

/// showPanel turns [e] to the panel named [key] -- see panelKey -- where
/// the playhead is.
CharacterElement showPanel(
    CanvasController controller, CharacterElement e, String key) {
  var [turn, tilt] = [for (var p in key.split(",")) double.parse(p)];
  var pose = e.poseAtFrame(controller.frame).withTurn(turn).withTilt(tilt);
  return controller.characterPosed(e, pose.inPanel);
}

/// drawingTarget is the drawing the tools edit for [e]: the one laid over
/// it while it is drawn on, or -- before -- the one that would be, which
/// picking a tool lays over it. See CanvasController.drawOnCharacter.
VectorElement drawingTarget(CanvasController controller, CharacterElement e) {
  if (controller.document.elementById(drawingProxyId(e.id))
      case VectorElement on) {
    return on;
  }
  return drawingProxy(
      e, controller.frame, math.max(1, controller.document.frameRate));
}

Widget characterDrawingSection(
    BuildContext context,
    CanvasController controller,
    CharacterElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  void now(CharacterElement next) {
    begin();
    write(next);
    commit();
  }

  var pose = e.poseAtFrame(controller.frame).inPanel;
  var turn = pose.panelTurn, tilt = pose.panelTilt;
  var (drawing, mirrored) = e.drawingFor(turn, tilt);
  var drawingOn = controller.drawingOn == e.id;
  var panels = e.drawings.length;

  void hide(CharacterRegion region, bool hidden) {
    var next = {...drawing.hidden};
    hidden ? next.add(region) : next.remove(region);
    // A mirrored panel changed is its own from then on.
    now(e.withDrawing(turn, tilt, drawing.copyWith(hidden: next)));
  }

  return section(e, "drawing",
      icon: Icons.draw_outlined,
      title: "Drawing",
      summary: [
        panelLabel(turn, tilt),
        if (mirrored) "mirrored" else if (!drawing.isEmpty) "drawn",
        if (panels > 0) "$panels panel${panels == 1 ? "" : "s"} drawn",
        if (drawingOn) controller.vectorTool.label,
      ].join(" · "),
      forceOpen: drawingOn,
      children: [
        CanvasControlGroup(
            key: const ValueKey("characterDrawingPanel"),
            label: "Panel",
            help: "A sketch is drawn from eight sides and four heights. "
                "What is drawn goes on the panel it is seen from, each shape "
                "on the part of the body under it, and moves with that part "
                "as the character is posed. A side not drawn yet is the "
                "other side's drawing, mirrored, until it is drawn on.",
            children: [
              CanvasDropdown<String>(
                key: const ValueKey("characterDrawingPanelPick"),
                label: "Seen from",
                value: panelKey(turn, tilt),
                options: panelOptions(e),
                onChanged: (key) => now(showPanel(controller, e, key)),
              ),
              CanvasDropdown<CharacterZoom?>(
                key: const ValueKey("characterDrawingZoom"),
                label: "Zoom to",
                value: null,
                options: [
                  (null, "Choose a part"),
                  for (var z in CharacterZoom.values) (z, z.label),
                ],
                onChanged: (z) {
                  if (z != null) controller.zoomToCharacter(e.id, z);
                },
              ),
            ]),
        // The drawing's own tools: picking one lays the drawing over the
        // character to draw on, and the one in hand again puts it down.
        ...vectorSettings(context, controller, drawingTarget(controller, e),
            write, begin, commit,
            toolsOnly: true),
        CanvasControlGroup(
            key: const ValueKey("characterDrawingHidden"),
            label: "Drawn instead",
            help: "Leave the generated drawing out where yours takes its "
                "place -- a head drawn whole, or an arm. On this panel only.",
            children: [
              for (var region in CharacterRegion.values)
                CanvasToggle(
                  key: ValueKey("characterDrawingHide-${region.name}"),
                  label: "Hide the ${region.label.toLowerCase()}",
                  value: drawing.hidden.contains(region),
                  onChanged: (v) => hide(region, v),
                ),
              if (!drawing.isEmpty && !mirrored)
                CanvasTextButton(
                  key: const ValueKey("characterDrawingClear"),
                  label: (turn.round() % 180 != 0)
                      ? "Clear · mirror the other side"
                      : "Clear this panel",
                  icon: Icons.delete_outline,
                  onPressed: () =>
                      now(e.withDrawing(turn, tilt, CharacterDrawing.empty)),
                ),
            ]),
      ]);
}

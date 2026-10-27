import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_drawing_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_tool_hint.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_draw_bar.dart is what floats over the canvas while a sketched
// character is picked, as a picture's bar does (see image_tool_hint.dart):
// going round it, the panel it is seen from, zooming onto a part of it,
// and the drawing tools -- a drawing's own, as its Drawing section has
// them -- to draw on it there.

/// drawBarTools are the drawing tools the bar has: the ones for drawing,
/// the rest in the Drawing section.
const List<VectorTool> drawBarTools = [
  VectorTool.select,
  VectorTool.selectShapes,
  VectorTool.pen,
  VectorTool.pencil,
  VectorTool.shapes,
  VectorTool.eraser,
  VectorTool.knife,
  VectorTool.corner,
  VectorTool.scale,
];

/// drawBarCharacter is the character the bar is for: the one drawn on, or
/// the sketch picked alone.
CharacterElement? drawBarCharacter(CanvasController controller) {
  var id = controller.drawingOn ??
      (controller.selection.length == 1 ? controller.selection.first : null);
  var e = id == null ? null : controller.document.elementById(id);
  return e is CharacterElement && !e.body.inThreeD ? e : null;
}

class CharacterDrawBar extends StatelessWidget {
  final CanvasController controller;
  const CharacterDrawBar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          var e = drawBarCharacter(controller);
          if (e == null || controller.playing) return const SizedBox.shrink();
          var theme = ThemeNotifier.of(context);
          var drawing = controller.drawingOn == e.id;
          var pose = e.poseAtFrame(controller.frame).inPanel;

          void write(CharacterElement next) {
            controller.beginInteraction();
            controller.replaceElement(next, transient: true);
          }

          Widget rule() => Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: theme.colors.outlineVariant);

          return Container(
            key: const ValueKey("characterDrawBar"),
            padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colors.outlineVariant),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 14,
                    offset: Offset(0, 4)),
              ],
            ),
            // On as many lines as the canvas has room for: a narrow window
            // takes the tools onto a second line rather than cutting them off.
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  // Going round it, panel to panel.
                  CanvasOrbitPad(
                    key: const ValueKey("characterDrawOrbit"),
                    turn: pose.turn,
                    tilt: pose.tilt,
                    onStart: controller.beginInteraction,
                    onChanged: (turn, tilt) => write(controller.characterPosed(
                        e,
                        e
                            .poseAtFrame(controller.frame)
                            .withTurn(turn)
                            .withTilt(tilt)
                            .inPanel)),
                    onEnd: controller.endInteraction,
                  ),
                  const SizedBox(width: 6),
                  CanvasDropdown<String>(
                    key: const ValueKey("characterDrawPanel"),
                    label: "Panel",
                    width: 190,
                    grow: false,
                    value: panelKey(pose.panelTurn, pose.panelTilt),
                    options: panelOptions(e),
                    onChanged: (key) {
                      write(showPanel(controller, e, key));
                      controller.endInteraction();
                    },
                  ),
                  const SizedBox(width: 6),
                  CanvasDropdown<CharacterZoom?>(
                    key: const ValueKey("characterDrawZoom"),
                    label: "Zoom",
                    width: 130,
                    grow: false,
                    value: null,
                    options: [
                      (null, "Zoom to…"),
                      for (var z in CharacterZoom.values) (z, z.label),
                    ],
                    onChanged: (z) {
                      if (z != null) controller.zoomToCharacter(e.id, z);
                    },
                  ),
                  const SizedBox(width: 4),
                  // The puppet to draw over: its proportions the character's.
                  CanvasIconButton(
                    key: const ValueKey("characterDrawPuppet"),
                    icon: Icons.accessibility_new,
                    tooltip: controller.showPuppet
                        ? "Hide the puppet"
                        : "Show the puppet",
                    active: controller.showPuppet,
                    onPressed: () =>
                        controller.showPuppet = !controller.showPuppet,
                  ),
                  // The limbs point by point, to bend, thicken and turn.
                  CanvasIconButton(
                    key: const ValueKey("characterDrawRig"),
                    icon: Icons.polyline_outlined,
                    tooltip: controller.editRig
                        ? "Put the rig's points away"
                        : "Reshape the limbs point by point",
                    active: controller.editRig,
                    onPressed: () => controller.editRig = !controller.editRig,
                  ),
                  rule(),
                  for (var tool in drawBarTools)
                    CanvasIconButton(
                      key: ValueKey("characterDrawTool-${tool.name}"),
                      icon: vectorToolIcon(tool),
                      tooltip: tool.label,
                      active: drawing && controller.vectorTool == tool,
                      onPressed: () {
                        // The one in hand again puts the drawing down.
                        if (drawing && controller.vectorTool == tool) {
                          controller.stopDrawingOnCharacter();
                          return;
                        }
                        controller.drawOnCharacter(e.id);
                        controller.vectorTool = tool;
                      },
                    ),
                ]),
          );
        },
      );
}

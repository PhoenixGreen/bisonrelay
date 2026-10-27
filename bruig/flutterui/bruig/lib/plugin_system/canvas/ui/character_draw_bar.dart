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
// character is picked, as a picture's bar does (see image_tool_hint.dart),
// on one line: going round it, the panel it is seen from, zooming onto a
// part of it, the puppet, face and limb handles, the drawing tools -- a
// drawing's own, as its Drawing section has them, all of them -- and,
// while it is drawn on, what to do with the tool in hand and the way out.
// A narrow canvas scrolls it sideways rather than taking it onto a second
// line.

/// drawBarTools are the drawing tools the bar steps through, the ones for
/// drawing first.
const List<VectorTool> drawBarTools = [
  VectorTool.select,
  VectorTool.pen,
  VectorTool.pencil,
  VectorTool.shapes,
  VectorTool.eraser,
  VectorTool.selectShapes,
  VectorTool.knife,
  VectorTool.corner,
  VectorTool.scale,
  VectorTool.boolean,
  VectorTool.align,
  VectorTool.tint,
  VectorTool.text,
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
          var garment = switch (controller.drawingGarment) {
            var g? when drawing && g < e.dna.wardrobe.length =>
              e.dna.wardrobe[g],
            _ => null,
          };
          // What is being drawn on: a garment, or one layer of the body.
          var onLayer = garment?.title ??
              (drawing ? BodyLayer.fromName(controller.drawingLayer)?.label : null);

          void write(CharacterElement next) {
            controller.beginInteraction();
            controller.replaceElement(next, transient: true);
          }

          Widget rule() => Container(
              width: 1,
              height: 24,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: theme.colors.outlineVariant);

          Widget toggle(String key, IconData icon, bool on, String tip,
                  VoidCallback press) =>
              CanvasIconButton(
                  key: ValueKey(key),
                  icon: icon,
                  tooltip: tip,
                  active: on,
                  onPressed: press);

          var zoom = controller.characterZoom;
          var row = Row(mainAxisSize: MainAxisSize.min, children: [
            // What is being drawn on, when it is something it wears.
            if (onLayer != null)
              Padding(
                key: const ValueKey("characterDrawGarment"),
                padding: const EdgeInsets.only(left: 6, right: 8),
                child: Tooltip(
                  message: "Drawing: $onLayer",
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.checkroom_outlined,
                        size: 16, color: theme.colors.primary),
                    const SizedBox(width: 4),
                    Text(onLayer,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colors.onSurface)),
                  ]),
                ),
              ),
            // Going round it, panel to panel: the globe, a size down.
            SizedBox(
              width: 40,
              height: 40,
              child: FittedBox(
                child: CanvasOrbitPad(
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
              ),
            ),
            const SizedBox(width: 6),
            CanvasDropdown<String>(
              key: const ValueKey("characterDrawPanel"),
              label: "Panel",
              width: 200,
              grow: false,
              stepped: true,
              value: panelKey(pose.panelTurn, pose.panelTilt),
              options: panelOptions(e),
              onChanged: (key) {
                write(showPanel(controller, e, key));
                controller.endInteraction();
              },
            ),
            CanvasDropdown<CharacterZoom?>(
              key: const ValueKey("characterDrawZoom"),
              label: "Zoom",
              width: 150,
              grow: false,
              stepped: true,
              value: zoom,
              options: [
                if (zoom == null) (null, "Zoom to…"),
                for (var z in CharacterZoom.values) (z, z.label),
              ],
              onChanged: (z) {
                if (z != null) controller.zoomToCharacter(e.id, z);
              },
            ),
            rule(),
            toggle(
                "characterDrawPuppet",
                Icons.accessibility_new,
                controller.showPuppet,
                controller.showPuppet ? "Hide the puppet" : "Show the puppet",
                () => controller.showPuppet = !controller.showPuppet),
            toggle(
                "characterDrawFace",
                Icons.face_retouching_natural,
                controller.editFace,
                controller.editFace
                    ? "Put the face's handles away"
                    : "Set the face on this panel",
                () => controller.editFace = !controller.editFace),
            toggle(
                "characterDrawRig",
                Icons.polyline_outlined,
                controller.editRig,
                controller.editRig
                    ? "Put the rig's points away"
                    : "Reshape the limbs point by point",
                () => controller.editRig = !controller.editRig),
            rule(),
            _ToolRow(controller: controller, character: e, drawing: drawing),
            // The tool in hand and the way out, at the end of the line.
            if (drawing) ...[
              rule(),
              _Tip(controller: controller),
            ],
          ]);

          return Container(
            key: const ValueKey("characterDrawBar"),
            padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
            decoration: BoxDecoration(
              color: theme.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.colors.outlineVariant),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 14,
                    offset: Offset(0, 4)),
              ],
            ),
            // Captions in hover text: the bar is one line, and the controls
            // are known by what is in them.
            child: CanvasControlScope(
              maxWidth: 240,
              hoverCaptions: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: row,
              ),
            ),
          );
        },
      );
}

/// _ToolRow is every drawing tool, side by side: one click to any of them.
class _ToolRow extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  final bool drawing;
  const _ToolRow(
      {required this.controller,
      required this.character,
      required this.drawing});

  @override
  Widget build(BuildContext context) {
    var inHand = drawing ? controller.vectorTool : null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var tool in drawBarTools)
        CanvasIconButton(
          key: ValueKey("characterDrawTool-${tool.name}"),
          icon: vectorToolIcon(tool),
          tooltip: tool.label,
          active: inHand == tool,
          onPressed: () {
            // The one in hand again puts the drawing down.
            if (inHand == tool) {
              controller.stopDrawingOnCharacter();
              return;
            }
            controller.drawOnCharacter(character.id,
                garment: controller.drawingGarment);
            controller.vectorTool = tool;
          },
        ),
    ]);
  }
}

/// _Tip is what to do with the tool in hand, and the way back out: to the
/// points tool, then out of drawing altogether -- as Escape steps.
class _Tip extends StatelessWidget {
  final CanvasController controller;
  const _Tip({required this.controller});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var tool = controller.vectorTool;
    var points = tool == VectorTool.select;
    // With a select tool in hand and nothing of the panel's own to pick
    // yet: its drawing can be taken apart into shapes to edit.
    var offer = (points || tool == VectorTool.selectShapes) &&
        !controller.drawnTakenApart;
    var muted = TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        key: const ValueKey("characterDrawHint"),
        constraints: const BoxConstraints(maxWidth: 230),
        child: Text(
            offer
                ? (controller.drawingGarment == null
                    ? "Take the panel apart to edit its outline"
                    : "Take it apart to edit its outline")
                : vectorToolLine(tool),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted),
      ),
      const SizedBox(width: 8),
      if (offer) ...[
        _Pill(
          key: const ValueKey("characterDrawTakeApart"),
          label: "Take apart",
          onTap: () {
            if (controller.drawingOn case var id?) {
              controller.takeApartCharacter(id,
                  garment: controller.drawingGarment);
            }
          },
        ),
        const SizedBox(width: 6),
      ],
      if (!points) ...[
        _Pill(
          key: const ValueKey("characterDrawPoints"),
          label: "Points · Esc",
          onTap: () => controller.vectorTool = VectorTool.select,
        ),
        const SizedBox(width: 6),
      ],
      _Pill(
        key: const ValueKey("characterDrawDone"),
        label: points ? "Done · Esc" : "Done",
        onTap: controller.stopDrawingOnCharacter,
      ),
    ]);
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: theme.colors.outlineVariant),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11.5, color: theme.colors.onSurface)),
        ),
      ),
    );
  }
}

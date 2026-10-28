import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart'
    show styleHairOf;
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

/// dollLenses is how strongly the doll can be seen in perspective: flat,
/// as most drawing is, to a camera close up, the near hand reaching out
/// big.
const List<(double, String)> dollLenses = [
  (0, "Flat"),
  (0.35, "Natural"),
  (0.65, "Wide"),
  (0.9, "Close up"),
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
          var pose = e.inView(e.poseAtFrame(controller.frame));
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
                      e.inView(e
                          .poseAtFrame(controller.frame)
                          .withTurn(turn)
                          .withTilt(tilt)))),
                  onEnd: controller.endInteraction,
                ),
              ),
            ),
            const SizedBox(width: 6),
            CanvasDropdown<String>(
              key: const ValueKey("characterDrawPanel"),
              label: "View",
              width: 200,
              grow: false,
              stepped: true,
              value: panelKey(pose.panelTurn, pose.panelTilt),
              // Only the views it has: more are added in its Layers' views.
              options: [
                ...panelOptions(e, adding: false),
                if (!panelOptions(e, adding: false)
                    .any((o) => o.$1 == panelKey(pose.panelTurn, pose.panelTilt)))
                  (panelKey(pose.panelTurn, pose.panelTilt),
                      viewLabel(pose.panelTurn, pose.panelTilt)),
              ],
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
            // Every view at once, laid out beside it, and the one next round
            // faintly over it.
            toggle(
                "characterDrawTurnaround",
                Icons.view_week_outlined,
                controller.showTurnaround,
                controller.showTurnaround
                    ? "Put the turnaround away"
                    : "Show every view beside it, lined up",
                () => controller.showTurnaround = !controller.showTurnaround),
            if (controller.showTurnaround)
              toggle(
                  "characterDrawOnion",
                  Icons.flip_to_back_outlined,
                  controller.onionSkin,
                  controller.onionSkin
                      ? "Hide the view next round"
                      : "Show the view next round faintly over this one",
                  () => controller.onionSkin = !controller.onionSkin),
            rule(),
            toggle(
                "characterDrawPuppet",
                Icons.accessibility_new,
                controller.showPuppet,
                controller.showPuppet ? "Hide the puppet" : "Show the puppet",
                () => controller.showPuppet = !controller.showPuppet),
            // The puppet as a doll in 3D, to pose and draw over, or flat.
            if (controller.showPuppet)
              toggle(
                  "characterDrawPuppet3D",
                  Icons.view_in_ar,
                  controller.puppet3D,
                  controller.puppet3D
                      ? "Show the flat puppet, with its handles"
                      : "Show the puppet as a doll in 3D",
                  () => controller.puppet3D = !controller.puppet3D),
            if (controller.dollShown) ...[
              toggle(
                  "characterDollLines",
                  Icons.architecture,
                  controller.dollLines,
                  controller.dollLines
                      ? "Hide the doll's guide lines"
                      : "Show the doll's guide lines: its middle, and rings round it",
                  () => controller.dollLines = !controller.dollLines),
              CanvasDropdown<double>(
                key: const ValueKey("characterDollLens"),
                label: "Lens",
                width: 130,
                grow: false,
                value: dollLenses.any((l) => l.$1 == controller.dollLens)
                    ? controller.dollLens
                    : dollLenses.first.$1,
                options: dollLenses,
                onChanged: (v) => controller.dollLens = v,
              ),
            ],
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
            // The hair stroke by stroke, when it is made of them -- its own,
            // or its style's, which shaping makes its own.
            if (styleHairOf(e.dna, e.style) != null)
              toggle(
                  "characterDrawHair",
                  Icons.gesture,
                  controller.editHair,
                  controller.editHair
                      ? "Put the hair's handles away"
                      : "Shape the hair stroke by stroke",
                  () {
                    if (!controller.editHair && e.dna.hairRig == null) {
                      controller.beginInteraction();
                      controller.replaceElement(e.copyWith(
                          dna: e.dna.copyWith(hairRig: styleHairOf(e.dna, e.style))));
                      controller.endInteraction();
                    }
                    controller.editHair = !controller.editHair;
                  }),
            if (controller.editHair && e.dna.hairRig != null)
              toggle(
                  "characterDrawLocks",
                  Icons.brush,
                  controller.hairAddLocks,
                  controller.hairAddLocks
                      ? "Stop drawing new locks"
                      : "Draw new locks: press where one grows, drag to its tip",
                  () => controller.hairAddLocks = !controller.hairAddLocks),
            // The tool in hand and the way out, at the end of the line. The
            // tools themselves are in the layer drawn on -- see
            // character_layers_settings.dart.
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
    var muted = TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        key: const ValueKey("characterDrawHint"),
        constraints: const BoxConstraints(maxWidth: 230),
        child: Text(vectorToolLine(tool),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
      ),
      const SizedBox(width: 8),
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

import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// vector_tool_hint.dart is what floats over the canvas while a drawing is
// being edited, as a picture's does (see image_tool_hint.dart): the tool in
// hand and what to do with it, where the eye already is, and the way back
// out -- to the points tool, or out of the drawing altogether.

/// vectorToolIcon is each drawing tool's icon, on its tile and over the
/// canvas.
IconData vectorToolIcon(VectorTool tool) => switch (tool) {
      VectorTool.select => Icons.near_me_outlined,
      VectorTool.selectShapes => Icons.near_me,
      VectorTool.pen => Icons.draw_outlined,
      VectorTool.scale => Icons.open_in_full,
      VectorTool.tint => Icons.brush_outlined,
      VectorTool.boolean => Icons.join_inner,
      VectorTool.align => Icons.align_horizontal_center,
      VectorTool.corner => Icons.rounded_corner,
      VectorTool.pencil => Icons.edit,
      VectorTool.eraser => Icons.cleaning_services_outlined,
      VectorTool.shapes => Icons.category_outlined,
      VectorTool.knife => Icons.content_cut,
      VectorTool.text => Icons.text_fields,
    };

/// vectorToolLine is what to do with [tool], in a line.
String vectorToolLine(VectorTool tool) => switch (tool) {
      VectorTool.select => "Click a shape or a point · drag a box round points",
      VectorTool.selectShapes => "Click shapes to pick them · Shift adds",
      VectorTool.pen => "Click to put points down · drag to curve",
      VectorTool.scale => "Drag right to thicken the line, left to thin it",
      VectorTool.tint => "Paint over the drawing to tint it · Alt rubs off",
      VectorTool.boolean => "Pick shapes, then combine them",
      VectorTool.align => "Line up what the last select tool picked",
      VectorTool.corner => "Click a point to round or cut its corner",
      VectorTool.pencil => "Draw freehand",
      VectorTool.eraser => "Rub out what the eraser goes over",
      VectorTool.shapes => "Drag a shape out · a click puts one down",
      VectorTool.knife => "Draw a line through a shape to cut it",
      VectorTool.text => "Click to start text, or click text to type into it",
    };

/// VectorToolHint is the pill over the canvas while a drawing is edited.
class VectorToolHint extends StatelessWidget {
  final CanvasController controller;
  const VectorToolHint({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          // A character drawn on has its own bar, with this at its end --
          // see character_draw_bar.dart.
          if (controller.editingVector == null ||
              controller.playing ||
              controller.drawingOn != null) {
            return const SizedBox.shrink();
          }
          var theme = ThemeNotifier.of(context);
          var tool = controller.vectorTool;
          var muted = theme.colors.onSurfaceVariant;
          var points = tool == VectorTool.select;
          return Container(
            key: const ValueKey("vectorToolHint"),
            padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(vectorToolIcon(tool), size: 16, color: theme.colors.primary),
              const SizedBox(width: 6),
              Text(tool.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colors.onSurface)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(vectorToolLine(tool),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
              const SizedBox(width: 8),
              // Escape steps back the same way: the tool first, then out.
              if (!points) ...[
                _Pill(
                  key: const ValueKey("vectorToolPoints"),
                  label: "Points · Esc",
                  icon: Icons.near_me_outlined,
                  onTap: () => controller.vectorTool = VectorTool.select,
                ),
                const SizedBox(width: 6),
              ],
              _Pill(
                key: const ValueKey("vectorToolDone"),
                label: points ? "Done · Esc" : "Done",
                onTap: () => controller.editVector(null),
              ),
            ]),
          );
        },
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.onTap, this.icon, super.key});

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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: theme.colors.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: theme.colors.onSurface),
              const SizedBox(width: 5),
            ],
            Text(label,
                style:
                    TextStyle(fontSize: 11.5, color: theme.colors.onSurface)),
          ]),
        ),
      ),
    );
  }
}

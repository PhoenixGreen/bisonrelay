import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// palette_section.dart is the document's palette: its own few colours, each
// of which recolours everything drawn in it when it is changed. See
// canvas_palette.dart.

/// CanvasPaletteSection shows and edits the document's palette.
class CanvasPaletteSection extends StatelessWidget {
  final CanvasController controller;
  const CanvasPaletteSection({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var palette = controller.palette;
    return CanvasControlGroup(
      key: const ValueKey("palette"),
      label: "Palette",
      children: [
        for (var (i, swatch) in palette.indexed)
          CanvasColorButton(
            key: ValueKey("swatch$i"),
            label: swatch.name,
            color: swatch.color,
            onChanged: (c) => controller.setSwatch(i, c),
          ),
        CanvasIconButton(
          key: const ValueKey("paletteFromCanvas"),
          icon: Icons.auto_awesome_outlined,
          tooltip: "Take the palette from the colours this canvas is drawn in",
          onPressed: () => controller.paletteFromCanvas(),
        ),
        CanvasIconButton(
          key: const ValueKey("paletteAdd"),
          icon: Icons.add,
          tooltip: "Add a colour",
          onPressed: () => controller.addSwatch(const Color(0xFFFFFFFF)),
        ),
        if (palette.isNotEmpty)
          CanvasIconButton(
            key: const ValueKey("paletteRemove"),
            icon: Icons.remove,
            tooltip: "Remove the last colour",
            onPressed: () => controller.removeSwatch(palette.length - 1),
          ),
        if (palette.length >= 3)
          CanvasIconButton(
            key: const ValueKey("paletteToBackgrounds"),
            icon: Icons.wallpaper_outlined,
            tooltip: "Draw every generated background in the first three "
                "colours: ground, pattern, highlight",
            onPressed: controller.paletteToBackgrounds,
          ),
        CanvasHint(palette.isEmpty
            ? "A palette is the few colours a video is drawn in. Take one "
                "from this canvas, then change a colour here to change it "
                "everywhere it is used."
            : "Change a colour to change it everywhere it is used -- every "
                "scene, chart, text and background."),
      ],
    );
  }
}

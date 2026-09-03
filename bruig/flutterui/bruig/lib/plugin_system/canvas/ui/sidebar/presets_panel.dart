import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// presets_panel.dart is the Presets tab: the canvases you can start from.
//
// Each one shows a real thumbnail of itself, drawn by the same renderer that
// draws the canvas -- not a stored picture. That is worth the few milliseconds
// it costs: the thumbnail cannot go stale, a preset changed in code shows its
// change immediately, and nothing has to ship a set of PNGs that have to be
// regenerated whenever a colour moves.

class CanvasPresetsPanel extends StatefulWidget {
  /// onChoose is called with a fresh document built from the preset. What to
  /// do about unsaved work is the screen's decision, not this panel's.
  final void Function(CanvasPreset preset, CanvasDocument document) onChoose;

  const CanvasPresetsPanel({required this.onChoose, super.key});

  @override
  State<CanvasPresetsPanel> createState() => _CanvasPresetsPanelState();
}

class _CanvasPresetsPanelState extends State<CanvasPresetsPanel> {
  /// _thumbnails holds one built document per preset, for drawing the
  /// previews.
  ///
  /// Built once rather than on every rebuild, because building the football
  /// preset lays out twenty-two players and the panel rebuilds whenever the
  /// sidebar does. They are never edited, so one copy is safe to share between
  /// every paint -- what the tap hands over is a *newly built* document, so
  /// the preview and the working copy are never the same object.
  late final Map<String, CanvasDocument> _thumbnails = {
    for (var preset in builtinPresets) preset.id: preset.build(),
  };

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
        children: [
          const CanvasSectionHeading("Presets",
              hint: "Start from one of these, then change whatever you like "
                  "and save your own copy."),
          for (var preset in builtinPresets)
            _PresetCard(
              preset: preset,
              preview: _thumbnails[preset.id],
              onTap: () => widget.onChoose(preset, preset.build()),
            ),
        ],
      );
}

class _PresetCard extends StatelessWidget {
  final CanvasPreset preset;
  final CanvasDocument? preview;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: preview == null
                  ? Container(color: theme.colors.surfaceContainerHighest)
                  : CustomPaint(painter: _PreviewPainter(preview!)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                Icon(preset.icon, size: 16, color: theme.colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preset.label,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(
                        preset.description,
                        style: TextStyle(
                            fontSize: 10,
                            color: theme.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// _PreviewPainter draws a whole document scaled into a thumbnail.
///
/// Letterboxed rather than cropped, so a preset's shape is part of what the
/// preview tells you -- a 9:16 preset should look tall in the list rather than
/// looking like a 16:9 one with its sides cut off.
class _PreviewPainter extends CustomPainter {
  final CanvasDocument document;
  const _PreviewPainter(this.document);

  @override
  void paint(Canvas canvas, Size size) {
    var docSize = document.size.size;
    if (docSize.width <= 0 || docSize.height <= 0) return;

    var scale = math.min(size.width / docSize.width, size.height / docSize.height);
    var drawn = Size(docSize.width * scale, docSize.height * scale);
    var offset = Offset((size.width - drawn.width) / 2,
        (size.height - drawn.height) / 2);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    // No image source: a preset ships no pictures, and an element that had one
    // would draw its placeholder rather than nothing at all.
    paintCanvasDocument(canvas, document);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.document != document;
}

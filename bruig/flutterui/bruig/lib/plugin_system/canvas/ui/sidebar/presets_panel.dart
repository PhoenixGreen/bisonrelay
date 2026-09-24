import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// presets_panel.dart is the Presets sidebar: the canvases, scenes and
// elements you can start from.
//
// Three lists in one column rather than one list, and a stack rather than
// tabs, for the reason the Design sidebar is one -- see design_panel.dart. A
// canvas is chosen once at the beginning; an element preset is reached for
// again and again while the work happens, and a tab is a place you have to
// leave to get back to what you were doing.
//
// Each one shows a real thumbnail of itself, drawn by the same renderer that
// draws the canvas -- not a stored picture. That is worth the few milliseconds
// it costs: the thumbnail cannot go stale, a preset changed in code shows its
// change immediately, and nothing has to ship a set of PNGs that have to be
// regenerated whenever a colour moves.

/// CanvasPresetsSidebar is the three lists, stacked.
class CanvasPresetsSidebar extends StatelessWidget {
  final CanvasController controller;

  /// onChoose starts a new document from a preset. What to do about unsaved
  /// work is the screen's decision, not this sidebar's.
  final void Function(CanvasPreset? preset, CanvasDocument document) onChoose;

  const CanvasPresetsSidebar(
      {required this.controller, required this.onChoose, super.key});

  @override
  Widget build(BuildContext context) => PanelStack(
        storageKey: "canvasPresets",
        panels: [
          StackPanel(
            id: "canvases",
            label: "Canvas",
            icon: Icons.dashboard_outlined,
            hint: "A whole document to start from. Tap one to begin a new "
                "canvas, or use its menu to add its scenes to the canvas "
                "already open.",
            body: CanvasPresetsPanel(
              controller: controller,
              onChoose: onChoose,
            ),
          ),
          StackPanel(
            id: "scenes",
            label: "Scene",
            icon: Icons.movie_outlined,
            hint: "Saved scenes. Tap one to add it to this document, after "
                "the scene being looked at.",
            startsOpen: false,
            body: ScenePresetsPanel(controller: controller),
          ),
          StackPanel(
            id: "elements",
            label: "Element",
            icon: Icons.category_outlined,
            hint: "Saved elements, and the ones that ship with the app. Tap "
                "one to put it on the canvas being looked at.",
            startsOpen: false,
            body: ElementPresetsPanel(controller: controller),
          ),
        ],
      );
}

class CanvasPresetsPanel extends StatefulWidget {
  final CanvasController controller;

  /// onChoose is called with a fresh document built from the preset. What to
  /// do about unsaved work is the screen's decision, not this panel's.
  final void Function(CanvasPreset? preset, CanvasDocument document) onChoose;

  const CanvasPresetsPanel(
      {required this.controller, required this.onChoose, super.key});

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
          for (var preset in builtinPresets)
            _PresetCard(
              preset: preset,
              preview: _thumbnails[preset.id],
              onTap: () => widget.onChoose(preset, preset.build()),
            ),
          // Whatever has been saved, under what ships with the app: the
          // built-in ones are always there, and a list whose beginning moves
          // as things are added to it is one nobody learns the shape of.
          SavedCanvasPresets(
            controller: widget.controller,
            onOpen: (document) => widget.onChoose(null, document),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: preview == null
                  ? Container(color: theme.colors.surfaceContainerHighest)
                  : CustomPaint(painter: _PreviewPainter(preview!)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                Icon(preset.icon,
                    size: 16, color: theme.colors.onSurfaceVariant),
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
                            fontSize: 10, color: theme.colors.onSurfaceVariant),
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

    var scale =
        math.min(size.width / docSize.width, size.height / docSize.height);
    var drawn = Size(docSize.width * scale, docSize.height * scale);
    var offset = Offset(
        (size.width - drawn.width) / 2, (size.height - drawn.height) / 2);

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

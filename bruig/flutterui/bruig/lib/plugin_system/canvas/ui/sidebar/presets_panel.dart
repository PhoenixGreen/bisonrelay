import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/preset_panels.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// presets_panel.dart is the canvases to start from, with a preview each: a
// part of the Presets panel (see presets_library.dart).
//
// Each preview is drawn by the canvas renderer from the preset itself rather
// than a stored picture, so it cannot go stale.

class CanvasPresetsPanel extends StatefulWidget {
  final CanvasController controller;

  /// onChoose is called with a fresh document built from the preset; see
  /// CanvasPresetsSidebar.onChoose.
  final void Function(CanvasPreset? preset, CanvasDocument document) onChoose;

  /// query keeps only the presets whose names have it in them.
  final String query;

  /// embedded is the list inside another: see ScenePresetsPanel.embedded.
  final bool embedded;

  /// only keeps only the built-in presets with these ids, and leaves the
  /// saved ones out; all of them where not given.
  final Set<String>? only;

  const CanvasPresetsPanel(
      {required this.controller,
      required this.onChoose,
      this.query = "",
      this.embedded = false,
      this.only,
      super.key});

  @override
  State<CanvasPresetsPanel> createState() => _CanvasPresetsPanelState();
}

class _CanvasPresetsPanelState extends State<CanvasPresetsPanel> {
  /// _thumbnails holds one built document per preset, for the previews.
  ///
  /// Built once, because some presets are costly to build (football lays out
  /// twenty-two players). Never edited, so safe to share: a tap hands over a
  /// newly built document, never this one.
  late final Map<String, CanvasDocument> _thumbnails = {
    for (var preset in builtinPresets) preset.id: preset.build(),
  };

  @override
  Widget build(BuildContext context) => presetList(
        embedded: widget.embedded,
        children: [
          for (var preset in builtinPresets)
            if ((widget.only == null || widget.only!.contains(preset.id)) &&
                presetMatches(preset.label, widget.query))
              _PresetCard(
                preset: preset,
                preview: _thumbnails[preset.id],
                onTap: () => widget.onChoose(preset, preset.build()),
              ),
          // Saved ones under the built-in ones, so the start of the list never
          // moves.
          if (widget.only == null)
            SavedCanvasPresets(
              controller: widget.controller,
              query: widget.query,
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
      child: Material(
        // Its own Material inside the list: the sidebar's let the highlight
        // spill over other sections and stay put when the list scrolled.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
      ),
    );
  }
}

/// _PreviewPainter draws a whole document scaled into a thumbnail,
/// letterboxed rather than cropped so the preset's shape shows.
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

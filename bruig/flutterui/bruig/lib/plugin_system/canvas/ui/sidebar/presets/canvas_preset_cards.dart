import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets/preset_lists.dart';
import 'package:bruig/theming_system/theme_manager.dart';

// canvas_preset_cards.dart is the canvases to start from, in the Presets
// panel (presets_panel.dart): a card with a preview for each that ships,
// and the saved ones as rows under them. Previews are drawn by the
// renderer from the preset itself, not a stored picture, so they cannot go
// stale.

/// CanvasPresetCards is the canvases to start from.
class CanvasPresetCards extends StatefulWidget {
  final CanvasController controller;

  /// onChoose is given a fresh document built from the preset; what to do
  /// about unsaved work is the screen's decision.
  final ValueChanged<CanvasDocument> onChoose;

  /// query keeps only the presets whose names have it in them.
  final String query;

  /// only keeps only the built-in presets with these ids, and leaves the
  /// saved ones out; all of them where not given.
  final Set<String>? only;

  const CanvasPresetCards(
      {required this.controller,
      required this.onChoose,
      this.query = "",
      this.only,
      super.key});

  @override
  State<CanvasPresetCards> createState() => _CanvasPresetCardsState();
}

class _CanvasPresetCardsState extends State<CanvasPresetCards> {
  /// _thumbnails holds one built document per preset, for the previews, built
  /// once because some are costly (football lays out twenty-two players). Never
  /// edited, so safe to share: a tap hands over a newly built document.
  late final Map<String, CanvasDocument> _thumbnails = {
    for (var preset in builtinPresets) preset.id: preset.build(),
  };

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var preset in builtinPresets)
            if ((widget.only == null || widget.only!.contains(preset.id)) &&
                presetMatches(preset.label, widget.query))
              _PresetCard(
                preset: preset,
                preview: _thumbnails[preset.id],
                onTap: () => widget.onChoose(preset.build()),
              ),
          // Saved ones under the built-in, so the list's start never moves.
          if (widget.only == null)
            SavedCanvasList(
              controller: widget.controller,
              query: widget.query,
              onOpen: widget.onChoose,
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
        // Its own Material inside the list: the sidebar's would let the
        // highlight spill over other sections and stay put on scroll.
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
    // No image source: a preset ships no pictures, and an element that had
    // one would draw its placeholder rather than nothing.
    paintCanvasDocument(canvas, document);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.document != document;
}

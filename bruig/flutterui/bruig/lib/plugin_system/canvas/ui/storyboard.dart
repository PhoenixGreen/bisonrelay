import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter/material.dart';

// storyboard.dart is the whole run at a glance: every scene as a strip of
// pictures at even points through it, drawn by the renderer the export uses,
// so what is looked over here is what will be published. A press on a
// picture goes there.
//
// It exists because the only other way to review a three-minute video was to
// play all three minutes, or to scrub scene by scene and remember the last
// one while looking at the next.

/// storyboardShots is how many pictures each scene is shown as.
const int storyboardShots = 5;

/// storyboardFrames is where in [scene] its pictures are taken: evenly
/// through it, never on its first or last frame, where a transition is.
List<int> storyboardFrames(CanvasDocument doc, int scene,
    {int shots = storyboardShots}) {
  var frames = doc.allScenes[scene].frames;
  return [
    for (var k = 0; k < shots; k++)
      ((frames - 1) * (k + 0.5) / shots).round().clamp(0, frames - 1).toInt(),
  ];
}

/// showStoryboard opens the storyboard over the editor.
Future<void> showStoryboard(BuildContext context, CanvasController controller) =>
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: CanvasStoryboard(controller: controller),
      ),
    );

/// CanvasStoryboard is the storyboard itself, for a dialog or a test.
class CanvasStoryboard extends StatefulWidget {
  final CanvasController controller;

  /// render draws one picture; the export's renderer unless a test says
  /// otherwise.
  final Future<ui.Image> Function(CanvasDocument doc, int frame)? render;

  const CanvasStoryboard({required this.controller, this.render, super.key});

  @override
  State<CanvasStoryboard> createState() => _CanvasStoryboardState();
}

class _CanvasStoryboardState extends State<CanvasStoryboard> {
  late final CanvasDocument _doc = widget.controller.document;
  final Map<(int, int), ui.Image> _shots = {};
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_drawAll());
  }

  @override
  void dispose() {
    _closed = true;
    for (var image in _shots.values) {
      image.dispose();
    }
    super.dispose();
  }

  /// _drawAll draws the pictures one at a time, top to bottom, each shown
  /// as soon as it is ready: all of them at once is a long wait for the
  /// first, and a burst of work the editor behind is still drawing through.
  Future<void> _drawAll() async {
    var render = widget.render ??
        (CanvasDocument d, int f) => renderFrame(d,
            frame: f,
            // Small: a storyboard tile is a few hundred pixels wide.
            scale: 320 / math.max(1, d.size.exportSize.width),
            images: widget.controller.images);
    for (var i = 0; i < _doc.allScenes.length; i++) {
      for (var f in storyboardFrames(_doc, i)) {
        if (_closed) return;
        var run = _doc.hasScenes ? _doc.startOfScene(i) + f : f;
        try {
          var image = await render(_doc, run);
          if (_closed) {
            image.dispose();
            return;
          }
          setState(() => _shots[(i, f)] = image);
        } catch (_) {
          // A picture that will not draw is left as its empty tile.
        }
      }
    }
  }

  void _go(int scene, int frame) {
    var c = widget.controller;
    c.goToScene(scene);
    c.frame = frame;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var rate = _doc.frameRate <= 0 ? 1 : _doc.frameRate;
    var aspect = _doc.size.size.width / math.max(1, _doc.size.size.height);
    String time(int run) {
      var s = run / rate;
      return "${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, "0")}";
    }

    return SizedBox(
      width: 1100,
      height: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Text("Storyboard", style: theme.textTheme.titleMedium),
              const SizedBox(width: 12),
              Text(
                  "${_doc.allScenes.length} ${_doc.kind.many}, "
                  "${time(_doc.playFrames)}",
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              IconButton(
                key: const ValueKey("storyboardClose"),
                tooltip: "Close",
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _doc.allScenes.length,
              itemBuilder: (context, i) {
                var start = _doc.hasScenes ? _doc.startOfScene(i) : 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${_doc.nameOf(i)}  ·  ${time(start)}",
                          style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Row(children: [
                        for (var f in storyboardFrames(_doc, i))
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                key: ValueKey("shot-$i-$f"),
                                onTap: () => _go(i, f),
                                child: AspectRatio(
                                  aspectRatio: aspect,
                                  child: Container(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                    child: _shots[(i, f)] == null
                                        ? null
                                        : RawImage(
                                            image: _shots[(i, f)],
                                            fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

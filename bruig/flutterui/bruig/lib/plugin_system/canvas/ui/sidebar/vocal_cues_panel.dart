import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/cues_section.dart';
import 'package:flutter/material.dart';

// vocal_cues_panel.dart is the run's cues down the sidebar: the named
// moments a voice-over's lines start on, that elements are timed against.
// A scene's transition and camera are in the Animation panel, opened by a
// double click on the scene on the timeline.

class CanvasVocalCuesPanel extends StatelessWidget {
  final CanvasController controller;
  const CanvasVocalCuesPanel({required this.controller, super.key});

  // Rebuilt with the canvas: the section shows the cues as they are now.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: CanvasControlScope(
            maxWidth: 240,
            child: CanvasCuesSection(controller: controller),
          ),
        ),
      );
}

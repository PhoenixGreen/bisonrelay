import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// sound_tools.dart is what can be done to a sound on the timeline as a
// whole. Cutting and fading are the timeline's own tools, and ducking is the
// mixer's -- see Ducking. See audio_tools.dart for the arithmetic.

/// CanvasSoundTools is the tools for the timeline sound [e]: nothing at all
/// unless it carries a volume shape to clear.
class CanvasSoundTools extends StatelessWidget {
  final CanvasController controller;
  final AudioElement e;
  const CanvasSoundTools(
      {required this.controller, required this.e, super.key});

  @override
  Widget build(BuildContext context) {
    // A volume shape written on the clip by an older ducking tool. The
    // mixer's Duck slot does that job now, and the two together would duck
    // it twice.
    if (e.clip.envelope.isEmpty) return const SizedBox.shrink();
    return CanvasControlGroup(
      key: const ValueKey("soundTools"),
      label: "Tools",
      children: [
        CanvasIconButton(
          key: const ValueKey("soundEven"),
          icon: Icons.horizontal_rule,
          tooltip: "Back to an even level -- duck with the mixer instead",
          onPressed: () => controller.replaceAnywhere(
              e.copyWith(clip: e.clip.copyWith(envelope: const []))),
        ),
      ],
    );
  }
}

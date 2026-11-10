import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart'
    show markerKindColours;
import 'package:flutter/material.dart';

// marker_note.dart is a marker's label on the canvas while playback holds
// at it (Ken, 2026-11-10): a stop's "Press to jump", a pause's "Get ready",
// where the marker says it is shown on the canvas. See
// CanvasController.holdingMarker.

/// MarkerNote is the label of the marker playback holds at, over the foot of
/// the canvas, in its kind's colour; nothing while none holds.
class MarkerNote extends StatelessWidget {
  final CanvasController controller;
  const MarkerNote({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.playheadMoved]),
        builder: (context, _) {
          var marker = controller.holdingMarker;
          if (marker == null) return const SizedBox.shrink();
          var colour = markerKindColours[marker.kind]!;
          return Container(
            key: const ValueKey("markerNote"),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xE6151320),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colour.withValues(alpha: 0.8)),
            ),
            child: Text(marker.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF2F0FA))),
          );
        },
      );
}

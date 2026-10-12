import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// stagger_section.dart is what can be done to several elements at once that
// none of them can do alone: arrive one after another.

/// CanvasStaggerSection staggers the arrivals of what is selected.
class CanvasStaggerSection extends StatefulWidget {
  final CanvasController controller;
  const CanvasStaggerSection({required this.controller, super.key});

  @override
  State<CanvasStaggerSection> createState() => _CanvasStaggerSectionState();
}

class _CanvasStaggerSectionState extends State<CanvasStaggerSection> {
  double _gap = 6;
  bool _downwards = false;

  @override
  Widget build(BuildContext context) {
    var controller = widget.controller;
    var count = controller.selection.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Txt.S("$count elements selected. Choose one to change its settings."),
        const SizedBox(height: canvasGroupGap),
        CanvasControlGroup(
          key: const ValueKey("stagger"),
          label: "Arrive one after another",
          children: [
            CanvasNumberField(
              key: const ValueKey("staggerGap"),
              label: "Frames apart",
              value: _gap,
              min: 0,
              max: 600,
              width: 58,
              onChanged: (v) => setState(() => _gap = v),
            ),
            CanvasDropdown<bool>(
              key: const ValueKey("staggerOrder"),
              label: "In order",
              value: _downwards,
              width: 116,
              options: const [
                (false, "Left to right"),
                (true, "Top to bottom"),
              ],
              onChanged: (v) => setState(() => _downwards = v),
            ),
            CanvasIconButton(
              key: const ValueKey("staggerApply"),
              icon: Icons.stacked_line_chart,
              tooltip: "Stagger their arrivals",
              onPressed: () => controller.staggerArrivals(
                  controller.selection.toList(), _gap.round(),
                  downwards: _downwards),
            ),
            const CanvasHint(
                "Each keeps its own animation; only when it starts moves. The "
                "first in order keeps its timing."),
          ],
        ),
      ],
    );
  }
}

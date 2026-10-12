import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// sound_tools.dart is what can be done to a sound on the timeline as a
// whole: fitting it to the end of the run, and ducking its channel under a
// voice. See audio_tools.dart for the arithmetic.

/// CanvasSoundTools is the tools for the timeline sound [e].
class CanvasSoundTools extends StatefulWidget {
  final CanvasController controller;
  final AudioElement e;
  const CanvasSoundTools(
      {required this.controller, required this.e, super.key});

  @override
  State<CanvasSoundTools> createState() => _CanvasSoundToolsState();
}

class _CanvasSoundToolsState extends State<CanvasSoundTools> {
  CanvasController get controller => widget.controller;

  String? _under;
  double _depth = -12;
  bool _ducking = false;
  String _said = "";

  /// _end is the last frame of what this sound plays under: the whole run
  /// for one on the master, its scene for one on a scene.
  int get _end {
    var d = controller.document;
    if (d.master?.elements.any((x) => x.id == widget.e.id) ?? false) {
      return d.playFrames;
    }
    for (var s in d.allScenes) {
      if (s.elements.any((x) => x.id == widget.e.id)) return s.frames;
    }
    return d.frames;
  }

  @override
  Widget build(BuildContext context) {
    var channels = controller.timelineChannels;
    var mine = channels
        .where((c) => c.lanes.any((l) => l.element.id == widget.e.id))
        .firstOrNull;
    var others = [
      for (var c in channels)
        if (c.key != mine?.key && c.key != "transitions") c,
    ];
    var under = others.where((c) => c.key == _under).firstOrNull ??
        others.firstOrNull;
    var ducked = mine?.lanes.any((l) => l.clip.envelope.isNotEmpty) ?? false;
    return CanvasControlGroup(
      key: const ValueKey("soundTools"),
      label: "Tools",
      children: [
        CanvasIconButton(
          key: const ValueKey("soundFit"),
          icon: Icons.straighten,
          tooltip: "Fit it to end with the run -- cut and faded if it is too "
              "long, its own ending laid over copies if it is too short",
          onPressed: () => controller.fitToEnd(widget.e, _end),
        ),
        if (mine != null && others.isNotEmpty) ...[
          CanvasDropdown<String>(
            key: const ValueKey("soundDuckUnder"),
            label: "Duck under",
            value: under!.key,
            width: 120,
            options: [for (var c in others) (c.key, c.name)],
            onChanged: (v) => setState(() => _under = v),
          ),
          CanvasNumberField(
            key: const ValueKey("soundDuckDepth"),
            label: "By",
            value: _depth,
            min: -40,
            max: -1,
            suffix: "dB",
            width: 56,
            onChanged: (v) => setState(() => _depth = v),
          ),
          CanvasIconButton(
            key: const ValueKey("soundDuck"),
            icon: Icons.call_received,
            tooltip: "Turn this channel down wherever ${under.name} speaks",
            onPressed: _ducking
                ? null
                : () async {
                    setState(() => _ducking = true);
                    var n = await controller.duckUnder(mine, under.key,
                        depthDb: _depth);
                    if (!mounted) return;
                    setState(() {
                      _ducking = false;
                      _said = n == 0
                          ? "Nothing heard on ${under.name} to duck under."
                          : "Ducked under $n lines.";
                    });
                  },
          ),
          if (ducked)
            CanvasIconButton(
              key: const ValueKey("soundUnduck"),
              icon: Icons.horizontal_rule,
              tooltip: "Back to an even level",
              onPressed: () => controller.clearDucking(mine),
            ),
        ],
        if (_said.isNotEmpty) CanvasHint(_said),
      ],
    );
  }
}

import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_touchup_panel.dart is the new Character Studio's Touch up: the
// body shaped by hand, with a brush dragged over it on the stage, where the
// sliders do not reach. See character_sculpt.dart.

/// The list's id for Touch up.
const String touchUpPartId = "touchup";

/// SculptBrush is the brush the next stroke is drawn with. Not kept: each
/// stroke keeps its own.
class SculptBrush {
  final SculptTool tool;

  /// size is the brush's radius as a share of the body's height; strength
  /// how far it goes, nought to one.
  final double size, strength;
  final bool mirror;
  const SculptBrush(
      {this.tool = SculptTool.raise,
      this.size = 0.04,
      this.strength = 0.5,
      this.mirror = true});

  SculptBrush copyWith(
          {SculptTool? tool, double? size, double? strength, bool? mirror}) =>
      SculptBrush(
          tool: tool ?? this.tool,
          size: size ?? this.size,
          strength: strength ?? this.strength,
          mirror: mirror ?? this.mirror);
}

/// CharacterTouchUpControls are the brush, and the strokes drawn so far.
class CharacterTouchUpControls extends StatelessWidget {
  final SculptBrush brush;
  final List<SculptStroke> strokes;
  final ValueChanged<SculptBrush> onBrush;
  final ValueChanged<List<SculptStroke>> onStrokes;
  const CharacterTouchUpControls(
      {required this.brush,
      required this.strokes,
      required this.onBrush,
      required this.onStrokes,
      super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    String percent(double v) => "${(v * 100).round()}%";
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        StudioPanelHead(
          title: "Touch up",
          says: "Shape the body by hand where the sliders do not reach: drag "
              "the brush over it to raise, lower or flatten the surface. The "
              "clothes follow the body. Hold Option (Alt) to turn it while "
              "touching up.",
          resetLabel: "Clear it all",
          onReset: strokes.isEmpty ? null : () => onStrokes(const []),
        ),
        StudioPills<SculptTool>(
          key: const ValueKey("sculpt-tool"),
          id: "sculpt-tool",
          label: "Brush",
          value: brush.tool,
          options: [for (final t in SculptTool.values) (t, t.label)],
          onChanged: (t) => onBrush(brush.copyWith(tool: t)),
        ),
        const SizedBox(height: 6),
        StudioSlider(
          key: const ValueKey("sculpt-size"),
          label: "Size",
          value: brush.size,
          min: 0.01,
          max: 0.15,
          rest: 0.04,
          format: percent,
          onChanged: (v) => onBrush(brush.copyWith(size: v)),
        ),
        StudioSlider(
          key: const ValueKey("sculpt-strength"),
          label: "Strength",
          value: brush.strength,
          min: 0.05,
          max: 1,
          rest: 0.5,
          format: percent,
          onChanged: (v) => onBrush(brush.copyWith(strength: v)),
        ),
        StudioPills<bool>(
          key: const ValueKey("sculpt-mirror"),
          id: "sculpt-mirror",
          label: "Sides",
          value: brush.mirror,
          options: const [(true, "Both sides"), (false, "One side")],
          onChanged: (m) => onBrush(brush.copyWith(mirror: m)),
        ),
        const SizedBox(height: 14),
        Text(
            strokes.isEmpty
                ? "Nothing touched up yet."
                : strokes.length == 1
                    ? "One stroke."
                    : "${strokes.length} strokes.",
            key: const ValueKey("sculptCount"),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: StudioPill(
            key: const ValueKey("sculptUndo"),
            label: "Take back the last",
            onTap: strokes.isEmpty
                ? null
                : () => onStrokes(strokes.sublist(0, strokes.length - 1)),
          ),
        ),
      ],
    );
  }
}

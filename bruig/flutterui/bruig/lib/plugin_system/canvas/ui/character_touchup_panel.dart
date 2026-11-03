import 'package:bruig/plugin_system/canvas/model/elements/character_sculpt.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// character_touchup_panel.dart is the new Character Studio's Touch up: the
// body shaped by hand, and the skin and clothes painted, with a brush
// dragged over the character on the stage, where the sliders and the
// decals do not reach. See character_sculpt.dart.

/// The list's id for Touch up.
const String touchUpPartId = "touchup";

/// TouchMode is what the brush does: shapes the body, or paints on it.
enum TouchMode {
  shape("Shape"),
  paint("Paint");

  final String label;
  const TouchMode(this.label);
}

/// TouchBrush is the brush the next stroke is drawn with. Not kept: each
/// stroke keeps its own.
class TouchBrush {
  final TouchMode mode;
  final SculptTool tool;
  final PaintTool paintTool;

  /// size is the brush's radius as a share of the body's height; strength
  /// how far a shaping stroke goes, nought to one.
  final double size, strength;

  /// colour, opacity and softness are a paint stroke's.
  final int colour;
  final double opacity, softness;
  final bool mirror;

  const TouchBrush({
    this.mode = TouchMode.shape,
    this.tool = SculptTool.raise,
    this.paintTool = PaintTool.paint,
    this.size = 0.04,
    this.strength = 0.5,
    this.colour = 0x9c3a32,
    this.opacity = 0.9,
    this.softness = 0.4,
    this.mirror = true,
  });

  TouchBrush copyWith({
    TouchMode? mode,
    SculptTool? tool,
    PaintTool? paintTool,
    double? size,
    double? strength,
    int? colour,
    double? opacity,
    double? softness,
    bool? mirror,
  }) =>
      TouchBrush(
        mode: mode ?? this.mode,
        tool: tool ?? this.tool,
        paintTool: paintTool ?? this.paintTool,
        size: size ?? this.size,
        strength: strength ?? this.strength,
        colour: colour ?? this.colour,
        opacity: opacity ?? this.opacity,
        softness: softness ?? this.softness,
        mirror: mirror ?? this.mirror,
      );
}

/// paintColours are the paints offered: skin tones for blush and shading,
/// lip and eye colours, ink for tattoos and markings, and bright face
/// paint.
const List<int> paintColours = [
  0x1b1a22, 0x3d2a24, 0x7a4a3a, 0xc98a72, 0xe8b4a0, 0xf4f1ea, //
  0x9c3a32, 0xd0506a, 0xe88aa8, 0x6a3d6e, 0x263552, 0x3a7ac0,
  0x3e6145, 0x7aa64a, 0xe0b040, 0xe07a30,
];

/// CharacterTouchUpControls are the brush, and the strokes drawn so far.
class CharacterTouchUpControls extends StatelessWidget {
  final TouchBrush brush;
  final List<SculptStroke> strokes;
  final List<PaintStroke> paint;
  final ValueChanged<TouchBrush> onBrush;
  final ValueChanged<List<SculptStroke>> onStrokes;
  final ValueChanged<List<PaintStroke>> onPaint;
  const CharacterTouchUpControls(
      {required this.brush,
      required this.strokes,
      this.paint = const [],
      required this.onBrush,
      required this.onStrokes,
      this.onPaint = _ignore,
      super.key});

  static void _ignore(List<PaintStroke> _) {}

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    String percent(double v) => "${(v * 100).round()}%";
    final painting = brush.mode == TouchMode.paint;
    final count = painting ? paint.length : strokes.length;
    void clear() => painting ? onPaint(const []) : onStrokes(const []);
    void takeBack() => painting
        ? onPaint(paint.sublist(0, paint.length - 1))
        : onStrokes(strokes.sublist(0, strokes.length - 1));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        StudioPanelHead(
          title: "Touch up",
          says: painting
              ? "Paint on the skin and the clothes: blush, lipstick, face "
                  "paint, markings, stains. Drag the brush over the "
                  "character; the paint stays on what it was put on. Hold "
                  "Option (Alt) to turn it while painting."
              : "Shape the body by hand where the sliders do not reach: drag "
                  "the brush over it to raise, lower or flatten the surface. "
                  "The clothes follow the body. Hold Option (Alt) to turn it "
                  "while touching up.",
          resetLabel: "Clear it all",
          onReset: count == 0 ? null : clear,
        ),
        StudioPills<TouchMode>(
          key: const ValueKey("touch-mode"),
          id: "touch-mode",
          label: "Brush does",
          value: brush.mode,
          options: [for (final m in TouchMode.values) (m, m.label)],
          onChanged: (m) => onBrush(brush.copyWith(
              mode: m,
              // A paint brush is finer to start with than a shaping one.
              size: m == TouchMode.paint
                  ? brush.size.clamp(0.004, 0.02)
                  : brush.size.clamp(0.02, 0.15))),
        ),
        if (!painting)
          StudioPills<SculptTool>(
            key: const ValueKey("sculpt-tool"),
            id: "sculpt-tool",
            label: "Brush",
            value: brush.tool,
            options: [for (final t in SculptTool.values) (t, t.label)],
            onChanged: (t) => onBrush(brush.copyWith(tool: t)),
          )
        else ...[
          StudioPills<PaintTool>(
            key: const ValueKey("paint-tool"),
            id: "paint-tool",
            label: "Brush",
            value: brush.paintTool,
            options: [for (final t in PaintTool.values) (t, t.label)],
            onChanged: (t) => onBrush(brush.copyWith(paintTool: t)),
          ),
          if (brush.paintTool == PaintTool.paint)
            StudioSwatches(
              id: "paint-colour",
              label: "Colour",
              palette: paintColours,
              value: brush.colour,
              onPick: (c) => onBrush(brush.copyWith(colour: c ?? brush.colour)),
            ),
        ],
        const SizedBox(height: 6),
        StudioSlider(
          key: const ValueKey("sculpt-size"),
          label: "Size",
          value: brush.size,
          min: painting ? 0.002 : 0.01,
          max: painting ? 0.08 : 0.15,
          rest: painting ? 0.01 : 0.04,
          format: (v) => "${(v * 1000).round() / 10}%",
          onChanged: (v) => onBrush(brush.copyWith(size: v)),
        ),
        if (!painting)
          StudioSlider(
            key: const ValueKey("sculpt-strength"),
            label: "Strength",
            value: brush.strength,
            min: 0.05,
            max: 1,
            rest: 0.5,
            format: percent,
            onChanged: (v) => onBrush(brush.copyWith(strength: v)),
          )
        else ...[
          StudioSlider(
            key: const ValueKey("paint-opacity"),
            label: "Opacity",
            value: brush.opacity,
            min: 0.05,
            max: 1,
            rest: 0.9,
            format: percent,
            onChanged: (v) => onBrush(brush.copyWith(opacity: v)),
          ),
          StudioSlider(
            key: const ValueKey("paint-softness"),
            label: "Softness",
            value: brush.softness,
            min: 0,
            max: 1,
            rest: 0.4,
            format: percent,
            onChanged: (v) => onBrush(brush.copyWith(softness: v)),
          ),
        ],
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
            count == 0
                ? (painting
                    ? "Nothing painted yet."
                    : "Nothing touched up yet.")
                : count == 1
                    ? "One stroke."
                    : "$count strokes.",
            key: const ValueKey("sculptCount"),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: StudioPill(
            key: const ValueKey("sculptUndo"),
            label: "Take back the last",
            onTap: count == 0 ? null : takeBack,
          ),
        ),
      ],
    );
  }
}

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// procedural_settings.dart is the controls for a generated background.
//
// The same widget serves both places a generator can be pointed: the canvas's
// own background and a background element. That is deliberate -- they are one
// recipe with one set of controls, and a reader who has learned to build a
// matrix rain on the canvas should not meet a different panel when they put
// one behind a title.
//
// The controls are the five shared ones (density, scale, intensity, variation,
// seed) plus the colours, and they are shown for every style. A generator that
// ignored one of them would leave a slider doing nothing, which is why each
// generator is written to make all five mean something -- see
// render/procedural/generators.dart.

/// ProceduralSettings edits a [ProceduralSpec].
class ProceduralSettings extends StatelessWidget {
  final ProceduralSpec spec;
  final ValueChanged<ProceduralSpec> onChanged;
  final VoidCallback onBegin;
  final VoidCallback onCommit;

  /// label names the group, so the canvas's own background and an element's
  /// can be told apart when both are on the bar.
  final String label;

  const ProceduralSettings({
    required this.spec,
    required this.onChanged,
    required this.onBegin,
    required this.onCommit,
    this.label = "Background",
    super.key,
  });

  void _set(ProceduralSpec next) => onChanged(next);

  void _setNow(ProceduralSpec next) {
    onBegin();
    onChanged(next);
    onCommit();
  }

  @override
  Widget build(BuildContext context) {
    var groups = _groups();
    // Stacked, in the Layers sidebar, these run down the column like every
    // other element's settings. A Row of five groups in a 280px sidebar is a
    // thousand pixels of overflow, and it does not shrink -- the groups are
    // sized to their controls.
    return CanvasControlScope.isStacked(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: groups)
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: groups);
  }

  List<Widget> _groups() => [
          CanvasControlGroup(label: label, children: [
            CanvasDropdown<ProceduralStyle>(
              label: "Style",
              value: spec.style,
              width: 138,
              options: [for (var s in ProceduralStyle.values) (s, s.label)],
              onChanged: (v) => _setNow(spec.copyWith(style: v)),
            ),
            // The seed and its shuffle sit together, because the number is
            // almost never typed -- what it is for is pressing the button
            // until something good appears, and then being able to write down
            // which one it was.
            CanvasNumberField(
              label: "Seed",
              value: spec.seed.toDouble(),
              min: 0,
              max: 1000000,
              width: 62,
              onChanged: (v) => _set(spec.copyWith(seed: v.round())),
              onCommit: onCommit,
            ),
            CanvasIconButton(
              icon: Icons.casino_outlined,
              tooltip: "Try the next variation",
              onPressed: () => _setNow(spec.shuffled()),
            ),
            if (spec.style == ProceduralStyle.pitch)
              CanvasDropdown<PitchSport>(
                label: "Sport",
                value: spec.sport,
                width: 148,
                options: [for (var s in PitchSport.values) (s, s.label)],
                onChanged: (v) => _setNow(spec.copyWith(sport: v)),
              ),
          ]),
          CanvasControlGroup(label: "Colours", children: [
            CanvasColorButton(
              label: "Base",
              color: spec.background,
              onChanged: (c) => _setNow(spec.copyWith(background: c)),
            ),
            CanvasColorButton(
              label: "Main",
              color: spec.foreground,
              onChanged: (c) => _setNow(spec.copyWith(foreground: c)),
            ),
            CanvasColorButton(
              label: "Accent",
              color: spec.accent,
              onChanged: (c) => _setNow(spec.copyWith(accent: c)),
            ),
            CanvasToggle(
              label: "Gradient",
              value: spec.gradient,
              onChanged: (v) => _setNow(spec.copyWith(gradient: v)),
            ),
            if (spec.gradient) ...[
              CanvasColorButton(
                label: "To",
                color: spec.gradientTo,
                onChanged: (c) => _setNow(spec.copyWith(gradientTo: c)),
              ),
              CanvasNumberField(
                label: "Angle",
                value: spec.gradientAngle,
                min: -360,
                max: 360,
                width: 54,
                suffix: "°",
                onChanged: (v) => _set(spec.copyWith(gradientAngle: v)),
                onCommit: onCommit,
              ),
            ],
          ]),
          CanvasControlGroup(label: "Amount", children: [
            CanvasNumberField(
              label: "Density",
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              value: spec.density,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(density: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              label: "Size",
              width: 62,
              value: spec.scale,
              min: 0.004,
              max: 0.25,
              decimals: 3,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(scale: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              label: "Brightness",
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              value: spec.intensity,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(intensity: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              label: "Variation",
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              value: spec.variation,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(variation: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              label: "Vignette",
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              value: spec.vignette,
              onChanged: (v) {
                onBegin();
                _set(spec.copyWith(vignette: v));
              },
              onCommit: onCommit,
            ),
            CanvasNumberField(
              label: "Rotation",
              value: spec.rotation,
              min: -360,
              max: 360,
              width: 54,
              suffix: "°",
              onChanged: (v) => _set(spec.copyWith(rotation: v)),
              onCommit: onCommit,
            ),
          ]),
          if (spec.style.usesGlyphs)
            CanvasControlGroup(label: "Symbols", children: [
              // The whole set as one string, so adding a character means
              // typing it. A picker of symbol categories would be a longer
              // walk to the same place, and would not let somebody use their
              // own initials as the rain.
              CanvasTextField(
                label: "Characters used",
                value: spec.glyphs,
                width: 240,
                onChanged: (v) => _set(spec.copyWith(glyphs: v)),
                onCommit: onCommit,
              ),
              CanvasIconButton(
                icon: Icons.restart_alt,
                tooltip: "Back to the default characters",
                onPressed: () => _setNow(spec.copyWith(glyphs: defaultGlyphs)),
              ),
            ]),
          if (spec.style.canAnimate)
            CanvasControlGroup(label: "Movement", children: [
              CanvasToggle(
                label: "Animate",
                value: spec.animated,
                onChanged: (v) => _setNow(spec.copyWith(animated: v)),
              ),
              if (spec.animated)
                CanvasNumberField(
                  label: "Speed",
                  decimals: 2,
                  width: 62,
                  value: spec.speed,
                  min: 0.05,
                  max: 6,
                  onChanged: (v) {
                    onBegin();
                    _set(spec.copyWith(speed: v));
                  },
                  onCommit: onCommit,
                ),
            ]),
      ];
}

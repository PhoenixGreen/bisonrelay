import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_controls.dart';
import 'package:flutter/material.dart';

// character_look_panel.dart is the new Character Studio's Drawing style: a
// look to start from, then its lines, shading and light, its colour, and the
// finish of the page. See character_look.dart.

/// The list's id for the Drawing style.
const String stylePartId = "style";

/// CharacterLookControls are the Drawing style's settings. [name] is the
/// look last started from.
class CharacterLookControls extends StatelessWidget {
  final CharacterLook look;
  final String name;
  final void Function(CharacterLook look, String name) onChanged;
  const CharacterLookControls(
      {required this.look,
      required this.name,
      required this.onChanged,
      super.key});

  static const _ink = [
    0x000000,
    0x1b1a22,
    0x3a2a26,
    0x2c3a55,
    0x5a2e5e,
    0x7a5a3a
  ];
  static const _paper = [
    0xe9e6df,
    0xf4f1ea,
    0xf7f1e3,
    0xf3eef2,
    0xdfe6ea,
    0xd8d6d2,
    0x2a2a30
  ];

  @override
  Widget build(BuildContext context) {
    final from = characterLooks[name] ?? const CharacterLook();
    void set(CharacterLook l) => onChanged(l, name);
    Widget pills(String key, String label) => StudioPills<String>(
          key: ValueKey("look-$key"),
          id: "look-$key",
          label: label,
          value: look.choices[key]!,
          options: lookOptions[key]!,
          onChanged: (v) => set(look.withChoice(key, v)),
        );
    Widget slider(String key, String label, {double min = 0}) => StudioSlider(
          key: ValueKey("look-$key"),
          label: label,
          value: look.numbers[key]!,
          min: min,
          max: 1,
          rest: from.numbers[key]!,
          onChanged: (v) => set(look.withNumber(key, v)),
        );
    final r = look.render;
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          StudioPanelHead(
            title: "Drawing style",
            says:
                "How the character is drawn: its lines, its shading and light, "
                "its colour and the finish of the page. 2D and 3D are both looks "
                "of the same character.",
            resetLabel: "As $name",
            onReset: look == from ? null : () => onChanged(from, name),
          ),
          StudioPills<String>(
            key: const ValueKey("look-looks"),
            id: "look-looks",
            label: "Look",
            value: name,
            options: [for (final n in characterLooks.keys) (n, n)],
            onChanged: (n) => onChanged(characterLooks[n]!, n),
          ),
          pills("lineStyle", "Lines"),
          const SizedBox(height: 6),
          slider("width", "Outline"),
          slider("inner", "Inner lines"),
          pills("lineMode", "Line colour"),
          StudioSwatches(
            id: "look-ink",
            label: "Ink",
            palette: _ink,
            value: look.lineColour,
            onPick: (c) => set(look.withLineColour(c ?? from.lineColour)),
          ),
          pills("fill", "Fill"),
          if (look.fill == "flat") ...[
            const SizedBox(height: 6),
            slider("levels", "Tones"),
          ],
          pills("shading", "Shading"),
          const SizedBox(height: 6),
          slider("amount", "Shadow"),
          slider("bands", "Tone bands"),
          pills("shadowTint", "Shadow colour"),
          pills("highlight", "Highlights"),
          const SizedBox(height: 6),
          slider("shine", "Highlight"),
          pills("light", "Light from"),
          const StudioLabel("Colour"),
          slider("sat", "Saturation", min: -1),
          slider("bright", "Brightness", min: -1),
          slider("warmth", "Warmth", min: -1),
          pills("render", "Finish"),
          const SizedBox(height: 6),
          if (r == "manga") slider("tone", "Screentone"),
          if (r == "manga" || r == "comic") slider("contrast", "Contrast"),
          if (r == "pencil" || r == "sketch") slider("hatch", "Hatching"),
          if (r == "pencil" || r == "watercolour")
            slider("wash", "Colour wash"),
          if (r == "watercolour") ...[
            slider("bleed", "Bleed"),
            slider("edge", "Pooled edges")
          ],
          if (r == "painterly") slider("brush", "Brush size"),
          if (r == "comic") slider("dots", "Dot size"),
          if (const ["pencil", "watercolour", "painterly", "sketch"]
              .contains(r))
            slider("paper", "Paper grain"),
          StudioSwatches(
            id: "look-paper",
            label: "Paper",
            palette: _paper,
            value: look.paperColour,
            onPick: (c) => set(look.withPaperColour(c ?? from.paperColour)),
          ),
        ]);
  }
}

import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// type_parts.dart is how words are set, a control at a time, for the
// rebuilt settings panel (see panel_parts.dart): the face, the size and the
// colour for a quick strip, and the rest of the letters for a Look. One
// control for each, the same on every element that draws words.

/// TypeEdit is how a control changes [spec]: [onChanged] for each step of
/// a drag, [begin] and [commit] around a change made at once.
class TypeEdit {
  final TextSpec spec;
  final ValueChanged<TextSpec> onChanged;
  final VoidCallback begin;
  final VoidCallback commit;
  const TypeEdit(this.spec, this.onChanged, this.begin, this.commit);

  /// now changes it at once, as one step.
  void now(TextSpec next) {
    begin();
    onChanged(next);
    commit();
  }
}

/// typeFont is the face.
Widget typeFont(TypeEdit t) => CanvasDropdown<String>(
      key: const ValueKey("typeFont"),
      label: "Font",
      value: t.spec.fontFamily,
      width: 120,
      options: [for (var f in canvasFonts) (f, f)],
      onChanged: (v) => t.now(t.spec.copyWith(fontFamily: v)),
    );

/// typeSize is the size; [fitted] says it is worked out from the box, so a
/// size typed there is one wanted and the caller stops the fitting.
Widget typeSize(TypeEdit t, {bool fitted = false}) => CanvasNumberField(
      key: const ValueKey("typeSize"),
      label: fitted ? "Size (fitted)" : "Size",
      value: t.spec.fontSize,
      min: 1,
      max: 800,
      width: 64,
      onChanged: (v) => t.onChanged(t.spec.copyWith(fontSize: v)),
      onCommit: t.commit,
    );

/// typeColour is the words' colour, or a fade from one to another.
Widget typeColour(TypeEdit t) => CanvasColorButton(
      key: const ValueKey("typeColour"),
      label: "Colour",
      color: t.spec.color,
      gradient: t.spec.fade,
      onChanged: (c) => t.now(t.spec.copyWith(color: c)),
      onGradientChanged: (g) => t.now(g == null
          ? t.spec.copyWith(flatText: true)
          : t.spec.copyWith(fade: g)),
    );

/// typeAlign is how the lines line up across the box.
Widget typeAlign(TypeEdit t) => CanvasSegmented<TextAlignSpec>(
      key: const ValueKey("typeAlign"),
      label: "Align",
      value: t.spec.align,
      options: const [
        (TextAlignSpec.left, "Left"),
        (TextAlignSpec.center, "Centre"),
        (TextAlignSpec.right, "Right"),
      ],
      keyOf: (a) => "typeAlign-${a.name}",
      onChanged: (v) => t.now(t.spec.copyWith(align: v)),
    );

/// typeLetters is the rest of how the letters are set: their weight and
/// slant, their spacing, how they sit up and down the box, their case.
List<Widget> typeLetters(TypeEdit t,
        {bool underline = true,
        bool vertical = true,
        bool justify = true,
        bool textCase = true}) =>
    [
      CanvasDropdown<int>(
        key: const ValueKey("typeWeight"),
        label: "Weight",
        value: t.spec.weight,
        width: 104,
        options: const [
          (100, "Thin"),
          (300, "Light"),
          (400, "Regular"),
          (500, "Medium"),
          (600, "Semibold"),
          (700, "Bold"),
          (800, "Extrabold"),
          (900, "Black"),
        ],
        onChanged: (v) => t.now(t.spec.copyWith(weight: v)),
      ),
      CanvasIconButton(
        key: const ValueKey("typeItalic"),
        icon: Icons.format_italic,
        tooltip: "Italic",
        active: t.spec.italic,
        onPressed: () => t.now(t.spec.copyWith(italic: !t.spec.italic)),
      ),
      if (underline)
        CanvasIconButton(
          key: const ValueKey("typeUnderline"),
          icon: Icons.format_underlined,
          tooltip: "Underline",
          active: t.spec.underline,
          onPressed: () => t.now(t.spec.copyWith(underline: !t.spec.underline)),
        ),
      const CanvasLineBreak(),
      CanvasNumberField(
        key: const ValueKey("typeLetter"),
        label: "Letter",
        value: t.spec.letterSpacing,
        min: -50,
        max: 200,
        decimals: 1,
        width: 64,
        onChanged: (v) => t.onChanged(t.spec.copyWith(letterSpacing: v)),
        onCommit: t.commit,
      ),
      CanvasNumberField(
        key: const ValueKey("typeLine"),
        label: "Line",
        value: t.spec.lineHeight,
        min: 0.5,
        max: 5,
        decimals: 2,
        width: 64,
        onChanged: (v) => t.onChanged(t.spec.copyWith(lineHeight: v)),
        onCommit: t.commit,
      ),
      if (vertical || textCase) const CanvasLineBreak(),
      if (justify)
        CanvasToggle(
          key: const ValueKey("typeJustify"),
          label: "Justified",
          value: t.spec.align == TextAlignSpec.justify,
          onChanged: (v) => t.now(t.spec
              .copyWith(align: v ? TextAlignSpec.justify : TextAlignSpec.left)),
        ),
      if (vertical)
        CanvasDropdown<VerticalAlignSpec>(
          key: const ValueKey("typeVertical"),
          label: "Up and down",
          value: t.spec.verticalAlign,
          width: 96,
          options: [for (var a in VerticalAlignSpec.values) (a, a.label)],
          onChanged: (v) => t.now(t.spec.copyWith(verticalAlign: v)),
        ),
      if (textCase)
        CanvasDropdown<TextCase>(
          key: const ValueKey("typeCase"),
          label: "Case",
          value: t.spec.textCase,
          width: 104,
          options: [for (var c in TextCase.values) (c, c.label)],
          onChanged: (v) => t.now(t.spec.copyWith(textCase: v)),
        ),
    ];

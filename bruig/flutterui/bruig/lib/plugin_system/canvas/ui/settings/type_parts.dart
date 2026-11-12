import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
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
      iconOf: (a) => switch (a) {
        TextAlignSpec.left => Icons.format_align_left,
        TextAlignSpec.center => Icons.format_align_center,
        TextAlignSpec.right => Icons.format_align_right,
        TextAlignSpec.justify => Icons.format_align_justify,
      },
      onChanged: (v) => t.now(t.spec.copyWith(align: v)),
    );

/// typeLetters is the rest of how the letters are set, in rows as the
/// prototype has them: weight, letter and line spacing side by side, the
/// switches each a line, and how they sit up and down beside their case.
List<Widget> typeLetters(TypeEdit t,
        {bool underline = true,
        bool vertical = true,
        bool justify = true,
        bool textCase = true}) =>
    [
      panelRow([
        cell(CanvasNumberField(
          key: const ValueKey("typeWeight"),
          label: "Weight",
          value: t.spec.weight.toDouble(),
          min: 100,
          max: 900,
          step: 100,
          width: 60,
          onChanged: (v) => t.onChanged(t.spec.copyWith(weight: v.round())),
          onCommit: t.commit,
        )),
        cell(CanvasNumberField(
          key: const ValueKey("typeLetter"),
          label: "Letter",
          value: t.spec.letterSpacing,
          min: -50,
          max: 200,
          decimals: 1,
          width: 60,
          onChanged: (v) => t.onChanged(t.spec.copyWith(letterSpacing: v)),
          onCommit: t.commit,
        )),
        cell(CanvasNumberField(
          key: const ValueKey("typeLine"),
          label: "Line",
          value: t.spec.lineHeight,
          min: 0.5,
          max: 5,
          decimals: 2,
          width: 60,
          onChanged: (v) => t.onChanged(t.spec.copyWith(lineHeight: v)),
          onCommit: t.commit,
        )),
      ]),
      CanvasToggle(
        key: const ValueKey("typeItalic"),
        label: "Italic",
        value: t.spec.italic,
        onChanged: (v) => t.now(t.spec.copyWith(italic: v)),
      ),
      if (underline)
        CanvasToggle(
          key: const ValueKey("typeUnderline"),
          label: "Underline",
          value: t.spec.underline,
          onChanged: (v) => t.now(t.spec.copyWith(underline: v)),
        ),
      if (justify)
        CanvasToggle(
          key: const ValueKey("typeJustify"),
          label: "Justified",
          value: t.spec.align == TextAlignSpec.justify,
          onChanged: (v) => t.now(t.spec
              .copyWith(align: v ? TextAlignSpec.justify : TextAlignSpec.left)),
        ),
      if (vertical || textCase)
        panelRow([
          if (vertical)
            cell(CanvasDropdown<VerticalAlignSpec>(
              key: const ValueKey("typeVertical"),
              label: "Up and down",
              value: t.spec.verticalAlign,
              width: 80,
              options: [for (var a in VerticalAlignSpec.values) (a, a.label)],
              onChanged: (v) => t.now(t.spec.copyWith(verticalAlign: v)),
            )),
          if (textCase)
            cell(CanvasDropdown<TextCase>(
              key: const ValueKey("typeCase"),
              label: "Case",
              value: t.spec.textCase,
              width: 80,
              options: [for (var c in TextCase.values) (c, c.label)],
              onChanged: (v) => t.now(t.spec.copyWith(textCase: v)),
            )),
        ]),
    ];

/// labelType is the words on an element that is not a text -- a shape's
/// label, a button's, a counter's -- set as a text's are: the face and its
/// size, its colour and how it lines up, then its letters (Ken, 2026-11-12:
/// one control for each, the same on every element). Their shadow, glow
/// and outline are the element's looks, not the label's own.
Widget labelType(TypeEdit t,
        {String label = "Label type", String remember = "label"}) =>
    CanvasControlGroup(
        key: ValueKey("${remember}Type"),
        label: label,
        rule: false,
        children: [
          panelRow([
            cell(typeFont(t), flex: 3, min: 120),
            cell(typeSize(t), width: 132),
          ]),
          panelRow([
            cell(typeColour(t), width: 104),
            cell(typeAlign(t), flex: 2, min: 120),
          ]),
          ...typeLetters(t, vertical: false, justify: false),
        ]);

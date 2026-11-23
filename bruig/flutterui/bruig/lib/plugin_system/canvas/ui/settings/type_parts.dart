import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:flutter/material.dart';

// type_parts.dart is how words are set, a control at a time (see
// panel_parts.dart), the same on every element that draws words.
//
// It holds two kits for the same thing. The controls a piece at a time
// (typeFont, typeSize, typeLetters and labelType built from them) are what
// a text, a shape's label, a table, a button and a counter's number and
// words use.
// typeGroups is a second, whole set in two "more" groups, weight as a list
// and italic as a button where the other kit has a number and a switch; a
// team's names and a counter's buttons use it.

/// TypeEdit is how a control changes [spec]: [onChanged] for each step of a
/// drag, [begin] and [commit] round a one-go change.
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

/// fontOptions is a face dropdown's choices: canvasFonts, after [current]
/// where a received canvas names a face not among them, so the dropdown
/// says what the words are set in rather than nothing.
List<(String, String)> fontOptions(String current) => [
      if (current.isNotEmpty && !canvasFonts.contains(current))
        (current, current),
      for (var f in canvasFonts) (f, f),
    ];

Widget typeFont(TypeEdit t) => CanvasDropdown<String>(
      key: const ValueKey("typeFont"),
      label: "Font",
      value: t.spec.fontFamily,
      width: 120,
      options: fontOptions(t.spec.fontFamily),
      onChanged: (v) => t.now(t.spec.copyWith(fontFamily: v)),
    );

/// typeSize is the size; [fitted] says it comes from the box, so a typed
/// size is a wanted one and the caller stops the fitting.
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

/// typeAlign is how the lines align across the box.
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

/// typeJustify sets the lines justified across the box, or, off, to the
/// left.
Widget typeJustify(TypeEdit t) => CanvasToggle(
      key: const ValueKey("typeJustify"),
      label: "Justified",
      value: t.spec.align == TextAlignSpec.justify,
      onChanged: (v) => t.now(t.spec
          .copyWith(align: v ? TextAlignSpec.justify : TextAlignSpec.left)),
    );

/// typeVertical is where the lines sit in a box taller than they are.
Widget typeVertical(TypeEdit t) => CanvasDropdown<VerticalAlignSpec>(
      key: const ValueKey("typeVertical"),
      label: "Up and down",
      value: t.spec.verticalAlign,
      width: 80,
      options: [for (var a in VerticalAlignSpec.values) (a, a.label)],
      onChanged: (v) => t.now(t.spec.copyWith(verticalAlign: v)),
    );

/// typeCaseButtons is the case as a row of buttons, where a panel has room
/// for one rather than typeLetters' dropdown: [key] names the row and
/// [keyOf], if given, each button.
Widget typeCaseButtons(TypeEdit t,
        {required Key key, String Function(TextCase)? keyOf}) =>
    CanvasSegmented<TextCase>(
      key: key,
      label: "Case",
      value: t.spec.textCase,
      options: const [
        (TextCase.none, "As typed"),
        (TextCase.upper, "UPPER"),
        (TextCase.lower, "lower"),
        (TextCase.title, "Title"),
      ],
      keyOf: keyOf,
      onChanged: (v) => t.now(t.spec.copyWith(textCase: v)),
    );

/// typeLetters is the rest of the letters' setting: weight and spacing side
/// by side, the switches a line each, baseline beside case.
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
      if (justify) typeJustify(t),
      if (vertical || textCase)
        panelRow([
          if (vertical) cell(typeVertical(t)),
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

/// labelType is a non-text element's label (shape, button, counter), set as
/// a text's is; shadow, glow and outline are the element's looks.
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

/// typeGroups is the shared type controls for elements that draw words.
List<Widget> typeGroups(
  TextSpec spec,
  ValueChanged<TextSpec> onChanged,
  VoidCallback begin,
  VoidCallback commit, {
  String label = "Type",

  /// hideCaption drops the first caption where the section says it already.
  bool hideCaption = false,

  /// remember prefixes the two buttons' open state, so a panel with three
  /// sets (a counter's number, words and buttons) does not open all three.
  String remember = "type",

  /// rule draws the line under each group; off where they run on into what
  /// follows as one subject (a text element's face, colour and box).
  bool rule = true,
}) {
  var t = TypeEdit(spec, onChanged, begin, commit);
  return [
    CanvasMoreGroup(
        label: label,
        hideCaption: hideCaption,
        rule: rule,
        remember: "${remember}Type",
        tooltip: "Spacing, alignment and case",
        row: _faceRow(t),
        more: _spacingMore(t)),
    CanvasMoreGroup(
        label: "Colour",
        rule: rule,
        remember: "${remember}Colour",
        tooltip: "The shadow and the glow",
        row: _colourRow(t),
        more: _lightMore(t)),
  ];
}

/// _faceRow is the face, its size and weight, then italic and underline.
List<Widget> _faceRow(TypeEdit t) {
  var spec = t.spec;
  return [
    CanvasDropdown<String>(
      label: "Font",
      value: spec.fontFamily,
      // Least widths, not widths: six things share the line, and
      // wider minimums push the switches down in a narrow sidebar.
      width: 60,
      options: [for (var f in canvasFonts) (f, f)],
      onChanged: (v) => t.now(spec.copyWith(fontFamily: v)),
    ),
    CanvasNumberField(
      key: const ValueKey("typeSize"),
      label: "Size",
      value: spec.fontSize,
      min: 1,
      max: 800,
      width: 44,
      onChanged: (v) => t.onChanged(spec.copyWith(fontSize: v)),
      onCommit: t.commit,
    ),
    CanvasDropdown<int>(
      label: "Weight",
      value: spec.weight,
      width: 56,
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
      onChanged: (v) => t.now(spec.copyWith(weight: v)),
    ),
    // Italic and underline, which end the type row.
    CanvasIconButton(
      icon: Icons.format_italic,
      tooltip: "Italic",
      active: spec.italic,
      onPressed: () => t.now(spec.copyWith(italic: !spec.italic)),
    ),
    CanvasIconButton(
      icon: Icons.format_underlined,
      tooltip: "Underline",
      active: spec.underline,
      onPressed: () => t.now(spec.copyWith(underline: !spec.underline)),
    ),
  ];
}

/// _spacingMore is what is behind the type row's button: spacing between
/// letters and lines, alignment both ways, and case.
List<Widget> _spacingMore(TypeEdit t) {
  var spec = t.spec;
  return [
    CanvasNumberField(
      label: "Letter",
      value: spec.letterSpacing,
      min: -50,
      max: 200,
      decimals: 1,
      width: 54,
      onChanged: (v) => t.onChanged(spec.copyWith(letterSpacing: v)),
      onCommit: t.commit,
    ),
    CanvasNumberField(
      label: "Line",
      value: spec.lineHeight,
      min: 0.5,
      max: 5,
      decimals: 2,
      width: 54,
      onChanged: (v) => t.onChanged(spec.copyWith(lineHeight: v)),
      onCommit: t.commit,
    ),
    CanvasDropdown<TextAlignSpec>(
      label: "Align",
      value: spec.align,
      width: 92,
      options: [for (var a in TextAlignSpec.values) (a, a.label)],
      onChanged: (v) => t.now(spec.copyWith(align: v)),
    ),
    CanvasDropdown<VerticalAlignSpec>(
      label: "Vertical",
      value: spec.verticalAlign,
      width: 86,
      options: [for (var a in VerticalAlignSpec.values) (a, a.label)],
      onChanged: (v) => t.now(spec.copyWith(verticalAlign: v)),
    ),
    CanvasDropdown<TextCase>(
      label: "Case",
      value: spec.textCase,
      width: 96,
      options: [for (var c in TextCase.values) (c, c.label)],
      onChanged: (v) => t.now(spec.copyWith(textCase: v)),
    ),
  ];
}

/// _colourRow is the colour, first, as it is what is changed first; then
/// the outline's and the shadow's amount and colour.
List<Widget> _colourRow(TypeEdit t) {
  var spec = t.spec;
  return [
    // The swatch can fade the words between two colours across their box,
    // unless outlined or filled with a picture or pattern. See TextSpec.fade.
    CanvasColorButton(
      label: "Colour",
      color: spec.color,
      gradient: spec.fade,
      onChanged: (c) => t.now(spec.copyWith(color: c)),
      onGradientChanged: (g) => t.now(
          g == null ? spec.copyWith(flatText: true) : spec.copyWith(fade: g)),
    ),
    CanvasNumberField(
      label: "Outline",
      value: spec.outlineWidth,
      min: 0,
      max: 60,
      decimals: 1,
      width: 54,
      onChanged: (v) => t.onChanged(spec.copyWith(outlineWidth: v)),
      onCommit: t.commit,
    ),
    // No caption: it is the outline's colour, beside its thickness.
    CanvasColorButton(
      color: spec.outlineColor,
      onChanged: (c) => t.now(spec.copyWith(outlineColor: c)),
    ),
    // The shadow's amount and colour with them: two of each in the same
    // shape read as one line rather than four things.
    CanvasNumberField(
      label: "Shadow",
      value: spec.shadowBlur,
      min: 0,
      max: 120,
      width: 54,
      onChanged: (v) => t.onChanged(spec.copyWith(shadowBlur: v)),
      onCommit: t.commit,
    ),
    CanvasColorButton(
      color: spec.shadowColor,
      onChanged: (c) => t.now(spec.copyWith(shadowColor: c)),
    ),
  ];
}

/// _lightMore is what is behind the colour row's button: where the light
/// falls from, and the glow.
List<Widget> _lightMore(TypeEdit t) {
  var spec = t.spec;
  return [
    // Where the light is, not where the shadow goes: one light for a scene,
    // the same two numbers on every element in it.
    CanvasNumberField(
      key: const ValueKey("textShadowAngle"),
      label: "Direction",
      value: spec.shadowAngle,
      min: 0,
      max: 360,
      width: 60,
      onChanged: (v) => t.onChanged(spec.copyWith(shadowAngle: v)),
      onCommit: t.commit,
    ),
    CanvasNumberField(
      key: const ValueKey("textShadowDistance"),
      label: "Distance",
      value: spec.shadowDistance,
      min: 0,
      max: 400,
      decimals: 1,
      width: 60,
      onChanged: (v) => t.onChanged(spec.copyWith(shadowDistance: v)),
      onCommit: t.commit,
    ),
    CanvasNumberField(
      key: const ValueKey("textGlow"),
      label: "Glow",
      value: spec.glowBlur,
      min: 0,
      max: 200,
      width: 54,
      onChanged: (v) => t.onChanged(spec.copyWith(glowBlur: v)),
      onCommit: t.commit,
    ),
    CanvasColorButton(
      label: "Light",
      color: spec.glowColor,
      onChanged: (c) => t.now(spec.copyWith(glowColor: c)),
    ),
    if (spec.shadowDistance > 0 || spec.shadowBlur > 0)
      const CanvasHint(
          "Direction is where the light is, read like a compass: 0 is "
          "straight up, 90 to the right. The shadow falls the other way, "
          "Distance away from the words. At a distance of 0 it sits "
          "directly underneath them, which is a shadow that reads as a "
          "glow in its own colour."),
    if (spec.glowBlur > 0)
      const CanvasHint(
          "Glow is light all round the letters, in its own colour, and it "
          "is drawn behind them — so a picture or a pattern showing "
          "through the words cannot cut it up, and an outline sits over "
          "it rather than under it."),
  ];
}

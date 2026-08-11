import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// inputs.dart is the "Input Areas" area: one background,
// border and shape for every text input in the app, so the chat composer,
// the feed's post and comment boxes and the search bars stop each looking
// slightly different from the others.
//
// Every setting starts at its "leave it alone" value, so an untouched
// theme renders exactly as it did before the area existed.
List<Widget> inputAreasAreaEditor(AreaEditorContext ctx) => [
      ctx.colorPick(
        "Background",
        value: ctx.style.resolveInputBackgroundColor(ctx.theme),
        valueIndex: ctx.style.inputBackgroundColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearInputBackgroundColor: true,
                clearInputBackgroundColorIndex: true)
            : s.copyWith(
                inputBackgroundColor: c,
                inputBackgroundColorIndex: i,
                clearInputBackgroundColorIndex: i == null)),
      ),
      ctx.note("The fill inside every input box. Default leaves each one "
          "transparent, as it is now."),
      ctx.colorPick(
        "Border color",
        value: ctx.style.resolveInputBorderColor(ctx.theme),
        valueIndex: ctx.style.inputBorderColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearInputBorderColor: true, clearInputBorderColorIndex: true)
            : s.copyWith(
                inputBorderColor: c,
                inputBorderColorIndex: i,
                clearInputBorderColorIndex: i == null)),
      ),
      ctx.note("Defaults to the palette's Input Selected Color."),
      ctx.slider("inputBorderWidth", ctx.style.inputBorderWidth,
          label: (v) => v <= 0
              ? "Border width: Default"
              : "Border width: ${v.toStringAsFixed(1)}",
          max: 6,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(inputBorderWidth: v))),
      ctx.slider("inputBorderRadius", ctx.style.inputBorderRadius,
          label: (v) => v <= 0
              ? "Border radius: Default"
              : "Border radius: ${v.toStringAsFixed(1)}",
          max: 40,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(inputBorderRadius: v))),
    ];

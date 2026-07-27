import 'package:bruig/theming_system/area_fill.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_login.dart is the "Login Screen" area's own settings.
//
// Unlike every other area, its one setting belongs *with* the background
// fill editor rather than after it -- it picks between the two built-in
// background looks, and so only applies while the background is still on
// Default (a custom solid/gradient/image fill replaces it entirely). It's
// rendered from theming_areas_section.dart right below the background
// editor for that reason.
List<Widget> loginAreaBackgroundEditor(AreaEditorContext ctx) {
  if (ctx.area != ThemeArea.loginScreen ||
      ctx.style.mode != AreaBackgroundMode.token) {
    return const [];
  }
  return [
    const SizedBox(height: 12),
    ctx.choice<LoginBackgroundPreset>(
      "Background preset",
      value: ctx.style.loginBgPreset,
      options: LoginBackgroundPreset.values,
      labelOf: loginBackgroundPresetLabel,
      onChanged: (p) => ctx.setStyle((s) => s.copyWith(loginBgPreset: p)),
    ),
  ];
}

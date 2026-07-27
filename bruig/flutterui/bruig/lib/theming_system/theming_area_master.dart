import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_master.dart is the "Master" area's own settings: the app-wide
// chrome toggles that don't belong to any single screen. The Settings screen
// isn't itself a ThemeArea, so its restyle rides here too.
List<Widget> masterAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Settings page restyle",
        subtitle: "Icon + highlight rows in the Settings page's left nav, "
            "and a card-based layout for the Account page",
        value: ctx.style.settingsShellRestyle,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(settingsShellRestyle: v)),
      ),
      ctx.toggle(
        "Monochrome avatars",
        subtitle: "Uses a graphite-gray fallback avatar instead of a "
            "colorful hashed hue (real avatar images are unaffected) "
            "-- applies to every avatar in the app",
        value: ctx.style.monochromeAvatars,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(monochromeAvatars: v)),
      ),
    ];

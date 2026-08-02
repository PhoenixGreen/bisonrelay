import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_header.dart is the "Header" area's own settings: where the
// header sits, how tall it is, and how its logo/title are laid out.
List<Widget> headerAreaEditor(AreaEditorContext ctx) => [
      ctx.choice<HeaderPosition>(
        "Position",
        value: ctx.style.headerPosition ?? HeaderPosition.top,
        options: HeaderPosition.values,
        labelOf: headerPositionLabel,
        onChanged: (p) => ctx.setStyle((s) => s.copyWith(headerPosition: p)),
      ),
      const SizedBox(height: 12),
      // Edited here, but it replaces the Bison Relay icon everywhere the
      // app draws it -- the header, the nav bar and the About button --
      // each at that place's own size. Clearing it (the X) is the "reset
      // to the Bison Relay icon" route; the thumbnail shows that icon
      // whenever nothing of the user's own is set.
      const Txt("App icon"),
      const SizedBox(height: 4),
      Row(children: [
        ctx.imagePreview(
          ctx.style.logoPath,
          assetFallback: "assets/images/icon.png",
          onPick: () async {
            var relPath = await ctx.pickImage(
                suffix: "logo", dialogTitle: "Pick app icon", allowSvg: true);
            if (relPath != null) {
              ctx.setStyle((s) => s.copyWith(logoPath: relPath));
            }
          },
        ),
        if (ctx.style.logoPath != null)
          IconButton(
            onPressed: () =>
                ctx.setStyle((s) => s.copyWith(clearLogoPath: true)),
            icon: const Icon(Icons.close),
            tooltip: "Reset to Bison Relay icon",
          ),
      ]),
      const SizedBox(height: 8),
      ctx.slider("logoSize", ctx.style.logoSize ?? 40,
          label: (v) => "Logo size: ${v.toStringAsFixed(1)}",
          min: 16,
          max: 80,
          onCommit: (v) => ctx.setStyle((s) => s.copyWith(logoSize: v))),
      ctx.slider("loginLogoSize", ctx.style.loginLogoSize ?? 24,
          label: (v) => "Login Custom Logo Size: ${v.toStringAsFixed(1)}",
          min: 16,
          max: 96,
          onCommit: (v) => ctx.setStyle((s) => s.copyWith(loginLogoSize: v))),
      ctx.slider("height", ctx.style.height ?? 56,
          label: (v) => "Height: ${v.toStringAsFixed(1)}",
          min: 40,
          max: 120,
          onCommit: (v) => ctx.setStyle((s) => s.copyWith(height: v))),
      ctx.choice<ContentAlign>(
        "Text align",
        value: ctx.style.contentAlign ?? ContentAlign.center,
        options: ContentAlign.values,
        labelOf: contentAlignLabel,
        onChanged: (a) => ctx.setStyle((s) => s.copyWith(contentAlign: a)),
      ),
    ];

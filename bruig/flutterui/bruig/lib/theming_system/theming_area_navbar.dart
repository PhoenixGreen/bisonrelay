import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_navbar.dart is the "Navigation Bar" area's own settings. Its
// width/padding/margin aren't editable -- the third-party sidebarx package
// composes its own fixed layout and animates off specific width values (see
// theming_areas_section.dart).
List<Widget> navBarAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Show logo",
        subtitle: "Displays the Bison Relay logo at the top of the nav bar -- "
            "useful when the header is set to Content or None",
        value: ctx.style.showLogo,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(showLogo: v)),
      ),
      if (ctx.style.showLogo) ...[
        ctx.slider("logoSize", ctx.style.logoSize ?? 32,
            label: (v) => "Logo size: ${v.toStringAsFixed(1)}",
            min: 16,
            max: 80,
            onCommit: (v) => ctx.setStyle((s) => s.copyWith(logoSize: v))),
        ctx.choice<ContentAlign>(
          "Logo position",
          value: ctx.style.logoAlign ?? ContentAlign.center,
          // hidden doesn't apply here -- showLogo above already covers
          // visibility.
          options: const [
            ContentAlign.start,
            ContentAlign.center,
            ContentAlign.end
          ],
          labelOf: contentAlignLabel,
          onChanged: (a) => ctx.setStyle((s) => s.copyWith(logoAlign: a)),
        ),
      ],
    ];

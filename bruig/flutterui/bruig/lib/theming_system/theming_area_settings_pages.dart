import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_settings_pages.dart is the "Settings Pages" area: the three
// Settings pages that have a look of their own -- Account, Stats and Logs --
// edited together rather than as three near-empty entries in the area
// picker. Each is labelled and divided below so it's still clear which page
// a setting belongs to.
//
// They carry no background/border/spacing of their own; that's Dual Panel's,
// which wraps every page's sidebar and content as one region.
// The bare section labels below carry no padding of their own, unlike the
// toggles and dropdowns other areas open with -- hence the explicit space at
// the top (off the area picker above) and the bottom (off the panel edge).
List<Widget> settingsPagesAreaEditor(AreaEditorContext ctx) => [
      const SizedBox(height: 20),
      const Txt.S("Account"),
      ctx.toggle(
        "Card layout",
        subtitle: "Groups the page into Identity/Relay Counter/Account "
            "cards, with a camera badge on the avatar, instead of a plain "
            "list",
        value: ctx.style.accountCardLayout,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(accountCardLayout: v)),
      ),
      const Divider(height: 28),
      const Txt.S("Stats"),
      ctx.toggle(
        "Redesigned stats page",
        subtitle: "Total sent/received summary cards and redesigned rows "
            "with an avatar and an inline sent-amount bar chart on "
            "the Payment Stats page",
        value: ctx.style.payStatsCardStyle,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(payStatsCardStyle: v)),
      ),
      const Divider(height: 28),
      const Txt.S("Logs"),
      ctx.note("No settings of its own yet."),
      const SizedBox(height: 20),
    ];

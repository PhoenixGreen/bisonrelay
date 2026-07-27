import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_account.dart is the "Account Page" area's own settings --
// Settings > Account, the one Settings page with a layout of its own worth
// choosing between.
//
// This used to be half of a "Settings page restyle" toggle on the Master
// area. Its other half restyled the Settings left nav with icon + pill-
// highlight rows, which is dropped: the Sidebar area's own "Show icons" and
// "List Rounded Corners" settings already do that, for every sidebar in the
// app rather than just this one screen's.
List<Widget> accountAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Card layout",
        subtitle: "Groups the page into Identity/Relay Counter/Account "
            "cards, with a camera badge on the avatar, instead of a plain "
            "list",
        value: ctx.style.accountCardLayout,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(accountCardLayout: v)),
      ),
    ];

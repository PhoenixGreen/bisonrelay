import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// pages.dart is the "Pages" area's own settings: the reader's half of how
// somebody else's page is drawn.
//
// Only a half, deliberately. A page states its width and its background in
// the page itself, because the page bytes are the only thing that reaches a
// reader -- see components/feed/markdown_page.dart. These two say what this
// reader will allow of that. The page knows its design, the reader knows
// their screen, and neither can answer for the other.
//
// The colour is the same bargain read the other way: the page says *that* it
// wants to sit on something, in a word that means the same in a dark theme
// and a light one, and this says what that word comes out as here.
List<Widget> pagesAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  return [
    ctx.slider("pagesWidthCap", style.pagesWidthCap,
        label: (v) => v == 0
            ? "Maximum page width: As the page asks"
            : "Maximum page width: ${v.toStringAsFixed(0)} px",
        max: 2000,
        divisions: 40,
        onCommit: (v) => ctx.setStyle((s) => s.copyWith(pagesWidthCap: v))),
    ctx.colorPick(
      "Page background color",
      value: style.pagesBackgroundColor,
      valueIndex: style.pagesBackgroundColorIndex,
      noneLabel: "As the page asks",
      onChanged: (c, i) => ctx.setStyle((s) => c == null
          ? s.copyWith(
              clearPagesBackgroundColor: true,
              clearPagesBackgroundColorIndex: true)
          : s.copyWith(pagesBackgroundColor: c, pagesBackgroundColorIndex: i)),
    ),
    ctx.toggle(
      "Let a page choose its own background",
      subtitle: "A page may sit on a raised or quiet surface of your theme. "
          "Turn this off to draw every page on this area's background "
          "instead",
      value: style.pagesHonourBackground,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(pagesHonourBackground: v)),
    ),
  ];
}

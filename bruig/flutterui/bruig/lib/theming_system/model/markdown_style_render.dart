import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// markdown_style_render.dart is the guide's rendering half: it folds a
// MarkdownStyleGuide onto the stylesheet the reader's theme already built.
//
// Onto rather than instead of. A guide states the few things it cares about
// and everything else is left exactly as the theme had it, which is what
// lets one guide read correctly in a light theme and a dark one without
// being written twice.

/// applyGuide returns [base] with [guide]'s rules folded in.
///
/// [roleColor] resolves the small set of colour roles a guide can name
/// against the live theme -- see MarkdownRole.
/// [base] must be the sheet as it will actually render -- every field
/// filled in -- and not one that still has nulls for MarkdownBody to
/// resolve later. A guide adjusts what is there; it is not a place to
/// invent values that had not been worked out yet.
MarkdownStyleSheet applyGuide(
  MarkdownStyleSheet base,
  MarkdownStyleGuide guide,
  Color Function(MarkdownRole) roleColor, {
  Color? Function(int)? paletteColor,
}) {
  TextStyle on(TextStyle? from, TextRule rule) =>
      rule.applyTo(from ?? const TextStyle(fontSize: 14), roleColor,
          paletteColor: paletteColor);

  WrapAlignment wrap(MarkdownAlign align) => switch (align) {
        MarkdownAlign.left => WrapAlignment.start,
        MarkdownAlign.center => WrapAlignment.center,
        MarkdownAlign.right => WrapAlignment.end,
        MarkdownAlign.inherit => base.textAlign,
      };

  var quoteBar =
      guide.quoteBarInk.resolve(roleColor, paletteColor: paletteColor);
  var quoteBack =
      guide.quoteBackground.resolve(roleColor, paletteColor: paletteColor);
  var codeBack =
      guide.codeBackground.resolve(roleColor, paletteColor: paletteColor);
  var rule = guide.ruleInk.resolve(roleColor, paletteColor: paletteColor);
  var tableEdge =
      guide.tableBorderInk.resolve(roleColor, paletteColor: paletteColor);

  return base.copyWith(
    p: on(base.p, guide.body),
    h1: on(base.h1, guide.headings[0]),
    h2: on(base.h2, guide.headings[1]),
    h3: on(base.h3, guide.headings[2]),
    h4: on(base.h4, guide.headings[3]),
    h5: on(base.h5, guide.headings[4]),
    h6: on(base.h6, guide.headings[5]),
    a: on(base.a, guide.link),
    strong: on(base.strong, guide.strong),
    em: on(base.em, guide.emphasis),
    blockquote: on(base.blockquote, guide.quote),
    code: on(base.code, guide.code),
    listBullet: on(base.listBullet, guide.listBullet),
    tableHead: on(base.tableHead, guide.tableHead),
    tableBody: on(base.tableBody, guide.tableBody),
    // flutter_markdown has one spacing figure and puts it between every
    // pair of block children -- paragraphs and list items alike (see
    // _addBlockChild in its builder). The two want different numbers: prose
    // reads better with a clear gap, and a list with that same gap between
    // every bullet falls apart into unrelated lines.
    //
    // So the shared figure is set to the smaller of the two, and paragraphs
    // make up the difference with padding of their own, which nothing else
    // uses.
    blockSpacing: guide.listItemGap.clamp(0, 48),
    pPadding: EdgeInsets.only(
        bottom: (guide.blockGap - guide.listItemGap).clamp(0, 48)),
    listIndent: guide.listIndent.clamp(8, 64),
    textAlign: wrap(guide.bodyAlign),
    // The quote's bar and background are one decoration, so a guide that
    // sets only one of them has to keep whatever the theme put in the
    // other.
    // Built from the theme's own quote decoration every time, overriding
    // only the parts the guide names.
    //
    // It used to be rebuilt only when the guide named a colour, which broke
    // it two ways at once: setting the bar's width while leaving its colour
    // alone did nothing at all, and setting the background alone deleted the
    // bar, because the branch that built the decoration wrote a null border
    // whenever no bar colour had been given.
    blockquoteDecoration: _quoteDecoration(base, guide, quoteBar, quoteBack),
    codeblockDecoration: codeBack == null
        ? base.codeblockDecoration
        : BoxDecoration(color: codeBack),
    horizontalRuleDecoration: rule == null
        ? base.horizontalRuleDecoration
        : BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: rule, width: guide.ruleThickness.clamp(0.5, 8)))),
    tableBorder: tableEdge == null
        ? base.tableBorder
        : TableBorder.all(
            color: tableEdge, width: guide.tableBorderWidth.clamp(0, 6)),
  );
}

/// _quoteDecoration is the theme's quote styling with the guide's changes.
Decoration _quoteDecoration(
  MarkdownStyleSheet base,
  MarkdownStyleGuide guide,
  Color? barInk,
  Color? background,
) {
  var existing = base.blockquoteDecoration is BoxDecoration
      ? base.blockquoteDecoration as BoxDecoration
      : null;
  // The bar's colour falls back to whatever the theme was already drawing,
  // so a guide can widen a bar without having to restate its colour.
  // BoxBorder does not expose its sides; only Border does, and that is what
  // a quote's bar is drawn with.
  var existingBorder =
      existing?.border is Border ? existing!.border as Border : null;
  var barColor = barInk ?? existingBorder?.left.color;
  var width = guide.quoteBarWidth.clamp(0.0, 12.0);
  return BoxDecoration(
    color: background ?? existing?.color,
    border: barColor == null || width == 0
        ? null
        : Border(left: BorderSide(color: barColor, width: width)),
  );
}

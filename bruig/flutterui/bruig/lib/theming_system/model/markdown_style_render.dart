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
  // The body first, because every other size is a share of it.
  var body = guide.body.applyTo(
      base.p ?? const TextStyle(fontSize: 14), roleColor,
      paletteColor: paletteColor);
  var bodySize = body.fontSize ?? 14;

  /// on folds one rule onto the theme's style for that element, measuring
  /// the rule's scale against the body rather than against whatever size the
  /// theme happened to give that element.
  ///
  /// The editor says "Size: 190% of body text" and the guides are written
  /// that way, so that is what it has to mean. Applied to the theme's own
  /// style it did not: MarkdownStyleSheet.fromTheme sets h1 from
  /// headlineSmall, so Article's 1.9 was 1.9 times *that* -- an h1 at some
  /// 325% of the body, and inline code at 85% of it while the editor read
  /// 100%. The composer's preview already scaled from the body, so the two
  /// disagreed about the same guide.
  TextStyle on(TextStyle? from, TextRule rule) => rule.applyTo(
      (from ?? const TextStyle()).copyWith(fontSize: bodySize), roleColor,
      paletteColor: paletteColor);

  /// onInline is [on] for a run inside a line rather than a line of its own:
  /// bold, italic, a link.
  ///
  /// flutter_markdown builds these by merging their style onto the style of
  /// whatever they sit in, so a size stated here replaces the surrounding
  /// text's -- and a bold word inside a heading would come out at body size.
  /// At 100% nothing is stated and the run keeps the size around it; a rule
  /// that does ask for a different size gets a share of the body, which is
  /// what the editor's slider says.
  TextStyle onInline(TextStyle? from, TextRule rule) => rule.applyTo(
      rule.scale == 1.0
          ? (from ?? const TextStyle())
          : (from ?? const TextStyle()).copyWith(fontSize: bodySize),
      roleColor,
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
  var tableHead =
      guide.tableHeadBackground.resolve(roleColor, paletteColor: paletteColor);
  var tableStripe =
      guide.tableStripeInk.resolve(roleColor, paletteColor: paletteColor);

  var sheet = base.copyWith(
    p: body,
    h1: on(base.h1, guide.headings[0]),
    h2: on(base.h2, guide.headings[1]),
    h3: on(base.h3, guide.headings[2]),
    h4: on(base.h4, guide.headings[3]),
    h5: on(base.h5, guide.headings[4]),
    h6: on(base.h6, guide.headings[5]),
    // Links, bold and italic are runs inside a line, so they keep the size
    // of whatever they sit in unless the guide asks otherwise. Folded on as
    // block elements were, a rule saying "100% of body text" pinned them to
    // a flat 14 points -- so a link read at the old size for anyone who had
    // scaled their body text up, and a bold word inside a heading came out
    // no bigger than the paragraph below it.
    a: onInline(base.a, guide.link),
    strong: onInline(base.strong, guide.strong),
    em: onInline(base.em, guide.emphasis),
    blockquote: on(base.blockquote, guide.quote),
    // The block's colour goes behind the letters as well as behind the
    // block, so the two agree exactly and a code block reads as one shape.
    //
    // MarkdownStyleSheet.fromTheme paints `code` on the card colour, and
    // that survives into every sheet built from it -- a second background,
    // a different colour from the block's, folded around the text and
    // breaking between the lines. Matching it to the block makes it vanish
    // there and gives inline code the same tint everywhere else.
    code: on(base.code, guide.code)
        .copyWith(backgroundColor: codeBack ?? Colors.transparent),
    listBullet: on(base.listBullet, guide.listBullet),
    tableHead: on(base.tableHead, guide.tableHead),
    tableBody: on(base.tableBody, guide.tableBody),
    // The space between blocks, and the space between the items of a list,
    // which are two different numbers: prose reads better with a clear gap
    // between paragraphs, and a list with that same gap between every
    // bullet falls apart into unrelated lines.
    //
    // Upstream flutter_markdown has one figure and puts it between every
    // pair of block children, list items included, so this used to set it
    // to the smaller of the two and have paragraphs make up the difference
    // with padding of their own. Only paragraphs can do that -- there is no
    // such padding for a quotation, a code block, a table or a rule -- so
    // everything else sat hard against whatever came before it, and the
    // blank line the writer left between a heading and a quotation produced
    // no space at all. The vendored copy takes both figures; see
    // MarkdownStyleSheet.listItemSpacing.
    blockSpacing: guide.blockGap.clamp(0, 48),
    listItemSpacing: guide.listItemGap.clamp(0, 48),
    pPadding: EdgeInsets.zero,
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
    // The space between the bar and the words, and around the rest of it.
    // Without it the two sit hard against each other.
    blockquotePadding: EdgeInsets.all(guide.quotePadding.clamp(0, 40)),
    codeblockDecoration: codeBack == null
        ? base.codeblockDecoration
        : BoxDecoration(color: codeBack),
    // The guide's own figure, or the built-in 8 it has always been.
    codeblockPadding: guide.codePadding == null
        ? base.codeblockPadding
        : EdgeInsets.all(guide.codePadding!.clamp(0, 48)),
    horizontalRuleDecoration: rule == null
        ? base.horizontalRuleDecoration
        : BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: rule, width: guide.ruleThickness.clamp(0.5, 8)))),
    // Width zero is "no grid", not a hairline: BorderSide treats 0 as the
    // thinnest line it can draw rather than as nothing, so the slider's
    // bottom stop has to be spelled out as an absent border.
    // The header row and every other body row, which are what make a table
    // readable across as well as down. Upstream has no header decoration at
    // all -- see the vendored copy.
    tableHeadDecoration:
        tableHead == null ? null : BoxDecoration(color: tableHead),
    tableCellsDecoration:
        tableStripe == null ? null : BoxDecoration(color: tableStripe),
    tableCellsPadding: EdgeInsets.symmetric(
        horizontal: (guide.tableCellPadding * 1.5).clamp(0, 48),
        vertical: guide.tableCellPadding.clamp(0, 32)),
    tableColumnWidth: switch (guide.tableFit) {
      MarkdownTableFit.fitContent => const IntrinsicColumnWidth(),
      MarkdownTableFit.equal => const FlexColumnWidth(),
    },
    tableBorder: tableEdge == null
        ? base.tableBorder
        : (guide.tableBorderWidth <= 0
            ? const TableBorder()
            : TableBorder.all(
                color: tableEdge, width: guide.tableBorderWidth.clamp(0, 6))),
  );

  // copyWith rebuilds the sheet's tag map from its fields, and that map sets
  // <pre> -- what a fenced code block parses to -- from the paragraph style.
  // Code is set in the code face wherever it appears, so both the block tag
  // and the attached-text-file tag are pointed at it again, exactly as the
  // theme's own sheet does.
  sheet.styles["pre"] = sheet.code;
  sheet.styles["embedtext"] = sheet.code;
  return sheet;
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

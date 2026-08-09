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
MarkdownStyleSheet applyGuide(
  MarkdownStyleSheet base,
  MarkdownStyleGuide guide,
  Color Function(MarkdownRole) roleColor, {
  required TextStyle bodyStyle,
}) {
  TextStyle on(TextStyle? from, TextRule rule) =>
      rule.applyTo(from ?? bodyStyle, roleColor);

  WrapAlignment wrap(MarkdownAlign align) => switch (align) {
        MarkdownAlign.left => WrapAlignment.start,
        MarkdownAlign.center => WrapAlignment.center,
        MarkdownAlign.right => WrapAlignment.end,
        MarkdownAlign.inherit => base.textAlign,
      };

  var quoteBar = guide.quoteBarInk.resolve(roleColor);
  var quoteBack = guide.quoteBackground.resolve(roleColor);
  var codeBack = guide.codeBackground.resolve(roleColor);
  var rule = guide.ruleInk.resolve(roleColor);
  var tableEdge = guide.tableBorderInk.resolve(roleColor);

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
    blockSpacing: guide.blockGap.clamp(0, 48),
    listIndent: guide.listIndent.clamp(8, 64),
    textAlign: wrap(guide.bodyAlign),
    // The quote's bar and background are one decoration, so a guide that
    // sets only one of them has to keep whatever the theme put in the
    // other.
    blockquoteDecoration: (quoteBar == null && quoteBack == null)
        ? base.blockquoteDecoration
        : BoxDecoration(
            color: quoteBack ??
                (base.blockquoteDecoration is BoxDecoration
                    ? (base.blockquoteDecoration as BoxDecoration).color
                    : null),
            border: quoteBar == null
                ? null
                : Border(
                    left: BorderSide(
                        color: quoteBar,
                        width: guide.quoteBarWidth.clamp(0, 12))),
          ),
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

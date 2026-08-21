import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_nav.dart is a bar of links, and where one sits in a banner.
//
// Its own file rather than the header's: a bar is a block in its own right,
// written anywhere on a page, and only happens to be what most headers put
// in their nav field. Split out when the header outgrew them sharing one.

/// NavStyle is the shape of a bar of links. The writer picks one, because it
/// is part of how the page is laid out; what each looks like is the reader's,
/// through NavRule and the palette.
enum NavStyle {
  /// Words with space between them.
  plain,

  /// Each link in a filled, rounded box.
  pills,

  /// A line under each link.
  underline,

  /// Each link in an outlined box.
  boxed;

  static NavStyle parse(String? raw) {
    for (var s in NavStyle.values) {
      if (s.name == (raw ?? "").toLowerCase().trim()) return s;
    }
    return NavStyle.plain;
  }
}

/// NavBlockSyntax reads a bar of links.
///
///     --nav[pills]--
///     [Home](index.md)
///     [About](about.md)
///     --/nav--
///
/// One link a line, which is what makes it a bar rather than a paragraph
/// that happens to contain links: the writer says what is in it and the
/// reader's theme says what it looks like, so a bar written once reads
/// correctly on a narrow window and in somebody else's colours.
///
/// A reader whose client does not know it sees the links, one a line, in
/// order -- which is still the navigation, just not drawn as a bar.
class NavBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--nav(?:\[(\w+)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/nav--\s*$');

  /// The most links one bar may hold. Past this it is not navigation.
  static const maxLinks = 24;

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var style =
        NavStyle.parse(_open.firstMatch(parser.current.content)?.group(1));
    parser.advance();

    var links = <String>[];
    while (!parser.isDone) {
      var at = parser.current.content;
      if (_close.hasMatch(at)) {
        parser.advance();
        break;
      }
      var text = at.trim();
      if (text.isNotEmpty && links.length < maxLinks) links.add(text);
      parser.advance();
    }

    var element = md.Element.text("nav", "");
    element.attributes["style"] = style.name;
    element.attributes["count"] = "${links.length}";
    for (var i = 0; i < links.length; i++) {
      element.attributes["l$i"] = links[i];
    }
    return md.Element("p", [element]);
  }
}

class NavMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var count = int.tryParse(element.attributes["count"] ?? "") ?? 0;
    return _MarkdownNav(
      links: [for (var i = 0; i < count; i++) element.attributes["l$i"] ?? ""],
      style: NavStyle.parse(element.attributes["style"]),
    );
  }
}

class _MarkdownNav extends StatelessWidget {
  final List<String> links;
  final NavStyle style;
  const _MarkdownNav({required this.links, required this.style});

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.navOf(context) ?? const NavRule();
    var ink = theme.markdownInk(rule.ink) ?? theme.colors.primary;

    // Each link is markdown of its own, so a link is a link -- followed the
    // same way as one in a paragraph, br:// and all.
    Widget item(String text) {
      var inner = MarkdownArea(text, false);
      switch (style) {
        case NavStyle.plain:
          return inner;
        case NavStyle.pills:
          return Container(
            padding: EdgeInsets.symmetric(
                horizontal: rule.boundedPadding,
                vertical: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(rule.boundedRadius),
            ),
            child: inner,
          );
        case NavStyle.boxed:
          return Container(
            padding: EdgeInsets.symmetric(
                horizontal: rule.boundedPadding,
                vertical: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              border: Border.all(color: ink, width: rule.boundedBorder),
              borderRadius: BorderRadius.circular(rule.boundedRadius),
            ),
            child: inner,
          );
        case NavStyle.underline:
          return Container(
            padding: EdgeInsets.only(bottom: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: ink, width: rule.boundedBorder)),
            ),
            child: inner,
          );
      }
    }

    // Which way the bar runs, when it is in a banner's row. A block fills
    // the width it is given, so a bar in a centred row would otherwise
    // start at the left of it and look nothing like centred.
    var within = HeaderCellAlign.of(context);
    var across = switch (within) {
      Alignment.center => WrapAlignment.center,
      Alignment.centerRight => WrapAlignment.end,
      _ => WrapAlignment.start,
    };

    // Wrapped rather than a Row: a bar of six links in a narrow window is
    // two rows of three, not six squeezed columns.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: rule.boundedGap / 2),
      child: Wrap(
        spacing: rule.boundedGap,
        runSpacing: rule.boundedGap / 2,
        alignment: across,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (var l in links) item(l)],
      ),
    );
  }
}

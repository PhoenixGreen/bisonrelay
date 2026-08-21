import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/markdown_rules.dart';
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

/// navLink splits "[label](target)" into its two halves.
///
/// A bar's links are drawn here rather than handed to the markdown renderer,
/// which is what lets them take the bar's own colour, light up under the
/// pointer and mark the page being read. Through the renderer they were
/// whatever a link is in body text, and the bar's colour setting reached
/// only the pill drawn round them -- which is why setting it appeared to do
/// nothing.
({String label, String target})? navLink(String raw) {
  var m = RegExp(r'^\s*\[([^\]]*)\]\(([^)]*)\)\s*$').firstMatch(raw);
  if (m == null) return null;
  return (label: m.group(1)!.trim(), target: m.group(2)!.trim());
}

/// NavCurrentPage is the page being read, so a bar can mark the link to it.
///
/// Provided by whatever is showing a page. Absent everywhere else -- a bar in
/// a post has no current page -- and a bar then marks nothing, which is
/// right.
class NavCurrentPage extends InheritedWidget {
  final String path;
  const NavCurrentPage({required this.path, required super.child, super.key});

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavCurrentPage>()?.path;

  @override
  bool updateShouldNotify(NavCurrentPage old) => old.path != path;
}

class _MarkdownNav extends StatefulWidget {
  final List<String> links;
  final NavStyle style;
  const _MarkdownNav({required this.links, required this.style});

  @override
  State<_MarkdownNav> createState() => _MarkdownNavState();
}

class _MarkdownNavState extends State<_MarkdownNav> {
  int? _under;

  /// _isCurrent is whether a link points at the page being read.
  ///
  /// Compared on the last part of the path only. A bar written as
  /// "[Home](index.md)" is the same link whether the page was reached as
  /// "index.md" or as a whole br:// address, and a reader should not have to
  /// write it twice.
  bool _isCurrent(String target, String? here) {
    if (here == null || target.isEmpty) return false;
    String tail(String s) =>
        s.split("/").where((p) => p.isNotEmpty).lastOrNull ?? s;
    return tail(target).toLowerCase() == tail(here).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    var links = widget.links;
    if (links.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.navOf(context) ?? const NavRule();
    var here = NavCurrentPage.of(context);

    Color? inkOf(MarkdownInk i) => i.resolve(theme.markdownRoleColor,
        paletteColor: theme.markdownPaletteColor);

    var base = inkOf(rule.ink) ?? theme.markdownRoleColor(MarkdownRole.link);
    var hover = inkOf(rule.hover) ?? base;
    var current = inkOf(rule.active) ?? base;
    var background = inkOf(rule.background);

    Widget item(int index, String raw) {
      var parsed = navLink(raw);
      // Not a link: shown as it was written rather than dropped, so a typo
      // is visible instead of silently costing an entry.
      if (parsed == null) {
        return Text(raw, style: TextStyle(color: base));
      }

      var isHere = _isCurrent(parsed.target, here);
      var colour = _under == index ? hover : (isHere ? current : base);

      Widget label = Text(
        parsed.label,
        style: TextStyle(
          color: colour,
          fontWeight: isHere ? FontWeight.bold : FontWeight.normal,
          decoration:
              widget.style == NavStyle.underline ? TextDecoration.none : null,
        ),
      );

      Widget body;
      switch (widget.style) {
        case NavStyle.plain:
          body = label;
          break;
        case NavStyle.pills:
          body = Container(
            padding: EdgeInsets.symmetric(
                horizontal: rule.boundedPadding,
                vertical: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: _under == index ? 0.26 : 0.12),
              borderRadius: BorderRadius.circular(rule.boundedRadius),
            ),
            child: label,
          );
          break;
        case NavStyle.boxed:
          body = Container(
            padding: EdgeInsets.symmetric(
                horizontal: rule.boundedPadding,
                vertical: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              border: Border.all(color: colour, width: rule.boundedBorder),
              borderRadius: BorderRadius.circular(rule.boundedRadius),
            ),
            child: label,
          );
          break;
        case NavStyle.underline:
          body = Container(
            padding: EdgeInsets.only(bottom: rule.boundedPadding / 2),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: colour,
                      width: isHere || _under == index
                          ? rule.boundedBorder * 2
                          : rule.boundedBorder)),
            ),
            child: label,
          );
          break;
      }

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _under = index),
        onExit: (_) => setState(() => _under = null),
        child: GestureDetector(
          onTap: () => followMarkdownLink(context, parsed.target),
          child: body,
        ),
      );
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
    Widget bar = Padding(
      padding: EdgeInsets.symmetric(vertical: rule.boundedGap / 2),
      child: Wrap(
        spacing: rule.boundedGap,
        runSpacing: rule.boundedGap / 2,
        alignment: across,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (var i = 0; i < links.length; i++) item(i, links[i])],
      ),
    );

    if (background != null) {
      // Across the whole width when asked, which is what makes a bar in a
      // row flush to an edge read as a strip along it rather than a patch
      // behind the words.
      bar = Container(
        width: rule.fullWidth ? double.infinity : null,
        alignment: rule.fullWidth ? Alignment.center : null,
        color: background,
        child: bar,
      );
    }

    return bar;
  }
}

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
  static final _open = RegExp(r'^\s*--nav(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/nav--\s*$');

  /// The most links one bar may hold. Past this it is not navigation.
  static const maxLinks = 24;

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var written = NavWritten.parse(
        _open.firstMatch(parser.current.content)?.group(1));
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
    element.attributes["style"] = written.style.name;
    written.attributes.forEach((k, v) => element.attributes[k] = v);
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
      written: NavWritten.fromAttributes(element.attributes),
    );
  }
}

/// parseNavHex reads #rgb, #rrggbb or #rrggbbaa, the way a banner's colours
/// are written. Anything else is nothing.
Color? parseNavHex(String? raw) {
  var t = (raw ?? "").trim();
  if (!t.startsWith("#")) return null;
  var hex = t.substring(1);
  if (hex.length == 3) hex = hex.split("").map((c) => "$c$c").join();
  var argb = switch (hex.length) {
    6 => "ff$hex",
    8 => hex.substring(6) + hex.substring(0, 6),
    _ => null,
  };
  if (argb == null) return null;
  var n = int.tryParse(argb, radix: 16);
  return n == null ? null : Color(n);
}

/// hexOfColour writes one back out, keeping the alpha only when there is
/// some to keep.
String hexOfColour(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, "0");
  var rgb = "#${two(c.r)}${two(c.g)}${two(c.b)}";
  return c.a >= 1.0 ? rgb : "$rgb${two(c.a)}";
}

/// NavAlign is which way a bar of links runs.
enum NavAlign {
  left,
  center,
  right;

  static NavAlign? parse(String? raw) {
    var t = (raw ?? "").trim().toLowerCase();
    if (t == "centre" || t == "middle") return NavAlign.center;
    for (var a in NavAlign.values) {
      if (a.name == t) return a;
    }
    return null;
  }
}

/// NavWritten is what a page said about one bar, as opposed to what the
/// reader's theme says about every bar.
///
/// The theme decides how bars look, which is where it belongs: a reader who
/// has set their Markdown theme should see every page in it. But a bar is
/// also a piece of a page's layout -- whether it sits left or centred, how
/// far it is from what is above it -- and that is the page's business, not
/// the reader's. So anything written here wins for this bar, and anything
/// left out falls through to the theme, which is what every bar did before
/// any of this could be written.
///
/// Written as --nav[pills, align=left, gap=12]--: the bare word is the
/// style, as it always was, and the rest are settings.
@immutable
class NavWritten {
  final NavStyle style;
  final NavAlign? align;
  final double? gap;
  final double? padding;
  final EdgeInsets? margin;
  final double? radius;

  /// background is what the bar sits on, or null to leave it to the theme.
  ///
  /// A colour or a role, because a bar lives in two places and they want
  /// different answers. On a page it belongs to the reader's palette like
  /// everything else, so a role is right. In a banner it sits over a
  /// picture the writer chose, and only they can know what will read
  /// against it -- which is the same bargain a banner's own writing makes.
  final MarkdownInk? background;

  /// height is how tall the bar is, whatever is in it. A strip along the
  /// edge of a banner has a height the row gives it; one on a page has
  /// none unless it is asked for.
  final double? height;

  /// fullWidth runs the bar's background the whole way across, or null to
  /// leave it to the theme.
  final bool? fullWidth;

  const NavWritten({
    this.style = NavStyle.plain,
    this.align,
    this.gap,
    this.padding,
    this.margin,
    this.radius,
    this.background,
    this.height,
    this.fullWidth,
  });

  static const none = NavWritten();

  static double? _number(String? raw, double most) {
    var n = double.tryParse((raw ?? "").trim());
    if (n == null || n < 0) return null;
    return n > most ? most : n;
  }

  /// _space reads room around the bar the way it is written everywhere else:
  /// one number for all four sides, two for down-and-up then across, four
  /// for each side from the top going clockwise.
  static EdgeInsets? _space(String? raw) {
    var parts = (raw ?? "")
        .trim()
        .split(RegExp(r'[\s]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    var got = [for (var p in parts) _number(p, 200)];
    if (got.isEmpty || got.any((v) => v == null)) return null;
    var n = got.cast<double>();
    return switch (n.length) {
      1 => EdgeInsets.all(n[0]),
      2 => EdgeInsets.symmetric(vertical: n[0], horizontal: n[1]),
      3 => EdgeInsets.fromLTRB(n[1], n[0], n[1], n[2]),
      _ => EdgeInsets.fromLTRB(n[3], n[0], n[1], n[2]),
    };
  }

  /// parse reads what is between the brackets.
  ///
  /// A setting it does not know is ignored rather than guessed at, and one
  /// whose value will not read leaves that setting to the theme rather than
  /// the whole bar. A bar with a typo in its gap is still a bar.
  /// _colour reads either a role from the reader's palette or a hex colour.
  ///
  /// "none" is neither, and means no background at all rather than the
  /// theme's -- a bar that says none has said something, and falling
  /// through to the theme would be ignoring it.
  static MarkdownInk? _colour(String? raw) {
    var t = (raw ?? "").trim();
    if (t.isEmpty) return null;
    if (t.toLowerCase() == "none") return MarkdownInk.inherit;
    for (var r in MarkdownRole.values) {
      if (r.name.toLowerCase() == t.toLowerCase()) return MarkdownInk.of(r);
    }
    var hex = parseNavHex(t);
    return hex == null ? null : MarkdownInk.literal(hex);
  }

  static NavWritten parse(String? attributes) {
    if (attributes == null || attributes.trim().isEmpty) return none;

    var style = NavStyle.plain;
    var fields = <String, String>{};
    for (var part in attributes.split(",")) {
      var at = part.indexOf("=");
      if (at == -1) {
        // The bare word, which is the style and has been since before any
        // of the rest could be written.
        var bare = part.trim();
        if (bare.isNotEmpty) style = NavStyle.parse(bare);
        continue;
      }
      fields[part.substring(0, at).trim().toLowerCase()] =
          part.substring(at + 1).trim();
    }

    var width = (fields["width"] ?? "").toLowerCase();
    return NavWritten(
      style: style,
      align: NavAlign.parse(fields["align"]),
      gap: _number(fields["gap"], 64),
      padding: _number(fields["padding"], 64),
      margin: _space(fields["margin"]),
      radius: _number(fields["radius"], 64),
      background: _colour(fields["background"]),
      height: _number(fields["height"], 400),
      fullWidth: width.isEmpty ? null : (width == "full"),
    );
  }

  /// asAttributes is what parse read, so it can be carried on the element
  /// and read back on the other side. Only what was actually written.
  Map<String, String> get asAttributes => {
        if (align != null) "align": align!.name,
        if (gap != null) "gap": "$gap",
        if (padding != null) "padding": "$padding",
        if (margin != null)
          "margin": "${margin!.top} ${margin!.right} "
              "${margin!.bottom} ${margin!.left}",
        if (radius != null) "radius": "$radius",
        if (background != null)
          "background": background!.isInherit
              ? "none"
              : (background!.role?.name ?? hexOfColour(background!.literal!)),
        if (height != null) "height": "$height",
        if (fullWidth != null) "width": fullWidth! ? "full" : "fit",
      };

  Map<String, String> get attributes => asAttributes;

  static NavWritten fromAttributes(Map<String, String> a) => NavWritten(
        style: NavStyle.parse(a["style"]),
        align: NavAlign.parse(a["align"]),
        gap: double.tryParse(a["gap"] ?? ""),
        padding: double.tryParse(a["padding"] ?? ""),
        margin: _space(a["margin"]),
        radius: double.tryParse(a["radius"] ?? ""),
        background: _colour(a["background"]),
        height: double.tryParse(a["height"] ?? ""),
        fullWidth: a["width"] == null ? null : a["width"] == "full",
      );
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

  /// written is what the page said about this bar, over the theme's answer
  /// for every bar.
  final NavWritten written;
  const _MarkdownNav({
    required this.links,
    required this.style,
    this.written = NavWritten.none,
  });

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
    // What the page said about this bar, over what the theme says about
    // every bar. A background of "none" is an answer, not a blank: it means
    // no background rather than the theme's.
    var written = widget.written;
    var background = written.background == null
        ? inkOf(rule.background)
        : (written.background!.isInherit ? null : inkOf(written.background!));
    var radius = written.radius ?? rule.boundedRadius;

    var pad = written.padding ?? rule.boundedPadding;

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
                horizontal: pad, vertical: pad / 2),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: _under == index ? 0.26 : 0.12),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: label,
          );
          break;
        case NavStyle.boxed:
          body = Container(
            padding: EdgeInsets.symmetric(
                horizontal: pad, vertical: pad / 2),
            decoration: BoxDecoration(
              border: Border.all(color: colour, width: rule.boundedBorder),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: label,
          );
          break;
        case NavStyle.underline:
          body = Container(
            padding: EdgeInsets.only(bottom: pad / 2),
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
    // What the page said first, then the row it sits in. A bar written
    // align=left in a centred row is a bar somebody has asked to be left,
    // and the row is only the answer when nobody asked.
    var within = HeaderCellAlign.of(context);
    var across = switch (written.align) {
      NavAlign.left => WrapAlignment.start,
      NavAlign.center => WrapAlignment.center,
      NavAlign.right => WrapAlignment.end,
      null => switch (within) {
          Alignment.center => WrapAlignment.center,
          Alignment.centerRight => WrapAlignment.end,
          _ => WrapAlignment.start,
        },
    };
    var gap = written.gap ?? rule.boundedGap;
    var fullWidth = written.fullWidth ?? rule.fullWidth;

    // Wrapped rather than a Row: a bar of six links in a narrow window is
    // two rows of three, not six squeezed columns.
    Widget bar = Padding(
      padding: EdgeInsets.symmetric(vertical: gap / 2),
      child: Wrap(
        spacing: gap,
        runSpacing: gap / 2,
        alignment: across,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (var i = 0; i < links.length; i++) item(i, links[i])],
      ),
    );

    if (background != null || written.height != null) {
      // Across the whole width when asked, which is what makes a bar in a
      // row flush to an edge read as a strip along it rather than a patch
      // behind the words.
      bar = Container(
        width: fullWidth ? double.infinity : null,
        // The height belongs to the coloured part, not to something around
        // it: a strip asked to be 44 tall is 44 tall in its colour, with
        // the links held in the middle of it. Sized outside the colour, the
        // colour stayed the height of the words and the rest was a gap.
        height: written.height,
        // Centred only when nobody said otherwise. Running the background
        // the whole way across used to centre the links with it, so a bar
        // asked for as a strip along an edge could not also be a strip that
        // starts at the left.
        alignment: fullWidth || written.height != null
            ? switch (across) {
                WrapAlignment.start => Alignment.centerLeft,
                WrapAlignment.end => Alignment.centerRight,
                _ => Alignment.center,
              }
            : null,
        color: background,
        child: bar,
      );
    }

    // Outside the background, so a bar kept away from what is above it is
    // moved rather than padded -- padding would grow the strip instead.
    if (written.margin != null) {
      bar = Padding(padding: written.margin!, child: bar);
    }

    return bar;
  }
}

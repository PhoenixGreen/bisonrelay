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
    var written =
        NavWritten.parse(_open.firstMatch(parser.current.content)?.group(1));
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
      // --right-- divides the bar: what follows it is pushed to the far end.
      // A marker rather than a setting on each link, because it is one
      // decision about the bar -- where the second group starts.
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
  var m = _linkPattern.firstMatch(raw);
  if (m == null) return null;
  return (label: m.group(1)!.trim(), target: m.group(2)!.trim());
}

/// _linkPattern is one entry of a bar: a Markdown link, and settings of its
/// own after it.
///
///     [Cart](/cart)[badge=2, icon=cart, label=off]
///
/// The settings are written the way every other block here writes its own,
/// and a client that does not know them shows the link, which is what a bar
/// degrades to anyway.
final _linkPattern =
    RegExp(r'^\s*\[([^\]]*)\]\(([^)]*)\)\s*(?:\[([^\]]*)\])?\s*$');

/// NavEntry is one link of a bar, with whatever it said about itself.
@immutable
class NavEntry {
  final String label;
  final String target;

  /// badge is the number drawn over the link -- what is waiting behind it --
  /// or null for none. Nought is none: a cart with nothing in it should not
  /// wear a nought.
  final int? badge;

  /// icon is what it is drawn as, or null for words.
  final MarkdownCardIcon? icon;

  /// labelled is whether the words are drawn. Off, the icon stands alone and
  /// the words become what it is called when hovered -- which is the only
  /// place they can go without taking the room the icon saved.
  final bool labelled;

  /// active is whether this link is the page being read, said outright.
  ///
  /// A bar marks the link to the page it is on by comparing paths, which
  /// works for a site's own pages and cannot work for a section: a shop is a
  /// dozen paths -- the front, a product, the cart, an order -- and only one
  /// of them is what the link says. So whoever knows can say, and for a shop
  /// that is the shop, which is dressing the page in the first place.
  final bool active;

  /// plain is whether the bar's style is drawn round this link.
  ///
  /// A row of icons in pills is a row of buttons, which is a different thing
  /// from a row of icons -- and the shop's half of a bar is often wanted as
  /// the second while the site's half stays the first.
  final bool plain;

  const NavEntry({
    required this.label,
    required this.target,
    this.badge,
    this.icon,
    this.labelled = true,
    this.plain = false,
    this.active = false,
  });

  /// parse reads one line of a bar, or null for a line that is not a link.
  static NavEntry? parse(String raw) {
    var m = _linkPattern.firstMatch(raw);
    if (m == null) return null;

    var fields = <String, String>{};
    for (var part in (m.group(3) ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var badge = int.tryParse(fields["badge"] ?? "");
    return NavEntry(
      label: m.group(1)!.trim(),
      target: m.group(2)!.trim(),
      badge: badge == null || badge <= 0 ? null : badge,
      icon: MarkdownCardIcon.named(fields["icon"] ?? ""),
      labelled: (fields["label"] ?? "").toLowerCase() != "off",
      plain: (fields["plain"] ?? "").toLowerCase() == "on",
      active: (fields["active"] ?? "").toLowerCase() == "on",
    );
  }
}

/// _rightMarker divides a bar: what follows it is pushed to the far end.
///
/// It carries settings for the group it opens -- --right[gap=4]-- -- because
/// the two halves of a divided bar are not the same kind of thing. One is a
/// site's pages, read as words; the other is a shop's cart and orders, often
/// as icons, and icons want to sit closer together than words do.
final _rightMarker = RegExp(r'^\s*--right(?:\[([^\]]*)\])?--\s*$');

/// _rightSaid is what the marker said about the group it opens: the room
/// between its links, how large its icons are, and how far in from the end of
/// the bar it sits.
({double? gap, double? size, double? inset}) _rightSaid(String marker) {
  var fields = <String, String>{};
  for (var part
      in (_rightMarker.firstMatch(marker)?.group(1) ?? "").split(",")) {
    var at = part.indexOf("=");
    if (at == -1) continue;
    fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
        () => part.substring(at + 1).trim());
  }

  double? read(String key, double most) {
    var got = double.tryParse(fields[key] ?? "");
    return got == null || got < 0 || got > most ? null : got;
  }

  return (
    gap: read("gap", 64),
    size: read("size", 64),
    inset: read("inset", 64)
  );
}

/// _menuWidth is roughly how much room a folded group takes: one icon, the
/// padding round it, and the corner its count sits on.
const double _menuWidth = 44;

/// _collapseBelow is how narrow a bar has to be before its second group
/// becomes a menu.
///
/// A width rather than a measurement of the links themselves. What is being
/// asked is "is this a phone", and the answer that matters is the same for
/// every bar -- a threshold is predictable, and a bar that collapses at a
/// width somebody can find is a bar they can reason about.
const double _collapseBelow = 560;

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

  /// _badged draws the count over a link: what is waiting behind it.
  ///
  /// Over rather than beside, and small. A cart holding one thing is a fact
  /// somebody wants at a glance, and "(1)" written into the label is a
  /// different label -- it changes width as things go into the cart, which
  /// moves everything after it in the bar.
  Widget _badged(Widget label, int count, ThemeNotifier theme,
          {bool tight = false}) =>
      Stack(
        clipBehavior: Clip.none,
        children: [
          label,
          Positioned(
            // Tight is for a count on an icon that must not make its row
            // taller: it overlaps rather than sitting above.
            top: tight ? -2 : -6,
            right: tight ? -4 : -10,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? "99+" : "$count",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.onPrimary),
              ),
            ),
          ),
        ],
      );

  /// _twoGroups draws a bar divided by --right--: what was written before
  /// the marker at one end, what came after it at the other.
  ///
  /// Narrow enough and the second group becomes one button with a menu
  /// behind it. That group is the one that can be given up: it is a shop's
  /// cart and orders beside a site's own pages, and on a phone a row of
  /// nine links is not a bar, it is a wrap of three rows.
  Widget _twoGroups(
      BuildContext context,
      ThemeNotifier theme,
      List<String> links,
      int divide,
      Widget Function(int, String, {double? iconSize}) item,
      double gap,
      WrapAlignment across,
      Color ink,
      {required BoxConstraints constraints,
      required double pad}) {
    var left = [for (var i = 0; i < divide; i++) i];
    var right = [
      for (var i = divide + 1; i < links.length; i++)
        if (NavEntry.parse(links[i]) != null) i
    ];
    var said = _rightSaid(links[divide]);
    var rightGap = said.gap ?? gap;

    // The style the labels are measured in, which is not the ink they are
    // drawn in: one is how wide a word is, the other what colour it is.
    var measured = DefaultTextStyle.of(context).style;

    {
      // Which group gives way, and when.
      //
      // Measured rather than compared against a width, and that is the whole
      // of one bug. The second group took its natural width and the first
      // took whatever was left, so on a middling window the site's own links
      // -- the ones that must not go -- were squeezed to empty boxes while
      // the shop's icons sat there at full size. The group added to a bar is
      // the group that folds, so it folds as soon as keeping both would cost
      // the first one room it needs.
      var leftNeeds = _widthOf(left, links, measured, gap);
      var rightNeeds = _widthOf(right, links, measured, rightGap, said.size);
      var collapse = right.length > 1 &&
          (leftNeeds + gap + rightNeeds > constraints.maxWidth ||
              constraints.maxWidth < _collapseBelow ||
              _tooShort(constraints, measured, pad));

      // And when even that is not enough, the site's own links fold too.
      //
      // A bar cannot always answer by wrapping: this one is usually written
      // into a row of a banner, and a row has a height. Wrapped inside one,
      // the second line is simply cut off -- which is a bar showing whichever
      // of its links happened to land on the first line, and no way to reach
      // the rest. A menu holds all of them at any width.
      var folded = collapse ? _menuWidth : rightNeeds;
      var short = _tooShort(constraints, measured, pad);
      var foldLeft = left.length > 1 &&
          (leftNeeds + gap + folded > constraints.maxWidth || short);

      // The vertical padding belongs to the caller, which wraps both kinds
      // of bar in it: applied here as well it would be doubled, and the
      // strip behind a divided bar would be taller than one behind an
      // undivided one.
      return Row(children: [
        Expanded(
          child: foldLeft
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: _menu(context, theme, ink, links, left,
                      mark: Icons.menu, pad: pad),
                )
              : Wrap(
                  spacing: gap,
                  runSpacing: gap / 2,
                  alignment: across,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [for (var i in left) item(i, links[i])],
                ),
        ),
        SizedBox(width: gap),
        if (collapse)
          _menu(context, theme, ink, links, right, pad: pad)
        else
          Wrap(
            spacing: rightGap,
            runSpacing: rightGap / 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i in right) item(i, links[i], iconSize: said.size)
            ],
          ),
        // Room at the end of the bar, so what is last in it is not pressed
        // against the edge -- and so a count hung off the corner of the last
        // icon has somewhere to be.
        if (said.inset != null) SizedBox(width: said.inset),
      ]);
    }
  }

  /// _tooShort is whether the bar has been given less height than a row of
  /// links needs.
  ///
  /// A bar is usually written into a row of a banner, and a banner drawn in a
  /// narrow window scales itself down -- deliberately, so that a logo and a
  /// title keep their proportions. The bar is scaled with it, and its links
  /// are not: their words stay the size the reader reads at, so what happens
  /// as the window narrows is that the row gets shorter and the links stay
  /// the height they were, until what is left of them is a strip through the
  /// middle of some words. That is the state this catches -- a bar collapsed
  /// onto itself rather than folded.
  ///
  /// One icon in place of the words is both shorter and narrower, which is
  /// the only thing that still reads at that size.
  bool _tooShort(BoxConstraints constraints, TextStyle style, double pad) {
    // The room the cell has, which for a banner's cell is not the room it
    // was given: a block there is handed all the height it asks for and
    // clipped to the row afterwards, so its own constraints say nothing.
    var room = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : HeaderCellRoom.of(context);
    if (room == null) return false;

    // What is being asked is whether the words themselves still fit, not
    // whether the box around them does. A pill whose background is clipped by
    // a pixel or two is a bar that looks right; a row shorter than the
    // writing is a strip through the middle of some words.
    //
    // Measured rather than reckoned from the font size: a line is the font's
    // own height, not a multiple somebody guessed, and guessing it high folds
    // a bar that had room to spare -- which is a bar that is always a menu.
    var painter = TextPainter(
      text: TextSpan(text: "Ag", style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return room < painter.height + 4;
  }

  /// _widthOf is roughly how much room a group of links needs.
  ///
  /// Roughly is enough: what it decides is whether both groups fit, and a
  /// few pixels either way moves the point at which the second one folds by
  /// a few pixels. Measuring the words rather than counting the links is
  /// what matters -- "Home About Store" and "Documentation Contributing
  /// Downloads" are three links each and nothing like the same width.
  double _widthOf(
      List<int> group, List<String> links, TextStyle base, double gap,
      [double? iconSize]) {
    var rule = MarkdownGuideScope.navOf(context) ?? const NavRule();
    var pad = widget.written.padding ?? rule.boundedPadding;

    var total = 0.0;
    for (var i in group) {
      var entry = NavEntry.parse(links[i]);
      if (entry == null) continue;

      var wide = 0.0;
      if (entry.icon != null) {
        wide += (iconSize ?? 18) + (entry.labelled ? 6 : 0);
      }
      if (entry.labelled) {
        var painter = TextPainter(
          text: TextSpan(text: entry.label, style: base),
          textDirection: TextDirection.ltr,
        )..layout();
        wide += painter.width;
      }
      // The box round it, when there is one.
      if (!entry.plain && widget.style != NavStyle.plain) wide += pad * 2;
      total += wide + gap;
    }
    return total;
  }

  /// _menu is the second group when there is no room for it.
  Widget _menu(BuildContext context, ThemeNotifier theme, Color ink,
      List<String> links, List<int> right,
      {IconData? mark, double? pad}) {
    // What is waiting behind the whole menu, so a cart with something in it
    // is visible while the menu is shut.
    var waiting = 0;
    for (var i in right) {
      waiting += NavEntry.parse(links[i])?.badge ?? 0;
    }

    // The group's own first icon rather than three dots: this menu is one
    // thing -- the shop -- and a shop with a storefront on it says which menu
    // it is, where three dots say only that there is one.
    var own = NavEntry.parse(links[right.first])?.icon;
    var drawn = mark ?? own?.icon ?? Icons.more_horiz;

    // In the bar's own ink, which is what every link in it is drawn in. Set
    // from the link role instead, a folded group changed colour when it
    // folded -- the same links, the same bar, a different blue.
    Widget button = Icon(drawn, size: 20, color: ink);
    if (waiting > 0) {
      // The count overlaps the icon rather than being hung off it.
      //
      // Hung off the corner it needed room, and room is what a bar at the end
      // of a row has least of: given it above, the bar grew six pixels the
      // moment it folded and moved the banner it is written into; given it at
      // the side, the icon sat visibly further in than the links it replaced.
      // Overlapping, it needs neither -- the button's own padding is already
      // wider than the corner it hangs over.
      button = _badged(button, waiting, theme, tight: true);
    }

    return PopupMenuButton<String>(
      tooltip: "More",
      // No room of its own: a button carries a link's own padding below, and
      // this one's default eight on every side made a folded bar taller than
      // the same bar drawn out -- which moves the banner it sits in.
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (var i in right)
          if (NavEntry.parse(links[i]) case var entry?)
            PopupMenuItem(
              value: entry.target,
              child: Row(children: [
                if (entry.icon != null) ...[
                  Icon(entry.icon!.icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(entry.label)),
                if (entry.badge != null)
                  Text("${entry.badge}",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colors.primary)),
              ]),
            ),
      ],
      onSelected: (target) => followMarkdownLink(context, target),
      // The same room a link keeps inside its own box, so a bar is the same
      // height folded as it is drawn out. Sized differently, the banner it
      // sits in changed height with the window.
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: pad ?? 4, vertical: (pad ?? 8) / 2),
        child: button,
      ),
    );
  }

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

    Widget item(int index, String raw, {double? iconSize}) {
      var parsed = NavEntry.parse(raw);
      // Not a link: shown as it was written rather than dropped, so a typo
      // is visible instead of silently costing an entry.
      if (parsed == null) {
        return Text(raw, style: TextStyle(color: base));
      }

      var isHere = parsed.active || _isCurrent(parsed.target, here);
      var colour = _under == index ? hover : (isHere ? current : base);

      var words = Text(
        parsed.label,
        style: TextStyle(
          color: colour,
          fontWeight: isHere ? FontWeight.bold : FontWeight.normal,
          decoration:
              widget.style == NavStyle.underline ? TextDecoration.none : null,
        ),
      );

      // An icon, the words, or both. Words with no icon is what a bar has
      // always been, and is what a link that named no icon still gets.
      Widget label = parsed.icon == null
          ? words
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(parsed.icon!.icon, size: iconSize ?? 18, color: colour),
              if (parsed.labelled) ...[const SizedBox(width: 6), words],
            ]);

      if (parsed.badge != null) label = _badged(label, parsed.badge!, theme);

      // The words become the tooltip when they are not drawn: an icon on its
      // own is a guess until somebody hovers it, and a bar of guesses is not
      // navigation.
      if (!parsed.labelled && parsed.label.isNotEmpty) {
        label = Tooltip(message: parsed.label, child: label);
      }

      // A link that asked to be plain is drawn as the words or the icon it
      // is, whatever the bar's style: a row of icons in pills is a row of
      // buttons, which is a different thing from a row of icons.
      Widget body;
      switch (parsed.plain ? NavStyle.plain : widget.style) {
        case NavStyle.plain:
          body = label;
          break;
        case NavStyle.pills:
          body = Container(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad / 2),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: _under == index ? 0.26 : 0.12),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: label,
          );
          break;
        case NavStyle.boxed:
          body = Container(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad / 2),
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

    // Where the second group starts, if the bar has one.
    //
    // Built into the same bar as the undivided case rather than returned
    // from here, so that everything below applies to both. Returned early, a
    // divided bar lost the bar's own background, its height and its margin
    // -- and what that looks like is the strip behind the links stopping
    // where the first group does, which reads as the links having lost their
    // background rather than as the bar having lost its.
    var divide = links.indexWhere((l) => _rightMarker.hasMatch(l));

    // Wrapped rather than a Row: a bar of six links in a narrow window is
    // two rows of three, not six squeezed columns.
    // A bar that does not fit folds into a menu, divided or not.
    //
    // Wrapping is what a bar did before, and it is the wrong answer for a
    // reason that has nothing to do with taste: a bar is usually written into
    // a row of a banner, and a row has a height. The second line of a wrapped
    // bar is cut off by it -- so a narrow window produced a bar showing
    // whichever links happened to land on the first line, no way to reach the
    // rest, and a bar whose height changed with the window besides.
    Widget bar = Padding(
      padding: EdgeInsets.symmetric(vertical: gap / 2),
      child: LayoutBuilder(builder: (context, constraints) {
        if (divide != -1) {
          return _twoGroups(
              context, theme, links, divide, item, gap, across, base,
              constraints: constraints, pad: pad);
        }

        var all = [
          for (var i = 0; i < links.length; i++)
            if (NavEntry.parse(links[i]) != null) i
        ];
        var measured = DefaultTextStyle.of(context).style;
        if (all.length > 1 &&
            (_widthOf(all, links, measured, gap) > constraints.maxWidth ||
                _tooShort(constraints, measured, pad))) {
          return Align(
            alignment: switch (across) {
              WrapAlignment.center => Alignment.center,
              WrapAlignment.end => Alignment.centerRight,
              _ => Alignment.centerLeft,
            },
            child: _menu(context, theme, base, links, all,
                mark: Icons.menu, pad: pad),
          );
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap / 2,
          alignment: across,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (var i = 0; i < links.length; i++) item(i, links[i])],
        );
      }),
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

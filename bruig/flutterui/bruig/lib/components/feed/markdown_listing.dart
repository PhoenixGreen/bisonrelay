import 'package:bruig/components/feed/page_image.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_listing.dart is one item in a list of things, drawn as a
// composition rather than as a run of blocks:
//
//   --listing--
//   title: A guitar
//   link: product/gtr
//   summary: A lovely guitar with a spruce top
//   meta: $659.99
//   button: Buy Now
//   --/listing--
//
// Three rows: what it is, a line about it, and the line that ends in the
// thing to press.
//
// Built out of ordinary blocks first, and that is why this exists. A title, a
// paragraph and a two-column row is three blocks, and three blocks carry
// three blocks' worth of the reader's own paragraph spacing -- which is right
// for a page and much too airy for a card an inch and a half wide. The
// description wrapped to four lines on a narrow card and pushed the price out
// of sight; the two columns fell to one under a run of cards, so the price
// and the button stopped being a row at all; and the divider a run of columns
// draws put a rule down the middle of it.
//
// None of that is fixable from the outside, because each of those is the
// right behaviour for the block it belongs to. What a card wants is a fixed
// composition with its own spacing, one line of description whatever the
// width, and a row that stays a row.
//
// The fields are written one per line, the way --cards-- writes its own,
// rather than in brackets: a title or a price holds commas, and a comma is
// what separates one setting from the next inside brackets.

/// ListingRule is what one listing was written with.
@immutable
class ListingRule {
  final String title;
  final String link;
  final String summary;

  /// meta is the line beneath the summary -- a price, a date, a size --
  /// sitting opposite the button.
  final String meta;

  final String button;

  /// role is which of the app's buttons is drawn, or null for the ordinary
  /// one.
  final ButtonRole? role;

  /// align is which side the writing sits on.
  final CrossAxisAlignment align;

  /// lines is how much of the summary is shown before it is cut, and
  /// titleLines the same for the title.
  ///
  /// A title is one line by default here, unlike the summary, because a
  /// title that wraps is usually a title that should be shorter -- but the
  /// page says, because a shop selling things with long names would rather
  /// wrap than lose the end of every one.
  final int lines;
  final int titleLines;

  /// gap is the room between the title and the summary, and metaGap the room
  /// above the last row.
  ///
  /// Two, because they are not the same join. The summary belongs to the
  /// title above it and wants to sit close under it; the price and the
  /// button are the end of the card and usually want air above them.
  final double gap;
  final double metaGap;

  /// fill is what the button is coloured with, or null for whatever the
  /// app's own button of that role is.
  final MarkdownInk? fill;

  /// radius and padding are the button's own corners and the room inside
  /// it.
  final double radius;
  final double padding;

  /// image is a picture of the site's own shown beside the rows, or empty
  /// for none, and imageSize is how large a square it is drawn in.
  ///
  /// Beside rather than above: this is a thumbnail on a row of a list -- an
  /// order line, a product in a basket -- where the picture is what somebody
  /// recognises the row by and the rows still have to line up.
  final String image;
  final double imageSize;

  const ListingRule({
    this.title = "",
    this.link = "",
    this.summary = "",
    this.meta = "",
    this.button = "",
    this.role,
    this.align = CrossAxisAlignment.start,
    this.lines = 1,
    this.titleLines = 0,
    this.gap = 6,
    this.metaGap = 6,
    this.fill,
    this.radius = 8,
    this.padding = 12,
    this.image = "",
    this.imageSize = 48,
  });

  static ListingRule of(Map<String, String> fields) {
    ButtonRole? role;
    for (var r in ButtonRole.values) {
      if (r.name == fields["style"]?.toLowerCase()) role = r;
    }

    return ListingRule(
      title: fields["title"] ?? "",
      link: fields["link"] ?? "",
      summary: fields["summary"] ?? "",
      meta: fields["meta"] ?? fields["price"] ?? "",
      button: fields["button"] ?? "",
      role: role,
      align: switch (fields["align"]?.toLowerCase()) {
        "center" || "centre" || "middle" => CrossAxisAlignment.center,
        "right" || "end" => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      lines: int.tryParse(fields["lines"] ?? "")?.clamp(1, 6) ?? 1,
      // Nought is an answer: as many lines as the title takes.
      titleLines: int.tryParse(fields["titlelines"] ?? "")?.clamp(0, 6) ?? 0,
      gap: _length(fields["gap"], 6, 60),
      metaGap: _length(fields["metagap"], _length(fields["gap"], 6, 60), 60),
      fill: _ink(fields["color"]),
      radius: _length(fields["radius"], 8, 60),
      padding: _length(fields["padding"], 12, 40),
      // A path of this site's own and nothing else, the same bargain a
      // panel's background makes: a picture that could name a URL is every
      // page able to ask its reader's client to fetch from anywhere.
      image: isPageAssetPath(fields["image"] ?? "") ? fields["image"]! : "",
      imageSize: _length(fields["imagesize"], 48, 200),
    );
  }

  /// _length reads one of the numbers, bounded: these arrive from a page,
  /// and a button asking for a padding of ten thousand is a card nobody can
  /// read -- including the seller who typed it.
  static double _length(String? value, double fallback, double max) {
    var got = double.tryParse(value?.trim() ?? "");
    if (got == null || got < 0 || got > max) return fallback;
    return got;
  }

  /// _ink reads a colour written as a role's name or as #rrggbb.
  static MarkdownInk? _ink(String? value) {
    var written = value?.trim() ?? "";
    if (written.isEmpty) return null;
    for (var role in MarkdownRole.values) {
      if (role.name.toLowerCase() == written.toLowerCase()) {
        return MarkdownInk.of(role);
      }
    }
    var ink = MarkdownInk.fromJson(written);
    return ink.isInherit ? null : ink;
  }
}

class ListingBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--listing--\s*$');
  static final _close = RegExp(r'^\s*--/listing--\s*$');
  static final _field = RegExp(r'^\s*(\w+)\s*:\s*(.*)$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();

    var fields = <String, String>{};
    while (!parser.isDone) {
      var line = parser.current.content;
      if (_close.hasMatch(line)) {
        parser.advance();
        break;
      }
      var field = _field.firstMatch(line);
      if (field != null) {
        fields[field.group(1)!.toLowerCase()] = field.group(2)!.trim();
      }
      parser.advance();
    }

    var element = md.Element.text("listing", "");
    fields.forEach((key, value) => element.attributes[key] = value);

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks and handles
    // anything else as though it were already inside one.
    return md.Element("p", [element]);
  }
}

class ListingMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownListing(rule: ListingRule.of(element.attributes));
}

/// MarkdownListing draws the three rows.
class MarkdownListing extends StatelessWidget {
  final ListingRule rule;
  const MarkdownListing({required this.rule, super.key});

  /// _titleScale is how much larger the title is than the writing under it.
  ///
  /// A ratio rather than a size, so it follows whatever the reader is
  /// reading in. Deliberately small: this is the name of a thing in a list
  /// of things, not a heading on a page, and a card whose title is a heading
  /// is a card that is mostly title.
  static const _titleScale = 1.15;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var body =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    var base = body.fontSize ?? 14;

    // A link is set the way the reader's guide sets a link, not merely in
    // the link colour. The plain card's title is written as Markdown and
    // goes through the guide; this one did not, so switching between the two
    // layouts changed the colour of the title for no reason anybody could
    // see -- the same thing, drawn twice, two ways.
    var title = (rule.link.isEmpty
            ? body.copyWith(color: theme.markdownRoleColor(MarkdownRole.text))
            : theme.markdownLinkStyle(body))
        .copyWith(
      fontSize: base * _titleScale,
      fontWeight: FontWeight.bold,
    );
    var quiet =
        body.copyWith(color: theme.markdownRoleColor(MarkdownRole.muted));

    var textAlign = switch (rule.align) {
      CrossAxisAlignment.center => TextAlign.center,
      CrossAxisAlignment.end => TextAlign.right,
      _ => TextAlign.left,
    };

    var rows = <Widget>[
      if (rule.title.isNotEmpty)
        Text(rule.title,
            style: title,
            textAlign: textAlign,
            maxLines: rule.titleLines == 0 ? null : rule.titleLines,
            overflow: rule.titleLines == 0
                ? TextOverflow.clip
                : TextOverflow.ellipsis),
      // The seller's own gap. Tight by default: the summary belongs to the
      // title above it, and a paragraph's worth of air between them is what
      // made three rows look like three separate things.
      if (rule.title.isNotEmpty && rule.summary.isNotEmpty)
        SizedBox(height: rule.gap),
      if (rule.summary.isNotEmpty)
        Text(
          rule.summary,
          style: quiet,
          textAlign: textAlign,
          // One line whatever the width. A card is as wide as its share of
          // the row, and a description allowed to wrap is a card whose
          // height depends on how much its seller wrote.
          maxLines: rule.lines,
          overflow: TextOverflow.ellipsis,
        ),
      if (rule.meta.isNotEmpty || rule.button.isNotEmpty) ...[
        SizedBox(height: rule.metaGap),
        _footer(context, theme, body),
      ],
    ];

    var writing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: rule.align,
      children: rows,
    );

    if (rule.image.isEmpty) return writing;

    var picture = pageAssetPicture(context, rule.image,
        fit: BoxFit.cover, alignment: Alignment.center);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: rule.imageSize,
        height: rule.imageSize,
        child: picture == null
            ? null
            : ClipRRect(borderRadius: BorderRadius.circular(6), child: picture),
      ),
      SizedBox(width: rule.gap * 2),
      Expanded(child: writing),
    ]);
  }

  /// _footer is the last row: what it costs, and the thing to press.
  ///
  /// A Row rather than a run of columns, which is what this was first. A run
  /// of columns stacks below a width the reader's guide sets -- right for a
  /// page set in columns, wrong for two things that are one line by
  /// definition, and on a card three across it stacked every time.
  Widget _footer(BuildContext context, ThemeNotifier theme, TextStyle body) {
    var meta = rule.meta.isEmpty
        ? null
        : Flexible(
            child: Text(rule.meta,
                style: body, maxLines: 1, overflow: TextOverflow.ellipsis),
          );

    var button = rule.button.isEmpty
        ? null
        : ElevatedButton(
            style: _buttonStyle(theme),
            onPressed: rule.link.isEmpty
                ? null
                : () => followMarkdownLink(context, rule.link),
            child: Text(rule.button),
          );

    if (meta == null) return button ?? const SizedBox.shrink();
    if (button == null) return Row(children: [meta]);

    // Spread to the ends of the row only where the writing above it is:
    // under centred writing, a price pinned to one edge and a button pinned
    // to the other is not a centred card, it is a card with a gap in it.
    var spread = rule.align == CrossAxisAlignment.start;
    return Row(
      mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment:
          spread ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [meta, const SizedBox(width: 8), button],
    );
  }

  /// _buttonStyle is the button's own look: one of the app's buttons, with
  /// whatever the page said about its colour, corners and padding folded
  /// over it.
  ButtonStyle _buttonStyle(ThemeNotifier theme) {
    var base =
        rule.role == null ? const ButtonStyle() : theme.buttonStyle(rule.role!);
    var fill = rule.fill == null ? null : theme.markdownInk(rule.fill!);

    return base.copyWith(
      backgroundColor:
          fill == null ? base.backgroundColor : WidgetStatePropertyAll(fill),
      // A label the reader can read on whatever the seller chose. The roles
      // carry a label colour that suits their own fill; a written colour
      // carries none, and a dark word on a dark button is a button that
      // looks empty.
      foregroundColor: fill == null
          ? base.foregroundColor
          : WidgetStatePropertyAll(_readableOn(fill)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(
          horizontal: rule.padding, vertical: rule.padding / 2)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rule.radius))),
    );
  }

  /// _readableOn is black or white, whichever can be read on [fill].
  static Color _readableOn(Color fill) =>
      fill.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

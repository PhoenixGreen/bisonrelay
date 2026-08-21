import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/markdown_nav.dart';
import 'package:bruig/components/feed/markdown_title.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_header.dart is the two blocks a site's furniture is made of: the
// banner at the top of a page, and the bar of links that usually sits in it.
//
// Both are fielded rather than markdown-inside-markdown, for the same reason
// a card is: their parts are named things, in named places. A reader whose
// client does not know them sees labelled lines in the order they were
// written, which is still the header, just not drawn.

/// headerSlots are the places across a header, left to right.
const List<String> headerSlots = ["left", "middle", "right"];

/// headerFields is every field a header understands.
///
/// A closed list, because it is what tells a new field from a line that
/// happens to have a colon in it -- which is most lines of a navigation bar
/// with a br:// link in it. See HeaderBlockSyntax.
const List<String> headerFields = [
  "background",
  ...headerSlots,
  "description",
  "nav",
  "navat",
  // How tall a logo is drawn -- see headerLogoHeight.
  "logosize",
  // How the title is set -- see HeaderTextStyle.
  "titlesize",
  "titleweight",
  "titleitalic",
  "titlecase",
  "titletracking",
  "titlecolor",
  "titlegradient",
  "titlebackground",
  "titleborder",
  "titlebordercolor",
  "titleradius",
  "titlepadding",
];

/// HeaderBlockSyntax reads a page's banner.
///
///     --header[220]--
///     background: --embed[type=image/png,data=...]--
///     left: ![](logo)
///     right: # My Site
///     description: What the site is for.
///     nav: --include[navigation]--
///     navat: bottom
///     --/header--
///
/// The number is the tallest it may be, in pixels, matching --columns[n]--
/// and --grid[n]-- next door; without one the reader's theme decides.
///
/// Every field is optional. A header with only a background is a banner; one
/// with only a title is a masthead.
class HeaderBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--header(?:\[(\d+)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/header--\s*$');
  static final _field = RegExp(r'^\s*(\w+)\s*:\s*(.*)$');

  /// The tallest a header may be asked to be. Past this it is not a banner
  /// on a page, it is the page.
  static const maxHeight = 600;

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var line = parser.current.content;
    var height = int.tryParse(_open.firstMatch(line)?.group(1) ?? "");
    parser.advance();

    // A field's value runs to the next field, so it can hold something
    // several lines long. Which it usually does: "nav: --include[bar]--" is
    // replaced with the whole of that fragment before this is parsed, and
    // reading one line per field kept the first line of a navigation bar and
    // threw the links away.
    //
    // Only a known field name starts a new one. Anything else with a colon
    // in it belongs to the value being read -- which is most lines of a bar,
    // since "[Home](br://...)" has one.
    var fields = <String, List<String>>{};
    String? current;
    while (!parser.isDone) {
      var at = parser.current.content;
      if (_close.hasMatch(at)) {
        parser.advance();
        break;
      }
      var m = _field.firstMatch(at);
      var key = m?.group(1)?.toLowerCase();
      if (m != null && key != null && headerFields.contains(key)) {
        current = key;
        fields[current] = [m.group(2)!.trim()];
      } else if (current != null) {
        fields[current]!.add(at);
      }
      parser.advance();
    }

    var element = md.Element.text("header", "");
    if (height != null) {
      element.attributes["height"] = "${height.clamp(40, maxHeight)}";
    }
    fields.forEach((k, lines) {
      var value = lines.join("\n").trim();
      if (value.isNotEmpty) element.attributes[k] = value;
    });
    // Wrapped in a paragraph for the same reason a run of columns is: the
    // builder that draws this is reached through flutter_markdown's inline
    // path, which expects to be inside a block.
    return md.Element("p", [element]);
  }
}

/// headerSpans works out how wide each slot is.
///
/// Three rules, which between them give the shapes people actually write:
///
///  - A slot on its own takes the whole width, and sits where its name says.
///  - Otherwise each named slot takes one column, and the last of them
///    absorbs whatever is left at the end -- so a logo left and a title in
///    the middle gives the title the right-hand space too.
///  - An empty column *between* two named slots stays empty. A logo on the
///    left and a title on the right means the gap between them, not a logo
///    stretched across two thirds of the banner.
///
/// Returns a span per slot, zero for a slot that was not named.
List<int> headerSpans(Map<String, String> fields) {
  var named = [for (var s in headerSlots) fields[s]?.isNotEmpty ?? false];
  var count = named.where((n) => n).length;
  var spans = List<int>.filled(headerSlots.length, 0);
  if (count == 0) return spans;

  if (count == 1) {
    var only = named.indexOf(true);
    spans[only] = headerSlots.length;
    return spans;
  }

  var last = named.lastIndexOf(true);
  for (var i = 0; i < headerSlots.length; i++) {
    if (named[i]) spans[i] = 1;
  }
  spans[last] += headerSlots.length - 1 - last;
  return spans;
}

/// headerLogoHeight is how tall a picture in a slot is drawn, or null to
/// fill the height it has.
///
/// Filling is the sensible default and the wrong one as soon as there is a
/// title beside it: a logo takes the whole banner and the words next to it
/// are set to whatever titlesize says, and matching the two by eye means
/// changing one of them. This is the other one.
double? headerLogoHeight(Map<String, String> fields) {
  var raw = (fields["logosize"] ?? "").trim().toLowerCase();
  if (raw.isEmpty || raw == "fill") return null;
  var v = double.tryParse(raw);
  return v == null ? null : v.clamp(8, 600);
}

/// _slot draws one place across a banner.
///
/// A slot is a logo or a title, not a page of markdown, and it is drawn as
/// whichever it is. That is what lets the row place them: a block of
/// markdown wants the whole width and cannot be measured on its own -- it
/// lays out through a LayoutBuilder, so its intrinsic width throws -- so
/// slots drawn that way could not be put anywhere, and the gap between a
/// logo and the title beside it grew with the window.
Widget _slot(BuildContext context, String value, HeaderTextStyle style,
    HeaderRule rule, Alignment within, double? logoHeight) {
  var image = embedImage(value);
  if (image != null) {
    // Without a height of its own a logo fills the banner, which is what it
    // did before there was anything to match it to.
    Widget picture = isSvgMime(image.mime)
        ? SvgPicture.memory(image.bytes, fit: BoxFit.contain)
        : Image.memory(image.bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox.shrink());
    return logoHeight == null
        ? picture
        : SizedBox(height: logoHeight, child: picture);
  }
  return HeaderText(
      text: value,
      style: style,
      rule: rule,
      within: within,
      fillTo: logoHeight);
}

/// headerSlotAlignment is where a slot's contents sit within it.
///
/// Where the slot is named for, with one exception: a middle slot that has
/// something to its left hugs that instead of centring. A logo and a title
/// written as left and middle means the title beside the logo -- centring it
/// in the space it grew into puts it further from the logo than writing it
/// on the right would have.
///
/// So the three slots give three distances: middle is next to the logo,
/// right is against the far edge, and a middle with nothing to its left is
/// centred in the banner.
Alignment headerSlotAlignment(Map<String, String> fields, int index) {
  if (index == 0) return Alignment.centerLeft;
  if (index == headerSlots.length - 1) return Alignment.centerRight;
  var hasLeft = fields[headerSlots[0]]?.isNotEmpty ?? false;
  return hasLeft ? Alignment.centerLeft : Alignment.center;
}

/// embedImageBytes pulls the picture out of an --embed[...]-- string.
///
/// The background is drawn rather than rendered: it has to fill the banner
/// and be cropped to it, which is a decision about the box and not something
/// the markdown renderer can be asked for. Returns null for anything that is
/// not an inline image, which is then simply not drawn.
({Uint8List bytes, String mime})? embedImage(String? value) {
  if (value == null) return null;
  var m = RegExp(r'--embed\[(.*?)\]--').firstMatch(value);
  if (m == null) return null;

  var parms = <String, String>{};
  for (var part in (m.group(1) ?? "").split(",")) {
    var at = part.indexOf("=");
    if (at == -1) continue;
    parms[part.substring(0, at)] = part.substring(at + 1);
  }
  var mime = parms["type"] ?? "";
  if (!mime.startsWith("image/")) return null;
  var data = parms["data"];
  if (data == null || data.isEmpty) return null;
  try {
    return (bytes: base64Decode(data), mime: mime);
  } catch (_) {
    // A truncated embed, or one still holding the "[content abc]" reference
    // a document carries while it is being written. Neither is a
    // background; the header draws without one.
    return null;
  }
}

class HeaderMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      _MarkdownHeader(fields: element.attributes);
}

class _MarkdownHeader extends StatelessWidget {
  final Map<String, String> fields;
  const _MarkdownHeader({required this.fields});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var rule = MarkdownGuideScope.headerOf(context) ?? const HeaderRule();
    var height = double.tryParse(fields["height"] ?? "") ?? rule.boundedHeight;
    var spans = headerSpans(fields);
    var titleStyle = HeaderTextStyle.parse(fields);
    var logoHeight = headerLogoHeight(fields);
    var background = embedImage(fields["background"]);
    var nav = fields["nav"];
    var navAt = NavPlacement.parse(fields["navat"]);

    // Placed in a row of its own so it can sit anywhere across the banner --
    // a bar is rarely as wide as the page, and where it sits along the edge
    // is as much a decision as which edge it is on.
    Widget? bar = nav == null
        ? null
        : Align(alignment: navAt.across, child: MarkdownArea(nav, false));

    // The row places the slots; nothing inside them is stretched to do it.
    //
    // Each slot is drawn at its natural size -- see _slot -- and bounded to
    // a share of the width so one long title cannot push the others out.
    // Deliberately no Flexible: a Row divides its space between flex
    // children by their factors, so a Spacer sharing the row with two of
    // them got a third of the width rather than the slack, and a title
    // asked for the right-hand edge stopped in the middle.
    Widget slots() {
      var named = [
        for (var i = 0; i < headerSlots.length; i++)
          if (spans[i] > 0) i
      ];
      var endsApart = named.length == 2 &&
          named.first == 0 &&
          named.last == headerSlots.length - 1;

      return LayoutBuilder(builder: (context, constraints) {
        // The gaps come out of the width before it is shared, or three
        // slots each given a third plus two gaps between them add up to
        // more than there is.
        var gaps = endsApart ? 0 : (named.length - 1) * rule.boundedGap;
        var share =
            ((constraints.maxWidth - gaps) / named.length).clamp(0.0, 1e6);
        var children = <Widget>[];
        for (var i in named) {
          // A fixed gap between slots that belong together. Nothing between
          // the two ends, where the alignment below puts the slack.
          if (children.isNotEmpty && !endsApart) {
            children.add(SizedBox(width: rule.boundedGap));
          }
          Widget slot = _slot(context, fields[headerSlots[i]]!, titleStyle,
              rule, headerSlotAlignment(fields, i), logoHeight);

          // Bounded to its share and no more. Nothing is wrapped in an
          // Align: the row's own alignment places these, and an Align
          // passes loose constraints to its child -- which undid the
          // stretch below, so a title told to fill went on sizing itself to
          // the words.
          children.add(ConstrainedBox(
              constraints: BoxConstraints(maxWidth: share), child: slot));
        }

        return Row(
          // Stretched when a title is to fill and there is no logo height
          // to match: that hands every slot the row's height, which is what
          // a logo without one takes, so the two come out level. Centred
          // otherwise, since stretching a slot that wanted its own size
          // would undo the sizing above.
          crossAxisAlignment: titleStyle.fill && logoHeight == null
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          mainAxisAlignment: endsApart
              ? MainAxisAlignment.spaceBetween
              // A single slot sits where its name says; anything else starts
              // at the left, with the gaps above holding them together.
              : (named.length == 1 && named.first == 1
                  ? MainAxisAlignment.center
                  : (named.length == 1 && named.first == 2
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start)),
          children: children,
        );
      });
    }

    var anySlot = spans.any((s) => s > 0);

    // The banner is a fixed height, so the row of slots takes what the bar
    // and the description leave rather than whatever its tallest picture
    // wants. Without that a logo taller than the banner pushed the bar out
    // of the bottom of it -- a Spacer cannot give back room that has
    // already been claimed.
    var content = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bar != null && navAt.atTop) ...[
          bar,
          SizedBox(height: rule.boundedGap),
        ],
        if (anySlot) Expanded(child: slots()) else const Spacer(),
        if (fields["description"] != null) ...[
          SizedBox(height: rule.boundedGap),
          MarkdownArea(fields["description"]!, false),
        ],
        if (bar != null && !navAt.atTop) ...[
          SizedBox(height: rule.boundedGap),
          bar,
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: rule.boundedGap),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rule.boundedRadius),
        // A fixed height rather than a maximum: what is in a banner is laid
        // out against a height that is known, instead of discovering it by
        // overrunning. The number the writer gives is what the banner is.
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            if (background != null)
              Positioned.fill(
                // Cover, not contain: a banner fills its space and is
                // cropped to it, which is what a background is.
                child: isSvgMime(background.mime)
                    ? SvgPicture.memory(background.bytes, fit: BoxFit.cover)
                    : Image.memory(
                        background.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
              ),
            // A wash over the picture, so writing stays readable on top of
            // whatever was chosen. Skipped entirely when there is no
            // picture, where it would only mute the page's own background.
            if (background != null && rule.scrim > 0)
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colors.surface
                      .withValues(alpha: rule.scrim.clamp(0, 1)),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(rule.boundedPadding),
              child: content,
            ),
          ]),
        ),
      ),
    );
  }
}

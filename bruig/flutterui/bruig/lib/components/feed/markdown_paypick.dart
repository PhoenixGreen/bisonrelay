import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/tooltips.dart';
import 'package:bruig/components/pages/forms.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_paypick.dart is the one choice a checkout asks a buyer to make:
//
//   --paypick[action=/setCheckout, chosen=ln]--
//   --option[method=ln, icon=lightning, label=Lightning]--
//   Settles straight away. Paid from your Bison Relay wallet with one press.
//   --option[method=onchain, icon=onchain, label=On-chain]--
//   Settles after one confirmation from the network — about five minutes.
//   --/paypick--
//
// One block holding both cards rather than two panels side by side, because
// everything that makes it read as a choice is a fact about the pair: they
// are the same height whatever length their words are, they are as wide as
// each other, and they sit together in the middle of the page instead of
// stretching to its edges. None of that can be said by a card about itself.
//
// The whole card is the press. A card with a button in it asks twice -- once
// with the card, once with the button -- and the second ask is the one that
// counts, which is why buyers press the card and nothing happens.
//
// The words that explain each way to pay are behind a question mark rather
// than printed under the title. They are the reason to pick one, and they
// are also four lines of prose in the middle of a decision that is really
// being made on one word and one icon. Somebody who knows what Lightning is
// should not have to read past it; somebody who does not has a mark to press.

/// PayOption is one card.
@immutable
class PayOption {
  /// method is what is posted when this one is pressed.
  final String method;

  /// label is the word on the card.
  final String label;

  /// icon names the mark drawn above the label, from a closed list.
  final String icon;

  /// help is what the question mark says, or empty for a card with nothing
  /// more to add.
  final String help;

  /// note is two or three words under the label -- "Instant", "About five
  /// minutes" -- for the one fact that decides this between people who are
  /// not going to read the help.
  ///
  /// Which is nearly everybody. The choice is made on how long it takes, and
  /// putting that behind a question mark is hiding the answer to the only
  /// question being asked.
  final String note;

  const PayOption({
    this.method = "",
    this.label = "",
    this.icon = "",
    this.help = "",
    this.note = "",
  });

  bool get draws => label.isNotEmpty && method.isNotEmpty;
}

/// PayPickRule is the pair of them, and what to do when one is pressed.
@immutable
class PayPickRule {
  final String action;

  /// title is the question, centred over the cards it is asking about.
  ///
  /// Inside the block rather than a heading above it, because a heading is
  /// left-aligned like the rest of the page and the cards are not: a question
  /// at one edge of the page over two cards in the middle of it reads as two
  /// separate things.
  final String title;

  /// chosen is the method already picked, or empty for a choice not yet
  /// made.
  final String chosen;

  final List<PayOption> options;

  const PayPickRule({
    this.action = "",
    this.title = "",
    this.chosen = "",
    this.options = const [],
  });

  bool get draws => options.any((o) => o.draws);

  static Map<String, String> _fields(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }
    return fields;
  }

  static PayPickRule parse(String? attributes, String body) {
    var outer = _fields(attributes);

    var options = <PayOption>[];
    String? openAttrs;
    var help = <String>[];

    void close() {
      if (openAttrs == null) return;
      var f = _fields(openAttrs);
      options.add(PayOption(
        method: f["method"] ?? "",
        label: f["label"] ?? "",
        icon: (f["icon"] ?? "").toLowerCase(),
        note: f["note"] ?? "",
        help: help.join(" ").trim(),
      ));
      help = [];
    }

    for (var line in body.split("\n")) {
      var open = _option.firstMatch(line);
      if (open != null) {
        close();
        openAttrs = open.group(1) ?? "";
        continue;
      }
      if (openAttrs != null && line.trim().isNotEmpty) help.add(line.trim());
    }
    close();

    return PayPickRule(
      action: outer["action"] ?? "",
      title: outer["title"] ?? "",
      chosen: (outer["chosen"] ?? "").trim(),
      options: options,
    );
  }

  static final _option = RegExp(r'^\s*--option(?:\[([^\]]*)\])?--\s*$');
}

class PayPickBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--paypick(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/paypick--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var lines = <String>[];
    while (!parser.isDone) {
      if (_close.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    var element = md.Element.text("paypick", "");
    element.attributes["body"] = lines.join("\n");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class PayPickMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownPayPick(
        rule: PayPickRule.parse(
            element.attributes["attrs"], element.attributes["body"] ?? ""),
      );
}

/// payIcons is the closed list of marks a card may draw.
///
/// Closed, like every other icon this app takes from a page, because an icon
/// named by a page is a page choosing from what the app happens to ship --
/// and a name that resolves to nothing is a card with a hole in it.
const Map<String, IconData> payIcons = {
  "lightning": Icons.bolt,
  "onchain": Icons.link_rounded,
  "wallet": Icons.account_balance_wallet_outlined,
};

/// MarkdownPayPick draws the pair.
class MarkdownPayPick extends StatelessWidget {
  final PayPickRule rule;
  const MarkdownPayPick({required this.rule, super.key});

  /// _cardWidth is how wide one card is drawn, and _stackBelow is the room
  /// the pair needs before they stop sitting side by side.
  ///
  /// A fixed width rather than a share of the page: two cards holding a word
  /// and an icon do not get better at 400 points each, they just get further
  /// apart, and a choice whose halves are at opposite edges of a window
  /// reads as two unrelated things.
  static const double _cardWidth = 210;
  static const double _gap = 14;
  static const double _stackBelow = _cardWidth * 2 + _gap;

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();
    var options = rule.options.where((o) => o.draws).toList();
    var theme = ThemeNotifier.of(context);
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    // The full width of the page, whatever is in it.
    //
    // A block is laid out as a child of the column the page is built from,
    // and that column sizes its children to their content -- so without this
    // the pair is centred inside a box as wide as the title, which is a box
    // sitting against the left edge of the page. Centred in nothing looks
    // exactly like not centred at all.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(builder: (context, constraints) {
          var stacked = constraints.maxWidth.isFinite &&
              constraints.maxWidth < _stackBelow;

          var cards = [
            for (var option in options)
              SizedBox(
                width: _cardWidth,
                child: _PayCard(
                  option: option,
                  chosen: option.method == rule.chosen,
                  onPressed: rule.action.isEmpty
                      ? null
                      : () => postToPage(context, rule.action, {
                            "doing": "method",
                            "method": option.method,
                          }),
                ),
              ),
          ];

          Widget row;
          if (stacked) {
            row = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: _gap),
                  cards[i],
                ],
              ],
            );
          } else {
            // IntrinsicHeight is what makes them match: the taller card sets
            // the height and the other stretches to it, so a longer word on
            // one does not make the pair look like a mistake.
            row = IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    cards[i],
                  ],
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rule.title.isNotEmpty) ...[
                Text(
                  rule.title,
                  textAlign: TextAlign.center,
                  style: theme.markdownTextStyle(
                      theme.markdownGuide.headings[1], base),
                ),
                const SizedBox(height: 12),
              ],
              row,
            ],
          );
        }),
      ),
    );
  }
}

/// _PayCard is one of them.
class _PayCard extends StatefulWidget {
  final PayOption option;
  final bool chosen;
  final VoidCallback? onPressed;

  const _PayCard({
    required this.option,
    required this.chosen,
    required this.onPressed,
  });

  @override
  State<_PayCard> createState() => _PayCardState();
}

class _PayCardState extends State<_PayCard> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    var chosen = widget.chosen;
    // Lifted under the pointer, so a card that can be pressed looks like one
    // before it is. The chosen card never lifts: it is not an offer any more.
    var lifted = _over && !chosen;

    var edge = chosen
        ? colors.primary
        : lifted
            ? colors.primary.withValues(alpha: 0.55)
            : colors.outlineVariant;

    var mark = chosen ? colors.primary : colors.onSurfaceVariant;

    return MouseRegion(
      cursor: chosen ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: Material(
        color: chosen
            ? colors.primary.withValues(alpha: 0.10)
            : lifted
                ? colors.primary.withValues(alpha: 0.04)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: chosen ? null : widget.onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: edge, width: chosen ? 2 : 1),
            ),
            child: Stack(
              children: [
                // The full width of the card, so the centring is against the
                // card rather than against the writing.
                //
                // A Stack sizes itself to its largest unpositioned child and
                // lays that child out loosely -- so the column came out as
                // wide as its longest line and sat against the left edge,
                // with everything in it centred inside that. Two cards whose
                // longest lines differ then had their marks in two different
                // places, which is what it looked like: not off-centre by a
                // fixed amount, but by however much the words differed.
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // The mark in a disc of its own, rather than loose above
                      // the words. It gives the card a centre, and it is what
                      // tells the two apart at a glance -- which is how this
                      // choice is actually made.
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: chosen
                              ? colors.primary.withValues(alpha: 0.16)
                              : colors.onSurfaceVariant.withValues(alpha: 0.10),
                        ),
                        child: Icon(
                          payIcons[widget.option.icon] ??
                              Icons.payments_outlined,
                          size: 28,
                          color: mark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.option.label,
                        textAlign: TextAlign.center,
                        style: base.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: chosen ? colors.primary : colors.onSurface,
                        ),
                      ),
                      if (widget.option.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.option.note,
                          textAlign: TextAlign.center,
                          style: base.copyWith(
                              fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // The card always says which state it is in. A chosen
                      // card that only differs by its border is a card nobody
                      // is sure they pressed.
                      _footer(context, chosen, colors, base),
                    ],
                  ),
                ),
                if (widget.option.help.isNotEmpty)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: HelpTooltip(
                      message: widget.option.help,
                      triggerMode: TooltipTriggerMode.tap,
                      showDuration: const Duration(seconds: 8),
                      // Wide enough for a sentence: the default wraps a line
                      // of prose into a column one word across.
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.help_outline,
                            size: 16, color: colors.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(
      BuildContext context, bool chosen, ColorScheme colors, TextStyle base) {
    if (chosen) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          Text("Chosen",
              style: base.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text("Choose",
          style: base.copyWith(fontSize: 13, color: colors.onSurface)),
    );
  }
}

// --------------------------------------------------------------------------
// A row that says one settled fact about how an order is being paid:
//
//   --paysummary[icon=lightning, label=Paying with, value=Lightning,
//                link=/checkout, linklabel=Change]--
//
// The review page's version of the card above, after the choice is made. It
// is a row rather than a card because it is no longer a choice: it runs the
// width of the page like the order it belongs to, with the mark on the right
// so the two facts a buyer is checking -- what they are paying with, and
// whether they can still change it -- are at opposite ends of one line.

/// PaySummaryRule is one such row.
@immutable
class PaySummaryRule {
  final String icon;
  final String label;
  final String value;
  final String link;
  final String linkLabel;

  const PaySummaryRule({
    this.icon = "",
    this.label = "",
    this.value = "",
    this.link = "",
    this.linkLabel = "",
  });

  bool get draws => value.isNotEmpty || label.isNotEmpty;

  static PaySummaryRule parse(String? attributes) {
    var f = PayPickRule._fields(attributes);
    return PaySummaryRule(
      icon: (f["icon"] ?? "").toLowerCase(),
      label: f["label"] ?? "",
      value: f["value"] ?? "",
      link: f["link"] ?? "",
      linkLabel: f["linklabel"] ?? "Change",
    );
  }
}

class PaySummaryBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--paysummary(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("paysummary", "");
    if (attributes != null) element.attributes["attrs"] = attributes;
    return md.Element("p", [element]);
  }
}

class PaySummaryMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownPaySummary(
          rule: PaySummaryRule.parse(element.attributes["attrs"]));
}

/// MarkdownPaySummary draws it.
class MarkdownPaySummary extends StatelessWidget {
  final PaySummaryRule rule;
  const MarkdownPaySummary({required this.rule, super.key});

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rule.label.isNotEmpty)
                    Text(rule.label,
                        style: base.copyWith(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  if (rule.value.isNotEmpty)
                    Text(rule.value,
                        style: base.copyWith(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (rule.link.isNotEmpty) ...[
              TextButton(
                onPressed: () => followMarkdownLink(context, rule.link),
                child: Text(rule.linkLabel),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.onSurfaceVariant.withValues(alpha: 0.10),
              ),
              child: Icon(
                payIcons[rule.icon] ?? Icons.payments_outlined,
                size: 22,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/models/purchases.dart';
import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/screens/manage_content_screen.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/screens/overview.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

// markdown_purchase.dart is the file a shop owed you, on the order that
// bought it:
//
//   --purchase[order=00000001, sku=g1, title=A guide]--
//
// A shop sends a paid order's files over Bison Relay, and they land in
// Files > Purchases like anything else that arrives. Which is correct, and
// leaves the buyer on an order page that says the file is on its way and then
// says nothing else -- with no way to know whether it came, and a section of
// the app to go and look in.
//
// So the order says. The shop cannot: where a file landed is a fact about the
// buyer's own machine, and the page was written by somebody else's. This block
// is the buyer's client answering a question their page asked.
//
// What it offers depends on what arrived. Something the app can read opens in
// the reader in Files, where it keeps its place; anything else is handed to
// whatever the machine opens it with, because a document this app cannot show
// is not one it should pretend to.

/// PurchaseRule names the file one line of an order is owed.
@immutable
class PurchaseRule {
  /// order and sku are what the shop stamped on the file it sent. Matched on
  /// the SKU, with the order as a tiebreak: a product bought twice arrives
  /// twice, and either copy is the thing that was bought.
  final String order;
  final String sku;
  final String title;

  const PurchaseRule({this.order = "", this.sku = "", this.title = ""});

  bool get draws => sku.isNotEmpty;

  static PurchaseRule parse(String? attributes) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }
    return PurchaseRule(
      order: (fields["order"] ?? "").trim(),
      sku: (fields["sku"] ?? "").trim(),
      title: (fields["title"] ?? "").trim(),
    );
  }
}

class PurchaseBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--purchase(?:\[([^\]]*)\])?--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var element = md.Element.text("purchase", "");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class PurchaseMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownPurchase(rule: PurchaseRule.parse(element.attributes["attrs"]));
}

/// arrivedFor is the file that arrived for one line of an order, or null when
/// nothing has.
///
/// Public so a test can hold this to what it promises without a downloads
/// model behind it: which copy of which product this row is about is the only
/// hard part, and it is decided here.
({String path, String filename})? arrivedFor(
    Iterable<({String diskPath, dynamic metadata})> received,
    PurchaseRule rule) {
  ({String path, String filename})? best;
  for (var f in received) {
    var metadata = f.metadata;
    if (metadata == null || f.diskPath.isEmpty) continue;
    var attrs = metadata.attributes as Map<String, dynamic>?;
    if (attrs == null) continue;
    if ((attrs[purchaseSKUAttr] as String?) != rule.sku) continue;

    var found = (path: f.diskPath, filename: metadata.filename as String);
    // The copy sent for this order wins outright; a copy of the same product
    // from another order is still the thing that was bought, so it is kept
    // as the answer if no better one turns up.
    if (rule.order.isNotEmpty &&
        (attrs[purchaseOrderAttr] as String?) == rule.order) {
      return found;
    }
    best ??= found;
  }
  return best;
}

/// MarkdownPurchase draws it.
class MarkdownPurchase extends StatelessWidget {
  final PurchaseRule rule;
  const MarkdownPurchase({required this.rule, super.key});

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();

    // Listening, because the whole point is the moment it arrives: the buyer
    // is looking at this page while the file is still being pushed to them,
    // and a row that only told them on the next visit would be a row they
    // read once, wrong.
    var downloads = Provider.of<DownloadsModel?>(context);
    if (downloads == null) return const SizedBox.shrink();

    var arrived = arrivedFor([
      for (var f in downloads.downloads)
        (diskPath: f.diskPath, metadata: f.rf.metadata),
    ], rule);

    var theme = ThemeNotifier.of(context);
    var colors = theme.colors;
    var base = Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);

    var name = rule.title.isEmpty ? "This file" : rule.title;

    Widget body;
    if (arrived == null) {
      body = Row(
        children: [
          Icon(Icons.schedule, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "$name is on its way. It arrives here and in "
              "Files > Purchases, usually within a few seconds.",
              style: base.copyWith(fontSize: 13),
            ),
          ),
        ],
      );
    } else {
      var readable = fileKindOf(arrived.path) != FileKind.other;
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(readable ? Icons.menu_book_outlined : Icons.description_outlined,
              size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style:
                        base.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  readable
                      ? "Delivered. It is in Files > Purchases."
                      : "Delivered as ${arrived.filename}. This app cannot "
                          "show that kind of file, so it opens on your machine.",
                  style: base.copyWith(
                      fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // The app's primary button: a bare ElevatedButton is the "plain"
          // role in this theme, which is no fill and no border -- a line of
          // coloured text where the row's one action should be.
          readable
              ? ElevatedButton.icon(
                  style: theme.buttonStyle(ButtonRole.primary),
                  onPressed: () => openInPurchases(context, arrived.path),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text("Read it"),
                )
              : ElevatedButton.icon(
                  style: theme.buttonStyle(ButtonRole.primary),
                  onPressed: () => OpenFilex.open(arrived.path),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text("Open it"),
                ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: body,
      ),
    );
  }
}

/// openInPurchases opens a delivered file in the reader, in Files >
/// Purchases.
///
/// The tab and the file are set before navigating rather than passed as an
/// argument, because that screen keeps both on a model of its own so they
/// survive it being rebuilt -- see ManageContentNavModel.
void openInPurchases(BuildContext context, String path) {
  var client = ClientModel.of(context, listen: false);
  client.ui.manageContentNav
    ..tab = purchasesTabIndex
    ..open(path);

  var menu = Provider.of<MainMenuModel?>(context, listen: false);
  menu?.activePageTab = purchasesTabIndex;

  Navigator.of(context).pushNamed(ManageContentScreen.routeName,
      arguments: PageTabs(purchasesTabIndex, null, null));
}

/// purchasesTabIndex is which tab of Files holds what somebody has bought.
const int purchasesTabIndex = 3;

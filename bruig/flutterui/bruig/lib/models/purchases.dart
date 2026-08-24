import 'package:golib_plugin/definitions.dart';

// purchases.dart is what a buyer has bought, worked out from what they were
// sent.
//
// A file a shop sends carries the order, the SKU and the product's title in
// its metadata attributes, and the receiving client keeps them beside the
// file. So "what have I bought" is a question the downloads can answer on
// their own -- nothing has to be recorded separately, and nothing can drift
// out of step with what actually arrived.
//
// There is no version attribute. The metadata already carries a hash of the
// contents, so the same SKU arriving with a different hash is a new version
// of that product; a version field beside it would be a second answer to one
// question.

/// Attribute names a shop sets on a file it sends. The same strings the
/// serving side writes -- see simplestore's goods.go.
const String purchaseOrderAttr = "simplestore.order";
const String purchaseSKUAttr = "simplestore.sku";
const String purchaseTitleAttr = "simplestore.product";

/// isPurchase is whether a received file came from a shop.
bool isPurchase(FileMetadata? metadata) =>
    (metadata?.attributes?[purchaseSKUAttr] as String?)?.isNotEmpty ?? false;

String? _attr(FileMetadata? metadata, String key) =>
    metadata?.attributes?[key] as String?;

/// Purchase is one product somebody bought, and the copies of it they have.
class Purchase {
  final String sku;
  final String title;
  final String seller;

  /// copies are what arrived for this product, newest last.
  final List<FileMetadata> copies;

  const Purchase({
    required this.sku,
    required this.title,
    required this.seller,
    required this.copies,
  });

  /// hasUpdate is whether the shop has sent a version of this since the one
  /// the buyer opened first.
  ///
  /// More than one copy of the same product with different contents is the
  /// whole of the evidence: a shop that sends the same file again sends the
  /// same hash, and nothing here calls that an update.
  bool get hasUpdate => copies.length > 1;

  /// latest is the copy to read: the newest that arrived.
  FileMetadata get latest => copies.last;
}

/// purchasesOf gathers what somebody has bought out of what they were sent.
///
/// Grouped by product rather than listed by file, because a product sent
/// three times is one thing somebody bought and not three -- and the
/// difference between those two readings is the whole point of showing it
/// separately from the downloads.
List<Purchase> purchasesOf(
    Iterable<({String seller, FileMetadata? metadata})> received) {
  var byProduct = <String, List<({String seller, FileMetadata metadata})>>{};
  for (var item in received) {
    var metadata = item.metadata;
    if (metadata == null || !isPurchase(metadata)) continue;
    var sku = _attr(metadata, purchaseSKUAttr)!;
    // Keyed on the seller as well as the SKU: two shops are free to use the
    // same SKU, and nothing stops them, so keying on the SKU alone would
    // fold one seller's product into another's.
    (byProduct["${item.seller}/$sku"] ??= [])
        .add((seller: item.seller, metadata: metadata));
  }

  var out = <Purchase>[];
  byProduct.forEach((_, items) {
    // One entry per distinct copy: a file that arrived twice unchanged is
    // one thing, and calling it an update would be telling somebody to go
    // and read what they have already read.
    var seen = <String>{};
    var copies = <FileMetadata>[];
    for (var item in items) {
      if (seen.add(item.metadata.hash)) copies.add(item.metadata);
    }
    out.add(Purchase(
      sku: _attr(copies.first, purchaseSKUAttr) ?? "",
      title: _attr(copies.first, purchaseTitleAttr) ?? copies.first.filename,
      seller: items.first.seller,
      copies: copies,
    ));
  });
  out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return out;
}

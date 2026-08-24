import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

// store_goods.dart publishes a document from the writing library as the file
// a product sends.
//
// The same relationship a page has with the document it was written from:
// the document stays in the library and goes on being edited, and the shop
// sends a copy that changes when somebody says so. Editing a document does
// not quietly change what buyers are being sent -- that is a thing to mean,
// the way publishing a page is.

/// goodNameFor is what a document is called once it is a product's file.
///
/// The document's own name, slugged, because it becomes a file on a buyer's
/// machine: "My Guide" arrives as my-guide.md rather than as something with
/// a space in it that their downloads folder has to cope with.
String goodNameFor(String documentName) => "${pageSlug(documentName)}.md";

/// StoreGoods is publishing a library document into the shop.
class StoreGoods {
  /// publish writes the document into the shop's goods, and gives back the
  /// name for the product to record.
  ///
  /// The pictures are put back first, the same way publishing a page does
  /// it. A document carries "data=[content abc]" while it is being written
  /// and the bytes live in the embed store -- so a guide published without
  /// this would reach the buyer with a hole where every picture was, and
  /// they would be the only one who could see that, because the author's
  /// own copy fills the references in from memory.
  static Future<({String recorded, int missing})> publish(
      String folder, String name) async {
    var text = await PostStorage.read(folder, name) ?? "";
    var resolved = await resolveEmbeds(text);
    var recorded = await Golib.publishStoreGood(
        goodNameFor(name), Uint8List.fromList(utf8.encode(resolved.text)));
    return (recorded: recorded, missing: resolved.missing);
  }

  /// unpublish takes the copy out of the shop, keeping the document.
  static Future<void> unpublish(String recorded) =>
      Golib.removeStoreGood(recorded);

  /// stateOf is what a product's file is, as the library sees it.
  ///
  /// Compared on the text rather than on a timestamp: a document saved
  /// without being changed is not an edit, and a writer who opened
  /// something and closed it again should not be told they have unpublished
  /// work.
  static Future<PagePublishState> stateOf(
      String folder, String name, ManagedProduct product) async {
    if (product.sendFilename.isEmpty) return PagePublishState.draft;
    var text = await PostStorage.read(folder, name);
    if (text == null) return PagePublishState.draft;
    var published = await Golib.readStoreGood(product.sendFilename);
    if (published == null) return PagePublishState.draft;
    var resolved = await resolveEmbeds(text);
    return resolved.text == published
        ? PagePublishState.published
        : PagePublishState.edited;
  }
}

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/storage_manager.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// canvas_picture_cache.dart remembers which stored picture came from which
// address.
//
// The store is content-addressed, so a crest fetched twice is one file on disk
// -- but it is also two requests, and a league table is twenty crests that
// have not changed since last week. Refreshing the table fetched all of them
// again every time, which is slow, rude to the server, and on a rate-limited
// free tier is most of the allowance spent on pictures nobody needed.
//
// So: address to asset id, kept on this machine. It is only ever an
// optimisation -- every entry is checked against the store before it is
// trusted, and a miss simply fetches -- which is what lets it be thrown away
// safely and why nothing here has to be kept in step with anything else.
//
// Not in the document. Which pictures this machine happens to have already is
// not a fact about the design, and a canvas carrying one reader's cache to
// another reader would be carrying a list of files they do not have.

/// _prefix is the storage key. A hash of the address is appended, rather than
/// the address itself: a URL is long, contains characters a key should not,
/// and is not worth keeping in full when all that is ever asked of it is
/// whether it is the same one.
const String _prefix = "canvasPicture:";

String _keyFor(String url) =>
    "$_prefix${sha256.convert(utf8.encode(url)).toString().substring(0, 16)}";

class CanvasPictureCache {
  /// known is the picture already stored for [url], or null.
  ///
  /// Null when the entry names a picture the store no longer has -- swept
  /// because no canvas referred to it, or deleted by hand -- and the entry is
  /// forgotten on the way past so the next answer is arrived at directly.
  static Future<String?> known(String url) async {
    var id = await StorageManager.readString(_keyFor(url));
    if (id.isEmpty) return null;
    if (await CanvasAssets.exists(id)) return id;
    await StorageManager.saveString(_keyFor(url), "");
    return null;
  }

  /// remember files [assetId] under [url].
  static Future<void> remember(String url, String assetId) async {
    if (url.isEmpty || assetId.isEmpty) return;
    await StorageManager.saveString(_keyFor(url), assetId);
  }
}

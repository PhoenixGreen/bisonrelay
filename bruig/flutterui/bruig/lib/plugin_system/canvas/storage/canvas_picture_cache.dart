import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/storage_manager.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

// canvas_picture_cache.dart remembers which stored picture came from which
// address.
//
// The store is content-addressed, so a crest fetched twice is one file, but
// still two requests, and a league table's crests rarely change. So: address
// to asset id, kept on this machine. Only an optimisation: every entry is
// checked against the store before it is trusted and a miss simply fetches,
// so it can be thrown away safely. Not in the document: what pictures this
// machine already has is not part of the design.

/// _prefix is the storage key. A hash of the address is appended rather than
/// the address itself, which is long and holds characters a key should not.
const String _prefix = "canvasPicture:";

String _keyFor(String url) =>
    "$_prefix${sha256.convert(utf8.encode(url)).toString().substring(0, 16)}";

class CanvasPictureCache {
  /// known is the picture already stored for [url], or null. Null too when
  /// the entry names a picture the store no longer has, and the entry is then
  /// forgotten.
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

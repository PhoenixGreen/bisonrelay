import 'package:bruig/storage_manager.dart';

// canvas_api_keys.dart keeps the keys a data source needs, outside the
// document. A canvas is sent to people, and a key saved in it would go to
// everybody who received it; so the document holds the address and the key
// lives here, on this machine only, filed by host: a key belongs to a
// service, and several tables using one API need it once.

/// _prefix is the storage key; the host is appended.
const String _prefix = "canvasApiKey:";

class CanvasApiKeys {
  /// read is the key for [host], or empty when there is not one.
  static Future<String> read(String host) async =>
      host.isEmpty ? "" : StorageManager.readString("$_prefix$host");

  /// write saves a key, or forgets it when [key] is empty.
  static Future<void> write(String host, String key) async {
    if (host.isEmpty) return;
    await StorageManager.saveString("$_prefix$host", key.trim());
  }

  /// has is whether a key has been given, which is all a settings panel
  /// shows: the key itself is never shown again once entered.
  static Future<bool> has(String host) async => (await read(host)).isNotEmpty;
}

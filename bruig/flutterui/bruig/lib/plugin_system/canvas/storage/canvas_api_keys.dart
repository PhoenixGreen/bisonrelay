import 'package:bruig/storage_manager.dart';

// canvas_api_keys.dart keeps the keys a data source needs, outside the
// document that uses them.
//
// This separation is the whole point of the file. A canvas is a thing people
// send each other -- as a bundle, into a chat, into the post library -- and a
// key saved in the document would be a key handed to everybody who received
// it, from a field the sender had no reason to think of as secret. So the
// document holds the address and the key lives here, filed under the host it
// belongs to, on this machine only.
//
// Filed by host rather than by canvas, because a key is a fact about a service
// rather than about a design: three tables pulling three leagues from one API
// need one key between them, and asking for it three times would be three
// chances to paste it into the wrong box.

/// _prefix is the storage key. The host is appended.
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

  /// has is whether one has been given, which is what a settings panel shows.
  /// The key itself is never shown again once it has been entered.
  static Future<bool> has(String host) async => (await read(host)).isNotEmpty;
}

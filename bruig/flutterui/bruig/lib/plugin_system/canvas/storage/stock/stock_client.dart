import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

// stock_client.dart makes the requests a stock search needs: the search
// itself, a preview to listen to, and the file when one is used.
//
// Behind the same two gates as a table's data -- see canvas_data.dart. Nothing
// is fetched unless the reader has turned fetching on, and nothing at all
// while a proxy is set, because a request from here would not go through it.
// Both are asked by the caller and handed in, so this file never decides on
// its own to connect.
//
// Keys are the reader's own, one per library, kept on this machine by
// CanvasApiKeys and never written into anything that is shared.
//
// A search answer is kept for a day. Pixabay's terms ask for that, and it is
// the right thing for every library on a free tier: paging back and forth,
// or searching for the same thing twice, should not spend the allowance.

/// StockKeys reads and writes the keys, filed under each library's host.
class StockKeys {
  static Future<String> key(StockSource s) => CanvasApiKeys.read(s.keyHost);
  static Future<String> secret(StockSource s) =>
      CanvasApiKeys.read("${s.keyHost}#secret");

  static Future<bool> has(StockSource s) async =>
      (await key(s)).isNotEmpty &&
      (!s.needsSecret || (await secret(s)).isNotEmpty);

  static Future<void> save(StockSource s, String key,
      [String secret = ""]) async {
    await CanvasApiKeys.write(s.keyHost, key);
    if (s.needsSecret) await CanvasApiKeys.write("${s.keyHost}#secret", secret);
  }

  static Future<void> forget(StockSource s) => save(s, "", "");
}

/// pct is RFC 3986 percent-encoding, which OAuth signs over. Dart's own
/// encodeComponent leaves ! * ' ( ) alone, and a signature over those is a
/// signature the server works out differently.
String pct(String s) {
  var out = StringBuffer();
  for (var b in utf8.encode(s)) {
    var c = String.fromCharCode(b);
    if (RegExp(r"[A-Za-z0-9\-._~]").hasMatch(c)) {
      out.write(c);
    } else {
      out.write("%${b.toRadixString(16).toUpperCase().padLeft(2, "0")}");
    }
  }
  return out.toString();
}

/// oauthHeader signs a GET of [uri] with a consumer [key] and [secret] alone:
/// OAuth 1.0a, two-legged, HMAC-SHA1 -- which is what the Noun Project asks
/// for, and what its own examples send.
///
/// [nonce] and [timestamp] are for a test to fix; left out, they are fresh.
String oauthHeader(Uri uri, String key, String secret,
    {String? nonce, int? timestamp}) {
  var random = math.Random.secure();
  var oauth = {
    "oauth_consumer_key": key,
    "oauth_nonce": nonce ??
        List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join(),
    "oauth_signature_method": "HMAC-SHA1",
    "oauth_timestamp":
        "${timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}",
    "oauth_version": "1.0",
  };
  var pairs = [
    for (var e in uri.queryParametersAll.entries)
      for (var v in e.value) (pct(e.key), pct(v)),
    for (var e in oauth.entries) (pct(e.key), pct(e.value)),
  ]..sort((a, b) {
      var k = a.$1.compareTo(b.$1);
      return k != 0 ? k : a.$2.compareTo(b.$2);
    });
  var params = pairs.map((p) => "${p.$1}=${p.$2}").join("&");
  var base = uri.replace(query: "").toString().replaceAll(RegExp(r"\?$"), "");
  var text = "GET&${pct(base)}&${pct(params)}";
  var signature = base64.encode(Hmac(sha1, utf8.encode("${pct(secret)}&"))
      .convert(utf8.encode(text))
      .bytes);
  var header = {...oauth, "oauth_signature": signature};
  return "OAuth ${header.entries.map((e) => '${pct(e.key)}="${pct(e.value)}"').join(", ")}";
}

/// StockClient is the network side of the stock libraries. Replaced in tests
/// -- see [instance] -- so the sidebar can be driven with nothing connected.
class StockClient {
  /// instance is the client the sidebar uses.
  static StockClient instance = StockClient();

  /// cacheFor is how long a search answer is kept.
  static const cacheFor = Duration(hours: 24);

  final Map<String, (DateTime, String)> _memory = {};

  /// search runs [q], or says why it cannot.
  Future<StockPage> search(StockQuery q,
      {required bool allowFetching, required bool proxied}) async {
    var refused = refusal(allowFetching: allowFetching, proxied: proxied);
    if (refused != null) return StockPage.failed(refused);
    var source = q.source;
    if (source.needsText && q.text.trim().isEmpty) {
      return const StockPage.failed("Type what you are looking for.");
    }
    if (!await StockKeys.has(source)) {
      return StockPage.failed("Add your ${source.from} key first.");
    }

    var request = requestFor(q, key: await StockKeys.key(source));
    var text = await _cached(request.cacheKey);
    if (text == null) {
      var headers = {...request.headers};
      if (request.signed) {
        headers["Authorization"] = oauthHeader(request.uri,
            await StockKeys.key(source), await StockKeys.secret(source));
      }
      var (status, body) = await getText(request.uri, headers);
      // Freesound moved its search in 2025; an older server answers the
      // old address only.
      if (status == 404 && source == StockSource.freesound) {
        var older = request.uri.replace(path: "/apiv2/search/text/");
        (status, body) = await getText(older, headers);
      }
      if (status != 200) return StockPage.failed(_problem(source, status));
      text = body;
      await _remember(request.cacheKey, text);
    }
    try {
      return parseStock(q, jsonDecode(text));
    } catch (exception) {
      debugPrint("Unreadable ${source.from} answer: $exception");
      return StockPage.failed("${source.from} answered with something "
          "that could not be read.");
    }
  }

  /// refusal is why nothing may be fetched, or null when it may.
  static String? refusal({required bool allowFetching, required bool proxied}) {
    if (!allowFetching) {
      return "Fetching is switched off. Turn it on to search the stock "
          "libraries.";
    }
    if (proxied) {
      return "This app reaches the network through a proxy, which a stock "
          "search cannot use, so the stock libraries are unavailable.";
    }
    return null;
  }

  static String _problem(StockSource s, int status) => switch (status) {
        0 => "${s.from} could not be reached.",
        401 || 403 => "${s.from} did not accept the key. Check it, or get a "
            "new one.",
        429 => "${s.from} says too many searches. Wait a minute and try "
            "again.",
        _ => "${s.from} answered $status.",
      };

  /// thumbnail is a result's small picture, shown from the library's own
  /// server and kept only in the image cache.
  ImageProvider thumbnail(String url) => NetworkImage(url);

  /// getText is one GET: its status, and its body when it is 200. Status 0
  /// is no answer at all.
  @protected
  Future<(int, String)> getText(Uri uri, Map<String, String> headers) async {
    if (!uri.isScheme("https")) return (0, "");
    var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      var request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      var response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return (response.statusCode, "");
      }
      return (200, await response.transform(utf8.decoder).join());
    } catch (exception) {
      debugPrint("Stock search failed: $exception");
      return (0, "");
    } finally {
      client.close(force: true);
    }
  }

  /// download saves [url] to [to], or returns false -- refused, failed, or
  /// larger than [maxBytes].
  Future<bool> download(String url, File to,
      {required int maxBytes,
      required bool allowFetching,
      required bool proxied}) async {
    if (refusal(allowFetching: allowFetching, proxied: proxied) != null) {
      return false;
    }
    var uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme("https")) return false;
    var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    var partial = File("${to.path}.part");
    try {
      var response = await (await client.getUrl(uri)).close();
      if (response.statusCode != 200) return false;
      var sink = partial.openWrite();
      var got = 0;
      var tooBig = false;
      try {
        await for (var chunk in response) {
          got += chunk.length;
          if (got > maxBytes) {
            tooBig = true;
            break;
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (tooBig || got == 0) {
        await partial.delete();
        return false;
      }
      await partial.rename(to.path);
      return true;
    } catch (exception) {
      debugPrint("Stock download failed: $exception");
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// _cacheDir is beside the library, dotted so the library listing skips
  /// it.
  Future<Directory> _cacheDir() async =>
      Directory(path.join(await CanvasStorage.libraryDir(), ".stock-cache"));

  String _hash(String key) =>
      sha256.convert(utf8.encode(key)).toString().substring(0, 24);

  Future<String?> _cached(String key) async {
    var now = DateTime.now();
    var kept = _memory[key];
    if (kept != null && now.difference(kept.$1) < cacheFor) return kept.$2;
    try {
      var file =
          File(path.join((await _cacheDir()).path, "${_hash(key)}.json"));
      if (!await file.exists()) return null;
      var when = await file.lastModified();
      if (now.difference(when) >= cacheFor) return null;
      var text = await file.readAsString();
      _memory[key] = (when, text);
      return text;
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(String key, String text) async {
    var now = DateTime.now();
    _memory[key] = (now, text);
    try {
      var dir = await _cacheDir();
      await dir.create(recursive: true);
      await File(path.join(dir.path, "${_hash(key)}.json")).writeAsString(text);
      // And out with the old, while here: a day's searches are small, a
      // year's are not.
      await for (var f in dir.list()) {
        if (f is File && now.difference(await f.lastModified()) >= cacheFor) {
          await f.delete();
        }
      }
    } catch (exception) {
      debugPrint("Unable to keep the stock search: $exception");
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_picture_cache.dart';
import 'package:flutter/foundation.dart';

// canvas_data.dart goes and gets what a data source describes.
//
// Two ways in, and they are not equals. Reading a file is the ordinary one and
// costs nothing: whatever collects the data -- a browser, curl, a script on a
// schedule -- writes JSON somewhere, and the canvas reads it when asked. The
// other opens a connection to the internet, which nothing else in this app's
// interface does, and is refused unless the reader has turned it on. See
// CanvasPreferences.allowFetching.
//
// Everything here is on demand. There is no polling and no background
// refresh: a canvas that quietly connected to a server every few minutes would
// be a canvas that announced its owner was at their desk, which is not a thing
// a design tool should do to somebody.

/// DataResult is what came back, or why nothing did.
class DataResult {
  final List<List<String>>? rows;
  final String? problem;

  /// fields is every path that led to a value in the first record.
  ///
  /// What the settings panel offers as "Available", so a column's path is
  /// chosen from a list of what is actually there rather than guessed from an
  /// API's documentation. Worked out on the way past, because this is the one
  /// moment the answer is known.
  final List<String> fields;

  const DataResult.ok(this.rows, [this.fields = const []]) : problem = null;
  const DataResult.failed(this.problem)
      : rows = null,
        fields = const [];

  bool get worked => rows != null;
}

/// loadData reads [source] and maps it into rows.
///
/// [allowFetching] and [proxied] are handed in rather than read here, so that
/// the one function that decides whether a connection is allowed is testable
/// and so this file does not reach for the app's settings.
Future<DataResult> loadData(
  DataSource source, {
  bool allowFetching = false,
  bool proxied = false,
}) async {
  if (!source.on) return const DataResult.failed("There is no data source.");

  String text;
  switch (source.kind) {
    case DataKind.typed:
      return const DataResult.failed("There is no data source.");

    case DataKind.file:
      try {
        var file = File(source.where);
        if (!await file.exists()) {
          return DataResult.failed("There is no file at ${source.where}.");
        }
        text = await file.readAsString();
      } catch (exception) {
        debugPrint("Unable to read the canvas data file: $exception");
        return const DataResult.failed("That file could not be read.");
      }

    case DataKind.url:
      if (!allowFetching) {
        return const DataResult.failed(
            "Fetching is switched off. Turn it on in Settings > Plugins > "
            "Canvas, or use a file instead.");
      }
      // Refused rather than quietly bypassed. A reader who has pointed this
      // app at a SOCKS proxy has said how they want it to reach the network,
      // and a request from here would not go that way -- so the honest thing
      // is to say that this one cannot be made, not to make it anyway.
      if (proxied) {
        return const DataResult.failed(
            "This app is set to reach the network through a proxy, which a "
            "fetch from the canvas cannot use. Use a file instead.");
      }
      var fetched = await _fetch(source);
      if (fetched == null) {
        return const DataResult.failed("Nothing came back from that address.");
      }
      text = fetched;
  }

  dynamic json;
  try {
    json = jsonDecode(text);
  } catch (exception) {
    debugPrint("The canvas data is not JSON: $exception");
    return const DataResult.failed("That is not JSON.");
  }

  var rows = rowsFromJson(json, source);
  if (rows.isEmpty) {
    return DataResult.failed(source.rowsPath.isEmpty
        ? "No rows were found. Is the document a list?"
        : "No rows were found at ${source.rowsPath}.");
  }
  return DataResult.ok(rows, _fieldsIn(valueAtPath(json, source.rowsPath)));
}

/// _fieldsIn is every dotted path that leads to a value in the first record.
///
/// The first record only: a hundred identical shapes tell you nothing the
/// first one did not, and walking them all on a long table is work for no
/// answer. Lists are described by their first entry, so "standings.0.table"
/// is offered rather than one path per row.
List<String> _fieldsIn(dynamic records, {String prefix = "", int depth = 0}) {
  if (records is List) {
    return records.isEmpty
        ? const []
        : _fieldsIn(records.first, prefix: prefix, depth: depth);
  }
  if (records is! Map || depth > 3) return const [];

  var out = <String>[];
  for (var entry in records.entries) {
    var path = prefix.isEmpty ? "${entry.key}" : "$prefix.${entry.key}";
    var value = entry.value;
    if (value is Map || value is List) {
      out.addAll(_fieldsIn(value, prefix: path, depth: depth + 1));
    } else if (value != null) {
      out.add(path);
    }
  }
  out.sort();
  return out;
}

/// _fetch is the request itself.
///
/// A plain HttpClient rather than a package, because this is one GET with one
/// header and the app has no HTTP dependency to reuse. The key is read here
/// from the machine's own store rather than passed in, so that no caller ever
/// holds one and it cannot be written into a document by accident.
Future<String?> _fetch(DataSource source) async {
  var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    var address = Uri.tryParse(source.where);
    if (address == null || !address.isScheme("https")) {
      // https only. A key sent in a header over http is a key sent to whoever
      // is between the two machines.
      debugPrint("A canvas data source must be an https address");
      return null;
    }

    var request = await client.getUrl(address);
    var key = await CanvasApiKeys.read(address.host);
    if (key.isNotEmpty) {
      // football-data.org's header, which is also the commonest spelling of
      // this among the APIs a table is likely to come from.
      request.headers.set("X-Auth-Token", key);
    }
    var response = await request.close();
    if (response.statusCode != 200) {
      debugPrint("The data source answered ${response.statusCode}");
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } catch (exception) {
    debugPrint("Unable to fetch the canvas data: $exception");
    return null;
  } finally {
    client.close(force: true);
  }
}

/// collectPictures replaces the addresses in a table's picture columns with
/// pictures actually stored on this machine.
///
/// One request per distinct address, and the results are content-addressed --
/// so twenty rows sharing a crest store one file, and refreshing a table whose
/// crests have not changed stores nothing at all.
///
/// A picture that cannot be had is left as its address. The cell then shows a
/// URL, which is visibly wrong in a way an empty cell is not.
Future<List<List<String>>> collectPictures(
  List<List<String>> rows,
  DataSource source, {
  bool allowFetching = false,
}) async {
  var wanted = <int>[
    for (var i = 0; i < source.columns.length; i++)
      if (source.columns[i].picture) i,
  ];
  if (wanted.isEmpty || !allowFetching) return rows;

  var stored = <String, String>{};
  var out = [
    for (var row in rows) [...row]
  ];
  // Skipping the header, which holds a column name rather than an address.
  for (var r = 1; r < out.length; r++) {
    for (var c in wanted) {
      if (c >= out[r].length) continue;
      var address = out[r][c].trim();
      if (!address.startsWith("https://")) continue;

      // Three places to look before the network: this refresh, this
      // machine's memory of earlier ones, and only then the address itself.
      // A league table is twenty crests that have not changed since last
      // week, and fetching them again every time is most of a free tier's
      // allowance spent on pictures nobody needed.
      var id = stored[address] ??
          await CanvasPictureCache.known(address) ??
          await _storePicture(address);
      if (id == null) continue;
      stored[address] = id;
      out[r][c] = "img:$id";
    }
  }
  return out;
}

Future<String?> _storePicture(String address) async {
  var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    var uri = Uri.tryParse(address);
    if (uri == null || !uri.isScheme("https")) return null;
    var response = await (await client.getUrl(uri)).close();
    if (response.statusCode != 200) return null;

    var bytes = <int>[];
    await for (var chunk in response) {
      bytes.addAll(chunk);
      // A crest is a few kilobytes. Anything running away with itself is not
      // one, and the store would refuse it a moment later anyway.
      if (bytes.length > maxAssetBytes) return null;
    }
    var id = await CanvasAssets.save(bytes);
    if (id != null) await CanvasPictureCache.remember(address, id);
    return id;
  } catch (exception) {
    debugPrint("Unable to collect the picture at $address: $exception");
    return null;
  } finally {
    client.close(force: true);
  }
}

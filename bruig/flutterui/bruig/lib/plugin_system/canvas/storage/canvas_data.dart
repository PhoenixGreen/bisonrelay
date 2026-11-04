import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_picture_cache.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';

// canvas_data.dart goes and gets what a data source describes.
//
// Two ways in. Reading a file is the ordinary one: whatever collects the
// data (a browser, curl, a scheduled script) writes JSON somewhere and the
// canvas reads it when asked. The other connects to the internet, which
// nothing else in this app's interface does, and is refused unless the reader
// has turned it on (see CanvasPreferences.allowFetching).
//
// Everything is on demand, with no polling or background refresh: a canvas
// that connected to a server every few minutes would announce that its owner
// was at their desk.

/// DataResult is what came back, or why nothing did.
class DataResult {
  final List<List<String>>? rows;
  final String? problem;

  /// fields is every path that led to a value in the first record: what the
  /// settings panel offers as "Available", so a column's path is chosen from
  /// what is actually there.
  final List<String> fields;

  /// raw is the same rows with any date column left as the timestamp it
  /// arrived as; empty when no column is a date. For a chart choosing its
  /// points by date, which formatted cells ("Feb 26") cannot give. See
  /// rowsFromJson.
  final List<List<String>> raw;

  const DataResult.ok(this.rows, [this.fields = const [], this.raw = const []])
      : problem = null;
  const DataResult.failed(this.problem)
      : rows = null,
        fields = const [],
        raw = const [];

  bool get worked => rows != null;
}

/// maxDataFileBytes is the most a data file can be.
const int maxDataFileBytes = 20 * 1024 * 1024;

/// DataFiles are the files this machine's owner has said a data source may
/// read: chosen with the picker, or agreed to when asked. A canvas comes from
/// other people, and its path would otherwise read whatever file it names.
class DataFiles {
  static const _key = "canvasDataFiles";

  static Future<Set<String>> _all() async =>
      (await StorageManager.readString(_key))
          .split("\n")
          .where((p) => p.isNotEmpty)
          .toSet();

  static Future<bool> allowed(String path) async =>
      (await _all()).contains(path);

  static Future<void> allow(String path) async {
    var all = await _all();
    if (all.add(path)) await StorageManager.saveString(_key, all.join("\n"));
  }
}

/// loadData reads [source] and maps it into rows. [allowFetching] and
/// [proxied] are handed in rather than read here, so the decision is
/// testable and this file does not reach for the app's settings.
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
        var type = await FileSystemEntity.type(source.where);
        if (type == FileSystemEntityType.notFound) {
          return DataResult.failed("There is no file at ${source.where}.");
        }
        // Not a device, a pipe or a folder, and not more than a table holds.
        if (type != FileSystemEntityType.file) {
          return const DataResult.failed("That is not a file.");
        }
        if (await file.length() > maxDataFileBytes) {
          return const DataResult.failed("That file is too big to be data.");
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
      // Refused rather than quietly bypassed: a reader using a SOCKS proxy has
      // said how they want to reach the network, and this request would not
      // go that way.
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
  return DataResult.ok(
    rows,
    _fieldsIn(valueAtPath(json, source.rowsPath)),
    // Only where there is a date to keep, since for everything else these are
    // the same rows again.
    source.columns.any((c) => c.date.isNotEmpty)
        ? rowsFromJson(json, source, raw: true)
        : const [],
  );
}

/// _fieldsIn is every dotted path a record has, whether or not it holds
/// anything: a field that came back null is still a field, and leaving it out
/// would mark a column mapped to it as missing.
///
/// The first record only, and a list by its first entry. A field missing
/// from the first record but present in others cannot be seen, which is why
/// the preset's own list is offered alongside this one.
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
    if (value is Map || (value is List && value.isNotEmpty)) {
      out.addAll(_fieldsIn(value, prefix: path, depth: depth + 1));
    } else {
      out.add(path);
    }
  }
  out.sort();
  return out;
}

/// _fetch is the request itself: a plain HttpClient, for one GET with one
/// header. The key is read here from the machine's store rather than passed
/// in, so no caller holds one and it cannot end up in a document.
Future<String?> _fetch(DataSource source) async {
  var client = canvasHttpClient();
  try {
    // https only (see canvasGet): a key sent in a header over http is a key
    // sent to whoever is between the two machines.
    var address = Uri.tryParse(source.where);
    if (address == null) return null;
    var key = await CanvasApiKeys.read(address.host);
    // football-data.org's header, which is also the commonest spelling of
    // this among the APIs a table is likely to come from.
    var response = await canvasGet(client, address,
        headers: {if (key.isNotEmpty) "X-Auth-Token": key});
    if (response?.statusCode != 200) {
      debugPrint("The data source answered ${response?.statusCode}");
      return null;
    }
    var bytes = await readCapped(response!, maxDataFileBytes);
    return bytes == null ? null : utf8.decode(bytes);
  } catch (exception) {
    debugPrint("Unable to fetch the canvas data: $exception");
    return null;
  } finally {
    client.close(force: true);
  }
}

/// fetchJsonAt is one more request, for a source that needs a second look:
/// whatever a preset asked for, which the preset knows how to read. Null on
/// any failure, which the caller treats as "leave the rows alone". Behind the
/// same switch as everything here, and refused when a proxy is configured.
Future<dynamic> fetchJsonAt(
  String url, {
  bool allowFetching = false,
  bool proxied = false,
}) async {
  if (!allowFetching || proxied) return null;
  var text = await _fetch(DataSource(kind: DataKind.url, where: url));
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } catch (exception) {
    debugPrint("The second request did not answer with JSON: $exception");
    return null;
  }
}

/// collectPictures replaces the addresses in a table's picture columns with
/// pictures stored on this machine. One request per distinct address, stored
/// by content, so rows sharing a crest store one file. A picture that cannot
/// be had is left as its address: a visible URL is more obviously wrong than
/// an empty cell.
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
      // machine's memory of earlier ones, and only then the address itself,
      // so unchanged crests do not spend an API's allowance.
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
  var client = canvasHttpClient();
  try {
    var uri = Uri.tryParse(address);
    if (uri == null) return null;
    var response = await canvasGet(client, uri);
    if (response?.statusCode != 200) return null;
    var bytes = await readCapped(response!, maxAssetBytes);
    if (bytes == null) return null;
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

import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_api_keys.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_picture_cache.dart';
import 'package:bruig/storage_manager.dart';
import 'package:flutter/foundation.dart';

// canvas_data.dart fetches what a data source describes. Reading a file is
// the ordinary way: whatever collects the data writes JSON somewhere and
// the canvas reads it when asked. Fetching from the internet, which nothing
// else in the app's interface does, is refused unless the reader turned it
// on (CanvasPreferences.allowFetching). Everything is on demand, never
// polled: a canvas calling a server every few minutes would announce that
// its owner was at their desk.

/// DataResult is what came back, or why nothing did.
class DataResult {
  final List<List<String>>? rows;
  final String? problem;

  /// fields is every path to a value in the first record: what the settings
  /// panel offers as "Available", so a column's path is chosen from what is
  /// there.
  final List<String> fields;

  /// raw is the same rows with date columns left as the timestamps they
  /// arrived as, or empty when none is a date: for a chart choosing points by
  /// date, which formatted cells ("Feb 26") cannot give. See rowsFromJson.
  final List<List<String>> raw;

  const DataResult.ok(this.rows, [this.fields = const [], this.raw = const []])
      : problem = null;
  const DataResult.failed(this.problem)
      : rows = null,
        fields = const [],
        raw = const [];

  bool get worked => rows != null;
}

const int maxDataFileBytes = 20 * 1024 * 1024;

/// DataFiles are the files this machine's owner has let a data source read:
/// picked, or agreed to when asked. A canvas comes from other people, and
/// its path would otherwise read whatever file it names.
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

/// DataHosts are the hosts this machine's owner has let a data source fetch
/// from: named here, or agreed to when asked. Otherwise a received canvas
/// naming its sender's server would tell that server who opened it as soon
/// as its rows refreshed.
class DataHosts {
  static const _key = "canvasDataHosts";

  static Future<Set<String>> _all() async =>
      (await StorageManager.readString(_key))
          .split("\n")
          .where((h) => h.isNotEmpty)
          .toSet();

  /// hostOf is [where]'s host, or empty where it names none.
  static String hostOf(String where) =>
      (Uri.tryParse(where.trim())?.host ?? "").toLowerCase();

  static Future<bool> allowed(String where) async {
    var host = hostOf(where);
    return host.isNotEmpty && (await _all()).contains(host);
  }

  static Future<void> allow(String where) async {
    var host = hostOf(where);
    if (host.isEmpty) return;
    var all = await _all();
    if (all.add(host)) await StorageManager.saveString(_key, all.join("\n"));
  }
}

/// JsonResult is a source's answer read and decoded, or why not: what
/// [loadData] maps, kept whole by Connect data so its columns can be chosen
/// and previewed without asking again.
class JsonResult {
  final dynamic json;
  final String? problem;
  const JsonResult.ok(this.json) : problem = null;
  const JsonResult.failed(this.problem) : json = null;
  bool get worked => problem == null;
}

/// loadJson reads and decodes [source], with [loadData]'s switches.
Future<JsonResult> loadJson(
  DataSource source, {
  bool allowFetching = false,
  bool proxied = false,
}) async {
  if (!source.on) return const JsonResult.failed("There is no data source.");

  String text;
  switch (source.kind) {
    case DataKind.typed:
      return const JsonResult.failed("There is no data source.");

    case DataKind.file:
      // Only a file picked here or agreed to when asked: a path inside somebody
      // else's canvas reads nothing on its own, whoever calls this.
      if (!await DataFiles.allowed(source.where)) {
        return JsonResult.failed(
            "This canvas asks to read ${source.where}, which has not been "
            "allowed here.");
      }
      try {
        var file = File(source.where);
        var type = await FileSystemEntity.type(source.where);
        if (type == FileSystemEntityType.notFound) {
          return JsonResult.failed("There is no file at ${source.where}.");
        }
        // Not a device, pipe or folder, and no bigger than a table holds.
        if (type != FileSystemEntityType.file) {
          return const JsonResult.failed("That is not a file.");
        }
        if (await file.length() > maxDataFileBytes) {
          return const JsonResult.failed("That file is too big to be data.");
        }
        text = await file.readAsString();
      } catch (exception) {
        debugPrint("Unable to read the canvas data file: $exception");
        return const JsonResult.failed("That file could not be read.");
      }

    case DataKind.url:
      if (!allowFetching) {
        return const JsonResult.failed(
            "Fetching is switched off. Turn it on in Settings > Plugins > "
            "Canvas, or use a file instead.");
      }
      // Refused rather than quietly bypassed: a reader with a SOCKS proxy has
      // said how to reach the network, and this request would not go that way.
      if (proxied) {
        return const JsonResult.failed(
            "This app is set to reach the network through a proxy, which a "
            "fetch from the canvas cannot use. Use a file instead.");
      }
      var fetched = await _fetch(source);
      if (fetched == null) {
        return const JsonResult.failed("Nothing came back from that address.");
      }
      text = fetched;
  }

  try {
    return JsonResult.ok(jsonDecode(text));
  } catch (exception) {
    debugPrint("The canvas data is not JSON: $exception");
    return const JsonResult.failed("That is not JSON.");
  }
}

/// loadData reads [source] and maps it into rows. [allowFetching] and
/// [proxied] are passed in so the decision is testable and this file does
/// not reach for the app's settings.
Future<DataResult> loadData(
  DataSource source, {
  bool allowFetching = false,
  bool proxied = false,
}) async {
  var read =
      await loadJson(source, allowFetching: allowFetching, proxied: proxied);
  if (!read.worked) return DataResult.failed(read.problem);
  return mapData(read.json, source);
}

/// mapData maps [json] by [source] into rows, as [loadData] does.
DataResult mapData(dynamic json, DataSource source) {
  var rows = rowsFromJson(json, source);
  if (rows.isEmpty) {
    return DataResult.failed(source.rowsPath.isEmpty
        ? "No rows were found. Is the document a list?"
        : "No rows were found at ${source.rowsPath}.");
  }
  return DataResult.ok(
    rows,
    _fieldsIn(valueAtPath(json, source.rowsPath)),
    // Only where there is a date to keep; otherwise these are the same rows.
    source.columns.any((c) => c.date.isNotEmpty)
        ? rowsFromJson(json, source, raw: true)
        : const [],
  );
}

/// fieldsAt is every field the records at [rowsPath] in [json] have; in
/// their own order with [sorted] false, as a first mapping lays them out.
List<String> fieldsAt(dynamic json, String rowsPath, {bool sorted = true}) =>
    _fieldsIn(valueAtPath(json, rowsPath), sorted: sorted);

/// listsIn is every list of records inside [json], where a table's rows
/// might be, as (path, count), the answer itself first if it is one. For
/// Connect data's "which list is the rows".
List<(String, int)> listsIn(dynamic json, {String prefix = "", int depth = 0}) {
  var out = <(String, int)>[];
  if (json is List) {
    if (json.isNotEmpty && (json.first is Map || json.first is List)) {
      out.add((prefix, json.length));
    }
    if (json.isNotEmpty && depth < 4) {
      out.addAll(listsIn(json.first,
          prefix: prefix.isEmpty ? "0" : "$prefix.0", depth: depth + 1));
    }
  } else if (json is Map && depth < 4) {
    for (var MapEntry(:key, :value) in json.entries) {
      out.addAll(listsIn(value,
          prefix: prefix.isEmpty ? "$key" : "$prefix.$key", depth: depth + 1));
    }
  }
  return out;
}

/// _fieldsIn is every dotted path a record has, even one holding null:
/// leaving it out would mark a column mapped to it missing. Only the first
/// record (and a list's first entry) is read, so a field absent there
/// cannot be seen; hence the preset's own list is offered alongside.
List<String> _fieldsIn(dynamic records,
    {String prefix = "", int depth = 0, bool sorted = true}) {
  if (records is List) {
    return records.isEmpty
        ? const []
        : _fieldsIn(records.first,
            prefix: prefix, depth: depth, sorted: sorted);
  }
  if (records is! Map || depth > 3) return const [];

  var out = <String>[];
  for (var entry in records.entries) {
    var path = prefix.isEmpty ? "${entry.key}" : "$prefix.${entry.key}";
    var value = entry.value;
    if (value is Map || (value is List && value.isNotEmpty)) {
      out.addAll(
          _fieldsIn(value, prefix: path, depth: depth + 1, sorted: sorted));
    } else {
      out.add(path);
    }
  }
  if (sorted) out.sort();
  return out;
}

/// _fetch is one GET with one header on a plain HttpClient. The key is read
/// here from the machine's store, so no caller holds it and it cannot end
/// up in a document.
Future<String?> _fetch(DataSource source) async {
  var client = canvasHttpClient();
  try {
    // https only (see canvasGet): a key sent in a header over http is sent to
    // whoever is between the two machines.
    var address = Uri.tryParse(source.where);
    if (address == null) return null;
    var key = await CanvasApiKeys.read(address.host);
    // football-data.org's header, also the commonest spelling among the APIs
    // a table is likely to use.
    var response = await canvasGet(client, address,
        headers: {if (key.isNotEmpty) "X-Auth-Token": key});
    if (response?.statusCode != 200) {
      debugPrint("The data source answered ${response?.statusCode}");
      return null;
    }
    var bytes = await readCapped(response!, maxDataFileBytes);
    return bytes == null ? null : utf8.decode(bytes);
  } catch (exception) {
    debugPrint("Unable to fetch the canvas data: ${exception.runtimeType}");
    return null;
  } finally {
    client.close(force: true);
  }
}

/// fetchJsonAt is a second request for a preset that needs one, which the
/// preset knows how to read. Null on any failure, meaning "leave the rows
/// alone". Behind the same switch, and refused when a proxy is configured.
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

/// collectPictures replaces addresses in a table's picture columns with
/// pictures stored on this machine: one request per distinct address,
/// stored by content, so rows sharing a crest share a file. A picture that
/// cannot be had stays an address, more obviously wrong than an empty cell.
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

      // Before the network: this refresh, then this machine's memory of earlier
      // ones, so unchanged crests do not spend an API's allowance.
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

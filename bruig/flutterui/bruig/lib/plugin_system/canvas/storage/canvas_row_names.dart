import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_row_names.dart is the list of things a source has: every coin
// CoinGecko knows, and any later source with a list of rows. A built-in
// list cannot be right -- CoinGecko files Firo under "zcoin" and XRP under
// "ripple" -- so the list is fetched once and kept; the built-in one is
// only what is offered before then.

class CanvasRowNames {
  /// _loaded is each preset's fetched list for this run: identifier by
  /// asRowKey of the name, as a cell is matched, so a row saying "Bitcoin
  /// Cash" finds bitcoin-cash.
  static final Map<String, Map<String, String>> _loaded = {};

  /// _names is the same lists as names, in arrival order, for the cell that
  /// suggests one.
  static final Map<String, List<String>> _names = {};

  /// known is what has been fetched for [presetId], or null. Synchronous on
  /// purpose: the settings panel asks while it builds.
  static Map<String, String>? known(String presetId) => _loaded[presetId];

  /// idFor is what to ask for when a row says [cell]: the fetched identifier
  /// (the source's own answer, so it wins), else the preset's own, else the
  /// cell's own key.
  static String idFor(DataPreset preset, String cell) {
    var fetched = _loaded[preset.id];
    if (fetched != null) {
      var found = fetched[asRowKey(cell)];
      if (found != null) return found;
    }
    return preset.idFor(cell);
  }

  /// suggestionsFor is what to offer while somebody types a row.
  static List<String> suggestionsFor(DataPreset? preset) {
    if (preset == null) return const [];
    return _names[preset.id] ?? preset.rowNames;
  }

  /// load reads a list fetched in an earlier sitting; it does nothing once
  /// the list is in memory.
  static Future<void> load(String presetId) async {
    if (_loaded.containsKey(presetId)) return;
    try {
      var file = File(await _pathFor(presetId));
      if (!await file.exists()) return;
      var raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      _remember(presetId, {
        for (var entry in raw.entries)
          if (entry.value is String) "${entry.key}": entry.value as String,
      });
    } catch (exception) {
      debugPrint("The saved list of names could not be read: $exception");
    }
  }

  /// fetch asks the source for its list and keeps it. Returns how many it
  /// knows, or null where the request failed, which the caller reports.
  static Future<int?> fetch(
    DataPreset preset,
    Future<dynamic> Function(String url) get,
  ) async {
    if (preset.namesAddress.isEmpty) return null;
    var raw = await get(preset.namesAddress);
    if (raw is! List) return null;

    var byKey = <String, String>{};
    var names = <String>[];
    for (var entry in raw) {
      if (entry is! Map) continue;
      var id = entry[preset.namesId];
      var name = entry[preset.namesName];
      if (id is! String || name is! String) continue;
      if (id.isEmpty || name.isEmpty) continue;
      var key = asRowKey(name);
      if (key.isEmpty) continue;
      // The first of a name wins: CoinGecko lists the real coin before its
      // imitators of the same name.
      if (byKey.containsKey(key)) continue;
      byKey[key] = id;
      names.add(name);
    }
    if (byKey.isEmpty) return null;

    _remember(preset.id, byKey, names);
    try {
      await writeWholeText(await _pathFor(preset.id), jsonEncode(byKey));
    } catch (exception) {
      // Kept for this sitting even where it cannot be written: failing to save
      // it is no reason to throw it away.
      debugPrint("The list of names could not be saved: $exception");
    }
    return byKey.length;
  }

  static void _remember(String presetId, Map<String, String> byKey,
      [List<String>? names]) {
    _loaded[presetId] = byKey;
    _names[presetId] = names ?? byKey.keys.toList();
  }

  /// forget drops what is held, for tests and a stale list.
  @visibleForTesting
  static void forget() {
    _loaded.clear();
    _names.clear();
  }

  static Future<String> _pathFor(String presetId) async => path.join(
      await CanvasStorage.libraryDir(), "names-${asRowKey(presetId)}.json");
}

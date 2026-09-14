import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_row_names.dart is the list of things a source has: every coin
// CoinGecko knows, and whatever the next source with a list of rows turns out
// to hold.
//
// It exists because the built-in list could not be right. Two hundred
// identifiers written out by hand are two hundred chances to be wrong, and
// wrong here is invisible until somebody types a name and the refresh comes
// back without it -- CoinGecko files Firo under "zcoin" and XRP under
// "ripple", and there is no way to know that except to ask. So the list is
// asked for, once, and kept.
//
// The built-in list stays as what is offered before anybody asks. It is short
// and it is a guess; this is long and it is the truth.

/// CanvasRowNames is the fetched list, in memory and on disk.
class CanvasRowNames {
  /// _loaded is what each preset's list turned out to be, for this run.
  ///
  /// Name key to identifier -- keyed by asRowKey of the name, the same way a
  /// cell is matched, so a row saying "Bitcoin Cash" finds bitcoin-cash.
  static final Map<String, Map<String, String>> _loaded = {};

  /// _names is the same lists as names, in the order they arrived, for the
  /// cell that suggests one.
  static final Map<String, List<String>> _names = {};

  /// known is what has been fetched for [presetId], or null where nothing
  /// has. Synchronous on purpose: the settings panel asks while it builds,
  /// and a future there is a panel that flickers into place.
  static Map<String, String>? known(String presetId) => _loaded[presetId];

  /// namesOf is the same list as names to suggest, or null.
  static List<String>? namesOf(String presetId) => _names[presetId];

  /// idFor is what to ask for when a row says [cell]: the fetched identifier,
  /// the preset's own where nothing has been fetched, and the cell's own key
  /// where neither knows it.
  ///
  /// The fetched list wins because it is the source's own answer. The built-in
  /// one is a guess that was written months ago against an API that renames
  /// things -- Firo used to be Zcoin, and its identifier still says so.
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

  /// load reads a list fetched in some earlier sitting. Cheap and safe to
  /// call again: it does nothing once the list is in memory.
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

  /// fetch asks the source for its list and keeps it.
  ///
  /// Returns how many it now knows, or null where the request failed --
  /// which the caller says out loud rather than leaving the button looking
  /// like it did nothing.
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
      // The first of a name wins. CoinGecko has several coins called the same
      // thing -- a dozen tokens named "Ethereum" something -- and the list
      // comes back with the real one before its imitators.
      if (byKey.containsKey(key)) continue;
      byKey[key] = id;
      names.add(name);
    }
    if (byKey.isEmpty) return null;

    _remember(preset.id, byKey, names);
    try {
      await File(await _pathFor(preset.id)).writeAsString(jsonEncode(byKey));
    } catch (exception) {
      // Kept for this sitting even where it cannot be written: the list is
      // useful now, and failing to save it is not a reason to throw it away.
      debugPrint("The list of names could not be saved: $exception");
    }
    return byKey.length;
  }

  static void _remember(String presetId, Map<String, String> byKey,
      [List<String>? names]) {
    _loaded[presetId] = byKey;
    _names[presetId] = names ?? byKey.keys.toList();
  }

  /// forget drops what is held, for tests and for a list that has gone stale.
  @visibleForTesting
  static void forget() {
    _loaded.clear();
    _names.clear();
  }

  static Future<String> _pathFor(String presetId) async => path.join(
      await CanvasStorage.libraryDir(), "names-${asRowKey(presetId)}.json");
}

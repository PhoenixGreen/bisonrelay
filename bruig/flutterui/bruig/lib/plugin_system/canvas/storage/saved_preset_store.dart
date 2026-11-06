import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// saved_preset_store.dart keeps the scenes and the canvases somebody has
// saved, as element_preset_store.dart keeps the elements: one file per
// preset, in a folder of its own under the presets folder.

/// presetsFolderName is where every kind of preset lives, inside the canvas
/// library. The leading dot keeps it out of the Files panel (see
/// CanvasStorage.list).
const presetsFolderName = ".presets";

/// SavedPresetStore is one kind's worth of them, kept in memory so a panel
/// can draw the list without waiting for the disk. One instance per kind, so
/// a change to one does not redraw the other's panel.
class SavedPresetStore extends ChangeNotifier {
  static final SavedPresetStore scenes =
      SavedPresetStore._(SavedPresetKind.scene);
  static final SavedPresetStore canvases =
      SavedPresetStore._(SavedPresetKind.canvas);
  static final SavedPresetStore brushes =
      SavedPresetStore._(SavedPresetKind.brush);
  static final SavedPresetStore pitchViews =
      SavedPresetStore._(SavedPresetKind.pitchView);
  static final SavedPresetStore looks =
      SavedPresetStore._(SavedPresetKind.look);
  static final SavedPresetStore paintBrushes =
      SavedPresetStore._(SavedPresetKind.paintBrush);
  static final SavedPresetStore devices =
      SavedPresetStore._(SavedPresetKind.device);

  final SavedPresetKind kind;
  SavedPresetStore._(this.kind);

  List<SavedPreset> _saved = const [];
  bool _loaded = false;
  Future<void>? _loading;

  /// presets are what has been saved, by name.
  List<SavedPreset> get presets => _saved;

  bool get loaded => _loaded;

  /// load reads the folder, once. Called again while it is reading, it joins
  /// the read in progress rather than starting a second one.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _read();
  }

  Future<void> _read() async {
    try {
      var dir = Directory(await _dir());
      if (await dir.exists()) {
        var found = <SavedPreset>[];
        await for (var file in dir.list(followLinks: false)) {
          if (file is! File || !file.path.endsWith(".json")) continue;
          try {
            var json = jsonDecode(await file.readAsString());
            if (json is Map<String, dynamic>) {
              found.add(SavedPreset.fromJson(json));
            }
          } catch (exception) {
            debugPrint("Unable to read the preset ${file.path}: $exception");
          }
        }
        _saved = _sorted(found);
      }
    } catch (exception) {
      debugPrint("Unable to read the saved ${kind.folder}: $exception");
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  /// save keeps [data] under [name] and answers with the preset it made.
  /// [data] is copied on the way in: a preset is a copy, not a link to the
  /// scene it came from.
  Future<SavedPreset?> save(String name, Map<String, dynamic> data,
      {Size? madeOn}) async {
    var clean = name.trim();
    if (clean.isEmpty) return null;
    await load();

    var preset = SavedPreset(
      id: "p${DateTime.now().microsecondsSinceEpoch}",
      name: clean,
      kind: kind,
      data: jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
      made: DateTime.now(),
      madeOn: madeOn,
    );
    if (!await _write(preset)) return null;

    _saved = _sorted([..._saved, preset]);
    notifyListeners();
    return preset;
  }

  /// rename changes what one is called.
  Future<bool> rename(SavedPreset preset, String name) async {
    var clean = name.trim();
    if (clean.isEmpty || clean == preset.name) return false;
    var next = preset.copyWith(name: clean);
    if (!await _write(next)) return false;

    _saved = _sorted([
      for (var p in _saved) p.id == preset.id ? next : p,
    ]);
    notifyListeners();
    return true;
  }

  /// remove deletes one.
  Future<bool> remove(SavedPreset preset) async {
    try {
      var file = File(path.join(await _dir(), "${preset.id}.json"));
      if (await file.exists()) await file.delete();
    } catch (exception) {
      debugPrint("Unable to delete the preset ${preset.id}: $exception");
      return false;
    }
    _saved = [
      for (var p in _saved)
        if (p.id != preset.id) p
    ];
    notifyListeners();
    return true;
  }

  List<SavedPreset> _sorted(List<SavedPreset> list) => list
    ..sort((a, b) {
      var byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.made.compareTo(b.made);
    });

  Future<bool> _write(SavedPreset preset) async {
    try {
      var dir = Directory(await _dir());
      if (!await dir.exists()) await dir.create(recursive: true);
      await writeWholeText(path.join(dir.path, "${preset.id}.json"),
          jsonEncode(preset.toJson()));
      return true;
    } catch (exception) {
      debugPrint("Unable to save the preset ${preset.name}: $exception");
      return false;
    }
  }

  Future<String> _dir() async => path.join(
      await CanvasStorage.libraryDir(), presetsFolderName, kind.folder);

  /// forget drops what has been read, for the tests that write a folder and
  /// then expect to see it.
  @visibleForTesting
  void forget() {
    _saved = const [];
    _loaded = false;
    _loading = null;
  }
}

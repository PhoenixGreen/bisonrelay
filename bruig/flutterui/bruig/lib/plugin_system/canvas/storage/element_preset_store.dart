import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_element_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// element_preset_store.dart keeps the designs somebody has saved.
//
// One file per preset in a hidden folder beside the canvases, rather than one
// list that two windows could both rewrite, losing one's preset. The leading
// dot keeps the folder out of the Files panel (see CanvasStorage.list).

/// _folderName is where they live, inside the canvas library.
const _folderName = ".presets";

/// ElementPresetStore is the presets, built in and saved, kept in memory so a
/// settings panel can draw them without waiting for the disk. A single
/// ChangeNotifier, because the panel that lists them and the button that
/// saves one are in different parts of the tree. Loaded once, on first look.
class ElementPresetStore extends ChangeNotifier {
  static final ElementPresetStore instance = ElementPresetStore();

  List<ElementPreset> _saved = const [];
  bool _loaded = false;
  Future<void>? _loading;

  /// presets are the built-in ones first, then whatever has been saved, so
  /// the start of the list never moves.
  List<ElementPreset> get presets => [...builtinElementPresets, ..._saved];

  /// forKind is the presets that make one kind of element.
  List<ElementPreset> forKind(ElementKind kind) => [
        for (var p in presets)
          if (p.kind == kind) p
      ];

  /// loaded says whether the disk has been read yet. A panel drawing before
  /// it has shows the built-in ones.
  bool get loaded => _loaded;

  /// load reads the folder, once. Calling it again while it is reading joins
  /// the read in progress rather than starting a second one.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _read();
  }

  Future<void> _read() async {
    try {
      var dir = Directory(await _dir());
      if (await dir.exists()) {
        var found = <ElementPreset>[];
        await for (var file in dir.list(followLinks: false)) {
          if (file is! File || !file.path.endsWith(".json")) continue;
          try {
            var json = jsonDecode(await file.readAsString());
            if (json is Map<String, dynamic>) {
              found.add(ElementPreset.fromJson(json));
            }
          } catch (exception) {
            debugPrint("Unable to read the preset ${file.path}: $exception");
          }
        }
        found.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _saved = found;
      }
    } catch (exception) {
      debugPrint("Unable to read the saved presets: $exception");
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  /// save keeps [element] under [name], and returns the preset it made.
  /// [madeOn] is the page it was designed on, so it can be sized to the page
  /// it is dropped on later (see presetScale).
  Future<ElementPreset?> save(String name, CanvasElement element,
      {Size? madeOn}) async {
    var clean = name.trim();
    if (clean.isEmpty) return null;
    await load();

    var preset = ElementPreset(
      id: "p${DateTime.now().microsecondsSinceEpoch}",
      name: clean,
      kind: element.kind,
      // Without its place on the canvas: a preset is dropped where the canvas
      // decides, and saved coordinates could land it off a smaller page.
      element: {...element.toJson()}
        ..remove("id")
        ..remove("x")
        ..remove("y")
        ..remove("track"),
      madeOn: madeOn,
    );
    if (!await _write(preset)) return null;

    _saved = [..._saved, preset]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return preset;
  }

  /// rename changes what a saved preset is called. Built-in ones are not the
  /// reader's to rename.
  Future<bool> rename(ElementPreset preset, String name) async {
    var clean = name.trim();
    if (preset.builtIn || clean.isEmpty) return false;
    var next = preset.copyWith(name: clean);
    if (!await _write(next)) return false;

    _saved = [
      for (var p in _saved) p.id == preset.id ? next : p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return true;
  }

  /// remove deletes a saved preset.
  Future<bool> remove(ElementPreset preset) async {
    if (preset.builtIn) return false;
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

  Future<bool> _write(ElementPreset preset) async {
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

  Future<String> _dir() async =>
      path.join(await CanvasStorage.libraryDir(), _folderName);

  /// forget drops what has been read, for the tests that write a folder and
  /// then expect to see it.
  @visibleForTesting
  void forget() {
    _saved = const [];
    _loaded = false;
    _loading = null;
  }
}

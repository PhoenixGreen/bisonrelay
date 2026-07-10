import 'dart:convert';
import 'dart:io';

import 'package:bruig/config.dart';
import 'package:bruig/models/palette_library.dart';
import 'package:path/path.dart' as path;

// PaletteLibraryStorage persists user-saved ColorPalettes (see
// palette_library.dart) as one plain JSON file per palette under
// "<appDataDir>/palettes/<id>.json". Unlike ThemePresetStorage, palettes
// carry no images, so there's no directory-per-preset or zip packaging --
// export/import work directly on that single JSON file.
class PaletteLibraryStorage {
  static Future<String> palettesDir() async {
    var dir = path.join(await defaultAppDataDir(), "palettes");
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> _paletteFile(String id) async =>
      path.join(await palettesDir(), "$id.json");

  static Future<List<ColorPalette>> listPalettes() async {
    var dir = Directory(await palettesDir());
    if (!await dir.exists()) return [];

    var res = <ColorPalette>[];
    await for (var entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith(".json")) continue;
      try {
        var j = jsonDecode(await entry.readAsString());
        res.add(ColorPalette.fromJson(j));
      } catch (exception) {
        // Skip corrupt/unreadable palettes rather than failing startup.
        continue;
      }
    }
    return res;
  }

  static Future<void> savePalette(ColorPalette palette) async {
    var file = File(await _paletteFile(palette.id));
    await file.writeAsString(jsonEncode(palette.toJson()));
  }

  static Future<void> deletePalette(String id) async {
    var file = File(await _paletteFile(id));
    if (await file.exists()) {
      await file.delete();
    }
  }

  // exportPalette returns the palette's JSON as a UTF-8 byte array, ready
  // to be written wherever the caller's file-save dialog points.
  static Future<List<int>> exportPalette(ColorPalette palette) async =>
      utf8.encode(jsonEncode(palette.toJson()));

  // importPalette parses a previously-exported palette JSON file, assigns
  // it a fresh id (so importing never collides with an existing palette),
  // saves it, and returns the resulting ColorPalette.
  static Future<ColorPalette> importPalette(List<int> jsonBytes) async {
    var j = jsonDecode(utf8.decode(jsonBytes));
    var palette = ColorPalette.fromJson(j);
    palette = ColorPalette(
        id: "imported-${DateTime.now().millisecondsSinceEpoch}",
        name: palette.name,
        colors: palette.colors);
    await savePalette(palette);
    return palette;
  }
}

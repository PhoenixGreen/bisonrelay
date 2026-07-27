import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bruig/config.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:path/path.dart' as path;

// ThemePresetStorage persists custom ThemePresets as directories under
// "<appDataDir>/themes/<id>/", each holding a preset.json plus an optional
// images/ subfolder for area background images. Presets are addressed by
// this directory rather than a bare JSON file so that area image references
// stay self-contained (relative paths) and portable across machines when
// exported/imported as a zip.
class ThemePresetStorage {
  static Future<String> themesDir() async {
    var dir = path.join(await defaultAppDataDir(), "themes");
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static Future<String> presetDir(String id) async =>
      path.join(await themesDir(), id);

  // listPresets loads every saved preset from disk.
  static Future<List<ThemePreset>> listPresets() async {
    var dir = Directory(await themesDir());
    if (!await dir.exists()) return [];

    var res = <ThemePreset>[];
    await for (var entry in dir.list()) {
      if (entry is! Directory) continue;
      var jsonFile = File(path.join(entry.path, "preset.json"));
      if (!await jsonFile.exists()) continue;
      try {
        var j = jsonDecode(await jsonFile.readAsString());
        res.add(ThemePreset.fromJson(j).copyWith(sourceDir: entry.path));
      } catch (exception) {
        // Skip corrupt/unreadable presets rather than failing startup.
        continue;
      }
    }
    return res;
  }

  // savePreset writes (or overwrites) a preset's preset.json to its
  // directory, returning the preset with sourceDir populated.
  static Future<ThemePreset> savePreset(ThemePreset preset) async {
    var dir = await presetDir(preset.id);
    await Directory(dir).create(recursive: true);
    var jsonFile = File(path.join(dir, "preset.json"));
    await jsonFile.writeAsString(jsonEncode(preset.toJson()));
    return preset.copyWith(sourceDir: dir);
  }

  // saveAreaImage copies an image file (e.g. picked via FilePicker) into a
  // preset's images/ subfolder, returning the path to store in an
  // AreaStyle.imagePath/borderImagePath (relative to the preset's
  // directory). `suffix` distinguishes multiple images for the same area
  // (e.g. a background image vs. a border image).
  static Future<String> saveAreaImage(
      String presetId, ThemeArea area, String sourceFilePath,
      {String suffix = "bg"}) async {
    var dir = await presetDir(presetId);
    var imagesDir = path.join(dir, "images");
    await Directory(imagesDir).create(recursive: true);
    var ext = path.extension(sourceFilePath);
    var relPath = "images/${area.name}_$suffix$ext";
    await File(sourceFilePath).copy(path.join(dir, relPath));
    return relPath;
  }

  static Future<void> deletePreset(String id) async {
    var dir = Directory(await presetDir(id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // exportPresetZip zips a preset's whole directory (preset.json + any
  // images/) into an in-memory byte array, ready to be written wherever the
  // caller's file-save dialog points.
  static Future<Uint8List> exportPresetZip(String id) async {
    var dir = Directory(await presetDir(id));
    if (!await dir.exists()) {
      throw Exception("Preset $id not found");
    }

    var archive = Archive();
    await for (var entry in dir.list(recursive: true)) {
      if (entry is! File) continue;
      var relPath = path.relative(entry.path, from: dir.path);
      var bytes = await entry.readAsBytes();
      archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
    }

    var encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  // importPresetZip extracts a previously-exported preset zip into a new
  // preset directory (a fresh id is assigned so importing never collides
  // with an existing preset), parses its preset.json and returns the
  // resulting ThemePreset.
  static Future<ThemePreset> importPresetZip(Uint8List zipBytes) async {
    var archive = ZipDecoder().decodeBytes(zipBytes);
    var jsonEntry = archive.files
        .where((f) => f.name == "preset.json" || f.name.endsWith("/preset.json"))
        .firstOrNull;
    if (jsonEntry == null) {
      throw Exception("preset.json not found in imported file");
    }

    var newId = "imported-${DateTime.now().millisecondsSinceEpoch}";
    var dir = await presetDir(newId);
    await Directory(dir).create(recursive: true);

    for (var f in archive.files) {
      if (!f.isFile) continue;
      var outPath = path.join(dir, f.name);
      await Directory(path.dirname(outPath)).create(recursive: true);
      await File(outPath).writeAsBytes(f.content as List<int>);
    }

    var j = jsonDecode(utf8.decode(jsonEntry.content as List<int>));
    var preset = ThemePreset.fromJson(j)
        .copyWith(id: newId, sourceDir: dir);
    // Re-save preset.json under the new id (the imported preset.json still
    // has the old id from the exporting machine).
    return savePreset(preset);
  }
}

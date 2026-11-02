import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_asset.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/human_assets.dart'
    show inTestsUnaimed;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// character_library.dart keeps the library's characters: one file each in
// Characters, beside Pictures and Vectors, named by the character's id so a
// rename never moves it. See character_asset.dart.

/// canvasCharacterFolder is where the library's characters are kept.
const canvasCharacterFolder = "Characters";

class CharacterLibrary {
  /// changed counts the library's changes, for lists of it to follow.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static Future<String> dir() async {
    var d = path.join(await CanvasStorage.libraryDir(), canvasCharacterFolder);
    await Directory(d).create(recursive: true);
    return d;
  }

  static Future<String> _file(String id) async =>
      path.join(await dir(), "$id.json");

  /// newId is an id no character has: random, so two made on two machines
  /// do not meet.
  static String newId() {
    var r = math.Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// list is every character in the library, the last changed first.
  static Future<List<CharacterAsset>> list() async {
    var out = <CharacterAsset>[];
    // A test that has not said where its library is never sees this
    // machine's.
    if (inTestsUnaimed) return out;
    try {
      await for (var f in Directory(await dir()).list()) {
        if (f is! File || !f.path.endsWith(".json")) continue;
        try {
          if (CharacterAsset.fromJson(jsonDecode(await f.readAsString()))
              case var a?) {
            out.add(a);
          }
        } catch (_) {
          // A file half written, or not ours: passed over.
        }
      }
    } on FileSystemException {
      return out;
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  static Future<CharacterAsset?> load(String id) async {
    if (inTestsUnaimed) return null;
    try {
      var f = File(await _file(id));
      if (!await f.exists()) return null;
      return CharacterAsset.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// save writes [asset], over what it was: written to the side and moved
  /// into place, so a save cut short leaves the last one whole.
  static Future<bool> save(CharacterAsset asset) async {
    if (inTestsUnaimed) return false;
    try {
      var target = await _file(asset.id);
      var temp = File("$target.tmp");
      await temp.writeAsString(jsonEncode(asset.toJson()), flush: true);
      await temp.rename(target);
      changed.value++;
      return true;
    } catch (exception) {
      debugPrint("Unable to save the character ${asset.name}: $exception");
      return false;
    }
  }

  static Future<void> delete(String id) async {
    if (inTestsUnaimed) return;
    try {
      var f = File(await _file(id));
      if (await f.exists()) await f.delete();
      changed.value++;
    } catch (_) {}
  }

  /// assetIds and mediaIds are the pictures, and the sounds and models,
  /// the library's characters use: kept by a tidy of the stores, though no
  /// canvas has them.
  static Future<Set<String>> assetIds() async => {
        for (var a in await list())
          ...a.element(const ElementBase(id: "_")).assetIds,
      };

  static Future<Set<String>> mediaIds() async => {
        for (var a in await list())
          ...a.element(const ElementBase(id: "_")).mediaIds,
      };
}

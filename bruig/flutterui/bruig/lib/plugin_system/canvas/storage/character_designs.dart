import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// character_designs.dart keeps the library's new 3D characters, made in the
// Character Studio: one file each in Characters 3D, named by the
// character's id so a rename never moves it. See character_design.dart.

/// canvasCharacter3dFolder is where they are kept.
const canvasCharacter3dFolder = "Characters 3D";

class CharacterDesigns {
  /// changed counts the library's changes, for lists of it to follow.
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static Future<String> dir() async {
    final d =
        path.join(await CanvasStorage.libraryDir(), canvasCharacter3dFolder);
    await Directory(d).create(recursive: true);
    return d;
  }

  static Future<String> _file(String id) async =>
      path.join(await dir(), "$id.json");

  /// newId is an id no character has: random, so two made on two machines
  /// do not meet.
  static String newId() {
    final r = math.Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// list is every character, the last changed first.
  static Future<List<CharacterDesign>> list() async {
    final out = <CharacterDesign>[];
    // A test that has not said where its library is never sees this
    // machine's.
    if (inTestsUnaimed) return out;
    try {
      await for (final f in Directory(await dir()).list()) {
        if (f is! File || !f.path.endsWith(".json")) continue;
        try {
          if (CharacterDesign.fromJson(jsonDecode(await f.readAsString()))
              case final d?) {
            out.add(d);
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

  static Future<CharacterDesign?> load(String id) async {
    if (inTestsUnaimed) return null;
    try {
      final f = File(await _file(id));
      if (!await f.exists()) return null;
      return CharacterDesign.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  /// save writes [d], over what it was: written to the side and moved into
  /// place, so a save cut short leaves the last one whole.
  static Future<bool> save(CharacterDesign d) async {
    if (inTestsUnaimed) return false;
    try {
      final target = await _file(d.id);
      final temp = File("$target.tmp");
      await temp.writeAsString(jsonEncode(d.toJson()), flush: true);
      await temp.rename(target);
      changed.value++;
      return true;
    } catch (exception) {
      debugPrint("Unable to save the character ${d.name}: $exception");
      return false;
    }
  }

  static Future<void> delete(String id) async {
    if (inTestsUnaimed) return;
    try {
      final f = File(await _file(id));
      if (await f.exists()) await f.delete();
      final p = File(await pictureFile(id));
      if (await p.exists()) await p.delete();
      changed.value++;
    } catch (_) {}
  }

  /// pictureFile is where character [id]'s picture is kept: a PNG of it
  /// standing, drawn as the Studio is left, for the library's list.
  static Future<String> pictureFile(String id) async =>
      path.join(await dir(), "$id.png");

  /// picture is character [id]'s picture, or null where it has none.
  static Future<Uint8List?> picture(String id) async {
    if (inTestsUnaimed) return null;
    try {
      final f = File(await pictureFile(id));
      return await f.exists() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  /// savePicture keeps [png] as character [id]'s picture.
  static Future<void> savePicture(String id, Uint8List png) async {
    if (inTestsUnaimed) return;
    try {
      final target = await pictureFile(id);
      final temp = File("$target.tmp");
      await temp.writeAsBytes(png, flush: true);
      await temp.rename(target);
    } catch (exception) {
      debugPrint("Unable to save the character's picture: $exception");
    }
  }

  /// pictureIds and vectorIds are the pictures and vectors the characters'
  /// decals use: kept by a tidy of the stores, though no canvas has them.
  static Future<Set<String>> pictureIds() async =>
      {for (final d in await list()) ...d.pictureIds};
  static Future<Set<String>> vectorIds() async =>
      {for (final d in await list()) ...d.vectorIds};
}

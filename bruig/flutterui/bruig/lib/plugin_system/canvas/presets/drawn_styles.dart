import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/drawn_characters.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// drawn_styles.dart is the drawn characters' styles as the app has them (see
// model/drawn_characters.dart and assets/canvas/characters/SOURCES.md), and
// a character kept in the library as a drawing, credited to its artist.

const drawnStylesAsset = "assets/canvas/characters/drawn_styles.json.gz";

class DrawnStyles {
  DrawnStyles._();

  static Map<String, DrawnStyle> _styles = const {};
  static Future<void>? _loading;

  static Map<String, DrawnStyle> get all => _styles;

  static Future<Map<String, DrawnStyle>> load() async {
    await (_loading ??= _read());
    return _styles;
  }

  static Future<void> _read() async {
    try {
      var data = await rootBundle.load(drawnStylesAsset);
      _styles = readDrawnStyles(data.buffer.asUint8List());
    } catch (exception) {
      debugPrint("The drawn characters did not load: $exception");
      // Asked again next time, not left empty for the run.
      _loading = null;
    }
  }

  /// forgetForTest forgets the styles and any read of them under way, so
  /// the next test file reads afresh: a read begun under one file's clock
  /// never finishes under the next's, and its load would wait for ever.
  @visibleForTesting
  static void forgetForTest() {
    _styles = const {};
    _loading = null;
  }
}

/// keepDrawnCharacter keeps [character] in the library as a drawing called
/// [name], credited to its style's artist: its id, or null.
Future<String?> keepDrawnCharacter(
    DrawnStyle style, DrawnCharacter character, String name) async {
  var id =
      await CanvasMedia.saveVector(utf8.encode(drawnSvg(style, character)));
  if (id == null) return null;
  await CanvasLibrary.addVector(id, name.trim().isEmpty ? style.title : name);
  await CanvasLibrary.credit(id,
      author: style.creator,
      license: style.licence,
      origin: style.source,
      from: "${style.title} (DiceBear)");
  return id;
}

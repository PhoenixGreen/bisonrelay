import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';

// picture_import.dart is the one way a picture or a drawing comes into the
// library, whichever road brought it: a file chosen from disk, a stock
// result, or a drawing a script supplies. Each road asks its own questions
// first (a large file's size controls, stock's fetching rules) and reports
// in its own way; from the bytes on, they are the same, so a file is judged
// alike whoever brought it -- but for a drawing nobody has looked at before
// it arrives (a script's, a stock result), which is held to a stricter rule.

/// PictureImport is what bringing a picture or a drawing in came to: its
/// [asset] in the library, or the [problem] that kept it out, worded for
/// the person who chose it.
typedef PictureImport = ({LibraryAsset? asset, String? problem});

/// importPicture keeps [bytes] in the stores and lists them in the library
/// as [name]. An SVG, known by what it holds and not by its name, is kept
/// as a drawing; anything else as a picture, if it is one the canvas can
/// decode. [author], [license], [origin] and [from] credit it, as for a
/// stock result. [drawingOnly] refuses anything but a drawing, for a road
/// whose caller can place nothing else; [strict] holds a drawing to the
/// rule for drawings nobody has looked at, a script's or a stock library's
/// (see [_holdsItself]), and does nothing to a picture. Shows nothing: the
/// caller says the problem in its own way.
Future<PictureImport> importPicture(
  Uint8List bytes, {
  required String name,
  String author = "",
  String license = "",
  String origin = "",
  String from = "",
  bool drawingOnly = false,
  bool strict = false,
}) async {
  PictureImport refused(String why) => (asset: null, problem: why);
  var drawing = looksLikeSvg(bytes);
  var listed =
      name.trim().isEmpty ? (drawing ? "Drawing" : "Picture") : name.trim();

  if (!drawing) {
    if (drawingOnly) return refused(_notADrawing(name));
    if (bytes.length > maxAssetBytes) {
      return refused(tooLargeToKeep(name, drawing: false));
    }
    // Decodable is what makes it a picture: the store keeps any bytes, and
    // what it cannot draw would sit in the library as an empty tile.
    var size = await _measure(bytes);
    if (size == null) return refused(_notAPicture(name));
    var id = await CanvasAssets.save(bytes);
    if (id == null) return refused(_notStored(name));
    return _listed(LibraryAsset(
        id: id,
        kind: AssetKind.picture,
        name: listed,
        added: DateTime.now(),
        width: size.$1,
        height: size.$2,
        author: author,
        license: license,
        origin: origin,
        from: from));
  }

  if (bytes.length > MediaKind.vector.maxBytes) {
    return refused(tooLargeToKeep(name, drawing: true));
  }
  if (strict && !_holdsItself(bytes)) return refused(_reachesOutside(name));
  var id = await CanvasMedia.saveVector(bytes);
  if (id == null) return refused(_notStored(name));
  return _listed(LibraryAsset(
      id: id,
      kind: AssetKind.vector,
      name: listed,
      added: DateTime.now(),
      author: author,
      license: license,
      origin: origin,
      from: from));
}

/// _listed puts [asset] in the library and answers with it as listed: one
/// added again from disk keeps the credit it already had.
Future<PictureImport> _listed(LibraryAsset asset) async {
  await CanvasLibrary.add(asset);
  return (asset: await CanvasLibrary.byId(asset.id) ?? asset, problem: null);
}

/// _measure is a picture's width and height, read from its header, or null
/// when the engine cannot decode it. Not decoded whole: a large photograph
/// would be read into memory only to count it.
Future<(int, int)?> _measure(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  try {
    var buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    var descriptor = await ui.ImageDescriptor.encoded(buffer);
    var size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size.$1 > 0 && size.$2 > 0 ? size : null;
  } catch (_) {
    return null;
  }
}

/// _holdsItself is whether drawing [bytes] keep to the rule for drawings
/// nobody has looked at: no script, no foreignObject (a web page set inside
/// the drawing), and no href or src naming another site or a file on the
/// computer. The canvas runs no scripts, draws no embedded page and fetches
/// no outside file, so a drawing leaning on them arrives with parts missing,
/// and an outside link would be followed by whoever opens it elsewhere.
/// A script's drawing and a stock library's are held to it, as nobody has
/// looked at one before it arrives; a drawing a person chose from disk is
/// seen the moment it is placed.
bool _holdsItself(Uint8List bytes) {
  var lower = String.fromCharCodes(bytes).toLowerCase();
  return !(lower.contains("<script") ||
      lower.contains("<foreignobject") ||
      RegExp(r"""(href|src)\s*=\s*["']\s*(https?:|file:|//)""")
          .hasMatch(lower));
}

/// _called is how a message names what was brought in: by [name], or as
/// "That" where it came with none.
String _called(String name) => name.trim().isEmpty ? "That" : name.trim();

/// tooLargeToKeep is the words for [name] refused for its size, with the
/// limit that applies: a drawing's, or a picture's. For a road that can
/// tell before the bytes are read, as a file on disk can.
String tooLargeToKeep(String name, {required bool drawing}) {
  var limit = (drawing ? MediaKind.vector.maxBytes : maxAssetBytes) >> 20;
  return "${_called(name)} is too large for a canvas: "
      "a ${drawing ? "drawing" : "picture"} may be up to $limit MB.";
}

String _notAPicture(String name) =>
    "${_called(name)} is not a picture or drawing the canvas can keep.";

String _notADrawing(String name) =>
    "${_called(name)} is not a drawing the canvas can keep.";

String _reachesOutside(String name) =>
    "${_called(name)} has a script, an embedded page or a link to an outside "
    "file: a drawing made for a canvas holds everything itself.";

String _notStored(String name) =>
    "${_called(name)} could not be kept in the library.";

import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_media.dart keeps the sounds and videos canvases play, beside the
// pictures.
//
// The same arrangement as the picture store (canvas_assets.dart): one copy
// of each file, named by a hash of its bytes, swept of anything no saved
// canvas names. Two differences, both because these files are big: a file is
// hashed and copied as a stream, never read into memory whole; and the
// player (SoLoud, ffmpeg) is handed a path rather than bytes, so it reads
// only what it needs.

/// isPlaylist is whether [bytes] are a playlist or a list of other files
/// (m3u, ffconcat, xml, ini-like) rather than a sound or a film: text that
/// would have ffmpeg read files the sender names. Media is never text, but
/// AMR, which begins "#!AMR", is let through.
bool isPlaylist(List<int> bytes) {
  var i = 0;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB) i = 3;
  while (i < bytes.length && " \t\r\n".codeUnits.contains(bytes[i])) {
    i++;
  }
  if (i >= bytes.length) return true;
  var head = String.fromCharCodes(bytes.skip(i).take(8));
  if (head.startsWith("#!AMR")) return false;
  return "#<[".contains(head[0]) || head.startsWith("ffconcat");
}

/// MediaKind is which store folder a file belongs in.
enum MediaKind {
  audio(canvasAudioFolder, 512 * 1024 * 1024),
  video(canvasVideoFolder, 4 * 1024 * 1024 * 1024),

  /// vector is the drawings: .svg files, bounded as pictures are.
  vector(canvasVectorFolder, 20 * 1024 * 1024),

  /// model is the 3D models the old characters were made of: .glb and
  /// .gltf files. Nothing is added to it now, and nothing in it is listed or
  /// swept away -- what somebody imported stays theirs, where it was.
  model(canvasModelFolder, 256 * 1024 * 1024);

  final String folder;

  /// maxBytes bounds one file: generous enough for a real recording, bounded
  /// because a canvas is sent to people.
  final int maxBytes;
  const MediaKind(this.folder, this.maxBytes);
}

final _idPattern = RegExp(r"^[a-f0-9]{16}\.[a-z0-9]{2,5}$");

/// playableAudio is what the audio engine can open as it is. Anything else is
/// converted on the way in -- see media_import.dart.
const playableAudio = {".mp3", ".wav", ".ogg", ".opus", ".flac"};

/// isMidiId is whether stored sound [id] is a MIDI file: notes for an
/// instrument to play, not a sound the engine can.
bool isMidiId(String id) => id.endsWith(".mid");

class CanvasMedia {
  /// _dir is the folder for [kind], created only when something is about to
  /// be written to it.
  static Future<String> _dir(MediaKind kind, {bool create = false}) async {
    var dir = path.join(await CanvasStorage.libraryDir(), kind.folder);
    if (create) await Directory(dir).create(recursive: true);
    return dir;
  }

  /// isId is whether [id] could name a stored file. Every id read from a
  /// document goes through this before it becomes part of a path, so a
  /// document naming "../../something" names nothing.
  static bool isId(String id) => _idPattern.hasMatch(id);

  /// pathFor is where [id] is kept, whether or not it is there yet.
  static Future<String?> pathFor(MediaKind kind, String id,
      {bool create = false}) async {
    if (!isId(id)) return null;
    return path.join(await _dir(kind, create: create), id);
  }

  /// existingPath is [pathFor] for a file that is actually there.
  static Future<String?> existingPath(MediaKind kind, String id) async {
    var file = await pathFor(kind, id);
    if (file != null && await File(file).exists()) return file;
    return null;
  }

  /// saveFile copies [sourcePath] into the store and returns its id, or null
  /// when it could not be stored: missing, empty, too big, or of a kind the
  /// store does not know.
  static Future<String?> saveFile(MediaKind kind, String sourcePath) async {
    try {
      var source = File(sourcePath);
      var length = await source.length();
      if (length <= 0 || length > kind.maxBytes) return null;
      var ext = await sniffExtension(sourcePath);
      if (ext.isEmpty) return null;

      var digest = await sha256.bind(source.openRead()).first;
      var id = "${digest.toString().substring(0, 16)}$ext";
      var target = await pathFor(kind, id, create: true);
      if (target == null) return null;
      // Already stored, by this canvas or another.
      if (await File(target).exists()) return id;

      // Copied under a temporary name and moved into place, so a copy that
      // fails halfway never leaves a truncated file under a real id.
      var partial = "$target.part";
      await source.copy(partial);
      await File(partial).rename(target);
      return id;
    } catch (exception) {
      debugPrint("Unable to store $sourcePath: $exception");
      return null;
    }
  }

  /// saveBytes stores a file that arrived as bytes, under the id it arrived
  /// with -- for unpacking a bundle, whose ids are the sender's hashes.
  static Future<bool> saveBytes(
      MediaKind kind, String id, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > kind.maxBytes) return false;
    // Named by its digest, so it must be what the name says -- see saveAs.
    if (!await idMatches(id, bytes)) return false;
    if ((kind == MediaKind.audio || kind == MediaKind.video) &&
        isPlaylist(bytes)) {
      return false;
    }
    var target = await pathFor(kind, id, create: true);
    if (target == null) return false;
    try {
      var file = File(target);
      if (await file.exists()) return true;
      await writeWhole(target, bytes);
      return true;
    } catch (exception) {
      debugPrint("Unable to store $id: $exception");
      return false;
    }
  }

  /// saveVector stores a drawing's bytes and returns its id -- the file's own
  /// digest and ".svg", so the same drawing added twice is one file -- or
  /// null where it could not be stored.
  static Future<String?> saveVector(List<int> bytes) async {
    var id = "${sha256.convert(bytes).toString().substring(0, 16)}.svg";
    return await saveBytes(MediaKind.vector, id, bytes) ? id : null;
  }

  /// load reads a stored file whole, for packing into a bundle.
  static Future<List<int>?> load(MediaKind kind, String id) async {
    var file = await existingPath(kind, id);
    if (file == null) return null;
    try {
      return await File(file).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// kindOf is which store an id belongs in, from its extension.
  static MediaKind kindOf(String id) => path.extension(id) == ".svg"
      ? MediaKind.vector
      : const {".glb", ".gltf", ".vrm"}.contains(path.extension(id))
          ? MediaKind.model
          : _videoExtensions.contains(path.extension(id))
          ? MediaKind.video
          : MediaKind.audio;

  /// stored is every file in [kind]'s store.
  static Future<List<String>> stored(MediaKind kind) async {
    try {
      var dir = Directory(await _dir(kind));
      return [
        await for (var entry in dir.list(followLinks: false))
          if (entry is File && isId(path.basename(entry.path)))
            path.basename(entry.path),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// sweep deletes every file in [kind]'s store that [liveIds] does not name,
  /// except those newer than [sweepGrace].
  static Future<int> sweep(MediaKind kind, Set<String> liveIds) async {
    var removed = 0;
    try {
      var dir = Directory(await _dir(kind));
      await for (var entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        var id = path.basename(entry.path);
        if (liveIds.contains(id)) continue;
        if (DateTime.now().difference(await entry.lastModified()) <
            sweepGrace) {
          continue;
        }
        try {
          await entry.delete();
          removed++;
        } catch (_) {
          // Being unable to delete one is not a reason to stop.
        }
      }
    } catch (_) {
      // No folder yet, which means nothing to sweep.
    }
    return removed;
  }

  /// sweepUnused sweeps the stores against every saved canvas, and against
  /// [open], the canvas being worked on, which may never have been saved:
  /// otherwise a sound added to an unnamed canvas would be deleted by the
  /// first save of any other.
  static Future<int> sweepUnused({Set<String> open = const {}}) async {
    try {
      var live = {...await CanvasStorage.liveMediaIds(), ...open};
      // A drawing can be named as a picture too -- a text element's icon
      // reads either store -- so the drawings keep whatever either names.
      var drawn = {...live, ...await CanvasStorage.liveAssetIds()};
      return await sweep(MediaKind.audio, live) +
          await sweep(MediaKind.video, live) +
          await sweep(MediaKind.vector, drawn);
    } catch (_) {
      return 0;
    }
  }

  /// sniffExtension is what a file is, from its first bytes -- never from its
  /// name, which is whatever somebody called it.
  static Future<String> sniffExtension(String filePath) async {
    RandomAccessFile? handle;
    try {
      handle = await File(filePath).open();
      return extensionOf(await handle.read(64));
    } catch (_) {
      return "";
    } finally {
      await handle?.close();
    }
  }

  /// extensionOf is [sniffExtension] for bytes already read.
  @visibleForTesting
  static String extensionOf(List<int> b) {
    bool at(int offset, String text) {
      if (b.length < offset + text.length) return false;
      for (var i = 0; i < text.length; i++) {
        if (b[offset + i] != text.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (at(0, "RIFF") && at(8, "WAVE")) return ".wav";
    // A Standard MIDI File: notes, not a sound -- kept with the sounds, and
    // played by an instrument.
    if (at(0, "MThd")) return ".mid";
    if (at(0, "RIFF") && at(8, "AVI ")) return ".avi";
    if (at(0, "fLaC")) return ".flac";
    if (at(0, "OggS")) {
      // Opus says so in its first page; anything else in Ogg is Vorbis as far
      // as a player is concerned.
      return at(28, "OpusHead") ? ".opus" : ".ogg";
    }
    if (at(0, "glTF")) return ".glb";
    // A glTF written as text: a JSON object whose first key is the asset or
    // the scene graph. Anything else that starts with a brace is not taken.
    if (b.isNotEmpty) {
      var text = String.fromCharCodes(b.take(64)).trimLeft();
      if (text.startsWith("{") &&
          (text.contains('"asset"') ||
              text.contains('"accessors"') ||
              text.contains('"buffers"') ||
              text.contains('"scene'))) {
        return ".gltf";
      }
    }
    if (at(0, "ID3")) return ".mp3";
    // An MPEG audio frame with no tag in front of it: eleven set bits.
    if (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return ".mp3";
    if (at(0, "FORM") && (at(8, "AIFF") || at(8, "AIFC"))) return ".aiff";
    if (at(4, "ftyp")) {
      // The ISO family, which is both a song and a film. The brand says which
      // it was made as; a video without its picture is still a video file.
      if (at(8, "M4A ") || at(8, "M4B ") || at(8, "M4P ")) return ".m4a";
      if (at(8, "qt  ")) return ".mov";
      return ".mp4";
    }
    if (b.length >= 4 &&
        b[0] == 0x1A &&
        b[1] == 0x45 &&
        b[2] == 0xDF &&
        b[3] == 0xA3) {
      return ".webm";
    }
    return "";
  }
}

const _videoExtensions = {".mp4", ".mov", ".webm", ".avi"};

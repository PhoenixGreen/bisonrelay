import 'dart:io';

import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// canvas_media.dart keeps the sounds and videos canvases play, beside the
// pictures.
//
// The same arrangement as the picture store -- see canvas_assets.dart: one
// copy of each file, named by a hash of its bytes, in a folder the library
// listing leaves out, swept of anything no saved canvas names. Two
// differences, both because these files are big:
//
// - A file is hashed and copied as a stream, never read into memory whole.
//   A forty-minute recording is hundreds of megabytes, and the picture
//   store's "read the bytes, hash the bytes" would hold all of them at once.
// - The player is handed a path rather than bytes. SoLoud and ffmpeg both
//   read files, and giving them one is what lets them read only what they
//   need.

/// MediaKind is which of the two folders a file belongs in.
enum MediaKind {
  audio(canvasAudioFolder, 512 * 1024 * 1024),
  video(canvasVideoFolder, 4 * 1024 * 1024 * 1024);

  final String folder;

  /// maxBytes bounds one file. Generous, because a store that refuses a
  /// real recording is a store that does not work; bounded, because a
  /// canvas is sent to people and somebody will try to add a film.
  final int maxBytes;
  const MediaKind(this.folder, this.maxBytes);
}

final _idPattern = RegExp(r"^[a-f0-9]{16}\.[a-z0-9]{2,5}$");

/// playableAudio is what the audio engine can open as it is. Anything else is
/// converted on the way in -- see media_import.dart.
const playableAudio = {".mp3", ".wav", ".ogg", ".opus", ".flac"};

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
    if (file == null || !await File(file).exists()) return null;
    return file;
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
      // fails halfway does not leave a truncated file under a real id --
      // which would be a sound that plays its first half forever after.
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
    var target = await pathFor(kind, id, create: true);
    if (target == null) return false;
    try {
      var file = File(target);
      if (await file.exists()) return true;
      await File("$target.part").writeAsBytes(bytes, flush: true);
      await File("$target.part").rename(target);
      return true;
    } catch (exception) {
      debugPrint("Unable to store $id: $exception");
      return false;
    }
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
  static MediaKind kindOf(String id) =>
      _videoExtensions.contains(path.extension(id))
          ? MediaKind.video
          : MediaKind.audio;

  /// stored is every file in [kind]'s store.
  static Future<List<String>> stored(MediaKind kind) async {
    try {
      var dir = Directory(await _dir(kind));
      return [
        await for (var entry in dir.list(followLinks: false))
          if (entry is File && _idPattern.hasMatch(path.basename(entry.path)))
            path.basename(entry.path),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// sweep deletes every file in [kind]'s store that [liveIds] does not name.
  static Future<int> sweep(MediaKind kind, Set<String> liveIds) async {
    var removed = 0;
    try {
      var dir = Directory(await _dir(kind));
      await for (var entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        var id = path.basename(entry.path);
        if (liveIds.contains(id)) continue;
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

  /// sweepUnused sweeps both stores against every saved canvas, and against
  /// [open] -- the canvas being worked on, which may never have been saved.
  ///
  /// Without it, a sound added to a canvas nobody has named yet is a file no
  /// saved canvas mentions, and the first save of any other canvas deleted it
  /// out from under the one it was added to.
  static Future<int> sweepUnused({Set<String> open = const {}}) async {
    try {
      var live = {...await CanvasStorage.liveMediaIds(), ...open};
      return await sweep(MediaKind.audio, live) +
          await sweep(MediaKind.video, live);
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
    if (at(0, "RIFF") && at(8, "AVI ")) return ".avi";
    if (at(0, "fLaC")) return ".flac";
    if (at(0, "OggS")) {
      // Opus says so in its first page; anything else in Ogg is Vorbis as far
      // as a player is concerned.
      return at(28, "OpusHead") ? ".opus" : ".ogg";
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

import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// media_picking.dart is adding a sound to a canvas: choosing the file,
// making it something the player can open, storing it and measuring it.
//
// The player opens MP3, WAV, Ogg (Vorbis and Opus) and FLAC. The two formats
// most people actually have -- AAC in an .m4a from a phone, and AIFF from a
// Mac -- are neither, so they are converted on the way in when ffmpeg is on
// the machine. Converted to FLAC, which loses nothing and which every ffmpeg
// can write whatever it was built with. Without ffmpeg they are refused with
// a sentence saying what would take them, rather than stored and silent.

const _audioPickable = [
  "mp3", "wav", "ogg", "opus", "flac", "m4a", "aac", "aiff", "aif", "mp4" //
];

/// pickCanvasAudio asks for a sound file and stores it, returning it as a
/// playlist entry ready to add -- or null when nothing was added.
Future<MediaSource?> pickCanvasAudio(
    BuildContext context, CanvasController controller) async {
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _audioPickable,
    withData: false,
  );
  var chosen = picked?.files.singleOrNull?.path?.trim();
  if (chosen == null || chosen.isEmpty) return null;
  if (!context.mounted) return null;
  return addCanvasAudio(context, controller, chosen);
}

/// addCanvasAudio stores the sound at [file]. Its own function so a file
/// dropped on the canvas can take the same road as one chosen.
Future<MediaSource?> addCanvasAudio(
    BuildContext context, CanvasController controller, String file) async {
  var name = path.basenameWithoutExtension(file);
  void report(String message) {
    if (context.mounted) SnackBarModel.of(context).error(message);
  }

  var kind = await CanvasMedia.sniffExtension(file);
  if (kind.isEmpty) {
    report("$name is not a sound file this canvas can read.");
    return null;
  }

  var source = file;
  Directory? scratch;
  try {
    if (!playableAudio.contains(kind)) {
      var ffmpeg = await ffmpegPath();
      if (ffmpeg == null) {
        report("$name is ${kind.substring(1).toUpperCase()}, which needs "
            "ffmpeg to be converted. Install ffmpeg, or use an MP3, WAV, "
            "Ogg or FLAC file.");
        return null;
      }
      scratch = await Directory.systemTemp.createTemp("canvas-audio");
      source = path.join(scratch.path, "$name.flac");
      var run = await Process.run(
          ffmpeg, ["-y", "-i", file, "-vn", "-c:a", "flac", source]);
      if (run.exitCode != 0 || !await File(source).exists()) {
        report("ffmpeg could not convert $name.");
        return null;
      }
    }

    var id = await CanvasMedia.saveFile(MediaKind.audio, source);
    if (id == null) {
      report("$name could not be added. It may be too large.");
      return null;
    }
    var length = await controller.audio.measure(id) ?? 0;
    return MediaSource(assetId: id, name: name, length: length);
  } catch (exception) {
    report("Unable to add $name: $exception");
    return null;
  } finally {
    try {
      await scratch?.delete(recursive: true);
    } catch (_) {}
  }
}

import 'dart:io';

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';

// The settings themselves are the document's; see audio_settings.dart.
export 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show AudioFormat, AudioOptions, audioBitrates, audioRates, audioDepths;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// audio_export.dart is a canvas's sound on its own: its timeline mixed, as a
// video's soundtrack is, and written as a sound file -- and the settings any
// export with sound in it takes for how that sound is written.

/// AudioWriting is how ffmpeg is told to write a sound in [AudioOptions].
extension AudioWriting on AudioOptions {
  /// encodeArgs is how ffmpeg writes a sound file in [format], of
  /// [channels] -- more than two for surround, in a format that carries it.
  List<String> encodeArgs({int channels = 2}) => [
        "-ar", "${format.fixedRate ?? sampleRate}", //
        ...switch (format) {
          AudioFormat.wav => [
              "-c:a",
              bitDepth == 24 ? "pcm_s24le" : "pcm_s16le",
            ],
          AudioFormat.flac => [
              "-c:a", "flac", //
              "-sample_fmt", bitDepth == 24 ? "s32" : "s16",
              if (bitDepth == 24) ...["-bits_per_raw_sample", "24"],
            ],
          AudioFormat.mp3 => ["-c:a", "libmp3lame", "-b:a", "${kbps}k"],
          AudioFormat.aac => [
              "-c:a", "aac", "-b:a", "${kbps}k", //
              "-movflags", "+faststart",
            ],
          AudioFormat.opus => [
              "-c:a", "libopus", "-b:a", "${kbps}k", //
              // Opus's own surround mapping: without it, more than two
              // channels are refused.
              if (channels > 2) ...["-mapping_family", "1"],
            ],
        },
      ];

  /// videoArgs is how a video's sound is written: AAC in an MP4, Opus in a
  /// WebM -- what each container plays everywhere -- at this bitrate and
  /// rate.
  List<String> videoArgs({required bool webm, int channels = 2}) => webm
      ? [
          "-c:a", "libopus", "-b:a", "${kbps}k", "-ar", "48000", //
          if (channels > 2) ...["-mapping_family", "1"],
        ]
      : ["-c:a", "aac", "-b:a", "${kbps}k", "-ar", "$sampleRate"];

}

/// estimateAudioBytes is about how large [document]'s sound is written with
/// [options].
int estimateAudioBytes(CanvasDocument document, AudioOptions options) {
  var seconds =
      document.playFrames / (document.frameRate <= 0 ? 1 : document.frameRate);
  var rate = options.format.fixedRate ?? options.sampleRate;
  var speakers = document.audio.speakers;
  var channels = options.format.carriesSurround ? speakers.channels : 2;
  return switch (options.format) {
    AudioFormat.wav =>
      (seconds * rate * channels * options.bitDepth / 8).round(),
    AudioFormat.flac =>
      (seconds * rate * channels * options.bitDepth / 8 * 0.55).round(),
    _ => (seconds * options.kbps * 1000 / 8).round(),
  };
}

/// renderAudio is [document]'s timeline sound, mixed, as a file in
/// [options]. Null where there is nothing to hear, or no ffmpeg.
Future<CanvasExport?> renderAudio(CanvasDocument document,
    {AudioOptions options = const AudioOptions(),
    Future<String?> Function(MediaKind kind, String id)? locate}) async {
  var ffmpeg = await ffmpegPath();
  if (ffmpeg == null) return null;
  var media = ExportMedia.of(document, locate: locate);
  if (media == null) return null;
  Directory? work;
  try {
    var sounds = await media.sounds();
    if (sounds.isEmpty) return null;
    var seconds = document.playFrames /
        (document.frameRate <= 0 ? 1 : document.frameRate);
    work = await Directory.systemTemp.createTemp("canvas-audio");
    var mixed = path.join(work.path, "mix.wav");
    if (!await renderMixWav(sounds, document.masterMix,
        seconds: seconds,
        ffmpeg: ffmpeg,
        out: mixed,
        returns: document.returns,
        speakers: document.audio.speakers,
        fold: !options.format.carriesSurround)) {
      return null;
    }
    var out = path.join(work.path, "sound${options.format.extension}");
    var run = await Process.run(ffmpeg, [
      "-hide_banner", "-loglevel", "error", "-y", //
      "-i", mixed,
      ...options.encodeArgs(
          channels: options.format.carriesSurround
              ? document.audio.speakers.channels
              : 2),
      out,
    ]);
    if (run.exitCode != 0 || !await File(out).exists()) {
      debugPrint("Unable to write the sound: ${run.stderr}");
      return null;
    }
    return CanvasExport(await File(out).readAsBytes(), options.format.mime,
        width: 0, height: 0);
  } catch (exception) {
    debugPrint("Unable to write the sound: $exception");
    return null;
  } finally {
    media.dispose();
    if (work != null) {
      await work.delete(recursive: true).catchError((_) => work!);
    }
  }
}

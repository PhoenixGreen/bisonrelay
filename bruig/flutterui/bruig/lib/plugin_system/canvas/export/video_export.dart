import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/audio_export.dart';
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/export/export_media.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/panel_video.dart';
import 'package:bruig/plugin_system/canvas/render/panel_reading.dart'
    show panelSteps;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// video_export.dart writes MP4 and WebM through the system's ffmpeg, and
// finds ffmpeg for the features that use it. [ffmpegPath] is asked when the
// publish sheet opens, so [ffmpegHelp] shows while choosing, not on Publish.

/// _found is whether ffmpeg is here, worked out once even when not: the
/// publish sheet asks every build. A new install needs an app restart.
String? _found;
bool _looked = false;

/// _looking is the look under way, so a second ask waits for it rather
/// than hearing "not installed" from a look not yet done.
Future<String?>? _looking;

/// _candidates are where ffmpeg tends to be off PATH: a macOS GUI app
/// lacks the shell's PATH, so `which` misses a Homebrew install.
const List<String> _candidates = [
  "/opt/homebrew/bin/ffmpeg",
  "/usr/local/bin/ffmpeg",
  "/usr/bin/ffmpeg",
  "/snap/bin/ffmpeg",
  r"C:\ffmpeg\bin\ffmpeg.exe",
];

/// ffmpegHelp is what to tell somebody without ffmpeg. Not bundled: libx264
/// is GPL and Bison Relay ISC, so shipping both would relicense the app.
const String ffmpegHelp =
    "Publishing a video or a sound needs ffmpeg, which is not installed. "
    "Install it with "
    "\"brew install ffmpeg\" on a Mac, \"apt install ffmpeg\" on Linux, or "
    "from ffmpeg.org on Windows — then restart. The GIF export needs nothing.";

/// ffmpegPath is where ffmpeg is, or null if it is not to be found.
Future<String?> ffmpegPath() async {
  if (_looked) return _found;
  var found = await (_looking ??= _findFfmpeg());
  _found = found;
  _looked = true;
  _looking = null;
  return found;
}

Future<String?> _findFfmpeg() async {
  // Phones do not let one app run another's binaries.
  if (Platform.isAndroid || Platform.isIOS) return null;

  try {
    var which = Platform.isWindows ? "where" : "which";
    var found = await Process.run(which, ["ffmpeg"]);
    if (found.exitCode == 0) {
      var first = (found.stdout as String).trim().split("\n").first.trim();
      if (first.isNotEmpty && await File(first).exists()) return first;
    }
  } catch (exception) {
    // No `which` at all: still try the list below.
    debugPrint("Unable to look for ffmpeg on the path: $exception");
  }

  for (var candidate in _candidates) {
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}

/// useFfmpegForTest fixes [ffmpegPath]'s answer: an argument-recording
/// script, or null for none. [forgetFfmpegForTest] puts it back.
@visibleForTesting
void useFfmpegForTest(String? path) {
  _looked = true;
  _found = path;
  _looking = null;
}

/// forgetFfmpegForTest clears the pinned answer, so the next look is a real
/// one. Every test that pins must end with this.
@visibleForTesting
void forgetFfmpegForTest() {
  _looked = false;
  _found = null;
  _looking = null;
}

/// VideoFormat is which of the two files to write: MP4 plays everywhere,
/// WebM is smaller but does not open in Photos on a Mac or an iPhone.
enum VideoFormat {
  mp4("MP4", "video/mp4", ".mp4", "libx264",
      "Plays everywhere, including Photos on a Mac or an iPhone."),
  webm(
      "WebM",
      "video/webm",
      ".webm",
      "libvpx-vp9",
      "Smaller at the same quality, and plays in browsers and most chat "
          "apps — but not in Photos on a Mac or an iPhone.");

  final String label;
  final String mime;
  final String extension;

  /// encoder is what ffmpeg is asked for by name.
  final String encoder;

  final String note;
  const VideoFormat(
      this.label, this.mime, this.extension, this.encoder, this.note);
}

/// VideoQuality is ffmpeg's constant-rate factor (lower: better, larger);
/// two numbers a label, as x264 (0..51) and VP9 (0..63) scale differently.
enum VideoQuality {
  high("Best", 18, 24),
  balanced("Balanced", 23, 31),
  small("Smallest", 28, 40);

  final String label;
  final int _h264;
  final int _vp9;
  const VideoQuality(this.label, this._h264, this._vp9);

  int crfFor(VideoFormat format) => format == VideoFormat.webm ? _vp9 : _h264;
}

/// renderVideo draws every frame and hands them to ffmpeg. Raw pixels go
/// down its standard input (see _renderPiped), as encoding each frame as a
/// PNG costs over ten times the drawing; if the pipe fails, the frames are
/// written as PNGs to a temporary directory instead. Null when there is no
/// ffmpeg, it fails, or the document has no frames; see [ffmpegHelp].
Future<CanvasExport?> renderVideo(
  CanvasDocument document, {
  double scale = 1,
  CanvasImageSource? images,
  VideoFormat format = VideoFormat.mp4,
  VideoQuality quality = VideoQuality.balanced,
  GifProgress? onProgress,

  /// sound is how its sound is written: see AudioOptions.videoArgs.
  AudioOptions sound = const AudioOptions(),

  /// viaFiles skips the pipe and writes every frame as a numbered PNG: the
  /// fallback, asked for directly by its test.
  bool viaFiles = false,

  /// panels reads a comic panel by panel at that pace, as Panel mode does
  /// (panel_video.dart), in place of playing its timeline. Ignored where
  /// there are no panels.
  PanelPace? panels,

  /// panelMusic lays the canvas's own sound under a panel video: from the
  /// start, round again until the reading ends, fading out with it. Not in
  /// time with the panels, which is why it is a choice; silent without.
  bool panelMusic = false,
}) async {
  var ffmpeg = await ffmpegPath();
  if (ffmpeg == null) return null;
  if (panels != null) {
    var steps = panelSteps(document);
    if (steps.any((s) => !s.whole)) {
      // A book of paper may run at a frame a second; a glide needs more.
      var rate = document.frameRate >= 12 ? document.frameRate : 24;
      var exported = await _renderPanels(document.copyWith(frameRate: rate),
          PanelTimeline(steps, rate, panels),
          ffmpeg: ffmpeg,
          scale: scale,
          images: images,
          format: format,
          quality: quality,
          onProgress: onProgress,
          viaFiles: viaFiles,
          music: panelMusic ? document : null,
          sound: sound);
      if (exported != null || viaFiles) return exported;
      return _renderPanels(document.copyWith(frameRate: rate),
          PanelTimeline(steps, rate, panels),
          ffmpeg: ffmpeg,
          scale: scale,
          images: images,
          format: format,
          quality: quality,
          onProgress: onProgress,
          viaFiles: true,
          music: panelMusic ? document : null,
          sound: sound);
    }
  }
  if (document.playFrames <= 0) return null;

  if (!viaFiles) {
    var piped = await _renderPiped(document,
        ffmpeg: ffmpeg,
        scale: scale,
        images: images,
        format: format,
        quality: quality,
        sound: sound,
        onProgress: onProgress);
    if (piped != null) return piped;
    debugPrint("Streaming the frames to ffmpeg did not work; writing them "
        "out as files instead.");
  }

  Directory? work;
  ExportBackdrop? backdrop;
  var media = ExportMedia.of(document, scale: scale);
  try {
    work = await Directory.systemTemp.createTemp("bruig-canvas-video");

    backdrop =
        await ExportBackdrop.prepare(document, scale: scale, images: images);

    var width = 0, height = 0;
    for (var i = 0; i < document.playFrames; i++) {
      ui.Image? image;
      try {
        image = await renderFrame(document,
            frame: i,
            scale: scale,
            images: images,
            backdrop: backdrop,
            videoShow: await media?.at(i));
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        width = image.width;
        height = image.height;
        await File(path.join(work.path, _numbered(i)))
            .writeAsBytes(png.buffer.asUint8List());
      } finally {
        image?.dispose();
      }
      onProgress?.call(i + 1, document.playFrames);
      // Yield so progress can be drawn (as in renderGif).
      await Future<void>.delayed(Duration.zero);
    }
    if (width == 0) return null;

    var out = path.join(work.path, "canvas${format.extension}");
    var soundArgs = await _soundArgs(media, format, ffmpeg, work.path, sound);
    var result = await Process.run(ffmpeg, [
      "-y",
      ..._input(document, work.path),
      ...soundArgs.inputs,
      ..._encoderArgs(document, format, quality),
      ...soundArgs.output,
      out,
    ]);

    if (result.exitCode != 0) {
      var why = "${result.stderr}";
      // A build without the encoder is something the reader can fix.
      if (why.contains("Unknown encoder")) {
        debugPrint("This ffmpeg has no ${format.encoder}: ${format.label} "
            "needs a build that includes it.");
      } else {
        debugPrint("ffmpeg could not write the video: $why");
      }
      return null;
    }
    var file = File(out);
    if (!await file.exists()) return null;

    return CanvasExport(await file.readAsBytes(), format.mime,
        width: _even(width), height: _even(height));
  } catch (exception) {
    debugPrint("Unable to render the canvas video: $exception");
    return null;
  } finally {
    backdrop?.dispose();
    media?.dispose();
    // A 200-frame 4K export is gigabytes of PNG: never leave it behind.
    try {
      await work?.delete(recursive: true);
    } catch (exception) {
      debugPrint("Unable to clear the video's working directory: $exception");
    }
  }
}

/// _renderPiped writes every frame's raw pixels to ffmpeg, draining both
/// its output pipes and flushing each frame; null on any failure, so the
/// caller falls back to files.
Future<CanvasExport?> _renderPiped(
  CanvasDocument document, {
  required String ffmpeg,
  required double scale,
  required CanvasImageSource? images,
  required VideoFormat format,
  required VideoQuality quality,
  required AudioOptions sound,
  GifProgress? onProgress,
}) async {
  ExportBackdrop? backdrop;
  Process? process;
  Directory? work;
  var media = ExportMedia.of(document, scale: scale);
  try {
    // Raw pixels carry no size: the first frame is drawn first, and kept.
    backdrop =
        await ExportBackdrop.prepare(document, scale: scale, images: images);
    var first = await renderFrame(document,
        frame: 0,
        scale: scale,
        images: images,
        backdrop: backdrop,
        videoShow: await media?.at(0));
    var width = first.width, height = first.height;

    work = await Directory.systemTemp.createTemp("bruig-canvas-video");
    var out = path.join(work.path, "canvas${format.extension}");
    var soundArgs = await _soundArgs(media, format, ffmpeg, work.path, sound);

    process = await Process.start(ffmpeg, [
      "-y",
      "-f",
      "rawvideo",
      "-pix_fmt",
      "rgba",
      "-s",
      "${width}x$height",
      "-framerate",
      "${document.frameRate}",
      "-i",
      "-",
      ...soundArgs.inputs,
      ..._encoderArgs(document, format, quality),
      ...soundArgs.output,
      out,
    ]);

    // Drained from the start: an unread stderr fills, ffmpeg blocks writing
    // to it and stops reading frames, and both sides deadlock.
    var errors = StringBuffer();
    var draining = [
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(errors.write),
      process.stdout.drain<void>(),
    ];

    Future<void> send(ui.Image image) async {
      try {
        var raw =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (raw == null) throw StateError("no pixels");
        process!.stdin.add(raw.buffer.asUint8List());
        // Flushed per frame for backpressure, or every frame queues.
        await process.stdin.flush();
      } finally {
        image.dispose();
      }
    }

    await send(first);
    onProgress?.call(1, document.playFrames);
    for (var i = 1; i < document.playFrames; i++) {
      await send(await renderFrame(document,
          frame: i,
          scale: scale,
          images: images,
          backdrop: backdrop,
          videoShow: await media?.at(i)));
      onProgress?.call(i + 1, document.playFrames);
      // Yield so progress can be drawn.
      await Future<void>.delayed(Duration.zero);
    }

    await process.stdin.close();
    var code = await process.exitCode;
    await Future.wait(draining);
    if (code != 0) {
      var why = errors.toString();
      if (why.contains("Unknown encoder")) {
        debugPrint("This ffmpeg has no ${format.encoder}: ${format.label} "
            "needs a build that includes it.");
        // Null like any failure, so renderVideo retries via files.
        return null;
      }
      debugPrint("ffmpeg could not write the video: $why");
      return null;
    }

    var file = File(out);
    if (!await file.exists()) return null;
    return CanvasExport(await file.readAsBytes(), format.mime,
        width: _even(width), height: _even(height));
  } catch (exception) {
    debugPrint("Unable to stream the canvas video: $exception");
    return null;
  } finally {
    backdrop?.dispose();
    media?.dispose();
    try {
      process?.kill();
    } catch (_) {
      // Already gone: the usual case.
    }
    try {
      await work?.delete(recursive: true);
    } catch (exception) {
      debugPrint("Unable to clear the video's working directory: $exception");
    }
  }
}

/// _renderPanels writes [timeline]'s frames (PanelFrames) to ffmpeg, through
/// the pipe or, [viaFiles], as numbered PNGs. A frame held still is the one
/// before it again, sent without drawing. Null on any failure.
Future<CanvasExport?> _renderPanels(
  CanvasDocument document,
  PanelTimeline timeline, {
  required String ffmpeg,
  required double scale,
  required CanvasImageSource? images,
  required VideoFormat format,
  required VideoQuality quality,
  GifProgress? onProgress,
  bool viaFiles = false,

  /// music is the canvas whose timeline sound goes under it, looped; null
  /// for none (see renderVideo's panelMusic).
  CanvasDocument? music,
  AudioOptions sound = const AudioOptions(),
}) async {
  var frames = PanelFrames(document, timeline, scale: scale, images: images);
  Directory? work;
  Process? process;
  var total = timeline.frames;
  var media = music == null ? null : ExportMedia.of(music, scale: scale);
  try {
    work = await Directory.systemTemp.createTemp("bruig-canvas-panels");
    var out = path.join(work.path, "canvas${format.extension}");
    var width = frames.width, height = frames.height;

    // The mix, round again for as long as the reading lasts, faded out at
    // its end; nothing where the canvas has nothing to hear.
    var mixed = await _soundArgs(media, format, ffmpeg, work.path, sound);
    var seconds = total / math.max(1, document.frameRate);
    var soundIn = mixed.inputs.isEmpty
        ? const <String>[]
        : ["-stream_loop", "-1", ...mixed.inputs];
    var soundOut = mixed.inputs.isEmpty
        ? const <String>[]
        : [
            ...mixed.output,
            "-af",
            "afade=t=out:st=${math.max(0.0, seconds - 2).toStringAsFixed(2)}:d=2",
          ];

    Future<Uint8List> draw(int i, ui.ImageByteFormat as) async {
      var image = await frames.frame(i);
      try {
        var bytes = await image.toByteData(format: as);
        if (bytes == null) throw StateError("no pixels");
        return bytes.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }

    int code;
    var errors = StringBuffer();
    Uint8List? last;
    if (!viaFiles) {
      process = await Process.start(ffmpeg, [
        "-y",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgba",
        "-s",
        "${width}x$height",
        "-framerate",
        "${document.frameRate}",
        "-i",
        "-",
        ...soundIn,
        ..._encoderArgs(document, format, quality),
        ...soundOut,
        out,
      ]);
      // Drained from the start, as in _renderPiped.
      var draining = [
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .forEach(errors.write),
        process.stdout.drain<void>(),
      ];
      for (var i = 0; i < total; i++) {
        if (last == null || !timeline.still(i)) {
          last = await draw(i, ui.ImageByteFormat.rawStraightRgba);
        }
        process.stdin.add(last);
        await process.stdin.flush();
        onProgress?.call(i + 1, total);
        await Future<void>.delayed(Duration.zero);
      }
      await process.stdin.close();
      code = await process.exitCode;
      await Future.wait(draining);
    } else {
      for (var i = 0; i < total; i++) {
        if (last == null || !timeline.still(i)) {
          last = await draw(i, ui.ImageByteFormat.png);
        }
        await File(path.join(work.path, _numbered(i))).writeAsBytes(last);
        onProgress?.call(i + 1, total);
        await Future<void>.delayed(Duration.zero);
      }
      var result = await Process.run(ffmpeg, [
        "-y",
        ..._input(document, work.path),
        ...soundIn,
        ..._encoderArgs(document, format, quality),
        ...soundOut,
        out,
      ]);
      code = result.exitCode;
      errors.write(result.stderr);
    }
    if (code != 0) {
      debugPrint("ffmpeg could not write the panel video: $errors");
      return null;
    }
    var file = File(out);
    if (!await file.exists()) return null;
    return CanvasExport(await file.readAsBytes(), format.mime,
        width: _even(width), height: _even(height));
  } catch (exception) {
    debugPrint("Unable to render the panel video: $exception");
    return null;
  } finally {
    frames.dispose();
    media?.dispose();
    try {
      process?.kill();
    } catch (_) {
      // Already gone: the usual case.
    }
    try {
      await work?.delete(recursive: true);
    } catch (exception) {
      debugPrint("Unable to clear the video's working directory: $exception");
    }
  }
}

/// _soundArgs is the timeline's sound as ffmpeg arguments: the mix rendered
/// to one WAV in [work] (see mix_render.dart), as an input after the
/// picture's, and how it is encoded. Empty when there is nothing to hear.
Future<({List<String> inputs, List<String> output})> _soundArgs(
    ExportMedia? media, VideoFormat format, String ffmpeg, String work,
    [AudioOptions sound = const AudioOptions()]) async {
  const none = (inputs: <String>[], output: <String>[]);
  var sounds = media == null ? const <ExportSound>[] : await media.sounds();
  if (sounds.isEmpty) return none;
  var document = media!.document;
  var mixed = path.join(work, "mix.wav");
  var ok = await renderMixWav(sounds, document.syncedMaster,
      seconds: document.playFrames /
          (document.frameRate <= 0 ? 1 : document.frameRate),
      ffmpeg: ffmpeg,
      out: mixed,
      returns: document.syncedReturns,
      scenes: sceneBuses(document),
      // An MP4's AAC and a WebM's Opus both carry surround.
      speakers: document.audio.speakers);
  if (!ok) return none;
  return (
    inputs: ["-i", mixed],
    output: [
      "-map", "0:v",
      "-map", "1:a",
      ...sound.videoArgs(
          webm: format == VideoFormat.webm,
          channels: document.audio.speakers.channels),
      // The picture decides how long it is: the mix is padded with silence
      // to reach its end, and cut where it ends.
      "-shortest",
    ],
  );
}

/// _input is where ffmpeg reads the frames from: a numbered set of PNGs.
List<String> _input(CanvasDocument document, String work) => [
      "-framerate",
      "${document.frameRate}",
      "-i",
      path.join(work, "frame-%05d.png"),
    ];

/// _encoderArgs is everything after the input: what the file is and how good
/// it is. Shared by the pipe and the file fallback so they cannot drift.
List<String> _encoderArgs(
        CanvasDocument document, VideoFormat format, VideoQuality quality) =>
    [
      // yuv420p plays everywhere, and 4:2:0 cannot have an odd side.
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
      "-pix_fmt", "yuv420p",
      "-c:v", format.encoder,
      "-crf", "${quality.crfFor(format)}",
      if (format == VideoFormat.mp4) ...[
        "-preset", "medium",
        // Index at the front, so it plays before it has all arrived.
        "-movflags", "+faststart",
      ],
      if (format == VideoFormat.webm) ...[
        // VP9 ignores the CRF unless the bitrate is explicitly zero.
        "-b:v", "0",
        // Rows in parallel: without it a long VP9 export reads as a hang.
        "-row-mt", "1",
      ],
    ];

/// _numbered is a frame's file name in ffmpeg's zero-padded sequence.
String _numbered(int frame) =>
    "frame-${(frame + 1).toString().padLeft(5, "0")}.png";

/// _even is what the scale filter above will have made of a dimension.
int _even(int side) => math.max(2, side - (side % 2));

/// estimateVideoBytes is a rough guess at a video's size: bytes per pixel
/// at the quality, times pixels, times frames. Orders of magnitude only.
int estimateVideoBytes(CanvasDocument document,
    {double scale = 1,
    VideoFormat format = VideoFormat.mp4,
    VideoQuality quality = VideoQuality.balanced}) {
  // The file's size, not the design's: see CanvasSize.exportSize.
  var pixels = document.size.exportSize.width *
      document.size.exportSize.height *
      scale *
      scale;
  var perPixel = switch (quality) {
    VideoQuality.high => 0.12,
    VideoQuality.balanced => 0.05,
    VideoQuality.small => 0.02,
  };
  // VP9 lands around two thirds of x264 at a matched quality.
  if (format == VideoFormat.webm) perPixel *= 0.65;
  // An animation is mostly still: later frames cost a fraction.
  var first = pixels * perPixel;
  var rest = math.max(0, document.playFrames - 1) * pixels * perPixel * 0.15;
  return (first + rest).round() + 40000;
}

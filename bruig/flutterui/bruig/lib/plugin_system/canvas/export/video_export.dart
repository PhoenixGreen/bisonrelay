import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

// video_export.dart is the MP4, and it is the one export that needs something
// this app does not carry.
//
// Flutter can encode a PNG and nothing else. The GIF next door is written out
// by hand for exactly that reason -- see gif_encoder.dart -- and an H.264
// encoder is not a thing anybody sensibly writes by hand: it is a
// standards-sized job whose output has to be right in a way a GIF's does not.
// The alternatives were a video codec nobody can review, a large native
// dependency shipped to every reader for a feature most will never press, or
// the encoder that is already on a lot of machines.
//
// So: ffmpeg, if it is there. The thing that made this unattractive before was
// failing silently on the machines without it, and that is what everything
// here is arranged to avoid. [ffmpegPath] is asked when the publish sheet
// opens rather than when Publish is pressed, so a reader without one is told
// while they are choosing -- the row is still listed, because a feature nobody
// can see is a feature nobody knows they could have, but it says [ffmpegHelp]
// and the button is disabled. Nothing else in the canvas depends on this file:
// with no ffmpeg the feature is one row that explains itself, and the GIF
// still exports.

/// _found is the answer to "is ffmpeg here", worked out once.
///
/// Cached because the publish sheet asks on every build and a process launch
/// per rebuild would be absurd. Cached even when the answer is no, for the
/// same reason -- somebody who installs ffmpeg while the sheet is open can
/// close and reopen the app, which is a fair price for not launching a
/// process on every frame.
String? _found;
bool _looked = false;

/// _candidates are the places an ffmpeg tends to be when it is not on PATH.
///
/// A GUI app on macOS does not inherit the shell's PATH -- it is started by
/// the window server, not by a login shell -- so the Homebrew install that
/// works perfectly in a terminal is invisible to `which` here. These are the
/// two Homebrew prefixes and the usual system ones.
const List<String> _candidates = [
  "/opt/homebrew/bin/ffmpeg",
  "/usr/local/bin/ffmpeg",
  "/usr/bin/ffmpeg",
  "/snap/bin/ffmpeg",
  r"C:\ffmpeg\bin\ffmpeg.exe",
];

/// ffmpegHelp is what to tell somebody who has not got one.
///
/// The exact commands rather than "install ffmpeg", because this message is
/// the whole of what stands between a reader and a working export -- ffmpeg is
/// not bundled, and it is not bundled for a reason worth knowing: the H.264
/// encoder ffmpeg uses, libx264, is GPL, and Bison Relay is ISC. Shipping the
/// two together would relicense the app. So the encoder is the reader's, on
/// their machine, under whatever licence they please.
const String ffmpegHelp =
    "Video needs ffmpeg, which is not installed. Install it with "
    "\"brew install ffmpeg\" on a Mac, \"apt install ffmpeg\" on Linux, or "
    "from ffmpeg.org on Windows — then restart. The GIF export needs nothing.";

/// ffmpegPath is where ffmpeg is, or null if it is not to be found.
Future<String?> ffmpegPath() async {
  if (_looked) return _found;
  _looked = true;
  // Phones do not let one app run another's binaries, and there is nothing to
  // find there in any case.
  if (Platform.isAndroid || Platform.isIOS) return null;

  try {
    var which = Platform.isWindows ? "where" : "which";
    var found = await Process.run(which, ["ffmpeg"]);
    if (found.exitCode == 0) {
      var first = (found.stdout as String).trim().split("\n").first.trim();
      if (first.isNotEmpty && await File(first).exists()) return _found = first;
    }
  } catch (exception) {
    // A machine with no `which` at all is a machine with no ffmpeg on PATH,
    // which is not an error worth reporting -- the list below is still worth
    // trying.
    debugPrint("Unable to look for ffmpeg on the path: $exception");
  }

  for (var candidate in _candidates) {
    if (await File(candidate).exists()) return _found = candidate;
  }
  return _found = null;
}

/// useFfmpegForTest fixes what [ffmpegPath] answers.
///
/// A test can point this at a script that records what it was called with.
/// Everything except the encoding itself -- the frames written out, the
/// arguments, reading the file back, clearing up afterwards -- is then
/// checked on a machine with no ffmpeg on it, which is most machines.
///
/// Pass null to pin the answer to "there is not one", which is what the
/// publish sheet's own tests need and cannot get from the machine they happen
/// to be running on. [forgetFfmpegForTest] puts it back.
@visibleForTesting
void useFfmpegForTest(String? path) {
  _looked = true;
  _found = path;
}

/// forgetFfmpegForTest clears the pinned answer, so the next look is a real
/// one. Every test that pins has to end with this, or a machine that does have
/// ffmpeg quietly stops testing the half that uses it.
@visibleForTesting
void forgetFfmpegForTest() {
  _looked = false;
  _found = null;
}

/// VideoFormat is which of the two files to write.
///
/// Two rather than one because they fail in opposite places. An MP4 is the
/// file everything takes -- QuickTime, Photos, a phone, a browser -- and its
/// encoder is GPL, which is why it can only ever be the reader's own copy of
/// ffmpeg and never one shipped here. A WebM is smaller at the same quality
/// and its encoder is BSD, so it is the one that could be built in one day if
/// that ever became worth doing; what it will not do is open in iOS or macOS
/// Photos, which is exactly where somebody sending a clip to a friend expects
/// it to land.
enum VideoFormat {
  mp4("MP4", "video/mp4", ".mp4", "libx264",
      "Plays everywhere, including Photos on a Mac or an iPhone."),
  webm("WebM", "video/webm", ".webm", "libvpx-vp9",
      "Smaller at the same quality, and plays in browsers and most chat "
          "apps — but not in Photos on a Mac or an iPhone.");

  final String label;
  final String mime;
  final String extension;

  /// encoder is what ffmpeg is asked for by name. A build without it says so
  /// and is reported as such -- see [renderVideo].
  final String encoder;

  final String note;
  const VideoFormat(
      this.label, this.mime, this.extension, this.encoder, this.note);
}

/// VideoQuality is the constant-rate factor handed to ffmpeg: lower is better
/// and larger.
///
/// Offered as three named choices rather than a number, because a CRF is a
/// number nobody outside video encoding has an opinion about -- and because
/// the two encoders do not even use the same scale. x264 runs 0..51 and calls
/// 18 visually lossless; VP9 runs 0..63 and wants something in the low
/// thirties for the same picture. One label, two numbers, so that switching
/// format does not silently change how good the file is.
enum VideoQuality {
  high("Best", 18, 24),
  balanced("Balanced", 23, 31),
  small("Smallest", 28, 40);

  final String label;
  final int _h264;
  final int _vp9;
  const VideoQuality(this.label, this._h264, this._vp9);

  int crfFor(VideoFormat format) =>
      format == VideoFormat.webm ? _vp9 : _h264;
}

/// renderVideo draws every frame and hands them to ffmpeg.
///
/// The frames go to a temporary directory as PNGs rather than down ffmpeg's
/// standard input. Piping is the tidier shape and it deadlocks: ffmpeg blocks
/// writing its own output while we are still blocked writing input, and the
/// export hangs with no error on exactly the long animations that most need
/// one. Files also mean the exact frames handed over can be looked at when
/// something goes wrong.
///
/// Returns null when there is no ffmpeg, when it fails, or when the document
/// has no frames. The caller reports it; see [ffmpegHelp].
Future<CanvasExport?> renderVideo(
  CanvasDocument document, {
  double scale = 1,
  CanvasImageSource? images,
  VideoFormat format = VideoFormat.mp4,
  VideoQuality quality = VideoQuality.balanced,
  GifProgress? onProgress,
}) async {
  var ffmpeg = await ffmpegPath();
  if (ffmpeg == null || document.frames <= 0) return null;

  Directory? work;
  try {
    work = await Directory.systemTemp.createTemp("bruig-canvas-video");

    var width = 0, height = 0;
    for (var i = 0; i < document.frames; i++) {
      ui.Image? image;
      try {
        image =
            await renderFrame(document, frame: i, scale: scale, images: images);
        var png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return null;
        width = image.width;
        height = image.height;
        await File(path.join(work.path, _numbered(i)))
            .writeAsBytes(png.buffer.asUint8List());
      } finally {
        image?.dispose();
      }
      onProgress?.call(i + 1, document.frames);
      // The same yield the GIF export makes, and for the same reason: without
      // it the whole run happens in one turn of the event loop and the
      // progress line the caller is drawing never appears.
      await Future<void>.delayed(Duration.zero);
    }
    if (width == 0) return null;

    var out = path.join(work.path, "canvas${format.extension}");
    var result = await Process.run(ffmpeg, [
      "-y",
      "-framerate", "${document.frameRate}",
      "-i", path.join(work.path, "frame-%05d.png"),
      // yuv420p and the even-sized scale are what makes the file play in
      // QuickTime, on a phone and in a browser rather than only in VLC.
      // Neither codec in 4:2:0 can have an odd dimension, and a canvas is any
      // size its author made it.
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
      "-pix_fmt", "yuv420p",
      "-c:v", format.encoder,
      "-crf", "${quality.crfFor(format)}",
      if (format == VideoFormat.mp4) ...[
        "-preset", "medium",
        // Puts the index at the front, so the file starts playing before it
        // has all arrived -- which is the difference between a link that
        // plays and one that downloads.
        "-movflags", "+faststart",
      ],
      if (format == VideoFormat.webm) ...[
        // VP9 only honours the CRF when the bitrate is explicitly nothing.
        // Left out, it quietly encodes to a default bitrate instead and the
        // quality control does nothing at all.
        "-b:v", "0",
        // Rows in parallel. VP9 is slow enough without it that a long export
        // reads as a hang.
        "-row-mt", "1",
      ],
      out,
    ]);

    if (result.exitCode != 0) {
      var why = "${result.stderr}";
      // An ffmpeg built without the encoder is a different problem from a
      // failed encode, and it is one the reader can do something about.
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
    // Whatever happened, the frames are not left behind. A 200-frame 4K export
    // is gigabytes of PNG in the temporary directory.
    try {
      await work?.delete(recursive: true);
    } catch (exception) {
      debugPrint("Unable to clear the video's working directory: $exception");
    }
  }
}

/// _numbered is ffmpeg's zero-padded sequence, which is how it knows the order
/// without being told.
String _numbered(int frame) =>
    "frame-${(frame + 1).toString().padLeft(5, "0")}.png";

/// _even is what the scale filter above will have made of a dimension.
int _even(int side) => math.max(2, side - (side % 2));

/// estimateVideoBytes is a rough guess at a video's size, for the line under
/// the publish sheet.
///
/// Deliberately crude: bits per pixel per frame at the chosen quality, times
/// the pixels, times the frames. Video compression depends almost entirely on
/// how much moves between one frame and the next, which is not something that
/// can be known without encoding -- so this is honest about orders of
/// magnitude and nothing finer, which is exactly what the line is for.
int estimateVideoBytes(CanvasDocument document,
    {double scale = 1,
    VideoFormat format = VideoFormat.mp4,
    VideoQuality quality = VideoQuality.balanced}) {
  var pixels = document.size.width * document.size.height * scale * scale;
  var perPixel = switch (quality) {
    VideoQuality.high => 0.12,
    VideoQuality.balanced => 0.05,
    VideoQuality.small => 0.02,
  };
  // VP9 lands somewhere around two thirds of what x264 does at a matched
  // quality, which is the reason anybody chooses it.
  if (format == VideoFormat.webm) perPixel *= 0.65;
  // A canvas animation is mostly still: the background does not change, and
  // the parts that do are a few elements moving. An inter-frame codec spends
  // almost nothing on the rest, so the frames after the first are a fraction
  // of it.
  var first = pixels * perPixel;
  var rest = math.max(0, document.frames - 1) * pixels * perPixel * 0.15;
  return (first + rest).round() + 40000;
}

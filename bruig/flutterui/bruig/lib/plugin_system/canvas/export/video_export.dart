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
const String ffmpegHelp =
    "MP4 needs ffmpeg, which is not installed. Install it with "
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

/// mp4Quality is the constant-rate factor handed to ffmpeg: lower is better
/// and larger, 18 is generally called visually lossless, 28 is small.
///
/// Offered as three named choices rather than a number, because a CRF is a
/// number nobody outside video encoding has an opinion about.
enum Mp4Quality {
  high("Best", 18),
  balanced("Balanced", 23),
  small("Smallest", 28);

  final String label;
  final int crf;
  const Mp4Quality(this.label, this.crf);
}

/// renderMp4 draws every frame and hands them to ffmpeg.
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
Future<CanvasExport?> renderMp4(
  CanvasDocument document, {
  double scale = 1,
  CanvasImageSource? images,
  Mp4Quality quality = Mp4Quality.balanced,
  GifProgress? onProgress,
}) async {
  var ffmpeg = await ffmpegPath();
  if (ffmpeg == null || document.frames <= 0) return null;

  Directory? work;
  try {
    work = await Directory.systemTemp.createTemp("bruig-canvas-mp4");

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

    var out = path.join(work.path, "canvas.mp4");
    var result = await Process.run(ffmpeg, [
      "-y",
      "-framerate", "${document.frameRate}",
      "-i", path.join(work.path, "frame-%05d.png"),
      // yuv420p and the even-sized scale are what makes the file play in
      // QuickTime, on a phone and in a browser rather than only in VLC. H.264
      // in 4:2:0 cannot have an odd dimension, and a canvas is any size its
      // author made it.
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
      "-pix_fmt", "yuv420p",
      "-c:v", "libx264",
      "-crf", "${quality.crf}",
      "-preset", "medium",
      // Puts the index at the front, so the file starts playing before it has
      // all arrived -- which is the difference between a link that plays and
      // one that downloads.
      "-movflags", "+faststart",
      out,
    ]);

    if (result.exitCode != 0) {
      debugPrint("ffmpeg could not write the video: ${result.stderr}");
      return null;
    }
    var file = File(out);
    if (!await file.exists()) return null;

    return CanvasExport(await file.readAsBytes(), "video/mp4",
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

/// estimateVideoBytes is a rough guess at an MP4's size, for the line under
/// the publish sheet.
///
/// Deliberately crude: bits per pixel per frame at the chosen quality, times
/// the pixels, times the frames. Video compression depends almost entirely on
/// how much moves between one frame and the next, which is not something that
/// can be known without encoding -- so this is honest about orders of
/// magnitude and nothing finer, which is exactly what the line is for.
int estimateVideoBytes(CanvasDocument document,
    {double scale = 1, Mp4Quality quality = Mp4Quality.balanced}) {
  var pixels = document.size.width * document.size.height * scale * scale;
  var perPixel = switch (quality) {
    Mp4Quality.high => 0.12,
    Mp4Quality.balanced => 0.05,
    Mp4Quality.small => 0.02,
  };
  // A canvas animation is mostly still: the background does not change, and
  // the parts that do are a few elements moving. An inter-frame codec spends
  // almost nothing on the rest, so the frames after the first are a fraction
  // of it.
  var first = pixels * perPixel;
  var rest = math.max(0, document.frames - 1) * pixels * perPixel * 0.15;
  return (first + rest).round() + 40000;
}

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

// ffmpeg_video.dart is everything the canvas asks ffmpeg about a video: what
// it is, a still from it, its sound, and its frames one after another.
//
// ffmpeg rather than the platform's player because the frames have to come
// back as pictures the canvas renderer can draw, key and grade -- see
// scene_renderer.dart, which is the only place a canvas becomes pixels. A
// player that draws into a texture of its own cannot be keyed, cannot be cut
// to a shape, and cannot be exported, which is three of the things a Video
// element is for.
//
// Found where the video exporter finds it -- see ffmpegPath. Without it a
// video can still be shown as its poster, which is stored as a picture.

/// VideoProbe is what a file turned out to be.
class VideoProbe {
  final double duration;
  final int width;
  final int height;
  final double fps;
  final bool hasAudio;

  const VideoProbe({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasAudio,
  });
}

/// probeVideo asks ffmpeg what [path] is, or returns null where it is not a
/// video it can read.
///
/// From ffmpeg's own report on stderr rather than ffprobe, which is not
/// installed everywhere ffmpeg is.
Future<VideoProbe?> probeVideo(String ffmpeg, String path) async {
  try {
    var run = await Process.run(ffmpeg, ["-hide_banner", "-i", path]);
    return parseProbe(run.stderr.toString());
  } catch (exception) {
    debugPrint("Unable to probe $path: $exception");
    return null;
  }
}

/// parseProbe reads ffmpeg's description of an input. Public so the reading
/// can be tested against real reports without running ffmpeg.
@visibleForTesting
VideoProbe? parseProbe(String report) {
  var video = RegExp(r"Stream #\S+.*?Video: .*").firstMatch(report)?.group(0);
  if (video == null) return null;
  var size = RegExp(r"\b(\d{2,5})x(\d{2,5})\b").firstMatch(video);
  if (size == null) return null;
  var fps = RegExp(r"([\d.]+) fps").firstMatch(video) ??
      RegExp(r"([\d.]+) tbr").firstMatch(video);
  var d = RegExp(r"Duration: (\d+):(\d+):([\d.]+)").firstMatch(report);
  var duration = d == null
      ? 0.0
      : int.parse(d.group(1)!) * 3600 +
          int.parse(d.group(2)!) * 60 +
          double.parse(d.group(3)!);
  return VideoProbe(
    duration: duration,
    width: int.parse(size.group(1)!),
    height: int.parse(size.group(2)!),
    fps: double.tryParse(fps?.group(1) ?? "") ?? 25,
    hasAudio: RegExp(r"Stream #\S+.*?Audio: ").hasMatch(report),
  );
}

/// posterOf is a still from [path] at [at] seconds, as PNG bytes, no wider
/// than [maxWidth].
Future<Uint8List?> posterOf(String ffmpeg, String path,
    {double at = 0, int maxWidth = 1280}) async {
  try {
    var run = await Process.run(
        ffmpeg,
        [
          "-hide_banner", "-loglevel", "error", //
          "-ss", at.toStringAsFixed(3), "-i", path,
          "-frames:v", "1",
          "-vf", "scale='min($maxWidth,iw)':-2",
          "-f", "image2pipe", "-c:v", "png", "-",
        ],
        stdoutEncoding: null);
    var bytes = run.stdout;
    if (run.exitCode != 0 || bytes is! List<int> || bytes.isEmpty) return null;
    return Uint8List.fromList(bytes);
  } catch (exception) {
    debugPrint("Unable to take a poster from $path: $exception");
    return null;
  }
}

/// extractSound writes [path]'s audio to [to] as FLAC, which the audio engine
/// opens and which loses nothing. False where there was none to take.
Future<bool> extractSound(String ffmpeg, String path, String to) async {
  try {
    var run = await Process.run(ffmpeg, [
      "-hide_banner", "-loglevel", "error", "-y", //
      "-i", path, "-vn", "-c:a", "flac", to,
    ]);
    return run.exitCode == 0 && await File(to).exists();
  } catch (exception) {
    debugPrint("Unable to take the sound from $path: $exception");
    return false;
  }
}

/// VideoFrame is one decoded picture and the moment in the file it is of.
class VideoFrame {
  final double time;
  final ui.Image image;
  const VideoFrame(this.time, this.image);
}

/// FrameReader hands out a file's frames in order.
abstract class FrameReader {
  /// next is the next frame, or null once there are no more.
  Future<VideoFrame?> next();
  void close();
}

/// FrameSource opens a reader on a file from a moment, at a size and rate.
abstract class FrameSource {
  Future<FrameReader?> open(String path,
      {required double from,
      required int width,
      required int height,
      required double fps});
}

/// FfmpegFrames decodes with an ffmpeg process per reader, streaming raw
/// RGBA down its stdout.
class FfmpegFrames implements FrameSource {
  final Future<String?> Function() locate;
  FfmpegFrames(this.locate);

  @override
  Future<FrameReader?> open(String path,
      {required double from,
      required int width,
      required int height,
      required double fps}) async {
    var ffmpeg = await locate();
    if (ffmpeg == null) return null;
    try {
      var process = await Process.start(ffmpeg, [
        "-hide_banner", "-loglevel", "error", //
        "-ss", from.toStringAsFixed(3), "-i", path, "-an",
        "-vf", "fps=${fps.toStringAsFixed(3)},scale=$width:$height",
        "-pix_fmt", "rgba", "-f", "rawvideo", "-",
      ]);
      return _FfmpegReader(process, from, width, height, fps);
    } catch (exception) {
      debugPrint("Unable to decode $path: $exception");
      return null;
    }
  }
}

class _FfmpegReader implements FrameReader {
  final Process process;
  final double from;
  final int width;
  final int height;
  final double fps;

  /// frameBytes is one picture's worth of stdout.
  final int frameBytes;

  /// _ready is frames read and not yet asked for. Bounded: reading is paused
  /// while it is full, so a paused video does not decode its whole length
  /// into memory in the background.
  final Queue<Uint8List> _ready = Queue();
  static const _ahead = 6;
  final BytesBuilder _partial = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> _out;
  Completer<void>? _waiting;
  bool _done = false;
  int _index = 0;

  _FfmpegReader(this.process, this.from, this.width, this.height, this.fps)
      : frameBytes = width * height * 4 {
    // Drained from the start, or an ffmpeg with something to say blocks on
    // a full pipe and never produces another frame. See video_export.dart.
    process.stderr.drain<void>();
    _out = process.stdout.listen(_take, onDone: () {
      _done = true;
      _wake();
    }, onError: (_) {
      _done = true;
      _wake();
    });
  }

  void _take(List<int> chunk) {
    var at = 0;
    while (at < chunk.length) {
      var need = frameBytes - _partial.length;
      var take = math.min(need, chunk.length - at);
      _partial.add(chunk.sublist(at, at + take));
      at += take;
      if (_partial.length == frameBytes) {
        _ready.add(_partial.takeBytes());
      }
    }
    if (_ready.length >= _ahead && !_out.isPaused) _out.pause();
    _wake();
  }

  void _wake() {
    var w = _waiting;
    _waiting = null;
    w?.complete();
  }

  @override
  Future<VideoFrame?> next() async {
    while (_ready.isEmpty && !_done) {
      _waiting ??= Completer<void>();
      await _waiting!.future;
    }
    if (_ready.isEmpty) return null;
    var pixels = _ready.removeFirst();
    if (_out.isPaused && _ready.length < _ahead) _out.resume();
    var completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    var image = await completer.future;
    var time = from + _index / fps;
    _index++;
    return VideoFrame(time, image);
  }

  @override
  void close() {
    _done = true;
    _wake();
    _out.cancel();
    process.kill();
  }
}

/// decodeSize is how large to decode a [source]-sized video to be drawn at
/// about [wanted] -- never larger than the file, never wider than
/// [maxWidth], and even on both sides, which the decoder's scaler needs.
(int, int) decodeSize(ui.Size source, ui.Size wanted, {int maxWidth = 1280}) {
  if (source.width <= 0 || source.height <= 0) return (2, 2);
  var width = math.min(source.width,
      math.min(maxWidth.toDouble(), math.max(64.0, wanted.width)));
  var height = width * source.height / source.width;
  int even(double v) => math.max(2, (v / 2).round() * 2);
  return (even(width), even(height));
}

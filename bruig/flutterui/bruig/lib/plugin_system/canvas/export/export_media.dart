import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';

// export_media.dart is the media on the timeline, for an export: the frame
// each video shows on each frame of the run, and the sound to put under it.
//
// The editor plays media with the runtimes, which keep time by the sound card
// -- see video_runtime.dart. An export has no sound card and no clock: it
// renders frame after frame as fast as it can, and frame 200 is the frame at
// eight seconds however long it took to get there. So the same question --
// where is this clip at this frame -- is asked of the same function,
// MediaClip.momentAt, and answered by decoding: one reader per video, read
// forward as the export goes forward.
//
// Only media on the timeline is here. Media a reader presses is not part of
// the animation, and an export shows it as its poster, silent.

/// ExportSound is one stretch of one file in the finished sound: where it
/// starts in the export, which part of the file, and how it fades.
class ExportSound {
  final String path;

  /// at is seconds into the export; from and length are the part of the file.
  final double at;
  final double from;
  final double length;
  final double fadeIn;
  final double fadeOut;
  final double volume;

  const ExportSound({
    required this.path,
    required this.at,
    required this.from,
    required this.length,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.volume = 1,
  });
}

/// _Placed is one piece of timed media as it sits in the run.
class _Placed {
  final CanvasElement element;

  /// start is the frame of the run its own timeline counts from -- its
  /// scene's first frame, or nought for media on the master -- and until is
  /// the frame after the last one it can be seen or heard on.
  final int start;
  final int until;

  FrameReader? reader;
  int readerIndex = -1;
  double readFrom = -1;
  VideoFrame? current;
  VideoFrame? pending;
  bool ended = false;

  _Placed(this.element, this.start, this.until);

  MediaClip get clip => switch (element) {
        VideoElement v => v.clip,
        AudioElement a => a.clip,
        _ => const MediaClip(),
      };

  void close() {
    reader?.close();
    reader = null;
    current?.image.dispose();
    current = null;
    pending?.image.dispose();
    pending = null;
  }
}

bool _timed(CanvasElement e) => switch (e) {
      VideoElement v => v.clip.timed && !v.isLink && !v.clip.isEmpty,
      AudioElement a => a.clip.timed && !a.clip.isEmpty,
      _ => false,
    };

class ExportMedia {
  final CanvasDocument document;
  final FrameSource frames;
  final Future<String?> Function(MediaKind kind, String id) locate;

  /// scale is the export's own multiplier, so a video is decoded at the size
  /// it will be drawn in the file.
  final double scale;
  final List<_Placed> _placed;

  ExportMedia._(
      this.document, this.frames, this.locate, this.scale, this._placed);

  /// of is the timed media in [document], or null where there is none -- so
  /// an export with nothing on its timeline costs nothing extra.
  static ExportMedia? of(
    CanvasDocument document, {
    double scale = 1,
    FrameSource? frames,
    Future<String?> Function(MediaKind kind, String id)? locate,
  }) {
    var placed = <_Placed>[];
    var scenes = document.allScenes;
    var run = math.max(1, document.playFrames);
    var master = document.masterScene;

    for (var i = 0; i < scenes.length; i++) {
      var from = document.hasScenes ? document.startOfScene(i) : 0;
      var until = math.min(run, from + scenes[i].frames);
      for (var e in scenes[i].elements) {
        if (_timed(e)) placed.add(_Placed(e, from, until));
      }
      // A scene's backdrop is its own, unless the master's covers it --
      // which is placed once, below, against the whole run.
      if (master?.sharedBackground == null) {
        for (var e in document.backgroundOf(i).media) {
          if (_timed(e)) placed.add(_Placed(e, from, until));
        }
      }
    }
    if (master != null) {
      for (var e in [...master.elements, ...?master.sharedBackground?.media]) {
        if (_timed(e)) placed.add(_Placed(e, 0, run));
      }
    }
    if (placed.isEmpty) return null;
    return ExportMedia._(
        document,
        frames ?? FfmpegFrames(ffmpegPath),
        locate ?? (kind, id) => CanvasMedia.existingPath(kind, id),
        scale,
        placed);
  }

  double get _rate =>
      (document.frameRate <= 0 ? 1 : document.frameRate).toDouble();

  ClipMoment? _momentAt(_Placed p, int frame) {
    if (frame < p.start || frame >= p.until) return null;
    return p.clip.momentAt((frame - p.start - p.clip.at) / _rate);
  }

  /// at decodes whatever frames the run's frame [frame] needs, and returns
  /// what to hand the renderer for it.
  ///
  /// Frames must be asked for in order, as an export does. Asked for out of
  /// order it still works, by opening each reader again, which is slow.
  Future<VideoShow Function(VideoElement)> at(int frame) async {
    var shows = <String, VideoShow>{};
    for (var p in _placed) {
      var e = p.element;
      if (e is! VideoElement) continue;
      if (frame < p.start || frame >= p.until) continue;
      var moment = _momentAt(p, frame);
      if (moment == null) {
        shows[e.id] = const VideoShow(hidden: true);
        continue;
      }
      await _frameAt(p, moment);
      var source = e.clip.playlist[moment.index];
      shows[e.id] = VideoShow(
        playing: true,
        muted: e.clip.muted,
        volume: e.clip.volume,
        position: moment.time,
        start: source.start,
        end: source.endOr(source.length),
        frame: p.current?.image,
        poster: source.posterId,
        opacity: moment.gain,
      );
    }
    return (e) => shows[e.id] ?? VideoShow.idle(e);
  }

  Future<void> _frameAt(_Placed p, ClipMoment moment) async {
    var e = p.element as VideoElement;
    var source = e.clip.playlist[moment.index];
    var step = 1 / _rate;
    var behind = p.current != null && moment.time < p.current!.time - step / 2;
    var jumped = p.current != null && moment.time > p.current!.time + 1.0;
    if (p.reader == null || p.readerIndex != moment.index || behind || jumped) {
      p.close();
      p.ended = false;
      var path = await locate(MediaKind.video, source.assetId);
      if (path == null) return;
      var (w, h) = decodeSize(
          ui.Size(source.width.toDouble(), source.height.toDouble()),
          ui.Size(e.width * scale, e.height * scale),
          maxWidth: 1920);
      p.reader = await frames.open(path,
          from: moment.time, width: w, height: h, fps: _rate);
      p.readerIndex = moment.index;
      p.readFrom = moment.time;
    }
    var reader = p.reader;
    if (reader == null) return;
    // Forward to the last frame due by now: the export's frames and the
    // file's are at the same rate, so this is usually exactly one.
    while (!p.ended) {
      var next = p.pending ?? await reader.next();
      p.pending = null;
      if (next == null) {
        p.ended = true;
        break;
      }
      if (p.current != null && next.time > moment.time + step / 2) {
        p.pending = next;
        break;
      }
      p.current?.image.dispose();
      p.current = next;
      if (next.time >= moment.time - step / 2) break;
    }
  }

  /// sounds is every stretch of sound the export carries, placed.
  Future<List<ExportSound>> sounds() async {
    var out = <ExportSound>[];
    var total = document.playFrames / _rate;
    for (var p in _placed) {
      var clip = p.clip;
      if (clip.muted || clip.volume <= 0) continue;
      var begins = (p.start + clip.at) / _rate;
      var limit = math.min(p.until / _rate, total) - begins;
      if (limit <= 0) continue;
      var run = clip.runLength;
      if (run <= 0) continue;

      var t = 0.0;
      while (t < limit) {
        for (var source in clip.playlist) {
          var span = source.span;
          if (span <= 0 || t >= limit) continue;
          var file = switch (p.element) {
            VideoElement _ => source.soundId,
            _ => source.assetId,
          };
          if (file.isNotEmpty) {
            var path = await locate(MediaKind.audio, file);
            if (path != null) {
              var length = math.min(span, limit - t);
              out.add(ExportSound(
                path: path,
                at: begins + t,
                from: source.start,
                length: length,
                fadeIn: clip.fadeIn,
                // Cut short by the end of the scene, it stops rather than
                // fading: the fade belongs to the end of the file.
                fadeOut: length < span ? 0 : clip.fadeOut,
                volume: clip.volume,
              ));
            }
          }
          t += span;
        }
        if (clip.loop == MediaLoop.none) break;
      }
    }
    return out;
  }

  void dispose() {
    for (var p in _placed) {
      p.close();
    }
  }
}

/// mixArgs is what ffmpeg is told to put [sounds] together as one track, when
/// they are its inputs from [first] on: the input arguments, and the filter
/// graph whose output is labelled "mix".
///
/// Each stretch is trimmed by input seeking, faded, set to its volume and
/// delayed to where it starts; then all of them are summed without being
/// turned down -- amix's default halves every input, which would make a
/// clip on its own half as loud as it was set to be.
(List<String>, String) mixArgs(List<ExportSound> sounds, {int first = 1}) {
  var inputs = <String>[];
  var chains = <String>[];
  var labels = <String>[];
  String n(double v) => v.toStringAsFixed(3);
  for (var (i, s) in sounds.indexed) {
    inputs.addAll(["-ss", n(s.from), "-t", n(s.length), "-i", s.path]);
    var filters = <String>[
      "aresample=48000",
      "aformat=channel_layouts=stereo",
      if (s.fadeIn > 0) "afade=t=in:st=0:d=${n(s.fadeIn)}",
      if (s.fadeOut > 0)
        "afade=t=out:st=${n(math.max(0, s.length - s.fadeOut))}:d=${n(s.fadeOut)}",
      if (s.volume != 1) "volume=${n(s.volume)}",
      "adelay=${(s.at * 1000).round()}:all=1",
    ];
    chains.add("[${first + i}:a]${filters.join(",")}[s$i]");
    labels.add("[s$i]");
  }
  var mix = sounds.length == 1
      ? "${labels.single}apad[mix]"
      : "${labels.join()}amix=inputs=${sounds.length}:normalize=0"
          ":dropout_transition=0,apad[mix]";
  return (inputs, [...chains, mix].join(";"));
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/export/mix_render.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/audio_tools.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/render/sound_placement.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

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

  /// mix is the channel strip this stretch plays through, and channel the
  /// channel's key: every stretch on one channel is summed and then played
  /// through the strip once, as the editor plays it. Empty for a stretch
  /// with a strip of its own.
  final ChannelMix mix;
  final String channel;

  /// envelope is the clip's volume envelope, in seconds from the start of
  /// this stretch -- see MediaClip.envelope.
  final List<GainPoint> envelope;

  /// place is where the sound is heard from over the export, for a placed
  /// sound: each (seconds into the export, where), in order. See
  /// SoundPlacement.
  final List<(double, Heard)> place;

  /// clock is the seconds into the export its channel's timeline counts
  /// from -- its scene's start -- for the lanes of the channel's
  /// automation, whose points are counted from there.
  final double clock;

  const ExportSound({
    this.clock = 0,
    this.place = const [],
    required this.path,
    required this.at,
    required this.from,
    required this.length,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.volume = 1,
    this.mix = const ChannelMix(),
    this.channel = "",
    this.envelope = const [],
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

  /// scene is the scene it is in, or null for one on the master or a
  /// transition: where a placed sound finds its stage.
  final int? scene;

  _Placed(this.element, this.start, this.until, [this.scene]);

  /// clip is the element's clip as the export plays it: a video that is not
  /// on the timeline from the start of its scene, wherever it was once put.
  MediaClip get clip => switch (element) {
        VideoElement v when !v.clip.timed => v.clip.copyWith(at: 0),
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

/// _timed is whether [e] plays in an export. A video plays whether it is on
/// the timeline or not: one that is not starts with its scene, as a film
/// has no viewer to press its play button -- and a poster with a player's
/// controls drawn on it was what it had been.
bool _timed(CanvasElement e) => switch (e) {
      VideoElement v => !v.isLink && !v.clip.isEmpty,
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
        if (_timed(e)) placed.add(_Placed(e, from, until, i));
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
    // What the transitions carry, where each transition is -- see
    // CanvasDocument.transitionSounds.
    for (var e in document.transitionSounds) {
      placed.add(_Placed(e, 0, run));
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
        // A video that is not on the timeline stays on its last frame once
        // it has played, as it does on the page; one on the timeline has
        // been cut out.
        shows[e.id] = e.clip.timed
            ? const VideoShow(hidden: true)
            : VideoShow(
                controls: false,
                frame: p.current?.image,
                poster: e.clip.playlist.last.posterId);
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
        controls: false,
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
    var ducks = await _duckEnvelopes();
    // A muted channel a vocoder takes its carrier from is still carried:
    // unheard itself, it is heard through the vocoder.
    var carriers = {
      for (var p in _placed)
        for (var d in p.clip.mix.devices)
          if (d.sidechain case var c?) c,
      for (var r in document.returns)
        for (var d in r.devices)
          if (d.sidechain case var c?) c,
    };
    for (var p in _placed) {
      var clip = p.clip;
      if (clip.muted || clip.volume <= 0) continue;
      if (clip.mix.mute && !carriers.contains(_channelOf(p.element, clip))) {
        continue;
      }
      var begins = (p.start + clip.at) / _rate;
      var limit = math.min(p.until / _rate, total) - begins;
      if (limit <= 0) continue;
      var run = clip.runLength;
      if (run <= 0) continue;
      var place = _placeOf(p, clip, begins, limit);

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
                mix: clip.mix,
                channel:
                    clip.channel.isNotEmpty ? clip.channel : p.element.id,
                clock: p.start / _rate,
                place: place,
                envelope: multiplyEnvelopes(
                  [for (var g in clip.envelope) GainPoint(g.time - t, g.gain)],
                  // The run's ducking, from where this stretch starts.
                  [
                    for (var g in ducks[_channelOf(p.element, clip)] ??
                        const <GainPoint>[])
                      GainPoint(g.time - (begins + t), g.gain),
                  ],
                ),
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

  /// _placeOf is where [p]'s sound is heard from, frame by frame, from
  /// [begins] seconds into the export for [limit] seconds -- each change
  /// kept, the rest left out -- or nothing for a sound that is not placed.
  List<(double, Heard)> _placeOf(
      _Placed p, MediaClip clip, double begins, double limit) {
    if (clip.place.isOff) return const [];
    var doc = p.scene == null ? document : document.goToScene(p.scene!);
    var out = <(double, Heard)>[];
    var first = (begins * _rate).floor();
    var last = ((begins + limit) * _rate).ceil();
    for (var f = first; f <= last; f++) {
      var h = heardAt(doc, p.element, clip.place, f - p.start);
      if (h == null) continue;
      if (out.isNotEmpty) {
        var was = out.last.$2;
        if ((wrapAngle(h.angle - was.angle)).abs() < 0.5 &&
            (h.gain - was.gain).abs() < 0.005) {
          continue;
        }
      }
      out.add((f / _rate, h));
    }
    return out;
  }

  /// _channelOf is the channel a sound is on: its own, untagged.
  static String _channelOf(CanvasElement e, MediaClip clip) =>
      clip.channel.isNotEmpty ? clip.channel : e.id;

  /// _duckEnvelopes is the run's ducking -- see duckEnvelopes -- with the
  /// shapes of the channels that duck read from their files by ffmpeg, as the
  /// editor reads them to play.
  Future<Map<String, List<GainPoint>>> _duckEnvelopes() async {
    var wanted = {
      for (var s in timedSounds(document))
        if (s.clip.mix.duck.on)
          for (var source in s.clip.playlist) source.assetId,
    };
    if (wanted.isEmpty) return const {};
    var ffmpeg = await ffmpegPath();
    if (ffmpeg == null) return const {};
    var peaks = <String, Float32List>{};
    for (var id in wanted) {
      var file = await locate(MediaKind.audio, id);
      if (file == null) continue;
      if (await filePeaks(ffmpeg, file) case var p?) peaks[id] = p;
    }
    return duckEnvelopes(document, (id) => peaks[id]);
  }

  void dispose() {
    for (var p in _placed) {
      p.close();
    }
  }
}

/// renderSoundtrack is [document]'s timeline sound through its mix and
/// nothing else -- what a video export of it would carry -- as an AAC file
/// exactly as long as the timeline. Null where there is nothing to hear, or
/// no ffmpeg.
///
/// For a book page laid out as its elements: the page plays its soundtrack
/// in step with its own playhead, and every channel strip, the master and
/// the loudness target are in it, as they are in a film of the page.
Future<Uint8List?> renderSoundtrack(CanvasDocument document,
    {Future<String?> Function(MediaKind kind, String id)? locate}) async {
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
    work = await Directory.systemTemp.createTemp("canvas-soundtrack");
    var mixed = path.join(work.path, "mix.wav");
    // A book's player is a browser's: two speakers, folded down.
    if (!await renderMixWav(sounds, document.masterMix,
        seconds: seconds,
        ffmpeg: ffmpeg,
        out: mixed,
        returns: document.returns,
        speakers: document.audio.speakers,
        fold: true)) {
      return null;
    }
    var out = path.join(work.path, "sound.m4a");
    var run = await Process.run(ffmpeg, [
      "-hide_banner", "-loglevel", "error", "-y", //
      "-i", mixed,
      "-t", seconds.toStringAsFixed(3),
      "-c:a", "aac", "-b:a", "192k",
      "-movflags", "+faststart",
      out,
    ]);
    if (run.exitCode != 0 || !await File(out).exists()) {
      debugPrint("Unable to render the soundtrack: ${run.stderr}");
      return null;
    }
    return await File(out).readAsBytes();
  } catch (exception) {
    debugPrint("Unable to render the soundtrack: $exception");
    return null;
  } finally {
    media.dispose();
    try {
      await work?.delete(recursive: true);
    } catch (_) {}
  }
}

/// Loudness is what a mix measured, the way broadcast measures it: EBU R128
/// integrated loudness, loudness range and true peak.
class Loudness {
  final double integrated;
  final double range;
  final double truePeak;
  const Loudness(this.integrated, this.range, this.truePeak);
}

/// parseLoudness reads the summary ffmpeg's ebur128 filter prints at the end.
@visibleForTesting
Loudness? parseLoudness(String report) {
  var at = report.lastIndexOf("Summary:");
  if (at < 0) return null;
  var summary = report.substring(at);
  double? read(String label) {
    var m = RegExp("$label:\\s+(-?[\\d.]+|-inf)").firstMatch(summary);
    var v = m?.group(1);
    if (v == null) return null;
    return v == "-inf" ? double.negativeInfinity : double.tryParse(v);
  }

  var integrated = read("I");
  var range = read("LRA");
  var peak = read("Peak");
  if (integrated == null) return null;
  return Loudness(integrated, range ?? 0, peak ?? double.negativeInfinity);
}

/// measureMix plays [document]'s timeline sound through its mix, as an
/// export would, into ffmpeg's loudness meter -- and nowhere else. The one
/// honest answer to "how loud is this", because it is the export's own sound.
Future<Loudness?> measureMix(CanvasDocument document,
    {Future<String?> Function(MediaKind kind, String id)? locate}) async {
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
    // The mix as an export renders it, then ffmpeg's meter over that.
    work = await Directory.systemTemp.createTemp("canvas-measure");
    var mixed = path.join(work.path, "mix.wav");
    if (!await renderMixWav(sounds, document.masterMix,
        seconds: seconds,
        ffmpeg: ffmpeg,
        out: mixed,
        returns: document.returns,
        // Every speaker: ffmpeg's meter weights them as BS.1770 says.
        speakers: document.audio.speakers)) {
      return null;
    }
    var run = await Process.run(ffmpeg, [
      "-hide_banner", "-nostats", //
      "-i", mixed,
      "-filter_complex", "ebur128=peak=true",
      "-f", "null", "-",
    ]);
    return parseLoudness(run.stderr.toString());
  } catch (exception) {
    debugPrint("Unable to measure the mix: $exception");
    return null;
  } finally {
    media.dispose();
    if (work != null) await work.delete(recursive: true).catchError((_) => work!);
  }
}

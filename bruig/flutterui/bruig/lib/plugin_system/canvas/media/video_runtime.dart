import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/media/audio_runtime.dart';
import 'package:bruig/plugin_system/canvas/media/ffmpeg_video.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:flutter/foundation.dart';

// video_runtime.dart plays the canvas's videos: which file, which frame of it
// is showing, where the sound has got to, and what survives a page turn.
//
// Session state, like the audio runtime's -- see audio_runtime.dart. The same
// rules about ranges, playlists and loops, applied to pictures.
//
// **Time is kept by the sound.** A video with sound hands it to the audio
// runtime, and the picture shows whichever frame is due at the position the
// sound has reached. Two clocks -- a stopwatch for the picture and the sound
// card for the sound -- drift apart by a frame every few seconds, and lips
// that move before the words is the one thing anybody notices about a video.
// A video with no sound, or before its sound has opened, keeps time by a
// stopwatch.

/// VideoView is how a video is doing now, for the painter.
class VideoView {
  final bool playing;
  final bool muted;
  final double volume;

  /// position is seconds into the file, and start and end the range playing.
  final double position;
  final double start;
  final double end;

  /// frame is the picture to show, or null for the poster.
  final ui.Image? frame;

  /// opacity is the picture's fade, in and out at the ends of the range.
  final double opacity;

  /// poster is the still of the file that is current, for when there is no
  /// frame yet.
  final String poster;

  const VideoView({
    this.playing = false,
    this.muted = false,
    this.volume = 1,
    this.position = 0,
    this.start = 0,
    this.end = 0,
    this.frame,
    this.opacity = 1,
    this.poster = "",
  });

  /// through is how far along the range [position] is, nought to one.
  double get through =>
      end > start ? ((position - start) / (end - start)).clamp(0.0, 1.0) : 0;
}

class _Showing {
  VideoElement element;
  int index = 0;

  /// started is whether a file is open -- playing or paused. Not started is
  /// the poster.
  bool started = false;
  bool playing = false;
  bool muted;
  double volume;

  FrameReader? reader;
  VideoFrame? shown;
  VideoFrame? waiting;
  bool pulling = false;
  bool ended = false;

  double start = 0;
  double end = 0;

  /// base is where in the file the stopwatch counts from.
  double base = 0;
  final Stopwatch watch = Stopwatch();

  int generation = 0;

  /// timed, gain and opening are the same as the audio runtime's: a video
  /// the playhead drives, its fade there, and a file being opened.
  bool timed = false;
  double gain = 1;
  bool opening = false;

  _Showing(this.element)
      : muted = element.clip.muted,
        volume = element.clip.volume;

  String get soundId => "video:${element.id}";
  MediaSource? get source {
    var list = element.clip.playlist;
    return list.isEmpty ? null : list[index.clamp(0, list.length - 1)];
  }
}

class VideoRuntime extends ChangeNotifier {
  final FrameSource frames;
  final AudioRuntime audio;

  /// locate is where a stored video file is on disk.
  final Future<String?> Function(String assetId) locate;

  VideoRuntime({
    required this.frames,
    required this.audio,
    required this.locate,
  });

  final Map<String, _Showing> _shows = {};
  Timer? _timer;
  bool _disposed = false;

  int get revision => _revision;
  int _revision = 0;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  /// isVideoSound is whether an id in the audio runtime is a video's sound,
  /// and whose -- so the page-turn rule for sounds can ask the video.
  static String? videoOfSound(String soundId) =>
      soundId.startsWith("video:") ? soundId.substring(6) : null;

  VideoView view(VideoElement e) {
    var p = _shows[e.id];
    if (p == null || !p.started) {
      var first = e.clip.playlist.isEmpty ? null : e.clip.playlist.first;
      return VideoView(
        muted: p?.muted ?? e.clip.muted,
        volume: p?.volume ?? e.clip.volume,
        frame: p?.shown?.image,
        start: first?.start ?? 0,
        end: first == null ? 0 : first.endOr(first.length),
        position: first?.start ?? 0,
        poster: first?.posterId ?? "",
      );
    }
    var at = _time(p);
    return VideoView(
      playing: p.playing,
      muted: p.muted,
      volume: p.volume,
      position: at,
      start: p.start,
      end: p.end,
      frame: p.shown?.image,
      opacity: p.timed ? p.gain : _fade(p, at),
      poster: p.source?.posterId ?? "",
    );
  }

  bool isPlaying(String id) => _shows[id]?.playing ?? false;

  Set<String> get playingIds => {
        for (var e in _shows.entries)
          if (e.value.playing) e.key,
      };

  _Showing _for(VideoElement e) {
    var p = _shows.putIfAbsent(e.id, () => _Showing(e));
    p.element = e;
    return p;
  }

  Future<void> play(VideoElement e) async {
    if (e.isLink || e.clip.isEmpty) return;
    var p = _for(e);
    if (p.started && !p.playing) {
      p.playing = true;
      p.watch.start();
      unawaited(audio.play(_sound(p)));
      _startTimer();
      notifyListeners();
      return;
    }
    if (p.started) return;
    await _start(p, p.index, from: null);
  }

  void pause(String id) {
    var p = _shows[id];
    if (p == null || !p.playing) return;
    // Where it got to, read while it is still playing -- which is when the
    // clock is the sound's. Read after, it was the stopwatch's, and pressing
    // play again jumped back to wherever that had been started.
    var at = _time(p);
    p.playing = false;
    p.watch
      ..stop()
      ..reset();
    p.base = at;
    audio.pause(p.soundId);
    notifyListeners();
  }

  Future<void> toggle(VideoElement e) {
    if (!isPlaying(e.id)) return play(e);
    pause(e.id);
    return Future.value();
  }

  /// stop closes the file and goes back to the poster.
  void stop(String id) {
    var p = _shows[id];
    if (p == null) return;
    _close(p);
    p.index = 0;
    notifyListeners();
  }

  /// seekTo moves [e] to [through] of the way along its range -- a press on
  /// the play bar.
  Future<void> seekTo(VideoElement e, double through) async {
    var p = _for(e);
    if (!p.started) {
      await _start(p, p.index, from: null, paused: true);
    }
    if (!p.started) return;
    var at = p.start + (p.end - p.start) * through.clamp(0.0, 1.0);
    await _open(p, at);
    audio.seek(p.soundId, at);
    notifyListeners();
  }

  void setVolume(VideoElement e, double volume) {
    var p = _for(e);
    p.volume = volume.clamp(0.0, 1.0);
    audio.setVolume(_sound(p), p.volume);
    notifyListeners();
  }

  void setMuted(VideoElement e, bool muted) {
    var p = _for(e);
    p.muted = muted;
    audio.setMuted(_sound(p), muted);
    notifyListeners();
  }

  void toggleMute(VideoElement e) => setMuted(e, !view(e).muted);

  /// keepOnly stops and forgets every video [keep] says no to.
  void keepOnly(bool Function(String id) keep) {
    var gone = [
      for (var id in _shows.keys)
        if (!keep(id)) id,
    ];
    if (gone.isEmpty) return;
    for (var id in gone) {
      _close(_shows.remove(id)!);
    }
    notifyListeners();
  }

  void stopAll() => keepOnly((_) => false);

  void autoplay(Iterable<VideoElement> elements) {
    for (var e in elements) {
      if (!e.clip.autoplay || e.clip.isEmpty || e.isLink) continue;
      var p = _shows[e.id];
      if (p != null && p.started) continue;
      unawaited(play(e));
    }
  }

  /// cue puts [e] where the playhead says it is. See AudioRuntime.cue, which
  /// is the same idea for a sound: held or playing as the playhead is, moved
  /// back into step when it drifts, and never on to its next file by itself.
  ///
  /// Held, it is moved to within a frame, because a held video is being
  /// scrubbed and the frame under the playhead is the whole point; playing,
  /// it is left alone unless it is a good fraction of a second out, because
  /// reopening a file to correct a frame of drift is a stutter.
  void cue(VideoElement e, ClipMoment? moment, {required bool playing}) {
    var p = _for(e);
    p.timed = true;
    // As loud as its clip's volume line says, as a sound on the timeline is:
    // nobody turns a timed video up by hand.
    if (p.volume != e.clip.volume || p.muted != e.clip.muted) {
      p.volume = e.clip.volume;
      p.muted = e.clip.muted;
      if (p.started) {
        audio.setVolume(_sound(p), p.volume, most: 2);
        audio.setMuted(_sound(p), p.muted);
      }
    }
    if (moment == null) {
      if (p.started || p.opening) {
        _close(p);
        p.opening = false;
        notifyListeners();
      }
      return;
    }
    p.gain = moment.gain;
    audio.setGain(p.soundId, moment.gain);
    if (p.opening) return;
    if (!p.started || p.index != moment.index) {
      unawaited(_start(p, moment.index, from: moment.time, paused: !playing));
      return;
    }
    if (playing && !p.playing) {
      p.playing = true;
      p.watch.start();
      unawaited(audio.play(_sound(p)));
      _startTimer();
    } else if (!playing && p.playing) {
      pause(e.id);
    }
    var fps = p.source?.fps ?? 25;
    var slack = playing ? 0.3 : 0.5 / (fps > 0 ? fps : 25);
    if ((_time(p) - moment.time).abs() > slack) {
      unawaited(_open(p, moment.time));
      audio.seek(p.soundId, moment.time);
    }
    notifyListeners();
  }

  /// tick shows whichever frame is due and moves on at the end of a range.
  @visibleForTesting
  void tick() {
    var changed = false;
    for (var p in _shows.values.toList()) {
      if (!p.started || !p.playing) continue;
      var at = _time(p);
      if (!p.timed && (at >= p.end - 0.02 || (p.ended && p.waiting == null))) {
        _next(p);
        changed = true;
        continue;
      }
      var due = p.waiting;
      if (due != null && due.time <= at) {
        p.shown?.image.dispose();
        p.shown = due;
        p.waiting = null;
        changed = true;
      }
      if (p.waiting == null) _pull(p);
      // The fades change the picture every tick while they run.
      if (p.element.clip.fadeIn > 0 || p.element.clip.fadeOut > 0) {
        changed = true;
      }
    }
    if (changed) notifyListeners();
    if (_shows.values.every((p) => !p.playing)) {
      _timer?.cancel();
      _timer = null;
    }
  }

  double _time(_Showing p) {
    if (p.playing) {
      var heard = audio.positionOf(p.soundId);
      if (heard != null) return heard;
    }
    return p.base + p.watch.elapsedMicroseconds / 1e6;
  }

  double _fade(_Showing p, double at) {
    var clip = p.element.clip;
    var alpha = 1.0;
    if (clip.fadeIn > 0) alpha = math.min(alpha, (at - p.start) / clip.fadeIn);
    if (clip.fadeOut > 0) alpha = math.min(alpha, (p.end - at) / clip.fadeOut);
    return alpha.clamp(0.0, 1.0);
  }

  /// _sound is the video's sound as the audio runtime knows sounds: an Audio
  /// element nobody sees, under the video's own name.
  AudioElement _sound(_Showing p) {
    var source = p.source;
    var clip = p.element.clip;
    return AudioElement(ElementBase(id: p.soundId),
        clip: MediaClip(
          playlist: [
            if (source != null && source.soundId.isNotEmpty)
              MediaSource(assetId: source.soundId, start: p.base, end: p.end),
          ],
          volume: p.volume,
          muted: p.muted,
          // A timed video's fades come from the playhead -- see cue -- and a
          // fade the sound ran by itself would be a second one on top.
          fadeIn: !p.timed && p.base <= p.start ? clip.fadeIn : 0,
          fadeOut: p.timed ? 0 : clip.fadeOut,
        ));
  }

  Future<void> _start(_Showing p, int index,
      {double? from, bool paused = false}) async {
    var list = p.element.clip.playlist;
    if (list.isEmpty) return;
    _close(p);
    p.index = index.clamp(0, list.length - 1);
    var source = p.source!;
    p.start = source.start;
    p.end = source.endOr(source.length > 0 ? source.length : 1e9);
    p.started = true;
    p.playing = !paused;
    notifyListeners();
    await _open(p, from ?? source.start);
    if (!p.started || _disposed) return;
    if (p.playing) {
      audio.stop(p.soundId);
      unawaited(audio.play(_sound(p)));
      _startTimer();
    }
  }

  /// _open starts reading frames from [at], closing whatever was reading.
  Future<void> _open(_Showing p, double at) async {
    p.opening = true;
    try {
      await _reopen(p, at);
    } finally {
      p.opening = false;
    }
  }

  Future<void> _reopen(_Showing p, double at) async {
    var generation = ++p.generation;
    p.reader?.close();
    p.reader = null;
    p.waiting?.image.dispose();
    p.waiting = null;
    p.pulling = false;
    p.ended = false;
    p.base = at;
    p.watch
      ..reset()
      ..stop();
    if (p.playing) p.watch.start();

    var source = p.source;
    if (source == null) return;
    var path = await locate(source.assetId);
    if (path == null || generation != p.generation || _disposed) return;
    var (w, h) = decodeSize(
        ui.Size(source.width.toDouble(), source.height.toDouble()),
        ui.Size(p.element.width, p.element.height));
    var fps = math.min(30.0, source.fps > 0 ? source.fps : 25.0);
    var reader =
        await frames.open(path, from: at, width: w, height: h, fps: fps);
    if (reader == null) return;
    if (generation != p.generation || _disposed) {
      reader.close();
      return;
    }
    p.reader = reader;
    _pull(p);
  }

  void _pull(_Showing p) {
    var reader = p.reader;
    if (reader == null || p.pulling || p.ended) return;
    p.pulling = true;
    var generation = p.generation;
    reader.next().then((frame) {
      if (generation != p.generation || _disposed) {
        frame?.image.dispose();
        return;
      }
      p.pulling = false;
      if (frame == null) {
        p.ended = true;
        return;
      }
      // The first frame goes straight up: it is the picture for a video that
      // has just been opened or moved, and waiting for its moment would leave
      // the old picture showing.
      if (p.shown == null || !p.playing) {
        p.shown?.image.dispose();
        p.shown = frame;
        notifyListeners();
        if (p.playing) _pull(p);
      } else {
        p.waiting = frame;
      }
    });
  }

  void _next(_Showing p) {
    var list = p.element.clip.playlist;
    switch (p.element.clip.loop) {
      case MediaLoop.one:
        unawaited(_start(p, p.index));
      case MediaLoop.all:
        unawaited(_start(p, (p.index + 1) % list.length));
      case MediaLoop.none:
        if (p.index + 1 < list.length) {
          unawaited(_start(p, p.index + 1));
        } else {
          // The last frame stays up: a video that snaps back to its poster
          // the moment it ends reads as having been interrupted.
          p.generation++;
          p.reader?.close();
          p.reader = null;
          p.playing = false;
          p.started = false;
          p.index = 0;
          p.watch.stop();
          audio.stop(p.soundId);
          notifyListeners();
        }
    }
  }

  void _close(_Showing p) {
    p.generation++;
    p.reader?.close();
    p.reader = null;
    p.shown?.image.dispose();
    p.shown = null;
    p.waiting?.image.dispose();
    p.waiting = null;
    p.pulling = false;
    p.started = false;
    p.playing = false;
    p.watch
      ..stop()
      ..reset();
    audio.stop(p.soundId);
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => tick());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (var p in _shows.values) {
      _close(p);
    }
    _shows.clear();
    super.dispose();
  }
}

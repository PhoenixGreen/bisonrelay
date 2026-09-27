import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter/foundation.dart';

// audio_runtime.dart decides what is playing: which file of a playlist, from
// where to where, how it fades, whether it goes round again, and which sounds
// survive the page being turned.
//
// Session state, like a running counter's value -- see CanvasController. The
// document says how a sound is meant to play; this says how it is playing for
// the reader in front of it, who may have muted it or dragged the volume down.
// None of that is written back into the document, so a published canvas opens
// the way its author set it up whatever the author last did to it.

/// AudioView is what the element should look like right now.
class AudioView {
  final bool playing;
  final bool muted;
  final double volume;

  const AudioView({
    this.playing = false,
    this.muted = false,
    this.volume = 0.8,
  });
}

/// _Playing is one element's sound.
class _Playing {
  AudioElement element;

  /// index is which file of the playlist is current.
  int index = 0;
  AudioVoice? voice;

  /// playing is false while paused, and once the list has run out.
  bool playing = false;
  bool muted;
  double volume;

  /// end is where the current file's range stops, in seconds into the file.
  double end = 0;

  /// fadingOut is set once the fade at the end of the range has begun, so it
  /// is begun once rather than on every tick after.
  bool fadingOut = false;

  /// generation goes up whenever what this should be playing changes, so an
  /// open that finishes after the reader has pressed stop does not start a
  /// sound nobody wants any more.
  int generation = 0;

  /// timed is a sound the playhead drives -- see AudioRuntime.cue -- which
  /// never moves itself on, and gain its fade at the moment the playhead is
  /// at.
  bool timed = false;
  double gain = 1;

  /// starting is set while a file is being opened, so the cues that arrive
  /// in the meantime do not open it again.
  bool starting = false;

  _Playing(this.element)
      : muted = element.clip.muted,
        volume = element.clip.volume;

  MediaClip get clip => element.clip;
  double get heard => muted ? 0 : volume * gain;
}

class AudioRuntime extends ChangeNotifier {
  final AudioEngine engine;

  /// locate is where a stored file is on disk, or null where it is not
  /// there -- see CanvasMedia.existingPath.
  final Future<String?> Function(String assetId) locate;

  AudioRuntime({required this.engine, required this.locate});

  final Map<String, _Playing> _sounds = {};
  final Map<String, AudioTrack> _tracks = {};
  Timer? _timer;
  bool _disposed = false;

  /// revision goes up with every change a speaker might show.
  int get revision => _revision;
  int _revision = 0;

  @override
  void notifyListeners() {
    _revision++;
    super.notifyListeners();
  }

  /// unavailable is set once the engine has said there is no sound to be
  /// had, so the settings can say so rather than the speaker doing nothing.
  bool get unavailable => _unavailable;
  bool _unavailable = false;

  /// view is how [e] is doing now.
  AudioView view(AudioElement e) {
    var p = _sounds[e.id];
    if (p == null) {
      return AudioView(muted: e.clip.muted, volume: e.clip.volume);
    }
    return AudioView(playing: p.playing, muted: p.muted, volume: p.volume);
  }

  bool isPlaying(String id) => _sounds[id]?.playing ?? false;

  /// playingIds is every element whose sound is going.
  Set<String> get playingIds => {
        for (var e in _sounds.entries)
          if (e.value.playing) e.key,
      };

  _Playing _for(AudioElement e) {
    var p = _sounds.putIfAbsent(e.id, () => _Playing(e));
    p.element = e;
    return p;
  }

  /// play starts [e], or carries it on from where it was paused.
  Future<void> play(AudioElement e) async {
    var p = _for(e);
    var voice = p.voice;
    if (voice != null && engine.alive(voice)) {
      if (!p.playing) {
        engine.pause(voice, false);
        p.playing = true;
        _startTimer();
        notifyListeners();
      }
      return;
    }
    await _start(p, p.index);
  }

  void pause(String id) {
    var p = _sounds[id];
    var voice = p?.voice;
    if (p == null || !p.playing) return;
    if (voice != null) engine.pause(voice, true);
    p.playing = false;
    notifyListeners();
  }

  /// toggle pauses [e] if it is going and plays it if not. The pause is done
  /// before this returns: a press that stops a sound one turn of the event
  /// loop late is a press that reads as missed.
  Future<void> toggle(AudioElement e) {
    if (!isPlaying(e.id)) return play(e);
    pause(e.id);
    return Future.value();
  }

  /// stop ends [id]'s sound and puts it back to the start of its list.
  void stop(String id) {
    var p = _sounds[id];
    if (p == null) return;
    p.generation++;
    _silence(p);
    p.index = 0;
    notifyListeners();
  }

  // ------------------------------------------------------------------------
  // The mixer
  // ------------------------------------------------------------------------

  /// _channels is what each mixer channel was last set to, by channel -- the
  /// element's id -- and _master the master. Kept so that setting the same
  /// mix again, which happens on every frame the playhead moves, costs a
  /// comparison rather than two dozen calls into the engine.
  final Map<String, ChannelSound> _channels = {};
  final Map<String, String> _channelSignature = {};
  MasterSound? _master;
  String _masterSignature = "";
  bool _started = false;

  /// setMix is the mixer as it stands: a strip for each channel, which of
  /// them are soloed, and the master.
  ///
  /// Solo is worked in here, as a level of nought for every channel that is
  /// not soloed while any is. It is the reader's, for listening, not the
  /// document's: an export plays every channel that is not muted.
  void setMix(Map<String, ChannelMix> channels,
      {Set<String> solo = const {}, required MasterMix master}) {
    var soloing = solo.any(channels.containsKey);
    for (var entry in channels.entries) {
      var mix = entry.value;
      var silent = mix.mute || (soloing && !solo.contains(entry.key));
      var (l, r) = silent ? (0.0, 0.0) : mix.gains;
      var sound = ChannelSound(
        left: l,
        right: r,
        eq: mix.eq.flat ? null : eqBandGains(mix.eq),
        comp: mix.comp.on ? mix.comp : null,
      );
      var signature =
          "$l|$r|${mix.eq.flat ? "" : mix.eq.toJson()}|${mix.comp.on ? mix.comp.toJson() : ""}";
      _channels[entry.key] = sound;
      if (_channelSignature[entry.key] == signature) continue;
      _channelSignature[entry.key] = signature;
      if (_started) engine.setChannel(entry.key, sound);
    }
    var sound = MasterSound(
      volume: dbToGain(master.gainDb),
      eq: master.eq.flat ? null : eqBandGains(master.eq),
      comp: master.comp.on ? master.comp : null,
      ceilingDb: master.limiter ? master.ceilingDb : null,
    );
    var signature = master.toJson().toString();
    _master = sound;
    if (signature != _masterSignature) {
      _masterSignature = signature;
      if (_started) engine.setMaster(sound);
    }
  }

  /// levels is how loud [channel] -- or the master -- is right now.
  (double, double) levels([String? channel]) =>
      _started ? engine.levels(channel) : (0, 0);

  /// _channelFor is the mixer channel a sound plays through, or null for
  /// none: the element's own, or for a video's sound, its video's.
  String? _channelFor(String soundId) {
    var key = soundId.startsWith("video:") ? soundId.substring(6) : soundId;
    return _channels.containsKey(key) ? key : null;
  }

  /// cue puts [e] where the playhead says it is: [moment] into its playlist,
  /// playing or held. Null is the playhead outside the sound's span, which is
  /// silence.
  ///
  /// The sound does not keep time of its own once it is cued. It is moved
  /// back into step whenever it has drifted more than a few hundredths of a
  /// second from where it should be, and never moved on to its next file by
  /// itself -- the next cue says which file it is on.
  void cue(AudioElement e, ClipMoment? moment, {required bool playing}) {
    var p = _for(e);
    p.timed = true;
    if (moment == null) {
      if (p.voice != null || p.playing || p.starting) {
        p.generation++;
        p.starting = false;
        _silence(p);
        notifyListeners();
      }
      return;
    }
    p.gain = moment.gain;
    if (p.starting) return;
    var voice = p.voice;
    var alive = voice != null && engine.alive(voice);
    if (!playing) {
      // Held where it is. Where it should be is worked out again the moment
      // the playhead moves, so there is no point seeking a held sound.
      if (alive && p.playing) {
        engine.pause(voice, true);
        p.playing = false;
        notifyListeners();
      }
      return;
    }
    if (!alive || p.index != moment.index) {
      unawaited(_start(p, moment.index, from: moment.time, fades: false));
      return;
    }
    if (!p.playing) {
      engine.pause(voice, false);
      p.playing = true;
      _startTimer();
      notifyListeners();
    }
    if ((engine.position(voice) - moment.time).abs() > 0.15) {
      engine.seek(voice, moment.time);
    }
    _heard(p);
  }

  /// setGain is a fade applied from outside -- a video's picture fading, and
  /// its sound with it.
  void setGain(String id, double gain) {
    var p = _sounds[id];
    if (p == null) return;
    p.gain = gain.clamp(0.0, 1.0);
    _heard(p);
  }

  /// positionOf is how far into its file [id]'s sound has got, in seconds,
  /// or null where nothing is sounding -- which is what a video keeps time
  /// by, so the picture follows the sound rather than drifting from it.
  double? positionOf(String id) {
    var voice = _sounds[id]?.voice;
    if (voice == null || !engine.alive(voice)) return null;
    return engine.position(voice);
  }

  /// seek moves [id]'s sound to [at] seconds into its file.
  void seek(String id, double at) {
    var p = _sounds[id];
    var voice = p?.voice;
    if (p == null || voice == null) return;
    engine.seek(voice, at);
    p.fadingOut = false;
    _heard(p);
  }

  void setVolume(AudioElement e, double volume) {
    var p = _for(e);
    p.volume = volume.clamp(0.0, 1.0);
    _heard(p);
    notifyListeners();
  }

  void setMuted(AudioElement e, bool muted) {
    var p = _for(e);
    p.muted = muted;
    _heard(p);
    notifyListeners();
  }

  void toggleMute(AudioElement e) => setMuted(e, !view(e).muted);

  /// keepOnly stops and forgets every sound [keep] says no to -- what turning
  /// the page does to everything that was on the page left behind.
  ///
  /// Forgotten rather than only stopped, so coming back to a page finds its
  /// speaker as the author left it rather than muted from last time.
  void keepOnly(bool Function(String id) keep) {
    var gone = [
      for (var id in _sounds.keys)
        if (!keep(id)) id,
    ];
    if (gone.isEmpty) return;
    for (var id in gone) {
      var p = _sounds.remove(id)!;
      p.generation++;
      _silence(p);
    }
    notifyListeners();
  }

  void stopAll() => keepOnly((_) => false);

  /// autoplay starts every sound in [elements] that says it starts by itself
  /// and is not already going.
  void autoplay(Iterable<AudioElement> elements) {
    for (var e in elements) {
      if (!e.clip.autoplay || e.clip.isEmpty) continue;
      var p = _sounds[e.id];
      if (p != null && (p.playing || p.voice != null)) continue;
      unawaited(play(e));
    }
  }

  /// measure is how long a stored file is, in seconds, or null where it
  /// cannot be opened. For writing the length down when a file is added.
  Future<double?> measure(String assetId) async {
    if (!await _ready()) return null;
    var track = await _track(assetId);
    return track == null ? null : engine.lengthOf(track);
  }

  /// tick moves every sound on: begins a fade that is due, and goes to the
  /// next file where one has finished. Run by a timer while anything plays;
  /// called directly by tests.
  @visibleForTesting
  void tick() {
    for (var p in _sounds.values.toList()) {
      var voice = p.voice;
      if (voice == null || !p.playing || p.timed) continue;
      if (!engine.alive(voice)) {
        _next(p);
        continue;
      }
      var at = engine.position(voice);
      var fade = p.clip.fadeOut;
      if (fade > 0 && !p.timed && !p.fadingOut && at >= p.end - fade) {
        p.fadingOut = true;
        engine.volume(voice, 0, fade: math.max(0.01, p.end - at));
      }
      // A little early rather than exactly on it: a tick lands anywhere
      // inside forty milliseconds, and the few samples past the range are
      // the start of whatever was cut off.
      if (at >= p.end - 0.02) _next(p);
    }
    if (_sounds.values.every((p) => !p.playing)) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<bool> _ready() async {
    var ok = await engine.start();
    // The mix set before there was a device to set it on, put on it now.
    if (ok && !_started) {
      _started = true;
      for (var entry in _channels.entries) {
        engine.setChannel(entry.key, entry.value);
      }
      if (_master case var m?) engine.setMaster(m);
    }
    if (!ok && !_unavailable) {
      _unavailable = true;
      notifyListeners();
    }
    return ok;
  }

  Future<AudioTrack?> _track(String assetId) async {
    var held = _tracks[assetId];
    if (held != null) return held;
    var path = await locate(assetId);
    if (path == null) return null;
    var track = await engine.open(path);
    if (track != null) _tracks[assetId] = track;
    return track;
  }

  /// _start plays file [index] of [p]'s list from the start of its range.
  Future<void> _start(_Playing p, int index,
      {double? from, bool fades = true}) async {
    var list = p.clip.playlist;
    if (list.isEmpty) return;
    var generation = ++p.generation;
    _silence(p);
    p.index = index.clamp(0, list.length - 1);
    p.starting = true;
    // Said to be playing from the press, not from when the file has opened:
    // a speaker that waits half a second to light up reads as a press that
    // was missed, and gets pressed again -- which is stop.
    p.playing = true;
    notifyListeners();

    if (!await _ready() || _disposed) {
      if (generation == p.generation) {
        p.playing = false;
        p.starting = false;
        notifyListeners();
      }
      return;
    }
    var source = list[p.index];
    var track = await _track(source.assetId);
    if (generation != p.generation || _disposed) return;
    p.starting = false;
    if (track == null) {
      // A file that is not there is skipped rather than ending the list: one
      // missing song is not a reason for the rest of the playlist not to play.
      if (p.index < list.length - 1) {
        await _start(p, p.index + 1);
      } else {
        p.playing = false;
        notifyListeners();
      }
      return;
    }

    p.end = source.endOr(engine.lengthOf(track));
    p.fadingOut = false;
    var fadeIn = fades ? p.clip.fadeIn : 0.0;
    var voice = engine.play(track,
        volume: fadeIn > 0 ? 0 : p.heard,
        at: from ?? source.start,
        channel: _channelFor(p.element.id));
    if (voice == null) {
      p.playing = false;
      notifyListeners();
      return;
    }
    if (fadeIn > 0) engine.volume(voice, p.heard, fade: fadeIn);
    p.voice = voice;
    if (!fades) p.fadingOut = false;
    _startTimer();
  }

  /// _next goes on to whatever the loop says follows the file just finished.
  void _next(_Playing p) {
    var list = p.clip.playlist;
    var voice = p.voice;
    if (voice != null) engine.stop(voice);
    p.voice = null;
    if (list.isEmpty) {
      p.playing = false;
      notifyListeners();
      return;
    }
    switch (p.clip.loop) {
      case MediaLoop.one:
        unawaited(_start(p, p.index));
      case MediaLoop.all:
        unawaited(_start(p, (p.index + 1) % list.length));
      case MediaLoop.none:
        if (p.index + 1 < list.length) {
          unawaited(_start(p, p.index + 1));
        } else {
          p.playing = false;
          p.index = 0;
          notifyListeners();
        }
    }
  }

  /// _heard puts the volume the reader chose onto the sound, unless a fade
  /// is under way -- moving the volume mid-fade would snap it back up.
  void _heard(_Playing p) {
    var voice = p.voice;
    if (voice == null || p.fadingOut) return;
    engine.volume(voice, p.heard);
  }

  void _silence(_Playing p) {
    var voice = p.voice;
    if (voice != null) engine.stop(voice);
    p.voice = null;
    p.playing = false;
    p.fadingOut = false;
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 40), (_) => tick());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (var p in _sounds.values) {
      _silence(p);
    }
    _sounds.clear();
    for (var track in _tracks.values) {
      engine.close(track);
    }
    _tracks.clear();
    super.dispose();
  }
}

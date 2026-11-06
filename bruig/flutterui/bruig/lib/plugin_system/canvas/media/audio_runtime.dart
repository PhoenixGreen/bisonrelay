import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:flutter/foundation.dart';

// audio_runtime.dart decides what is playing: which file of a playlist, from
// where to where, how it fades, whether it goes round again, and which sounds
// survive the page being turned.
//
// Session state: the document says how a sound is meant to play; this says
// how it is playing for this reader, who may have muted it or turned it
// down. None of that is written back, so a published canvas opens the way
// its author set it up.

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

  /// sent is the volume last put on the voice, so the same one is not put
  /// on it again every frame -- see AudioRuntime._heard.
  double? sent;

  _Playing(this.element)
      : muted = element.clip.muted,
        volume = element.clip.volume;

  MediaClip get clip => element.clip;
  double get heard => muted ? 0 : volume * gain;
}

/// declickSeconds is how long a sound started part way through takes to
/// rise to its level: too short to hear as a fade, long enough not to click.
const double declickSeconds = 0.015;

/// glideSeconds is how long a sound on the timeline takes to reach a new
/// volume: a fade set outright every frame is a staircase, heard as a buzz,
/// and cuts short the rise a sound starts with.
const double glideSeconds = 0.03;

/// driftSeconds is how far a sound on the timeline may be from where the
/// playhead says before it is moved there. Positions are reported in steps
/// of the buffer, and moving a playing sound is a heard jump.
const double driftSeconds = 0.3;

/// AudioRuntime plays the open canvas's sounds: see the file comment.
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

  AudioTrack? _click;
  AudioVoice? _clickVoice;
  (double, int)? _clickMetre;
  int _clickGeneration = 0;

  /// metronomeUnavailable is set once the engine has said it has no
  /// metronome -- SoLoud's buses -- so the button can say why it is silent.
  bool get metronomeUnavailable => _noClick;
  bool _noClick = false;

  /// metronome is the click as it should be now: sounding from [at] seconds,
  /// a beat every [secondsPerBeat] in bars of [beatsPerBar], or -- not [on]
  /// -- silent. Called whenever the playhead moves, as cue is: a click that
  /// has drifted from [at] by more than a little is moved back to it, so a
  /// loop's jump back or a seek takes the click with it.
  void metronome(
      {required bool on,
      double at = 0,
      double secondsPerBeat = 0.5,
      int beatsPerBar = 4}) {
    if (!on || _disposed) {
      _clickGeneration++;
      if (_clickVoice case var v?) engine.stop(v);
      _clickVoice = null;
      return;
    }
    var metre = (secondsPerBeat, beatsPerBar);
    if (_clickMetre != metre) {
      if (_clickVoice case var v?) engine.stop(v);
      _clickVoice = null;
      _click = null;
      _clickMetre = metre;
    }
    // Counted from the start of the timeline: a beat falls where the ruler
    // says it does, wherever playing began.
    if (_clickVoice case var v? when engine.alive(v)) {
      if ((engine.position(v) - at).abs() > 0.05) engine.seek(v, at);
      return;
    }
    var generation = ++_clickGeneration;
    () async {
      if (!await _ready() || generation != _clickGeneration) return;
      var track = _click ??= engine.metronome(secondsPerBeat, beatsPerBar);
      if (track == null) {
        if (!_noClick) {
          _noClick = true;
          notifyListeners();
        }
        return;
      }
      _clickVoice = engine.play(track, volume: 1, at: at);
    }();
  }

  /// noteOn sounds [key] on channel [channel]'s instrument, live -- the
  /// bank read first, where the part is played on it and it is there.
  Future<void> noteOn(
      String channel, InstrumentPart part, int key, int velocity) async {
    var down = _down.putIfAbsent(channel, () => {})..add(key);
    if (!await _ready()) return;
    var font =
        part.sound == InstrumentSound.bank ? await loadSoundBank() : null;
    // Let go while the bank was being read: not started at all, or it
    // would never be stopped.
    if (_disposed || !down.contains(key)) return;
    engine.noteOn(channel, part, key, velocity, font: font);
  }

  void noteOff(String channel, int key) {
    _down[channel]?.remove(key);
    if (_started) engine.noteOff(channel, key);
  }

  /// control sets a controller of channel [channel]'s instrument, live.
  void control(String channel, MidiControl control, double value) {
    if (_started) engine.control(channel, control, value);
  }

  /// _down is the keys held on each channel, live.
  final Map<String, Set<int>> _down = {};

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
  /// before this returns, so the press never reads as missed.
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

  /// _channels is what each mixer channel was last set to, and _master the
  /// master, so the same mix set again every frame costs a comparison
  /// rather than calls into the engine.
  final Map<String, ChannelSound> _channels = {};

  /// _routes is the channel each sound plays through -- see setMix.
  final Map<String, String> _routes = {};

  /// strips and routes are the mix as last set, for tests.
  @visibleForTesting
  Set<String> get strips => _channels.keys.toSet();
  @visibleForTesting
  Map<String, String> get routes => Map.unmodifiable(_routes);
  final Map<String, String> _channelSignature = {};

  /// _mixOwners is which runtime last set each engine's mix.
  static final Expando<AudioRuntime> _mixOwners = Expando();
  MasterSound? _master;
  String _masterSignature = "";
  bool _started = false;

  /// setMix is the mixer as it stands: a strip for each channel, which of
  /// them are soloed, and the master.
  ///
  /// Solo is worked in here, as nought for every channel not soloed while
  /// any is. It is for listening only: an export plays every unmuted channel.
  ///
  /// [channels] is keyed by mixer channel; [routes] maps a sound's element
  /// id to its channel. One strip per channel, not per sound: each strip is
  /// an always-playing bus voice. A sound with no route plays through the
  /// strip of its own id, if there is one.
  void setMix(Map<String, ChannelMix> channels,
      {Map<String, String> routes = const {},
      Set<String> solo = const {},
      required MasterMix master,
      List<ReturnChannel> returns = const [],
      ChannelMix sceneBus = const ChannelMix(),
      Set<String> sceneChannels = const {},
      SpeakerLayout speakers = SpeakerLayout.stereo,
      SpeakerGroup hear = SpeakerGroup.all,
      Map<String, Heard> placements = const {}}) {
    // Another runtime on the same engine -- a canvas previewed from the
    // Files -- has set the mix since: all of this one's is sent again, not
    // only what changed, or it would play through the other's.
    if (_mixOwners[engine] != this) {
      _mixOwners[engine] = this;
      _channelSignature.clear();
      _masterSignature = "";
      _returnsKey = null;
      _sceneKey = null;
      _placements.clear();
      if (_started) engine.setSpeakers(speakers);
      if (_started) engine.setHear(hear);
    }
    if (speakers != _speakers) {
      _speakers = speakers;
      if (_started) engine.setSpeakers(speakers);
    }
    if (hear != _hear) {
      _hear = hear;
      if (_started) engine.setHear(hear);
    }
    // Where each placed sound's channel is heard from, on this frame; a
    // channel no longer placed goes back to its own pan.
    for (var key in [..._placements.keys]) {
      if (placements.containsKey(key)) continue;
      _placements.remove(key);
      if (_started) engine.setPlacement(key, null);
    }
    for (var e in placements.entries) {
      if (_placements[e.key] == e.value) continue;
      _placements[e.key] = e.value;
      if (_started) engine.setPlacement(e.key, e.value);
    }
    // The scene's bus, and which channels are heard through it.
    var sceneKey =
        "${sceneBus.toJson()}|${(sceneChannels.toList()..sort()).join("|")}";
    _sceneBus = sceneBus;
    _sceneChannels = sceneChannels;
    if (sceneKey != _sceneKey) {
      _sceneKey = sceneKey;
      if (_started) engine.setScene(sceneBus, sceneChannels);
    }
    var returnsKey = [for (var r in returns) r.toKey()].join("|");
    _returns = returns;
    if (returnsKey != _returnsKey) {
      _returnsKey = returnsKey;
      if (_started) engine.setReturns(returns);
    }
    _routes
      ..clear()
      ..addAll(routes);
    var soloing = solo.any(channels.containsKey);
    // Channels gone from the canvas are let go of: kept, their strips and
    // buses ran for as long as the engine lived.
    for (var key in [..._channels.keys]) {
      if (channels.containsKey(key)) continue;
      _channels.remove(key);
      _channelSignature.remove(key);
      if (_started) engine.removeChannel(key);
    }
    for (var entry in channels.entries) {
      var mix = entry.value;
      var silent = mix.mute || (soloing && !solo.contains(entry.key));
      var (l, r) = silent ? (0.0, 0.0) : mix.gains;
      var sound = ChannelSound(
        left: l,
        right: r,
        eq: mix.eq.flat ? null : eqBandGains(mix.eq),
        comp: mix.comp.on ? mix.comp : null,
        compFirst: mix.compFirst,
        mix: silent ? mix.copyWith(mute: true) : mix,
      );
      // The whole strip: a send, a surround pan or the LFE changed alone is
      // a change the engine has to hear of too.
      var signature = "$l|$r|$silent|${mix.toJson()}";
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
      compFirst: master.compFirst,
      // Never brought to a target while playing: that is measured over the
      // whole mix, which the editor has not heard yet.
      mix: master.copyWith(normalise: false),
    );
    var signature = master.toJson().toString();
    _master = sound;
    if (signature != _masterSignature) {
      _masterSignature = signature;
      if (_started) engine.setMaster(sound);
    }
  }

  List<ReturnChannel> _returns = const [];
  String? _returnsKey;
  ChannelMix _sceneBus = const ChannelMix();
  Set<String> _sceneChannels = const {};
  String? _sceneKey;
  SpeakerLayout _speakers = SpeakerLayout.stereo;
  SpeakerGroup _hear = SpeakerGroup.all;
  final Map<String, Heard> _placements = {};

  /// placements are where each placed channel is heard from now, for tests
  /// and the strip's own display.
  Map<String, Heard> get placements => Map.unmodifiable(_placements);

  /// levels is how loud [channel] -- or the master -- is right now.
  (double, double) levels([String? channel]) =>
      _started ? engine.levels(channel) : (0, 0);

  /// deviceLevels is [channel]'s levels at each step of its strip -- see
  /// AudioEngine.deviceLevels.
  List<(double, double)> deviceLevels(String channel) =>
      _started ? engine.deviceLevels(channel) : const [];

  /// reduction is [channel]'s compressor's reduction now, in decibels.
  double reduction(String channel) => _started ? engine.reduction(channel) : 0;

  /// spectrum is what [channel], or the master, is playing now -- see
  /// AudioEngine.spectrum.
  Float32List? spectrum([String? channel]) =>
      _started ? engine.spectrum(channel) : null;

  /// pitch is what a tuner on [channel] hears now -- see AudioEngine.pitch.
  PitchReading? pitch([String? channel]) =>
      _started ? engine.pitch(channel) : null;

  /// wave, loudness and resetLoudness: see AudioEngine's.
  Wave? wave(DeviceKind kind, [String? channel]) =>
      _started ? engine.wave(kind, channel) : null;

  LoudnessReading? loudness([String? channel]) =>
      _started ? engine.loudness(channel) : null;

  void resetLoudness([String? channel]) {
    if (_started) engine.resetLoudness(channel);
  }

  /// _channelFor is the mixer channel a sound plays through, or null for
  /// none: the element's own, or for a video's sound, its video's.
  String? _channelFor(String soundId) {
    var id = soundId.startsWith("video:") ? soundId.substring(6) : soundId;
    var key = _routes[id] ?? id;
    return _channels.containsKey(key) ? key : null;
  }

  /// cue puts [e] where the playhead says it is: [moment] into its playlist,
  /// playing or held. Null is the playhead outside the sound's span, which is
  /// silence.
  ///
  /// A cued sound keeps no time of its own: it is moved back into step once
  /// it drifts past [driftSeconds], and never moves on to its next file by
  /// itself; the next cue says which file it is on.
  void cue(AudioElement e, ClipMoment? moment, {required bool playing}) {
    var p = _for(e);
    p.timed = true;
    // Read on every cue, so a clip's volume line is followed.
    p.volume = e.clip.volume;
    p.muted = e.clip.muted;
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
      // Brought down and stopped, not paused: a pause cuts mid-swing and
      // clicks. It is started afresh, rising from nothing, on the next move.
      if (alive && p.playing) {
        p.generation++;
        _silence(p);
        notifyListeners();
      }
      return;
    }
    if (!alive || p.index != moment.index) {
      unawaited(_start(p, moment.index,
          from: moment.time, fades: false, asked: Stopwatch()..start()));
      return;
    }
    if (!p.playing) {
      // Moved into place and silenced before it is heard again, or a moment
      // of the old place at the old level is heard as a spike.
      if ((engine.position(voice) - moment.time).abs() > 0.02) {
        engine.seek(voice, moment.time);
      }
      engine.volume(voice, 0);
      engine.pause(voice, false);
      p.sent = p.heard;
      engine.volume(voice, p.heard, fade: declickSeconds);
      p.playing = true;
      _startTimer();
      notifyListeners();
      return;
    }
    if ((engine.position(voice) - moment.time).abs() > driftSeconds) {
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

  /// indexOf is which file of [id]'s playlist is sounding, or null where
  /// none is.
  int? indexOf(String id) {
    var p = _sounds[id];
    var voice = p?.voice;
    if (p == null || voice == null || !engine.alive(voice)) return null;
    return p.index;
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

  /// setVolume sets how loud [e] is, up to [most]: full for a reader's
  /// speaker, and over it for a clip on the timeline turned up there.
  void setVolume(AudioElement e, double volume, {double most = 1}) {
    var p = _for(e);
    p.volume = volume.clamp(0.0, most);
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
        p.sent = 0;
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
      engine.setReturns(_returns);
      engine.setScene(_sceneBus, _sceneChannels);
      engine.setSpeakers(_speakers);
      engine.setHear(_hear);
      for (var e in _placements.entries) {
        engine.setPlacement(e.key, e.value);
      }
    }
    if (!ok && !_unavailable) {
      _unavailable = true;
      notifyListeners();
    }
    return ok;
  }

  /// ready starts the engine, as a first play does: false where there is no
  /// sound to be had.
  Future<bool> ready() => _ready();

  /// trackOf is the stored file [assetId], opened -- once, and kept -- or
  /// null where it is not there.
  Future<AudioTrack?> trackOf(String assetId) => _track(assetId);

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
  /// [asked] times how long the file took to open, so a sound on the
  /// timeline starts where the playhead has got to, not behind it.
  Future<void> _start(_Playing p, int index,
      {double? from, bool fades = true, Stopwatch? asked}) async {
    var list = p.clip.playlist;
    if (list.isEmpty) return;
    var generation = ++p.generation;
    _silence(p);
    p.index = index.clamp(0, list.length - 1);
    p.starting = true;
    // Playing from the press, not from the open: a speaker slow to light
    // up gets pressed again, which is stop.
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
      // A missing file is skipped rather than ending the list.
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
    if (from != null && asked != null && p.timed) {
      from = math.min(from + asked.elapsedMicroseconds / 1e6, p.end);
    }
    var fadeIn = fades ? p.clip.fadeIn : 0.0;
    // Started part way through, it rises over a few milliseconds: a wave
    // cut into mid-swing clicks.
    var at = from ?? source.start;
    if (fadeIn <= 0 && at > source.start + 0.001) fadeIn = declickSeconds;
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
    p.sent = p.heard;
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
    p.sent = null;
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
  ///
  /// Only when it has changed, since it is asked every frame and setting it
  /// again cuts off the rise a sound starts with; on the timeline by a
  /// short glide (see glideSeconds).
  void _heard(_Playing p) {
    var voice = p.voice;
    if (voice == null || p.fadingOut) return;
    var to = p.heard;
    if (p.sent case var was? when (was - to).abs() < 0.0005) return;
    p.sent = to;
    engine.volume(voice, to, fade: p.timed ? glideSeconds : 0);
  }

  /// _silence stops [p]'s voice: brought down over a few milliseconds where
  /// it is sounding, since stopped outright it clicks. [softly] off is for
  /// going away altogether, when there is no time for the fade.
  void _silence(_Playing p, {bool softly = true}) {
    var voice = p.voice;
    if (voice != null) {
      softly && engine.alive(voice)
          ? engine.stopSoftly(voice, declickSeconds)
          : engine.stop(voice);
    }
    p.voice = null;
    p.sent = null;
    p.playing = false;
    p.fadingOut = false;
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 40), (_) => tick());
  }

  @override
  void dispose() {
    metronome(on: false);
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    // Its strips go with it, from an engine others go on using: left, they
    // went on being mixed. Whoever sets the mix next sends theirs whole.
    if (_started) {
      for (var key in _channels.keys) {
        engine.removeChannel(key);
      }
    }
    if (_mixOwners[engine] == this) _mixOwners[engine] = null;
    for (var p in _sounds.values) {
      _silence(p, softly: false);
    }
    _sounds.clear();
    for (var track in _tracks.values) {
      engine.close(track);
    }
    _tracks.clear();
    super.dispose();
  }
}

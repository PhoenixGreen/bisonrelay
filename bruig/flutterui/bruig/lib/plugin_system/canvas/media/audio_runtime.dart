import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
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

// audio_runtime.dart decides what is playing: which playlist file, what
// range, fades, loops, and which sounds survive a page turn. Session state
// only: a reader's mutes are never written back, so a canvas opens as its
// author set it.

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

class _Playing {
  AudioElement element;

  /// index is which file of the playlist is current.
  int index = 0;
  AudioVoice? voice;

  /// routedTo is the channel [voice] was sent through: see setMix, which
  /// puts it through another once that is known.
  String? routedTo;

  /// playing is false while paused and once the list has run out.
  bool playing = false;
  bool muted;
  double volume;

  /// end is where the current file's range stops, in seconds into the file.
  double end = 0;

  /// fadingOut is set once the end-of-range fade has begun, so it is begun
  /// only once.
  bool fadingOut = false;

  /// generation goes up whenever what this should play changes, so an open
  /// that finishes after the reader pressed stop starts nothing.
  int generation = 0;

  /// missing is when file [missingIndex] was last found missing: asked for
  /// again only after a while, not every frame, in case it has come.
  Stopwatch? missing;
  int missingIndex = -1;

  /// timed is a sound the playhead drives (see AudioRuntime.cue): it never
  /// moves itself on, and gain is its fade at the playhead.
  bool timed = false;
  double gain = 1;

  /// starting is set while a file is being opened, so the cues that arrive
  /// in the meantime do not open it again.
  bool starting = false;

  /// sent is the volume last put on the voice, so it is not set again every
  /// frame (see AudioRuntime._heard).
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

/// glideSeconds is how long a timeline sound takes to reach a new volume: a
/// fade set outright every frame is a staircase, heard as a buzz.
const double glideSeconds = 0.03;

/// driftSeconds is how far a timeline sound may stray from the playhead
/// before it is moved. Positions come in buffer steps, and a move is heard.
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

  /// unavailable is set once the engine has said there is no sound, so the
  /// settings can say so.
  bool get unavailable => _unavailable;
  bool _unavailable = false;

  /// _clicks are each click sounding or ready, by its [metronome] key: the
  /// canvas's, and each Metronome element's of its own.
  final Map<String, _Click> _clicks = {};

  /// metronome sets click [key] ("canvas", or a Metronome element's): from
  /// [at] seconds, a beat every [secondsPerBeat], [beatsPerBar] to a bar, or
  /// silent. Called as the playhead moves; a drifted click is moved back.
  void metronome(
      {required bool on,
      double at = 0,
      double secondsPerBeat = 0.5,
      int beatsPerBar = 4,
      String key = "canvas"}) {
    var click = _clicks[key] ??= _Click();
    if (!on || _disposed) {
      click.generation++;
      if (click.voice case var v?) engine.stop(v);
      click.voice = null;
      return;
    }
    var metre = (secondsPerBeat, beatsPerBar);
    if (click.metre != metre) {
      if (click.voice case var v?) engine.stop(v);
      click.voice = null;
      click.track = null;
      click.metre = metre;
    }
    // Counted from the start of the timeline: a beat falls where the ruler
    // says it does, wherever playing began.
    if (click.voice case var v? when engine.alive(v)) {
      if ((engine.position(v) - at).abs() > 0.05) engine.seek(v, at);
      return;
    }
    var generation = ++click.generation;
    () async {
      if (!await _ready() || generation != click.generation) return;
      var track = click.track ??= engine.metronome(secondsPerBeat, beatsPerBar);
      click.voice = engine.play(track, volume: 1, at: math.max(0, at));
    }();
  }

  /// noteOn sounds [key] on channel [channel]'s instrument, live, reading
  /// the bank first where the part needs it.
  Future<void> noteOn(
      String channel, InstrumentPart part, int key, int velocity) async {
    var down = _down.putIfAbsent(channel, () => {})..add(key);
    var press = _presses[(channel, key)] = ++_pressed;
    // Nothing awaited between the key and the sound, unless a bank is read.
    var kit = part.sound == InstrumentSound.slices ? part.slices : null;
    if (_started && !_disposed) {
      var bank = part.sound == InstrumentSound.bank;
      var ready = kit != null
          ? loadedSliceFont(kit)
          : bank
              ? loadedSoundBank
              : null;
      if ((!bank && kit == null) || ready != null) {
        engine.noteOn(channel, part, key, velocity, font: ready);
        return;
      }
    }
    if (!await _ready()) return;
    var font = kit != null
        ? await sliceFontOf(kit)
        : part.sound == InstrumentSound.bank
            ? await loadSoundBank()
            : null;
    // Let go while the bank was read: not started, or it would never stop.
    // Pressed again meanwhile, only that later press is heard.
    if (_disposed || !down.contains(key) || _presses[(channel, key)] != press) {
      return;
    }
    engine.noteOn(channel, part, key, velocity, font: font);
  }

  /// _presses is each key's latest press, numbered by [_pressed].
  final Map<(String, int), int> _presses = {};
  int _pressed = 0;

  void noteOff(String channel, int key) {
    _down[channel]?.remove(key);
    if (_started) engine.noteOff(channel, key);
  }

  /// control sets a controller of channel [channel]'s instrument, live.
  /// Moved before the engine has started, it is kept and set at the start.
  void control(String channel, MidiControl control, double value) {
    if (_started) {
      engine.control(channel, control, value);
      return;
    }
    _controlsWaiting[(channel, control)] = value;
    _ready();
  }

  /// livePatch sets the synth patch channel [channel] plays, live.
  void livePatch(String channel, SynthPatch patch) {
    if (_started) engine.livePatch(channel, patch);
  }

  /// _controlsWaiting are the controllers moved before the engine started.
  final Map<(String, MidiControl), double> _controlsWaiting = {};

  /// _down is the keys held on each channel, live.
  final Map<String, Set<int>> _down = {};

  AudioView view(AudioElement e) {
    var p = _sounds[e.id];
    if (p == null) {
      return AudioView(muted: e.clip.muted, volume: e.clip.volume);
    }
    return AudioView(playing: p.playing, muted: p.muted, volume: p.volume);
  }

  bool isPlaying(String id) => _sounds[id]?.playing ?? false;

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

  /// toggle pauses or plays [e]. The pause is done before this returns, so
  /// the press never reads as missed.
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

  // ---- The mixer ---------------------------------------------------------

  /// _channels and _master are the mix last set, so setting the same mix
  /// every frame costs a comparison, not engine calls.
  final Map<String, ChannelMix> _channels = {};

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
  MasterMix? _master;
  String _masterSignature = "";
  bool _started = false;

  /// setMix is the mixer: a strip per channel, the soloes, and the master.
  /// Solo is listening only (an export plays every unmuted channel).
  /// [routes] maps element id to channel; a sound with no route uses the
  /// strip of its own id. Each strip is a bus voice.
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
    // Another runtime on the same engine (a canvas previewed from Files)
    // set the mix since: send all of this one's, or it plays through theirs.
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
    // Where each placed channel is heard from; an unplaced one goes back to
    // its own pan.
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
    var sceneKey = "${_written(sceneBus, sceneBus.toJson)}|"
        "${(sceneChannels.toList()..sort()).join("|")}";
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
    // Channels gone from the canvas are let go of, or their strips and
    // buses run for as long as the engine lives.
    for (var key in [..._channels.keys]) {
      if (channels.containsKey(key)) continue;
      _channels.remove(key);
      _channelSignature.remove(key);
      if (_started) engine.removeChannel(key);
    }
    for (var entry in channels.entries) {
      var mix = entry.value;
      var silent = mix.mute || (soloing && !solo.contains(entry.key));
      var sound = silent ? mix.copyWith(mute: true) : mix;
      // The whole strip: a send, surround pan or LFE change alone counts.
      var signature = "$silent|${_written(mix, mix.toJson)}";
      _channels[entry.key] = sound;
      if (_channelSignature[entry.key] == signature) continue;
      _channelSignature[entry.key] = signature;
      if (_started) engine.setChannel(entry.key, sound);
    }
    // Never normalised while playing: that is measured over the whole mix.
    var sound = master.copyWith(normalise: false);
    var signature = _written(master, master.toJson);
    _master = sound;
    if (signature != _masterSignature) {
      _masterSignature = signature;
      if (_started) engine.setMaster(sound);
    }
    // A sound started before its channel was known goes through the chain
    // now, not only after it is stopped and started again.
    if (_started) {
      for (var p in _sounds.values) {
        var voice = p.voice;
        if (voice == null) continue;
        var through = _channelFor(p.element.id);
        if (through == p.routedTo) continue;
        engine.route(voice, through);
        p.routedTo = through;
      }
    }
  }

  /// _written is a strip, bus or master written out, kept per object: mixes
  /// are immutable, and setMix is called on every edit and frame, with the
  /// same strips more often than not.
  static final _writtenOut = Expando<String>("mixWritten");
  static String _written(Object mix, Map<String, dynamic> Function() json) =>
      _writtenOut[mix] ??= "${json()}";

  List<ReturnChannel> _returns = const [];
  String? _returnsKey;
  ChannelMix _sceneBus = const ChannelMix();
  Set<String> _sceneChannels = const {};
  String? _sceneKey;
  SpeakerLayout _speakers = SpeakerLayout.stereo;
  SpeakerGroup _hear = SpeakerGroup.all;
  final Map<String, Heard> _placements = {};

  /// placements are where each placed channel is heard from now.
  Map<String, Heard> get placements => Map.unmodifiable(_placements);

  /// levels is how loud [channel] -- or the master -- is right now.
  (double, double) levels([String? channel]) =>
      _started ? engine.levels(channel) : (0, 0);

  /// deviceLevels: see AudioEngine.deviceLevels.
  List<(double, double)> deviceLevels(String channel) =>
      _started ? engine.deviceLevels(channel) : const [];

  /// deviceScope and stopScope: see AudioEngine's.
  ScopeReading? deviceScope(String channel, String id) =>
      _started ? engine.deviceScope(channel, id) : null;

  void stopScope(String channel, String id) {
    if (_started) engine.stopScope(channel, id);
  }

  void listenAt(String channel, int? step) {
    if (_started) engine.listenAt(channel, step);
  }

  /// reduction is [channel]'s compressor's reduction now, in decibels.
  double reduction(String channel) => _started ? engine.reduction(channel) : 0;

  /// spectrum: see AudioEngine.spectrum.
  Float32List? spectrum([String? channel]) =>
      _started ? engine.spectrum(channel) : null;

  /// pitch: see AudioEngine.pitch.
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

  /// cue puts [e] where the playhead says: [moment] into its playlist, or
  /// silent with null. It keeps no time of its own: moved back past
  /// [driftSeconds], and told its file by the next cue.
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
      // Faded and stopped, not paused, as a pause clicks. It restarts rising
      // from nothing on the next move.
      if (alive && p.playing) {
        p.generation++;
        _silence(p);
        notifyListeners();
      }
      return;
    }
    if (!alive || p.index != moment.index) {
      if (p.missing case var since?
          when p.missingIndex == moment.index &&
              since.elapsed < const Duration(seconds: 2)) {
        return;
      }
      unawaited(_start(p, moment.index,
          from: moment.time, fades: false, asked: Stopwatch()..start()));
      return;
    }
    if (!p.playing) {
      // Moved and silenced before it is heard again, or the old place at the
      // old level is heard as a spike.
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

  /// setGain is a fade from outside, as a video's sound follows its picture.
  void setGain(String id, double gain) {
    var p = _sounds[id];
    if (p == null) return;
    p.gain = gain.clamp(0.0, 1.0);
    _heard(p);
  }

  /// positionOf is how far into its file [id]'s sound is, in seconds, or
  /// null: a video keeps time by it, so the picture follows the sound.
  double? positionOf(String id) {
    var voice = _sounds[id]?.voice;
    if (voice == null || !engine.alive(voice)) return null;
    return engine.position(voice);
  }

  /// indexOf is which file of [id]'s playlist is sounding, or null.
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

  /// setVolume sets how loud [e] is, up to [most]: over full for a clip
  /// turned up on the timeline.
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

  /// keepOnly stops and forgets every sound [keep] refuses, as a page turn
  /// does, so a page revisited plays as its author left it.
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

  /// autoplay starts each sound in [elements] that starts by itself and is
  /// not already going.
  void autoplay(Iterable<AudioElement> elements) {
    for (var e in elements) {
      if (!e.clip.autoplay || e.clip.isEmpty) continue;
      var p = _sounds[e.id];
      if (p != null && (p.playing || p.voice != null)) continue;
      unawaited(play(e));
    }
  }

  /// measure is how long a stored file is, in seconds, or null where it
  /// cannot be opened.
  Future<double?> measure(String assetId) async {
    if (!await _ready()) return null;
    var track = await _track(assetId);
    return track == null ? null : engine.lengthOf(track);
  }

  /// tick moves every sound on: starts due fades and next files. Run by a
  /// timer while anything plays.
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
      // A little early: a tick lands anywhere within 40 ms, and samples past
      // the range belong to whatever was cut off.
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
      for (var MapEntry(key: (channel, control), value: v)
          in _controlsWaiting.entries) {
        engine.control(channel, control, v);
      }
      _controlsWaiting.clear();
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

  /// ready starts the engine: false where there is no sound to be had.
  Future<bool> ready() => _ready();

  /// trackOf is stored file [assetId], opened once and kept, or null.
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
  /// [asked] times the open, so a timeline sound starts at the playhead.
  Future<void> _start(_Playing p, int index,
      {double? from, bool fades = true, Stopwatch? asked}) async {
    var list = p.clip.playlist;
    if (list.isEmpty) return;
    var generation = ++p.generation;
    _silence(p);
    p.index = index.clamp(0, list.length - 1);
    p.starting = true;
    // Playing from the press, not the open, or a slow speaker is pressed
    // again, which stops it.
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
        p.missing = Stopwatch()..start();
        p.missingIndex = p.index;
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
    // Started part way, it rises over a few milliseconds: a wave cut
    // mid-swing clicks.
    var at = from ?? source.start;
    if (fadeIn <= 0 && at > source.start + 0.001) fadeIn = declickSeconds;
    var through = _channelFor(p.element.id);
    var voice = engine.play(track,
        volume: fadeIn > 0 ? 0 : p.heard,
        at: from ?? source.start,
        channel: through);
    p.routedTo = through;
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

  /// _heard puts the reader's volume on the sound unless fading, and only
  /// when changed, as setting it cuts a sound's rise (see glideSeconds).
  void _heard(_Playing p) {
    var voice = p.voice;
    if (voice == null || p.fadingOut) return;
    var to = p.heard;
    if (p.sent case var was? when (was - to).abs() < 0.0005) return;
    p.sent = to;
    engine.volume(voice, to, fade: p.timed ? glideSeconds : 0);
  }

  /// _silence stops [p]'s voice, faded over a few milliseconds where it is
  /// sounding. [softly] off is for going away when there is no time to fade.
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
    for (var key in [..._clicks.keys]) {
      metronome(on: false, key: key);
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    // Its strips go too, or the shared engine goes on mixing them. Whoever
    // sets the mix next sends theirs whole.
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

/// _Click is one click: track, voice, metre, and latest start.
class _Click {
  AudioTrack? track;
  AudioVoice? voice;
  (double, int)? metre;
  int generation = 0;
}

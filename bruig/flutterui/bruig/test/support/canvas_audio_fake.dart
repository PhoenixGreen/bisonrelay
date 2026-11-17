import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart'
    show ChannelMix, MasterMix;
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'package:path/path.dart' as path;

// canvas_audio_fake.dart is a sound card for tests: an engine that plays
// nothing, and whose voices sit at whatever position the test puts them.
//
// Files are known by their base name, so a test can hand it either an asset
// id or the full path the media store resolves one to.

class FakeTrack extends AudioTrack {
  final String path;
  final double length;
  FakeTrack(this.path, this.length);
}

class FakeVoice extends AudioVoice {
  final FakeTrack track;
  double at;
  double volume;
  bool paused = false;
  bool alive = true;

  /// fades is every volume change asked for, as (to, over seconds).
  final List<(double, double)> fades = [];
  FakeVoice(this.track, this.at, this.volume);
}

class FakeEngine implements AudioEngine {
  final Map<String, double> lengths;
  bool works = true;
  final List<FakeVoice> voices = [];
  FakeEngine(this.lengths);

  FakeVoice get last => voices.last;

  /// starts is how many times anything asked for the sound device, so a
  /// test can say that a canvas with no sound on it never did.
  int starts = 0;

  @override
  Future<bool> start() async {
    starts++;
    return works;
  }

  @override
  Future<AudioTrack?> open(String file) async {
    var name = path.basename(file);
    var length = lengths[name];
    return length == null ? null : FakeTrack(name, length);
  }

  @override
  double lengthOf(AudioTrack track) => (track as FakeTrack).length;

  /// clicks is every metronome asked for, as (seconds a beat, beats a bar).
  final List<(double, int)> clicks = [];

  @override
  AudioTrack metronome(double secondsPerBeat, int beatsPerBar) {
    clicks.add((secondsPerBeat, beatsPerBar));
    return FakeTrack("metronome", 24 * 3600);
  }

  /// channels is every mixer channel as last set, master the master, and
  /// onChannel which channel each voice was played through.
  final Map<String, ChannelMix> channels = {};
  MasterMix? master;
  final Map<FakeVoice, String?> onChannel = {};

  @override
  void setChannel(String key, ChannelMix mix) => channels[key] = mix;

  @override
  void removeChannel(String key) => channels.remove(key);

  @override
  void setMaster(MasterMix mix) => master = mix;

  /// returns is the returns as last set -- see AudioEngine.setReturns.
  List<ReturnChannel> returns = const [];
  @override
  void setReturns(List<ReturnChannel> returns) => this.returns = returns;

  /// sceneBus and sceneChannels are the scene's bus as last set -- see
  /// AudioEngine.setScene.
  ChannelMix sceneBus = const ChannelMix();
  Set<String> sceneChannels = const {};
  @override
  void setScene(ChannelMix bus, Set<String> channels) {
    sceneBus = bus;
    sceneChannels = channels;
  }

  /// speakers and placements are as last set -- see AudioEngine.
  SpeakerLayout speakers = SpeakerLayout.stereo;
  final Map<String, Heard> placements = {};
  @override
  void setSpeakers(SpeakerLayout layout) => speakers = layout;

  SpeakerGroup hear = SpeakerGroup.all;
  @override
  void setHear(SpeakerGroup group) => hear = group;

  /// notes is every live note, as (channel, key, velocity) -- nought for a
  /// let-go -- in order.
  final List<(String, int, int)> notes = [];

  /// parts is the part each live note was played on, in order.
  final List<InstrumentPart> parts = [];
  @override
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font}) {
    notes.add((channel, key, velocity));
    parts.add(sound);
  }

  @override
  void noteOff(String channel, int key) => notes.add((channel, key, 0));

  /// controls is every controller set live, as (channel, control, value).
  final List<(String, MidiControl, double)> controls = [];
  @override
  void control(String channel, MidiControl control, double value) =>
      controls.add((channel, control, value));

  /// patches are the live patches set, in order.
  final List<(String, SynthPatch)> patches = [];
  @override
  void livePatch(String channel, SynthPatch patch) =>
      patches.add((channel, patch));
  @override
  void setPlacement(String key, Heard? heard) =>
      heard == null ? placements.remove(key) : placements[key] = heard;

  /// heardLevels is how loud levels says every strip is, and heardTaps
  /// what deviceLevels says of each step of a strip -- set by a test.
  (double, double) heardLevels = (0.5, 0.5);
  List<(double, double)> heardTaps = const [];

  @override
  (double, double) levels([String? channel]) => heardLevels;

  @override
  List<(double, double)> deviceLevels(String channel) => heardTaps;

  /// heardScope is what deviceScope says any device passes, and scoped
  /// the devices asked for and not yet stopped, as "channel|device".
  ScopeReading? heardScope;
  final Set<String> scoped = {};

  @override
  ScopeReading? deviceScope(String channel, String id) {
    scoped.add("$channel|$id");
    return heardScope;
  }

  @override
  void stopScope(String channel, String id) => scoped.remove("$channel|$id");

  /// listened is each channel heard from a step of its chain.
  final Map<String, int> listened = {};

  @override
  void listenAt(String channel, int? step) =>
      step == null ? listened.remove(channel) : listened[channel] = step;

  @override
  double reduction(String channel) => 0;

  /// heardPitch is what pitch says a tuner hears.
  PitchReading? heardPitch;
  @override
  PitchReading? pitch([String? channel]) => heardPitch;

  /// heardWave and heardLoudness are what its analysers report, set by a
  /// test; loudnessResets counts the Loudness started again.
  Wave? heardWave;
  LoudnessReading? heardLoudness;
  int loudnessResets = 0;

  @override
  Wave? wave(DeviceKind kind, [String? channel]) => heardWave;

  @override
  LoudnessReading? loudness([String? channel]) => heardLoudness;

  @override
  void resetLoudness([String? channel]) => loudnessResets++;

  @override
  Float32List? spectrum([String? channel]) =>
      Float32List.fromList([for (var i = 0; i < 256; i++) 1 / (1 + i)]);

  /// launches is every clip launched, as (voice, delay, loop); stopsIn
  /// every stop set, as (voice, delay).
  final List<(FakeVoice, double, (double, double)?)> launches = [];
  final List<(FakeVoice, double)> stopsIn = [];

  @override
  AudioVoice? launch(AudioTrack track,
      {required double volume,
      required double delay,
      double at = 0,
      (double, double)? loop,
      String? channel}) {
    var v = play(track, volume: volume, at: at, channel: channel) as FakeVoice;
    launches.add((v, delay, loop));
    return v;
  }

  @override
  void stopIn(AudioVoice voice, double delay) =>
      stopsIn.add((voice as FakeVoice, delay));

  @override
  double latency = 0;

  @override
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel}) {
    var v = FakeVoice(track as FakeTrack, at, volume);
    onChannel[v] = channel;
    voices.add(v);
    return v;
  }

  /// routed is each voice put through another channel, as it was asked.
  final List<(AudioVoice, String?)> routed = [];
  @override
  void route(AudioVoice voice, String? channel) => routed.add((voice, channel));

  @override
  void volume(AudioVoice voice, double to, {double fade = 0}) {
    var v = voice as FakeVoice;
    v.fades.add((to, fade));
    v.volume = to;
  }

  /// softStops is every voice stopped with a fade, and over how long.
  final List<(FakeVoice, double)> softStops = [];

  @override
  void stopSoftly(AudioVoice voice, double fade) {
    var v = voice as FakeVoice;
    softStops.add((v, fade));
    v.fades.add((0, fade));
    v.alive = false;
  }

  @override
  void pause(AudioVoice voice, bool paused) =>
      (voice as FakeVoice).paused = paused;

  @override
  void seek(AudioVoice voice, double at) => (voice as FakeVoice).at = at;

  @override
  double position(AudioVoice voice) => (voice as FakeVoice).at;

  @override
  bool alive(AudioVoice voice) => (voice as FakeVoice).alive;

  @override
  void stop(AudioVoice voice) => (voice as FakeVoice).alive = false;

  @override
  void close(AudioTrack track) {}

  /// shapes is what [peaks] answers, by file base name: a test's waveform.
  final Map<String, Float32List> shapes = {};

  @override
  Future<Float32List?> peaks(String file, int count) async =>
      shapes[path.basename(file)];
}

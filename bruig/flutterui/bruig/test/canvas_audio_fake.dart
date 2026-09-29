import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
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

  /// channels is every mixer channel as last set, master the master, and
  /// onChannel which channel each voice was played through.
  final Map<String, ChannelSound> channels = {};
  MasterSound? master;
  final Map<FakeVoice, String?> onChannel = {};

  @override
  void setChannel(String key, ChannelSound sound) => channels[key] = sound;

  @override
  void setMaster(MasterSound sound) => master = sound;

  @override
  (double, double) levels([String? channel]) => (0.5, 0.5);

  @override
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel}) {
    var v = FakeVoice(track as FakeTrack, at, volume);
    onChannel[v] = channel;
    voices.add(v);
    return v;
  }

  @override
  void volume(AudioVoice voice, double to, {double fade = 0}) {
    var v = voice as FakeVoice;
    v.fades.add((to, fade));
    v.volume = to;
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

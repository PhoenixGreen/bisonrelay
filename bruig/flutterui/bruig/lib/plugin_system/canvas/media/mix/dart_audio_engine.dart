import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/mix/click_track.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_core.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

// dart_audio_engine.dart plays the editor's sound through the mix engine:
// MixCore renders it, a block at a time, and one SoLoud stream carries it to
// the sound card. So the editor hears exactly the arithmetic an export is
// rendered with (see mix_render.dart), and a mix can do what SoLoud's buses
// cannot -- one sound feeding two places, which is what a send is.
//
// The stream is kept a little ahead of the speakers: [lead] seconds rendered
// and waiting. SoLoud reports how much of the stream has been heard, so the
// difference is how far ahead the render is -- and a sound's position is
// where it has been heard to, not where it has been rendered to, which is
// what keeps the playhead on the sound.
//
// On by default; the switch in Settings > Plugins > Canvas goes back to
// SoLoud's own buses, which cannot play a send.

/// _Track is a file the engine plays: decoded as it plays, or -- for one
/// only ffmpeg can read -- held whole.
class _Track extends AudioTrack {
  final String path;
  final int frames;
  final MemoryTrack? held;

  /// made is a track that is no file: made as it plays, as the metronome is.
  final TrackSource Function()? made;
  _Track(this.path, this.frames, [this.held, this.made]);

  TrackSource? source() => switch ((made, held)) {
        (var m?, _) => m(),
        (_, MemoryTrack h) => MemoryTrack(h.l, h.r),
        _ => FileTrack.open(path),
      };
}

/// _LiveInstrument is a sampler as a track: what it has sounding, read a
/// block at a time, for as long as the window is open.
class _LiveInstrument implements TrackSource {
  final String which;
  final Sampler sampler;
  _LiveInstrument(this.which, this.sampler);

  @override
  int get frames => 1 << 40;

  @override
  int read(Float32List l, Float32List r, int n) {
    l.fillRange(0, n, 0);
    r.fillRange(0, n, 0);
    sampler.render(l, r, n);
    return n;
  }

  @override
  void seek(int frame) {}

  @override
  void close() => sampler.allOff();
}

class _Voice extends AudioVoice {
  final CoreVoice core;
  _Voice(this.core);
}

/// sharedMixEngine is the one mix engine: one stream to the sound card,
/// whichever canvas is open.
final DartAudioEngine sharedMixEngine = DartAudioEngine();

/// useMixEngine is the switch in Settings > Plugins > Canvas: whether the
/// editor plays through the mix engine -- on unless turned off, now that it
/// has been listened to. Read when a canvas first opens its sound, so a
/// change is heard from the next canvas opened.
bool useMixEngine = true;

class DartAudioEngine implements AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  /// lead is how far ahead of the speakers the render keeps.
  static const double lead = 0.08;

  /// block is how much is rendered at a time.
  static const int block = 512;

  final MixCore core = MixCore();

  AudioSource? _stream;
  Timer? _pump;
  int _pushed = 0;
  Future<bool>? _starting;
  final Float32List _l = Float32List(block), _r = Float32List(block);
  final Float32List _interleaved = Float32List(block * 2);

  /// _limit is how much one stream may carry before a new one takes over:
  /// a SoLoud stream ends once that much has been added to it.
  static const int _limitBytes = 1 << 30;

  @override
  Future<bool> start() {
    if (_soloud.isInitialized && _stream != null) return Future.value(true);
    return _starting ??= () async {
      try {
        if (!_soloud.isInitialized) await _soloud.init();
        _open();
        _pump = Timer.periodic(const Duration(milliseconds: 5), (_) => _fill());
        return true;
      } catch (exception) {
        debugPrint("The mix engine could not start: $exception");
        return false;
      } finally {
        _starting = null;
      }
    }();
  }

  void _open() {
    var stream = _soloud.setBufferStream(
      maxBufferSizeBytes: _limitBytes,
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: lead / 2,
      sampleRate: mixRate,
      channels: Channels.stereo,
      format: BufferType.f32le,
    );
    _soloud.play(stream);
    _stream = stream;
    _pushed = 0;
  }

  /// _heard is how much of the stream has reached the speakers, in frames.
  int get _heard {
    var stream = _stream;
    if (stream == null) return 0;
    try {
      return (_soloud.getStreamTimeConsumed(stream).inMicroseconds *
              mixRate ~/
              1000000)
          .clamp(0, _pushed);
    } catch (_) {
      return _pushed;
    }
  }

  /// _ahead is how many frames are rendered and not yet heard.
  int get _ahead => _pushed - _heard;

  /// _quiet is how many frames have been rendered with nothing playing. A
  /// second of it and the stream is left to run dry -- SoLoud waits for
  /// more without a sound -- rather than fed silence for as long as the
  /// window is open.
  int _quiet = 0;

  /// load is how hard the engine is working: the share of each block's
  /// time spent making it, eased so a meter reads steadily. Nought to one,
  /// and over one when it cannot keep up.
  double get load => _load;
  double _load = 0;
  final Stopwatch _work = Stopwatch();

  void _fill() {
    var stream = _stream;
    if (stream == null) return;
    if (core.voices.isEmpty) {
      if (_quiet > mixRate) return;
    } else {
      _quiet = 0;
    }
    var want = (lead * mixRate).round();
    // A stall longer than the lead is not caught up all at once.
    for (var guard = 0; _ahead < want && guard < 32; guard++) {
      _work
        ..reset()
        ..start();
      core.render(_l, _r, block);
      _work.stop();
      var share = _work.elapsedMicroseconds / (block / mixRate * 1e6);
      _load += (share - _load) * 0.05;
      for (var i = 0; i < block; i++) {
        _interleaved[i * 2] = _l[i];
        _interleaved[i * 2 + 1] = _r[i];
      }
      try {
        _soloud.addAudioDataStream(stream, _interleaved.buffer.asUint8List());
      } catch (exception) {
        debugPrint("The mix engine could not play: $exception");
        return;
      }
      _pushed += block;
      if (core.voices.isEmpty) _quiet += block;
      if (_pushed * 8 > _limitBytes * 0.9) {
        // Near the end of what one stream may carry: the next takes over.
        _soloud.setDataIsEnded(stream);
        _open();
        return;
      }
    }
  }

  void dispose() {
    _pump?.cancel();
    _pump = null;
    if (_stream case var s?) {
      try {
        _soloud.setDataIsEnded(s);
      } catch (_) {}
    }
    _stream = null;
  }

  @override
  Future<AudioTrack?> open(String path) async {
    var probe = FileTrack.open(path);
    if (probe != null) {
      var frames = probe.frames;
      probe.close();
      return _Track(path, frames);
    }
    var ffmpeg = await ffmpegPath();
    var held = ffmpeg == null ? null : await ffmpegTrack(ffmpeg, path);
    if (held == null) {
      debugPrint("The mix engine could not open $path");
      return null;
    }
    return _Track(path, held.frames, held);
  }

  @override
  double lengthOf(AudioTrack track) => (track as _Track).frames / mixRate;

  @override
  AudioTrack? metronome(double secondsPerBeat, int beatsPerBar) {
    var click = ClickTrack(secondsPerBeat, beatsPerBar);
    return _Track("metronome", click.frames, null,
        () => ClickTrack(secondsPerBeat, beatsPerBar));
  }

  @override
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel}) {
    var source = (track as _Track).source();
    if (source == null) return null;
    return _Voice(core.play(source, volume: volume, at: at, channel: channel));
  }

  @override
  AudioVoice? launch(AudioTrack track,
      {required double volume,
      required double delay,
      double at = 0,
      (double, double)? loop,
      String? channel}) {
    var source = (track as _Track).source();
    if (source == null) return null;
    return _Voice(core.play(source,
        volume: volume, at: at, channel: channel, delay: delay, loop: loop));
  }

  @override
  void stopIn(AudioVoice voice, double delay) =>
      core.stopIn((voice as _Voice).core, delay);

  @override
  double get latency => _ahead / mixRate;

  @override
  void setChannel(String key, ChannelSound sound) =>
      core.setChannel(key, sound.mix ?? _fromLevels(sound));

  /// _fromLevels is a strip for a sound handed over without its mix: its
  /// levels as fader and balance, and nothing else.
  static ChannelMix _fromLevels(ChannelSound sound) {
    var loud = math.max(sound.left, sound.right);
    if (loud <= 0) return const ChannelMix(mute: true);
    var balance = sound.left >= sound.right
        ? -(1 - sound.right / loud)
        : 1 - sound.left / loud;
    return ChannelMix(gainDb: gainToDb(loud), balance: balance);
  }

  @override
  void setReturns(List<ReturnChannel> returns) => core.setReturns(returns);

  @override
  void setSpeakers(SpeakerLayout layout) => core.graph.setSpeakers(layout);

  /// _live is each channel's instrument played live: a sampler always
  /// sounding on the channel, as one more voice through its strip.
  final Map<String, (CoreVoice, _LiveInstrument)> _live = {};

  @override
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font}) {
    var which = "${sound.look.name}:${sound.sound.name}:${sound.bank}:"
        "${sound.program}:"
        "${font != null && sound.sound == InstrumentSound.bank}";
    var held = _live[channel];
    if (held == null || held.$2.which != which || !held.$1.alive) {
      if (held != null) core.stop(held.$1);
      var instrument = _LiveInstrument(
          which,
          Sampler(
              font: sound.sound == InstrumentSound.bank ? font : null,
              bank: sound.bank,
              program: sound.program,
              look: sound.look));
      held = (core.play(instrument, volume: 1, channel: channel), instrument);
      _live[channel] = held;
    }
    held.$2.sampler.noteOn(key, velocity);
  }

  @override
  void noteOff(String channel, int key) =>
      _live[channel]?.$2.sampler.noteOff(key);

  @override
  void control(String channel, MidiControl control, double value) =>
      _live[channel]?.$2.sampler.control(control, value);

  @override
  void setPlacement(String key, Heard? heard) =>
      core.graph.setPlacement(key, heard);

  @override
  void setMaster(MasterSound sound) => core.setMaster(sound.mix ??
      MasterMix(
          gainDb: gainToDb(sound.volume),
          limiter: sound.ceilingDb != null,
          ceilingDb: sound.ceilingDb ?? -1));

  @override
  (double, double) levels([String? channel]) => core.levels(channel);

  @override
  Float32List? spectrum([String? channel]) => core.spectrum(channel);

  @override
  PitchReading? pitch([String? channel]) => core.graph.pitchOf(channel);

  @override
  void volume(AudioVoice voice, double to, {double fade = 0}) =>
      core.volume((voice as _Voice).core, to, fade: fade);

  @override
  void pause(AudioVoice voice, bool paused) =>
      core.pause((voice as _Voice).core, paused);

  @override
  void seek(AudioVoice voice, double at) =>
      core.seek((voice as _Voice).core, at);

  /// position is where the voice has been heard to: rendered, less what is
  /// still on its way -- and never before where it last started.
  @override
  double position(AudioVoice voice) {
    var v = (voice as _Voice).core;
    return math.max(v.since, v.frame - _ahead) / mixRate;
  }

  @override
  bool alive(AudioVoice voice) => (voice as _Voice).core.alive;

  @override
  void stop(AudioVoice voice) => core.stop((voice as _Voice).core);

  @override
  void stopSoftly(AudioVoice voice, double fade) =>
      core.stopSoftly((voice as _Voice).core, fade);

  @override
  void close(AudioTrack track) {}

  @override
  Future<Float32List?> peaks(String path, int count) =>
      Isolate.run(() => filePeaks(path, count));
}

/// filePeaks is the shape of the file at [path]: [count] values, nought to
/// one, each the loudest moment in its share of the file.
Float32List? filePeaks(String path, int count) {
  var track = FileTrack.open(path);
  if (track == null || count <= 0) return null;
  try {
    var out = Float32List(count);
    var per = math.max(1, track.frames / count);
    var l = Float32List(4096), r = Float32List(4096);
    var at = 0;
    while (true) {
      var got = track.read(l, r, 4096);
      if (got == 0) break;
      for (var i = 0; i < got; i++) {
        var k = ((at + i) / per).floor().clamp(0, count - 1);
        var v = math.max(l[i].abs(), r[i].abs());
        if (v > out[k]) out[k] = v;
      }
      at += got;
    }
    return out;
  } finally {
    track.close();
  }
}

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/audio_engine.dart';
import 'package:bruig/plugin_system/canvas/export/video_export.dart'
    show ffmpegPath;
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/media/mix/click_track.dart';
import 'package:bruig/plugin_system/canvas/media/latency_log.dart';
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
import 'package:bruig/plugin_system/canvas/media/mix/mix_worker.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart'
    show soundBankPath;

// dart_audio_engine.dart plays the editor's sound through the mix engine:
// MixCore renders it a block at a time and one SoLoud stream carries it to
// the sound card. The editor so hears the same arithmetic an export renders
// with (see mix_render.dart), sends included.
//
// The stream is kept [lead] seconds ahead of the speakers. A voice's
// position is where it has been heard to (rendered less what SoLoud has not
// yet consumed), which keeps the playhead on the sound.

/// _Track is a file the engine plays: decoded as it plays, or -- for one
/// only ffmpeg can read -- held whole.
class _Track extends AudioTrack {
  final String path;
  final int frames;
  final MemoryTrack? held;

  /// made generates a track that is no file, such as the metronome.
  final TrackSource Function()? made;
  _Track(this.path, this.frames, [this.held, this.made]);

  TrackSource? source() => switch ((made, held)) {
        (var m?, _) => m(),
        (_, MemoryTrack h) => MemoryTrack(h.l, h.r),
        _ => FileTrack.open(path),
      };
}

/// _LiveInstrument is a sampler played live, as an endless track.
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
  /// core is the voice, where the mix runs here; id is its name in the
  /// worker's, where it runs there.
  final CoreVoice? core;
  final int id;

  /// at is where it was asked to start, and born when: what its position is
  /// until the worker first reports it.
  final double at;
  final int born;
  _Voice(this.id, {this.core, this.at = 0, this.born = 0});
}

/// _RemoteTrack is a track opened in the worker, by its id there.
class _RemoteTrack extends AudioTrack {
  final int id;
  final int frames;
  _RemoteTrack(this.id, this.frames);
}

/// sharedMixEngine is the one mix engine: one stream to the sound card,
/// whichever canvas is open.
final DartAudioEngine sharedMixEngine = DartAudioEngine();

/// useMixWorker is whether the mix renders in an isolate of its own (see
/// mix_worker.dart) rather than on the UI's, where a slow frame could leave
/// the speakers waiting. Where the worker cannot start, the mix runs here.
bool useMixWorker = true;

class DartAudioEngine implements AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  /// lead is how far ahead of the speakers the render keeps, in seconds:
  /// enough for the pump to miss a few turns, and no more, since it is
  /// also the delay before a sound played at a press is heard.
  static const double lead = 0.05;

  /// block is how many frames are rendered at a time.
  static const int block = 512;

  /// core is the mix, where it runs on this isolate. With the worker
  /// running, it is idle: everything is sent there.
  final MixCore core = MixCore();

  AudioSource? _stream;
  Timer? _pump;
  int _pushed = 0;
  Future<bool>? _starting;
  final Float32List _l = Float32List(block), _r = Float32List(block);
  final Float32List _interleaved = Float32List(block * 2);

  /// _limitBytes is how much one stream may carry before a new one takes
  /// over: a SoLoud stream ends once that much has been added to it.
  static const int _limitBytes = 1 << 30;

  // The worker, where it runs: where to send, and what it last said.
  SendPort? _to;
  Isolate? _isolate;
  ReceivePort? _from;
  MixSnapshot _snap = MixSnapshot.empty;
  final Stopwatch _clock = Stopwatch()..start();
  int _snapAt = 0;
  int _nextTrack = 1, _nextVoice = 1;
  final Map<int, Completer<int?>> _opening = {};
  final Set<int> _seen = {}, _stopped = {};
  final Set<String> _watching = {};

  bool get _remote => _to != null;

  void _send(List message) => _to?.send(message);

  @override
  Future<bool> start() {
    if (_soloud.isInitialized && _stream != null) return Future.value(true);
    return _starting ??= () async {
      try {
        if (!_soloud.isInitialized) {
          await _soloud.init(bufferSize: soloudBufferFrames);
        }
        if (useMixWorker && await _startWorker()) return true;
        _open();
        _wakeLocal();
        return true;
      } catch (exception) {
        debugPrint("The mix engine could not start: $exception");
        return false;
      } finally {
        _starting = null;
      }
    }();
  }

  /// _startWorker starts the mix in its own isolate, handing it the stream
  /// to push to. Whether it could.
  Future<bool> _startWorker() async {
    var from = ReceivePort();
    try {
      _isolate = await Isolate.spawn(mixWorkerMain, from.sendPort,
          debugName: "canvas mix");
    } catch (exception) {
      debugPrint("The mix runs on the UI's isolate: $exception");
      from.close();
      return false;
    }
    var ready = Completer<SendPort>();
    from.listen((m) {
      if (m is SendPort) {
        if (!ready.isCompleted) ready.complete(m);
        return;
      }
      if (m is! List || m.isEmpty) return;
      switch (m[0]) {
        case "snapshot":
          _snap = m[1] as MixSnapshot;
          _snapAt = _clock.elapsedMicroseconds;
          _seen.addAll(_snap.voices.keys);
        case "opened":
          _opening.remove(m[1])?.complete(m[2] as int?);
        case "streamReached":
          if (!_reached.isCompleted) _reached.complete(m[1] as bool);
        case "renew":
          _openStream();
          _send(["stream", _stream!.soundHash]);
      }
    });
    _from = from;
    _to = await ready.future;
    if (_held) _send(const ["held", true]);
    try {
      _send(["fontPath", await soundBankPath()]);
    } catch (_) {}
    _openStream();
    _send(["stream", _stream!.soundHash]);
    // Pushed to from there, or the mix runs here after all.
    var reached = await _reached.future
        .timeout(const Duration(seconds: 1), onTimeout: () => false);
    if (reached) return true;
    debugPrint("The mix worker could not reach the stream: it runs here.");
    _send(const ["dispose"]);
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    from.close();
    _to = null;
    _isolate = null;
    _from = null;
    if (_stream case var s?) {
      try {
        _soloud.setDataIsEnded(s);
      } catch (_) {}
    }
    _stream = null;
    return false;
  }

  /// _reached is the worker's answer to whether it can push to the stream.
  final Completer<bool> _reached = Completer();

  void _open() {
    _openStream();
    _pushed = 0;
  }

  void _openStream() {
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
  int get _ahead => _remote ? _snap.ahead : _pushed - _heard;

  /// _quiet is how many frames have been rendered with nothing playing.
  /// After a second of it the stream is left to run dry (SoLoud waits
  /// silently) rather than fed silence for as long as the window is open.
  int _quiet = 0;

  /// load is the eased share of each block's time spent rendering it:
  /// over one when the engine cannot keep up.
  double get load => _remote ? _snap.load : _load;
  double _load = 0;
  final Stopwatch _work = Stopwatch();

  /// held is whether the mix is held still: nothing is rendered, so every
  /// voice and its scheduled stops wait where they are. Used when a game
  /// pauses.
  bool get held => _held;
  bool _held = false;
  set held(bool on) {
    _held = on;
    _send(["held", on]);
    if (!on) _wakeLocal();
  }

  /// _wakeLocal sets the pump going again, mixing here rather than in the
  /// worker: after a second of quiet it rests (see _fill), and anything
  /// that may start a sound wakes it.
  void _wakeLocal() {
    if (_remote) return;
    _quiet = 0;
    _pump ??= Timer.periodic(const Duration(milliseconds: 5), (_) => _fill());
  }

  void _fill() {
    var stream = _stream;
    if (stream == null || _held) return;
    if (core.voices.every((v) => v.paused)) {
      if (_quiet > mixRate) {
        // Rested: no timer on the editor's isolate while nothing sounds,
        // and its meters to silence rather than where they last stood.
        core.graph.quiet();
        _pump?.cancel();
        _pump = null;
        return;
      }
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
      if (core.voices.every((v) => v.paused)) _quiet += block;
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
    if (_remote) {
      _send(const ["dispose"]);
      _isolate?.kill(priority: Isolate.beforeNextEvent);
      _from?.close();
      _to = null;
      _isolate = null;
      _from = null;
    } else if (_stream case var s?) {
      try {
        _soloud.setDataIsEnded(s);
      } catch (_) {}
    }
    _stream = null;
  }

  @override
  Future<AudioTrack?> open(String path) async {
    if (_remote) {
      var id = _nextTrack++;
      var done = Completer<int?>();
      _opening[id] = done;
      _send(["open", id, path, await ffmpegPath()]);
      var frames = await done.future;
      if (frames == null) {
        debugPrint("The mix engine could not open $path");
        return null;
      }
      return _RemoteTrack(id, frames);
    }
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
  double lengthOf(AudioTrack track) => switch (track) {
        _RemoteTrack t => t.frames / mixRate,
        _ => (track as _Track).frames / mixRate,
      };

  @override
  AudioTrack metronome(double secondsPerBeat, int beatsPerBar) {
    var click = ClickTrack(secondsPerBeat, beatsPerBar);
    if (_remote) {
      var id = _nextTrack++;
      _send(["click", id, secondsPerBeat, beatsPerBar, click.frames]);
      return _RemoteTrack(id, click.frames);
    }
    return _Track("metronome", click.frames, null,
        () => ClickTrack(secondsPerBeat, beatsPerBar));
  }

  AudioVoice? _start(AudioTrack track,
      {required double volume,
      double at = 0,
      String? channel,
      double delay = 0,
      (double, double)? loop}) {
    if (track is _RemoteTrack) {
      var id = _nextVoice++;
      _send(["play", id, track.id, volume, at, channel, delay, loop]);
      return _Voice(id, at: at, born: _clock.elapsedMicroseconds);
    }
    var source = (track as _Track).source();
    if (source == null) return null;
    _wakeLocal();
    return _Voice(0,
        core: core.play(source,
            volume: volume,
            at: at,
            channel: channel,
            delay: delay,
            loop: loop));
  }

  @override
  AudioVoice? play(AudioTrack track,
          {required double volume, double at = 0, String? channel}) =>
      _start(track, volume: volume, at: at, channel: channel);

  @override
  AudioVoice? launch(AudioTrack track,
          {required double volume,
          required double delay,
          double at = 0,
          (double, double)? loop,
          String? channel}) =>
      _start(track,
          volume: volume, at: at, channel: channel, delay: delay, loop: loop);

  /// _on is [voice] here, or null where it runs in the worker -- and then
  /// [message] is sent there, with its id.
  CoreVoice? _on(AudioVoice voice, List message) {
    var v = voice as _Voice;
    if (v.core case var c?) return c;
    _send([message.first, v.id, ...message.skip(1)]);
    return null;
  }

  @override
  void route(AudioVoice voice, String? channel) {
    if (_on(voice, ["route", channel]) case var c?) c.channel = channel;
  }

  @override
  void stopIn(AudioVoice voice, double delay) {
    if (_on(voice, ["stopIn", delay]) case var c?) core.stopIn(c, delay);
  }

  @override
  double get latency => _ahead / mixRate;

  @override
  void setChannel(String key, ChannelMix mix) {
    _remote ? _send(["channel", key, mix]) : core.setChannel(key, mix);
  }

  @override
  void removeChannel(String key) =>
      _remote ? _send(["removeChannel", key]) : core.removeChannel(key);

  @override
  void setReturns(List<ReturnChannel> returns) =>
      _remote ? _send(["returns", returns]) : core.setReturns(returns);

  @override
  void setScene(ChannelMix bus, Set<String> channels) => _remote
      ? _send(["scene", bus, channels])
      : core.graph.setScene(bus, channels);

  @override
  void setSpeakers(SpeakerLayout layout) =>
      _remote ? _send(["speakers", layout]) : core.graph.setSpeakers(layout);

  @override
  void setHear(SpeakerGroup group) =>
      _remote ? _send(["hear", group]) : core.graph.hear = group;

  /// _live is each channel's instrument played live: a sampler always
  /// sounding on the channel, as one more voice through its strip.
  final Map<String, (CoreVoice, _LiveInstrument)> _live = {};

  /// _slicesSent are the instruments of slices whose banks the worker has.
  final Set<String> _slicesSent = {};

  @override
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font}) {
    if (_remote) {
      // What plays it, not what it plays: a part's notes and curves are
      // not copied to the worker on every key pressed.
      // An instrument of slices: its bank sent once, and kept there.
      var kit = sound.sound == InstrumentSound.slices ? sound.slices : null;
      var send = kit != null && font != null && _slicesSent.add(kit.key);
      _send([
        "noteOn",
        channel,
        sound.copyWith(notes: const [], controls: const {}),
        key,
        velocity,
        font != null,
        hostTicks(),
        send ? font : null,
      ]);
      return;
    }
    _wakeLocal();
    var which = "${sound.look.name}:${sound.sound.name}:${sound.bank}:"
        "${sound.program}:"
        "${font != null && sound.sound != InstrumentSound.builtin}:"
        "${sound.slices?.key}";
    var held = _live[channel];
    if (held == null || held.$2.which != which || !held.$1.alive) {
      if (held != null) core.stop(held.$1);
      var instrument = _LiveInstrument(
          which,
          Sampler(
              font: sound.sound == InstrumentSound.builtin ? null : font,
              bank: sound.bank,
              program: sound.program,
              look: sound.look));
      held = (core.play(instrument, volume: 1, channel: channel), instrument);
      _live[channel] = held;
    }
    // Its shape as it is now: changed in its editor, the next note has it.
    held.$2.sampler
      ..shape = sound.shape
      ..noteOn(key, velocity);
  }

  @override
  void noteOff(String channel, int key) => _remote
      ? _send(["noteOff", channel, key])
      : _live[channel]?.$2.sampler.noteOff(key);

  @override
  void control(String channel, MidiControl control, double value) => _remote
      ? _send(["control", channel, control, value])
      : _live[channel]?.$2.sampler.control(control, value);

  @override
  void setPlacement(String key, Heard? heard) => _remote
      ? _send(["placement", key, heard])
      : core.graph.setPlacement(key, heard);

  @override
  void setMaster(MasterMix mix) {
    _remote ? _send(["master", mix]) : core.setMaster(mix);
  }

  /// _watch asks the worker, once, to report [what] of [channel].
  void _watch(String what, String? channel) {
    if (_watching.add("$what:$channel")) _send(["watch", what, channel]);
  }

  @override
  (double, double) levels([String? channel]) {
    if (!_remote) return core.levels(channel);
    _watch("levels", channel);
    return _snap.levels[channel ?? snapshotMaster] ?? (0, 0);
  }

  @override
  List<(double, double)> deviceLevels(String channel) {
    if (!_remote) {
      core.graph.tapped.add(channel);
      return core.graph.tapsOf(channel);
    }
    _watch("taps", channel);
    return _snap.taps[channel] ?? const [];
  }

  @override
  ScopeReading? deviceScope(String channel, String id) {
    if (!_remote) {
      core.graph.scope(channel, id, true);
      return core.graph.scopeOf(channel, id);
    }
    _watch("scope:$id", channel);
    return _snap.scopes["$channel|$id"];
  }

  @override
  void listenAt(String channel, int? step) {
    if (!_remote) {
      step == null
          ? core.graph.listenAt.remove(channel)
          : core.graph.listenAt[channel] = step;
      return;
    }
    _send(["listenAt", channel, step]);
  }

  @override
  void stopScope(String channel, String id) {
    if (!_remote) {
      core.graph.scope(channel, id, false);
      return;
    }
    if (_watching.remove("scope:$id:$channel")) {
      _send(["unwatch", "scope:$id", channel]);
    }
  }

  @override
  double reduction(String channel) {
    if (!_remote) return core.graph.reductionOf(channel);
    _watch("taps", channel);
    return _snap.reductions[channel] ?? 0;
  }

  @override
  Float32List? spectrum([String? channel]) {
    if (!_remote) return core.spectrum(channel);
    _watch("spectrum", channel);
    return _snap.spectra[channel ?? snapshotMaster];
  }

  @override
  Wave? wave(DeviceKind kind, [String? channel]) {
    if (!_remote) return core.graph.waveOf(channel, kind);
    _watch("wave:${kind.name}", channel);
    return _snap.waves["${kind.name}:${channel ?? snapshotMaster}"];
  }

  @override
  LoudnessReading? loudness([String? channel]) {
    if (!_remote) return core.graph.loudnessOf(channel);
    _watch("loudness", channel);
    return _snap.loudness[channel ?? snapshotMaster];
  }

  @override
  void resetLoudness([String? channel]) => _remote
      ? _send(["resetLoudness", channel])
      : core.graph.resetLoudness(channel);

  @override
  PitchReading? pitch([String? channel]) {
    if (!_remote) return core.graph.pitchOf(channel);
    _watch("pitch", channel);
    return switch (_snap.pitches[channel ?? snapshotMaster]) {
      (var hz, var clarity) => (hz: hz, clarity: clarity),
      null => null,
    };
  }

  @override
  void volume(AudioVoice voice, double to, {double fade = 0}) {
    if (_on(voice, ["volume", to, fade]) case var c?) {
      core.volume(c, to, fade: fade);
    }
  }

  @override
  void pause(AudioVoice voice, bool paused) {
    if (_on(voice, ["pause", paused]) case var c?) {
      core.pause(c, paused);
      if (!paused) _wakeLocal();
    }
  }

  @override
  void seek(AudioVoice voice, double at) {
    if (_on(voice, ["seek", at]) case var c?) {
      core.seek(c, at);
      _wakeLocal();
    }
  }

  /// position is where the voice has been heard to: rendered less what is
  /// still on its way, and never before where it last started. From the
  /// worker, as last reported and on by the time since.
  @override
  double position(AudioVoice voice) {
    var v = voice as _Voice;
    if (v.core case var c?) {
      return math.max(c.since, c.frame - _ahead) / mixRate;
    }
    var seen = _snap.voices[v.id];
    var now = _clock.elapsedMicroseconds;
    if (seen == null) {
      return v.at + math.max(0, now - v.born) / 1e6;
    }
    var (frame, since, alive, paused) = seen;
    var heard = frame - _snap.ahead;
    if (alive && !paused && !_held) {
      heard = extrapolated(heard, now - _snapAt, cap: frame);
    }
    return math.max(since, heard) / mixRate;
  }

  @override
  bool alive(AudioVoice voice) {
    var v = voice as _Voice;
    if (v.core case var c?) return c.alive;
    if (_stopped.contains(v.id)) return false;
    if (_snap.voices[v.id] case (_, _, var alive, _)) return alive;
    // Not reported yet, or reported and gone.
    return !_seen.contains(v.id);
  }

  @override
  void stop(AudioVoice voice) {
    if (_on(voice, ["stop"]) case var c?) {
      core.stop(c);
    } else {
      _stopped.add((voice as _Voice).id);
    }
  }

  @override
  void stopSoftly(AudioVoice voice, double fade) {
    if (_on(voice, ["stopSoftly", fade]) case var c?) {
      core.stopSoftly(c, fade);
    }
  }

  @override
  void close(AudioTrack track) {
    if (track is _RemoteTrack) _send(["closeTrack", track.id]);
  }

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

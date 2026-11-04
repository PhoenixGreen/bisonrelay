import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/click_track.dart';
import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/mix/mix_core.dart';
import 'package:bruig/plugin_system/canvas/media/synth/sampler.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

// mix_worker.dart runs the mix in an isolate of its own. It renders ahead
// and pushes to SoLoud's stream from there, so a frame the UI takes too long
// over cannot leave the speakers without sound. The editor's side
// (DartAudioEngine) sends it what changes and reads back, every few
// milliseconds, a snapshot: how far ahead it is, its load, where each voice
// is, and the meters the screen is showing.
//
// Messages are lists, the first item naming what they are. Everything sent
// is plain data -- mixes, parts, records -- copied between the isolates.

/// MixSnapshot is the worker's state as last reported.
class MixSnapshot {
  /// at is when it was taken, in microseconds on the reporting clock.
  final int at;
  final int ahead;
  final double load;

  /// voices are each voice's (frame, since, alive, paused), by id.
  final Map<int, (int, int, bool, bool)> voices;
  final Map<String, (double, double)> levels;
  final Map<String, Float32List?> spectra;
  final Map<String, (double, double)?> pitches;

  const MixSnapshot(this.at, this.ahead, this.load, this.voices, this.levels,
      this.spectra, this.pitches);

  static const empty = MixSnapshot(0, 0, 0, {}, {}, {}, {});
}

/// master is the key the master's meters go by in a snapshot.
const String snapshotMaster = "";

/// mixWorkerMain is the worker isolate's entry: [port] is where it answers.
void mixWorkerMain(SendPort port) {
  var inbox = ReceivePort();
  port.send(inbox.sendPort);
  var w = _Worker(port);
  inbox.listen((m) {
    if (m is List && m.isNotEmpty) {
      if (m[0] == "dispose") {
        w.dispose();
        inbox.close();
        return;
      }
      w.handle(m);
    }
  });
}

class _WTrack {
  final String path;
  final int frames;
  final MemoryTrack? held;
  final (double, int)? click;
  _WTrack(this.path, this.frames, {this.held, this.click});

  TrackSource? source() => switch ((click, held)) {
        ((var spb, var bpb)?, _) => ClickTrack(spb, bpb),
        (_, MemoryTrack h) => MemoryTrack(h.l, h.r),
        _ => FileTrack.open(path),
      };
}

class _Live implements TrackSource {
  final String which;
  final Sampler sampler;
  _Live(this.which, this.sampler);

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

class _Worker {
  final SendPort port;
  final MixCore core = MixCore();
  final Map<int, _WTrack> tracks = {};
  final Map<int, CoreVoice> voices = {};
  final Map<String, (CoreVoice, _Live)> live = {};
  final Set<String> watchLevels = {}, watchSpectra = {}, watchPitches = {};
  String? fontPath;
  SoundFont? _font;
  bool _fontTried = false;

  SoundHash? _stream;
  int _pushed = 0, _quiet = 0;
  bool held = false, _renewing = false;
  double _load = 0;
  final Stopwatch _work = Stopwatch(), _clock = Stopwatch()..start();
  Timer? _pump, _report;

  static const int block = 512;
  static const double lead = 0.05;
  static const int _limitBytes = 1 << 30;
  final Float32List _l = Float32List(block), _r = Float32List(block);
  final Float32List _interleaved = Float32List(block * 2);

  _Worker(this.port) {
    _pump = Timer.periodic(const Duration(milliseconds: 5), (_) => _fill());
    _report =
        Timer.periodic(const Duration(milliseconds: 20), (_) => _snapshot());
  }

  // Safe off the main isolate once the main one has started the engine --
  // see SoLoudIsolate. Experimental in flutter_soloud; pinned to 4.1.7.
  // ignore: experimental_member_use
  final _ffi = SoLoudIsolate.instance.bindings;

  int get _heard {
    var hash = _stream;
    if (hash == null) return 0;
    try {
      var r = _ffi.getStreamTimeConsumed(hash);
      return (r.value * mixRate).round().clamp(0, _pushed);
    } catch (_) {
      return _pushed;
    }
  }

  int get _ahead => _pushed - _heard;

  void _fill() {
    var hash = _stream;
    if (hash == null || held || _renewing) return;
    if (core.voices.isEmpty) {
      if (_quiet > mixRate) return;
    } else {
      _quiet = 0;
    }
    var want = (lead * mixRate).round();
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
        _ffi.addAudioDataStream(hash.hash, _interleaved.buffer.asUint8List());
      } catch (_) {
        return;
      }
      _pushed += block;
      if (core.voices.isEmpty) _quiet += block;
      if (_pushed * 8 > _limitBytes * 0.9) {
        // Near what one stream may carry: the editor opens the next.
        try {
          _ffi.setDataIsEnded(hash);
        } catch (_) {}
        _renewing = true;
        port.send(const ["renew"]);
        return;
      }
    }
  }

  void _snapshot() {
    var ahead = _stream == null ? 0 : _ahead;
    port.send([
      "snapshot",
      MixSnapshot(
        _clock.elapsedMicroseconds,
        ahead,
        _load,
        {
          for (var e in voices.entries)
            e.key: (e.value.frame, e.value.since, e.value.alive, e.value.paused)
        },
        {
          for (var k in watchLevels)
            k: core.levels(k == snapshotMaster ? null : k)
        },
        {
          for (var k in watchSpectra)
            k: core.spectrum(k == snapshotMaster ? null : k)
        },
        {
          for (var k in watchPitches)
            k: switch (core.graph.pitchOf(k == snapshotMaster ? null : k)) {
              var p? => (p.hz, p.clarity),
              null => null,
            }
        },
      ),
    ]);
    // Voices that have ended are forgotten once reported.
    voices.removeWhere((_, v) => !v.alive);
  }

  SoundFont? get font {
    if (_font != null || _fontTried) return _font;
    _fontTried = true;
    var at = fontPath;
    if (at == null || !File(at).existsSync()) return null;
    try {
      _font = SoundFont.read(File(at).readAsBytesSync());
    } catch (_) {}
    return _font;
  }

  Future<void> _open(int request, String path, String? ffmpeg) async {
    var probe = FileTrack.open(path);
    _WTrack? track;
    if (probe != null) {
      track = _WTrack(path, probe.frames);
      probe.close();
    } else if (ffmpeg != null) {
      var memory = await ffmpegTrack(ffmpeg, path);
      if (memory != null) track = _WTrack(path, memory.frames, held: memory);
    }
    if (track != null) tracks[request] = track;
    port.send(["opened", request, track?.frames]);
  }

  CoreVoice? _voice(Object? id) => voices[id];

  void handle(List m) {
    switch (m[0]) {
      case "stream":
        _stream = m[1] as SoundHash;
        _pushed = 0;
        _renewing = false;
        // Whether the stream can be reached from here at all: the editor
        // runs the mix itself where it cannot.
        var reached = false;
        try {
          reached = streamAnswered(_ffi.getStreamTimeConsumed(_stream!).error);
        } catch (_) {}
        port.send(["streamReached", reached]);
      case "fontPath":
        fontPath = m[1] as String?;
      case "open":
        unawaited(_open(m[1] as int, m[2] as String, m[3] as String?));
      case "click":
        tracks[m[1] as int] = _WTrack("metronome", m[4] as int,
            click: (m[2] as double, m[3] as int));
      case "closeTrack":
        tracks.remove(m[1]);
      case "play":
        var source = tracks[m[2]]?.source();
        if (source == null) {
          voices.remove(m[1]);
          return;
        }
        voices[m[1] as int] = core.play(source,
            volume: m[3] as double,
            at: m[4] as double,
            channel: m[5] as String?,
            delay: m[6] as double,
            loop: m[7] as (double, double)?);
      case "stopIn":
        if (_voice(m[1]) case var v?) core.stopIn(v, m[2] as double);
      case "stop":
        if (_voice(m[1]) case var v?) core.stop(v);
      case "stopSoftly":
        if (_voice(m[1]) case var v?) core.stopSoftly(v, m[2] as double);
      case "volume":
        if (_voice(m[1]) case var v?) {
          core.volume(v, m[2] as double, fade: m[3] as double);
        }
      case "pause":
        if (_voice(m[1]) case var v?) core.pause(v, m[2] as bool);
      case "seek":
        if (_voice(m[1]) case var v?) core.seek(v, m[2] as double);
      case "channel":
        core.setChannel(m[1] as String, m[2]);
      case "removeChannel":
        core.removeChannel(m[1] as String);
      case "returns":
        core.setReturns((m[1] as List).cast());
      case "speakers":
        core.graph.setSpeakers(m[1]);
      case "placement":
        core.graph.setPlacement(m[1] as String, m[2]);
      case "master":
        core.setMaster(m[1]);
      case "held":
        held = m[1] as bool;
      case "watch":
        var key = (m[2] as String?) ?? snapshotMaster;
        switch (m[1]) {
          case "levels":
            watchLevels.add(key);
          case "spectrum":
            watchSpectra.add(key);
          case "pitch":
            watchPitches.add(key);
        }
      case "noteOn":
        var channel = m[1] as String;
        var part = m[2] as InstrumentPart;
        var useFont = m[5] as bool;
        var which = "${part.look.name}:${part.sound.name}:${part.bank}:"
            "${part.program}:$useFont";
        var had = live[channel];
        if (had == null || had.$2.which != which || !had.$1.alive) {
          if (had != null) core.stop(had.$1);
          var instrument = _Live(
              which,
              Sampler(
                  font: useFont && part.sound == InstrumentSound.bank
                      ? font
                      : null,
                  bank: part.bank,
                  program: part.program,
                  look: part.look));
          had =
              (core.play(instrument, volume: 1, channel: channel), instrument);
          live[channel] = had;
        }
        had.$2.sampler.noteOn(m[3] as int, m[4] as int);
      case "noteOff":
        live[m[1]]?.$2.sampler.noteOff(m[2] as int);
      case "control":
        live[m[1]]?.$2.sampler.control(m[2], m[3] as double);
    }
  }

  void dispose() {
    _pump?.cancel();
    _report?.cancel();
    if (_stream case var hash?) {
      try {
        _ffi.setDataIsEnded(hash);
      } catch (_) {}
    }
    _stream = null;
  }
}

/// streamAnswered is whether [error], SoLoud's answer to a call on the
/// stream, is no error. By name: the type is not exported, and it prints
/// as "PlayerErrors.noError (No error)", so its text is no test.
bool streamAnswered(Enum error) => error.name == "noError";

/// extrapolated is where a voice reported at [frame] is [elapsedMicros]
/// later, playing: on by the time passed, never past [cap].
int extrapolated(int frame, int elapsedMicros, {int? cap}) {
  var on = frame + (elapsedMicros * mixRate / 1e6).round();
  return cap == null ? on : math.min(on, cap);
}

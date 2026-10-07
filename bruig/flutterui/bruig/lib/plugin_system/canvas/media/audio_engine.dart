import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

// audio_engine.dart is the one place a canvas touches a sound card.
//
// Everything that decides *what* plays -- the playlist, the range, the fades,
// the loop, which page a sound belongs to -- is in audio_runtime.dart and
// speaks to this interface. So the rules can be tested against a fake engine
// with a clock the test moves, and SoLoud is the only thing that has to be
// run on a real machine to be trusted.

/// AudioTrack is a file the engine has opened, and AudioVoice one playing of
/// it. Opaque: only the engine that made one knows what is inside.
abstract class AudioTrack {}

abstract class AudioVoice {}

/// ChannelSound is a mixer strip as the engine applies it: the level of each
/// side (fader, balance, mute and solo already worked in -- see
/// AudioRuntime.setMix), the EQ as band gains, and the compressor.
class ChannelSound {
  final double left;
  final double right;

  /// eq is SoLoud's band gains for the strip's curve, or null for none. See
  /// eqBandGains.
  final List<double>? eq;
  final Dynamics? comp;

  const ChannelSound({this.left = 1, this.right = 1, this.eq, this.comp});
}

/// MasterSound is the master strip as the engine applies it.
class MasterSound {
  final double volume;
  final List<double>? eq;
  final Dynamics? comp;

  /// ceilingDb is the limiter's, or null for no limiter.
  final double? ceilingDb;

  const MasterSound({this.volume = 1, this.eq, this.comp, this.ceilingDb});
}

abstract class AudioEngine {
  /// start makes the engine ready, returning false where there is no sound to
  /// be had -- no device, or a library that would not load. Asked before
  /// every first play, and cheap once it has worked.
  Future<bool> start();

  /// open reads the file at [path], or returns null where it cannot.
  Future<AudioTrack?> open(String path);

  /// lengthOf is how long [track] is, in seconds.
  double lengthOf(AudioTrack track);

  /// play starts [track] from [at] seconds in, at [volume], through the
  /// mixer channel called [channel] where it has one.
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel});

  /// setChannel makes or changes the mixer channel called [key].
  void setChannel(String key, ChannelSound sound);

  /// setMaster is the master strip, over everything.
  void setMaster(MasterSound sound);

  /// levels is how loud a channel -- or with no [channel], the master -- is
  /// coming out right now, left and right, nought to one. For the meters;
  /// asking for it is what turns the measuring on.
  (double, double) levels([String? channel]);

  /// volume moves [voice] to [to], over [fade] seconds.
  void volume(AudioVoice voice, double to, {double fade = 0});

  void pause(AudioVoice voice, bool paused);

  /// seek moves [voice] to [at] seconds into its file.
  void seek(AudioVoice voice, double at);

  /// position is how far into the file [voice] has got, in seconds.
  double position(AudioVoice voice);

  /// alive is whether [voice] is still playing or paused -- false once it has
  /// reached the end of the file or been stopped.
  bool alive(AudioVoice voice);

  void stop(AudioVoice voice);

  /// stopSoftly brings [voice] down to nothing over [fade] seconds and then
  /// stops it, both on the sound card's own clock. A sound stopped outright
  /// is cut mid-swing, which is a click.
  void stopSoftly(AudioVoice voice, double fade);

  void close(AudioTrack track);

  /// peaks is the shape of the sound in the file at [path]: [count] values,
  /// nought to one, each the loudest moment in its share of the file. For
  /// drawing, never for playing. Null where the file cannot be read.
  Future<Float32List?> peaks(String path, int count);
}

class _SoLoudTrack extends AudioTrack {
  final AudioSource source;
  _SoLoudTrack(this.source);
}

class _SoLoudVoice extends AudioVoice {
  final SoundHandle handle;
  _SoLoudVoice(this.handle);
}

/// _busMetering switches level-gathering on for one mixing bus.
///
/// Looked up by hand. A bus's meter reads nothing until this has been called
/// for it, and flutter_soloud 4.1 exports the native function but leaves its
/// Dart binding commented out -- so every channel meter sat at the bottom
/// while the master, which has a binding, moved. The library is opened the
/// way the package opens it, which hands back the one already loaded. Null
/// where it cannot be found, and the meters simply stay still.
final void Function(int busId, bool enable)? _busMetering = () {
  try {
    var lib = Platform.isLinux || Platform.isAndroid
        ? ffi.DynamicLibrary.open("libflutter_soloud_plugin.so")
        : Platform.isWindows
            ? ffi.DynamicLibrary.open("flutter_soloud_plugin.dll")
            : ffi.DynamicLibrary.process();
    return lib.lookupFunction<ffi.Void Function(ffi.UnsignedInt, ffi.Bool),
        void Function(int, bool)>("busSetVisualizationEnable");
  } catch (exception) {
    debugPrint("Channel meters are unavailable: $exception");
    return null;
  }
}();

/// SoLoudAudioEngine plays through flutter_soloud.
class SoLoudAudioEngine implements AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  Future<bool>? _starting;

  @override
  Future<bool> start() {
    if (_soloud.isInitialized) return Future.value(true);
    return _starting ??= () async {
      try {
        await _soloud.init();
        return true;
      } catch (exception) {
        debugPrint("Canvas audio could not start: $exception");
        return false;
      } finally {
        _starting = null;
      }
    }();
  }

  @override
  Future<AudioTrack?> open(String path) async {
    try {
      // Read from the disk as it plays rather than decoded into memory whole:
      // a long recording decoded up front is gigabytes of samples.
      return _SoLoudTrack(await _soloud.loadFile(path, mode: LoadMode.disk));
    } catch (exception) {
      debugPrint("Canvas audio could not open $path: $exception");
      return null;
    }
  }

  @override
  double lengthOf(AudioTrack track) =>
      _soloud.getLength((track as _SoLoudTrack).source).inMicroseconds / 1e6;

  /// _buses is a mixing bus per mixer channel, made when the channel is first
  /// set and played on the engine for as long as the engine lives.
  final Map<String, Bus> _buses = {};

  /// _metered is the buses whose levels are being gathered -- see
  /// _busMetering.
  final Set<String> _metered = {};
  bool _measuring = false;

  static const _eqBands = soloudBands;

  @override
  void setChannel(String key, ChannelSound sound) {
    if (!_soloud.isInitialized) return;
    try {
      var bus = _buses[key];
      if (bus == null) {
        bus = Bus(name: key);
        bus.playOnEngine();
        _buses[key] = bus;
      }
      var handle = bus.soundHandle;
      if (handle != null) {
        _soloud.setVolume(handle, 1);
        _soloud.setPanAbsolute(handle, sound.left, sound.right);
      }
      _eq(bus.filters.parametricEqFilter.isActive, sound.eq,
          activate: bus.filters.parametricEqFilter.activate,
          deactivate: bus.filters.parametricEqFilter.deactivate,
          bands: (n) => bus!.filters.parametricEqFilter.numBands().value = n,
          band: (i, g) =>
              bus!.filters.parametricEqFilter.bandGain(i).value = g);
      var comp = bus.filters.compressorFilter;
      if (sound.comp case var c?) {
        if (!comp.isActive) comp.activate();
        comp.threshold().value = c.threshold;
        comp.ratio().value = c.ratio;
        comp.attackTime().value = c.attackMs;
        comp.releaseTime().value = c.releaseMs;
        comp.makeupGain().value = c.makeupDb;
        comp.kneeWidth().value = Dynamics.kneeDb;
      } else if (comp.isActive) {
        comp.deactivate();
      }
    } catch (exception) {
      debugPrint("Canvas audio could not set the channel $key: $exception");
    }
  }

  @override
  void setMaster(MasterSound sound) {
    if (!_soloud.isInitialized) return;
    try {
      _soloud.setGlobalVolume(sound.volume);
      var filters = _soloud.filters;
      _eq(filters.parametricEqFilter.isActive, sound.eq,
          activate: filters.parametricEqFilter.activate,
          deactivate: filters.parametricEqFilter.deactivate,
          bands: (n) => filters.parametricEqFilter.numBands.value = n,
          band: (i, g) => filters.parametricEqFilter.bandGain(i).value = g);
      var comp = filters.compressorFilter;
      if (sound.comp case var c?) {
        if (!comp.isActive) comp.activate();
        comp.threshold.value = c.threshold;
        comp.ratio.value = c.ratio;
        comp.attackTime.value = c.attackMs;
        comp.releaseTime.value = c.releaseMs;
        comp.makeupGain.value = c.makeupDb;
        comp.kneeWidth.value = Dynamics.kneeDb;
      } else if (comp.isActive) {
        comp.deactivate();
      }
      var limiter = filters.limiterFilter;
      if (sound.ceilingDb case var ceiling?) {
        if (!limiter.isActive) limiter.activate();
        // No drive: the limiter only catches peaks. Pushing the level up into
        // it is what the loudness target is for, at export.
        limiter.threshold.value = 0;
        limiter.outputCeiling.value = ceiling;
        limiter.attackTime.value = 5;
        limiter.releaseTime.value = 50;
      } else if (limiter.isActive) {
        limiter.deactivate();
      }
    } catch (exception) {
      debugPrint("Canvas audio could not set the master: $exception");
    }
  }

  void _eq(bool active, List<double>? gains,
      {required void Function() activate,
      required void Function() deactivate,
      required void Function(double) bands,
      required void Function(int, double) band}) {
    if (gains == null) {
      if (active) deactivate();
      return;
    }
    if (!active) {
      activate();
      bands(_eqBands.toDouble());
    }
    for (var (i, g) in gains.indexed) {
      if (i < _eqBands) band(i, g);
    }
  }

  @override
  Future<Float32List?> peaks(String path, int count) async {
    try {
      // Eight readings for each peak, the loudest kept: a single reading per
      // point lands between the beats as often as on them, and draws a quiet
      // sound where there is a loud one.
      const per = 8;
      var raw = await _soloud.readSamplesFromFile(path, count * per);
      var out = Float32List(count);
      for (var i = 0; i < count; i++) {
        var most = 0.0;
        for (var j = i * per; j < (i + 1) * per && j < raw.length; j++) {
          var v = raw[j].abs();
          if (v > most) most = v;
        }
        out[i] = most.clamp(0.0, 1.0);
      }
      return out;
    } catch (exception) {
      debugPrint("Unable to read the shape of $path: $exception");
      return null;
    }
  }

  @override
  (double, double) levels([String? channel]) {
    if (!_soloud.isInitialized) return (0, 0);
    try {
      if (!_measuring) {
        _soloud.setVisualizationEnabled(true);
        _measuring = true;
      }
      // Each bus gathers its own levels, and only once asked to.
      for (var entry in _buses.entries) {
        if (_metered.add(entry.key)) {
          _busMetering?.call(entry.value.busId, true);
        }
      }
      if (channel == null) {
        return (
          _soloud.getApproximateVolume(0),
          _soloud.getApproximateVolume(1)
        );
      }
      var bus = _buses[channel];
      if (bus == null) return (0, 0);
      return (bus.getChannelVolume(0), bus.getChannelVolume(1));
    } catch (_) {
      return (0, 0);
    }
  }

  @override
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel}) {
    try {
      var source = (track as _SoLoudTrack).source;
      var bus = channel == null ? null : _buses[channel];
      var handle = bus != null
          ? bus.play(source, volume: volume, paused: at > 0)
          : _soloud.play(source, volume: volume, paused: at > 0);
      if (at > 0) {
        // Started paused and moved before it is heard, or the first moment
        // of the file plays before the range begins.
        _soloud.seek(handle, _duration(at));
        _soloud.setPause(handle, false);
      }
      return _SoLoudVoice(handle);
    } catch (exception) {
      debugPrint("Canvas audio could not play: $exception");
      return null;
    }
  }

  @override
  void volume(AudioVoice voice, double to, {double fade = 0}) {
    var handle = (voice as _SoLoudVoice).handle;
    if (!_soloud.getIsValidVoiceHandle(handle)) return;
    if (fade > 0) {
      _soloud.fadeVolume(handle, to, _duration(fade));
    } else {
      _soloud.setVolume(handle, to);
    }
  }

  @override
  void pause(AudioVoice voice, bool paused) {
    var handle = (voice as _SoLoudVoice).handle;
    if (_soloud.getIsValidVoiceHandle(handle)) {
      _soloud.setPause(handle, paused);
    }
  }

  @override
  void seek(AudioVoice voice, double at) {
    var handle = (voice as _SoLoudVoice).handle;
    if (_soloud.getIsValidVoiceHandle(handle)) {
      _soloud.seek(handle, _duration(at));
    }
  }

  @override
  double position(AudioVoice voice) {
    var handle = (voice as _SoLoudVoice).handle;
    if (!_soloud.getIsValidVoiceHandle(handle)) return 0;
    return _soloud.getPosition(handle).inMicroseconds / 1e6;
  }

  @override
  bool alive(AudioVoice voice) =>
      _soloud.isInitialized &&
      _soloud.getIsValidVoiceHandle((voice as _SoLoudVoice).handle);

  @override
  void stop(AudioVoice voice) {
    var handle = (voice as _SoLoudVoice).handle;
    if (_soloud.getIsValidVoiceHandle(handle)) unawaited(_soloud.stop(handle));
  }

  /// _bufferSeconds is how much sound SoLoud mixes at a time: the default
  /// 2048 frames at 44.1 kHz. A fade and a scheduled stop are only looked
  /// at once a buffer, and the level is ramped across the buffer toward
  /// wherever the fade has got by then.
  static const double _bufferSeconds = 2048 / 44100;

  @override
  void stopSoftly(AudioVoice voice, double fade) {
    var handle = (voice as _SoLoudVoice).handle;
    if (!_soloud.getIsValidVoiceHandle(handle)) return;
    _soloud.fadeVolume(handle, 0, _duration(fade));
    // Stopped two buffers after the fade is due to end, not as it ends. The
    // stop is acted on at the start of a buffer, and a fade shorter than a
    // buffer has only been ramped part of the way down by then -- so a stop
    // timed with it cut the sound off at that level, which is the click it
    // was there to prevent. Two buffers on, a whole buffer has ramped it to
    // nothing first; in between it is silent.
    _soloud.scheduleStop(handle, _duration(fade + 2 * _bufferSeconds));
  }

  @override
  void close(AudioTrack track) {
    if (!_soloud.isInitialized) return;
    unawaited(_soloud.disposeSource((track as _SoLoudTrack).source));
  }

  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());
}

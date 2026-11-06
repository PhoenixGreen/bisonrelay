import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

// audio_engine.dart is the one place a canvas touches a sound card.
//
// What plays (playlist, range, fades, loop, page) is decided in
// audio_runtime.dart, which speaks to this interface, so those rules can be
// tested against a fake engine with a test-driven clock.

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

  /// compFirst is the order: the compressor before the EQ, or after it.
  final bool compFirst;

  /// mix is the strip itself, solo and mute worked in, for an engine that
  /// runs the strip rather than approximating it -- see DartAudioEngine.
  final ChannelMix? mix;

  const ChannelSound(
      {this.left = 1,
      this.right = 1,
      this.eq,
      this.comp,
      this.compFirst = false,
      this.mix});
}

/// MasterSound is the master strip as the engine applies it.
class MasterSound {
  final double volume;
  final List<double>? eq;
  final Dynamics? comp;

  /// ceilingDb is the limiter's, or null for no limiter.
  final double? ceilingDb;

  /// compFirst is the order of the EQ and the glue. The limiter is last.
  final bool compFirst;

  /// mix is the master itself -- see ChannelSound.mix.
  final MasterMix? mix;

  const MasterSound(
      {this.volume = 1,
      this.eq,
      this.comp,
      this.ceilingDb,
      this.compFirst = false,
      this.mix});
}

/// busLevels splits a strip's level on each side into what SoLoud takes:
/// a volume, which may be over one (a fader above nought), and a pan for
/// each side, which may not: SoLoud throws for a pan over one, losing the
/// strip's EQ and compressor too.
(double, double, double) busLevels(double left, double right) {
  var loud = math.max(left, right);
  if (loud <= 0) return (0, 1, 1);
  return (loud, left / loud, right / loud);
}

/// reorderSteps is how to go from the filters running, [have], to [want],
/// both in order, when a filter switched on always lands last: switch off
/// everything from the first one out of place, then switch on the rest of
/// [want] in order.
(List<String>, List<String>) reorderSteps(
    List<String> have, List<String> want) {
  var keep = 0;
  while (keep < have.length && keep < want.length && have[keep] == want[keep]) {
    keep++;
  }
  return (have.sublist(keep), want.sublist(keep));
}

/// releaseAudioAfterHotRestart lets go of a sound engine the program left
/// running before a hot restart, as the app starts.
///
/// A hot restart keeps the native engine and its callbacks into the old,
/// gone program; any call into one (a device change, or deinit itself)
/// stops the VM with "Callback invoked after it has been deleted". So the
/// callbacks are forgotten first, by a native function the package has no
/// Dart binding for, and only then is the engine torn down. Debug only.
void releaseAudioAfterHotRestart() {
  if (!kDebugMode) return;
  try {
    var lib = Platform.isLinux || Platform.isAndroid
        ? ffi.DynamicLibrary.open("libflutter_soloud_plugin.so")
        : Platform.isWindows
            ? ffi.DynamicLibrary.open("flutter_soloud_plugin.dll")
            : ffi.DynamicLibrary.process();
    var forget = lib.lookupFunction<ffi.Void Function(), void Function()>(
        "clearDartCallbackRegistrations");
    var running =
        lib.lookupFunction<ffi.Int32 Function(), int Function()>("isInited");
    forget();
    if (running() == 1) SoLoud.instance.deinit();
  } catch (exception) {
    debugPrint("Could not release the canvas sound engine: $exception");
  }
}

/// AudioEngine is the sound card, as audio_runtime.dart drives it.
abstract class AudioEngine {
  /// start makes the engine ready, returning false where there is no sound to
  /// be had -- no device, or a library that would not load. Asked before
  /// every first play, and cheap once it has worked.
  Future<bool> start();

  /// open reads the file at [path], or returns null where it cannot.
  Future<AudioTrack?> open(String path);

  /// lengthOf is how long [track] is, in seconds.
  double lengthOf(AudioTrack track);

  /// metronome is a click on every beat of a bar of [beatsPerBar], a beat
  /// every [secondsPerBeat], as a track to play like any other -- or null
  /// from an engine that cannot make one.
  AudioTrack? metronome(double secondsPerBeat, int beatsPerBar);

  /// play starts [track] from [at] seconds in, at [volume], through the
  /// mixer channel called [channel] where it has one.
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel});

  /// launch plays [track] as a clip: from [delay] seconds from now -- to
  /// the frame, where the engine can -- from [at] seconds into it, going
  /// round [loop]'s two points, in seconds into the file, where given. See
  /// CanvasController.launchClip.
  AudioVoice? launch(AudioTrack track,
      {required double volume,
      required double delay,
      double at = 0,
      (double, double)? loop,
      String? channel});

  /// stopIn stops [voice] [delay] seconds from now: a clip stopped on the
  /// next bar.
  void stopIn(AudioVoice voice, double delay);

  /// latency is how far behind what is being rendered the speakers are, in
  /// seconds: a clip meant to be heard on a bar is started this much
  /// earlier.
  double get latency;

  /// setChannel makes or changes the mixer channel called [key].
  void setChannel(String key, ChannelSound sound);

  /// removeChannel lets go of channel [key], gone from the canvas: its
  /// strip no longer runs, and its sounds play on the master.
  void removeChannel(String key) {}

  /// setMaster is the master strip, over everything.
  void setMaster(MasterSound sound);

  /// setReturns is the returns the channels' sends feed. An engine that
  /// cannot send -- SoLoud's buses carry a sound to one place only --
  /// leaves them silent.
  void setReturns(List<ReturnChannel> returns);

  /// setScene is the bus of the scene playing (see CanvasScene.bus) and
  /// the channels heard through it. An engine with no buses of buses --
  /// SoLoud's -- plays the scene's channels straight to the master.
  void setScene(ChannelMix bus, Set<String> channels);

  /// setSpeakers is what the mix is for. The editor hears surround folded
  /// down to stereo; an engine with no surround hears it as stereo.
  void setSpeakers(SpeakerLayout layout);

  /// setPlacement is where the sound on channel [key] is heard from, taken
  /// from the picture -- or null for the channel's own pan. See
  /// SoundPlacement. SoLoud's buses cannot follow one, and leave it.
  void setPlacement(String key, Heard? heard);

  /// noteOn sounds [key] at [velocity] on channel [channel]'s instrument,
  /// played with [sound]'s sound -- on [font], where that is the bank.
  /// noteOff lets it go. An engine with no instruments of its own leaves
  /// them: what an instrument plays on the timeline is its rendered file.
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font});
  void noteOff(String channel, int key);

  /// control sets one of channel [channel]'s instrument's controllers --
  /// the mod wheel, the pitch bend, expression -- nought to one. An engine
  /// with no instruments of its own leaves it.
  void control(String channel, MidiControl control, double value);

  /// levels is how loud a channel -- or with no [channel], the master -- is
  /// coming out right now, left and right, nought to one. For the meters;
  /// asking for it is what turns the measuring on.
  (double, double) levels([String? channel]);

  /// deviceLevels is how loud channel [channel] is at each step of its
  /// strip right now, left and right, nought to one: coming in, after each
  /// device in order, then after its EQ and compressor in the order they
  /// run -- the meters between devices. Empty from an engine that cannot
  /// measure inside a strip. Asking is what turns the measuring on.
  List<(double, double)> deviceLevels(String channel);

  /// reduction is how many decibels [channel]'s compressor is taking off
  /// right now, or 0: none, or an engine that cannot say.
  double reduction(String channel);

  /// spectrum is what [channel] -- or the master -- is playing now, as 256
  /// magnitudes from the lowest frequency to half the rate, or null where
  /// none can be had. For the EQ to draw what it is shaping.
  Float32List? spectrum([String? channel]);

  /// pitch is the pitch a tuner on [channel] -- or Auto-tune -- is hearing
  /// now, or null: nothing heard, no tuner, or an engine with none.
  PitchReading? pitch([String? channel]);

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

/// _busSpectrum reads a bus's FFT, looked up by hand as _busMetering is.
final ffi.Pointer<ffi.Float> Function(int busId)? _busSpectrum = () {
  try {
    var lib = Platform.isLinux || Platform.isAndroid
        ? ffi.DynamicLibrary.open("libflutter_soloud_plugin.so")
        : Platform.isWindows
            ? ffi.DynamicLibrary.open("flutter_soloud_plugin.dll")
            : ffi.DynamicLibrary.process();
    return lib.lookupFunction<ffi.Pointer<ffi.Float> Function(ffi.UnsignedInt),
        ffi.Pointer<ffi.Float> Function(int)>("busCalcFFT");
  } catch (_) {
    return null;
  }
}();

/// _busMetering switches level-gathering on for one mixing bus; its meter
/// reads nothing until then. Looked up by hand: flutter_soloud 4.1 exports
/// the native function but has no Dart binding for it. Opening the library
/// as the package does hands back the one already loaded. Null where it
/// cannot be found, and the channel meters stay still.
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

/// soloudBufferFrames is the sound card's period, in frames, SoLoud is
/// started with, by whichever engine starts it first. SoLoud's own 2048,
/// three periods deep, is some 140 ms of latency, audibly late for a game
/// sound; 512 is a twelfth of a second all told, and still steady.
const int soloudBufferFrames = 512;

/// SoLoudAudioEngine plays through flutter_soloud.
class SoLoudAudioEngine implements AudioEngine {
  SoLoud get _soloud => SoLoud.instance;

  @override
  void setReturns(List<ReturnChannel> returns) {}

  @override
  void setScene(ChannelMix bus, Set<String> channels) {}

  Future<bool>? _starting;

  @override
  void setSpeakers(SpeakerLayout layout) {}

  @override
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font}) {}

  @override
  void noteOff(String channel, int key) {}

  @override
  void control(String channel, MidiControl control, double value) {}

  @override
  void setPlacement(String key, Heard? heard) {}

  /// No metronome on SoLoud's buses: the click is the mix engine's, made
  /// as it plays. See click_track.dart.
  @override
  AudioTrack? metronome(double secondsPerBeat, int beatsPerBar) => null;

  @override
  Future<bool> start() {
    if (_soloud.isInitialized) return Future.value(true);
    return _starting ??= () async {
      try {
        await _soloud.init(bufferSize: soloudBufferFrames);
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

  /// _soundRoom is how many voices are kept free for the sounds themselves,
  /// over and above one for every bus.
  static const _soundRoom = 32;

  /// _roomForBuses raises SoLoud's active voice limit so that [buses] buses
  /// and [_soundRoom] sounds all fit inside it.
  ///
  /// A bus is a voice that is always playing, and SoLoud only gives mixing
  /// buffers to as many voices as the limit (sixteen at first): past it the
  /// audio thread writes through a null pointer and the app crashes. A bus
  /// is made per timed sound. Raised in steps of 32, since every change
  /// reallocates SoLoud's buffers.
  void _roomForBuses(int buses) {
    var want = buses + _soundRoom;
    if (want <= _soloud.getMaxActiveVoiceCount()) return;
    // SoLoud refuses 1024 or more.
    _soloud.setMaxActiveVoiceCount(math.min(1000, (want + 31) ~/ 32 * 32));
  }

  @override
  void removeChannel(String key) {
    var bus = _buses.remove(key);
    _metered.remove(key);
    if (bus == null || !_soloud.isInitialized) return;
    try {
      bus.dispose();
    } catch (exception) {
      debugPrint("Unable to let go of the channel $key: $exception");
    }
  }

  /// _mostBuses is as many buses as SoLoud's voice limit -- under 1024 --
  /// holds with room for the sounds. A channel past it plays on the master
  /// rather than crashing the audio thread.
  static const _mostBuses = 1000 - _soundRoom;

  @override
  void setChannel(String key, ChannelSound sound) {
    if (!_soloud.isInitialized) return;
    try {
      var bus = _buses[key];
      if (bus == null) {
        if (_buses.length >= _mostBuses) return;
        _roomForBuses(_buses.length + 1);
        bus = Bus(name: key);
        bus.playOnEngine();
        _buses[key] = bus;
      }
      var handle = bus.soundHandle;
      if (handle != null) {
        var (volume, left, right) = busLevels(sound.left, sound.right);
        _soloud.setVolume(handle, volume);
        _soloud.setPanAbsolute(handle, left, right);
      }
      var f = bus.filters;
      var fresh = _arrange(key, [
        if (sound.compFirst && sound.comp != null) "comp",
        if (sound.eq != null) "eq",
        if (!sound.compFirst && sound.comp != null) "comp",
      ], {
        "eq": (
          on: () => f.parametricEqFilter.isActive,
          activate: f.parametricEqFilter.activate,
          deactivate: f.parametricEqFilter.deactivate,
        ),
        "comp": (
          on: () => f.compressorFilter.isActive,
          activate: f.compressorFilter.activate,
          deactivate: f.compressorFilter.deactivate,
        ),
      });
      _eq(fresh.contains("eq"), sound.eq,
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
        comp.makeupGain().value = c.totalMakeupDb;
        comp.kneeWidth().value = c.kneeDb;
        comp.wet().value = c.mix;
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
      var fresh = _arrange(_masterKey, [
        if (sound.compFirst && sound.comp != null) "comp",
        if (sound.eq != null) "eq",
        if (!sound.compFirst && sound.comp != null) "comp",
        // Last, whatever else is switched on after it: nothing may take a
        // peak back over the ceiling.
        if (sound.ceilingDb != null) "limiter",
      ], {
        "eq": (
          on: () => filters.parametricEqFilter.isActive,
          activate: filters.parametricEqFilter.activate,
          deactivate: filters.parametricEqFilter.deactivate,
        ),
        "comp": (
          on: () => filters.compressorFilter.isActive,
          activate: filters.compressorFilter.activate,
          deactivate: filters.compressorFilter.deactivate,
        ),
        "limiter": (
          on: () => filters.limiterFilter.isActive,
          activate: filters.limiterFilter.activate,
          deactivate: filters.limiterFilter.deactivate,
        ),
      });
      _eq(fresh.contains("eq"), sound.eq,
          bands: (n) => filters.parametricEqFilter.numBands.value = n,
          band: (i, g) => filters.parametricEqFilter.bandGain(i).value = g);
      var comp = filters.compressorFilter;
      if (sound.comp case var c?) {
        if (!comp.isActive) comp.activate();
        comp.threshold.value = c.threshold;
        comp.ratio.value = c.ratio;
        comp.attackTime.value = c.attackMs;
        comp.releaseTime.value = c.releaseMs;
        comp.makeupGain.value = c.totalMakeupDb;
        comp.kneeWidth.value = c.kneeDb;
        comp.wet.value = c.mix;
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

  /// _order is the effects switched on, by strip, in the order they were:
  /// the order SoLoud runs them in.
  final Map<String, List<String>> _order = {};
  static const _masterKey = "\u0000master";

  /// _arrange switches [filters] on and off so that those running are
  /// [want], in that order: SoLoud runs filters in the order they were
  /// switched on (see reorderSteps). Returns those switched on here, which
  /// need setting up afresh.
  Set<String> _arrange(
      String key,
      List<String> want,
      Map<
              String,
              ({
                bool Function() on,
                void Function() activate,
                void Function() deactivate
              })>
          filters) {
    var have = [
      for (var n in _order[key] ?? const <String>[])
        if (filters[n]!.on()) n,
      for (var e in filters.entries)
        if (e.value.on() && !(_order[key] ?? const []).contains(e.key)) e.key,
    ];
    var (off, on) = reorderSteps(have, want);
    for (var n in off) {
      filters[n]!.deactivate();
    }
    for (var n in on) {
      filters[n]!.activate();
    }
    _order[key] = want;
    return on.toSet();
  }

  /// _eq sets the band EQ to [gains]. [fresh] is whether _arrange has just
  /// switched it on, and its bands need counting out first.
  void _eq(bool fresh, List<double>? gains,
      {required void Function(double) bands,
      required void Function(int, double) band}) {
    // Switched off, if it is not wanted, by _arrange.
    if (gains == null) return;
    if (fresh) bands(_eqBands.toDouble());
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

  /// _masterData reads the whole mix's spectrum -- see spectrum.
  AudioData? _masterData;

  @override
  PitchReading? pitch([String? channel]) => null;

  @override
  Float32List? spectrum([String? channel]) {
    if (!_soloud.isInitialized) return null;
    // Gathered only while levels are being read -- see levels.
    levels(channel);
    try {
      if (channel == null) {
        // The whole mix: the package's own reader, which keeps the FFT and
        // the wave side by side.
        var data = _masterData ??= AudioData(GetSamplesKind.linear);
        data.updateSamples();
        var all = data.getAudioData();
        if (all.length < 256) return null;
        return Float32List.fromList(all.sublist(0, 256));
      }
      var bus = _buses[channel];
      var read = _busSpectrum;
      if (bus == null || read == null) return null;
      var data = read(bus.busId);
      if (data == ffi.nullptr) return null;
      return Float32List.fromList(data.asTypedList(256));
    } catch (_) {
      return null;
    }
  }

  /// deviceLevels: SoLoud runs a strip's filters as one, so there are no
  /// steps to measure between.
  @override
  List<(double, double)> deviceLevels(String channel) => const [];

  @override
  double reduction(String channel) => 0;

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

  // SoLoud plays a clip on a timer: on the bar to the timer's word, which is
  // near enough for the buses the mix engine has replaced.
  @override
  AudioVoice? launch(AudioTrack track,
      {required double volume,
      required double delay,
      double at = 0,
      (double, double)? loop,
      String? channel}) {
    var voice = play(track, volume: volume, at: at, channel: channel);
    if (voice is! _SoLoudVoice) return voice;
    var handle = voice.handle;
    try {
      if (delay > 0) {
        _soloud.setPause(handle, true);
        Timer(_duration(delay), () {
          if (_soloud.getIsValidVoiceHandle(handle)) {
            _soloud.setPause(handle, false);
          }
        });
      }
      if (loop case (var from, _)) {
        _soloud.setLooping(handle, true);
        _soloud.setLoopPoint(handle, _duration(from));
      }
    } catch (exception) {
      debugPrint("Canvas audio could not launch a clip: $exception");
    }
    return voice;
  }

  @override
  void stopIn(AudioVoice voice, double delay) {
    var handle = (voice as _SoLoudVoice).handle;
    if (!_soloud.getIsValidVoiceHandle(handle)) return;
    _soloud.scheduleStop(handle, _duration(delay));
  }

  @override
  double get latency => 0;

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

  /// _bufferSeconds is the most sound SoLoud mixes at a time: its default
  /// 2048 frames at 44.1 kHz (started at soloudBufferFrames it is less, so
  /// this errs long). Fades and scheduled stops are looked at once a buffer,
  /// the level ramped across it.
  static const double _bufferSeconds = 2048 / 44100;

  @override
  void stopSoftly(AudioVoice voice, double fade) {
    var handle = (voice as _SoLoudVoice).handle;
    if (!_soloud.getIsValidVoiceHandle(handle)) return;
    _soloud.fadeVolume(handle, 0, _duration(fade));
    // Stopped two buffers after the fade ends: a stop acts at a buffer's
    // start, when a short fade may be only part way down, which clicks.
    // Two buffers on, a whole buffer has ramped it to nothing.
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

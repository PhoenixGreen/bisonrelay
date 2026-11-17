import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show PitchReading;
import 'package:bruig/plugin_system/canvas/media/mix/analysers.dart'
    show Wave, LoudnessReading;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/surround.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/media/synth/soundfont.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

// audio_engine.dart is the one place a canvas touches a sound card. What
// plays is audio_runtime.dart's, tested against a fake engine and clock.

/// AudioTrack is a file the engine has opened, and AudioVoice one playing of
/// it. Opaque: only the engine that made one knows what is inside.
abstract class AudioTrack {}

abstract class AudioVoice {}

/// releaseAudioAfterHotRestart lets go of a sound engine left running
/// before a hot restart (debug only). Its native callbacks into the old
/// program stop the VM if called, so they are forgotten first.
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

abstract class AudioEngine {
  /// start makes the engine ready: false where there is no sound to be had
  /// (no device, or a library that would not load). Cheap once it has worked.
  Future<bool> start();

  /// open reads the file at [path], or returns null where it cannot.
  Future<AudioTrack?> open(String path);

  /// lengthOf is how long [track] is, in seconds.
  double lengthOf(AudioTrack track);

  /// metronome is a click on every beat of a bar of [beatsPerBar], a beat
  /// every [secondsPerBeat], as a track to play like any other.
  AudioTrack metronome(double secondsPerBeat, int beatsPerBar);

  /// play starts [track] from [at] seconds in, at [volume], through the
  /// mixer channel called [channel] where it has one.
  AudioVoice? play(AudioTrack track,
      {required double volume, double at = 0, String? channel});

  /// launch plays [track] as a clip [delay] seconds from now, from [at]
  /// seconds in, round [loop]'s points. See CanvasController.launchClip.
  AudioVoice? launch(AudioTrack track,
      {required double volume,
      required double delay,
      double at = 0,
      (double, double)? loop,
      String? channel});

  /// stopIn stops [voice] [delay] seconds from now, as on the next bar.
  void stopIn(AudioVoice voice, double delay);

  /// latency is how far behind the render the speakers are, in seconds: a
  /// clip meant for a bar is started this much earlier.
  double get latency;

  /// setChannel makes or changes the mixer channel called [key]: its strip,
  /// solo and mute worked in (see AudioRuntime.setMix).
  void setChannel(String key, ChannelMix mix);

  /// removeChannel lets go of channel [key]: its strip stops running and
  /// its sounds play on the master.
  void removeChannel(String key) {}

  void setMaster(MasterMix mix);

  void setReturns(List<ReturnChannel> returns);

  /// setScene is the bus of the scene playing (see CanvasScene.bus) and
  /// the channels heard through it.
  void setScene(ChannelMix bus, Set<String> channels);

  /// setSpeakers is what the mix is for. The editor hears surround folded
  /// down to stereo; an engine with no surround hears it as stereo.
  void setSpeakers(SpeakerLayout layout);

  /// setHear is which of a surround mix's speakers the editor plays on its
  /// two (see SpeakerGroup). An engine with no surround hears them all.
  void setHear(SpeakerGroup group);

  /// setPlacement is where channel [key] is heard from, from the picture,
  /// or null for its own pan. See SoundPlacement.
  void setPlacement(String key, Heard? heard);

  /// noteOn sounds [key] at [velocity] on channel [channel]'s instrument,
  /// with [sound] (on [font] for a bank); noteOff lets it go. An engine
  /// without instruments ignores both and plays the rendered file.
  void noteOn(String channel, InstrumentPart sound, int key, int velocity,
      {SoundFont? font});
  void noteOff(String channel, int key);

  /// control sets a controller of [channel]'s instrument (mod wheel, pitch
  /// bend, expression), nought to one.
  void control(String channel, MidiControl control, double value);

  /// livePatch sets [channel]'s synth patch as a knob turns; sounding notes
  /// carry on in it (see Sampler.patch).
  void livePatch(String channel, SynthPatch patch);

  /// levels is how loud [channel], or the master, is now, left and right,
  /// nought to one. For the meters; asking turns the measuring on.
  (double, double) levels([String? channel]);

  /// deviceLevels is [channel]'s left and right levels at each strip step:
  /// in, after each device, then after EQ and compressor. Empty where the
  /// engine cannot measure; asking turns measuring on.
  List<(double, double)> deviceLevels(String channel);

  /// deviceScope is what device [id] of [channel] ("" the master) passes
  /// now, or null (see device_scope.dart). Asking keeps it until [stopScope].
  ScopeReading? deviceScope(String channel, String id);

  /// stopScope stops keeping what device [id] of [channel]'s strip passes.
  void stopScope(String channel, String id);

  /// listenAt hears [channel] from chain step [step] (nought is its input)
  /// instead of its end; null hears all again.
  void listenAt(String channel, int? step);

  /// reduction is how many decibels [channel]'s compressor is taking off
  /// right now, or 0: none, or an engine that cannot say.
  double reduction(String channel);

  /// spectrum is what [channel], or the master, is playing now: 256
  /// magnitudes up to half the rate, or null. For the EQ to draw.
  Float32List? spectrum([String? channel]);

  /// pitch is the pitch a tuner on [channel] -- or Auto-tune -- is hearing
  /// now, or null: nothing heard, no tuner, or an engine with none.
  PitchReading? pitch([String? channel]);

  /// wave is the latest reading of [channel]'s first analyser of [kind] (a
  /// Scope or a Stereo Image), or null.
  Wave? wave(DeviceKind kind, [String? channel]);

  /// loudness is [channel]'s first Loudness's reading, or null.
  LoudnessReading? loudness([String? channel]);

  /// resetLoudness starts [channel]'s Loudness measuring again.
  void resetLoudness([String? channel]);

  /// volume moves [voice] to [to], over [fade] seconds.
  void volume(AudioVoice voice, double to, {double fade = 0});

  /// route sends [voice] through [channel]'s strip, or the master with
  /// null: a sound started before its channel was known joins it later.
  void route(AudioVoice voice, String? channel);

  void pause(AudioVoice voice, bool paused);

  /// seek moves [voice] to [at] seconds into its file.
  void seek(AudioVoice voice, double at);

  /// position is how far into the file [voice] has got, in seconds.
  double position(AudioVoice voice);

  /// alive is whether [voice] is still playing or paused -- false once it has
  /// reached the end of the file or been stopped.
  bool alive(AudioVoice voice);

  void stop(AudioVoice voice);

  /// stopSoftly fades [voice] out over [fade] seconds, then stops it, on the
  /// sound card's own clock: a sound stopped outright clicks.
  void stopSoftly(AudioVoice voice, double fade);

  void close(AudioTrack track);

  /// peaks is [count] values, nought to one, each the loudest moment in its
  /// share of the file at [path]; for drawing only. Null where unreadable.
  Future<Float32List?> peaks(String path, int count);
}

/// soloudBufferFrames is SoLoud's period: its own 2048, three deep, is some
/// 140 ms, audibly late for a game sound; 512 is still steady.
const int soloudBufferFrames = 512;

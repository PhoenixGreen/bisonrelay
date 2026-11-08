import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

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

// audio_engine.dart is the one place a canvas touches a sound card.
//
// What plays (playlist, range, fades, loop, page) is decided in
// audio_runtime.dart, which speaks to this interface, so those rules can be
// tested against a fake engine with a test-driven clock.

/// AudioTrack is a file the engine has opened, and AudioVoice one playing of
/// it. Opaque: only the engine that made one knows what is inside.
abstract class AudioTrack {}

abstract class AudioVoice {}

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
  /// every [secondsPerBeat], as a track to play like any other.
  AudioTrack metronome(double secondsPerBeat, int beatsPerBar);

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

  /// setChannel makes or changes the mixer channel called [key]: its strip,
  /// solo and mute worked in (see AudioRuntime.setMix).
  void setChannel(String key, ChannelMix mix);

  /// removeChannel lets go of channel [key], gone from the canvas: its
  /// strip no longer runs, and its sounds play on the master.
  void removeChannel(String key) {}

  /// setMaster is the master strip, over everything.
  void setMaster(MasterMix mix);

  /// setReturns is the returns the channels' sends feed.
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

  /// setPlacement is where the sound on channel [key] is heard from, taken
  /// from the picture -- or null for the channel's own pan. See
  /// SoundPlacement.
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

  /// deviceScope is what device [id] of [channel]'s strip ("" for the
  /// master's) is passing now -- see device_scope.dart -- or null: not kept
  /// yet, or an engine that cannot. Asking starts the keeping, which goes
  /// on until [stopScope].
  ScopeReading? deviceScope(String channel, String id);

  /// stopScope stops keeping what device [id] of [channel]'s strip passes.
  void stopScope(String channel, String id);

  /// listenAt hears [channel] from step [step] of its chain -- the sound
  /// coming in (nought), or after that many steps -- in place of its end;
  /// null hears all of it again. Nothing where an engine cannot.
  void listenAt(String channel, int? step);

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

  /// wave is the latest of what [channel]'s first analyser of [kind] (a
  /// Scope or a Stereo Image) heard, where it is in the chain; null with
  /// none, or an engine with none.
  Wave? wave(DeviceKind kind, [String? channel]);

  /// loudness is [channel]'s first Loudness's reading, or null.
  LoudnessReading? loudness([String? channel]);

  /// resetLoudness starts [channel]'s Loudness measuring again.
  void resetLoudness([String? channel]);

  /// volume moves [voice] to [to], over [fade] seconds.
  void volume(AudioVoice voice, double to, {double fade = 0});

  /// route sends [voice] through channel [channel]'s strip from now on --
  /// or straight to the master, with null: a sound started before its
  /// channel was known is put through its chain once it is.
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

/// soloudBufferFrames is the sound card's period, in frames, SoLoud -- which
/// carries the mix engine's stream to it -- is started with. SoLoud's own 2048,
/// three periods deep, is some 140 ms of latency, audibly late for a game
/// sound; 512 is a twelfth of a second all told, and still steady.
const int soloudBufferFrames = 512;

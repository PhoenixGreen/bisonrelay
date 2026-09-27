import 'dart:async';

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

abstract class AudioEngine {
  /// start makes the engine ready, returning false where there is no sound to
  /// be had -- no device, or a library that would not load. Asked before
  /// every first play, and cheap once it has worked.
  Future<bool> start();

  /// open reads the file at [path], or returns null where it cannot.
  Future<AudioTrack?> open(String path);

  /// lengthOf is how long [track] is, in seconds.
  double lengthOf(AudioTrack track);

  /// play starts [track] from [at] seconds in, at [volume].
  AudioVoice? play(AudioTrack track, {required double volume, double at = 0});

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

  void close(AudioTrack track);
}

class _SoLoudTrack extends AudioTrack {
  final AudioSource source;
  _SoLoudTrack(this.source);
}

class _SoLoudVoice extends AudioVoice {
  final SoundHandle handle;
  _SoLoudVoice(this.handle);
}

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

  @override
  AudioVoice? play(AudioTrack track, {required double volume, double at = 0}) {
    try {
      var handle = _soloud.play((track as _SoLoudTrack).source,
          volume: volume, paused: at > 0);
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

  @override
  void close(AudioTrack track) {
    if (!_soloud.isInitialized) return;
    unawaited(_soloud.disposeSource((track as _SoLoudTrack).source));
  }

  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());
}

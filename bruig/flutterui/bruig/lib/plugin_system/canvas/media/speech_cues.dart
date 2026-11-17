import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/speech_engines.dart'
    show upsample2x;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// speech_cues.dart is our voices' non-word cues: breaths, laughs, sighs and
// coughs are CC0 recordings (assets/canvas/cues/SOURCES.md), a whisper the
// voice said softly.

final Map<String, Future<Float32List?>> _loaded = {};

/// cueRecording is [cue]'s recording at the mix rate, a man's or a woman's,
/// or null for a cue with none or one that could not be read.
Future<Float32List?> cueRecording(SpeechCue cue, {required bool man}) {
  if (!cue.sound) return Future.value(null);
  var name = "${man ? "man" : "woman"}-${cue.name}";
  return _loaded[name] ??= () async {
    try {
      var data = await rootBundle.load("assets/canvas/cues/$name.wav");
      var pcm = readWav16(data);
      if (pcm == null) throw const FormatException("not 16-bit mono PCM");
      return upsample2x(pcm);
    } catch (exception) {
      // Not cached: tried again next time.
      debugPrint("The $name sound could not be read: $exception");
      unawaited(_loaded.remove(name));
      return null;
    }
  }();
}

/// readWav16 is the samples of a mono 16-bit PCM WAV, or null for any other
/// file.
Float32List? readWav16(ByteData b) {
  String tag(int at) =>
      String.fromCharCodes([for (var i = 0; i < 4; i++) b.getUint8(at + i)]);
  if (b.lengthInBytes < 12 || tag(0) != "RIFF" || tag(8) != "WAVE") {
    return null;
  }
  var mono16 = false;
  for (var at = 12; at + 8 <= b.lengthInBytes;) {
    var id = tag(at);
    var size = b.getUint32(at + 4, Endian.little);
    var body = at + 8;
    if (id == "fmt ") {
      mono16 = b.getUint16(body, Endian.little) == 1 &&
          b.getUint16(body + 2, Endian.little) == 1 &&
          b.getUint16(body + 14, Endian.little) == 16;
    } else if (id == "data") {
      if (!mono16) return null;
      var n = math.min(size, b.lengthInBytes - body) ~/ 2;
      return Float32List.fromList([
        for (var i = 0; i < n; i++)
          b.getInt16(body + 2 * i, Endian.little) / 32768,
      ]);
    }
    // Chunks are padded to an even length.
    at = body + size + (size & 1);
  }
  return null;
}

/// softly is [voice] at [by] as loud: neither engine can whisper, and
/// voice-shaped hiss sounds like a vocoder (which the Vocoder effect does).
Float32List softly(Float32List voice, {required double by}) =>
    Float32List.fromList([for (var v in voice) v * by]);

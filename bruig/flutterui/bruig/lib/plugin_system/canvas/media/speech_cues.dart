import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/vocoder.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart'
    show upsample2x;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// speech_cues.dart is what our own voices do for the cues of a script that
// are not words. A breath, a laugh, a sigh and a cough are recordings -- a
// woman's and a man's, each CC0 from Freesound, listed in
// assets/canvas/cues/SOURCES.md -- put between the words as they are. A
// whisper is the voice itself, laid onto hiss by the Vocoder: each band of
// it as loud as the voice's, none of it voiced.

final Map<String, Future<Float32List?>> _loaded = {};

/// cueRecording is [cue]'s recording at the mix rate -- a man's or a
/// woman's -- or null for a cue with none, or one that could not be read.
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
      // Not kept: tried again next time.
      debugPrint("The $name sound could not be read: $exception");
      _loaded.remove(name);
      return null;
    }
  }();
}

/// readWav16 is the samples of a mono 16-bit PCM WAV, or null for a file of
/// any other kind.
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

/// _whisper is the Vocoder as a whisper: hiss carrying the voice, its
/// bands up to 12kHz so the hiss says the s and t sounds too. None of the
/// voice's own sound comes through -- its highs are still pitched -- and
/// the bands follow it no faster than 25ms, slower than a pitch's period,
/// which they would otherwise beat at.
const _whisper = MixDevice(DeviceKind.vocoder, values: {
  "carrier": 0,
  "bands": 28,
  "high": 12000,
  "unvoiced": 0,
  "attack": 25,
  "release": 50,
});

/// whispered is [voice], at the mix rate, whispered -- and quieter, by
/// a little, as a whisper is.
Float32List whispered(Float32List voice) {
  var v = Vocoder(_whisper);
  var out = Float32List.fromList(voice);
  var other = Float32List(512);
  for (var at = 0; at < out.length; at += 512) {
    var n = math.min(512, out.length - at);
    var block = Float32List.sublistView(out, at, at + n);
    other.setRange(0, n, block);
    v.process(block, other, n);
  }
  for (var i = 0; i < out.length; i++) {
    out[i] *= 0.75;
  }
  return out;
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/media/speech_cues.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_speech_cues_test.dart is what our own voices do for a script's
// cues that are not words: the recorded breaths, laughs, sighs and coughs,
// a woman's and a man's, and a whisper made by the Vocoder.

double rms(Float32List x, [int from = 0]) {
  var s = 0.0;
  for (var i = from; i < x.length; i++) {
    s += x[i] * x[i];
  }
  return math.sqrt(s / math.max(1, x.length - from));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("every sound cue has a recording, a woman's and a man's", () async {
    for (var man in [false, true]) {
      for (var cue in SpeechCue.values.where((c) => c.sound)) {
        var why = "${man ? "man" : "woman"} ${cue.name}";
        var sound = await cueRecording(cue, man: man);
        expect(sound, isNotNull, reason: why);
        var seconds = sound!.length / 48000;
        expect(seconds, inInclusiveRange(0.3, 3), reason: why);
        var peak = sound.fold(0.0, (m, v) => math.max(m, v.abs()));
        expect(peak, inInclusiveRange(0.05, 0.95), reason: why);
        // Faded at both ends: no click going in or coming out.
        expect(sound.first.abs(), lessThan(0.01), reason: why);
        expect(sound.last.abs(), lessThan(0.01), reason: why);
      }
    }
    // A cue that is no sound has none.
    expect(await cueRecording(SpeechCue.whisper, man: false), isNull);
  });

  test("only mono 16-bit WAVs are read", () {
    ByteData wav(int channels, int bits) {
      var b = ByteData(44 + 8);
      void tag(int at, String s) {
        for (var i = 0; i < 4; i++) {
          b.setUint8(at + i, s.codeUnitAt(i));
        }
      }

      tag(0, "RIFF");
      b.setUint32(4, 44, Endian.little);
      tag(8, "WAVE");
      tag(12, "fmt ");
      b.setUint32(16, 16, Endian.little);
      b.setUint16(20, 1, Endian.little);
      b.setUint16(22, channels, Endian.little);
      b.setUint32(24, 24000, Endian.little);
      b.setUint16(34, bits, Endian.little);
      tag(36, "data");
      b.setUint32(40, 8, Endian.little);
      b.setInt16(44, 16384, Endian.little);
      b.setInt16(46, -32768, Endian.little);
      return b;
    }

    expect(readWav16(wav(1, 16)), [0.5, -1, 0, 0]);
    expect(readWav16(wav(2, 16)), isNull);
    expect(readWav16(wav(1, 24)), isNull);
    expect(readWav16(ByteData(8)), isNull);
  });

  test("a whisper keeps the voice's shape but not its pitch", () {
    // A voiced vowel: a saw at 140 Hz, through a resonance or two.
    var n = 48000;
    var voice = Float32List(n);
    for (var i = 0; i < n; i++) {
      var t = i / 48000;
      voice[i] = 0.3 * (2 * ((t * 140) % 1) - 1);
    }
    var window =
        (Float32List x) => Float32List.fromList(x.sublist(24000, 26048));
    expect(detectPitch(window(voice))!.clarity, greaterThan(0.8));
    var hushed = whispered(voice);
    var heard = detectPitch(window(hushed));
    expect(heard == null || heard.clarity < 0.5, isTrue,
        reason: "no pitch left: ${heard?.hz} at ${heard?.clarity}");
    expect(rms(hushed, 4800), lessThan(rms(voice, 4800)));
    expect(rms(hushed, 4800), greaterThan(rms(voice, 4800) * 0.1),
        reason: "quieter, not gone");
  });
}

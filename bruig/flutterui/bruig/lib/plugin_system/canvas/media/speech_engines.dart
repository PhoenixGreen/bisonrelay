import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/decode.dart';
import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// speech_engines.dart speaks a Speech device's script with voices of our
// own, on this computer: Kokoro (kokoro_speech.dart) or the expressive
// voices (qwen_speech.dart).
//
// Our own voices speak the script a piece at a time (see parseScript), and
// the pieces are put end to end here as one take at the mix's rate: the
// words as the engine says them, a pause as silence. Each word is kept with
// its time, spread across its stretch by length.

/// SpeechVoice is a voice an engine can speak in.
class SpeechVoice {
  final String id;
  final String name;

  /// about is what it sounds like: its accent or language, and how.
  final String about;

  /// gender is "f" or "m" where the engine says, for the filter; "" where
  /// it does not.
  final String gender;
  const SpeechVoice(this.id, this.name, this.about, {this.gender = ""});
}

/// SpokenAudio is a take: the sound, at the mix rate, and its words.
class SpokenAudio {
  final Float32List l, r;
  final List<TimedWord> words;
  final bool exact;
  const SpokenAudio(this.l, this.r, this.words, {this.exact = false});

  double get seconds => l.length / mixRate;
}

/// SpeechException is a take that could not be spoken, with why.
class SpeechException implements Exception {
  final String message;
  const SpeechException(this.message);
  @override
  String toString() => message;
}

abstract class SpeechEngine {
  Future<List<SpeechVoice>> voices();
  Future<SpokenAudio> speak(SpeechSpec spec);

  /// speakLine speaks one of the device's lines as directed -- by default
  /// as a script of its own, its direction the nearest cue the engine has.
  /// Another [seed] is another take, where the engine can vary.
  Future<SpokenAudio> speakLine(SpeechSpec spec, SpeechLine line,
          {int seed = 1}) =>
      speak(spec.copyWith(script: lineScript(line), lines: const []));

  /// batches is whether speakLines does better than one line at a time --
  /// an engine that loads its voice for each call loads it once.
  bool get batches => false;

  /// speakLines speaks [lines], a take of each, in order: by default one at
  /// a time.
  Future<List<SpokenAudio>> speakLines(
          SpeechSpec spec, List<SpeechLine> lines) async =>
      [for (var l in lines) await speakLine(spec, l)];
}

/// lineScript is [line] as a script of its own: its direction as the
/// nearest of our cues, then its words.
String lineScript(SpeechLine line) =>
    "${line.direction.kokoro} ${line.text}".trim();

/// speechRunsOn is whether a line of [words] words, said at [speed], that
/// came out [seconds] long ran on or stopped short: far longer or shorter
/// than its words should take, at about two and a half a second.
bool speechRunsOn(double seconds, int words, double speed) {
  var expected = words * 0.4 / speed.clamp(0.5, 2.0);
  return seconds > expected * 2.2 + 1.5 || seconds < expected * 0.35;
}

/// decodeFile reads [file] whole through the mix engine's decoder.
(Float32List, Float32List)? decodeFile(String file) => readWhole(file);

// ---------------------------------------------------------------------------
// Putting a take together
// ---------------------------------------------------------------------------

/// assembleTake puts [pieces] end to end, as one take: each the sound of a
/// piece and its words in seconds from the piece's own start.
SpokenAudio assembleTake(
    List<(Float32List, Float32List, List<TimedWord>)> pieces,
    {bool exact = false}) {
  var total = pieces.fold(0, (n, p) => n + p.$1.length);
  var l = Float32List(total), r = Float32List(total);
  var words = <TimedWord>[];
  var at = 0;
  for (var (pl, pr, pw) in pieces) {
    l.setRange(at, at + pl.length, pl);
    r.setRange(at, at + pr.length, pr);
    var offset = at / mixRate;
    for (var w in pw) {
      words.add((text: w.text, start: w.start + offset, end: w.end + offset));
    }
    at += pl.length;
  }
  return SpokenAudio(l, r, words, exact: exact);
}

(Float32List, Float32List, List<TimedWord>) silence(double seconds) {
  var n = (seconds * mixRate).round();
  return (Float32List(n), Float32List(n), const []);
}

const _halfTaps = 16;

/// _between are the weights of the samples either side of a point halfway
/// between two: a sinc, windowed by a Blackman window, summing to one.
final _between = () {
  var w = Float64List(_halfTaps * 2);
  for (var k = 0; k < _halfTaps * 2; k++) {
    var t = k - _halfTaps + 0.5; // from the point, in samples
    var sinc = math.sin(math.pi * t) / (math.pi * t);
    var u = (k + 0.5) / (_halfTaps * 2);
    var window = 0.42 -
        0.5 * math.cos(2 * math.pi * u) +
        0.08 * math.cos(4 * math.pi * u);
    w[k] = sinc * window;
  }
  var sum = w.reduce((a, b) => a + b);
  for (var k = 0; k < w.length; k++) {
    w[k] /= sum;
  }
  return w;
}();

/// upsample2x is [x] at twice its rate: its own samples, and between each
/// two the sound's value there -- read from a windowed sinc, not a straight
/// line, which would leave a hiss of mirrored highs over a voice.
Float32List upsample2x(Float32List x) {
  var n = x.length;
  var out = Float32List(n * 2);
  for (var i = 0; i < n; i++) {
    out[i * 2] = x[i];
    var v = 0.0;
    for (var k = 0; k < _halfTaps * 2; k++) {
      var j = i + k - _halfTaps + 1;
      if (j >= 0 && j < n) v += x[j] * _between[k];
    }
    out[i * 2 + 1] = v;
  }
  return out;
}

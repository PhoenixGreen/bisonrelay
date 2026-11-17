import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart' show mixRate;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// speech_engines.dart speaks a Speech device's script with our own voices,
// Kokoro or the expressive ones, a piece at a time (see parseScript), joined
// here into one take at the mix rate. Word times come from speech_timing.

class SpeechVoice {
  final String id;
  final String name;

  /// about is what it sounds like: its accent or language, and how.
  final String about;

  /// gender is "f" or "m" where the engine says, for the filter, else "".
  final String gender;
  const SpeechVoice(this.id, this.name, this.about, {this.gender = ""});
}

/// SpokenAudio is a take: the sound at the mix rate, and its words.
class SpokenAudio {
  final Float32List l, r;
  final List<TimedWord> words;

  /// exact is as SpeechTake.exact: the word times are not estimated.
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

/// SpeechStopped is a take not spoken because Stop was pressed.
class SpeechStopped extends SpeechException {
  const SpeechStopped() : super("Stopped.");
}

/// SpeechStop is Stop for the engine speaking: whether it was pressed, and
/// what to do when it is (a running program to end).
class SpeechStop {
  bool _stopped = false;
  final _then = <void Function()>{};

  bool get stopped => _stopped;

  void stop() {
    if (_stopped) return;
    _stopped = true;
    for (var f in [..._then]) {
      f();
    }
    _then.clear();
  }

  /// whenStopped does [f] when Stop is pressed (now, if it was) and returns
  /// how to forget it.
  void Function() whenStopped(void Function() f) {
    if (_stopped) {
      f();
      return () {};
    }
    _then.add(f);
    return () => _then.remove(f);
  }

  /// check throws SpeechStopped once Stop is pressed: called between runs.
  void check() {
    if (_stopped) throw const SpeechStopped();
  }
}

abstract class SpeechEngine {
  /// stopper is Stop for what this engine speaks: a running program is
  /// ended; an engine that cannot stop mid-way stops between takes.
  SpeechStop stopper = SpeechStop();

  Future<List<SpeechVoice>> voices();
  Future<SpokenAudio> speak(SpeechSpec spec);

  /// speakLine speaks one line as directed, by default as its own script.
  /// Another [seed] is another take, where the engine can vary.
  Future<SpokenAudio> speakLine(SpeechSpec spec, SpeechLine line,
          {int seed = 1}) =>
      speak(spec.copyWith(script: lineScript(line), lines: const []));

  /// batches is whether speakLines beats one line at a time, as for an
  /// engine that loads its voice on each call.
  bool get batches => false;

  /// speakLines speaks a take of each of [lines] in order: by default one
  /// at a time.
  Future<List<SpokenAudio>> speakLines(
          SpeechSpec spec, List<SpeechLine> lines) async =>
      [for (var l in lines) await speakLine(spec, l)];
}

/// lineScript is [line] as a script of its own: its direction as our
/// nearest cue, then its words.
String lineScript(SpeechLine line) =>
    "${line.direction.kokoro} ${line.text}".trim();

/// speechRunsOn is whether a [words]-word line at [speed] that came out
/// [seconds] long ran on or stopped short, at about 2.5 words a second.
bool speechRunsOn(double seconds, int words, double speed) {
  var expected = words * 0.4 / speed.clamp(0.5, 2.0);
  return seconds > expected * 2.2 + 1.5 || seconds < expected * 0.35;
}

// ---- Putting a take together ---------------------------------------------

/// assembleTake joins [pieces] into one take: each a piece's sound and its
/// words in seconds from the piece's start.
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

/// silence is [seconds] of quiet, as a piece for [assembleTake].
(Float32List, Float32List, List<TimedWord>) silence(double seconds) {
  var n = (seconds * mixRate).round();
  return (Float32List(n), Float32List(n), const []);
}

const _halfTaps = 16;

/// _between are the weights of the samples either side of a halfway point:
/// a Blackman-windowed sinc, summing to one.
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

/// upsample2x is [x] at twice its rate, the new samples read from a
/// windowed sinc: a straight line would leave a hiss of mirrored highs.
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

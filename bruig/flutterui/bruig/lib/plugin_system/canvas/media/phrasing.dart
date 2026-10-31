import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// phrasing.dart shapes a take's words after it is spoken: the voice cannot
// be told to raise one word, or draw out another, so the take is changed
// afterwards, a word at a time -- its pitch moved by PSOLA, which keeps the
// voice its own (as Auto-tune does), its length changed by the same slices
// laid further apart or closer (as Warp does), its loudness a gain. A word
// left as it was is copied as it was, and each joins the next across 5ms,
// so nothing clicks where they meet.
//
// readTake is what the Phrasing panel opens on: each word's pitch, read
// along it, and how loud it is.

/// TakeReading is a take as the voice said it: its pitch every 20ms, as a
/// MIDI note -- null where nothing is voiced -- each word's loudness in
/// dB, and the voice's middle, the note it speaks about.
class TakeReading {
  final List<double?> pitch;
  final List<double> levels;
  final double middle;
  const TakeReading(this.pitch, this.levels, this.middle);

  /// frame is how long each reading of [pitch] is, in seconds.
  static const frame = 0.02;

  /// pitchOf is [word]'s pitch along it: the readings within it.
  List<double?> pitchOf(TimedWord word) {
    var from = (word.start / frame).round().clamp(0, pitch.length);
    var to = (word.end / frame).round().clamp(from, pitch.length);
    return pitch.sublist(from, to);
  }

  /// meanOf is [word]'s pitch as a whole: the mean of its voiced readings,
  /// or null for a word with none -- a whispered one, an "s".
  double? meanOf(TimedWord word) {
    var voiced = pitchOf(word).whereType<double>().toList();
    return voiced.isEmpty
        ? null
        : voiced.reduce((a, b) => a + b) / voiced.length;
  }
}

/// readTake reads [pcm] -- a take, mono, at [rate] -- and its [words]: the
/// pitch heard every 20ms, at a third of the rate, where a voice's pitch
/// still is and YIN costs a ninth.
TakeReading readTake(Float32List pcm, List<TimedWord> words,
    {double rate = 48000}) {
  const down = 3;
  var low = Float32List(pcm.length ~/ down);
  for (var i = 0; i < low.length; i++) {
    low[i] = (pcm[i * down] + pcm[i * down + 1] + pcm[i * down + 2]) / down;
  }
  var lowRate = rate / down;
  var window = (lowRate * 0.04).round();
  var hop = lowRate * TakeReading.frame;
  var pitch = <double?>[];
  for (var at = 0.0; at < low.length; at += hop) {
    var from = (at - window / 2)
        .round()
        .clamp(0, math.max(0, low.length - window))
        .toInt();
    if (low.length < window) {
      pitch.add(null);
      continue;
    }
    var p = detectPitch(Float32List.sublistView(low, from, from + window),
        rate: lowRate, minHz: 60, maxHz: 500);
    pitch.add(p == null || p.clarity < 0.6 ? null : midiOf(p.hz));
  }
  var levels = [
    for (var w in words)
      () {
        var from = (w.start * rate).round().clamp(0, pcm.length);
        var to = (w.end * rate).round().clamp(from, pcm.length);
        if (to <= from) return -60.0;
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += pcm[i] * pcm[i];
        }
        return math.max(
            -60.0, 10 * math.log(sum / (to - from) + 1e-12) / math.ln10);
      }(),
  ];
  var voiced = pitch.whereType<double>().toList()..sort();
  var middle = voiced.isEmpty ? 50.0 : voiced[voiced.length ~/ 2];
  return TakeReading(pitch, levels, middle);
}

/// _Piece is a stretch of the take as shaped: [from] to [to] in the take
/// as spoken, in samples, made [length] samples long -- or, with no
/// source, a pause that long -- [word] the word it is, or -1 between.
typedef _Piece = ({int from, int to, int length, int word, bool silent});

List<_Piece> _pieces(
    List<TimedWord> words, List<WordShape> shapes, int total, double rate) {
  var out = <_Piece>[];
  var at = 0;
  for (var (i, w) in words.indexed) {
    var from = (w.start * rate).round().clamp(at, total);
    var to = (w.end * rate).round().clamp(from, total);
    if (from > at) {
      out.add((from: at, to: from, length: from - at, word: -1, silent: false));
    }
    var shape = i < shapes.length ? shapes[i] : WordShape.plain;
    out.add((
      from: from,
      to: to,
      length: ((to - from) * shape.length).round(),
      word: i,
      silent: false
    ));
    if (shape.pause > 0) {
      var n = (shape.pause * rate).round();
      out.add((from: to, to: to, length: n, word: -1, silent: true));
    }
    at = to;
  }
  if (total > at) {
    out.add((from: at, to: total, length: total - at, word: -1, silent: false));
  }
  return out;
}

/// shapedWords is where [words] are once shaped by [shapes], in a take
/// [seconds] long as spoken: what the panel lays its words out by, and the
/// shaped take's words.
List<TimedWord> shapedWords(
    List<TimedWord> words, List<WordShape> shapes, double seconds,
    {double rate = 48000}) {
  var at = 0;
  var out = <TimedWord>[];
  for (var p in _pieces(words, shapes, (seconds * rate).round(), rate)) {
    if (p.word >= 0) {
      out.add((
        text: words[p.word].text,
        start: at / rate,
        end: (at + p.length) / rate
      ));
    }
    at += p.length;
  }
  return out;
}

/// shapeTake is [pcm] -- a take, mono, at [rate], as spoken -- with its
/// [words] shaped by [shapes], [reading] being what was heard of it: the
/// sound, and its words where they are now.
({Float32List sound, List<TimedWord> words}) shapeTake(Float32List pcm,
    List<TimedWord> words, List<WordShape> shapes, TakeReading reading,
    {double rate = 48000}) {
  var margin = (rate * 0.005).round();
  var pieces = _pieces(words, shapes, pcm.length, rate);
  var total = pieces.fold(0, (n, p) => n + p.length);
  // Laid from a margin before the start: each piece reaches a margin into
  // its neighbours either side, and fades across both margins into them.
  var out = Float32List(total + 2 * margin);
  var at = 0;
  for (var p in pieces) {
    var shape = p.word >= 0 && p.word < shapes.length
        ? shapes[p.word]
        : WordShape.plain;
    var n = p.length + 2 * margin;
    Float32List piece;
    if (p.silent) {
      piece = Float32List(n);
    } else if (shape.pitch == 0 && shape.inflection == 1 && shape.length == 1) {
      piece = Float32List(n);
      for (var j = 0; j < n; j++) {
        var src = p.from - margin + j;
        if (src >= 0 && src < pcm.length) piece[j] = pcm[src];
      }
    } else {
      piece = _psola(
          pcm, p, margin, shape, reading.meanOf(words[p.word]), reading, rate);
    }
    var gain = math.pow(10, shape.loudness / 20).toDouble();
    var fade = 2 * margin;
    for (var j = 0; j < n; j++) {
      var w = 1.0;
      if (j < fade) w = math.min(w, j / fade);
      if (j >= n - fade) w = math.min(w, (n - j) / fade);
      out[at + j] += piece[j] * w * gain;
    }
    at += p.length;
  }
  var sound = Float32List.sublistView(out, margin, margin + total);
  return (
    sound: Float32List.fromList(sound),
    words: shapedWords(words, shapes, pcm.length / rate, rate: rate),
  );
}

/// _psola is piece [p] of [pcm], with a margin either side, said as
/// [shape] says: [mean] the word's own pitch, about which its rise and
/// fall is made more or less of. Two-period slices of the take, each at a
/// period of its voice from the last, are laid down a period of the new
/// pitch apart, read through the word as fast as its new length says --
/// so a slice may be laid twice, drawn out, or skipped, hurried.
Float32List _psola(Float32List pcm, _Piece p, int margin, WordShape shape,
    double? mean, TakeReading reading, double rate) {
  var n = p.length + 2 * margin;
  var out = Float32List(n);
  var weight = Float32List(n);
  var core = p.to - p.from;
  // Where in the take each moment of the piece is read from: the margins
  // as they were, the word through its new length.
  double sourceAt(double u) {
    if (u < margin) return p.from - margin + u;
    if (u < margin + p.length) {
      return p.from + (p.length == 0 ? 0 : (u - margin) * core / p.length);
    }
    return p.to + (u - margin - p.length);
  }

  double? hzAt(num x) {
    var f = (x / rate / TakeReading.frame).round();
    if (f < 0 || f >= reading.pitch.length) return null;
    var m = reading.pitch[f];
    return m == null ? null : 440 * math.pow(2, (m - 69) / 12).toDouble();
  }

  // The take's own marks, a period of its voice apart -- or, unvoiced, a
  // steady 120th of a second.
  var marks = <int>[];
  var end = p.to + margin;
  for (var m = (p.from - margin).toDouble(); m < end;) {
    marks.add(m.round());
    m += rate / (hzAt(m) ?? 120);
  }
  var k = 0;
  for (var u = 0.0; u < n;) {
    var x = sourceAt(u);
    while (k + 1 < marks.length &&
        (marks[k + 1] - x).abs() <= (marks[k] - x).abs()) {
      k++;
    }
    var centre = marks.isEmpty ? x.round() : marks[k];
    var period = k + 1 < marks.length
        ? (marks[k + 1] - marks[k]).toDouble()
        : rate / (hzAt(centre) ?? 120);
    // Voiced, the pitch moved -- and its rise and fall about the word's
    // own made more or less of; unvoiced, an "s" or a breath, left be.
    var heard = hzAt(centre);
    var ratio = 1.0;
    if (heard != null) {
      var semis = shape.pitch;
      if (mean != null) {
        semis += (shape.inflection - 1) * (midiOf(heard) - mean);
      }
      ratio = math.pow(2, semis / 12).toDouble();
    }
    var spacing = period / ratio;
    var span = period.round().clamp(16, 2000);
    var gain = math.min(1.0, spacing / period);
    var o = u.round();
    for (var j = -span; j < span; j++) {
      var src = centre + j, dst = o + j;
      if (src < 0 || src >= pcm.length || dst < 0 || dst >= n) continue;
      var w = 0.5 + 0.5 * math.cos(math.pi * j / span);
      out[dst] += pcm[src] * w * gain;
      weight[dst] += w * gain;
    }
    u += spacing;
  }
  // Where slices overlapped more than they meet, brought back to level.
  for (var i = 0; i < n; i++) {
    if (weight[i] > 1) out[i] /= weight[i];
  }
  return out;
}

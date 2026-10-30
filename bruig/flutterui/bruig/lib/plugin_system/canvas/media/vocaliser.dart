import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// vocaliser.dart sings speech: a Speech take's words, broken into
// syllables, each stretched over a note of a melody and moved to its pitch
// -- by PSOLA, so the voice keeps its own sound while it sings.
//
// The melody is a MIDI channel's notes, one at a time: where notes overlap
// the higher is sung. A syllable to a note, in order; notes left over hold
// the last syllable, as a singer holds a vowel; syllables left over share
// the last note.

/// Syllable is a stretch of a take: part of a word, where it is said.
typedef Syllable = ({String text, double start, double end});

final _vowels = RegExp(r"[aeiouyAEIOUY]+");

/// syllablesOf breaks [words] into syllables: a vowel group each, with the
/// consonants round it, each word's time shared out by their letters.
List<Syllable> syllablesOf(List<TimedWord> words) {
  var out = <Syllable>[];
  for (var w in words) {
    var text = w.text.replaceAll(RegExp(r"[^A-Za-z']"), "");
    var groups = _vowels.allMatches(text).toList();
    // A final silent e is not a syllable of its own: "made" is one.
    if (groups.length > 1 &&
        groups.last.end == text.length &&
        groups.last.group(0)!.toLowerCase() == "e" &&
        text.length > 2) {
      groups.removeLast();
    }
    if (groups.length <= 1) {
      out.add((text: w.text, start: w.start, end: w.end));
      continue;
    }
    // Cut between vowel groups, halfway through the consonants between.
    var cuts = <int>[0];
    for (var i = 1; i < groups.length; i++) {
      cuts.add((groups[i - 1].end + groups[i].start) ~/ 2);
    }
    cuts.add(text.length);
    var span = w.end - w.start;
    for (var i = 0; i + 1 < cuts.length; i++) {
      var a = cuts[i] / text.length, b = cuts[i + 1] / text.length;
      out.add((
        text: text.substring(cuts[i], cuts[i + 1]),
        start: w.start + span * a,
        end: w.start + span * b
      ));
    }
  }
  return out;
}

/// melodyOf is [notes] one at a time: sorted, and where two overlap the
/// higher held, the lower cut short.
List<MidiNote> melodyOf(List<MidiNote> notes) {
  var sorted = [...notes]..sort((a, b) =>
      a.start != b.start ? a.start.compareTo(b.start) : b.key.compareTo(a.key));
  var out = <MidiNote>[];
  for (var n in sorted) {
    if (out.isNotEmpty) {
      var last = out.last;
      if (n.start < last.end - 1e-6) {
        if (n.start <= last.start + 1e-6) {
          // Together: the higher.
          if (n.key > last.key) out[out.length - 1] = n;
          continue;
        }
        out[out.length - 1] =
            last.copyWith(length: math.max(0.01, n.start - last.start));
      }
    }
    out.add(n);
  }
  return out;
}

/// SungNote is a note and the syllable sung on it.
typedef SungNote = ({MidiNote note, Syllable syllable});

/// assignSyllables puts [syllables] on [melody]'s notes in order: leftover
/// notes hold the last syllable, leftover syllables join the last note.
List<SungNote> assignSyllables(
    List<Syllable> syllables, List<MidiNote> melody) {
  if (syllables.isEmpty || melody.isEmpty) return const [];
  var out = <SungNote>[];
  for (var i = 0; i < melody.length; i++) {
    var s = syllables[math.min(i, syllables.length - 1)];
    if (i == melody.length - 1 && syllables.length > melody.length) {
      // The rest, run together on the last note.
      s = (
        text: [for (var r in syllables.skip(i)) r.text].join(),
        start: s.start,
        end: syllables.last.end
      );
    }
    out.add((note: melody[i], syllable: s));
  }
  return out;
}

/// SingSettings are how it sings: how much vibrato (a semitone at the
/// most, five and a half times a second, from a third of the way into a
/// note) and how long each note glides in from the last.
class SingSettings {
  final double vibrato;
  final double glideSeconds;
  const SingSettings({this.vibrato = 0.3, this.glideSeconds = 0.06});
}

/// singTake is [source] -- a take, mono, at [rate] -- sung on [sung]'s notes,
/// from the first note's start: the whole melody's length.
Float32List singTake(Float32List source, List<SungNote> sung,
    {double rate = 48000, SingSettings settings = const SingSettings()}) {
  if (sung.isEmpty) return Float32List(0);
  var t0 = sung.first.note.start;
  var end = sung.map((s) => s.note.end).reduce(math.max);
  var out = Float32List(((end - t0) * rate).ceil() + 4096);
  var weight = Float32List(out.length);
  double? lastHz;
  for (var s in sung) {
    var n = s.note;
    var hz = 440 * math.pow(2, (n.key - 69) / 12).toDouble();
    var from = (s.syllable.start * rate).clamp(0, source.length - 1).toDouble();
    var to = (s.syllable.end * rate).clamp(from + 1, source.length.toDouble());
    var outFrom = (n.start - t0) * rate, outLen = n.length * rate;
    // Where in the source each output moment is read from: straight
    // through the syllable, stretched to the note.
    double sourceAt(double u) => from + (to - from) * (u / outLen);
    // The source's own marks, a period of its voice apart -- or of the
    // note, where it is unvoiced -- so that every slice starts at the same
    // point of a cycle as the one before, and they join without a beat.
    var marks = <int>[];
    for (var m = from; m < to;) {
      marks.add(m.round());
      m += _periodAt(source, m.round(), rate) ?? rate / hz;
    }
    var k = 0;
    var u = 0.0;
    while (u < outLen) {
      // The pitch sung here: gliding in from the last note, then the
      // note, swung by the vibrato once it has settled.
      var glide = settings.glideSeconds * rate;
      var f = hz;
      if (lastHz != null && u < glide) {
        f = lastHz * math.pow(hz / lastHz, u / glide);
      }
      if (u > outLen / 3 && settings.vibrato > 0) {
        var t = u / rate;
        f *= math.pow(
            2, settings.vibrato * math.sin(2 * math.pi * 5.5 * t) / 12);
      }
      var synthPeriod = rate / f;
      // The source's own period where it is read: its pitch heard there,
      // or -- unvoiced, a consonant -- the note's own, to keep the hiss.
      var at = sourceAt(u);
      while (k + 1 < marks.length &&
          (marks[k + 1] - at).abs() <= (marks[k] - at).abs()) {
        k++;
      }
      var centre = marks.isEmpty ? at.round() : marks[k];
      var period = k + 1 < marks.length
          ? (marks[k + 1] - marks[k]).toDouble()
          : (_periodAt(source, centre, rate) ?? synthPeriod);
      var span = period.round().clamp(16, 2000);
      var gain = math.min(1.0, synthPeriod / period);
      var o = (outFrom + u).round();
      for (var j = -span; j < span; j++) {
        var src = centre + j, dst = o + j;
        if (src < 0 || src >= source.length || dst < 0 || dst >= out.length) {
          continue;
        }
        var w = 0.5 + 0.5 * math.cos(math.pi * j / span);
        out[dst] += source[src] * w * gain;
        weight[dst] += w * gain;
      }
      u += synthPeriod;
    }
    lastHz = hz;
  }
  // Where slices overlapped more than they meet, brought back to level.
  for (var i = 0; i < out.length; i++) {
    if (weight[i] > 1) out[i] /= weight[i];
  }
  return Float32List.sublistView(out, 0, ((end - t0) * rate).ceil());
}

/// _periodAt is the period the source repeats at round [at], in samples,
/// or null where it does not.
double? _periodAt(Float32List source, int at, double rate) {
  const window = 1024;
  if (source.length < window) return null;
  var from = (at - window ~/ 2).clamp(0, source.length - window).toInt();
  var p = detectPitch(Float32List.sublistView(source, from, from + window),
      rate: rate, minHz: 70, maxHz: 1000);
  if (p == null || p.clarity < 0.6) return null;
  return rate / p.hz;
}

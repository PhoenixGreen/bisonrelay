import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';

// pitch_retune.dart makes a recording again with its notes moved (see
// pitch_edit.dart): each note changed is said again by PSOLA -- slices a
// period of the voice long, laid the new period apart, so the voice keeps
// its own sound -- at the pitch asked for, moment by moment, and its timing
// as it was; everything else is copied as it was. A changed note meets the
// rest over 10ms margins, cross-faded, so nothing clicks.

/// hzOf is a MIDI note's frequency.
double hzOf(double midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// retuneTake is [source] -- mono, at [rate] -- with [notes] done, read
/// against [track]: its pitch every [frame] seconds as a MIDI note, null
/// where nothing is voiced.
Float32List retuneTake(
    Float32List source, List<double?> track, List<PitchNote> notes,
    {double rate = 48000, double frame = 0.02}) {
  var out = Float32List.fromList(source);
  var margin = (0.01 * rate).round();
  var slow = driftTrack(track);
  for (var (k, n) in notes.indexed) {
    if (!n.edited) continue;
    // From where it is heard to start, moved by Quantise timing, or sung.
    var a = (math.min(n.start, n.heardStart) * rate).round() - margin;
    var b = (n.end * rate).round() + margin;
    a = a.clamp(0, source.length);
    b = b.clamp(a, source.length);
    if (b - a < 2 * margin + 16) continue;
    // Glided into from the note before, where it runs on into this one.
    var before =
        k > 0 && n.start - notes[k - 1].end < 0.3 ? notes[k - 1].target : null;
    var said = _retune(source, track, slow, n, before, a, b, rate, frame);
    for (var i = a; i < b; i++) {
      // In over the first margin, out over the last.
      var w = math.min(1.0, math.min(i - a, b - 1 - i) / margin);
      out[i] = out[i] * (1 - w) + said[i - a] * w;
    }
  }
  return out;
}

/// driftTrack is [track] smoothed over about a sixth of a second: the slow
/// drift of each note, without its vibrato.
List<double?> driftTrack(List<double?> track) {
  const half = 4;
  return [
    for (var i = 0; i < track.length; i++)
      if (track[i] == null)
        null
      else
        () {
          var sum = 0.0, count = 0;
          for (var j = math.max(0, i - half);
              j <= math.min(track.length - 1, i + half);
              j++) {
            if (track[j] case var m?) {
              sum += m;
              count++;
            }
          }
          return sum / count;
        }(),
  ];
}

/// pitchHeardAt is where note [n] is heard [t] seconds into the original,
/// where it was sung at [sung] and drifting at [drift] (see driftTrack):
/// its drawn pitch, or its target with as much of its drift and vibrato as
/// is kept -- glided into from [before] over its slide, and reached from
/// the pitch sung over its retune.
double pitchHeardAt(PitchNote n, double t, double sung, double drift,
    {double? before}) {
  if (n.drawnAt(t) case var drawn?) return drawn;
  var want =
      n.target + (drift - n.sung) * n.wobble + (sung - drift) * n.vibrato;
  var since = math.max(0.0, t - n.start);
  if (n.slideMs > 0 && before != null) {
    var u = (since / (n.slideMs / 1000)).clamp(0.0, 1.0);
    var eased = u * u * (3 - 2 * u);
    want = before + (want - before) * eased;
  }
  if (n.retuneMs > 0) {
    var k = 1 - math.exp(-since / (n.retuneMs / 1000));
    want = sung + (want - sung) * k;
  }
  return want;
}

/// _retune is [source] from [a] to [b] said as note [n] asks.
Float32List _retune(Float32List source, List<double?> track, List<double?> slow,
    PitchNote n, double? before, int a, int b, double rate, double frame) {
  var gain = math.pow(10, n.gainDb / 20).toDouble();
  int at(double s) => (s / rate / frame).round();
  // The pitch sung at [s] (a sample), or the note's own where unvoiced.
  double sungAt(double s) {
    var i = at(s);
    return i >= 0 && i < track.length ? track[i] ?? n.sung : n.sung;
  }

  double driftAt(double s) {
    var i = at(s);
    return i >= 0 && i < slow.length ? slow[i] ?? n.sung : n.sung;
  }

  double targetAt(double s) =>
      pitchHeardAt(n, s / rate, sungAt(s), driftAt(s), before: before);

  // Its voice's colour: each slice read faster (thinner) or slower
  // (deeper), its pitch still the marks' spacing.
  var colour = math.pow(2, n.formant / 12).toDouble();

  // The source's marks, a period of its voice apart.
  var marks = <double>[];
  for (var m = a.toDouble(); m < b;) {
    marks.add(m);
    m += rate / hzOf(sungAt(m));
  }
  var out = Float32List(b - a);
  var weight = Float32List(b - a);
  var k = 0;
  var u = a.toDouble();
  while (u < b) {
    // Where in the original this moment is heard from: its own sound
    // stretched from where it is moved to; silence before it, moved later.
    var from = n.sourceAt(u / rate);
    if (from == null) {
      u += rate / hzOf(n.target);
      continue;
    }
    var su = from * rate;
    while (k + 1 < marks.length &&
        (marks[k + 1] - su).abs() <= (marks[k] - su).abs()) {
      k++;
    }
    var centre = marks.isEmpty ? su.round() : marks[k].round();
    var period = rate / hzOf(sungAt(centre.toDouble()));
    var synthPeriod = rate / hzOf(targetAt(su));
    var span = (period / colour).round().clamp(16, 2000);
    var o = u.round();
    for (var j = -span; j < span; j++) {
      var dst = o + j - a;
      if (dst < 0 || dst >= out.length) continue;
      var w = 0.5 + 0.5 * math.cos(math.pi * j / span);
      double sample;
      if (colour == 1) {
        var src = centre + j;
        if (src < 0 || src >= source.length) continue;
        sample = source[src];
      } else {
        var pos = centre + j * colour;
        var i0 = pos.floor();
        if (i0 < 0 || i0 + 1 >= source.length) continue;
        var f = pos - i0;
        sample = source[i0] * (1 - f) + source[i0 + 1] * f;
      }
      out[dst] += sample * w;
      weight[dst] += w;
    }
    u += synthPeriod;
  }
  for (var i = 0; i < out.length; i++) {
    if (weight[i] > 1e-6) out[i] = out[i] / math.max(1.0, weight[i]) * gain;
  }
  return out;
}

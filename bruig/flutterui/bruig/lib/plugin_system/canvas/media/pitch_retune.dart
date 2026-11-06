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
  for (var n in notes) {
    if (!n.edited) continue;
    var a = (n.start * rate).round() - margin;
    var b = (n.end * rate).round() + margin;
    a = a.clamp(0, source.length);
    b = b.clamp(a, source.length);
    if (b - a < 2 * margin + 16) continue;
    var said = _retune(source, track, n, a, b, rate, frame);
    for (var i = a; i < b; i++) {
      // In over the first margin, out over the last.
      var w = math.min(1.0, math.min(i - a, b - 1 - i) / margin);
      out[i] = out[i] * (1 - w) + said[i - a] * w;
    }
  }
  return out;
}

/// _retune is [source] from [a] to [b] said as note [n] asks.
Float32List _retune(Float32List source, List<double?> track, PitchNote n, int a,
    int b, double rate, double frame) {
  var gain = math.pow(10, n.gainDb / 20).toDouble();
  // The pitch sung at [s] (a sample), or the note's own where unvoiced.
  double sungAt(double s) {
    var i = (s / rate / frame).round();
    return i >= 0 && i < track.length ? track[i] ?? n.sung : n.sung;
  }

  // Where it is asked to be at [s]: the note's target, swung round it as
  // much of its own wobble as is kept.
  double targetAt(double s) => n.target + (sungAt(s) - n.sung) * n.wobble;

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
    while (k + 1 < marks.length &&
        (marks[k + 1] - u).abs() <= (marks[k] - u).abs()) {
      k++;
    }
    var centre = marks.isEmpty ? u.round() : marks[k].round();
    var period = rate / hzOf(sungAt(centre.toDouble()));
    var synthPeriod = rate / hzOf(targetAt(u));
    var span = period.round().clamp(16, 2000);
    var o = u.round();
    for (var j = -span; j < span; j++) {
      var src = centre + j, dst = o + j - a;
      if (src < 0 || src >= source.length || dst < 0 || dst >= out.length) {
        continue;
      }
      var w = 0.5 + 0.5 * math.cos(math.pi * j / span);
      out[dst] += source[src] * w;
      weight[dst] += w;
    }
    u += synthPeriod;
  }
  for (var i = 0; i < out.length; i++) {
    if (weight[i] > 1e-6) out[i] = out[i] / math.max(1.0, weight[i]) * gain;
  }
  return out;
}

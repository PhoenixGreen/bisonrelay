import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/dsp.dart';
import 'package:bruig/plugin_system/canvas/media/speech_engines.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart';

// speech_finish.dart finishes a Speech device's lines on every engine:
// joined with speed-following pauses, then a little room and the speaker
// boost, applied after the voice so changing them respeaks nothing. Kept
// light, as heavier warmth or room sounds artificial.

/// lineGap is the pause between two lines at [speed]: shorter when faster,
/// by more than the words are.
double lineGap(double speed) => 0.35 / math.pow(speed.clamp(0.5, 2.0), 1.5);

/// joinLines puts [takes] end to end, a pause between each two.
SpokenAudio joinLines(List<SpokenAudio> takes, double speed) {
  var pieces = <(Float32List, Float32List, List<TimedWord>)>[];
  for (var (i, t) in takes.indexed) {
    if (i > 0) pieces.add(silence(lineGap(speed)));
    pieces.add((t.l, t.r, t.words));
  }
  return assembleTake(pieces, exact: takes.every((t) => t.exact));
}

/// _boost is the speaker boost's tone: a low cut under the voice, a little
/// more body and presence.
const _boost = Eq(
  on: true,
  lowCut: EqBand(70),
  low: EqBand(160, gainDb: 1.5),
  presence: EqBand(4500, gainDb: 1.5, q: 0.8),
);

/// _evenly is its compression: gentle, so quiet words come up rather than
/// loud ones being flattened.
const _evenly = Dynamics(
    on: true,
    threshold: -24,
    ratio: 2.2,
    attackMs: 8,
    releaseMs: 140,
    kneeDb: 8);

/// finished is [take] with [room] (nought dry, one a small room) and the
/// speaker boost where [boost]. Words stay put; a tail lengthens it.
SpokenAudio finished(SpokenAudio take,
    {required double room, required bool boost}) {
  room = room.clamp(0.0, 1.0);
  var tail = room > 0 ? (0.1 + 0.25 * room) : 0.0;
  var n = take.l.length + (tail * mixRate).round();
  var l = Float32List(n)..setRange(0, take.l.length, take.l);
  var r = Float32List(n)..setRange(0, take.r.length, take.r);
  if (boost) {
    EqProcessor(_boost).process(l, r, n);
    Compressor(_evenly).process(l, r, n);
  }
  if (room > 0) {
    Reverb(MixDevice(DeviceKind.reverb, values: {
      "size": 0.12 + 0.2 * room,
      "damping": 0.75,
      "predelay": 3,
      "width": 0.6,
      "mix": 0.1 * room,
    })).process(l, r, n);
    _roomTone(l, r, room);
  }
  // An even level under a ceiling: with the boost, brought to a
  // voice-over's loudness; without, only kept from clipping.
  if (boost) {
    var g = _toLevel(l, -19);
    for (var i = 0; i < n; i++) {
      l[i] *= g;
      r[i] *= g;
    }
  }
  Limiter(-1).process(l, r, n);
  // The limiter's 5ms look-ahead delays the sound: taken back, so the words
  // stay where they were.
  var ahead = (0.005 * mixRate).round();
  l.setRange(0, n - ahead, l, ahead);
  r.setRange(0, n - ahead, r, ahead);
  l.fillRange(n - ahead, n, 0);
  r.fillRange(n - ahead, n, 0);
  return SpokenAudio(l, r, take.words, exact: take.exact);
}

/// _roomTone is a room's quiet under the voice: noise, highs rolled off,
/// sixty decibels down at most.
void _roomTone(Float32List l, Float32List r, double room) {
  var random = math.Random(7);
  var level = 0.0012 * room;
  var a = 0.0, b = 0.0;
  for (var i = 0; i < l.length; i++) {
    a += 0.06 * ((random.nextDouble() * 2 - 1) - a);
    b += 0.06 * ((random.nextDouble() * 2 - 1) - b);
    l[i] += a * level * 4;
    r[i] += b * level * 4;
  }
}

/// _toLevel is the gain bringing the voice's loudness (measured where it
/// speaks, not its silences) to [db] decibels, within twelve of where it is.
double _toLevel(Float32List l, double db) {
  var sum = 0.0;
  var count = 0;
  for (var x in l) {
    if (x.abs() > 0.01) {
      sum += x * x;
      count++;
    }
  }
  if (count == 0) return 1;
  var rms = math.sqrt(sum / count);
  return (dbToGain(db) / rms).clamp(0.25, 4.0);
}

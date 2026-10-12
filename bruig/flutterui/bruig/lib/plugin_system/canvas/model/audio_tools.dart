import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/media_clip.dart';

// audio_tools.dart is the arithmetic behind the timeline's sound tools:
// ducking music under a voice, and fitting a track to the length of a film.
// Pure, so it can be tested without a sound card, and so the tools write
// ordinary clips and envelopes that play and export as anything else does.

/// speechSpans is when somebody is speaking in a recording whose shape is
/// [peaks] across [seconds]: each stretch of sound, with pauses shorter than
/// [gap] bridged, as (from, to) in seconds.
List<(double, double)> speechSpans(Float32List peaks, double seconds,
    {double gap = 0.35, double floor = 0.08}) {
  if (peaks.isEmpty || seconds <= 0) return const [];
  var loudest = peaks.fold(0.0, (m, p) => p > m ? p : m);
  if (loudest <= 0) return const [];
  var quiet = loudest * floor;
  var step = seconds / peaks.length;
  var spans = <(double, double)>[];
  double? from;
  double to = 0;
  for (var i = 0; i < peaks.length; i++) {
    if (peaks[i] <= quiet) continue;
    var t = i * step;
    if (from != null && t - to < gap) {
      to = t + step;
      continue;
    }
    if (from != null) spans.add((from, to));
    from = t;
    to = t + step;
  }
  if (from != null) spans.add((from, to));
  return spans;
}

/// duckEnvelope is the volume envelope that sinks a clip to [gain] for
/// every span of [spans] -- each in seconds from the clip's start --
/// sinking over [attack] before a span and rising over [release] after it.
///
/// Spans whose dips would meet are one dip: the music does not bob up for a
/// breath between two lines.
List<GainPoint> duckEnvelope(List<(double, double)> spans,
    {double gain = 0.25, double attack = 0.15, double release = 0.45}) {
  var merged = <(double, double)>[];
  for (var s in [...spans]..sort((a, b) => a.$1.compareTo(b.$1))) {
    if (merged.isNotEmpty && s.$1 - attack <= merged.last.$2 + release) {
      var last = merged.removeLast();
      merged.add((last.$1, math.max(last.$2, s.$2)));
    } else {
      merged.add(s);
    }
  }
  return [
    for (var (from, to) in merged) ...[
      GainPoint(from - attack, 1),
      GainPoint(from, gain),
      GainPoint(to, gain),
      GainPoint(to + release, 1),
    ],
  ];
}

/// FitPiece is one copy of a track in a fitted run: where it starts on the
/// timeline, the part of the file it plays, and its fades.
class FitPiece {
  final int at;
  final double start;
  final double end;
  final double fadeIn;
  final double fadeOut;
  const FitPiece(this.at, this.start, this.end, this.fadeIn, this.fadeOut);

  @override
  String toString() => "FitPiece($at, $start..$end, in $fadeIn, out $fadeOut)";
}

/// fitTrack is how to make a track of [length] seconds, starting at frame
/// [at], end exactly on frame [end] at [rate] frames a second.
///
/// Too long, it is cut short and faded out. Too short, copies of it are laid
/// end to end, overlapping by [crossfade], and the last copy plays whole --
/// so the track's own ending, which is the part a listener notices, lands
/// on [end] -- with the copies before it each stopping short to make room.
List<FitPiece> fitTrack(
    {required int at,
    required double length,
    required int end,
    required int rate,
    double crossfade = 3,
    double fadeOut = 2}) {
  var want = (end - at) / rate;
  if (want <= 0 || length <= 0) return const [];
  if (length >= want) {
    return [FitPiece(at, 0, want, 0, math.min(fadeOut, want / 2))];
  }
  var lastAt = end - (length * rate).round();
  var pieces = <FitPiece>[];
  var t = at;
  var hop = ((length - crossfade) * rate).round();
  if (hop <= 0) hop = (length * rate).round();
  while (t + hop < lastAt) {
    pieces.add(FitPiece(t, 0, length, pieces.isEmpty ? 0 : crossfade, crossfade));
    t += hop;
  }
  // The one before the last stops where the last has faded in.
  var room = (lastAt - t) / rate + crossfade;
  pieces.add(FitPiece(t, 0, math.min(length, room), pieces.isEmpty ? 0 : crossfade,
      crossfade));
  pieces.add(FitPiece(lastAt, 0, length, crossfade, 0));
  return pieces;
}

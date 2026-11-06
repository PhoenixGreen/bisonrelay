import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// note_tools.dart is the clip editor's Notes tools (Ableton's pitch and time
// utilities). Starts and lengths are in beats.

/// NoteTool is one of the tools, with what its button says.
enum NoteTool {
  up("+1"),
  down("−1"),
  octaveUp("+12"),
  octaveDown("−12"),
  fitToScale("Fit to scale"),
  invert("Invert"),
  reverse("Reverse"),
  legato("Legato"),
  faster("÷2"),
  slower("×2"),
  third("+ third"),
  fifth("+ fifth"),
  humanise("Humanise"),
  quantise("Quantise"),
  strum("Strum"),
  crescendo("Crescendo"),
  chop("Chop"),
  join("Join"),
  mute("Mute"),
  chance("Chance 50%"),
  always("Always"),

  /// duplicate puts a copy of the notes after them, a grid step on from
  /// where the last ends.
  duplicate("Duplicate"),

  /// swing pushes every second step of the grid a third of a step later.
  swing("Swing"),

  /// arpeggiate spreads each chord's notes up the grid, lowest first.
  arpeggiate("Arpeggiate chords"),

  /// rhythm lays five notes in every eight steps of the grid (Euclid's
  /// spacing, as Bjorklund's) on the lowest key, from the first note to the
  /// loop's end -- or on middle C from the start, with none.
  rhythm("Rhythm 5 in 8"),

  /// fillChords makes each note the root of the scale's chord on it: the
  /// scale's third and fifth over it.
  fillChords("Fill chords");

  final String label;
  const NoteTool(this.label);
}

/// applyNoteTool is [notes] after [tool], on those at [picked] (all of them,
/// with none picked). [scale] is the root and steps Fit to scale uses; [grid]
/// the beats Quantise moves onto; [loopEnd] where Legato holds the last note
/// to; [seed] seeds Humanise so a test gets the same result.
List<MidiNote> applyNoteTool(
  NoteTool tool,
  List<MidiNote> notes,
  Set<int> picked, {
  (int, List<int>) scale = (0, const [0, 2, 4, 5, 7, 9, 11]),
  double grid = 0.25,
  double loopEnd = 4,
  int seed = 1,
}) {
  bool on(int i) => picked.isEmpty || picked.contains(i);
  var chosen = [
    for (var (i, n) in notes.indexed)
      if (on(i)) n
  ];
  // A rhythm needs no notes to start from: middle C, from the start.
  if (chosen.isEmpty && tool == NoteTool.rhythm) {
    return _rhythm(notes, 60, 0, loopEnd, grid);
  }
  if (chosen.isEmpty) return notes;
  List<MidiNote> each(MidiNote Function(MidiNote n, int i) f) => [
        for (var (i, n) in notes.indexed) on(i) ? f(n, i) : n,
      ];
  var first = chosen.map((n) => n.start).reduce(math.min);
  var last = chosen.map((n) => n.end).reduce(math.max);
  switch (tool) {
    case NoteTool.up:
      return each((n, _) => n.copyWith(key: n.key + 1));
    case NoteTool.down:
      return each((n, _) => n.copyWith(key: n.key - 1));
    case NoteTool.octaveUp:
      return each((n, _) => n.copyWith(key: n.key + 12));
    case NoteTool.octaveDown:
      return each((n, _) => n.copyWith(key: n.key - 12));
    case NoteTool.fitToScale:
      // To the nearest note of the scale -- the lower, between two.
      var (root, steps) = scale;
      bool inScale(int k) => steps.contains((k - root) % 12);
      return each((n, _) {
        for (var d = 0; d < 12; d++) {
          if (inScale(n.key - d)) return n.copyWith(key: n.key - d);
          if (inScale(n.key + d)) return n.copyWith(key: n.key + d);
        }
        return n;
      });
    case NoteTool.invert:
      var hi = chosen.map((n) => n.key).reduce(math.max);
      var lo = chosen.map((n) => n.key).reduce(math.min);
      return each((n, _) => n.copyWith(key: hi + lo - n.key));
    case NoteTool.reverse:
      return each((n, _) => n.copyWith(start: first + last - n.end));
    case NoteTool.legato:
      // Each held to the next start after it; the last to the loop's end.
      var starts = {for (var n in chosen) n.start}.toList()..sort();
      return each((n, _) {
        var next = starts.where((s) => s > n.start + 1e-6).firstOrNull;
        var to = next ?? math.max(loopEnd, n.end);
        return n.copyWith(length: math.max(0.01, to - n.start));
      });
    case NoteTool.faster:
      return each((n, _) => n.copyWith(
          start: first + (n.start - first) / 2, length: n.length / 2));
    case NoteTool.slower:
      return each((n, _) => n.copyWith(
          start: first + (n.start - first) * 2, length: n.length * 2));
    case NoteTool.third || NoteTool.fifth:
      var up = tool == NoteTool.third ? 4 : 7;
      return [
        ...notes,
        for (var n in chosen)
          if (n.key + up <= 127) n.copyWith(key: n.key + up),
      ];
    case NoteTool.humanise:
      // A little off the grid -- up to a fifth of a sixteenth either way --
      // and a little louder or softer.
      var dice = math.Random(seed);
      return each((n, _) => n.copyWith(
          start: math.max(0, n.start + (dice.nextDouble() - 0.5) * 0.1),
          velocity: (n.velocity + (dice.nextDouble() - 0.5) * 24)
              .round()
              .clamp(1, 127)));
    case NoteTool.quantise:
      if (grid <= 0) return notes;
      return each((n, _) {
        var start = (n.start / grid).round() * grid;
        var end = math.max(start + grid, (n.end / grid).round() * grid);
        return n.copyWith(start: start, length: end - start);
      });
    case NoteTool.strum:
      // A chord's notes each a little after the one under it, as a hand
      // drawn across the strings.
      var under = <int, int>{};
      for (var (i, n) in notes.indexed) {
        if (!on(i)) continue;
        under[i] = [
          for (var (j, m) in notes.indexed)
            if (on(j) && (m.start - n.start).abs() < 1e-6 && m.key < n.key) j
        ].length;
      }
      return each((n, i) {
        var late = (under[i] ?? 0) * 0.06;
        return n.copyWith(
            start: n.start + late, length: math.max(0.06, n.length - late));
      });
    case NoteTool.crescendo:
      // Softer to louder, the first to start to the last.
      var lastStart = chosen.map((n) => n.start).reduce(math.max);
      var span = math.max(1e-6, lastStart - first);
      return each((n, _) =>
          n.copyWith(velocity: (40 + (n.start - first) / span * 87).round()));
    case NoteTool.chop:
      // Each cut in two.
      return [
        for (var (i, n) in notes.indexed)
          if (on(i) && n.length >= 0.02) ...[
            n.copyWith(length: n.length / 2),
            n.copyWith(start: n.start + n.length / 2, length: n.length / 2),
          ] else
            n,
      ];
    case NoteTool.join:
      // Notes of one key that touch made one.
      var out = <MidiNote>[];
      var byKey = <int, List<MidiNote>>{};
      for (var (i, n) in notes.indexed) {
        if (on(i)) {
          (byKey[n.key] ??= []).add(n);
        } else {
          out.add(n);
        }
      }
      for (var run in byKey.values) {
        run.sort((a, b) => a.start.compareTo(b.start));
        var held = run.first;
        for (var n in run.skip(1)) {
          if (n.start <= held.end + 1e-6) {
            held =
                held.copyWith(length: math.max(held.end, n.end) - held.start);
          } else {
            out.add(held);
            held = n;
          }
        }
        out.add(held);
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    case NoteTool.mute:
      // Muted -- or, all muted, played again.
      var all = chosen.every((n) => n.muted);
      return each((n, _) => n.copyWith(muted: !all));
    case NoteTool.chance:
      return each((n, _) => n.copyWith(chance: 0.5));
    case NoteTool.always:
      return each((n, _) => n.copyWith(chance: 1));
    case NoteTool.duplicate:
      var step = grid <= 0 ? 0.25 : grid;
      var by = math.max(step, ((last - first) / step).ceil() * step);
      return [
        ...notes,
        for (var n in chosen) n.copyWith(start: n.start + by),
      ];
    case NoteTool.swing:
      if (grid <= 0) return notes;
      return each((n, _) {
        var step = (n.start / grid).round();
        var onGrid = (n.start - step * grid).abs() < grid / 8;
        if (!onGrid || step.isEven) return n;
        return n.copyWith(start: n.start + grid / 3);
      });
    case NoteTool.arpeggiate:
      var step = grid <= 0 ? 0.25 : grid;
      var byStart = <double, List<int>>{};
      for (var (i, n) in notes.indexed) {
        if (on(i)) (byStart[n.start] ??= []).add(i);
      }
      var place = <int, int>{};
      for (var group in byStart.values) {
        group.sort((a, b) => notes[a].key.compareTo(notes[b].key));
        for (var (k, i) in group.indexed) {
          place[i] = k;
        }
      }
      return each((n, i) {
        var k = place[i] ?? 0;
        if (k == 0) return n.copyWith(length: math.min(n.length, step));
        return n.copyWith(
            start: n.start + k * step, length: math.min(n.length, step));
      });
    case NoteTool.rhythm:
      var low = chosen.map((n) => n.key).reduce(math.min);
      return _rhythm(notes, low, first, loopEnd, grid);
    case NoteTool.fillChords:
      var (root, steps) = scale;
      List<int> chordOn(int key) {
        var at = steps.indexOf((key - root) % 12);
        if (at < 0) return const [];
        int up(int by) {
          var d = at + by;
          var octave = d ~/ steps.length;
          var s = steps[d % steps.length];
          var base = key - steps[at];
          return base + s + 12 * octave;
        }

        return [up(2), up(4)];
      }

      return [
        ...notes,
        for (var n in chosen)
          for (var k in chordOn(n.key))
            if (k <= 127 &&
                !notes
                    .any((m) => m.key == k && (m.start - n.start).abs() < 1e-6))
              n.copyWith(key: k),
      ];
  }
}

/// _rhythm is [notes] with five notes in every eight grid steps on [key],
/// from [from] to [to], where none of that key starts already.
List<MidiNote> _rhythm(
    List<MidiNote> notes, int key, double from, double to, double grid) {
  var step = grid <= 0 ? 0.25 : grid;
  // Five in eight, as evenly as eight steps let them be: x.xx.xx.
  const pattern = [true, false, true, true, false, true, true, false];
  var out = [...notes];
  var i = 0;
  for (var t = from; t < to - 1e-6; t += step, i++) {
    if (!pattern[i % pattern.length]) continue;
    if (notes.any((n) => n.key == key && (n.start - t).abs() < 1e-6)) continue;
    out.add(MidiNote(key, t, step, 100));
  }
  return out;
}

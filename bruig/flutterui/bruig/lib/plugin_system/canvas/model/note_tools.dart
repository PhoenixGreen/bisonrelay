import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// note_tools.dart is the clip editor's Notes tools -- Ableton's pitch and
// time utilities: each takes a clip's notes and which of them are picked
// (all of them, with none picked) and answers the notes changed. Starts and
// lengths are in beats.

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
  quantise("Quantise");

  final String label;
  const NoteTool(this.label);
}

/// applyNoteTool is [notes] after [tool], on those at [picked] -- or all of
/// them, with none picked. [scale] is the root and steps a note is fitted
/// to; [grid] the beats Quantise moves notes onto; [loopEnd] where Legato's
/// last note is held to; [seed] Humanise's dice, so a press does the same
/// each time it is tested.
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
      // Upside down: the highest the lowest.
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
  }
}

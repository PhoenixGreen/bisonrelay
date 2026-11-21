import 'dart:math' as math;

// panel_heights.dart sizes the panels stacked under the canvas as one: never
// taller than the room under the settings bar and, once they fill it, kept
// filling it. A panel grown takes free room, then the panels over it,
// nearest first, to each one's least; shrunk, the panel over it takes the
// room, so the top stays under the bar. Only the top edge dragged down
// lets the stack come away from it.

/// resizePanel is [heights] -- panels top to bottom, none shorter than its
/// [least] -- with panel [index]'s top edge dragged so it would be [wanted]
/// tall, in [room]. A [fixed] panel -- a bar, a mixer minimised -- neither
/// gives room nor takes it.
List<double> resizePanel(List<double> heights, List<double> least, int index,
    double wanted, double room,
    {Set<int> fixed = const {}}) {
  var out = [...heights];
  var total = out.fold(0.0, (a, b) => a + b);
  var pinned = total >= room - 0.5;
  wanted = math.max(wanted, least[index]);
  var delta = wanted - out[index];
  if (delta > 0) {
    var give = math.min(delta, math.max(0.0, room - total));
    var need = delta - give;
    for (var j = index - 1; j >= 0 && need > 1e-9; j--) {
      if (fixed.contains(j)) continue;
      var take = math.min(need, math.max(0.0, out[j] - least[j]));
      out[j] -= take;
      need -= take;
      give += take;
    }
    out[index] += give;
  } else if (delta < 0) {
    out[index] += delta;
    if (pinned) {
      // The nearest over it that can grow takes it, so the top stays put.
      for (var j = index - 1; j >= 0; j--) {
        if (fixed.contains(j)) continue;
        out[j] -= delta;
        break;
      }
    }
  }
  return out;
}

/// fitPanels is [heights] fitted to [room] (a shorter window, a panel
/// opened): the top ones give way first, each to its [least].
List<double> fitPanels(List<double> heights, List<double> least, double room) {
  var out = [...heights];
  var over = out.fold(0.0, (a, b) => a + b) - room;
  for (var j = 0; j < out.length && over > 1e-9; j++) {
    var take = math.min(over, math.max(0.0, out[j] - least[j]));
    out[j] -= take;
    over -= take;
  }
  return out;
}

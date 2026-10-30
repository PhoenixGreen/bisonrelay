import 'dart:math' as math;

// panel_heights.dart sizes the panels stacked under the canvas -- the
// mixer, the effects, the timeline -- as one: together never taller than the
// room under the settings bar, and, once they fill it, kept filling it.
//
// Each panel is sized by dragging its top edge. Made taller, it takes the
// free room first and then the room of the panels over it, the nearest
// first, down to each one's least: so it never pushes the stack past the
// bar. Made shorter while the stack fills the room, the panel over it takes
// what it gives up: the top stays pinned where it is, under the bar. Only
// the top panel's own edge, dragged down, lets the stack come away from it.

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

/// fitPanels is [heights] made to fit [room] -- a window made shorter, a
/// panel opened -- the top ones giving way first, each down to its [least];
/// and then, where they still do not fit, the [collapsible] one -- the
/// timeline -- shut to [collapsed], its bar alone.
List<double> fitPanels(List<double> heights, List<double> least, double room,
    {int? collapsible, double collapsed = 0}) {
  var out = [...heights];
  var over = out.fold(0.0, (a, b) => a + b) - room;
  for (var j = 0; j < out.length && over > 1e-9; j++) {
    var take = math.min(over, math.max(0.0, out[j] - least[j]));
    out[j] -= take;
    over -= take;
  }
  if (collapsible != null && over > 0.5) out[collapsible] = collapsed;
  return out;
}

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';

// canvas_palette.dart is one colour changed everywhere a document uses it:
// shapes, words, charts, tables, backgrounds, transitions -- the saved
// colours' Replace everywhere. See CanvasController.replaceColour.
//
// The colours stay where they always were, on each element as a plain
// colour, and are changed where they are. That keeps every painter, every
// export and every document ever saved exactly as it was.

/// _notColours are keys whose numbers are never colours, however much they
/// look like one: frames, lengths, counts, a chart's numbers, a counter's.
/// A colour is a large integer, and so is thirty million atoms.
const _notColours = {
  "frame",
  "frames",
  "at",
  "seed",
  "from",
  "to",
  "count",
  "values",
  "value",
  "length",
  "start",
  "end",
  "width",
  "height",
  "w",
  "h",
  "x",
  "y",
  "rows",
  "exportWidth",
  "loopFrames",
  "passFrames",
  "pauseAt",
  "pauseFor",
  "series",
  "data",
  "estimated",
  "track",
  "keys",
  "vb",
  "nodes",
  "points",
  "envelope",
  "textStyles",
  "cues",
  "decimals",
  "rate",
  "params",
};

/// _rgb is a colour's red, green and blue, without its opacity.
int _rgb(int argb) => argb & 0xFFFFFF;

/// _looksLikeColour is whether [v] could be a colour at all: an integer with
/// some opacity in it. A colour with none is invisible, and nothing is lost
/// by leaving it alone.
bool _looksLikeColour(Object? v) =>
    v is int && v >= 0x01000000 && v <= 0xFFFFFFFF;

/// _walk visits every colour-shaped number in [json] that is not under a
/// key that rules it out, handing it to [visit] and putting back whatever
/// that returns.
Object? _walk(Object? json, int Function(int) visit, {bool skip = false}) {
  if (json is Map<String, dynamic>) {
    return {
      for (var e in json.entries)
        e.key: _walk(e.value, visit, skip: _notColours.contains(e.key)),
    };
  }
  if (json is List) {
    return [for (var v in json) _walk(v, visit, skip: skip)];
  }
  if (!skip && _looksLikeColour(json)) return visit(json as int);
  return json;
}

/// recoloured is [json] -- a whole document's -- with every use of [from]
/// made [to]. A use is any colour with [from]'s red, green and blue,
/// whatever its opacity: a shade drawn in the brand blue at half strength
/// is the brand blue too, and keeps its half.
Map<String, dynamic> recoloured(
    Map<String, dynamic> json, Color from, Color to) {
  var old = _rgb(colorToJson(from));
  var next = _rgb(colorToJson(to));
  if (old == next) return json;
  return _walk(json, (v) => _rgb(v) == old ? (v & 0xFF000000) | next : v)
      as Map<String, dynamic>;
}

/// CanvasColours is what a canvas is already dressed in: the [ground]
/// behind it, the [ink] its words are in, and the [accent] its shapes and
/// headings stand out in. For an element that should look like it belongs
/// -- a table dropped on to a design -- rather than arrive in a look of its
/// own.
class CanvasColours {
  final Color ground;
  final Color ink;
  final Color accent;
  const CanvasColours(this.ground, this.ink, this.accent);
}

/// canvasColours reads [ground] -- the background -- and the colours
/// [elements] use most into a ground, an ink and an accent.
CanvasColours canvasColours(Color ground, Iterable<CanvasElement> elements) {
  var counts = <int, int>{};
  for (var e in elements) {
    _walk(e.toJson(), (v) {
      // Only colours meant to be seen: a faint tint is a shade, not a choice.
      if (((v >> 24) & 0xFF) >= 0xC0) {
        var rgb = _rgb(v) | 0xFF000000;
        counts[rgb] = (counts[rgb] ?? 0) + 1;
      }
      return v;
    });
  }
  var groundLight = ground.computeLuminance();
  var byUse = counts.entries.toList()..sort((a, b) => b.value - a.value);
  Color? ink, accent;
  for (var entry in byUse) {
    var c = Color(entry.key);
    var light = c.computeLuminance();
    // Words have to be read against the ground.
    if (ink == null && (light - groundLight).abs() > 0.45) ink = c;
    if (accent == null &&
        _saturation(c) > 0.35 &&
        (light - groundLight).abs() > 0.08) {
      accent = c;
    }
    if (ink != null && accent != null) break;
  }
  ink ??= groundLight > 0.4 ? const Color(0xFF1A1D23) : const Color(0xFFF2F4F7);
  accent ??= Color.lerp(ground, ink, 0.18)!.withValues(alpha: 1);
  return CanvasColours(ground, ink, accent);
}

double _saturation(Color c) {
  var most = math.max(c.r, math.max(c.g, c.b));
  var least = math.min(c.r, math.min(c.g, c.b));
  return most <= 0 ? 0 : (most - least) / most;
}

/// tableInColours is [e] dressed in [colours]: its header band in the
/// accent, its words in the ink, its rules and stripes faint ink -- the
/// sizes, rules and everything else as they were.
TableElement tableInColours(TableElement e, CanvasColours colours) {
  var onAccent = colours.accent.computeLuminance() > 0.4
      ? const Color(0xFF111418)
      : const Color(0xFFFFFFFF);
  return e.copyWith(
    headerFill: colours.accent,
    flatHeader: true,
    cellFill: const Color(0x00000000),
    flatCells: true,
    zebraFill: colours.ink.withValues(alpha: 0.07),
    gridColor: colours.ink.withValues(alpha: 0.22),
    headerSpec: e.headerSpec.copyWith(color: onAccent),
    cellSpec: e.cellSpec.copyWith(color: colours.ink),
  );
}

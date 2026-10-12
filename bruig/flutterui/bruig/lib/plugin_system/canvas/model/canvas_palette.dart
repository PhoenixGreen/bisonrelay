import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// canvas_palette.dart is a document's own colours: a few named swatches that
// everything on it -- shapes, words, charts, tables, backgrounds,
// transitions -- is drawn in, so that changing one swatch recolours the
// whole video at once.
//
// The colours stay where they always were, on each element as a plain
// colour, and the palette changes them where they are: a swatch changed is
// every use of its old colour, anywhere in the document, made the new one.
// That keeps every painter, every export and every document ever saved
// exactly as it was, at the cost of the palette being a promise about which
// colours are the same rather than a reference each element holds -- which
// is also what makes "take the palette from this canvas" possible at all.

/// PaletteSwatch is one of a document's colours, with a name.
class PaletteSwatch {
  final String name;
  final Color color;
  const PaletteSwatch(this.name, this.color);

  PaletteSwatch copyWith({String? name, Color? color}) =>
      PaletteSwatch(name ?? this.name, color ?? this.color);

  Map<String, dynamic> toJson() => {"name": name, "color": colorToJson(color)};

  static PaletteSwatch? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json["color"] is! num) return null;
    return PaletteSwatch(
        jsonString(json["name"], ""), colorFromJson(json["color"]));
  }
}

/// _notColours are keys whose numbers are never colours, however much they
/// look like one: frames, lengths, counts, a chart's numbers, a counter's.
/// A colour is a large integer, and so is thirty million atoms.
const _notColours = {
  "frame", "frames", "at", "seed", "from", "to", "count", "values", "value",
  "length", "start", "end", "width", "height", "w", "h", "x", "y", "rows",
  "exportWidth", "loopFrames", "passFrames", "pauseAt", "pauseFor",
  "series", "data", "estimated", "track", "keys", "vb", "nodes", "points",
  "envelope", "textStyles", "cues", "decimals", "rate", "params",
};

/// _rgb is a colour's red, green and blue, without its opacity.
int _rgb(int argb) => argb & 0xFFFFFF;

/// _looksLikeColour is whether [v] could be a colour at all: an integer with
/// some opacity in it. A colour with none is invisible, and nothing is lost
/// by leaving it alone.
bool _looksLikeColour(Object? v) => v is int && v >= 0x01000000 && v <= 0xFFFFFFFF;

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

/// coloursUsed is the colours [json] is drawn in, by how often, most used
/// first, opacity set aside.
List<Color> coloursUsed(Map<String, dynamic> json) {
  var counts = <int, int>{};
  _walk(json, (v) {
    var rgb = _rgb(v);
    counts[rgb] = (counts[rgb] ?? 0) + 1;
    return v;
  });
  var order = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (var rgb in order) Color(0xFF000000 | rgb)];
}

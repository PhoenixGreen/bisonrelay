import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

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

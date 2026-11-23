import 'dart:ui' show Color;

import 'package:bruig/components/paint_spec.dart';

// colour_map.dart is how a canvas's colours are visited: each type that owns
// a colour has a mapColours that puts every colour it holds, and every colour
// of what it holds, through one function, and answers a copy. So "replace a
// colour everywhere" and "the colours in use" ask the types instead of
// guessing from saved numbers.
//
// Two rules hold for every mapColours:
//  1. Nothing changed, nothing new: when the function hands every colour back
//     unchanged, the very same object comes back (and the same list or map
//     where it holds one), all the way up. The controller compares documents
//     by identity, so a replace that finds nothing is no edit at all.
//  2. A colour that can be none (a nullable field) stays none: the function
//     is not asked about it.

/// ColourMap is a change of colours: handed each colour a thing holds, it
/// answers the colour to put there. [shown] says whether that colour is seen
/// as the thing stands: an outline's colour while the outline has no width,
/// a shadow's while there is no shadow, or a light's while the light is off,
/// is held but not shown. A replace changes every colour, shown or not; a
/// count of the colours in use counts only those shown.
typedef ColourMap = Color Function(Color colour, {required bool shown});

/// ColourMapShown narrows a [ColourMap] for a part that is not seen.
extension ColourMapShown on ColourMap {
  /// shownOnlyIf is this map where [shows] is true, and otherwise the same
  /// map told that every colour it is handed is hidden: for a whole part
  /// that is switched off (a layer hidden, a light off), so the types inside
  /// it need not know.
  ColourMap shownOnlyIf(bool shows) =>
      shows ? this : (Color c, {required bool shown}) => this(c, shown: false);
}

/// ColourPass is one object's turn through a [ColourMap]: it maps each
/// colour and nested part it is handed and notes whether any came back
/// different, so the object can answer itself when none did.
///
/// A colour that comes back equal to the one handed in is kept as it was,
/// and a part that comes back identical is kept, so [changed] is true only
/// for a real change.
class ColourPass {
  final ColourMap f;

  /// changed is whether anything handed in so far came back different.
  bool changed = false;

  ColourPass(this.f);

  /// call maps one colour.
  Color call(Color c, {bool shown = true}) {
    var next = f(c, shown: shown);
    if (next == c) return c;
    changed = true;
    return next;
  }

  /// orNone maps a colour that may be none, which stays none.
  Color? orNone(Color? c, {bool shown = true}) =>
      c == null ? null : call(c, shown: shown);

  /// argb maps a colour kept as a 0xAARRGGBB number.
  int argb(int v, {bool shown = true}) {
    var c = Color(v & 0xFFFFFFFF);
    var next = f(c, shown: shown);
    if (next == c) return v;
    changed = true;
    return next.toARGB32();
  }

  /// argbOrNone is [argb] for a number that may be none.
  int? argbOrNone(int? v, {bool shown = true}) =>
      v == null ? null : argb(v, shown: shown);

  /// rgb maps a colour kept as 0xRRGGBB, with no alpha: it is handed over
  /// opaque, and the answer's alpha is dropped on the way back, so a map
  /// that answers a colour that is not opaque has its alpha discarded here.
  int rgb(int v, {bool shown = true}) {
    var c = Color(0xFF000000 | (v & 0xFFFFFF));
    var next = f(c, shown: shown);
    if (next == c) return v;
    var out = next.toARGB32() & 0xFFFFFF;
    if (out == (v & 0xFFFFFF)) return v;
    changed = true;
    return out;
  }

  /// argbNumber maps a colour kept as a 0xAARRGGBB number held in a double,
  /// as a Design device keys its colours. A number that is not finite is not
  /// a colour and is left as it is.
  double argbNumber(double v, {bool shown = true}) {
    if (!v.isFinite) return v;
    var c = Color(v.toInt() & 0xFFFFFFFF);
    var next = f(c, shown: shown);
    if (next == c) return v;
    changed = true;
    return next.toARGB32().toDouble();
  }

  /// hex maps a colour kept as six hex digits, "rrggbb", with no alpha and
  /// no "#", as a character's shape choices keep theirs. The answer is
  /// written the same way, lower case, its alpha dropped as for [rgb]; a
  /// string that is not six hex digits is not a colour and is left alone.
  String hex(String s, {bool shown = true}) {
    if (!RegExp(r"^[0-9a-fA-F]{6}$").hasMatch(s)) return s;
    var v = int.parse(s, radix: 16);
    var out = rgb(v, shown: shown);
    if (out == v) return s;
    return out.toRadixString(16).padLeft(6, "0");
  }

  /// part maps a nested part through [map], keeping it where it comes back
  /// identical.
  T part<T>(T v, T Function(T v) map) {
    var next = map(v);
    if (identical(next, v)) return v;
    changed = true;
    return next;
  }

  /// partOrNone is [part] for a part that may be none, which stays none.
  T? partOrNone<T extends Object>(T? v, T Function(T v) map) =>
      v == null ? null : part<T>(v, map);

  /// list maps each of a list's items through [map], answering the very same
  /// list where every item comes back identical.
  List<T> list<T>(List<T> items, T Function(T v) map) {
    var next = mappedList(items, map);
    if (!identical(next, items)) changed = true;
    return next;
  }

  /// values maps each of a map's values through [map], answering the very
  /// same map where every value comes back identical.
  Map<K, V> values<K, V>(Map<K, V> items, V Function(K key, V v) map) {
    var next = mappedValues(items, map);
    if (!identical(next, items)) changed = true;
    return next;
  }
}

/// mappedList is [items] with each put through [map], or [items] itself
/// where every one comes back identical.
List<T> mappedList<T>(List<T> items, T Function(T v) map) {
  List<T>? out;
  for (var i = 0; i < items.length; i++) {
    var next = map(items[i]);
    if (out == null && !identical(next, items[i])) {
      out = [...items.take(i)];
    }
    out?.add(next);
  }
  return out ?? items;
}

/// mappedValues is [items] with each value put through [map], or [items]
/// itself where every one comes back identical. Keys keep their order.
Map<K, V> mappedValues<K, V>(Map<K, V> items, V Function(K key, V v) map) {
  var changed = false;
  var out = <K, V>{};
  for (var MapEntry(:key, :value) in items.entries) {
    var next = map(key, value);
    if (!identical(next, value)) changed = true;
    out[key] = next;
  }
  return changed ? out : items;
}

/// GradientStopColours maps a gradient stop's colour. Defined here rather
/// than on the class, which the app's theming shares.
extension GradientStopColours on GradientStop {
  GradientStop mapColours(ColourMap f) {
    var next = f(color, shown: true);
    return next == color ? this : copyWith(color: next);
  }
}

/// GradientSpecColours maps a gradient's second colour and any after it;
/// its first is its holder's. Defined here rather than on the class, which
/// the app's theming shares.
extension GradientSpecColours on GradientSpec {
  GradientSpec mapColours(ColourMap f) {
    var p = ColourPass(f);
    var to = p(this.to);
    var more = p.list(this.more, (s) => s.mapColours(f));
    if (!p.changed) return this;
    return copyWith(to: to, more: more);
  }
}

/// PaintSpecColours maps a paint's colour and its fade. Defined here rather
/// than on the class, which the app's theming shares.
extension PaintSpecColours on PaintSpec {
  PaintSpec mapColours(ColourMap f) {
    var p = ColourPass(f);
    var color = p(this.color);
    var gradient = p.partOrNone(this.gradient, (g) => g.mapColours(f));
    if (!p.changed) return this;
    return copyWith(color: color, gradient: gradient);
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// font_outlines.dart reads the shapes of letters out of a font file, which
// Flutter will draw but will not hand over: a drawing's text is its letters'
// outlines, so that once it is edited it is points like anything else.
//
// Both kinds of outline a font carries. TrueType's (the glyf table, curves
// with one handle) in .ttf files and collections of them; and the Compact
// Font Format's (CFF, curves with two, as a small program per letter) in
// .otf files -- Inter, the app's own face, is one. Enough of each to draw
// any letter of a Latin font: the character map, the advances, the older
// kerning table, composite letters built of others, and CFF's subroutines.
// Not hinting, which is for pixels, and not a variable font's other weights:
// its outlines as they are, the regular.

/// GlyphSegment is one stretch of a letter's outline, in the font's own
/// units with y upward: a straight line where [line], else a curve with two
/// handles.
class GlyphSegment {
  final Offset c1, c2, to;
  final bool line;
  const GlyphSegment.line(this.to)
      : c1 = Offset.zero,
        c2 = Offset.zero,
        line = true;
  const GlyphSegment.curve(this.c1, this.c2, this.to) : line = false;
}

/// GlyphContour is one closed run of a letter's outline: where it starts,
/// and its segments round, the last ending where it started.
class GlyphContour {
  final Offset start;
  final List<GlyphSegment> segments;
  const GlyphContour(this.start, this.segments);

  GlyphContour transformed(Offset Function(Offset) f) =>
      GlyphContour(f(start), [
        for (var s in segments)
          s.line
              ? GlyphSegment.line(f(s.to))
              : GlyphSegment.curve(f(s.c1), f(s.c2), f(s.to)),
      ]);
}

/// FontFace is one face of a font file, read for its letters' outlines.
class FontFace {
  final ByteData _d;
  final Map<String, (int, int)> _tables;
  final int unitsPerEm;
  final int ascender;
  final int descender;
  final int lineGap;
  final int _hMetrics;
  final int _locFormat;
  final int Function(int) _cmap;
  final Map<int, int> _kern;
  final _Cff? _cff;
  final Map<int, List<GlyphContour>> _outlines = {};

  FontFace._(
      this._d,
      this._tables,
      this.unitsPerEm,
      this.ascender,
      this.descender,
      this.lineGap,
      this._hMetrics,
      this._locFormat,
      this._cmap,
      this._kern,
      this._cff);

  /// parse reads [bytes] -- a font file, or face [index] of a collection --
  /// or gives null where it is not one this can read.
  static FontFace? parse(Uint8List bytes, {int index = 0}) {
    try {
      var d = ByteData.sublistView(bytes);
      var at = 0;
      if (_tag(d, 0) == "ttcf") {
        var count = d.getUint32(8);
        if (index >= count) return null;
        at = d.getUint32(12 + 4 * index);
      }
      var tables = <String, (int, int)>{};
      var n = d.getUint16(at + 4);
      for (var i = 0; i < n; i++) {
        var r = at + 12 + 16 * i;
        tables[_tag(d, r)] = (d.getUint32(r + 8), d.getUint32(r + 12));
      }
      var head = tables["head"]!.$1, hhea = tables["hhea"]!.$1;
      var cff = tables["CFF "];
      return FontFace._(
        d,
        tables,
        d.getUint16(head + 18),
        d.getInt16(hhea + 4),
        d.getInt16(hhea + 6),
        d.getInt16(hhea + 8),
        d.getUint16(hhea + 34),
        d.getInt16(head + 50),
        _readCmap(d, tables["cmap"]!.$1),
        tables["kern"] == null ? const {} : _readKern(d, tables["kern"]!.$1),
        cff == null ? null : _Cff(d, cff.$1),
      );
    } catch (_) {
      return null;
    }
  }

  /// faces is how many faces [bytes] holds: one, unless it is a
  /// collection.
  static int faces(Uint8List bytes) {
    var d = ByteData.sublistView(bytes);
    return bytes.length >= 12 && _tag(d, 0) == "ttcf" ? d.getUint32(8) : 1;
  }

  /// style is the face's own name for its style -- "Regular", "Bold
  /// Oblique" -- from its name table, or "" where it gives none.
  String get style {
    var name = _tables["name"];
    if (name == null) return "";
    var at = name.$1;
    var count = _d.getUint16(at + 2), strings = at + _d.getUint16(at + 4);
    for (var i = 0; i < count; i++) {
      var r = at + 6 + 12 * i;
      var platform = _d.getUint16(r), id = _d.getUint16(r + 6);
      if (id != 2) continue;
      var len = _d.getUint16(r + 8), off = strings + _d.getUint16(r + 10);
      if (platform == 3 || platform == 0) {
        return String.fromCharCodes([
          for (var k = 0; k + 1 < len; k += 2) _d.getUint16(off + k),
        ]);
      }
      if (platform == 1) {
        return String.fromCharCodes(
            [for (var k = 0; k < len; k++) _d.getUint8(off + k)]);
      }
    }
    return "";
  }

  /// glyphFor is the letter drawn for [codepoint], or nought -- the font's
  /// box for a letter it does not have.
  int glyphFor(int codepoint) => _cmap(codepoint);

  /// advance is how far on the next letter starts after [glyph].
  int advance(int glyph) {
    var hmtx = _tables["hmtx"]!.$1;
    var i = glyph < _hMetrics ? glyph : _hMetrics - 1;
    return _d.getUint16(hmtx + 4 * i);
  }

  /// kerning is how much closer -- less than nought -- or further apart
  /// [left] and [right] sit side by side.
  int kerning(int left, int right) => _kern[(left << 16) | right] ?? 0;

  /// outline is [glyph]'s outline, in font units with y upward.
  List<GlyphContour> outline(int glyph) =>
      _outlines[glyph] ??= _readOutline(glyph, 0);

  List<GlyphContour> _readOutline(int glyph, int depth) {
    try {
      if (_cff case var cff?) return cff.outline(glyph);
      return _glyf(glyph, depth);
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------------------
  // TrueType
  // ------------------------------------------------------------------------

  List<GlyphContour> _glyf(int glyph, int depth) {
    var loca = _tables["loca"]!.$1, glyf = _tables["glyf"]!.$1;
    int off(int g) => _locFormat == 0
        ? _d.getUint16(loca + 2 * g) * 2
        : _d.getUint32(loca + 4 * g);
    var start = off(glyph), end = off(glyph + 1);
    if (end <= start) return const [];
    var p = glyf + start;
    var contours = _d.getInt16(p);
    if (contours < 0) return depth > 8 ? const [] : _composite(p, depth);
    var ends = [
      for (var i = 0; i < contours; i++) _d.getUint16(p + 10 + 2 * i)
    ];
    if (ends.isEmpty) return const [];
    var points = ends.last + 1;
    var q = p + 10 + 2 * contours;
    q += 2 + _d.getUint16(q);
    var flags = <int>[];
    while (flags.length < points) {
      var f = _d.getUint8(q++);
      flags.add(f);
      if (f & 8 != 0) {
        var r = _d.getUint8(q++);
        for (var k = 0; k < r; k++) {
          flags.add(f);
        }
      }
    }
    var xs = List<int>.filled(points, 0), ys = List<int>.filled(points, 0);
    var v = 0;
    for (var i = 0; i < points; i++) {
      var f = flags[i];
      if (f & 2 != 0) {
        var dx = _d.getUint8(q++);
        v += f & 16 != 0 ? dx : -dx;
      } else if (f & 16 == 0) {
        v += _d.getInt16(q);
        q += 2;
      }
      xs[i] = v;
    }
    v = 0;
    for (var i = 0; i < points; i++) {
      var f = flags[i];
      if (f & 4 != 0) {
        var dy = _d.getUint8(q++);
        v += f & 32 != 0 ? dy : -dy;
      } else if (f & 32 == 0) {
        v += _d.getInt16(q);
        q += 2;
      }
      ys[i] = v;
    }
    var out = <GlyphContour>[];
    var from = 0;
    for (var e in ends) {
      var pts = [
        for (var i = from; i <= e; i++)
          (Offset(xs[i].toDouble(), ys[i].toDouble()), flags[i] & 1 != 0),
      ];
      from = e + 1;
      if (pts.length >= 2) out.add(_quadContour(pts));
    }
    return out;
  }

  /// _quadContour is a TrueType run -- points on the line and handles off
  /// it, a point halfway between any two handles in a row -- as segments.
  static GlyphContour _quadContour(List<(Offset, bool)> pts) {
    var n = pts.length;
    // Start on a point on the line: the first that is, or halfway between
    // the first two handles.
    var first = pts.indexWhere((p) => p.$2);
    Offset start;
    int i0;
    if (first < 0) {
      start = (pts[0].$1 + pts[1].$1) / 2;
      i0 = 1;
    } else {
      start = pts[first].$1;
      i0 = first + 1;
    }
    var segs = <GlyphSegment>[];
    var cur = start;
    Offset? handle;
    void quad(Offset c, Offset to) {
      segs.add(GlyphSegment.curve(
          cur + (c - cur) * (2 / 3), to + (c - to) * (2 / 3), to));
      cur = to;
    }

    for (var k = 0; k < n; k++) {
      var (p, on) = pts[(i0 + k) % n];
      if (on) {
        if (handle != null) {
          quad(handle, p);
          handle = null;
        } else {
          segs.add(GlyphSegment.line(p));
          cur = p;
        }
      } else {
        if (handle != null) quad(handle, (handle + p) / 2);
        handle = p;
      }
    }
    if (handle != null) {
      quad(handle, start);
    } else if (cur != start) {
      segs.add(GlyphSegment.line(start));
    }
    return GlyphContour(start, segs);
  }

  List<GlyphContour> _composite(int p, int depth) {
    var q = p + 10;
    var out = <GlyphContour>[];
    while (true) {
      var flags = _d.getUint16(q), glyph = _d.getUint16(q + 2);
      q += 4;
      double dx, dy;
      if (flags & 1 != 0) {
        dx = (flags & 2 != 0 ? _d.getInt16(q) : _d.getUint16(q)).toDouble();
        dy = (flags & 2 != 0 ? _d.getInt16(q + 2) : _d.getUint16(q + 2))
            .toDouble();
        q += 4;
      } else {
        dx = (flags & 2 != 0 ? _d.getInt8(q) : _d.getUint8(q)).toDouble();
        dy = (flags & 2 != 0 ? _d.getInt8(q + 1) : _d.getUint8(q + 1))
            .toDouble();
        q += 2;
      }
      // Matched by points rather than moved by offsets: put where it is.
      if (flags & 2 == 0) dx = dy = 0;
      double f2(int at) => _d.getInt16(at) / 16384;
      var a = 1.0, b = 0.0, c = 0.0, d = 1.0;
      if (flags & 8 != 0) {
        a = d = f2(q);
        q += 2;
      } else if (flags & 0x40 != 0) {
        a = f2(q);
        d = f2(q + 2);
        q += 4;
      } else if (flags & 0x80 != 0) {
        a = f2(q);
        b = f2(q + 2);
        c = f2(q + 4);
        d = f2(q + 6);
        q += 8;
      }
      for (var part in _readOutline(glyph, depth + 1)) {
        out.add(part.transformed(
            (o) => Offset(a * o.dx + c * o.dy + dx, b * o.dx + d * o.dy + dy)));
      }
      if (flags & 0x20 == 0) break;
    }
    return out;
  }
}

String _tag(ByteData d, int at) =>
    String.fromCharCodes([for (var i = 0; i < 4; i++) d.getUint8(at + i)]);

/// _readCmap is the font's character map, as a lookup: the Unicode one,
/// the full range where it has it.
int Function(int) _readCmap(ByteData d, int at) {
  var n = d.getUint16(at + 2);
  int? best;
  var bestRank = -1;
  for (var i = 0; i < n; i++) {
    var r = at + 4 + 8 * i;
    var platform = d.getUint16(r), encoding = d.getUint16(r + 2);
    var sub = at + d.getUint32(r + 4);
    var format = d.getUint16(sub);
    var rank = switch ((platform, encoding, format)) {
      (3, 10, 12) || (0, _, 12) => 3,
      (3, 1, 4) || (0, _, 4) => 2,
      (3, 0, 4) => 1,
      _ => -1,
    };
    if (rank > bestRank) {
      bestRank = rank;
      best = sub;
    }
  }
  if (best == null) return (_) => 0;
  var sub = best;
  if (d.getUint16(sub) == 12) {
    var groups = d.getUint32(sub + 12);
    return (c) {
      var lo = 0, hi = groups - 1;
      while (lo <= hi) {
        var mid = (lo + hi) >> 1, g = sub + 16 + 12 * mid;
        var s = d.getUint32(g), e = d.getUint32(g + 4);
        if (c < s) {
          hi = mid - 1;
        } else if (c > e) {
          lo = mid + 1;
        } else {
          return d.getUint32(g + 8) + c - s;
        }
      }
      return 0;
    };
  }
  var segs = d.getUint16(sub + 6) ~/ 2;
  var ends = sub + 14, starts = ends + 2 * segs + 2;
  var deltas = starts + 2 * segs, ranges = deltas + 2 * segs;
  return (c) {
    if (c > 0xFFFF) return 0;
    for (var i = 0; i < segs; i++) {
      if (d.getUint16(ends + 2 * i) < c) continue;
      var s = d.getUint16(starts + 2 * i);
      if (s > c) return 0;
      var delta = d.getInt16(deltas + 2 * i);
      var range = d.getUint16(ranges + 2 * i);
      if (range == 0) return (c + delta) & 0xFFFF;
      var g = d.getUint16(ranges + 2 * i + range + 2 * (c - s));
      return g == 0 ? 0 : (g + delta) & 0xFFFF;
    }
    return 0;
  };
}

/// _readKern is the older kerning table's pairs, keyed left << 16 | right.
Map<int, int> _readKern(ByteData d, int at) {
  var out = <int, int>{};
  var n = d.getUint16(at + 2);
  var p = at + 4;
  for (var t = 0; t < n; t++) {
    var length = d.getUint16(p + 2), coverage = d.getUint16(p + 4);
    if (coverage >> 8 == 0 && coverage & 1 != 0) {
      var pairs = d.getUint16(p + 6);
      for (var i = 0; i < pairs; i++) {
        var r = p + 14 + 6 * i;
        out[(d.getUint16(r) << 16) | d.getUint16(r + 2)] = d.getInt16(r + 4);
      }
    }
    p += length;
  }
  return out;
}

// --------------------------------------------------------------------------
// CFF
// --------------------------------------------------------------------------

/// _Index is one of CFF's INDEXes: a count of items, and where each is.
class _Index {
  final List<(int, int)> items;
  final int end;
  _Index(this.items, this.end);

  factory _Index.at(ByteData d, int at) {
    var count = d.getUint16(at);
    if (count == 0) return _Index(const [], at + 2);
    var size = d.getUint8(at + 2);
    int off(int i) {
      var p = at + 3 + i * size, v = 0;
      for (var k = 0; k < size; k++) {
        v = (v << 8) | d.getUint8(p + k);
      }
      return v;
    }

    var base = at + 3 + (count + 1) * size - 1;
    return _Index([
      for (var i = 0; i < count; i++) (base + off(i), base + off(i + 1)),
    ], base + off(count));
  }

  int get length => items.length;
}

/// _dict reads a CFF DICT: each operator with the numbers before it.
Map<int, List<double>> _dict(ByteData d, int from, int to) {
  var out = <int, List<double>>{};
  var nums = <double>[];
  var p = from;
  while (p < to) {
    var b = d.getUint8(p);
    if (b <= 21) {
      var op = b;
      p++;
      if (b == 12) op = 1200 + d.getUint8(p++);
      out[op] = nums;
      nums = [];
    } else if (b == 28) {
      nums.add(d.getInt16(p + 1).toDouble());
      p += 3;
    } else if (b == 29) {
      nums.add(d.getInt32(p + 1).toDouble());
      p += 5;
    } else if (b == 30) {
      var s = StringBuffer();
      p++;
      var done = false;
      while (!done) {
        var byte = d.getUint8(p++);
        for (var nib in [byte >> 4, byte & 15]) {
          if (nib == 15) {
            done = true;
            break;
          }
          s.write(switch (nib) {
            10 => ".",
            11 => "E",
            12 => "E-",
            14 => "-",
            13 => "",
            _ => "$nib",
          });
        }
      }
      nums.add(double.tryParse(s.toString()) ?? 0);
    } else if (b >= 32 && b <= 246) {
      nums.add(b - 139.0);
      p++;
    } else if (b >= 247 && b <= 250) {
      nums.add(((b - 247) * 256 + d.getUint8(p + 1) + 108).toDouble());
      p += 2;
    } else if (b >= 251 && b <= 254) {
      nums.add((-(b - 251) * 256 - d.getUint8(p + 1) - 108).toDouble());
      p += 2;
    } else {
      p++;
    }
  }
  return out;
}

int _bias(int count) => count < 1240 ? 107 : (count < 33900 ? 1131 : 32768);

/// _Cff is a font's CFF table: its letters as Type 2 charstrings, run to
/// draw them.
class _Cff {
  final ByteData d;
  late final _Index _chars;
  late final _Index _global;
  final List<_Index> _locals = [];
  int Function(int) _fdOf = (_) => 0;

  _Cff(this.d, int at) {
    var hdr = d.getUint8(at + 2);
    var names = _Index.at(d, at + hdr);
    var tops = _Index.at(d, names.end);
    var strings = _Index.at(d, tops.end);
    _global = _Index.at(d, strings.end);
    var top = _dict(d, tops.items[0].$1, tops.items[0].$2);
    _chars = _Index.at(d, at + top[17]![0].toInt());
    _Index local(List<double>? private) {
      if (private == null || private.length < 2) return _Index(const [], 0);
      var size = private[0].toInt(), off = at + private[1].toInt();
      var pd = _dict(d, off, off + size);
      var subrs = pd[19];
      return subrs == null
          ? _Index(const [], 0)
          : _Index.at(d, off + subrs[0].toInt());
    }

    var fdArray = top[1236];
    if (fdArray != null) {
      // A font keyed by character ID: each letter's own private dictionary.
      var fds = _Index.at(d, at + fdArray[0].toInt());
      for (var (s, e) in fds.items) {
        _locals.add(local(_dict(d, s, e)[18]));
      }
      var sel = at + top[1237]![0].toInt();
      var format = d.getUint8(sel);
      if (format == 0) {
        _fdOf = (g) => d.getUint8(sel + 1 + g);
      } else if (format == 3) {
        var n = d.getUint16(sel + 1);
        _fdOf = (g) {
          for (var i = 0; i < n; i++) {
            var r = sel + 3 + 3 * i;
            if (g >= d.getUint16(r) && g < d.getUint16(r + 3)) {
              return d.getUint8(r + 2);
            }
          }
          return 0;
        };
      }
    } else {
      _locals.add(local(top[18]));
    }
  }

  List<GlyphContour> outline(int glyph) {
    if (glyph >= _chars.length) return const [];
    var local = _locals[math.min(_fdOf(glyph), _locals.length - 1)];
    return _Charstring(d, _global, local).run(_chars.items[glyph]);
  }
}

/// _Charstring runs one letter's Type 2 charstring, drawing as it goes.
class _Charstring {
  final ByteData d;
  final _Index global, local;
  final stack = <double>[];
  final contours = <GlyphContour>[];
  List<GlyphSegment> _segs = [];
  Offset _start = Offset.zero;
  var x = 0.0, y = 0.0;
  var stems = 0;
  var widthDone = false;
  var ended = false;

  _Charstring(this.d, this.global, this.local);

  List<GlyphContour> run((int, int) at) {
    _exec(at.$1, at.$2, 0);
    _close();
    return contours;
  }

  void _close() {
    if (_segs.isNotEmpty) {
      if (Offset(x, y) != _start) _segs.add(GlyphSegment.line(_start));
      contours.add(GlyphContour(_start, _segs));
    }
    _segs = [];
  }

  void _moveTo(double dx, double dy) {
    _close();
    x += dx;
    y += dy;
    _start = Offset(x, y);
  }

  void _lineTo(double dx, double dy) {
    x += dx;
    y += dy;
    _segs.add(GlyphSegment.line(Offset(x, y)));
  }

  void _curveTo(double a, double b, double c, double e, double f, double g) {
    var c1 = Offset(x + a, y + b);
    var c2 = c1 + Offset(c, e);
    var to = c2 + Offset(f, g);
    _segs.add(GlyphSegment.curve(c1, c2, to));
    x = to.dx;
    y = to.dy;
  }

  /// _width drops the advance width a letter's first operator may carry.
  void _width(bool odd) {
    if (!widthDone && odd && stack.isNotEmpty) stack.removeAt(0);
    widthDone = true;
  }

  void _exec(int p, int end, int depth) {
    while (p < end && !ended) {
      var b = d.getUint8(p);
      if (b >= 32 || b == 28) {
        if (b == 28) {
          stack.add(d.getInt16(p + 1).toDouble());
          p += 3;
        } else if (b <= 246) {
          stack.add(b - 139.0);
          p++;
        } else if (b <= 250) {
          stack.add(((b - 247) * 256 + d.getUint8(p + 1) + 108).toDouble());
          p += 2;
        } else if (b <= 254) {
          stack.add((-(b - 251) * 256 - d.getUint8(p + 1) - 108).toDouble());
          p += 2;
        } else {
          stack.add(d.getInt32(p + 1) / 65536);
          p += 5;
        }
        continue;
      }
      p++;
      var s = stack;
      switch (b) {
        case 1 || 3 || 18 || 23:
          _width(s.length.isOdd);
          stems += s.length ~/ 2;
          s.clear();
        case 19 || 20:
          _width(s.length.isOdd);
          stems += s.length ~/ 2;
          s.clear();
          p += (stems + 7) ~/ 8;
        case 21:
          _width(s.length > 2);
          _moveTo(s[0], s[1]);
          s.clear();
        case 22:
          _width(s.length > 1);
          _moveTo(s[0], 0);
          s.clear();
        case 4:
          _width(s.length > 1);
          _moveTo(0, s[0]);
          s.clear();
        case 5:
          for (var i = 0; i + 1 < s.length; i += 2) {
            _lineTo(s[i], s[i + 1]);
          }
          s.clear();
        case 6 || 7:
          var horizontal = b == 6;
          for (var v in s) {
            horizontal ? _lineTo(v, 0) : _lineTo(0, v);
            horizontal = !horizontal;
          }
          s.clear();
        case 8:
          for (var i = 0; i + 5 < s.length; i += 6) {
            _curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
          }
          s.clear();
        case 27:
          var i = 0;
          var dy1 = 0.0;
          if (s.length.isOdd) dy1 = s[i++];
          for (; i + 3 < s.length; i += 4) {
            _curveTo(s[i], dy1, s[i + 1], s[i + 2], s[i + 3], 0);
            dy1 = 0;
          }
          s.clear();
        case 26:
          var i = 0;
          var dx1 = 0.0;
          if (s.length.isOdd) dx1 = s[i++];
          for (; i + 3 < s.length; i += 4) {
            _curveTo(dx1, s[i], s[i + 1], s[i + 2], 0, s[i + 3]);
            dx1 = 0;
          }
          s.clear();
        case 30 || 31:
          var horizontal = b == 31;
          var i = 0;
          while (i + 3 < s.length) {
            var last = s.length - i == 5 ? s[i + 4] : 0.0;
            if (horizontal) {
              _curveTo(s[i], 0, s[i + 1], s[i + 2], last, s[i + 3]);
            } else {
              _curveTo(0, s[i], s[i + 1], s[i + 2], s[i + 3], last);
            }
            i += 4;
            horizontal = !horizontal;
          }
          s.clear();
        case 24:
          var i = 0;
          for (; i + 7 < s.length; i += 6) {
            _curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
          }
          _lineTo(s[i], s[i + 1]);
          s.clear();
        case 25:
          var i = 0;
          for (; i + 7 < s.length; i += 2) {
            _lineTo(s[i], s[i + 1]);
          }
          _curveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5]);
          s.clear();
        case 10 || 29:
          var index = b == 10 ? local : global;
          var n = s.removeLast().toInt() + _bias(index.length);
          if (n >= 0 && n < index.length && depth < 10) {
            var (from, to) = index.items[n];
            _exec(from, to, depth + 1);
          }
        case 11:
          return;
        case 14:
          _width(s.length == 1 || s.length == 5);
          _close();
          ended = true;
          s.clear();
        case 12:
          var op = d.getUint8(p++);
          switch (op) {
            case 35:
              _curveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
              _curveTo(s[6], s[7], s[8], s[9], s[10], s[11]);
            case 34:
              _curveTo(s[0], 0, s[1], s[2], s[3], 0);
              _curveTo(s[4], 0, s[5], -s[2], s[6], 0);
            case 36:
              _curveTo(s[0], s[1], s[2], s[3], s[4], 0);
              _curveTo(s[5], 0, s[6], s[7], s[8], -(s[1] + s[3] + s[7]));
            case 37:
              var dx = s[0] + s[2] + s[4] + s[6] + s[8];
              var dy = s[1] + s[3] + s[5] + s[7] + s[9];
              _curveTo(s[0], s[1], s[2], s[3], s[4], s[5]);
              if (dx.abs() > dy.abs()) {
                _curveTo(s[6], s[7], s[8], s[9], s[10], -dy);
              } else {
                _curveTo(s[6], s[7], s[8], s[9], -dx, s[10]);
              }
          }
          s.clear();
        default:
          s.clear();
      }
    }
  }
}

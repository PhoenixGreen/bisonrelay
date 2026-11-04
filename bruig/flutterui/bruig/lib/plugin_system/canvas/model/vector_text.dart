import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/model/font_outlines.dart';

// vector_text.dart sets a drawing's text in the font's own outlines, as the
// same runs of points any shape is made of, so the text can later be edited
// into an ordinary shape. See VectorText.

/// VectorTextLayout is text laid out: its runs, the caret position on the
/// baseline before each character (plus one after the last), and the line's
/// ascent and descent.
class VectorTextLayout {
  final List<VectorPath> runs;
  final List<Offset> carets;
  final double ascent;
  final double descent;
  const VectorTextLayout(this.runs, this.carets, this.ascent, this.descent);
}

/// layoutVectorText lays [t] out from [origin] -- where its first line
/// starts, on the baseline -- in [pick]'s outlines.
VectorTextLayout layoutVectorText(VectorText t, Offset origin, FontPick pick) {
  var face = pick.face;
  var k = t.size / face.unitsPerEm;
  var lean = pick.lean ? 0.2 : 0.0;
  var lineHeight =
      (face.ascender - face.descender + face.lineGap) * k * t.leading;
  var runs = <VectorPath>[];
  var carets = <Offset>[];
  var lines = t.text.split("\n");
  for (var (row, line) in lines.indexed) {
    var y = origin.dy + row * lineHeight;
    // Where each letter goes, before lining the line up.
    var placed = <(int, double)>[];
    var x = 0.0;
    var xs = <double>[];
    int? before;
    for (var unit in line.runes) {
      var glyph = face.glyphFor(unit);
      if (before != null) x += face.kerning(before, glyph) * k;
      xs.add(x);
      // A character beyond the first plane takes two places in the text,
      // and the caret stands at the same place for both.
      if (unit > 0xFFFF) xs.add(x);
      placed.add((glyph, x));
      x += face.advance(glyph) * k + t.spacing * t.size;
      before = glyph;
    }
    var width = line.isEmpty ? 0.0 : x - t.spacing * t.size;
    xs.add(width);
    var shift = switch (t.align) {
      VectorTextAlign.left => 0.0,
      VectorTextAlign.centre => -width / 2,
      VectorTextAlign.right => -width,
    };
    for (var cx in xs) {
      carets.add(Offset(origin.dx + shift + cx, y));
    }
    for (var (glyph, gx) in placed) {
      Offset at(Offset p) => Offset(
          origin.dx + shift + gx + (p.dx + lean * p.dy) * k, y - p.dy * k);
      for (var contour in face.outline(glyph)) {
        if (_run(contour, at) case var run?) runs.add(run);
      }
    }
  }
  // One place per character of the text and one after: each line's end
  // is where its newline stands.
  return VectorTextLayout(runs, carets, face.ascender * k, -face.descender * k);
}

/// _run is one contour of a letter as a closed run of points, placed by
/// [at].
VectorPath? _run(GlyphContour c, Offset Function(Offset) at) {
  if (c.segments.isEmpty) return null;
  var nodes = <VectorNode>[VectorNode(at(c.start).dx, at(c.start).dy)];
  for (var s in c.segments) {
    var to = at(s.to);
    if (s.line) {
      nodes.add(VectorNode(to.dx, to.dy));
      continue;
    }
    var c1 = at(s.c1), c2 = at(s.c2);
    var last = nodes.last;
    nodes[nodes.length - 1] =
        last.copyWith(outX: c1.dx - last.x, outY: c1.dy - last.y);
    nodes.add(VectorNode(to.dx, to.dy, inX: c2.dx - to.dx, inY: c2.dy - to.dy));
  }
  // Round to where it began: the last point is the first again.
  if (nodes.length > 1 &&
      (nodes.last.point - nodes.first.point).distanceSquared < 1e-12) {
    var end = nodes.removeLast();
    nodes[0] = nodes[0].copyWith(inX: end.inX, inY: end.inY);
  }
  if (nodes.length < 2) return null;
  return VectorPath(nodes, closed: true);
}

/// typed is [shape] set as [t] from [origin], in [pick]: its runs become
/// the letters, and the text is kept with a signature (see
/// VectorShape.liveText) so it stays text until the runs are changed.
VectorShape typed(
    VectorShape shape, VectorText t, Offset origin, FontPick pick) {
  var laid = layoutVectorText(t, origin, pick);
  var first = laid.runs.where((r) => r.nodes.isNotEmpty).firstOrNull;
  return shape.copyWith(
    paths: laid.runs,
    text: t.copyWith(
      origin: origin,
      fromFirst: first == null ? Offset.zero : origin - first.nodes.first.point,
      signature: pathSignature(laid.runs),
    ),
  );
}

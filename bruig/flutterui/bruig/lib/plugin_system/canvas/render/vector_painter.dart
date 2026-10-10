import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// vector_painter.dart draws a Vector element: the file it came from, exactly,
// until it has been taken apart for editing -- and its shapes after that.

/// _paths remembers each shape's outline. A shape is never changed in place
/// -- an edit makes a new one -- so its outline is worked out once, rather
/// than on every frame for every one of what can be thousands of points.
final Expando<Path> _paths = Expando<Path>();

Path vectorShapePath(VectorShape shape) => _paths[shape] ??= shape.path;

final Expando<Path> _lines = Expando<Path>();

/// vectorLinePath is [shape]'s line as an area to fill, drawn point by
/// point -- see VectorShape.ownLine. Worked out once per shape, as the
/// outline is.
Path vectorLinePath(VectorShape shape) => _lines[shape] ??= _lineOutline(shape);

/// _lineOutline walks each run in short steps, the width blending from one
/// point's to the next's, and lays a band along it: a four-sided piece from
/// each step to the next, a disc at each step of a curve so it bends without
/// gaps, each point's own corner where one segment meets the next, and each
/// end's own end. Every piece is wound the same way round, so filled
/// together they are one shape with no double paint where they overlap --
/// which matters to a line that is half see-through.
Path _lineOutline(VectorShape shape) {
  var out = Path()..fillType = PathFillType.nonZero;
  var base = shape.strokeWidth;
  if (base <= 0) return out;
  void piece(List<Offset> pts) {
    var area = 0.0;
    for (var i = 0; i < pts.length; i++) {
      var a = pts[i], b = pts[(i + 1) % pts.length];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    if (area.abs() < 1e-12) return;
    out.addPolygon(area < 0 ? pts.reversed.toList() : pts, true);
  }

  void disc(Offset c, double r) {
    if (r <= 0) return;
    piece([
      for (var k = 0; k < 16; k++)
        c + Offset(math.cos(k * math.pi / 8), math.sin(k * math.pi / 8)) * r,
    ]);
  }

  Offset unit(Offset d) =>
      d.distance == 0 ? const Offset(1, 0) : d / d.distance;
  Offset normal(Offset d) {
    var u = unit(d);
    return Offset(-u.dy, u.dx);
  }

  // An end: nothing past the point for flat, a half disc's worth for round,
  // half the width on for square. [dir] points out of the line.
  void end(StrokeCap cap, Offset p, Offset dir, double w) {
    switch (cap) {
      case StrokeCap.butt:
        break;
      case StrokeCap.round:
        disc(p, w / 2);
      case StrokeCap.square:
        var s = normal(dir) * (w / 2), past = unit(dir) * (w / 2);
        piece([p + s, p + s + past, p - s + past, p - s]);
    }
  }

  // A corner, on its outside: the side the line turns away from.
  void corner(StrokeJoin join, Offset p, Offset into, Offset outOf, double w) {
    var a = unit(into), b = unit(outOf);
    var cross = a.dx * b.dy - a.dy * b.dx;
    if (cross.abs() < 1e-4 && a.dx * b.dx + a.dy * b.dy > 0) return;
    if (join == StrokeJoin.round) {
      disc(p, w / 2);
      return;
    }
    var nIn = normal(a), nOut = normal(b);
    var side = nIn.dx * b.dx + nIn.dy * b.dy > 0 ? -1.0 : 1.0;
    var h = w / 2;
    var e1 = p + nIn * side * h, e2 = p + nOut * side * h;
    var mid = nIn + nOut;
    var cosHalf = mid.distance / 2;
    // Sharp, unless so sharp the point would run off -- past four times
    // the width, as a stroke's own corners give up.
    if (join == StrokeJoin.miter && cosHalf > 1 / 4) {
      var tip = p + unit(mid) * side * (h / cosHalf);
      piece([p, e1, tip, e2]);
    } else {
      piece([p, e1, e2]);
    }
  }

  for (var run in shape.paths) {
    var nodes = run.nodes;
    if (nodes.length < 2) {
      if (nodes.length == 1) {
        disc(nodes.single.point, base * nodes.single.width / 2);
      }
      continue;
    }
    // How wide the line is [t] along the segment from point [i]: a curve
    // through the points' widths, so it swells and thins smoothly across
    // them rather than levelling off at each.
    double widthAt(int i, double t) {
      double w(int k) {
        if (run.closed) return nodes[k % nodes.length].width;
        return nodes[k.clamp(0, nodes.length - 1)].width;
      }

      var w0 = w(i), w1 = w(i + 1);
      var m0 = (w1 - w(i - 1 + (run.closed ? nodes.length : 0))) / 2;
      var m1 = (w(i + 2) - w0) / 2;
      var t2 = t * t, t3 = t2 * t;
      var v = (2 * t3 - 3 * t2 + 1) * w0 +
          (t3 - 2 * t2 + t) * m0 +
          (-2 * t3 + 3 * t2) * w1 +
          (t3 - t2) * m1;
      // Never thinner than the thinner end, nor past the wider: no dips or
      // bulges the points do not have.
      return v.clamp(math.min(w0, w1), math.max(w0, w1)).toDouble();
    }

    // Each segment's steps: where, which way, how wide.
    var segments = <List<(Offset, Offset, double)>>[];
    var count = run.closed ? nodes.length : nodes.length - 1;
    for (var i = 0; i < count; i++) {
      var a = nodes[i], b = nodes[(i + 1) % nodes.length];
      var curved = a.hasOut || b.hasIn;
      var seg = Path()..moveTo(a.x, a.y);
      if (!curved) {
        seg.lineTo(b.x, b.y);
      } else {
        seg.cubicTo(a.outHandle.dx, a.outHandle.dy, b.inHandle.dx,
            b.inHandle.dy, b.x, b.y);
      }
      var metrics = seg.computeMetrics().toList();
      if (metrics.isEmpty || metrics.first.length == 0) continue;
      var m = metrics.first;
      var n = 1;
      if (curved || a.width != b.width) {
        var thinnest = base * math.max(0.05, math.min(a.width, b.width));
        n = (m.length / math.max(thinnest / 2, m.length / 200)).ceil();
        n = n.clamp(1, 200);
      }
      var steps = <(Offset, Offset, double)>[];
      for (var k = 0; k <= n; k++) {
        var t = k / n;
        var at = m.getTangentForOffset(m.length * t);
        if (at == null) continue;
        steps.add((at.position, at.vector, base * widthAt(i, t)));
      }
      if (steps.length < 2) continue;
      for (var k = 0; k + 1 < steps.length; k++) {
        var (p0, d0, w0) = steps[k];
        var (p1, d1, w1) = steps[k + 1];
        var s0 = normal(d0) * (w0 / 2), s1 = normal(d1) * (w1 / 2);
        piece([p0 + s0, p1 + s1, p1 - s1, p0 - s0]);
        if (curved && k > 0) disc(p0, w0 / 2);
      }
      segments.add(steps);
    }
    if (segments.isEmpty) continue;
    // Where one segment meets the next, the point's corner.
    var joints = run.closed ? segments.length : segments.length - 1;
    for (var i = 0; i < joints; i++) {
      var before = segments[i], after = segments[(i + 1) % segments.length];
      var node = nodes[(i + 1) % nodes.length];
      var (p, into, w) = before.last;
      corner(node.join ?? shape.join, p, into, after.first.$2, w);
    }
    if (!run.closed) {
      var (p0, d0, w0) = segments.first.first;
      end(nodes.first.cap ?? shape.cap, p0, -d0, w0);
      var (p1, d1, w1) = segments.last.last;
      end(nodes.last.cap ?? shape.cap, p1, d1, w1);
    }
  }
  return out;
}

/// VectorDrawn is one thing a drawing draws: a shape, or a run of shapes
/// combined -- see VectorCombine -- the first one's colours on the outline
/// they make together.
typedef VectorDrawn = ({
  VectorShape style,
  Path outline,
  bool combined,
  List<VectorShape> members
});

final Expando<(List<VectorShape>, Path)> _combined =
    Expando<(List<VectorShape>, Path)>();

/// vectorDrawn is what [shapes] draw, in order: each shape on its own, and
/// each run of combining shapes as the one outline they make. The outline
/// is worked out once for as long as none of the shapes in it changes.
List<VectorDrawn> vectorDrawn(List<VectorShape> shapes) {
  var out = <VectorDrawn>[];
  var i = 0;
  while (i < shapes.length) {
    var base = shapes[i];
    var j = i + 1;
    while (j < shapes.length && shapes[j].combine != null) {
      j++;
    }
    if (j == i + 1) {
      out.add((
        style: base,
        outline: vectorShapePath(base),
        combined: false,
        members: [base]
      ));
    } else {
      var members = shapes.sublist(i, j);
      var kept = _combined[base];
      Path outline;
      if (kept != null &&
          kept.$1.length == members.length &&
          [for (var k = 0; k < members.length; k++) k]
              .every((k) => identical(kept.$1[k], members[k]))) {
        outline = kept.$2;
      } else {
        outline = vectorShapePath(base);
        for (var m in members.skip(1)) {
          outline =
              Path.combine(m.combine!.operation, outline, vectorShapePath(m));
        }
        _combined[base] = (members, outline);
      }
      out.add(
          (style: base, outline: outline, combined: true, members: members));
    }
    i = j;
  }
  return out;
}

/// _strokeDrawn draws the line of [d] with [paint]: a shape's own, or one
/// stroke round a combined outline -- [extra] wider, for a tint's reach.
void _strokeDrawn(ui.Canvas canvas, VectorDrawn d, Paint paint,
    {double extra = 0}) {
  var shape = d.style;
  if (!d.combined && shape.ownLine) {
    var band = vectorLinePath(shape);
    canvas.drawPath(band, paint..style = PaintingStyle.fill);
    if (extra > 0) {
      canvas.drawPath(
          band,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = extra
            ..strokeJoin = StrokeJoin.round);
    }
    return;
  }
  canvas.drawPath(
      d.combined ? d.outline : vectorShapePath(shape),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = shape.strokeWidth + extra
        ..strokeCap = shape.cap
        ..strokeJoin = shape.join);
}

/// paintVector draws [e] fitted into [box].
void paintVector(
    ui.Canvas canvas, Rect box, VectorElement e, CanvasImageSource? images) {
  if (box.width <= 0 || box.height <= 0) return;
  var shapes = e.shapes;
  if (shapes == null) {
    // As the file draws itself, which is the only way to be exact about a
    // drawing nobody has taken apart yet.
    var drawn = images?.resolveVector(e.assetId);
    if (drawn == null) {
      _placeholder(canvas, box);
      return;
    }
    var p = e.placement(box, Offset.zero & drawn.size);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(p.sx, p.sy);
    canvas.drawPicture(drawn.picture);
    canvas.restore();
    return;
  }

  var p = e.placement(box, e.viewBox);
  canvas.save();
  canvas.translate(p.dx, p.dy);
  canvas.scale(p.sx, p.sy);
  // Tinted, the drawing is drawn into a layer of its own for the tint to be
  // laid on -- see _paintTints.
  for (var d in vectorDrawn(shapes)) {
    _paintGroup(canvas, d);
  }
  canvas.restore();
}

/// _paintGroup draws one shape -- with whatever is combined into it, its
/// tints and its rub-outs -- in the drawing's own units.
void _paintGroup(ui.Canvas canvas, VectorDrawn d) {
  var shape = d.style;
  // Tinted or rubbed out, a shape is drawn into a layer of its own for its
  // tints to be laid on and its rub-outs taken out of -- its own, so what
  // is drawn over it later is untouched by them. See _paintTints and
  // _paintErasures.
  var layered = shape.tints.isNotEmpty || shape.erasures.isNotEmpty;
  if (layered) canvas.saveLayer(null, Paint());
  // A fade runs across the shape's own box, as a shape element's does.
  Paint paintOf(Color c, GradientSpec? fade, Rect area) {
    var paint = Paint()
      ..color = c
      ..isAntiAlias = true;
    if (fade != null) {
      paint.shader = PaintSpec(c, gradient: fade).shaderFor(area);
    }
    return paint;
  }

  if (shape.fill case var fill? when fill.a > 0) {
    canvas.drawPath(
        d.outline, paintOf(fill, shape.fillFade, d.outline.getBounds()));
  }
  if (shape.stroke case var stroke?
      when stroke.a > 0 && shape.strokeWidth > 0) {
    _strokeDrawn(
        canvas,
        d,
        paintOf(stroke, shape.strokeFade,
            d.outline.getBounds().inflate(shape.strokeWidth / 2)));
  }
  if (layered) {
    if (shape.tints.isNotEmpty) _paintTints(canvas, d.members, shape.tints);
    if (shape.erasures.isNotEmpty) {
      _paintErasures(canvas, d.members, shape.erasures);
    }
    canvas.restore();
  }
}

/// naturalTimes is when each of [shapes]' groups comes in, in its own
/// frames, before the drawing's arrival is fitted round them all: the frame
/// it starts on, counted from the first, and how many it takes -- its own
/// length, or [span], the drawing's. With the one before, it starts as that
/// one starts; after it, as that one finishes; after a gap, that many frames
/// after -- or, a gap less than nought, that many before, overlapping it.
/// See VectorCue.
List<(double, double)> naturalTimes(List<VectorShape> shapes, int span) {
  var out = <(double, double)>[];
  for (var (i, d) in vectorDrawn(shapes).indexed) {
    var s = d.style;
    var length = math.max(1, s.cueLength ?? span).toDouble();
    var start = 0.0;
    if (i > 0) {
      var (before, took) = out[i - 1];
      start = switch (s.cue) {
        VectorCue.together => before,
        VectorCue.after => before + took,
        VectorCue.gap => math.max(before, before + took + s.cueGap),
      };
    }
    out.add((start, length));
  }
  return out;
}

/// naturalLength is how many of their own frames [shapes] take to come in,
/// first start to last finish.
double naturalLength(List<VectorShape> shapes, int span) {
  var times = naturalTimes(shapes, span);
  if (times.isEmpty) return span.toDouble();
  return times.map((t) => t.$1 + t.$2).reduce(math.max);
}

/// cueTimes is when each of [shapes]' groups comes in, in frames from where
/// the drawing's arrival starts, the whole of them fitted into the arrival's
/// [span]: the arrival covers every shape's, and stretching it stretches
/// them all alike. See naturalTimes.
List<(double, double)> cueTimes(List<VectorShape> shapes, int span) {
  var times = naturalTimes(shapes, span);
  var whole = naturalLength(shapes, span);
  var k = whole <= 0 ? 1.0 : span / whole;
  return [for (var (start, length) in times) (start * k, length * k)];
}

/// cueStarts is the frame each group starts on -- see cueTimes.
List<double> cueStarts(List<VectorShape> shapes, int span) =>
    [for (var (start, _) in cueTimes(shapes, span)) start];

/// sequenced is whether any of [shapes] comes in other than with the one
/// before -- whether the drawing comes in shape by shape rather than as one.
bool sequenced(List<VectorShape> shapes) {
  var groups = vectorDrawn(shapes);
  return groups.skip(1).any((d) => d.style.cue != VectorCue.together) ||
      groups.any((d) => d.style.cueLength != null);
}

/// vectorArrivalSpan is where [e]'s arrival starts on the timeline and how
/// many frames it takes -- the frames of its reveal keyframes -- or null
/// where it has none.
(int, int)? vectorArrivalSpan(VectorElement e) {
  int? from, to;
  for (var key in e.track?.keys ?? const <Keyframe>[]) {
    if (!key.values.containsKey(KeyframeChannel.reveal)) continue;
    from = from == null ? key.frame : math.min(from, key.frame);
    to = to == null ? key.frame : math.max(to, key.frame);
  }
  if (from == null || to == null || to <= from) return null;
  return (from, to - from);
}

/// paintVectorGroup draws [d], one of [e]'s groups, alone, fitted into
/// [box] as the whole drawing is: what a drawing coming in shape by shape
/// draws, one shape at a time. See VectorCue.
void paintVectorGroup(
    ui.Canvas canvas, Rect box, VectorElement e, VectorDrawn d) {
  var p = e.placement(box, e.viewBox);
  canvas.save();
  canvas.translate(p.dx, p.dy);
  canvas.scale(p.sx, p.sy);
  _paintGroup(canvas, d);
  canvas.restore();
}

/// vectorGroupBox is where [d], one of [e]'s groups, lies when the drawing
/// is fitted into [box]: the box it comes in in, shape by shape.
Rect vectorGroupBox(Rect box, VectorElement e, VectorDrawn d) {
  var p = e.placement(box, e.viewBox);
  var r = d.outline
      .getBounds()
      .inflate(d.style.stroke == null ? 0 : d.style.strokeWidth / 2);
  return Rect.fromLTRB(r.left * p.sx + p.dx, r.top * p.sy + p.dy,
      r.right * p.sx + p.dx, r.bottom * p.sy + p.dy);
}

/// _paintTints lays the tint brush's strokes over [shapes], each seen only
/// where the drawing is: on its lines, in its fills, or both.
///
/// The strokes are painted into a layer of their own and that layer is cut
/// down to the drawing's lines or fills afterwards, so a soft brush fades
/// into the drawing and an eraser takes tint off without touching the
/// drawing under it. Strokes in a row that show in the same places share
/// one cut.
///
/// The layer is laid on the drawing's own layer source-atop: it recolours
/// the drawing, keeping the drawing's own edges. Laid over it, a pixel the
/// drawing half covers was tinted by half and kept half the colour under
/// it -- a thin ring of the old colour round everything tinted.
void _paintTints(
    ui.Canvas canvas, List<VectorShape> shapes, List<VectorTint> tints) {
  // A pixel and a half, in the drawing's units: how far each part's cut
  // reaches past its edge, so the edge pixels are tinted whole. Source-atop
  // keeps the reach off anything the drawing does not cover.
  var m = canvas.getTransform();
  var pixel = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  var bleed = pixel > 0 ? 1.5 / pixel : 0.0;
  canvas.saveLayer(null, Paint()..blendMode = BlendMode.srcATop);
  var i = 0;
  while (i < tints.length) {
    var t = tints[i];
    if (t.erase) {
      _paintTintStroke(canvas, t, Paint()..blendMode = BlendMode.dstOut);
      i++;
      continue;
    }
    canvas.saveLayer(null, Paint());
    var j = i;
    while (j < tints.length &&
        !tints[j].erase &&
        tints[j].line == t.line &&
        tints[j].fill == t.fill) {
      _paintTintStroke(canvas, tints[j], Paint());
      j++;
    }
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstIn);
    _paintCoverage(canvas, shapes, line: t.line, fill: t.fill, bleed: bleed);
    canvas.restore();
    canvas.restore();
    i = j;
  }
  canvas.restore();
}

/// _paintErasures takes the eraser's rub-outs out of the drawing's layer:
/// whatever is under each, or -- for one that rubs out only lines, or only
/// fills -- that part of it, the rub-out cut down to where the drawing's
/// lines or fills show before it takes anything out. Rub-outs in a row that
/// take out the same parts share one cut.
void _paintErasures(
    ui.Canvas canvas, List<VectorShape> shapes, List<VectorTint> erasures) {
  var i = 0;
  while (i < erasures.length) {
    var t = erasures[i];
    var j = i;
    while (j < erasures.length &&
        erasures[j].line == t.line &&
        erasures[j].fill == t.fill) {
      j++;
    }
    var run = erasures.sublist(i, j);
    i = j;
    if (!t.line && !t.fill) continue;
    if (t.line && t.fill) {
      for (var r in run) {
        _paintTintStroke(canvas, r, Paint()..blendMode = BlendMode.dstOut);
      }
      continue;
    }
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstOut);
    for (var r in run) {
      _paintTintStroke(canvas, r, Paint());
    }
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstIn);
    _paintCoverage(canvas, shapes, line: t.line, fill: t.fill);
    canvas.restore();
    canvas.restore();
  }
}

/// _paintTintStroke draws one stroke of the brush with [paint]: its colour,
/// or its gradient laid across the stroke.
void _paintTintStroke(ui.Canvas canvas, VectorTint t, Paint paint) {
  var width = math.max(t.width, 1e-3);
  var soft = t.soft.clamp(0.0, 1.0);
  paint.isAntiAlias = true;
  if (t.erase) {
    paint.color = const Color(0xFF000000);
  } else {
    var area = Rect.fromPoints(t.points.first, t.points.first);
    for (var p in t.points) {
      area = area.expandToInclude(Rect.fromPoints(p, p));
    }
    t.paint.into(paint, area.inflate(t.width / 2));
  }
  if (soft > 0) {
    // The fade is the blur; the hard middle shrinks to leave room for it, so
    // the brush covers about as much soft as hard.
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, width * soft / 4);
    width *= 1 - soft / 2;
  }
  var first = t.points.first;
  if (t.points.length == 1) {
    canvas.drawCircle(first, width / 2, paint);
    return;
  }
  var path = Path()..moveTo(first.dx, first.dy);
  for (var p in t.points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
}

/// _paintCoverage draws where the drawing shows, solid: its fills, its
/// lines, or both -- what a tint is cut down to.
///
/// Built in the order the drawing is drawn, so it is what is seen: a line
/// over a fill hides that much of the fill, and a shape over another hides
/// it. What is not to be tinted is drawn as a cut, taking out whatever it
/// covers.
void _paintCoverage(ui.Canvas canvas, List<VectorShape> shapes,
    {required bool line, required bool fill, double bleed = 0}) {
  Paint mark(bool keep) => Paint()
    ..color = const Color(0xFF000000)
    ..blendMode = keep ? BlendMode.srcOver : BlendMode.dstOut
    ..isAntiAlias = true;
  // First each kept part reaching [bleed] past its edges, so its edge
  // pixels are covered whole; then the parts in order over that, kept or
  // cut, so the reach survives only off the drawing's edge -- where
  // source-atop keeps it to the pixels the drawing half covers -- and never
  // onto a part that is not being tinted.
  var drawn = vectorDrawn(shapes);
  if (bleed > 0) {
    for (var d in drawn) {
      var shape = d.style;
      if (fill && (shape.fill?.a ?? 0) > 0) {
        canvas.drawPath(
            d.outline,
            mark(true)
              ..style = PaintingStyle.stroke
              ..strokeWidth = bleed * 2
              ..strokeJoin = StrokeJoin.round);
      }
      if (line && (shape.stroke?.a ?? 0) > 0 && shape.strokeWidth > 0) {
        _strokeDrawn(canvas, d, mark(true), extra: bleed * 2);
      }
    }
  }
  for (var d in drawn) {
    var shape = d.style;
    if ((shape.fill?.a ?? 0) > 0) canvas.drawPath(d.outline, mark(fill));
    if ((shape.stroke?.a ?? 0) > 0 && shape.strokeWidth > 0) {
      _strokeDrawn(canvas, d, mark(line));
    }
  }
}

/// _placeholder is a Vector element with nothing in it yet: a dashed box
/// with a pen in it, so it can be found, picked and given a drawing.
void _placeholder(ui.Canvas canvas, Rect box) {
  var ink = Paint()
    ..color = const Color(0x99888888)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  var r = RRect.fromRectAndRadius(box.deflate(1), const Radius.circular(6));
  canvas.drawRRect(r, Paint()..color = const Color(0x22888888));
  // Dashed by hand: a path drawn in short pieces round the box.
  var metric = (Path()..addRRect(r)).computeMetrics();
  for (var m in metric) {
    for (var d = 0.0; d < m.length; d += 10) {
      canvas.drawPath(m.extractPath(d, d + 5), ink);
    }
  }
  // A curve and its two handles: what a drawing is made of.
  var c = box.center;
  var s = box.shortestSide * 0.18;
  var curve = Path()
    ..moveTo(c.dx - s, c.dy + s * 0.4)
    ..cubicTo(c.dx - s * 0.4, c.dy - s * 1.2, c.dx + s * 0.4, c.dy + s * 1.2,
        c.dx + s, c.dy - s * 0.4);
  canvas.drawPath(curve, ink..strokeWidth = 2);
  var dot = Paint()..color = const Color(0xCC888888);
  canvas.drawCircle(Offset(c.dx - s, c.dy + s * 0.4), 3, dot);
  canvas.drawCircle(Offset(c.dx + s, c.dy - s * 0.4), 3, dot);
}

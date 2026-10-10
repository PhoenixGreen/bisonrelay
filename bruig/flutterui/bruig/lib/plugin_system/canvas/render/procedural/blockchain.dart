import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/noise.dart';
import 'package:flutter/painting.dart';

// blockchain.dart draws the Blockchain style, in five ways: a chain of
// blocks, a network of nodes, a ledger of lines, a Merkle tree, and a field
// of blocks seen from above.
//
// Like every generator, a pure function of the frame, the spec and the time.
// Every block, node and line is known by a number -- its place in the chain,
// its cell, its row -- and everything about it comes from hashing that
// number, so a block keeps its hash as it scrolls across the frame and the
// same frame is the same picture on every machine.
//
// Main is the structure -- blocks, links, nodes, text -- and Accent is what
// is happening: the newest block, a confirmation, a transaction in flight.

/// paintBlockchain draws [spec] into [rect] at time [t].
void paintBlockchain(
    ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  switch (spec.choice("mode")) {
    case BlockchainMode.network:
      _network(canvas, rect, spec, t);
    case BlockchainMode.ledger:
      _ledger(canvas, rect, spec, t);
    case BlockchainMode.merkle:
      _merkle(canvas, rect, spec, t);
    case BlockchainMode.field:
      _field(canvas, rect, spec, t);
    default:
      _chain(canvas, rect, spec, t);
  }
}

Color _a(Color c, double a) => c.withValues(alpha: (c.a * a).clamp(0.0, 1.0));

double _frac(double v) => v - v.floorToDouble();

/// _mixed is a hash that keeps nearby inputs apart in every argument.
///
/// The shared [hash] adds its inputs before mixing them, so two columns a
/// fixed seed apart picked out the same rows: every column of a ledger lit
/// up at the same height. Each input is mixed in on its own here.
double _mixed(int a, int b, int c) {
  var h = a * 0x9E3779B1;
  h = (h ^ (h >> 15)) + b * 0x85EBCA77;
  h = (h ^ (h >> 13)) * 0x2C1B3C6D;
  h = (h ^ (h >> 12)) + c * 0xC2B2AE3D;
  h = (h ^ (h >> 15)) * 0x297A2D39;
  h ^= h >> 15;
  return (h & 0x7FFFFFFF) / 0x7FFFFFFF;
}

/// _hex is [n] hex digits that belong to the thing numbered [a], [b].
String _hex(int seed, int a, int b, int n) {
  const digits = "0123456789abcdef";
  var out = StringBuffer();
  for (var i = 0; i < n; i++) {
    out.write(digits[(hash(seed + i * 31, a, b) * 16).floor().clamp(0, 15)]);
  }
  return out.toString();
}

/// _withCommas is [n] written the way a block height is.
String _withCommas(int n) {
  var s = n.abs().toString();
  var out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(",");
    out.write(s[i]);
  }
  return out.toString();
}

final Map<String, TextPainter> _texts = {};

/// _text draws [s] in a monospaced face, its left edge at [at] -- or, with
/// [centred], its middle -- and its middle on the line.
///
/// Kept once made, as the glyphs of the rain are: a ledger scrolling is the
/// same few hundred lines drawn again a little higher every frame.
double _text(ui.Canvas canvas, String s, Offset at, double size, Color color,
    {bool centred = false}) {
  if (size < 3 || color.a <= 0.01) return 0;
  var bucket = (color.a * 20).round();
  var key = "$s|${size.toStringAsFixed(1)}|${color.toARGB32() & 0xFFFFFF}"
      "|$bucket";
  var p = _texts[key];
  if (p == null) {
    if (_texts.length > 3000) _texts.clear();
    p = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: "RobotoMono",
            fontSize: size,
            height: 1,
            color: color.withValues(alpha: bucket / 20),
          )),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _texts[key] = p;
  }
  p.paint(canvas,
      Offset(centred ? at.dx - p.width / 2 : at.dx, at.dy - p.height / 2));
  return p.width;
}

// --------------------------------------------------------------------------
// Blocks and the links between them
// --------------------------------------------------------------------------

/// _Block is how one block is drawn: its colours, and how far it stands
/// out.
class _BlockLook {
  final int shape;
  final double depth;
  final Color line;
  final Color fill;
  final double stroke;
  const _BlockLook(this.shape, this.depth, this.line, this.fill, this.stroke);
}

/// _block draws one block, its front face [face], and returns that face.
void _block(ui.Canvas canvas, Rect face, _BlockLook look) {
  var stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = look.stroke
    ..strokeJoin = StrokeJoin.round
    ..color = look.line;
  var fill = Paint()..color = look.fill;
  switch (look.shape) {
    case 1:
      canvas.drawRect(face, fill);
      canvas.drawRect(face, stroke);
    case 2:
      var r = RRect.fromRectAndRadius(face, Radius.circular(face.width * 0.18));
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, stroke);
    default:
      // A cube seen from a little above and to the right: the front, then
      // the top and the side going back from it, lit from above.
      var d = Offset(look.depth * 0.8, -look.depth * 0.6);
      var top = Path()
        ..moveTo(face.left, face.top)
        ..lineTo(face.right, face.top)
        ..relativeLineTo(d.dx, d.dy)
        ..lineTo(face.left + d.dx, face.top + d.dy)
        ..close();
      var side = Path()
        ..moveTo(face.right, face.top)
        ..relativeLineTo(d.dx, d.dy)
        ..lineTo(face.right + d.dx, face.bottom + d.dy)
        ..lineTo(face.right, face.bottom)
        ..close();
      var a = look.fill.a;
      canvas.drawPath(
          top, Paint()..color = look.fill.withValues(alpha: a * 1.8));
      canvas.drawPath(
          side, Paint()..color = look.fill.withValues(alpha: a * 0.55));
      canvas.drawRect(face, fill);
      canvas.drawPath(top, stroke);
      canvas.drawPath(side, stroke);
      canvas.drawRect(face, stroke);
  }
}

/// _blockText is a block's height, its hash and its transactions, inside
/// [face] -- or, where the block is too small to read, the transactions
/// alone, as bars.
void _blockText(
    ui.Canvas canvas, Rect face, int seed, int id, Color color, bool words) {
  var b = face.width;
  var pad = b * 0.12;
  if (words && b >= 34) {
    _text(canvas, "#${_withCommas(810000 + id)}",
        Offset(face.left + pad, face.top + pad + b * 0.07), b * 0.115, color);
    _text(
        canvas,
        "${_hex(seed, id, 1, 4)}…${_hex(seed, id, 2, 4)}",
        Offset(face.left + pad, face.top + pad + b * 0.25),
        b * 0.1,
        _a(color, 0.75));
  }
  // The transactions, as lines of differing length.
  var rows = words && b >= 34 ? 3 : 4;
  var top = words && b >= 34 ? face.top + b * 0.55 : face.top + pad;
  var step = (face.bottom - pad - top) / rows;
  var bar = Paint()..color = _a(color, 0.45);
  for (var i = 0; i < rows; i++) {
    var len = (b - pad * 2) * (0.35 + hash(seed + 5, id, i) * 0.65);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(face.left + pad, top + i * step + step * 0.3, len,
                math.max(1.0, step * 0.32)),
            Radius.circular(step * 0.16)),
        bar);
  }
}

/// _link joins two blocks: from [a] to [b], drawn as [style] says.
void _link(
    ui.Canvas canvas, Offset a, Offset b, int style, double size, Color color) {
  var len = (b - a).distance;
  if (len < 2) return;
  var dir = (b - a) / len;
  var normal = Offset(-dir.dy, dir.dx);
  var w = math.max(1.0, size * 0.025);
  var paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = color;
  switch (style) {
    case 1:
      var o = normal * size * 0.06;
      canvas.drawLine(a + o, b + o, paint);
      canvas.drawLine(a - o, b - o, paint);
    case 2:
      // Interlocking links, alternately face on and edge on.
      var linkLen = size * 0.3;
      var n = math.max(1, (len / (linkLen * 0.7)).round());
      var step = len / n;
      canvas.save();
      canvas.translate(a.dx, a.dy);
      canvas.rotate(math.atan2(dir.dy, dir.dx));
      for (var i = 0; i < n; i++) {
        var c = Offset(step * (i + 0.5), 0);
        var tall = i.isEven ? size * 0.16 : size * 0.05;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: step * 1.3, height: tall),
                Radius.circular(tall / 2)),
            paint..strokeWidth = w * (i.isEven ? 1.2 : 1.6));
      }
      canvas.restore();
    case 3:
      var dash = size * 0.08;
      for (var d = 0.0; d < len; d += dash * 2) {
        canvas.drawLine(a + dir * d, a + dir * math.min(len, d + dash), paint);
      }
    case 4:
      // A hash pointer: each block points back at the one before it.
      canvas.drawLine(a, b, paint);
      var head = size * 0.09;
      canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo((a + dir * head + normal * head * 0.6).dx,
                (a + dir * head + normal * head * 0.6).dy)
            ..lineTo((a + dir * head - normal * head * 0.6).dx,
                (a + dir * head - normal * head * 0.6).dy)
            ..close(),
          Paint()..color = color);
    default:
      canvas.drawLine(a, b, paint);
  }
}

/// _pulse is a transaction in flight: a bright point with a soft halo.
void _pulse(ui.Canvas canvas, Offset at, double r, Color color) {
  canvas.drawCircle(
      at,
      r * 4,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader =
            ui.Gradient.radial(at, r * 4, [_a(color, 0.45), _a(color, 0)]));
  canvas.drawCircle(at, r, Paint()..color = color);
}

// --------------------------------------------------------------------------
// Chain
// --------------------------------------------------------------------------

/// _chain is rows of blocks, each linked to the one before it, the newest
/// arriving from the right and the chain moving off to the left.
void _chain(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var short = math.min(rect.width, rect.height);
  var b = math.max(10.0, short * spec.scale * 2.4);
  var pitch = b + b * spec.p("blockGap");
  var rows = spec.p("rows").round().clamp(1, 8);
  var shape = spec.choice("blockShape");
  var depth = shape == 0 ? spec.p("blockDepth") * b * 0.6 : 0.0;
  var linkStyle = spec.choice("link");
  var words = spec.on("hashText");
  var band = rect.height / rows;
  var fg = spec.foreground, ac = spec.accent;
  var bright = spec.intensity;

  for (var r = 0; r < rows; r++) {
    var seed = spec.seed * 97 + r * 7919;
    var y = rect.top +
        band * (r + 0.5) +
        (hash(seed, 1, 1) - 0.5) * band * 0.4 * spec.variation +
        depth * 0.3;
    // Each chain at its own pace, so the rows do not march in step.
    var speed = 0.25 + hash(seed, 2, 2) * 0.35 * (0.3 + spec.variation);
    var along = t * speed + hash(seed, 3, 3) * 50;
    var first = (along - 1).floor();
    var count = (rect.width / pitch).ceil() + 3;

    // A confirmation running back down the chain from the newest block.
    var wave = 1.15 - _frac(t * 0.22 + hash(seed, 4, 4)) * 1.5;

    for (var k = first; k < first + count; k++) {
      var x = rect.left + (k - along) * pitch;
      var face = Rect.fromLTWH(x, y - b / 2, b, b);
      var next = Offset(x + pitch, y);

      var lit = hash(seed, k, 5) < spec.density * 0.35;
      var where = (x + b / 2 - rect.left) / rect.width;
      var conf = spec.animated && spec.on("ripple")
          ? math.exp(-math.pow((where - wave) / 0.07, 2))
          : 0.0;
      var line = Color.lerp(_a(fg, bright * 0.85), _a(ac, bright), conf)!;

      if (pitch - b > 1) {
        _link(canvas, Offset(x + b, y), next, linkStyle, b,
            _a(lit ? ac : fg, bright * 0.6));
        if (spec.p("pulses") > 0 && hash(seed, k, 6) < spec.p("pulses")) {
          var f = _frac(t * 0.8 + hash(seed, k, 7));
          _pulse(canvas, Offset(x + b + (pitch - b) * f, y),
              math.max(1.2, b * 0.035), _a(ac, bright));
        }
      }
      _block(
          canvas,
          face,
          _BlockLook(
            shape,
            depth,
            lit ? _a(ac, bright) : line,
            lit ? _a(ac, 0.22 * bright) : _a(fg, (0.09 + conf * 0.2) * bright),
            math.max(1.0, b * 0.022),
          ));
      _blockText(canvas, face.deflate(1), seed, k, lit ? ac : line, words);
    }
  }
}

// --------------------------------------------------------------------------
// Network
// --------------------------------------------------------------------------

/// _network is nodes joined to their neighbours, with transactions moving
/// along the links between them.
void _network(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var short = math.min(rect.width, rect.height);
  var long = math.max(rect.width, rect.height);
  // One node to a cell of a grid, shaken out of line: spread evenly enough
  // to fill the frame, and loosely enough not to look like a grid.
  var cell = short * (0.26 - spec.density * 0.19);
  var cols = (rect.width / cell).ceil() + 2;
  var rows = (rect.height / cell).ceil() + 2;
  var shake = cell * (0.25 + spec.variation * 0.45);
  var nodes = <Offset>[];
  var ids = <int>[];
  for (var j = -1; j < rows - 1; j++) {
    for (var i = -1; i < cols - 1; i++) {
      var h = hash(spec.seed, i, j);
      var p = Offset(
        rect.left +
            (i + 0.5) * cell +
            (hash(spec.seed + 1, i, j) - 0.5) * shake * 2,
        rect.top +
            (j + 0.5) * cell +
            (hash(spec.seed + 2, i, j) - 0.5) * shake * 2,
      );
      // A slow drift, each node on its own.
      p += Offset(math.sin(t * 0.35 + h * 40), math.cos(t * 0.3 + h * 70)) *
          cell *
          0.06;
      nodes.add(p);
      ids.add(i * 4099 + j);
    }
  }

  var reach = long * spec.p("linkReach");
  var size = math.max(2.0, short * spec.scale * 0.32);
  var fg = spec.foreground, ac = spec.accent;
  var bright = spec.intensity;
  var pulses = spec.p("pulses");

  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.7, size * 0.18);
  // Each node to its nearest few within reach -- a mesh rather than a
  // tangle, which is what joining everything within reach gives.
  var drawn = <int>{};
  for (var a = 0; a < nodes.length; a++) {
    var near = <(double, int)>[];
    for (var b = 0; b < nodes.length; b++) {
      if (a == b) continue;
      var d = (nodes[a] - nodes[b]).distance;
      if (d < reach) near.add((d, b));
    }
    near.sort((x, y) => x.$1.compareTo(y.$1));
    for (var (d, b) in near.take(3 + (spec.variation * 2).round())) {
      var key = a < b ? a * 100000 + b : b * 100000 + a;
      if (!drawn.add(key)) continue;
      var fade = math.pow(1 - d / reach, 0.6).toDouble();
      line.color = _a(fg, bright * 0.55 * fade);
      canvas.drawLine(nodes[a], nodes[b], line);
      var h = hash(spec.seed + 9, ids[a], ids[b]);
      if (h < pulses * 0.7) {
        var f = _frac(t * (0.25 + h) + h * 13);
        var from = h < pulses * 0.35 ? nodes[a] : nodes[b];
        var to = from == nodes[a] ? nodes[b] : nodes[a];
        _pulse(canvas, Offset.lerp(from, to, f)!, math.max(1.2, size * 0.45),
            _a(ac, bright * fade));
      }
    }
  }

  var shape = spec.choice("nodeShape");
  var hubs = spec.p("hubs");
  for (var n = 0; n < nodes.length; n++) {
    var hub = hash(spec.seed + 3, ids[n], 0) < hubs;
    var r = size * (hub ? 2.4 : 0.8 + hash(spec.seed + 4, ids[n], 0) * 0.6);
    var colour = hub ? ac : fg;
    var p = nodes[n];
    var fill = Paint()..color = _a(colour, bright * (hub ? 0.35 : 0.9));
    var edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.22)
      ..color = _a(colour, bright);
    switch (shape) {
      case 1:
        var path = Path();
        for (var k = 0; k < 6; k++) {
          var a = math.pi / 3 * k + math.pi / 6;
          var q = p + Offset(math.cos(a), math.sin(a)) * r * 1.3;
          k == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        path.close();
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
      case 2:
        _block(
            canvas,
            Rect.fromCenter(center: p, width: r * 2, height: r * 2),
            _BlockLook(0, r * 0.9, _a(colour, bright),
                _a(colour, 0.25 * bright), math.max(0.7, r * 0.12)));
      case 3:
        canvas.drawCircle(p, r * 1.2, edge);
        canvas.drawCircle(p, r * 0.35, fill..color = _a(colour, bright));
      default:
        canvas.drawCircle(p, r, fill);
        if (hub) canvas.drawCircle(p, r, edge);
    }
    // A hub is a busy node: a ring going out from it when it moves.
    if (hub && spec.animated) {
      var f = _frac(t * 0.5 + hash(spec.seed + 5, ids[n], 0));
      canvas.drawCircle(
          p,
          r * (1.2 + f * 2.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.7, r * 0.12)
            ..color = _a(ac, bright * (1 - f) * 0.7));
    }
  }
}

// --------------------------------------------------------------------------
// Ledger
// --------------------------------------------------------------------------

/// _ledger is columns of records scrolling up, the newest arriving at the
/// bottom and still resolving.
void _ledger(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var short = math.min(rect.width, rect.height);
  var size = math.max(5.0, short * spec.scale * 0.6);
  var lineH = size * 1.75;
  var cols = spec.p("columns").round().clamp(1, 6);
  var colW = rect.width / cols;
  var margin = size * 1.2;
  var chars = math.max(4, ((colW - margin * 2) / (size * 0.6)).floor());
  var kind = spec.choice("ledgerKind");
  var fg = spec.foreground, ac = spec.accent;
  var bright = spec.intensity;
  var present = 0.35 + spec.density * 0.65;

  var scroll = t * lineH * 1.1;
  var first = (scroll / lineH).floor();
  var shift = scroll - first * lineH;
  var rows = (rect.height / lineH).ceil() + 2;
  var tick = (t * 10).floor();

  for (var c = 0; c < cols; c++) {
    var seed = spec.seed * 31 + c * 977;
    // Each column a little out of step with the next.
    var lag = (hash(seed, 0, 0) * lineH * spec.variation);
    for (var i = 0; i < rows; i++) {
      var id = first + i;
      if (_mixed(seed, id, 1) > present) continue;
      var y = rect.top + i * lineH - shift + lag + lineH / 2;
      if (y < rect.top - lineH || y > rect.bottom + lineH) continue;
      var x = rect.left + c * colW + margin;

      String s;
      // Each line laid out to the width of its column, so the columns read
      // as columns rather than as ragged text.
      var row = id * 7 + 3;
      switch (kind) {
        case 0:
          s = _hex(seed, row, 2, chars);
        case 2:
          var tx = "${1 + (hash(seed, row, 3) * 240).floor()} tx".padLeft(7);
          var height = "#${_withCommas(810000 + id + c * 100000)}";
          var room = math.max(4, chars - height.length - tx.length - 4);
          s = "$height  ${"0" * math.min(6, room ~/ 3)}"
              "${_hex(seed, row, 4, room - math.min(6, room ~/ 3))}  $tx";
        default:
          var amount = (hash(seed, row, 5) * hash(seed, row, 6) * 400)
              .toStringAsFixed(2)
              .padLeft(7);
          var each = math.max(4, (chars - amount.length - 5) ~/ 2);
          s = "${_hex(seed, row, 7, each)} \u00bb ${_hex(seed, row, 9, each)}"
              "  $amount";
      }
      if (s.length > chars) s = s.substring(0, chars);

      // The newest lines are still being worked out: some of their
      // characters change from one moment to the next.
      var fromBottom = (rect.bottom - y) / lineH;
      if (spec.animated && fromBottom < 2.5) {
        var b = StringBuffer();
        for (var k = 0; k < s.length; k++) {
          var ch = s[k];
          if (ch != " " && hash(seed + tick, id, k) < 0.4) {
            ch = "0123456789abcdef"[
                (hash(seed + tick + 1, id, k) * 16).floor() % 16];
          }
          b.write(ch);
        }
        s = b.toString();
      }

      var hot = _mixed(seed, id, 11) < spec.p("highlight");
      var shade = 0.35 + _mixed(seed, id, 12) * 0.65;
      if (hot) {
        canvas.drawRect(
            Rect.fromLTWH(
                x - size * 0.4,
                y - lineH * 0.42,
                math.min(
                    colW - margin * 1.2, s.length * size * 0.6 + size * 0.8),
                lineH * 0.84),
            Paint()..color = _a(ac, 0.14 * bright));
      }
      _text(canvas, s, Offset(x, y), size,
          hot ? _a(ac, bright) : _a(fg, bright * shade));
    }
  }
}

// --------------------------------------------------------------------------
// Merkle tree
// --------------------------------------------------------------------------

/// _merkle is a tree of hashes: the transactions along the bottom, each
/// pair hashed into the one above, up to the root -- and one leaf's proof,
/// the path from it to the root, lit.
void _merkle(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var levels = spec.p("levels").round().clamp(2, 7);
  var leaves = 1 << (levels - 1);
  var up = spec.choice("treeDir") == 1;
  var margin = rect.height * 0.12;
  var gapY = (rect.height - margin * 2) / (levels - 1);
  var width = rect.width * 0.92;
  var left = rect.left + (rect.width - width) / 2;
  var leafW = width / leaves;
  var b = math.min(math.min(leafW * 0.66, gapY * 0.55),
      math.max(10.0, math.min(rect.width, rect.height) * spec.scale * 2.4));
  var shape = spec.choice("blockShape");
  var depth = shape == 0 ? spec.p("blockDepth") * b * 0.5 : 0.0;
  var linkStyle = spec.choice("link");
  var words = spec.on("hashText");
  var fg = spec.foreground, ac = spec.accent;
  var bright = spec.intensity;

  Offset at(int level, int i) {
    var x = left + (i + 0.5) * width / (1 << level);
    var y = rect.top + margin + level * gapY;
    return Offset(x, up ? rect.bottom - (y - rect.top) : y);
  }

  // Which leaf is being proved, changing every couple of seconds.
  var proving = (hash(spec.seed, (t * 0.45).floor(), 9) * leaves).floor();
  bool onPath(int level, int i) => i == proving >> (levels - 1 - level);

  // The links first, so the blocks sit over their ends.
  for (var level = 0; level < levels - 1; level++) {
    for (var i = 0; i < (1 << level); i++) {
      var p = at(level, i);
      for (var c in [i * 2, i * 2 + 1]) {
        var q = at(level + 1, c);
        var lit = onPath(level + 1, c);
        var colour = _a(lit ? ac : fg, bright * (lit ? 0.95 : 0.5));
        // Down from the parent, across, and down into the child.
        var dy = up ? -1 : 1;
        var from = p + Offset(0, dy * b / 2);
        var mid = (from.dy + q.dy - dy * b / 2) / 2;
        var to = q - Offset(0, dy * b / 2);
        _link(canvas, from, Offset(from.dx, mid),
            linkStyle == 2 ? 0 : linkStyle, b, colour);
        _link(canvas, Offset(from.dx, mid), Offset(to.dx, mid),
            linkStyle == 2 ? 0 : linkStyle, b, colour);
        _link(canvas, Offset(to.dx, mid), to, linkStyle, b, colour);
        if (lit && spec.p("pulses") > 0) {
          // The proof climbing towards the root.
          var f = _frac(t * 0.9 - level * 0.18);
          var path = [to, Offset(to.dx, mid), Offset(from.dx, mid), from];
          var seg = (f * 3).floor().clamp(0, 2);
          _pulse(canvas, Offset.lerp(path[seg], path[seg + 1], f * 3 - seg)!,
              math.max(1.2, b * 0.05), _a(ac, bright));
        }
      }
    }
  }

  for (var level = 0; level < levels; level++) {
    for (var i = 0; i < (1 << level); i++) {
      var c = at(level, i);
      var lit = onPath(level, i);
      var face = Rect.fromCenter(center: c, width: b, height: b * 0.62);
      _block(
          canvas,
          face,
          _BlockLook(
              shape,
              depth,
              _a(lit ? ac : fg, bright * (lit ? 1 : 0.8)),
              _a(lit ? ac : fg, bright * (lit ? 0.25 : 0.1)),
              math.max(1.0, b * 0.025)));
      if (words && b > 22) {
        var label = level == 0 ? "root" : _hex(spec.seed, level, i, 4);
        _text(canvas, label, c, b * 0.2,
            _a(lit ? ac : fg, bright * (lit ? 1 : 0.85)),
            centred: true);
      }
    }
  }
}

// --------------------------------------------------------------------------
// Block field
// --------------------------------------------------------------------------

/// _field is ground covered in blocks, seen from above at an angle, each
/// stack its own height -- a city of blocks.
void _field(ui.Canvas canvas, Rect rect, ProceduralSpec spec, double t) {
  var short = math.min(rect.width, rect.height);
  var e = math.max(6.0, short * spec.scale * 1.5);
  var halfW = e * math.sqrt(3) / 2, halfH = e / 2;
  var noise = ValueNoise(spec.seed);
  var rise = spec.p("fieldHeight") * e * 3;
  var fg = spec.foreground, ac = spec.accent;
  var bright = spec.intensity;
  var present = 0.3 + spec.density * 0.7;
  var stroke = math.max(0.6, e * 0.03);

  // The ground's grid seen corner on: [s] counts rows going back into the
  // picture and [d] places across it. Back to front, so that nearer stacks
  // are drawn over the ones behind them.
  var across = (rect.width / halfW / 2).ceil() + 2;
  var rows = ((rect.height + rise) / halfH).ceil() + 4;
  var origin = Offset(rect.center.dx, rect.top - halfH * 2);
  for (var s = 0; s < rows; s++) {
    for (var d = -across * 2; d <= across * 2; d++) {
      if ((s + d).isOdd) continue;
      var gi = (s + d) ~/ 2, gj = (s - d) ~/ 2;
      var x = origin.dx + d * halfW;
      var y = origin.dy + s * halfH;
      if (x < rect.left - halfW * 2 || x > rect.right + halfW * 2) continue;
      if (hash(spec.seed + 1, gi, gj) > present) continue;

      var f = noise.fbm(gi * 0.12 + t * 0.05, gj * 0.12 + t * 0.03, octaves: 3);
      // Stepped rather than smooth, which is what makes them blocks.
      var z = (f * rise / (e * 0.5)).round() * e * 0.5;
      var top = Offset(x, y - z);

      var lit = hash(
              spec.seed + 2, gi, gj + (spec.animated ? (t * 0.7).floor() : 0)) <
          spec.p("highlight") * 0.6;
      var colour = lit ? ac : fg;
      var shade = 0.6 + f * 0.6;

      var topFace = Path()
        ..moveTo(top.dx, top.dy - halfH)
        ..lineTo(top.dx + halfW, top.dy)
        ..lineTo(top.dx, top.dy + halfH)
        ..lineTo(top.dx - halfW, top.dy)
        ..close();
      var h = z + e * 0.6;
      var leftFace = Path()
        ..moveTo(top.dx - halfW, top.dy)
        ..lineTo(top.dx, top.dy + halfH)
        ..lineTo(top.dx, top.dy + halfH + h)
        ..lineTo(top.dx - halfW, top.dy + h)
        ..close();
      var rightFace = Path()
        ..moveTo(top.dx + halfW, top.dy)
        ..lineTo(top.dx, top.dy + halfH)
        ..lineTo(top.dx, top.dy + halfH + h)
        ..lineTo(top.dx + halfW, top.dy + h)
        ..close();
      canvas.drawPath(
          leftFace,
          Paint()
            ..color = Color.lerp(spec.background, colour,
                (0.22 * shade * bright).clamp(0.0, 1.0))!);
      canvas.drawPath(
          rightFace,
          Paint()
            ..color = Color.lerp(spec.background, colour,
                (0.12 * shade * bright).clamp(0.0, 1.0))!);
      canvas.drawPath(
          topFace,
          Paint()
            ..color = Color.lerp(spec.background, colour,
                ((lit ? 0.75 : 0.35) * shade * bright).clamp(0.0, 1.0))!);
      var edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round
        ..color = _a(colour, bright * (lit ? 0.9 : 0.4));
      canvas.drawPath(topFace, edge);
      canvas.drawLine(Offset(top.dx, top.dy + halfH),
          Offset(top.dx, top.dy + halfH + h), edge);
    }
  }
}

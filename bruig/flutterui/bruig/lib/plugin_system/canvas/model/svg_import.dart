import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';

// svg_import.dart takes an .svg apart into the shapes a Vector element edits:
// runs of points with handles, each with a fill and a stroke.
//
// Its own reader rather than a package, and deliberately small. What it keeps
// is what a drawing is made of -- paths and the basic shapes, groups and
// transforms, fills and strokes, classes in a stylesheet. What it cannot keep
// it says so about, in [SvgImport.dropped], so the reader is told before the
// drawing is changed: a gradient becomes the colour it starts with, and words,
// pictures, filters and masks are left out.

/// SvgImport is a drawing taken apart.
class SvgImport {
  final Rect viewBox;
  final List<VectorShape> shapes;

  /// dropped is what could not be kept, said the way the reader is told:
  /// "gradients (made solid)", "text".
  final Set<String> dropped;

  const SvgImport(this.viewBox, this.shapes, this.dropped);
}

/// importSvg takes [source] apart, or returns null where it is not a drawing
/// that can be read at all.
SvgImport? importSvg(String source) {
  var root = _Xml.parse(source);
  if (root == null) return null;
  var svg = root.name == "svg" ? root : root.find("svg");
  if (svg == null) return null;
  return _Importer(svg).run();
}

// ---------------------------------------------------------------------------
// A small XML reader: elements, attributes and text, enough for a drawing.
// ---------------------------------------------------------------------------

class _Node {
  final String name;
  final Map<String, String> attrs;
  final List<_Node> children = [];
  final StringBuffer text = StringBuffer();
  _Node(this.name, this.attrs);

  _Node? find(String tag) {
    for (var c in children) {
      if (c.name == tag) return c;
      var deeper = c.find(tag);
      if (deeper != null) return deeper;
    }
    return null;
  }

  void each(void Function(_Node) visit) {
    visit(this);
    for (var c in children) {
      c.each(visit);
    }
  }
}

class _Xml {
  static final _attr = RegExp(r'''([^\s=/>]+)\s*=\s*("([^"]*)"|'([^']*)')''');

  static _Node? parse(String s) {
    var top = _Node("#document", const {});
    var stack = [top];
    var i = 0;
    while (i < s.length) {
      var lt = s.indexOf("<", i);
      if (lt < 0) break;
      if (lt > i) stack.last.text.write(s.substring(i, lt));
      if (s.startsWith("<!--", lt)) {
        var end = s.indexOf("-->", lt);
        i = end < 0 ? s.length : end + 3;
        continue;
      }
      if (s.startsWith("<![CDATA[", lt)) {
        var end = s.indexOf("]]>", lt);
        stack.last.text.write(s.substring(lt + 9, end < 0 ? s.length : end));
        i = end < 0 ? s.length : end + 3;
        continue;
      }
      if (s.startsWith("<?", lt) || s.startsWith("<!", lt)) {
        var end = s.indexOf(">", lt);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      var gt = _tagEnd(s, lt);
      if (gt < 0) break;
      var tag = s.substring(lt + 1, gt);
      i = gt + 1;
      if (tag.startsWith("/")) {
        if (stack.length > 1) stack.removeLast();
        continue;
      }
      var selfClosing = tag.endsWith("/");
      if (selfClosing) tag = tag.substring(0, tag.length - 1);
      var space = tag.indexOf(RegExp(r"\s"));
      var name = (space < 0 ? tag : tag.substring(0, space)).trim();
      // Namespaced names -- svg:path -- are the plain ones.
      var colon = name.indexOf(":");
      if (colon >= 0) name = name.substring(colon + 1);
      var attrs = <String, String>{};
      if (space >= 0) {
        for (var m in _attr.allMatches(tag.substring(space))) {
          var key = m.group(1)!;
          var k = key.indexOf(":");
          // xlink:href and href are the same thing; other namespaced
          // attributes (inkscape:*, sodipodi:*) mean nothing to a drawing.
          if (k >= 0) {
            if (key.substring(k + 1) != "href") continue;
            key = "href";
          }
          attrs[key] = _unescape(m.group(3) ?? m.group(4) ?? "");
        }
      }
      var node = _Node(name, attrs);
      stack.last.children.add(node);
      if (!selfClosing) stack.add(node);
    }
    return top.children.isEmpty ? null : top.children.first;
  }

  /// _tagEnd is the ">" that ends the tag at [from], past any in quotes.
  static int _tagEnd(String s, int from) {
    String? quote;
    for (var i = from + 1; i < s.length; i++) {
      var c = s[i];
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == ">") {
        return i;
      }
    }
    return -1;
  }

  static String _unescape(String v) => v
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", '"')
      .replaceAll("&apos;", "'")
      .replaceAll("&amp;", "&");
}

// ---------------------------------------------------------------------------
// Styles: what a shape inherits from the groups round it.
// ---------------------------------------------------------------------------

class _Style {
  final Color? fill; // null is none
  final Color? stroke;
  final double strokeWidth;
  final double opacity;
  final double fillOpacity;
  final double strokeOpacity;
  final bool evenOdd;
  final StrokeCap cap;
  final StrokeJoin join;
  final Color color; // currentColor
  final bool hidden;

  const _Style({
    this.fill = const Color(0xFF000000),
    this.stroke,
    this.strokeWidth = 1,
    this.opacity = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.evenOdd = false,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.color = const Color(0xFF000000),
    this.hidden = false,
  });
}

class _Importer {
  final _Node svg;
  final Map<String, _Node> _ids = {};
  final Map<String, Map<String, String>> _classes = {};
  final Map<String, Map<String, String>> _tags = {};
  final List<VectorShape> _shapes = [];
  final Set<String> _dropped = {};

  _Importer(this.svg);

  SvgImport run() {
    svg.each((n) {
      var id = n.attrs["id"];
      if (id != null) _ids[id] = n;
      if (n.name == "style") _readCss(n.text.toString());
    });
    _walk(svg, const _Style(), _Matrix.identity, inDefs: false);
    return SvgImport(_viewBox(), _shapes, _dropped);
  }

  Rect _viewBox() {
    var vb = _numbers(svg.attrs["viewBox"] ?? "");
    if (vb.length == 4 && vb[2] > 0 && vb[3] > 0) {
      return Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]);
    }
    var w = _length(svg.attrs["width"]), h = _length(svg.attrs["height"]);
    if (w != null && h != null && w > 0 && h > 0) {
      return Rect.fromLTWH(0, 0, w, h);
    }
    // Neither: the shapes' own extent.
    Rect? all;
    for (var s in _shapes) {
      var b = s.path.getBounds();
      all = all == null ? b : all.expandToInclude(b);
    }
    return all ?? const Rect.fromLTWH(0, 0, 100, 100);
  }

  void _readCss(String css) {
    css = css.replaceAll(RegExp(r"/\*.*?\*/", dotAll: true), "");
    for (var m in RegExp(r"([^{}]+)\{([^}]*)\}").allMatches(css)) {
      var rules = _declarations(m.group(2)!);
      for (var sel in m.group(1)!.split(",")) {
        sel = sel.trim();
        if (sel.startsWith(".") && !sel.contains(" ")) {
          (_classes[sel.substring(1)] ??= {}).addAll(rules);
        } else if (RegExp(r"^[a-zA-Z]+$").hasMatch(sel)) {
          (_tags[sel] ??= {}).addAll(rules);
        }
      }
    }
  }

  static Map<String, String> _declarations(String text) => {
        for (var d in text.split(";"))
          if (d.contains(":"))
            d.substring(0, d.indexOf(":")).trim().toLowerCase():
                d.substring(d.indexOf(":") + 1).trim(),
      };

  /// _props is every presentation property on [n]: its tag's and classes'
  /// from the stylesheet, its attributes, then its own style -- later ones
  /// winning, as in a browser.
  Map<String, String> _props(_Node n) {
    var out = <String, String>{...?_tags[n.name]};
    for (var c in (n.attrs["class"] ?? "").split(RegExp(r"\s+"))) {
      if (c.isNotEmpty) out.addAll(_classes[c] ?? const {});
    }
    for (var k in const [
      "fill",
      "stroke",
      "stroke-width",
      "opacity",
      "fill-opacity",
      "stroke-opacity",
      "fill-rule",
      "stroke-linecap",
      "stroke-linejoin",
      "color",
      "display",
      "visibility",
    ]) {
      if (n.attrs[k] case var v?) out[k] = v;
    }
    out.addAll(_declarations(n.attrs["style"] ?? ""));
    return out;
  }

  _Style _styled(_Node n, _Style up) {
    var p = _props(n);
    var color = _paint(p["color"], up.color, up.color) ?? up.color;
    return _Style(
      fill: p.containsKey("fill") ? _paint(p["fill"], up.fill, color) : up.fill,
      stroke: p.containsKey("stroke")
          ? _paint(p["stroke"], up.stroke, color)
          : up.stroke,
      strokeWidth: _length(p["stroke-width"]) ?? up.strokeWidth,
      opacity: up.opacity * (_number(p["opacity"]) ?? 1),
      fillOpacity: _number(p["fill-opacity"]) ?? up.fillOpacity,
      strokeOpacity: _number(p["stroke-opacity"]) ?? up.strokeOpacity,
      evenOdd:
          p.containsKey("fill-rule") ? p["fill-rule"] == "evenodd" : up.evenOdd,
      cap: switch (p["stroke-linecap"]) {
        "round" => StrokeCap.round,
        "square" => StrokeCap.square,
        "butt" => StrokeCap.butt,
        _ => up.cap,
      },
      join: switch (p["stroke-linejoin"]) {
        "round" => StrokeJoin.round,
        "bevel" => StrokeJoin.bevel,
        "miter" => StrokeJoin.miter,
        _ => up.join,
      },
      color: color,
      hidden:
          up.hidden || p["display"] == "none" || p["visibility"] == "hidden",
    );
  }

  /// _paint reads a fill or stroke: a colour, none, currentColor, or a
  /// gradient -- which is made the colour it starts with.
  Color? _paint(String? v, Color? inherited, Color current) {
    if (v == null) return inherited;
    v = v.trim();
    if (v == "none" || v == "transparent") return null;
    if (v == "currentColor") return current;
    if (v.startsWith("url(")) {
      var id = RegExp(r"url\(\s*#([^)\s]+)\s*\)").firstMatch(v)?.group(1);
      var gradient = id == null ? null : _ids[id];
      if (gradient != null && gradient.name.endsWith("Gradient")) {
        _dropped.add("gradients (made solid)");
        var stops = _stops(gradient);
        if (stops != null) return stops;
      } else if (gradient != null && gradient.name == "pattern") {
        _dropped.add("patterns (made solid)");
      }
      // A fallback colour after the url, as SVG allows.
      var after = v.substring(v.indexOf(")") + 1).trim();
      return after.isEmpty ? const Color(0xFF888888) : parseSvgColor(after);
    }
    return parseSvgColor(v) ?? inherited;
  }

  Color? _stops(_Node gradient) {
    var node = gradient;
    // A gradient can borrow its stops from another.
    for (var hops = 0; hops < 4; hops++) {
      var stops = node.children.where((c) => c.name == "stop").toList();
      if (stops.isNotEmpty) {
        var p = _props(stops.first)..addAll(_declarations(""));
        var c = parseSvgColor(stops.first.attrs["stop-color"] ??
                p["stop-color"] ??
                "black") ??
            const Color(0xFF000000);
        var o = _number(stops.first.attrs["stop-opacity"] ?? p["stop-opacity"]);
        return o == null ? c : c.withValues(alpha: c.a * o);
      }
      var href = node.attrs["href"];
      var next =
          href != null && href.startsWith("#") ? _ids[href.substring(1)] : null;
      if (next == null) return null;
      node = next;
    }
    return null;
  }

  void _walk(_Node n, _Style up, _Matrix m, {required bool inDefs}) {
    var style = _styled(n, up);
    if (style.hidden) return;
    var here = m.times(_Matrix.parse(n.attrs["transform"] ?? ""));
    switch (n.name) {
      case "svg" when n != svg:
        // A drawing inside the drawing: placed at its x and y.
        here = here.times(_Matrix.translate(
            _length(n.attrs["x"]) ?? 0, _length(n.attrs["y"]) ?? 0));
        for (var c in n.children) {
          _walk(c, style, here, inDefs: inDefs);
        }
      case "svg" || "g" || "a" || "switch":
        for (var c in n.children) {
          _walk(c, style, here, inDefs: inDefs);
        }
      case "defs" ||
            "symbol" ||
            "linearGradient" ||
            "radialGradient" ||
            "style" ||
            "title" ||
            "desc" ||
            "metadata" ||
            "marker":
        break;
      case "clipPath" || "mask":
        _dropped.add("masks and clipping");
      case "filter":
        _dropped.add("filters");
      case "text" || "tspan" || "textPath":
        _dropped.add("text");
      case "image":
        _dropped.add("embedded pictures");
      case "foreignObject" || "pattern":
        _dropped.add("embedded content");
      case "use":
        var href = n.attrs["href"];
        var target = href != null && href.startsWith("#")
            ? _ids[href.substring(1)]
            : null;
        if (target == null) break;
        var at = here.times(_Matrix.translate(
            _length(n.attrs["x"]) ?? 0, _length(n.attrs["y"]) ?? 0));
        if (target.name == "symbol") {
          for (var c in target.children) {
            _walk(c, style, at, inDefs: false);
          }
        } else {
          _walk(target, style, at, inDefs: false);
        }
      default:
        if (n.attrs.containsKey("filter")) _dropped.add("filters");
        if (n.attrs.containsKey("clip-path") || n.attrs.containsKey("mask")) {
          _dropped.add("masks and clipping");
        }
        var paths = _outline(n);
        if (paths == null || paths.isEmpty) break;
        _add(paths, style, here);
    }
  }

  /// _outline is [n]'s outline as runs of points, in its own units -- or
  /// null where it is not a shape.
  List<_Run>? _outline(_Node n) {
    double a(String k) => _length(n.attrs[k]) ?? 0;
    switch (n.name) {
      case "path":
        return _PathData(n.attrs["d"] ?? "").runs();
      case "rect":
        var x = a("x"), y = a("y"), w = a("width"), h = a("height");
        if (w <= 0 || h <= 0) return null;
        var rx = _length(n.attrs["rx"]), ry = _length(n.attrs["ry"]);
        rx ??= ry ?? 0;
        ry ??= rx;
        rx = math.min(rx, w / 2);
        ry = math.min(ry, h / 2);
        if (rx <= 0 || ry <= 0) {
          return [
            _Run.closed([
              _P(x, y),
              _P(x + w, y),
              _P(x + w, y + h),
              _P(x, y + h),
            ])
          ];
        }
        // Eight points round the box, two to each corner: a straight edge
        // between the two of a side, a quarter ellipse between the two of a
        // corner.
        var kx = rx * 0.5523, ky = ry * 0.5523;
        return [
          _Run.closed([
            _P(x + rx, y, inX: -kx),
            _P(x + w - rx, y, outX: kx),
            _P(x + w, y + ry, inY: -ky),
            _P(x + w, y + h - ry, outY: ky),
            _P(x + w - rx, y + h, inX: kx),
            _P(x + rx, y + h, outX: -kx),
            _P(x, y + h - ry, inY: ky),
            _P(x, y + ry, outY: -ky),
          ])
        ];
      case "circle":
        var r = a("r");
        if (r <= 0) return null;
        return [_ellipse(a("cx"), a("cy"), r, r)];
      case "ellipse":
        var rx = a("rx"), ry = a("ry");
        if (rx <= 0 || ry <= 0) return null;
        return [_ellipse(a("cx"), a("cy"), rx, ry)];
      case "line":
        return [
          _Run([_P(a("x1"), a("y1")), _P(a("x2"), a("y2"))])
        ];
      case "polyline" || "polygon":
        var v = _numbers(n.attrs["points"] ?? "");
        var pts = [
          for (var i = 0; i + 1 < v.length; i += 2) _P(v[i], v[i + 1]),
        ];
        if (pts.length < 2) return null;
        return [n.name == "polygon" ? _Run.closed(pts) : _Run(pts)];
    }
    return null;
  }

  static _Run _ellipse(double cx, double cy, double rx, double ry) {
    var k = 0.5523;
    return _Run.closed([
      _P(cx + rx, cy, inY: -ry * k, outY: ry * k),
      _P(cx, cy + ry, inX: rx * k, outX: -rx * k),
      _P(cx - rx, cy, inY: ry * k, outY: -ry * k),
      _P(cx, cy - ry, inX: -rx * k, outX: rx * k),
    ]);
  }

  void _add(List<_Run> runs, _Style s, _Matrix m) {
    var fill = s.fill, stroke = s.stroke;
    if (fill != null) {
      fill = fill.withValues(alpha: fill.a * s.fillOpacity * s.opacity);
    }
    if (stroke != null) {
      stroke = stroke.withValues(alpha: stroke.a * s.strokeOpacity * s.opacity);
    }
    if (fill == null && stroke == null) return;
    _shapes.add(VectorShape(
      paths: [for (var r in runs) r.toPath(m)],
      fill: fill,
      stroke: stroke,
      strokeWidth: s.strokeWidth * m.scale,
      cap: s.cap,
      join: s.join,
      evenOdd: s.evenOdd,
    ));
  }
}

/// _P is a point being built, with handles as offsets.
class _P {
  double x, y, inX, inY, outX, outY;
  _P(this.x, this.y,
      {this.inX = 0, this.inY = 0, this.outX = 0, this.outY = 0});
}

class _Run {
  final List<_P> points;
  final bool closed;
  _Run(this.points) : closed = false;
  _Run.closed(this.points) : closed = true;
  _Run._(this.points, this.closed);

  VectorPath toPath(_Matrix m) {
    var nodes = <VectorNode>[];
    for (var p in points) {
      var at = m.apply(p.x, p.y);
      var i = m.apply(p.x + p.inX, p.y + p.inY);
      var o = m.apply(p.x + p.outX, p.y + p.outY);
      var inX = p.inX == 0 && p.inY == 0 ? 0.0 : i.dx - at.dx;
      var inY = p.inX == 0 && p.inY == 0 ? 0.0 : i.dy - at.dy;
      var outX = p.outX == 0 && p.outY == 0 ? 0.0 : o.dx - at.dx;
      var outY = p.outX == 0 && p.outY == 0 ? 0.0 : o.dy - at.dy;
      nodes.add(VectorNode(at.dx, at.dy,
          inX: inX,
          inY: inY,
          outX: outX,
          outY: outY,
          smooth: _smooth(inX, inY, outX, outY)));
    }
    return VectorPath(nodes, closed: closed);
  }

  /// _smooth is whether two handles point straight away from each other.
  static bool _smooth(double ix, double iy, double ox, double oy) {
    if ((ix == 0 && iy == 0) || (ox == 0 && oy == 0)) return false;
    var cross = ix * oy - iy * ox;
    var dot = ix * ox + iy * oy;
    var size = math.sqrt((ix * ix + iy * iy) * (ox * ox + oy * oy));
    return dot < 0 && cross.abs() <= size * 0.02;
  }
}

// ---------------------------------------------------------------------------
// Path data: d="M10 10 C 20 20, 40 20, 50 10 Z" and all its shorthands.
// ---------------------------------------------------------------------------

class _PathData {
  final String d;
  int _i = 0;
  _PathData(this.d);

  static final _number = RegExp(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?");

  List<_Run> runs() {
    var out = <_Run>[];
    List<_P>? current;
    var closed = false;
    double cx = 0, cy = 0, sx = 0, sy = 0;
    // The last control point, for the smooth shorthands.
    double? lastC2x, lastC2y, lastQx, lastQy;
    String? command;

    void finish() {
      if (current != null && current!.isNotEmpty) {
        var pts = current!;
        // Closed back onto its own start: the last point is the first.
        if (closed && pts.length > 1) {
          var a = pts.first, b = pts.last;
          if ((a.x - b.x).abs() < 1e-6 && (a.y - b.y).abs() < 1e-6) {
            a.inX = b.inX;
            a.inY = b.inY;
            pts.removeLast();
          }
        }
        out.add(_Run._(pts, closed));
      }
      current = null;
      closed = false;
    }

    void lineTo(double x, double y) {
      current ??= [_P(cx, cy)];
      current!.add(_P(x, y));
      cx = x;
      cy = y;
    }

    void cubicTo(
        double x1, double y1, double x2, double y2, double x, double y) {
      current ??= [_P(cx, cy)];
      var last = current!.last;
      last.outX = x1 - last.x;
      last.outY = y1 - last.y;
      current!.add(_P(x, y, inX: x2 - x, inY: y2 - y));
      cx = x;
      cy = y;
    }

    while (true) {
      _skip();
      if (_i >= d.length) break;
      var c = d[_i];
      if (RegExp(r"[A-Za-z]").hasMatch(c)) {
        command = c;
        _i++;
      } else if (command == null) {
        break;
      }
      var cmd = command;
      var rel = cmd == cmd.toLowerCase();
      double nx(double v) => rel ? cx + v : v;
      double ny(double v) => rel ? cy + v : v;
      switch (cmd.toUpperCase()) {
        case "M":
          var x = _num(), y = _num();
          if (x == null || y == null) return out..addAll(_tail(current));
          finish();
          cx = nx(x);
          cy = ny(y);
          sx = cx;
          sy = cy;
          current = [_P(cx, cy)];
          // Further pairs after a move are lines.
          command = rel ? "l" : "L";
          lastC2x = lastQx = null;
        case "L":
          var x = _num(), y = _num();
          if (x == null || y == null) break;
          lineTo(nx(x), ny(y));
          lastC2x = lastQx = null;
        case "H":
          var x = _num();
          if (x == null) break;
          lineTo(rel ? cx + x : x, cy);
          lastC2x = lastQx = null;
        case "V":
          var y = _num();
          if (y == null) break;
          lineTo(cx, rel ? cy + y : y);
          lastC2x = lastQx = null;
        case "C":
          var v = _nums(6);
          if (v == null) break;
          var x1 = nx(v[0]), y1 = ny(v[1]), x2 = nx(v[2]), y2 = ny(v[3]);
          cubicTo(x1, y1, x2, y2, nx(v[4]), ny(v[5]));
          lastC2x = x2;
          lastC2y = y2;
          lastQx = null;
        case "S":
          var v = _nums(4);
          if (v == null) break;
          // Reflected from the last curve's second handle, or the point
          // itself where the last segment was not a cubic.
          var x1 = lastC2x == null ? cx : 2 * cx - lastC2x;
          var y1 = lastC2x == null ? cy : 2 * cy - (lastC2y ?? cy);
          var x2 = nx(v[0]), y2 = ny(v[1]);
          cubicTo(x1, y1, x2, y2, nx(v[2]), ny(v[3]));
          lastC2x = x2;
          lastC2y = y2;
          lastQx = null;
        case "Q":
          var v = _nums(4);
          if (v == null) break;
          var qx = nx(v[0]), qy = ny(v[1]), x = nx(v[2]), y = ny(v[3]);
          _quad(cubicTo, cx, cy, qx, qy, x, y);
          lastQx = qx;
          lastQy = qy;
          lastC2x = null;
        case "T":
          var v = _nums(2);
          if (v == null) break;
          var qx = lastQx == null ? cx : 2 * cx - lastQx;
          var qy = lastQx == null ? cy : 2 * cy - (lastQy ?? cy);
          var x = nx(v[0]), y = ny(v[1]);
          _quad(cubicTo, cx, cy, qx, qy, x, y);
          lastQx = qx;
          lastQy = qy;
          lastC2x = null;
        case "A":
          var rx = _num(), ry = _num(), rot = _num();
          var large = _flag(), sweep = _flag();
          var x = _num(), y = _num();
          if (rx == null || ry == null || rot == null || large == null) break;
          if (sweep == null || x == null || y == null) break;
          _arc(
              cubicTo, lineTo, cx, cy, rx, ry, rot, large, sweep, nx(x), ny(y));
          lastC2x = lastQx = null;
        case "Z":
          closed = true;
          cx = sx;
          cy = sy;
          finish();
          // A draw after Z starts from the start of the run just closed.
          lastC2x = lastQx = null;
          command = null;
        default:
          // A command this does not know: stop rather than draw nonsense.
          finish();
          return out;
      }
    }
    finish();
    return out;
  }

  List<_Run> _tail(List<_P>? pts) =>
      pts == null || pts.length < 2 ? const [] : [_Run(pts)];

  void _skip() {
    while (_i < d.length &&
        (d[_i] == " " ||
            d[_i] == "," ||
            d[_i] == "\n" ||
            d[_i] == "\t" ||
            d[_i] == "\r")) {
      _i++;
    }
  }

  double? _num() {
    _skip();
    var m = _number.matchAsPrefix(d, _i);
    if (m == null) return null;
    _i = m.end;
    return double.tryParse(m.group(0)!);
  }

  List<double>? _nums(int count) {
    var out = <double>[];
    for (var i = 0; i < count; i++) {
      var v = _num();
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  /// _flag is an arc's 0 or 1, which may be written with nothing after it.
  bool? _flag() {
    _skip();
    if (_i >= d.length) return null;
    var c = d[_i];
    if (c != "0" && c != "1") return null;
    _i++;
    return c == "1";
  }

  static void _quad(
      void Function(double, double, double, double, double, double) cubic,
      double x0,
      double y0,
      double qx,
      double qy,
      double x,
      double y) {
    cubic(x0 + 2 / 3 * (qx - x0), y0 + 2 / 3 * (qy - y0), x + 2 / 3 * (qx - x),
        y + 2 / 3 * (qy - y), x, y);
  }

  /// _arc draws an elliptical arc as cubic curves, a quarter turn or less
  /// each -- the conversion every renderer does (SVG implementation notes,
  /// F.6).
  static void _arc(
      void Function(double, double, double, double, double, double) cubic,
      void Function(double, double) line,
      double x1,
      double y1,
      double rx,
      double ry,
      double angle,
      bool large,
      bool sweep,
      double x2,
      double y2) {
    if (rx == 0 || ry == 0) {
      line(x2, y2);
      return;
    }
    if (x1 == x2 && y1 == y2) return;
    rx = rx.abs();
    ry = ry.abs();
    var phi = angle * math.pi / 180;
    var cosP = math.cos(phi), sinP = math.sin(phi);
    var dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
    var x1p = cosP * dx + sinP * dy, y1p = -sinP * dx + cosP * dy;
    var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
      var s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
    }
    var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    var den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    var coef = (large != sweep ? 1 : -1) * math.sqrt(math.max(0, num / den));
    var cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx;
    var cx = cosP * cxp - sinP * cyp + (x1 + x2) / 2;
    var cy = sinP * cxp + cosP * cyp + (y1 + y2) / 2;
    double ang(double ux, double uy, double vx, double vy) {
      var a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
      return a;
    }

    var t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx,
        (-y1p - cyp) / ry);
    if (!sweep && dt > 0) dt -= 2 * math.pi;
    if (sweep && dt < 0) dt += 2 * math.pi;
    var pieces = (dt.abs() / (math.pi / 2)).ceil().clamp(1, 8);
    var step = dt / pieces;
    var k = 4 / 3 * math.tan(step / 4);
    Offset at(double t) => Offset(
        cx + rx * math.cos(t) * cosP - ry * math.sin(t) * sinP,
        cy + rx * math.cos(t) * sinP + ry * math.sin(t) * cosP);
    Offset tangent(double t) => Offset(
        -rx * math.sin(t) * cosP - ry * math.cos(t) * sinP,
        -rx * math.sin(t) * sinP + ry * math.cos(t) * cosP);
    var t = t1;
    for (var i = 0; i < pieces; i++) {
      var a = at(t), b = at(t + step);
      var ta = tangent(t), tb = tangent(t + step);
      var end = i == pieces - 1 ? Offset(x2, y2) : b;
      cubic(a.dx + k * ta.dx, a.dy + k * ta.dy, b.dx - k * tb.dx,
          b.dy - k * tb.dy, end.dx, end.dy);
      t += step;
    }
  }
}

// ---------------------------------------------------------------------------
// Transforms, numbers and colours.
// ---------------------------------------------------------------------------

class _Matrix {
  final double a, b, c, d, e, f;
  const _Matrix(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _Matrix(1, 0, 0, 1, 0, 0);

  factory _Matrix.translate(double x, double y) => _Matrix(1, 0, 0, 1, x, y);

  _Matrix times(_Matrix o) => _Matrix(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  Offset apply(double x, double y) =>
      Offset(a * x + c * y + e, b * x + d * y + f);

  /// scale is how much it grows a line's width: the square root of how much
  /// it grows an area.
  double get scale => math.sqrt((a * d - b * c).abs());

  static _Matrix parse(String s) {
    var out = identity;
    for (var m in RegExp(r"(\w+)\s*\(([^)]*)\)").allMatches(s)) {
      var v = _numbers(m.group(2)!);
      double at(int i, [double or = 0]) => i < v.length ? v[i] : or;
      _Matrix? next = switch (m.group(1)) {
        "matrix" when v.length >= 6 =>
          _Matrix(v[0], v[1], v[2], v[3], v[4], v[5]),
        "translate" => _Matrix(1, 0, 0, 1, at(0), at(1)),
        "scale" => _Matrix(at(0, 1), 0, 0, at(1, at(0, 1)), 0, 0),
        "rotate" => _rotate(at(0), at(1), at(2)),
        "skewX" => _Matrix(1, 0, math.tan(at(0) * math.pi / 180), 1, 0, 0),
        "skewY" => _Matrix(1, math.tan(at(0) * math.pi / 180), 0, 1, 0, 0),
        _ => null,
      };
      if (next != null) out = out.times(next);
    }
    return out;
  }

  static _Matrix _rotate(double deg, double cx, double cy) {
    var r = deg * math.pi / 180;
    var co = math.cos(r), si = math.sin(r);
    var rot = _Matrix(co, si, -si, co, 0, 0);
    if (cx == 0 && cy == 0) return rot;
    return _Matrix.translate(cx, cy)
        .times(rot)
        .times(_Matrix.translate(-cx, -cy));
  }
}

List<double> _numbers(String s) => [
      for (var m in _PathData._number.allMatches(s))
        if (double.tryParse(m.group(0)!) case var v?) v,
    ];

double? _number(String? s) {
  if (s == null) return null;
  s = s.trim();
  if (s.endsWith("%")) {
    var v = double.tryParse(s.substring(0, s.length - 1));
    return v == null ? null : v / 100;
  }
  return double.tryParse(s);
}

/// _length reads a length, its unit taken as pixels at 96 to the inch.
double? _length(String? s) {
  if (s == null) return null;
  var m = RegExp(r"^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)\s*([a-z%]*)")
      .firstMatch(s);
  if (m == null) return null;
  var v = double.tryParse(m.group(1)!);
  if (v == null) return null;
  return switch (m.group(2)) {
    "pt" => v * 4 / 3,
    "pc" => v * 16,
    "mm" => v * 96 / 25.4,
    "cm" => v * 96 / 2.54,
    "in" => v * 96,
    _ => v,
  };
}

/// parseSvgColor reads a colour as SVG writes one, or null where it cannot.
Color? parseSvgColor(String s) {
  s = s.trim().toLowerCase();
  if (s.startsWith("#")) {
    var h = s.substring(1);
    if (h.length == 3 || h.length == 4) {
      h = h.split("").map((c) => "$c$c").join();
    }
    if (h.length == 6) h = "${h}ff";
    if (h.length != 8) return null;
    var v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    // RRGGBBAA as written, to AARRGGBB.
    return Color(((v & 0xFF) << 24) | (v >> 8));
  }
  var fn = RegExp(r"^(rgba?|hsla?)\(([^)]*)\)").firstMatch(s);
  if (fn != null) {
    var parts = fn
        .group(2)!
        .split(RegExp(r"[\s,/]+"))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    double channel(String p, double scale) => p.endsWith("%")
        ? (double.tryParse(p.substring(0, p.length - 1)) ?? 0) / 100 * scale
        : (double.tryParse(p) ?? 0);
    var alpha = parts.length > 3 ? (_number(parts[3]) ?? 1) : 1.0;
    if (fn.group(1)!.startsWith("rgb")) {
      int c(int i) => channel(parts[i], 255).round().clamp(0, 255);
      return Color.fromARGB(
          (alpha * 255).round().clamp(0, 255), c(0), c(1), c(2));
    }
    var hsl = _Hsl(
        alpha.clamp(0.0, 1.0),
        (double.tryParse(parts[0]) ?? 0) % 360,
        (channel(parts[1], 1)).clamp(0.0, 1.0),
        (channel(parts[2], 1)).clamp(0.0, 1.0));
    return hsl.toColor();
  }
  return _named[s];
}

/// _Hsl is a colour given as hue, saturation and lightness.
class _Hsl {
  final double a, h, s, l;
  const _Hsl(this.a, this.h, this.s, this.l);

  Color toColor() {
    var c = (1 - (2 * l - 1).abs()) * s;
    var x = c * (1 - ((h / 60) % 2 - 1).abs());
    var m = l - c / 2;
    var (r, g, b) = switch (h ~/ 60) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    int to(double v) => ((v + m) * 255).round().clamp(0, 255);
    return Color.fromARGB((a * 255).round(), to(r), to(g), to(b));
  }
}

const Map<String, Color> _named = {
  "black": Color(0xFF000000),
  "white": Color(0xFFFFFFFF),
  "red": Color(0xFFFF0000),
  "green": Color(0xFF008000),
  "lime": Color(0xFF00FF00),
  "blue": Color(0xFF0000FF),
  "yellow": Color(0xFFFFFF00),
  "orange": Color(0xFFFFA500),
  "purple": Color(0xFF800080),
  "fuchsia": Color(0xFFFF00FF),
  "magenta": Color(0xFFFF00FF),
  "aqua": Color(0xFF00FFFF),
  "cyan": Color(0xFF00FFFF),
  "gray": Color(0xFF808080),
  "grey": Color(0xFF808080),
  "silver": Color(0xFFC0C0C0),
  "maroon": Color(0xFF800000),
  "olive": Color(0xFF808000),
  "navy": Color(0xFF000080),
  "teal": Color(0xFF008080),
  "pink": Color(0xFFFFC0CB),
  "brown": Color(0xFFA52A2A),
  "gold": Color(0xFFFFD700),
  "indigo": Color(0xFF4B0082),
  "violet": Color(0xFFEE82EE),
  "beige": Color(0xFFF5F5DC),
  "coral": Color(0xFFFF7F50),
  "crimson": Color(0xFFDC143C),
  "darkgray": Color(0xFFA9A9A9),
  "darkgrey": Color(0xFFA9A9A9),
  "lightgray": Color(0xFFD3D3D3),
  "lightgrey": Color(0xFFD3D3D3),
  "darkblue": Color(0xFF00008B),
  "darkgreen": Color(0xFF006400),
  "darkred": Color(0xFF8B0000),
  "skyblue": Color(0xFF87CEEB),
  "tomato": Color(0xFFFF6347),
  "salmon": Color(0xFFFA8072),
  "tan": Color(0xFFD2B48C),
  "khaki": Color(0xFFF0E68C),
  "turquoise": Color(0xFF40E0D0),
  "orchid": Color(0xFFDA70D6),
  "plum": Color(0xFFDDA0DD),
  "lavender": Color(0xFFE6E6FA),
  "ivory": Color(0xFFFFFFF0),
  "whitesmoke": Color(0xFFF5F5F5),
  "dimgray": Color(0xFF696969),
  "dimgrey": Color(0xFF696969),
  "slategray": Color(0xFF708090),
  "steelblue": Color(0xFF4682B4),
  "royalblue": Color(0xFF4169E1),
  "dodgerblue": Color(0xFF1E90FF),
  "firebrick": Color(0xFFB22222),
  "forestgreen": Color(0xFF228B22),
  "seagreen": Color(0xFF2E8B57),
  "chocolate": Color(0xFFD2691E),
  "sienna": Color(0xFFA0522D),
};

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/render/canvas_perf.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';

// mesh_painter.dart draws triangles in 3D on a flat canvas: lit, the ones
// facing away left out, and the rest drawn from the furthest to the
// nearest so the near ones cover the far.
//
// It is the one place a body in 3D becomes pixels, whether it is a
// mannequin built from a character's proportions or a model from a file.
// No depth buffer -- a canvas has none -- so two triangles that pass
// through each other are drawn whole, one over the other. For a body seen
// from outside, which is all this draws, that is never seen.

/// MeshPiece is triangles in one material, already where they are seen:
/// x to the right, y up and z towards the reader, in pixels from the point
/// the painter is given.
class MeshPiece {
  /// points is x, y, z for each vertex.
  final Float32List points;

  /// normals is which way each vertex faces, or null to light each
  /// triangle by its own face.
  final Float32List? normals;

  /// uvs is where on [image] each vertex is, 0 to 1 across and down.
  final Float32List? uvs;

  /// colors is red, green, blue and alpha, 0 to 1, for each vertex, laid
  /// over [color].
  final Float32List? colors;
  final Uint32List indices;
  final Color color;
  final Image? image;

  /// doubleSided draws a triangle facing away too: cloth, hair cards and
  /// anything else made of one sheet.
  final bool doubleSided;

  /// cutOut is [image] used only for where it is solid: every way the piece
  /// is drawn is cut out by it, not only its colour.
  final bool cutOut;

  /// toon is how the piece is drawn with toon shading, when it says --
  /// see MeshToon; null for the anime look every piece has by default.
  final MeshToon? toon;

  /// depth, when given, is how near the reader the whole piece is drawn
  /// as being: it is drawn whole, in its turn among the others, rather
  /// than triangle by triangle among theirs. For a piece that is one
  /// rounded lump, which is every piece of a mannequin -- where two lumps
  /// pass through each other, a triangle at a time leaves a ragged seam.
  final double? depth;

  const MeshPiece({
    required this.points,
    required this.indices,
    this.normals,
    this.uvs,
    this.colors,
    this.color = const Color(0xFFFFFFFF),
    this.image,
    this.doubleSided = false,
    this.depth,
    this.toon,
    this.cutOut = false,
  });
}

/// MeshToon is a piece's toon shading: the colour its shadow is, as a
/// share of its own colour; how hard the edge between light and shadow is,
/// from soft at nought to sharp at one; how far round it falls; and the
/// light caught round its rim.
class MeshToon {
  final Color shade;
  final double toony;
  final double shift;
  final Color rim;
  final double rimPower;
  const MeshToon({
    this.shade = const Color(0xFFB7A8D6),
    this.toony = 0.92,
    this.shift = -0.05,
    this.rim = const Color(0x33FFFFFF),
    this.rimPower = 4,
  });

  /// anime is the look a piece with no settings of its own is given: a
  /// soft violet shadow and a little light round the edge.
  static const MeshToon anime = MeshToon();
}

/// _light is the way the light comes from: above, to the left and in
/// front, which is how a figure is lit to read as solid.
const List<double> _light = [-0.38, 0.55, 0.74];

/// meshBounds is where [pieces] are drawn round [origin], or null for
/// nothing to draw.
Rect? meshBounds(List<MeshPiece> pieces, Offset origin) {
  var left = double.infinity, top = double.infinity;
  var right = -double.infinity, bottom = -double.infinity;
  for (var p in pieces) {
    var v = p.points;
    for (var i = 0; i + 2 < v.length; i += 3) {
      left = math.min(left, v[i]);
      right = math.max(right, v[i]);
      top = math.min(top, -v[i + 1]);
      bottom = math.max(bottom, -v[i + 1]);
    }
  }
  if (!left.isFinite) return null;
  return Rect.fromLTRB(left, top, right, bottom).shift(origin);
}

/// paintMeshes draws [pieces] round [origin] -- their x and y nought --
/// lit as [shading] says, with a line [outline] pixels wide round the
/// whole when it is more than nought.
void paintMeshes(Canvas canvas, Offset origin, List<MeshPiece> pieces,
    {ModelShading shading = ModelShading.soft,
    double outline = 0,
    Color outlineColor = const Color(0xFF1A1A1A)}) {
  var bounds = meshBounds(pieces, origin);
  if (bounds == null) return;
  var order = _sorted(pieces);
  if (order.isEmpty) return;
  if (outline > 0) {
    // The figure in one colour, grown by the line's width, under the
    // figure: what is left showing round it is the line.
    canvas.saveLayer(
        bounds.inflate(outline * 2),
        Paint()
          ..imageFilter = ImageFilter.dilate(radiusX: outline, radiusY: outline)
          ..colorFilter = ColorFilter.mode(outlineColor, BlendMode.srcIn));
    _draw(canvas, origin, pieces, order, shading, plain: true);
    canvas.restore();
  }
  _draw(canvas, origin, pieces, order, shading);
}

/// _Tri is a triangle to draw: which piece, which of its triangles, and
/// whether it is seen from behind.
typedef _Tri = ({int piece, int at, bool back, double depth, double own});

List<_Tri> _sorted(List<MeshPiece> pieces) {
  var out = <_Tri>[];
  for (var (pi, p) in pieces.indexed) {
    var v = p.points, ix = p.indices;
    for (var t = 0; t + 2 < ix.length; t += 3) {
      var a = ix[t] * 3, b = ix[t + 1] * 3, c = ix[t + 2] * 3;
      if (c + 2 >= v.length || a + 2 >= v.length || b + 2 >= v.length) continue;
      // Which way it faces the reader: the z of its face's normal, the
      // corners going round anticlockwise for a face seen from the front.
      var nz = (v[b] - v[a]) * (v[c + 1] - v[a + 1]) -
          (v[b + 1] - v[a + 1]) * (v[c] - v[a]);
      var back = nz <= 0;
      if (back && !p.doubleSided) continue;
      var own = v[a + 2] + v[b + 2] + v[c + 2];
      out.add((
        piece: pi,
        at: t,
        back: back,
        depth: p.depth == null ? own : p.depth! * 3,
        own: own,
      ));
    }
  }
  // The furthest first; the same depth kept in the file's order, so a
  // decal laid on a face stays on it. Within a piece drawn whole, its own
  // triangles furthest first.
  out.sort((x, y) {
    var d = x.depth.compareTo(y.depth);
    if (d != 0) return d;
    d = x.piece.compareTo(y.piece);
    if (d != 0) return d;
    d = x.own.compareTo(y.own);
    return d != 0 ? d : x.at.compareTo(y.at);
  });
  return out;
}

/// _shade is how lit a surface facing [nx], [ny], [nz] is.
double _shade(double nx, double ny, double nz, ModelShading shading) {
  var l = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (l == 0) return 1;
  var d = (nx * _light[0] + ny * _light[1] + nz * _light[2]) / l;
  return switch (shading) {
    ModelShading.toon => d > 0.2 ? 1.0 : 0.68,
    _ => 0.45 + 0.55 * math.max(0.0, d) + 0.08 * math.max(0.0, nz / l),
  }
      .clamp(0.0, 1.1);
}

/// _Pass is what a drawing of the triangles records: their lit colour,
/// black for an outline, or -- for the toon shader to light later -- their
/// own colour, which way they face, how near they are, or their shadow
/// colour.
enum _Pass { lit, plain, albedo, normal, depth, shade }

void _draw(Canvas canvas, Offset origin, List<MeshPiece> pieces,
    List<_Tri> order, ModelShading shading,
    {bool plain = false, _Pass pass = _Pass.lit, (double, double)? depth}) {
  if (plain) pass = _Pass.plain;
  var start = 0;
  while (start < order.length) {
    // A run of triangles in the same piece, drawn in one call.
    var piece = order[start].piece;
    var end = start + 1;
    while (end < order.length && order[end].piece == piece) {
      end++;
    }
    _run(canvas, origin, pieces[piece], order, start, end, shading, pass, depth);
    start = end;
  }
}

void _run(Canvas canvas, Offset origin, MeshPiece p, List<_Tri> order,
    int start, int end, ModelShading shading, _Pass pass,
    (double, double)? depth) {
  var plain = pass == _Pass.plain;
  var n = (end - start) * 3;
  var positions = Float32List(n * 2);
  var colors = Int32List(n);
  var image = pass == _Pass.lit || pass == _Pass.albedo ? p.image : null;
  var uvs = image != null && p.uvs != null ? Float32List(n * 2) : null;
  var v = p.points, ix = p.indices, normals = p.normals, vc = p.colors;
  var base = p.color;
  var flat = shading == ModelShading.flat || normals == null;
  var w = image?.width.toDouble() ?? 0, h = image?.height.toDouble() ?? 0;
  var k = 0;
  for (var o = start; o < end; o++) {
    var tri = order[o];
    var flip = tri.back ? -1.0 : 1.0;
    double faceShade = 1;
    // A face's own direction, for faceted light and for the toon shader
    // drawing faceted.
    var faceNormal = const <double>[0, 0, 1];
    if (flat && !plain) {
      var a = ix[tri.at] * 3, b = ix[tri.at + 1] * 3, c = ix[tri.at + 2] * 3;
      var ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
      var wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
      faceNormal = [
        (uy * wz - uz * wy) * flip,
        (uz * wx - ux * wz) * flip,
        (ux * wy - uy * wx) * flip
      ];
      faceShade = _shade(faceNormal[0], faceNormal[1], faceNormal[2], shading);
    }
    for (var c = 0; c < 3; c++) {
      var i = ix[tri.at + c];
      positions[k * 2] = origin.dx + v[i * 3];
      positions[k * 2 + 1] = origin.dy - v[i * 3 + 1];
      if (uvs != null) {
        uvs[k * 2] = p.uvs![i * 2] * w;
        uvs[k * 2 + 1] = p.uvs![i * 2 + 1] * h;
      }
      if (plain) {
        colors[k] = 0xFF000000;
      } else if (pass == _Pass.albedo) {
        var r = base.r, g = base.g, b = base.b, a = base.a;
        if (vc != null && vc.length >= (i + 1) * 4) {
          r *= vc[i * 4];
          g *= vc[i * 4 + 1];
          b *= vc[i * 4 + 2];
          a *= vc[i * 4 + 3];
        }
        colors[k] = _argb(a < 0.5 ? a : 1, r, g, b);
      } else if (pass == _Pass.normal) {
        double nx, ny, nz;
        if (flat) {
          (nx, ny, nz) = (faceNormal[0], faceNormal[1], faceNormal[2]);
        } else {
          (nx, ny, nz) = (normals[i * 3] * flip, normals[i * 3 + 1] * flip,
              normals[i * 3 + 2] * flip);
        }
        var l = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (l == 0) l = 1;
        colors[k] = _argb(1, nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5);
      } else if (pass == _Pass.depth) {
        // Nearer is more, in sixteen bits over two channels.
        var (lo, hi) = depth ?? (0.0, 1.0);
        var t = ((v[i * 3 + 2] - lo) / math.max(1e-9, hi - lo)).clamp(0.0, 1.0);
        var whole = (t * 255).floor() / 255;
        colors[k] = _argb(1, whole, (t - whole) * 255, 0);
      } else if (pass == _Pass.shade) {
        var t = p.toon ?? MeshToon.anime;
        colors[k] = _argb(1, t.shade.r, t.shade.g, t.shade.b);
      } else if (shading == ModelShading.toon && normals != null) {
        colors[k] = _toonColour(normals[i * 3] * flip, normals[i * 3 + 1] * flip,
            normals[i * 3 + 2] * flip, base, vc, i, p.toon ?? MeshToon.anime);
      } else {
        var s = flat
            ? faceShade
            : _shade(normals[i * 3] * flip, normals[i * 3 + 1] * flip,
                normals[i * 3 + 2] * flip, shading);
        var r = base.r, g = base.g, b = base.b, a = base.a;
        if (vc != null && vc.length >= (i + 1) * 4) {
          r *= vc[i * 4];
          g *= vc[i * 4 + 1];
          b *= vc[i * 4 + 2];
          a *= vc[i * 4 + 3];
        }
        colors[k] = _argb(a, r * s, g * s, b * s);
      }
      k++;
    }
  }
  var vertices = Vertices.raw(VertexMode.triangles, positions,
      textureCoordinates: uvs, colors: colors);
  var paint = Paint();
  if (uvs != null) {
    paint.shader = ImageShader(image!, TileMode.repeated, TileMode.repeated,
        _identity, filterQuality: FilterQuality.medium);
  }
  canvas.drawVertices(vertices, BlendMode.modulate, paint);
  vertices.dispose();
}

final Float64List _identity = Float64List(16)
  ..[0] = 1
  ..[5] = 1
  ..[10] = 1
  ..[15] = 1;

/// _toonColour is a vertex facing [nx], [ny], [nz] in [base] colour, as
/// toon shading draws it: its shadow colour, its lit colour, or between
/// across the edge as [toon] says, and light round the rim.
int _toonColour(double nx, double ny, double nz, Color base, Float32List? vc,
    int i, MeshToon toon) {
  var l = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (l == 0) l = 1;
  var d = (nx * _light[0] + ny * _light[1] + nz * _light[2]) / l;
  var soft = math.max(0.02, 1 - toon.toony);
  var lit = ((d + toon.shift + soft / 2) / soft).clamp(0.0, 1.0);
  var r = base.r, g = base.g, b = base.b, a = base.a;
  if (vc != null && vc.length >= (i + 1) * 4) {
    r *= vc[i * 4];
    g *= vc[i * 4 + 1];
    b *= vc[i * 4 + 2];
    a *= vc[i * 4 + 3];
  }
  double mix(double c, double shade) => c * shade + (c - c * shade) * lit;
  var rim = math.pow(1 - (nz / l).abs().clamp(0.0, 1.0), toon.rimPower) * toon.rim.a;
  return _argb(a, mix(r, toon.shade.r) + toon.rim.r * rim,
      mix(g, toon.shade.g) + toon.rim.g * rim, mix(b, toon.shade.b) + toon.rim.b * rim);
}

int _argb(double a, double r, double g, double b) {
  int c(double x) => (x.clamp(0.0, 1.0) * 255).round();
  return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
}


/// ToonShader is character_toon.frag, loaded once.
class ToonShader {
  static FragmentProgram? _program;
  static Future<void>? _loading;

  static FragmentProgram? get program => _program;

  static Future<void> load() => _loading ??= () async {
        try {
          _program = await FragmentProgram.fromAsset("shaders/character_toon.frag");
        } catch (e) {
          // Without it, bodies in 3D are lit a vertex at a time, as before.
          _program = null;
        }
      }();
}

/// InkLook is how the toon shader draws a body: cel bands or soft light,
/// how hard their edge is and where it falls, light round the rim, and the
/// ink -- the outline's width and how strong the lines inside are.
class InkLook {
  final bool cel;
  final double toony;
  final double shift;
  final Color rim;
  final double rimPower;
  final double outline;
  final double inner;
  final Color ink;

  /// light is where the light comes from: x right, y up, z towards the
  /// reader -- round to the side, so the shadow side of a form reads.
  final List<double> light;
  const InkLook({
    this.light = const [-0.66, 0.42, 0.62],
    this.cel = true,
    this.toony = 0.92,
    this.shift = -0.12,
    this.rim = const Color(0x40FFFFFF),
    this.rimPower = 4,
    this.outline = 1.5,
    this.inner = 0.8,
    this.ink = const Color(0xFF2A2024),
    this.shade,
    this.pattern = 0,
  });

  /// pattern is the shadow as a printed screen: 0 solid, 1 halftone dots,
  /// 2 screentone.
  final int pattern;

  /// shade is the colour a shadow is tinted, for a piece that does not say
  /// its own: a style's -- null for the usual.
  final Color? shade;

  /// key is everything it draws by, as one string.
  String get key => "$light|$cel|$toony|$shift|${rim.toARGB32()}|$rimPower|"
      "$outline|$inner|${ink.toARGB32()}|${shade?.toARGB32()}|$pattern";
}

/// paintMeshesInked draws [pieces] as the toon shader does -- lit a pixel
/// at a time, outlined and inked -- and is whether it could: false while
/// the shader is not loaded, for the caller to draw them another way.
bool paintMeshesInked(Canvas canvas, Offset origin, List<MeshPiece> pieces,
    InkLook look,
    {ModelShading shading = ModelShading.toon}) {
  var program = ToonShader.program;
  if (program == null) {
    ToonShader.load();
    return false;
  }
  var m = canvas.getTransform();
  var seen = math.sqrt(m[0] * m[0] + m[1] * m[1]).clamp(0.25, 8.0);
  // The same posed pieces drawn the same way again -- the canvas redrawn
  // for a selection, a panel, a hover -- are the picture made last time.
  var key = "$seen|$shading|${look.key}";
  if (_inked[pieces] case (var k, var r, var img) when k == key) {
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        r.shift(origin),
        Paint()..filterQuality = FilterQuality.medium);
    return true;
  }
  CanvasPerf.count("character3dInk");
  var bounds = meshBounds(pieces, origin);
  if (bounds == null) return true;
  var order = CanvasPerf.time("character3dSort", () => _sorted(pieces));
  if (order.isEmpty) return true;
  bounds = bounds.inflate(look.outline * 2 + 2);
  // Drawn half as large again as it is seen at, for smooth edges; no
  // bigger than a picture can sensibly be.
  var scale = seen * 1.5;
  var longest = math.max(bounds.width, bounds.height) * scale;
  if (longest > 2400) scale *= 2400 / longest;
  var w = math.max(1, (bounds.width * scale).ceil());
  var h = math.max(1, (bounds.height * scale).ceil());
  var lo = double.infinity, hi = -double.infinity;
  for (var p in pieces) {
    for (var i = 2; i < p.points.length; i += 3) {
      lo = math.min(lo, p.points[i]);
      hi = math.max(hi, p.points[i]);
    }
  }
  var runs = _prepare(origin, pieces, order, shading == ModelShading.flat);
  Image record(_Pass pass) {
    var rec = PictureRecorder();
    var c = Canvas(rec)
      ..scale(scale)
      ..translate(-bounds!.left, -bounds.top);
    for (var r in runs) {
      r.paint(c, pieces[r.piece], pass, (lo, hi), shade: look.shade);
    }
    return rec.endRecording().toImageSync(w, h);
  }

  var albedo = record(_Pass.albedo);
  var normal = record(_Pass.normal);
  var depth = record(_Pass.depth);
  var shade = record(_Pass.shade);
  var shader = program.fragmentShader();
  var k = 0;
  void f(double v) => shader.setFloat(k++, v);
  f(w.toDouble());
  f(h.toDouble());
  f(look.light[0]);
  f(look.light[1]);
  f(look.light[2]);
  f(look.cel && shading != ModelShading.soft ? 1 : 0);
  f(look.toony);
  f(look.shift);
  f(look.rim.r);
  f(look.rim.g);
  f(look.rim.b);
  f(look.rim.a);
  f(look.rimPower);
  f(look.outline * scale);
  f(look.inner);
  f(look.ink.r);
  f(look.ink.g);
  f(look.ink.b);
  f(look.ink.a);
  f(look.pattern.toDouble());
  shader.setImageSampler(0, albedo, filterQuality: FilterQuality.none);
  shader.setImageSampler(1, normal, filterQuality: FilterQuality.none);
  shader.setImageSampler(2, depth, filterQuality: FilterQuality.none);
  shader.setImageSampler(3, shade, filterQuality: FilterQuality.none);
  var lit = PictureRecorder();
  Canvas(lit).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = shader);
  var picture = lit.endRecording().toImageSync(w, h);
  canvas.drawImageRect(
      picture,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      bounds,
      Paint()..filterQuality = FilterQuality.medium);
  for (var i in [albedo, normal, depth, shade]) {
    i.dispose();
  }
  _inked[pieces] = (key, bounds.shift(-origin), picture);
  return true;
}

/// _inked is the picture paintMeshesInked last made of a list of pieces,
/// and how: kept with the pieces, and let go with them.
final Expando<(String, Rect, Image)> _inked = Expando();


/// _Run is a run of one piece's triangles, laid out once for every pass
/// the toon shader needs: where each corner is on the page, where on the
/// piece's picture, which vertex it is, and which way it faces.
class _Run {
  final int piece;
  final Float32List positions;
  final Float32List? uvs;
  final Int32List vertex;

  /// normals is each corner's facing, x y z, already turned round for a
  /// triangle seen from behind, and its face's own facing where faceted.
  final Float32List normals;
  _Run(this.piece, this.positions, this.uvs, this.vertex, this.normals);

  void paint(Canvas canvas, MeshPiece p, _Pass pass, (double, double) depth,
      {Color? shade}) {
    var n = vertex.length;
    var colors = Int32List(n);
    var base = p.color, vc = p.colors, v = p.points;
    var (lo, hi) = depth;
    var range = math.max(1e-9, hi - lo);
    var toon = p.toon ?? MeshToon.anime;
    for (var k = 0; k < n; k++) {
      var i = vertex[k];
      switch (pass) {
        case _Pass.albedo:
          var r = base.r, g = base.g, b = base.b, a = base.a;
          if (vc != null && vc.length >= (i + 1) * 4) {
            r *= vc[i * 4];
            g *= vc[i * 4 + 1];
            b *= vc[i * 4 + 2];
            a *= vc[i * 4 + 3];
          }
          colors[k] = _argb(a < 0.5 ? a : 1, r, g, b);
        case _Pass.normal:
          colors[k] = _argb(1, normals[k * 3] * 0.5 + 0.5,
              normals[k * 3 + 1] * 0.5 + 0.5, normals[k * 3 + 2] * 0.5 + 0.5);
        case _Pass.depth:
          var t = ((v[i * 3 + 2] - lo) / range).clamp(0.0, 1.0);
          var whole = (t * 255).floor() / 255;
          colors[k] = _argb(1, whole, (t - whole) * 255, 0);
        case _Pass.shade:
          var sc = p.toon == null && shade != null ? shade : toon.shade;
          // Hair cut out of cards is marked by a shade a little see-through,
          // for the light to give it a sheen and no lines between cards.
          colors[k] = _argb(p.cutOut ? 0.6 : 1, sc.r, sc.g, sc.b);
        default:
          colors[k] = 0xFF000000;
      }
    }
    var textured = (pass == _Pass.albedo || p.cutOut) && uvs != null && p.image != null;
    var vertices = Vertices.raw(VertexMode.triangles, positions,
        textureCoordinates: textured ? uvs : null, colors: colors);
    var paint = Paint();
    if (textured) {
      paint.shader = ImageShader(p.image!, TileMode.repeated, TileMode.repeated,
          _identity, filterQuality: FilterQuality.medium);
    }
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }
}

/// _prepare lays [order]'s triangles out in runs, once -- see _Run.
List<_Run> _prepare(
    Offset origin, List<MeshPiece> pieces, List<_Tri> order, bool faceted) {
  var runs = <_Run>[];
  var start = 0;
  while (start < order.length) {
    var piece = order[start].piece;
    var end = start + 1;
    while (end < order.length && order[end].piece == piece) {
      end++;
    }
    var p = pieces[piece];
    var n = (end - start) * 3;
    var positions = Float32List(n * 2);
    var vertex = Int32List(n);
    var normals = Float32List(n * 3);
    var image = p.image;
    var uvs = image != null && p.uvs != null ? Float32List(n * 2) : null;
    var w = image?.width.toDouble() ?? 0, h = image?.height.toDouble() ?? 0;
    var v = p.points, ix = p.indices, pn = p.normals;
    var flatShade = faceted || pn == null;
    var k = 0;
    for (var o = start; o < end; o++) {
      var tri = order[o];
      var flip = tri.back ? -1.0 : 1.0;
      var fx = 0.0, fy = 0.0, fz = 1.0;
      if (flatShade) {
        var a = ix[tri.at] * 3, b = ix[tri.at + 1] * 3, c = ix[tri.at + 2] * 3;
        var ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
        var wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
        fx = (uy * wz - uz * wy) * flip;
        fy = (uz * wx - ux * wz) * flip;
        fz = (ux * wy - uy * wx) * flip;
        var l = math.sqrt(fx * fx + fy * fy + fz * fz);
        if (l > 0) {
          fx /= l;
          fy /= l;
          fz /= l;
        }
      }
      for (var c = 0; c < 3; c++) {
        var i = ix[tri.at + c];
        vertex[k] = i;
        positions[k * 2] = origin.dx + v[i * 3];
        positions[k * 2 + 1] = origin.dy - v[i * 3 + 1];
        if (uvs != null) {
          uvs[k * 2] = p.uvs![i * 2] * w;
          uvs[k * 2 + 1] = p.uvs![i * 2 + 1] * h;
        }
        if (flatShade) {
          normals[k * 3] = fx;
          normals[k * 3 + 1] = fy;
          normals[k * 3 + 2] = fz;
        } else {
          var nx = pn[i * 3] * flip, ny = pn[i * 3 + 1] * flip, nz = pn[i * 3 + 2] * flip;
          var l = math.sqrt(nx * nx + ny * ny + nz * nz);
          if (l == 0) l = 1;
          normals[k * 3] = nx / l;
          normals[k * 3 + 1] = ny / l;
          normals[k * 3 + 2] = nz / l;
        }
        k++;
      }
    }
    runs.add(_Run(piece, positions, uvs, vertex, normals));
    start = end;
  }
  return runs;
}

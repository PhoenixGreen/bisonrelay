import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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
  });
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

void _draw(Canvas canvas, Offset origin, List<MeshPiece> pieces,
    List<_Tri> order, ModelShading shading,
    {bool plain = false}) {
  var start = 0;
  while (start < order.length) {
    // A run of triangles in the same piece, drawn in one call.
    var piece = order[start].piece;
    var end = start + 1;
    while (end < order.length && order[end].piece == piece) {
      end++;
    }
    _run(canvas, origin, pieces[piece], order, start, end, shading, plain);
    start = end;
  }
}

void _run(Canvas canvas, Offset origin, MeshPiece p, List<_Tri> order,
    int start, int end, ModelShading shading, bool plain) {
  var n = (end - start) * 3;
  var positions = Float32List(n * 2);
  var colors = Int32List(n);
  var image = plain ? null : p.image;
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
    if (flat && !plain) {
      var a = ix[tri.at] * 3, b = ix[tri.at + 1] * 3, c = ix[tri.at + 2] * 3;
      var ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
      var wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
      faceShade = _shade((uy * wz - uz * wy) * flip, (uz * wx - ux * wz) * flip,
          (ux * wy - uy * wx) * flip, shading);
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

int _argb(double a, double r, double g, double b) {
  int c(double x) => (x.clamp(0.0, 1.0) * 255).round();
  return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b);
}

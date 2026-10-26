import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/human_wear.dart';

// human_wear_fit.dart puts a piece of hair, a brow, a shoe on a sculpted
// body: each of its vertices is pinned to three of the body's -- that much
// of each, and a little off them -- so it sits right on any body the
// sliders make, and moves with it.

/// WearMesh is a piece read: its own mesh, and how each of its vertices is
/// pinned to the body.
class WearMesh {
  final WearItem item;

  /// refs is three body vertices for each of the piece's, weights how much
  /// of each, and offsets how far off them, before scaling.
  final Int32List refs;
  final Float32List weights;
  final Float32List offsets;

  /// scales is, for x, y and z, two body vertices and how far apart they
  /// were when the piece was made: how much bigger a body is along each.
  final List<(int, int, double)?> scales;
  final Float32List uvs;

  /// corners is the piece's triangles: a vertex then a uv index, three
  /// corners a triangle.
  final Uint32List corners;

  /// hides is the body's vertices the piece covers, not to be drawn.
  final Set<int> hides;

  WearMesh(this.item, this.refs, this.weights, this.offsets, this.scales,
      this.uvs, this.corners, this.hides);

  int get vertexCount => refs.length ~/ 3;

  static WearMesh parse(WearItem item, String obj, String mhclo) {
    var uvs = <double>[];
    var corners = <int>[];
    var vertices = 0;
    for (var line in obj.split("\n")) {
      if (line.startsWith("v ")) {
        vertices++;
      } else if (line.startsWith("vt ")) {
        var p = line.trim().split(RegExp(r"\s+"));
        uvs.addAll([double.parse(p[1]), 1 - double.parse(p[2])]);
      } else if (line.startsWith("f ")) {
        var c = [
          for (var part in line.substring(2).trim().split(RegExp(r"\s+")))
            [for (var n in part.split("/")) n.isEmpty ? 0 : int.parse(n) - 1],
        ];
        for (var k = 1; k + 1 < c.length; k++) {
          for (var x in [c[0], c[k], c[k + 1]]) {
            corners.add(x[0]);
            corners.add(x.length > 1 ? x[1] : 0);
          }
        }
      }
    }
    var refs = Int32List(vertices * 3);
    var weights = Float32List(vertices * 3);
    var offsets = Float32List(vertices * 3);
    var scales = List<(int, int, double)?>.filled(3, null);
    var hides = <int>{};
    var section = "";
    var v = 0;
    for (var raw in mhclo.split("\n")) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith("#")) continue;
      var p = line.split(RegExp(r"\s+"));
      if (p[0] == "x_scale" || p[0] == "y_scale" || p[0] == "z_scale") {
        var axis = "xyz".indexOf(p[0][0]);
        scales[axis] = (int.parse(p[1]), int.parse(p[2]), double.parse(p[3]));
        continue;
      }
      if (p[0] == "verts") {
        section = "verts";
        continue;
      }
      if (p[0] == "delete_verts") {
        section = "delete";
        continue;
      }
      if (int.tryParse(p[0]) == null) {
        // Another header line, or another section this does not need.
        if (section == "verts" && v > 0) section = "";
        continue;
      }
      if (section == "verts" && v < vertices) {
        if (p.length >= 9) {
          for (var k = 0; k < 3; k++) {
            refs[v * 3 + k] = int.parse(p[k]);
            weights[v * 3 + k] = double.parse(p[3 + k]);
            offsets[v * 3 + k] = double.parse(p[6 + k]);
          }
        } else {
          // Pinned to one vertex exactly.
          refs[v * 3] = int.parse(p[0]);
          weights[v * 3] = 1;
        }
        v++;
      } else if (section == "delete") {
        for (var i = 0; i < p.length; i++) {
          if (p[i] == "-" && i > 0 && i + 1 < p.length) {
            var a = int.parse(p[i - 1]), b = int.parse(p[i + 1]);
            for (var x = a; x <= b; x++) {
              hides.add(x);
            }
          } else if (int.tryParse(p[i]) case var x?) {
            hides.add(x);
          }
        }
      }
    }
    return WearMesh(item, refs, weights, offsets, scales,
        Float32List.fromList(uvs), Uint32List.fromList(corners), hides);
  }

  /// fit is the piece's vertices on a body whose vertices are [body].
  Float32List fit(Float32List body) {
    var scale = [1.0, 1.0, 1.0];
    for (var a = 0; a < 3; a++) {
      if (scales[a] case (var i, var j, var den) when den != 0) {
        scale[a] = (body[i * 3 + a] - body[j * 3 + a]).abs() / den;
      }
    }
    var n = vertexCount;
    var out = Float32List(n * 3);
    for (var v = 0; v < n; v++) {
      for (var a = 0; a < 3; a++) {
        var s = 0.0;
        for (var k = 0; k < 3; k++) {
          var w = weights[v * 3 + k];
          if (w == 0) continue;
          s += body[refs[v * 3 + k] * 3 + a] * w;
        }
        out[v * 3 + a] = s + offsets[v * 3 + a] * scale[a];
      }
    }
    return out;
  }
}

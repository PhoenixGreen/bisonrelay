import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_decal.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_wear.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_decal.dart makes a decal's shape: the triangles of the surface it lies
// on (the skin, or a piece of clothing) that face it within its square, lifted
// off the surface a hair, with the picture laid across them as if projected
// from in front. Bound to the same bones as the surface, so it bends and
// moves with it, and shaped with the body. Plain Dart, tested without a GPU.

/// DecalSurface is what a decal can lie on: vertices, their triangles, and
/// whether the vertices are numbered as the skin's are -- so each is known
/// to be on an arm, a leg, the body.
class DecalSurface {
  final VrmVertices vertices;
  final Uint32List triangles;
  final bool likeSkin;

  /// lift is how far over the surface the decal lies.
  final double lift;
  const DecalSurface(this.vertices, this.triangles,
      {this.likeSkin = true, this.lift = 0.0008});
}

/// DecalFrame is where a decal lies: its middle on the surface, the way it
/// faces, its up and its side, and its width.
class DecalFrame {
  final vm.Vector3 centre, normal, up, side;
  final double size;
  const DecalFrame(this.centre, this.normal, this.up, this.side, this.size);
}

/// decalFrame is where [d] lies on [w]'s body, or null for a body without
/// the bones to place it by.
DecalFrame? decalFrame(VrmWardrobe w, CharacterDecal d, DecalSurface s) {
  final P = w.rig.data.bindPos, face = w.rig.face;
  final F = face?.fwd ?? 1;
  vm.Vector3? at(String b) => P[b];
  final head = at(VroidBone.head);
  final (a, b) = switch (d.area) {
    DecalArea.torso => (at(VroidBone.hips), at(VroidBone.neck)),
    DecalArea.neck => (at(VroidBone.neck), head),
    DecalArea.head => (
        head,
        head == null
            ? null
            : vm.Vector3(head.x, face?.headTop.y ?? head.y + 0.2, head.z)
      ),
    DecalArea.leftArm => (at(VroidBone.upperArm('L')), at(VroidBone.hand('L'))),
    DecalArea.rightArm => (
        at(VroidBone.upperArm('R')),
        at(VroidBone.hand('R'))
      ),
    DecalArea.leftLeg => (at(VroidBone.upperLeg('L')), at(VroidBone.foot('L'))),
    DecalArea.rightLeg => (
        at(VroidBone.upperLeg('R')),
        at(VroidBone.foot('R'))
      ),
  };
  if (a == null || b == null || (b - a).length2 < 1e-10) return null;
  final t = (b - a).normalized();
  // Forward, square to the line: where "around" turns from.
  final f0 = vm.Vector3(0, 0, F);
  var f = f0 - t * f0.dot(t);
  if (f.length2 < 1e-8) f = vm.Vector3(1, 0, 0) - t * t.x;
  f.normalize();
  final th = d.around * math.pi;
  final n = (f * math.cos(th) + t.cross(f) * math.sin(th)).normalized();
  final p = a + (b - a) * d.along;
  final height = face?.headTop.y ?? 1.5;
  final size = d.size * height;
  // The surface where a line out from [p] along [n] meets it: the vertex
  // nearest that line, furthest out along it.
  final pos = s.vertices.positions;
  final reach = math.max(0.012, size * 0.2);
  vm.Vector3? hit;
  var best = double.negativeInfinity;
  for (var i = 0; i < s.vertices.count; i++) {
    if (!_inArea(w, s, d.area, i)) continue;
    final v = vm.Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]) - p;
    final out = v.dot(n);
    if (out < 0) continue;
    if ((v - n * out).length > reach) continue;
    if (out > best) {
      best = out;
      hit = v + p;
    }
  }
  final centre = hit ?? p;
  var up = t - n * t.dot(n);
  if (up.length2 < 1e-8) up = vm.Vector3(0, 1, 0);
  up.normalize();
  var side = up.cross(n).normalized();
  final ph = d.turn * math.pi;
  final up2 = up * math.cos(ph) + side * math.sin(ph);
  final side2 = side * math.cos(ph) - up * math.sin(ph);
  return DecalFrame(centre, n, up2, side2, size);
}

/// _inArea is whether vertex [i] of [s] is on [area] of the body: always,
/// for a surface not numbered as the skin is.
bool _inArea(VrmWardrobe w, DecalSurface s, DecalArea area, int i) {
  if (!s.likeSkin || i >= w.group.length) return true;
  var g = w.groupAt(i);
  final x = s.vertices.positions[i * 3];
  // The body's own clothes are in the skin's mesh but not grouped as it is:
  // their part of the body is the bone they follow most.
  if (g == BodyGroup.other) g = _groupOfBone(w, s, i);
  final arm = g == BodyGroup.armU ||
      g == BodyGroup.armF ||
      g == BodyGroup.hand ||
      g == BodyGroup.finger;
  final leg = g == BodyGroup.legU || g == BodyGroup.legL || g == BodyGroup.foot;
  return switch (area) {
    DecalArea.torso => g == BodyGroup.torso,
    DecalArea.neck => g == BodyGroup.neck || g == BodyGroup.torso,
    DecalArea.head => g == BodyGroup.head || g == BodyGroup.neck,
    // VRM 1 puts the left side at +x.
    DecalArea.leftArm => arm && x > 0,
    DecalArea.rightArm => arm && x < 0,
    DecalArea.leftLeg => leg && x > 0,
    DecalArea.rightLeg => leg && x < 0,
  };
}

/// makeDecal is [d]'s shape on [s], or null where it lies on nothing.
GarmentMesh? makeDecal(VrmWardrobe w, CharacterDecal d, DecalSurface s) {
  final fr = decalFrame(w, d, s);
  if (fr == null) return null;
  final vs = s.vertices, pos = vs.positions, nrm = vs.normals;
  final n = vs.count, half = fr.size / 2 * 1.15, depth = fr.size * 0.75 + 0.02;
  // keep is a vertex in the decal's square; may, one a triangle reaching
  // into it may bring along: facing it, on its part of the body, and near.
  final keep = Uint8List(n), may = Uint8List(n);
  final uv = Float32List(n * 2);
  for (var i = 0; i < n; i++) {
    final v =
        vm.Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]) - fr.centre;
    final x = v.dot(fr.side), y = v.dot(fr.up), z = v.dot(fr.normal);
    uv[i * 2] = x / fr.size + 0.5;
    uv[i * 2 + 1] = 0.5 - y / fr.size;
    if (x.abs() > half * 2 || y.abs() > half * 2 || z.abs() > depth) continue;
    // Only what faces the decal: not the far side of an arm.
    final facing = nrm[i * 3] * fr.normal.x +
        nrm[i * 3 + 1] * fr.normal.y +
        nrm[i * 3 + 2] * fr.normal.z;
    if (facing < 0.05) continue;
    if (!_inArea(w, s, d.area, i)) continue;
    may[i] = 1;
    if (x.abs() <= half && y.abs() <= half) keep[i] = 1;
  }
  final tris = <int>[];
  final t = s.triangles;
  for (var k = 0; k + 2 < t.length; k += 3) {
    // Any triangle reaching into the square, not only those wholly in it:
    // where the surface curves away, a triangle with a corner outside left
    // a gap in the picture. What lies past the picture is clear.
    final a = t[k], b = t[k + 1], c = t[k + 2];
    if ((keep[a] == 1 || keep[b] == 1 || keep[c] == 1) &&
        may[a] == 1 &&
        may[b] == 1 &&
        may[c] == 1) {
      tris.addAll([t[k], t[k + 1], t[k + 2]]);
    }
  }
  if (tris.isEmpty) return null;
  final lifted = Float32List(n * 3);
  for (var i = 0; i < n * 3; i++) {
    lifted[i] = pos[i] + nrm[i] * s.lift;
  }
  return GarmentMesh(
    VrmVertices(
      positions: lifted,
      normals: Float32List.fromList(nrm),
      uv0: uv,
      uv1: Float32List(n * 2),
      colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
      tangents: Float32List(n * 4),
      joints: vs.joints,
      weights: vs.weights,
      skinned: vs.skinned,
    ),
    Uint32List.fromList(tris),
  );
}

/// decalPicture is [rgba] ([w] by [h]) as [d] draws it, with a clear pixel
/// round its edge so nothing past the picture is drawn. RGBA, with its
/// width and height.
(Uint8List, int, int) decalPicture(
    Uint8List rgba, int w, int h, CharacterDecal d) {
  final pw = w + 4, ph = h + 4;
  final out = Uint8List(pw * ph * 4);
  final ink = [(d.ink >> 16) & 0xff, (d.ink >> 8) & 0xff, d.ink & 0xff];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4, o = ((y + 2) * pw + x + 2) * 4;
      var r = rgba[i].toDouble(),
          g = rgba[i + 1].toDouble(),
          b = rgba[i + 2].toDouble();
      var a = rgba[i + 3] / 255;
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      switch (d.mode) {
        case "tattoo":
          // Muted, darkened and a little blue-green, as ink under skin is.
          r = (l + (r - l) * 0.5) * 0.8 + 0.15 * 26;
          g = (l + (g - l) * 0.5) * 0.8 + 0.15 * 31;
          b = (l + (b - l) * 0.5) * 0.8 + 0.15 * 41;
          a *= 0.9;
        case "faded":
          r = l + (r - l) * 0.6;
          g = l + (g - l) * 0.6;
          b = l + (b - l) * 0.6;
          r += (255 - r) * 0.15;
          g += (255 - g) * 0.15;
          b += (255 - b) * 0.15;
          a *= 0.55;
        case "ink":
          // The dark of the picture in the ink, the light of it left clear.
          r = ink[0].toDouble();
          g = ink[1].toDouble();
          b = ink[2].toDouble();
          a *= 1 - l / 255;
      }
      out[o] = r.round().clamp(0, 255);
      out[o + 1] = g.round().clamp(0, 255);
      out[o + 2] = b.round().clamp(0, 255);
      out[o + 3] = (a * d.opacity * 255).round().clamp(0, 255);
    }
  }
  return (out, pw, ph);
}

/// _groupOfBone is the part of the body vertex [i] of [s] follows most, by
/// its bone's name.
BodyGroup _groupOfBone(VrmWardrobe w, DecalSurface s, int i) {
  final vs = s.vertices;
  if (!vs.skinned || i >= vs.domBone.length) return BodyGroup.torso;
  final names = w.body.jointNames, b = vs.domBone[i];
  final name = b >= 0 && b < names.length ? names[b] : "";
  if (name.contains("Hand") ||
      name.contains("Thumb") ||
      name.contains("Index") ||
      name.contains("Middle") ||
      name.contains("Ring") ||
      name.contains("Little")) {
    return BodyGroup.hand;
  }
  if (name.contains("LowerArm")) return BodyGroup.armF;
  if (name.contains("UpperArm") || name.contains("Shoulder")) {
    return BodyGroup.armU;
  }
  if (name.contains("Foot") || name.contains("Toe")) return BodyGroup.foot;
  if (name.contains("LowerLeg")) return BodyGroup.legL;
  if (name.contains("UpperLeg")) return BodyGroup.legU;
  if (name.contains("Neck")) return BodyGroup.neck;
  if (name.contains("Head")) return BodyGroup.head;
  return BodyGroup.torso;
}

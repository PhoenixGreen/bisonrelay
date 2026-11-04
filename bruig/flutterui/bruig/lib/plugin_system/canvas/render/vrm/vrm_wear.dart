import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_outfit.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_shape.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_wear.dart makes clothes to fit a VRoid body from the body itself: the
// skin where a garment covers it, cut along the garment's lines and stood
// off the skin a little, bound to the same bones. So a garment fits whatever
// shape the body is given and moves with it. A skirt is the one garment made
// of its own shape: a cone falling from the waist, clear of the hips.
//
// Also here: the body's own sleeves and trouser legs cut shorter, the
// patterns garments are drawn in, and the body's skin painted again where
// clothes come off -- VRoid paints underwear, socks and even whole suits on
// the skin under the clothes it models.
//
// Plain Dart, so it is tested without a GPU; vrm_scene.dart draws it.

/// BodyGroup is which part of the body a vertex is on, from the bone it
/// follows most.
enum BodyGroup {
  other,
  torso,
  neck,
  head,
  armU,
  armF,
  hand,
  finger,
  legU,
  legL,
  foot
}

BodyGroup bodyGroupOf(String bone) {
  if (RegExp(r'Thumb|Index|Middle|Ring|Little').hasMatch(bone)) {
    return RegExp(r'[23]$').hasMatch(bone) ? BodyGroup.finger : BodyGroup.hand;
  }
  if (bone.contains('Hand')) return BodyGroup.hand;
  if (bone.contains('LowerArm')) return BodyGroup.armF;
  if (bone.contains('UpperArm')) return BodyGroup.armU;
  if (RegExp(r'Toe|Foot').hasMatch(bone)) return BodyGroup.foot;
  if (bone.contains('LowerLeg')) return BodyGroup.legL;
  if (bone.contains('UpperLeg')) return BodyGroup.legU;
  if (bone.contains('Neck')) return BodyGroup.neck;
  if (RegExp(r'Head|Face|Eye|Hair').hasMatch(bone)) return BodyGroup.head;
  if (RegExp(r'Hips|Spine|Chest|Bust|Shoulder').hasMatch(bone)) {
    return BodyGroup.torso;
  }
  return BodyGroup.other;
}

bool _isArm(BodyGroup g) =>
    g.index >= BodyGroup.armU.index && g.index <= BodyGroup.finger.index;
bool _isLeg(BodyGroup g) => g.index >= BodyGroup.legU.index;

/// ClothesLines are the heights clothes are cut at, from the bones: the
/// sole of the foot, the ankle, the crotch, the top of the hips, the waist,
/// the chest and the neck.
class ClothesLines {
  final double sole,
      ankle,
      ankleZ,
      fwd,
      crotch,
      hipTop,
      waist,
      chest,
      neck,
      chestZ,
      shoulderX;

  /// tuck is the top of a waistband a top is worn over, which it stands off
  /// further from; -infinity for none.
  final double tuck;
  const ClothesLines(
      this.sole,
      this.ankle,
      this.ankleZ,
      this.fwd,
      this.crotch,
      this.hipTop,
      this.waist,
      this.chest,
      this.neck,
      this.chestZ,
      this.shoulderX,
      this.tuck);
}

/// covers is whether [w], worn in [slot], covers a point on the body: on
/// [g], [t] of the way down its limb, at x, y, z.
bool covers(WearSlot slot, Garment w, BodyGroup g, double t, double x, double y,
    double z, ClothesLines L) {
  final torso = g == BodyGroup.torso, front = L.fwd * (z - L.chestZ) > 0;
  final briefs = (torso && y < L.hipTop - 0.01 && y > L.crotch - 0.06) ||
      (g == BodyGroup.legU && t < 0.06);
  bool band(double lo, double hi) => torso && y >= lo && y <= hi;
  switch (slot) {
    case WearSlot.underwear:
      return switch (w.kind) {
        'set' => briefs || band(L.chest - 0.075, L.chest + 0.02),
        'sports' => briefs || band(L.chest - 0.095, L.chest + 0.05),
        'swim' => band(L.crotch - 0.06, L.chest + 0.035) ||
            (g == BodyGroup.legU && t < 0.05),
        'boxers' => band(L.crotch - 0.06, L.hipTop + 0.01) ||
            (g == BodyGroup.legU && t < 0.24),
        'briefs' => briefs,
        _ => false,
      };
    case WearSlot.top:
      if (g == BodyGroup.armU || g == BodyGroup.armF) {
        if (w.kind == 'tank') return false;
        final sleeve = w.kind == 'long' || w.kind == 'turtle'
            ? 0.97
            : 0.06 + 0.91 * w.sleeves;
        return t < sleeve;
      }
      if (g == BodyGroup.neck) return w.kind == 'turtle' && y < L.neck + 0.07;
      if (!torso) return false;
      final hem = w.kind == 'crop'
          ? L.waist + 0.1 - 0.05 * w.hem
          : L.waist + 0.08 - w.hem * (L.waist + 0.08 - (L.crotch - 0.03));
      if (y < hem) return false;
      if (w.kind == 'tank' &&
          y > L.chest + 0.04 &&
          !(x.abs() > 0.42 * L.shoulderX && x.abs() < 0.68 * L.shoulderX)) {
        return false;
      }
      if (w.kind != 'turtle') {
        final top = L.neck - 0.012, d = w.depth;
        if (y > top) return false;
        if (w.neckline == 'scoop' &&
            front &&
            y > top - 0.02 - d * 0.12 &&
            x.abs() < 0.05 + d * 0.05) {
          return false;
        }
        if (w.neckline == 'v' &&
            front &&
            x.abs() < (y - (top - 0.03 - d * 0.16)) * 0.8) {
          return false;
        }
        if (w.neckline == 'boat' && y > top - 0.012 - d * 0.04) return false;
      }
      return true;
    case WearSlot.bottom:
      final waistTop =
          L.crotch + 0.07 + w.rise * (L.waist + 0.02 - L.crotch - 0.07);
      if (torso) return y < waistTop && y > L.crotch - 0.08;
      if (g == BodyGroup.legU || g == BodyGroup.legL) {
        return t <
            (w.kind == 'shorts'
                ? 0.1 + w.length * 0.32
                : 0.3 + w.length * 0.68);
      }
      return false;
    case WearSlot.legwear:
      if (g == BodyGroup.foot) return true;
      return switch (w.kind) {
        'ankle' => g == BodyGroup.legL && t > 0.88,
        'knee' => g == BodyGroup.legL && t > 0.55,
        'thigh' => (g == BodyGroup.legU && t > 0.25) || g == BodyGroup.legL,
        'tights' => briefs ||
            g == BodyGroup.legU ||
            g == BodyGroup.legL ||
            (torso && y < L.hipTop + 0.02 && y > L.crotch - 0.08),
        _ => false,
      };
    case WearSlot.shoes:
      // The sole all round; above it, what each kind covers.
      if (g != BodyGroup.foot && g != BodyGroup.legL) return false;
      if (g == BodyGroup.foot && y < L.sole + 0.004) return true;
      return switch (w.kind) {
        'trainers' => g == BodyGroup.foot || t > 0.96,
        'flats' => g == BodyGroup.foot &&
            y < L.ankle - 0.012 &&
            (L.fwd * (z - L.ankleZ) > 0.03 || y < L.sole + 0.03),
        'sandals' => g == BodyGroup.foot &&
            ((L.fwd * (z - L.ankleZ) - 0.07).abs() < 0.012 ||
                (y > L.ankle - 0.02 && y < L.ankle - 0.005)),
        'ankle' => g == BodyGroup.foot || t > 0.84,
        'knee' => g == BodyGroup.foot || t > 0.36,
        _ => false,
      };
    case WearSlot.gloves:
      if (w.kind == 'fingerless') return g == BodyGroup.hand;
      if (g == BodyGroup.hand || g == BodyGroup.finger) return true;
      return w.kind == 'long' && g == BodyGroup.armF && t > 0.6;
  }
}

/// _layer is how far each slot stands off the skin, so what goes on later
/// is over what went on before.
const Map<WearSlot, double> _layer = {
  WearSlot.underwear: 0.0018,
  WearSlot.legwear: 0.0026,
  WearSlot.gloves: 0.0022,
  WearSlot.bottom: 0.0045,
  WearSlot.top: 0.0068,
  WearSlot.shoes: 0.0062,
};

/// GarmentMesh is a garment's shape: vertices bound to the body's bones
/// (indices into its skin's joints), and its triangles.
class GarmentMesh {
  final VrmVertices vertices;
  final Uint32List indices;

  /// doubleSided is drawn from inside as well: a skirt is seen up into.
  final bool doubleSided;
  const GarmentMesh(this.vertices, this.indices, {this.doubleSided = false});
}

/// VrmWardrobe is one body ready to be dressed: its body mesh, where each
/// of its vertices is on the body, and the lines clothes are cut by.
class VrmWardrobe {
  final VrmShapeRig rig;

  /// body is the mesh with the skin, and the body's own clothes.
  final VrmMeshNode body;
  final VrmVertices skin;

  /// group and along are, for each of the body's vertices, the part of the
  /// body it is on, and how far down its arm or leg.
  final Uint8List group;
  final Float32List along;

  /// waistband is the top of the body's own trousers, or -infinity.
  final double waistband;

  VrmWardrobe._(
      this.rig, this.body, this.skin, this.group, this.along, this.waistband);

  /// of is [rig]'s wardrobe, or null for a body without skin and bones to
  /// make clothes from.
  static VrmWardrobe? of(VrmShapeRig rig) {
    final data = rig.data;
    VrmMeshNode? body;
    for (final m in data.meshes) {
      if (m.region == VrmRegion.body &&
          m.primitives
              .any((p) => p.part == VrmPart.skin && p.vertices.skinned)) {
        body = m;
      }
    }
    if (body == null) return null;
    final skin = body.primitives
        .firstWhere((p) => p.part == VrmPart.skin && p.vertices.skinned)
        .vertices;
    final P = data.bindPos;
    for (final b in [
      VroidBone.hips,
      VroidBone.spine,
      VroidBone.neck,
      VroidBone.upperLeg('L'),
      VroidBone.lowerLeg('L'),
      VroidBone.upperArm('L')
    ]) {
      if (P[b] == null) return null;
    }
    final n = skin.count;
    final group = Uint8List(n), along = Float32List(n);
    for (var i = 0; i < n; i++) {
      final j = skin.domBone[i];
      final name = j < body.jointNames.length ? body.jointNames[j] : '';
      final g = bodyGroupOf(name);
      group[i] = g.index;
      final sd = name.contains('_L_') ? 'L' : 'R';
      vm.Vector3? a, b;
      if (_isArm(g)) {
        a = P[VroidBone.upperArm(sd)];
        b = P[VroidBone.hand(sd)];
      } else if (_isLeg(g)) {
        a = P[VroidBone.upperLeg(sd)];
        b = P[VroidBone.foot(sd)];
      }
      if (a != null && b != null) {
        final ab = b - a, l2 = ab.length2 == 0 ? 1.0 : ab.length2;
        final x = skin.positions[i * 3] - a.x,
            y = skin.positions[i * 3 + 1] - a.y,
            z = skin.positions[i * 3 + 2] - a.z;
        along[i] = ((x * ab.x + y * ab.y + z * ab.z) / l2).clamp(0.0, 1.2);
      }
    }
    var band = double.negativeInfinity;
    for (final p in body.primitives) {
      if (p.part != VrmPart.bottom) continue;
      for (final i in p.used) {
        band = math.max(band, p.vertices.positions[i * 3 + 1]);
      }
    }
    return VrmWardrobe._(rig, body, skin, group, along, band);
  }

  /// lines are the lines clothes are cut by; with [overOwnBottom] a top
  /// stands off the body's own waistband.
  ClothesLines lines({bool overOwnBottom = false}) {
    final P = rig.data.bindPos;
    final hips = P[VroidBone.hips]!,
        spine = P[VroidBone.spine]!,
        neck = P[VroidBone.neck]!;
    final chest = P[VroidBone.upperChest] ?? P[VroidBone.chest] ?? spine;
    final legTop = P[VroidBone.upperLeg('L')]!,
        knee = P[VroidBone.lowerLeg('L')]!;
    final ankle = P[VroidBone.foot('L')] ?? knee;
    return ClothesLines(
      0.016 * (legTop.y.abs() / 0.95),
      ankle.y,
      ankle.z,
      rig.face?.fwd ?? 1,
      legTop.y - (legTop.y - knee.y) * 0.1,
      hips.y + 0.03,
      spine.y + 0.03,
      chest.y,
      neck.y,
      chest.z,
      P[VroidBone.upperArm('L')]!.x.abs(),
      overOwnBottom ? waistband : double.negativeInfinity,
    );
  }

  bool get hasOwnBottom => waistband.isFinite;

  bool hasOwn(WearSlot slot) =>
      body.primitives.any((p) => p.part.name == slot.name);

  BodyGroup groupAt(int i) => BodyGroup.values[group[i]];

  /// offset is how far [w] stands off the skin in [slot].
  double offset(WearSlot slot, Garment w) =>
      _layer[slot]! +
      (slot == WearSlot.top ? w.fit * 0.022 : 0) +
      (slot == WearSlot.bottom ? w.fit * 0.016 : 0) +
      (slot == WearSlot.bottom && w.kind == 'leggings' ? -0.002 : 0);

  /// make is [w] made to fit for [slot], or null when it covers nothing. A
  /// skirt's waistband stands [over] off the skin, to go over a top.
  GarmentMesh? make(WearSlot slot, Garment w, ClothesLines L,
      {double over = 0, bool shod = false}) {
    if (!w.made) return null;
    final repeat = 4 + (1 - w.scale) * 10;
    if (slot == WearSlot.bottom && w.kind == 'skirt') {
      return _skirt(w, L, repeat, over);
    }
    final off = offset(slot, w);
    final o = skin.positions, n = skin.count;
    final keep = Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (covers(slot, w, groupAt(i), along[i], o[i * 3], o[i * 3 + 1],
          o[i * 3 + 2], L)) {
        keep[i] = 1;
      }
    }
    // Where along o->p the garment starts, judged as p's part of the body.
    double cutAt(int a, int b) {
      var lo = 0.0, hi = 1.0;
      for (var k = 0; k < 7; k++) {
        final f = (lo + hi) / 2, g = 1 - f;
        final inside = covers(
            slot,
            w,
            groupAt(b),
            along[a] * g + along[b] * f,
            o[a * 3] * g + o[b * 3] * f,
            o[a * 3 + 1] * g + o[b * 3 + 1] * f,
            o[a * 3 + 2] * g + o[b * 3 + 2] * f,
            L);
        if (inside) {
          hi = f;
        } else {
          lo = f;
        }
      }
      return hi;
    }

    // Triangles partly inside are kept, and each point outside is drawn in
    // to where the cut crosses its edges: a hem along the cut, not a
    // saw-tooth along the triangles.
    final out = <int>[];
    final pull = <int, List<double>>{};
    for (final p in body.primitives) {
      if (p.part != VrmPart.skin || p.vertices != skin) continue;
      final idx = p.indices;
      for (var k = 0; k + 2 < idx.length; k += 3) {
        final tri = [idx[k], idx[k + 1], idx[k + 2]];
        final inside = keep[tri[0]] + keep[tri[1]] + keep[tri[2]];
        if (inside == 0) continue;
        out.addAll(tri);
        if (inside == 3) continue;
        for (final a in tri) {
          if (keep[a] == 1) continue;
          final acc = pull.putIfAbsent(a, () => [0, 0, 0, 0]);
          for (final b in tri) {
            if (keep[b] == 0) continue;
            final f = math.min(0.9, cutAt(a, b));
            for (var c = 0; c < 3; c++) {
              acc[c] += (1 - f) * o[a * 3 + c] + f * o[b * 3 + c];
            }
            acc[3]++;
          }
        }
      }
    }
    if (out.isEmpty) return null;
    final nrm = skin.normals;
    final pos = Float32List(n * 3), uv = Float32List(n * 2);
    double offAt(double y) =>
        off +
        (slot == WearSlot.shoes && y < L.sole + 0.004 ? 0.004 : 0) +
        (slot == WearSlot.top && L.tuck.isFinite
            ? 0.014 * ((L.tuck + 0.05 - y) / 0.04).clamp(0.0, 1.0)
            : 0);
    for (var i = 0; i < n; i++) {
      final x = o[i * 3], y = o[i * 3 + 1], z = o[i * 3 + 2], d = offAt(y);
      pos[i * 3] = x + nrm[i * 3] * d;
      pos[i * 3 + 1] = y + nrm[i * 3 + 1] * d;
      pos[i * 3 + 2] = z + nrm[i * 3 + 2] * d;
      if (slot == WearSlot.shoes) {
        uv[i * 2] = y < L.sole + 0.004 ? 0.75 : 0.25;
        uv[i * 2 + 1] = 0.5;
      } else {
        final arm = _isArm(groupAt(i));
        uv[i * 2] = (arm ? y + z : x + z * 0.7) * repeat;
        uv[i * 2 + 1] = (arm ? x.abs() : y) * repeat;
      }
    }
    for (final e in pull.entries) {
      final a = e.key, acc = e.value, d = offAt(acc[1] / acc[3]);
      for (var c = 0; c < 3; c++) {
        pos[a * 3 + c] = acc[c] / acc[3] + nrm[a * 3 + c] * d;
      }
    }
    return GarmentMesh(
      VrmVertices(
        positions: pos,
        normals: Float32List.fromList(nrm),
        uv0: uv,
        uv1: Float32List(n * 2),
        colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
        tangents: Float32List(n * 4),
        joints: skin.joints,
        weights: skin.weights,
        skinned: true,
      ),
      // Socks inside shoes are not drawn, as the skin is not.
      slot == WearSlot.legwear && shod
          ? withoutFeet(Uint32List.fromList(out))
          : Uint32List.fromList(out),
    );
  }

  /// _skirt is a cone falling from the waist, flared and pleated, pushed
  /// out wherever the body under it reaches further, and bound to the hips
  /// and, more towards its hem, the legs.
  GarmentMesh? _skirt(Garment w, ClothesLines L, double repeat, double over) {
    final P = rig.data.bindPos;
    int joint(String name) => math.max(0, body.jointNames.indexOf(name));
    final hipsI = joint(VroidBone.hips),
        lI = joint(VroidBone.upperLeg('L')),
        rI = joint(VroidBone.upperLeg('R'));
    final lX = P[VroidBone.upperLeg('L')]!.x;
    final top = L.crotch + 0.07 + w.rise * (L.waist + 0.02 - L.crotch - 0.07);
    final len = 0.12 + w.length * 0.5;
    final o = skin.positions;
    final skinVerts = <int>{
      for (final p in body.primitives)
        if (p.part == VrmPart.skin && p.vertices == skin) ...p.used,
    };
    var cz = 0.0, cnt = 0;
    for (final i in skinVerts) {
      if ((o[i * 3 + 1] - top).abs() < 0.012) {
        cz += o[i * 3 + 2];
        cnt++;
      }
    }
    cz /= math.max(1, cnt);
    var rx = 0.05, rz = 0.05;
    for (final i in skinVerts) {
      if ((o[i * 3 + 1] - top).abs() < 0.012) {
        rx = math.max(rx, o[i * 3].abs());
        rz = math.max(rz, (o[i * 3 + 2] - cz).abs());
      }
    }
    rx += 0.01 + over;
    rz += 0.01 + over;
    final flare = 1.12 + w.flare * 1.3;
    const segs = 72, rows = 16;
    // How far out the body reaches at each height and angle under the
    // skirt, so it falls from the hips and the bum, not through them.
    final reach = List.generate(rows + 1, (_) => Float64List(segs));
    for (final i in skinVerts) {
      final x = o[i * 3], y = o[i * 3 + 1], z = o[i * 3 + 2] - cz;
      final r = math.sqrt(x * x + z * z);
      if (y > top + 0.01 || y < top - len - 0.01 || r > 0.35) continue;
      final row = ((top - y) / len * rows).round().clamp(0, rows);
      final j =
          ((math.atan2(x, z) / (math.pi * 2) * segs).round() % segs + segs) %
              segs;
      reach[row][j] = math.max(reach[row][j], r);
    }
    final need = Float64List(segs);
    final pos = <double>[],
        uv = <double>[],
        joints = <double>[],
        weights = <double>[],
        ind = <int>[];
    for (var r = 0; r <= rows; r++) {
      final s = r / rows,
          y = top - len * s,
          k = 1 + (flare - 1) * math.pow(s, 0.85);
      for (var j = 0; j < segs; j++) {
        need[j] = math.max(
            need[j],
            math.max(
                    reach[r][j],
                    math.max(reach[r][(j + 1) % segs],
                        reach[r][(j + segs - 1) % segs])) +
                0.012 +
                over);
      }
      for (var j = 0; j <= segs; j++) {
        final a = j / segs * math.pi * 2,
            pleat = 1 + w.pleats * 0.07 * s * math.cos(a * 18);
        final ex = math.sin(a) * rx * k, ez = math.cos(a) * rz * k;
        final f = math.max(
            1.0, need[j % segs] / math.max(1e-9, math.sqrt(ex * ex + ez * ez)));
        final x = ex * f * pleat, z = cz + ez * f * pleat;
        pos.addAll([x, y, z]);
        uv.addAll([j / segs * 2 * repeat, s * 0.6 * repeat]);
        final legW =
            math.min(0.6, 0.7 * s) * math.min(1.0, math.sin(a).abs() * 1.3);
        joints.addAll(
            [hipsI.toDouble(), (x.sign == lX.sign ? lI : rI).toDouble(), 0, 0]);
        weights.addAll([1 - legW, legW, 0, 0]);
      }
    }
    for (var r = 0; r < rows; r++) {
      for (var j = 0; j < segs; j++) {
        final a = r * (segs + 1) + j, b = a + segs + 1;
        ind.addAll([a, b, a + 1, b, b + 1, a + 1]);
      }
    }
    final n = pos.length ~/ 3;
    final p32 = Float32List.fromList(pos);
    final nrm = Float32List(n * 3);
    for (var t = 0; t < ind.length; t += 3) {
      final i0 = ind[t], i1 = ind[t + 1], i2 = ind[t + 2];
      final ax = p32[i1 * 3] - p32[i0 * 3],
          ay = p32[i1 * 3 + 1] - p32[i0 * 3 + 1],
          az = p32[i1 * 3 + 2] - p32[i0 * 3 + 2];
      final bx = p32[i2 * 3] - p32[i0 * 3],
          by = p32[i2 * 3 + 1] - p32[i0 * 3 + 1],
          bz = p32[i2 * 3 + 2] - p32[i0 * 3 + 2];
      final c = [ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx];
      for (final i in [i0, i1, i2]) {
        for (var k = 0; k < 3; k++) {
          nrm[i * 3 + k] += c[k];
        }
      }
    }
    for (var i = 0; i < n; i++) {
      var x = nrm[i * 3], y = nrm[i * 3 + 1], z = nrm[i * 3 + 2];
      final l = math.max(1e-12, math.sqrt(x * x + y * y + z * z));
      // Outward, away from the middle of the skirt.
      final s = x * p32[i * 3] + z * (p32[i * 3 + 2] - cz) < 0 ? -1 : 1;
      nrm[i * 3] = s * x / l;
      nrm[i * 3 + 1] = s * y / l;
      nrm[i * 3 + 2] = s * z / l;
    }
    return GarmentMesh(
      VrmVertices(
        positions: p32,
        normals: nrm,
        uv0: Float32List.fromList(uv),
        uv1: Float32List(n * 2),
        colors: Float32List(n * 4)..fillRange(0, n * 4, 1),
        tangents: Float32List(n * 4),
        joints: Float32List.fromList(joints),
        weights: Float32List.fromList(weights),
        skinned: true,
      ),
      Uint32List.fromList(ind),
      doubleSided: true,
    );
  }

  /// cut is [p]'s triangles -- the body's own top or bottom -- with the
  /// sleeves or trouser legs cut to [keep] of their length.
  Uint32List cut(VrmPrimitive p, double keep) {
    if (keep >= 0.999 || p.vertices != skin) return p.indices;
    final top = p.part == VrmPart.top;
    final lim = top ? 0.06 + 0.91 * keep : 0.1 + 0.88 * keep;
    bool gone(int i) =>
        (top ? _isArm(groupAt(i)) : _isLeg(groupAt(i))) && along[i] > lim;
    final idx = p.indices, out = <int>[];
    for (var k = 0; k + 2 < idx.length; k += 3) {
      if (!gone(idx[k]) && !gone(idx[k + 1]) && !gone(idx[k + 2])) {
        out.addAll([idx[k], idx[k + 1], idx[k + 2]]);
      }
    }
    return Uint32List.fromList(out);
  }

  /// withoutFeet is [p]'s triangles -- the skin's, or socks' -- without
  /// those on the feet, for when shoes are on: what is inside a shoe is not
  /// drawn, so nothing can show through it however the foot is shaped.
  Uint32List withoutFeet(Uint32List idx) {
    bool foot(int i) => i < group.length && groupAt(i) == BodyGroup.foot;
    final out = <int>[];
    for (var k = 0; k + 2 < idx.length; k += 3) {
      if (!(foot(idx[k]) && foot(idx[k + 1]) && foot(idx[k + 2]))) {
        out.addAll([idx[k], idx[k + 1], idx[k + 2]]);
      }
    }
    return Uint32List.fromList(out);
  }

  /// skinTriangles are the skin's triangles in its picture, each with
  /// where it is: the head, the legs below the top of the thigh (which
  /// legwear and shoes cover), or the rest; and its part of the body.
  List<({Float32List uv, String where, BodyGroup group})> skinTriangles() {
    final out = <({Float32List uv, String where, BodyGroup group})>[];
    final uv0 = skin.uv0;
    for (final p in body.primitives) {
      if (p.part != VrmPart.skin || p.vertices != skin) continue;
      final idx = p.indices;
      for (var k = 0; k + 2 < idx.length; k += 3) {
        final a = idx[k], b = idx[k + 1], c = idx[k + 2];
        final g = groupAt(a), lt = (along[a] + along[b] + along[c]) / 3;
        final where = g == BodyGroup.legL ||
                g == BodyGroup.foot ||
                (g == BodyGroup.legU && lt > 0.22)
            ? 'lower'
            : g == BodyGroup.head
                ? 'head'
                : 'upper';
        out.add((
          uv: Float32List.fromList([
            uv0[a * 2],
            uv0[a * 2 + 1],
            uv0[b * 2],
            uv0[b * 2 + 1],
            uv0[c * 2],
            uv0[c * 2 + 1]
          ]),
          where: where,
          group: g,
        ));
      }
    }
    return out;
  }
}

/// garmentPicture is what [w] is drawn in: its pattern, 128 pixels square
/// and repeated, or for shoes the upper's colour and the sole's side by
/// side. RGBA, with its width and height.
(Uint8List, int, int) garmentPicture(WearSlot slot, Garment w) {
  if (slot == WearSlot.shoes) {
    const W = 64, H = 8;
    final px = Uint8List(W * H * 4);
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        _put(px, (y * W + x) * 4, x < 32 ? w.colour : w.sole, 1);
      }
    }
    return (px, W, H);
  }
  const N = 128;
  final px = Uint8List(N * N * 4);
  for (var i = 0; i < N * N; i++) {
    _put(px, i * 4, w.colour, 1);
  }
  void rect(int x0, int y0, int w0, int h0, [double alpha = 1]) {
    for (var y = y0; y < y0 + h0 && y < N; y++) {
      for (var x = x0; x < x0 + w0 && x < N; x++) {
        _put(px, (y * N + x) * 4, w.patternColour, alpha);
      }
    }
  }

  switch (w.pattern) {
    case 'stripes':
      rect(0, 0, N, 32);
      rect(0, 64, N, 32);
    case 'pinstripe':
      for (var y = 0; y < N; y += 16) {
        rect(0, y, N, 3);
      }
    case 'checks':
      rect(0, 0, 64, 64);
      rect(64, 64, 64, 64);
    case 'dots':
      for (final (cx, cy) in const [(32, 32), (96, 96), (96, 32), (32, 96)]) {
        for (var y = cy - 12; y <= cy + 12; y++) {
          for (var x = cx - 12; x <= cx + 12; x++) {
            final d = math.sqrt((x + 0.5 - cx) * (x + 0.5 - cx) +
                (y + 0.5 - cy) * (y + 0.5 - cy));
            if (d < 11.5) {
              _put(px, (y * N + x) * 4, w.patternColour,
                  (11.5 - d).clamp(0.0, 1.0));
            }
          }
        }
      }
    case 'plaid':
      rect(0, 20, N, 24, 0.45);
      rect(20, 0, 24, N, 0.45);
      rect(0, 84, N, 4, 0.8);
      rect(84, 0, 4, N, 0.8);
  }
  return (px, N, N);
}

/// _put lays [rgb] over the pixel at [at], [alpha] of the way.
void _put(Uint8List px, int at, int rgb, double alpha) {
  for (var c = 0; c < 3; c++) {
    final v = (rgb >> (16 - 8 * c)) & 0xff;
    px[at + c] = (px[at + c] + (v - px[at + c]) * alpha).round();
  }
  px[at + 3] = 255;
}

/// medianColour is the middle of [samples] (RGB triples), channel by
/// channel, or null for none.
List<int>? medianColour(List<int> samples) {
  if (samples.length < 3) return null;
  final out = <int>[];
  for (var c = 0; c < 3; c++) {
    final l = [for (var i = c; i < samples.length; i += 3) samples[i]]..sort();
    out.add(l[l.length >> 1]);
  }
  return out;
}

/// faceSkinColour is the colour of the face's skin, from its picture
/// ([rgba], [w] by [h]) at the face's own points: the one part of a VRoid
/// body never painted over.
List<int>? faceSkinColour(Uint8List rgba, int w, int h, VrmMeshData data) {
  final samples = <int>[];
  for (final p in data.primitivesOf(VrmRegion.face, VrmPart.face)) {
    final uv = p.vertices.uv0;
    for (var k = 0; k < p.used.length; k += 3) {
      final i = p.used[k];
      final x = (uv[i * 2] * w).floor().clamp(0, w - 1),
          y = (uv[i * 2 + 1] * h).floor().clamp(0, h - 1);
      final at = (y * w + x) * 4;
      if (rgba[at + 3] < 200) continue;
      samples.addAll([rgba[at], rgba[at + 1], rgba[at + 2]]);
    }
  }
  return medianColour(samples);
}

/// bareSkin is the body's skin picture ([rgba], [w] by [h]) with whatever
/// is painted on it taken off where clothes have come off: above the
/// knees ([upper]) and below them ([lower]). Painted is anything not near
/// the skin's own colour, found from the neck and hands -- or, where those
/// are a painted suit too, from [face].
Uint8List bareSkin(Uint8List rgba, int w, int h, VrmWardrobe wardrobe,
    {required bool upper, required bool lower, List<int>? face}) {
  final tris = wardrobe.skinTriangles();
  final mask = Uint8List(w * h), ref = Uint8List(w * h);
  for (final t in tris) {
    if (t.where != 'head') {
      _fillTriangle(mask, w, h, t.uv, t.where == 'lower' ? 2 : 1);
    }
    if (t.group == BodyGroup.neck || t.group == BodyGroup.hand) {
      _fillTriangle(ref, w, h, t.uv, 1);
    }
  }
  final samples = <int>[];
  for (var i = 0; i < w * h; i += 7) {
    if (ref[i] == 1) {
      samples.addAll([rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]]);
    }
  }
  var skin = medianColour(samples) ?? const [220, 190, 170];
  if (face != null && _dist(skin, face[0], face[1], face[2]) > 40) skin = face;
  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < w * h; i++) {
    final m = mask[i];
    if (!((m == 1 && upper) || (m == 2 && lower))) continue;
    final a = i * 4;
    final d = _dist(skin, out[a], out[a + 1], out[a + 2]);
    if (d < 16) continue;
    final k = math.min(1.0, (d - 16) / 18);
    for (var c = 0; c < 3; c++) {
      out[a + c] = (out[a + c] + (skin[c] - out[a + c]) * k).round();
    }
  }
  return out;
}

double _dist(List<int> c, int r, int g, int b) =>
    math.sqrt(((r - c[0]) * (r - c[0]) +
            (g - c[1]) * (g - c[1]) +
            (b - c[2]) * (b - c[2]))
        .toDouble());

/// _fillTriangle marks [value] in [mask] over a triangle given by its
/// texture coordinates, and three pixels round it, so the seams
/// between triangles are covered.
void _fillTriangle(Uint8List mask, int w, int h, Float32List uv, int value) {
  final x = [uv[0] * w, uv[2] * w, uv[4] * w],
      y = [uv[1] * h, uv[3] * h, uv[5] * h];
  final area = (x[1] - x[0]) * (y[2] - y[0]) - (y[1] - y[0]) * (x[2] - x[0]);
  if (area.abs() < 1e-9) return;
  final s = area > 0 ? 1.0 : -1.0;
  const grow = 3.0;
  final x0 = (x.reduce(math.min) - 2).floor().clamp(0, w - 1),
      x1 = (x.reduce(math.max) + 2).ceil().clamp(0, w - 1);
  final y0 = (y.reduce(math.min) - 2).floor().clamp(0, h - 1),
      y1 = (y.reduce(math.max) + 2).ceil().clamp(0, h - 1);
  final len = [
    for (var e = 0; e < 3; e++)
      math.sqrt(math.pow(x[(e + 1) % 3] - x[e], 2) +
          math.pow(y[(e + 1) % 3] - y[e], 2))
  ];
  for (var py = y0; py <= y1; py++) {
    for (var px = x0; px <= x1; px++) {
      final cx = px + 0.5, cy = py + 0.5;
      var inside = true;
      for (var e = 0; e < 3 && inside; e++) {
        final ax = x[e], ay = y[e], bx = x[(e + 1) % 3], by = y[(e + 1) % 3];
        final d = s *
            ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) /
            math.max(1e-9, len[e]);
        if (d < -grow) inside = false;
      }
      if (inside) mask[py * w + px] = value;
    }
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';

// human_garments.dart makes a sculpted body's clothes out of the body: a
// top is the skin of the chest and arms cut off at its hems, smoothed so it
// does not cling to every hollow, and stood off the skin by how loose it
// is; a skirt is a cone from the waist. Cut where a hem is -- partway
// across a triangle where it falls there -- so a cuff is a clean line, not
// the mesh's own steps.
//
// Each piece is skinned as the body under it, so it moves as the body
// does, and the skin it covers is not drawn.

/// ShellPiece is one garment's surface, ready to be a primitive.
class ShellPiece {
  final Float32List positions;
  final Float32List normals;
  final Uint16List joints;
  final Float32List weights;
  final Uint32List triangles;
  final Color colour;

  /// open is whether it is seen from inside too: a skirt is.
  final bool open;
  ShellPiece(this.positions, this.normals, this.joints, this.weights,
      this.triangles, this.colour, this.open);
}

/// _Family is what part of the body a bone moves.
enum _Family { torso, arm, hand, leg, foot, head }

_Family _familyOf(String bone) {
  // MakeHuman's shoulder bones move the chest as much as the arm: torso.
  if (bone.contains("upperarm") || bone.contains("lowerarm")) return _Family.arm;
  if (bone.contains("wrist") || bone.contains("finger") ||
      bone.contains("metacarpal") || bone.contains("thumb")) {
    return _Family.hand;
  }
  if (bone.contains("upperleg") || bone.contains("lowerleg")) return _Family.leg;
  if (bone.contains("foot") || bone.contains("toe")) return _Family.foot;
  if (bone == "root" || bone.contains("spine") || bone.contains("pelvis") ||
      bone.contains("clavicle") || bone.contains("shoulder") ||
      bone.contains("breast")) {
    return _Family.torso;
  }
  return _Family.head;
}

/// _rank is how far out a garment is worn: what is put on later goes
/// over what is under it.
int _rank(Garment g) => switch (g.kind.slot) {
      GarmentSlot.base => 1,
      GarmentSlot.bottom => 2,
      GarmentSlot.top => 3,
      GarmentSlot.full => 3,
      GarmentSlot.outer => 5,
      _ => 3,
    };

/// garmentShells is the clothes [dna] wears that cover the body -- tops,
/// trousers, skirts, dresses -- made from the body at [pos], whose faces
/// are [corners] (vertex then uv, three to a face), each vertex following
/// the bones [best] says, as the bones [bones] at [heads]. hides is the
/// body's faces they cover, as the index of each face's first corner.
({List<ShellPiece> pieces, Set<int> hides}) garmentShells({
  required CharacterDna dna,
  required Float32List pos,
  required Uint32List corners,
  required List<List<(int, double)>> best,
  required List<String> bones,
  required Map<String, List<double>> heads,
}) {
  var worn = [
    for (var g in dna.worn)
      if (g.kind.shape == GarmentShape.torso ||
          g.kind.shape == GarmentShape.legs ||
          g.kind.shape == GarmentShape.skirt ||
          g.kind.shape == GarmentShape.dress)
        g,
  ];
  if (worn.isEmpty) return (pieces: const [], hides: const {});
  var n = pos.length ~/ 3;
  List<double> at(String b) => heads[b] ?? const [0.0, 0.0, 0.0];

  // The body's measurements.
  var low = double.infinity, high = -double.infinity;
  for (var v = 0; v < n; v++) {
    low = math.min(low, pos[v * 3 + 1]);
    high = math.max(high, pos[v * 3 + 1]);
  }
  var tall = math.max(1e-6, high - low);
  var shoulderL = at("upperarm01.L"), shoulderR = at("upperarm01.R");
  var wristL = at("wrist.L"), wristR = at("wrist.R");
  var hipL = at("upperleg01.L"), hipR = at("upperleg01.R");
  var ankleL = at("foot.L"), ankleR = at("foot.R");
  var kneeL = at("lowerleg01.L");
  var neck = at("neck01");
  var yShoulder = (shoulderL[1] + shoulderR[1]) / 2;
  var yHip = (hipL[1] + hipR[1]) / 2;
  var trunk = math.max(1e-6, yShoulder - yHip);
  var yChest = yShoulder - 0.35 * trunk;
  var yHipLine = yHip - 0.08 * trunk;
  var yWaist = yHip + 0.3 * trunk;
  var yCollar = neck[1] - 0.01 * tall;
  var thigh = math.max(1e-6, hipL[1] - kneeL[1]);
  var legDrop = math.max(1e-6, yWaist - (ankleL[1] + ankleR[1]) / 2);

  // Each vertex's share of each part, and which side it is on.
  var family = [for (var b in bones) _familyOf(b)];
  var left = [for (var b in bones) b.endsWith(".L")];
  var share = List.generate(n, (_) => Float32List(_Family.values.length));
  var onLeft = List<bool>.filled(n, false);
  for (var v = 0; v < n; v++) {
    var l = 0.0, r = 0.0;
    for (var (b, w) in best[v]) {
      share[v][family[b].index] += w;
      if (left[b]) l += w;
      if (bones[b].endsWith(".R")) r += w;
    }
    var total = share[v].fold(0.0, (a, b) => a + b);
    if (total > 0) {
      for (var k = 0; k < share[v].length; k++) {
        share[v][k] /= total;
      }
    }
    onLeft[v] = l == r ? pos[v * 3] > 0 : l > r;
  }

  // How far along a limb a point is: 0 at its top joint, 1 at its end.
  double along(int v, List<double> from, List<double> to) {
    var dx = to[0] - from[0], dy = to[1] - from[1], dz = to[2] - from[2];
    var len2 = math.max(1e-9, dx * dx + dy * dy + dz * dz);
    return ((pos[v * 3] - from[0]) * dx +
            (pos[v * 3 + 1] - from[1]) * dy +
            (pos[v * 3 + 2] - from[2]) * dz) /
        len2;
  }

  double dist(List<double> a, List<double> b) => math.sqrt(
      math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2) + math.pow(a[2] - b[2], 2));
  var armLen = dist(shoulderL, wristL);
  var legLen = dist(hipL, ankleL);

  // Where each skirt -- a skirt's, a dress's, a long coat's -- hangs from,
  // to, and how much it flares.
  (double, double, double)? coneOf(Garment g) {
    var length = g.lengthOr;
    return switch (g.kind.shape) {
      GarmentShape.torso when length > 1.05 =>
        (yWaist, yHipLine - (length - 1) * thigh, 1.12 * g.fitOr),
      GarmentShape.dress => (yWaist + 0.01 * tall, yWaist - length * legDrop, g.kind.flare),
      GarmentShape.skirt => (yWaist, yWaist - length * legDrop, g.kind.flare),
      _ => null,
    };
  }

  var pieces = <ShellPiece>[];
  var hides = <int>{};
  // Outer garments go furthest out.
  worn.sort((a, b) => _rank(a).compareTo(_rank(b)));
  // Inside each garment where its s is not negative, in body units from
  // its nearest hem; null for one with no shell, a skirt.
  Float64List? insideOf(Garment g) {
    var shape = g.kind.shape;
    var rank = _rank(g);
    var length = g.lengthOr;
    var sleeve = g.sleeveOr;
    var s = Float64List(n);
    switch (shape) {
      case GarmentShape.torso:
      case GarmentShape.dress:
        var hem = shape == GarmentShape.dress
            ? yWaist
            : yChest - math.min(length, 1.0) * (yChest - yHipLine);
        // A top stops a little inside any skirt worn over it, its own
        // included: hidden there, and level with it, it would show
        // through in specks.
        for (var over in worn) {
          if (_rank(over) < rank) continue;
          if (coneOf(over) case (var top, _, _)) {
            hem = math.max(hem, top - 0.02 * tall);
          }
        }
        for (var v = 0; v < n; v++) {
          var sh = share[v];
          var y = pos[v * 3 + 1], z = pos[v * 3 + 2];
          if (sh[_Family.hand.index] > 0.5 || sh[_Family.head.index] > 0.6 ||
              sh[_Family.foot.index] > 0.3) {
            s[v] = -1;
            continue;
          }
          // The collar, a little lower at the front -- or, strapless, a
          // line straight across the chest under the arms.
          var collar = g.kind.strapless
              ? (yShoulder - 0.2 * trunk) - y
              : yCollar - y - math.max(0.0, z - neck[2]) * 0.35;
          var arm = sh[_Family.arm.index];
          var t = onLeft[v] ? along(v, shoulderL, wristL) : along(v, shoulderR, wristR);
          var cuff = (sleeve - t) * armLen;
          // No sleeves: the armhole is where the arm starts to move the
          // skin more than the chest does.
          if (sleeve < 0.05) cuff = (0.45 - arm) * armLen * 0.3;
          if (g.kind.strapless) cuff = (0.15 - arm) * armLen * 0.3;
          if (arm > 0.5) {
            s[v] = cuff;
          } else {
            var body = math.min(y - hem, collar);
            s[v] = arm > 0 ? math.min(body, cuff) : body;
          }
        }
      case GarmentShape.legs:
        var full = g.kind.slot == GarmentSlot.full;
        var top = full ? yChest : (length < 0.15 ? yHip + 0.12 * trunk : yWaist);
        var from = g.kind.from;
        for (var v = 0; v < n; v++) {
          var sh = share[v];
          if (sh[_Family.arm.index] + sh[_Family.hand.index] > 0.4 ||
              sh[_Family.head.index] > 0.5) {
            s[v] = -1;
            continue;
          }
          var y = pos[v * 3 + 1];
          var waist = top - y;
          var leg = sh[_Family.leg.index] + sh[_Family.foot.index];
          var t = onLeft[v] ? along(v, hipL, ankleL) : along(v, hipR, ankleR);
          var hem = (length - t) * legLen;
          if (from > 0) hem = math.min(hem, (t - from) * legLen);
          s[v] = leg > 0 ? math.min(waist, hem) : waist;
        }
      default:
        return null;
    }
    return s;
  }

  var inside = {for (var g in worn) g: insideOf(g)};
  for (var g in worn) {
    var rank = _rank(g);
    var thick = tall * (0.003 + 0.0022 * rank) * g.fitOr;
    var cone = coneOf(g);
    var s = inside[g];
    var hasShell = s != null;
    // Under a garment worn over it, a garment is not seen, and drawn so
    // near it, would show through it in specks: it stops a little way in
    // under the other's hem.
    if (s != null) {
      for (var over in worn) {
        if (over == g || _rank(over) <= rank) continue;
        if (inside[over] case var o?) {
          for (var v = 0; v < n; v++) {
            s[v] = math.min(s[v], 0.006 * tall - o[v]);
          }
        }
      }
    }

    if (hasShell) {
      var shell = _cut(pos, corners, best, s, n);
      if (shell != null) {
        _smoothAndStandOff(shell, thick);
        pieces.add(shell.piece(g.color, false));
        for (var k = 0; k + 5 < corners.length; k += 6) {
          if (s[corners[k]] > 0 && s[corners[k + 2]] > 0 && s[corners[k + 4]] > 0) {
            hides.add(k);
          }
        }
      }
    }
    // A skirt wholly inside a longer one over it is not seen, and drawn
    // so near it, would show through it in specks.
    if (cone case (var top, var hem, _)) {
      for (var over in worn) {
        if (over == g || _rank(over) < rank) continue;
        if (coneOf(over) case (var oTop, var oHem, _)
            when oTop >= top - 0.03 * tall && oHem <= hem) {
          cone = null;
        }
      }
    }
    if (cone case (var top, var hem, var flare) when hem < top) {
      var skirt = _cone(pos, share, bones, heads, top, hem, yHip, flare,
          thick * 1.4, tall, g.color);
      if (skirt != null) pieces.add(skirt);
    }
  }
  return (pieces: pieces, hides: hides);
}

/// _Shell is a piece being made: its vertices, where each is, which way it
/// faces, the bones it follows, and whether it is on a hem.
class _Shell {
  final positions = <double>[];
  final weights = <Map<int, double>>[];
  final hem = <bool>[];
  final triangles = <int>[];

  int add(double x, double y, double z, Map<int, double> w, bool onHem) {
    positions.addAll([x, y, z]);
    weights.add(w);
    hem.add(onHem);
    return hem.length - 1;
  }

  ShellPiece piece(Color colour, bool open) {
    var m = hem.length;
    var joints = Uint16List(m * 4), ws = Float32List(m * 4);
    for (var i = 0; i < m; i++) {
      var sorted = weights[i].entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      var total = 0.0;
      for (var k = 0; k < 4 && k < sorted.length; k++) {
        total += sorted[k].value;
      }
      for (var k = 0; k < 4 && k < sorted.length; k++) {
        joints[i * 4 + k] = sorted[k].key;
        ws[i * 4 + k] = total == 0 ? 0 : sorted[k].value / total;
      }
    }
    var p = Float32List.fromList(positions);
    return ShellPiece(p, _normals(p, triangles), joints, ws,
        Uint32List.fromList(triangles), colour, open);
  }
}

/// _cut is the body's faces where [s] is not negative, cut through where
/// it changes sign.
_Shell? _cut(Float32List pos, Uint32List corners, List<List<(int, double)>> best,
    Float64List s, int n) {
  var shell = _Shell();
  var ofVertex = <int, int>{};
  var ofEdge = <int, int>{};
  int vertex(int v) => ofVertex.putIfAbsent(v, () {
        return shell.add(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2],
            {for (var (b, w) in best[v]) b: w}, false);
      });
  int edge(int a, int b) {
    var key = a < b ? a * n + b : b * n + a;
    return ofEdge.putIfAbsent(key, () {
      var t = s[a] / (s[a] - s[b]);
      var w = <int, double>{};
      for (var (bone, x) in best[a]) {
        w[bone] = (w[bone] ?? 0) + x * (1 - t);
      }
      for (var (bone, x) in best[b]) {
        w[bone] = (w[bone] ?? 0) + x * t;
      }
      double mix(int c) => pos[a * 3 + c] * (1 - t) + pos[b * 3 + c] * t;
      return shell.add(mix(0), mix(1), mix(2), w, true);
    });
  }

  for (var k = 0; k + 5 < corners.length; k += 6) {
    var tri = [corners[k], corners[k + 2], corners[k + 4]];
    if (tri.every((v) => s[v] < 0)) continue;
    var poly = <int>[];
    for (var c = 0; c < 3; c++) {
      var a = tri[c], b = tri[(c + 1) % 3];
      var inA = s[a] >= 0, inB = s[b] >= 0;
      if (inA) poly.add(vertex(a));
      if (inA != inB) poly.add(edge(a, b));
    }
    for (var c = 1; c + 1 < poly.length; c++) {
      shell.triangles.addAll([poly[0], poly[c], poly[c + 1]]);
    }
  }
  return shell.triangles.isEmpty ? null : shell;
}

/// _smoothAndStandOff smooths [shell] over the body's hollows -- cloth
/// spans them -- without shrinking it, and stands it [thick] off the skin.
void _smoothAndStandOff(_Shell shell, double thick) {
  var m = shell.hem.length;
  var near = List.generate(m, (_) => <int>{});
  var t = shell.triangles;
  for (var k = 0; k + 2 < t.length; k += 3) {
    near[t[k]]..add(t[k + 1])..add(t[k + 2]);
    near[t[k + 1]]..add(t[k])..add(t[k + 2]);
    near[t[k + 2]]..add(t[k])..add(t[k + 1]);
  }
  var p = shell.positions;
  var next = List<double>.from(p);
  // Taubin's smoothing: a step in, then a slightly larger step out, so it
  // loses its bumps but keeps its size.
  for (var pass = 0; pass < 16; pass++) {
    var f = pass.isEven ? 0.5 : -0.53;
    for (var v = 0; v < m; v++) {
      if (shell.hem[v] || near[v].isEmpty) continue;
      for (var c = 0; c < 3; c++) {
        var sum = 0.0;
        for (var u in near[v]) {
          sum += p[u * 3 + c];
        }
        var mid = sum / near[v].length;
        next[v * 3 + c] = p[v * 3 + c] + (mid - p[v * 3 + c]) * f;
      }
    }
    p.setAll(0, next);
  }
  var nm = _normals(Float32List.fromList(p), t);
  for (var v = 0; v < m; v++) {
    for (var c = 0; c < 3; c++) {
      p[v * 3 + c] += nm[v * 3 + c] * thick;
    }
  }
}

/// _normals is each vertex's facing, from the faces round it.
Float32List _normals(Float32List p, List<int> t) {
  var nm = Float32List(p.length);
  for (var k = 0; k + 2 < t.length; k += 3) {
    var a = t[k] * 3, b = t[k + 1] * 3, c = t[k + 2] * 3;
    var ux = p[b] - p[a], uy = p[b + 1] - p[a + 1], uz = p[b + 2] - p[a + 2];
    var wx = p[c] - p[a], wy = p[c + 1] - p[a + 1], wz = p[c + 2] - p[a + 2];
    var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
    for (var v in [a, b, c]) {
      nm[v] += nx;
      nm[v + 1] += ny;
      nm[v + 2] += nz;
    }
  }
  for (var v = 0; v + 2 < nm.length; v += 3) {
    var l = math.sqrt(nm[v] * nm[v] + nm[v + 1] * nm[v + 1] + nm[v + 2] * nm[v + 2]);
    if (l > 0) {
      nm[v] /= l;
      nm[v + 1] /= l;
      nm[v + 2] /= l;
    }
  }
  return nm;
}

/// _cone is a skirt from [top] down to [hem]: round the body at each
/// height, wider towards the hem by [flare], following the hips and, a
/// little, the thighs.
ShellPiece? _cone(
    Float32List pos,
    List<Float32List> share,
    List<String> bones,
    Map<String, List<double>> heads,
    double top,
    double hem,
    double yHip,
    double flare,
    double thick,
    double tall,
    Color colour) {
  // Fine enough that each face is small: they are drawn far ones first,
  // and a large one is put behind small ones it is in front of.
  const around = 64;
  var root = bones.indexOf("root");
  var legL = bones.indexOf("upperleg01.L"), legR = bones.indexOf("upperleg01.R");
  if (root < 0) return null;
  var hipL = heads["upperleg01.L"] ?? const [0.5, 0.0, 0.0];
  var hipR = heads["upperleg01.R"] ?? const [-0.5, 0.0, 0.0];
  var cx = (hipL[0] + hipR[0]) / 2, cz = (hipL[2] + hipR[2]) / 2;
  var n = pos.length ~/ 3;
  // How far out the body is, each way round, at a height.
  List<double> girth(double y) {
    var band = 0.025 * tall;
    var r = List<double>.filled(around, 0);
    for (var v = 0; v < n; v++) {
      var vy = pos[v * 3 + 1];
      if ((vy - y).abs() > band) continue;
      var sh = share[v];
      if (sh[_Family.arm.index] + sh[_Family.hand.index] > 0.3) continue;
      var dx = pos[v * 3] - cx, dz = pos[v * 3 + 2] - cz;
      var a = math.atan2(dz, dx);
      var i = ((a + math.pi) / (2 * math.pi) * around).round() % around;
      r[i] = math.max(r[i], math.sqrt(dx * dx + dz * dz));
    }
    // Fill any way round no vertex fell, from its neighbours.
    var most = r.reduce(math.max);
    for (var pass = 0; pass < 3; pass++) {
      for (var i = 0; i < around; i++) {
        if (r[i] == 0) {
          r[i] = math.max(r[(i + 1) % around], r[(i + around - 1) % around]);
        }
      }
    }
    // Smoothed round, as cloth hangs.
    return [
      for (var i = 0; i < around; i++)
        math.max(most * 0.6,
            (r[(i + around - 1) % around] + 2 * r[i] + r[(i + 1) % around]) / 4),
    ];
  }

  var atTop = girth(top);
  var atHip = girth(math.min(top, yHip));
  var widest = [for (var i = 0; i < around; i++) math.max(atTop[i], atHip[i])];
  const rings = 28;
  var shell = _Shell();
  for (var ring = 0; ring <= rings; ring++) {
    var f = ring / rings;
    var y = top + (hem - top) * f;
    var hipShare = top <= yHip ? 1.0 : ((top - y) / (top - yHip)).clamp(0.0, 1.0);
    var below = y >= yHip ? 0.0 : (yHip - y) / math.max(1e-6, yHip - hem);
    for (var i = 0; i < around; i++) {
      var a = -math.pi + i / around * 2 * math.pi;
      var r = atTop[i] + (widest[i] - atTop[i]) * hipShare;
      r = r * (1 + (flare - 1) * below) + thick;
      var x = cx + math.cos(a) * r, z = cz + math.sin(a) * r;
      // Mostly the hips; towards the hem, a little of the thigh on its
      // side, so it swings as the legs do.
      var leg = 0.35 * below * (math.cos(a).abs());
      var w = <int, double>{root: 1 - leg};
      var side = math.cos(a) > 0 ? legL : legR;
      if (side >= 0 && leg > 0) w[side] = leg;
      shell.add(x, y, z, w, ring == 0 || ring == rings);
    }
  }
  for (var ring = 0; ring < rings; ring++) {
    for (var i = 0; i < around; i++) {
      var a = ring * around + i, b = ring * around + (i + 1) % around;
      var c = a + around, d = b + around;
      shell.triangles.addAll([a, c, b, b, c, d]);
    }
  }
  return shell.piece(colour, true);
}

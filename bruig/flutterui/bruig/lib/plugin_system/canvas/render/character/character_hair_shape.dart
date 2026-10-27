import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_hair.dart';

// character_hair_shape.dart is where a stroke of hair is, as seen: grown
// from its root on the scalp -- a ball, in the head's own space, w across
// and h down -- turned and tipped with the head. What the painter draws and
// the editor's handles are both made from it, so they agree.

/// HeadView is how the head is seen: its half width and half height in its
/// own space, how far it is turned and tipped, in radians, and how far the
/// features have moved down as it nods.
class HeadView {
  final double w;
  final double h;
  final double yaw;
  final double pitch;
  final double nod;
  const HeadView(this.w, this.h, this.yaw, this.pitch, {this.nod = 0});

  /// seen is a point of the head -- in its radii: x right, y up, z towards
  /// the reader when it faces them -- on the page, and how far towards the
  /// reader it is.
  (Offset, double) seen(double x, double y, double z) {
    var cy = math.cos(yaw), sy = math.sin(yaw);
    var cp = math.cos(pitch), sp = math.sin(pitch);
    var x1 = x * cy - z * sy, z1 = z * cy + x * sy;
    var y2 = y * cp - z1 * sp, z2 = z1 * cp + y * sp;
    return (Offset(x1 * w, -y2 * h + nod), z2);
  }

  /// step is a step in the head's own space -- in head heights, the same
  /// across as up, so a shape keeps its proportions however it is turned --
  /// as a step on the page.
  Offset step(double x, double y, double z) {
    var cy = math.cos(yaw), sy = math.sin(yaw);
    var cp = math.cos(pitch), sp = math.sin(pitch);
    var x1 = x * cy - z * sy, z1 = z * cy + x * sy;
    var y2 = y * cp - z1 * sp;
    return Offset(x1 * h, -y2 * h);
  }

  /// unstep is a step on the page as a step in the head's own space, across
  /// the way the reader looks: the inverse of [step] for what lies flat to
  /// the reader.
  List<double> unstep(Offset d) {
    var cy = math.cos(yaw), sy = math.sin(yaw);
    var cp = math.cos(pitch), sp = math.sin(pitch);
    var ax = d.dx / h, ay = d.dy / h;
    // Across the page, and down it.
    return [
      cy * ax + sp * sy * ay,
      -cp * ay,
      -sy * ax + sp * cy * ay,
    ];
  }

  /// toward is the way the reader looks from, in the head's own space.
  (double, double, double) get toward {
    var cp = math.cos(pitch), sp = math.sin(pitch);
    return (cp * math.sin(yaw), sp, cp * math.cos(yaw));
  }

  /// scalpAt is where on the scalp -- lon and lat, in degrees -- [p] is, a
  /// point of the head's own space on the side of it towards the reader, or
  /// null off it.
  (double, double)? scalpAt(Offset p) {
    var x1 = p.dx / w, y2 = -(p.dy - nod) / h;
    var rr = x1 * x1 + y2 * y2;
    if (rr > 1.1) return null;
    var z2 = math.sqrt(math.max(0, 1 - rr));
    // Back through the tip, then the turn.
    var cp = math.cos(pitch), sp = math.sin(pitch);
    var y = y2 * cp + z2 * sp, z1 = z2 * cp - y2 * sp;
    var cy = math.cos(yaw), sy = math.sin(yaw);
    var x = x1 * cy + z1 * sy, z = z1 * cy - x1 * sy;
    var lat = math.asin(y.clamp(-1.0, 1.0)) * 180 / math.pi;
    var lon = math.atan2(x, z) * 180 / math.pi;
    return (lon, lat);
  }
}

/// HairStrokeShape is a stroke as seen: down its middle, how wide it is
/// there, its outline, and how near the reader its root is.
class HairStrokeShape {
  final List<Offset> middle;
  final List<double> widths;
  final Path outline;
  final double depth;

  /// left and right are its two edges, root to tip.
  final List<Offset> left;
  final List<Offset> right;

  /// handles are its curve's two handles, off the root and off the tip.
  final (Offset, Offset) handles;
  const HairStrokeShape(this.middle, this.widths, this.outline, this.depth,
      [this.left = const [],
      this.right = const [],
      this.handles = (Offset.zero, Offset.zero)]);

  Offset get root => middle.first;
  Offset get tip => middle.last;
  Offset get mid => middle[middle.length ~/ 2];
}

/// hairStrokeShape is [s] -- of a group looking as [g] does -- as [head]
/// sees it.
HairStrokeShape hairStrokeShape(HairStroke s, HairGroupLook g, HeadView head) {
  List<double> on(double lonD, double latD) {
    var lon = lonD * math.pi / 180, lat = latD * math.pi / 180;
    return [
      math.cos(lat) * math.sin(lon),
      math.sin(lat),
      math.cos(lat) * math.cos(lon)
    ];
  }

  // Where it grows, and the frame its shape is made in: where it grew when
  // it was shaped, so a stroke moved keeps its shape.
  var root = [for (var v in on(s.lon, s.lat)) v * 1.02];
  var (rootPage, depth) = head.seen(root[0], root[1], root[2]);
  var (fLon, fLat) = s.shapedAt ?? (s.lon, s.lat);
  var o = on(fLon, fLat);
  var lon = fLon * math.pi / 180;
  var t = [math.cos(lon), 0.0, -math.sin(lon)];
  var down = [0.0, -1.0, 0.0];
  // The top grows up and out; everything else falls.
  var fall = s.group == HairGroup.top ? 0.15 : 0.95;
  var len = s.length * 2 * g.length;
  var vol = g.volume;
  // How far out from the head it stands: the fringe off the forehead, the
  // sides and back close to the head they fall round.
  // The sides and back full in the middle and tucked in towards the head
  // at their tips, as hair hangs round a head rather than off it.
  var (lift, bulge) = switch (s.group) {
    HairGroup.fringe => (0.18, 0.32),
    HairGroup.sides => (-0.1, 0.2),
    HairGroup.back => (-0.04, 0.24),
    HairGroup.top => (0.18, 0.3),
  };
  var out = lift * vol + (1 - fall) * 0.8;
  var curl = s.curl + g.curl;
  List<double> sum(List<(List<double>, double)> parts) => [
        for (var i = 0; i < 3; i++)
          parts.fold(0.0, (a, p) => a + p.$1[i] * p.$2)
      ];
  // Its shape, as steps from the root.
  var p1 = sum([(o, len * bulge * vol), (down, len * 0.1 * fall)]);
  var tip = sum([(o, len * out), (down, len * fall), (t, len * s.lean)]);
  var p2 = sum([
    (tip, 1),
    (o, len * lift * vol),
    (down, -len * 0.3 * fall),
    (t, len * curl * 0.6)
  ]);
  // Turned as a whole: by its turn about the level line out of that side
  // of the head, then by its spin.
  List<double> turned(List<double> v) {
    if (s.turn != 0) {
      var a = s.turn * math.pi / 180, c = math.cos(a), sn = math.sin(a);
      var axis = [math.sin(lon), 0.0, math.cos(lon)];
      var dot = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2];
      var cr = [
        axis[1] * v[2] - axis[2] * v[1],
        axis[2] * v[0] - axis[0] * v[2],
        axis[0] * v[1] - axis[1] * v[0]
      ];
      v = [
        for (var i = 0; i < 3; i++)
          v[i] * c + cr[i] * sn + axis[i] * dot * (1 - c)
      ];
    }
    return spinBy(s.spin, v);
  }

  // Pulled by hand.
  var b = s.bend;
  p1 = [p1[0] + b[0], p1[1] + b[1], p1[2] + b[2]];
  p2 = [p2[0] + b[3], p2[1] + b[4], p2[2] + b[5]];
  p1 = turned(p1);
  tip = turned(tip);
  p2 = turned(p2);
  // Down the middle, finely, then out each side as wide as it is.
  var mid = <Offset>[];
  const steps = 20;
  for (var k = 0; k <= steps; k++) {
    var q = k / steps, u0 = 1 - q;
    var b = [
      for (var i = 0; i < 3; i++)
        3 * u0 * u0 * q * p1[i] + 3 * u0 * q * q * p2[i] + q * q * q * tip[i]
    ];
    mid.add(rootPage + head.step(b[0], b[1], b[2]));
  }
  var left = <Offset>[], right = <Offset>[], widths = <double>[];
  for (var k = 0; k <= steps; k++) {
    var q = k / steps;
    var d = mid[math.min(steps, k + 1)] - mid[math.max(0, k - 1)];
    var l = d.distance;
    var n = l < 1e-9 ? const Offset(1, 0) : Offset(-d.dy / l, d.dx / l);
    var width = (q < 0.5
            ? s.w0 + (s.w1 - s.w0) * q * 2
            : s.w1 + (s.w2 - s.w1) * (q - 0.5) * 2) *
        g.width *
        head.h;
    widths.add(width);
    left.add(mid[k] + n * width);
    right.add(mid[k] - n * width);
  }
  // A round end where the tip is wide enough to have one.
  var cap = <Offset>[];
  if (widths.last > 0.01 * head.h) {
    var d = mid.last - mid[steps - 1];
    var a0 = math.atan2(d.dy, d.dx);
    for (var k = 1; k < 8; k++) {
      var a = a0 + math.pi / 2 - math.pi * k / 8;
      cap.add(mid.last + Offset(math.cos(a), math.sin(a)) * widths.last);
    }
  }
  return HairStrokeShape(
      mid,
      widths,
      Path()..addPolygon([...left, ...cap, ...right.reversed], true),
      depth,
      left,
      right,
      (
        rootPage + head.step(p1[0], p1[1], p1[2]),
        rootPage + head.step(p2[0], p2[1], p2[2])
      ));
}

/// unturned is [v], a step in the head's space, as it was before [s] was
/// turned and spun: what a step pulled by hand is kept as.
List<double> unturned(HairStroke s, List<double> v) {
  var q = s.spin;
  v = spinBy([q[0], -q[1], -q[2], -q[3]], v);
  if (s.turn == 0) return v;
  var (fLon, _) = s.shapedAt ?? (s.lon, s.lat);
  var lon = fLon * math.pi / 180;
  var a = -s.turn * math.pi / 180, c = math.cos(a), sn = math.sin(a);
  var axis = [math.sin(lon), 0.0, math.cos(lon)];
  var dot = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2];
  var cr = [
    axis[1] * v[2] - axis[2] * v[1],
    axis[2] * v[0] - axis[0] * v[2],
    axis[0] * v[1] - axis[1] * v[0]
  ];
  return [
    for (var i = 0; i < 3; i++) v[i] * c + cr[i] * sn + axis[i] * dot * (1 - c)
  ];
}

/// spinBy is [v] turned by the quaternion [q] -- w, x, y, z.
List<double> spinBy(List<double> q, List<double> v) {
  var w = q[0], x = q[1], y = q[2], z = q[3];
  if ((w - 1).abs() < 1e-12) return v;
  // v + 2w(q x v) + 2 q x (q x v)
  var cx = y * v[2] - z * v[1], cy = z * v[0] - x * v[2], cz = x * v[1] - y * v[0];
  var dx = y * cz - z * cy, dy = z * cx - x * cz, dz = x * cy - y * cx;
  return [
    v[0] + 2 * (w * cx + dx),
    v[1] + 2 * (w * cy + dy),
    v[2] + 2 * (w * cz + dz),
  ];
}

/// spinAbout is the quaternion turning [degrees] about [axis], right-handed.
List<double> spinAbout((double, double, double) axis, double degrees) {
  var (x, y, z) = axis;
  var n = math.sqrt(x * x + y * y + z * z);
  if (n < 1e-12) return HairStroke.noSpin;
  var a = degrees * math.pi / 360, s = math.sin(a) / n;
  return [math.cos(a), x * s, y * s, z * s];
}

/// spinThen is [b] after [a]: a quaternion product.
List<double> spinThen(List<double> a, List<double> b) {
  var (aw, ax, ay, az) = (a[0], a[1], a[2], a[3]);
  var (bw, bx, by, bz) = (b[0], b[1], b[2], b[3]);
  return [
    bw * aw - bx * ax - by * ay - bz * az,
    bw * ax + bx * aw + by * az - bz * ay,
    bw * ay - bx * az + by * aw + bz * ax,
    bw * az + bx * ay - by * ax + bz * aw,
  ];
}

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
  const HairStrokeShape(this.middle, this.widths, this.outline, this.depth);

  Offset get root => middle.first;
  Offset get tip => middle.last;
  Offset get mid => middle[middle.length ~/ 2];
}

/// hairStrokeShape is [s] -- of a group looking as [g] does -- as [head]
/// sees it.
HairStrokeShape hairStrokeShape(HairStroke s, HairGroupLook g, HeadView head) {
  var lon = s.lon * math.pi / 180, lat = s.lat * math.pi / 180;
  var o = [
    math.cos(lat) * math.sin(lon),
    math.sin(lat),
    math.cos(lat) * math.cos(lon)
  ];
  var root = [for (var v in o) v * 1.02];
  var (_, depth) = head.seen(root[0], root[1], root[2]);
  // The top grows up and out; everything else falls.
  var fall = s.group == HairGroup.top ? 0.15 : 0.95;
  var len = s.length * 2 * g.length;
  var vol = g.volume;
  // How far out from the head it stands: the fringe off the forehead, the
  // sides and back close to the head they fall round.
  var (lift, bulge) = switch (s.group) {
    HairGroup.fringe => (0.18, 0.32),
    HairGroup.sides => (0.04, 0.14),
    HairGroup.back => (0.08, 0.2),
    HairGroup.top => (0.18, 0.3),
  };
  var out = lift * vol + (1 - fall) * 0.8;
  var t = [math.cos(lon), 0.0, -math.sin(lon)];
  // Turned about where it grows: which way it falls and leans, round the
  // level line out of that side of the head -- a turn of the stroke in the
  // view that looks at it face on, the front for the fringe and the side
  // for the sides, going all the way round there.
  var down = [0.0, -1.0, 0.0];
  if (s.turn != 0) {
    var a = s.turn * math.pi / 180, c = math.cos(a), sn = math.sin(a);
    var axis = [math.sin(lon), 0.0, math.cos(lon)];
    List<double> turned(List<double> v) {
      var dot = axis[0] * v[0] + axis[1] * v[1] + axis[2] * v[2];
      var cr = [
        axis[1] * v[2] - axis[2] * v[1],
        axis[2] * v[0] - axis[0] * v[2],
        axis[0] * v[1] - axis[1] * v[0]
      ];
      return [
        for (var i = 0; i < 3; i++)
          v[i] * c + cr[i] * sn + axis[i] * dot * (1 - c)
      ];
    }

    down = turned(down);
    t = turned(t);
  }
  var up = [for (var v in down) -v];
  var curl = s.curl + g.curl;
  List<double> at(List<double> a, List<double> b, double k) =>
      [for (var i = 0; i < 3; i++) a[i] + b[i] * k];
  var p1 = at(at(root, o, len * bulge * vol), down, len * 0.1 * fall);
  var tip = at(at(at(root, o, len * out), down, len * fall), t, len * s.lean);
  var p2 = at(at(at(tip, o, len * lift * vol), up, len * 0.3 * fall), t,
      len * curl * 0.6);
  // Down the middle, finely, then out each side as wide as it is.
  var mid = <Offset>[];
  const steps = 20;
  for (var k = 0; k <= steps; k++) {
    var q = k / steps, u0 = 1 - q;
    var b = [
      for (var i = 0; i < 3; i++)
        u0 * u0 * u0 * root[i] +
            3 * u0 * u0 * q * p1[i] +
            3 * u0 * q * q * p2[i] +
            q * q * q * tip[i]
    ];
    mid.add(head.seen(b[0], b[1], b[2]).$1);
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
  return HairStrokeShape(mid, widths,
      Path()..addPolygon([...left, ...right.reversed], true), depth);
}

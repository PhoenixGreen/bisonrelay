import 'dart:math' as math;
import 'dart:typed_data';

// model_math.dart is the little 3D arithmetic a modelled character needs:
// turns as quaternions, places as 4x4 matrices -- column by column, the way
// glTF writes them -- and the few things done with them.

/// Quat is a turn in 3D: x, y, z, w.
class Quat {
  final double x, y, z, w;
  const Quat(this.x, this.y, this.z, this.w);

  static const Quat identity = Quat(0, 0, 0, 1);

  Quat operator *(Quat b) => Quat(
        w * b.x + x * b.w + y * b.z - z * b.y,
        w * b.y - x * b.z + y * b.w + z * b.x,
        w * b.z + x * b.y - y * b.x + z * b.w,
        w * b.w - x * b.x - y * b.y - z * b.z,
      );

  Quat get conjugate => Quat(-x, -y, -z, w);

  Quat get normalized {
    var l = math.sqrt(x * x + y * y + z * z + w * w);
    return l == 0 ? identity : Quat(x / l, y / l, z / l, w / l);
  }

  /// rotate is [v] turned by this.
  List<double> rotate(List<double> v) {
    // v' = q v q*, written out.
    var tx = 2 * (y * v[2] - z * v[1]);
    var ty = 2 * (z * v[0] - x * v[2]);
    var tz = 2 * (x * v[1] - y * v[0]);
    return [
      v[0] + w * tx + (y * tz - z * ty),
      v[1] + w * ty + (z * tx - x * tz),
      v[2] + w * tz + (x * ty - y * tx),
    ];
  }

  /// between is the shortest turn that takes direction [a] to [b].
  static Quat between(List<double> a, List<double> b) {
    var ua = unit(a), ub = unit(b);
    var d = ua[0] * ub[0] + ua[1] * ub[1] + ua[2] * ub[2];
    if (d > 0.999999) return identity;
    if (d < -0.999999) {
      // Opposite: half a turn about any line square to them.
      var axis = cross(const [1, 0, 0], ua);
      if (length(axis) < 1e-6) axis = cross(const [0, 1, 0], ua);
      axis = unit(axis);
      return Quat(axis[0], axis[1], axis[2], 0);
    }
    var c = cross(ua, ub);
    return Quat(c[0], c[1], c[2], 1 + d).normalized;
  }

  /// slerp is the turn [t] of the way from [a] to [b].
  static Quat slerp(Quat a, Quat b, double t) {
    var d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    if (d < 0) {
      b = Quat(-b.x, -b.y, -b.z, -b.w);
      d = -d;
    }
    if (d > 0.9995) {
      return Quat(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t,
              a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t)
          .normalized;
    }
    var th = math.acos(d), s = math.sin(th);
    var ka = math.sin((1 - t) * th) / s, kb = math.sin(t * th) / s;
    return Quat(a.x * ka + b.x * kb, a.y * ka + b.y * kb, a.z * ka + b.z * kb,
        a.w * ka + b.w * kb);
  }
}

List<double> cross(List<double> a, List<double> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

double length(List<double> v) =>
    math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

List<double> unit(List<double> v) {
  var l = length(v);
  return l == 0 ? const [0, 1, 0] : [v[0] / l, v[1] / l, v[2] / l];
}

/// Mat4 is a place in 3D -- where, how turned, how big -- as a 4x4 matrix,
/// column by column.
class Mat4 {
  final Float64List m;
  Mat4(this.m);

  factory Mat4.identity() => Mat4(Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1);

  /// trs is moved by [t], turned by [r], sized by [s] -- in that order of
  /// meaning, which is scale first, then turn, then move.
  factory Mat4.trs(List<double> t, Quat r, List<double> s) {
    var x = r.x, y = r.y, z = r.z, w = r.w;
    var m = Float64List(16);
    m[0] = (1 - 2 * (y * y + z * z)) * s[0];
    m[1] = 2 * (x * y + z * w) * s[0];
    m[2] = 2 * (x * z - y * w) * s[0];
    m[4] = 2 * (x * y - z * w) * s[1];
    m[5] = (1 - 2 * (x * x + z * z)) * s[1];
    m[6] = 2 * (y * z + x * w) * s[1];
    m[8] = 2 * (x * z + y * w) * s[2];
    m[9] = 2 * (y * z - x * w) * s[2];
    m[10] = (1 - 2 * (x * x + y * y)) * s[2];
    m[12] = t[0];
    m[13] = t[1];
    m[14] = t[2];
    m[15] = 1;
    return Mat4(m);
  }

  Mat4 operator *(Mat4 b) {
    var o = Float64List(16);
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += m[k * 4 + r] * b.m[c * 4 + k];
        }
        o[c * 4 + r] = v;
      }
    }
    return Mat4(o);
  }

  List<double> point(double x, double y, double z) => [
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
      ];

  List<double> direction(double x, double y, double z) => [
        m[0] * x + m[4] * y + m[8] * z,
        m[1] * x + m[5] * y + m[9] * z,
        m[2] * x + m[6] * y + m[10] * z,
      ];

  List<double> get translation => [m[12], m[13], m[14]];

  /// rotation is the turn in this matrix, its scale taken out.
  Quat get rotation {
    var sx = length([m[0], m[1], m[2]]);
    var sy = length([m[4], m[5], m[6]]);
    var sz = length([m[8], m[9], m[10]]);
    var a = m[0] / sx, b = m[4] / sy, c = m[8] / sz;
    var d = m[1] / sx, e = m[5] / sy, f = m[9] / sz;
    var g = m[2] / sx, h = m[6] / sy, i = m[10] / sz;
    var trace = a + e + i;
    if (trace > 0) {
      var s = 0.5 / math.sqrt(trace + 1);
      return Quat((h - f) * s, (c - g) * s, (d - b) * s, 0.25 / s).normalized;
    }
    if (a > e && a > i) {
      var s = 2 * math.sqrt(1 + a - e - i);
      return Quat(0.25 * s, (b + d) / s, (c + g) / s, (h - f) / s).normalized;
    }
    if (e > i) {
      var s = 2 * math.sqrt(1 + e - a - i);
      return Quat((b + d) / s, 0.25 * s, (f + h) / s, (c - g) / s).normalized;
    }
    var s = 2 * math.sqrt(1 + i - a - e);
    return Quat((c + g) / s, (f + h) / s, 0.25 * s, (d - b) / s).normalized;
  }

  /// inverted is the matrix that undoes this one -- for one that moves,
  /// turns and sizes, which is every matrix a model has.
  Mat4 inverted() {
    var a = m;
    var o = Float64List(16);
    var b00 = a[0] * a[5] - a[1] * a[4], b01 = a[0] * a[6] - a[2] * a[4];
    var b02 = a[0] * a[7] - a[3] * a[4], b03 = a[1] * a[6] - a[2] * a[5];
    var b04 = a[1] * a[7] - a[3] * a[5], b05 = a[2] * a[7] - a[3] * a[6];
    var b06 = a[8] * a[13] - a[9] * a[12], b07 = a[8] * a[14] - a[10] * a[12];
    var b08 = a[8] * a[15] - a[11] * a[12], b09 = a[9] * a[14] - a[10] * a[13];
    var b10 = a[9] * a[15] - a[11] * a[13], b11 = a[10] * a[15] - a[11] * a[14];
    var det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    if (det.abs() < 1e-12) return Mat4.identity();
    var k = 1 / det;
    o[0] = (a[5] * b11 - a[6] * b10 + a[7] * b09) * k;
    o[1] = (a[2] * b10 - a[1] * b11 - a[3] * b09) * k;
    o[2] = (a[13] * b05 - a[14] * b04 + a[15] * b03) * k;
    o[3] = (a[10] * b04 - a[9] * b05 - a[11] * b03) * k;
    o[4] = (a[6] * b08 - a[4] * b11 - a[7] * b07) * k;
    o[5] = (a[0] * b11 - a[2] * b08 + a[3] * b07) * k;
    o[6] = (a[14] * b02 - a[12] * b05 - a[15] * b01) * k;
    o[7] = (a[8] * b05 - a[10] * b02 + a[11] * b01) * k;
    o[8] = (a[4] * b10 - a[5] * b08 + a[7] * b06) * k;
    o[9] = (a[1] * b08 - a[0] * b10 - a[3] * b06) * k;
    o[10] = (a[12] * b04 - a[13] * b02 + a[15] * b00) * k;
    o[11] = (a[9] * b02 - a[8] * b04 - a[11] * b00) * k;
    o[12] = (a[5] * b07 - a[4] * b09 - a[6] * b06) * k;
    o[13] = (a[0] * b09 - a[1] * b07 + a[2] * b06) * k;
    o[14] = (a[13] * b01 - a[12] * b03 - a[14] * b00) * k;
    o[15] = (a[8] * b03 - a[9] * b01 + a[10] * b00) * k;
    return Mat4(o);
  }
}

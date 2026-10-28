import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_extremities.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mesh_painter.dart';

// mannequin.dart builds a character's body in 3D from its rig: rounded
// pieces between the joints, the proportions the character has, coloured
// with its skin, its hair and what it is wearing.
//
// Built again on every frame from the joints, so it is posed by everything
// that poses the drawn figure -- pins, keyframes, motions, a camera's
// swing -- with nothing of its own to keep in step.

/// _V is a point in the body's space -- see CharacterRig.joints3.
typedef _V = List<double>;

_V _add(_V a, _V b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
_V _sub(_V a, _V b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
_V _mul(_V a, double k) => [a[0] * k, a[1] * k, a[2] * k];
_V _cross(_V a, _V b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];
double _dot(_V a, _V b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
double _len(_V a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
_V _unit(_V a, [_V fallback = const [0, 1, 0]]) {
  var l = _len(a);
  return l < 1e-9 ? fallback : _mul(a, 1 / l);
}

/// _Frame is three directions square to each other: a piece's across,
/// down and forward, in the body's space.
class _Frame {
  final _V x, y, z;
  const _Frame(this.x, this.y, this.z);

  static const _Frame body = _Frame([1, 0, 0], [0, 1, 0], [0, 0, 1]);

  /// of is the frame whose columns are [m]'s, a 3x3 row by row.
  factory _Frame.of(List<double> m) =>
      _Frame([m[0], m[3], m[6]], [m[1], m[4], m[7]], [m[2], m[5], m[8]]);

  _V on(double a, double b, double c) => [
        x[0] * a + y[0] * b + z[0] * c,
        x[1] * a + y[1] * b + z[1] * c,
        x[2] * a + y[2] * b + z[2] * c,
      ];
}

/// _Shape is one rounded lump of a mannequin: its colour, its points,
/// normals and triangles, and its middle.
class _Shape {
  final Color color;
  final List<double> pts = [], nrm = [];
  final List<int> idx = [];
  final _V centre;

  /// on is the shape this one sits on -- an eye on the head -- and is
  /// drawn just after, when it is on the side facing the reader; or -1.
  final int on;

  /// always draws it after [on] whichever way round it is: hair on a
  /// head, which covers it from every side.
  final bool always;
  _Shape(this.color, this.centre, this.on, this.always);
}

/// _Builder gathers the shapes.
class _Builder {
  final List<_Shape> _shapes = [];

  /// _on and _always are what the next shape added sits on -- see _Shape.
  int _on = -1;
  bool _always = false;

  /// last is the shape added most recently, for others to sit on.
  int get last => _shapes.length - 1;

  /// sittingOn adds what [add] adds as sitting on shape [on].
  void sittingOn(int on, void Function() add, {bool always = false}) {
    _on = on;
    _always = always;
    add();
    _on = -1;
    _always = false;
  }

  _Shape _start(Color c, _V centre) {
    var s = _Shape(c, centre, _on, _always);
    _shapes.add(s);
    return s;
  }

  /// ellipsoid is a rounded lump at [c], [rx] across, [ry] down and [rz]
  /// forward in [f] -- from the top down to [toLat], a share of the way
  /// round to the bottom, so a cap of hair is the top of one.
  void ellipsoid(Color color, _V c, _Frame f, double rx, double ry, double rz,
      {double toLat = 1, int rings = 9, int sides = 16}) {
    var shape = _start(color, c);
    var (pts, nrm, idx) = (shape.pts, shape.nrm, shape.idx);
    var first = 0;
    for (var r = 0; r <= rings; r++) {
      var lat = math.pi * toLat * r / rings;
      var sy = -math.cos(lat), sr = math.sin(lat);
      for (var s = 0; s <= sides; s++) {
        var lon = 2 * math.pi * s / sides;
        var ux = sr * math.sin(lon), uz = sr * math.cos(lon);
        var p = _add(c, f.on(ux * rx, sy * ry, uz * rz));
        // The normal of an ellipsoid is its point divided by its radii
        // twice over.
        var n = _unit(f.on(ux / rx, sy / ry, uz / rz));
        pts.addAll(p);
        nrm.addAll(n);
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < sides; s++) {
        var a = first + r * (sides + 1) + s, b = a + sides + 1;
        idx.addAll([a, b, a + 1, a + 1, b, b + 1]);
      }
    }
  }

  /// tube is a rounded piece from [a] to [b], [ra] thick at one end and
  /// [rb] at the other, its ends closed with balls.
  void tube(Color color, _V a, _V b, double ra, double rb,
      {int sides = 14, bool ends = true}) {
    var d = _sub(b, a);
    var length = _len(d);
    if (length < 1e-6) {
      ellipsoid(color, a, _Frame.body, ra, ra, ra);
      return;
    }
    var down = _mul(d, 1 / length);
    var ref = down[2].abs() > 0.9 ? const [1.0, 0.0, 0.0] : const [0.0, 0.0, 1.0];
    var across = _unit(_cross(down, ref));
    var forward = _cross(across, down);
    var shape = _start(color, _mul(_add(a, b), 0.5));
    var (pts, nrm, idx) = (shape.pts, shape.nrm, shape.idx);
    const first = 0;
    for (var (at, r) in [(a, ra), (b, rb)]) {
      for (var s = 0; s <= sides; s++) {
        var t = 2 * math.pi * s / sides;
        var n = _add(_mul(across, math.cos(t)), _mul(forward, math.sin(t)));
        pts.addAll(_add(at, _mul(n, r)));
        nrm.addAll(n);
      }
    }
    for (var s = 0; s < sides; s++) {
      var i = first + s, j = first + sides + 1 + s;
      idx.addAll([i, j, i + 1, i + 1, j, j + 1]);
    }
    if (ends) {
      // The ends rounded off, as part of the same lump.
      var f = _Frame(across, down, forward);
      for (var (at, r) in [(a, ra), (b, rb)]) {
        ellipsoid(color, at, f, r, r, r, rings: 6, sides: sides);
        var ball = _shapes.removeLast();
        var base = shape.pts.length ~/ 3;
        shape.pts.addAll(ball.pts);
        shape.nrm.addAll(ball.nrm);
        shape.idx.addAll([for (var i in ball.idx) i + base]);
      }
    }
  }

  /// loft is a smooth lump through [rings] -- each a loop of points the
  /// same number round -- closed at both ends: a body swept through its
  /// cross sections.
  /// [sortAt] is where it is sorted from, near or far, when not its middle.
  void loft(Color color, List<List<_V>> rings, {_V? sortAt}) {
    if (rings.length < 2) return;
    var sides = rings.first.length;
    _V centreOf(List<_V> ring) =>
        _mul(ring.fold<_V>(const [0.0, 0.0, 0.0], _add), 1 / ring.length);
    var centres = [for (var r in rings) centreOf(r)];
    var shape = _start(color, sortAt ?? centreOf(centres));
    var (pts, nrm, idx) = (shape.pts, shape.nrm, shape.idx);
    var n = rings.length;
    for (var r = 0; r < n; r++) {
      for (var k = 0; k < sides; k++) {
        var p = rings[r][k];
        var round = _sub(rings[r][(k + 1) % sides], rings[r][(k - 1 + sides) % sides]);
        var along = _sub(rings[math.min(r + 1, n - 1)][k], rings[math.max(r - 1, 0)][k]);
        var normal = _unit(_cross(round, along), _unit(_sub(p, centres[r])));
        // Out of the lump, whichever way round its rings go.
        var out = _sub(p, centres[r]);
        if (normal[0] * out[0] + normal[1] * out[1] + normal[2] * out[2] < 0) {
          normal = _mul(normal, -1);
        }
        pts.addAll(p);
        nrm.addAll(normal);
      }
    }
    for (var r = 0; r + 1 < n; r++) {
      for (var k = 0; k < sides; k++) {
        var a = r * sides + k, b = r * sides + (k + 1) % sides;
        var c = a + sides, d = b + sides;
        idx.addAll([a, c, b, b, c, d]);
      }
    }
    // Each end closed with a point at its middle.
    for (var (r, beyond) in [(0, 1), (n - 1, n - 2)]) {
      var at = pts.length ~/ 3;
      pts.addAll(centres[r]);
      nrm.addAll(_unit(_sub(centres[r], centres[beyond])));
      for (var k = 0; k < sides; k++) {
        idx.addAll([at, r * sides + k, r * sides + (k + 1) % sides]);
      }
    }
  }

  /// limb is one smooth piece through [joints], [radii] round at each --
  /// a whole arm or leg, bending at its middle joint with no seam there --
  /// its ends rounded off.
  void limb(Color color, List<_V> joints, List<double> radii,
      {int sides = 16, _V? sortAt}) {
    // Points along it, a few to each bone, each with its radius.
    var along = <(_V, double)>[];
    for (var i = 0; i + 1 < joints.length; i++) {
      const steps = 4;
      for (var k = 0; k < steps; k++) {
        var t = k / steps;
        along.add((_add(joints[i], _mul(_sub(joints[i + 1], joints[i]), t)),
            radii[i] + (radii[i + 1] - radii[i]) * t));
      }
    }
    along.add((joints.last, radii.last));
    _V tangent(int i) => _unit(_sub(along[math.min(i + 1, along.length - 1)].$1,
        along[math.max(i - 1, 0)].$1));
    // Each ring square to the way it runs, turned no more from the last
    // than it must, so the piece does not twist.
    var t0 = tangent(0);
    var side = _unit(_cross(t0, t0[2].abs() > 0.9 ? const [1.0, 0.0, 0.0] : const [0.0, 0.0, 1.0]));
    List<_V> ringAt(_V centre, _V t, double r) {
      side = _unit(_sub(side, _mul(t, side[0] * t[0] + side[1] * t[1] + side[2] * t[2])), side);
      var up = _cross(t, side);
      return [
        for (var k = 0; k < sides; k++)
          _add(centre, _add(_mul(side, r * math.cos(2 * math.pi * k / sides)),
              _mul(up, r * math.sin(2 * math.pi * k / sides)))),
      ];
    }

    var rings = <List<_V>>[];
    // A rounded end: rings closing in beyond the first point.
    const cap = 4;
    for (var k = cap; k >= 1; k--) {
      var a = k / cap * math.pi / 2;
      var (p, r) = along.first;
      rings.add(ringAt(_add(p, _mul(t0, -r * math.sin(a))), t0, r * math.cos(a)));
    }
    for (var (i, (p, r)) in along.indexed) {
      rings.add(ringAt(p, tangent(i), r));
    }
    var tn = tangent(along.length - 1);
    for (var k = 1; k <= cap; k++) {
      var a = k / cap * math.pi / 2;
      var (p, r) = along.last;
      rings.add(ringAt(_add(p, _mul(tn, r * math.sin(a))), tn, r * math.cos(a)));
    }
    loft(color, rings, sortAt: sortAt);
  }

  /// pieces is everything built, seen turned [yaw] degrees away from the
  /// reader, in pixels from the hips.
  List<MeshPiece> pieces(double yaw, {double tilt = 0, double ground = 0}) {
    var r = yaw * math.pi / 180, cy = math.cos(r), sy = math.sin(r);
    var t = tilt * math.pi / 180, ct = math.cos(t), st = math.sin(t);
    // Turned and tipped as CharacterRig turns a body onto the page, and y
    // made to run up.
    List<double> seen(double x, double y, double z, double g) {
      var near = x * sy + z * cy;
      return [
        x * cy - z * sy,
        -(g + (y - g) * ct + near * st),
        -(y - g) * st + near * ct,
      ];
    }

    double depthOf(_V p) => seen(p[0], p[1], p[2], ground)[2];
    var depths = [for (var s in _shapes) depthOf(s.centre)];
    var out = <MeshPiece>[];
    for (var (k, shape) in _shapes.indexed) {
      var depth = depths[k];
      if (shape.on >= 0) {
        var under = depths[shape.on];
        // On the far side of what it sits on, it is hidden by it.
        if (!shape.always && depth <= under) continue;
        depth = under + 1e-3 * (k + 1);
      }
      var (pts, nrm, idx) = (shape.pts, shape.nrm, shape.idx);
      var n = pts.length ~/ 3;
      var points = Float32List(n * 3), normals = Float32List(n * 3);
      for (var i = 0; i < n; i++) {
        var p = seen(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2], ground);
        points[i * 3] = p[0];
        points[i * 3 + 1] = p[1];
        points[i * 3 + 2] = p[2];
        var n = seen(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2], 0);
        normals[i * 3] = n[0];
        normals[i * 3 + 1] = n[1];
        normals[i * 3 + 2] = n[2];
      }
      var indices = Uint32List.fromList(idx);
      _outwards(points, normals, indices);
      out.add(MeshPiece(
          points: points,
          normals: normals,
          indices: indices,
          color: shape.color,
          depth: depth));
    }
    return out;
  }
}

/// _outwards turns each triangle of [indices] round so that it goes
/// anticlockwise seen from outside -- the way its corners' normals point
/// -- which is what the painter takes as facing the reader.
void _outwards(Float32List v, Float32List n, Uint32List ix) {
  for (var t = 0; t + 2 < ix.length; t += 3) {
    var a = ix[t] * 3, b = ix[t + 1] * 3, c = ix[t + 2] * 3;
    var ux = v[b] - v[a], uy = v[b + 1] - v[a + 1], uz = v[b + 2] - v[a + 2];
    var wx = v[c] - v[a], wy = v[c + 1] - v[a + 1], wz = v[c + 2] - v[a + 2];
    var gx = uy * wz - uz * wy, gy = uz * wx - ux * wz, gz = ux * wy - uy * wx;
    var ox = n[a] + n[b] + n[c],
        oy = n[a + 1] + n[b + 1] + n[c + 1],
        oz = n[a + 2] + n[b + 2] + n[c + 2];
    if (gx * ox + gy * oy + gz * oz < 0) {
      var keep = ix[t + 1];
      ix[t + 1] = ix[t + 2];
      ix[t + 2] = keep;
    }
  }
}

/// BodyColours is what each part of a body is coloured: its skin where
/// nothing covers it, and the outermost thing worn where something does.
class BodyColours {
  final Color skin, hair, eyes;
  Color torso, upperArm, foreArm, pelvis, thigh, shin, foot;
  Color? hat;

  BodyColours(CharacterDna dna)
      : skin = dna.skin,
        hair = dna.hair,
        eyes = dna.eyes,
        torso = dna.skin,
        upperArm = dna.skin,
        foreArm = dna.skin,
        pelvis = dna.skin,
        thigh = dna.skin,
        shin = dna.skin,
        foot = dna.skin {
    for (var g in dna.worn) {
      var c = g.color;
      switch (g.kind.shape) {
        case GarmentShape.torso:
          if (g.lengthOr >= 0.3) torso = c;
          if (g.lengthOr >= 0.95) pelvis = c;
          if (g.sleeveOr > 0.05) upperArm = c;
          if (g.sleeveOr > 0.6) foreArm = c;
        case GarmentShape.legs:
          pelvis = c;
          if (g.lengthOr > 0.2) thigh = c;
          if (g.lengthOr > 0.6) shin = c;
        case GarmentShape.skirt:
          pelvis = c;
          if (g.lengthOr > 0.3) thigh = c;
          if (g.lengthOr > 0.75) shin = c;
        case GarmentShape.dress:
          torso = c;
          pelvis = c;
          if (g.lengthOr > 0.3) thigh = c;
          if (g.lengthOr > 0.75) shin = c;
          if (g.sleeveOr > 0.05) upperArm = c;
          if (g.sleeveOr > 0.6) foreArm = c;
        case GarmentShape.shoes:
          foot = c;
        case GarmentShape.hat:
          hat = c;
        case GarmentShape.cape:
        case GarmentShape.glasses:
        case GarmentShape.neck:
          break;
      }
    }
  }
}

/// mannequinPieces is [dna] as a mannequin, posed as [rig] is and with the
/// face [face] has, in pixels from the rig's hips -- for paintMeshes,
/// with the hips as its origin.
List<MeshPiece> mannequinPieces(
    CharacterRig rig, CharacterDna dna, CharacterFace face) {
  var j = rig.joints3;
  _V at(RigJoint k) => j[k] ?? const [0.0, 0.0, 0.0];
  var u = rig.unit;
  var lk = dna.look;
  var colors = BodyColours(dna);
  var b = _Builder();

  // The body: a chest, a waist and a pelvis, each a rounded lump.
  var hips = at(RigJoint.hips), chest = at(RigJoint.chest);
  var across = _unit(_sub(at(RigJoint.shoulderR), at(RigJoint.shoulderL)),
      const [1, 0, 0]);
  var down = _unit(_sub(hips, chest));
  var forward = _unit(_cross(across, down), const [0, 0, 1]);
  across = _cross(down, forward);
  var trunk = _Frame(across, down, forward);
  var t = rig.torsoLength;
  // The waist first, so the chest and the pelvis -- as near the reader as
  // it is -- are drawn over its ends, and it shows only between them.
  var waist = 1 + 0.3 * lk[Look.waist] + 0.2 * lk[Look.belly];
  var belly = 1 + 0.45 * lk[Look.belly];
  var chestDeep = 1 + 0.35 * lk[Look.chest];
  b.ellipsoid(colors.torso, _add(chest, _mul(down, t * 0.66)), trunk,
      rig.shoulderHalf * 0.58 * waist, t * 0.28, rig.shoulderHalf * 0.36 * belly);
  b.ellipsoid(colors.pelvis, _add(hips, _mul(down, -t * 0.06)), trunk,
      rig.hipHalf * 0.98, t * 0.24, rig.hipHalf * 0.62 * (1 + 0.2 * lk[Look.belly]));
  b.ellipsoid(colors.torso, _add(chest, _mul(down, t * 0.3)), trunk,
      rig.shoulderHalf * 0.82, t * 0.36, rig.shoulderHalf * 0.46 * chestDeep);

  // Neck and head.
  var head = _Frame.of(rig.headBasis);
  var hs = rig.headScale;
  var turn = face[FaceControl.turn] * math.pi / 180;
  var nod = face[FaceControl.nod] * math.pi / 180;
  // The face's own turn and nod, on top of the head's tilt.
  var ct = math.cos(turn), st = math.sin(turn);
  var cn = math.cos(nod), sn = math.sin(nod);
  var hx = head.on(ct, 0, st);
  var hz0 = head.on(-st, 0, ct);
  var hy = _add(_mul(head.y, cn), _mul(hz0, -sn));
  var hz = _add(_mul(head.y, sn), _mul(hz0, cn));
  var skull = _Frame(hx, hy, hz);
  var headAt = at(RigJoint.head);
  var neck = at(RigJoint.neck);
  if (!dna.species.legless) {
    b.tube(colors.skin, _add(neck, _mul(down, t * 0.12)),
        _add(headAt, skull.on(0, u * 0.3 * hs, 0)), u * 0.12, u * 0.11,
        ends: false);
  }
  // As wide and long as the drawn head is.
  var radii = rig.headRadii;
  var rx = radii.width / 0.46 * 0.4 * hs, ry = radii.height * hs;
  var rz = u * 0.44 * hs;
  b.ellipsoid(colors.skin, headAt, skull, rx, ry, rz);
  var skullShape = b.last;
  void onHead(void Function() add, {bool always = false}) =>
      b.sittingOn(skullShape, add, always: always);
  var nose = 1 + 0.4 * lk[Look.noseWidth];
  var noseLong = 1 + 0.4 * lk[Look.noseLength];
  onHead(() => b.ellipsoid(colors.skin,
      _add(headAt, skull.on(0, u * 0.06 * hs, rz * 0.98)), skull,
      u * 0.055 * hs * nose, u * 0.08 * hs * noseLong,
      u * 0.06 * hs * (1 + 0.4 * lk[Look.noseBridge]),
      rings: 5, sides: 8));
  // Ears at the sides, as big as the drawn ones.
  var ear = 1 + 0.35 * lk[Look.earSize];
  for (var side in [-1.0, 1.0]) {
    onHead(() => b.ellipsoid(
        colors.skin,
        _add(headAt, skull.on(side * rx * 0.98, u * 0.06 * hs, -rz * 0.05)),
        skull,
        u * 0.04 * hs * (1 + 0.5 * lk[Look.earAngle]),
        u * 0.1 * hs * ear,
        u * 0.07 * hs * ear,
        rings: 5,
        sides: 8));
  }
  // Eyes, looking where the face looks and as open as it is.
  var open = face[FaceControl.eyesOpen].clamp(0.05, 1.3) *
      (1 - face[FaceControl.squint] * 0.5);
  var lookX = face[FaceControl.lookX] * rx * 0.12;
  var lookY = -face[FaceControl.lookY] * ry * 0.08;
  var eyeSize = 1 + 0.3 * lk[Look.eyeSize];
  var spacing = 1 + 0.22 * lk[Look.eyeSpacing];
  for (var side in [-1.0, 1.0]) {
    onHead(() => b.ellipsoid(
        colors.eyes,
        _add(
            headAt,
            skull.on(side * rx * 0.36 * spacing + lookX,
                -ry * 0.08 + lookY - lk[Look.eyeHeight] * u * 0.06 * hs, rz * 0.9)),
        skull,
        u * 0.055 * hs * eyeSize,
        u * 0.06 * hs * open * eyeSize * (1 - 0.3 * lk[Look.eyeShape]),
        u * 0.03 * hs,
        rings: 5,
        sides: 10));
  }
  // A mouth that opens as the face speaks.
  var jaw = face[FaceControl.jaw].clamp(0.0, 1.0);
  var mouth = face.mouth;
  if (mouth != MouthShape.rest && mouth != MouthShape.closed) {
    jaw = math.max(jaw, switch (mouth) {
      MouthShape.wide => 0.9,
      MouthShape.open => 0.6,
      MouthShape.round => 0.7,
      MouthShape.pucker => 0.35,
      _ => 0.25,
    });
  }
  var wide = mouth == MouthShape.pucker || mouth == MouthShape.round
      ? 0.6
      : 1 + face[FaceControl.smile] * 0.2;
  onHead(() => b.ellipsoid(
      Color.lerp(colors.skin, const Color(0xFF3A1414), 0.75)!,
      _add(headAt, skull.on(0, ry * 0.42, rz * 0.86)),
      skull,
      u * 0.1 * hs * wide,
      u * (0.012 + 0.07 * jaw) * hs,
      u * 0.04 * hs,
      rings: 5,
      sides: 10));
  // A beard: the lower face and chin in the hair's colour.
  var beard = lk[Look.beard];
  if (beard > 0.05) {
    var long = 1 + 0.5 * lk[Look.beardLength];
    onHead(
        () => b.ellipsoid(colors.hair,
            _add(headAt, skull.on(0, ry * 0.55 * long, rz * 0.35)), skull,
            rx * (0.45 + 0.5 * beard), ry * 0.45 * long, rz * 0.62),
        always: false);
  }
  if (dna.hairStyle != HairStyle.bald) {
    var curly = dna.hairStyle == HairStyle.curly ? 1.1 : 1.04;
    onHead(
        () => b.ellipsoid(colors.hair,
            _add(headAt, skull.on(0, -ry * 0.04, -rz * 0.04)), skull,
            rx * curly, ry * curly, rz * curly,
            toLat: 0.42),
        always: true);
    if (dna.hairStyle == HairStyle.long) {
      b.ellipsoid(colors.hair, _add(headAt, skull.on(0, ry * 0.5, -rz * 0.5)),
          skull, rx * 0.95, ry * 0.9, rz * 0.45);
    } else if (dna.hairStyle == HairStyle.bun) {
      b.ellipsoid(colors.hair, _add(headAt, skull.on(0, -ry * 0.75, -rz * 0.55)),
          skull, rx * 0.4, ry * 0.36, rz * 0.4);
    }
  }
  if (colors.hat case var hat?) {
    onHead(
        () => b.ellipsoid(hat, _add(headAt, skull.on(0, -ry * 0.18, 0)),
            skull, rx * 1.1, ry * 1.0, rz * 1.1,
            toLat: 0.4),
        always: true);
  }

  // Arms, with hands.
  var arm = rig.limbWidth * 0.5;
  for (var (s, e, w) in [
    (RigJoint.shoulderL, RigJoint.elbowL, RigJoint.wristL),
    (RigJoint.shoulderR, RigJoint.elbowR, RigJoint.wristR),
  ]) {
    b.tube(colors.upperArm, at(s), at(e), arm * 1.05, arm * 0.85);
    b.tube(colors.foreArm, at(e), at(w), arm * 0.85, arm * 0.7);
    var along = _unit(_sub(at(w), at(e)));
    b.ellipsoid(colors.skin, _add(at(w), _mul(along, u * 0.12)),
        _frameAlong(along, forward), arm * 0.8, u * 0.13, arm * 0.45,
        rings: 6, sides: 10);
  }
  // Legs, with feet.
  var leg = rig.legWidth * 0.5;
  for (var (h, k, a) in [
    (RigJoint.hipL, RigJoint.kneeL, RigJoint.ankleL),
    (RigJoint.hipR, RigJoint.kneeR, RigJoint.ankleR),
  ]) {
    if (dna.species.legless) break;
    b.tube(colors.thigh, at(h), at(k), leg * 1.1, leg * 0.85);
    b.tube(colors.shin, at(k), at(a), leg * 0.85, leg * 0.62);
    var shin = _unit(_sub(at(a), at(k)));
    // The foot points the way the shin's front does.
    var toe = _unit(_cross(across, shin), const [0, 0, 1]);
    var footFrame = _Frame(across, shin, toe);
    b.ellipsoid(colors.foot,
        _add(at(a), footFrame.on(0, u * 0.05, u * 0.09)), footFrame,
        leg * 0.75, u * 0.07, u * 0.19,
        rings: 6, sides: 12);
  }
  return b.pieces(rig.yaw, tilt: rig.tilt, ground: rig.ground);
}

/// _frameAlong is a frame pointing down [along], facing as near
/// [forward] as it can.
_Frame _frameAlong(_V along, _V forward) {
  var x = _unit(_cross(along, forward), const [1, 0, 0]);
  var z = _cross(x, along);
  return _Frame(x, along, z);
}

/// dollColour is the guide figure's grey.
const Color dollColour = Color(0xFFDADBDF);

/// dollPieces is the guide figure to pose and draw over -- see
/// character_doll.dart -- built from [rig] as the mannequin is: a smooth
/// grey body with no face, its proportions and its pose the rig's, its
/// hands and feet made as the drawn ones are. In pixels from the rig's
/// hips, for paintMeshes.
List<MeshPiece> dollPieces(CharacterRig rig, CharacterDna dna) {
  var j = rig.joints3;
  _V at(RigJoint k) => j[k] ?? const [0.0, 0.0, 0.0];
  var u = rig.unit;
  var lk = dna.look;
  const c = dollColour;
  var b = _Builder();

  // The trunk, swept from the neck to between the legs.
  var hips = at(RigJoint.hips), chest = at(RigJoint.chest);
  var across = _unit(_sub(at(RigJoint.shoulderR), at(RigJoint.shoulderL)),
      const [1, 0, 0]);
  var spine = _sub(hips, chest);
  var length = math.max(_len(spine), u * 0.2);
  var down = _unit(spine, const [0, 1, 0]);
  var forward = _unit(_cross(across, down), const [0, 0, 1]);
  across = _cross(down, forward);
  var trunk = _Frame(across, down, forward);
  var trunkMiddle = _add(chest, _mul(down, length * 0.55));
  var sh = rig.shoulderHalf, hip = rig.hipHalf;
  var neckR = u * 0.13;
  var waist = 1 + 0.3 * lk[Look.waist] + 0.2 * lk[Look.belly];
  var belly = 1 + 0.45 * lk[Look.belly];
  var chestDeep = 1 + 0.35 * lk[Look.chest];
  List<_V> ring(_V centre, _Frame f, double w, double d, {int sides = 20}) => [
        for (var k = 0; k < sides; k++)
          _add(centre, f.on(w * math.sin(2 * math.pi * k / sides), 0,
              d * math.cos(2 * math.pi * k / sides))),
      ];
  b.loft(c, [
    for (var (a, w, d, f) in [
      (-0.2, neckR, neckR * 0.95, 0.0),
      (-0.12, neckR * 1.7, neckR * 1.35, -0.02),
      (-0.05, sh * 0.72, sh * 0.36, 0.0),
      (0.04, sh * 0.94, sh * 0.42, 0.0),
      (0.17, sh * 0.92, sh * 0.48 * chestDeep, 0.03),
      (0.34, sh * 0.8, sh * 0.48 * chestDeep, 0.04),
      (0.52, sh * 0.62 * waist, sh * 0.4 * belly, 0.03),
      (0.68, sh * 0.58 * waist, sh * 0.38 * belly, 0.02),
      (0.82, hip * 0.97, hip * 0.58, 0.0),
      (0.96, hip * 1.06, hip * 0.62, 0.0),
      (1.08, hip * 1.0, hip * 0.6, 0.0),
      (1.18, hip * 0.76, hip * 0.48, 0.0),
      (1.25, hip * 0.36, hip * 0.3, 0.0),
    ])
      ring(_add(chest, trunk.on(0, a * length, f * sh)), trunk, w, d),
  ]);

  // The neck and the head: an egg, narrowing to the chin, with no face.
  var skull = _Frame.of(rig.headBasis);
  var hs = rig.headScale;
  var headAt = at(RigJoint.head);
  var radii = rig.headRadii;
  var rx = radii.width / 0.46 * 0.4 * hs, ry = radii.height * hs;
  var rz = u * 0.44 * hs;
  if (!dna.species.legless) {
    b.tube(c, _add(at(RigJoint.neck), _mul(down, length * 0.1)),
        _add(headAt, skull.on(0, ry * 0.3, -rz * 0.2)), neckR, neckR * 0.92,
        ends: false);
  }
  b.loft(c, [
    for (var r = 1; r < 14; r++)
      () {
        var lat = math.pi * r / 14;
        var sy = -math.cos(lat), sr = math.sin(lat);
        // Below the middle the jaw narrows to the chin, which comes forward.
        var k = sy > 0 ? 1 - 0.42 * sy * sy : 1.0;
        var ahead = sy > 0 ? sy * sy * rz * 0.12 : 0.0;
        return [
          for (var s = 0; s < 18; s++)
            _add(headAt, skull.on(sr * math.sin(2 * math.pi * s / 18) * rx * k,
                sy * ry, sr * math.cos(2 * math.pi * s / 18) * rz * k + ahead)),
        ];
      }(),
  ]);
  var headShape = b.last;
  for (var side in [-1.0, 1.0]) {
    b.sittingOn(headShape, () => b.ellipsoid(c,
        _add(headAt, skull.on(side * rx * 0.97, ry * 0.08, -rz * 0.05)), skull,
        u * 0.035 * hs, u * 0.09 * hs, u * 0.06 * hs,
        rings: 5, sides: 8));
  }

  // Arms, the shoulders rounded over them, and hands with fingers.
  var arm = rig.limbWidth * 0.5;
  var hand = rig.handRadius;
  for (var (limb, s, e, w) in [
    (CharacterLimb.armL, RigJoint.shoulderL, RigJoint.elbowL, RigJoint.wristL),
    (CharacterLimb.armR, RigJoint.shoulderR, RigJoint.elbowR, RigJoint.wristR),
  ]) {
    b.limb(c, [at(s), at(e), at(w)], [arm * 1.25, arm * 0.92, arm * 0.7]);
    var m = rig.frames[limb];
    if (m == null) continue;
    var frame = ExtremityFrame(rig, m);
    _V on((double, double, double) p) {
      var (x, y, z) = frame.body(p.$1, p.$2, p.$3);
      return _add(at(w), [x, y, z]);
    }

    b.loft(c, [
      for (var (y, wd, t) in handPalm)
        [
          for (var k = 0; k < 12; k++)
            on((hand * wd * math.cos(2 * math.pi * k / 12), hand * y,
                hand * t * math.sin(2 * math.pi * k / 12))),
        ],
    ]);
    for (var (joints, radii, _) in handJoints(rig, limb, hand)) {
      for (var i = 0; i + 1 < joints.length; i++) {
        b.tube(c, on(joints[i]), on(joints[i + 1]), radii[i], radii[i + 1],
            sides: 8);
      }
    }
  }

  // Legs, and feet made as the drawn ones are.
  var leg = rig.legWidth * 0.5;
  var foot = rig.footSize();
  for (var (limb, h, k, a) in [
    (CharacterLimb.legL, RigJoint.hipL, RigJoint.kneeL, RigJoint.ankleL),
    (CharacterLimb.legR, RigJoint.hipR, RigJoint.kneeR, RigJoint.ankleR),
  ]) {
    if (dna.species.legless) break;
    // The top of the thigh is in the hips, so it is sorted just behind
    // them -- in the order the two legs are -- and in front only as far as
    // the knee is lifted out in front.
    var middle = _mul(_add(at(h), at(k)), 0.5);
    var lifted = math.max(0.0,
        _dot(_sub(at(k), at(h)), forward) - hip * 0.6);
    b.limb(c, [at(h), at(k), at(a)], [leg * 1.45, leg * 0.98, leg * 0.66],
        sides: 18,
        sortAt: _add(
            _add(trunkMiddle, _mul(_sub(middle, trunkMiddle), 0.05)),
            _mul(forward, lifted * 2 - hip * 0.5)));
    if (rig.frames[limb] == null) continue;
    b.loft(c, [
      for (var r in footRings(rig, limb, foot))
        [for (var (x, y, z) in r) _add(at(a), [x, y, z])],
    ]);
  }
  return b.pieces(rig.yaw, tilt: rig.tilt, ground: rig.ground);
}

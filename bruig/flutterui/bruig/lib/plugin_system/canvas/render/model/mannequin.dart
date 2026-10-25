import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
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

  /// pieces is everything built, seen turned [yaw] degrees away from the
  /// reader, in pixels from the hips.
  List<MeshPiece> pieces(double yaw) {
    var r = yaw * math.pi / 180, cy = math.cos(r), sy = math.sin(r);
    // Turned as CharacterRig turns a body onto the page, and y made to run
    // up.
    double depthOf(_V p) => p[0] * sy + p[2] * cy;
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
        var x = pts[i * 3], y = pts[i * 3 + 1], z = pts[i * 3 + 2];
        points[i * 3] = x * cy - z * sy;
        points[i * 3 + 1] = -y;
        points[i * 3 + 2] = x * sy + z * cy;
        var nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
        normals[i * 3] = nx * cy - nz * sy;
        normals[i * 3 + 1] = -ny;
        normals[i * 3 + 2] = nx * sy + nz * cy;
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

/// _Colors is what each part of a mannequin is coloured: its skin where
/// nothing covers it, and the outermost thing worn where something does.
class _Colors {
  final Color skin, hair, eyes;
  Color torso, upperArm, foreArm, pelvis, thigh, shin, foot;
  Color? hat;

  _Colors(CharacterDna dna)
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
  var colors = _Colors(dna);
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
  b.ellipsoid(colors.torso, _add(chest, _mul(down, t * 0.66)), trunk,
      rig.shoulderHalf * 0.58, t * 0.28, rig.shoulderHalf * 0.36);
  b.ellipsoid(colors.pelvis, _add(hips, _mul(down, -t * 0.06)), trunk,
      rig.hipHalf * 0.98, t * 0.24, rig.hipHalf * 0.62);
  b.ellipsoid(colors.torso, _add(chest, _mul(down, t * 0.3)), trunk,
      rig.shoulderHalf * 0.82, t * 0.36, rig.shoulderHalf * 0.46);

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
  var rx = u * 0.4 * hs, ry = u * 0.5 * hs, rz = u * 0.44 * hs;
  b.ellipsoid(colors.skin, headAt, skull, rx, ry, rz);
  var skullShape = b.last;
  void onHead(void Function() add, {bool always = false}) =>
      b.sittingOn(skullShape, add, always: always);
  onHead(() => b.ellipsoid(colors.skin,
      _add(headAt, skull.on(0, u * 0.06 * hs, rz * 0.98)), skull,
      u * 0.055 * hs, u * 0.08 * hs, u * 0.06 * hs,
      rings: 5, sides: 8));
  // Eyes, looking where the face looks and as open as it is.
  var open = face[FaceControl.eyesOpen].clamp(0.05, 1.3) *
      (1 - face[FaceControl.squint] * 0.5);
  var lookX = face[FaceControl.lookX] * rx * 0.12;
  var lookY = -face[FaceControl.lookY] * ry * 0.08;
  for (var side in [-1.0, 1.0]) {
    onHead(() => b.ellipsoid(
        colors.eyes,
        _add(headAt,
            skull.on(side * rx * 0.36 + lookX, -ry * 0.08 + lookY, rz * 0.9)),
        skull,
        u * 0.055 * hs,
        u * 0.06 * hs * open,
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
  return b.pieces(rig.yaw);
}

/// _frameAlong is a frame pointing down [along], facing as near
/// [forward] as it can.
_Frame _frameAlong(_V along, _V forward) {
  var x = _unit(_cross(along, forward), const [1, 0, 0]);
  var z = _cross(x, along);
  return _Frame(x, along, z);
}

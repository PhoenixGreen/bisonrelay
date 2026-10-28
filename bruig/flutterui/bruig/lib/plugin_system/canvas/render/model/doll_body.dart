part of 'mannequin.dart';

// doll_body.dart is the guide figure a sketch is posed and drawn over --
// see character_doll.dart -- as a drawing figure is in a paint program:
// one smooth grey body, built from the character's rig so it is as tall,
// as big-headed and as posed as the character is, and shaped enough to
// tell each part of it -- chest and hips, shoulders, elbows and knees, a
// jaw, hands with fingers -- with the lines a figure is drawn by round
// it.
//
// Each part is a sweep through cross sections: their size along it a
// smooth curve through a few keys, and their shape round it an ellipse
// with soft bumps laid on -- a breast, a kneecap, a calf -- so it is one
// surface, with no seam where one shape meets the next.

/// dollColour is the guide figure's grey.
const Color dollColour = Color(0xFFDADBDF);

/// dollCentreLine and dollRingLine are the colours of the doll's guide
/// lines: the middle of each part, and the rings round it.
const Color dollCentreLine = Color(0xFFE8742A);
const Color dollRingLine = Color(0xFF8C8F98);

/// _keyed is the value at [t] of a smooth curve through [keys], each a
/// place along it and the value there, in order.
double _keyed(List<(double, double)> keys, double t) {
  if (t <= keys.first.$1) return keys.first.$2;
  if (t >= keys.last.$1) return keys.last.$2;
  var i = 0;
  while (keys[i + 1].$1 < t) {
    i++;
  }
  var (t0, v0) = keys[i];
  var (t1, v1) = keys[i + 1];
  var (tm, vm) = i > 0 ? keys[i - 1] : (t0 - (t1 - t0), v0);
  var (tp, vp) = i + 2 < keys.length ? keys[i + 2] : (t1 + (t1 - t0), v1);
  var h = t1 - t0, u = (t - t0) / h;
  // Through each key heading from the one before to the one after.
  var m0 = (v1 - vm) / (t1 - tm) * h, m1 = (vp - v0) / (tp - t0) * h;
  var u2 = u * u, u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * v0 +
      (u3 - 2 * u2 + u) * m0 +
      (-2 * u3 + 3 * u2) * v1 +
      (u3 - u2) * m1;
}

/// _bump is how much of a soft bump [x] gets, centred on [at], [size]
/// across.
double _bump(double x, double at, double size) {
  var d = (x - at) / size;
  return math.exp(-d * d);
}

/// _round is how far round from [b] angle [a] is, either way.
double _round(double a, double b) => math.atan2(math.sin(a - b), math.cos(a - b));

/// _squarish is [s] -- a sine or cosine -- pushed out towards the corners
/// by [n]: two for an ellipse, more for a squarer section.
double _squarish(double s, double n) =>
    s.sign * math.pow(s.abs(), 2 / n).toDouble();

extension _Sweep on _Builder {
  /// sweep is one smooth piece through [joints] -- an arm, a leg, a
  /// finger -- [radius] round at [t] along it (nought at the first joint,
  /// one at the last) and [theta] round it from its front, which faces
  /// [front] at its start. Its ends are rounded off.
  ///
  /// It is the shape added, and the ring each joint is at -- [sides]
  /// points to a ring -- for the lines drawn round it there.
  ///
  /// [colour], when given, is its colour at [t] along it: bands round it.
  (int, List<int>) sweep(Color color, List<_V> joints, _V front,
      double Function(double t, double theta) radius,
      {int steps = 8, int sides = 20, _V? sortAt, Color Function(double t)? colour}) {
    var bones = joints.length - 1;
    var along = <(_V, double)>[];
    var atJoint = <int>[];
    for (var i = 0; i < bones; i++) {
      atJoint.add(along.length);
      for (var k = 0; k < steps; k++) {
        along.add((_add(joints[i], _mul(_sub(joints[i + 1], joints[i]), k / steps)),
            (i + k / steps) / bones));
      }
    }
    atJoint.add(along.length);
    along.add((joints.last, 1));
    _V tangent(int i) => _unit(
        _sub(along[math.min(i + 1, along.length - 1)].$1, along[math.max(i - 1, 0)].$1));
    // Each ring square to the way it runs, its front turned no more from
    // the last ring's than it must, so the piece does not twist.
    var t0 = tangent(0);
    var up = _sub(front, _mul(t0, _dot(front, t0)));
    if (_len(up) < 1e-6) up = _cross(t0, const [1.0, 0.0, 0.0]);
    up = _unit(up);
    List<_V> ringAt(_V c, _V t, double tt, {double scale = 1}) {
      up = _unit(_sub(up, _mul(t, _dot(up, t))), up);
      var side = _cross(t, up);
      return [
        for (var k = 0; k < sides; k++)
          () {
            var th = 2 * math.pi * k / sides;
            var r = radius(tt, th) * scale;
            return _add(c, _add(_mul(up, r * math.cos(th)), _mul(side, r * math.sin(th))));
          }(),
      ];
    }

    double meanRadius(double tt) {
      var sum = 0.0;
      for (var k = 0; k < 8; k++) {
        sum += radius(tt, 2 * math.pi * k / 8);
      }
      return sum / 8;
    }

    const cap = 4;
    var rings = <List<_V>>[];
    for (var k = cap; k >= 1; k--) {
      var a = k / cap * math.pi / 2;
      rings.add(ringAt(_add(along.first.$1, _mul(t0, -meanRadius(0) * math.sin(a))), t0, 0,
          scale: math.cos(a)));
    }
    for (var (i, (p, tt)) in along.indexed) {
      rings.add(ringAt(p, tangent(i), tt));
    }
    var tn = tangent(along.length - 1);
    for (var k = 1; k <= cap; k++) {
      var a = k / cap * math.pi / 2;
      rings.add(ringAt(_add(along.last.$1, _mul(tn, meanRadius(1) * math.sin(a))), tn, 1,
          scale: math.cos(a)));
    }
    var shape = loft(color, rings,
        sortAt: sortAt,
        ringColours: colour == null
            ? null
            : [
                for (var k = 0; k < cap; k++) colour(0),
                for (var (_, tt) in along) colour(tt),
                for (var k = 0; k < cap; k++) colour(1),
              ]);
    return (shape, [for (var j in atJoint) j + cap]);
  }

  /// ringLine draws a guide line round ring [r] of shape [shape], [sides]
  /// points to a ring.
  void ringLine(int shape, int r, int sides, Color color, double width) =>
      stripe(shape, [for (var k = 0; k < sides; k++) r * sides + k], color, width,
          closed: true);

  /// lengthLine draws a guide line along shape [shape] through point [k]
  /// of each of rings [from] to [to].
  void lengthLine(int shape, int from, int to, int k, int sides, Color color, double width) =>
      stripe(shape, [for (var r = from; r <= to; r++) r * sides + k], color, width);
}

/// dollPieces is the guide figure to pose and draw over: built from
/// [rig] and shaped as [dna] is -- [feminine], from nought to one, how
/// much a woman's figure it has. In pixels from the rig's hips, for
/// paintMeshes.
///
/// [lens] is how strongly it is seen in perspective, nought for not at
/// all to one for a camera close up; [lines] draws the guide lines round
/// it -- the middle down its front and back, and rings round its parts.
List<MeshPiece> dollPieces(CharacterRig rig, CharacterDna dna,
    {double lens = 0, bool lines = false, double feminine = 0}) {
  var j = rig.joints3;
  _V at(RigJoint k) => j[k] ?? const [0.0, 0.0, 0.0];
  var u = rig.unit;
  var lk = dna.look;
  const c = dollColour;
  var b = _Builder();
  // Never under a pixel and a bit, where a line breaks into dashes.
  var line = math.max(u * 0.02, 1.6);
  var ring = line * 0.65;
  var she = feminine.clamp(0.0, 1.0);
  var muscle = lk[Look.muscle];

  // ---- the trunk, swept from the neck to between the legs ----
  var hips = at(RigJoint.hips), chest = at(RigJoint.chest);
  var across = _unit(_sub(at(RigJoint.shoulderR), at(RigJoint.shoulderL)), const [1, 0, 0]);
  var spine = _sub(hips, chest);
  var length = math.max(_len(spine), u * 0.2);
  var down = _unit(spine, const [0, 1, 0]);
  var forward = _unit(_cross(across, down), const [0, 0, 1]);
  across = _cross(down, forward);
  var trunkMiddle = _add(chest, _mul(down, length * 0.55));
  var sh = rig.shoulderHalf;
  var hip = rig.hipHalf * (1 + 0.1 * she);
  var neckR = u * 0.12 * (1 + 0.25 * lk[Look.neckWidth]);
  var waist = (1 + 0.25 * lk[Look.waist]) * (1 - 0.1 * she);
  var belly = 1 + 0.4 * lk[Look.belly];
  var chestFull = 1 + 0.3 * lk[Look.chest];
  var bust = she * (0.6 + 0.4 * lk[Look.chest]).clamp(0.2, 1.4);
  // The shoulders sloping from the neck -- the arms' own tops round them
  // off -- the waist in, and the hips no wider than the thighs below them
  // carry on from.
  var widths = [
    (-0.22, neckR),
    (-0.14, neckR * 2.1),
    (-0.06, sh * 0.66),
    (0.03, sh * 0.86),
    (0.14, sh * 0.88),
    (0.3, sh * 0.8 * (1 - 0.06 * she)),
    (0.48, sh * 0.66 * waist),
    (0.6, sh * 0.62 * waist),
    (0.74, hip * 0.86),
    (0.9, hip * 0.96),
    (1.0, hip * 0.97),
    (1.1, hip * 0.86),
    (1.18, hip * 0.52),
    (1.25, hip * 0.2),
  ];
  // Front and back apart: the chest and the belly come forward, and the
  // back is its own -- flat across the shoulder blades, in at the small of
  // it, the seat behind the hips no further out than a seat is.
  var frontDepths = [
    (-0.22, neckR * 0.95),
    (-0.14, neckR * 1.3),
    (-0.07, sh * 0.36),
    (0.04, sh * 0.44),
    (0.16, sh * 0.5 * chestFull),
    (0.32, sh * 0.48 * chestFull),
    (0.48, sh * 0.4),
    (0.62, sh * 0.38 * belly),
    (0.78, hip * 0.52 * belly),
    (0.92, hip * 0.55),
    (1.06, hip * 0.5),
    (1.18, hip * 0.4),
    (1.25, hip * 0.18),
  ];
  var backDepths = [
    (-0.22, neckR * 0.95),
    (-0.14, neckR * 1.3),
    (-0.07, sh * 0.4),
    (0.04, sh * 0.44),
    (0.16, sh * 0.45),
    (0.32, sh * 0.41),
    (0.48, sh * 0.35),
    (0.62, sh * 0.33),
    (0.78, hip * 0.46),
    (0.92, hip * 0.54),
    (1.04, hip * 0.52),
    (1.14, hip * 0.4),
    (1.25, hip * 0.18),
  ];
  // The spine's curve: the neck set back, the chest forward, the small of
  // the back in.
  var ahead = [(-0.22, -0.1), (-0.07, -0.04), (0.2, 0.03), (0.6, 0.0), (1.0, -0.02), (1.25, 0.0)];
  const torsoSides = 32, torsoRings = 34;
  double torsoAt(int r) => -0.22 + (1.25 + 0.22) * r / (torsoRings - 1);
  // Soft bumps laid on it, each where on it -- how far down, and how far
  // round from the front -- how big, and how far out.
  var bumps = <(double, double, double, double, double)>[
    // A woman's breasts, or a man's chest.
    for (var side in [-1.0, 1.0]) ...[
      (0.3, side * 0.62, 0.11, 0.42, sh * 0.32 * bust),
      (0.2, side * 0.5, 0.11, 0.5, sh * 0.06 * (1 - she) * (1 + muscle)),
      // Shoulder blades, and the seat.
      (0.14, math.pi + side * 0.55, 0.12, 0.45, sh * 0.05),
      (1.0, math.pi + side * 0.5, 0.1, 0.5, hip * 0.07 * (1 + 0.5 * she)),
    ],
    // A belly.
    (0.76, 0.0, 0.16, 0.8, hip * 0.14 * math.max(0.0, lk[Look.belly])),
  ];
  var torsoRingsList = <List<_V>>[];
  for (var r = 0; r < torsoRings; r++) {
    var a = torsoAt(r);
    var w = _keyed(widths, a), df = _keyed(frontDepths, a), db = _keyed(backDepths, a);
    // Squarer through the chest and hips, rounder at the neck.
    var n = 2 + 0.6 * _bump(a, 0.35, 0.5) + 0.4 * _bump(a, 1.0, 0.2);
    var centre = _add(chest, _add(_mul(down, a * length), _mul(forward, _keyed(ahead, a) * sh)));
    torsoRingsList.add([
      for (var k = 0; k < torsoSides; k++)
        () {
          var th = 2 * math.pi * k / torsoSides;
          var out = 0.0;
          for (var (ba, bt, sa, st, h) in bumps) {
            if (h == 0) continue;
            out += h * _bump(a, ba, sa) * _bump(_round(th, bt), 0, st);
          }
          var sx = _squarish(math.sin(th), n), cz = _squarish(math.cos(th), n);
          return _add(
              centre,
              _add(_mul(across, sx * w + math.sin(th) * out),
                  _mul(forward, cz * (cz > 0 ? df : db) + math.cos(th) * out)));
        }(),
    ]);
  }
  var torso = b.loft(c, torsoRingsList, sortAt: trunkMiddle);
  if (lines) {
    int rowAt(double a) => ((a + 0.22) / 1.47 * (torsoRings - 1)).round();
    b.lengthLine(torso, 1, torsoRings - 2, 0, torsoSides, dollCentreLine, line);
    b.lengthLine(torso, 1, torsoRings - 2, torsoSides ~/ 2, torsoSides, dollCentreLine, line);
    for (var k in [torsoSides ~/ 4, torsoSides * 3 ~/ 4]) {
      b.lengthLine(torso, rowAt(-0.05), rowAt(1.15), k, torsoSides, dollRingLine, ring);
    }
    for (var a in [0.44, 0.62, 0.98]) {
      b.ringLine(torso, rowAt(a), torsoSides, dollRingLine, ring);
    }
  }

  // ---- the neck and the head ----
  var skull = _Frame.of(rig.headBasis);
  var hs = rig.headScale;
  var headAt = at(RigJoint.head);
  var radii = rig.headRadii;
  var rx = radii.width / 0.46 * 0.42 * hs, ry = radii.height * hs;
  var rz = u * 0.46 * hs;
  if (!dna.species.legless) {
    var neckTop = _add(headAt, skull.on(0, ry * 0.45, -rz * 0.25));
    var neckBottom = _add(chest, _mul(down, -length * 0.12));
    b.sweep(c, [neckBottom, neckTop], forward, (t, th) => neckR * (1 + 0.08 * math.cos(th) * t),
        steps: 4, sides: 16, sortAt: _add(trunkMiddle, _mul(forward, -sh * 0.8)));
  }
  const headLat = 28, headLon = 32;
  var jaw = 1 + 0.25 * lk[Look.jaw];
  var chinLong = 1 + 0.2 * lk[Look.chinLength];
  var headRings = <List<_V>>[];
  for (var r = 1; r < headLat; r++) {
    var lat = math.pi * r / headLat;
    var sy = -math.cos(lat), sr = math.sin(lat);
    headRings.add([
      for (var k = 0; k < headLon; k++)
        () {
          var th = 2 * math.pi * k / headLon;
          var front = math.cos(th);
          // The cranium full and round behind; below the middle the jaw
          // narrowing to the chin, the chin coming forward and down.
          var narrow = sy > 0 ? 1 - (0.5 - 0.12 * jaw) * math.pow(sy, 1.5) : 1.0;
          var x = sr * math.sin(th) * rx * narrow;
          var z = sr * front * rz * (front < 0 ? (sy < 0.2 ? 1.08 : 0.92) : 1.0) * narrow;
          if (sy > 0 && front > 0) z += sy * sy * rz * 0.18 * front;
          var y = sy * ry * (sy > 0 ? chinLong : 1.0);
          // Hollows for the eyes, a brow over them, a nose between.
          var dent = 0.0;
          for (var side in [-1.0, 1.0]) {
            dent -= 0.07 * _bump(lat, math.pi * 0.56, 0.13) * _bump(_round(th, side * 0.42), 0, 0.2);
            dent += 0.03 * _bump(lat, math.pi * 0.49, 0.06) * _bump(_round(th, side * 0.4), 0, 0.3);
          }
          dent += 0.09 * _bump(lat, math.pi * 0.64, 0.07) * _bump(_round(th, 0), 0, 0.12);
          var p = [x, y, z];
          var l = _len(p);
          if (l > 0) p = _mul(p, 1 + dent * rz / l);
          return _add(headAt, skull.on(p[0], p[1], p[2]));
        }(),
    ]);
  }
  // Nearer than the neck and the top of the body, which it sits over.
  var head = b.loft(c, headRings, sortAt: _add(headAt, _mul(forward, sh * 0.6)));
  for (var side in [-1.0, 1.0]) {
    b.sittingOn(head, () => b.ellipsoid(c,
        _add(headAt, skull.on(side * rx * 0.94, ry * 0.12, -rz * 0.08)), skull,
        u * 0.04 * hs, u * 0.11 * hs, u * 0.075 * hs,
        rings: 6, sides: 10));
  }
  if (lines) {
    // The face's cross: down its middle and over the head, and round it
    // at the eyes.
    b.stripe(head, [
      for (var r = 0; r < headLat - 1; r++) r * headLon,
      for (var r = headLat - 2; r >= 0; r--) r * headLon + headLon ~/ 2,
    ], dollCentreLine, line, closed: true);
    b.ringLine(head, (headLat * 0.52).round(), headLon, dollRingLine, ring);
  }

  // ---- arms, shaped, and hands with fingers ----
  var arm = rig.limbWidth * 0.5 * (1 + 0.15 * lk[Look.armWidth]);
  var flex = 1 + 0.5 * muscle;
  // Bigger than a style draws them, to draw a hand over.
  var hand = rig.handRadius * 1.25;
  for (var (limb, s, e, w) in [
    (CharacterLimb.armL, RigJoint.shoulderL, RigJoint.elbowL, RigJoint.wristL),
    (CharacterLimb.armR, RigJoint.shoulderR, RigJoint.elbowR, RigJoint.wristR),
  ]) {
    var reach = math.max(0.0, _dot(_sub(at(e), at(s)), forward));
    // In front of the body only as far as it reaches out in front of it.
    var sortAt = _add(_mul(_add(at(s), at(e)), 0.5), _mul(forward, reach * 1.5 - sh * 0.45));
    var (shape, joints) = b.sweep(c, [at(s), at(e), at(w)], forward, (t, th) {
      var r = _keyed(const [
        (0.0, 1.34), (0.1, 1.3), (0.26, 1.1), (0.42, 0.9), (0.5, 0.85),
        (0.6, 0.95), (0.74, 0.86), (0.9, 0.7), (1.0, 0.64)
      ], t);
      var f = math.cos(th);
      // The biceps in front, the point of the elbow behind, the wrist
      // wider than it is deep.
      r += 0.12 * flex * _bump(t, 0.25, 0.1) * math.max(0.0, f);
      r += 0.1 * _bump(t, 0.5, 0.05) * math.max(0.0, -f);
      r *= 1 + 0.16 * _bump(t, 1, 0.2) * -math.cos(2 * th);
      return r * arm;
    }, sortAt: sortAt);
    if (lines) {
      b.lengthLine(shape, joints.first, joints.last, 0, 20, dollCentreLine, line * 0.85);
      for (var r in [joints[1], (joints[0] + joints[1]) ~/ 2, (joints[1] + joints[2]) ~/ 2]) {
        b.ringLine(shape, r, 20, dollRingLine, ring);
      }
    }
    var m = rig.frames[limb];
    if (m == null) continue;
    var frame = ExtremityFrame(rig, m);
    _V on((double, double, double) p) {
      var (x, y, z) = frame.body(p.$1, p.$2, p.$3);
      return _add(at(w), [x, y, z]);
    }

    // The palm: boxy, thick at the heel, from the wrist to the knuckles.
    b.loft(c, [
      for (var k = 0; k <= 8; k++)
        () {
          var y = -0.1 + 1.12 * k / 8;
          var keys = [for (var (py, pw, _) in handPalm) (py, pw)];
          var thick = [for (var (py, _, pt) in handPalm) (py, pt)];
          var wd = _keyed(keys, y) * (k == 0 || k == 8 ? 0.85 : 1);
          var th = _keyed(thick, y) * 1.1 * (k == 0 || k == 8 ? 0.8 : 1);
          return [
            for (var a = 0; a < 16; a++)
              on((hand * wd * _squarish(math.cos(2 * math.pi * a / 16), 3),
                  hand * y,
                  hand * th * _squarish(math.sin(2 * math.pi * a / 16), 3))),
          ];
        }(),
    ]);
    var back = frame.body(0, 0, 1);
    for (var (chain, radii, _) in handJoints(rig, limb, hand)) {
      var pts = [for (var p in chain) on(p)];
      var (finger, knuckles) = b.sweep(c, pts, [back.$1, back.$2, back.$3], (t, th) {
        var x = t * (radii.length - 1);
        var i = math.min(x.floor(), radii.length - 2);
        return radii[i] + (radii[i + 1] - radii[i]) * (x - i);
      }, steps: 3, sides: 10);
      if (lines) {
        for (var r in knuckles.skip(1).take(knuckles.length - 2)) {
          b.ringLine(finger, r, 10, dollRingLine, ring * 0.8);
        }
      }
    }
  }

  // ---- legs, shaped, and feet made as the drawn ones are ----
  var leg = rig.legWidth * 0.5 * (1 + 0.15 * lk[Look.legWidth]);
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
    var lifted = math.max(0.0, _dot(_sub(at(k), at(h)), forward) - hip * 0.6);
    var sortAt = _add(_add(trunkMiddle, _mul(_sub(middle, trunkMiddle), 0.05)),
        _mul(forward, lifted * 2 - hip * 0.5));
    var (shape, joints) = b.sweep(c, [at(h), at(k), at(a)], forward, (t, th) {
      var r = _keyed([
        (0.0, 1.75 + 0.15 * she), (0.1, 1.66 + 0.12 * she), (0.3, 1.28), (0.44, 1.02), (0.5, 0.97),
        (0.6, 1.0), (0.72, 0.92), (0.88, 0.68), (1.0, 0.6)
      ], t);
      var f = math.cos(th);
      // A kneecap in front, the calf behind.
      r += 0.13 * _bump(t, 0.5, 0.045) * math.max(0.0, f);
      r += 0.2 * flex * _bump(t, 0.64, 0.09) * math.max(0.0, -f * 0.8 + 0.2);
      return r * leg;
    }, sides: 22, sortAt: sortAt);
    if (lines) {
      b.lengthLine(shape, joints.first, joints.last, 0, 22, dollCentreLine, line * 0.85);
      for (var r in [joints[1], (joints[0] + joints[1]) ~/ 2, (joints[1] + joints[2]) ~/ 2]) {
        b.ringLine(shape, r, 22, dollRingLine, ring);
      }
    }
    if (rig.frames[limb] == null) continue;
    b.loft(c, [
      for (var r in footRings(rig, limb, foot))
        [for (var (x, y, z) in r) _add(at(a), [x, y, z])],
    ]);
  }
  return b.pieces(rig.yaw,
      tilt: rig.tilt,
      ground: rig.ground,
      lens: lens <= 0 ? 0 : u * dna.headsTall * (6 - 4.8 * lens.clamp(0.0, 1.0)));
}

/// The wooden doll's colours: its pale wood, the warmer wood of its trunk,
/// the tan of the joints it bends at, and its grey shoes.
const Color woodColour = Color(0xFFE4DFD5);
const Color woodTrunk = Color(0xFFE7CDA9);
const Color woodJoint = Color(0xFFCDA673);
const Color woodShoe = Color(0xFF8F9298);

/// woodenPieces is the guide figure as an artist's wooden doll, after
/// mannequin.js: a fluted barrel of a trunk and a bowl of a pelvis with a
/// ball between them, a ball at each shoulder and hip, a band at each
/// elbow, wrist and knee -- the points it bends at, in a warmer wood --
/// slim limbs, thighs fluted and full, grey shoes, and a carved head with
/// a face and grooves for hair. Built from [rig] as dollPieces is, in
/// pixels from the rig's hips.
List<MeshPiece> woodenPieces(CharacterRig rig, CharacterDna dna,
    {double lens = 0, double feminine = 0}) {
  var j = rig.joints3;
  _V at(RigJoint k) => j[k] ?? const [0.0, 0.0, 0.0];
  var u = rig.unit;
  var b = _Builder();
  const c = woodColour;
  var she = feminine.clamp(0.0, 1.0);

  var hips = at(RigJoint.hips), chest = at(RigJoint.chest);
  var across = _unit(_sub(at(RigJoint.shoulderR), at(RigJoint.shoulderL)), const [1, 0, 0]);
  var spine = _sub(hips, chest);
  var t = math.max(_len(spine), u * 0.2);
  var down = _unit(spine, const [0, 1, 0]);
  var forward = _unit(_cross(across, down), const [0, 0, 1]);
  across = _cross(down, forward);
  var trunk = _Frame(across, down, forward);
  var trunkMiddle = _add(chest, _mul(down, t * 0.5));
  var sh = rig.shoulderHalf, hip = rig.hipHalf * (1 + 0.1 * she);

  // A section round the trunk: [w] across and [d] deep, squarish, fluted.
  List<_V> section(double a, double w, double d, {int sides = 36, double flutes = 0.025}) => [
        for (var k = 0; k < sides; k++)
          () {
            var th = 2 * math.pi * k / sides;
            var groove = 1 + flutes * math.cos(12 * th);
            return _add(
                _add(chest, _mul(down, a * t)),
                _add(_mul(across, _squarish(math.sin(th), 2.6) * w * groove),
                    _mul(forward, _squarish(math.cos(th), 2.4) * d * groove)));
          }(),
      ];

  // The trunk: broad at the shoulders, in to the waist, rounded off.
  const chestKeys = [
    (-0.13, 0.36), (-0.08, 0.68), (0.0, 0.84), (0.12, 0.86), (0.3, 0.8), (0.46, 0.7), (0.56, 0.64), (0.61, 0.45),
  ];
  var bust = 1 + 0.12 * she;
  var trunkRings = [
    for (var r = 0; r < 18; r++)
      () {
        var a = -0.13 + 0.74 * r / 17;
        var w = _keyed(chestKeys, a) * sh;
        var d = sh * 0.42 * _keyed([(-0.13, 0.7), (0.0, 0.95), (0.2, bust), (0.5, 0.92), (0.61, 0.6)], a);
        return section(a, w, d);
      }(),
  ];
  var torso = b.loft(c, trunkRings,
      sortAt: trunkMiddle,
      ringColours: [
        for (var r = 0; r < 18; r++) Color.lerp(woodTrunk, const Color(0xFFEBDDC6), r / 17)!,
      ]);
  // The ball it bends at, and the pelvis below.
  b.ellipsoid(woodJoint, _add(chest, _mul(down, t * 0.66)), trunk, sh * 0.34, t * 0.1, sh * 0.3,
      rings: 8, sides: 18);
  const pelvisKeys = [(0.66, 0.62), (0.74, 0.9), (0.86, 1.08), (0.98, 1.1), (1.08, 0.95), (1.16, 0.62), (1.2, 0.3)];
  var pelvis = b.loft(c, [
    for (var r = 0; r < 14; r++)
      () {
        var a = 0.66 + 0.54 * r / 13;
        var w = _keyed(pelvisKeys, a) * hip;
        return section(a, w, w * 0.62, flutes: 0.03);
      }(),
  ], sortAt: _add(hips, _mul(forward, -hip * 0.05)));
  // The balls at the shoulders and the hips, over the trunk and the pelvis.
  var arm = rig.limbWidth * 0.5;
  var leg = rig.legWidth * 0.5;
  for (var s in [RigJoint.shoulderL, RigJoint.shoulderR]) {
    b.sittingOn(torso, () => b.ellipsoid(woodJoint, at(s), trunk, arm * 1.55, arm * 1.45, arm * 1.5,
        rings: 10, sides: 16), always: true);
  }
  for (var h in [RigJoint.hipL, RigJoint.hipR]) {
    // At the top of the thigh, to the outside: a cap, not a ball out front.
    var out = _mul(across, (h == RigJoint.hipL ? -1.0 : 1.0) * leg * 0.45);
    b.sittingOn(pelvis, () => b.ellipsoid(woodJoint, _add(_add(at(h), out), _mul(down, leg * 1.0)),
        trunk, leg * 1.2, leg * 0.9, leg * 1.05, rings: 10, sides: 16), always: true);
  }

  // The neck, and the head carved over it: a face, and grooves for hair.
  var skull = _Frame.of(rig.headBasis);
  var hs = rig.headScale;
  var headAt = at(RigJoint.head);
  var radii = rig.headRadii;
  var rx = radii.width / 0.46 * 0.4 * hs, ry = radii.height * hs, rz = u * 0.44 * hs;
  var neckR = u * 0.095;
  b.sweep(c, [_add(chest, _mul(down, -t * 0.1)), _add(headAt, skull.on(0, ry * 0.7, -rz * 0.1))],
      forward, (tt, th) => neckR * (1 - 0.1 * tt), steps: 3, sides: 14);
  var neckPiece = b.last;
  b.sittingOn(neckPiece, () {
    const lats = 26, lons = 32;
    b.loft(c, [
      for (var r = 1; r < lats; r++)
        () {
          var lat = math.pi * r / lats;
          var sy = -math.cos(lat), sr = math.sin(lat);
          return [
            for (var s = 0; s < lons; s++)
              () {
                var th = 2 * math.pi * s / lons;
                var front = math.cos(th);
                var narrow = sy > 0 ? 1 - 0.42 * math.pow(sy, 1.5) : 1.0;
                var x = sr * math.sin(th) * rx * narrow;
                var z = sr * front * rz * narrow;
                if (sy > 0 && front > 0) z += sy * sy * rz * 0.15 * front;
                var p = [x, sy * ry, z];
                var dent = 0.0;
                // Eyes set in, a brow, a nose, lips.
                for (var side in [-1.0, 1.0]) {
                  dent -= 0.09 * _bump(lat, math.pi * 0.55, 0.08) * _bump(_round(th, side * 0.36), 0, 0.17);
                  dent += 0.03 * _bump(lat, math.pi * 0.49, 0.05) * _bump(_round(th, side * 0.36), 0, 0.25);
                }
                dent += 0.12 * _bump(lat, math.pi * 0.63, 0.06) * _bump(_round(th, 0), 0, 0.1);
                dent += 0.04 * _bump(lat, math.pi * 0.73, 0.03) * _bump(_round(th, 0), 0, 0.22);
                // Grooves of hair over the crown and down the back.
                var hair = sy < -0.15 || (front < -0.2 && sy < 0.25);
                if (hair) dent += 0.025 * math.cos(22 * th) * math.min(1, (0.25 - sy).abs() * 4);
                var l = _len(p);
                if (l > 0) p = _mul(p, 1 + dent * rz / l);
                return _add(headAt, skull.on(p[0], p[1], p[2]));
              }(),
          ];
        }(),
    ], sortAt: headAt);
  }, always: true);

  // Arms, each one piece from the shoulder, its elbow and wrist banded.
  var hand = rig.handRadius * 1.25;
  Color band(double tt, List<double> at, double width) {
    for (var a in at) {
      if ((tt - a).abs() < width) return woodJoint;
    }
    return c;
  }

  for (var (limb, s, e, w) in [
    (CharacterLimb.armL, RigJoint.shoulderL, RigJoint.elbowL, RigJoint.wristL),
    (CharacterLimb.armR, RigJoint.shoulderR, RigJoint.elbowR, RigJoint.wristR),
  ]) {
    var reach = math.max(0.0, _dot(_sub(at(e), at(s)), forward));
    b.sweep(c, [at(s), at(e), at(w)], forward, (tt, th) {
      var r = _keyed(const [(0.0, 1.15), (0.2, 1.1), (0.44, 0.92), (0.5, 1.12), (0.56, 0.95),
        (0.7, 1.0), (0.92, 0.72), (0.97, 0.85), (1.0, 0.68)], tt);
      return r * arm;
    },
        steps: 10,
        sides: 16,
        colour: (tt) => band(tt, const [0.5, 0.975], 0.035),
        sortAt: _add(_mul(_add(at(s), at(e)), 0.5), _mul(forward, reach * 1.5 - sh * 0.45)));
    var m = rig.frames[limb];
    if (m == null) continue;
    var frame = ExtremityFrame(rig, m);
    _V on((double, double, double) p) {
      var (x, y, z) = frame.body(p.$1, p.$2, p.$3);
      return _add(at(w), [x, y, z]);
    }

    b.loft(c, [
      for (var (y, wd, th) in handPalm)
        [
          for (var a = 0; a < 14; a++)
            on((hand * wd * 0.95 * math.cos(2 * math.pi * a / 14), hand * y,
                hand * th * 0.9 * math.sin(2 * math.pi * a / 14))),
        ],
    ]);
    for (var (chain, radii, _) in handJoints(rig, limb, hand)) {
      b.sweep(c, [for (var p in chain) on(p)], forward, (tt, _) {
        var x = tt * (radii.length - 1);
        var i = math.min(x.floor(), radii.length - 2);
        return (radii[i] + (radii[i + 1] - radii[i]) * (x - i)) * 0.95;
      }, steps: 2, sides: 8);
    }
  }

  // Legs: full fluted thighs, a band at the knee, slim shins, grey shoes.
  var foot = rig.footSize();
  for (var (limb, h, k, a) in [
    (CharacterLimb.legL, RigJoint.hipL, RigJoint.kneeL, RigJoint.ankleL),
    (CharacterLimb.legR, RigJoint.hipR, RigJoint.kneeR, RigJoint.ankleR),
  ]) {
    if (dna.species.legless) break;
    var middle = _mul(_add(at(h), at(k)), 0.5);
    var lifted = math.max(0.0, _dot(_sub(at(k), at(h)), forward) - hip * 0.6);
    b.sweep(c, [at(h), at(k), at(a)], forward, (tt, th) {
      var r = _keyed(const [(0.0, 1.55), (0.15, 1.6), (0.38, 1.25), (0.46, 1.0), (0.5, 1.18),
        (0.54, 0.98), (0.64, 1.02), (0.85, 0.72), (1.0, 0.62)], tt);
      if (tt < 0.45) r *= 1 + 0.03 * math.cos(10 * th);
      return r * leg;
    },
        steps: 10,
        sides: 20,
        colour: (tt) => band(tt, const [0.5], 0.035),
        sortAt: _add(_add(trunkMiddle, _mul(_sub(middle, trunkMiddle), 0.05)),
            _mul(forward, lifted * 2 - hip * 0.5)));
    if (rig.frames[limb] == null) continue;
    b.loft(woodShoe, [
      for (var r in footRings(rig, limb, foot))
        [for (var (x, y, z) in r) _add(at(a), [x, y, z])],
    ]);
  }
  return b.pieces(rig.yaw,
      tilt: rig.tilt,
      ground: rig.ground,
      lens: lens <= 0 ? 0 : u * dna.headsTall * (6 - 4.8 * lens.clamp(0.0, 1.0)));
}

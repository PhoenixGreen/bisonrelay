import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';

// character_extremities.dart is a sketch's hands and feet as seen: made in
// 3D on the frame the rig gives the end of each limb, then laid on the page
// as the body is, so a hand turned away shows its edge and a foot seen
// from the front is its toes. What the painter fills and the puppet's pins
// sit on are both made here, so they agree. See character_hands.dart.
//
// A hand is a palm, four fingers of three bones each and a thumb of two,
// each a tapered rod that curls towards the palm. A foot is two pieces --
// heel to ball, ball to toes -- swept through cross sections, the toes
// bending up at the ball.

/// ExtremityFrame is the frame a hand or a foot is made on, as the rig has
/// it: a turn in the body's space, row by row, seen on the page as the body
/// is.
class ExtremityFrame {
  final CharacterRig rig;
  final List<double> m;
  const ExtremityFrame(this.rig, this.m);

  (double, double, double) _body(double x, double y, double z) => (
        m[0] * x + m[1] * y + m[2] * z,
        m[3] * x + m[4] * y + m[5] * z,
        m[6] * x + m[7] * y + m[8] * z,
      );

  /// body is how far from the frame's middle, in the body's own space --
  /// see CharacterRig.joints3 -- [x], [y], [z] of its own space is.
  (double, double, double) body(double x, double y, double z) => _body(x, y, z);

  /// at is how far from the frame's middle, on the page, [x], [y], [z] of
  /// its own space is.
  Offset at(double x, double y, double z) {
    var (a, b, c) = _body(x, y, z);
    return rig.stepOnPage(a, b, c);
  }

  /// depth is how much nearer the reader than the frame's middle it is.
  double depth(double x, double y, double z) {
    var (a, b, c) = _body(x, y, z);
    return rig.stepDepth(a, b, c);
  }

  /// down is how far below the frame's middle it is, in the body's space.
  double down(double x, double y, double z) => _body(x, y, z).$2;
}

// ---- feet ----

/// FootSize is how big a foot is: how long from the heel to the toes, half
/// as wide across, and how far its sole is below the ankle.
class FootSize {
  final double length;
  final double half;
  final double drop;
  const FootSize(this.length, this.half, this.drop);

  /// of is a foot under a leg [legWidth] thick, shaped as [look] has it:
  /// a slender ankle stands on a small foot.
  factory FootSize.of(double legWidth, Appearance look, double drop) {
    var slender = 0.75 + 0.25 * (1 + 0.45 * look[Look.ankles]);
    var big = 1 + 0.25 * look[Look.feet];
    return FootSize(
        legWidth * 2.1 * slender * big, legWidth * 0.62 * slender * big, drop);
  }
}

/// A foot's cross sections, heel to toes: how far forward of the ankle, as
/// a share of its length; how wide, as a share of its half width; and how
/// tall, as a share of the drop to the sole -- which they all stand on.
const List<(double, double, double)> _heelToBall = [
  (-0.3, 0.45, 0.42),
  (-0.26, 0.7, 0.8),
  (-0.12, 0.82, 1.0),
  (0.12, 0.88, 1.05),
  (0.42, 1.0, 0.8),
];
const List<(double, double, double)> _ballToToes = [
  (0.42, 1.0, 0.8),
  (0.62, 0.95, 0.72),
  (0.72, 0.78, 0.6),
  (0.77, 0.45, 0.4),
];

/// _ball is how far forward the ball of the foot is, as a share of its
/// length: where the toes bend.
const double _ball = 0.42;

/// footOutward is how far out from under the ankle a foot stands, as a
/// share of the leg's width.
const double footOutward = 0.22;

/// _toesTurned is [f] forward and [d] down of the foot's own space with the
/// toes bent [toes] degrees up at the ball, when [front] is of the toes.
(double, double) _toesTurned(
    double f, double d, double toes, FootSize s, bool front) {
  if (!front || toes == 0) return (f, d);
  var t = toes * math.pi / 180, c = math.cos(t), sn = math.sin(t);
  var bf = _ball * s.length, bd = s.drop;
  var x = f - bf, y = d - bd;
  return (bf + x * c + y * sn, bd - x * sn + y * c);
}

/// footBottoms is the heel, the ball and the tip of the toes of a foot
/// [s] big, its toes bent [toes] degrees -- each forward, down and out of
/// the foot's own space -- what stands on the ground.
List<(double, double, double)> footBottoms(
    FootSize s, double toes, double outward) {
  (double, double, double) at(double f, bool front) {
    var (ff, dd) = _toesTurned(f * s.length, s.drop, toes, s, front);
    return (outward, dd, ff);
  }

  return [at(-0.26, false), at(_ball, false), at(0.76, true)];
}

/// FootShape is a foot as seen: its two pieces' outlines, on the page from
/// the ankle, how near the reader each is, and where the tip of its toes
/// is.
class FootShape {
  final List<Offset> heel;
  final List<Offset> toes;
  final double heelDepth;
  final double toesDepth;
  final Offset tip;
  const FootShape(this.heel, this.toes, this.heelDepth, this.toesDepth, this.tip);

  Path get path => Path.combine(PathOperation.union,
      Path()..addPolygon(heel, true), Path()..addPolygon(toes, true));
}

/// footShape is the foot on the end of [leg], [s] big, seen as [rig] lays
/// it out: [scale] times as long and wide -- a shoe over it bigger than a
/// bare foot -- and [tall] times as tall; [sole] only the bottom of it, as
/// deep as that share of the drop.
FootShape footShape(CharacterRig rig, CharacterLimb leg, FootSize s,
    {double scale = 1, double tall = 1, double? sole, double above = 0}) {
  var frame = ExtremityFrame(rig, rig.frames[leg]!);
  var toes = rig.toes[leg] ?? 0;
  var out = rig.legWidth * footOutward;
  const ring = 12;
  (List<Offset>, double) piece(List<(double, double, double)> sections,
      bool front) {
    var pts = <Offset>[];
    var depth = 0.0;
    for (var (f, w, h) in sections) {
      var half = s.half * w * scale;
      var height = s.drop * h * tall;
      if (sole != null) height = math.min(height, s.drop * sole);
      // Standing [above] the sole's share of the drop off the ground: a
      // shoe's upper, on its sole.
      var centre = s.drop * (1 - above) - height / 2;
      for (var k = 0; k < ring; k++) {
        var a = k / ring * math.pi * 2;
        var (ff, dd) = _toesTurned(f * s.length * scale,
            centre + height / 2 * math.sin(a), toes, s, front);
        var x = out + half * math.cos(a);
        pts.add(frame.at(x, dd, ff));
      }
      var (ff, dd) = _toesTurned(f * s.length * scale, centre, toes, s, front);
      depth += frame.depth(out, dd, ff);
    }
    return (convexHull(pts), depth / sections.length);
  }

  var (heel, hd) = piece(_heelToBall, false);
  var (toesPiece, td) = piece(_ballToToes, true);
  var (tf, tdn) =
      _toesTurned(0.76 * s.length * scale, s.drop * 0.85, toes, s, true);
  return FootShape(heel, toesPiece, hd, td, frame.at(out, tdn, tf));
}

/// footRings is the foot on the end of [leg], [s] big, as rings round
/// it, heel to toes, [sides] points each: each point in the body's own
/// space from the ankle -- see CharacterRig.joints3 -- for a foot made in
/// 3D.
List<List<(double, double, double)>> footRings(
    CharacterRig rig, CharacterLimb leg, FootSize s, {int sides = 12}) {
  var frame = ExtremityFrame(rig, rig.frames[leg]!);
  var toes = rig.toes[leg] ?? 0;
  var out = rig.legWidth * footOutward;
  return [
    for (var (sections, front) in [(_heelToBall, false), (_ballToToes.skip(1), true)])
      for (var (f, w, h) in sections)
        [
          for (var k = 0; k < sides; k++)
            () {
              var a = k / sides * math.pi * 2;
              var height = s.drop * h;
              var centre = s.drop - height / 2;
              var (ff, dd) = _toesTurned(
                  f * s.length, centre + height / 2 * math.sin(a), toes, s, front);
              return frame.body(out + s.half * w * math.cos(a), dd, ff);
            }(),
        ],
  ];
}

/// strapAt is a strap over the top of the foot [at] of the way from the
/// heel to the toes, as a line on the page from the ankle.
List<Offset> strapAt(CharacterRig rig, CharacterLimb leg, FootSize s, double at) {
  var frame = ExtremityFrame(rig, rig.frames[leg]!);
  var out = rig.legWidth * footOutward;
  var f = (-0.27 + at * 0.99);
  var (_, w, h) = f < _ball
      ? _heelToBall.lastWhere((c) => c.$1 <= f, orElse: () => _heelToBall.first)
      : _ballToToes.lastWhere((c) => c.$1 <= f, orElse: () => _ballToToes.first);
  var half = s.half * w * 1.02, height = s.drop * h;
  var centre = s.drop - height / 2;
  return [
    for (var k = 0; k <= 10; k++)
      () {
        var a = math.pi + k / 10 * math.pi;
        var (ff, dd) = _toesTurned(f * s.length, centre + height / 2 * math.sin(a),
            rig.toes[leg] ?? 0, s, f > _ball);
        return frame.at(out + half * math.cos(a), dd, ff);
      }(),
  ];
}

// ---- hands ----

/// HandPiece is one piece of a hand as seen -- the palm, a bone of a
/// finger -- its outline on the page from the wrist, and how near the
/// reader it is.
class HandPiece {
  final List<Offset> outline;
  final double depth;
  const HandPiece(this.outline, this.depth);
}

/// Each finger's bones, as shares of the hand's size, index first: their
/// lengths, and how far across the knuckles it stands -- the thumb's side
/// positive.
const List<List<double>> _fingerBones = [
  [0.42, 0.26, 0.2],
  [0.46, 0.29, 0.21],
  [0.43, 0.27, 0.2],
  [0.33, 0.21, 0.17],
];
const List<double> _knuckles = [0.4, 0.13, -0.14, -0.39];

/// How much of a finger's curl each knuckle takes: the first the most, the
/// last less.
const List<double> _fold = [1, 1.08, 0.78];

/// handPieces is the hand on the end of [arm], [r] its size, as [rig] lays
/// it out: the palm and each bone of each finger, the thumb's too -- a
/// finger left straight as one piece -- farthest from the reader first.
List<HandPiece> handPieces(CharacterRig rig, CharacterLimb arm, double r) {
  var frame = ExtremityFrame(rig, rig.frames[arm]!);
  var pieces = <HandPiece>[];

  // The palm: swept from the wrist to the knuckles, wider there.
  var palm = <Offset>[];
  for (var (y, w, t) in handPalm) {
    for (var k = 0; k < 12; k++) {
      var a = k / 12 * math.pi * 2;
      palm.add(frame.at(r * w * math.cos(a), r * y, r * t * math.sin(a)));
    }
  }
  pieces.add(HandPiece(convexHull(palm), frame.depth(0, r * 0.55, 0)));

  void rods(List<(double, double, double)> joints, List<double> radii,
      {bool together = false}) {
    var seen = [for (var (x, y, z) in joints) frame.at(x, y, z)];
    var widths = radii;
    if (together) {
      var all = <Offset>[];
      for (var i = 0; i + 1 < seen.length; i++) {
        all.addAll(rod(seen[i], widths[i], seen[i + 1], widths[i + 1]));
      }
      var (x, y, z) = joints[joints.length ~/ 2];
      pieces.add(HandPiece(convexHull(all), frame.depth(x, y, z)));
      return;
    }
    for (var i = 0; i + 1 < seen.length; i++) {
      var (x0, y0, z0) = joints[i];
      var (x1, y1, z1) = joints[i + 1];
      pieces.add(HandPiece(rod(seen[i], widths[i], seen[i + 1], widths[i + 1]),
          frame.depth((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) + r * 0.01));
    }
  }

  for (var (joints, radii, together) in handJoints(rig, arm, r)) {
    rods(joints, radii, together: together);
  }

  pieces.sort((a, b) => a.depth.compareTo(b.depth));
  return pieces;
}

/// FingerChain is a finger's joints in its hand's own space -- see
/// CharacterRig.frames -- how round it is at each, and whether it is
/// straight enough to be drawn as one piece.
typedef FingerChain = (List<(double, double, double)>, List<double>, bool);

/// handPalm is the palm's cross sections, wrist to knuckles: how far along
/// the hand, how wide and how thick, as shares of the hand's size.
const List<(double, double, double)> handPalm = [
  (-0.08, 0.42, 0.17),
  (0.55, 0.6, 0.2),
  (1.02, 0.6, 0.15),
];

/// handJoints is each finger of the hand on the end of [arm], [r] its
/// size, as [rig] has it curled and spread: the four, index first, then
/// the thumb's root in the palm and the thumb.
List<FingerChain> handJoints(CharacterRig rig, CharacterLimb arm, double r) {
  var shape = rig.hands[arm] ?? const [0, 0, 0, 0, 0, 0];
  var spread = shape[5];
  var chains = <FingerChain>[];
  for (var f = 0; f < 4; f++) {
    var curl = shape[f + 1];
    var fan = spread * (1.5 - f) * math.pi / 180;
    var dx = math.sin(fan), dy = math.cos(fan);
    var p = (r * _knuckles[f], r * 1.0, 0.0);
    var joints = [p];
    var fold = 0.0;
    for (var k = 0; k < 3; k++) {
      fold += curl * _fold[k] * math.pi / 180;
      var l = _fingerBones[f][k] * r;
      var c = math.cos(fold), s = math.sin(fold);
      p = (p.$1 + dx * c * l, p.$2 + dy * c * l, p.$3 - s * l);
      joints.add(p);
    }
    var base = 0.13 * (f == 3 ? 0.85 : 1);
    chains.add((joints, [for (var k = 0; k < 4; k++) r * base * (1 - k * 0.1)],
        curl.abs() < 20));
  }

  // The thumb: from the heel of the palm on its side, out along the hand
  // and in front of the palm, curling across it towards the little finger.
  var thumbCurl = shape[0] / 90;
  var open = spread / 30;
  (double, double, double) toward(double k) {
    var a = (0.32 + open, 0.9, -0.35);
    var b = (-0.55, 0.45, -0.72);
    var x = a.$1 + (b.$1 - a.$1) * k,
        y = a.$2 + (b.$2 - a.$2) * k,
        z = a.$3 + (b.$3 - a.$3) * k;
    var n = math.sqrt(x * x + y * y + z * z);
    return (x / n, y / n, z / n);
  }

  var t0 = (r * 0.2, r * 0.12, -r * 0.05);
  var t1 = (r * 0.5, r * 0.42, -r * 0.14);
  var d1 = toward((thumbCurl * 0.6).clamp(0.0, 1.0));
  var t2 = (t1.$1 + d1.$1 * r * 0.4, t1.$2 + d1.$2 * r * 0.4, t1.$3 + d1.$3 * r * 0.4);
  var d2 = toward((thumbCurl * 1.05).clamp(0.0, 1.2));
  var t3 = (t2.$1 + d2.$1 * r * 0.32, t2.$2 + d2.$2 * r * 0.32, t2.$3 + d2.$3 * r * 0.32);
  chains.add(([t0, t1], [r * 0.2, r * 0.16], true));
  chains.add(([t1, t2, t3], [r * 0.155, r * 0.135, r * 0.115], shape[0].abs() < 20));
  return chains;
}

/// handTip is where the tip of the middle finger of the hand on the end of
/// [arm] is, on the page from the wrist.
Offset handTip(CharacterRig rig, CharacterLimb arm, double r) {
  var frame = ExtremityFrame(rig, rig.frames[arm]!);
  var curl = (rig.hands[arm] ?? const [0, 0, 0, 0, 0, 0])[2];
  var p = (r * _knuckles[1], r, 0.0);
  var fold = 0.0;
  for (var k = 0; k < 3; k++) {
    fold += curl * _fold[k] * math.pi / 180;
    var l = _fingerBones[1][k] * r;
    p = (p.$1, p.$2 + math.cos(fold) * l, p.$3 - math.sin(fold) * l);
  }
  return frame.at(p.$1, p.$2, p.$3);
}

// ---- outlines ----

/// rod is the outline of a rod from [a], [ra] round, to [b], [rb] round:
/// the two circles and the lines touching both.
List<Offset> rod(Offset a, double ra, Offset b, double rb) {
  var d = b - a;
  var l = d.distance;
  const n = 10;
  List<Offset> circle(Offset c, double rad) => [
        for (var k = 0; k < n * 2; k++)
          c + Offset.fromDirection(k / (n * 2) * math.pi * 2, rad)
      ];
  if (l <= (ra - rb).abs() + 1e-9) return circle(ra >= rb ? a : b, math.max(ra, rb));
  var base = math.atan2(d.dy, d.dx);
  var phi = math.acos(((ra - rb) / l).clamp(-1.0, 1.0));
  var pts = <Offset>[];
  // Round the back of the first circle, then the front of the second.
  for (var k = 0; k <= n; k++) {
    var t = base + phi + (math.pi * 2 - phi * 2) * k / n;
    pts.add(a + Offset.fromDirection(t, ra));
  }
  for (var k = 0; k <= n; k++) {
    var t = base - phi + phi * 2 * k / n;
    pts.add(b + Offset.fromDirection(t, rb));
  }
  return pts;
}

/// convexHull is the smallest convex outline round [points], anticlockwise
/// on the page.
List<Offset> convexHull(List<Offset> points) {
  if (points.length < 3) return points;
  var pts = [...points]..sort((a, b) => a.dx != b.dx
      ? a.dx.compareTo(b.dx)
      : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  var lower = <Offset>[];
  for (var p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  var upper = <Offset>[];
  for (var p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

import 'dart:math' as math;
import 'dart:ui';

// cubic_segment.dart is the geometry of a curve made of cubic pieces, in
// whatever space its points are given in: one piece (CubicSegment), and
// distance along a run of points (PointsAlong). A path is drawn, split and
// followed with these; the vector drawing's own copies (vector_editing.dart,
// vector_cut.dart) are the same arithmetic, and are meant to take these up.

/// CubicSegment is one cubic piece of a curve: from [p0] to [p3], pulled
/// towards [c1] on leaving and [c2] on arriving. A control point lying on
/// its own end pulls nothing that way, which is what a point with no handle
/// is: with both so, the piece is straight.
class CubicSegment {
  final Offset p0, c1, c2, p3;

  const CubicSegment(this.p0, this.c1, this.c2, this.p3);

  /// at is the point at [t] of the curve's own parameter, nought to one:
  /// not a share of its length (see [along]).
  Offset at(double t) {
    var u = 1 - t;
    return Offset(
      u * u * u * p0.dx +
          3 * u * u * t * c1.dx +
          3 * u * t * t * c2.dx +
          t * t * t * p3.dx,
      u * u * u * p0.dy +
          3 * u * u * t * c1.dy +
          3 * u * t * t * c2.dy +
          t * t * t * p3.dy,
    );
  }

  /// split cuts it at [t] into two pieces that are exactly it (de
  /// Casteljau), the first ending where the second begins.
  (CubicSegment, CubicSegment) split(double t) {
    Offset lerp(Offset p, Offset q) =>
        Offset(p.dx * (1 - t) + q.dx * t, p.dy * (1 - t) + q.dy * t);
    var q0 = lerp(p0, c1), q1 = lerp(c1, c2), q2 = lerp(c2, p3);
    var r0 = lerp(q0, q1), r1 = lerp(q1, q2);
    var mid = lerp(r0, r1);
    return (CubicSegment(p0, q0, r0, mid), CubicSegment(mid, r1, q2, p3));
  }

  /// samplesPerPiece is how finely a piece is walked into points: well
  /// under a pixel from the curve at any export size, and cheap enough to
  /// walk every piece of a path whenever it is pressed or followed.
  static const int samplesPerPiece = 16;

  /// points is the piece walked into [steps] straight runs, [steps] + 1
  /// points from [p0] to [p3] by the curve's own parameter.
  List<Offset> points([int steps = samplesPerPiece]) =>
      [for (var i = 0; i <= steps; i++) at(i / steps)];

  /// along is the point [t] of the way along it *by distance*, nought to
  /// one: the curve's own parameter runs slow round a bend, and something
  /// travelling it by that would slow there. The share is found along
  /// [points], and the point taken on the curve itself.
  Offset along(double t) {
    if (t <= 0) return at(0);
    if (t >= 1) return at(1);
    var walked = PointsAlong(points());
    if (walked.total <= 0) return p3;
    var (i, within) = walked.find(t * walked.total);
    return at((i - 1 + within) / samplesPerPiece);
  }
}

/// PointsAlong is a run of points measured end to end: how far along each
/// one is, so a distance along the run can be found on it. The one way
/// distance along a curve is measured, for a path's follower
/// (CubicSegment.along) and for the Follow path device.
class PointsAlong {
  final List<Offset> points;

  /// lengths is how far along the run each point is: the first nought, the
  /// last [total].
  final List<double> lengths;

  PointsAlong(this.points) : lengths = _lengthsOf(points);

  static List<double> _lengthsOf(List<Offset> points) {
    var lengths = <double>[0];
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
      lengths.add(total);
    }
    return lengths;
  }

  double get total => lengths.last;

  /// find is where [distance] along the run falls: the point it is short
  /// of, by index, and how far it is from the one before, nought to one.
  /// Past the end, it is on the last stretch. Asked of a run of fewer than
  /// two points, it answers (0, 0).
  (int, double) find(double distance) {
    for (var i = 1; i < points.length; i++) {
      if (lengths[i] >= distance || i == points.length - 1) {
        var span = lengths[i] - lengths[i - 1];
        return (i, span <= 0 ? 0.0 : (distance - lengths[i - 1]) / span);
      }
    }
    return (0, 0);
  }

  /// heading is the point [u] of the way along the run, nought to one, and
  /// the way the run heads there, in radians: on the straight between two
  /// points, not on any curve they were walked from.
  (Offset, double) heading(double u) {
    if (points.length < 2) {
      return (points.isEmpty ? Offset.zero : points.first, 0);
    }
    var (i, f) = find(u.clamp(0.0, 1.0) * total);
    var a = points[i - 1], b = points[i];
    return (
      Offset.lerp(a, b, f.clamp(0.0, 1.0))!,
      math.atan2(b.dy - a.dy, b.dx - a.dx)
    );
  }
}

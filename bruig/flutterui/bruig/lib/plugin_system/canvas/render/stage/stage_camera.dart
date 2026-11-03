import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';

// stage_camera.dart is how a 3D stage is seen: where a camera stands, which
// way it looks, and where a point on the stage lands on the page.
//
// The stage is measured in metres: x across it, y up from the floor, z
// towards where the camera starts. The camera always looks at a point a
// metre above the middle of the floor -- about a person's chest, unless it
// is panned away -- from some distance away, swung round it ([yaw]) and
// raised above it ([pitch]).
// That is the whole of a camera a reader needs to set: where from, how far,
// how wide a lens. A free camera with its own aim is more to learn and
// mostly gets lost.

/// _target is the point a camera looks at: a metre above the middle of
/// the floor.
const _target = _P(0, 1, 0);

class _P {
  final double x, y, z;
  const _P(this.x, this.y, this.z);
  _P operator -(_P o) => _P(x - o.x, y - o.y, z - o.z);
  _P operator +(_P o) => _P(x + o.x, y + o.y, z + o.z);
  _P operator *(double k) => _P(x * k, y * k, z * k);
  double dot(_P o) => x * o.x + y * o.y + z * o.z;
  _P cross(_P o) =>
      _P(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _P get unit {
    var l = math.sqrt(dot(this));
    return l == 0 ? this : this * (1 / l);
  }
}

/// StagePoint is where a point of the stage is seen: on the page, and how
/// far in front of the camera -- nought or less is behind it.
typedef StagePoint = ({Offset page, double depth});

/// StageView is a camera looking at a stage drawn in [box] on the page.
class StageView {
  final Rect box;
  final StageCamera camera;
  final _P _eye, _right, _up, _forward, _aim;
  final double _focal;

  StageView._(this.box, this.camera, this._eye, this._right, this._up,
      this._forward, this._focal, this._aim);

  factory StageView(Rect box, StageCamera camera) {
    var yaw = camera.yaw * math.pi / 180;
    var pitch = camera.pitch * math.pi / 180;
    var aim = _target + _P(camera.tx, camera.ty, camera.tz);
    var eye = aim +
        _P(math.sin(yaw) * math.cos(pitch), math.sin(pitch),
                math.cos(yaw) * math.cos(pitch)) *
            camera.distance;
    var forward = (aim - eye).unit;
    var right = forward.cross(const _P(0, 1, 0)).unit;
    var up = right.cross(forward);
    // A lens's focal length against the 24 mm height of a full frame: how
    // much of the box's height one metre at one metre's distance takes.
    var focal = box.height * camera.lens / 24;
    return StageView._(box, camera, eye, right, up, forward, focal, aim);
  }

  /// nearest is how close in front of the camera a point can be and still
  /// be drawn: anything nearer is behind the lens.
  static const double nearest = 0.1;

  /// eye and target are where the camera stands and what it looks at, in
  /// metres on the stage; fovY is how much it sees top to bottom, in
  /// radians. For a 3D scene to be seen exactly as the stage is.
  (double, double, double) get eye => (_eye.x, _eye.y, _eye.z);
  (double, double, double) get target => (_aim.x, _aim.y, _aim.z);
  double get fovY => 2 * math.atan(box.height / 2 / _focal);

  /// right is the camera's right, across the stage: what a flat turned to
  /// face the camera lies along.
  (double, double, double) get right => (_right.x, _right.y, _right.z);

  /// perspective is the matrix that lays [rect], a box on the page, onto
  /// the stage with its top-left corner at [topLeft], its top-right at
  /// [topRight] and its bottom-left at [bottomLeft] -- metres on the stage
  /// -- and shows it as the camera sees it: for Canvas.transform, so an
  /// element is drawn as it is on the page and set into the stage. Null
  /// where any corner is behind the lens.
  Float64List? perspective(Rect rect, (double, double, double) topLeft,
      (double, double, double) topRight, (double, double, double) bottomLeft) {
    _P p((double, double, double) v) => _P(v.$1, v.$2, v.$3);
    var o = p(topLeft) - _eye;
    var du = (p(topRight) - p(topLeft)) * (1 / rect.width);
    var dv = (p(bottomLeft) - p(topLeft)) * (1 / rect.height);
    var far = o + (p(topRight) - p(topLeft)) + (p(bottomLeft) - p(topLeft));
    for (var c in [o, o + du * rect.width, o + dv * rect.height, far]) {
      if (c.dot(_forward) <= nearest) return null;
    }
    // A point (u, v) of the page is o + du·(u − left) + dv·(v − top) from
    // the eye, so each of its distances along the camera's axes is linear
    // in u and v: (a, b, c) with a·u + b·v + c.
    (double, double, double) along(_P axis) {
      var a = du.dot(axis), b = dv.dot(axis);
      return (a, b, o.dot(axis) - a * rect.left - b * rect.top);
    }

    var (fa, fb, fc) = along(_forward);
    var (ra, rb, rc) = along(_right);
    var (ua, ub, uc) = along(_up);
    var cx = box.center.dx, cy = box.center.dy, f = _focal;
    // Rows: x·w, y·w, z, w -- with w the depth -- column by column.
    return Float64List.fromList([
      cx * fa + f * ra, cy * fa - f * ua, 0, fa, //
      cx * fb + f * rb, cy * fb - f * ub, 0, fb, //
      0, 0, 1, 0, //
      cx * fc + f * rc, cy * fc - f * uc, 0, fc,
    ]);
  }

  /// toWall is the point on the upright plane [z] metres along -- the back
  /// wall -- seen at [page], as metres across and up, or null where it is
  /// not seen.
  Offset? toWall(Offset page, double z) {
    var p = page - box.center;
    var ray = (_forward + _right * (p.dx / _focal) - _up * (p.dy / _focal));
    if (ray.z.abs() < 1e-6) return null;
    var t = (z - _eye.z) / ray.z;
    if (t <= 0) return null;
    var hit = _eye + ray * t;
    return Offset(hit.x, hit.y);
  }

  /// see is where [x], [y], [z] -- metres on the stage -- is seen.
  StagePoint see(double x, double y, double z) {
    var v = _P(x, y, z) - _eye;
    var depth = v.dot(_forward);
    var d = math.max(depth, 1e-6);
    return (
      page: box.center +
          Offset(v.dot(_right) * _focal / d, -v.dot(_up) * _focal / d),
      depth: depth,
    );
  }

  /// heardFrom is where [x], [y], [z] is from the camera, as a listener
  /// standing there hears it: the angle round from straight ahead --
  /// positive to the right, a half turn behind -- and how far, in metres.
  /// See SoundPlacement.
  (double, double) heardFrom(double x, double y, double z) {
    var v = _P(x, y, z) - _eye;
    var side = v.dot(_right), ahead = v.dot(_forward);
    var angle = math.atan2(side, ahead) * 180 / math.pi;
    return (angle, math.sqrt(v.dot(v)));
  }

  /// lookingDown is how far down the camera looks to see [x], [y], [z], in
  /// degrees: the angle from level to the line from its eye -- negative
  /// looking up.
  double lookingDown(double x, double y, double z) {
    var dx = x - _eye.x, dz = z - _eye.z;
    return math.atan2(_eye.y - y, math.sqrt(dx * dx + dz * dz)) * 180 / math.pi;
  }

  /// scaleAt is how many page units one metre is at [depth].
  double scaleAt(double depth) => _focal / math.max(depth, nearest);

  /// toFloor is the point on the floor seen at [page], as metres across
  /// and towards the camera's start, or null where the floor is not seen
  /// -- above the horizon. With [y], on the level that far above the
  /// floor instead: where something lifted off it slides.
  Offset? toFloor(Offset page, {double y = 0}) {
    var p = page - box.center;
    var ray = (_forward + _right * (p.dx / _focal) - _up * (p.dy / _focal));
    if (ray.y.abs() < 1e-6) return null;
    var t = (y - _eye.y) / ray.y;
    if (t <= 0) return null;
    var hit = _eye + ray * t;
    return Offset(hit.x, hit.z);
  }

  /// panned is the camera moved sideways and up by [by], page units on
  /// the box: what it looks at slides so the stage follows the pointer
  /// that far, at the distance of what it looks at.
  StageCamera panned(Offset by) {
    var k = camera.distance / _focal;
    var move = _right * (-by.dx * k) + _up * (by.dy * k);
    return camera.copyWith(
        tx: camera.tx + move.x, ty: camera.ty + move.y, tz: camera.tz + move.z);
  }

  /// framing is the camera turned on [x], [y], [z] -- metres on the stage
  /// -- from far enough away to see [size] metres of it top to bottom,
  /// with room round it.
  StageCamera framing(double x, double y, double z, double size) {
    var d = size * 1.4 * _focal / box.height;
    return camera.copyWith(
        tx: x - _target.x,
        ty: y - _target.y,
        tz: z - _target.z,
        distance: math.max(StageCamera.minDistance, d));
  }

  /// polygon is [points] on the stage as the camera sees them, cut off
  /// where they go behind the lens: what a floor or a wall is drawn as.
  List<Offset> polygon(List<(double, double, double)> points) {
    // Clipped against the plane just in front of the camera, so a floor the
    // camera stands on is drawn to the bottom of the box and not folded
    // back over the top of it.
    var cam = [
      for (var (x, y, z) in points) (_P(x, y, z) - _eye),
    ];
    double depthOf(_P v) => v.dot(_forward);
    var kept = <_P>[];
    for (var i = 0; i < cam.length; i++) {
      var a = cam[i], b = cam[(i + 1) % cam.length];
      var da = depthOf(a) - nearest, db = depthOf(b) - nearest;
      if (da >= 0) kept.add(a);
      if ((da >= 0) != (db >= 0)) {
        var t = da / (da - db);
        kept.add(a + (b - a) * t);
      }
    }
    return [
      for (var v in kept)
        box.center +
            Offset(v.dot(_right) * _focal / depthOf(v),
                -v.dot(_up) * _focal / depthOf(v)),
    ];
  }
}

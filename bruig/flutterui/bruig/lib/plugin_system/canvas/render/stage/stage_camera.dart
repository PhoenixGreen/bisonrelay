import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';

// stage_camera.dart is how a 3D stage is seen: where a camera stands, which
// way it looks, and where a point on the stage lands on the page.
//
// The stage is measured in metres: x across it, y up from the floor, z
// towards where the camera starts. The camera always looks at a point a
// metre above the middle of the floor -- about a person's chest -- from
// some distance away, swung round it ([yaw]) and raised above it ([pitch]).
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
  final _P _eye, _right, _up, _forward;
  final double _focal;

  StageView._(this.box, this.camera, this._eye, this._right, this._up,
      this._forward, this._focal);

  factory StageView(Rect box, StageCamera camera) {
    var yaw = camera.yaw * math.pi / 180;
    var pitch = camera.pitch * math.pi / 180;
    var eye = _target +
        _P(math.sin(yaw) * math.cos(pitch), math.sin(pitch),
                math.cos(yaw) * math.cos(pitch)) *
            camera.distance;
    var forward = (_target - eye).unit;
    var right = forward.cross(const _P(0, 1, 0)).unit;
    var up = right.cross(forward);
    // A lens's focal length against the 24 mm height of a full frame: how
    // much of the box's height one metre at one metre's distance takes.
    var focal = box.height * camera.lens / 24;
    return StageView._(box, camera, eye, right, up, forward, focal);
  }

  /// nearest is how close in front of the camera a point can be and still
  /// be drawn: anything nearer is behind the lens.
  static const double nearest = 0.1;

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
  /// -- above the horizon.
  Offset? toFloor(Offset page) {
    var p = page - box.center;
    var ray = (_forward + _right * (p.dx / _focal) - _up * (p.dy / _focal));
    if (ray.y >= -1e-6) return null;
    var t = -_eye.y / ray.y;
    if (t <= 0) return null;
    var hit = _eye + ray * t;
    return Offset(hit.x, hit.z);
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

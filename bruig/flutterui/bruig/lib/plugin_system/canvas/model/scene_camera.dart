import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:bruig/plugin_system/canvas/model/json_read.dart';
import 'package:bruig/plugin_system/canvas/model/scene_transition.dart';

/// SceneCamera is a slow move over a whole scene from one framing to
/// another: a push in, a pull out, a drift. A framing is a zoom (never less
/// than one, so the page is filled) and the point it centres on, as
/// fractions of the page.
class SceneCamera {
  final double fromZoom;
  final double fromX;
  final double fromY;
  final double toZoom;
  final double toX;
  final double toY;
  final SceneTransitionEase ease;

  /// orbit goes once round the point it looks at over the scene, as far
  /// out as [fromX] is from the middle, instead of from one framing to the
  /// other.
  final bool orbit;

  /// shake is how much it shakes (0 to 1): a few pixels' jitter, as a hand
  /// held camera's -- or a hit's, all the way up.
  final double shake;

  const SceneCamera({
    this.fromZoom = 1,
    this.fromX = 0.5,
    this.fromY = 0.5,
    this.toZoom = 1.12,
    this.toX = 0.5,
    this.toY = 0.5,
    this.ease = SceneTransitionEase.smooth,
    this.orbit = false,
    this.shake = 0,
  });

  /// at is the framing [t] of the way through the scene: a zoom, and the
  /// point of [page] at the middle of the picture, held in from the edges
  /// so the picture never runs off the page. [seconds] into the scene times
  /// its shake; without it, [t] does.
  (double, Offset) at(double t, Rect page, {double? seconds}) {
    var e = ease.apply(t.clamp(0.0, 1.0));
    var zoom = math.max(1.0, fromZoom + (toZoom - fromZoom) * e);
    var fx = fromX + (toX - fromX) * e, fy = fromY + (toY - fromY) * e;
    if (orbit) {
      // Round the middle, as far out as it starts, once over the scene.
      var r = math.max((fromX - 0.5).abs(), 0.04);
      var a = 2 * math.pi * e;
      fx = 0.5 + r * math.cos(a);
      fy = 0.5 + r * math.sin(a) * page.width / math.max(1, page.height);
    }
    if (shake > 0) {
      // Room to shake in: closer by as much, so the page never shows its
      // edge; then a quick jitter, a few sines out of step.
      zoom = math.max(zoom, 1 + shake * 0.06);
      var s = (seconds ?? t * 10) * 9;
      double jitter(double k) =>
          math.sin(s * 1.7 + k) * 0.5 +
          math.sin(s * 3.1 + k * 2) * 0.3 +
          math.sin(s * 5.3 + k * 3) * 0.2;
      fx += jitter(0) * shake * 0.012;
      fy += jitter(4) * shake * 0.012 * page.width / math.max(1, page.height);
    }
    var x = fx * page.width;
    var y = fy * page.height;
    var hx = page.width / 2 / zoom, hy = page.height / 2 / zoom;
    return (
      zoom,
      Offset(page.left + x.clamp(hx, page.width - hx),
          page.top + y.clamp(hy, page.height - hy)),
    );
  }

  SceneCamera copyWith({
    double? fromZoom,
    double? fromX,
    double? fromY,
    double? toZoom,
    double? toX,
    double? toY,
    SceneTransitionEase? ease,
    bool? orbit,
    double? shake,
  }) =>
      SceneCamera(
        fromZoom: fromZoom ?? this.fromZoom,
        fromX: fromX ?? this.fromX,
        fromY: fromY ?? this.fromY,
        toZoom: toZoom ?? this.toZoom,
        toX: toX ?? this.toX,
        toY: toY ?? this.toY,
        ease: ease ?? this.ease,
        orbit: orbit ?? this.orbit,
        shake: (shake ?? this.shake).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
        "from": [fromZoom, fromX, fromY],
        "to": [toZoom, toX, toY],
        if (ease != SceneTransitionEase.smooth) "ease": ease.name,
        if (orbit) "orbit": true,
        if (shake > 0) "shake": shake,
      };

  static SceneCamera? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    List<double> three(Object? v, List<double> or) =>
        v is List && v.length == 3 && v.every((x) => x is num)
            ? [for (var x in v) (x as num).toDouble()]
            : or;
    var from = three(json["from"], const [1, 0.5, 0.5]);
    var to = three(json["to"], const [1.12, 0.5, 0.5]);
    return SceneCamera(
      fromZoom: from[0].clamp(1.0, 8.0),
      fromX: from[1].clamp(0.0, 1.0),
      fromY: from[2].clamp(0.0, 1.0),
      toZoom: to[0].clamp(1.0, 8.0),
      toX: to[1].clamp(0.0, 1.0),
      toY: to[2].clamp(0.0, 1.0),
      ease: SceneTransitionEase.fromName(jsonStr(json["ease"])),
      orbit: json["orbit"] == true,
      shake: jsonDouble(json["shake"], 0).clamp(0.0, 1.0),
    );
  }
}
